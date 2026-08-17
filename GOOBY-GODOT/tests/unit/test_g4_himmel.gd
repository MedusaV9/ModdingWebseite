extends TestCase
## G4-HIMMEL — Präsentations-Verträge der bubblePop/bunnyHop-Politur (W17):
## Intro-Beats 1,5 s gaten Sim UND Eingabe (Läufe bleiben zahlengleich, M1),
## _ui-Skalierung des HUD samt Konturen und vp-gekoppelter Hinweis-Breite
## (M9/M7 — behebt das belegte Fix-340-px-Clipping), bunnyHops Böen-Telegraf
## als Partikel statt 2D-Linien (M4, Reduced-Motion-gegatet an der Call-Site),
## der Trudel-Sturz vor dem Rundenende (M3), der Hint-Fade (M6) und die
## DE/EN-Parität der neuen Domain-Datei mg_himmel.json. Die MECHANIK
## (bubble_pop_logic.gd/bunny_hop_logic.gd) wird hier NICHT berührt —
## deren Zahlen sichern test_mg1_* und test_w13c_crosscheck.

const Bubble := preload("res://scripts/minigames/games/bubble_pop/bubble_pop.gd")
const Bunny := preload("res://scripts/minigames/games/bunny_hop/bunny_hop.gd")
const BUBBLE_SCENE := "res://scripts/minigames/games/bubble_pop/bubble_pop.tscn"
const BUNNY_SCENE := "res://scripts/minigames/games/bunny_hop/bunny_hop.tscn"

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
	for script: GDScript in [Bubble, Bunny]:
		var consts := script.get_script_constant_map()
		assert_true(consts.has("INTRO_S"), "INTRO_S vorhanden")
		assert_almost(float(consts["INTRO_S"]), 1.5, 1e-6, "Intro-Beat = 1,5 s (W14-Kanon)")


func test_bubble_intro_gatet_sim_und_eingabe() -> void:
	var game := _mount(BUBBLE_SCENE, "bubblePop")
	assert_almost(float(game.get("_intro_left")), 1.5, 1e-6, "Intro startet voll")
	assert_eq(str(game.get("_banner_text")), I18nService.t("mg.bubblePop.intro"), "Ziel-Banner")
	assert_true(float(game.get("_banner_t")) > 0.0, "Banner steht im Intro")
	# Während des Beats wartet die Sim: elapsed bleibt 0, nichts spawnt.
	var bubbles: Array = game.get("bubbles")
	var target := str(game.call("target_food"))
	bubbles.append({"kind": "food", "food": target, "x": 0.0, "y": 0.0, "wobble": 0.0})
	for _i in 3:
		game._process(0.4)
	assert_true(float(game.get("_intro_left")) > 0.0, "Beat läuft noch (1,2 s)")
	assert_almost(float(game.get("elapsed")), 0.0, 1e-6, "Sim wartet im Intro")
	assert_eq((game.get("bubbles") as Array).size(), 1, "keine Spawns im Intro")
	# Eingabe ist gegatet: der Tipp auf die Zielblase platzt nichts.
	_tap(game, game.call("_to_screen", Vector2(0.0, 0.0)))
	assert_eq((game.get("bubbles") as Array).size(), 1, "Tipp platzt im Intro nichts")
	assert_eq(int(game.get("score")), 0, "Score unberührt")
	game._process(0.4)
	assert_almost(float(game.get("_intro_left")), 0.0, 1e-6, "Beat nach 1,6 s vorbei")
	assert_almost(float(game.get("elapsed")), 0.0, 1e-6, "Übergangs-Frame zählt nicht")
	game._process(0.2)
	assert_almost(float(game.get("elapsed")), 0.2, 1e-6, "danach tickt die Sim normal")
	_tap(game, game.call("_to_screen", Vector2(0.0, 0.0)))
	assert_eq(int(game.get("score")), 2, "nach dem Intro platzt der Treffer (+2)")
	game.free()


func test_bubble_intro_kamera_faehrt_vom_riff_hoch() -> void:
	var game := _mount(BUBBLE_SCENE, "bubblePop")
	var stage: Node3D = game.get("_stage")
	var cam: Camera3D = (stage.get("stage") as Node3D).get("camera")
	game._process(0.1)
	assert_true(cam.position.y < -0.5, "Intro: Kamera startet unten am Riff")
	assert_true(cam.rotation_degrees.x > 0.5, "Intro: Blick hoch Richtung Ziel-Abzeichen")
	# Der letzte Intro-Frame ruft establish(1.0) — exakte Spielpose, kein Ruck.
	game.set("_intro_left", 0.05)
	game._process(0.1)
	assert_almost(cam.position.y, 0.0, 1e-4, "Spielpose: exakte Rahmung wie frame()")
	assert_almost(cam.rotation_degrees.x, 0.0, 1e-4, "Spielpose: frontal")
	game.free()


func test_bubble_ui_faktor_und_hint_breite() -> void:
	var game := _mount(BUBBLE_SCENE, "bubblePop")
	game.call("apply_view", Vector2(390.0, 844.0))
	assert_almost(float(game.get("_ui")), 1.0, 1e-6, "Phone-Kurzkante = Faktor 1")
	var label: Label = game.get("_time_label")
	assert_eq(label.get_theme_font_size("font_size"), 34, "Phone: Headline wie Theme")
	assert_eq(label.position, Vector2(16.0, 10.0), "Phone: Entwurfsposition")
	assert_true(label.get_theme_constant("outline_size") >= 6, "Kontur auf der Zeit (M7)")
	var streak: Label = game.get("_streak_label")
	assert_true(streak.get_theme_constant("outline_size") >= 5, "Kontur auf der Serie (M7)")
	game.call("apply_view", Vector2(834.0, 1194.0))
	assert_almost(float(game.get("_ui")), 834.0 / 390.0, 1e-4, "iPad: Kurzkante/390")
	assert_eq(label.get_theme_font_size("font_size"), int(34.0 * 834.0 / 390.0), "HUD wächst")
	game.call("apply_view", Vector2(9999.0, 9999.0))
	assert_almost(float(game.get("_ui")), 3.0, 1e-6, "Deckel bei 3,0")
	game.call("apply_view", Vector2(200.0, 400.0))
	assert_almost(float(game.get("_ui")), 0.75, 1e-6, "Boden bei 0,75")
	var hint: Label = game.get("_hint_label")
	assert_true(hint.size.x <= 360.0 * 0.75 + 0.001, "Hinweis-Breite folgt _ui statt Fix-340-px")
	var vp := (game.call("get_viewport_rect") as Rect2).size
	assert_true(hint.size.x <= vp.x - 32.0 * 0.75 + 0.001, "Hinweis bleibt im Bild (Clipping-Fix)")
	var banner: Label = game.get("_banner_label")
	assert_true(banner.size.x <= vp.x - 32.0 * 0.75 + 0.001, "Banner-Breite hängt an vp.x")
	game.free()


func test_bunny_intro_gatet_sim_und_starttipp() -> void:
	var game := _mount(BUNNY_SCENE, "bunnyHop")
	assert_almost(float(game.get("_intro_left")), 1.5, 1e-6, "Intro startet voll")
	assert_eq(str(game.get("_banner")), I18nService.t("mg.bunnyHop.intro"), "Ziel-Banner")
	for _i in 3:
		game._process(0.4)
	assert_true(float(game.get("_intro_left")) > 0.0, "Beat läuft noch (1,2 s)")
	assert_almost(float(game.get("elapsed")), 0.0, 1e-6, "Sim-Uhr (Windfahrplan) wartet")
	assert_almost(float(game.get("gooby_y")), 0.4, 1e-6, "Sim-Schwebe bleibt exakt HOVER_Y")
	# Der Start-Tipp ist gegatet: Gooby hüpft im Intro nicht los.
	_tap(game, Vector2(200.0, 400.0))
	assert_false(bool(game.get("started")), "Tipp startet im Intro nicht")
	game._process(0.4)
	game._process(0.2)
	assert_almost(float(game.get("elapsed")), 0.2, 1e-6, "danach tickt die Sim normal")
	_tap(game, Vector2(200.0, 400.0))
	assert_true(bool(game.get("started")), "nach dem Intro startet der Tipp")
	assert_almost(float(game.get("gooby_vy")), 3.1, 1e-6, "Start-Hüpfer wie im Web")
	game.free()


func test_bunny_intro_kamera_totale() -> void:
	var game := _mount(BUNNY_SCENE, "bunnyHop")
	var stage: Node3D = game.get("_stage")
	var cam: Camera3D = (stage.get("stage") as Node3D).get("camera")
	game._process(0.1)
	assert_true(cam.position.y > 0.9, "Intro: Kamera schwebt erhöht über der Wiese")
	assert_true(cam.rotation_degrees.x < -0.5, "Intro: Blick hinab auf die Szene")
	game.set("_intro_left", 0.05)
	game._process(0.1)
	assert_almost(cam.position.y, 0.4, 1e-4, "Spielpose: exakte Rahmung wie apply_size()")
	assert_almost(cam.rotation_degrees.x, 0.0, 1e-4, "Spielpose: frontal")
	game.free()


func test_bunny_ui_faktor_und_hint_breite() -> void:
	var game := _mount(BUNNY_SCENE, "bunnyHop")
	game.call("apply_view", Vector2(390.0, 844.0))
	assert_almost(float(game.get("_ui")), 1.0, 1e-6, "Phone-Kurzkante = Faktor 1")
	var label: Label = game.get("_time_label")
	assert_eq(label.get_theme_font_size("font_size"), 34, "Phone: Headline wie Theme")
	assert_eq(label.position, Vector2(16.0, 10.0), "Phone: Entwurfsposition")
	assert_true(label.get_theme_constant("outline_size") >= 6, "Kontur auf den Toren (M7)")
	var gate: Label = game.get("_gate_label")
	assert_true(gate.get_theme_constant("outline_size") >= 5, "Kontur auf der Wind-Zeile (M7)")
	assert_true(game.get("_hud_plate") is StyleBoxFlat, "Milchglas-Plate existiert (M6)")
	game.call("apply_view", Vector2(834.0, 1194.0))
	assert_eq(label.get_theme_font_size("font_size"), int(34.0 * 834.0 / 390.0), "HUD wächst")
	game.call("apply_view", Vector2(200.0, 400.0))
	assert_almost(float(game.get("_ui")), 0.75, 1e-6, "Boden bei 0,75")
	var hint: Label = game.get("_hint_label")
	assert_true(hint.size.x <= 360.0 * 0.75 + 0.001, "Hinweis-Breite folgt _ui statt Fix-340-px")
	var vp := (game.call("get_viewport_rect") as Rect2).size
	assert_true(hint.size.x <= vp.x - 32.0 * 0.75 + 0.001, "Hinweis bleibt im Bild (Clipping-Fix)")
	game.free()


func test_bunny_hint_fade_erst_nach_dem_start() -> void:
	var game := _mount(BUNNY_SCENE, "bunnyHop")
	game.set("_intro_left", 0.0)
	# Vor dem ersten Tipp bleibt der Hinweis voll sichtbar — er erklärt ihn.
	for _i in 20:
		game._process(0.5)
	var hint: Label = game.get("_hint_label")
	assert_almost(hint.modulate.a, 1.0, 1e-6, "Hinweis steht bis zum ersten Tipp")
	_tap(game, Vector2(200.0, 400.0))
	game.set("_hint_seen", 6.0)
	game._process(0.016)
	assert_almost(hint.modulate.a, 0.0, 1e-6, "nach dem Start blendet der Hinweis aus (M6)")
	game.free()


func test_bunny_wind_partikel_statt_2d_linien() -> void:
	var game := _mount(BUNNY_SCENE, "bunnyHop")
	game.set("_intro_left", 0.0)
	assert_false(game.has_method("_draw_wind"), "2D-Linien-Telegraf ist ersetzt (M4)")
	var stage: Node3D = game.get("_stage")
	var wind: GPUParticles3D = stage.get("_wind")
	game._process(0.016)
	assert_false(wind.emitting, "Ruhephase: keine Wind-Partikel")
	# Normal-Modus: Telegraf ab Sekunde 4,5, Böe ab Sekunde 6 (Richtung +1).
	game.set("elapsed", 4.6)
	game._process(0.016)
	assert_true(wind.emitting, "Telegraf weht als Partikel")
	assert_almost(wind.speed_scale, 0.8, 1e-6, "Telegraf sanft")
	game.set("elapsed", 6.2)
	game._process(0.016)
	assert_true(wind.emitting, "Böe weht kräftig")
	assert_almost(wind.speed_scale, 1.5, 1e-6, "Böe kräftig")
	var proc := wind.process_material as ParticleProcessMaterial
	assert_true(proc.direction.y > 0.0, "Richtung +1 kippt die Bahn nach oben")
	game.set("elapsed", 9.0)
	game._process(0.016)
	assert_false(wind.emitting, "nach der Böe versiegen die Partikel")
	game.free()


func test_bunny_wind_reduced_motion_gate() -> void:
	var previous: Variant = _set_reduced_motion(true)
	if previous == null:
		fail_test("AppSettings-Autoload fehlt")
		return
	var game := _mount(BUNNY_SCENE, "bunnyHop")
	game.set("_intro_left", 0.0)
	game.set("elapsed", 6.2)
	game._process(0.016)
	var wind: GPUParticles3D = (game.get("_stage") as Node3D).get("_wind")
	assert_false(wind.emitting, "Reduced Motion: keine Wind-Partikel (Call-Site-Gate)")
	var gate: Label = game.get("_gate_label")
	assert_eq(gate.text, I18nService.t("mg.bunnyHop.gust"), "Warntext bleibt lesbar")
	game.free()
	_set_reduced_motion(bool(previous))


func test_bunny_crash_sturz_vor_dem_rundenende() -> void:
	_end_results.clear()
	var game := _mount(BUNNY_SCENE, "bunnyHop")
	game.set("_intro_left", 0.0)
	game._process(0.1)
	_tap(game, Vector2(200.0, 400.0))
	# Säule direkt auf Gooby (Lücke weit weg, schon gewertet) → Kollision.
	var gooby_x := float(game.call("_gooby_world_x"))
	var pillars: Array = game.get("pillars")
	pillars.append({"x": gooby_x, "gapCenterY": 10.0, "gapHeight": 2.0, "passed": true})
	var gates_before := int(game.get("gates"))
	game._process(0.016)
	assert_false(bool(game.get("finished")), "Crash endet NICHT sofort — erst der Sturz (M3)")
	assert_true(float(game.get("_crash_left")) > 0.0, "Sturz-Uhr läuft")
	assert_eq(str(game.get("_banner")), I18nService.t("mg.bunnyHop.crash"), "Rums-Banner steht")
	assert_eq(_end_results.size(), 0, "report_end wartet auf den Sturz")
	var stage: Node3D = game.get("_stage")
	var gooby: Node3D = stage.get("gooby")
	var y_before := gooby.position.y
	game._process(0.2)
	assert_true(gooby.position.y < y_before, "Gooby trudelt sichtbar zu Boden")
	assert_true(gooby.rotation.z != 0.0, "Sturz dreht Gooby")
	game._process(0.5)
	game._process(0.5)
	assert_true(bool(game.get("finished")), "nach dem Sturz endet die Runde")
	assert_eq(_end_results.size(), 1, "genau ein report_end")
	assert_eq(int(_end_results[0]["gates"]), gates_before, "Wertung unangetastet")
	game.free()


func test_bunny_crash_reduced_motion_endet_sofort() -> void:
	var previous: Variant = _set_reduced_motion(true)
	if previous == null:
		fail_test("AppSettings-Autoload fehlt")
		return
	_end_results.clear()
	var game := _mount(BUNNY_SCENE, "bunnyHop")
	game.set("_intro_left", 0.0)
	game._process(0.1)
	_tap(game, Vector2(200.0, 400.0))
	var gooby_x := float(game.call("_gooby_world_x"))
	var pillars: Array = game.get("pillars")
	pillars.append({"x": gooby_x, "gapCenterY": 10.0, "gapHeight": 2.0, "passed": true})
	game._process(0.016)
	assert_true(bool(game.get("finished")), "Reduced Motion: Runde endet sofort wie bisher")
	assert_eq(_end_results.size(), 1, "report_end kommt direkt")
	game.free()
	_set_reduced_motion(bool(previous))


func test_intro_strings_de_en_paritaet() -> void:
	var de := _flat_keys("res://strings/de/mg_himmel.json")
	var en := _flat_keys("res://strings/en/mg_himmel.json")
	assert_eq(de, en, "DE/EN-Schlüssel der Domain-Datei paritätisch")
	assert_true(de.has("mg.bubblePop.intro"), "bubblePop-Intro-Key vorhanden")
	assert_true(de.has("mg.bunnyHop.intro"), "bunnyHop-Intro-Key vorhanden")
	assert_ne(
		I18nService.t("mg.bubblePop.intro"),
		"mg.bubblePop.intro",
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
