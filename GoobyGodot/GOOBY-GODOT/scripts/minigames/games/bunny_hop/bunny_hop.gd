extends MinigameBase
## Hasenhüpfer (bunnyHop) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus BunnyHopLogic
## (zahlengleich zum Web, Bot-zertifiziert): Tippen = Hüpfen, Score = passierte
## Tore, Tempo +2 % je Tor, verzeihende Hitbox (70 % der Optik), die Lücke wird
## alle 10 Tore enger. Ab Sekunde 6 kommt Wind: erst Telegraf, dann ein
## 0,4-Bahnen-Schubs — währenddessen zählen Tore doppelt. Eine Berührung
## beendet den Lauf (in JEDEM Modus, wie im Web).
##
## ECHTE 3D-HECKENLANDSCHAFT (FB-4, BunnyHopStage3D): Gooby flattert als
## echtes Rig durch 3D-Heckensäulen mit Blätterkronen, dahinter Parallax-Hügel
## und Wolken. Die Kamera rahmt die Spielebene EXAKT wie die 2D-Rechnung
## (set_half_height), Spawn/Kollision bleiben zahlengleich. Die 3D-Welt hängt
## unter der Node2D-Wurzel, der MinigameBase-Vertrag bleibt unberührt.
##
## W17/G4-Politur (NUR Präsentation): Intro-Beat 1,5 s mit Kamera-Totale und
## Ziel-Banner — Gooby schwebt derweil, die Sim-Uhr wartet (M1). Der Böen-
## Telegraf sind jetzt wehende 3D-Partikel statt 2D-Linien (M4), der Crash
## bekommt einen sichtbaren Trudel-Sturz VOR dem Rundenende (M3, Wertung
## längst fix). HUD auf _ui-Skalierung mit Milchglas-Plates und Konturen,
## die Wind-/Verengungs-Popups laufen als zentriertes Banner statt
## float_text-Magic-Offsets (M7/M9), der Hinweis blendet nach dem ersten
## Hüpfer aus (M6).

const Stage := preload("res://scripts/minigames/games/bunny_hop/bunny_hop_stage3d.gd")

## Sichtbare Welt-Halbhöhe: FLOOR_Y −3.1 bis CEILING_Y 3.9 plus Rand.
const WORLD_HALF_H := 3.9
## Gooby steht bei dieser Bildschirm-Bruchbreite (Web: linkes Drittel).
const GOOBY_X_FRAC := 0.28
## Neue Säulen erscheinen so weit rechts neben dem Bildrand (Web: halfW+1.6).
const SPAWN_MARGIN := 1.6
## Vor dem ersten Hüpfer schwebt Gooby (Web: y = 0.4 + sin(t·3)·0.12).
const HOVER_Y := 0.4
const HOVER_AMP := 0.12
## W17 M9: Entwurfs-Kurzkante — HUD-Pixelmaße skalieren damit (hide_seek-Muster).
const DESIGN_SHORT := 390.0
## W17 M1: Intro-Beat (s) — Kamera-Totale + Ziel-Banner, die Sim-Uhr wartet.
const INTRO_S := 1.5
## W17 M3: Trudel-Sturz (s) nach dem Crash, DANN erst endet die Runde.
const CRASH_FALL_S := 0.9
## Warm-weiße Kontur der HUD-Labels (M7): hebt Ziffern von Himmel/Hecke ab.
const OUTLINE_RIM := Color(1.0, 0.99, 0.94, 0.9)

var tune: Dictionary = {}
var rng: GoobyRng
var gates := 0
var score := 0
var elapsed := 0.0
var gooby_y := 0.0
var gooby_vy := 0.0
var pillars: Array[Dictionary] = []
var coins: Array[Dictionary] = []
var scroll := 0.0
var next_pillar_x := INF
var last_gap_center := INF
var last_gust_index := -1
var finished := false
## Web-Parität: Schwerkraft, Scroll UND Kollision warten auf den ERSTEN Tipp,
## damit weder der Countdown noch ein zögernder Spieler Gooby abstürzen lässt.
var started := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

var _time_label: Label
var _gate_label: Label
var _hint_label: Label
var _stage: Node3D
var _pulse := 0.0
var _ear := 0.0
var _ui := 1.0
var _intro_left := 0.0
var _crash_left := 0.0
## Hint-Fade-Uhr (M6): tickt erst ab dem ersten Hüpfer — der Hinweis erklärt
## genau diesen ersten Tipp und darf vorher nicht verschwinden.
var _hint_seen := 0.0
var _banner := ""
var _banner_t := 0.0
var _banner_plate := StyleBoxFlat.new()
var _hud_plate := _make_hud_plate()
var _hint_plate := _make_hud_plate()


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = BunnyHopLogic.apply_difficulty(BunnyHopLogic.HOP, ctx.difficulty)
	rng = ctx.rng()
	gooby_y = HOVER_Y
	gooby_vy = 0.0
	# RNG-Parität mit der 2D-Fassung: die vier Wolken-Würfe (je 3 Züge) bleiben
	# im Seed-Strom, sonst verschieben sich alle späteren Lücken-Zentren.
	for _i in 4 * 3:
		rng.next()
	_stage = Stage.new()
	_stage.name = "Hecke3D"
	add_child(_stage)
	_stage.setup_stage(float(tune["FLOOR_Y"]))
	if ctx.juice != null:
		ctx.juice.world_environment = _stage.stage.world_env
	_build_hud()
	_fit_viewport()
	_banner_plate.set_corner_radius_all(12)
	# W17 M1: Intro-Beat — Kamera-Totale über der Wiese, Gooby schwebt als
	# Aufhänger; die Sim-Uhr (elapsed = Windfahrplan) und der Start-Tipp
	# warten, der Lauf bleibt danach zahlengleich.
	_intro_left = INTRO_S
	_set_banner(I18nService.t("mg.bunnyHop.intro"), INTRO_S + 0.7)
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
		_stage.apply_size(view_size)
	_layout_hud()
	_update_labels()
	queue_redraw()


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	_time_label.add_theme_color_override("font_outline_color", OUTLINE_RIM)
	add_child(_time_label)
	_gate_label = Label.new()
	_gate_label.theme_type_variation = &"CaptionLabel"
	_gate_label.add_theme_color_override("font_outline_color", OUTLINE_RIM)
	add_child(_gate_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.bunnyHop.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.add_theme_color_override("font_outline_color", Color(OUTLINE_RIM, 0.6))
	add_child(_hint_label)
	_layout_hud()
	_update_labels()


## HUD IMMER aus dem Viewport-Rect stellen: unter canvas_items-Stretch sind
## Canvas-Einheiten ≠ Fensterpixel. W17 M9: alle Pixelmaße skalieren mit dem
## _ui-Faktor statt in Fix-Pixeln zu kleben, die Hinweis-Breite hängt an
## vp.x statt an Fix-340-px (das Hint-Clipping des Audits), dazu Konturen
## auf Tore/Wind-Zeile (M7).
func _layout_hud() -> void:
	if _time_label == null:
		return
	var vp := get_viewport_rect().size
	_time_label.position = Vector2(16.0, 10.0) * _ui
	_time_label.add_theme_font_size_override("font_size", int(34.0 * _ui))
	_time_label.add_theme_constant_override("outline_size", int(6.0 * _ui))
	_gate_label.position = Vector2(16.0, 48.0) * _ui
	_gate_label.add_theme_font_size_override("font_size", int(15.0 * _ui))
	_gate_label.add_theme_constant_override("outline_size", int(5.0 * _ui))
	_layout_hint(vp, 8.0)


## M9: Hinweis unten mittig — Breite folgt vp.x/_ui, Höhe dem umbrochenen
## Text (lange Übersetzungen liefen vorher aus dem Fix-340-px-Kasten).
func _layout_hint(vp: Vector2, bottom_pad: float) -> void:
	var hint_w := minf(vp.x - 32.0 * _ui, 360.0 * _ui)
	var font_size := int(20.0 * _ui)
	_hint_label.add_theme_font_size_override("font_size", font_size)
	_hint_label.add_theme_constant_override("outline_size", int(5.0 * _ui))
	var font := _hint_label.get_theme_font("font")
	var text_size := font.get_multiline_string_size(
		_hint_label.text, HORIZONTAL_ALIGNMENT_CENTER, hint_w, font_size
	)
	var box := Vector2(hint_w, text_size.y + 6.0 * _ui)
	_hint_label.position = Vector2((vp.x - box.x) * 0.5, vp.y - box.y - bottom_pad * _ui)
	_hint_label.size = box


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	_pulse += delta
	_ear = maxf(0.0, _ear - delta * 3.0)
	# W17 M3: Crash-Sturz — die Welt steht, Gooby trudelt sichtbar zu Boden,
	# DANN endet die Runde (Wertung steht längst fest, nur Präsentation).
	if _crash_left > 0.0:
		_crash_left = maxf(0.0, _crash_left - delta)
		_banner_t = maxf(0.0, _banner_t - delta)
		_stage.crash_fall(delta, float(tune["FLOOR_Y"]))
		queue_redraw()
		if _crash_left <= 0.0:
			_finish()
		return
	# W17 M1: Intro-Beat — Kamera-Totale + Ziel-Banner; elapsed (und damit
	# der Windfahrplan) wartet, Gooby schwebt nur. Der Bob klingt zum Ende
	# des Beats aus, damit er nahtlos in das elapsed-Schweben übergeht.
	if _intro_left > 0.0:
		_intro_left = maxf(0.0, _intro_left - delta)
		_banner_t = maxf(0.0, _banner_t - delta)
		_stage.establish(1.0 if _reduced_motion() else 1.0 - _intro_left / INTRO_S)
		var bob := 0.0
		if not _reduced_motion():
			bob = sin(_pulse * 3.0) * HOVER_AMP * (_intro_left / INTRO_S)
		_sync_stage(delta, HOVER_Y + bob)
		_update_labels()
		queue_redraw()
		return
	_banner_t = maxf(0.0, _banner_t - delta)
	elapsed += delta
	if not started:
		# Vorstart-Schweben: kein Scroll, keine Tore, keine Kollision.
		gooby_y = HOVER_Y + sin(elapsed * 3.0) * HOVER_AMP
		_sync_stage(delta)
		_update_labels()
		queue_redraw()
		return
	_hint_seen += delta
	var speed := BunnyHopLogic.speed_at_gate(gates, tune)
	scroll += speed * delta
	var physics := BunnyHopLogic.step_physics({"y": gooby_y, "vy": gooby_vy}, delta, tune)
	gooby_y = float(physics["y"])
	gooby_vy = float(physics["vy"])
	_gust_tick()
	_pillar_tick()
	_coin_tick()
	if _crashed():
		_crash()
		return
	_sync_stage(delta)
	_update_labels()
	queue_redraw()


## `visual_y` überschreibt NUR die gezeichnete Gooby-Höhe (Intro-Schweben) —
## die Sim-Variable gooby_y bleibt unangetastet.
func _sync_stage(delta: float, visual_y := INF) -> void:
	# W17 M4: Böen-Telegraf als wehende Partikel statt 2D-Linien — Reduced
	# Motion gatet an DIESER Call-Site (Q2-Regel), der Warntext bleibt immer.
	var phase := BunnyHopLogic.gust_phase_at(elapsed, tune)
	_stage.set_wind("none" if _reduced_motion() else str(phase["phase"]), int(phase["direction"]))
	_stage.sync(
		pillars,
		coins,
		_gooby_world_x(),
		visual_y if is_finite(visual_y) else gooby_y,
		gooby_vy,
		scroll,
		float(tune["PILLAR_HALF_W"]),
		0.04,
		_pulse,
		delta
	)


## Der eine Windschubs pro Zyklus — exakt beim Übergang in die Böe.
## W17 M7: zentriertes Banner mit Kontur statt float_text mit Magic-Offset.
func _gust_tick() -> void:
	var phase := BunnyHopLogic.gust_phase_at(elapsed, tune)
	if str(phase["phase"]) != "gust" or int(phase["index"]) == last_gust_index:
		return
	last_gust_index = int(phase["index"])
	gooby_y = BunnyHopLogic.apply_gust_shift(gooby_y, int(phase["direction"]), tune)
	AudioDirector.try_play(self, "mg_spill", 1.2)
	_set_banner(I18nService.t("mg.bunnyHop.gust"), 1.4)
	if ctx.juice != null:
		ctx.juice.shake(0.25)


func _pillar_tick() -> void:
	var gooby_x := _gooby_world_x()
	for pillar in pillars:
		if bool(pillar["passed"]) or float(pillar["x"]) - scroll > gooby_x:
			continue
		pillar["passed"] = true
		gates += 1
		var gusting := str(BunnyHopLogic.gust_phase_at(elapsed, tune)["phase"]) == "gust"
		var points := BunnyHopLogic.gate_points(gusting)
		score += points
		AudioDirector.try_play(self, "mg_good", 1.0 + 0.01 * minf(gates, 20.0))
		if ctx.juice != null:
			ctx.juice.float_text(
				_stage.gooby_screen() + Vector2(40.0, 0.0),
				"+%d" % points,
				AcTokens.GOLD if gusting else AcTokens.LEAF_DARK
			)
			if gusting:
				ctx.juice.bloom_pulse(0.5)
		if BunnyHopLogic.gap_narrows_at_gate(gates, tune):
			AudioDirector.try_play(self, "mg_combo")
			# W17 M7: Banner statt float_text-Magic-Offset.
			_set_banner(I18nService.t("mg.bunnyHop.narrow"), 1.2)
		ctx.report_score(BunnyHopLogic.final_hop_score(score, tune), points)
	# Passierte Säulen entsorgen und Nachschub setzen.
	var kept: Array[Dictionary] = []
	for pillar in pillars:
		if float(pillar["x"]) - scroll > -2.0:
			kept.append(pillar)
	pillars = kept
	_spawn_due_pillars()


## Web-Parität: die nächste Säule wird erst geboren, wenn ihr Slot in den
## Rand-Streifen rechts vom Bild rutscht — nie ein Vorrat auf Halde.
func _spawn_due_pillars() -> void:
	var edge := _view_width_world() + SPAWN_MARGIN
	if not is_finite(next_pillar_x):
		next_pillar_x = edge
	while next_pillar_x - scroll < edge:
		_spawn_pillar()


func _spawn_pillar() -> void:
	var gap := BunnyHopLogic.gap_at_gate(gates, tune)
	var center := BunnyHopLogic.roll_gap_center(rng, gap, last_gap_center, tune)
	last_gap_center = center
	var at_x := next_pillar_x
	next_pillar_x += float(tune["PILLAR_SPACING_X"])
	pillars.append({"x": at_x, "gapCenterY": center, "gapHeight": gap, "passed": false})
	if BunnyHopLogic.coin_spawns(rng.next(), tune):
		coins.append({"x": at_x, "y": center, "taken": false})


func _coin_tick() -> void:
	var gooby_x := _gooby_world_x()
	var kept: Array[Dictionary] = []
	for coin in coins:
		var cx := float(coin["x"]) - scroll
		if cx < -2.0:
			continue
		if not bool(coin["taken"]) and absf(cx - gooby_x) < 0.42:
			if absf(float(coin["y"]) - gooby_y) < 0.5:
				coin["taken"] = true
				score += 1
				AudioDirector.try_play(self, "gvz_collect")
				_stage.coin_fx(cx, float(coin["y"]))
				if ctx.juice != null:
					ctx.juice.float_text(
						_stage.gooby_screen() + Vector2(30.0, -30.0), "+1", AcTokens.GOLD
					)
				ctx.report_score(BunnyHopLogic.final_hop_score(score, tune), 1)
				continue
		kept.append(coin)
	coins = kept


func _crashed() -> bool:
	var gooby_x := _gooby_world_x()
	for pillar in pillars:
		var local := {
			"x": float(pillar["x"]) - scroll,
			"gapCenterY": pillar["gapCenterY"],
			"gapHeight": pillar["gapHeight"]
		}
		if BunnyHopLogic.collides({"x": gooby_x, "y": gooby_y}, local, tune):
			return true
	return false


func _crash() -> void:
	AudioDirector.try_play(self, "mg_lose")
	_stage.crash_fx()
	_sync_stage(0.0)
	# W17 M7: „Rums!" als zentriertes Banner statt float_text-Magic-Offset.
	_set_banner(I18nService.t("mg.bunnyHop.crash"), CRASH_FALL_S + 0.5)
	if ctx.juice != null:
		# W14 Quick-Win: Crash beendet die Runde — 0,6er-Shake ohne Blitz wirkte
		# dafür zu zart (Audit d: „Rums!"-Moment zu klein). Nur Präsentation.
		ctx.juice.shake(0.9)
		ctx.juice.hit_freeze(120)
		ctx.juice.hit_flash(Color(0.92, 0.32, 0.28, 0.3), 180)
	# W17 M3: sichtbarer Trudel-Sturz VOR dem Rundenende (nur Präsentation,
	# Score/Tore stehen fest); Reduced Motion endet sofort wie bisher.
	if _reduced_motion():
		_finish()
		return
	_crash_left = CRASH_FALL_S
	_stage.begin_crash_fall()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished or _intro_left > 0.0 or _crash_left > 0.0:
		return
	var pressed := event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed
	if not pressed:
		return
	started = true
	gooby_vy = float(tune["HOP_VY"])
	_ear = 1.0
	_stage.hop_fx()
	AudioDirector.try_play(self, "gvz_pop", 1.1)


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	ctx.report_end({"score": BunnyHopLogic.final_hop_score(score, tune), "gates": gates})


func _update_labels() -> void:
	if _time_label == null:
		return
	_time_label.text = I18nService.t("mg.bunnyHop.gates", {"n": gates})
	var phase := BunnyHopLogic.gust_phase_at(elapsed, tune)
	if str(phase["phase"]) == "telegraph":
		_gate_label.text = I18nService.t("mg.bunnyHop.gust_warn")
	elif str(phase["phase"]) == "gust":
		_gate_label.text = I18nService.t("mg.bunnyHop.gust")
	else:
		_gate_label.text = ""
	_hint_label.modulate.a = _hint_alpha()


## Der Hinweis erklärt den ERSTEN Tipp: volle Deckkraft bis zum Start, danach
## blendet er nach ein paar Sekunden aus (M6, carrot_guard-Muster).
func _hint_alpha() -> float:
	if not started:
		return 1.0
	return clampf(1.0 - (_hint_seen - 4.0) / 1.5, 0.0, 1.0)


func _ppu() -> float:
	return view_size.y / (WORLD_HALF_H * 2.0 + 0.6)


## Sichtbare Weltbreite in Welteinheiten (x=0 ist der linke Bildrand).
func _view_width_world() -> float:
	return view_size.x / _ppu()


func _gooby_world_x() -> float:
	return view_size.x * GOOBY_X_FRAC / _ppu()


## Nur noch HUD-Overlay: Milchglas hinter den Labels + zentrierte Banner —
## der Böen-Telegraf lebt jetzt als wehende Partikel in der Bühne (M4), die
## WARNUNG bleibt als Text in der Wind-Zeile und im Böen-Banner lesbar.
func _draw() -> void:
	_draw_hud_backing()
	_draw_banner()


## Milchglas hinter Tore-/Wind-Zeile und dem Hinweis (M6/M7): die Labels
## standen vorher nackt auf Himmel und Hecke.
static func _make_hud_plate() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1.0, 0.99, 0.94, 0.72)
	box.set_corner_radius_all(16)
	return box


func _draw_hud_backing() -> void:
	if _time_label == null:
		return
	var pad := Vector2(12.0, 6.0) * _ui
	var top_left := _time_label.position - pad
	var bottom_right := (
		_gate_label.position
		+ Vector2(maxf(_time_label.size.x, _gate_label.size.x), _gate_label.size.y)
		+ pad
	)
	draw_style_box(_hud_plate, Rect2(top_left, bottom_right - top_left))
	var hint_a := _hint_alpha()
	if hint_a > 0.0:
		_hint_plate.bg_color = Color(1.0, 0.99, 0.94, 0.72 * hint_a)
		draw_style_box(
			_hint_plate, Rect2(_hint_label.position - Vector2(0.0, 2.0), _hint_label.size)
		)


func _set_banner(text: String, sec := 1.4) -> void:
	_banner = text
	_banner_t = sec


## Zentriertes Banner mit Milchglas-Plate und Kontur (M7, carrot_guard-
## Muster) — ersetzt die float_text-Magic-Offsets; lange Texte brechen um.
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


## Reduced-Motion-Abfrage (Duck-Typing wie im JuiceKit — ohne Autoload = aus).
func _reduced_motion() -> bool:
	if not is_inside_tree():
		return true
	var settings := get_node_or_null(^"/root/AppSettings")
	if settings != null and settings.has_method("is_reduced_motion"):
		return settings.is_reduced_motion()
	return false
