extends MinigameBase
## Gooby Runner (runner) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus RunnerLogic
## (zahlengleich zum Web): 3 Spuren, Tempo +5 % alle 10 s, Hütchen/Kiste/
## Schranke springen, Gerüst rutschen, Auto ausweichen; Münzen ×Kombo,
## Überraschungskisten (Magnet/×2/Schild), 1. Treffer = Stolpern, 2. = Aus.
##
## 2D statt 3D (Web war three.js mit City-Kit-GLBs): die GLB-Kits gibt es im
## Godot-Projekt nicht, und der Korridor ist eine reine Tiefenachse. Eine
## perspektivische 2D-Sticker-Projektion (project()) hält JEDE Weltmeter-Zahl
## exakt — Kollisionen laufen ohnehin in Weltkoordinaten über RunnerLogic —
## und liest sich auf dem Handy sauberer als ein Mini-3D-Nachbau.
##
## AUTOHAUS-HAKEN (bewusst offen, NICHT implementiert): `car_skin` /
## `speed_bonus` bleiben leer; sobald das Autohaus Fahrzeuge liefert, kann
## der Host sie hier hineinreichen, ohne die Logik anzufassen.

const Logic := preload("res://scripts/minigames/games/runner/runner_logic.gd")

## Weltzahlen der Darstellung (KEINE Spiel-Mathe).
const SPAWN_Z := -88.0
const DESPAWN_Z := 9.0
const CAM_BEHIND := 6.2
## Halbe Straßenbreite (m) — Spuren ±1.1 m plus Randstreifen.
const ROAD_HALF := 1.85
## Sichtweite, ab der ein Objekt gezeichnet wird (m).
const DRAW_Z := -70.0
## Nahgrenze: alles hinter der Kamera wird nicht mehr gezeichnet (m).
const DRAW_NEAR_Z := 1.2
## Münzen sitzen auf dieser Höhe (Web: y 0.55).
const COIN_Y := 0.55
## Entwurfs-Kurzkante — Pixelmaße der Bedienleiste skalieren damit.
const DESIGN_SHORT := 390.0

## Autohaus-Haken: später vom Host befüllbar (Skin-Id / Tempo-Bonus).
var car_skin := ""
var speed_bonus := 0.0

var tune: Dictionary = {}
var rng: GoobyRng
var score := 0
var meters := 0.0
var coin_points := 0.0
var coins := 0
var coin_streak := 0
var powerups := 0
var elapsed := 0.0
var hits := 0
var finished := false
var view_size := Vector2(844.0, 390.0)
var landscape := true

var _lane := 1
var _lane_x := 0.0
var _jump_t := -1.0
var _slide_t := -1.0
var _invuln := 0.0
var _shield := false
var _magnet_t := 0.0
var _x2_t := 0.0
var _obstacles: Array[Dictionary] = []
var _coins: Array[Dictionary] = []
var _mystery: Array[Dictionary] = []
var _recent_rows: Array = []
var _pending_row: Dictionary = {}
var _dist_since_row := 0.0
var _next_mystery_at := 0.0
var _scenery: Array[Vector3] = []
var _focal_px := 400.0
var _cam_y := 1.6
var _horizon_px := 120.0
var _ui := 1.0
var _swipe_from := Vector2.ZERO
var _swipe_live := false
var _score_label: Label
var _stat_label: Label
var _hint_label: Label
var _banner := ""
var _banner_t := 0.0


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = Logic.apply_difficulty(Logic.RUNNER, ctx.difficulty)
	rng = ctx.rng()
	_next_mystery_at = float(tune["MYSTERY_FIRST_M"])
	for i in 26:
		# x-Seite (±1), z-Tiefe im Korridor, Art (0..1 → Baum/Haus).
		_scenery.append(Vector3(-1.0 if i % 2 == 0 else 1.0, -i * 4.0 - 2.0, rng.next()))
	_build_hud()
	_fit_viewport()
	if is_inside_tree():
		get_viewport().size_changed.connect(_fit_viewport)


func end() -> void:
	super.end()
	finished = true


## Pflicht-Layouthook: beide Orientierungen laufen über DIESE Funktion.
func apply_view(size: Vector2) -> void:
	if size.x > 1.0 and size.y > 1.0:
		view_size = size
	landscape = view_size.x > view_size.y
	_ui = clampf(minf(view_size.x, view_size.y) / DESIGN_SHORT, 0.75, 3.0)
	position = Vector2.ZERO
	_recompute_camera()
	_layout_hud()
	queue_redraw()


## Die Bedienleiste wird in Entwurfspixeln gedacht und mit _ui skaliert —
## sonst schrumpfen Zeit/Statuszeile auf großen Bühnen zu Krümeln.
func _layout_hud() -> void:
	if _score_label == null:
		return
	var pad := 14.0 * _ui
	_score_label.position = Vector2(pad, 8.0 * _ui)
	_score_label.add_theme_font_size_override("font_size", int(26.0 * _ui))
	_stat_label.position = Vector2(pad, 44.0 * _ui)
	_stat_label.add_theme_font_size_override("font_size", int(17.0 * _ui))
	var hint_w := minf(view_size.x - pad * 2.0, 420.0 * _ui)
	_hint_label.add_theme_font_size_override("font_size", int(15.0 * _ui))
	_hint_label.position = Vector2((view_size.x - hint_w) * 0.5, view_size.y - 44.0 * _ui)
	_hint_label.size = Vector2(hint_w, 38.0 * _ui)


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	var dt := minf(delta, 0.1)
	elapsed += dt
	_banner_t = maxf(0.0, _banner_t - dt)
	_invuln = maxf(0.0, _invuln - dt)
	_magnet_t = maxf(0.0, _magnet_t - dt)
	_x2_t = maxf(0.0, _x2_t - dt)
	var speed := Logic.speed_at(elapsed, tune)
	var dz := speed * dt
	var prev_meters := meters
	meters += dz
	_advance_scenery(dz)
	_spawn(dz)
	_move_player(dt)
	_collide(dz)
	_milestone(prev_meters)
	_publish_score()
	_update_labels()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_swipe_from = event.position
			_swipe_live = true
		elif _swipe_live:
			_swipe_live = false
			_resolve_swipe(event.position - _swipe_from)
	elif event is InputEventScreenDrag and _swipe_live:
		var delta: Vector2 = event.position - _swipe_from
		if delta.length() >= 44.0:
			_swipe_live = false
			_resolve_swipe(delta)
	elif event is InputEventKey and event.pressed and not event.echo:
		# Desktop-Komfort (Tests/Screenshots) — dieselben vier Aktionen.
		match event.keycode:
			KEY_LEFT, KEY_A:
				_change_lane(-1)
			KEY_RIGHT, KEY_D:
				_change_lane(1)
			KEY_UP, KEY_W, KEY_SPACE:
				_jump()
			KEY_DOWN, KEY_S:
				_slide()


## Welt (x, y, z) → Bildschirmpixel; z < 0 = vor dem Spieler.
func project(wx: float, wy: float, wz: float) -> Vector2:
	var s := scale_at(wz)
	return Vector2(view_size.x * 0.5 + wx * s, _horizon_px + (_cam_y - wy) * s)


## Pixel-pro-Meter an dieser Tiefe (für Größen).
func scale_at(wz: float) -> float:
	return _focal_px / maxf(0.35, CAM_BEHIND - wz)


## Kamera aus dem Layout ableiten: die Straße füllt einen festen Anteil der
## Breite, die Füße stehen auf einem festen Anteil der Höhe — daraus folgen
## Brennweite und Kamerahöhe. So sitzt Gooby in BEIDEN Orientierungen richtig
## (fest verdrahtete Werte kippten ihn hochkant aus dem Bild).
func _recompute_camera() -> void:
	var road_fill := 0.42 if landscape else 0.8
	var horizon_frac := 0.36 if landscape else 0.3
	var feet_frac := 0.86 if landscape else 0.84
	_focal_px = road_fill * view_size.x * CAM_BEHIND / (2.0 * ROAD_HALF)
	_horizon_px = view_size.y * horizon_frac
	_cam_y = (view_size.y * feet_frac - _horizon_px) * CAM_BEHIND / _focal_px


func _build_hud() -> void:
	_score_label = Label.new()
	_score_label.theme_type_variation = &"HeadlineLabel"
	add_child(_score_label)
	_stat_label = Label.new()
	_stat_label.theme_type_variation = &"CaptionLabel"
	add_child(_stat_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.runner.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Der Hinweis liegt auf dem grauen Asphalt — heller Text mit weichem
	# Schattenrand bleibt dort lesbar, dunkle Tinte nicht.
	_hint_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.94))
	_hint_label.add_theme_color_override("font_outline_color", Color(0.15, 0.13, 0.18, 0.45))
	_hint_label.add_theme_constant_override("outline_size", 7)
	add_child(_hint_label)
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _resolve_swipe(delta: Vector2) -> void:
	if delta.length() < 30.0:
		return
	if absf(delta.x) > absf(delta.y):
		_change_lane(1 if delta.x > 0.0 else -1)
	elif delta.y < 0.0:
		_jump()
	else:
		_slide()


func _change_lane(step: int) -> void:
	var next := clampi(_lane + step, 0, int(tune["LANES"]) - 1)
	if next == _lane:
		return
	_lane = next
	AudioDirector.try_play(self, "ui_chip", 1.2)


func _jump() -> void:
	if _jump_t >= 0.0 or _slide_t >= 0.0:
		return
	_jump_t = 0.0
	AudioDirector.try_play(self, "mg_good", 1.3)


func _slide() -> void:
	if _slide_t >= 0.0 or _jump_t >= 0.0:
		return
	_slide_t = 0.0
	AudioDirector.try_play(self, "mg_junk", 1.25)


func _advance_scenery(dz: float) -> void:
	for i in _scenery.size():
		var s := _scenery[i]
		s.y += dz
		if s.y > DESPAWN_Z:
			s.y -= 104.0
		_scenery[i] = s


func _spawn(dz: float) -> void:
	_dist_since_row += dz
	if _pending_row.is_empty():
		_pending_row = Logic.generate_row(rng, elapsed, _recent_rows, tune)
	if _dist_since_row >= float(_pending_row["gap"]):
		_spawn_row(_pending_row)
		_recent_rows.append(_pending_row)
		if _recent_rows.size() > 6:
			_recent_rows.pop_front()
		_dist_since_row = 0.0
		_pending_row = {}
	if meters >= _next_mystery_at:
		_mystery.append({"lane": _lane, "z": SPAWN_Z})
		_next_mystery_at += float(tune["MYSTERY_GAP_M"])


func _spawn_row(row: Dictionary) -> void:
	var lanes: Array = row["lanes"]
	for lane in lanes.size():
		if lanes[lane] == null:
			continue
		_obstacles.append({"kind": str(lanes[lane]), "lane": lane, "z": SPAWN_Z})
	if rng.next() >= float(tune["COIN_LINE_CHANCE"]):
		return
	var pass_flags := Logic.passable_lanes(row, tune)
	var options: Array = []
	for lane in lanes.size():
		if bool(pass_flags[lane]):
			options.append(lane)
	if options.is_empty():
		return
	var free_lanes: Array = []
	for lane: int in options:
		if lanes[lane] == null:
			free_lanes.append(lane)
	var pick: int = options[int(floor(rng.next() * options.size()))]
	if not free_lanes.is_empty() and rng.next() < 0.7:
		pick = free_lanes[int(floor(rng.next() * free_lanes.size()))]
	var kind: Variant = lanes[pick]
	var over_jump := (
		kind != null and str((tune["OBSTACLES"] as Dictionary)[str(kind)]["pass"]) == "jump"
	)
	var count := Logic.coin_line_count(rng, tune)
	for i in count:
		var z_off := (i - (count - 1) / 2.0) * 1.15
		var y := COIN_Y
		if over_jump:
			var arc := cos((z_off / 2.2) * PI * 0.5)
			y = COIN_Y + float(tune["JUMP_HEIGHT"]) * 0.8 * arc * arc
		_coins.append({"lane": pick, "z": SPAWN_Z + z_off, "y": y})


func _move_player(dt: float) -> void:
	var lane_target := float((tune["LANE_X"] as Array)[_lane])
	_lane_x += (lane_target - _lane_x) * minf(1.0, dt / float(tune["LANE_CHANGE_SEC"]))
	if _jump_t >= 0.0:
		_jump_t += dt
		if _jump_t >= float(tune["JUMP_SEC"]):
			_jump_t = -1.0
	if _slide_t >= 0.0:
		_slide_t += dt
		if _slide_t >= float(tune["SLIDE_SEC"]):
			_slide_t = -1.0


func player_y() -> float:
	if _jump_t < 0.0:
		return 0.0
	return float(tune["JUMP_HEIGHT"]) * sin((_jump_t / float(tune["JUMP_SEC"])) * PI)


func is_sliding() -> bool:
	return _slide_t >= 0.0


## Nächstliegende Spur zum aktuellen Weg-x (wie im Web `laneNow`).
func lane_now() -> int:
	var lane_x: Array = tune["LANE_X"]
	var best := 0
	for i in lane_x.size():
		if absf(_lane_x - float(lane_x[i])) < absf(_lane_x - float(lane_x[best])):
			best = i
	return best


func _collide(dz: float) -> void:
	var lane := lane_now()
	var y := player_y()
	var sliding := is_sliding()
	var player := {"lane": lane, "y": y, "sliding": sliding}
	var keep: Array[Dictionary] = []
	for ob in _obstacles:
		var hit := (
			not finished and _invuln <= 0.0 and Logic.sweep_hits_obstacle(player, ob, dz, tune)
		)
		ob["z"] = float(ob["z"]) + dz
		if float(ob["z"]) > DESPAWN_Z:
			continue
		keep.append(ob)
		if hit:
			_on_hit()
			if finished:
				break
	_obstacles = keep
	_collect_coins(dz, lane, y)
	_collect_mystery(dz, lane, y)


func _collect_coins(dz: float, lane: int, y: float) -> void:
	var lane_x: Array = tune["LANE_X"]
	var keep: Array[Dictionary] = []
	for coin in _coins:
		coin["z"] = float(coin["z"]) + dz
		var z := float(coin["z"])
		if z > DESPAWN_Z:
			continue
		var magnet := Logic.magnet_collects(
			Vector3(float(lane_x[int(coin["lane"])]), float(coin["y"]), z),
			Vector3(_lane_x, y + 0.55, 0.0),
			_magnet_t > 0.0,
			tune
		)
		var reach := (
			absf(z) < 0.55 and int(coin["lane"]) == lane and absf(y + 0.55 - float(coin["y"])) < 0.8
		)
		if finished or not (magnet or reach):
			keep.append(coin)
			continue
		_take_coin(coin)
	_coins = keep


func _take_coin(coin: Dictionary) -> void:
	coins += 1
	var prev_mult := Logic.combo_multiplier(coin_streak, tune)
	coin_streak += 1
	var mult := Logic.combo_multiplier(coin_streak, tune)
	var points := Logic.mystery_coin_points(mult, _x2_t > 0.0, tune)
	coin_points += points
	AudioDirector.try_play(self, "mg_good")
	if ctx.juice != null:
		var lane_x: Array = tune["LANE_X"]
		var pos := project(
			float(lane_x[int(coin["lane"])]), float(coin["y"]) + 0.5, float(coin["z"])
		)
		ctx.juice.float_text(pos, "+%d" % points, Color(1.0, 0.82, 0.4))
	if mult > prev_mult:
		_set_banner(I18nService.t("mg.runner.combo", {"mult": mult}))
		AudioDirector.try_play(self, "mg_combo")
		if ctx.juice != null:
			ctx.juice.bloom_pulse(0.7)


func _collect_mystery(dz: float, lane: int, y: float) -> void:
	var keep: Array[Dictionary] = []
	for box in _mystery:
		box["z"] = float(box["z"]) + dz
		if float(box["z"]) > DESPAWN_Z:
			continue
		var reach := absf(float(box["z"])) < 0.7 and int(box["lane"]) == lane and y < 0.8
		if finished or not reach:
			keep.append(box)
			continue
		var kind := Logic.roll_mystery_power(rng)
		var state := Logic.activate_mystery_power(
			{"magnetT": _magnet_t, "x2T": _x2_t, "shield": _shield}, kind, tune
		)
		_magnet_t = float(state["magnetT"])
		_x2_t = float(state["x2T"])
		_shield = bool(state["shield"])
		powerups += 1
		AudioDirector.try_play(self, "mg_golden")
		_set_banner(I18nService.t("mg.runner.%s" % kind))
		if ctx.juice != null:
			ctx.juice.bloom_pulse(1.0)
	_mystery = keep


func _on_hit() -> void:
	var result := Logic.resolve_runner_hit(
		{"hits": hits, "shield": _shield, "invulnT": _invuln}, tune
	)
	var outcome := str(result["outcome"])
	if outcome == "ignored":
		return
	hits = int(result["hits"])
	_shield = bool(result["shield"])
	_invuln = float(result["invulnT"])
	coin_streak = 0
	if ctx.juice != null:
		ctx.juice.shake(0.45 if outcome == "wipeout" else 0.3)
	if outcome == "shielded":
		AudioDirector.try_play(self, "mg_junk")
		_set_banner(I18nService.t("mg.runner.shield_pop"))
		return
	AudioDirector.try_play(self, "mg_spill")
	if ctx.juice != null:
		ctx.juice.hit_freeze(90)
	if outcome == "wipeout":
		_finish()
		return
	_set_banner(I18nService.t("mg.runner.stumble", {"left": int(tune["MAX_HITS"]) - hits}))


func _milestone(prev_meters: float) -> void:
	var milestone := Logic.crossed_runner_milestone(prev_meters, meters)
	if milestone <= 0:
		return
	AudioDirector.try_play(self, "mg_perfect")
	if ctx.juice != null:
		ctx.juice.float_text(
			Vector2(view_size.x * 0.5 - 40.0, view_size.y * 0.3),
			I18nService.t("mg.runner.milestone", {"m": milestone}),
			Color(0.7, 1.0, 0.8)
		)
		ctx.juice.bloom_pulse(0.6)


func _publish_score() -> void:
	var total := Logic.final_runner_score(meters, coin_points, tune)
	if total == score:
		return
	var delta := total - score
	score = total
	ctx.report_score(score, delta)


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	AudioDirector.try_play(self, "mg_lose")
	(
		ctx
		. report_end(
			{
				"score": Logic.final_runner_score(meters, coin_points, tune),
				"meters": int(floor(meters)),
				"coins": coins,
				"powerups": powerups,
				"hits": hits,
			}
		)
	)


func _set_banner(text: String) -> void:
	_banner = text
	_banner_t = 1.3


func _update_labels() -> void:
	# Der Host zeigt den Score bereits oben — hier laufen die Renn-Zahlen.
	_score_label.text = I18nService.t("mg.runner.distance", {"m": int(floor(meters))})
	_stat_label.text = I18nService.t(
		"mg.runner.stats", {"coins": coins, "left": maxi(0, int(tune["MAX_HITS"]) - hits)}
	)


func _draw() -> void:
	_draw_world()
	_draw_scenery()
	# Alles Bewegliche von HINTEN nach VORNE (Maler-Algorithmus).
	var items: Array = []
	for ob in _obstacles:
		items.append({"z": float(ob["z"]), "kind": "obstacle", "data": ob})
	for coin in _coins:
		items.append({"z": float(coin["z"]), "kind": "coin", "data": coin})
	for box in _mystery:
		items.append({"z": float(box["z"]), "kind": "mystery", "data": box})
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["z"] < b["z"])
	for item in items:
		if float(item["z"]) < DRAW_Z or float(item["z"]) > DRAW_NEAR_Z:
			continue
		match str(item["kind"]):
			"obstacle":
				_draw_obstacle(item["data"])
			"coin":
				_draw_coin(item["data"])
			_:
				_draw_mystery(item["data"])
	_draw_gooby()
	_draw_powerups()
	_draw_banner()


func _draw_world() -> void:
	var vp := view_size
	var hz := _horizon_px
	draw_rect(Rect2(Vector2.ZERO, Vector2(vp.x, hz)), Color(0.75, 0.89, 1.0))
	for i in 10:
		var f := float(i) / 9.0
		draw_rect(
			Rect2(0.0, hz * f, vp.x, hz / 9.0 + 1.0),
			Color(0.55, 0.79, 0.98).lerp(Color(0.86, 0.94, 1.0), f)
		)
	draw_rect(Rect2(0.0, hz, vp.x, vp.y - hz), Color(0.66, 0.85, 0.63))
	# Straße als Trapez, Spurlinien laufen mit.
	var road_half := 1.85
	var near := project(-road_half, 0.0, DRAW_NEAR_Z)
	var near_r := project(road_half, 0.0, DRAW_NEAR_Z)
	var far := project(-road_half, 0.0, DRAW_Z)
	var far_r := project(road_half, 0.0, DRAW_Z)
	draw_colored_polygon(PackedVector2Array([far, far_r, near_r, near]), Color(0.44, 0.44, 0.48))
	draw_line(far, near, Color(0.86, 0.86, 0.9, 0.8), 2.0)
	draw_line(far_r, near_r, Color(0.86, 0.86, 0.9, 0.8), 2.0)
	var lane_x: Array = tune["LANE_X"]
	for i in [0.5, 1.5]:
		var x := lerpf(float(lane_x[int(i - 0.5)]), float(lane_x[int(i + 0.5)]), 0.5)
		# Gestrichelt: Segmente wandern mit den gelaufenen Metern.
		var offset := fposmod(meters, 6.0)
		var z := DRAW_NEAR_Z - offset
		while z > DRAW_Z:
			var a := project(x, 0.01, z)
			var b := project(x, 0.01, maxf(DRAW_Z, z - 3.0))
			draw_line(a, b, Color(0.95, 0.93, 0.7, 0.75), maxf(1.0, scale_at(z) * 0.05))
			z -= 6.0
	# Randsteine
	for side in [-1.0, 1.0]:
		var a := project(side * road_half, 0.12, DRAW_NEAR_Z)
		var b := project(side * road_half, 0.12, DRAW_Z)
		draw_line(a, b, Color(0.93, 0.9, 0.85, 0.9), 3.0)


func _draw_scenery() -> void:
	# Von HINTEN nach VORNE, sonst überdeckt ein fernes Haus ein nahes.
	var sorted: Array[Vector3] = _scenery.duplicate()
	sorted.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.y < b.y)
	for s: Vector3 in sorted:
		var z := s.y
		if z > DRAW_NEAR_Z or z < DRAW_Z:
			continue
		var x := s.x * (4.3 + s.z * 3.4)
		var sc := scale_at(z)
		var base := project(x, 0.0, z)
		if s.z < 0.45:
			# Baum
			var h := 2.4 * sc
			draw_line(
				base, base + Vector2(0.0, -h * 0.45), Color(0.45, 0.31, 0.22), maxf(1.0, sc * 0.16)
			)
			draw_circle(base + Vector2(0.0, -h * 0.66), sc * 0.75, Color(0.34, 0.62, 0.35))
			draw_circle(base + Vector2(-sc * 0.35, -h * 0.5), sc * 0.5, Color(0.4, 0.68, 0.4))
		else:
			# Haus-Sticker
			var w := sc * (1.6 + s.z)
			var h := sc * (2.6 + s.z * 3.2)
			var col := Color(0.93, 0.84, 0.76).lerp(Color(0.8, 0.72, 0.9), s.z)
			draw_rect(Rect2(base + Vector2(-w * 0.5, -h), Vector2(w, h)), col)
			draw_rect(
				Rect2(base + Vector2(-w * 0.5, -h), Vector2(w, h)),
				Color(0.55, 0.45, 0.42, 0.7),
				false,
				maxf(1.0, sc * 0.04)
			)
			for row in 3:
				for col_i in 2:
					var wp := (
						base + Vector2((-0.26 + 0.52 * col_i) * w, -h + h * (0.18 + 0.28 * row))
					)
					draw_rect(
						Rect2(wp - Vector2(w * 0.09, h * 0.06), Vector2(w * 0.18, h * 0.12)),
						Color(0.99, 0.93, 0.66, 0.9)
					)


func _draw_obstacle(ob: Dictionary) -> void:
	var lane_x: Array = tune["LANE_X"]
	var z := float(ob["z"])
	var x := float(lane_x[int(ob["lane"])])
	var sc := scale_at(z)
	var base := project(x, 0.0, z)
	match str(ob["kind"]):
		"cone":
			var w := sc * 0.4
			var h := sc * 0.62
			draw_colored_polygon(
				PackedVector2Array(
					[
						base + Vector2(-w, 0.0),
						base + Vector2(w, 0.0),
						base + Vector2(0.0, -h),
					]
				),
				Color(0.98, 0.48, 0.16)
			)
			draw_rect(
				Rect2(base + Vector2(-w * 0.62, -h * 0.62), Vector2(w * 1.24, h * 0.16)),
				Color(1.0, 0.97, 0.92)
			)
			draw_rect(
				Rect2(base + Vector2(-w * 1.15, -sc * 0.06), Vector2(w * 2.3, sc * 0.06)),
				Color(0.86, 0.38, 0.12)
			)
		"box":
			var w := sc * 0.44
			var h := sc * 0.7
			draw_rect(Rect2(base + Vector2(-w, -h), Vector2(w * 2.0, h)), Color(0.78, 0.58, 0.34))
			draw_rect(
				Rect2(base + Vector2(-w, -h), Vector2(w * 2.0, h)),
				Color(0.5, 0.34, 0.2),
				false,
				maxf(1.0, sc * 0.05)
			)
			draw_line(
				base + Vector2(-w, -h),
				base + Vector2(w, 0.0),
				Color(0.6, 0.42, 0.24),
				maxf(1.0, sc * 0.04)
			)
		"barrier":
			var w := sc * 0.55
			var h := sc * 0.72
			draw_rect(
				Rect2(base + Vector2(-w, -h), Vector2(w * 2.0, h * 0.42)), Color(0.95, 0.95, 0.96)
			)
			for i in 4:
				draw_rect(
					Rect2(base + Vector2(-w + i * w * 0.5, -h), Vector2(w * 0.25, h * 0.42)),
					Color(0.9, 0.24, 0.22)
				)
			for side in [-1.0, 1.0]:
				draw_line(
					base + Vector2(side * w * 0.8, 0.0),
					base + Vector2(side * w * 0.8, -h * 0.6),
					Color(0.55, 0.55, 0.6),
					maxf(1.0, sc * 0.06)
				)
		"overhead":
			var w := sc * 0.58
			var top := sc * 1.5
			var gap := sc * float((tune["OBSTACLES"] as Dictionary)["overhead"]["gapY"])
			for side in [-1.0, 1.0]:
				draw_line(
					base + Vector2(side * w, 0.0),
					base + Vector2(side * w, -top),
					Color(0.69, 0.33, 0.18),
					maxf(1.5, sc * 0.09)
				)
			draw_rect(
				Rect2(base + Vector2(-w * 1.1, -top), Vector2(w * 2.2, top - gap)),
				Color(0.32, 0.56, 0.85)
			)
			draw_rect(
				Rect2(base + Vector2(-w * 1.1, -top), Vector2(w * 2.2, top - gap)),
				Color(0.2, 0.34, 0.55),
				false,
				maxf(1.0, sc * 0.04)
			)
		_:
			# Auto — voller Blocker
			var w := sc * 0.9
			var h := sc * 0.72
			draw_rect(
				Rect2(base + Vector2(-w, -h * 0.72), Vector2(w * 2.0, h * 0.72)),
				Color(0.93, 0.76, 0.24)
			)
			draw_rect(
				Rect2(base + Vector2(-w * 0.6, -h * 1.2), Vector2(w * 1.2, h * 0.5)),
				Color(0.72, 0.85, 0.95)
			)
			for side in [-1.0, 1.0]:
				draw_circle(base + Vector2(side * w * 0.6, 0.0), sc * 0.14, Color(0.22, 0.2, 0.22))


func _draw_coin(coin: Dictionary) -> void:
	var lane_x: Array = tune["LANE_X"]
	var z := float(coin["z"])
	var sc := scale_at(z)
	var pos := project(float(lane_x[int(coin["lane"])]), float(coin["y"]), z)
	var spin := absf(sin(elapsed * 4.0 + z * 0.3))
	draw_circle(pos, sc * 0.2, Color(1.0, 0.85, 0.35, 0.25))
	draw_ellipse_coin(pos, sc * 0.16 * (0.35 + 0.65 * spin), sc * 0.16)


func draw_ellipse_coin(center: Vector2, rx: float, ry: float) -> void:
	var pts := PackedVector2Array()
	for i in 18:
		var a := TAU * i / 18.0
		pts.append(center + Vector2(cos(a) * maxf(1.0, rx), sin(a) * maxf(1.0, ry)))
	draw_colored_polygon(pts, Color(1.0, 0.82, 0.4))
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.85, 0.6, 0.15), 1.5)


func _draw_mystery(box: Dictionary) -> void:
	var lane_x: Array = tune["LANE_X"]
	var z := float(box["z"])
	var sc := scale_at(z)
	var base := project(float(lane_x[int(box["lane"])]), 0.0, z)
	var w := sc * 0.36
	var rect := Rect2(base + Vector2(-w, -w * 2.0), Vector2(w * 2.0, w * 2.0))
	draw_rect(rect, Color(0.98, 0.78, 0.3))
	draw_rect(rect, Color(0.7, 0.45, 0.1), false, maxf(1.0, sc * 0.05))
	var font := ThemeService.font(800)
	draw_string(
		font,
		base + Vector2(-w, -w * 0.55),
		"?",
		HORIZONTAL_ALIGNMENT_CENTER,
		w * 2.0,
		maxi(10, int(sc * 0.45)),
		Color(0.4, 0.24, 0.1)
	)


func _draw_gooby() -> void:
	var sc := scale_at(0.0)
	var y := player_y()
	var sliding := is_sliding()
	var squash := float(tune["SLIDE_HEIGHT"]) / float(tune["STAND_HEIGHT"]) if sliding else 1.0
	var base := project(_lane_x, y, 0.0)
	var alpha := 1.0 if _invuln <= 0.0 else (0.35 + 0.65 * absf(sin(_invuln * 20.0)))
	var body_h := sc * float(tune["STAND_HEIGHT"]) * squash
	var body_w := sc * 0.44 * (1.0 + (1.0 - squash) * 0.55)
	# Schatten
	var ground := project(_lane_x, 0.0, 0.0)
	draw_circle(ground, body_w * (0.85 - y * 0.2), Color(0.15, 0.2, 0.15, 0.22 * alpha))
	if _magnet_t > 0.0:
		draw_arc(
			base + Vector2(0.0, -body_h * 0.5),
			body_w * 2.6,
			0.0,
			TAU,
			32,
			Color(0.55, 0.85, 1.0, 0.5 * alpha),
			3.0
		)
	if _shield:
		draw_arc(
			base + Vector2(0.0, -body_h * 0.5),
			body_w * 1.9,
			0.0,
			TAU,
			32,
			Color(1.0, 0.9, 0.45, 0.8 * alpha),
			4.0
		)
	# Gooby-Sticker: Beine, Rumpf, runder Kopf mit zwei Ohren.
	var fur := Color(0.99, 0.9, 0.65, alpha)
	var ink := Color(0.32, 0.22, 0.18, alpha)
	var head := base + Vector2(0.0, -body_h * 0.66)
	var r := body_h * 0.3
	if not sliding:
		var step := sin(elapsed * 14.0) * body_h * 0.09
		for side in [-1.0, 1.0]:
			draw_line(
				base + Vector2(side * body_w * 0.34, -body_h * 0.3),
				base + Vector2(side * body_w * 0.34, step * side),
				Color(0.86, 0.72, 0.5, alpha),
				maxf(3.0, body_w * 0.24)
			)
	draw_ellipse(base + Vector2(0.0, -body_h * 0.4), body_w * 0.78, body_h * 0.28, fur)
	for side in [-1.0, 1.0]:
		draw_circle(head + Vector2(side * r * 0.62, -r * 0.82), r * 0.34, fur)
	draw_circle(head, r, fur)
	var eye := r * 0.13
	draw_circle(head + Vector2(-r * 0.34, -r * 0.1), eye, ink)
	draw_circle(head + Vector2(r * 0.34, -r * 0.1), eye, ink)
	draw_arc(head + Vector2(0.0, r * 0.22), r * 0.3, 0.3, PI - 0.3, 12, ink, maxf(2.0, r * 0.1))
	draw_circle(head + Vector2(0.0, r * 0.12), r * 0.1, Color(0.95, 0.6, 0.6, alpha))


func draw_ellipse(center: Vector2, rx: float, ry: float, color: Color, filled := true) -> void:
	var pts := PackedVector2Array()
	for i in 26:
		var a := TAU * i / 26.0
		pts.append(center + Vector2(cos(a) * maxf(1.0, rx), sin(a) * maxf(1.0, ry)))
	if filled:
		draw_colored_polygon(pts, color)
	else:
		draw_polyline(pts + PackedVector2Array([pts[0]]), color, 2.0)


func _draw_powerups() -> void:
	var font := ThemeService.font(700)
	var x := view_size.x - 150.0
	var y := 16.0
	if _x2_t > 0.0:
		draw_string(
			font,
			Vector2(x, y + 22.0),
			"x2 %.1fs" % _x2_t,
			HORIZONTAL_ALIGNMENT_RIGHT,
			130.0,
			20,
			Color(1.0, 0.86, 0.4)
		)
		y += 26.0
	if _magnet_t > 0.0:
		draw_string(
			font,
			Vector2(x, y + 22.0),
			"%s %.1fs" % [I18nService.t("mg.runner.magnet"), _magnet_t],
			HORIZONTAL_ALIGNMENT_RIGHT,
			130.0,
			20,
			Color(0.6, 0.88, 1.0)
		)


func _draw_banner() -> void:
	if _banner_t <= 0.0 or _banner.is_empty():
		return
	var font := ThemeService.font(800)
	var alpha := clampf(_banner_t * 1.4, 0.0, 1.0)
	draw_string(
		font,
		Vector2(view_size.x * 0.5 - 200.0, view_size.y * 0.24),
		_banner,
		HORIZONTAL_ALIGNMENT_CENTER,
		400.0,
		28,
		Color(1.0, 0.95, 0.8, alpha)
	)
