extends MinigameBase
## Guck-guck-Garten (hideSeek) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## HideSeekLogic (zahlengleich zum Web): 3×4-Versteckraster, Tierchen lugen
## periodisch hervor, Tipp aufs richtige Versteck +2, geräumte Welle +3,
## 60 s (Endlos: bis 3 abgelaufene Wellen).
##
## 2D (Web war three.js, aber flach frontal): das Raster wurde schon im Web
## wie ein Brettspiel von vorn gezeigt — als gezeichnete Sticker-Bühne ist es
## auf dem Handy schärfer lesbar und braucht keine 3D-Pipeline.

const Logic := preload("res://scripts/minigames/games/hide_seek/hide_seek_logic.gd")

## Pastellfarben der Tierchen (eine je Verstecker, zyklisch).
const CRITTER_COLORS: Array[Color] = [
	Color(1.0, 0.66, 0.78),
	Color(0.5, 0.83, 0.76),
	Color(1.0, 0.85, 0.48),
	Color(0.73, 0.66, 1.0),
	Color(1.0, 0.69, 0.54),
]
const SKY_TOP := Color(0.72, 0.89, 0.96)
const SKY_BOTTOM := Color(0.92, 0.97, 0.88)
const GRASS := Color(0.55, 0.79, 0.5)
## Entwurfs-Kurzkante — Pixelmaße der Bedienleiste skalieren damit.
const DESIGN_SHORT := 390.0

var tune: Dictionary = {}
var rng: GoobyRng
var score := 0
var wave := 0
var expired := 0
var found_total := 0
var elapsed := 0.0
var wave_t := 0.0
var wave_sec := 13.0
var serve_t := 0.0
var phase := "play"
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

## spot index → {"found": bool, "peek_t": float, "next_peek": float, "color": int}
var _critters: Dictionary = {}
var _hidden: Dictionary = {}
var _shake: PackedFloat32Array = PackedFloat32Array()
var _ui := 1.0
var _time_label: Label
var _wave_label: Label
var _hint_label: Label
var _banner := ""
var _banner_t := 0.0


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = Logic.apply_difficulty(Logic.SEEK, ctx.difficulty)
	rng = ctx.rng()
	_shake.resize(Logic.spot_count(tune))
	_build_hud()
	_start_wave(0)
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
	_layout_hud()
	queue_redraw()


## Bedienleiste in Entwurfspixeln, mit _ui skaliert (sonst Krümelschrift).
func _layout_hud() -> void:
	if _time_label == null:
		return
	var pad := 14.0 * _ui
	_time_label.position = Vector2(pad, 8.0 * _ui)
	_time_label.add_theme_font_size_override("font_size", int(26.0 * _ui))
	_wave_label.position = Vector2(pad, 44.0 * _ui)
	_wave_label.add_theme_font_size_override("font_size", int(17.0 * _ui))
	var hint_w := minf(view_size.x - pad * 2.0, 420.0 * _ui)
	_hint_label.add_theme_font_size_override("font_size", int(15.0 * _ui))
	_hint_label.position = Vector2((view_size.x - hint_w) * 0.5, view_size.y - 48.0 * _ui)
	_hint_label.size = Vector2(hint_w, 42.0 * _ui)


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	elapsed += delta
	_banner_t = maxf(0.0, _banner_t - delta)
	for i in _shake.size():
		_shake[i] = maxf(0.0, _shake[i] - delta)
	if not bool(tune["ENDLESS"]) and elapsed >= float(tune["DURATION_SEC"]):
		_finish()
		return
	if phase == "serve":
		serve_t -= delta
		if serve_t <= 0.0:
			phase = "play"
			_start_wave(wave + 1)
		_update_labels()
		queue_redraw()
		return
	wave_t += delta
	if wave_t >= wave_sec:
		_expire_wave()
		_update_labels()
		queue_redraw()
		return
	_tick_peeks(delta)
	_update_labels()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished or phase != "play":
		return
	if event is InputEventScreenTouch and event.pressed:
		var spot := _spot_at(event.position)
		if spot >= 0:
			_tap_spot(spot)


## Raster-Geometrie: Spalten/Zeilen tauschen in Landscape (rein visuell).
func grid_dims() -> Vector2i:
	var cols := int(tune["COLS"])
	var rows := int(tune["ROWS"])
	return Vector2i(rows, cols) if landscape else Vector2i(cols, rows)


## Bildschirm-Mittelpunkt eines Verstecks.
func spot_center(spot: int) -> Vector2:
	var dims := grid_dims()
	var col := spot % dims.x
	var row := spot / dims.x
	var cell := _cell_size()
	var origin := _grid_origin(cell, dims)
	return origin + Vector2((col + 0.5) * cell.x, (row + 0.55) * cell.y)


func _cell_size() -> Vector2:
	var dims := grid_dims()
	var usable := Vector2(view_size.x * 0.9, view_size.y * (0.66 if landscape else 0.7))
	return Vector2(usable.x / dims.x, usable.y / dims.y)


func _grid_origin(cell: Vector2, dims: Vector2i) -> Vector2:
	var w := cell.x * dims.x
	var h := cell.y * dims.y
	var top := view_size.y * (0.2 if landscape else 0.17)
	return Vector2((view_size.x - w) * 0.5, top + (view_size.y * 0.72 - h) * 0.5)


func _spot_at(pos: Vector2) -> int:
	var total := Logic.spot_count(tune)
	var cell := _cell_size()
	var reach := minf(cell.x, cell.y) * 0.55
	for i in total:
		if pos.distance_to(spot_center(i)) <= reach:
			return i
	return -1


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	add_child(_time_label)
	_wave_label = Label.new()
	_wave_label.theme_type_variation = &"CaptionLabel"
	add_child(_wave_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.hideSeek.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Der Hinweis liegt auf der Wiese — heller Text mit weichem Rand.
	_hint_label.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.95))
	_hint_label.add_theme_color_override("font_outline_color", Color(0.16, 0.28, 0.14, 0.42))
	_hint_label.add_theme_constant_override("outline_size", 7)
	add_child(_hint_label)
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _start_wave(index: int) -> void:
	wave = index
	wave_sec = Logic.wave_sec_for(wave, tune)
	wave_t = 0.0
	_hidden.clear()
	_critters.clear()
	var spots := Logic.roll_hiders(rng, wave, tune)
	for i in spots.size():
		var spot: int = spots[i]
		_hidden[spot] = true
		_critters[spot] = {
			"found": false,
			"peek_t": 0.0,
			"next_peek": elapsed + 0.6 + rng.next() * float(tune["PEEK_EVERY_SEC"]),
			"color": i % CRITTER_COLORS.size(),
		}
	if wave > 0:
		_set_banner(I18nService.t("mg.hideSeek.wave_new", {"n": spots.size()}))


func _tick_peeks(delta: float) -> void:
	for spot: int in _critters:
		var critter: Dictionary = _critters[spot]
		if bool(critter["found"]) or not _hidden.has(spot):
			continue
		if float(critter["peek_t"]) > 0.0:
			critter["peek_t"] = float(critter["peek_t"]) - delta
			if float(critter["peek_t"]) <= 0.0:
				critter["peek_t"] = 0.0
				critter["next_peek"] = (
					elapsed + float(tune["PEEK_EVERY_SEC"]) * (0.75 + rng.next() * 0.5)
				)
		elif elapsed >= float(critter["next_peek"]):
			critter["peek_t"] = float(tune["PEEK_DURATION_SEC"])
			AudioDirector.try_play(self, "ui_tick", 1.2)


func _tap_spot(spot: int) -> void:
	if spot < 0 or spot >= _shake.size():
		return
	_shake[spot] = 0.35
	var pos := spot_center(spot)
	if not _hidden.has(spot):
		AudioDirector.try_play(self, "ui_chip")
		if ctx.juice != null:
			ctx.juice.float_text(pos, I18nService.t("mg.hideSeek.empty"), Color(0.54, 0.5, 0.66))
		return
	_hidden.erase(spot)
	var critter: Dictionary = _critters[spot]
	critter["found"] = true
	critter["peek_t"] = 0.0
	found_total += 1
	var prev := score
	score = Logic.apply_score(score, int(tune["FIND_PTS"]))
	if score != prev:
		ctx.report_score(score, score - prev)
	AudioDirector.try_play(self, "mg_good", 1.08)
	if ctx.juice != null:
		ctx.juice.float_text(
			pos,
			"+%d %s" % [int(tune["FIND_PTS"]), I18nService.t("mg.hideSeek.found")],
			Color(0.18, 0.55, 0.34)
		)
		ctx.juice.hit_freeze(40)
		ctx.juice.bloom_pulse(0.4)
	if _hidden.is_empty():
		_clear_wave()


func _clear_wave() -> void:
	var prev := score
	score = Logic.apply_score(score, int(tune["WAVE_BONUS"]))
	if score != prev:
		ctx.report_score(score, score - prev)
	AudioDirector.try_play(self, "mg_perfect")
	_set_banner(I18nService.t("mg.hideSeek.wave_clear", {"n": int(tune["WAVE_BONUS"])}))
	if ctx.juice != null:
		ctx.juice.bloom_pulse(0.9)
		ctx.juice.shake(0.12)
	phase = "serve"
	serve_t = float(tune["SERVE_SEC"])


func _expire_wave() -> void:
	expired += 1
	AudioDirector.try_play(self, "mg_spill")
	_set_banner(I18nService.t("mg.hideSeek.expired"))
	for spot: int in _critters:
		(_critters[spot] as Dictionary)["peek_t"] = 0.0
	if ctx.juice != null:
		ctx.juice.shake(0.28)
	if Logic.endless_should_end(expired, tune):
		_finish()
		return
	phase = "serve"
	serve_t = float(tune["SERVE_SEC"])


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	ctx.report_end({"score": score, "waves": wave + 1, "found": found_total, "expired": expired})


func _set_banner(text: String) -> void:
	_banner = text
	_banner_t = 1.4


func _update_labels() -> void:
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.hideSeek.expired_count", {"n": expired, "max": int(tune["ENDLESS_MAX_EXPIRED"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - elapsed)))
		_time_label.text = I18nService.t("mg.game.time", {"sec": left})
	_wave_label.text = I18nService.t("mg.hideSeek.wave", {"n": wave + 1, "left": _hidden.size()})


func _draw() -> void:
	_draw_garden()
	var total := Logic.spot_count(tune)
	for i in total:
		_draw_spot(i)
	for spot: int in _critters:
		_draw_critter(spot)
	_draw_timer_bar()
	_draw_banner()


## Geschlossenes Wiesenband: gewellte Oberkante, sonst bis zum Bühnenboden.
func _hill_band(vp: Vector2, base_y: float, amp: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var steps := 40
	for i in steps + 1:
		var f := float(i) / float(steps)
		var wave := sin(f * PI * 2.3) * 0.62 + sin(f * PI * 5.1 + 1.2) * 0.38
		pts.append(Vector2(vp.x * f, base_y - amp * wave))
	pts.append(Vector2(vp.x, vp.y))
	pts.append(Vector2(0.0, vp.y))
	return pts


func _draw_garden() -> void:
	var vp := view_size
	draw_rect(Rect2(Vector2.ZERO, vp), SKY_BOTTOM)
	for i in 24:
		var f := float(i) / 23.0
		draw_rect(
			Rect2(0.0, vp.y * 0.4 * f, vp.x, vp.y * 0.4 / 23.0 + 1.0), SKY_TOP.lerp(SKY_BOTTOM, f)
		)
	# Hügel + Wiese. Der Hügelrücken ist eine durchgehende Wellenkante statt
	# zweier Kreise — die ließen in breiten Bühnen eine Himmelslücke stehen.
	# Der Horizont hängt an der OBERSTEN Versteckreihe, damit kein Versteck
	# im Himmel steht (das passiert sonst in beiden Orientierungen).
	var horizon := clampf(spot_center(0).y - _cell_size().y * 0.45, vp.y * 0.16, vp.y * 0.46)
	draw_colored_polygon(_hill_band(vp, horizon, vp.y * 0.045), Color(0.63, 0.85, 0.58))
	draw_colored_polygon(_hill_band(vp, horizon + vp.y * 0.06, vp.y * 0.028), GRASS)
	for i in 18:
		var gx := vp.x * (0.02 + 0.055 * i)
		var gy := horizon + vp.y * (0.11 + 0.03 * ((i * 7) % 5))
		draw_line(Vector2(gx, gy), Vector2(gx + 4.0, gy - 12.0), Color(0.44, 0.7, 0.4, 0.7), 2.0)
	# Sonne
	draw_circle(
		Vector2(vp.x * 0.86, minf(vp.y * 0.09, horizon * 0.5)),
		maxf(18.0, minf(vp.x, vp.y) * 0.055),
		Color(1.0, 0.9, 0.55, 0.85)
	)


func _draw_spot(spot: int) -> void:
	var center := spot_center(spot)
	var cell := _cell_size()
	var r := minf(cell.x, cell.y) * 0.38
	var wobble := 0.0
	if spot < _shake.size() and _shake[spot] > 0.0:
		wobble = sin(_shake[spot] * 36.0) * 0.12 * maxf(0.0, _shake[spot] / 0.35)
	else:
		wobble = sin(elapsed * 1.1 + spot * 1.7) * 0.015
	var off := Vector2(wobble * r, 0.0)
	# Schatten
	draw_circle(center + Vector2(0.0, r * 0.85), r * 0.9, Color(0.32, 0.42, 0.3, 0.22))
	match spot % 3:
		0:
			_draw_bush(center + off, r)
		1:
			_draw_crate(center + off, r)
		_:
			_draw_pot(center + off, r)


func _draw_bush(center: Vector2, r: float) -> void:
	draw_circle(center + Vector2(-r * 0.5, r * 0.1), r * 0.62, Color(0.35, 0.66, 0.38))
	draw_circle(center + Vector2(r * 0.5, r * 0.12), r * 0.58, Color(0.33, 0.62, 0.36))
	draw_circle(center + Vector2(0.0, -r * 0.18), r * 0.78, Color(0.4, 0.72, 0.42))
	var petals: Array[Color] = [
		Color(1.0, 0.61, 0.74), Color(1.0, 0.82, 0.4), Color(1.0, 0.96, 0.89)
	]
	var offsets := [Vector2(-0.35, 0.3), Vector2(0.15, 0.44), Vector2(0.55, 0.1)]
	for i in petals.size():
		var o: Vector2 = offsets[i]
		draw_circle(center + Vector2(o.x * r, -o.y * r), r * 0.12, petals[i])


func _draw_crate(center: Vector2, r: float) -> void:
	var box := Rect2(center - Vector2(r * 0.78, r * 0.6), Vector2(r * 1.56, r * 1.2))
	draw_rect(box, Color(0.78, 0.61, 0.42))
	draw_rect(box, Color(0.55, 0.4, 0.26), false, 3.0)
	draw_rect(
		Rect2(center - Vector2(r * 0.88, r * 0.78), Vector2(r * 1.76, r * 0.22)),
		Color(0.88, 0.73, 0.54)
	)
	draw_line(box.position, box.position + box.size, Color(0.6, 0.45, 0.3, 0.6), 2.0)


func _draw_pot(center: Vector2, r: float) -> void:
	draw_circle(center - Vector2(0.0, r * 0.42), r * 0.6, Color(0.45, 0.76, 0.42))
	var pts := PackedVector2Array(
		[
			center + Vector2(-r * 0.6, -r * 0.1),
			center + Vector2(r * 0.6, -r * 0.1),
			center + Vector2(r * 0.42, r * 0.72),
			center + Vector2(-r * 0.42, r * 0.72),
		]
	)
	draw_colored_polygon(pts, Color(0.85, 0.53, 0.41))
	draw_rect(
		Rect2(center - Vector2(r * 0.66, r * 0.22), Vector2(r * 1.32, r * 0.2)),
		Color(0.92, 0.62, 0.48)
	)


func _draw_critter(spot: int) -> void:
	var critter: Dictionary = _critters[spot]
	var center := spot_center(spot)
	var cell := _cell_size()
	var r := minf(cell.x, cell.y) * 0.38
	var color: Color = CRITTER_COLORS[int(critter["color"])]
	var rise := 0.0
	if bool(critter["found"]):
		rise = 1.25
	elif float(critter["peek_t"]) > 0.0:
		var k := sin(
			PI * maxf(0.0, 1.0 - float(critter["peek_t"]) / float(tune["PEEK_DURATION_SEC"]))
		)
		rise = 0.15 + k * 0.95
	else:
		return
	var pos := center - Vector2(0.0, r * rise)
	var br := r * 0.4
	# Ohren
	for side in [-1.0, 1.0]:
		draw_circle(pos + Vector2(side * br * 0.45, -br * 1.25), br * 0.26, color)
	draw_circle(pos, br, color)
	draw_circle(pos + Vector2(-br * 0.36, -br * 0.1), br * 0.12, Color(0.19, 0.15, 0.24))
	draw_circle(pos + Vector2(br * 0.36, -br * 0.1), br * 0.12, Color(0.19, 0.15, 0.24))
	draw_circle(pos + Vector2(0.0, br * 0.16), br * 0.1, Color(1.0, 0.48, 0.66))
	if bool(critter["found"]):
		draw_arc(
			pos + Vector2(0.0, br * 0.2), br * 0.3, 0.35, PI - 0.35, 12, Color(0.3, 0.2, 0.25), 2.5
		)


func _draw_timer_bar() -> void:
	var frac := maxf(0.0, 1.0 - wave_t / maxf(0.001, wave_sec))
	var w := view_size.x * 0.72
	var x := (view_size.x - w) * 0.5
	var y := view_size.y * (0.13 if landscape else 0.115)
	draw_rect(Rect2(x, y, w, 12.0), Color(1.0, 1.0, 1.0, 0.5), true)
	var col := Color(0.96, 0.55, 0.43) if frac < 0.3 else Color(0.35, 0.79, 0.73)
	draw_rect(Rect2(x, y, w * frac, 12.0), col, true)
	draw_rect(Rect2(x, y, w, 12.0), Color(0.35, 0.3, 0.3, 0.35), false, 2.0)


func _draw_banner() -> void:
	if _banner_t <= 0.0 or _banner.is_empty():
		return
	var font := ThemeService.font(800)
	var alpha := clampf(_banner_t * 1.4, 0.0, 1.0)
	draw_string(
		font,
		Vector2(view_size.x * 0.5 - 190.0, view_size.y * 0.36),
		_banner,
		HORIZONTAL_ALIGNMENT_CENTER,
		380.0,
		32,
		Color(0.32, 0.24, 0.28, alpha)
	)
