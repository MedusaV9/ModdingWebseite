extends TestCase
## G5 P31 — Präsentations-Verträge des ghostHunt-Splits + Politur (W17):
## Auslagerung in ghost_hunt_scenery.gd/ghost_hunt_hud.gd (Sync-Anker der
## Szene bleiben stehen — Kontrakt von test_mph_polish/screenshot_3da),
## Intro-Beat 1,5 s gatet Sim UND Eingabe mit Gruft→Tor-Kameraschwenk
## (M1/Q4), _ui-Skalierung des HUD samt vp-gekoppelter Hinweis-Breite
## (M9/Q5), Hint-Fade (Q3), Creme-Banner-Plate statt des rohen dunklen
## Vollbreiten-Bands (M7), Reduced-Motion-Gate an der Funken-Call-Site (Q2)
## und die DE/EN-Parität der neuen Domain-Datei mg_ghost.json. Die MECHANIK
## (ghost_hunt_logic.gd) wird hier NICHT berührt — deren Zahlen sichern
## test_mg2_ghost_hunt und test_w13c_crosscheck (test_ghost_hunt_matches_web).

const Ghost := preload("res://scripts/minigames/games/ghost_hunt/ghost_hunt.gd")
const GHOST_SCENE := "res://scripts/minigames/games/ghost_hunt/ghost_hunt.tscn"
## Fenster-Pinnung VOR der Instanziierung: setup() rahmt die Kamera aus dem
## echten Viewport — ein Resize NACH dem Mount würde mitten im Test
## size_changed/apply_view feuern und die Kamera-Asserts verwackeln.
const WINDOW := Vector2i(720, 1160)

var _end_results: Array[Dictionary] = []


func _mount(difficulty := "normal") -> MinigameBase:
	tree.root.size = WINDOW
	var ctx := MinigameCtx.new()
	ctx.game_id = "ghostHunt"
	ctx.difficulty = difficulty
	ctx.run_seed = 4242
	ctx.on_end = Callable(self, "_capture_end")
	var game: MinigameBase = (load(GHOST_SCENE) as PackedScene).instantiate()
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


func test_intro_beat_konstante() -> void:
	var consts := (Ghost as GDScript).get_script_constant_map()
	assert_true(consts.has("INTRO_S"), "INTRO_S vorhanden")
	assert_almost(float(consts["INTRO_S"]), 1.5, 1e-6, "Intro-Beat = 1,5 s (W14-Kanon)")


func test_intro_gatet_sim_und_eingabe() -> void:
	var game := _mount()
	assert_almost(float(game.get("_intro_left")), 1.5, 1e-6, "Intro startet voll")
	var hud: GhostHuntHud = game.get("hud")
	assert_eq(hud.banner_text, I18nService.t("mg.ghostHunt.intro"), "Ziel-Banner")
	assert_true(hud.banner_t > 0.0, "Banner steht im Intro")
	for _i in 3:
		game._process(0.4)
	assert_true(float(game.get("_intro_left")) > 0.0, "Beat läuft noch (1,2 s)")
	var state: Dictionary = game.get("state")
	assert_almost(float(state["t"]), 0.0, 1e-6, "Sim-Uhr wartet im Intro")
	# Eingabe ist gegatet: ein Tipp ins Dunkel würde die Kette brechen —
	# im Intro erreicht er die Logik gar nicht erst.
	state["chain"] = 3
	_tap(game, Vector2(360.0, 580.0))
	assert_eq(int(state["chain"]), 3, "Tipp wirkt im Intro nicht (Kette bleibt)")
	game._process(0.4)
	assert_almost(float(game.get("_intro_left")), 0.0, 1e-6, "Beat nach 1,6 s vorbei")
	assert_almost(float(state["t"]), 0.0, 1e-6, "Übergangs-Frame zählt nicht")
	game._process(0.2)
	assert_almost(float(state["t"]), 0.2, 1e-6, "danach tickt die Sim normal")
	_tap(game, Vector2(360.0, 580.0))
	assert_eq(int(state["chain"]), 0, "nach dem Intro erreicht der Tipp die Logik")
	game.free()


func test_intro_kamera_gruft_schwenk() -> void:
	var game := _mount()
	var stage: Node3D = game.get("_stage")
	var cam: Camera3D = stage.get("camera")
	var play_from: Vector3 = game.get("_play_from")
	var crypt: Vector3 = game.call("_crypt_anchor")
	game._process(0.1)
	assert_true(
		cam.position.distance_to(play_from) > 0.5, "Intro: Kamera hängt NICHT in der Spielpose"
	)
	assert_true(
		cam.position.distance_to(crypt) < play_from.distance_to(crypt),
		"Intro: Kamera startet an der Gruft (näher dran als die Spielpose)"
	)
	# Der letzte Intro-Frame fährt exakt in die fit()-Spielpose — kein Ruck.
	game.set("_intro_left", 0.05)
	game._process(0.1)
	assert_almost(cam.position.x, play_from.x, 1e-4, "Spielpose x")
	assert_almost(cam.position.y, play_from.y, 1e-4, "Spielpose y")
	assert_almost(cam.position.z, play_from.z, 1e-4, "Spielpose z")
	var settled := cam.transform
	game.call("_frame_yard")
	assert_true(cam.transform.is_equal_approx(settled), "Pose identisch mit frischem _frame_yard()")
	game.free()


func test_ui_faktor_und_hint_breite() -> void:
	var game := _mount()
	game.call("apply_view", Vector2(390.0, 844.0))
	assert_almost(float(game.get("_ui")), 1.0, 1e-6, "Phone-Kurzkante = Faktor 1")
	var hud: GhostHuntHud = game.get("hud")
	assert_eq(hud.score_label.get_theme_font_size("font_size"), 34, "Phone: Headline wie Theme")
	assert_eq(hud.score_label.position, Vector2(16.0, 10.0), "Phone: Entwurfsposition")
	for label: Label in [hud.score_label, hud.chain_label, hud.hint_label]:
		assert_true(label.get_theme_constant("outline_size") >= 6, "Kontur bleibt (M7)")
	game.call("apply_view", Vector2(834.0, 1194.0))
	assert_almost(float(game.get("_ui")), 834.0 / 390.0, 1e-4, "iPad: Kurzkante/390")
	assert_eq(
		hud.score_label.get_theme_font_size("font_size"),
		int(34.0 * 834.0 / 390.0),
		"HUD wächst mit"
	)
	game.call("apply_view", Vector2(9999.0, 9999.0))
	assert_almost(float(game.get("_ui")), 3.0, 1e-6, "Deckel bei 3,0")
	game.call("apply_view", Vector2(200.0, 400.0))
	assert_almost(float(game.get("_ui")), 0.75, 1e-6, "Boden bei 0,75")
	assert_true(
		hud.hint_label.size.x <= 360.0 * 0.75 + 0.001, "Hinweis-Breite folgt _ui statt Fix-340-px"
	)
	var vp := (game.call("get_viewport_rect") as Rect2).size
	assert_true(hud.hint_label.size.x <= vp.x - 32.0 * 0.75 + 0.001, "Hinweis bleibt im Bild")
	game.free()


func test_hint_fade() -> void:
	var game := _mount()
	var hud: GhostHuntHud = game.get("hud")
	game._process(0.4)
	assert_almost(hud.hint_seen, 0.0, 1e-6, "Hinweis-Uhr wartet im Intro (Lesezeit)")
	game.set("_intro_left", 0.0)
	game._process(0.5)
	assert_almost(hud.hint_label.modulate.a, 1.0, 1e-6, "Hinweis steht am Anfang voll")
	hud.hint_seen = 8.0
	game._process(0.016)
	assert_almost(hud.hint_label.modulate.a, 0.0, 1e-6, "nach ~6 s blendet der Hinweis aus (Q3)")
	game.free()


func test_banner_plate_statt_band() -> void:
	var game := _mount()
	assert_false(game.has_method("_draw_banner"), "rohes draw_string-Band ist ersetzt (M7)")
	assert_false(game.has_method("_show_banner"), "Banner-Zustand wohnt im HUD-Helfer")
	game.set("_intro_left", 0.0)
	var hud: GhostHuntHud = game.get("hud")
	hud.banner_t = 0.0
	# Attrappen-Ereignis einspeisen: der Event-Übersetzer füttert das Band.
	((game.get("state") as Dictionary)["events"] as Array).append({"type": "decoy"})
	game.call("_drain_events")
	assert_eq(hud.banner_text, I18nService.t("mg.ghostHunt.decoy"), "Attrappen-Banner")
	assert_true(hud.banner_t > 0.0, "Banner-Plate steht")
	game.free()


func test_q2_gate_funken() -> void:
	var previous: Variant = _set_reduced_motion(true)
	if previous == null:
		fail_test("AppSettings-Autoload fehlt")
		return
	var game := _mount()
	game.set("_intro_left", 0.0)
	var sparks: Node3D = game.get("_sparks")
	var particles: GPUParticles3D = sparks.get("particles")
	game.call("_on_catch", {"spot": 0, "chain": 1, "points": 3})
	assert_false(particles.emitting, "Reduced Motion: Fang-Funken bleiben aus (Q2)")
	_set_reduced_motion(false)
	game.call("_on_catch", {"spot": 0, "chain": 1, "points": 3})
	assert_true(particles.emitting, "Normal: Fang-Funken feuern")
	game.free()
	_set_reduced_motion(bool(previous))


func test_scenery_anker_stehen() -> void:
	var game := _mount()
	assert_eq((game.get("_mist") as Array).size(), 5, "fünf Nebelschwaden (mph-Kontrakt)")
	assert_eq((game.get("_ghosts") as Array).size(), 6, "Geister-Pool = 6 Rigs")
	assert_eq((game.get("_decoys") as Array).size(), 4, "vier Attrappen")
	assert_eq((game.get("_tokens") as Array).size(), 2, "Laterne + Netz")
	assert_true(game.get("_gooby") != null, "Gooby steht am Tor")
	assert_true(game.get("_lantern_light") != null, "Laternenlicht hängt")
	assert_true(game.get("_sky") != null, "Kamerafeste Himmelskuppel")
	assert_false(bool(game.has_visible_ghost()), "vor dem ersten Spawn kein Geist")
	# Nebel treibt weiter über die Szene (Kontrakt von test_mph_polish).
	var wisp: Node3D = ((game.get("_mist") as Array)[0] as Dictionary)["node"]
	var before := wisp.position
	game.set("_bob", 10.0)
	game.call("_drift_mist")
	assert_true(before.distance_to(wisp.position) > 0.01, "Nebel driftet")
	game.free()


func test_strings_de_en_paritaet() -> void:
	var de := _flat_keys("res://strings/de/mg_ghost.json")
	var en := _flat_keys("res://strings/en/mg_ghost.json")
	assert_eq(de, en, "DE/EN-Schlüssel der Domain-Datei paritätisch")
	assert_true(de.has("mg.ghostHunt.intro"), "ghostHunt-Intro-Key vorhanden")
	assert_ne(
		I18nService.t("mg.ghostHunt.intro"),
		"mg.ghostHunt.intro",
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
