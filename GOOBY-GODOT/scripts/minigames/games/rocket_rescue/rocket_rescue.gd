extends MinigameBase
## Raketen-Rettung (rocketRescue) — Spiel-Szene. Die gesamte Flugmechanik
## läuft in RocketRescueEngine (zahlengleich zum Web): Mondgravitation 2.4,
## Schub 5.6 entlang der Schiffsachse, Neigung über die Bildschirmdrittel,
## Tank 100 / 8 pro Sekunde, 5 Plattformen mit je einem Hasen, Landung ≤ 1.2 m/s
## nimmt den Hasen auf, Abliefern auf der Station zählt, harte Landung prallt ab
## und kostet 10 Sprit (NIE Tod), leerer Tank schleppt zurück und beendet.
##
## 2D-STATT-3D (begründet): der Lander lebt von exakt lesbarer Höhe und
## Sinkrate. Eine flache Seitenansicht zeigt Geschwindigkeitsvektor, Plattform-
## kante und Abstand ohne Tiefenmehrdeutigkeit — im Web war die 3D-Kamera
## genau hier das Problem. Hochkant folgt die Kamera dem Schiff (die Welt ist
## 16 m breit), quer passt das ganze Feld ins Bild.

const Logic := preload("res://scripts/minigames/games/rocket_rescue/rocket_rescue_logic.gd")
const Lander := preload("res://scripts/minigames/games/rocket_rescue/rocket_rescue_engine.gd")

## Anteil der Viewport-Höhe zwischen Boden und Decke der Spielwelt.
const WORLD_H_FRAC := 0.8
## Bildschirmhöhe des Bodens (Anteil von oben).
const GROUND_FRAC := 0.88

const SKY_TOP := Color(0.06, 0.05, 0.16)
const SKY_BOTTOM := Color(0.24, 0.15, 0.34)
const GROUND_COLOR := Color(0.34, 0.29, 0.42)
const PAD_COLOR := Color(0.95, 0.78, 0.35)
const PLATFORM_COLOR := Color(0.7, 0.74, 0.86)
const HULL_COLOR := Color(0.95, 0.96, 0.99)
const FUEL_COLOR := Color(0.45, 0.86, 0.6)
const BUNNY_COLOR := Color(0.99, 0.92, 0.86)

var tune: Dictionary = {}
var engine: RocketRescueEngine
var score := 0
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

var _world_scale := 24.0
var _cam_x := 0.0
var _thrust := false
var _tilt_dir := 0
var _touch_nx := 0.0
var _touching := false
var _stars: Array[Vector3] = []
var _squash := 0.0
var _beacon := 0.0
var _flash := 0.0
var _flash_text := ""
var _low_pulse := 0.0
var _fuel_label: Label
var _rescue_label: Label
var _hint_label: Label


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = Logic.apply_difficulty(Logic.ROCKET, ctx.difficulty)
	var rng := ctx.rng()
	engine = Lander.new(func() -> float: return rng.next(), tune)
	for i in 70:
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
	_world_scale = (view_size.y * WORLD_H_FRAC) / (float(tune["CEILING_Y"]) + 1.4)
	if _fuel_label != null:
		_fuel_label.position = Vector2(16.0, 10.0)
		_rescue_label.position = Vector2(16.0, 48.0)
		_hint_label.position = Vector2(view_size.x * 0.5 - 160.0, view_size.y - 46.0)
		_hint_label.size = Vector2(320.0, 40.0)
	queue_redraw()


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	_squash = maxf(0.0, _squash - delta)
	_beacon = maxf(0.0, _beacon - delta)
	_flash = maxf(0.0, _flash - delta)
	_low_pulse += delta
	for event in engine.step({"thrust": _thrust, "tiltDir": _tilt_dir}, delta):
		_handle_event(event)
	score = engine.score()
	ctx.report_score(score, 0)
	_track_camera()
	_update_labels()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished:
		return
	if event is InputEventScreenTouch:
		_touching = event.pressed
		if event.pressed:
			_touch_nx = _normalized_x(event.position.x)
		_apply_input()
	elif event is InputEventScreenDrag and _touching:
		_touch_nx = _normalized_x(event.position.x)
		_apply_input()


## Restsprit in Prozent (HUD + Warnpuls).
func fuel_pct() -> float:
	return float(engine.state["fuel"]) / float(tune["FUEL_MAX"])


## Weltkoordinate (m) → Bildschirmpixel.
func to_screen(wx: float, wy: float) -> Vector2:
	return Vector2(
		view_size.x * 0.5 + (wx - _cam_x) * _world_scale,
		view_size.y * GROUND_FRAC - wy * _world_scale
	)


func _normalized_x(px: float) -> float:
	return clampf(px / maxf(1.0, view_size.x) * 2.0 - 1.0, -1.0, 1.0)


func _apply_input() -> void:
	_thrust = _touching
	_tilt_dir = Logic.tilt_command_for(_touch_nx, _touching)


func _build_hud() -> void:
	_fuel_label = Label.new()
	_fuel_label.theme_type_variation = &"HeadlineLabel"
	add_child(_fuel_label)
	_rescue_label = Label.new()
	_rescue_label.theme_type_variation = &"CaptionLabel"
	add_child(_rescue_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.rocketRescue.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint_label)
	# Nachthimmel — die Theme-Schriftfarben sind für Helles gedacht.
	_fuel_label.add_theme_color_override("font_color", Color(1.0, 0.97, 0.92))
	_rescue_label.add_theme_color_override("font_color", Color(0.72, 0.95, 0.85))
	_hint_label.add_theme_color_override("font_color", Color(0.82, 0.84, 0.98))
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


## Hochkant folgt die Kamera dem Schiff, quer bleibt das Feld zentriert.
func _track_camera() -> void:
	var half_w := float(tune["WORLD_HALF_W"])
	var visible_half := view_size.x * 0.5 / _world_scale
	if visible_half >= half_w:
		_cam_x = 0.0
		return
	var limit := half_w - visible_half
	_cam_x = clampf(float(engine.state["x"]), -limit, limit)


func _handle_event(event: Dictionary) -> void:
	match str(event["type"]):
		"landing":
			_on_landing(event)
		"hardLanding":
			_on_hard_landing()
		"bunnyPickup":
			_banner("mg.rocketRescue.aboard", Color(0.99, 0.85, 0.6))
			AudioDirector.try_play(self, "mg_good", 1.15)
		"rescue":
			_on_rescue()
		"fuelPickup":
			_beacon = 0.0
			AudioDirector.try_play(self, "mg_combo", 1.1)
			if ctx.juice != null:
				ctx.juice.float_text(_craft_pos(), "+Sprit", FUEL_COLOR)
		"fuelLow":
			_banner("mg.rocketRescue.low_fuel", Color(1.0, 0.6, 0.4))
			AudioDirector.try_play(self, "mg_junk", 0.9)
		"outOfFuel":
			_banner("mg.rocketRescue.towed", Color(0.8, 0.8, 0.95))
			AudioDirector.try_play(self, "mg_lose")
		"windTelegraph":
			AudioDirector.try_play(self, "mg_junk", 0.6)
		"ended":
			_finish(str(event["reason"]))


func _on_landing(event: Dictionary) -> void:
	_squash = float(Logic.ROCKET_JUICE["TOUCH_SQUASH_SEC"])
	if str(event["kind"]) != "soft":
		AudioDirector.try_play(self, "mg_good", 0.95)
		return
	AudioDirector.try_play(self, "mg_perfect")
	if not bool(event["bonusEligible"]):
		return
	if ctx.juice != null:
		ctx.juice.float_text(
			_craft_pos(), "+%d" % int(tune["SOFT_LANDING_BONUS"]), Color(0.6, 0.95, 0.8)
		)


func _on_hard_landing() -> void:
	_squash = float(Logic.ROCKET_JUICE["TOUCH_SQUASH_SEC"])
	_banner("mg.rocketRescue.hard", Color(1.0, 0.55, 0.45))
	AudioDirector.try_play(self, "mg_spill")
	if ctx.juice != null:
		ctx.juice.shake(0.55)
		ctx.juice.hit_freeze(70)
		ctx.juice.float_text(
			_craft_pos(), "−%d" % int(tune["HARD_FUEL_PENALTY"]), Color(1.0, 0.6, 0.5)
		)


func _on_rescue() -> void:
	_beacon = float(Logic.ROCKET_JUICE["BEACON_POP_SEC"])
	_banner("mg.rocketRescue.saved", Color(0.99, 0.8, 0.45))
	AudioDirector.try_play(self, "mg_golden")
	if ctx.juice != null:
		ctx.juice.bloom_pulse(1.0)
		ctx.juice.hit_freeze(60)
		ctx.juice.float_text(_pad_pos(), "+%d" % int(tune["RESCUE_POINTS"]), Color(1.0, 0.86, 0.5))


func _banner(key: String, color: Color) -> void:
	_flash_text = I18nService.t(key)
	_flash = 1.3
	if ctx.juice != null:
		ctx.juice.float_text(_craft_pos() + Vector2(0.0, -40.0), _flash_text, color)


func _finish(reason: String) -> void:
	if finished:
		return
	finished = true
	running = false
	if reason == "complete":
		AudioDirector.try_play(self, "mg_win")
	(
		ctx
		. report_end(
			{
				"score": engine.score(),
				"rescues": int(engine.state["rescued"]),
				"reason": reason,
			}
		)
	)


func _update_labels() -> void:
	_fuel_label.text = I18nService.t(
		"mg.rocketRescue.fuel", {"n": int(round(float(engine.state["fuel"])))}
	)
	_rescue_label.text = I18nService.t(
		"mg.rocketRescue.rescued",
		{"n": int(engine.state["rescued"]), "max": int(tune["PLATFORM_COUNT"])}
	)


func _craft_pos() -> Vector2:
	return to_screen(float(engine.state["x"]), float(engine.state["y"]))


func _pad_pos() -> Vector2:
	var pad: Dictionary = engine.layout["pad"]
	return to_screen(float(pad["x"]), float(pad["y"]))


func _draw() -> void:
	_draw_sky()
	_draw_ground()
	_draw_pad()
	for p: Dictionary in engine.layout["platforms"]:
		_draw_platform(p)
	for f: Dictionary in engine.layout["fuelPickups"]:
		if not bool(f["taken"]):
			_draw_canister(f)
	_draw_wind()
	_draw_craft()
	_draw_fuel_bar()
	_draw_flash()


func _draw_sky() -> void:
	for i in 14:
		var f := float(i) / 13.0
		draw_rect(
			Rect2(0.0, view_size.y * f, view_size.x, view_size.y / 13.0 + 1.0),
			SKY_TOP.lerp(SKY_BOTTOM, f)
		)
	for s in _stars:
		var pos := Vector2(s.x * view_size.x, s.y * view_size.y * GROUND_FRAC)
		draw_circle(pos, 0.8 + s.z * 1.6, Color(1.0, 0.98, 0.92, 0.3 + s.z * 0.5))
	# Ferner Planet als GOOBY-Sticker-Akzent.
	var moon := Vector2(view_size.x * 0.78, view_size.y * 0.12)
	draw_circle(moon, view_size.y * 0.05, Color(0.99, 0.86, 0.62, 0.85))
	draw_circle(moon + Vector2(-6.0, 4.0), view_size.y * 0.014, Color(0.9, 0.74, 0.52, 0.7))


func _draw_ground() -> void:
	var ground_y := view_size.y * GROUND_FRAC
	draw_rect(Rect2(0.0, ground_y, view_size.x, view_size.y - ground_y), GROUND_COLOR)
	draw_line(
		Vector2(0.0, ground_y), Vector2(view_size.x, ground_y), GROUND_COLOR.lightened(0.25), 3.0
	)


func _draw_pad() -> void:
	var pad: Dictionary = engine.layout["pad"]
	var half := float(pad["halfW"]) * _world_scale
	var pos := _pad_pos()
	var pop := 1.0
	if _beacon > 0.0:
		var f := _beacon / float(Logic.ROCKET_JUICE["BEACON_POP_SEC"])
		pop = 1.0 + (float(Logic.ROCKET_JUICE["BEACON_POP_SCALE"]) - 1.0) * f
	draw_rect(Rect2(pos.x - half, pos.y - 8.0, half * 2.0, 12.0), PAD_COLOR)
	draw_rect(
		Rect2(pos.x - half, pos.y - 8.0, half * 2.0, 12.0), PAD_COLOR.darkened(0.35), false, 2.0
	)
	for side in [-1.0, 1.0]:
		var beacon := pos + Vector2(side * half, -14.0)
		draw_circle(beacon, 5.0 * pop, Color(1.0, 0.9, 0.5, 0.85))
		draw_circle(beacon, 11.0 * pop, Color(1.0, 0.85, 0.4, 0.18))
	if bool(engine.state["carrying"]):
		draw_arc(
			pos + Vector2(0.0, -10.0), half * 0.9, PI, TAU, 20, Color(1.0, 0.9, 0.55, 0.55), 2.0
		)


func _draw_platform(p: Dictionary) -> void:
	var pos := to_screen(float(p["x"]), float(p["y"]))
	var half := float(p["halfW"]) * _world_scale
	draw_rect(Rect2(pos.x - half, pos.y - 7.0, half * 2.0, 11.0), PLATFORM_COLOR)
	draw_rect(
		Rect2(pos.x - half, pos.y - 7.0, half * 2.0, 11.0), PLATFORM_COLOR.darkened(0.4), false, 2.0
	)
	# Ständer zur Bodenlinie hin (Sticker-Look statt echter Perspektive).
	draw_line(pos + Vector2(0.0, 4.0), pos + Vector2(0.0, 16.0), PLATFORM_COLOR.darkened(0.45), 3.0)
	if bool(p["bunny"]):
		_draw_bunny(pos + Vector2(0.0, -18.0), 13.0)


func _draw_bunny(pos: Vector2, r: float) -> void:
	draw_circle(pos + Vector2(0.0, r * 0.55), r * 0.85, BUNNY_COLOR)
	draw_circle(pos, r * 0.62, BUNNY_COLOR)
	for side in [-1.0, 1.0]:
		draw_circle(pos + Vector2(side * r * 0.3, -r * 0.75), r * 0.22, BUNNY_COLOR)
		draw_circle(pos + Vector2(side * r * 0.22, -r * 0.05), r * 0.09, Color(0.22, 0.18, 0.16))
	draw_circle(pos + Vector2(0.0, r * 0.18), r * 0.08, Color(0.95, 0.6, 0.66))


func _draw_canister(f: Dictionary) -> void:
	var pos := to_screen(float(f["x"]), float(f["y"]))
	var bob := sin(_low_pulse * 2.4 + pos.x * 0.05) * 3.0
	pos.y += bob
	draw_circle(pos, 16.0, Color(FUEL_COLOR, 0.16))
	draw_rect(Rect2(pos.x - 7.0, pos.y - 10.0, 14.0, 20.0), FUEL_COLOR)
	draw_rect(Rect2(pos.x - 7.0, pos.y - 10.0, 14.0, 20.0), FUEL_COLOR.darkened(0.4), false, 2.0)
	draw_rect(Rect2(pos.x - 3.0, pos.y - 14.0, 6.0, 5.0), FUEL_COLOR.darkened(0.3))


func _draw_wind() -> void:
	var wind: Dictionary = engine.state["wind"]
	var phase := str(wind["phase"])
	if phase == "idle":
		return
	var dir := float(wind["dir"])
	var strong := phase == "gust"
	var alpha := 0.5 if strong else (0.22 + 0.18 * sin(_low_pulse * 22.0))
	var streak := 54.0 if strong else 30.0
	for i in 9:
		var y := view_size.y * (0.08 + 0.075 * i)
		var t := fposmod(_low_pulse * (2.4 if strong else 0.9) + i * 0.37, 1.0)
		var x := lerpf(-60.0, view_size.x + 60.0, t if dir > 0.0 else 1.0 - t)
		draw_line(Vector2(x, y), Vector2(x + dir * streak, y), Color(0.7, 0.85, 1.0, alpha), 2.5)


func _draw_craft() -> void:
	var pos := _craft_pos()
	var s := _world_scale * 0.42
	var squash := 1.0
	if _squash > 0.0:
		var f := _squash / float(Logic.ROCKET_JUICE["TOUCH_SQUASH_SEC"])
		squash = lerpf(1.0, float(Logic.ROCKET_JUICE["TOUCH_SQUASH"]), f)
	var tilt := float(engine.state["tilt"])
	if _thrust and float(engine.state["fuel"]) > 0.0:
		_draw_flame(pos, s, tilt)
	var hull := PackedVector2Array(
		[
			pos + Vector2(0.0, -s * 1.5 * squash).rotated(tilt),
			pos + Vector2(s * 0.78, -s * 0.1).rotated(tilt),
			pos + Vector2(s * 0.6, s * 0.72 * squash).rotated(tilt),
			pos + Vector2(-s * 0.6, s * 0.72 * squash).rotated(tilt),
			pos + Vector2(-s * 0.78, -s * 0.1).rotated(tilt),
		]
	)
	draw_colored_polygon(hull, HULL_COLOR)
	draw_polyline(hull + PackedVector2Array([hull[0]]), Color(0.42, 0.46, 0.62), 2.0)
	# Landebeine.
	for side in [-1.0, 1.0]:
		draw_line(
			pos + Vector2(side * s * 0.5, s * 0.6).rotated(tilt),
			pos + Vector2(side * s * 0.95, s * 1.05).rotated(tilt),
			Color(0.42, 0.46, 0.62),
			3.0
		)
	# Gooby im Fenster; ein geretteter Hase sitzt daneben.
	var window := pos + Vector2(0.0, -s * 0.35).rotated(tilt)
	draw_circle(window, s * 0.4, Color(0.55, 0.82, 0.96))
	draw_circle(window, s * 0.3, Color(0.99, 0.9, 0.66))
	draw_circle(window + Vector2(-s * 0.1, -s * 0.03), s * 0.05, Color(0.2, 0.16, 0.14))
	draw_circle(window + Vector2(s * 0.1, -s * 0.03), s * 0.05, Color(0.2, 0.16, 0.14))
	if bool(engine.state["carrying"]):
		_draw_bunny(pos + Vector2(s * 0.95, -s * 0.9), s * 0.42)


func _draw_flame(pos: Vector2, s: float, tilt: float) -> void:
	var flick := 1.0 + 0.3 * sin(_low_pulse * 34.0)
	var tip := pos + Vector2(0.0, s * (1.6 + flick * 0.6)).rotated(tilt)
	draw_colored_polygon(
		PackedVector2Array(
			[
				pos + Vector2(-s * 0.42, s * 0.7).rotated(tilt),
				pos + Vector2(s * 0.42, s * 0.7).rotated(tilt),
				tip,
			]
		),
		Color(1.0, 0.62, 0.24, 0.9)
	)
	draw_colored_polygon(
		PackedVector2Array(
			[
				pos + Vector2(-s * 0.2, s * 0.7).rotated(tilt),
				pos + Vector2(s * 0.2, s * 0.7).rotated(tilt),
				pos + Vector2(0.0, s * (1.1 + flick * 0.4)).rotated(tilt),
			]
		),
		Color(1.0, 0.93, 0.7, 0.95)
	)


func _draw_fuel_bar() -> void:
	var w := minf(view_size.x - 32.0, 320.0)
	var x := view_size.x * 0.5 - w * 0.5
	var y := view_size.y * 0.055
	var pct := clampf(fuel_pct(), 0.0, 1.0)
	var color := FUEL_COLOR
	if pct <= 0.2:
		color = Color(1.0, 0.5, 0.4).lerp(Color(1.0, 0.85, 0.5), 0.5 + 0.5 * sin(_low_pulse * 9.0))
	draw_rect(Rect2(x, y, w, 14.0), Color(0.16, 0.14, 0.24, 0.85))
	draw_rect(Rect2(x + 2.0, y + 2.0, (w - 4.0) * pct, 10.0), color)
	draw_rect(Rect2(x, y, w, 14.0), Color(1.0, 1.0, 1.0, 0.25), false, 2.0)


func _draw_flash() -> void:
	if _flash <= 0.0 or _flash_text.is_empty():
		return
	draw_string(
		ThemeService.font(800),
		Vector2(0.0, view_size.y * 0.3),
		_flash_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		view_size.x,
		28,
		Color(1.0, 0.88, 0.55, clampf(_flash, 0.0, 1.0))
	)
