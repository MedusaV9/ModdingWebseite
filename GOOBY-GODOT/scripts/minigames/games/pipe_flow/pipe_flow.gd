extends MinigameBase
## Rohr-Wirrwarr (pipeFlow) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## PipeFlowLogic (zahlengleich zum Web, Board-Deals gegen Web-Golddeals
## gepinnt): 5×5-Brett, Antippen dreht eine Kachel 90°, verbundene Leitung vom
## Hahn (oben) zum Sprenger (unten) löst das Rätsel. 90 s; Score = 25·gelöst +
## Tap-Effizienz-Bonus (0–10) − 5 je Leck. Ab Rätsel 3 tropft eine Stelle und
## kostet nach LEAK_SEC fünf Punkte. Endlos endet nach drei Patzern.
##
## ECHTES 3D-ROHRPANEL (MP-D, PipeFlowStage3D): das Blaupausen-Brett steht als
## 3D-Panel in einer Gärtnerei (Hügel, Hecke, Wolken), Kacheln sind echte
## Rohrstücke über MultiMesh (Draw-Call-Diät), Wasser leuchtet als Kern durch
## die Leitung, unten sprüht der Sprenger ins 3D-Beet und Gooby (echtes Rig)
## schraubt auf seinem Hocker mit. Jeder Tap dreht die Kachel SICHTBAR, alles
## am Hahn Angeschlossene ist blass blau getintet (sichtbarer Fortschritt).
## Eingabe bleibt zahlengleich (Canvas-Rechtecke), 2D bleibt nur der
## Leck-Countdown-Ring. MECHANIK komplett in PipeFlowLogic.
##
## W17/G5-Politur (NUR Präsentation): Intro-Beat 1,5 s mit Puzzle-Totale
## (die Sim wartet, M1), _ui-Skalierung des HUD samt Konturen auf Zeit-/
## Rätsel-Label (M9/M7), Hint-Fade (Q3), „Verbunden!“ als Banner-Plate statt
## rohem float_text (M7), Reduced-Motion-Gates an den eigenen Stage-Burst-
## Call-Sites (Q2) und Fluss-Start-Moment: läuft das Wasser los, pulst eine
## Kette durch die verbundenen Rohre (RM: statischer Fortschritts-Tint
## bleibt) und ein Gluck-Foley (care_spuelung) untermalt die Füllwelle.

const WATER := Color("4FD8F7")

const Stage := preload("res://scripts/minigames/games/pipe_flow/pipe_flow_stage3d.gd")

## W17 M9: Entwurfs-Kurzkante — HUD-Pixelmaße skalieren damit (G4-Muster).
const DESIGN_SHORT := 390.0
## W17 M1: Intro-Beat (s) — Puzzle-Totale vom Beet hoch, die Sim wartet.
const INTRO_S := 1.5
## Q3: der Hinweis blendet nach ~6 s Spielzeit über 1,5 s aus (G2-Muster).
const HINT_FADE_AT := 6.0
const HINT_FADE_SEC := 1.5

var tune: Dictionary = {}
var board: Dictionary = {}
var puzzle_no := 0
var solved := 0
var failures := 0
## Lösungs-Serie ohne Leck (nur Anzeige/Feel — Combo-Ton steigt mit).
var solve_streak := 0
var total_taps := 0
var optimal_taps := 0
var elapsed := 0.0
var puzzle_elapsed := 0.0
var leak_index := -1
var leak_applied := false
var fill_left := 0.0
var filling := false
var fill_depth := 0
var depths: Dictionary = {}
## Kacheln, die aktuell am Hahn hängen (water_reach-Tiefen) — Cache für den
## Fortschritts-Tint der Bühne, neu berechnet je Tap/Rätsel statt je Frame.
var reach: Dictionary = {}
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

var _time_label: Label
var _puzzle_label: Label
var _hint_label: Label
var _grid_origin := Vector2.ZERO
var _cell := 60.0
var _pulse := 0.0
var _stage: Node3D
## W17 M9: HUD-Skalenfaktor (Kurzkante/390, geklemmt 0.75..3.0).
var _ui := 1.0
## W17 M1: Rest-Sekunden des Intro-Beats (0 = Spielbetrieb).
var _intro_left := 0.0
## Banner-Plate (M7): trägt Intro-Ziel und die „Verbunden!“-Meldung.
var _banner_text := ""
var _banner_t := 0.0
var _banner_plate := StyleBoxFlat.new()


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = PipeFlowLogic.apply_difficulty(PipeFlowLogic.PIPE, ctx.difficulty)
	_stage = Stage.new()
	_stage.name = "Panel3D"
	add_child(_stage)
	_stage.setup_stage()
	if ctx.juice != null:
		ctx.juice.world_environment = _stage.stage.world_env
	_build_hud()
	_next_puzzle()
	_fit_viewport()
	_banner_plate.set_corner_radius_all(12)
	# W17 M1: Intro-Beat — die Kamera steigt vom Blumenbeet zur frontalen
	# Puzzle-Totale; Rundenuhr, Leck-Uhr und Eingabe warten, der Lauf bleibt
	# danach zahlengleich (Crosscheck-Vertrag unberührt).
	_intro_left = INTRO_S
	_set_banner(I18nService.t("mg.pipeFlow.intro"), INTRO_S + 0.7)
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
	var grid := int(PipeFlowLogic.PIPE["GRID"])
	var top := 104.0 if not landscape else 60.0
	var bottom := 62.0
	var avail := Vector2(view_size.x - 24.0, maxf(120.0, view_size.y - top - bottom))
	_cell = minf(avail.x, avail.y) / float(grid)
	var board_px := _cell * grid
	# Etwas oberhalb der Mitte: der Rest unten trägt Fallrohr + Sprenger-Beet,
	# damit im Hochformat keine tote Fläche stehen bleibt.
	_grid_origin = Vector2((view_size.x - board_px) * 0.5, top + (avail.y - board_px) * 0.42)
	_layout_stage()
	_layout_hud()
	queue_redraw()


## Bühne an die aktuellen Brett-Anker hängen (srcCol/goalCol je Rätsel neu!).
func _layout_stage() -> void:
	if _stage == null or board.is_empty():
		return
	_stage.frame(view_size)
	_stage.layout(
		_grid_origin,
		_cell,
		int(board["size"]),
		int(board["srcCol"]),
		int(board["goalCol"]),
		_bed_y()
	)


## HUD IMMER aus dem Viewport-Rect stellen: unter canvas_items-Stretch sind
## Canvas-Einheiten ≠ Fensterpixel, apply_view-Größen können abweichen.
## W17 M9: alle Pixelmaße skalieren mit _ui; die Hinweis-Breite hängt an
## vp.x statt an fixen 360 px (Tablet-Krümelschrift des Audits).
func _layout_hud() -> void:
	if _time_label == null:
		return
	var vp := get_viewport_rect().size
	_time_label.position = Vector2(16.0, 10.0) * _ui
	_time_label.add_theme_font_size_override("font_size", int(34.0 * _ui))
	_puzzle_label.position = Vector2(16.0, 48.0) * _ui
	_puzzle_label.add_theme_font_size_override("font_size", int(15.0 * _ui))
	var hint_w := minf(vp.x - 32.0 * _ui, 360.0 * _ui)
	var font_size := int(20.0 * _ui)
	_hint_label.add_theme_font_size_override("font_size", font_size)
	var font := _hint_label.get_theme_font("font")
	var text_size := font.get_multiline_string_size(
		_hint_label.text, HORIZONTAL_ALIGNMENT_CENTER, hint_w, font_size
	)
	var box := Vector2(hint_w, text_size.y + 6.0 * _ui)
	_hint_label.position = Vector2((vp.x - box.x) * 0.5, vp.y - box.y - 8.0 * _ui)
	_hint_label.size = box
	for label: Label in [_time_label, _puzzle_label, _hint_label]:
		label.add_theme_constant_override("outline_size", int(6.0 * _ui))


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	add_child(_time_label)
	_puzzle_label = Label.new()
	_puzzle_label.theme_type_variation = &"CaptionLabel"
	add_child(_puzzle_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.pipeFlow.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_hint_label)
	# Vor Himmel UND Wiese lesbar: heller Text mit dunkler Kontur — jetzt
	# auf ALLEN drei Labels (Zeit/Rätsel hatten vorher keine Overrides und
	# soffen als Theme-Standard vor dem hellen Himmel ab, M7).
	for label: Label in [_time_label, _puzzle_label, _hint_label]:
		label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.97))
		label.add_theme_color_override("font_outline_color", Color(0.16, 0.3, 0.24, 0.85))
		label.add_theme_constant_override("outline_size", 6)
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _next_puzzle() -> void:
	puzzle_no += 1
	# Dieselbe Deal-Formel wie der Zertifizierungs-Bot: seed·1009 + Rätselnummer.
	board = PipeFlowLogic.generate_board(ctx.run_seed * 1009 + puzzle_no, tune)
	optimal_taps += int(board["optimalTaps"])
	leak_index = PipeFlowLogic.leak_joint_for(board, puzzle_no, tune)
	leak_applied = false
	puzzle_elapsed = 0.0
	filling = false
	fill_depth = 0
	depths = {}
	reach = PipeFlowLogic.water_reach(board)["depths"]
	_layout_stage()
	_update_labels()


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	_banner_t = maxf(0.0, _banner_t - delta)
	_pulse += delta
	# W17 M1: Intro-Beat — die Kamera steigt vom Beet zur Puzzle-Totale, das
	# Ziel steht als Banner; Runden-/Leck-Uhr warten, der Lauf bleibt
	# zahlengleich. Reduced Motion überspringt die Fahrt (Call-Site-Gate)
	# und hält nur den Banner-Beat.
	if _intro_left > 0.0:
		_intro_left = maxf(0.0, _intro_left - delta)
		_stage.establish(1.0 if _reduced_motion() else 1.0 - _intro_left / INTRO_S)
		_sync_and_labels(delta)
		return
	elapsed += delta
	puzzle_elapsed += delta
	if filling:
		_fill_tick(delta)
	elif leak_index >= 0 and PipeFlowLogic.leak_penalty_due(puzzle_elapsed, leak_applied, tune):
		_apply_leak()
	if not bool(tune["ENDLESS"]) and elapsed >= float(tune["DURATION_SEC"]):
		_finish()
		return
	if PipeFlowLogic.endless_should_end(failures, tune):
		_finish()
		return
	_sync_and_labels(delta)


## Bühne + HUD eines Frames stellen (läuft im Intro UND im Spielbetrieb).
func _sync_and_labels(delta: float) -> void:
	var tiles: Array = board["tiles"]
	var watered: Array[bool] = []
	for i in tiles.size():
		watered.append(_tile_watered(i))
	var leak_pending := leak_index if (leak_index >= 0 and not leak_applied and not filling) else -1
	_stage.sync(tiles, watered, reach, filling, leak_pending, _pulse, delta)
	_update_labels()
	queue_redraw()


## Wasser läuft in BFS-Tiefenschritten durch die verbundene Leitung.
func _fill_tick(delta: float) -> void:
	fill_left -= delta
	if fill_left > 0.0:
		return
	var max_depth := 0
	for value: int in depths.values():
		max_depth = maxi(max_depth, value)
	if fill_depth <= max_depth:
		fill_depth += 1
		fill_left = float(tune["FILL_STEP_SEC"])
		# Wasserlauf klettert hörbar die Tonleiter hoch (Halbton pro Stufe).
		AudioDirector.try_play(self, "mg_good", 0.9 * FeelSfx.combo_pitch(fill_depth))
		return
	filling = false
	fill_left = 0.0
	_next_puzzle()


func _apply_leak() -> void:
	leak_applied = true
	failures += 1
	solve_streak = 0
	# Q2: Reduced-Motion-Gate an der eigenen Stage-Burst-Call-Site.
	_stage.leak_fx(leak_index, _reduced_motion())
	AudioDirector.try_play(self, "mg_spill")
	if ctx.juice != null:
		ctx.juice.shake(0.3)
		ctx.juice.hit_flash(Color(0.5, 0.65, 0.95, 0.18), 180)
		ctx.juice.sfx("game_miss")
		ctx.juice.show_combo(0)
		ctx.juice.float_text(
			_cell_center(leak_index), I18nService.t("mg.pipeFlow.leak"), AcTokens.DANGER
		)
	ctx.report_score(_live_score(), -int(tune["LEAK_PENALTY"]))


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished or filling or _intro_left > 0.0:
		return
	var pressed := event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed
	if not pressed:
		return
	var index := _cell_at((event as InputEventScreenTouch).position)
	if index < 0:
		return
	var tiles: Array = board["tiles"]
	tiles[index] = PipeFlowLogic.rotate_tile(tiles[index])
	total_taps += 1
	_stage.tap_fx(index)
	AudioDirector.try_play(self, "ui_chip", 1.0 + 0.04 * float(index % 5))
	var result := PipeFlowLogic.water_reach(board)
	var grown: bool = (result["depths"] as Dictionary).size() > reach.size()
	reach = result["depths"]
	# Hörbare Zug-Bestätigung: schließt der Dreh neue Rohre ans Wasser an,
	# klingt ein hellerer Anschluss-Plop obendrauf.
	if grown and not bool(result["solved"]):
		FeelSfx.play(self, "game_pop", 1.0 + 0.03 * float(reach.size()))
	if bool(result["solved"]):
		_solve(result)
	queue_redraw()


func _solve(result: Dictionary) -> void:
	solved += 1
	solve_streak += 1
	depths = result["depths"]
	filling = true
	fill_depth = 0
	fill_left = 0.0
	var grid := int(board["size"])
	var reduced := _reduced_motion()
	# Q2: Reduced-Motion-Gate an der eigenen Stage-Burst-Call-Site.
	_stage.solve_fx((grid - 1) * grid + int(board["goalCol"]), reduced)
	# Fluss-Start-Moment: eine Puls-Kette läuft in Anschluss-Reihenfolge
	# durch die gelegte Leitung (RM: der statische Fortschritts-Tint bleibt)
	# und ein Gluck-Foley untermalt die loslaufende Füllwelle.
	if not reduced:
		_stage.flow_fx(depths)
	AudioDirector.try_play(self, "care_spuelung")
	# Lösungs-Serie ohne Leck: Sieges-Ton klettert pro Puzzle.
	AudioDirector.try_play(self, "mg_win", FeelSfx.combo_pitch(solve_streak))
	# M7: „Verbunden!“ als Banner-Plate statt rohem float_text — die Meldung
	# ist eine SCREEN-Meldung, die Ring-/Funken-Feier bleibt am Auslauf.
	_set_banner(I18nService.t("mg.pipeFlow.solved"), 1.4)
	if ctx.juice != null:
		ctx.juice.bloom_pulse(0.9)
		ctx.juice.hit_freeze(70)
		var size := int(board["size"])
		var goal_center := _cell_center((size - 1) * size + int(board["goalCol"]))
		ctx.juice.ring_burst(self, goal_center, AcTokens.TEAL_DARK, 90.0)
		ctx.juice.burst(self, goal_center, Color(0.5, 0.85, 0.95), 16)
		if solve_streak >= 2:
			ctx.juice.show_combo(solve_streak)
		# Ab drei Lösungen in Serie regnet Konfetti — der große Belohnungsmoment.
		if solve_streak >= 3:
			ctx.juice.confetti(70)
	ctx.report_score(_live_score(), int(tune["SOLVE_POINTS"]))


func _live_score() -> int:
	return PipeFlowLogic.pipe_score(solved, total_taps, optimal_taps, tune, failures)


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	ctx.report_end(
		{"score": _live_score(), "solved": solved, "failures": failures, "taps": total_taps}
	)


func _update_labels() -> void:
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.pipeFlow.failures", {"n": failures, "max": int(tune["ENDLESS_FAILURE_LIMIT"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - elapsed)))
		_time_label.text = I18nService.t("mg.game.time", {"sec": left})
	_puzzle_label.text = (
		"%s · %s"
		% [
			I18nService.t("mg.pipeFlow.puzzle", {"n": puzzle_no}),
			I18nService.t("mg.pipeFlow.taps", {"n": total_taps}),
		]
	)
	_hint_label.modulate.a = _hint_alpha()


## Q3: der Hinweis steht die ersten Sekunden und blendet dann aus — die
## Gärtnerei gehört danach ganz dem Brett.
func _hint_alpha() -> float:
	return clampf(1.0 - (elapsed - HINT_FADE_AT) / HINT_FADE_SEC, 0.0, 1.0)


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


func _cell_at(screen: Vector2) -> int:
	var grid := int(board["size"])
	var local := screen - _grid_origin
	if local.x < 0.0 or local.y < 0.0:
		return -1
	var col := int(local.x / _cell)
	var row := int(local.y / _cell)
	if col < 0 or col >= grid or row < 0 or row >= grid:
		return -1
	return row * grid + col


func _cell_center(index: int) -> Vector2:
	var grid := int(board["size"])
	var col := index % grid
	var row := index / grid
	return _grid_origin + Vector2((col + 0.5) * _cell, (row + 0.5) * _cell)


func _tile_watered(index: int) -> bool:
	return filling and depths.has(index) and int(depths[index]) < fill_depth


# Kein 2D-Brett mehr: Panel, Rohre, Hahn, Sprenger, Beet und Gooby rendert
# die 3D-Bühne (PipeFlowStage3D); 2D bleiben Leck-Countdown-Ring + Banner.
func _draw() -> void:
	if leak_index >= 0 and not leak_applied and not filling:
		_draw_leak()
	_draw_banner()


## Banner mittig mit Milchglas-Plate und Kontur (M7, bubble_pop-Muster);
## lange Übersetzungen brechen um. Trägt Intro-Ziel UND „Verbunden!“.
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
	var top := vp.y * 0.22
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


## Oberkante des Blumenbeets am unteren Bildrand.
func _bed_y() -> float:
	return view_size.y - (132.0 if not landscape else 76.0)


func _draw_leak() -> void:
	var center := _cell_center(leak_index)
	var due := float(tune["LEAK_SEC"])
	var ratio := clampf(puzzle_elapsed / maxf(0.35, due), 0.0, 1.0)
	draw_arc(center, _cell * 0.42, -PI * 0.5, -PI * 0.5 + TAU * ratio, 26, AcTokens.DANGER, 4.0)
	var drop := fmod(_pulse * 40.0, _cell * 0.5)
	draw_circle(center + Vector2(0.0, drop), 4.0, WATER)
