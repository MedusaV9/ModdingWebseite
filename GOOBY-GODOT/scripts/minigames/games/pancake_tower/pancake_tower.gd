extends MinigameBase
## Pfannkuchenturm (pancakeTower) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## PancakeTowerLogic (zahlengleich zum Web): Pendel-Kadenz, Schnitt-Mathematik,
## Perfect-Fenster (+2 & +10 % Breite), jede 5. Lage Topping (+4), Ende bei
## Breite < 20 % oder 40 Lagen, Turmschwingung ab Lage 8.
## Steuerung: Tippen lässt den Pfannkuchen fallen.
##
## ECHTE 3D-KÜCHE (FB-4, PancakeTowerStage3D): Pfannkuchen als 3D-Zylinder auf
## Teller + Arbeitsplatte, Turm-Schwingung als echte Rotation, Gooby (echtes
## Rig) reitet auf dem Pendel-Pfannkuchen, Kamera fährt mit der Spitze hoch.
## Die Abbildung nutzt exakt die Web-Kameramathematik — MECHANIK unangetastet.

## Sichtbare Weltbreite (Web-Kamera rahmt ≈ 2.9 Einheiten bei 390 px).
const VIEW_UNITS_X := 2.9
## Höhe der Stapelspitze auf dem Schirm (Anteil von unten).
const TOP_ANCHOR := 0.6
## Abwurfhöhe des Pendel-Pfannkuchens über der Stapelspitze (Einheiten).
const DROP_HEIGHT := 1.5

## Bildschirmhöhe der Tellerkante (Weltnullpunkt) als Anteil von oben.
const GROUND_FRAC := 0.88

const Stage := preload("res://scripts/minigames/games/pancake_tower/pancake_tower_stage3d.gd")

var tune: Dictionary = {}
var rng: GoobyRng
var layers: Array[Dictionary] = []
var stack := {"center": 0.0, "width": 1.5}
var bonus_points := 0
var perfects := 0
## Perfekt-Serie in Folge (nur Anzeige/Feel — Combo-Ton steigt mit).
var perfect_streak := 0
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
var _stage: Node3D
var _pulse := 0.0


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = PancakeTowerLogic.apply_difficulty(PancakeTowerLogic.PANCAKE, ctx.difficulty)
	rng = ctx.rng()
	stack = {"center": 0.0, "width": float(tune["BASE_WIDTH"])}
	wobble = PancakeTowerLogic.initial_wobble_state()
	slide_phase = rng.next()
	_stage = Stage.new()
	_stage.name = "Kueche3D"
	add_child(_stage)
	_stage.setup_stage(VIEW_UNITS_X, GROUND_FRAC, float(tune["LAYER_HEIGHT"]))
	if ctx.juice != null:
		ctx.juice.world_environment = _stage.stage.world_env
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
	if _stage != null:
		_stage.frame(view_size)
	_layout_hud()
	queue_redraw()


## HUD IMMER aus dem Viewport-Rect stellen: unter canvas_items-Stretch sind
## Canvas-Einheiten ≠ Fensterpixel, apply_view-Größen können abweichen.
func _layout_hud() -> void:
	if _layers_label == null:
		return
	var vp := get_viewport_rect().size
	_layers_label.position = Vector2(16.0, 10.0)
	_width_label.position = Vector2(16.0, 48.0)
	_hint_label.position = Vector2(vp.x * 0.5 - 150.0, vp.y - 56.0)
	_hint_label.size = Vector2(300.0, 40.0)


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	_flash = maxf(0.0, _flash - delta)
	_pulse += delta
	wobble = PancakeTowerLogic.step_wobble(wobble, delta, layers.size(), tune)
	_step_crumbs(delta)
	if falling:
		fall_y -= float(tune["FALL_SPEED"]) * delta
		if fall_y <= _stack_height():
			_land()
	else:
		slide_t += delta
	_sync_stage(delta)
	_update_labels()
	queue_redraw()


## Kamera-Anker + Bühnenzustand an die 3D-Küche geben (Web-Kameramathematik).
func _sync_stage(delta: float) -> void:
	var ppu := _ppu()
	var visible_units := view_size.y / ppu
	_cam_bottom = maxf(0.0, _stack_height() - visible_units * TOP_ANCHOR)
	var index := _current_index()
	var x := fall_x if falling else PancakeTowerLogic.slide_x(slide_t, index, slide_phase, tune)
	var y := fall_y if falling else _stack_height() + DROP_HEIGHT
	var active := {
		"x": x,
		"y": y,
		"width": float(stack["width"]),
		"topping": PancakeTowerLogic.is_topping_layer(index, tune),
		"visible": true,
		"stack_top": _stack_height(),
	}
	_stage.sync(layers, active, float(wobble["angle"]), _cam_bottom, _crumbs, _pulse, delta)


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
	# Heller Text + dunkler Saum: lesbar auf Tapete UND Arbeitsplatte.
	for label: Label in [_layers_label, _width_label, _hint_label]:
		label.add_theme_color_override("font_color", Color(1.0, 0.97, 0.92))
		label.add_theme_color_override("font_outline_color", Color(0.34, 0.2, 0.12, 0.9))
		label.add_theme_constant_override("outline_size", 7)
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
		_stage.topple_fx(fall_x, _stack_height())
		_flash_text = I18nService.t("mg.pancakeTower.topple")
		_flash = 1.0
		AudioDirector.try_play(self, "mg_spill")
		if ctx.juice != null:
			ctx.juice.shake(0.45)
			ctx.juice.hit_freeze(80)
			ctx.juice.hit_flash(Color(0.9, 0.32, 0.22, 0.16), 200)
			ctx.juice.sfx("game_miss")
			ctx.juice.show_combo(0)
		_finish()
		return
	if not (drop["cut"] as Dictionary).is_empty():
		var cut: Dictionary = drop["cut"]
		_spawn_crumb(float(cut["center"]), _stack_height(), float(cut["size"]))
		_stage.cut_fx(float(cut["center"]), _stack_height())
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
		perfect_streak += 1
		_stage.perfect_fx(float(drop["center"]), _stack_height())
		wobble = PancakeTowerLogic.damp_wobble(wobble, tune, layers.size())
		# Nur der Fließtext am Stapel — das große Band bleibt dem Spielende
		# vorbehalten, sonst steht die Meldung doppelt im Bild.
		# Perfekt-Serie klettert die Halbton-Treppe hoch.
		AudioDirector.try_play(self, "mg_perfect", FeelSfx.combo_pitch(perfect_streak))
		if ctx.juice != null:
			ctx.juice.hit_freeze(45)
			ctx.juice.bloom_pulse(0.7)
			ctx.juice.ring_burst(self, pos, Color(1.0, 0.72, 0.2), 66.0)
			ctx.juice.burst(self, pos, Color(1.0, 0.82, 0.4), 12)
			if perfect_streak >= 2:
				ctx.juice.show_combo(perfect_streak)
			ctx.juice.float_text(
				pos, I18nService.t("mg.pancakeTower.perfect"), Color(1.0, 0.72, 0.2)
			)
	elif topping:
		perfect_streak = 0
		_stage.topping_fx(float(drop["center"]), _stack_height())
		AudioDirector.try_play(self, "mg_golden")
		if ctx.juice != null:
			ctx.juice.bloom_pulse(0.5)
			ctx.juice.float_text(pos, "+%d" % int(drop["points"]), Color(0.93, 0.36, 0.48))
	else:
		perfect_streak = 0
		AudioDirector.try_play(self, "mg_good")
		if ctx.juice != null:
			ctx.juice.shake(0.12)
			ctx.juice.show_combo(0)


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


# Kein 2D-Turm mehr: Küche, Teller, Lagen, Pendel und Gooby rendert die
# 3D-Bühne (PancakeTowerStage3D); 2D bleiben Topple-Flash-Text + Breitenbalken.
func _draw() -> void:
	_draw_width_bar()
	_draw_flash()


## Breitenbalken unter dem HUD: färbt sich von Grün nach Rot, je näher der
## Turm dem Aus (Breite < 20 %) kommt — Gefahr auf einen Blick.
func _draw_width_bar() -> void:
	var frac := clampf(float(stack["width"]) / float(tune["BASE_WIDTH"]), 0.0, 1.0)
	var bar := Rect2(Vector2(16.0, 86.0), Vector2(132.0, 10.0))
	draw_rect(bar, Color(0.2, 0.12, 0.1, 0.45))
	var tint := Color(0.45, 0.78, 0.4).lerp(Color(0.92, 0.32, 0.24), 1.0 - frac)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), tint)
	# Marke bei 20 %: darunter kippt der Turm (MIN_WIDTH_FRAC der Logik).
	var mark_x := bar.position.x + bar.size.x * 0.2
	draw_rect(Rect2(Vector2(mark_x, bar.position.y - 2.0), Vector2(2.0, 14.0)), Color(1, 1, 1, 0.8))


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
