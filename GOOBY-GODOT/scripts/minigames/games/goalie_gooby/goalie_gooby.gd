extends MinigameBase
## Torwart-Gooby (goalieGooby) — Spiel-Szene. Alle MECHANIK-Zahlen aus
## GoalieGoobyLogic (zahlengleich zum Web): 5 Bahnen, Ankündigung 0.9 s → 0.45 s,
## Heber/Roller, Parade +4 (+2 Superparade), 3 Gegentore beenden früh,
## alle 10 Paraden Jubel + 10 % Tempo, Elfmeterfinale ab Sekunde 50.
##
## 2D-Sticker (begründet): das Tormaul ist ein flaches 5-Bahnen-Raster — eine
## frontale 2D-Ansicht macht Bahn und Höhe sofort lesbar; der Ball wächst beim
## Anflug (Scheinperspektive) statt einer echten 3D-Kamera.

const Logic := preload("res://scripts/minigames/games/goalie_gooby/goalie_gooby_logic.gd")

## Anteil der Viewport-Höhe, den das Tor einnimmt.
const GOAL_H_FRAC := 0.46
## Mindest-Wischweg (px), bevor eine Geste als Hechte gilt.
const SWIPE_MIN_PX := 10.0

const GRASS := Color(0.44, 0.72, 0.42)
const GRASS_DARK := Color(0.39, 0.67, 0.39)
const POST := Color(0.99, 0.99, 0.97)
const BALL_COLOR := Color(0.99, 0.99, 0.96)

var tune: Dictionary = {}
var rng: GoobyRng
var score := 0
var saves := 0
var goals := 0
var elapsed := 0.0
var kick: Dictionary = {}
var kick_start := 0.0
var arrive_t := 0.0
var next_kick_at := 0.6
var dive: Dictionary = {}
var finished := false
var view_size := Vector2(844.0, 390.0)
var landscape := true

var _stream: Callable
var _drag_from := Vector2.ZERO
var _ring := 0.0
var _ring_scale := 1.0
var _glove_pop := 0.0
var _pip_pop := 0.0
var _cheer := 0.0
var _flash := 0.0
var _flash_text := ""
var _time_label: Label
var _saves_label: Label
var _hint_label: Label


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = Logic.apply_difficulty(Logic.GOALIE, ctx.difficulty)
	rng = ctx.rng()
	_stream = func() -> float: return rng.next()
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
		_saves_label.position = Vector2(16.0, 48.0)
		_hint_label.position = Vector2(view_size.x * 0.5 - 150.0, view_size.y - 48.0)
		_hint_label.size = Vector2(300.0, 40.0)
	queue_redraw()


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	elapsed += delta
	_ring = maxf(0.0, _ring - delta)
	_glove_pop = maxf(0.0, _glove_pop - delta)
	_pip_pop = maxf(0.0, _pip_pop - delta)
	_cheer = maxf(0.0, _cheer - delta)
	_flash = maxf(0.0, _flash - delta)
	if not bool(tune["ENDLESS"]) and elapsed >= float(tune["DURATION_SEC"]):
		_finish()
		return
	if kick.is_empty():
		if elapsed >= next_kick_at:
			_spawn_kick()
	elif elapsed >= arrive_t:
		_resolve_kick()
	_update_labels()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_drag_from = event.position
		else:
			_dive(event.position - _drag_from)


## Aktuelle Torbreite in Weltmetern (quer breiter als hochkant).
func goal_half_width() -> float:
	var juice: Dictionary = Logic.GOALIE_JUICE
	return float(juice["GOAL_HALF_W_LANDSCAPE" if landscape else "GOAL_HALF_W_PORTRAIT"])


## Wie weit der aktuelle Schuss geflogen ist (0 Ankündigung … 1 Linie).
func kick_progress() -> float:
	if kick.is_empty():
		return 0.0
	var telegraph := float(kick["telegraph"])
	var flight := float(kick["flight"])
	var t := elapsed - kick_start
	if t < telegraph:
		return 0.0
	return clampf((t - telegraph) / maxf(0.001, flight), 0.0, 1.0)


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	add_child(_time_label)
	_saves_label = Label.new()
	_saves_label.theme_type_variation = &"CaptionLabel"
	add_child(_saves_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.goalieGooby.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint_label)
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _spawn_kick() -> void:
	var shootout := Logic.is_shootout_at(elapsed, tune)
	var rolled := Logic.roll_kick(_stream, elapsed)
	var telegraph: float = (
		tune["SHOOTOUT_TELEGRAPH_SEC"] if shootout else Logic.telegraph_sec_at(elapsed, tune)
	)
	var flight: float = (
		tune["SHOOTOUT_FLIGHT_SEC"]
		if shootout
		else Logic.flight_sec_at(Logic.cheers_at(saves), tune)
	)
	kick = {
		"lane": int(rolled["lane"]),
		"kind": str(rolled["kind"]),
		"telegraph": telegraph,
		"flight": flight,
		"shootout": shootout,
	}
	kick_start = elapsed
	arrive_t = elapsed + telegraph + flight
	dive = {}
	AudioDirector.try_play(self, "mg_junk", 0.7)


## Hechte in die gewischte Bahn (Tippen = Mitte).
func _dive(delta_px: Vector2) -> void:
	var lane := Logic.lane_from_swipe(delta_px.x, delta_px.y)
	var v := Logic.v_kind_from_swipe(delta_px.y)
	if delta_px.length() < SWIPE_MIN_PX:
		lane = 2
		v = "mid"
	dive = {"lane": lane, "v": v, "t": elapsed}
	_glove_pop = 0.25
	AudioDirector.try_play(self, "mg_good", 1.1)
	if ctx.juice != null:
		ctx.juice.shake(0.1)


func _resolve_kick() -> void:
	var saved := (
		not dive.is_empty()
		and Logic.save_matches(kick, dive)
		and Logic.dive_covers(float(dive["t"]), arrive_t, tune)
	)
	var shootout := bool(kick["shootout"])
	if saved:
		_on_save()
	else:
		_on_goal()
	kick = {}
	next_kick_at = elapsed + float(tune["SHOOTOUT_GAP_SEC" if shootout else "GAP_SEC"])


func _on_save() -> void:
	var super_save := Logic.is_super_save(float(dive["t"]), arrive_t, tune)
	var shootout := bool(kick["shootout"])
	var points := Logic.save_points(super_save, shootout, tune)
	var before := Logic.cheers_at(saves)
	saves += 1
	score += points
	_ring = float(Logic.GOALIE_JUICE["RING_LIFE_SEC"])
	_ring_scale = float(Logic.GOALIE_JUICE["RING_SCALE_SUPER" if super_save else "RING_SCALE_SAVE"])
	_flash_text = I18nService.t("mg.goalieGooby.super") if super_save else "+%d" % points
	_flash = 0.8
	AudioDirector.try_play(self, "mg_perfect" if super_save else "mg_good")
	if ctx.juice != null:
		# Nur die Punktzahl schwebt — der Klartext steht schon als Banner da.
		ctx.juice.float_text(_lane_pos(int(kick["lane"])), "+%d" % points, Color(1.0, 0.78, 0.3))
		ctx.juice.hit_freeze(70 if super_save else 35)
		ctx.juice.bloom_pulse(0.9 if super_save else 0.4)
		if super_save:
			ctx.juice.slowmo(0.35, 260)
	if Logic.cheers_at(saves) > before:
		_cheer = 1.4
		AudioDirector.try_play(self, "mg_golden")
		if ctx.juice != null:
			ctx.juice.bloom_pulse(1.0)
	ctx.report_score(score, points)


func _on_goal() -> void:
	goals += 1
	_pip_pop = 0.4
	_flash_text = I18nService.t("mg.goalieGooby.goal")
	_flash = 1.0
	AudioDirector.try_play(self, "mg_spill")
	if ctx.juice != null:
		ctx.juice.shake(0.5)
	ctx.report_score(score, 0)
	if goals >= int(tune["MAX_GOALS"]):
		_finish()


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	ctx.report_end({"score": score, "saves": saves, "goals": goals})


func _update_labels() -> void:
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.goalieGooby.conceded", {"n": goals, "max": int(tune["ENDLESS_GOALS"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - elapsed)))
		_time_label.text = I18nService.t("mg.game.time", {"sec": left})
	_saves_label.text = I18nService.t("mg.goalieGooby.saves", {"n": saves})


func _goal_rect() -> Rect2:
	var h := view_size.y * GOAL_H_FRAC
	var w := minf(view_size.x * 0.86, h * 2.3)
	return Rect2(view_size.x * 0.5 - w * 0.5, view_size.y * 0.16, w, h)


## Mittelpunkt einer Bahn auf der Torlinie.
func _lane_pos(lane: int) -> Vector2:
	var r := _goal_rect()
	var lanes := int(tune["LANES"])
	return Vector2(r.position.x + r.size.x * (lane + 0.5) / lanes, r.position.y + r.size.y * 0.62)


func _draw() -> void:
	_draw_pitch()
	_draw_goal()
	_draw_telegraph()
	_draw_keeper()
	_draw_ball()
	_draw_pips()
	if _cheer > 0.0:
		_draw_cheer()
	_draw_flash()


func _draw_pitch() -> void:
	var vp := view_size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.68, 0.86, 0.95))
	var horizon := vp.y * 0.14
	draw_rect(Rect2(0.0, horizon, vp.x, vp.y - horizon), GRASS)
	for i in 8:
		if i % 2 == 0:
			var y := horizon + (vp.y - horizon) * i / 8.0
			draw_rect(Rect2(0.0, y, vp.x, (vp.y - horizon) / 8.0), GRASS_DARK)
	# Strafraum + Elfmeterpunkt liegen VOR dem Tor (unterhalb der Torlinie),
	# sonst schneiden die Linien durch das Netz und die Perspektive kippt.
	var goal := _goal_rect()
	var line := Color(1.0, 1.0, 1.0, 0.3)
	var depth := maxf(40.0, vp.y - goal.end.y)
	var box_h := depth * 0.6
	var box_w := minf(vp.x * 0.94, goal.size.x * 1.9)
	var box := Rect2(vp.x * 0.5 - box_w * 0.5, goal.end.y, box_w, box_h)
	var six_w := minf(vp.x * 0.6, goal.size.x * 1.28)
	# Torlinie selbst.
	draw_line(box.position, Vector2(box.end.x, box.position.y), line, 3.0)
	draw_rect(box, line, false, 3.0)
	draw_rect(Rect2(vp.x * 0.5 - six_w * 0.5, goal.end.y, six_w, box_h * 0.42), line, false, 3.0)
	var spot := Vector2(vp.x * 0.5, goal.end.y + box_h * 0.58)
	draw_circle(spot, 4.0, line)
	draw_arc(spot, box_h * 0.5, 0.16 * PI, 0.84 * PI, 28, line, 3.0)
	# Hasenpublikum auf der Tribüne.
	for i in 12:
		var cx := vp.x * (0.04 + i * 0.082)
		var bob := sin(elapsed * 4.0 + i) * (6.0 if _cheer > 0.0 else 1.5)
		draw_circle(Vector2(cx, horizon * 0.6 - bob), 9.0, Color(0.98, 0.9, 0.82))
		draw_circle(Vector2(cx - 4.0, horizon * 0.6 - 12.0 - bob), 3.0, Color(0.98, 0.9, 0.82))
		draw_circle(Vector2(cx + 4.0, horizon * 0.6 - 12.0 - bob), 3.0, Color(0.98, 0.9, 0.82))


func _draw_goal() -> void:
	var r := _goal_rect()
	# Netz.
	draw_rect(r, Color(1.0, 1.0, 1.0, 0.14))
	for i in 15:
		var x := r.position.x + r.size.x * i / 14.0
		draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(1, 1, 1, 0.3), 1.2)
	for i in 8:
		var y := r.position.y + r.size.y * i / 7.0
		draw_line(Vector2(r.position.x, y), Vector2(r.end.x, y), Color(1, 1, 1, 0.3), 1.2)
	# Pfosten + Latte.
	draw_line(r.position, Vector2(r.position.x, r.end.y), POST, 9.0)
	draw_line(Vector2(r.end.x, r.position.y), r.end, POST, 9.0)
	draw_line(r.position, Vector2(r.end.x, r.position.y), POST, 9.0)
	# Bahntrenner.
	var lanes := int(tune["LANES"])
	for i in range(1, lanes):
		var x := r.position.x + r.size.x * i / lanes
		draw_line(Vector2(x, r.position.y), Vector2(x, r.end.y), Color(1, 1, 1, 0.16), 2.0)


## Angekündigte Bahn blinkt, solange der Schütze ausholt.
func _draw_telegraph() -> void:
	if kick.is_empty():
		return
	var t := elapsed - kick_start
	if t > float(kick["telegraph"]):
		return
	var r := _goal_rect()
	var lanes := int(tune["LANES"])
	var w := r.size.x / lanes
	var x := r.position.x + w * int(kick["lane"])
	var pulse := 0.35 + 0.35 * sin(t * 22.0)
	var tint := Color(1.0, 0.85, 0.35, pulse)
	if str(kick["kind"]) == "lob":
		tint = Color(0.55, 0.85, 1.0, pulse)
	elif str(kick["kind"]) == "roller":
		tint = Color(1.0, 0.6, 0.85, pulse)
	draw_rect(Rect2(x, r.position.y, w, r.size.y), tint)
	# Pfeil zeigt die nötige Wischrichtung an.
	var c := Vector2(x + w * 0.5, r.position.y + r.size.y * 0.5)
	if str(kick["kind"]) == "lob":
		draw_colored_polygon(
			PackedVector2Array([c + Vector2(0, -22), c + Vector2(-14, 6), c + Vector2(14, 6)]),
			Color(1, 1, 1, 0.85)
		)
	elif str(kick["kind"]) == "roller":
		draw_colored_polygon(
			PackedVector2Array([c + Vector2(0, 22), c + Vector2(-14, -6), c + Vector2(14, -6)]),
			Color(1, 1, 1, 0.85)
		)


func _draw_keeper() -> void:
	var r := _goal_rect()
	var lane := int(dive.get("lane", 2))
	var v := str(dive.get("v", "mid"))
	var base := _lane_pos(lane)
	var lift := -r.size.y * 0.2 if v == "up" else (r.size.y * 0.16 if v == "down" else 0.0)
	var pos := Vector2(base.x, r.end.y - r.size.y * 0.22 + lift)
	var scale := 26.0 * float(tune["RENDER_SCALE"])
	draw_circle(pos + Vector2(-scale * 0.5, -scale * 1.05), scale * 0.32, Color(0.98, 0.86, 0.6))
	draw_circle(pos + Vector2(scale * 0.5, -scale * 1.05), scale * 0.32, Color(0.98, 0.86, 0.6))
	draw_circle(pos, scale, Color(0.99, 0.9, 0.65))
	draw_circle(pos + Vector2(-scale * 0.32, -scale * 0.1), scale * 0.11, Color(0.2, 0.16, 0.14))
	draw_circle(pos + Vector2(scale * 0.32, -scale * 0.1), scale * 0.11, Color(0.2, 0.16, 0.14))
	draw_arc(
		pos + Vector2(0.0, scale * 0.2), scale * 0.3, 0.3, PI - 0.3, 10, Color(0.2, 0.16, 0.14), 2.4
	)
	# Handschuhe (poppen bei einer frischen Hechte).
	var glove := (
		scale
		* 0.42
		* (1.0 + (float(Logic.GOALIE_JUICE["GLOVE_PUNCH_SCALE"]) - 1.0) * (_glove_pop / 0.25))
	)
	draw_circle(pos + Vector2(-scale * 1.25, -scale * 0.25), glove, Color(0.98, 0.55, 0.35))
	draw_circle(pos + Vector2(scale * 1.25, -scale * 0.25), glove, Color(0.98, 0.55, 0.35))
	if _ring > 0.0:
		var f := 1.0 - _ring / float(Logic.GOALIE_JUICE["RING_LIFE_SEC"])
		draw_arc(
			_lane_pos(lane),
			18.0 * (1.0 + f * _ring_scale),
			0.0,
			TAU,
			26,
			Color(1.0, 0.92, 0.5, 1.0 - f),
			4.0
		)


func _draw_ball() -> void:
	if kick.is_empty():
		return
	var p := kick_progress()
	var r := _goal_rect()
	var target := _lane_pos(int(kick["lane"]))
	var from := Vector2(view_size.x * 0.5, r.position.y + r.size.y * 0.1)
	var pos := from.lerp(target, p)
	if str(kick["kind"]) == "lob":
		pos.y -= sin(p * PI) * r.size.y * 0.3
	elif str(kick["kind"]) == "roller":
		pos.y += sin(p * PI) * r.size.y * 0.18
	var rad := 5.0 + 16.0 * p
	draw_circle(pos + Vector2(2.0, 3.0), rad, Color(0.1, 0.2, 0.12, 0.3))
	draw_circle(pos, rad, BALL_COLOR)
	for i in 5:
		var a := TAU * i / 5.0 + elapsed * 5.0
		draw_circle(pos + Vector2(cos(a), sin(a)) * rad * 0.5, rad * 0.22, Color(0.2, 0.2, 0.24))


## Gegentor-Anzeige (drei Punkte).
func _draw_pips() -> void:
	var maxg := int(tune["ENDLESS_GOALS"] if bool(tune["ENDLESS"]) else tune["MAX_GOALS"])
	for i in maxg:
		var pos := Vector2(view_size.x - 34.0 - i * 30.0, 26.0)
		var rad := 10.0
		if i == goals - 1 and _pip_pop > 0.0:
			rad *= 1.0 + (float(Logic.GOALIE_JUICE["PIP_POP_SCALE"]) - 1.0) * (_pip_pop / 0.4)
		draw_circle(pos, rad, Color(0.9, 0.35, 0.35) if i < goals else Color(1, 1, 1, 0.35))


func _draw_cheer() -> void:
	draw_string(
		ThemeService.font(800),
		Vector2(0.0, view_size.y * 0.1),
		I18nService.t("mg.goalieGooby.cheer"),
		HORIZONTAL_ALIGNMENT_CENTER,
		view_size.x,
		26,
		Color(1.0, 0.85, 0.4, clampf(_cheer, 0.0, 1.0))
	)


func _draw_flash() -> void:
	if _flash <= 0.0 or _flash_text.is_empty():
		return
	var alpha := clampf(_flash * 1.5, 0.0, 1.0)
	# Ohne dunkles Band verschwindet Pink auf dem Rasen.
	var y := view_size.y * 0.78
	draw_rect(Rect2(0.0, y - 34.0, view_size.x, 48.0), Color(0.12, 0.2, 0.13, 0.5 * alpha))
	draw_string(
		ThemeService.font(800),
		Vector2(0.0, y),
		_flash_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		view_size.x,
		32,
		Color(1.0, 0.86, 0.5, alpha)
	)
