extends TestCase
## G4-CATCH — Präsentations-Verträge der carrotCatch-Politur (W17):
## Intro-Beat 1,5 s gatet Sim UND Eingabe (Lauf bleibt zahlengleich, M1),
## _ui-Skalierung des HUD samt Konturen (M9/M7), Miss-Feedback im Zeitmodus
## (Staubpuff + Plop, M3 — Endlos-Zählung unverändert), Vogelzug/Drachen im
## oberen Bilddrittel deterministisch + Reduced-Motion-gegatet (M2) und die
## DE/EN-Parität der neuen Domain-Datei mg_catch.json.
## Die MECHANIK (carrot_catch_logic.gd) wird hier NICHT berührt.

const Catch := preload("res://scripts/minigames/games/carrot_catch/carrot_catch.gd")
const SCENE := "res://scripts/minigames/games/carrot_catch/carrot_catch.tscn"


func _mount(difficulty := "normal", seed_value := 4242) -> MinigameBase:
	var ctx := MinigameCtx.new()
	ctx.game_id = "carrotCatch"
	ctx.difficulty = difficulty
	ctx.run_seed = seed_value
	var game: MinigameBase = (load(SCENE) as PackedScene).instantiate()
	tree.root.add_child(game)
	game.setup(ctx)
	game.start()
	return game


## Schaltet Reduced Motion am ECHTEN AppSettings-Autoload (ein Stub gleichen
## Namens würde verdeckt — Muster test_feel_juice). Liefert den Vorzustand.
func _set_reduced_motion(enabled: bool) -> Variant:
	var settings := tree.root.get_node_or_null("AppSettings")
	if settings == null:
		return null
	var previous := bool(settings.is_reduced_motion())
	settings.set_setting("reduced_motion", enabled)
	return previous


func _viewport_size(game: MinigameBase) -> Vector2:
	return (game.call("get_viewport_rect") as Rect2).size


func test_intro_beat_konstante() -> void:
	var consts := (Catch as GDScript).get_script_constant_map()
	assert_true(consts.has("INTRO_S"), "carrotCatch hat INTRO_S")
	assert_almost(float(consts["INTRO_S"]), 1.5, 1e-6, "Intro-Beat = 1,5 s (W14-Kanon)")


func test_intro_gatet_sim_und_eingabe() -> void:
	var game := _mount()
	assert_almost(float(game.get("_intro_left")), 1.5, 1e-6, "Intro startet voll")
	assert_eq(str(game.get("_banner")), I18nService.t("mg.carrotCatch.intro"), "Ziel-Banner")
	assert_true(float(game.get("_banner_t")) > 0.0, "Banner steht im Intro")
	# Während des Beats wartet die Sim: elapsed bleibt 0, nichts spawnt.
	for _i in 3:
		game._process(0.4)
	assert_true(float(game.get("_intro_left")) > 0.0, "Beat läuft noch (1,2 s)")
	assert_almost(float(game.get("elapsed")), 0.0, 1e-6, "Sim wartet im Intro")
	assert_eq((game.get("items") as Array).size(), 0, "nichts fällt im Intro")
	# Eingabe ist gegatet: der Drag zieht das Korb-Ziel noch nicht.
	var drag := InputEventScreenDrag.new()
	drag.position = Vector2(_viewport_size(game).x, 300.0)
	game._unhandled_input(drag)
	assert_almost(float(game.get("target_x")), 0.0, 1e-6, "Drag zieht im Intro nicht")
	game._process(0.4)
	assert_almost(float(game.get("_intro_left")), 0.0, 1e-6, "Beat nach 1,6 s vorbei")
	assert_almost(float(game.get("elapsed")), 0.0, 1e-6, "Übergangs-Frame zählt nicht")
	game._process(0.2)
	assert_almost(float(game.get("elapsed")), 0.2, 1e-6, "danach tickt die Sim normal")
	game._unhandled_input(drag)
	assert_true(float(game.get("target_x")) > 0.0, "nach dem Intro zieht der Drag")
	game.free()


func test_intro_kamera_fliegt_in_die_spielpose() -> void:
	var game := _mount()
	var stage: Node3D = game.get("_stage")
	var cam: Camera3D = (stage.get("stage") as Node3D).get("camera")
	var half_h := float(stage.get("_world_half_h"))
	game._process(0.1)
	assert_true(cam.position.y > half_h + 0.5, "Intro: Kamera startet erhöht")
	assert_true(cam.rotation_degrees.x < -0.5, "Intro: Kamera blickt auf den Garten")
	# Der letzte Intro-Frame ruft establish(1.0) — exakte Spielpose, kein Ruck.
	game.set("_intro_left", 0.05)
	game._process(0.1)
	assert_almost(cam.position.y, half_h, 1e-4, "Spielpose: exakte Rahmung wie frame()")
	assert_almost(cam.rotation_degrees.x, 0.0, 1e-4, "Spielpose: frontal")
	game.free()


func test_ui_faktor_und_hud_skalierung() -> void:
	var game := _mount()
	game.call("apply_view", Vector2(390.0, 844.0))
	assert_almost(float(game.get("_ui")), 1.0, 1e-6, "Phone-Kurzkante = Faktor 1")
	var label: Label = game.get("_time_label")
	assert_eq(label.get_theme_font_size("font_size"), 34, "Phone: Headline wie Theme")
	assert_eq(label.position, Vector2(16.0, 10.0), "Phone: Entwurfsposition")
	assert_true(label.get_theme_constant("outline_size") >= 6, "Kontur auf der Zeit (M7)")
	var combo: Label = game.get("_combo_label")
	assert_true(combo.get_theme_constant("outline_size") >= 5, "Kontur auf der Serie (M7)")
	game.call("apply_view", Vector2(834.0, 1194.0))
	assert_almost(float(game.get("_ui")), 834.0 / 390.0, 1e-4, "iPad: Kurzkante/390")
	assert_eq(label.get_theme_font_size("font_size"), int(34.0 * 834.0 / 390.0), "HUD wächst")
	game.call("apply_view", Vector2(9999.0, 9999.0))
	assert_almost(float(game.get("_ui")), 3.0, 1e-6, "Deckel bei 3,0")
	game.call("apply_view", Vector2(200.0, 400.0))
	assert_almost(float(game.get("_ui")), 0.75, 1e-6, "Boden bei 0,75")
	var hint: Label = game.get("_hint_label")
	assert_true(hint.size.x <= 360.0 * 0.75 + 0.001, "Hinweis-Breite folgt _ui statt Fix-Pixeln")
	game.free()


func test_miss_feedback_nur_im_zeitmodus() -> void:
	var game := _mount()
	game.set("_intro_left", 0.0)
	var vp := _viewport_size(game)
	var burst: GPUParticles3D = (game.get("_stage") as Node3D).get("_miss_burst")
	assert_false(burst.emitting, "Staubpuff startet still")
	var items: Array = game.get("items")
	items.append({"kind": "good", "key": "apple", "value": 1, "x": 3.0, "y": vp.y + 100.0})
	game._process(0.016)
	assert_eq((game.get("items") as Array).size(), 0, "Ware ist durchgefallen")
	assert_true(burst.emitting, "Zeitmodus: Staubpuff quittiert den Miss (M3)")
	assert_eq(int(game.get("missed_carrots")), 0, "Zeitmodus zählt KEINE Boden-Möhren")
	assert_eq(int(game.get("score")), 0, "Wertung unberührt")
	# Junk darf durchfallen — ohne Puff (das ist ja gut für den Spieler).
	burst.emitting = false
	items = game.get("items")
	items.append({"kind": "junk", "key": "burger", "value": -2, "x": 3.0, "y": vp.y + 100.0})
	game._process(0.016)
	assert_false(burst.emitting, "Junk-Durchfaller bekommt keinen Puff")
	game.free()


func test_endlos_zaehlung_bleibt_zahlengleich() -> void:
	var game := _mount("endless")
	game.set("_intro_left", 0.0)
	var vp := _viewport_size(game)
	var burst: GPUParticles3D = (game.get("_stage") as Node3D).get("_miss_burst")
	var items: Array = game.get("items")
	items.append({"kind": "good", "key": "carrot", "value": 1, "x": 3.0, "y": vp.y + 100.0})
	game._process(0.016)
	assert_eq(int(game.get("missed_carrots")), 1, "Endlos: Boden-Möhre zählt wie bisher")
	assert_false(burst.emitting, "Endlos nutzt Spill+Shake, keinen Zeitmodus-Puff")
	assert_false(bool(game.get("finished")), "eine Möhre beendet Endlos nicht")
	game.free()


func test_himmel_fuellt_und_ist_deterministisch() -> void:
	var game := _mount()
	var stage: Node3D = game.get("_stage")
	var birds: MultiMeshInstance3D = stage.get("_birds")
	assert_true(birds != null, "Vogelzug existiert (M2)")
	var consts := (stage.get_script() as GDScript).get_script_constant_map()
	assert_eq(birds.multimesh.instance_count, 2 * int(consts["BIRDS"]), "2 Flügel je Vogel")
	var kites: Array = stage.get("_kites")
	assert_eq(kites.size(), 2, "zwei Drachen am Himmel")
	var sky: Node3D = stage.get("_sky")
	var half_h := float(stage.get("_world_half_h"))
	assert_true(sky.position.y > half_h * 2.0, "Schmuck hängt im oberen Bilddrittel")
	# Ohne Reduced Motion pendelt der Drachen mit dem Puls.
	game.set("_intro_left", 0.0)
	game._process(0.4)
	var rot_a := (kites[0] as Node3D).rotation.z
	game._process(0.4)
	var rot_b := (kites[0] as Node3D).rotation.z
	assert_ne(rot_a, rot_b, "Drachen pendelt (kein Reduced Motion)")
	game.free()


func test_reduced_motion_friert_himmel_und_staub() -> void:
	var previous: Variant = _set_reduced_motion(true)
	if previous == null:
		fail_test("AppSettings-Autoload fehlt")
		return
	var game := _mount()
	game.set("_intro_left", 0.0)
	var stage: Node3D = game.get("_stage")
	var kites: Array = stage.get("_kites")
	game._process(0.4)
	var rot_a := (kites[0] as Node3D).rotation.z
	game._process(0.4)
	var rot_b := (kites[0] as Node3D).rotation.z
	assert_eq(rot_a, rot_b, "Reduced Motion: Drachen steht still")
	var vp := _viewport_size(game)
	var burst: GPUParticles3D = stage.get("_miss_burst")
	var items: Array = game.get("items")
	items.append({"kind": "good", "key": "apple", "value": 1, "x": 3.0, "y": vp.y + 100.0})
	game._process(0.016)
	assert_false(burst.emitting, "Reduced Motion: kein Staubpuff")
	game.free()
	_set_reduced_motion(bool(previous))


func test_intro_strings_de_en_paritaet() -> void:
	var de := _flat_keys("res://strings/de/mg_catch.json")
	var en := _flat_keys("res://strings/en/mg_catch.json")
	assert_eq(de, en, "DE/EN-Schlüssel der Domain-Datei paritätisch")
	assert_true(de.has("mg.carrotCatch.intro"), "Intro-Key vorhanden")
	assert_ne(
		I18nService.t("mg.carrotCatch.intro"),
		"mg.carrotCatch.intro",
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
