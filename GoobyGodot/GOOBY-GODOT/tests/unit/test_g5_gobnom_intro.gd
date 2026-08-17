extends TestCase
## G5 P36 — Intro-Beat des GOB-NOM-Rundenstarts (P20-Restpunkt, mg-audit-b
## §2 P2): 1,5-s-Kamerafahrt Regal→Seil (establish, W14-Kanon), Sim UND
## Eingabe warten solange (Q4-Muster gvz/carrot_catch/hide_seek), Reduced
## Motion überspringt die Fahrt (sofort Spielpose, Gate-Dauer identisch),
## die _wall-Raycasts projizieren während der Fahrt aus der NEUTRALEN
## End-Pose (Welt-Anker statt Screen-Kleben, hide_seek-W16-Muster) und der
## Netz-Coop bleibt lockstep-sicher: Start-Fence geht sofort raus, der Pump
## wartet nur wandzeitlich — Tick-Zahlen/Hashes bleiben zahlengleich zur
## Referenz-Sim. Rejoin (Snapshot) ist Aufholjagd und bekommt KEINEN Beat.

const Stage := preload("res://scripts/minigames/games/gobnom/gobnom_stage3d.gd")
const GAME_SCENE := "res://scripts/minigames/games/gobnom/gobnom_game.tscn"
const TICK := 1.0 / 60.0


## GameState-Double (Muster test_gobnom_game): get_value/update reichen.
class GameStateDouble:
	extends RefCounted
	var state := {}

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var cursor: Variant = state
		for part in path.split("."):
			if cursor is Dictionary and (cursor as Dictionary).has(part):
				cursor = cursor[part]
			else:
				return fallback
		return cursor

	func update(mutator: Callable) -> void:
		mutator.call(state)

	func notify_slice_changed(_slice_id: String) -> void:
		pass


## Session-Double: fängt die Lockstep-Sendungen der View ab (kein _net —
## send_frame/send_hash zeichnen nur auf, statt ROOM_MSG zu verschicken).
class SessionDouble:
	extends GobnomNetSession
	var sent_frames: Array = []
	var sent_hashes: Array = []

	func send_frame(frame: Dictionary) -> void:
		if not frame.is_empty():
			sent_frames.append(frame.duplicate(true))

	func send_hash(tick: int, hash_text: String) -> void:
		sent_hashes.append({"t": tick, "h": hash_text})


func _make_game() -> MinigameBase:
	var ctx := MinigameCtx.new()
	ctx.game_id = "gobnom"
	ctx.difficulty = "normal"
	ctx.run_seed = 7
	var scene: PackedScene = load(GAME_SCENE)
	var game: MinigameBase = scene.instantiate()
	game.set("game_state_override", GameStateDouble.new())
	tree.root.add_child(game)
	game.setup(ctx)
	game.start()
	return game


## Netz-Coop-Aufbau: Session-Double einhängen und den Server-Start faken.
func _make_netz_game(seed_value: int) -> Array:
	var game := _make_game()
	var session := SessionDouble.new()
	session.my_side = GobnomLogic.PLAYER_A
	session.seed_value = seed_value
	session.input_delay = GobnomLockstep.INPUT_DELAY
	game.add_child(session)
	game.set("netz_session", session)
	return [game, session]


## Reduced Motion am UiTheme-Autoload schalten (Muster test_g3_arcade).
func _set_rm(enabled: bool) -> Variant:
	var svc := tree.root.get_node_or_null("/root/UiTheme")
	if svc == null:
		return null
	var vorher: bool = svc.reduced_motion
	svc.reduced_motion = enabled
	return vorher


func _touch(game: MinigameBase, at: Vector2) -> void:
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = at
	game._unhandled_input(touch)


func _cam(game: MinigameBase) -> Camera3D:
	var stage: Node3D = game.get("_stage")
	return (stage.get("stage") as Node3D).get("camera")


func test_intro_konstante_w14_kanon() -> void:
	var game_script: GDScript = load("res://scripts/minigames/games/gobnom/gobnom_game.gd")
	var consts := game_script.get_script_constant_map()
	assert_true(consts.has("INTRO_S"), "INTRO_S vorhanden")
	assert_almost(float(consts["INTRO_S"]), 1.5, 1e-6, "Intro-Beat = 1,5 s (W14-Kanon)")


func test_solo_intro_gatet_sim_und_eingabe_zahlengleich() -> void:
	var game := _make_game()
	game.call("open_level", "campaign", 1)
	assert_almost(float(game.get("_intro_left")), 1.5, 1e-6, "Beat startet voll")
	assert_eq(int((game.get("state") as Dictionary)["tick"]), 0, "Sim steht am Start")
	for _i in 5:
		game._process(0.25)
	assert_almost(float(game.get("_intro_left")), 0.25, 1e-6, "Beat läuft noch (1,25 s)")
	assert_eq(int((game.get("state") as Dictionary)["tick"]), 0, "Sim wartet im Beat")
	assert_almost(float(game.get("_accum")), 0.0, 1e-6, "keine Zeitschuld im Beat")
	# Eingabe gegated: der Touch legt im Beat keinen Zeiger an.
	_touch(game, game.get_viewport_rect().size * 0.5)
	assert_eq((game.get("_pointers") as Dictionary).size(), 0, "Touch prallt im Beat ab")
	game._process(0.25)
	assert_almost(float(game.get("_intro_left")), 0.0, 1e-6, "Beat nach 1,5 s vorbei")
	assert_eq(int((game.get("state") as Dictionary)["tick"]), 0, "Übergangs-Frame tickt nicht")
	game._process(0.25)
	assert_eq(int((game.get("state") as Dictionary)["tick"]), 15, "danach tickt die Sim (60 Hz)")
	# Zahlengleich: Referenz-Sim mit demselben Seed (7 + 1·1009 + 1·131).
	var level := GobnomData.level_by_id(GobnomData.load_campaign(), 1)
	var referenz := GobnomLogic.new_run(level, GobnomData.load_balance(null), 1147)
	for _i in 15:
		GobnomLogic.step(referenz)
	assert_eq(
		GobnomLogic.state_hash(game.get("state")),
		GobnomLogic.state_hash(referenz),
		"State-Hash nach dem Beat == Referenz ohne Beat (Sim unberührt)"
	)
	_touch(game, game.get_viewport_rect().size * 0.5)
	assert_eq((game.get("_pointers") as Dictionary).size(), 1, "nach dem Beat greift der Touch")
	game.free()


func test_intro_kamera_regal_establish_und_endpose() -> void:
	var vorher: Variant = _set_rm(false)
	var game := _make_game()
	game.call("open_level", "campaign", 1)
	var cam := _cam(game)
	# _enter_play stellt die Fahrt sofort auf k=0: Regal-Totale links.
	assert_true(cam.position.x < Stage.CAM_POS.x - 2.0, "Establish: Kamera links am Regal")
	assert_true(cam.position.z < Stage.CAM_POS.z - 4.0, "Establish: nah an der Küchenwand")
	assert_true(cam.rotation_degrees.y > 10.0, "Establish: Blick schwenkt zum Regal")
	game._process(0.25)
	var mitte := cam.position
	assert_true(mitte.x > Stage.CAM_POS.x - 2.6 - 0.001, "Fahrt läuft Richtung Spielpose")
	assert_true(mitte.distance_to(Stage.CAM_POS) > 0.5, "Mitte der Fahrt ≠ Endpose")
	game.set("_intro_left", 0.05)
	game._process(0.1)
	assert_almost(cam.position.x, Stage.CAM_POS.x, 1e-4, "Endpose: exakt frame()-x")
	assert_almost(cam.position.z, Stage.CAM_POS.z, 1e-4, "Endpose: exakt frame()-z")
	assert_almost(cam.rotation_degrees.y, 0.0, 1e-4, "Endpose: frontal, kein Ruck")
	# Nach dem Beat bleibt die Spielpose stehen (kein Neutral-Swap mehr).
	game._process(0.1)
	assert_almost(cam.position.x, Stage.CAM_POS.x, 1e-4, "Spielpose stabil")
	game.free()
	if vorher != null:
		_set_rm(bool(vorher))


func test_reduced_motion_ueberspringt_fahrt_nicht_das_gate() -> void:
	var vorher: Variant = _set_rm(true)
	if vorher == null:
		fail_test("UiTheme-Autoload fehlt")
		return
	var game := _make_game()
	game.call("open_level", "campaign", 1)
	var cam := _cam(game)
	assert_almost(cam.position.x, Stage.CAM_POS.x, 1e-4, "RM: sofort Spielpose (keine Fahrt)")
	assert_almost(cam.rotation_degrees.y, 0.0, 1e-4, "RM: kein Schwenk")
	game._process(0.25)
	assert_almost(cam.position.x, Stage.CAM_POS.x, 1e-4, "RM: Kamera bleibt stehen")
	# Das Sim-Gate bleibt (Dauer identisch mit/ohne RM — wichtig fürs Netz).
	assert_almost(float(game.get("_intro_left")), 1.25, 1e-6, "RM: Gate-Uhr läuft normal")
	assert_eq(int((game.get("state") as Dictionary)["tick"]), 0, "RM: Sim wartet trotzdem")
	game.free()
	_set_rm(bool(vorher))


func test_intro_raycast_anker_bleiben_welt_stabil() -> void:
	var vorher: Variant = _set_rm(false)
	var game := _make_game()
	game.call("open_level", "campaign", 1)
	var stage: Node3D = game.get("_stage")
	var candy: Node3D = stage.get("_candy")
	var cam := _cam(game)
	game._process(TICK)
	var candy_frueh := candy.position
	var cam_frueh := cam.position
	for _i in 3:
		game._process(0.25)
	# Kamera ist klar weitergefahren — das Bonbon klebt trotzdem an der Welt
	# (Raycast aus der End-Pose), nicht an den Screen-Pixeln der Fahrt.
	assert_true(cam.position.distance_to(cam_frueh) > 0.5, "Kamera fährt wirklich")
	assert_true(candy.position.distance_to(candy_frueh) < 0.001, "Bonbon bleibt welt-verankert")
	game.free()
	if vorher != null:
		_set_rm(bool(vorher))


func test_retry_startet_neuen_beat() -> void:
	var game := _make_game()
	game.call("open_level", "campaign", 1)
	game.set("_intro_left", 0.0)
	game._process(0.25)
	assert_true(int((game.get("state") as Dictionary)["tick"]) > 0, "Erstlauf tickt")
	game.call("open_level", "campaign", 1)
	assert_almost(float(game.get("_intro_left")), 1.5, 1e-6, "Retry bekommt frischen Beat")
	assert_eq(int((game.get("state") as Dictionary)["tick"]), 0, "frische Sim wartet wieder")
	game.free()


func test_netz_start_intro_gated_pump_fence_sofort_zahlengleich() -> void:
	var seed_vom_server := 424_242
	var paar := _make_netz_game(seed_vom_server)
	var game: MinigameBase = paar[0]
	var session: SessionDouble = paar[1]
	game.call("_on_netz_start", {"level": 1})
	assert_true(bool(game.get("_netz_active")), "Netz-Lauf aktiv")
	assert_almost(float(game.get("_intro_left")), 1.5, 1e-6, "Netz-Start bekommt den Beat")
	# Der Start-Fence ging TROTZ Beat sofort raus — der Partner darf seine
	# ersten Ticks rechnen, niemand hungert am Fence aus.
	assert_eq(session.sent_frames.size(), 1, "Start-Fence sofort verschickt")
	assert_true(int((session.sent_frames[0] as Dictionary)["upTo"]) >= 0, "Fence deckt Ticks")
	var netz: GobnomLockstep = game.get("_netz")
	for _i in 6:
		game._process(0.25)
	assert_almost(float(game.get("_intro_left")), 0.0, 1e-6, "Beat vorbei")
	assert_eq(int(netz.state["tick"]), 0, "kein Tick im Beat gepumpt")
	assert_eq(int(netz.get("_clock")), 0, "auch die Fence-Uhr wartete (rein wandzeitlich)")
	assert_false(bool(game.get("_netz_waiting")), "kein Warte-Hinweis im Beat")
	# Partner-Fence rein (Muster test_w15) und 90 Wand-Ticks pumpen.
	netz.receive_frame({"n": 1, "upTo": 100_000, "a": []})
	for _i in 90:
		game._process(TICK)
	assert_eq(int(netz.state["tick"]), 90, "nach dem Beat pumpt der Lockstep normal")
	assert_false(netz.desynced, "kein Desync durch den Beat")
	# Zahlengleich zur Referenz-Sim OHNE Beat: gleicher Seed, gleiche Fences.
	var level := GobnomData.level_by_id(GobnomData.load_coop(), 1)
	var referenz := GobnomLockstep.new()
	referenz.start(level, GobnomData.load_balance(null), seed_vom_server, GobnomLogic.PLAYER_A)
	referenz.take_frame(true)
	referenz.receive_frame({"n": 1, "upTo": 100_000, "a": []})
	for _i in 90:
		referenz.advance()
	assert_eq(int(referenz.state["tick"]), 90, "Referenz läuft gleich weit")
	assert_eq(
		GobnomLogic.state_hash(netz.state),
		GobnomLogic.state_hash(referenz.state),
		"State-Hash mit Beat == Referenz ohne Beat (Lockstep zahlengleich)"
	)
	# Der eigene Hash-Report bei Tick 60 ging normal raus.
	var hash_ticks: Array = []
	for entry: Dictionary in session.sent_hashes:
		hash_ticks.append(int(entry["t"]))
	assert_true(hash_ticks.has(60), "Hash-Report bei Tick 60 verschickt")
	game.free()


func test_netz_rejoin_snapshot_ohne_beat() -> void:
	var paar := _make_netz_game(77)
	var game: MinigameBase = paar[0]
	var fence := {"n": 1, "upTo": 50, "a": []}
	(
		game
		. call(
			"_on_netz_snapshot",
			{
				"phase": "run",
				"level": 1,
				"seed": 77,
				"frames": {"a": [fence.duplicate(true)], "b": [fence.duplicate(true)]},
				"inputDelay": GobnomLockstep.INPUT_DELAY,
			}
		)
	)
	assert_true(bool(game.get("_netz_active")), "Rejoin-Lauf aktiv")
	assert_almost(float(game.get("_intro_left")), 0.0, 1e-6, "Rejoin: KEIN Beat (Aufholjagd)")
	var netz: GobnomLockstep = game.get("_netz")
	assert_true(int(netz.state["tick"]) > 0, "Replay hat vorgespult")
	var cam := _cam(game)
	assert_almost(cam.position.x, Stage.CAM_POS.x, 1e-4, "Rejoin: sofort Spielpose")
	# Der Pump läuft sofort wieder (kein Gate): am ausgereizten Fence meldet
	# er ehrlich „warte auf Partner" — der Beat blockiert ihn nicht.
	game._process(TICK)
	assert_true(bool(game.get("_netz_waiting")), "Pump lief sofort (wartet nur am Fence)")
	game.free()
