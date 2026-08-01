extends TestCase
## G4-GOALIE — Präsentations-Verträge der goalieGooby-Politur (W17):
## das tote Jubel-Feature ist angeschlossen (_crowd_pulse bei Parade UND
## Gegentor, M2/M8), Intro-Beat 1,2 s gatet Sim + Eingabe und fliegt vom
## Vereinsheim in die exakte Spielpose (M1), Telegraph-Legende nutzt exakt
## die Leuchtfeld-Farben (M4), _ui-Skalierung des HUD samt Hint-Fade (M9/M6),
## Reduced-Motion-Gates der eigenen FX und DE/EN-Parität von mg_goalie.json.
## Die MECHANIK (goalie_gooby_logic.gd) wird hier NICHT berührt.

const Goalie := preload("res://scripts/minigames/games/goalie_gooby/goalie_gooby.gd")
const Scenery := preload("res://scripts/minigames/games/goalie_gooby/goalie_gooby_scenery.gd")
const SCENE := "res://scripts/minigames/games/goalie_gooby/goalie_gooby.tscn"


func _mount(difficulty := "normal", seed_value := 4242) -> MinigameBase:
	var ctx := MinigameCtx.new()
	ctx.game_id = "goalieGooby"
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


## Legt einen entschiedenen Schuss in die Szene (reines Setzen von Sicht-
## Zustand; die Logik-Funktionen entscheiden in _resolve_kick wie im Spiel).
func _stage_kick(game: MinigameBase, dive: Dictionary) -> void:
	game.set(
		"kick", {"lane": 2, "kind": "straight", "telegraph": 0.5, "flight": 0.5, "shootout": false}
	)
	game.set("kick_start", 0.0)
	game.set("arrive_t", 1.0)
	game.set("elapsed", 1.0)
	game.set("dive", dive)


func test_intro_beat_konstante() -> void:
	var consts := (Goalie as GDScript).get_script_constant_map()
	assert_true(consts.has("INTRO_S"), "goalieGooby hat INTRO_S")
	assert_almost(float(consts["INTRO_S"]), 1.2, 1e-6, "Intro-Beat = 1,2 s (§3.6-Vorgabe)")


func test_intro_gatet_sim_und_eingabe() -> void:
	var game := _mount()
	assert_almost(float(game.get("_intro_left")), 1.2, 1e-6, "Intro startet voll")
	assert_true(float(game.get("_intro_banner_t")) > 0.0, "Ziel-Banner steht im Intro")
	for _i in 2:
		game._process(0.5)
	assert_true(float(game.get("_intro_left")) > 0.0, "Beat läuft noch (1,0 s)")
	assert_almost(float(game.get("elapsed")), 0.0, 1e-6, "Sim-Uhr wartet im Intro")
	assert_true((game.get("kick") as Dictionary).is_empty(), "kein Schuss im Intro")
	var press := InputEventScreenTouch.new()
	press.position = Vector2(100.0, 100.0)
	press.pressed = true
	var release := InputEventScreenTouch.new()
	release.position = Vector2(100.0, 100.0)
	release.pressed = false
	game._unhandled_input(press)
	game._unhandled_input(release)
	assert_true((game.get("dive") as Dictionary).is_empty(), "Intro gatet die Eingabe")
	game._process(0.3)
	assert_almost(float(game.get("_intro_left")), 0.0, 1e-6, "Beat nach 1,3 s vorbei")
	assert_almost(float(game.get("elapsed")), 0.0, 1e-6, "Übergangs-Frame zählt nicht")
	game._process(0.2)
	assert_almost(float(game.get("elapsed")), 0.2, 1e-6, "danach tickt die Sim normal")
	game._unhandled_input(press)
	game._unhandled_input(release)
	assert_eq(int((game.get("dive") as Dictionary).get("lane", -1)), 2, "Tippen hechtet Mitte")
	game.free()


func test_intro_kamera_fliegt_vom_vereinsheim_in_die_spielpose() -> void:
	var game := _mount()
	var stage: Node3D = game.get("_stage")
	var cam: Camera3D = stage.get("camera")
	var play: Transform3D = game.get("_play_cam")
	assert_true(cam.position.distance_to(play.origin) > 1.0, "Intro: Kamera startet abseits")
	assert_true(cam.position.x < -1.0, "Start-Pose steht auf der Vereinsheim-Seite")
	game._process(0.4)
	var mid := cam.position
	game._process(0.4)
	assert_true(cam.position.distance_to(mid) > 0.01, "die Kamera fliegt (kein Standbild)")
	game.set("_intro_left", 0.05)
	game._process(0.1)
	assert_true(
		cam.position.distance_to((game.get("_play_cam") as Transform3D).origin) < 1e-3,
		"nach dem Beat steht die Kamera EXAKT in der fit()-Spielpose (kein Ruck)"
	)
	game.free()


func test_ui_faktor_und_hud_skalierung() -> void:
	var game := _mount()
	game.call("apply_view", Vector2(844.0, 390.0))
	assert_almost(float(game.get("_ui")), 1.0, 1e-6, "Phone-Kurzkante = Faktor 1")
	var label: Label = game.get("_time_label")
	assert_eq(label.get_theme_font_size("font_size"), 34, "Phone: Headline wie Theme")
	assert_eq(label.position, Vector2(16.0, 10.0), "Phone: Entwurfsposition")
	assert_true(label.get_theme_constant("outline_size") >= 6, "Kontur auf der Zeit (M7)")
	game.call("apply_view", Vector2(1194.0, 834.0))
	assert_almost(float(game.get("_ui")), 834.0 / 390.0, 1e-4, "iPad: Kurzkante/390")
	assert_eq(label.get_theme_font_size("font_size"), int(34.0 * 834.0 / 390.0), "HUD wächst")
	game.call("apply_view", Vector2(9999.0, 9999.0))
	assert_almost(float(game.get("_ui")), 3.0, 1e-6, "Deckel bei 3,0")
	game.call("apply_view", Vector2(400.0, 200.0))
	assert_almost(float(game.get("_ui")), 0.75, 1e-6, "Boden bei 0,75")
	var hint: Label = game.get("_hint_label")
	assert_true(hint.size.x <= 460.0 * 0.75 + 0.001, "Hinweis-Breite folgt _ui statt Fix-300-px")
	game.free()


func test_crowd_pulse_bei_parade_und_gegentor() -> void:
	var game := _mount()
	game.set("_intro_left", 0.0)
	assert_almost(float(game.get("_crowd_pulse")), 0.0, 1e-6, "Tribüne startet ruhig")
	_stage_kick(game, {"lane": 2, "v": "mid", "t": 0.7})
	game.call("_resolve_kick")
	assert_eq(int(game.get("saves")), 1, "Parade gezählt (Logik unangetastet)")
	var save_pulse := float(game.get("_crowd_pulse"))
	assert_true(save_pulse > 0.0, "TOTES FEATURE EINGELÖST: Parade weckt die Tribüne")
	_stage_kick(game, {"lane": 2, "v": "mid", "t": 0.9})
	game.call("_resolve_kick")
	assert_true(float(game.get("_crowd_pulse")) > save_pulse, "Superparade hüpft höher als Parade")
	game.set("_crowd_pulse", 0.0)
	_stage_kick(game, {})
	game.call("_resolve_kick")
	assert_eq(int(game.get("goals")), 1, "Gegentor gezählt (Logik unangetastet)")
	var goal_pulse := float(game.get("_crowd_pulse"))
	assert_true(goal_pulse > 0.0, "auch das Gegentor erreicht die Tribüne")
	assert_true(goal_pulse < save_pulse, "Gegentor-Zucken bleibt schwächer als der Jubel")
	# Der Puls baut sich in _tick_crowd ab und hebt den Zuschauer-Knoten.
	var crowd: Node3D = game.get("_crowd")
	game.set("_crowd_pulse", 1.0)
	game.call("_tick_crowd", 0.05)
	assert_true(float(game.get("_crowd_pulse")) < 1.0, "Puls klingt ab")
	assert_true(crowd.position.y > 0.0, "die Blobs heben ab (Hüpfer sichtbar)")
	game.free()


func test_reduced_motion_gatet_intro_flug_und_tribuene() -> void:
	var previous: Variant = _set_reduced_motion(true)
	if previous == null:
		fail_test("AppSettings-Autoload fehlt")
		return
	var game := _mount()
	var stage: Node3D = game.get("_stage")
	var cam: Camera3D = stage.get("camera")
	var play: Transform3D = game.get("_play_cam")
	assert_true(cam.position.distance_to(play.origin) < 1e-4, "RM: kein Kameraflug im Intro")
	game._process(0.4)
	assert_true(cam.position.distance_to(play.origin) < 1e-4, "RM: Kamera bleibt stehen")
	assert_true(float(game.get("_intro_left")) > 0.0, "der Beat selbst wartet trotzdem")
	game.set("_intro_left", 0.0)
	_stage_kick(game, {"lane": 2, "v": "mid", "t": 0.7})
	game.call("_resolve_kick")
	assert_eq(int(game.get("saves")), 1, "Parade zählt auch unter RM")
	assert_almost(float(game.get("_crowd_pulse")), 0.0, 1e-6, "RM: Tribüne hüpft nicht")
	_stage_kick(game, {})
	game.call("_resolve_kick")
	assert_almost(float(game.get("_crowd_pulse")), 0.0, 1e-6, "RM: auch kein Gegentor-Zucken")
	game.free()
	_set_reduced_motion(bool(previous))


func test_hint_fade_nach_5s() -> void:
	var game := _mount()
	game.set("_intro_left", 0.0)
	var hint: Label = game.get("_hint_label")
	game.call("_update_labels")
	assert_almost(hint.modulate.a, 1.0, 1e-6, "Hinweis startet voll sichtbar")
	game.set("elapsed", 5.75)
	game.call("_update_labels")
	assert_almost(hint.modulate.a, 0.5, 1e-6, "Fade läuft (5,75 s)")
	game.set("elapsed", 7.0)
	game.call("_update_labels")
	assert_almost(hint.modulate.a, 0.0, 1e-6, "nach 6,5 s ist der Hinweis weg (M6)")
	game.free()


func test_telegraph_legende_nutzt_leuchtfeld_farben() -> void:
	var game := _mount()
	var legend: Array = game.get("_intro_legend")
	assert_eq(legend.size(), 2, "zwei Legenden-Zeilen (Heber + Roller)")
	assert_eq(legend[0][0] as Color, Scenery.LOB_TINT, "Heber-Punkt = Leuchtfeld-Blau")
	assert_eq(legend[1][0] as Color, Scenery.ROLLER_TINT, "Roller-Punkt = Leuchtfeld-Rosa")
	assert_ne(str(legend[0][1]), "", "Heber-Erklärtext gefüllt")
	assert_ne(str(legend[1][1]), "", "Roller-Erklärtext gefüllt")
	game.free()


func test_intro_strings_de_en_paritaet() -> void:
	var de := _flat_keys("res://strings/de/mg_goalie.json")
	var en := _flat_keys("res://strings/en/mg_goalie.json")
	assert_eq(de, en, "DE/EN-Schlüssel der Domain-Datei paritätisch")
	assert_true(de.has("mg.goalieGooby.intro"), "Intro-Key vorhanden")
	assert_true(de.has("mg.goalieGooby.intro_lob"), "Heber-Key vorhanden")
	assert_true(de.has("mg.goalieGooby.intro_roller"), "Roller-Key vorhanden")
	assert_ne(
		I18nService.t("mg.goalieGooby.intro"),
		"mg.goalieGooby.intro",
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
