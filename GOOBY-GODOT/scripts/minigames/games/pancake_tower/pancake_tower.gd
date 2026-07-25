extends MinigameBase
## Pfannkuchenturm (pancakeTower) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## PancakeTowerLogic (zahlengleich zum Web): Pendel-Kadenz, Schnitt-Mathematik,
## Perfect-Fenster (+2 & +10 % Breite), jede 5. Lage Topping (+4), Ende bei
## Breite < 20 % oder 40 Lagen, Turmschwingung ab Lage 8.
## Steuerung: Tippen lässt den Pfannkuchen fallen. Optik: Küchen-Pastell,
## echte Turmrotation um die Basis, JuiceKit (Perfect: Bloom + Hitfreeze,
## Schnitt: Shake) und AudioDirector-SFX.

## Sichtbare Weltbreite (Web-Kamera rahmt ≈ 2.9 Einheiten bei 390 px).
const VIEW_UNITS_X := 2.9
## Höhe der Stapelspitze auf dem Schirm (Anteil von unten).
const TOP_ANCHOR := 0.6
## Abwurfhöhe des Pendel-Pfannkuchens über der Stapelspitze (Einheiten).
const DROP_HEIGHT := 1.5

## Bildschirmhöhe der Tellerkante (Weltnullpunkt) als Anteil von oben.
const GROUND_FRAC := 0.88
const PLATE_COLOR := Color(0.95, 0.96, 1.0)
const PLATE_RIM := Color(0.6, 0.64, 0.76)
const CAKE_COLOR := Color(0.95, 0.76, 0.45)
const CAKE_EDGE := Color(0.78, 0.55, 0.28)
const BUTTER := Color(1.0, 0.85, 0.36)
const BERRY := Color(0.93, 0.36, 0.48)

var tune: Dictionary = {}
var rng: GoobyRng
var layers: Array[Dictionary] = []
var stack := {"center": 0.0, "width": 1.5}
var bonus_points := 0
var perfects := 0
var wobble: Dictionary = {}
var slide_t := 0.0
var slide_phase := 0.0
var falling := false
var fall_x := 0.0
var fall_y := 0.0
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

var _crumbs: Array[Dictionary] = []
var _flash := 0.0
var _flash_text := ""
var _cam_bottom := 0.0
var _layers_label: Label
var _width_label: Label
var _hint_label: Label


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = PancakeTowerLogic.apply_difficulty(PancakeTowerLogic.PANCAKE, ctx.difficulty)
	rng = ctx.rng()
	stack = {"center": 0.0, "width": float(tune["BASE_WIDTH"])}
	wobble = PancakeTowerLogic.initial_wobble_state()
	slide_phase = rng.next()
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
	if _layers_label != null:
		_layers_label.position = Vector2(16.0, 10.0)
		_width_label.position = Vector2(16.0, 48.0)
		_hint_label.position = Vector2(view_size.x * 0.5 - 150.0, view_size.y - 56.0)
		_hint_label.size = Vector2(300.0, 40.0)
	queue_redraw()


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	_flash = maxf(0.0, _flash - delta)
	wobble = PancakeTowerLogic.step_wobble(wobble, delta, layers.size(), tune)
	_step_crumbs(delta)
	if falling:
		fall_y -= float(tune["FALL_SPEED"]) * delta
		if fall_y <= _stack_height():
			_land()
	else:
		slide_t += delta
	_update_labels()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished or falling:
		return
	if event is InputEventScreenTouch and event.pressed:
		_drop()


## Aktuelle Turmhöhe in Welteinheiten.
func _stack_height() -> float:
	return layers.size() * float(tune["LAYER_HEIGHT"])


## 1-basierte Nummer des Pfannkuchens, der gerade pendelt.
func _current_index() -> int:
	return layers.size() + 1


func _build_hud() -> void:
	_layers_label = Label.new()
	_layers_label.theme_type_variation = &"HeadlineLabel"
	add_child(_layers_label)
	_width_label = Label.new()
	_width_label.theme_type_variation = &"CaptionLabel"
	add_child(_width_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.pancakeTower.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint_label)
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _drop() -> void:
	falling = true
	fall_x = PancakeTowerLogic.slide_x(slide_t, _current_index(), slide_phase, tune)
	fall_y = _stack_height() + DROP_HEIGHT
	AudioDirector.try_play(self, "mg_good", 0.9)


func _land() -> void:
	falling = false
	var index := _current_index()
	var topping := PancakeTowerLogic.is_topping_layer(index, tune)
	# Der Turm schwankt: der Welt-Abwurf wird in Turmkoordinaten zurückgerechnet.
	var local_x := PancakeTowerLogic.wobble_local_x(fall_x, _stack_height(), float(wobble["angle"]))
	var drop := PancakeTowerLogic.resolve_drop(stack, local_x, topping, tune)
	var pos := _to_screen(fall_x, _stack_height())
	if not bool(drop["landed"]):
		_spawn_crumb(local_x, _stack_height(), float(stack["width"]))
		_flash_text = I18nService.t("mg.pancakeTower.topple")
		_flash = 1.0
		AudioDirector.try_play(self, "mg_spill")
		if ctx.juice != null:
			ctx.juice.shake(0.45)
			ctx.juice.hit_freeze(80)
		_finish()
		return
	if not (drop["cut"] as Dictionary).is_empty():
		var cut: Dictionary = drop["cut"]
		_spawn_crumb(float(cut["center"]), _stack_height(), float(cut["size"]))
	bonus_points += int(drop["points"])
	(
		layers
		. append(
			{
				"center": float(drop["center"]),
				"width": float(drop["width"]),
				"topping": topping,
				"index": index,
			}
		)
	)
	stack = {"center": float(drop["center"]), "width": float(drop["width"])}
	_celebrate(drop, topping, pos)
	slide_t = 0.0
	slide_phase = rng.next()
	ctx.report_score(
		PancakeTowerLogic.tower_score(layers.size(), bonus_points, tune), int(drop["points"]) + 2
	)
	if PancakeTowerLogic.is_tower_done(float(stack["width"]), layers.size(), tune):
		_finish()


func _celebrate(drop: Dictionary, topping: bool, pos: Vector2) -> void:
	if bool(drop["perfect"]):
		perfects += 1
		wobble = PancakeTowerLogic.damp_wobble(wobble, tune, layers.size())
		# Nur der Fließtext am Stapel — das große Band bleibt dem Spielende
		# vorbehalten, sonst steht die Meldung doppelt im Bild.
		AudioDirector.try_play(self, "mg_perfect", 1.0 + 0.05 * minf(perfects, 8.0))
		if ctx.juice != null:
			ctx.juice.hit_freeze(45)
			ctx.juice.bloom_pulse(0.7)
			ctx.juice.float_text(
				pos, I18nService.t("mg.pancakeTower.perfect"), Color(1.0, 0.72, 0.2)
			)
	elif topping:
		AudioDirector.try_play(self, "mg_golden")
		if ctx.juice != null:
			ctx.juice.bloom_pulse(0.5)
			ctx.juice.float_text(pos, "+%d" % int(drop["points"]), Color(0.93, 0.36, 0.48))
	else:
		AudioDirector.try_play(self, "mg_good")
		if ctx.juice != null:
			ctx.juice.shake(0.12)


func _spawn_crumb(center: float, height: float, width: float) -> void:
	_crumbs.append({"x": center, "y": height, "w": width, "vy": -0.4, "age": 0.0})


func _step_crumbs(delta: float) -> void:
	var kept: Array[Dictionary] = []
	for crumb in _crumbs:
		crumb["age"] = float(crumb["age"]) + delta
		crumb["vy"] = float(crumb["vy"]) - 9.0 * delta
		crumb["y"] = float(crumb["y"]) + float(crumb["vy"]) * delta
		if not PancakeTowerLogic.is_fallen_expired(float(crumb["age"]), tune):
			kept.append(crumb)
	_crumbs = kept


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	(
		ctx
		. report_end(
			{
				"score": PancakeTowerLogic.tower_score(layers.size(), bonus_points, tune),
				"layers": layers.size(),
				"perfects": perfects,
			}
		)
	)


func _update_labels() -> void:
	_layers_label.text = I18nService.t("mg.pancakeTower.layers", {"n": layers.size()})
	var pct := int(round(float(stack["width"]) / float(tune["BASE_WIDTH"]) * 100.0))
	_width_label.text = I18nService.t("mg.pancakeTower.width", {"pct": pct})


func _ppu() -> float:
	return view_size.x / VIEW_UNITS_X


## Turm-lokale Koordinaten → Bildschirmpixel (inkl. Schwingung + Kamera).
func _to_screen(world_x: float, world_y: float) -> Vector2:
	var ppu := _ppu()
	return Vector2(
		view_size.x * 0.5 + world_x * ppu, view_size.y * GROUND_FRAC - (world_y - _cam_bottom) * ppu
	)


func _tower_point(local_center: float, height: float) -> Vector2:
	var a := float(wobble["angle"])
	return _to_screen(
		local_center * cos(a) - height * sin(a), local_center * sin(a) + height * cos(a)
	)


func _draw() -> void:
	var ppu := _ppu()
	var visible_units := view_size.y / ppu
	_cam_bottom = maxf(0.0, _stack_height() - visible_units * TOP_ANCHOR)
	_draw_kitchen()
	_draw_plate()
	for layer in layers:
		_draw_layer(layer)
	for crumb in _crumbs:
		_draw_crumb(crumb)
	_draw_active()
	_draw_flash()


func _draw_kitchen() -> void:
	var vp := view_size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.99, 0.95, 0.89))
	# Warme Tapetenstreifen + Fensterlicht.
	for i in 10:
		var x := vp.x * i / 10.0
		draw_rect(Rect2(x, 0.0, vp.x / 20.0, vp.y), Color(0.97, 0.91, 0.83, 0.55))
	var win := Rect2(vp.x * 0.06, vp.y * 0.06, vp.x * 0.3, vp.y * 0.16)
	draw_rect(win, Color(0.83, 0.92, 0.97, 0.9))
	draw_rect(win, Color(0.86, 0.72, 0.56), false, 6.0)
	draw_line(
		Vector2(win.get_center().x, win.position.y),
		Vector2(win.get_center().x, win.end.y),
		Color(0.86, 0.72, 0.56),
		5.0
	)
	draw_line(
		Vector2(win.position.x, win.get_center().y),
		Vector2(win.end.x, win.get_center().y),
		Color(0.86, 0.72, 0.56),
		5.0
	)
	draw_rect(
		Rect2(win.position.x - 8.0, win.end.y, win.size.x + 16.0, 9.0), Color(0.9, 0.78, 0.62)
	)
	# Die Arbeitsplatte hängt am Weltnullpunkt und rutscht mit dem Turm weg.
	var counter := _to_screen(0.0, 0.0).y
	draw_rect(Rect2(0.0, counter, vp.x, vp.y - counter), Color(0.85, 0.72, 0.58))
	draw_rect(Rect2(0.0, counter, vp.x, 6.0), Color(0.92, 0.81, 0.68))


func _draw_plate() -> void:
	var base := _to_screen(0.0, 0.0)
	var ppu := _ppu()
	var w := float(tune["BASE_WIDTH"]) * 1.35 * ppu
	# Schatten, dann Teller-Fuß und -Spiegel; ohne Rand geht Weiß auf der
	# hellen Arbeitsplatte komplett unter.
	draw_rect(Rect2(base.x - w * 0.66, base.y + 10.0, w * 1.32, 14.0), Color(0.6, 0.48, 0.38, 0.5))
	draw_rect(Rect2(base.x - w * 0.66, base.y + 4.0, w * 1.32, 16.0), PLATE_COLOR)
	draw_rect(Rect2(base.x - w * 0.66, base.y + 4.0, w * 1.32, 16.0), PLATE_RIM, false, 2.5)
	draw_rect(Rect2(base.x - w * 0.52, base.y - 8.0, w * 1.04, 16.0), PLATE_COLOR)
	draw_rect(Rect2(base.x - w * 0.52, base.y - 8.0, w * 1.04, 16.0), PLATE_RIM, false, 2.5)


## Pfannkuchen-Silhouette: Rechteck mit halbrunden Enden (Stadion-Form) im
## Turm-Koordinatensystem, damit die Schwingung sie korrekt mitdreht.
func _pancake_outline(center: float, half: float, y0: float, h: float) -> PackedVector2Array:
	var r := minf(h * 0.5, half * 0.9)
	var cy := y0 + h * 0.5
	var pts := PackedVector2Array()
	for i in 9:
		var a := -PI * 0.5 + PI * float(i) / 8.0
		pts.append(_tower_point(center + half - r + cos(a) * r, cy + sin(a) * r))
	for i in 9:
		var a := PI * 0.5 + PI * float(i) / 8.0
		pts.append(_tower_point(center - half + r + cos(a) * r, cy + sin(a) * r))
	return pts


func _draw_layer(layer: Dictionary) -> void:
	var ppu := _ppu()
	var h := float(tune["LAYER_HEIGHT"])
	var idx := int(layer["index"])
	var y0 := (idx - 1) * h
	var center := float(layer["center"])
	var half := float(layer["width"]) * 0.5
	var outline := _pancake_outline(center, half, y0, h)
	draw_colored_polygon(
		outline, CAKE_COLOR if not bool(layer["topping"]) else Color(0.97, 0.8, 0.5)
	)
	draw_polyline(outline + PackedVector2Array([outline[0]]), CAKE_EDGE, 2.0)
	# Heller Streifen oben = frisch gebackene Oberseite.
	draw_line(
		_tower_point(center - half * 0.62, y0 + h * 0.72),
		_tower_point(center + half * 0.62, y0 + h * 0.72),
		Color(1.0, 0.9, 0.68, 0.7),
		maxf(2.0, h * ppu * 0.18)
	)
	if bool(layer["topping"]):
		var top := _tower_point(center, y0 + h)
		if idx % 10 == 0:
			draw_circle(top + Vector2(0.0, -7.0), maxf(4.0, half * ppu * 0.22), BERRY)
		else:
			var bw := maxf(8.0, half * ppu * 0.5)
			draw_rect(Rect2(top.x - bw * 0.5, top.y - 10.0, bw, 10.0), BUTTER)


func _draw_crumb(crumb: Dictionary) -> void:
	var ppu := _ppu()
	var pos := _to_screen(float(crumb["x"]), float(crumb["y"]))
	var w := maxf(4.0, float(crumb["w"]) * ppu)
	var fade := 1.0 - float(crumb["age"]) / float(tune["FALLEN_DESPAWN_SEC"])
	draw_rect(
		Rect2(pos.x - w * 0.5, pos.y, w, float(tune["LAYER_HEIGHT"]) * ppu),
		Color(CAKE_COLOR.r, CAKE_COLOR.g, CAKE_COLOR.b, clampf(fade, 0.0, 1.0))
	)


func _draw_active() -> void:
	var ppu := _ppu()
	var index := _current_index()
	var x := fall_x if falling else PancakeTowerLogic.slide_x(slide_t, index, slide_phase, tune)
	var y := fall_y if falling else _stack_height() + DROP_HEIGHT
	var half := float(stack["width"]) * 0.5
	var pos := _to_screen(x, y)
	var w := half * 2.0 * ppu
	var h := float(tune["LAYER_HEIGHT"]) * ppu
	# Zielhilfe: senkrechte Linie auf die Stapelspitze.
	var target := _tower_point(0.0, _stack_height())
	draw_line(
		Vector2(pos.x, pos.y + h), Vector2(pos.x, target.y), Color(0.95, 0.45, 0.66, 0.35), 2.0
	)
	var r := minf(h * 0.5, w * 0.45)
	var cake := PackedVector2Array()
	for i in 9:
		var a := -PI * 0.5 + PI * float(i) / 8.0
		cake.append(Vector2(pos.x + w * 0.5 - r + cos(a) * r, pos.y - h * 0.5 + sin(a) * r))
	for i in 9:
		var a := PI * 0.5 + PI * float(i) / 8.0
		cake.append(Vector2(pos.x - w * 0.5 + r + cos(a) * r, pos.y - h * 0.5 + sin(a) * r))
	draw_colored_polygon(cake, CAKE_COLOR)
	draw_polyline(cake + PackedVector2Array([cake[0]]), CAKE_EDGE, 2.0)
	draw_line(
		Vector2(pos.x - w * 0.31, pos.y - h * 0.72),
		Vector2(pos.x + w * 0.31, pos.y - h * 0.72),
		Color(1.0, 0.9, 0.68, 0.7),
		maxf(2.0, h * 0.18)
	)
	if PancakeTowerLogic.is_topping_layer(index, tune):
		draw_circle(Vector2(pos.x, pos.y - h - 6.0), 7.0, BERRY)
	_draw_gooby(Vector2(pos.x, pos.y - h - _gooby_radius() * 1.6))


func _gooby_radius() -> float:
	return maxf(20.0, view_size.x * 0.055)


func _draw_gooby(pos: Vector2) -> void:
	var r := _gooby_radius()
	draw_circle(pos + Vector2(-r * 0.5, -r * 1.05), r * 0.32, Color(0.98, 0.86, 0.6))
	draw_circle(pos + Vector2(r * 0.5, -r * 1.05), r * 0.32, Color(0.98, 0.86, 0.6))
	draw_circle(pos, r, Color(0.99, 0.9, 0.65))
	draw_circle(pos + Vector2(-r * 0.32, -r * 0.1), r * 0.11, Color(0.2, 0.16, 0.14))
	draw_circle(pos + Vector2(r * 0.32, -r * 0.1), r * 0.11, Color(0.2, 0.16, 0.14))
	draw_arc(pos + Vector2(0.0, r * 0.2), r * 0.3, 0.3, PI - 0.3, 10, Color(0.2, 0.16, 0.14), 2.2)


func _draw_flash() -> void:
	if _flash <= 0.0 or _flash_text.is_empty():
		return
	var alpha := clampf(_flash * 1.6, 0.0, 1.0)
	draw_string(
		ThemeService.font(800),
		Vector2(0.0, view_size.y * 0.22),
		_flash_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		view_size.x,
		32,
		Color(0.95, 0.45, 0.66, alpha)
	)
