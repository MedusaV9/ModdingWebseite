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
##
## W17/G5-Politur (NUR Präsentation): Intro-Beat 1,5 s mit Pfannen-Totale
## (die Sim wartet, M1), _ui-Skalierung des HUD (M9), Hint-Fade (Q3),
## Topple-Meldung als Banner-Plate statt rohem draw_string (M7),
## Reduced-Motion-Gates an den eigenen Stage-Burst-Call-Sites (Q2) und
## Wackel-Warnung: ab kritischer Schieflage pulsiert ein Warnsaum (RM:
## statisch) und ein Wusch mahnt — die Schwingung selbst bleibt Logik-Sache.

## Sichtbare Weltbreite (Web-Kamera rahmt ≈ 2.9 Einheiten bei 390 px).
const VIEW_UNITS_X := 2.9
## Höhe der Stapelspitze auf dem Schirm (Anteil von unten).
const TOP_ANCHOR := 0.6
## Abwurfhöhe des Pendel-Pfannkuchens über der Stapelspitze (Einheiten).
const DROP_HEIGHT := 1.5

## Bildschirmhöhe der Tellerkante (Weltnullpunkt) als Anteil von oben.
const GROUND_FRAC := 0.88

## W17 M9: Entwurfs-Kurzkante — HUD-Pixelmaße skalieren damit (G4-Muster).
const DESIGN_SHORT := 390.0
## W17 M1: Intro-Beat (s) — Pfannen-Totale überm Tresen, die Sim wartet.
const INTRO_S := 1.5
## Q3: der Hinweis blendet nach ~6 s Spielzeit über 1,5 s aus (G2-Muster).
const HINT_FADE_AT := 6.0
const HINT_FADE_SEC := 1.5
## Wackel-Warnung: ab diesem Anteil des Schwingungs-Limits gilt es als ernst.
const WARN_FRAC := 0.55
## Warn-Wusch frühestens alle 0,9 s — sonst dauert-mahnt die Schieflage.
const WARN_TONE_GAP := 0.9

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
var _cam_bottom := 0.0
var _layers_label: Label
var _width_label: Label
var _hint_label: Label
var _stage: Node3D
var _pulse := 0.0
## W17 M9: HUD-Skalenfaktor (Kurzkante/390, geklemmt 0.75..3.0).
var _ui := 1.0
## W17 M1: Rest-Sekunden des Intro-Beats (0 = Spielbetrieb).
var _intro_left := 0.0
## Banner-Plate (M7): ersetzt den rohen Topple-draw_string, trägt auch Intro.
var _banner_text := ""
var _banner_t := 0.0
var _banner_plate := StyleBoxFlat.new()
## Q3: gesehene Spielzeit des Hinweises (tickt erst nach dem Intro).
var _hint_seen := 0.0
## Wackel-Warnung: 0..1-Pegel + Sperrzeit für den Warn-Wusch.
var _warn_level := 0.0
var _warn_tone_in := 0.0


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
	_banner_plate.set_corner_radius_all(12)
	# W17 M1: Intro-Beat — die Kamera schwebt als Pfannen-Totale überm Tresen
	# und senkt sich in die Spielpose; die Sim (Pendel/Schwingung) wartet,
	# der Lauf bleibt danach zahlengleich (Crosscheck-Vertrag unberührt).
	_intro_left = INTRO_S
	_set_banner(I18nService.t("mg.pancakeTower.intro"), INTRO_S + 0.7)
	if is_inside_tree():
		get_viewport().size_changed.connect(_fit_viewport)


func end() -> void:
	super.end()
	finished = true


## Pflicht-Layouthook: beide Orientierungen laufen über DIESE Funktion.
## W17 M9: der _ui-Faktor (Kurzkante/390, 0.75..3.0) skaliert alle HUD-Maße.
func apply_view(size: Vector2) -> void:
	if size.x > 1.0 and size.y > 1.0:
		view_size = size
	landscape = view_size.x > view_size.y
	_ui = clampf(minf(view_size.x, view_size.y) / DESIGN_SHORT, 0.75, 3.0)
	position = Vector2.ZERO
	if _stage != null:
		_stage.frame(view_size)
	_layout_hud()
	queue_redraw()


## HUD IMMER aus dem Viewport-Rect stellen: unter canvas_items-Stretch sind
## Canvas-Einheiten ≠ Fensterpixel, apply_view-Größen können abweichen.
## W17 M9: alle Pixelmaße skalieren mit _ui; die Hinweis-Breite hängt an
## vp.x statt an fixen 300 px (Tablet-Krümelschrift des Audits).
func _layout_hud() -> void:
	if _layers_label == null:
		return
	var vp := get_viewport_rect().size
	_layers_label.position = Vector2(16.0, 10.0) * _ui
	_layers_label.add_theme_font_size_override("font_size", int(34.0 * _ui))
	_width_label.position = Vector2(16.0, 48.0) * _ui
	_width_label.add_theme_font_size_override("font_size", int(15.0 * _ui))
	var hint_w := minf(vp.x - 32.0 * _ui, 360.0 * _ui)
	var font_size := int(20.0 * _ui)
	_hint_label.add_theme_font_size_override("font_size", font_size)
	var font := _hint_label.get_theme_font("font")
	var text_size := font.get_multiline_string_size(
		_hint_label.text, HORIZONTAL_ALIGNMENT_CENTER, hint_w, font_size
	)
	var box := Vector2(hint_w, text_size.y + 6.0 * _ui)
	_hint_label.position = Vector2((vp.x - box.x) * 0.5, vp.y - box.y - 10.0 * _ui)
	_hint_label.size = box
	for label: Label in [_layers_label, _width_label, _hint_label]:
		label.add_theme_constant_override("outline_size", int(7.0 * _ui))


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	_banner_t = maxf(0.0, _banner_t - delta)
	_pulse += delta
	# W17 M1: Intro-Beat — die Kamera senkt sich aus der Pfannen-Totale in
	# die Spielpose, das Ziel steht als Banner; Pendel-, Schwingungs- und
	# Krümel-Uhr warten, der Lauf bleibt zahlengleich. Reduced Motion
	# überspringt die Fahrt (Call-Site-Gate) und hält nur den Banner-Beat.
	if _intro_left > 0.0:
		_intro_left = maxf(0.0, _intro_left - delta)
		_sync_stage(delta)
		_stage.establish(1.0 if _reduced_motion() else 1.0 - _intro_left / INTRO_S)
		_update_labels()
		queue_redraw()
		return
	_hint_seen += delta
	wobble = PancakeTowerLogic.step_wobble(wobble, delta, layers.size(), tune)
	_step_crumbs(delta)
	if falling:
		fall_y -= float(tune["FALL_SPEED"]) * delta
		if fall_y <= _stack_height():
			_land()
	else:
		slide_t += delta
	_sync_stage(delta)
	_tick_warn(delta)
	_update_labels()
	queue_redraw()


## Wackel-Warnung (reine ANZEIGE — die Schwingung kommt unverändert aus der
## Logik): ab WARN_FRAC des Schwingungs-Limits steigt der Warnsaum-Pegel und
## ein leiser Wusch mahnt in Abständen; perfekte Landungen dämpfen die
## Schwingung ohnehin, die Warnung erlischt dann von selbst.
func _tick_warn(delta: float) -> void:
	_warn_tone_in = maxf(0.0, _warn_tone_in - delta)
	var frac := absf(float(wobble["angle"])) / maxf(1e-6, float(tune["WOBBLE_MAX_RAD"]))
	if layers.size() < int(tune["WOBBLE_START_LAYER"]) or frac < WARN_FRAC:
		_warn_level = 0.0
		return
	_warn_level = clampf((frac - WARN_FRAC) / (1.0 - WARN_FRAC), 0.0, 1.0)
	if _warn_tone_in <= 0.0:
		_warn_tone_in = WARN_TONE_GAP
		# Bestehende Feel-Id: das Wusch liest sich als Schwanken des Turms.
		FeelSfx.play(self, "game_whoosh", 0.9 + 0.2 * _warn_level)


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
	if not is_active() or finished or falling or _intro_left > 0.0:
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
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
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
		# Q2: Reduced-Motion-Gate an der eigenen Stage-Burst-Call-Site.
		_stage.topple_fx(fall_x, _stack_height(), _reduced_motion())
		# M7: Banner-Plate statt rohem draw_string — lesbar auf jeder Kulisse.
		_set_banner(I18nService.t("mg.pancakeTower.topple"), 1.2)
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
		_stage.cut_fx(float(cut["center"]), _stack_height(), _reduced_motion())
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
		# Q2: Reduced-Motion-Gate an der eigenen Stage-Burst-Call-Site —
		# die perfekte Landung feiert mit Landering + Pitch-Treppe (unten).
		_stage.perfect_fx(float(drop["center"]), _stack_height(), _reduced_motion())
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
		_stage.topping_fx(float(drop["center"]), _stack_height(), _reduced_motion())
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
	_hint_label.modulate.a = _hint_alpha()


## Q3: der Hinweis steht die ersten Sekunden und blendet dann aus — die
## Küche gehört danach ganz dem Turm.
func _hint_alpha() -> float:
	return clampf(1.0 - (_hint_seen - HINT_FADE_AT) / HINT_FADE_SEC, 0.0, 1.0)


func _set_banner(text: String, sec := 1.4) -> void:
	_banner_text = text
	_banner_t = sec


## Reduced-Motion-Abfrage (Duck-Typing wie im JuiceKit — ohne Autoload = aus).
func _reduced_motion() -> bool:
	if not is_inside_tree():
		return true
	var settings := get_node_or_null(^"/root/AppSettings")
	if settings != null and settings.has_method("is_reduced_motion"):
		return settings.is_reduced_motion()
	return false


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
# 3D-Bühne (PancakeTowerStage3D); 2D bleiben Banner, Warnsaum + Breitenbalken.
func _draw() -> void:
	_draw_width_bar()
	_draw_warn()
	_draw_banner()


## Breitenbalken unter dem HUD: färbt sich von Grün nach Rot, je näher der
## Turm dem Aus (Breite < 20 %) kommt — Gefahr auf einen Blick.
func _draw_width_bar() -> void:
	var frac := clampf(float(stack["width"]) / float(tune["BASE_WIDTH"]), 0.0, 1.0)
	var bar := Rect2(Vector2(16.0, 86.0) * _ui, Vector2(132.0, 10.0) * _ui)
	draw_rect(bar, Color(0.2, 0.12, 0.1, 0.45))
	var tint := Color(0.45, 0.78, 0.4).lerp(Color(0.92, 0.32, 0.24), 1.0 - frac)
	draw_rect(Rect2(bar.position, Vector2(bar.size.x * frac, bar.size.y)), tint)
	# Marke bei 20 %: darunter kippt der Turm (MIN_WIDTH_FRAC der Logik).
	var mark_x := bar.position.x + bar.size.x * 0.2
	draw_rect(
		Rect2(Vector2(mark_x, bar.position.y - 2.0 * _ui), Vector2(2.0, 14.0) * _ui),
		Color(1, 1, 1, 0.8)
	)


## Wackel-Warnsaum: bei kritischer Schieflage pulsiert ein roter Rand —
## Reduced Motion bekommt denselben Saum STATISCH (Info bleibt, Puls geht).
func _draw_warn() -> void:
	if _warn_level <= 0.0:
		return
	var vp := get_viewport_rect().size
	var throb := 0.6 if _reduced_motion() else 0.55 + 0.45 * sin(_pulse * 9.0)
	var tint := Color(0.92, 0.32, 0.24, 0.18 * _warn_level * throb)
	var w := 10.0 * _ui
	draw_rect(Rect2(Vector2.ZERO, Vector2(vp.x, w)), tint)
	draw_rect(Rect2(Vector2(0.0, vp.y - w), Vector2(vp.x, w)), tint)
	draw_rect(Rect2(Vector2(0.0, w), Vector2(w, vp.y - w * 2.0)), tint)
	draw_rect(Rect2(Vector2(vp.x - w, w), Vector2(w, vp.y - w * 2.0)), tint)


## Banner mittig mit Milchglas-Plate und Kontur (M7, bubble_pop-Muster);
## lange Übersetzungen brechen um. Trägt Intro-Ziel UND Topple-Meldung.
func _draw_banner() -> void:
	if _banner_t <= 0.0 or _banner_text.is_empty():
		return
	var vp := get_viewport_rect().size
	var font := ThemeService.font(800)
	var alpha := clampf(_banner_t * 1.4, 0.0, 1.0)
	var font_size := int(26.0 * _ui)
	var w := minf(vp.x * 0.92, 460.0 * _ui)
	var text_size := font.get_multiline_string_size(
		_banner_text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size
	)
	var top := vp.y * 0.24
	var pad := Vector2(18.0 * _ui, 10.0 * _ui)
	_banner_plate.set_corner_radius_all(int(12.0 * _ui))
	_banner_plate.bg_color = Color(1.0, 0.99, 0.94, 0.74 * alpha)
	var plate_pos := Vector2((vp.x - text_size.x) * 0.5, top) - pad
	draw_style_box(_banner_plate, Rect2(plate_pos, text_size + pad * 2.0))
	var ink := Color(0.32, 0.24, 0.28, alpha)
	var rim := Color(1.0, 1.0, 1.0, 0.75 * alpha)
	var at := Vector2((vp.x - w) * 0.5, top + font.get_ascent(font_size))
	draw_multiline_string_outline(
		font, at, _banner_text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, -1, int(5.0 * _ui), rim
	)
	draw_multiline_string(
		font, at, _banner_text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, -1, ink
	)
