extends MinigameBase
## Gooby Runner (runner) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus RunnerLogic
## (zahlengleich zum Web): 3 Spuren, Tempo +5 % alle 10 s, Hütchen/Kiste/
## Schranke springen, Gerüst rutschen, Auto ausweichen; Münzen ×Kombo,
## Überraschungskisten (Magnet/×2/Schild), 1. Treffer = Stolpern, 2. = Aus.
##
## ECHTES 3D (Agent 3D-B): die Ansicht ist eine Node3D-Welt mit Verfolgerkamera,
## Kenney-City-Kit-Korridor (dieselben GLBs wie die Web-Fassung), Tiefen-Nebel,
## dezentem Glow und dem ECHTEN Gooby-Rig, das wirklich läuft, springt und
## rutscht. Der MinigameBase-Vertrag bleibt: Wurzel ist Node2D, die 3D-Welt
## hängt darunter (Godot rendert 3D hinter den CanvasItems, HUD liegt oben).
## Die Kulisse ist ein recyceltes Band aus MultiMeshes — kein Instanzieren
## pro Frame, ein Draw-Call pro Modell.
##
## AUTOHAUS-HAKEN (bewusst offen, NICHT implementiert): `car_skin` /
## `speed_bonus` bleiben leer; sobald das Autohaus Fahrzeuge liefert, kann
## der Host sie hier hineinreichen, ohne die Logik anzufassen.

const Logic := preload("res://scripts/minigames/games/runner/runner_logic.gd")
const World := preload("res://scripts/minigames/games/runner/runner_world.gd")
const Stage3D := preload("res://scripts/minigames/games/_3db_stage/stage3d.gd")
const SpeedLines := preload("res://scripts/minigames/games/_3db_stage/speed_lines.gd")
const GoobyMount := preload("res://scripts/minigames/games/_3db_stage/gooby_mount.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")

## Weltzahlen der Darstellung (KEINE Spiel-Mathe) — aus runner.js übernommen.
const SPAWN_Z := -88.0
const DESPAWN_Z := 9.0
## Sichtweite, ab der ein Objekt gezeichnet wird (m).
const DRAW_Z := -86.0
## Münzen sitzen auf dieser Höhe (Web: y 0.55).
const COIN_Y := 0.55
## Verfolgerkamera. Web: 0/3.6/7 mit Blick auf 0/0.9/−3.5 — dort war Gooby ein
## Krümel am unteren Rand. Wir rücken näher heran und geben der Kamera einen
## festen Neigungswinkel statt eines Blickpunkts: so sitzt die Figur bei JEDEM
## Seitenverhältnis auf derselben Bildhöhe (Blickpunkt-Kameras verrutschen
## hochkant), und der Horizont bleibt oben im Bild.
const CAM_HEIGHT := 3.25
const CAM_BACK := 6.3
const CAM_PITCH := 16.0
## Hochkant: höher und weiter hinten, sonst sieht man die Hindernisse zu spät.
## Die Neigung geht dabei HOCH, nicht runter: das hohe Bild zeigt sonst ein
## Drittel nackten Asphalt direkt vor der Kamera statt der Strecke.
const CAM_PORTRAIT_LIFT := 0.55
const CAM_PORTRAIT_BACK := 0.8
const CAM_PORTRAIT_PITCH := -1.5
## §G4.8-Tempojuice: waagerechter Blickwinkel + Kick über das Tempoband.
const HFOV_BASE := 88.0
const HFOV_KICK := 12.0
const SPEED_BAND := Vector2(6.0, 13.0)
const STREAK_RATE: Array = [[9.0, 0.0], [11.0, 4.0], [13.0, 9.0]]
## Entwurfs-Kurzkante — Pixelmaße der Bedienleiste skalieren damit.
const DESIGN_SHORT := 390.0
## Nach so vielen Sekunden blendet der Wisch-Hinweis aus.
const HINT_FADE_SEC := 5.0

## Autohaus-Haken: später vom Host befüllbar (Skin-Id / Tempo-Bonus).
var car_skin := ""
var speed_bonus := 0.0

## Für Screenshot-/Zertifizierungsläufe: der Pilot aus runner.js übernimmt.
var autoplay := false

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
var _row_seq := 0
var _auto := {"handled": -1, "action": "", "at_z": 0.0, "row": -1, "target": 1}
var _dist_since_row := 0.0
var _next_mystery_at := 0.0
var _stage: Node3D
var _world: Node3D
var _gooby: Node3D
var _shadow: MeshInstance3D
var _shield_vis: MeshInstance3D
var _magnet_vis: MeshInstance3D
var _streaks: MultiMeshInstance3D
var _dust: GPUParticles3D
var _sparkle: GPUParticles3D
var _speed := 6.0
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
	_build_stage()
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
	if _stage != null:
		_stage.call("apply_size", view_size)
		_place_camera(0.0)
	_layout_hud()
	queue_redraw()


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	var dt := minf(delta, 0.1)
	elapsed += dt
	_banner_t = maxf(0.0, _banner_t - dt)
	_invuln = maxf(0.0, _invuln - dt)
	_magnet_t = maxf(0.0, _magnet_t - dt)
	_x2_t = maxf(0.0, _x2_t - dt)
	_speed = Logic.speed_at(elapsed, tune)
	var dz := _speed * dt
	var prev_meters := meters
	meters += dz
	_advance_band(dz)
	_spawn(dz)
	if autoplay:
		_autoplay_tick()
	_move_player(dt)
	_collide(dz)
	_milestone(prev_meters)
	_publish_score()
	_update_labels()
	_fade_hint()
	_sync_world(dt)
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


## Welt (x, y, z) → Bildschirmpixel des Viewports (für Float-Texte).
func project(wx: float, wy: float, wz: float) -> Vector2:
	var cam: Camera3D = _stage.get("camera")
	if cam == null:
		return view_size * 0.5
	return cam.unproject_position(Vector3(wx, wy, wz))


# ── Aufbau ────────────────────────────────────────────────────────────────


func _build_stage() -> void:
	_stage = Stage3D.new()
	add_child(_stage)
	(
		_stage
		. call(
			"build",
			{
				# Web: scene.background = 0xbfe3ff, Fog(SKY, 34, 92).
				"sky_top": Color(0.55, 0.79, 1.0),
				"sky_horizon": Color(0.749, 0.89, 1.0),
				"ground_horizon": Color(0.7, 0.82, 0.74),
				"ground_bottom": Color(0.42, 0.53, 0.4),
				"fog_color": Color(0.749, 0.89, 1.0),
				"fog_from": 34.0,
				"fog_to": 92.0,
				"glow": 0.22,
				# Web: DirectionalLight(0xfff2dd, 1.0) bei (4, 9, 6).
				"sun_dir": Vector3(-0.35, -0.79, -0.53),
				"sun_color": Color(1.0, 0.949, 0.867),
				"sun_energy": 1.0,
				# Web: HemisphereLight(0xfff5e8, 0xb8a898, 1.0) — der Mittelwert
				# beider Halbkugeln ist das, was eine senkrechte Fassade sieht.
				"ambient_color": Color(0.861, 0.81, 0.753),
				# 1,0 ist die WEB-TREUE Zahl, nicht mehr: three.js teilt die
				# Hemisphäre genauso durch π wie die Sonne (BRDF_Lambert), und
				# LIGHT_SCALE bildet beides ab. Größere Werte kochen den dunklen
				# Asphalt zu Lavendel-Weiß aus — genau das war der „alles wirkt
				# 2D"-Eindruck: ohne dunkle Fahrbahn fehlt dem Korridor Tiefe.
				"ambient": 2.2,
				# Winziges Gegenlicht von der Schattenseite (das Web hat keins,
				# aber ACES zieht dort stärker an als three.js' NoToneMapping).
				"fill_energy": 0.8,
				"fill_color": Color(0.8, 0.85, 0.95),
				# Die Kenney-Häuser tragen fast schwarze Sockelbänder. Mit dem
				# Bühnen-Kontrast (1,05) soffen sie zu einem Loch ab: ein
				# Viertel des Bildes lag unter Luma 30, im Web sind es 0,4 %.
				# Flacher gefahren bleibt der Sockel ein lesbares Dunkelgrau.
				"contrast": 0.92,
				"hfov": HFOV_BASE,
				"shadow_distance": 40.0,
				"far": 200.0,
			}
		)
	)
	_world = World.new()
	_stage.add_child(_world)
	_world.call("build", float((tune["OBSTACLES"] as Dictionary)["overhead"]["gapY"]))

	_gooby = GoobyMount.new()
	_stage.add_child(_gooby)
	_gooby.call("mount", float(tune["STAND_HEIGHT"]) * float(tune["RENDER_SCALE_MULT"]))
	_shadow = Fx.blob_shadow(0.42, 0.34)
	_stage.add_child(_shadow)
	_build_auras()

	_streaks = SpeedLines.new()
	(_stage.get("camera") as Camera3D).add_child(_streaks)
	_streaks.call("build", 16, Vector2(2.6, 3.6), Vector2(4.0, 9.0))
	_streaks.set("enabled", not _reduced_motion())

	_dust = (
		Fx
		. particles(
			{
				"color": Color(0.92, 0.88, 0.78, 0.85),
				"amount": 10,
				"lifetime": 0.55,
				"one_shot": true,
				"explosiveness": 0.95,
				"speed": Vector2(1.0, 2.6),
				"spread": 62.0,
				"size": Vector2(0.06, 0.15),
			}
		)
	)
	_stage.add_child(_dust)
	_sparkle = (
		Fx
		. particles(
			{
				"color": Color(1.0, 0.9, 0.5, 1.0),
				"amount": 12,
				"lifetime": 0.5,
				"one_shot": true,
				"explosiveness": 1.0,
				"additive": true,
				"speed": Vector2(1.2, 3.0),
				"spread": 180.0,
				"gravity": Vector3(0.0, -1.5, 0.0),
				"size": Vector2(0.05, 0.12),
			}
		)
	)
	_stage.add_child(_sparkle)
	_place_camera(0.0)


func _build_auras() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.72
	sphere.height = 1.44
	sphere.radial_segments = 16
	sphere.rings = 8
	sphere.material = Fx.glass(Color(0.39, 0.71, 0.96, 0.26))
	_shield_vis = MeshInstance3D.new()
	_shield_vis.mesh = sphere
	_shield_vis.visible = false
	_shield_vis.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage.add_child(_shield_vis)

	_magnet_vis = Fx.ring(0.95, 0.05, Color(0.42, 0.8, 1.0))
	_magnet_vis.rotation_degrees.x = -90.0
	_magnet_vis.visible = false
	_stage.add_child(_magnet_vis)


func _build_hud() -> void:
	_score_label = Label.new()
	_score_label.theme_type_variation = &"HeadlineLabel"
	_tint(_score_label)
	add_child(_score_label)
	_stat_label = Label.new()
	_stat_label.theme_type_variation = &"CaptionLabel"
	_tint(_stat_label)
	add_child(_stat_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.runner.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tint(_hint_label)
	add_child(_hint_label)
	_update_labels()


## Heller Text mit weichem Schattenrand — er liegt jetzt auf einer 3D-Szene.
func _tint(label: Label) -> void:
	label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.96))
	label.add_theme_color_override("font_outline_color", Color(0.14, 0.12, 0.17, 0.62))
	label.add_theme_constant_override("outline_size", 8)


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


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


# ── Eingabe/Aktionen ──────────────────────────────────────────────────────


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
	_gooby.call("play", "hop")
	AudioDirector.try_play(self, "mg_good", 1.3)


func _slide() -> void:
	if _slide_t >= 0.0 or _jump_t >= 0.0:
		return
	_slide_t = 0.0
	AudioDirector.try_play(self, "mg_junk", 1.25)


# ── Simulation (unverändert gegenüber der 2D-Fassung) ─────────────────────


func _advance_band(dz: float) -> void:
	(_world.get("band") as RefCounted).call("advance", dz)


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
		# Geparkte Autos stehen LÄNGS zum Korridor (Web-GP3-Korrektur) — quer
		# ragten sie in die Nachbarspuren und logen über die 0,95-m-Hitbox.
		var yaw := 0.0 if rng.next() < 0.5 else PI
		yaw += (rng.next() - 0.5) * 0.12
		(
			_obstacles
			. append(
				{
					"kind": str(lanes[lane]),
					"lane": lane,
					"z": SPAWN_Z,
					"yaw": yaw,
					"row": _row_seq,
				}
			)
		)
	_row_seq += 1
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


# ── Autoplay (nur Screenshots/Zertifizierung, Portierung von runner.js) ───


## Ein Pilotenschritt: Spur halten/wechseln, Sprung/Rutsche vormerken.
## Nutzt NICHT `rng` — der Bot darf den gesäten Ablauf des Spiels nicht
## verschieben (im Web ist er ebenfalls nur ein Dev-Schalter).
func _autoplay_tick() -> void:
	_autoplay_plan()
	if str(_auto["action"]).is_empty():
		return
	for ob in _obstacles:
		if int(ob["row"]) != int(_auto["row"]):
			continue
		if float(ob["z"]) < float(_auto["at_z"]):
			return
		if str(_auto["action"]) == "jump":
			_jump()
		else:
			_slide()
		_auto["action"] = ""
		return


func _autoplay_plan() -> void:
	if int(_auto["target"]) != _lane:
		_change_lane(signi(int(_auto["target"]) - _lane))
		return
	var row: Dictionary = {}
	for ob in _obstacles:
		if float(ob["z"]) > -1.0 or int(ob["row"]) <= int(_auto["handled"]):
			continue
		if row.is_empty() or float(ob["z"]) > float(row["z"]):
			row = ob
	# Überraschungskiste vor dem nächsten Hindernis mitnehmen.
	var box: Dictionary = {}
	for entry in _mystery:
		if float(entry["z"]) >= -0.5:
			continue
		if box.is_empty() or float(entry["z"]) > float(box["z"]):
			box = entry
	var box_first := (
		not box.is_empty()
		and float(box["z"]) > -_speed * 1.5
		and (row.is_empty() or float(box["z"]) > float(row["z"]) + 2.0)
	)
	if box_first:
		if int(box["lane"]) != _lane:
			_change_lane(signi(int(box["lane"]) - _lane))
		return
	if row.is_empty() or float(row["z"]) < -_speed * 0.95:
		return
	_auto["handled"] = int(row["row"])
	_autoplay_pick_lane(int(row["row"]))


func _autoplay_pick_lane(row_id: int) -> void:
	var lanes: Array = []
	for _i in int(tune["LANES"]):
		lanes.append(null)
	for ob in _obstacles:
		if int(ob["row"]) == row_id:
			lanes[int(ob["lane"])] = str(ob["kind"])
	var pass_flags := Logic.passable_lanes({"lanes": lanes, "gap": 0.0}, tune)
	var order: Array[int] = [_lane, _lane - 1, _lane + 1, _lane - 2, _lane + 2]
	var target := -1
	for lane in order:
		if lane >= 0 and lane < lanes.size() and bool(pass_flags[lane]):
			target = lane
			break
	if target < 0:
		return
	_auto["target"] = target
	if target != _lane:
		_change_lane(signi(target - _lane))
	var kind: Variant = lanes[target]
	if kind == null:
		_auto["action"] = ""
		return
	var pass_mode := str((tune["OBSTACLES"] as Dictionary)[str(kind)]["pass"])
	var lead := (
		float(tune["JUMP_SEC"]) * 0.45 if pass_mode == "jump" else float(tune["SLIDE_SEC"]) * 0.42
	)
	_auto["action"] = pass_mode
	_auto["at_z"] = -_speed * lead
	_auto["row"] = row_id


func _move_player(dt: float) -> void:
	var lane_target := float((tune["LANE_X"] as Array)[_lane])
	_lane_x += (lane_target - _lane_x) * minf(1.0, dt / float(tune["LANE_CHANGE_SEC"]))
	if _jump_t >= 0.0:
		_jump_t += dt
		if _jump_t >= float(tune["JUMP_SEC"]):
			_jump_t = -1.0
			if not _reduced_motion():
				Fx.burst(_dust, Vector3(_lane_x, 0.08, 0.0))
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
	var lane_x: Array = tune["LANE_X"]
	var at := Vector3(float(lane_x[int(coin["lane"])]), float(coin["y"]), float(coin["z"]))
	if not _reduced_motion():
		Fx.burst(_sparkle, at)
	if ctx.juice != null:
		ctx.juice.float_text(project(at.x, at.y + 0.5, at.z), "+%d" % points, Color(1.0, 0.82, 0.4))
	if mult > prev_mult:
		_set_banner(I18nService.t("mg.runner.combo", {"mult": mult}))
		AudioDirector.try_play(self, "mg_combo")
		_gooby.call("emote", "ecstatic", 1.0)
		_stage.call("pulse_glow", 0.7)


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
		_gooby.call("emote", "ecstatic", 1.2)
		if not _reduced_motion():
			Fx.burst(_sparkle, Vector3(_lane_x, 1.0, float(box["z"])))
		_stage.call("pulse_glow", 1.0)
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
		Fx.burst(_sparkle, Vector3(_lane_x, 0.9, 0.0))
		return
	AudioDirector.try_play(self, "mg_spill")
	Fx.burst(_dust, Vector3(_lane_x, 0.25, -0.6))
	if ctx.juice != null:
		ctx.juice.hit_freeze(90)
	if outcome == "wipeout":
		_gooby.call("emote", "dizzy", 4.0)
		_finish()
		return
	_gooby.call("emote", "sad", 1.2)
	_set_banner(I18nService.t("mg.runner.stumble", {"left": int(tune["MAX_HITS"]) - hits}))


func _milestone(prev_meters: float) -> void:
	var milestone := Logic.crossed_runner_milestone(prev_meters, meters)
	if milestone <= 0:
		return
	AudioDirector.try_play(self, "mg_perfect")
	if not _reduced_motion():
		Fx.burst(_sparkle, Vector3(_lane_x, 1.4, 0.0))
	if ctx.juice != null:
		ctx.juice.float_text(
			project(_lane_x, 2.0, 0.0),
			I18nService.t("mg.runner.milestone", {"m": milestone}),
			Color(0.7, 1.0, 0.8)
		)
	_stage.call("pulse_glow", 0.6)


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


## Der Hinweis steht unten mitten im Bild — nach ein paar Sekunden hat man ihn
## gelesen, danach gehört die Stelle Gooby.
func _fade_hint() -> void:
	if _hint_label == null:
		return
	_hint_label.modulate.a = clampf((HINT_FADE_SEC - elapsed) / 1.2, 0.0, 1.0)


func _update_labels() -> void:
	# Der Host zeigt den Score bereits oben — hier laufen die Renn-Zahlen.
	_score_label.text = I18nService.t("mg.runner.distance", {"m": int(floor(meters))})
	_stat_label.text = I18nService.t(
		"mg.runner.stats", {"coins": coins, "left": maxi(0, int(tune["MAX_HITS"]) - hits)}
	)


# ── 3D-Abgleich ───────────────────────────────────────────────────────────


## Alles, was sich bewegt, in die 3D-Welt schreiben. Läuft NACH der Simulation
## und fasst keine Spielzahl an — reine Darstellung.
func _sync_world(dt: float) -> void:
	_stage.call("tick", dt)
	_gooby.call("tick", dt)
	_sync_player(dt)
	_sync_props()
	_sync_camera(dt)


func _sync_player(dt: float) -> void:
	var y := player_y()
	var sliding := is_sliding()
	var squash := float(tune["SLIDE_HEIGHT"]) / float(tune["STAND_HEIGHT"]) if sliding else 1.0
	var target := Vector3(1.0 + (1.0 - squash) * 0.55, squash, 1.0 + (1.0 - squash) * 0.55)
	_gooby.scale = _gooby.scale.lerp(target, minf(1.0, dt * 16.0))
	_gooby.position = Vector3(_lane_x, y, 0.0)
	_gooby.rotation.z = (_lane_x - float((tune["LANE_X"] as Array)[_lane])) * 0.25
	_gooby.visible = _invuln <= 0.0 or fmod(_invuln * 12.0, 2.0) < 1.0
	_gooby.call("run", 1.0 if not sliding else 0.0)
	_shadow.position = Vector3(_lane_x, 0.02, 0.0)
	_shadow.scale = Vector3.ONE * maxf(0.45, 1.0 - y * 0.35)
	_shield_vis.visible = _shield
	_shield_vis.position = Vector3(_lane_x, y + 0.55, 0.0)
	_shield_vis.rotation.y += dt * 1.5
	_magnet_vis.visible = _magnet_t > 0.0
	_magnet_vis.position = Vector3(_lane_x, y + 0.12, 0.0)
	_magnet_vis.rotation.y += dt * 2.4


func _sync_props() -> void:
	var lane_x: Array = tune["LANE_X"]
	var gap_y := float((tune["OBSTACLES"] as Dictionary)["overhead"]["gapY"])
	_world.call("begin_props")
	for ob in _obstacles:
		var z := float(ob["z"])
		if z < DRAW_Z or z > DESPAWN_Z:
			continue
		_world.call(
			"push_obstacle",
			str(ob["kind"]),
			float(lane_x[int(ob["lane"])]),
			z,
			float(ob.get("yaw", 0.0)),
			gap_y
		)
	for coin in _coins:
		var cz := float(coin["z"])
		if cz < DRAW_Z or cz > DESPAWN_Z:
			continue
		_world.call(
			"push_coin",
			float(lane_x[int(coin["lane"])]),
			float(coin["y"]),
			cz,
			elapsed * 4.0 + cz * 0.3
		)
	for box in _mystery:
		var bz := float(box["z"])
		if bz < DRAW_Z or bz > DESPAWN_Z:
			continue
		_world.call(
			"push_mystery",
			float(lane_x[int(box["lane"])]),
			bz,
			elapsed * 2.0,
			sin(elapsed * 3.4) * 0.09
		)
	_world.call("flush_props")
	(_world.get("band") as RefCounted).call("flush")


## Verfolgerkamera + §G4.8-Tempojuice (FOV-Kick, Streifen, Mikro-Zittern).
func _sync_camera(dt: float) -> void:
	var reduced := _reduced_motion()
	var jitter := 0.0
	if not reduced:
		var top := clampf((_speed - 12.4) / 0.6, 0.0, 1.0)
		jitter = top * 0.03
	_place_camera(jitter)
	var band01 := clampf(
		(_speed - SPEED_BAND.x) / maxf(0.001, SPEED_BAND.y - SPEED_BAND.x), 0.0, 1.0
	)
	_stage.call("set_fov_bonus", HFOV_KICK * band01)
	_streaks.set("enabled", not reduced)
	_streaks.call("update", dt, _speed, SpeedLines.rate_at(_speed, STREAK_RATE))


func _place_camera(jitter: float) -> void:
	var cam: Camera3D = _stage.get("camera")
	if cam == null:
		return
	var lift := 0.0 if landscape else CAM_PORTRAIT_LIFT
	var back := 0.0 if landscape else CAM_PORTRAIT_BACK
	var pitch := CAM_PITCH + (0.0 if landscape else CAM_PORTRAIT_PITCH)
	var follow := _lane_x * 0.35
	var jx := randf_range(-jitter, jitter)
	var jy := randf_range(-jitter, jitter)
	cam.position = Vector3(follow + jx, CAM_HEIGHT + lift + jy, CAM_BACK + back)
	cam.rotation = Vector3(deg_to_rad(-pitch), 0.0, 0.0)


func _reduced_motion() -> bool:
	var settings := get_node_or_null(^"/root/AppSettings")
	if settings != null and settings.has_method("is_reduced_motion"):
		return bool(settings.call("is_reduced_motion"))
	return false


# ── 2D-Overlay (Banner + Powerup-Restzeiten über der 3D-Szene) ────────────


func _draw() -> void:
	_draw_powerups()
	_draw_banner()


func _draw_powerups() -> void:
	var font := ThemeService.font(700)
	var x := view_size.x - 150.0 * _ui
	var y := 16.0 * _ui
	var size := maxi(13, int(19.0 * _ui))
	if _x2_t > 0.0:
		draw_string(
			font,
			Vector2(x, y + size),
			"x2 %.1fs" % _x2_t,
			HORIZONTAL_ALIGNMENT_RIGHT,
			136.0 * _ui,
			size,
			Color(1.0, 0.86, 0.4)
		)
		y += size * 1.4
	if _magnet_t > 0.0:
		draw_string(
			font,
			Vector2(x, y + size),
			"%s %.1fs" % [I18nService.t("mg.runner.magnet"), _magnet_t],
			HORIZONTAL_ALIGNMENT_RIGHT,
			136.0 * _ui,
			size,
			Color(0.6, 0.88, 1.0)
		)


func _draw_banner() -> void:
	if _banner_t <= 0.0 or _banner.is_empty():
		return
	var font := ThemeService.font(800)
	var alpha := clampf(_banner_t * 1.4, 0.0, 1.0)
	var w := minf(view_size.x - 24.0, 440.0 * _ui)
	draw_string(
		font,
		Vector2((view_size.x - w) * 0.5, view_size.y * 0.24),
		_banner,
		HORIZONTAL_ALIGNMENT_CENTER,
		w,
		maxi(18, int(28.0 * _ui)),
		Color(1.0, 0.95, 0.8, alpha)
	)
