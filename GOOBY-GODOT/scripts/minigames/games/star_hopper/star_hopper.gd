extends MinigameBase
## Sternenhüpfer (starHopper) — Spiel-Szene. Alle MECHANIK-Zahlen aus
## StarHopperLogic/StarHopperBot (zahlengleich zum Web): 3 Bahnen, Tempo +5 %
## alle 10 s, Meteore mit 70-%-Hitbox, Sterne +3 / goldene Karotten +10,
## Schild ab Score 60, angekündigte Meteorschauer, Wurmloch-Tor, ein Treffer
## beendet die Runde. Score = Meter/10 + Aufsammler.
##
## 2D-STATT-3D (begründet): der Korridor ist ein 3-Bahn-Band entlang EINER
## Achse — eine gescrollte 2D-Ansicht mit Parallax-Sternenfeld zeigt mehr
## Vorwarnstrecke als eine 3D-Kamera und bleibt auf dem Handy scharf lesbar.

const Logic := preload("res://scripts/minigames/games/star_hopper/star_hopper_logic.gd")
const Bot := preload("res://scripts/minigames/games/star_hopper/star_hopper_bot.gd")

## Sichtbare Strecke oberhalb des Schiffs (m) — das ist die Vorwarnzeit.
const VIEW_AHEAD_M := 62.0
## Bildschirmanteil (von unten), auf dem das Schiff sitzt.
const SHIP_ANCHOR := 0.22
## Mindest-Wischweg (px) für einen Zwei-Bahn-Wechsel.
const SWIPE_MIN_PX := 40.0

const SPACE_TOP := Color(0.07, 0.05, 0.18)
const SPACE_BOTTOM := Color(0.17, 0.1, 0.3)
const METEOR_COLOR := Color(0.62, 0.45, 0.38)
const STAR_COLOR := Color(1.0, 0.88, 0.4)
const GOLD_COLOR := Color(1.0, 0.62, 0.2)

var tune: Dictionary = {}
var rng: GoobyRng
var traveled := 0.0
var elapsed := 0.0
var lane := 1
var lane_visual := 1.0
var pickup_points := 0
var score := 0
var shielded := false
var shield_spawned := false
var invuln := 0.0
var wormhole_left := 0.0
var wormhole_spawned := false
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

var _stream: Callable
var _rows: Array[Dictionary] = []
var _meteors: Array[Dictionary] = []
var _pickups: Array[Dictionary] = []
var _next_row_m := 30.0
var _shower_at := 0.0
var _shower_lanes: Dictionary = {}
var _shower_state := "idle"
var _shower_left := 0.0
var _shower_drop := 0.0
var _stars: Array[Vector3] = []
var _pop := 0.0
var _roll := 0.0
var _touch_from := Vector2.ZERO
var _flash := 0.0
var _flash_text := ""
var _dist_label: Label
var _state_label: Label
var _hint_label: Label


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = Logic.apply_difficulty(Logic.HOPPER, ctx.difficulty)
	rng = ctx.rng()
	_stream = func() -> float: return rng.next()
	_shower_at = float(tune["SHOWER_EVERY_SEC"])
	for i in 90:
		_stars.append(Vector3(rng.next(), rng.next(), 0.3 + rng.next() * 0.7))
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
	position = Vector2.ZERO
	if _dist_label != null:
		_dist_label.position = Vector2(16.0, 10.0)
		_state_label.position = Vector2(16.0, 48.0)
		_hint_label.position = Vector2(view_size.x * 0.5 - 150.0, view_size.y - 48.0)
		_hint_label.size = Vector2(300.0, 40.0)
	queue_redraw()


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	elapsed += delta
	invuln = maxf(0.0, invuln - delta)
	_pop = maxf(0.0, _pop - delta)
	_roll = maxf(0.0, _roll - delta)
	_flash = maxf(0.0, _flash - delta)
	lane_visual = move_toward(lane_visual, float(lane), delta / float(tune["LANE_CHANGE_SEC"]))
	var dm := Logic.speed_at(elapsed, tune) * delta
	_step_wormhole(delta)
	_advance(dm, delta)
	if not bool(tune["ENDLESS"]) and elapsed >= float(tune["DURATION_SEC"]):
		_finish()
		return
	_update_labels()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_touch_from = event.position
		else:
			_resolve_gesture(event.position)


## Aktueller Score inklusive Streckenpunkte.
func live_score() -> int:
	return Logic.hopper_score(traveled, pickup_points, tune)


func _build_hud() -> void:
	_dist_label = Label.new()
	_dist_label.theme_type_variation = &"HeadlineLabel"
	add_child(_dist_label)
	_state_label = Label.new()
	_state_label.theme_type_variation = &"CaptionLabel"
	add_child(_state_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.starHopper.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint_label)
	# Weltraum-Hintergrund — die Theme-Schriftfarben sind für Helles gedacht.
	_dist_label.add_theme_color_override("font_color", Color(1.0, 0.97, 0.92))
	_state_label.add_theme_color_override("font_color", Color(0.7, 0.92, 1.0))
	_hint_label.add_theme_color_override("font_color", Color(0.82, 0.84, 0.98))
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


## Tippen = 1 Bahn, Wischen = 2 Bahnen (Web-Kontrakt).
func _resolve_gesture(to: Vector2) -> void:
	var d := to - _touch_from
	var gesture := {}
	if absf(d.x) >= SWIPE_MIN_PX:
		gesture = {"kind": "swipe", "dir": "left" if d.x < 0.0 else "right"}
	else:
		gesture = {"kind": "tap", "side": "left" if to.x < view_size.x * 0.5 else "right"}
	var next := Logic.lane_after_gesture(lane, gesture, false, tune)
	if next != lane:
		lane = next
		AudioDirector.try_play(self, "mg_good", 1.15)


func _advance(dm: float, delta: float) -> void:
	var before := traveled
	traveled += dm
	_step_showers(delta)
	while traveled + VIEW_AHEAD_M >= _next_row_m:
		_spawn_row()
	_collect(before, dm)
	if invuln <= 0.0:
		_check_hits(before, dm)
	_cull()
	score = live_score()
	ctx.report_score(score, 0)
	if Logic.should_spawn_shield(score, shield_spawned, tune):
		shield_spawned = true
		_pickups.append({"kind": "shield", "lane": lane, "m": traveled + VIEW_AHEAD_M * 0.8})


func _spawn_row() -> void:
	var row := Bot.generate_row(_stream, elapsed, _rows, tune)
	_rows.append(row)
	if _rows.size() > 6:
		_rows.pop_front()
	var at := _next_row_m
	_next_row_m += float(row["gap"])
	for i in int(tune["LANES"]):
		if bool(row["blocked"][i]):
			_meteors.append({"lane": i, "m": at, "spin": rng.next() * TAU, "approach": 0.0})
	var pickup := Logic.roll_pickup(_stream, tune)
	if pickup.is_empty():
		return
	var free: Array[int] = []
	for i in int(tune["LANES"]):
		if not bool(row["blocked"][i]):
			free.append(i)
	if free.is_empty():
		return
	var slot: int = free[mini(free.size() - 1, int(rng.next() * free.size()))]
	_pickups.append(
		{"kind": str(pickup["kind"]), "points": int(pickup["points"]), "lane": slot, "m": at}
	)


func _step_showers(delta: float) -> void:
	match _shower_state:
		"idle":
			if elapsed >= _shower_at:
				_shower_lanes = Logic.pick_shower_lanes(_stream, tune)
				_shower_state = "warn"
				_shower_left = float(tune["SHOWER_TELEGRAPH_SEC"])
				AudioDirector.try_play(self, "mg_junk", 0.6)
		"warn":
			_shower_left -= delta
			if _shower_left <= 0.0:
				_shower_state = "active"
				_shower_left = float(tune["SHOWER_DURATION_SEC"])
				_shower_drop = 0.0
		"active":
			_shower_left -= delta
			_shower_drop -= delta
			if _shower_drop <= 0.0:
				_shower_drop = float(tune["SHOWER_DROP_EVERY_SEC"])
				for l: int in _shower_lanes["danger"]:
					(
						_meteors
						. append(
							{
								"lane": l,
								"m": traveled + VIEW_AHEAD_M,
								"spin": rng.next() * TAU,
								"approach": float(tune["SHOWER_METEOR_SPEED"]),
							}
						)
					)
			if _shower_left <= 0.0:
				_shower_state = "idle"
				_shower_at = elapsed + float(tune["SHOWER_EVERY_SEC"])


func _step_wormhole(delta: float) -> void:
	if wormhole_left > 0.0:
		var before := float(tune["WORMHOLE_SEC"]) - wormhole_left
		wormhole_left = maxf(0.0, wormhole_left - delta)
		var after := float(tune["WORMHOLE_SEC"]) - wormhole_left
		var awarded := Logic.wormhole_awards(before, after, tune)
		if awarded > 0:
			pickup_points += awarded * int(tune["WORMHOLE_TICK_POINTS"])
			AudioDirector.try_play(self, "mg_combo", 1.2)
		return
	if Logic.should_spawn_wormhole(_stream, elapsed, wormhole_spawned, false, tune):
		wormhole_spawned = true
		wormhole_left = float(tune["WORMHOLE_SEC"])
		AudioDirector.try_play(self, "mg_golden")
		_flash_text = I18nService.t("mg.starHopper.wormhole")
		_flash = 1.4
		if ctx.juice != null:
			ctx.juice.bloom_pulse(1.0)
			ctx.juice.slowmo(0.5, 320)


func _collect(before: float, dm: float) -> void:
	var kept: Array[Dictionary] = []
	for p in _pickups:
		var hit := (
			int(p["lane"]) == lane
			and float(p["m"]) >= before - 3.0
			and float(p["m"]) <= before + dm + 3.0
		)
		if not hit:
			kept.append(p)
			continue
		_on_pickup(p)
	_pickups = kept


func _on_pickup(p: Dictionary) -> void:
	var pos := _to_screen(int(p["lane"]), float(p["m"]))
	if str(p["kind"]) == "shield":
		shielded = true
		AudioDirector.try_play(self, "mg_golden")
		_flash_text = I18nService.t("mg.starHopper.shield")
		_flash = 1.2
		if ctx.juice != null:
			ctx.juice.bloom_pulse(0.9)
			ctx.juice.float_text(pos, _flash_text, Color(0.5, 0.85, 1.0))
		return
	pickup_points += int(p["points"])
	if str(p["kind"]) == "gold":
		_roll = float(Logic.HOPPER_JUICE["BARREL_ROLL_SEC"])
		AudioDirector.try_play(self, "mg_golden")
		if ctx.juice != null:
			ctx.juice.bloom_pulse(0.8)
			ctx.juice.hit_freeze(50)
			ctx.juice.float_text(pos, "+%d" % int(p["points"]), GOLD_COLOR)
	else:
		_pop = float(Logic.HOPPER_JUICE["POP_SEC"])
		AudioDirector.try_play(self, "mg_good", 1.2)
		if ctx.juice != null:
			ctx.juice.float_text(pos, "+%d" % int(p["points"]), STAR_COLOR)


func _check_hits(before: float, dm: float) -> void:
	var player := {"lane": lane, "m": before}
	for meteor in _meteors:
		if not Logic.sweep_hits_meteor(player, meteor, dm, tune):
			continue
		var result := Logic.resolve_hit(shielded)
		if bool(result["ended"]):
			AudioDirector.try_play(self, "mg_lose")
			if ctx.juice != null:
				ctx.juice.shake(0.8)
				ctx.juice.hit_freeze(140)
			_finish()
			return
		shielded = false
		invuln = float(tune["SHIELD_POP_INVULN_SEC"])
		_flash_text = I18nService.t("mg.starHopper.shield_pop")
		_flash = 1.2
		AudioDirector.try_play(self, "mg_spill")
		if ctx.juice != null:
			ctx.juice.shake(0.5)
			ctx.juice.bloom_pulse(0.7)
		return


func _cull() -> void:
	var kept_m: Array[Dictionary] = []
	for meteor in _meteors:
		meteor["m"] = float(meteor["m"]) - float(meteor["approach"]) * get_process_delta_time()
		if float(meteor["m"]) > traveled - 12.0:
			kept_m.append(meteor)
	_meteors = kept_m
	var kept_p: Array[Dictionary] = []
	for p in _pickups:
		if float(p["m"]) > traveled - 8.0:
			kept_p.append(p)
	_pickups = kept_p


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	ctx.report_end({"score": live_score(), "distance": int(traveled), "pickups": pickup_points})


func _update_labels() -> void:
	_dist_label.text = I18nService.t("mg.starHopper.distance", {"m": int(traveled)})
	if shielded:
		_state_label.text = I18nService.t("mg.starHopper.shield")
	else:
		_state_label.text = I18nService.t(
			"mg.starHopper.speed", {"v": "%.1f" % Logic.speed_at(elapsed, tune)}
		)


func _lane_x(lane_f: float) -> float:
	var span := minf(view_size.x * 0.78, 420.0)
	return view_size.x * 0.5 + (lane_f - 1.0) * span * 0.34


## Bahn + Streckenmeter → Bildschirmpixel.
func _to_screen(lane_i: int, m: float) -> Vector2:
	return _to_screen_f(float(lane_i), m)


func _to_screen_f(lane_f: float, m: float) -> Vector2:
	var anchor := view_size.y * (1.0 - SHIP_ANCHOR)
	var ppm := anchor / VIEW_AHEAD_M
	return Vector2(_lane_x(lane_f), anchor - (m - traveled) * ppm)


func _draw() -> void:
	_draw_space()
	_draw_lanes()
	if _shower_state == "warn":
		_draw_shower_warning()
	for meteor in _meteors:
		_draw_meteor(meteor)
	for p in _pickups:
		_draw_pickup(p)
	_draw_ship()
	_draw_flash()


func _draw_space() -> void:
	var vp := view_size
	for i in 12:
		var f := float(i) / 11.0
		draw_rect(Rect2(0.0, vp.y * f, vp.x, vp.y / 11.0 + 1.0), SPACE_TOP.lerp(SPACE_BOTTOM, f))
	for s in _stars:
		var depth := s.z
		var y := fposmod(s.y * vp.y + traveled * depth * 9.0, vp.y)
		var r := 1.0 + depth * 1.8
		draw_circle(Vector2(s.x * vp.x, y), r, Color(1.0, 0.98, 0.9, 0.35 + depth * 0.5))
	if wormhole_left > 0.0:
		var f := wormhole_left / float(tune["WORMHOLE_SEC"])
		for i in 8:
			draw_arc(
				vp * 0.5,
				40.0 + i * 42.0 + (1.0 - f) * 60.0,
				0.0,
				TAU,
				32,
				Color(0.6, 0.4, 1.0, 0.45 * f),
				3.0
			)


func _draw_lanes() -> void:
	# Abwechselnd getönte Bahnen — sonst verschwimmt das Raster im Dunkeln.
	for i in int(tune["LANES"]):
		if i % 2 == 0:
			continue
		var left := _lane_x(i - 0.5)
		draw_rect(
			Rect2(left, 0.0, _lane_x(i + 0.5) - left, view_size.y), Color(0.55, 0.6, 1.0, 0.05)
		)
	for i in int(tune["LANES"]) + 1:
		var x := _lane_x(i - 0.5)
		draw_line(Vector2(x, 0.0), Vector2(x, view_size.y), Color(0.55, 0.6, 1.0, 0.18), 2.0)
	# Fluchtstreifen als Tempo-Feedback.
	var speed := Logic.speed_at(elapsed, tune)
	for i in 10:
		var y := fposmod(view_size.y * i / 10.0 - traveled * 8.0, view_size.y)
		draw_line(
			Vector2(0.0, y),
			Vector2(view_size.x, y),
			Color(0.7, 0.75, 1.0, 0.05 + 0.03 * speed / 19.0),
			1.5
		)


func _draw_shower_warning() -> void:
	var pulse := 0.3 + 0.3 * sin(elapsed * 26.0)
	for l: int in _shower_lanes["danger"]:
		var x := _lane_x(float(l))
		var w := _lane_x(0.5) - _lane_x(-0.5)
		draw_rect(Rect2(x - w * 0.5, 0.0, w, view_size.y), Color(1.0, 0.35, 0.35, pulse * 0.35))
	draw_string(
		ThemeService.font(800),
		Vector2(0.0, view_size.y * 0.12),
		I18nService.t("mg.starHopper.shower"),
		HORIZONTAL_ALIGNMENT_CENTER,
		view_size.x,
		26,
		Color(1.0, 0.5, 0.45, 0.6 + pulse)
	)


func _draw_meteor(meteor: Dictionary) -> void:
	var pos := _to_screen(int(meteor["lane"]), float(meteor["m"]))
	if pos.y < -60.0 or pos.y > view_size.y + 60.0:
		return
	var r := maxf(22.0, view_size.x / float(tune["LANES"]) * 0.3)
	draw_circle(pos, r * 1.4, Color(1.0, 0.5, 0.28, 0.1))
	draw_circle(pos, r * 1.16, Color(1.0, 0.55, 0.3, 0.16))
	var pts := PackedVector2Array()
	for i in 9:
		var a := TAU * i / 9.0 + float(meteor["spin"]) + elapsed * 1.4
		pts.append(pos + Vector2(cos(a), sin(a)) * r * (0.82 + 0.18 * sin(a * 3.0)))
	draw_colored_polygon(pts, METEOR_COLOR)
	draw_circle(pos + Vector2(-r * 0.3, -r * 0.25), r * 0.24, METEOR_COLOR.darkened(0.25))
	draw_polyline(pts + PackedVector2Array([pts[0]]), Color(0.4, 0.28, 0.24), 2.0)


func _draw_pickup(p: Dictionary) -> void:
	var pos := _to_screen(int(p["lane"]), float(p["m"]))
	if pos.y < -40.0 or pos.y > view_size.y + 40.0:
		return
	var kind := str(p["kind"])
	if kind == "shield":
		draw_circle(pos, 18.0, Color(0.4, 0.8, 1.0, 0.35))
		draw_arc(pos, 15.0, 0.0, TAU, 20, Color(0.6, 0.9, 1.0), 3.0)
		return
	var color := GOLD_COLOR if kind == "gold" else STAR_COLOR
	var r := 16.0 if kind == "gold" else 12.0
	draw_circle(pos, r * 1.7, Color(color, 0.22))
	if kind == "gold":
		# Goldene Karotte.
		draw_colored_polygon(
			PackedVector2Array(
				[
					pos + Vector2(0.0, r),
					pos + Vector2(-r * 0.6, -r * 0.6),
					pos + Vector2(r * 0.6, -r * 0.6)
				]
			),
			color
		)
		draw_circle(pos + Vector2(0.0, -r * 0.8), r * 0.32, Color(0.45, 0.8, 0.4))
		return
	var pts := PackedVector2Array()
	for i in 10:
		var a := -PI * 0.5 + TAU * i / 10.0
		pts.append(pos + Vector2(cos(a), sin(a)) * (r if i % 2 == 0 else r * 0.45))
	draw_colored_polygon(pts, color)


func _draw_ship() -> void:
	var pos := _to_screen_f(lane_visual, traveled)
	# Mit der Bahnbreite skalieren, damit das Schiff auf dem Handy nicht
	# zwischen den Meteoren untergeht.
	var s := maxf(24.0, view_size.x / float(tune["LANES"]) * 0.34) * float(tune["GOOBY_SCALE"])
	if _pop > 0.0:
		s *= (
			1.0
			+ (
				(float(Logic.HOPPER_JUICE["POP_SCALE"]) - 1.0)
				* (_pop / float(Logic.HOPPER_JUICE["POP_SEC"]))
			)
		)
	var tilt := (float(lane) - lane_visual) * 0.5
	if _roll > 0.0:
		tilt += TAU * (1.0 - _roll / float(Logic.HOPPER_JUICE["BARREL_ROLL_SEC"]))
	# Triebwerksflamme.
	var flame := 1.0 + 0.25 * sin(elapsed * 30.0)
	draw_colored_polygon(
		PackedVector2Array(
			[
				pos + Vector2(-s * 0.4, s * 0.7),
				pos + Vector2(s * 0.4, s * 0.7),
				pos + Vector2(0.0, s * (1.5 + flame * 0.5)),
			]
		),
		Color(1.0, 0.62, 0.25, 0.85)
	)
	var hull := PackedVector2Array(
		[
			pos + Vector2(0.0, -s * 1.25).rotated(tilt),
			pos + Vector2(s * 0.9, s * 0.75).rotated(tilt),
			pos + Vector2(0.0, s * 0.35).rotated(tilt),
			pos + Vector2(-s * 0.9, s * 0.75).rotated(tilt),
		]
	)
	draw_colored_polygon(hull, Color(0.86, 0.9, 0.98))
	draw_polyline(hull + PackedVector2Array([hull[0]]), Color(0.5, 0.55, 0.75), 2.0)
	# Gooby im Cockpit.
	draw_circle(pos + Vector2(0.0, -s * 0.2), s * 0.42, Color(0.55, 0.8, 0.95, 0.85))
	draw_circle(pos + Vector2(0.0, -s * 0.2), s * 0.32, Color(0.99, 0.9, 0.65))
	draw_circle(pos + Vector2(-s * 0.12, -s * 0.24), s * 0.06, Color(0.2, 0.16, 0.14))
	draw_circle(pos + Vector2(s * 0.12, -s * 0.24), s * 0.06, Color(0.2, 0.16, 0.14))
	if shielded or invuln > 0.0:
		var alpha := 0.7 if shielded else clampf(invuln, 0.0, 1.0) * 0.5
		draw_arc(pos, s * 1.9, 0.0, TAU, 30, Color(0.5, 0.85, 1.0, alpha), 3.0)


func _draw_flash() -> void:
	if _flash <= 0.0 or _flash_text.is_empty():
		return
	var alpha := clampf(_flash, 0.0, 1.0)
	draw_string(
		ThemeService.font(800),
		Vector2(0.0, view_size.y * 0.32),
		_flash_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		view_size.x,
		30,
		Color(1.0, 0.85, 0.45, alpha)
	)
