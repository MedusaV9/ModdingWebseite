extends MinigameBase
## Minigolf (miniGolf) — Spiel-Szene. Alle MECHANIK-Zahlen kommen aus
## MiniGolfLogic/MiniGolfCourse (zahlengleich zum Web): 6 gesetzte Löcher,
## Zugkraft = Ziehlänge (gedeckelt), Reibung 0.985/Frame, Banden, Windmühlentor,
## Kuppel, Rampe, 10-Schlag-Abbruch, Wertung 30/20/12/6.
##
## 2D-STATT-3D (begründet): die Bahn IST ein Zellraster, und die Physik läuft
## ohnehin in der x/z-Ebene — eine Draufsicht bildet sie verlustfrei ab, macht
## Zieh-Zielen auf dem Handy präzise (Ball, Zielhilfe und Loch liegen in einer
## Ebene) und braucht keine Kachel-GLBs. Höhe (Rampe) wird als Farbverlauf
## plus Höhenlinie gezeigt.

const Logic := preload("res://scripts/minigames/games/mini_golf/mini_golf_logic.gd")
const Course := preload("res://scripts/minigames/games/mini_golf/mini_golf_course.gd")

## Ruhepause nach einem eingelochten/abgebrochenen Loch (s).
const HOLE_PAUSE_SEC := 1.1
## Punkte der gepunkteten Zielvorschau.
const PREVIEW_DOTS := 14

const FELT := Color(0.42, 0.74, 0.44)
const FELT_DARK := Color(0.34, 0.64, 0.38)
const RAIL_COLOR := Color(0.85, 0.72, 0.55)
const CUP_COLOR := Color(0.16, 0.14, 0.13)
const BALL_COLOR := Color(1.0, 0.99, 0.96)
const FLAG_COLOR := Color(0.95, 0.35, 0.45)

var tune: Dictionary = {}
var course: Array[Dictionary] = []
var hole_index := 0
var strokes := 0
var score := 0
var theta := 0.0
var ball := {"x": 0.0, "z": 0.0, "vx": 0.0, "vz": 0.0, "done": false}
var endless_state: Dictionary = {}
var phase := "aim"
var pause_left := 0.0
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

var _rng: GoobyRng
var _dragging := false
var _drag_from := Vector2.ZERO
var _drag_to := Vector2.ZERO
var _origin := Vector2.ZERO
var _ppm := 60.0
var _sparkles: Array[Dictionary] = []
var _ring := 0.0
var _ring_scale := 1.0
var _flash := 0.0
var _flash_text := ""
var _hole_label: Label
var _stroke_label: Label
var _hint_label: Label


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = Logic.apply_difficulty(Logic.GOLF, ctx.difficulty)
	_rng = ctx.rng()
	course = Course.generate_course(func() -> float: return _rng.next(), tune)
	endless_state = Logic.create_endless_state()
	_reset_ball()
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
	_fit_course()
	if _hole_label != null:
		_hole_label.position = Vector2(16.0, 10.0)
		_stroke_label.position = Vector2(16.0, 48.0)
		_hint_label.position = Vector2(view_size.x * 0.5 - 150.0, view_size.y - 52.0)
		_hint_label.size = Vector2(300.0, 40.0)
	queue_redraw()


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	_flash = maxf(0.0, _flash - delta)
	_ring = maxf(0.0, _ring - delta)
	_step_sparkles(delta)
	if phase == "pause":
		pause_left -= delta
		if pause_left <= 0.0:
			_next_hole()
		queue_redraw()
		return
	if phase == "roll":
		_step_roll(delta)
	theta += PI * 2.0 * float(Logic.GOLF["WINDMILL_RPS"]) * delta
	_update_labels()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished or phase != "aim":
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_dragging = true
			_drag_from = event.position
			_drag_to = event.position
		elif _dragging:
			_dragging = false
			_putt()
	elif event is InputEventScreenDrag and _dragging:
		_drag_to = event.position
		queue_redraw()


## Das gerade gespielte Loch.
func current_hole() -> Dictionary:
	return course[hole_index % course.size()]


## Par des aktuellen Lochs (Leicht spendiert bereits in der Bahn +1).
func current_par() -> int:
	return int(current_hole()["par"])


func _build_hud() -> void:
	_hole_label = Label.new()
	_hole_label.theme_type_variation = &"HeadlineLabel"
	add_child(_hole_label)
	_stroke_label = Label.new()
	_stroke_label.theme_type_variation = &"CaptionLabel"
	add_child(_stroke_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.miniGolf.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# SoftLabel ist dunkelgrau — auf dem dunklen Rough unlesbar.
	_hint_label.add_theme_color_override("font_color", Color(0.94, 0.98, 0.92, 0.9))
	add_child(_hint_label)
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


## Bahn in den Viewport einpassen (Draufsicht, z zeigt nach oben).
func _fit_course() -> void:
	if course.is_empty():
		return
	var min_x := 0.0
	var max_x := 0.0
	var max_z := 0.0
	for cell: Array in current_hole()["cells"]:
		min_x = minf(min_x, float(cell[0]) - 0.5)
		max_x = maxf(max_x, float(cell[0]) + 0.5)
		max_z = maxf(max_z, float(cell[1]) + 0.5)
	var span_x := maxf(1.0, max_x - min_x) + 0.6
	var span_z := max_z + 1.1
	var top := view_size.y * 0.11
	var bottom := view_size.y - 88.0
	_ppm = minf((view_size.x - 40.0) / span_x, (bottom - top) / span_z)
	var center_x := (min_x + max_x) * 0.5
	# Breite Bahnen füllen die Höhe nicht aus — den Rest leicht tief zentrieren,
	# damit der Ball in Daumennähe bleibt statt am oberen Rand zu kleben.
	var slack := maxf(0.0, (bottom - top) - span_z * _ppm)
	_origin = Vector2(view_size.x * 0.5 - center_x * _ppm, bottom - slack * 0.42 - 0.5 * _ppm)


## Weltkoordinaten (x, z) → Bildschirmpixel.
func _to_screen(x: float, z: float) -> Vector2:
	return Vector2(_origin.x + x * _ppm, _origin.y - z * _ppm)


func _reset_ball() -> void:
	var start: Dictionary = current_hole()["start"]
	ball = {"x": float(start["x"]), "z": float(start["z"]), "vx": 0.0, "vz": 0.0, "done": false}
	strokes = 0


func _putt() -> void:
	var pull := _drag_from - _drag_to
	if pull.length() < 8.0:
		return
	var power := Logic.power_from_drag(pull.length(), view_size.x, view_size.y)
	if power <= 0.05:
		return
	var dir := pull.normalized()
	# Bildschirm-y zeigt nach unten, Welt-z nach oben.
	ball["vx"] = dir.x * power
	ball["vz"] = -dir.y * power
	strokes += 1
	phase = "roll"
	AudioDirector.try_play(self, "mg_good", 1.0 + 0.05 * (power / 6.5))
	if ctx.juice != null:
		ctx.juice.shake(0.08 + 0.06 * power / 6.5)


func _step_roll(delta: float) -> void:
	var hole := current_hole()
	var events := Logic.step_ball(hole, ball, delta, theta, tune)
	for event in events:
		_on_event(event)
	if bool(ball.get("done", false)):
		_end_hole(true)
	elif Course.is_stopped(hole, ball):
		phase = "aim"
		if strokes >= int(tune["MAX_STROKES"]):
			_end_hole(false)


func _on_event(event: String) -> void:
	match event:
		"bank":
			AudioDirector.try_play(self, "mg_junk", 1.15)
			_spawn_sparkles(int(Logic.GOLF_JUICE["BANK_SPARKLES"]))
		"bump":
			AudioDirector.try_play(self, "mg_spill", 1.1)
			_spawn_sparkles(int(Logic.GOLF_JUICE["BANK_SPARKLES"]))
		"windmill":
			AudioDirector.try_play(self, "mg_junk", 0.8)
			if ctx.juice != null:
				ctx.juice.shake(0.2)
		"nougat":
			AudioDirector.try_play(self, "mg_spill", 0.9)
		"holed":
			pass


func _end_hole(holed: bool) -> void:
	var par := current_par()
	var taken := strokes if holed else int(tune["MAX_STROKES"]) + 1
	var points := Logic.hole_score(taken, par, tune)
	score += points
	var pos := _to_screen(
		float((current_hole()["hole"] as Dictionary)["x"]),
		float((current_hole()["hole"] as Dictionary)["z"])
	)
	_ring = float(Logic.GOLF_JUICE["RING_LIFE_SEC"])
	_ring_scale = float(Logic.GOLF_JUICE["RING_SCALE_SINK"])
	if holed and taken == 1:
		_ring_scale = float(Logic.GOLF_JUICE["RING_SCALE_ACE"])
		_flash_text = I18nService.t("mg.miniGolf.ace")
		_spawn_sparkles(int(Logic.GOLF_JUICE["ACE_SPARKLES"]))
		AudioDirector.try_play(self, "mg_golden")
		if ctx.juice != null:
			ctx.juice.hit_freeze(90)
			ctx.juice.bloom_pulse(1.0)
	elif holed:
		_flash_text = "+%d" % points
		AudioDirector.try_play(self, "mg_perfect" if taken <= par else "mg_good")
		if ctx.juice != null:
			ctx.juice.bloom_pulse(0.5)
	else:
		_flash_text = I18nService.t("mg.miniGolf.gave_up")
		AudioDirector.try_play(self, "mg_spill")
	_flash = 1.2
	if ctx.juice != null:
		ctx.juice.float_text(pos, _flash_text, Color(1.0, 0.72, 0.2))
	ctx.report_score(score, points)
	if bool(tune["ENDLESS"]) and Logic.record_hole(endless_state, taken, par):
		_finish()
		return
	phase = "pause"
	pause_left = HOLE_PAUSE_SEC


func _next_hole() -> void:
	hole_index += 1
	if not bool(tune["ENDLESS"]) and hole_index >= course.size():
		_finish()
		return
	_reset_ball()
	_fit_course()
	phase = "aim"


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	ctx.report_end({"score": score, "holes": hole_index + 1})


func _spawn_sparkles(count: int) -> void:
	var pos := _to_screen(float(ball["x"]), float(ball["z"]))
	for i in count:
		var a := TAU * _rng.next()
		_sparkles.append(
			{"p": pos, "v": Vector2(cos(a), sin(a)) * (60.0 + 90.0 * _rng.next()), "life": 0.5}
		)


func _step_sparkles(delta: float) -> void:
	var kept: Array[Dictionary] = []
	for s in _sparkles:
		s["life"] = float(s["life"]) - delta
		s["p"] = Vector2(s["p"]) + Vector2(s["v"]) * delta
		s["v"] = Vector2(s["v"]) * 0.9
		if float(s["life"]) > 0.0:
			kept.append(s)
	_sparkles = kept


func _update_labels() -> void:
	if bool(tune["ENDLESS"]):
		_hole_label.text = I18nService.t(
			"mg.miniGolf.over_par",
			{"n": int(endless_state["overPar"]), "max": int(endless_state["limit"])}
		)
	else:
		_hole_label.text = I18nService.t(
			"mg.miniGolf.hole", {"n": mini(hole_index + 1, course.size()), "max": course.size()}
		)
	_stroke_label.text = I18nService.t("mg.miniGolf.strokes", {"n": strokes, "par": current_par()})


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, view_size), Color(0.83, 0.91, 0.79))
	_draw_scenery()
	var hole := current_hole()
	_draw_fairway(hole)
	_draw_features(hole)
	_draw_cup(hole)
	_draw_ball()
	_draw_aim()
	for s in _sparkles:
		var a := clampf(float(s["life"]) * 2.0, 0.0, 1.0)
		draw_circle(Vector2(s["p"]), 3.0 + 2.0 * a, Color(1.0, 0.92, 0.55, a))
	_draw_gooby()
	_draw_flash()


## Gartenumfeld: Himmelband, Heckenreihe und Büsche rahmen die Bahn ein.
func _draw_scenery() -> void:
	var sky := view_size.y * 0.16
	for i in 8:
		var f := float(i) / 7.0
		draw_rect(
			Rect2(0.0, sky * f, view_size.x, sky / 7.0 + 1.0),
			Color(0.72, 0.88, 0.96).lerp(Color(0.86, 0.94, 0.86), f)
		)
	# Heckenreihe am Horizont.
	for i in 14:
		var x := view_size.x * (float(i) + 0.5) / 14.0
		draw_circle(Vector2(x, sky), view_size.x * 0.055, Color(0.24, 0.42, 0.28))
		draw_circle(
			Vector2(x - view_size.x * 0.012, sky - view_size.x * 0.014),
			view_size.x * 0.032,
			Color(0.31, 0.52, 0.33)
		)
	# Das Rough ist bewusst dunkel/entsättigt — sonst verschwimmt der helle
	# Bahnfilz mit der Umgebung und man sieht auf dem Handy die Bande nicht.
	draw_rect(Rect2(0.0, sky, view_size.x, view_size.y - sky), Color(0.29, 0.47, 0.31))
	# Rasenschraffur + Büsche an den Rändern.
	for i in 18:
		var y := sky + (view_size.y - sky) * float(i) / 18.0
		draw_rect(
			Rect2(0.0, y, view_size.x, (view_size.y - sky) / 36.0), Color(0.25, 0.42, 0.28, 0.7)
		)
	for i in 7:
		var t := float(i) / 6.0
		var r := view_size.x * 0.045 + 12.0 * sin(i * 2.1)
		var y := sky + (view_size.y - sky) * t
		draw_circle(Vector2(view_size.x * 0.05, y), r, Color(0.22, 0.38, 0.25, 0.9))
		draw_circle(
			Vector2(view_size.x * 0.95, view_size.y - (y - sky) * 0.9),
			r * 0.85,
			Color(0.24, 0.4, 0.26, 0.9)
		)


func _draw_fairway(hole: Dictionary) -> void:
	var cells: Array = hole["cells"]
	var pad := 0.5 * _ppm
	# Schlagschatten hebt die Bahn vom Rough ab.
	for cell: Array in cells:
		var sc := _to_screen(float(cell[0]), float(cell[1]))
		draw_rect(
			Rect2(sc.x - pad - 9.0, sc.y - pad - 3.0, pad * 2.0 + 18.0, pad * 2.0 + 18.0),
			Color(0.11, 0.2, 0.13, 0.35)
		)
	# Bandenschatten unter dem Filz.
	for cell: Array in cells:
		var c := _to_screen(float(cell[0]), float(cell[1]))
		draw_rect(
			Rect2(c.x - pad - 5.0, c.y - pad - 5.0, pad * 2.0 + 10.0, pad * 2.0 + 10.0), RAIL_COLOR
		)
	for i in cells.size():
		var cell: Array = cells[i]
		var c := _to_screen(float(cell[0]), float(cell[1]))
		var shade := FELT if i % 2 == 0 else FELT_DARK
		draw_rect(Rect2(c.x - pad, c.y - pad, pad * 2.0, pad * 2.0), shade)
	# Rampen-Höhenverlauf.
	var ramp: Dictionary = hole.get("ramp", {})
	if not ramp.is_empty():
		var rc := _to_screen(float(ramp["cell"][0]), float(ramp["cell"][1]))
		for i in 6:
			var f := float(i) / 5.0
			draw_rect(
				Rect2(
					rc.x - pad,
					rc.y + pad - (f + 0.18) * pad * 2.0 * 0.2 - i * pad * 0.33,
					pad * 2.0,
					pad * 0.3
				),
				Color(1.0, 1.0, 1.0, 0.10 + 0.10 * f)
			)


func _draw_features(hole: Dictionary) -> void:
	var bump: Dictionary = hole.get("bump", {})
	if not bump.is_empty():
		var bc := _to_screen(float(bump["x"]), float(bump["z"]))
		var br := float(Logic.GOLF["BUMP_R"]) * _ppm
		draw_circle(bc + Vector2(0.0, br * 0.18), br, Color(0.25, 0.5, 0.3, 0.5))
		draw_circle(bc, br, Color(0.55, 0.82, 0.55))
		draw_circle(bc - Vector2(br * 0.3, br * 0.3), br * 0.34, Color(0.75, 0.92, 0.72))
	var tunnel: Dictionary = hole.get("tunnel", {})
	if not tunnel.is_empty():
		var tc := _to_screen(float(tunnel["cell"][0]), float(tunnel["cell"][1]))
		var pad := 0.5 * _ppm
		draw_rect(Rect2(tc.x - pad, tc.y - pad, pad * 2.0, pad * 2.0), Color(0.42, 0.36, 0.5, 0.9))
		draw_arc(tc, pad * 0.8, PI, TAU, 18, Color(0.86, 0.8, 0.95), 4.0)
	var mill: Dictionary = hole.get("windmill", {})
	if not mill.is_empty():
		_draw_windmill(mill)
	var nougat: Dictionary = hole.get("nougat", {})
	if not nougat.is_empty():
		var nc := _to_screen(Course.nougat_x_at(hole, theta), float(nougat["z"]))
		draw_circle(nc, float(nougat["radius"]) * _ppm, Color(0.72, 0.45, 0.26))


func _draw_windmill(mill: Dictionary) -> void:
	var mc := _to_screen(float(mill["cellX"]), float(mill["gateZ"]))
	var blade := 0.46 * _ppm
	draw_rect(Rect2(mc.x - 0.5 * _ppm, mc.y - 3.0, _ppm, 6.0), Color(0.62, 0.5, 0.42, 0.6))
	var a := theta + float(mill["phase"])
	for i in 4:
		var ang := a + TAU * i / 4.0
		var tip := mc + Vector2(cos(ang), sin(ang)) * blade
		draw_line(mc, tip, Color(0.98, 0.95, 0.9), 8.0)
		draw_line(mc, tip, Color(0.85, 0.4, 0.45), 3.0)
	draw_circle(mc, 7.0, Color(0.5, 0.4, 0.36))
	if Logic.windmill_blocked(a):
		draw_arc(mc, blade * 1.15, 0.0, TAU, 24, Color(0.95, 0.35, 0.4, 0.5), 3.0)


func _draw_cup(hole: Dictionary) -> void:
	var cup: Dictionary = hole["hole"]
	var pos := _to_screen(float(cup["x"]), float(cup["z"]))
	var r := float(tune["HOLE_R"]) * _ppm
	draw_circle(pos, r * 1.25, Color(0.24, 0.44, 0.28))
	draw_circle(pos, r, CUP_COLOR)
	if _ring > 0.0:
		var f := 1.0 - _ring / float(Logic.GOLF_JUICE["RING_LIFE_SEC"])
		draw_arc(pos, r * (1.0 + f * _ring_scale), 0.0, TAU, 28, Color(1.0, 0.9, 0.5, 1.0 - f), 4.0)
	# Fahne mit kleinem Pop nach dem Einlochen.
	var pop := 1.0
	if _ring > 0.0:
		pop = (
			1.0
			+ (
				(float(Logic.GOLF_JUICE["FLAG_POP_SCALE"]) - 1.0)
				* (_ring / float(Logic.GOLF_JUICE["RING_LIFE_SEC"]))
			)
		)
	var top := pos + Vector2(0.0, -58.0 * pop)
	draw_line(pos, top, Color(0.95, 0.95, 0.95), 3.0)
	draw_colored_polygon(
		PackedVector2Array([top, top + Vector2(30.0 * pop, 9.0), top + Vector2(0.0, 20.0)]),
		FLAG_COLOR
	)


func _draw_ball() -> void:
	var pos := _to_screen(float(ball["x"]), float(ball["z"]))
	var r := maxf(5.0, float(Logic.GOLF["BALL_R"]) * _ppm)
	draw_circle(pos + Vector2(2.0, 3.0), r, Color(0.2, 0.35, 0.22, 0.35))
	draw_circle(pos, r, BALL_COLOR)
	draw_circle(pos - Vector2(r * 0.3, r * 0.3), r * 0.3, Color(1.0, 1.0, 1.0))
	draw_arc(pos, r, 0.0, TAU, 18, Color(0.7, 0.72, 0.7), 1.4)


## Zieh-Zielen: Linie + gepunktete Vorschau in Schussrichtung.
func _draw_aim() -> void:
	if not _dragging or phase != "aim":
		return
	var pull := _drag_from - _drag_to
	if pull.length() < 4.0:
		return
	var power := Logic.power_from_drag(pull.length(), view_size.x, view_size.y)
	var pos := _to_screen(float(ball["x"]), float(ball["z"]))
	var dir := pull.normalized()
	var reach := Logic.roll_distance(power) * _ppm
	draw_line(pos, pos - dir * minf(pull.length(), 150.0), Color(0.95, 0.45, 0.66, 0.5), 4.0)
	for i in PREVIEW_DOTS:
		var f := float(i + 1) / PREVIEW_DOTS
		var alpha := 0.85 - 0.5 * f
		draw_circle(pos + dir * reach * f, 3.5 - 1.5 * f, Color(1.0, 0.98, 0.9, alpha))
	var frac := power / float(Logic.GOLF["MAX_POWER"])
	draw_arc(
		pos,
		30.0,
		-PI * 0.5,
		-PI * 0.5 + TAU * frac,
		24,
		Color(1.0, 0.78, 0.3).lerp(Color(0.95, 0.35, 0.4), frac),
		5.0
	)


func _draw_gooby() -> void:
	var pos := Vector2(view_size.x - 54.0, view_size.y - 74.0)
	var r := 20.0
	draw_circle(pos + Vector2(-r * 0.5, -r * 1.05), r * 0.32, Color(0.98, 0.86, 0.6))
	draw_circle(pos + Vector2(r * 0.5, -r * 1.05), r * 0.32, Color(0.98, 0.86, 0.6))
	draw_circle(pos, r, Color(0.99, 0.9, 0.65))
	draw_circle(pos + Vector2(-r * 0.32, -r * 0.1), r * 0.11, Color(0.2, 0.16, 0.14))
	draw_circle(pos + Vector2(r * 0.32, -r * 0.1), r * 0.11, Color(0.2, 0.16, 0.14))
	draw_arc(pos + Vector2(0.0, r * 0.2), r * 0.3, 0.3, PI - 0.3, 10, Color(0.2, 0.16, 0.14), 2.2)


func _draw_flash() -> void:
	if _flash <= 0.0 or _flash_text.is_empty():
		return
	var alpha := clampf(_flash * 1.4, 0.0, 1.0)
	draw_string(
		ThemeService.font(800),
		Vector2(0.0, view_size.y * 0.2),
		_flash_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		view_size.x,
		32,
		Color(0.95, 0.45, 0.66, alpha)
	)
