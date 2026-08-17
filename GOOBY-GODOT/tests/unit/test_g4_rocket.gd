extends TestCase
## G4-ROCKET — Präsentations-Verträge der rocketRescue-Politur (W17):
## HUD-Entflechtung (der Tankbalken liegt UNTER den Labels statt mit dem
## „Gerettet"-Label zu kollidieren — der Audit-Defekt) samt _ui-Skalierung
## (M9/M7), Intro-Beat 1,5 s gatet Sim UND Eingabe bei zahlengleichem Lauf
## (M1, Crosscheck-Vertrag), Hint-Fade nach 5 s Sim-Zeit (M6), Schub-Loop
## mit play()-Gate + Spool-Pitch (M3/M10), Reduced-Motion-Gates für
## Böen-Partikel und Intro-Flug, Endton-Wahl (M8) und die DE/EN-Parität
## der neuen Domain-Datei mg_rocket.json.
## Die MECHANIK (rocket_rescue_engine.gd, zertifiziert) wird NICHT berührt.

const Rocket := preload("res://scripts/minigames/games/rocket_rescue/rocket_rescue.gd")
const Logic := preload("res://scripts/minigames/games/rocket_rescue/rocket_rescue_logic.gd")
const Lander := preload("res://scripts/minigames/games/rocket_rescue/rocket_rescue_engine.gd")
const SCENE := "res://scripts/minigames/games/rocket_rescue/rocket_rescue.tscn"


func _mount(difficulty := "normal", seed_value := 4242) -> MinigameBase:
	var ctx := MinigameCtx.new()
	ctx.game_id = "rocketRescue"
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


func test_intro_beat_konstante() -> void:
	var consts := (Rocket as GDScript).get_script_constant_map()
	assert_true(consts.has("INTRO_S"), "rocketRescue hat INTRO_S")
	assert_almost(float(consts["INTRO_S"]), 1.5, 1e-6, "Intro-Beat = 1,5 s (W14-Kanon)")


func test_intro_gatet_sim_und_eingabe() -> void:
	var game := _mount()
	assert_almost(float(game.get("_intro_left")), 1.5, 1e-6, "Intro startet voll")
	assert_eq(
		str(game.get("_flash_text")), I18nService.t("mg.rocketRescue.intro"), "Ziel-Banner steht"
	)
	assert_true(float(game.get("_flash")) > 1.5, "Banner überdauert den ganzen Beat")
	var eng: RocketRescueEngine = game.get("engine")
	for _i in 3:
		game._process(0.4)
	assert_true(float(game.get("_intro_left")) > 0.0, "Beat läuft noch (1,2 s)")
	assert_almost(float(eng.state["elapsed"]), 0.0, 0.0, "Sim-Uhr wartet im Intro")
	# Eingabe ist gegatet: der Touch zündet noch keinen Schub.
	var touch := InputEventScreenTouch.new()
	touch.position = Vector2(200.0, 400.0)
	touch.pressed = true
	game._unhandled_input(touch)
	assert_false(bool(game.get("_thrust")), "Touch zündet im Intro keinen Schub")
	game._process(0.4)
	assert_almost(float(game.get("_intro_left")), 0.0, 1e-6, "Beat nach 1,6 s vorbei")
	assert_almost(float(eng.state["elapsed"]), 0.0, 0.0, "Übergangs-Frame zählt nicht")
	game._process(0.03)
	assert_almost(float(eng.state["elapsed"]), 0.03, 1e-9, "danach tickt die Sim normal")
	game._unhandled_input(touch)
	assert_true(bool(game.get("_thrust")), "nach dem Beat zündet der Touch")
	game.free()


func test_intro_lauf_bleibt_zahlengleich() -> void:
	# Referenz: roher Engine-Lauf OHNE Szene/Intro — exakt der Vertrag, den
	# auch test_w13c_crosscheck an der Sim festschraubt (Seed 5 = Goldwerte).
	var rng := GoobyRng.new(5)
	var raw := Lander.new(
		func() -> float: return rng.next(), Logic.apply_difficulty(Logic.ROCKET, "normal")
	)
	var game := _mount("normal", 5)
	var eng: RocketRescueEngine = game.get("engine")
	assert_eq(eng.layout["platforms"], raw.layout["platforms"], "Plattform-Layout zahlengleich")
	assert_eq(eng.layout["fuelPickups"], raw.layout["fuelPickups"], "Kanister zahlengleich")
	for _i in 3:
		game._process(0.5)
	assert_almost(float(game.get("_intro_left")), 0.0, 1e-6, "Intro nach 1,5 s vorbei")
	assert_almost(float(eng.state["elapsed"]), 0.0, 0.0, "Intro hat die Sim nicht angefasst")
	for _i in 5:
		game._process(0.03)
		raw.step({"thrust": false, "tiltDir": 0}, 0.03)
	assert_eq(eng.state, raw.state, "Sim-Zustand nach dem Intro bit-gleich zum Referenzlauf")
	game.free()


func test_intro_kamera_totale_und_exakte_spielpose() -> void:
	var game := _mount()
	var stage: Node3D = game.get("_stage")
	var cam: Camera3D = stage.get("camera")
	var play_y := float(stage.get("_play_cam_y"))
	var cam_dist := float((stage.get_script() as GDScript).get_script_constant_map()["CAM_DIST"])
	game._process(0.1)
	assert_true(cam.position.y > play_y + 0.5, "Totale: Kamera startet erhöht")
	assert_true(cam.position.z > cam_dist + 1.0, "Totale: Kamera zurückgezogen")
	assert_true(cam.rotation_degrees.x > 0.5, "Totale: Blick hoch Richtung Planet")
	# Der letzte Intro-Frame ruft establish(1.0) — exakte Spielpose, kein Ruck.
	game.set("_intro_left", 0.05)
	game._process(0.1)
	assert_almost(cam.position.y, play_y, 1e-4, "Spielpose: exakte setup_stage-Höhe")
	assert_almost(cam.position.z, cam_dist, 1e-4, "Spielpose: exakter Kameraabstand")
	assert_almost(cam.rotation_degrees.x, 0.0, 1e-4, "Spielpose: frontal")
	game.free()


func test_hud_entflechtung_tankbalken_unter_labels() -> void:
	# DER Audit-Defekt (mg-audit-c §2): Balken bei fix view.y*0.055 lief durch
	# das „Gerettet"-Label (y=48). Jetzt liegt er in JEDER Größe UNTER beiden
	# Labels — hochkant, quer, Tablet und der Letterbox-Kleinstfall.
	# Textmaß = Fontgröße × 1,6 (gerenderte Baloo-Zeile ≈ 1,4 em + Reserve);
	# get_minimum_size (3 em Metrik-Box) bläht nur Layout, nicht Glyphen.
	var game := _mount()
	var sizes: Array[Vector2] = [
		Vector2(390.0, 844.0), Vector2(834.0, 1194.0), Vector2(1160.0, 720.0), Vector2(272.0, 574.0)
	]
	for size: Vector2 in sizes:
		game.call("apply_view", size)
		var bar: Rect2 = game.call("fuel_bar_rect")
		var rescue: Label = game.get("_rescue_label")
		var text_bottom := rescue.position.y + float(rescue.get_theme_font_size("font_size")) * 1.6
		assert_true(
			bar.position.y >= text_bottom - 0.001,
			"Balken-Y %.1f unter Text-Ende %.1f bei %s" % [bar.position.y, text_bottom, size]
		)
		assert_true(
			bar.position.y > rescue.position.y, "Balken-Band über Gerettet-Label (%s)" % size
		)
		var old_y := size.y * 0.055
		assert_true(old_y < text_bottom, "Gegenprobe %s: die alte Fix-Position kollidierte" % size)
	game.free()


func test_ui_faktor_und_hud_skalierung() -> void:
	var game := _mount()
	game.call("apply_view", Vector2(390.0, 844.0))
	assert_almost(float(game.get("_ui")), 1.0, 1e-6, "Phone-Kurzkante = Faktor 1")
	var fuel: Label = game.get("_fuel_label")
	assert_eq(fuel.get_theme_font_size("font_size"), 34, "Phone: Headline wie Theme")
	assert_true(fuel.get_theme_constant("outline_size") >= 6, "Kontur auf dem Tank (M7)")
	var rescue: Label = game.get("_rescue_label")
	assert_true(rescue.get_theme_constant("outline_size") >= 5, "Kontur auf Gerettet (M7)")
	game.call("apply_view", Vector2(834.0, 1194.0))
	assert_almost(float(game.get("_ui")), 834.0 / 390.0, 1e-4, "iPad: Kurzkante/390")
	assert_eq(fuel.get_theme_font_size("font_size"), int(34.0 * 834.0 / 390.0), "HUD wächst")
	game.call("apply_view", Vector2(9999.0, 9999.0))
	assert_almost(float(game.get("_ui")), 3.0, 1e-6, "Deckel bei 3,0")
	game.call("apply_view", Vector2(200.0, 400.0))
	assert_almost(float(game.get("_ui")), 0.75, 1e-6, "Boden bei 0,75")
	var hint: Label = game.get("_hint_label")
	assert_true(hint.size.x <= 360.0 * 0.75 + 0.001, "Hinweis-Breite folgt _ui statt Fix-320")
	game.free()


func test_hint_fade_nach_5s_simzeit() -> void:
	var game := _mount()
	game.set("_intro_left", 0.0)
	var eng: RocketRescueEngine = game.get("engine")
	var hint: Label = game.get("_hint_label")
	game.call("_update_labels")
	assert_almost(hint.modulate.a, 1.0, 1e-6, "Start: Hinweis voll lesbar")
	eng.state["elapsed"] = 6.5
	game.call("_update_labels")
	assert_almost(hint.modulate.a, 0.0, 1e-6, "nach 5 s + Fade: ausgeblendet (M6)")
	game.free()


func test_schub_loop_gate_und_spool_pitch() -> void:
	var game := _mount()
	var sfx: AudioStreamPlayer = game.get("_thrust_sfx")
	if sfx == null:
		fail_test("Schub-Loop fehlt (ranch_ambience_wind nicht auflösbar?)")
		game.free()
		return
	assert_false(sfx.playing, "play()-Gate: der Loop startet NICHT beim Mount")
	game.set("_intro_left", 0.0)
	game._process(0.05)
	assert_false(sfx.playing, "ohne Schub bleibt der Loop ungestartet")
	game.set("_thrust", true)
	game._process(0.05)
	assert_true(sfx.playing, "der ERSTE Schub weckt den Loop (play bei Bedarf)")
	assert_false(sfx.stream_paused, "beim Brennen läuft der Loop")
	var pitch_first := sfx.pitch_scale
	game._process(0.05)
	assert_true(sfx.pitch_scale > pitch_first, "Pitch spult mit dem Schub hoch (M10)")
	game.set("_thrust", false)
	game._process(0.05)
	assert_true(sfx.stream_paused, "ohne Schub pausiert der Loop (kein Dauerton)")
	game.free()


func test_reduced_motion_gatet_wind_und_introflug() -> void:
	var previous: Variant = _set_reduced_motion(true)
	if previous == null:
		fail_test("AppSettings-Autoload fehlt")
		return
	var game := _mount()
	var stage: Node3D = game.get("_stage")
	var cam: Camera3D = stage.get("camera")
	var play_y := float(stage.get("_play_cam_y"))
	var eng: RocketRescueEngine = game.get("engine")
	(eng.state["wind"] as Dictionary)["phase"] = "gust"
	game._process(0.1)
	assert_almost(cam.position.y, play_y, 1e-4, "RM: Intro-Flug übersprungen (Spielpose)")
	assert_almost(cam.rotation_degrees.x, 0.0, 1e-4, "RM: kein Kamera-Kippen")
	var wind: GPUParticles3D = stage.get("_wind")
	assert_false(wind.emitting, "RM: Böen-Deko-Partikel bleiben aus (Q2)")
	game.free()
	_set_reduced_motion(false)
	var game2 := _mount()
	var eng2: RocketRescueEngine = game2.get("engine")
	(eng2.state["wind"] as Dictionary)["phase"] = "gust"
	game2._process(0.1)
	var wind2: GPUParticles3D = (game2.get("_stage") as Node3D).get("_wind")
	assert_true(wind2.emitting, "Gegenprobe ohne RM: die Böe emittiert")
	game2.free()
	_set_reduced_motion(bool(previous))


func test_endton_wahl_pur() -> void:
	assert_eq(Rocket.end_tone_for("complete", false), "mg_win", "Komplett-Rettung feiert")
	assert_eq(Rocket.end_tone_for("complete", true), "mg_win")
	assert_eq(Rocket.end_tone_for("time", false), "mg_lose", "Zeit-Ende war stumm (M8)")
	assert_eq(Rocket.end_tone_for("fuel", false), "mg_lose", "Sprit-Ende auf der Station")
	assert_eq(Rocket.end_tone_for("fuel", true), "", "Abschlepp-Ton spielte schon — kein Doppel")


func test_intro_strings_de_en_paritaet() -> void:
	var de := _flat_keys("res://strings/de/mg_rocket.json")
	var en := _flat_keys("res://strings/en/mg_rocket.json")
	assert_eq(de, en, "DE/EN-Schlüssel der Domain-Datei paritätisch")
	assert_true(de.has("mg.rocketRescue.intro"), "Intro-Key vorhanden")
	assert_ne(
		I18nService.t("mg.rocketRescue.intro"),
		"mg.rocketRescue.intro",
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
