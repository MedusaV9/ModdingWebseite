extends TestCase
## G5 P30 — Präsentations-Verträge der pancakeTower/pipeFlow-Politur (W17):
## Intro-Beats 1,5 s gaten Sim UND Eingabe (Läufe bleiben zahlengleich, M1),
## _ui-Skalierung des HUD samt Konturen und vp-gekoppelter Hinweis-Breite
## (M9/M7), Hint-Fades (Q3), Banner-Plates statt roher Screen-Texte (M7),
## Reduced-Motion-Gates an den eigenen Stage-Burst-Call-Sites (Q2), die
## Wackel-Warnung des Turms, die Fluss-Puls-Kette des Rohrpanels und die
## DE/EN-Parität der neuen Domain-Datei mg_pancake_pipe.json. Die MECHANIK
## (pancake_tower_logic.gd/pipe_flow_logic.gd) wird hier NICHT berührt —
## deren Zahlen sichern test_mg2_pancake_tower/test_mg_batch3 (pipe) und
## test_w13c_crosscheck (test_pancake_tower_matches_web,
## test_pipe_flow_matches_web).

const Pancake := preload("res://scripts/minigames/games/pancake_tower/pancake_tower.gd")
const Pipe := preload("res://scripts/minigames/games/pipe_flow/pipe_flow.gd")
const PANCAKE_SCENE := "res://scripts/minigames/games/pancake_tower/pancake_tower.tscn"
const PIPE_SCENE := "res://scripts/minigames/games/pipe_flow/pipe_flow.tscn"

var _end_results: Array[Dictionary] = []


func _mount(scene: String, game_id: String, difficulty := "normal") -> MinigameBase:
	var ctx := MinigameCtx.new()
	ctx.game_id = game_id
	ctx.difficulty = difficulty
	ctx.run_seed = 4242
	ctx.on_end = Callable(self, "_capture_end")
	var game: MinigameBase = (load(scene) as PackedScene).instantiate()
	tree.root.add_child(game)
	game.setup(ctx)
	game.start()
	return game


func _capture_end(result: Dictionary) -> void:
	_end_results.append(result)


## Schaltet Reduced Motion am ECHTEN AppSettings-Autoload (ein Stub gleichen
## Namens würde verdeckt — Muster test_feel_juice). Liefert den Vorzustand.
func _set_reduced_motion(enabled: bool) -> Variant:
	var settings := tree.root.get_node_or_null("AppSettings")
	if settings == null:
		return null
	var previous := bool(settings.is_reduced_motion())
	settings.set_setting("reduced_motion", enabled)
	return previous


func _tap(game: MinigameBase, at: Vector2) -> void:
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = at
	game._unhandled_input(touch)


func test_intro_beat_konstanten() -> void:
	for script: GDScript in [Pancake, Pipe]:
		var consts := script.get_script_constant_map()
		assert_true(consts.has("INTRO_S"), "INTRO_S vorhanden")
		assert_almost(float(consts["INTRO_S"]), 1.5, 1e-6, "Intro-Beat = 1,5 s (W14-Kanon)")


func test_pancake_intro_gatet_sim_und_eingabe() -> void:
	var game := _mount(PANCAKE_SCENE, "pancakeTower")
	assert_almost(float(game.get("_intro_left")), 1.5, 1e-6, "Intro startet voll")
	assert_eq(str(game.get("_banner_text")), I18nService.t("mg.pancakeTower.intro"), "Ziel-Banner")
	assert_true(float(game.get("_banner_t")) > 0.0, "Banner steht im Intro")
	for _i in 3:
		game._process(0.4)
	assert_true(float(game.get("_intro_left")) > 0.0, "Beat läuft noch (1,2 s)")
	assert_almost(float(game.get("slide_t")), 0.0, 1e-6, "Pendel-Uhr wartet im Intro")
	assert_almost(
		float((game.get("wobble") as Dictionary)["phase"]), 0.0, 1e-6, "Schwingung wartet"
	)
	# Eingabe ist gegatet: der Tipp wirft im Intro keinen Pfannkuchen ab.
	_tap(game, Vector2(200.0, 400.0))
	assert_false(bool(game.get("falling")), "Tipp wirft im Intro nicht ab")
	game._process(0.4)
	assert_almost(float(game.get("_intro_left")), 0.0, 1e-6, "Beat nach 1,6 s vorbei")
	assert_almost(float(game.get("slide_t")), 0.0, 1e-6, "Übergangs-Frame zählt nicht")
	game._process(0.2)
	assert_almost(float(game.get("slide_t")), 0.2, 1e-6, "danach tickt die Sim normal")
	_tap(game, Vector2(200.0, 400.0))
	assert_true(bool(game.get("falling")), "nach dem Intro fällt der Abwurf")
	game.free()


func test_pancake_intro_kamera_pfannen_totale() -> void:
	var game := _mount(PANCAKE_SCENE, "pancakeTower")
	var stage: Node3D = game.get("_stage")
	var cam: Camera3D = (stage.get("stage") as Node3D).get("camera")
	game._process(0.1)
	var play_y := float(stage.call("_cam_center", 0.0))
	assert_true(cam.position.y > play_y + 0.5, "Intro: Kamera schwebt erhöht überm Tresen")
	assert_true(cam.position.z > 8.0 + 0.5, "Intro: Kamera zurückgesetzt (Totale)")
	assert_true(cam.rotation_degrees.x < -0.5, "Intro: Blick hinab auf Teller + Requisiten")
	# Der letzte Intro-Frame ruft establish(1.0) — exakte Spielpose, kein Ruck.
	game.set("_intro_left", 0.05)
	game._process(0.1)
	assert_almost(cam.position.y, play_y, 1e-4, "Spielpose: exakte Rahmung wie frame()/sync()")
	assert_almost(cam.rotation_degrees.x, 0.0, 1e-4, "Spielpose: frontal")
	game.free()


func test_pancake_ui_faktor_und_hint_breite() -> void:
	var game := _mount(PANCAKE_SCENE, "pancakeTower")
	game.call("apply_view", Vector2(390.0, 844.0))
	assert_almost(float(game.get("_ui")), 1.0, 1e-6, "Phone-Kurzkante = Faktor 1")
	var label: Label = game.get("_layers_label")
	assert_eq(label.get_theme_font_size("font_size"), 34, "Phone: Headline wie Theme")
	assert_eq(label.position, Vector2(16.0, 10.0), "Phone: Entwurfsposition")
	assert_true(label.get_theme_constant("outline_size") >= 7, "Kontur auf den Lagen (M7)")
	var width: Label = game.get("_width_label")
	assert_true(width.get_theme_constant("outline_size") >= 7, "Kontur auf der Breite (M7)")
	game.call("apply_view", Vector2(834.0, 1194.0))
	assert_almost(float(game.get("_ui")), 834.0 / 390.0, 1e-4, "iPad: Kurzkante/390")
	assert_eq(label.get_theme_font_size("font_size"), int(34.0 * 834.0 / 390.0), "HUD wächst")
	game.call("apply_view", Vector2(9999.0, 9999.0))
	assert_almost(float(game.get("_ui")), 3.0, 1e-6, "Deckel bei 3,0")
	game.call("apply_view", Vector2(200.0, 400.0))
	assert_almost(float(game.get("_ui")), 0.75, 1e-6, "Boden bei 0,75")
	var hint: Label = game.get("_hint_label")
	assert_true(hint.size.x <= 360.0 * 0.75 + 0.001, "Hinweis-Breite folgt _ui statt Fix-300-px")
	var vp := (game.call("get_viewport_rect") as Rect2).size
	assert_true(hint.size.x <= vp.x - 32.0 * 0.75 + 0.001, "Hinweis bleibt im Bild")
	game.free()


func test_pancake_hint_fade() -> void:
	var game := _mount(PANCAKE_SCENE, "pancakeTower")
	game.set("_intro_left", 0.0)
	game._process(0.5)
	var hint: Label = game.get("_hint_label")
	assert_almost(hint.modulate.a, 1.0, 1e-6, "Hinweis steht am Anfang voll")
	game.set("_hint_seen", 8.0)
	game._process(0.016)
	assert_almost(hint.modulate.a, 0.0, 1e-6, "nach ~6 s blendet der Hinweis aus (Q3)")
	game.free()


func test_pancake_topple_banner_statt_flash() -> void:
	_end_results.clear()
	var game := _mount(PANCAKE_SCENE, "pancakeTower")
	assert_false(game.has_method("_draw_flash"), "roher Topple-draw_string ist ersetzt (M7)")
	game.set("_intro_left", 0.0)
	game._process(0.1)
	# Abwurf weit neben den Stapel: resolve_drop landet nicht → Topple-Pfad.
	game.set("falling", true)
	game.set("fall_x", 2.0)
	game.set("fall_y", 0.0)
	game.call("_land")
	assert_eq(
		str(game.get("_banner_text")), I18nService.t("mg.pancakeTower.topple"), "Topple-Banner"
	)
	assert_true(float(game.get("_banner_t")) > 0.0, "Banner-Plate steht")
	assert_true(bool(game.get("finished")), "Topple beendet die Runde wie bisher")
	assert_eq(_end_results.size(), 1, "genau ein report_end")
	assert_eq(int(_end_results[0]["layers"]), 0, "Wertung unangetastet")
	game.free()


func test_pancake_wackel_warnung() -> void:
	var game := _mount(PANCAKE_SCENE, "pancakeTower")
	game.set("_intro_left", 0.0)
	game._process(0.1)
	assert_almost(float(game.get("_warn_level")), 0.0, 1e-6, "ruhiger Turm: keine Warnung")
	# Kritische Schieflage stellen: 8 Lagen (Schwingung aktiv) + Winkel nahe
	# am Limit — reine Anzeige, die Logik-Schwingung bleibt unangetastet.
	var tune: Dictionary = game.get("tune")
	var layers: Array = game.get("layers")
	for i in int(tune["WOBBLE_START_LAYER"]):
		layers.append({"center": 0.0, "width": 1.5, "topping": false, "index": i + 1})
	var limit := float(tune["WOBBLE_MAX_RAD"])
	game.set("wobble", {"angle": limit * 0.9, "velocity": 0.0, "phase": 0.0})
	game._process(0.016)
	assert_true(float(game.get("_warn_level")) > 0.0, "kritische Schieflage: Warn-Pegel an")
	assert_true(float(game.get("_warn_tone_in")) > 0.0, "Warn-Wusch gespielt + Sperrzeit läuft")
	var tone_in := float(game.get("_warn_tone_in"))
	game._process(0.016)
	assert_true(float(game.get("_warn_tone_in")) < tone_in, "Sperrzeit tickt ab (kein Dauerton)")
	game.set("wobble", {"angle": 0.0, "velocity": 0.0, "phase": 0.0})
	game._process(0.016)
	assert_almost(float(game.get("_warn_level")), 0.0, 1e-6, "aufgerichtet: Warnung erlischt")
	game.free()


func test_pancake_q2_gates_stage_bursts() -> void:
	var game := _mount(PANCAKE_SCENE, "pancakeTower")
	var stage: Node3D = game.get("_stage")
	var star: GPUParticles3D = stage.get("_star_burst")
	var crumb: GPUParticles3D = stage.get("_crumb_burst")
	stage.call("perfect_fx", 0.0, 0.0, true)
	assert_false(star.emitting, "Reduced Motion: Perfect-Burst bleibt aus (Q2)")
	assert_true(float(stage.get("_ring_age")) >= 0.35, "Reduced Motion: kein Landering-Puls")
	stage.call("perfect_fx", 0.0, 0.0, false)
	assert_true(star.emitting, "Normal: Perfect-Burst feuert")
	assert_almost(float(stage.get("_ring_age")), 0.0, 1e-6, "Normal: Landering pulst")
	stage.call("topple_fx", 0.0, 0.0, true)
	assert_false(crumb.emitting, "Reduced Motion: Topple-Burst bleibt aus (Q2)")
	stage.call("cut_fx", 0.0, 0.0, false)
	assert_true(crumb.emitting, "Normal: Schnitt-Burst feuert")
	game.free()


func test_pipe_intro_gatet_sim_und_eingabe() -> void:
	var game := _mount(PIPE_SCENE, "pipeFlow")
	assert_almost(float(game.get("_intro_left")), 1.5, 1e-6, "Intro startet voll")
	assert_eq(str(game.get("_banner_text")), I18nService.t("mg.pipeFlow.intro"), "Ziel-Banner")
	for _i in 3:
		game._process(0.4)
	assert_true(float(game.get("_intro_left")) > 0.0, "Beat läuft noch (1,2 s)")
	assert_almost(float(game.get("elapsed")), 0.0, 1e-6, "Runden-Uhr wartet im Intro")
	assert_almost(float(game.get("puzzle_elapsed")), 0.0, 1e-6, "Leck-Uhr wartet im Intro")
	# Eingabe ist gegatet: der Tipp dreht im Intro keine Kachel.
	_tap(game, game.call("_cell_center", 0))
	assert_eq(int(game.get("total_taps")), 0, "Tipp dreht im Intro nichts")
	game._process(0.4)
	assert_almost(float(game.get("_intro_left")), 0.0, 1e-6, "Beat nach 1,6 s vorbei")
	assert_almost(float(game.get("elapsed")), 0.0, 1e-6, "Übergangs-Frame zählt nicht")
	game._process(0.2)
	assert_almost(float(game.get("elapsed")), 0.2, 1e-6, "danach tickt die Sim normal")
	_tap(game, game.call("_cell_center", 0))
	assert_eq(int(game.get("total_taps")), 1, "nach dem Intro dreht der Tipp")
	game.free()


func test_pipe_intro_kamera_puzzle_totale() -> void:
	var game := _mount(PIPE_SCENE, "pipeFlow")
	var stage: Node3D = game.get("_stage")
	var cam: Camera3D = (stage.get("stage") as Node3D).get("camera")
	game._process(0.1)
	assert_true(cam.position.y < -0.5, "Intro: Kamera startet unten am Beet")
	assert_true(cam.position.z > 10.0 + 0.5, "Intro: Kamera zurückgesetzt (Totale)")
	assert_true(cam.rotation_degrees.x > 0.5, "Intro: Blick hoch zum Brett")
	game.set("_intro_left", 0.05)
	game._process(0.1)
	assert_almost(cam.position.y, 0.0, 1e-4, "Spielpose: exakte Rahmung wie frame()")
	assert_almost(cam.rotation_degrees.x, 0.0, 1e-4, "Spielpose: frontal")
	game.free()


func test_pipe_ui_faktor_und_konturen() -> void:
	var game := _mount(PIPE_SCENE, "pipeFlow")
	game.call("apply_view", Vector2(390.0, 844.0))
	assert_almost(float(game.get("_ui")), 1.0, 1e-6, "Phone-Kurzkante = Faktor 1")
	var time_label: Label = game.get("_time_label")
	assert_eq(time_label.get_theme_font_size("font_size"), 34, "Phone: Headline wie Theme")
	assert_eq(time_label.position, Vector2(16.0, 10.0), "Phone: Entwurfsposition")
	# Audit §10: Zeit-/Rätsel-Label hatten KEINE Kontur — jetzt wie der Hint.
	var puzzle: Label = game.get("_puzzle_label")
	for label: Label in [time_label, puzzle]:
		assert_true(label.get_theme_constant("outline_size") >= 6, "Kontur (M7)")
		assert_eq(
			label.get_theme_color("font_color"), Color(1.0, 1.0, 0.97), "heller Text vorm Himmel"
		)
	game.call("apply_view", Vector2(834.0, 1194.0))
	assert_eq(time_label.get_theme_font_size("font_size"), int(34.0 * 834.0 / 390.0), "wächst")
	game.call("apply_view", Vector2(200.0, 400.0))
	assert_almost(float(game.get("_ui")), 0.75, 1e-6, "Boden bei 0,75")
	var hint: Label = game.get("_hint_label")
	assert_true(hint.size.x <= 360.0 * 0.75 + 0.001, "Hinweis-Breite folgt _ui statt Fix-360-px")
	var vp := (game.call("get_viewport_rect") as Rect2).size
	assert_true(hint.size.x <= vp.x - 32.0 * 0.75 + 0.001, "Hinweis bleibt im Bild")
	game.free()


func test_pipe_hint_fade() -> void:
	var game := _mount(PIPE_SCENE, "pipeFlow")
	game.set("_intro_left", 0.0)
	game._process(0.5)
	var hint: Label = game.get("_hint_label")
	assert_almost(hint.modulate.a, 1.0, 1e-6, "Hinweis steht am Anfang voll")
	game.set("elapsed", 8.0)
	game._process(0.016)
	assert_almost(hint.modulate.a, 0.0, 1e-6, "nach ~6 s blendet der Hinweis aus (Q3)")
	game.free()


## Löst das erste Rätsel über ECHTE Taps (Solver-Lösung wie der Foto-Bot).
func _solve_first_puzzle(game: MinigameBase) -> void:
	var solution: Dictionary = PipeFlowLogic.solve_board(game.get("board"))
	for idx: int in solution["taps"]:
		_tap(game, game.call("_cell_center", idx))


func test_pipe_solved_banner_und_flusskette() -> void:
	var game := _mount(PIPE_SCENE, "pipeFlow")
	game.set("_intro_left", 0.0)
	game._process(0.1)
	_solve_first_puzzle(game)
	assert_true(bool(game.get("filling")), "Lösung startet die Füllwelle")
	assert_eq(str(game.get("_banner_text")), I18nService.t("mg.pipeFlow.solved"), "Banner (M7)")
	assert_true(float(game.get("_banner_t")) > 0.0, "Banner-Plate steht")
	var stage: Node3D = game.get("_stage")
	assert_true(float(stage.get("_flow_t")) >= 0.0, "Fluss-Puls-Kette läuft")
	assert_false((stage.get("_flow_depths") as Dictionary).is_empty(), "Kette kennt die Leitung")
	# Die Kette pulst in Anschluss-Reihenfolge und versiegt von selbst.
	game._process(0.05)
	assert_true(
		float(stage.call("_flow_pop", int(game.get("board")["srcCol"]))) > 0.0,
		"Hahn-Kachel pulst zuerst"
	)
	for _i in 40:
		game._process(0.1)
	assert_true(float(stage.get("_flow_t")) < 0.0, "Kette versiegt nach der Leitung")
	game.free()


func test_pipe_solved_reduced_motion_ohne_kette() -> void:
	var previous: Variant = _set_reduced_motion(true)
	if previous == null:
		fail_test("AppSettings-Autoload fehlt")
		return
	var game := _mount(PIPE_SCENE, "pipeFlow")
	game.set("_intro_left", 0.0)
	game._process(0.1)
	_solve_first_puzzle(game)
	assert_true(bool(game.get("filling")), "Lösung startet die Füllwelle auch unter RM")
	var stage: Node3D = game.get("_stage")
	assert_true(float(stage.get("_flow_t")) < 0.0, "Reduced Motion: keine Puls-Kette (Gate)")
	var win: GPUParticles3D = stage.get("_win_burst")
	assert_false(win.emitting, "Reduced Motion: Lösungs-Burst bleibt aus (Q2)")
	game.free()
	_set_reduced_motion(bool(previous))


func test_pipe_q2_gates_stage_bursts() -> void:
	var game := _mount(PIPE_SCENE, "pipeFlow")
	var stage: Node3D = game.get("_stage")
	var win: GPUParticles3D = stage.get("_win_burst")
	var gold: GPUParticles3D = stage.get("_gold_burst")
	stage.call("solve_fx", 0, true)
	assert_false(win.emitting, "Reduced Motion: Lösungs-Burst bleibt aus (Q2)")
	assert_false(gold.emitting, "Reduced Motion: Goldfunken bleiben aus (Q2)")
	assert_true(float(stage.get("_rainbow_t")) > 0.0, "Regenbogen bleibt (statisches Feedback)")
	stage.call("solve_fx", 0, false)
	assert_true(win.emitting, "Normal: Lösungs-Burst feuert")
	win.emitting = false
	stage.call("leak_fx", 0, true)
	assert_false(win.emitting, "Reduced Motion: Leck-Platsch bleibt aus (Q2)")
	stage.call("leak_fx", 0, false)
	assert_true(win.emitting, "Normal: Leck-Platsch feuert")
	game.free()


func test_strings_de_en_paritaet() -> void:
	var de := _flat_keys("res://strings/de/mg_pancake_pipe.json")
	var en := _flat_keys("res://strings/en/mg_pancake_pipe.json")
	assert_eq(de, en, "DE/EN-Schlüssel der Domain-Datei paritätisch")
	assert_true(de.has("mg.pancakeTower.intro"), "pancakeTower-Intro-Key vorhanden")
	assert_true(de.has("mg.pipeFlow.intro"), "pipeFlow-Intro-Key vorhanden")
	assert_ne(
		I18nService.t("mg.pancakeTower.intro"),
		"mg.pancakeTower.intro",
		"Loader mergt die neue Domain-Datei flach"
	)


func _flat_keys(path: String) -> Array[String]:
	var file := FileAccess.open(path, FileAccess.READ)
	assert_true(file != null, "%s fehlt" % path)
	if file == null:
		return []
	var data: Variant = JSON.parse_string(file.get_as_text())
	var out: Array[String] = []
	_collect_keys("", data, out)
	out.sort()
	return out


func _collect_keys(prefix: String, node: Variant, out: Array[String]) -> void:
	if node is Dictionary:
		for key: String in node:
			var path := key if prefix.is_empty() else "%s.%s" % [prefix, key]
			_collect_keys(path, node[key], out)
		return
	assert_true(str(node).length() > 0, "%s: Wert leer" % prefix)
	out.append(prefix)
