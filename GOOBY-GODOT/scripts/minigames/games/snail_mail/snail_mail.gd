extends MinigameBase
## Schneckenpost (snailMail) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## SnailMailLogic (zahlengleich zum Web): Weg vom Briefkasten zum leuchtenden
## Haus MALEN, danach kriecht die Postschnecke ihn ab. Pfütze = 2 s
## Schneckenhaus + kein Trocken-Bonus, Blumen +1. Zustellung +4 (+2 trocken).
##
## 2D (Web war ohnehin ein flaches Garten-Diorama): der Garten ist eine reine
## xy-Ebene, jede Weltkoordinate der Logik bleibt 1:1 erhalten.

const Logic := preload("res://scripts/minigames/games/snail_mail/snail_mail_logic.gd")

## Der gezeichnete Strich wird erst ab dieser Pixel-Distanz weiter abgetastet.
const INPUT_PX_STEP := 5.0
## Entwurfs-Kurzkante — Pixelmaße der Bedienleiste skalieren damit.
const DESIGN_SHORT := 390.0

var tune: Dictionary = {}
var rng: GoobyRng
var score := 0
var deliveries := 0
var splashes := 0
var flowers_total := 0
var elapsed := 0.0
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

var _level: Dictionary = {}
var _path: Dictionary = {}
var _raw: Array = []
var _drawing := false
var _phase := "draw"
var _arc := 0.0
var _retreat := 0.0
var _beat := 0.0
var _wet := false
var _picked: Array[int] = []
var _snail := {"x": 0.0, "y": -2.35, "angle": 1.5707963267948966}
var _ui := 1.0
var _time_label: Label
var _stat_label: Label
var _hint_label: Label
var _banner := ""
var _banner_t := 0.0


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = Logic.apply_difficulty(Logic.SNAIL, ctx.difficulty)
	rng = ctx.rng()
	_next_level()
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
	_layout_hud()
	queue_redraw()


## Bedienleiste in Entwurfspixeln, mit _ui skaliert (sonst Krümelschrift).
func _layout_hud() -> void:
	if _time_label == null:
		return
	var pad := 14.0 * _ui
	_time_label.position = Vector2(pad, 8.0 * _ui)
	_time_label.add_theme_font_size_override("font_size", int(26.0 * _ui))
	_stat_label.position = Vector2(pad, 44.0 * _ui)
	_stat_label.add_theme_font_size_override("font_size", int(17.0 * _ui))
	_hint_label.add_theme_font_size_override("font_size", int(15.0 * _ui))
	# Der Hinweis ist zweizeilig — genug Luft nach unten lassen.
	_hint_label.position = Vector2(pad, view_size.y - 64.0 * _ui)
	_hint_label.size = Vector2(maxf(120.0, view_size.x - pad * 2.0), 56.0 * _ui)


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	elapsed += delta
	_banner_t = maxf(0.0, _banner_t - delta)
	if not bool(tune["ENDLESS"]) and elapsed >= float(tune["DURATION_SEC"]):
		_finish()
		return
	match _phase:
		"retreat":
			_retreat = maxf(0.0, _retreat - delta)
			if _retreat <= 0.0:
				_phase = "follow"
		"follow":
			_follow(delta)
		"beat":
			_beat = maxf(0.0, _beat - delta)
			if _beat <= 0.0:
				_next_level()
	_update_labels()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished or _phase != "draw":
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_begin_stroke(world_from(event.position))
		elif _drawing:
			_drawing = false
			_commit_stroke()
	elif event is InputEventScreenDrag and _drawing:
		_extend_stroke(event.position)


## Weltkoordinate → Bildschirmpixel.
func project(wx: float, wy: float) -> Vector2:
	var s := _world_scale()
	return Vector2(view_size.x * 0.5 + wx * s, _field_center_y() - wy * s)


## Bildschirmpixel → Weltkoordinate (die EINE Eingabe-Grenze).
func world_from(px: Vector2) -> Dictionary:
	var s := _world_scale()
	return {"x": (px.x - view_size.x * 0.5) / s, "y": (_field_center_y() - px.y) / s}


func _world_scale() -> float:
	var half_w := float(tune["FIELD_HALF_W"])
	var span_y := float(tune["FIELD_Y_MAX"]) - float(tune["FIELD_Y_MIN"])
	return minf(view_size.x * 0.94 / (half_w * 2.0), view_size.y * 0.82 / span_y)


func _field_center_y() -> float:
	return view_size.y * (0.54 if not landscape else 0.52)


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	add_child(_time_label)
	_stat_label = Label.new()
	_stat_label.theme_type_variation = &"CaptionLabel"
	add_child(_stat_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.snailMail.hint")
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


func _next_level() -> void:
	_level = Logic.generate_level(rng, deliveries, tune)
	_path = {}
	_raw = []
	_arc = 0.0
	_wet = false
	_picked = []
	_phase = "draw"
	var post: Dictionary = _level["post"]
	_snail = {"x": float(post["x"]), "y": float(post["y"]), "angle": PI * 0.5}


func _begin_stroke(world: Dictionary) -> void:
	if not Logic.starts_at_post(world, tune):
		AudioDirector.try_play(self, "ui_error")
		_set_banner(I18nService.t("mg.snailMail.start_at_post"))
		return
	_drawing = true
	_raw = [world]
	AudioDirector.try_play(self, "ui_chip", 1.3)


func _extend_stroke(px: Vector2) -> void:
	if _raw.size() >= int(tune["MAX_INPUT_POINTS"]):
		return
	var world := world_from(px)
	var last: Dictionary = _raw[_raw.size() - 1]
	var dx := float(world["x"]) - float(last["x"])
	var dy := float(world["y"]) - float(last["y"])
	if sqrt(dx * dx + dy * dy) * _world_scale() < INPUT_PX_STEP:
		return
	_raw.append(world)


func _commit_stroke() -> void:
	var path := Logic.smooth_path(_raw, tune)
	if path.is_empty():
		_raw = []
		return
	if Logic.end_house(path, _level, tune) != int(_level["targetIdx"]):
		AudioDirector.try_play(self, "ui_error")
		_set_banner(I18nService.t("mg.snailMail.miss_door"))
		_raw = []
		return
	_path = path
	_arc = 0.0
	_phase = "follow"
	AudioDirector.try_play(self, "ui_confirm")


func _follow(delta: float) -> void:
	var length := float(_path["length"])
	_arc = Logic.advance_arc(_arc, delta, length, tune)
	_snail = Logic.follow_at(_path, _arc)
	var sx := float(_snail["x"])
	var sy := float(_snail["y"])
	if not _wet and Logic.puddle_hit_at(sx, sy, _level["puddles"], tune) >= 0:
		_splash()
		return
	_pick_flowers(sx, sy)
	if _arc >= length:
		_deliver()


func _pick_flowers(sx: float, sy: float) -> void:
	var flowers: Array = _level["flowers"]
	var radius := float(tune["FLOWER_PICK_RADIUS"])
	for i in flowers.size():
		if _picked.has(i):
			continue
		var f: Dictionary = flowers[i]
		var dx := sx - float(f["x"])
		var dy := sy - float(f["y"])
		if sqrt(dx * dx + dy * dy) > radius:
			continue
		_picked.append(i)
		AudioDirector.try_play(self, "mg_good", 1.2)
		if ctx.juice != null:
			ctx.juice.float_text(
				project(float(f["x"]), float(f["y"])),
				"+%d" % int(tune["FLOWER_PTS"]),
				Color(1.0, 0.72, 0.85)
			)


func _splash() -> void:
	_wet = true
	_phase = "retreat"
	_retreat = float(tune["RETREAT_SEC"])
	AudioDirector.try_play(self, "mg_spill")
	if ctx.juice != null:
		ctx.juice.shake(0.3)
	_set_banner(I18nService.t("mg.snailMail.splash"))


func _deliver() -> void:
	var points := Logic.delivery_points(_wet, _picked.size(), tune)
	score = Logic.apply_score(score, points)
	deliveries += 1
	flowers_total += _picked.size()
	if _wet:
		splashes += 1
	ctx.report_score(score, points)
	AudioDirector.try_play(self, "mg_win" if not _wet else "mg_good")
	var houses: Array = _level["houses"]
	var door := Logic.door_of(houses[int(_level["targetIdx"])], tune)
	if ctx.juice != null:
		ctx.juice.float_text(
			project(float(door["x"]), float(door["y"])),
			"+%d" % points,
			Color(0.55, 1.0, 0.7) if not _wet else Color(0.75, 0.86, 1.0)
		)
		ctx.juice.bloom_pulse(0.9 if not _wet else 0.3)
	_set_banner(
		I18nService.t("mg.snailMail.delivered" if not _wet else "mg.snailMail.delivered_wet")
	)
	if Logic.endless_should_end(splashes, tune):
		_finish()
		return
	_phase = "beat"
	_beat = float(tune["ROUND_BEAT_SEC"])


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	(
		ctx
		. report_end(
			{
				"score": score,
				"deliveries": deliveries,
				"splashes": splashes,
				"flowers": flowers_total,
			}
		)
	)


func _set_banner(text: String) -> void:
	_banner = text
	_banner_t = 1.4


func _update_labels() -> void:
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.snailMail.splash_count", {"n": splashes, "max": int(tune["ENDLESS_MAX_SPLASHES"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - elapsed)))
		_time_label.text = I18nService.t("mg.game.time", {"sec": left})
	_stat_label.text = I18nService.t(
		"mg.snailMail.stats", {"n": deliveries, "flowers": flowers_total}
	)


func _draw() -> void:
	_draw_garden()
	for p: Dictionary in _level["puddles"]:
		_draw_puddle(p)
	_draw_flowers()
	_draw_houses()
	_draw_post()
	_draw_path()
	_draw_snail()
	_draw_banner()


func _draw_garden() -> void:
	var s := _world_scale()
	var half_w := float(tune["FIELD_HALF_W"])
	var top_left := project(-half_w, float(tune["FIELD_Y_MAX"]))
	var bottom_right := project(half_w, float(tune["FIELD_Y_MIN"]))
	var field := Rect2(top_left, bottom_right - top_left)
	# Umgebender Rasen mit Mäh-Streifen (füllt beide Orientierungen)
	draw_rect(Rect2(Vector2.ZERO, view_size), Color(0.52, 0.74, 0.44))
	var stripe := maxf(24.0, s * 0.42)
	var stripes := int(ceil(view_size.y / stripe))
	for i in stripes:
		if i % 2 == 1:
			continue
		draw_rect(Rect2(0.0, i * stripe, view_size.x, stripe * 0.5), Color(0.56, 0.78, 0.47))
	_draw_surround(field, s)
	# Spielfeld als heller Garten-Teppich mit Beet-Einfassung
	draw_rect(field.grow(s * 0.16), Color(0.46, 0.34, 0.24, 0.55))
	draw_rect(field, Color(0.68, 0.86, 0.55))
	draw_rect(field, Color(0.38, 0.58, 0.32, 0.85), false, 3.0)
	for i in 54:
		var gx := -half_w + fposmod(i * 0.4327, half_w * 2.0)
		var gy := float(tune["FIELD_Y_MIN"]) + fposmod(i * 0.7919, 5.6)
		var base := project(gx, gy)
		var tuft := s * 0.09
		draw_line(base, base + Vector2(-tuft * 0.4, -tuft), Color(0.53, 0.74, 0.43, 0.7), 2.0)
		draw_line(base, base + Vector2(tuft * 0.4, -tuft), Color(0.53, 0.74, 0.43, 0.7), 2.0)


## Deko außerhalb des Spielfelds: Baumkronen von oben + Kieselsteine.
func _draw_surround(field: Rect2, s: float) -> void:
	var spots: Array[Vector3] = [
		Vector3(0.09, 0.09, 1.0),
		Vector3(0.9, 0.14, 0.78),
		Vector3(0.14, 0.9, 0.86),
		Vector3(0.87, 0.88, 1.05),
		Vector3(0.5, 0.03, 0.62),
		Vector3(0.5, 0.97, 0.7),
	]
	for spot: Vector3 in spots:
		var c := Vector2(view_size.x * spot.x, view_size.y * spot.y)
		if field.grow(s * 0.3).has_point(c):
			continue
		var r := s * 0.42 * spot.z
		draw_circle(c + Vector2(r * 0.12, r * 0.16), r, Color(0.24, 0.4, 0.2, 0.3))
		draw_circle(c, r, Color(0.36, 0.6, 0.31))
		draw_circle(c - Vector2(r * 0.22, r * 0.24), r * 0.52, Color(0.46, 0.71, 0.38))
	for i in 14:
		var p := Vector2(fposmod(i * 137.31, view_size.x), fposmod(i * 271.77 + 43.0, view_size.y))
		if field.grow(s * 0.2).has_point(p):
			continue
		draw_circle(p, s * 0.05, Color(0.78, 0.79, 0.74, 0.6))


func _draw_puddle(p: Dictionary) -> void:
	var s := _world_scale()
	var center := project(float(p["x"]), float(p["y"]))
	var r := float(p["r"]) * s
	# Leicht unrunde Lache: y gestaucht, Rand wellig (Sticker-Look)
	var blob := PackedVector2Array()
	var rim := PackedVector2Array()
	var phase := float(p["x"]) * 3.1 + float(p["y"]) * 1.7
	for i in 26:
		var a := TAU * i / 26.0
		var wob := 1.0 + 0.07 * sin(a * 3.0 + phase) + 0.04 * sin(a * 5.0 - phase)
		var pt := center + Vector2(cos(a) * r * wob, sin(a) * r * 0.74 * wob)
		blob.append(pt)
		rim.append(center + (pt - center) * 1.1)
	rim.append(rim[0])
	draw_colored_polygon(rim, Color(0.44, 0.56, 0.7, 0.3))
	draw_colored_polygon(blob, Color(0.4, 0.63, 0.84, 0.92))
	draw_polyline(rim, Color(0.28, 0.46, 0.66, 0.6), 2.0)
	draw_arc(
		center + Vector2(-r * 0.24, -r * 0.2),
		r * 0.34,
		PI * 0.85,
		PI * 1.75,
		12,
		Color(0.9, 0.96, 1.0, 0.8),
		3.0
	)


func _draw_flowers() -> void:
	var s := _world_scale()
	var flowers: Array = _level["flowers"]
	for i in flowers.size():
		if _picked.has(i):
			continue
		var f: Dictionary = flowers[i]
		var c := project(float(f["x"]), float(f["y"]))
		draw_line(c, c + Vector2(0.0, s * 0.14), Color(0.36, 0.6, 0.3), 3.0)
		for k in 5:
			var a := TAU * k / 5.0 + elapsed * 0.6
			draw_circle(c + Vector2(cos(a), sin(a)) * s * 0.07, s * 0.055, Color(1.0, 0.7, 0.84))
		draw_circle(c, s * 0.05, Color(1.0, 0.88, 0.4))


func _draw_houses() -> void:
	var s := _world_scale()
	var houses: Array = _level["houses"]
	var target := int(_level["targetIdx"])
	for i in houses.size():
		var h: Dictionary = houses[i]
		var c := project(float(h["x"]), float(h["y"]))
		var door := Logic.door_of(h, tune)
		var dpos := project(float(door["x"]), float(door["y"]))
		var glow := 0.5 + 0.5 * sin(elapsed * 3.2)
		if i == target:
			draw_circle(dpos, s * 0.6 * (0.9 + 0.14 * glow), Color(1.0, 0.92, 0.45, 0.2))
			draw_arc(
				dpos,
				float(tune["DELIVER_RADIUS"]) * s,
				0.0,
				TAU,
				30,
				Color(1.0, 0.86, 0.32, 0.8),
				3.0
			)
		draw_circle(c + Vector2(s * 0.06, s * 0.1), s * 0.4, Color(0.3, 0.45, 0.26, 0.28))
		if str(h.get("kind", "house")) == "burrow":
			draw_circle(c + Vector2(0.0, -s * 0.02), s * 0.36, Color(0.52, 0.4, 0.3))
			draw_circle(c + Vector2(0.0, s * 0.06), s * 0.24, Color(0.24, 0.17, 0.14))
			draw_arc(c, s * 0.36, PI, TAU, 18, Color(0.4, 0.55, 0.32), 5.0)
			for k in 6:
				var a := PI + PI * (k + 0.5) / 6.0
				draw_circle(
					c + Vector2(cos(a), sin(a)) * s * 0.36, s * 0.06, Color(0.45, 0.63, 0.36)
				)
		else:
			var w := s * 0.34
			var hgt := s * 0.36
			var body := Rect2(c + Vector2(-w, -hgt * 0.4), Vector2(w * 2.0, hgt))
			draw_rect(body, Color(0.98, 0.93, 0.84))
			draw_rect(body, Color(0.72, 0.6, 0.5, 0.8), false, 2.0)
			draw_colored_polygon(
				PackedVector2Array(
					[
						c + Vector2(-w * 1.2, -hgt * 0.4),
						c + Vector2(w * 1.2, -hgt * 0.4),
						c + Vector2(0.0, -hgt * 1.15),
					]
				),
				Color(0.85, 0.45, 0.36) if i != target else Color(0.93, 0.55, 0.34)
			)
			for side: float in [-0.62, 0.62]:
				var win := Rect2(
					c + Vector2(w * side - w * 0.2, -hgt * 0.16), Vector2(w * 0.4, hgt * 0.3)
				)
				draw_rect(win, Color(0.63, 0.83, 0.94))
				draw_rect(win, Color(0.72, 0.6, 0.5, 0.8), false, 1.5)
			draw_rect(
				Rect2(c + Vector2(-w * 0.28, hgt * 0.18), Vector2(w * 0.56, hgt * 0.42)),
				Color(0.6, 0.4, 0.3)
			)
			draw_circle(c + Vector2(w * 0.18, hgt * 0.4), s * 0.02, Color(0.95, 0.85, 0.4))
		if i == target:
			# Hüpfender Zielpfeil wie im Web
			var tip := c + Vector2(0.0, -s * (0.78 + 0.08 * glow))
			draw_colored_polygon(
				PackedVector2Array(
					[
						tip + Vector2(-s * 0.14, -s * 0.2),
						tip + Vector2(s * 0.14, -s * 0.2),
						tip,
					]
				),
				Color(1.0, 0.82, 0.3)
			)


func _draw_post() -> void:
	var s := _world_scale()
	var post: Dictionary = _level["post"]
	var c := project(float(post["x"]), float(post["y"]))
	if _phase == "draw" and not _drawing:
		draw_arc(
			c,
			float(tune["START_RADIUS"]) * s,
			0.0,
			TAU,
			30,
			Color(1.0, 0.98, 0.8, 0.35 + 0.2 * sin(elapsed * 3.0)),
			2.0
		)
	draw_line(c, c + Vector2(0.0, -s * 0.34), Color(0.55, 0.4, 0.28), maxf(3.0, s * 0.06))
	var box := Rect2(c + Vector2(-s * 0.16, -s * 0.62), Vector2(s * 0.32, s * 0.28))
	draw_rect(box, Color(0.36, 0.6, 0.86))
	draw_rect(box, Color(0.2, 0.36, 0.6), false, 2.0)
	draw_rect(
		Rect2(c + Vector2(-s * 0.1, -s * 0.53), Vector2(s * 0.2, s * 0.04)), Color(0.95, 0.97, 1.0)
	)


func _draw_path() -> void:
	var pts: Array = []
	if not _path.is_empty():
		pts = _path["pts"]
	elif _drawing and _raw.size() >= 2:
		var preview := Logic.smooth_path(_raw, tune)
		if not preview.is_empty():
			pts = preview["pts"]
	if pts.size() < 2:
		return
	var line := PackedVector2Array()
	for pt: Dictionary in pts:
		line.append(project(float(pt["x"]), float(pt["y"])))
	draw_polyline(line, Color(1.0, 0.98, 0.86, 0.55), 9.0)
	draw_polyline(line, Color(0.98, 0.78, 0.42, 0.85), 4.0)


func _draw_snail() -> void:
	var s := _world_scale()
	var c := project(float(_snail["x"]), float(_snail["y"]))
	var hidden := _phase == "retreat"
	var shell_r := s * 0.24
	var angle := float(_snail["angle"])
	var fwd := Vector2(cos(angle), -sin(angle))
	draw_circle(
		c + Vector2(shell_r * 0.2, shell_r * 0.3), shell_r * 1.05, Color(0.3, 0.45, 0.26, 0.25)
	)
	if not hidden:
		# Fuß
		draw_circle(c - fwd * shell_r * 0.5, shell_r * 0.62, Color(0.98, 0.86, 0.72))
		draw_circle(c + fwd * shell_r * 0.85, shell_r * 0.5, Color(0.98, 0.86, 0.72))
		for side: float in [-0.4, 0.4]:
			var eye: Vector2 = c + fwd * shell_r * 1.35 + fwd.orthogonal() * shell_r * side
			draw_line(c + fwd * shell_r * 0.8, eye, Color(0.98, 0.86, 0.72), maxf(2.0, s * 0.02))
			draw_circle(eye, shell_r * 0.16, Color(0.25, 0.18, 0.16))
	# Schneckenhaus
	draw_circle(c, shell_r, Color(0.86, 0.6, 0.35))
	draw_arc(c, shell_r, 0.0, TAU, 26, Color(0.58, 0.36, 0.2), 2.0)
	draw_arc(c, shell_r * 0.68, 0.0, TAU * 0.85, 22, Color(0.66, 0.42, 0.24), 3.0)
	draw_arc(c, shell_r * 0.36, 1.2, TAU * 0.9, 16, Color(0.66, 0.42, 0.24), 2.5)
	# Briefumschlag auf dem Haus
	if _phase != "beat":
		var env := Rect2(
			c + Vector2(-shell_r * 0.4, -shell_r * 1.2), Vector2(shell_r * 0.8, shell_r * 0.5)
		)
		draw_rect(env, Color(1.0, 0.98, 0.9))
		draw_rect(env, Color(0.7, 0.6, 0.5), false, 1.5)
	if hidden:
		var zzz := ThemeService.font(700)
		draw_string(
			zzz,
			c + Vector2(shell_r, -shell_r * 1.4),
			"zZ",
			HORIZONTAL_ALIGNMENT_LEFT,
			-1,
			18,
			Color(0.4, 0.45, 0.6, 0.85)
		)


func _draw_banner() -> void:
	if _banner_t <= 0.0 or _banner.is_empty():
		return
	var font := ThemeService.font(800)
	var alpha := clampf(_banner_t * 1.4, 0.0, 1.0)
	var w := minf(view_size.x - 24.0, 380.0 * _ui)
	draw_string(
		font,
		Vector2((view_size.x - w) * 0.5, view_size.y * 0.11),
		_banner,
		HORIZONTAL_ALIGNMENT_CENTER,
		w,
		maxi(16, int(24.0 * _ui)),
		Color(0.35, 0.28, 0.2, alpha)
	)
