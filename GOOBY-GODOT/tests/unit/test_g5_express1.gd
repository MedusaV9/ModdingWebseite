extends TestCase
## G5 P32 MG-EXPRESS-1 — Präsentations-Verträge der Restpunkte-Politur von
## burgerBuild + deliveryRush (Audit A §2.4/§2.7):
## Intro-Beats 1,5 s gaten Sim UND Eingabe bei zahlengleichem Lauf (M1,
## Crosscheck-Vertrag), Küchen-/Stadt-Totale mit exakter Spielpose danach,
## burgerBuild-Hint-Fade (M6), Flash-Plate UNTER den Lampen (M7),
## Ticket-Dringlichkeit (M4) + Gast-Goobys (M2) samt Q2-RM-Gates,
## deliveryRush-Motor-Loop (M10, rocket-Muster), Bump-Drossel + Karosserie-
## Ruck, Routen-Band-Verschlankung und die DE/EN-Parität von mg_express1.
## Die MECHANIK (burger_build_logic/delivery_rush_logic) wird NICHT berührt —
## Crosscheck: test_burger_build_matches_web / test_delivery_rush_matches_web.

const Burger := preload("res://scripts/minigames/games/burger_build/burger_build.gd")
const Delivery := preload("res://scripts/minigames/games/delivery_rush/delivery_rush.gd")
const Feel := preload("res://scripts/minigames/games/delivery_rush/delivery_rush_feel.gd")
const BURGER_SCENE := "res://scripts/minigames/games/burger_build/burger_build.tscn"
const DELIVERY_SCENE := "res://scripts/minigames/games/delivery_rush/delivery_rush.tscn"


func _mount(scene: String, game_id: String, seed_value := 4242) -> MinigameBase:
	var ctx := MinigameCtx.new()
	ctx.game_id = game_id
	ctx.difficulty = "normal"
	ctx.run_seed = seed_value
	var game: MinigameBase = (load(scene) as PackedScene).instantiate()
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


func test_intro_beat_konstanten() -> void:
	for script: GDScript in [Burger, Delivery]:
		var consts := script.get_script_constant_map()
		assert_true(consts.has("INTRO_S"), "INTRO_S vorhanden")
		assert_almost(float(consts["INTRO_S"]), 1.5, 1e-6, "Intro-Beat = 1,5 s (W14-Kanon)")


# ── burgerBuild ────────────────────────────────────────────────────────────


func test_burger_intro_gatet_sim_und_eingabe() -> void:
	var game := _mount(BURGER_SCENE, "burgerBuild")
	assert_almost(float(game.get("_intro_left")), 1.5, 1e-6, "Intro startet voll")
	assert_eq(
		str(game.get("_flash_text")), I18nService.t("mg.burgerBuild.intro"), "Ziel-Banner steht"
	)
	assert_true(float(game.get("_flash")) > 1.5, "Banner überdauert den ganzen Beat")
	for _i in 3:
		game._process(0.4)
	assert_true(float(game.get("_intro_left")) > 0.0, "Beat läuft noch (1,2 s)")
	assert_almost(float(game.get("elapsed")), 0.0, 0.0, "Sim-Uhr wartet im Intro")
	# Eingabe ist gegatet: der Touch schiebt den Teller noch nicht.
	var touch := InputEventScreenTouch.new()
	touch.position = Vector2(40.0, 500.0)
	touch.pressed = true
	game._unhandled_input(touch)
	assert_almost(float(game.get("plate_x")), 0.0, 1e-6, "Touch bewegt im Intro keinen Teller")
	game._process(0.4)
	assert_almost(float(game.get("_intro_left")), 0.0, 1e-6, "Beat nach 1,6 s vorbei")
	assert_almost(float(game.get("elapsed")), 0.0, 0.0, "Übergangs-Frame zählt nicht")
	game._process(0.03)
	assert_almost(float(game.get("elapsed")), 0.03, 1e-9, "danach tickt die Sim normal")
	game._unhandled_input(touch)
	assert_true(float(game.get("plate_x")) < 0.0, "nach dem Beat greift der Touch")
	game.free()


func test_burger_intro_lauf_bleibt_zahlengleich() -> void:
	# Referenz: gleiches Seed OHNE Intro (direkt auf 0 gesetzt) — nach
	# identischen Sim-Frames müssen Regen/Punkte bit-gleich stehen.
	var with_intro := _mount(BURGER_SCENE, "burgerBuild", 5)
	var reference := _mount(BURGER_SCENE, "burgerBuild", 5)
	reference.set("_intro_left", 0.0)
	assert_eq(with_intro.get("ticket"), reference.get("ticket"), "Ticket zahlengleich")
	for _i in 4:
		with_intro._process(0.4)
	assert_almost(float(with_intro.get("_intro_left")), 0.0, 1e-6, "Intro vorbei")
	assert_almost(float(with_intro.get("elapsed")), 0.0, 0.0, "Intro hat die Sim nicht angefasst")
	for _i in 12:
		with_intro._process(0.05)
		reference._process(0.05)
	assert_eq(with_intro.get("_items"), reference.get("_items"), "Zutaten-Regen bit-gleich")
	assert_almost(
		float(with_intro.get("score")), float(reference.get("score")), 0.0, "Punkte bit-gleich"
	)
	with_intro.free()
	reference.free()


func test_burger_intro_kamera_totale_und_exakte_spielpose() -> void:
	var game := _mount(BURGER_SCENE, "burgerBuild")
	var stage: Node3D = game.get("_stage")
	var cam: Camera3D = stage.get("camera")
	var cam_dist := float((stage.get_script() as GDScript).get_script_constant_map()["CAM_DIST"])
	game._process(0.1)
	assert_true(cam.position.y > 0.5, "Totale: Kamera startet erhöht")
	assert_true(cam.position.z > cam_dist + 1.0, "Totale: Kamera zurückgezogen")
	assert_true(cam.rotation_degrees.x < -0.5, "Totale: Blick hinunter in die Küche")
	# Der letzte Intro-Frame ruft establish(1.0) — exakte Spielpose, kein Ruck.
	game.set("_intro_left", 0.05)
	game._process(0.1)
	assert_almost(cam.position.y, 0.0, 1e-4, "Spielpose: Bildmitte = Weltnullpunkt")
	assert_almost(cam.position.z, cam_dist, 1e-4, "Spielpose: exakter Kameraabstand")
	assert_almost(cam.rotation_degrees.x, 0.0, 1e-4, "Spielpose: frontal")
	game.free()


func test_burger_hint_fade_nach_6s_simzeit() -> void:
	var game := _mount(BURGER_SCENE, "burgerBuild")
	var hint: Label = game.get("_hint_label")
	game.call("_update_labels")
	assert_almost(hint.modulate.a, 1.0, 1e-6, "Start: Hinweis voll lesbar (Intro zählt nicht)")
	game.set("elapsed", 7.5)
	game.call("_update_labels")
	assert_almost(hint.modulate.a, 0.0, 1e-6, "nach 6 s + Fade: ausgeblendet (M6)")
	game.free()


func test_burger_flash_plate_liegt_unter_den_lampen() -> void:
	# DER Audit-Beleg (burgerBuild_hoch.png): „Falsche Lage!" klebte bei
	# y·0,3 in den Deckenlampen. Die Plate-Oberkante (y·0,4) muss in BEIDEN
	# Formaten UNTER der Lampen-Unterkante (Welt-y ≈ 2,68) liegen.
	var game := _mount(BURGER_SCENE, "burgerBuild")
	for size: Vector2 in [Vector2(390.0, 844.0), Vector2(1160.0, 720.0), Vector2(834.0, 1194.0)]:
		game.call("apply_view", size)
		var lamp_bottom: Vector2 = game.call("project", 0.0, 2.68)
		assert_true(
			size.y * 0.4 > lamp_bottom.y + 8.0, "Plate-Oberkante unter den Lampen bei %s" % size
		)
	assert_true(game.get("_flash_plate") is StyleBoxFlat, "Milchglas-Plate vorhanden")
	game.free()


func test_burger_ticket_dringlichkeit_tickt_je_restsekunde() -> void:
	var game := _mount(BURGER_SCENE, "burgerBuild")
	game.set("order_left", 4.4)
	game.call("_tick_urgency")
	assert_eq(int(game.get("_last_tick_sec")), 5, "erster Tick bei Restsekunde 5")
	game.call("_tick_urgency")
	assert_eq(int(game.get("_last_tick_sec")), 5, "gleiche Restsekunde tickt nur EINMAL")
	game.set("order_left", 3.2)
	game.call("_tick_urgency")
	assert_eq(int(game.get("_last_tick_sec")), 4, "nächste Restsekunde tickt wieder")
	game.set("order_left", 8.0)
	game.call("_tick_urgency")
	assert_eq(int(game.get("_last_tick_sec")), -1, "über 5 s Restzeit: keine Dringlichkeit")
	game.free()


func test_burger_gaeste_schunkeln_und_feiern() -> void:
	var game := _mount(BURGER_SCENE, "burgerBuild")
	var stage: Node3D = game.get("_stage")
	var guests: Array = stage.get("_guests")
	assert_eq(guests.size(), 3, "drei Gast-Goobys im Diner (M2)")
	stage.set("_reduced", false)
	var before := (guests[0] as Node3D).position
	stage.call("tick", 0.35)
	assert_true(
		before.distance_to((guests[0] as Node3D).position) > 0.001, "Gäste schunkeln (Deko)"
	)
	stage.call("guests_cheer", false)
	assert_true(float(stage.get("_guest_cheer")) > 0.0, "fertiger Burger: Jubel-Schub")
	# Q2/Reduced Motion: Schunkeln friert ein, der Jubel-Schub bleibt aus.
	stage.set("_guest_cheer", 0.0)
	stage.set("_reduced", true)
	stage.call("tick", 0.35)
	var bases: Array = stage.get("_guest_bases")
	assert_eq((guests[0] as Node3D).position, bases[0], "RM: Gäste stehen still")
	stage.call("guests_cheer", true)
	assert_almost(float(stage.get("_guest_cheer")), 0.0, 1e-6, "RM: kein Schunkel-Schub")
	game.free()


func test_burger_rm_gatet_treffer_poof() -> void:
	var previous: Variant = _set_reduced_motion(true)
	if previous == null:
		fail_test("AppSettings-Autoload fehlt")
		return
	var game := _mount(BURGER_SCENE, "burgerBuild")
	game.set("_intro_left", 0.0)
	var stage: Node3D = game.get("_stage")
	var pop: GPUParticles3D = stage.get("_pop")
	var ticket: Array = game.get("ticket")
	game.call("_catch_item", {"id": str(ticket[0]), "x": 0.0, "y": 0.0, "col": 1})
	assert_false(pop.emitting, "RM: Treffer-Poof bleibt aus (Q2)")
	game.free()
	_set_reduced_motion(false)
	var game2 := _mount(BURGER_SCENE, "burgerBuild")
	game2.set("_intro_left", 0.0)
	var pop2: GPUParticles3D = (game2.get("_stage") as Node3D).get("_pop")
	var ticket2: Array = game2.get("ticket")
	game2.call("_catch_item", {"id": str(ticket2[0]), "x": 0.0, "y": 0.0, "col": 1})
	assert_true(pop2.emitting, "Gegenprobe ohne RM: der Poof zündet")
	game2.free()
	_set_reduced_motion(bool(previous))


# ── deliveryRush ───────────────────────────────────────────────────────────


func test_delivery_intro_gatet_sim_und_eingabe() -> void:
	var game := _mount(DELIVERY_SCENE, "deliveryRush")
	assert_almost(float(game.get("_intro_left")), 1.5, 1e-6, "Intro startet voll")
	assert_eq(str(game.get("_banner")), I18nService.t("mg.deliveryRush.intro"), "Ziel-Banner steht")
	var start_pos: Vector2 = game.get("van_pos")
	for _i in 3:
		game._process(0.4)
	assert_true(float(game.get("_intro_left")) > 0.0, "Beat läuft noch (1,2 s)")
	assert_almost(float(game.get("elapsed")), 0.0, 0.0, "Sim-Uhr wartet im Intro")
	assert_eq(game.get("van_pos"), start_pos, "der Wagen steht im Intro")
	# Rechte Bildhälfte (relativ zur echten view_size) ⇒ Lenkung nach rechts.
	var view: Vector2 = game.get("view_size")
	var touch := InputEventScreenTouch.new()
	touch.position = Vector2(view.x * 0.95, view.y * 0.6)
	touch.pressed = true
	game._unhandled_input(touch)
	assert_almost(float(game.get("steer")), 0.0, 1e-6, "Touch lenkt im Intro nicht")
	game._process(0.4)
	game._process(0.05)
	assert_true(float(game.get("elapsed")) > 0.0, "danach tickt die Sim normal")
	game._unhandled_input(touch)
	assert_true(float(game.get("steer")) > 0.0, "nach dem Beat greift die Lenkung")
	game.free()


func test_delivery_intro_lauf_bleibt_zahlengleich() -> void:
	var with_intro := _mount(DELIVERY_SCENE, "deliveryRush", 5)
	var reference := _mount(DELIVERY_SCENE, "deliveryRush", 5)
	reference.set("_intro_left", 0.0)
	assert_eq(with_intro.get("_targets"), reference.get("_targets"), "Ziel-Liste zahlengleich")
	for _i in 4:
		with_intro._process(0.4)
	for _i in 12:
		with_intro._process(0.05)
		reference._process(0.05)
	assert_eq(with_intro.get("van_pos"), reference.get("van_pos"), "Fahrweg bit-gleich")
	assert_almost(
		float(with_intro.get("elapsed")), float(reference.get("elapsed")), 0.0, "Uhr bit-gleich"
	)
	with_intro.free()
	reference.free()


func test_delivery_intro_stadt_totale_dann_verfolgerpose() -> void:
	var game := _mount(DELIVERY_SCENE, "deliveryRush")
	var cam: Camera3D = (game.get("_stage") as Node3D).get("camera")
	assert_true(cam.position.y > 15.0, "Totale: Kamera startet hoch über der Stadt")
	for _i in 4:
		game._process(0.5)
	assert_true(cam.position.y < 10.0, "nach dem Beat: Verfolger-Pose erreicht")
	game.free()


func test_delivery_rm_ueberspringt_introflug() -> void:
	var previous: Variant = _set_reduced_motion(true)
	if previous == null:
		fail_test("AppSettings-Autoload fehlt")
		return
	var game := _mount(DELIVERY_SCENE, "deliveryRush")
	var cam: Camera3D = (game.get("_stage") as Node3D).get("camera")
	assert_true(cam.position.y < 10.0, "RM: kein Kamera-Flug, direkt die Spielpose")
	game.free()
	_set_reduced_motion(bool(previous))


func test_delivery_motor_loop_gate_pitch_und_pause() -> void:
	var game := _mount(DELIVERY_SCENE, "deliveryRush")
	var feel: Node = game.get("_feel")
	var motor: AudioStreamPlayer = feel.get("_motor")
	if motor == null:
		fail_test("Motor-Loop fehlt (ranch_ambience_wind nicht auflösbar?)")
		game.free()
		return
	assert_false(motor.playing, "play()-Gate: der Loop startet NICHT beim Mount/Intro")
	game.set("_intro_left", 0.0)
	game._process(0.1)
	assert_true(motor.playing, "die erste Fahrt weckt den Loop (play bei Bedarf)")
	assert_false(motor.stream_paused, "beim Fahren läuft der Loop")
	var pitch_first := motor.pitch_scale
	game._process(0.1)
	game._process(0.1)
	assert_true(motor.pitch_scale > pitch_first, "Pitch folgt dem Tempo (M10)")
	# Pause: driving wird VOR dem Aktiv-Guard falsch → der Loop pausiert sauber.
	game.pause()
	for _i in 8:
		game._process(0.1)
	assert_true(motor.stream_paused, "Pause: der Loop stoppt sauber")
	game.resume()
	game._process(0.1)
	assert_false(motor.stream_paused, "Weiterfahrt weckt den Loop wieder")
	game.free()


func test_delivery_rm_stoppt_motor_loop() -> void:
	var previous: Variant = _set_reduced_motion(true)
	if previous == null:
		fail_test("AppSettings-Autoload fehlt")
		return
	var game := _mount(DELIVERY_SCENE, "deliveryRush")
	game.set("_intro_left", 0.0)
	var motor: AudioStreamPlayer = (game.get("_feel") as Node).get("_motor")
	for _i in 4:
		game._process(0.1)
	assert_false(motor.playing, "RM: der Motor-Loop startet gar nicht erst")
	game.free()
	_set_reduced_motion(bool(previous))


func test_delivery_bump_drossel_und_karosserie_ruck() -> void:
	var game := _mount(DELIVERY_SCENE, "deliveryRush")
	var feel: Node = game.get("_feel")
	feel.call("bump", game, true, null, Vector3.ZERO)
	assert_almost(float(feel.get("body_kick")), 1.0, 1e-6, "Bump ruckt die Karosserie")
	feel.set("body_kick", 0.0)
	feel.call("bump", game, true, null, Vector3.ZERO)
	assert_almost(
		float(feel.get("body_kick")), 0.0, 1e-6, "innerhalb des Cooldowns kein zweiter Bump"
	)
	feel.call("tick", 0.5)
	feel.call("bump", game, true, null, Vector3.ZERO)
	assert_almost(float(feel.get("body_kick")), 1.0, 1e-6, "nach dem Cooldown greift er wieder")
	feel.call("tick", 0.3)
	assert_true(float(feel.get("body_kick")) < 1.0, "der Ruck klingt über tick() ab")
	game.free()


func test_delivery_routenband_schlanker_und_transparenter() -> void:
	# PURE Verschlankung: volle Breite auf freier Strecke, 55 % am Ring.
	assert_almost(Feel.route_slim(60.0), 1.0, 1e-6, "freie Strecke: volle Breite")
	assert_almost(Feel.route_slim(22.0), 1.0, 1e-6, "ab 22 m beginnt die Verjüngung")
	assert_almost(Feel.route_slim(11.0), 0.55, 1e-6, "Hausnähe: 55 % (Deckel)")
	assert_almost(Feel.route_slim(0.0), 0.55, 1e-6, "nie unter 55 % (lesbar bleiben)")
	# Und das Band selbst ist milder gedeckt (0,44 statt 0,55 — Audit-Beleg).
	var game := _mount(DELIVERY_SCENE, "deliveryRush")
	var prop: Node3D = game.get("_route_prop")
	var layers: Array = prop.get("_layers")
	var mesh := (layers[0] as MultiMeshInstance3D).multimesh.mesh as BoxMesh
	var mat := mesh.material as StandardMaterial3D
	assert_almost(mat.albedo_color.a, 0.44, 1e-3, "Band-Deckkraft 0,44")
	game.free()


func test_delivery_drop_burst_rm_gate() -> void:
	# Q2: der Gold-Pop am Ring ist an der eigenen Call-Site gegated.
	var previous: Variant = _set_reduced_motion(true)
	if previous == null:
		fail_test("AppSettings-Autoload fehlt")
		return
	var game := _mount(DELIVERY_SCENE, "deliveryRush")
	game.set("_intro_left", 0.0)
	var pop: GPUParticles3D = game.get("_pop")
	var drop: Vector2 = game.call("current_drop")
	game.set("van_pos", drop)
	game.call("_check_drop", drop + Vector2(6.0, 0.0))
	assert_true(int(game.get("drops")) >= 1, "Zustellung ist passiert")
	assert_false(pop.emitting, "RM: Gold-Pop bleibt aus (Q2)")
	game.free()
	_set_reduced_motion(bool(previous))


# ── Strings ────────────────────────────────────────────────────────────────


func test_express1_strings_de_en_paritaet() -> void:
	var de := _flat_keys("res://strings/de/mg_express1.json")
	var en := _flat_keys("res://strings/en/mg_express1.json")
	assert_eq(de, en, "DE/EN-Schlüssel der Domain-Datei paritätisch")
	assert_true(de.has("mg.burgerBuild.intro"), "burgerBuild-Intro-Key vorhanden")
	assert_true(de.has("mg.deliveryRush.intro"), "deliveryRush-Intro-Key vorhanden")
	assert_ne(
		I18nService.t("mg.burgerBuild.intro"),
		"mg.burgerBuild.intro",
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
