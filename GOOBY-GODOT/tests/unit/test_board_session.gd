extends TestCase
## BoardSession gegen NetClient+FakeWsLink (W3c VISIT): BOARD_START (Push +
## Antwort-Pfad), kompletter Schuss-Wechsel (SHOT → SHOT_RESULT, Turn-
## Spiegel), Sieg/Niederlage, Tomaten-Limit inkl. Server-Ablehnung (ERROR
## mit re), Emote-Relay, Forfeit und BOARD_RESUME-Replay.

const ROOM := "board:test-1"
const PEER := "GOOBY-PEER"


func test_board_start_push_initialisiert() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var session := _make_session(rig)
	var started: Array = []
	session.game_started.connect(func(data: Dictionary) -> void: started.append(data))

	await _start_game(rig, session, rig.client.friend_code)
	assert_eq(started.size(), 1)
	assert_eq(session.room_id, ROOM)
	assert_eq(session.opponent_code, PEER)
	assert_eq(session.opponent_name, "Mia")
	assert_true(session.my_turn(), "first=ich → ich fange an")
	assert_eq(rig.link().count_sent("ROOM_JOIN"), 1)
	assert_true(session.is_active())
	await _cleanup(rig, session)


func test_accept_startet_ueber_antwort() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var session := _make_session(rig)

	var results: Array = []
	_collect(func() -> Dictionary: return await session.accept(PEER), results)
	await wait_frames(1)
	rig.link().respond_to("BOARD_ACCEPT", "BOARD_START", _start_payload(PEER))
	await wait_frames(2)
	rig.link().respond_to("ROOM_JOIN", "OK", {})
	assert_true(await wait_until(func() -> bool: return results.size() == 1, 3000))
	assert_true((results[0] as Dictionary)["ok"])
	assert_eq(session.room_id, ROOM)
	assert_false(session.my_turn(), "first=Gegner → der fängt an")
	await _cleanup(rig, session)


func test_schuss_wechsel_beide_richtungen() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var session := _make_session(rig)
	await _start_game(rig, session, rig.client.friend_code)
	session.set_fleet(session.default_fleet())

	var my_results: Array = []
	var their_shots: Array = []
	session.shot_result.connect(
		func(n: int, cell: Vector2i, hit: bool, sunk: bool) -> void:
			my_results.append([n, cell, hit, sunk])
	)
	session.opponent_shot.connect(
		func(n: int, cell: Vector2i, result: Dictionary) -> void:
			their_shots.append([n, cell, result])
	)

	# 1) Mein Schuss geht als ROOM_MSG SHOT raus (n=1, Zellen-Notation).
	assert_true(session.shoot(Vector2i(0, 0)))
	var shot: Dictionary = rig.link().last_sent("ROOM_MSG")
	assert_eq(shot["d"]["kind"], "SHOT")
	# FakeWsLink parst JSON → Zahlen kommen als float zurück.
	assert_eq(int(shot["d"]["body"]["n"]), 1)
	assert_eq(shot["d"]["body"]["cell"], "A1")
	assert_false(session.shoot(Vector2i(1, 1)), "nicht dran (phase=result)")
	assert_false(session.my_turn())

	# 2) SHOT_RESULT vom Gegner → Tracker + Turn-Wechsel.
	_push_room_msg(rig, "SHOT_RESULT", {"n": 1, "hit": true, "sunk": false})
	await wait_frames(2)
	assert_eq(my_results, [[1, Vector2i(0, 0), true, false]])
	assert_false(session.tracker.is_new_target(Vector2i(0, 0)), "Zelle verbraucht")
	assert_false(session.my_turn(), "jetzt ist der Gegner dran")

	# 3) Gegner schießt (n=2) → eigenes Brett antwortet automatisch.
	_push_room_msg(rig, "SHOT", {"n": 2, "cell": "J10"})
	await wait_frames(2)
	assert_eq(their_shots.size(), 1)
	assert_eq(their_shots[0][1], Vector2i(9, 9))
	var reply: Dictionary = rig.link().last_sent("ROOM_MSG")
	assert_eq(reply["d"]["kind"], "SHOT_RESULT")
	assert_eq(int(reply["d"]["body"]["n"]), 2, "Antwort trägt das n des Schusses")
	assert_true(session.my_turn(), "nach dem Paar bin wieder ich dran")
	await _cleanup(rig, session)


func test_sieg_nach_fuenf_versenkten() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var session := _make_session(rig)
	await _start_game(rig, session, rig.client.friend_code)
	session.set_fleet(session.default_fleet())
	var overs: Array = []
	session.game_over.connect(
		func(winner_code: String, i_won: bool) -> void: overs.append([winner_code, i_won])
	)

	for i in BattleshipLogic.FLEET.size():
		assert_true(session.shoot(Vector2i(i, 0)), "Runde %d: Schuss muss dran sein" % i)
		_push_room_msg(rig, "SHOT_RESULT", {"n": session.turn.n, "hit": true, "sunk": true})
		await wait_frames(2)
		if i < BattleshipLogic.FLEET.size() - 1:
			_push_room_msg(rig, "SHOT", {"n": session.turn.n, "cell": "J%d" % (i + 1)})
			await wait_frames(2)

	assert_eq(overs, [[rig.client.friend_code, true]], "5 versenkte Schiffe = Sieg")
	assert_true(session.finished)
	var last: Dictionary = rig.link().last_sent("ROOM_MSG")
	assert_eq(last["d"]["kind"], "GAME_OVER", "Sieger meldet GAME_OVER in den Room")
	assert_eq(last["d"]["body"]["winner"], rig.client.friend_code)
	await _cleanup(rig, session)


func test_niederlage_wenn_eigene_flotte_faellt() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var session := _make_session(rig)
	await _start_game(rig, session, PEER)
	var fleet: Array = [
		{"at": [0, 0], "len": 5, "horizontal": true},
		{"at": [0, 2], "len": 4, "horizontal": true},
		{"at": [0, 4], "len": 3, "horizontal": true},
		{"at": [0, 6], "len": 3, "horizontal": true},
		{"at": [0, 8], "len": 2, "horizontal": true},
	]
	assert_true(session.set_fleet(fleet))
	var overs: Array = []
	session.game_over.connect(
		func(winner_code: String, i_won: bool) -> void: overs.append([winner_code, i_won])
	)

	var n := 1
	for ship: Dictionary in fleet:
		for cell in BattleshipLogic.ship_cells(ship):
			_push_room_msg(rig, "SHOT", {"n": n, "cell": BattleshipLogic.cell_to_ref(cell)})
			await wait_frames(1)
			n += 2
	await wait_frames(2)
	assert_eq(overs, [[PEER, false]], "alle eigenen Schiffe weg = Niederlage")
	await _cleanup(rig, session)


func test_tomate_limit_und_server_reset() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var session := _make_session(rig)
	await _start_game(rig, session, rig.client.friend_code)
	var rejected: Array = []
	session.tomato_rejected.connect(func(code: String) -> void: rejected.append(code))

	assert_true(session.throw_tomato())
	assert_false(session.throw_tomato(), "Client-Spiegel: 1×/Runde")

	# Server lehnt trotzdem ab (z. B. Rejoin-Rennen) → ERROR mit re → Reset.
	var seq := int(rig.link().last_sent("ROOM_MSG")["seq"])
	rig.link().push_server(
		{"v": 1, "t": "ERROR", "re": seq, "ts": 0, "d": {"code": "TOMATO_LIMIT"}}
	)
	await wait_frames(2)
	assert_eq(rejected, ["TOMATO_LIMIT"])
	assert_true(session.throw_tomato(), "nach Server-Reset wieder erlaubt")
	await _cleanup(rig, session)


func test_emote_relay_und_tomate_rein() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var session := _make_session(rig)
	await _start_game(rig, session, rig.client.friend_code)
	var emotes: Array = []
	var tomatoes: Array = []
	session.opponent_emote.connect(func(emote_id: String) -> void: emotes.append(emote_id))
	session.tomato_incoming.connect(func() -> void: tomatoes.append(true))

	assert_true(session.send_emote("dance"))
	assert_eq(rig.link().last_sent("ROOM_MSG")["d"]["body"], {"id": "dance"})
	assert_false(session.send_emote("quatsch"), "nur die 4 Rad-Emotes")

	_push_room_msg(rig, "EMOTE", {"id": "laugh"})
	_push_room_msg(rig, "TOMATO", {})
	await wait_frames(2)
	assert_eq(emotes, ["laugh"])
	assert_eq(tomatoes.size(), 1)
	await _cleanup(rig, session)


func test_forfeit_beendet_das_spiel() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var session := _make_session(rig)
	await _start_game(rig, session, PEER)
	var overs: Array = []
	session.game_over.connect(
		func(winner_code: String, i_won: bool) -> void: overs.append([winner_code, i_won])
	)
	(
		rig
		. link()
		. push_server(
			{
				"v": 1,
				"t": "BOARD_FORFEIT",
				"ts": 0,
				"d": {"room": ROOM, "winner": rig.client.friend_code},
			}
		)
	)
	await wait_frames(2)
	assert_eq(overs, [[rig.client.friend_code, true]], "Gegner weg → Sieg für mich")
	assert_false(session.is_active())
	await _cleanup(rig, session)


func test_board_resume_replay() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var session := _make_session(rig)
	await _start_game(rig, session, rig.client.friend_code)
	var resumed: Array = []
	session.game_resumed.connect(func(data: Dictionary) -> void: resumed.append(data))

	# History: mein Treffer auf A1, dann Gegner-Schuss auf J10 (Wasser).
	(
		rig
		. link()
		. push_server(
			{
				"v": 1,
				"t": "BOARD_RESUME",
				"ts": 0,
				"d":
				{
					"room": ROOM,
					"game": "battleship",
					"turn": rig.client.friend_code,
					"n": 3,
					"history":
					[
						{
							"kind": "SHOT",
							"from": rig.client.friend_code,
							"body": {"n": 1, "cell": "A1"}
						},
						{"kind": "SHOT_RESULT", "from": PEER, "body": {"n": 1, "hit": true}},
						{"kind": "SHOT", "from": PEER, "body": {"n": 2, "cell": "J10"}},
						{
							"kind": "SHOT_RESULT",
							"from": rig.client.friend_code,
							"body": {"n": 2, "hit": false}
						},
					],
				},
			}
		)
	)
	await wait_frames(2)
	assert_eq(resumed.size(), 1)
	assert_false(session.tracker.is_new_target(Vector2i(0, 0)), "A1 aus History verbraucht")
	assert_true(session.tracker.is_new_target(Vector2i(5, 5)))
	assert_eq(session.turn.n, 3, "Server-n ist Autorität")
	assert_true(session.my_turn(), "Server sagt: ich bin dran")
	assert_true(session.board.is_ready(), "eigene Flotte deterministisch rekonstruiert")
	await _cleanup(rig, session)


func test_fleet_seed_deterministisch() -> void:
	assert_eq(BoardSession.fleet_seed(42, "GOOBY-AAAA"), BoardSession.fleet_seed(42, "GOOBY-AAAA"))
	assert_ne(BoardSession.fleet_seed(42, "GOOBY-AAAA"), BoardSession.fleet_seed(42, "GOOBY-BBBB"))
	assert_true(BoardSession.fleet_seed(-99999, "GOOBY-X") >= 0, "immer positiv (Maske)")


func _start_payload(first: String) -> Dictionary:
	return {
		"room": ROOM,
		"game": "battleship",
		"seed": 4242,
		"first": first,
		"players":
		[
			{"friendCode": "GOOBY-TEST", "name": "Ich", "goobyName": "Gooby"},
			{"friendCode": PEER, "name": "Mia", "goobyName": "Flauschi"},
		],
	}


## BOARD_START als Push einspielen + ROOM_JOIN beantworten.
func _start_game(rig: NetTestRig, _session: BoardSession, first: String) -> void:
	rig.link().push_server({"v": 1, "t": "BOARD_START", "ts": 0, "d": _start_payload(first)})
	await wait_frames(2)
	rig.link().respond_to("ROOM_JOIN", "OK", {})
	await wait_frames(2)


func _push_room_msg(rig: NetTestRig, kind: String, body: Dictionary) -> void:
	(
		rig
		. link()
		. push_server(
			{
				"v": 1,
				"t": "ROOM_MSG",
				"ts": 0,
				"d": {"room": ROOM, "kind": kind, "body": body, "from": PEER},
			}
		)
	)


func _make_session(rig: NetTestRig) -> BoardSession:
	var session := BoardSession.new()
	tree.root.add_child(session)
	session.setup(rig.client)
	return session


func _collect(coroutine: Callable, out: Array) -> void:
	out.append(await coroutine.call())


func _cleanup(rig: NetTestRig, session: BoardSession) -> void:
	session.queue_free()
	await rig.shutdown(tree)
