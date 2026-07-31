extends MinigameBase
## Raketen-Rettung (rocketRescue) — Spiel-Szene. Die gesamte Flugmechanik
## läuft in RocketRescueEngine (zahlengleich zum Web): Mondgravitation 2.4,
## Schub 5.6 entlang der Schiffsachse, Neigung über die Bildschirmdrittel,
## Tank 100 / 8 pro Sekunde, 5 Plattformen mit je einem Hasen, Landung ≤ 1.2 m/s
## nimmt den Hasen auf, Abliefern auf der Station zählt, harte Landung prallt ab
## und kostet 10 Sprit (NIE Tod), leerer Tank schleppt zurück und beendet.
##
## ECHTE 3D-MONDBÜHNE (RocketRescueStage): Gooby sitzt als Pilot auf dem Lander
## über einer Kraterebene mit Felsen, schwebenden Rettungsplattformen und
## Sternenhimmel. Die 3D-Kamera schaut GERADE auf die Spielebene und ist
## pixelgenau auf `to_screen()` gerahmt — Höhe und Sinkrate bleiben also exakt
## so lesbar wie in der flachen Ansicht (das war im Web das 3D-Problem).
## Hochkant folgt die Kamera dem Schiff (die Welt ist 16 m breit), quer passt
## das ganze Feld ins Bild.
##
## W15/GAMESQA2-Steuergefühl (Audit: "Schub-Steuerung schwammig, Rettungs-
## Feedback dünn"): die unsichtbaren Bildschirmdrittel sind jetzt als
## Zonen-Leiste ◀ ▲ ▶ am unteren Rand SICHTBAR, die aktive Zone leuchtet
## unter dem Finger auf (die zertifizierte Drittel-Zuordnung in
## Logic.tilt_command_for bleibt zahlengleich). Hochkant folgt die Kamera
## GEGLÄTTET mit Blickvorsprung in Flugrichtung (cam_target, pure) statt
## hart zu klemmen, und die Rettung feiert mit einem großen Herz-Funken-
## Burst der Bühne. Engine/Sim unverändert (zertifiziert).

const Logic := preload("res://scripts/minigames/games/rocket_rescue/rocket_rescue_logic.gd")
const Lander := preload("res://scripts/minigames/games/rocket_rescue/rocket_rescue_engine.gd")
const Stage := preload("res://scripts/minigames/games/rocket_rescue/rocket_rescue_stage.gd")

## Anteil der Viewport-Höhe zwischen Boden und Decke der Spielwelt.
const WORLD_H_FRAC := 0.8
## Bildschirmhöhe des Bodens (Anteil von oben).
const GROUND_FRAC := 0.88

const FUEL_COLOR := Color(0.45, 0.86, 0.6)

## W15: Kameraglättung (1/s) + Blickvorsprung (s Flugzeit) fürs Hochkant-Follow.
const CAM_SMOOTH := 6.0
const CAM_LOOKAHEAD_S := 0.4

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
var _stage: Node3D
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
	_build_stage()
	_build_hud()
	_fit_viewport()
	if is_inside_tree():
		get_viewport().size_changed.connect(_fit_viewport)


func end() -> void:
	super.end()
	finished = true


## 3D-Bühne unter die Node2D-Wurzel hängen (Godot rendert 3D hinter 2D).
func _build_stage() -> void:
	_stage = Stage.new()
	_stage.name = "Stage3D"
	add_child(_stage)
	_stage.setup_stage(tune, engine.layout)
	if ctx.juice != null:
		ctx.juice.world_environment = _stage.world_env


## Pflicht-Layouthook: beide Orientierungen laufen über DIESE Funktion.
func apply_view(size: Vector2) -> void:
	if size.x > 1.0 and size.y > 1.0:
		view_size = size
	landscape = view_size.x > view_size.y
	position = Vector2.ZERO
	_world_scale = (view_size.y * WORLD_H_FRAC) / (float(tune["CEILING_Y"]) + 1.4)
	if _stage != null:
		_stage.apply_size(view_size)
	if _fuel_label != null:
		_fuel_label.position = Vector2(16.0, 10.0)
		_rescue_label.position = Vector2(16.0, 48.0)
		# W15: der Hinweis rückt ÜBER die neue Zonen-Leiste am unteren Rand.
		_hint_label.position = Vector2(view_size.x * 0.5 - 160.0, view_size.y - 112.0)
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
	_track_camera(delta)
	_sync_stage()
	_update_labels()
	queue_redraw()


## Die 3D-Bühne bekommt EINEN Zustandsschnappschuss — sie rechnet nur Optik.
func _sync_stage() -> void:
	_stage.tick(get_process_delta_time())
	_stage.track(_cam_x)
	var snapshot := engine.state.duplicate()
	snapshot["thrust"] = _thrust
	snapshot["squash01"] = _squash / float(Logic.ROCKET_JUICE["TOUCH_SQUASH_SEC"])
	_stage.sync(snapshot, engine.layout, _low_pulse)
	_stage.feel(_mood())


## Gooby-Laune aus dem Flugzustand (Reihenfolge = Dringlichkeit).
func _mood() -> String:
	if bool(engine.state["towing"]):
		return "sad"
	if str(engine.state["wind"]["phase"]) == "gust":
		return "scared"
	if _squash > 0.0:
		return "dizzy"
	if bool(engine.state["carrying"]):
		return "ecstatic"
	if fuel_pct() <= 0.2:
		return "scared"
	return "happy"


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


## Hochkant folgt die Kamera dem Schiff — W15: GEGLÄTTET plus Blickvorsprung
## in Flugrichtung, statt hart am Schiff zu kleben (Framing-Audit).
func _track_camera(delta: float) -> void:
	var half_w := float(tune["WORLD_HALF_W"])
	var visible_half := view_size.x * 0.5 / _world_scale
	if visible_half >= half_w:
		_cam_x = 0.0
		return
	var want := cam_target(
		float(engine.state["x"]), float(engine.state["vx"]), half_w - visible_half
	)
	_cam_x += (want - _cam_x) * minf(1.0, CAM_SMOOTH * delta)


## PURE Kamera-Zielposition (W15, testbar): Schiff + Blickvorsprung in
## Flugrichtung, geklemmt auf die sichtbaren Weltränder.
static func cam_target(x: float, vx: float, limit: float) -> float:
	return clampf(x + vx * CAM_LOOKAHEAD_S, -limit, limit)


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
			_stage.spark_at(
				float(engine.state["x"]), float(engine.state["y"]), Color(0.45, 0.95, 0.65)
			)
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
	_stage.spark_at(float(engine.state["x"]), float(engine.state["y"]), Color(1.0, 0.55, 0.35))
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
	var pad: Dictionary = engine.layout["pad"]
	_stage.spark_at(float(pad["x"]), float(pad["y"]) + 0.6, Color(1.0, 0.86, 0.45))
	# W15: DIE Belohnung des Spiels bekommt die große Sterne-Fontäne.
	_stage.rescue_burst_at(float(pad["x"]), float(pad["y"]) + 0.8)
	_stage.pulse_glow(0.9)
	_stage.cheer("celebrate")
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


## Die WELT lebt in der 3D-Bühne — 2D bleibt nur, was Schrift und Balken ist.
func _draw() -> void:
	_draw_fuel_bar()
	_draw_zone_guide()
	_draw_flash()


## W15: die drei unsichtbaren Touch-Drittel als lesbare Zonen-Leiste
## ◀ ▲ ▶ — die Zone unter dem Finger leuchtet auf, solange er das Glas
## berührt (Halten = Schub, Seite = Neigung; Mapping bleibt zahlengleich).
func _draw_zone_guide() -> void:
	var y := view_size.y - 74.0
	var h := 58.0
	var third := view_size.x / 3.0
	var font := ThemeService.font(800)
	var labels := ["◀", "▲", "▶"]
	for i in 3:
		var zone := i - 1
		var active := _touching and _tilt_dir == zone
		var rect := Rect2(third * i + 6.0, y, third - 12.0, h)
		var bg := Color(0.5, 0.6, 1.0, 0.3) if active else Color(0.2, 0.2, 0.4, 0.16)
		draw_rect(rect, bg)
		draw_rect(rect, Color(0.8, 0.85, 1.0, 0.5 if active else 0.2), false, 2.0)
		var col := Color(1.0, 0.95, 0.75, 0.95) if active else Color(0.8, 0.84, 1.0, 0.5)
		draw_string(
			font,
			Vector2(rect.position.x, y + h * 0.68),
			labels[i],
			HORIZONTAL_ALIGNMENT_CENTER,
			rect.size.x,
			24,
			col
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
