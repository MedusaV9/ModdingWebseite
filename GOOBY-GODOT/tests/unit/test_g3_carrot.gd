extends TestCase
## G3/P10 MG-CARROT — Präsentations-Verträge der carrotGuard-Politur (W16):
## Intro-Beat gatet die Sim (Lauf bleibt zahlengleich, Crosscheck-Vertrag),
## _ui-Skalierung des HUD (M9), Möhren-Icon-Reihe mit sichtbarem Klau-Flug,
## Kombo-Pips zur 5er-Bonus-Kombo (pur), König-Banner mittig (M7) samt
## Vignette, Timer-Urgenz unter 5 s, Layout-Raycast aus der Spielpose und
## die DE/EN-Parität der neuen Domain-Datei mg_carrot.json.
## Die MECHANIK (carrot_guard_logic.gd) wird hier NICHT berührt.

const Guard := preload("res://scripts/minigames/games/carrot_guard/carrot_guard.gd")
const SCENE := "res://scripts/minigames/games/carrot_guard/carrot_guard.tscn"


func _mount(difficulty := "normal", seed_value := 4242) -> MinigameBase:
	var ctx := MinigameCtx.new()
	ctx.game_id = "carrotGuard"
	ctx.difficulty = difficulty
	ctx.run_seed = seed_value
	var game: MinigameBase = (load(SCENE) as PackedScene).instantiate()
	tree.root.add_child(game)
	game.setup(ctx)
	game.start()
	return game


func test_intro_beat_konstante() -> void:
	var consts := (Guard as GDScript).get_script_constant_map()
	assert_true(consts.has("INTRO_S"), "carrotGuard hat INTRO_S")
	assert_almost(float(consts["INTRO_S"]), 1.5, 1e-6, "Intro-Beat = 1,5 s (W14-Kanon)")


func test_intro_gatet_die_sim() -> void:
	var game := _mount()
	assert_almost(float(game.get("_intro_left")), 1.5, 1e-6, "Intro startet voll")
	# Während des Beats wartet die Sim: elapsed bleibt 0, nichts spawnt.
	for _i in 3:
		game._process(0.4)
	assert_true(float(game.get("_intro_left")) > 0.0, "Beat läuft noch (1,2 s)")
	assert_almost(float(game.get("elapsed")), 0.0, 1e-6, "Sim wartet im Intro")
	assert_eq((game.get("moles") as Array).size(), 0, "kein Maulwurf im Intro")
	game._process(0.4)
	assert_almost(float(game.get("_intro_left")), 0.0, 1e-6, "Beat nach 1,6 s vorbei")
	assert_almost(float(game.get("elapsed")), 0.0, 1e-6, "Übergangs-Frame zählt nicht")
	game._process(0.2)
	assert_almost(float(game.get("elapsed")), 0.2, 1e-6, "danach tickt die Sim normal")
	game.free()


func test_ui_faktor_und_hud_skalierung() -> void:
	var game := _mount()
	game.call("apply_view", Vector2(390.0, 844.0))
	assert_almost(float(game.get("_ui")), 1.0, 1e-6, "Phone-Kurzkante = Faktor 1")
	var slot_phone: Rect2 = game.call("_icon_rect", 0)
	game.call("apply_view", Vector2(834.0, 1194.0))
	assert_almost(float(game.get("_ui")), 834.0 / 390.0, 1e-4, "iPad: Kurzkante/390")
	var slot_pad: Rect2 = game.call("_icon_rect", 0)
	assert_true(slot_pad.size.x > slot_phone.size.x, "Icon-Slots wachsen mit dem Faktor")
	game.call("apply_view", Vector2(9999.0, 9999.0))
	assert_almost(float(game.get("_ui")), 3.0, 1e-6, "Deckel bei 3,0")
	game.call("apply_view", Vector2(200.0, 400.0))
	assert_almost(float(game.get("_ui")), 0.75, 1e-6, "Boden bei 0,75")
	game.free()


func test_kombo_pips_pur() -> void:
	assert_eq(Guard.pip_fill_for(0), 0, "ohne Serie kein Pip")
	assert_eq(Guard.pip_fill_for(1), 1)
	assert_eq(Guard.pip_fill_for(4), 4)
	assert_eq(Guard.pip_fill_for(5), 5, "der Bonus-Moment zeigt volle Pips")
	assert_eq(Guard.pip_fill_for(6), 1, "danach beginnt die nächste Serie")
	assert_eq(Guard.pip_fill_for(10), 5, "jedes Vielfache von 5 leuchtet voll")
	assert_eq(Guard.pip_fill_for(-3), 0, "nie negativ")


func test_klau_fliegt_sichtbar_aus_dem_hud() -> void:
	var game := _mount()
	game.set("_intro_left", 0.0)
	game.set("combo", 3)
	var moles: Array = game.get("moles")
	moles.append({"hole": 0, "left": 0.01, "up": 1.0})
	game._process(0.05)
	assert_eq(int(game.get("carrots")), 9, "der Klau kostet eine Möhre (Sim-Zahl)")
	var flights: Array = game.get("_fly_icons")
	assert_eq(flights.size(), 1, "die HUD-Möhre fliegt sichtbar raus")
	if flights.size() == 1:
		assert_eq(int((flights[0] as Dictionary)["slot"]), 9, "der geleerte Slot fliegt")
	assert_true(float(game.get("_pip_break")) > 0.0, "Riss-Blitz der Kombo-Pips")
	assert_eq(int(game.get("combo")), 0, "Kombo ist futsch (Logic unangetastet)")
	game.free()


func test_koenig_banner_mittig_mit_vignette() -> void:
	var game := _mount()
	game.set("_intro_left", 0.0)
	game.set("_banner_t", 0.0)
	game.call("_spawn_king")
	assert_eq(str(game.get("_banner")), I18nService.t("mg.carrotGuard.king"), "Banner-Text")
	assert_true(bool(game.get("_banner_gold")), "König-Banner ist gold")
	assert_true(float(game.get("_banner_t")) > 0.0, "Banner steht")
	assert_true(float(game.get("_vignette")) > 0.0, "Gold-Vignette pulst")
	assert_false((game.get("king") as Dictionary).is_empty(), "König steht im Loch")
	game.free()


func test_timer_urgenz_unter_5s() -> void:
	var game := _mount()
	game.set("_intro_left", 0.0)
	game.set("elapsed", 42.0)
	game.call("_update_labels")
	var label: Label = game.get("_time_label")
	assert_true(label.has_theme_color_override("font_color"), "3 s Rest: Zeit färbt rot")
	game.set("elapsed", 10.0)
	game.call("_update_labels")
	assert_false(label.has_theme_color_override("font_color"), "35 s Rest: keine Färbung")
	game.free()


func test_layout_raycastet_aus_der_spielpose() -> void:
	var game := _mount()
	game.call("apply_view", Vector2(390.0, 844.0))
	var stage: Node3D = game.get("_stage")
	var before: Array = (stage.get("_mound_pos") as Array).duplicate(true)
	# Kamera in die Intro-Totale stellen und das Layout erneut rechnen: der
	# Pose-Snapshot muss die Hügel EXAKT an derselben Stelle einmessen.
	stage.call("establish", 0.0)
	stage.call("layout", game.get("_holes"))
	var after: Array = stage.get("_mound_pos")
	assert_eq(after.size(), before.size(), "alle Hügel eingemessen")
	for i in before.size():
		assert_true(
			(before[i] as Vector3).distance_to(after[i]) < 0.001, "Hügel %d wandert nicht" % i
		)
	var cam: Camera3D = (stage.get("stage") as Node3D).get("camera")
	assert_true(cam.position.y > 12.0, "Pose-Snapshot: Kamera bleibt in der Totale")
	game.free()


func test_intro_strings_de_en_paritaet() -> void:
	var de := _flat_keys("res://strings/de/mg_carrot.json")
	var en := _flat_keys("res://strings/en/mg_carrot.json")
	assert_eq(de, en, "DE/EN-Schlüssel der Domain-Datei paritätisch")
	assert_true(de.has("mg.carrotGuard.intro"), "Intro-Key vorhanden")
	assert_ne(
		I18nService.t("mg.carrotGuard.intro"),
		"mg.carrotGuard.intro",
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
