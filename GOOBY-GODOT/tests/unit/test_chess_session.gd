extends TestCase
## BACKLOG-REST — ChessSession gegen NetClient+FakeWsLink: BOARD_START mit
## game "chess" (Farben aus first), Zug-Relay SHOT{n,move}/SHOT_RESULT{n}
## (Auto-Ack), Matt über das Relay (der EMPFÄNGER schreibt GAME_OVER),
## Aufgeben, Revanche-Farbtausch, BOARD_RESUME-Replay inkl. hängendem Ack —
## und die Spiel-Weiche: Battleship-Starts gehen an dieser Session vorbei
## (und Schach-Starts an der BoardSession).

const ROOM := "board:chess-1"
const PEER := "GOOBY-PEER"


func test_start_setzt_farben_und_brett() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var session := _make_session(rig)
	var started: Array = []
	session.game_started.connect(func(data: Dictionary) -> void: started.append(data))

	await _start_game(rig, session, rig.client.friend_code)
	assert_eq(started.size(), 1)
	assert_eq(session.room_id, ROOM)
	assert_eq(session.opponent_code, PEER)
	assert_eq(session.my_color, ChessLogic.WHITE, "first=ich → Weiß")
	assert_true(session.my_turn(), "Weiß beginnt")
	assert_eq(session.logic.to_fen(), ChessLogic.START_FEN)
	assert_eq(rig.link().count_sent("ROOM_JOIN"), 1)
	await _cleanup(rig, session)


func test_battleship_start_geht_vorbei() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var session := _make_session(rig)
	var board := BoardSession.new()
	tree.root.add_child(board)
	board.setup(rig.client)
	var chess_starts: Array = []
	var ship_starts: Array = []
	session.game_started.connect(func(data: Dictionary) -> void: chess_starts.append(data))
	board.game_started.connect(func(data: Dictionary) -> void: ship_starts.append(data))

	var payload := _start_payload(rig.client.friend_code)
	payload["game"] = "battleship"
	rig.link().push_server({"v": 1, "t": "BOARD_START", "ts": 0, "d": payload})
	await wait_frames(2)
	rig.link().respond_to("ROOM_JOIN", "OK", {})
	await wait_frames(2)
	assert_eq(chess_starts.size(), 0, "Schach-Session ignoriert Battleship")
	assert_eq(ship_starts.size(), 1, "BoardSession nimmt Battleship")

	await _start_game(rig, session, rig.client.friend_code)
	assert_eq(chess_starts.size(), 1, "Schach-Start kommt an")
	assert_eq(ship_starts.size(), 1, "BoardSession ignoriert Schach-Start")
	board.queue_free()
	await _cleanup(rig, session)


func test_zug_relay_beide_richtungen() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var session := _make_session(rig)
	await _start_game(rig, session, rig.client.friend_code)
	var moved: Array = []
	session.opponent_moved.connect(func(uci: String) -> void: moved.append(uci))

	# 1) Mein Zug reist als SHOT {n:1, move}.
	assert_true(session.send_move("e2e4"))
	var shot: Dictionary = rig.link().last_sent("ROOM_MSG")
	assert_eq(shot["d"]["kind"], "SHOT")
	assert_eq(int(shot["d"]["body"]["n"]), 1)
	assert_eq(shot["d"]["body"]["move"], "e2e4")
	assert_false(session.my_turn(), "Ack steht aus")
	assert_false(session.send_move("d2d4"), "kein Doppelzug")

	# 2) Ack des Gegners → wieder zugfähig, sobald er gezogen hat.
	_push_room_msg(rig, "SHOT_RESULT", {"n": 1})
	await wait_frames(2)
	assert_false(session.my_turn(), "Schwarz ist am Zug")

	# 3) Gegner zieht (n=2) → Brett übernimmt den Zug + Auto-Ack.
	_push_room_msg(rig, "SHOT", {"n": 2, "move": "e7e5"})
	await wait_frames(2)
	assert_eq(moved, ["e7e5"])
	var reply: Dictionary = rig.link().last_sent("ROOM_MSG")
	assert_eq(reply["d"]["kind"], "SHOT_RESULT")
	assert_eq(int(reply["d"]["body"]["n"]), 2, "Ack trägt das n des Zugs")
	assert_true(session.my_turn(), "wieder ich")
	assert_eq(session.logic.piece_at(4, 4), -ChessLogic.PAWN, "e5 steht")
	assert_false(session.send_move("e1e3"), "illegale Züge gehen nie raus")
	await _cleanup(rig, session)


func test_matt_ueber_relay_empfaenger_meldet() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var session := _make_session(rig)
	# Gegner (Weiß) spielt das Narrenmatt gegen uns.
	await _start_game(rig, session, PEER)
	var overs: Array = []
	session.game_over.connect(
		func(code: String, i_won: bool, why: String) -> void: overs.append([code, i_won, why])
	)

	_push_room_msg(rig, "SHOT", {"n": 1, "move": "f2f3"})
	await wait_frames(1)
	assert_true(session.send_move("e7e5"))
	_push_room_msg(rig, "SHOT_RESULT", {"n": 2})
	await wait_frames(1)
	_push_room_msg(rig, "SHOT", {"n": 3, "move": "g2g4"})
	await wait_frames(1)
	assert_true(session.send_move("d8h4"))
	_push_room_msg(rig, "SHOT_RESULT", {"n": 4})
	await wait_frames(1)
	_push_room_msg(rig, "SHOT", {"n": 5, "move": "quatsch"})
	await wait_frames(1)
	assert_eq(session.logic.piece_at(7, 3), -ChessLogic.QUEEN, "Dh4 steht")

	# WIR haben Dh4# gespielt → i_moved=true, der GEGNER meldet GAME_OVER
	# in die History. Lokal ist das Spiel sofort vorbei; der Müll-Zug danach
	# löst kein zweites game_over aus.
	assert_eq(overs.size(), 1, "Matt lokal erkannt (genau einmal)")
	assert_eq(overs[0][0], rig.client.friend_code, "wir gewinnen")
	assert_eq(overs[0][1], true)
	assert_eq(overs[0][2], ChessLogic.RESULT_CHECKMATE)
	await _cleanup(rig, session)


func test_matt_durch_gegner_wir_melden() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var session := _make_session(rig)
	await _start_game(rig, session, rig.client.friend_code)
	var overs: Array = []
	session.game_over.connect(
		func(code: String, i_won: bool, why: String) -> void: overs.append([code, i_won, why])
	)

	assert_true(session.send_move("f2f3"))
	_push_room_msg(rig, "SHOT_RESULT", {"n": 1})
	_push_room_msg(rig, "SHOT", {"n": 2, "move": "e7e5"})
	await wait_frames(1)
	assert_true(session.send_move("g2g4"))
	_push_room_msg(rig, "SHOT_RESULT", {"n": 3})
	_push_room_msg(rig, "SHOT", {"n": 4, "move": "d8h4"})
	await wait_frames(2)

	# Gegner-Zug hat uns mattgesetzt → WIR (Empfänger) melden GAME_OVER.
	assert_eq(overs.size(), 1)
	assert_eq(overs[0][0], PEER, "der Gegner gewinnt")
	assert_eq(overs[0][1], false)
	var last: Dictionary = rig.link().last_sent("ROOM_MSG")
	assert_eq(last["d"]["kind"], "GAME_OVER", "Empfänger schreibt die History")
	assert_eq(last["d"]["body"]["winner"], PEER)
	assert_eq(last["d"]["body"]["reason"], ChessLogic.RESULT_CHECKMATE)
	await _cleanup(rig, session)


func test_aufgeben_und_revanche_tauscht_farben() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var session := _make_session(rig)
	await _start_game(rig, session, rig.client.friend_code)
	var overs: Array = []
	session.game_over.connect(
		func(code: String, i_won: bool, why: String) -> void: overs.append([code, i_won, why])
	)

	assert_true(session.surrender())
	assert_eq(overs, [[PEER, false, ChessSession.REASON_SURRENDER]])
	var last: Dictionary = rig.link().last_sent("ROOM_MSG")
	assert_eq(last["d"]["kind"], "GAME_OVER")
	assert_eq(last["d"]["body"]["winner"], PEER)

	# Revanche: der Server startet frisch, first = Gegner → wir sind Schwarz.
	var results: Array = []
	_collect(func() -> Dictionary: return await session.request_rematch(), results)
	await wait_frames(1)
	var payload := _start_payload(PEER)
	payload["room"] = "board:chess-2"
	rig.link().respond_to("BOARD_REMATCH", "BOARD_START", payload)
	await wait_frames(2)
	rig.link().respond_to("ROOM_JOIN", "OK", {})
	assert_true(await wait_until(func() -> bool: return results.size() == 1, 3000))
	assert_eq(session.room_id, "board:chess-2")
	assert_eq(session.my_color, ChessLogic.BLACK, "Revanche: Farben getauscht")
	assert_false(session.my_turn(), "Weiß (Gegner) beginnt")
	assert_false(session.finished)
	await _cleanup(rig, session)


func test_resume_replay_mit_haengendem_gegner_zug() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var session := _make_session(rig)
	await _start_game(rig, session, rig.client.friend_code)
	var resumed: Array = []
	session.game_resumed.connect(func(data: Dictionary) -> void: resumed.append(data))

	# History: e4 (ich, geackt), e5 (Gegner, Ack fehlt noch → wir acken).
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
					"game": "chess",
					"turn": rig.client.friend_code,
					"n": 2,
					"history":
					[
						{
							"kind": "SHOT",
							"from": rig.client.friend_code,
							"body": {"n": 1, "move": "e2e4"}
						},
						{"kind": "SHOT_RESULT", "from": PEER, "body": {"n": 1}},
						{"kind": "SHOT", "from": PEER, "body": {"n": 2, "move": "e7e5"}},
					],
				},
			}
		)
	)
	await wait_frames(2)
	assert_eq(resumed.size(), 1)
	assert_eq(session.logic.piece_at(4, 3), ChessLogic.PAWN, "e4 rekonstruiert")
	assert_eq(session.logic.piece_at(4, 4), -ChessLogic.PAWN, "e5 rekonstruiert")
	var ack: Dictionary = rig.link().last_sent("ROOM_MSG")
	assert_eq(ack["d"]["kind"], "SHOT_RESULT", "hängender Gegner-Zug wird geackt")
	assert_eq(int(ack["d"]["body"]["n"]), 2)
	assert_true(session.my_turn(), "danach sind wir dran")
	await _cleanup(rig, session)


func test_server_lehnt_zug_ab_rollback() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var session := _make_session(rig)
	await _start_game(rig, session, rig.client.friend_code)
	var rejected: Array = []
	session.send_rejected.connect(
		func(kind: String, code: String) -> void: rejected.append([kind, code])
	)

	assert_true(session.send_move("e2e4"))
	var seq := int(rig.link().last_sent("ROOM_MSG")["seq"])
	rig.link().push_server(
		{"v": 1, "t": "ERROR", "re": seq, "ts": 0, "d": {"code": "NOT_YOUR_TURN"}}
	)
	await wait_frames(2)
	assert_eq(rejected, [["SHOT", "NOT_YOUR_TURN"]])
	assert_eq(session.logic.to_fen(), ChessLogic.START_FEN, "Zug zurückgerollt")
	assert_true(session.my_turn(), "wieder zugfähig")
	await _cleanup(rig, session)


func test_forfeit_und_peer_down() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var session := _make_session(rig)
	await _start_game(rig, session, PEER)
	var overs: Array = []
	var peers: Array = []
	session.game_over.connect(
		func(code: String, i_won: bool, why: String) -> void: overs.append([code, i_won, why])
	)
	session.peer_connection_changed.connect(
		func(down: bool, wait_ms: int) -> void: peers.append([down, wait_ms])
	)

	rig.link().push_server(
		{
			"v": 1,
			"t": "BOARD_PEER_DOWN",
			"ts": 0,
			"d": {"room": ROOM, "friendCode": PEER, "waitMs": 120000},
		}
	)
	await wait_frames(2)
	assert_eq(peers, [[true, 120000]])
	assert_true(session.peer_down)
	rig.link().push_server(
		{
			"v": 1,
			"t": "BOARD_FORFEIT",
			"ts": 0,
			"d": {"room": ROOM, "winner": rig.client.friend_code},
		}
	)
	await wait_frames(2)
	assert_eq(overs.size(), 1, "Forfeit beendet das Spiel")
	assert_eq(overs[0][0], rig.client.friend_code)
	assert_eq(overs[0][1], true)
	assert_false(session.is_active())
	await _cleanup(rig, session)


func _start_payload(first: String) -> Dictionary:
	return {
		"room": ROOM,
		"game": "chess",
		"seed": 777,
		"first": first,
		"players":
		[
			{"friendCode": "GOOBY-TEST", "name": "Ich", "goobyName": "Gooby"},
			{"friendCode": PEER, "name": "Mia", "goobyName": "Flauschi"},
		],
	}


func _start_game(rig: NetTestRig, _session: ChessSession, first: String) -> void:
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


func _make_session(rig: NetTestRig) -> ChessSession:
	var session := ChessSession.new()
	tree.root.add_child(session)
	session.setup(rig.client)
	return session


func _collect(coroutine: Callable, out: Array) -> void:
	out.append(await coroutine.call())


func _cleanup(rig: NetTestRig, session: ChessSession) -> void:
	session.queue_free()
	await rig.shutdown(tree)
