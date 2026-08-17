extends TestCase
## G5 P35 MG-EXPRESS-2 — Präsentations-Verträge der Restpunkte-Politur von
## shoppingSurf + toyRacer (Audit C §4/§7, Querschnitte Q2–Q5):
## Intro-Beats 1,5 s gaten Sim UND Eingabe bei zahlengleichem Lauf (M1,
## Crosscheck-Vertrag), Straßen-/Kurs-Totale mit Rückkehr in die Spielpose,
## Banner auf Creme-Plate (M7), Leben-Pips + Powerup-Chips (Surf),
## Q2-RM-Gates an den eigenen Fx.burst-Call-Sites, Motor-Loop (Racer,
## rocket-Muster), Item-Chip statt Item-Textzeile, deterministisches
## Boden-Konfetti fürs Hochkant-Nahfeld und die DE/EN-Parität von
## mg_express2. Die MECHANIK (shopping_surf_run/toy_racer_logic) wird NICHT
## berührt — Crosscheck: test_shopping_surf_matches_web /
## test_toy_racer_matches_web.

const Surf := preload("res://scripts/minigames/games/shopping_surf/shopping_surf.gd")
const SurfWorld := preload("res://scripts/minigames/games/shopping_surf/shopping_surf_world.gd")
const Racer := preload("res://scripts/minigames/games/toy_racer/toy_racer.gd")
const RacerLogic := preload("res://scripts/minigames/games/toy_racer/toy_racer_logic.gd")
const RacerFeel := preload("res://scripts/minigames/games/toy_racer/toy_racer_feel.gd")
const SURF_SCENE := "res://scripts/minigames/games/shopping_surf/shopping_surf.tscn"
const RACER_SCENE := "res://scripts/minigames/games/toy_racer/toy_racer.tscn"


## Fenster VOR der Instanziierung pinnen (Geometrie-Tests, W17-Konvention).
func _pin_window(size: Vector2i) -> void:
	tree.root.size = size
	tree.root.size_changed.emit()
	await wait_frames(2)


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
	for script: GDScript in [Surf, Racer]:
		var consts := script.get_script_constant_map()
		assert_true(consts.has("INTRO_S"), "INTRO_S vorhanden")
		assert_almost(float(consts["INTRO_S"]), 1.5, 1e-6, "Intro-Beat = 1,5 s (W14-Kanon)")


# ── shoppingSurf ───────────────────────────────────────────────────────────


func test_surf_intro_gatet_sim_und_eingabe() -> void:
	var game := _mount(SURF_SCENE, "shoppingSurf")
	assert_almost(float(game.get("_intro_left")), 1.5, 1e-6, "Intro startet voll")
	assert_eq(str(game.get("_banner")), I18nService.t("mg.shoppingSurf.intro"), "Ziel-Banner steht")
	assert_true(float(game.get("_banner_t")) > 1.5, "Banner überdauert den ganzen Beat")
	# _process kappt dt auf 0,1 s (Spiral-of-death-Schutz) — also 0,1er-Ticks.
	for _i in 12:
		game._process(0.1)
	assert_true(float(game.get("_intro_left")) > 0.0, "Beat läuft noch (1,2 s)")
	assert_almost(
		float((game.get("run") as Dictionary)["elapsed"]), 0.0, 0.0, "Sim-Uhr wartet im Intro"
	)
	# Eingabe ist gegatet: die Pfeiltaste erzeugt noch keine Eingabe-Flanke.
	var key := InputEventKey.new()
	key.keycode = KEY_LEFT
	key.pressed = true
	game._unhandled_input(key)
	assert_true((game.get("_held") as Dictionary).is_empty(), "Taste greift im Intro nicht")
	for _i in 3:
		game._process(0.1)
	assert_almost(float(game.get("_intro_left")), 0.0, 1e-6, "Beat nach 1,5 s vorbei")
	assert_almost(
		float((game.get("run") as Dictionary)["elapsed"]), 0.0, 0.0, "Übergangs-Frame zählt nicht"
	)
	game._process(0.05)
	assert_true(
		float((game.get("run") as Dictionary)["elapsed"]) > 0.0, "danach tickt die Sim normal"
	)
	game._unhandled_input(key)
	assert_true(bool((game.get("_held") as Dictionary).get("left", false)), "Taste greift wieder")
	game.free()


func test_surf_intro_lauf_bleibt_zahlengleich() -> void:
	# Referenz: gleiches Seed OHNE Intro (direkt auf 0 gesetzt) — nach
	# identischen Sim-Frames müssen Strecke/Hindernisse bit-gleich stehen.
	var with_intro := _mount(SURF_SCENE, "shoppingSurf", 5)
	var reference := _mount(SURF_SCENE, "shoppingSurf", 5)
	reference.set("_intro_left", 0.0)
	for _i in 15:
		with_intro._process(0.1)
	assert_almost(float(with_intro.get("_intro_left")), 0.0, 1e-6, "Intro vorbei")
	for _i in 12:
		with_intro._process(0.05)
		reference._process(0.05)
	assert_almost(
		float((with_intro.get("run") as Dictionary)["distanceM"]),
		float((reference.get("run") as Dictionary)["distanceM"]),
		0.0,
		"Strecke bit-gleich"
	)
	assert_eq(
		(with_intro.get("run") as Dictionary)["obstacles"],
		(reference.get("run") as Dictionary)["obstacles"],
		"Hindernis-Strom bit-gleich"
	)
	with_intro.free()
	reference.free()


func test_surf_intro_kamera_totale_dann_spielpose() -> void:
	await _pin_window(Vector2i(720, 1280))
	var game := _mount(SURF_SCENE, "shoppingSurf")
	var cam: Camera3D = (game.get("_stage") as Node3D).get("camera")
	# Hochkant-Spielpose wäre z = CAM_BACK + CAM_PORTRAIT_BACK = 5,7 m —
	# die Totale hängt um INTRO_CAM_BACK weiter hinten und höher.
	assert_true(cam.position.z > 8.0, "Totale: Kamera startet zurückgezogen")
	assert_true(cam.position.y > 3.5, "Totale: Kamera startet erhöht")
	# Der letzte Intro-Tick (1,5 s um) setzt die Kamera direkt auf die
	# Spielpose — noch VOR dem ersten Sim-Tick (kein Kamera-Sprung im Spiel).
	for _i in 15:
		game._process(0.1)
	assert_almost(cam.position.z, 5.7, 0.01, "Spielpose: Verfolgerabstand erreicht")
	game.free()


func test_surf_rm_ueberspringt_introflug_und_gatet_bursts() -> void:
	var previous: Variant = _set_reduced_motion(true)
	if previous == null:
		fail_test("AppSettings-Autoload fehlt")
		return
	await _pin_window(Vector2i(720, 1280))
	var game := _mount(SURF_SCENE, "shoppingSurf")
	var cam: Camera3D = (game.get("_stage") as Node3D).get("camera")
	assert_true(cam.position.z < 6.0, "RM: kein Kamera-Flug, direkt die Spielpose")
	assert_true(float(game.get("_intro_left")) > 0.0, "RM: Banner-Lesezeit bleibt trotzdem")
	# Q2: die eigenen Fx.burst-Call-Sites sind gegatet.
	game.call("_on_crash", 1)
	assert_false((game.get("_dust") as GPUParticles3D).emitting, "RM: Crash-Staub bleibt aus")
	game.call("_on_shield_pop")
	assert_false((game.get("_sparkle") as GPUParticles3D).emitting, "RM: Schild-Funken bleiben aus")
	game.free()
	_set_reduced_motion(false)
	var game2 := _mount(SURF_SCENE, "shoppingSurf")
	game2.call("_on_crash", 1)
	assert_true((game2.get("_dust") as GPUParticles3D).emitting, "Gegenprobe ohne RM: Staub zündet")
	game2.free()
	_set_reduced_motion(bool(previous))


func test_surf_leben_pips_pulsen_und_klingen_ab() -> void:
	var game := _mount(SURF_SCENE, "shoppingSurf")
	assert_almost(float(game.get("_pip_pulse")), 0.0, 1e-6, "Start: kein Puls")
	game.call("_on_crash", 1)
	assert_almost(float(game.get("_pip_pulse")), 1.0, 1e-6, "Crash pulst den frischen Pip")
	game.set("_intro_left", 0.0)
	game._process(0.1)
	var decayed := float(game.get("_pip_pulse"))
	assert_true(decayed < 1.0 and decayed > 0.0, "der Puls klingt über _process ab")
	assert_true(game.get("_banner_plate") is StyleBoxFlat, "Banner-Plate vorhanden (M7)")
	assert_true(game.get("_chip_plate") is StyleBoxFlat, "Powerup-Chip-Plate vorhanden")
	game.free()


func test_surf_hint_fade_haengt_an_der_simzeit() -> void:
	var game := _mount(SURF_SCENE, "shoppingSurf")
	var hint: Label = game.get("_hint_label")
	game.call("_fade_hint")
	assert_almost(hint.modulate.a, 1.0, 1e-6, "Start: Hinweis voll lesbar (Intro zählt nicht)")
	(game.get("run") as Dictionary)["elapsed"] = 7.0
	game.call("_fade_hint")
	assert_almost(hint.modulate.a, 0.0, 1e-6, "nach 5 s Sim + Fade: ausgeblendet (M6)")
	game.free()


func test_surf_boden_konfetti_deterministisch_im_nahfeld() -> void:
	# Audit C §4: Farbtupfer füllen das Hochkant-Nahfeld — deterministisch
	# (goldener Schnitt, kein RNG): zwei Builds liefern identische Streuung.
	var world_a: Node3D = SurfWorld.new()
	var world_b: Node3D = SurfWorld.new()
	world_a.call("build", 0.88)
	world_b.call("build", 0.88)
	var confetti_a := _confetti_items(world_a)
	var confetti_b := _confetti_items(world_b)
	assert_eq(confetti_a.size(), 30, "30 Farbtupfer auf dem Band")
	assert_eq(confetti_a, confetti_b, "Streuung bit-gleich (kein Zufallsstrom)")
	var tints: Array = SurfWorld.CANOPY_TINTS
	for item: Dictionary in confetti_a:
		assert_almost(float(item["y"]), 0.032, 1e-6, "Tupfer liegen auf dem Pflaster")
		assert_true(absf(float(item["x"])) < 4.6, "Tupfer bleiben in Straße/Gehweg")
		var z := float(item["z"])
		assert_true(z <= 8.0 and z > -121.01, "Tupfer im Band-Bereich")
		assert_true(tints.has(item["color"]), "Pastellton aus der Markisen-Palette")
	world_a.free()
	world_b.free()


func _confetti_items(world: Node3D) -> Array:
	var groups: Array = (world.get("band") as RefCounted).get("_groups")
	for group: Dictionary in groups:
		var items: Array = group["items"]
		if items.size() == 30 and (items[0] as Dictionary).has("color"):
			return items
	return []


# ── toyRacer ───────────────────────────────────────────────────────────────


func test_racer_intro_gatet_sim_und_eingabe() -> void:
	var game := _mount(RACER_SCENE, "toyRacer")
	assert_almost(float(game.get("_intro_left")), 1.5, 1e-6, "Intro startet voll")
	assert_eq(str(game.get("_banner")), I18nService.t("mg.toyRacer.intro"), "Ziel-Banner steht")
	# Die Grid-Position ist seed-abhängig (prozeduraler Kurs) — Stillstand
	# wird deshalb RELATIV zur Startposition geprüft, nicht gegen 0.
	var kart: Dictionary = (game.get("race") as Dictionary)["karts"][0]
	var start_s := float(kart["s"])
	# _process kappt dt auf 0,1 s (Spiral-of-death-Schutz) — also 0,1er-Ticks.
	for _i in 12:
		game._process(0.1)
	assert_true(float(game.get("_intro_left")) > 0.0, "Beat läuft noch (1,2 s)")
	assert_almost(float(kart["s"]), start_s, 0.0, "Sim wartet: das Kart steht am Start")
	assert_almost(float(game.get("_elapsed")), 0.0, 0.0, "View-Uhr wartet mit (Hint-Lesezeit)")
	# Eingabe ist gegatet: der Touch lädt noch keinen Drift.
	var touch := InputEventScreenTouch.new()
	touch.position = Vector2(100.0, 100.0)
	touch.pressed = true
	game._unhandled_input(touch)
	assert_false(bool(game.get("_drift_held")), "Touch greift im Intro nicht")
	for _i in 3:
		game._process(0.1)
	for _i in 8:
		game._process(0.05)
	kart = (game.get("race") as Dictionary)["karts"][0]
	assert_true(float(kart["s"]) > start_s, "nach dem Beat rollt das Feld")
	game._unhandled_input(touch)
	assert_true(bool(game.get("_drift_held")), "nach dem Beat greift der Drift-Touch")
	game.free()


func test_racer_intro_lauf_bleibt_zahlengleich() -> void:
	var with_intro := _mount(RACER_SCENE, "toyRacer", 5)
	var reference := _mount(RACER_SCENE, "toyRacer", 5)
	reference.set("_intro_left", 0.0)
	for _i in 15:
		with_intro._process(0.1)
	assert_almost(float(with_intro.get("_intro_left")), 0.0, 1e-6, "Intro vorbei")
	for _i in 12:
		with_intro._process(0.05)
		reference._process(0.05)
	var kart_a: Dictionary = (with_intro.get("race") as Dictionary)["karts"][0]
	var kart_b: Dictionary = (reference.get("race") as Dictionary)["karts"][0]
	assert_almost(float(kart_a["s"]), float(kart_b["s"]), 0.0, "Fahrweg bit-gleich")
	assert_almost(float(kart_a["speed"]), float(kart_b["speed"]), 0.0, "Tempo bit-gleich")
	assert_eq(
		(with_intro.get("race") as Dictionary)["overtakes"],
		(reference.get("race") as Dictionary)["overtakes"],
		"Überholer bit-gleich"
	)
	with_intro.free()
	reference.free()


func test_racer_intro_kurs_totale_dann_verfolgerpose() -> void:
	await _pin_window(Vector2i(1280, 720))
	var game := _mount(RACER_SCENE, "toyRacer")
	var cam: Camera3D = (game.get("_stage") as Node3D).get("camera")
	assert_true(cam.position.y > 8.0, "Totale: Kamera startet hoch überm Kurs")
	# Intro verbrennen (15 × 0,1 s), dann konvergiert die geglättete
	# Verfolgerkamera (lerp dt×4) in ~1 s auf die Spielpose.
	for _i in 27:
		game._process(0.1)
	assert_true(cam.position.y < 5.0, "nach dem Beat: Verfolger-Pose erreicht")
	game.free()


func test_racer_rm_ueberspringt_introflug() -> void:
	var previous: Variant = _set_reduced_motion(true)
	if previous == null:
		fail_test("AppSettings-Autoload fehlt")
		return
	await _pin_window(Vector2i(1280, 720))
	var game := _mount(RACER_SCENE, "toyRacer")
	var cam: Camera3D = (game.get("_stage") as Node3D).get("camera")
	assert_true(cam.position.y < 5.0, "RM: kein Kamera-Flug, direkt die Spielpose")
	game.free()
	_set_reduced_motion(bool(previous))


func test_racer_motor_loop_gate_pitch_und_pause() -> void:
	var game := _mount(RACER_SCENE, "toyRacer")
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
	game._process(0.1)
	assert_true(motor.stream_paused, "Pause: der Loop stoppt sauber")
	game.resume()
	game._process(0.1)
	assert_false(motor.stream_paused, "Weiterfahrt weckt den Loop wieder")
	# Zieleinlauf-Fenster (_ending): das Motor-Ohr schweigt für den Moment.
	game.set("_ending", true)
	game._process(0.1)
	assert_true(motor.stream_paused, "Zieleinlauf: der Loop pausiert")
	game.free()


func test_racer_rm_stoppt_motor_loop() -> void:
	var previous: Variant = _set_reduced_motion(true)
	if previous == null:
		fail_test("AppSettings-Autoload fehlt")
		return
	var game := _mount(RACER_SCENE, "toyRacer")
	game.set("_intro_left", 0.0)
	var motor: AudioStreamPlayer = (game.get("_feel") as Node).get("_motor")
	for _i in 4:
		game._process(0.1)
	assert_false(motor.playing, "RM: der Motor-Loop startet gar nicht erst")
	game.free()
	_set_reduced_motion(bool(previous))


func test_racer_q2_burst_gates() -> void:
	var previous: Variant = _set_reduced_motion(true)
	if previous == null:
		fail_test("AppSettings-Autoload fehlt")
		return
	var game := _mount(RACER_SCENE, "toyRacer")
	game.set("_intro_left", 0.0)
	game.call("_handle_event", {"type": "boost", "kart": 0})
	assert_false(
		(game.get("_sparks") as GPUParticles3D).emitting, "RM: Boost-Funken bleiben aus (Q2)"
	)
	game.call("_handle_event", {"type": "finish", "kart": 0, "rank": 2})
	assert_false(
		(game.get("_confetti") as GPUParticles3D).emitting, "RM: Ziel-Konfetti bleibt aus (Q2)"
	)
	game.free()
	_set_reduced_motion(false)
	var game2 := _mount(RACER_SCENE, "toyRacer")
	game2.set("_intro_left", 0.0)
	game2.call("_handle_event", {"type": "boost", "kart": 0})
	assert_true(
		(game2.get("_sparks") as GPUParticles3D).emitting, "Gegenprobe ohne RM: Funken zünden"
	)
	game2.free()
	_set_reduced_motion(bool(previous))


func test_racer_item_chip_und_platz_zeile() -> void:
	var game := _mount(RACER_SCENE, "toyRacer")
	game.call("_update_labels")
	var rank := RacerLogic.player_rank(game.get("race") as Dictionary)
	assert_eq(
		(game.get("_pos_label") as Label).text,
		I18nService.t("mg.toyRacer.pos_pill", {"p": rank}),
		"Platz-Zeile nutzt den neuen pos_pill-Key (Item wandert in den Chip)"
	)
	# Der Chip kennt jede Item-Art der Logik (nur lesend geprüft).
	var tints: Dictionary = RacerFeel.ITEM_TINTS
	for kind: String in (game.get("tune") as Dictionary)["ITEM_KINDS"]:
		assert_true(tints.has(kind), "Chip-Farbe für Item-Art %s" % kind)
	game.free()


# ── Strings ────────────────────────────────────────────────────────────────


func test_express2_strings_de_en_paritaet() -> void:
	var de := _flat_keys("res://strings/de/mg_express2.json")
	var en := _flat_keys("res://strings/en/mg_express2.json")
	assert_eq(de, en, "DE/EN-Schlüssel der Domain-Datei paritätisch")
	assert_true(de.has("mg.shoppingSurf.intro"), "shoppingSurf-Intro-Key vorhanden")
	assert_true(de.has("mg.toyRacer.intro"), "toyRacer-Intro-Key vorhanden")
	assert_true(de.has("mg.toyRacer.pos_pill"), "toyRacer-Platz-Key vorhanden")
	assert_ne(
		I18nService.t("mg.shoppingSurf.intro"),
		"mg.shoppingSurf.intro",
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
