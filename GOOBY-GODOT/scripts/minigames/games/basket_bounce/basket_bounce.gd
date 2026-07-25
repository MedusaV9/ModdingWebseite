extends MinigameBase
## Korbjagd (basketBounce) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## BasketBounceLogic (zahlengleich zum Web): Flick wirft, Ring/Brett prallen
## ab, Korb +3 / Brett +2 / Swish-Serie +2, ab Korb 10 wandert der Ring und
## Swishes zählen doppelt. 60 s (Endlos: bis 3 Fehlwürfe in Folge).
##
## 2D-STATT-3D (begründet): die Web-Fassung war three.js, die Physik selbst
## lebt aber komplett in der puren Logik. Die Szene projiziert dieselben
## 3D-Meter perspektivisch in eine gezeichnete Sticker-Halle — das ist auf
## dem Handy besser lesbar (Ring als Ellipse, Flugbahn als Bogen) und spart
## eine komplette 3D-Asset-Pipeline, ohne eine einzige Zahl zu verändern.

## Kamera für die Projektion (Meter): Position hinter dem Abwurfpunkt.
const CAM_Z := 8.5
const CAM_Y := 1.6
const FOCAL := 5.0
## Basis-Pixel pro Meter bei Tiefenfaktor 1 (skaliert mit der Viewport-Höhe).
const UNIT_FRAC := 0.09
## Flick-Abtastfenster (s) — nur die letzte Bewegung zählt als Wurfimpuls.
const FLICK_SAMPLE_SEC := 0.13
const TRAIL_MAX := 26

const BALL_COLOR := Color(0.95, 0.55, 0.22)
const RIM_COLOR := Color(0.98, 0.42, 0.35)
const BOARD_COLOR := Color(1.0, 0.98, 0.94, 0.92)

var tune: Dictionary = {}
var rng: GoobyRng
var score := 0
var baskets := 0
var shots := 0
var miss_streak := 0
var swish_streak := 0
var elapsed := 0.0
var slide_elapsed := 0.0
var phase := "aim"
var reset_left := 0.0
var ball: Dictionary = {}
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

var _trail: Array[Vector2] = []
var _samples: Array = []
var _dragging := false
var _drag_from := Vector2.ZERO
var _drag_to := Vector2.ZERO
var _flash := 0.0
var _flash_text := ""
var _time_label: Label
var _streak_label: Label
var _hint_label: Label


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = BasketBounceLogic.apply_difficulty(BasketBounceLogic.BASKET, ctx.difficulty)
	rng = ctx.rng()
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
	if _time_label != null:
		_time_label.position = Vector2(16.0, 10.0)
		_streak_label.position = Vector2(16.0, 48.0)
		_hint_label.position = Vector2(view_size.x * 0.5 - 150.0, view_size.y - 56.0)
		_hint_label.size = Vector2(300.0, 40.0)
	queue_redraw()


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	elapsed += delta
	_flash = maxf(0.0, _flash - delta)
	if BasketBounceLogic.is_moving_hoop(baskets, tune):
		slide_elapsed += delta
	if BasketBounceLogic.is_round_over(elapsed, miss_streak, tune):
		_finish()
		return
	if phase == "fly":
		_step_flight(delta)
	elif phase == "reset":
		reset_left -= delta
		if reset_left <= 0.0:
			phase = "aim"
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
			_samples = [{"p": event.position, "t": elapsed}]
		elif _dragging:
			_dragging = false
			_launch()
	elif event is InputEventScreenDrag and _dragging:
		_drag_to = event.position
		_samples.append({"p": event.position, "t": elapsed})
		if _samples.size() > 24:
			_samples.pop_front()
		queue_redraw()


## Aktueller Ringmittelpunkt in Weltmetern.
func hoop_now() -> Dictionary:
	var spawn: Dictionary = tune["SPAWN"]
	return {
		"x": BasketBounceLogic.hoop_slide_x(slide_elapsed, baskets, tune),
		"z": float(spawn["z"]) - BasketBounceLogic.hoop_distance(baskets, tune),
	}


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	add_child(_time_label)
	_streak_label = Label.new()
	_streak_label.theme_type_variation = &"CaptionLabel"
	add_child(_streak_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.basketBounce.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint_label)
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


## Wischimpuls aus den letzten Abtastpunkten (px/s, Bildschirmkoordinaten).
func _flick_velocity() -> Vector2:
	if _samples.size() < 2:
		return Vector2.ZERO
	var last: Dictionary = _samples[_samples.size() - 1]
	var first: Dictionary = _samples[0]
	for sample: Dictionary in _samples:
		if float(last["t"]) - float(sample["t"]) <= FLICK_SAMPLE_SEC:
			first = sample
			break
	var dt := float(last["t"]) - float(first["t"])
	if dt <= 0.0001:
		return Vector2.ZERO
	return (Vector2(last["p"]) - Vector2(first["p"])) / dt


func _launch() -> void:
	var flick := _flick_velocity()
	var vel := BasketBounceLogic.flick_to_velocity(flick.x, flick.y, tune)
	_samples = []
	if vel.is_empty():
		return
	ball = BasketBounceLogic.make_ball(vel, tune)
	_trail = []
	phase = "fly"
	AudioDirector.try_play(self, "mg_good", 0.82)


func _step_flight(delta: float) -> void:
	var hoop := hoop_now()
	var ev := BasketBounceLogic.step_ball_swept(ball, delta, hoop, tune)
	_trail.append(_project(float(ball["px"]), float(ball["py"]), float(ball["pz"])))
	if _trail.size() > TRAIL_MAX:
		_trail.pop_front()
	if bool(ev["rim"]):
		AudioDirector.try_play(self, "mg_junk", 1.1)
	if bool(ev["board"]):
		AudioDirector.try_play(self, "mg_spill", 1.15)
	if bool(ev["basket"]):
		_resolve_shot(true, not bool(ball["rim"]) and not bool(ball["board"]), bool(ball["board"]))
	elif bool(ev["dead"]):
		_resolve_shot(false, false, false)


func _resolve_shot(made: bool, swish: bool, bank: bool) -> void:
	shots += 1
	var moving := BasketBounceLogic.is_moving_hoop(baskets, tune)
	var shot := BasketBounceLogic.score_shot(
		{"basket": made, "swish": swish, "bank": bank}, swish_streak, moving, tune
	)
	swish_streak = int(shot["swishStreak"])
	var points := int(shot["points"])
	score += points
	var hoop := hoop_now()
	var pos := _project(float(hoop["x"]), float(tune["RIM_Y"]), float(hoop["z"]))
	if made:
		baskets += 1
		miss_streak = 0
		_flash_text = "+%d" % points
		_flash = 0.9
		_celebrate(swish, bank, pos, points)
	else:
		miss_streak += 1
		_flash_text = I18nService.t("mg.basketBounce.miss")
		_flash = 0.8
		AudioDirector.try_play(self, "mg_spill")
		if ctx.juice != null:
			ctx.juice.shake(0.25)
			ctx.juice.float_text(pos, _flash_text, Color(0.8, 0.35, 0.3))
	ctx.report_score(score, points)
	phase = "reset"
	reset_left = float(tune["SHOT_RESET_SEC"])
	if BasketBounceLogic.is_round_over(elapsed, miss_streak, tune):
		_finish()


func _celebrate(swish: bool, bank: bool, pos: Vector2, points: int) -> void:
	if swish:
		AudioDirector.try_play(self, "mg_perfect", 1.0 + 0.06 * minf(swish_streak - 1, 7.0))
	elif bank:
		AudioDirector.try_play(self, "mg_combo")
	else:
		AudioDirector.try_play(self, "mg_good")
	if ctx.juice == null:
		return
	ctx.juice.float_text(pos, "+%d" % points, Color(1.0, 0.72, 0.2))
	ctx.juice.hit_freeze(45)
	ctx.juice.bloom_pulse(0.7 if swish else 0.4)
	if BasketBounceLogic.is_on_fire(swish_streak):
		AudioDirector.try_play(self, "mg_golden")
		ctx.juice.bloom_pulse(1.0)
		ctx.juice.float_text(
			pos - Vector2(0.0, 44.0),
			I18nService.t("mg.basketBounce.on_fire"),
			Color(0.95, 0.45, 0.66)
		)


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	ctx.report_end({"score": score, "baskets": baskets, "shots": shots})


func _update_labels() -> void:
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.basketBounce.misses",
			{"n": miss_streak, "max": int(tune["ENDLESS_CONSECUTIVE_MISSES"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - elapsed)))
		_time_label.text = I18nService.t("mg.game.time", {"sec": left})
	if swish_streak > 1:
		_streak_label.text = I18nService.t("mg.game.streak", {"n": swish_streak})
	else:
		_streak_label.text = ""


## Perspektivische Projektion Weltmeter → Bildschirmpixel.
func _project(x: float, y: float, z: float) -> Vector2:
	var depth := maxf(0.6, CAM_Z - z)
	var s := FOCAL / depth
	var unit := view_size.y * UNIT_FRAC
	var horizon := view_size.y * (0.58 if landscape else 0.62)
	return Vector2(view_size.x * 0.5 + x * s * unit, horizon - (y - CAM_Y) * s * unit)


func _depth_scale(z: float) -> float:
	return FOCAL / maxf(0.6, CAM_Z - z)


func _draw() -> void:
	_draw_hall()
	var hoop := hoop_now()
	_draw_backboard(hoop)
	_draw_net(hoop)
	_draw_rim(hoop)
	_draw_gooby()
	if _trail.size() > 1:
		for i in range(1, _trail.size()):
			var a := float(i) / _trail.size()
			draw_line(_trail[i - 1], _trail[i], Color(1.0, 0.82, 0.4, a * 0.7), 3.0 * a + 1.0)
	_draw_ball()
	_draw_aim()
	_draw_flash()


func _draw_hall() -> void:
	var vp := view_size
	# Hallenwand mit Farbverlauf — sonst verschwimmt sie mit dem Seitenrand.
	for i in 10:
		var f := float(i) / 9.0
		draw_rect(
			Rect2(0.0, vp.y * f, vp.x, vp.y / 9.0 + 1.0),
			Color(0.93, 0.87, 0.79).lerp(Color(0.99, 0.95, 0.89), f)
		)
	# Tribünenblock mit Sitzreihen und Zuschauerköpfen.
	draw_rect(Rect2(0.0, 0.0, vp.x, vp.y * 0.34), Color(0.79, 0.88, 0.94))
	for row in 3:
		var ry := vp.y * (0.09 + row * 0.09)
		draw_rect(Rect2(0.0, ry + 12.0, vp.x, 5.0), Color(0.68, 0.79, 0.88, 0.8))
		for i in 8:
			var cx := vp.x * (0.06 + i * 0.13) + (row % 2) * vp.x * 0.05
			draw_circle(Vector2(cx, ry), 12.0, Color(0.98, 0.86, 0.6, 0.85))
			draw_circle(Vector2(cx - 8.0, ry - 8.0), 5.0, Color(0.98, 0.86, 0.6, 0.85))
			draw_circle(Vector2(cx + 8.0, ry - 8.0), 5.0, Color(0.98, 0.86, 0.6, 0.85))
	draw_rect(Rect2(0.0, vp.y * 0.34 - 8.0, vp.x, 8.0), Color(0.62, 0.74, 0.85))
	# Wimpelkette unter der Tribüne.
	for i in 11:
		var px := vp.x * (float(i) + 0.5) / 11.0
		draw_colored_polygon(
			PackedVector2Array(
				[
					Vector2(px - vp.x * 0.028, vp.y * 0.34),
					Vector2(px + vp.x * 0.028, vp.y * 0.34),
					Vector2(px, vp.y * 0.34 + vp.x * 0.05),
				]
			),
			[Color(0.95, 0.45, 0.66, 0.7), Color(0.35, 0.78, 0.7, 0.7), Color(1.0, 0.78, 0.35, 0.7)][
				i % 3
			]
		)
	var floor_near := _project(0.0, 0.0, 5.4).y
	var floor_far := _project(0.0, 0.0, -2.4).y
	draw_rect(Rect2(0.0, floor_far, vp.x, vp.y - floor_far), Color(0.93, 0.78, 0.56))
	for i in 9:
		var wx := -4.0 + i
		var near := _project(wx, 0.0, 5.4)
		var far := _project(wx, 0.0, -2.4)
		draw_line(near, far, Color(0.86, 0.68, 0.46, 0.55), 2.0)
	draw_line(Vector2(0.0, floor_far), Vector2(vp.x, floor_far), Color(0.84, 0.66, 0.44), 3.0)
	draw_line(Vector2(0.0, floor_near), Vector2(vp.x, floor_near), Color(0.9, 0.72, 0.5, 0.5), 2.0)


func _draw_backboard(hoop: Dictionary) -> void:
	var hz := float(hoop["z"]) - float(tune["BOARD_GAP"])
	var hx := float(hoop["x"])
	var half := float(tune["BOARD_W"]) * 0.5
	var bottom := float(tune["BOARD_BOTTOM_Y"])
	var top := bottom + float(tune["BOARD_H"])
	var quad := PackedVector2Array(
		[
			_project(hx - half, top, hz),
			_project(hx + half, top, hz),
			_project(hx + half, bottom, hz),
			_project(hx - half, bottom, hz),
		]
	)
	draw_colored_polygon(quad, BOARD_COLOR)
	draw_polyline(quad + PackedVector2Array([quad[0]]), Color(0.55, 0.45, 0.4), 3.0)
	# Zielrechteck auf dem Brett.
	var inner := PackedVector2Array(
		[
			_project(hx - half * 0.32, bottom + 0.86, hz),
			_project(hx + half * 0.32, bottom + 0.86, hz),
			_project(hx + half * 0.32, bottom + 0.2, hz),
			_project(hx - half * 0.32, bottom + 0.2, hz),
		]
	)
	draw_polyline(inner + PackedVector2Array([inner[0]]), RIM_COLOR, 3.0)
	# Mast bis zum Boden.
	draw_line(
		_project(hx, bottom, hz),
		_project(hx, 0.0, hz),
		Color(0.6, 0.55, 0.55),
		6.0 * _depth_scale(hz)
	)


func _draw_rim(hoop: Dictionary) -> void:
	var pts := _ring_points(hoop, float(tune["RIM_Y"]))
	draw_polyline(pts, RIM_COLOR, maxf(2.5, 6.0 * _depth_scale(float(hoop["z"]))))


func _draw_net(hoop: Dictionary) -> void:
	var top := _ring_points(hoop, float(tune["RIM_Y"]))
	var lip := float(tune["RIM_Y"]) - 0.42
	var center := _project(float(hoop["x"]), lip, float(hoop["z"]))
	for i in range(0, top.size() - 1, 2):
		draw_line(top[i], top[i].lerp(center, 0.92), Color(1.0, 1.0, 1.0, 0.75), 1.6)
	draw_polyline(_ring_points(hoop, lip, 0.62), Color(1.0, 1.0, 1.0, 0.55), 1.6)


## Ringkreis in Weltkoordinaten abtasten und projizieren.
func _ring_points(hoop: Dictionary, y: float, shrink := 1.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var r := float(tune["RIM_R"]) * shrink
	for i in 25:
		var a := TAU * i / 24.0
		pts.append(_project(float(hoop["x"]) + cos(a) * r, y, float(hoop["z"]) + sin(a) * r))
	return pts


func _ellipse_points(center: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 20:
		var a := TAU * float(i) / 20.0
		pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
	return pts


func _draw_ball() -> void:
	var pos: Vector2
	var depth: float
	var world := Vector3.ZERO
	if phase == "fly" and not ball.is_empty():
		world = Vector3(float(ball["px"]), float(ball["py"]), float(ball["pz"]))
	else:
		var spawn: Dictionary = tune["SPAWN"]
		world = Vector3(float(spawn["x"]), float(spawn["y"]), float(spawn["z"]))
	pos = _project(world.x, world.y, world.z)
	depth = _depth_scale(world.z)
	var r := maxf(6.0, float(tune["BALL_R"]) * depth * view_size.y * UNIT_FRAC)
	# Bodenschatten: einzige Höhenanzeige in der 2D-Projektion.
	var ground := _project(world.x, 0.0, world.z)
	var fade := clampf(1.0 - world.y / 4.0, 0.15, 0.55)
	draw_colored_polygon(_ellipse_points(ground, r * 1.15, r * 0.42), Color(0.55, 0.4, 0.26, fade))
	draw_circle(pos + Vector2(0.0, r * 0.15), r, Color(0.72, 0.36, 0.14))
	draw_circle(pos, r, BALL_COLOR)
	draw_arc(pos, r * 0.92, 0.0, TAU, 20, Color(0.6, 0.28, 0.12), 1.8)
	draw_line(pos + Vector2(-r, 0.0), pos + Vector2(r, 0.0), Color(0.6, 0.28, 0.12), 1.8)
	draw_arc(pos, r * 1.4, -PI * 0.9, -PI * 0.1, 14, Color(0.6, 0.28, 0.12, 0.5), 1.6)


func _draw_aim() -> void:
	if not _dragging:
		return
	var pull := _drag_to - _drag_from
	draw_line(_drag_from, _drag_to, Color(0.95, 0.45, 0.66, 0.55), 4.0)
	var flick := _flick_velocity()
	var preview := BasketBounceLogic.flick_to_velocity(flick.x, flick.y, tune)
	var strength := clampf(pull.length() / 220.0, 0.0, 1.0)
	var tint := Color(0.35, 0.78, 0.5, 0.9) if not preview.is_empty() else Color(0.8, 0.5, 0.5, 0.7)
	draw_arc(_drag_from, 26.0, -PI * 0.5, -PI * 0.5 + TAU * strength, 22, tint, 5.0)


func _draw_gooby() -> void:
	var pos := _project(-1.35, 0.0, 4.9)
	var r := 26.0 * _depth_scale(4.9)
	draw_circle(pos + Vector2(-r * 0.5, -r * 2.2), r * 0.34, Color(0.98, 0.86, 0.6))
	draw_circle(pos + Vector2(r * 0.5, -r * 2.2), r * 0.34, Color(0.98, 0.86, 0.6))
	draw_circle(pos + Vector2(0.0, -r), r, Color(0.99, 0.9, 0.65))
	draw_circle(pos + Vector2(-r * 0.34, -r * 1.1), r * 0.11, Color(0.2, 0.16, 0.14))
	draw_circle(pos + Vector2(r * 0.34, -r * 1.1), r * 0.11, Color(0.2, 0.16, 0.14))
	draw_arc(pos + Vector2(0.0, -r * 0.75), r * 0.3, 0.3, PI - 0.3, 12, Color(0.2, 0.16, 0.14), 2.5)


func _draw_flash() -> void:
	if _flash <= 0.0 or _flash_text.is_empty():
		return
	var font := ThemeService.font(800)
	var alpha := clampf(_flash * 1.6, 0.0, 1.0)
	var pos := Vector2(0.0, view_size.y * 0.3)
	draw_string(
		font,
		pos,
		_flash_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		view_size.x,
		34,
		Color(0.95, 0.45, 0.66, alpha)
	)
