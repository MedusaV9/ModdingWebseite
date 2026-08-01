extends MinigameBase
## Karottenwache (carrotGuard) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## CarrotGuardLogic (zahlengleich zum Web, Bot-zertifiziert): 3×3 Erdhügel,
## Maulwürfe bleiben 0,9 s → 0,5 s oben, 10 Karotten im Beet, Treffer +1, jede
## 5er-Kombo +3, entwischt einer klaut er eine Karotte. Nach je 20 Treffern
## kommt der Maulwurfkönig (3 Taps, +8 + 2 Münzen). 45 s oder Beet leer;
## Endlos endet nach drei geklauten Karotten.
##
## ECHTE 3D-GARTENWIESE (FB-4, CarrotGuardStage3D): 3D-Maulwürfe tauchen aus
## Erdhügeln auf einer Sommerwiese auf, hinten Zaun/Bäume/Karottenbeet, Gooby
## (echtes Rig) hält Wache. Die Hügel liegen per ground_point-Raycast EXAKT
## unter den 2D-Tap-Rechtecken (_holes) — Eingabe und Trefferflächen bleiben
## zahlengleich, die MECHANIK unangetastet.
##
## W16/G3-Politur (NUR Präsentation): Möhren-Icon-Reihe statt „n/max“-Text
## (Klau fliegt sichtbar aus dem Slot), Kombo-Pips zur 5er-Bonus-Kombo,
## König-Banner mittig mit Kontur (M7), _ui-Skalierung des HUD (M9),
## Timer-Urgenz unter 5 s und ein Intro-Beat (M1), der die Sim gatet.

const Stage := preload("res://scripts/minigames/games/carrot_guard/carrot_guard_stage3d.gd")
const Kit := preload("res://scripts/minigames/games/carrot_catch/mpb_garden_kit.gd")

## W16 M9: Entwurfs-Kurzkante — HUD-Pixelmaße skalieren damit (hide_seek-Muster).
const DESIGN_SHORT := 390.0
## W16 M1: Intro-Beat (s) — Kamera-Totale + Ziel-Banner, die Sim wartet.
const INTRO_S := 1.5
## Timer-Urgenz: unter so vielen Restsekunden pulsiert die Zeit rot + tickt.
const URGENT_UNDER_S := 5.0
## Flugdauer (s) der HUD-Möhre, wenn ein Klau ihren Slot leert.
const ICON_FLY_S := 0.6
## Möhren-Icon-Farben (Körper, Blattschopf) und der geleerte Slot.
const ICON_BODY := Color(0.91, 0.47, 0.16)
const ICON_LEAF := Color(0.38, 0.63, 0.32)
const ICON_EMPTY := Color(0.45, 0.38, 0.3, 0.22)
## Kombo-Pips: gefüllt, Gold-Blitz beim Bonus, leerer Ring, Riss-Blitz.
const PIP_FILL := Color(0.42, 0.66, 0.34)
const PIP_GOLD := Color(1.0, 0.78, 0.25)
const PIP_RING := Color(0.55, 0.48, 0.4, 0.55)
const PIP_BREAK := Color(0.9, 0.35, 0.3, 0.9)

var tune: Dictionary = {}
var rng: GoobyRng
var score := 0
var combo := 0
var bonks := 0
var kings_spawned := 0
var carrots := 10
var elapsed := 0.0
var next_spawn := 0.0
var last_tap_at := -INF
var moles: Array[Dictionary] = []
var king: Dictionary = {}
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

var _time_label: Label
var _hint_label: Label
var _holes: Array[Rect2] = []
var _stage: Node3D
var _pulse := 0.0
var _hud_plate := Kit.hud_plate()
var _hint_plate := Kit.hud_plate()
var _ui := 1.0
var _intro_left := 0.0
var _banner := ""
var _banner_t := 0.0
var _banner_gold := false
var _banner_plate := StyleBoxFlat.new()
var _vignette := 0.0
var _vignette_box := StyleBoxFlat.new()
## Klau-Flüge im HUD: {"slot": geleerter Icon-Index, "t": Flugzeit}.
var _fly_icons: Array[Dictionary] = []
var _pip_flash := 0.0
var _pip_break := 0.0
var _last_tick_sec := -1


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = CarrotGuardLogic.apply_difficulty(CarrotGuardLogic.GUARD, ctx.difficulty)
	rng = ctx.rng()
	carrots = int(tune["CARROTS"])
	next_spawn = CarrotGuardLogic.spawn_interval_at(0.0, float(tune["DURATION_SEC"]), tune)
	_stage = Stage.new()
	_stage.name = "Wiese3D"
	add_child(_stage)
	_stage.setup_stage(carrots)
	if ctx.juice != null:
		ctx.juice.world_environment = _stage.stage.world_env
	_build_hud()
	_fit_viewport()
	# W16 M1: Intro-Beat — Kamera-Totale des Gartens + Ziel-Banner; die Sim
	# (elapsed/Spawn-Uhr) wartet, der Lauf bleibt danach zahlengleich.
	_intro_left = INTRO_S
	_set_banner(I18nService.t("mg.carrotGuard.intro"), false, INTRO_S + 0.7)
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
	var grid := int(tune.get("GRID", 3))
	# Quer braucht das Feld MEHR Kopfraum: die oberste Reihe raycastet sonst
	# bis in die Kulissen-Zone (Gewächshaus/Zaun bei z≈-15) hinein.
	var top := 108.0 if not landscape else 118.0
	# Das Karottenbeet liegt in 3D HINTER dem Feld (oben im Bild) — unten
	# braucht es nur noch wenig Reserve, sonst bleibt ein leerer Grasstreifen.
	var bed := 56.0 if not landscape else 0.0
	var avail := Vector2(view_size.x - 32.0, maxf(120.0, view_size.y - top - bed - 52.0))
	var cell := minf(avail.x, avail.y) / float(grid)
	var board := cell * grid
	# Hochkant das Brett nach unten schieben: füllt den Vordergrund,
	# und die vorderen Hügel werden schön groß (Perspektive).
	var down := 0.72 if not landscape else 0.5
	var origin := Vector2((view_size.x - board) * 0.5, top + (avail.y - board) * down)
	_holes = []
	for row in grid:
		for col in grid:
			_holes.append(
				Rect2(
					origin + Vector2(col * cell, row * cell) + Vector2(cell * 0.08, cell * 0.08),
					Vector2.ONE * (cell * 0.84)
				)
			)
	if _stage != null:
		# Erst die Kamera stellen, dann die Hügel unter die Rechtecke raycasten.
		_stage.frame(view_size)
		_stage.layout(_holes)
	_layout_hud()
	queue_redraw()


## HUD IMMER aus dem Viewport-Rect stellen: unter canvas_items-Stretch sind
## Canvas-Einheiten ≠ Fensterpixel, apply_view-Größen können abweichen.
## W16 M9: alle Pixelmaße skalieren mit dem _ui-Faktor (Kurzkante/390).
func _layout_hud() -> void:
	if _time_label == null:
		return
	var vp := get_viewport_rect().size
	_time_label.position = Vector2(16.0, 8.0) * _ui
	_time_label.add_theme_font_size_override("font_size", int(26.0 * _ui))
	var hint_w := minf(vp.x - 32.0 * _ui, 360.0 * _ui)
	_hint_label.add_theme_font_size_override("font_size", int(15.0 * _ui))
	_hint_label.position = Vector2((vp.x - hint_w) * 0.5, vp.y - 48.0 * _ui)
	_hint_label.size = Vector2(hint_w, 42.0 * _ui)


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	add_child(_time_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.carrotGuard.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_hint_label)
	_banner_plate.set_corner_radius_all(12)
	_vignette_box.draw_center = false
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	# W16 Intro-Beat (M1): Kamera schwebt aus der Garten-Totale in die
	# Spielpose, das Ziel steht als Banner — elapsed und Spawn-Uhr warten,
	# der Lauf bleibt zahlengleich (Crosscheck-Vertrag unberührt).
	if _intro_left > 0.0:
		_intro_left = maxf(0.0, _intro_left - delta)
		_pulse += delta
		_stage.establish(1.0 if _reduced_motion() else 1.0 - _intro_left / INTRO_S)
		_banner_t = maxf(0.0, _banner_t - delta)
		_stage.sync(moles, king, carrots, _pulse, delta)
		_update_labels()
		queue_redraw()
		return
	elapsed += delta
	_pulse += delta
	_tick_hud_fx(delta)
	_spawn_tick(delta)
	_mole_tick(delta)
	if CarrotGuardLogic.is_round_over(
		{"elapsed": elapsed, "carrots": carrots}, float(tune["DURATION_SEC"]), tune
	):
		_finish()
		return
	_stage.sync(moles, king, carrots, _pulse, delta)
	_update_labels()
	queue_redraw()


func _spawn_tick(delta: float) -> void:
	if not king.is_empty():
		return
	next_spawn -= delta
	if next_spawn > 0.0:
		return
	next_spawn = CarrotGuardLogic.spawn_interval_at(elapsed, float(tune["DURATION_SEC"]), tune)
	if CarrotGuardLogic.is_king_due(bonks, kings_spawned):
		_spawn_king()
		return
	var count := 1
	if rng.next() < CarrotGuardLogic.double_chance_at(elapsed, float(tune["DURATION_SEC"]), tune):
		count = 2
	for _i in count:
		var free_holes := _free_holes()
		if free_holes.is_empty():
			return
		var hole: int = free_holes[mini(free_holes.size() - 1, int(rng.next() * free_holes.size()))]
		(
			moles
			. append(
				{
					"hole": hole,
					"left": CarrotGuardLogic.up_time_at(elapsed, float(tune["DURATION_SEC"]), tune),
					"up": 0.0,
				}
			)
		)


func _spawn_king() -> void:
	kings_spawned += 1
	var free_holes := _free_holes()
	if free_holes.is_empty():
		return
	king = {
		"hole": free_holes[mini(free_holes.size() - 1, int(rng.next() * free_holes.size()))],
		"hp": int(CarrotGuardLogic.GUARD["KING_TAPS"]),
		"up": 0.0,
	}
	AudioDirector.try_play(self, "gvz_boss")
	# W16 M7: zentriertes Banner mit Kontur statt float_text mit magischem
	# −110-px-Offset; dazu ein kurzer Gold-Vignette-Puls am Bildrand.
	_set_banner(I18nService.t("mg.carrotGuard.king"), true)
	_vignette = 0.55
	if ctx.juice != null:
		ctx.juice.bloom_pulse(0.8)


func _mole_tick(delta: float) -> void:
	if not king.is_empty():
		king["up"] = minf(1.0, float(king["up"]) + delta / float(tune["POP_SEC"]))
		return
	var kept: Array[Dictionary] = []
	for mole in moles:
		mole["up"] = minf(1.0, float(mole["up"]) + delta / float(tune["POP_SEC"]))
		mole["left"] = float(mole["left"]) - delta
		if float(mole["left"]) > 0.0:
			kept.append(mole)
			continue
		# Entwischt: eine Karotte weg, Kombo futsch.
		var had_combo := combo > 0
		var escaped := CarrotGuardLogic.apply_escape({"carrots": carrots, "combo": combo})
		carrots = int(escaped["carrots"])
		combo = int(escaped["combo"])
		# HUD-Echo des Klaus: die Möhre fliegt sichtbar aus ihrem Slot
		# (Index = neuer Bestand); Reduced Motion graut nur aus.
		if not _reduced_motion():
			_fly_icons.append({"slot": carrots, "t": 0.0})
		if had_combo:
			_pip_break = 0.45
		AudioDirector.try_play(self, "mg_spill")
		_stage.steal_fx(int(mole["hole"]))
		if ctx.juice != null:
			ctx.juice.shake(0.28)
			ctx.juice.hit_flash(Color(0.9, 0.4, 0.3, 0.12))
			ctx.juice.show_combo(0)
			ctx.juice.float_text(
				_holes[int(mole["hole"])].get_center(),
				I18nService.t("mg.carrotGuard.steal"),
				AcTokens.DANGER
			)
	moles = kept


func _free_holes() -> Array[int]:
	var used := {}
	for mole in moles:
		used[int(mole["hole"])] = true
	if not king.is_empty():
		used[int(king["hole"])] = true
	var out: Array[int] = []
	for i in _holes.size():
		if not used.has(i):
			out.append(i)
	return out


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished or _intro_left > 0.0:
		return
	var pressed := event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed
	if not pressed:
		return
	var since := elapsed - last_tap_at
	if not CarrotGuardLogic.accepts_tap_after(
		since, float(CarrotGuardLogic.GUARD["TAP_DEBOUNCE_SEC"])
	):
		return
	last_tap_at = elapsed
	var hole := _hole_at((event as InputEventScreenTouch).position)
	if hole < 0:
		return
	if not king.is_empty() and int(king["hole"]) == hole:
		_tap_king()
		return
	for i in moles.size():
		if int(moles[i]["hole"]) != hole:
			continue
		_bonk(i)
		return
	# Danebengehauen: kein Punktverlust, aber die Kombo ist weg.
	if combo > 0:
		_pip_break = 0.45
	combo = int(CarrotGuardLogic.apply_whiff({"combo": combo})["combo"])
	AudioDirector.try_play(self, "mg_junk", 0.9)
	_stage.whiff_fx(hole)
	if ctx.juice != null:
		ctx.juice.show_combo(0)


func _bonk(index: int) -> void:
	var hole := int(moles[index]["hole"])
	moles.remove_at(index)
	var result := CarrotGuardLogic.apply_bonk({"score": score, "combo": combo})
	var delta := int(result["score"]) - score
	score = int(result["score"])
	combo = int(result["combo"])
	bonks += 1
	var pos := _holes[hole].get_center()
	_stage.bonk_fx(hole)
	AudioDirector.try_play(self, "gvz_pop", 1.0 + 0.02 * minf(combo, 10.0))
	# Volle Fünferserie: die Kombo-Pips blitzen gold auf (persistente Anzeige).
	if int(result["bonus"]) > 0:
		_pip_flash = 0.6
	if ctx.juice != null:
		ctx.juice.float_text(pos, "+%d" % delta, AcTokens.LEAF_DARK)
		ctx.juice.hit_freeze(45)
		# Mitwachsende Combo-Anzeige mit steigendem Ton; Reset blendet sie aus.
		ctx.juice.show_combo(combo)
		if int(result["bonus"]) > 0:
			ctx.juice.bloom_pulse(0.5)
			ctx.juice.overlay_ring(pos, Color(1.0, 0.85, 0.45, 0.85), 64.0)
			ctx.juice.float_text(
				pos - Vector2(0.0, 40.0), I18nService.t("mg.carrotGuard.combo"), AcTokens.PINK
			)
	ctx.report_score(score, delta)


func _tap_king() -> void:
	var result := CarrotGuardLogic.apply_king_tap(
		{"score": score, "combo": combo, "hp": int(king["hp"])}
	)
	var pos := _holes[int(king["hole"])].get_center()
	king["hp"] = int(result["hp"])
	AudioDirector.try_play(self, "gvz_boom")
	if not bool(result["complete"]):
		_stage.king_hit_fx(int(king["hole"]))
		if ctx.juice != null:
			ctx.juice.shake(0.2)
			ctx.juice.float_text(pos, "×%d" % int(result["hp"]), AcTokens.GOLD)
		return
	var delta := int(result["score"]) - score
	score = int(result["score"])
	combo = int(result["combo"])
	bonks += 1
	_stage.king_down_fx(int(king["hole"]))
	king = {}
	if ctx.juice != null:
		ctx.juice.bloom_pulse(1.0)
		ctx.juice.slowmo(0.4, 260)
		ctx.juice.confetti(48)
		ctx.juice.show_combo(combo)
		ctx.juice.float_text(pos, I18nService.t("mg.carrotGuard.king_defeated"), AcTokens.GOLD)
	ctx.report_score(score, delta)


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	if carrots <= 0 and ctx.juice != null:
		ctx.juice.float_text(
			Vector2(view_size.x * 0.5 - 90.0, view_size.y * 0.4),
			I18nService.t("mg.carrotGuard.empty"),
			AcTokens.DANGER
		)
	ctx.report_end({"score": score, "carrots": carrots, "stolen": int(tune["CARROTS"]) - carrots})


func _update_labels() -> void:
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.carrotGuard.stolen",
			{"n": int(tune["CARROTS"]) - carrots, "max": int(tune["ENDLESS_STOLEN"])}
		)
	else:
		var left := maxf(0.0, float(tune["DURATION_SEC"]) - elapsed)
		_time_label.text = I18nService.t("mg.game.time", {"sec": int(ceil(left))})
		_sync_urgency(left)
	_hint_label.modulate.a = _hint_alpha()


## Timer-Urgenz (W16 Befund 5): unter 5 s Restzeit pulsiert die Zeit rot
## (Reduced Motion: statisch rot) und tickt einmal je Restsekunde mit
## steigendem Pitch — vorhandenes ui_tick, kein neues Audio-Asset.
func _sync_urgency(left: float) -> void:
	if left > URGENT_UNDER_S or left <= 0.0:
		_time_label.remove_theme_color_override("font_color")
		return
	var pulse := 1.0 if _reduced_motion() else 0.62 + 0.38 * sin(elapsed * 9.0)
	_time_label.add_theme_color_override(
		"font_color", Color(1.0, 0.85, 0.8).lerp(AcTokens.DANGER, pulse)
	)
	var sec := int(ceil(left))
	if sec != _last_tick_sec:
		_last_tick_sec = sec
		AudioDirector.try_play(self, "ui_tick", 0.9 + 0.5 * (1.0 - left / URGENT_UNDER_S))


## Zerfall der reinen HUD-Effekte (Banner, Vignette, Pip-Blitze, Klau-Flüge).
func _tick_hud_fx(delta: float) -> void:
	_banner_t = maxf(0.0, _banner_t - delta)
	_vignette = maxf(0.0, _vignette - delta)
	_pip_flash = maxf(0.0, _pip_flash - delta)
	_pip_break = maxf(0.0, _pip_break - delta)
	var kept: Array[Dictionary] = []
	for entry: Dictionary in _fly_icons:
		entry["t"] = float(entry["t"]) + delta
		if float(entry["t"]) < ICON_FLY_S:
			kept.append(entry)
	_fly_icons = kept


func _set_banner(text: String, gold := false, sec := 1.4) -> void:
	_banner = text
	_banner_gold = gold
	_banner_t = sec


## Reduced-Motion-Abfrage (Duck-Typing wie im JuiceKit — ohne Autoload = aus).
func _reduced_motion() -> bool:
	if not is_inside_tree():
		return true
	var settings := get_node_or_null(^"/root/AppSettings")
	if settings != null and settings.has_method("is_reduced_motion"):
		return settings.is_reduced_motion()
	return false


## Milchglas hinter Zeit/Möhrenreihe/Pips und dem Hinweis: die Wiese zog
## sonst direkt durch die Ziffern (Lesbarkeit auf dem Handy).
func _draw() -> void:
	if _time_label == null:
		return
	_draw_hud_block()
	_draw_fly_icons()
	var hint_a := _hint_alpha()
	if hint_a > 0.0:
		_hint_plate.bg_color = Color(1.0, 0.99, 0.94, 0.72 * hint_a)
		draw_style_box(
			_hint_plate, Rect2(_hint_label.position - Vector2(0.0, 2.0), _hint_label.size)
		)
	_draw_banner()
	_draw_vignette()


## Plate + Möhren-Icon-Reihe (10 Slots) + Kombo-Pips: die Verlust-Anzeige ist
## ablesbar statt „n/max“-Text (W16 Befund 1/3); der Klau graut den Slot aus.
func _draw_hud_block() -> void:
	var total := maxi(1, int(tune.get("CARROTS", 10)))
	var icons_end := _icon_rect(total - 1).end
	var pip_y := icons_end.y + 12.0 * _ui
	var pip_r := 5.0 * _ui
	var pad := Vector2(12.0, 6.0) * _ui
	var content_br := Vector2(
		maxf(_time_label.position.x + _time_label.size.x, icons_end.x), pip_y + pip_r
	)
	draw_style_box(
		_hud_plate, Rect2(_time_label.position - pad, content_br - _time_label.position + pad * 2.0)
	)
	for i in total:
		if i < carrots:
			_draw_carrot_icon(_icon_rect(i), ICON_BODY, ICON_LEAF)
		else:
			_draw_carrot_icon(_icon_rect(i), ICON_EMPTY, ICON_EMPTY)
	_draw_combo_pips(pip_y, pip_r)


## Slot-Rechteck einer HUD-Möhre (0-basiert) — auch der Klau-Flug startet hier.
func _icon_rect(i: int) -> Rect2:
	var s := 20.0 * _ui
	var origin := _time_label.position + Vector2(0.0, 36.0 * _ui)
	return Rect2(origin + Vector2(float(i) * (s + 4.0 * _ui), 0.0), Vector2(s, s))


## Stilisierte Mini-Möhre: Körper-Dreieck + zwei Blattschopf-Dreiecke.
func _draw_carrot_icon(rect: Rect2, body: Color, leaf: Color) -> void:
	var w := rect.size.x
	var p := rect.position
	var tri := PackedVector2Array(
		[p + Vector2(w * 0.16, w * 0.3), p + Vector2(w * 0.84, w * 0.3), p + Vector2(w * 0.5, w)]
	)
	draw_colored_polygon(tri, body)
	var left_leaf := PackedVector2Array(
		[
			p + Vector2(w * 0.5, w * 0.34),
			p + Vector2(w * 0.2, w * 0.02),
			p + Vector2(w * 0.42, w * 0.3),
		]
	)
	draw_colored_polygon(left_leaf, leaf)
	var right_leaf := PackedVector2Array(
		[
			p + Vector2(w * 0.5, w * 0.34),
			p + Vector2(w * 0.8, w * 0.02),
			p + Vector2(w * 0.58, w * 0.3),
		]
	)
	draw_colored_polygon(right_leaf, leaf)


## Der Klau fliegt SICHTBAR aus dem HUD: die Möhre des geleerten Slots segelt
## rotierend nach oben-rechts raus und verblasst (W16 Befund 1).
func _draw_fly_icons() -> void:
	for entry: Dictionary in _fly_icons:
		var f := clampf(float(entry["t"]) / ICON_FLY_S, 0.0, 1.0)
		var rect := _icon_rect(int(entry["slot"]))
		var center := rect.get_center() + Vector2(34.0, -50.0) * _ui * f
		var alpha := clampf(1.0 - f * 1.15, 0.0, 1.0)
		draw_set_transform(center, f * 2.4, Vector2.ONE)
		var local := Rect2(-rect.size * 0.5, rect.size)
		_draw_carrot_icon(local, Color(ICON_BODY, alpha), Color(ICON_LEAF, alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Kombo-Pips (W16 Befund 3): der Fortschritt zur 5er-Bonus-Kombo ist
## PERSISTENT ablesbar — Gold-Blitz beim Bonus, roter Riss-Blitz bei
## Whiff/Klau (unter Reduced Motion ohne Grössen-Puls).
func _draw_combo_pips(y: float, r: float) -> void:
	var filled := pip_fill_for(combo)
	var grow := 1.25 if _pip_flash > 0.0 and not _reduced_motion() else 1.0
	for i in 5:
		var at := Vector2(_time_label.position.x + r + float(i) * 16.0 * _ui, y)
		if i < filled:
			draw_circle(at, r * grow, PIP_GOLD if _pip_flash > 0.0 else PIP_FILL)
		else:
			var rim := PIP_BREAK if _pip_break > 0.0 else PIP_RING
			draw_arc(at, r - 1.0 * _ui, 0.0, TAU, 20, rim, 2.0 * _ui)


## Gefüllte Kombo-Pips (0..5) zum Stand `combo_now` — PUR für Tests: der
## Bonus zahlt bei JEDEM Vielfachen von 5, das fünfte Pip leuchtet also dort.
static func pip_fill_for(combo_now: int) -> int:
	if combo_now <= 0:
		return 0
	var m := combo_now % 5
	return 5 if m == 0 else m


## Banner mittig mit Milchglas-Plate und Kontur (M7, hide_seek-Muster) —
## König-Ankündigung und Intro-Ziel; lange Texte brechen um.
func _draw_banner() -> void:
	if _banner_t <= 0.0 or _banner.is_empty():
		return
	var font := ThemeService.font(800)
	var alpha := clampf(_banner_t * 1.4, 0.0, 1.0)
	var font_size := int(26.0 * _ui)
	var w := minf(view_size.x * 0.92, 460.0 * _ui)
	var text_size := font.get_multiline_string_size(
		_banner, HORIZONTAL_ALIGNMENT_CENTER, w, font_size
	)
	var top := view_size.y * 0.26
	var pad := Vector2(18.0 * _ui, 10.0 * _ui)
	_banner_plate.set_corner_radius_all(int(12.0 * _ui))
	_banner_plate.bg_color = (
		Color(1.0, 0.93, 0.62, 0.82 * alpha)
		if _banner_gold
		else Color(1.0, 0.99, 0.94, 0.74 * alpha)
	)
	var plate_pos := Vector2((view_size.x - text_size.x) * 0.5, top) - pad
	draw_style_box(_banner_plate, Rect2(plate_pos, text_size + pad * 2.0))
	var ink := Color(0.62, 0.4, 0.1, alpha) if _banner_gold else Color(0.32, 0.24, 0.28, alpha)
	var rim := Color(1.0, 1.0, 1.0, 0.75 * alpha)
	var at := Vector2((view_size.x - w) * 0.5, top + font.get_ascent(font_size))
	draw_multiline_string_outline(
		font, at, _banner, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, -1, int(5.0 * _ui), rim
	)
	draw_multiline_string(font, at, _banner, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, -1, ink)


## Kurzer Gold-Puls am Bildrand zur König-Ankündigung (M7-Zusatz).
func _draw_vignette() -> void:
	if _vignette <= 0.0:
		return
	var a := clampf(_vignette * 1.8, 0.0, 1.0)
	_vignette_box.set_border_width_all(int(10.0 * _ui))
	_vignette_box.set_corner_radius_all(int(18.0 * _ui))
	_vignette_box.border_color = Color(1.0, 0.8, 0.3, 0.5 * a)
	draw_style_box(_vignette_box, Rect2(Vector2.ZERO, view_size))


## Der Hinweis blendet nach ein paar Sekunden aus — das Beet gehört dann ganz
## den Maulwürfen.
func _hint_alpha() -> float:
	return clampf(1.0 - (elapsed - 5.0) / 1.5, 0.0, 1.0)


func _hole_at(screen: Vector2) -> int:
	for i in _holes.size():
		if _holes[i].has_point(screen):
			return i
	return -1
