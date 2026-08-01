extends MinigameBase
## Möhrenfang (carrotCatch) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## CarrotCatchLogic (zahlengleich zum Web, Bot-zertifiziert): Spawn-Kadenz,
## Junk-Quote 10→30 %, Fallspeed +8 %/10 s (gestuft), Junk −2 + 0.5 s Dizzy,
## 1× goldene Möhre (+10, 1.5× Speed), Endlos endet nach 3 Boden-Möhren.
## Steuerung: Touch-Drag zieht den Korb (Hochkant-optimiert).
##
## ECHTER 3D-OBSTGARTEN (FB-4, CarrotCatchStage3D): Kenney-Food-Modelle fallen
## als 3D-Objekte, Gooby rennt als echtes Rig mit dem Picknickkorb, hinten
## Möhrenbeete, Zaun und Bäume. Die Kamera rahmt EXAKT die 2D-Rechnung
## (Weltbreite 2·WORLD_HALF_W), alle Zahlen bleiben unangetastet. Die 3D-Welt
## hängt unter der Node2D-Wurzel, der MinigameBase-Vertrag bleibt gleich.
##
## W17/G4-Politur (NUR Präsentation): Intro-Beat 1,5 s mit Kamera-Anflug und
## Ziel-Banner (die Sim wartet, M1), _ui-Skalierung des HUD samt Konturen
## (M9/M7), Miss-Feedback im Zeitmodus (Staubpuff + leiser Plop, M3) und
## Endton mg_win/mg_lose (M8). Der Vogelzug/Drachen-Himmel (M2) lebt in
## carrot_catch_stage3d.gd.

const Stage := preload("res://scripts/minigames/games/carrot_catch/carrot_catch_stage3d.gd")
const Kit := preload("res://scripts/minigames/games/carrot_catch/mpb_garden_kit.gd")

## Sichtbare Welt-Halbbreite in Logik-Einheiten (Web-Kamera ≈ 3.25 bei 390px).
const WORLD_HALF_W := 3.25
## W17 M9: Entwurfs-Kurzkante — HUD-Pixelmaße skalieren damit (hide_seek-Muster).
const DESIGN_SHORT := 390.0
## W17 M1: Intro-Beat (s) — Kamera-Anflug + Ziel-Banner, die Sim wartet.
const INTRO_S := 1.5
## Warm-weiße Kontur der HUD-Labels (M7): hebt Ziffern von Wiese/Himmel ab.
const OUTLINE_RIM := Color(1.0, 0.99, 0.94, 0.9)

var tune: Dictionary = {}
var rng: GoobyRng
var score := 0
var combo := 0
var missed_carrots := 0
var elapsed := 0.0
var basket_x := 0.0
var target_x := 0.0
var dizzy_until := -1.0
var next_spawn := 0.0
var golden_at := -1.0
var golden_spawned := false
var finished := false
var items: Array[Dictionary] = []
var view_size := Vector2(390.0, 844.0)

var _time_label: Label
var _combo_label: Label
var _hint_label: Label
var _stage: Node3D
var _framed_vp := Vector2.ZERO
var _hud_plate := Kit.hud_plate()
var _hint_plate := Kit.hud_plate()
var _ui := 1.0
var _pulse := 0.0
var _intro_left := 0.0
var _banner := ""
var _banner_t := 0.0
var _banner_plate := StyleBoxFlat.new()


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = CarrotCatchLogic.apply_difficulty(CarrotCatchLogic.CATCH, ctx.difficulty)
	rng = ctx.rng()
	if not bool(tune["ENDLESS"]):
		golden_at = CarrotCatchLogic.golden_spawn_at(rng, float(tune["DURATION_SEC"]), tune)
	next_spawn = CarrotCatchLogic.spawn_interval_at(0.0, float(tune["DURATION_SEC"]), tune)
	_stage = Stage.new()
	_stage.name = "Garten3D"
	add_child(_stage)
	_stage.setup_stage(float(tune["BASKET_HALF_WIDTH"]))
	if ctx.juice != null:
		ctx.juice.world_environment = _stage.stage.world_env
	_build_labels()
	_frame_stage()
	_banner_plate.set_corner_radius_all(12)
	# W17 M1: Intro-Beat — Kamera-Anflug über den Obstgarten + Ziel-Banner;
	# die Sim (elapsed/Spawn-Uhr) wartet, der Lauf bleibt danach zahlengleich.
	_intro_left = INTRO_S
	_set_banner(I18nService.t("mg.carrotCatch.intro"), INTRO_S + 0.7)
	if is_inside_tree():
		get_viewport().size_changed.connect(_fit_viewport)


## Pflicht-Layouthook: die Kamera folgt dem Viewport-Rect (Canvas-Einheiten).
## W17 M9: der _ui-Faktor (Kurzkante/390, 0.75..3.0) skaliert alle HUD-Maße.
func apply_view(size: Vector2) -> void:
	if size.x > 1.0 and size.y > 1.0:
		view_size = size
	_ui = clampf(minf(view_size.x, view_size.y) / DESIGN_SHORT, 0.75, 3.0)
	position = Vector2.ZERO
	_frame_stage()
	_layout_hud()
	queue_redraw()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _frame_stage() -> void:
	var vp := get_viewport_rect().size
	if vp == _framed_vp or vp.x <= 1.0:
		return
	_framed_vp = vp
	_stage.frame(vp, _px_per_unit(vp))


func end() -> void:
	super.end()
	finished = true


func _build_labels() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	_time_label.add_theme_color_override("font_outline_color", OUTLINE_RIM)
	add_child(_time_label)
	_combo_label = Label.new()
	_combo_label.theme_type_variation = &"CaptionLabel"
	_combo_label.add_theme_color_override("font_outline_color", OUTLINE_RIM)
	add_child(_combo_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.carrotCatch.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_hint_label)
	_layout_hud()
	_update_labels()


## HUD IMMER aus dem Viewport-Rect stellen: unter canvas_items-Stretch sind
## Canvas-Einheiten ≠ Fensterpixel. W17 M9: alle Pixelmaße skalieren mit dem
## _ui-Faktor statt in Fix-Pixeln zu kleben (Krümel-HUD auf Tablets), dazu
## Konturen auf Zeit/Serie/Hinweis (M7).
func _layout_hud() -> void:
	if _time_label == null:
		return
	var vp := get_viewport_rect().size
	_time_label.position = Vector2(16.0, 10.0) * _ui
	_time_label.add_theme_font_size_override("font_size", int(34.0 * _ui))
	_time_label.add_theme_constant_override("outline_size", int(6.0 * _ui))
	_combo_label.position = Vector2(16.0, 52.0) * _ui
	_combo_label.add_theme_font_size_override("font_size", int(15.0 * _ui))
	_combo_label.add_theme_constant_override("outline_size", int(5.0 * _ui))
	var hint_w := minf(vp.x - 32.0 * _ui, 360.0 * _ui)
	_hint_label.add_theme_font_size_override("font_size", int(20.0 * _ui))
	_hint_label.add_theme_constant_override("outline_size", int(5.0 * _ui))
	_hint_label.add_theme_color_override("font_outline_color", Color(OUTLINE_RIM, 0.6))
	_hint_label.position = Vector2((vp.x - hint_w) * 0.5, vp.y - 52.0 * _ui)
	_hint_label.size = Vector2(hint_w, 40.0 * _ui)


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	_pulse += delta
	var vp := get_viewport_rect().size
	var ppu := _px_per_unit(vp)
	# W17 M1: Intro-Beat — die Kamera fliegt über den Obstgarten in die
	# Spielpose, das Ziel steht als Banner; elapsed und Spawn-Uhr warten,
	# der Lauf bleibt zahlengleich (Crosscheck-Vertrag unberührt).
	if _intro_left > 0.0:
		_intro_left = maxf(0.0, _intro_left - delta)
		_banner_t = maxf(0.0, _banner_t - delta)
		_frame_stage()
		_stage.establish(1.0 if _reduced_motion() else 1.0 - _intro_left / INTRO_S)
		_stage.sync(items, basket_x, false, vp, ppu, _pulse, delta, _reduced_motion())
		_update_labels()
		queue_redraw()
		return
	_banner_t = maxf(0.0, _banner_t - delta)
	elapsed += delta
	# Korb folgt dem Drag-Ziel (außer während Dizzy).
	if elapsed >= dizzy_until:
		basket_x = lerpf(basket_x, target_x, minf(1.0, delta * 14.0))
	var half := _visible_half_w(vp, ppu)
	basket_x = clampf(basket_x, -half + 0.5, half - 0.5)
	_spawn_tick(vp)
	_move_items(vp, ppu, delta)
	if CarrotCatchLogic.is_catch_round_over(
		{"elapsed": elapsed, "missedCarrots": missed_carrots}, tune
	):
		_finish()
		return
	_frame_stage()
	_stage.sync(items, basket_x, elapsed < dizzy_until, vp, ppu, _pulse, delta, _reduced_motion())
	_update_labels()
	queue_redraw()


func _spawn_tick(vp: Vector2) -> void:
	if not golden_spawned and golden_at >= 0.0 and elapsed >= golden_at:
		golden_spawned = true
		(
			items
			. append(
				{
					"kind": "golden",
					"key": "carrot",
					"value": int(tune["GOLDEN_POINTS"]),
					"x": CarrotCatchLogic.spawn_x_for_roll(rng.next(), _visible_half_w_default(vp)),
					"y": -30.0,
				}
			)
		)
	next_spawn -= get_process_delta_time()
	if next_spawn > 0.0:
		return
	next_spawn = CarrotCatchLogic.spawn_interval_at(elapsed, float(tune["DURATION_SEC"]), tune)
	var item := CarrotCatchLogic.roll_item(rng, elapsed, tune)
	item["x"] = CarrotCatchLogic.spawn_x_for_roll(rng.next(), _visible_half_w_default(vp))
	item["y"] = -30.0
	items.append(item)


func _move_items(vp: Vector2, ppu: float, delta: float) -> void:
	var basket_y := vp.y - 130.0
	var kept: Array[Dictionary] = []
	for item in items:
		var speed := CarrotCatchLogic.item_fall_speed(elapsed, str(item["kind"]), tune)
		item["y"] = float(item["y"]) + speed * ppu * delta
		var y := float(item["y"])
		if y >= basket_y and y < basket_y + 46.0:
			if CarrotCatchLogic.basket_catches_x(float(item["x"]), basket_x, tune):
				_catch(item, vp)
				continue
		if y > vp.y + 30.0:
			_on_item_missed(item)
			continue
		kept.append(item)
	items = kept


## Boden-Feedback (NUR Präsentation, Wertung/Logik unberührt): Endlos kostet
## die verpasste Möhre ein Leben (Spill + Shake wie gehabt); im Zeitmodus
## quittieren Staubpuff am Boden + leiser Plop die durchgefallene gute Ware
## (W17 M3 — vorher verschwand sie kommentarlos).
func _on_item_missed(item: Dictionary) -> void:
	var kind := str(item["kind"])
	if kind == "junk" or kind == "rotten":
		return
	if bool(tune["ENDLESS"]):
		if kind == "good" and str(item["key"]) == "carrot":
			missed_carrots += 1
			# Verpasste Möhre = ein Endlos-Leben weg: fühlbar machen.
			AudioDirector.try_play(self, "mg_spill", 0.85)
			if ctx.juice != null:
				ctx.juice.shake(0.25)
		return
	AudioDirector.try_play(self, "gvz_pop", 0.7)
	if not _reduced_motion():
		_stage.miss_fx(float(item["x"]))


func _catch(item: Dictionary, vp: Vector2) -> void:
	var res := CarrotCatchLogic.apply_catch_state({"score": score, "combo": combo}, item)
	var delta := int(res["delta"])
	score = int(res["score"])
	combo = int(res["combo"])
	var pos := Vector2(vp.x * 0.5 + float(item["x"]) * _px_per_unit(vp), vp.y - 190.0)
	var kind := str(item["kind"])
	if kind == "golden":
		AudioDirector.try_play(self, "mg_golden")
	elif kind == "good":
		AudioDirector.try_play(self, "mg_good")
	else:
		AudioDirector.try_play(self, "mg_junk")
	if kind == "junk" or kind == "rotten":
		_stage.junk_fx()
	else:
		_stage.catch_fx(kind == "golden")
	if ctx.juice != null:
		if kind == "golden":
			ctx.juice.float_text(pos, "+%d" % int(item["value"]), Color(1.0, 0.78, 0.1))
			ctx.juice.slowmo(0.35, 350)
			ctx.juice.bloom_pulse(0.8)
			ctx.juice.confetti(36)
		elif kind == "good":
			ctx.juice.float_text(pos, "+%d" % int(item["value"]), Color(0.42, 0.6, 0.36))
			ctx.juice.overlay_ring(pos, Color(1.0, 0.9, 0.55, 0.8), 52.0)
		else:
			ctx.juice.float_text(pos, I18nService.t("mg.carrotCatch.yuck"), Color(0.8, 0.3, 0.25))
			ctx.juice.shake(0.4)
			ctx.juice.hit_freeze(80)
			ctx.juice.hit_flash(Color(0.9, 0.35, 0.3, 0.16))
		# Mitwachsende Combo-Anzeige mit steigendem Ton; Reset blendet sie aus.
		ctx.juice.show_combo(combo)
		if CarrotCatchLogic.combo_milestone(combo):
			ctx.juice.bloom_pulse(0.4)
			ctx.juice.float_text(
				pos - Vector2(0, 42),
				I18nService.t("mg.game.streak", {"n": combo}),
				Color(0.95, 0.45, 0.66)
			)
	if kind == "junk" or kind == "rotten":
		dizzy_until = elapsed + float(tune["DIZZY_SEC"])
	ctx.report_score(score, delta)


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	# W17 M8: hörbarer Schlusspunkt — der Zeitmodus endet als geschaffte
	# Runde (mg_win), Endlos endet immer über die dritte Boden-Möhre (mg_lose).
	AudioDirector.try_play(self, "mg_lose" if bool(tune["ENDLESS"]) else "mg_win")
	var final_score := CarrotCatchLogic.final_catch_score(score, tune)
	ctx.report_end({"score": final_score, "missedCarrots": missed_carrots, "elapsed": elapsed})


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished or _intro_left > 0.0:
		return
	var vp := get_viewport_rect().size
	var ppu := _px_per_unit(vp)
	if event is InputEventScreenTouch and event.pressed:
		target_x = (event.position.x - vp.x * 0.5) / ppu
	elif event is InputEventScreenDrag:
		target_x = (event.position.x - vp.x * 0.5) / ppu


func _update_labels() -> void:
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.carrotCatch.missed",
			{"n": missed_carrots, "max": int(tune["ENDLESS_MISSED_CARROTS"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - elapsed)))
		_time_label.text = I18nService.t("mg.game.time", {"sec": left})
	if combo > 1:
		_combo_label.text = I18nService.t("mg.game.streak", {"n": combo})
	else:
		_combo_label.text = ""
	_hint_label.modulate.a = _hint_alpha()


## Milchglas hinter Zeit/Serie und dem Hinweis: fallende Ware und Wiese zogen
## sonst direkt durch die Ziffern (Lesbarkeit auf dem Handy).
func _draw() -> void:
	if _time_label == null:
		return
	var pad := Vector2(12.0, 6.0) * _ui
	var top_left := _time_label.position - pad
	var bottom_right := (
		_combo_label.position
		+ Vector2(maxf(_time_label.size.x, _combo_label.size.x), _combo_label.size.y)
		+ pad
	)
	draw_style_box(_hud_plate, Rect2(top_left, bottom_right - top_left))
	var hint_a := _hint_alpha()
	if hint_a > 0.0:
		_hint_plate.bg_color = Color(1.0, 0.99, 0.94, 0.72 * hint_a)
		draw_style_box(
			_hint_plate, Rect2(_hint_label.position - Vector2(0.0, 2.0), _hint_label.size)
		)
	_draw_banner()


func _set_banner(text: String, sec := 1.4) -> void:
	_banner = text
	_banner_t = sec


## Ziel-Banner mittig mit Milchglas-Plate und Kontur (M7, carrot_guard-Muster);
## lange Übersetzungen brechen um.
func _draw_banner() -> void:
	if _banner_t <= 0.0 or _banner.is_empty():
		return
	var vp := get_viewport_rect().size
	var font := ThemeService.font(800)
	var alpha := clampf(_banner_t * 1.4, 0.0, 1.0)
	var font_size := int(26.0 * _ui)
	var w := minf(vp.x * 0.92, 460.0 * _ui)
	var text_size := font.get_multiline_string_size(
		_banner, HORIZONTAL_ALIGNMENT_CENTER, w, font_size
	)
	var top := vp.y * 0.26
	var pad := Vector2(18.0 * _ui, 10.0 * _ui)
	_banner_plate.set_corner_radius_all(int(12.0 * _ui))
	_banner_plate.bg_color = Color(1.0, 0.99, 0.94, 0.74 * alpha)
	var plate_pos := Vector2((vp.x - text_size.x) * 0.5, top) - pad
	draw_style_box(_banner_plate, Rect2(plate_pos, text_size + pad * 2.0))
	var ink := Color(0.32, 0.24, 0.28, alpha)
	var rim := Color(1.0, 1.0, 1.0, 0.75 * alpha)
	var at := Vector2((vp.x - w) * 0.5, top + font.get_ascent(font_size))
	draw_multiline_string_outline(
		font, at, _banner, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, -1, int(5.0 * _ui), rim
	)
	draw_multiline_string(font, at, _banner, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, -1, ink)


## Der Hinweis blendet nach ein paar Sekunden aus — das Spielfeld gehört dann
## ganz dem Geschehen.
func _hint_alpha() -> float:
	return clampf(1.0 - (elapsed - 5.0) / 1.5, 0.0, 1.0)


## Reduced-Motion-Abfrage (Duck-Typing wie im JuiceKit — ohne Autoload = aus).
func _reduced_motion() -> bool:
	if not is_inside_tree():
		return true
	var settings := get_node_or_null(^"/root/AppSettings")
	if settings != null and settings.has_method("is_reduced_motion"):
		return settings.is_reduced_motion()
	return false


func _px_per_unit(vp: Vector2) -> float:
	return vp.x / (WORLD_HALF_W * 2.0)


## Halbbreite in Einheiten, die der aktuelle Viewport wirklich zeigt.
func _visible_half_w(vp: Vector2, ppu: float) -> float:
	return vp.x * 0.5 / ppu


func _visible_half_w_default(vp: Vector2) -> float:
	return _visible_half_w(vp, _px_per_unit(vp))
