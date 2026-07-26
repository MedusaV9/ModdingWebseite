extends TestCase
## BACKLOG-REST — ChessScene headless: Solo-Partie gegen den Bot (Auswahl →
## Zugeingabe über die Feld-Handler → KI antwortet legal), Umwandlungs-Picker,
## Sieg-Overlay + "chess_win"-Sticker-Hook, Brett-Drehung für Schwarz und die
## Mehrspieler-Verkabelung (Session-Zug erscheint auf dem Brett).

const GameStateScript := preload("res://scripts/state/game_state.gd")

var _dir_seq := 0


class FakeServices:
	extends Node

	var chess: ChessSession = null
	var game_state_override: Object = null


func test_solo_partie_zug_und_ki_antwort() -> void:
	var ctx := await _open_scene()
	var scene: ChessScene = ctx["scene"]
	assert_true(scene._pick_panel.visible, "Stärke-Auswahl zuerst")
	scene._ai_strength = 1
	scene._on_solo_start(ChessLogic.WHITE)
	assert_false(scene._pick_panel.visible)
	assert_eq(scene._squares.size(), 64, "8x8 Felder")

	# e2 antippen → Ziele e3+e4 leuchten; e4 antippen → Zug fällt.
	scene._on_square_pressed(0x14)
	assert_eq(scene._selected, 0x14, "e2 gewählt")
	assert_true(scene._targets.has(0x24) and scene._targets.has(0x34), "e3+e4 als Ziele")
	scene._on_square_pressed(0x34)
	assert_eq(scene.game_logic().piece_at(4, 3), ChessLogic.PAWN, "e4 gespielt")

	# KI (Schwarz) antwortet asynchron mit einem legalen Zug.
	assert_true(
		await wait_until(
			func() -> bool: return scene.game_logic().to_move == ChessLogic.WHITE, 8000
		),
		"KI hat geantwortet"
	)
	assert_eq(scene.game_logic().result(), ChessLogic.RESULT_RUNNING)
	assert_eq(scene._move_count, 2, "zwei Züge in der Liste")
	await _close_scene(ctx)


func test_umwandlung_ueber_picker() -> void:
	var ctx := await _open_scene()
	var scene: ChessScene = ctx["scene"]
	scene._ai_strength = 1
	scene._on_solo_start(ChessLogic.WHITE)
	scene._solo_logic.from_fen("6n1/5P2/8/8/8/8/1K6/7k w - - 0 1")
	scene._render()
	scene._on_square_pressed(0x65)
	assert_true(scene._targets.has(0x75), "f8 als Umwandlungs-Ziel")
	scene._on_square_pressed(0x75)
	assert_true(scene._promo_panel.visible, "Picker öffnet sich")
	scene._on_promo_picked(ChessLogic.KNIGHT)
	assert_eq(scene.game_logic().piece_at(5, 7), ChessLogic.KNIGHT, "Springer steht auf f8")
	await _close_scene(ctx)


func test_sieg_overlay_und_sticker_hook() -> void:
	var ctx := await _open_scene()
	var scene: ChessScene = ctx["scene"]
	var gs: Object = ctx["gs"]
	scene._ai_strength = 1
	scene._on_solo_start(ChessLogic.WHITE)
	scene._solo_logic.from_fen("6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1")
	scene._render()
	scene._on_square_pressed(0x00)
	assert_true(scene._targets.has(0x70), "a8 erreichbar")
	scene._on_square_pressed(0x70)
	assert_eq(scene._phase, "over", "Matt beendet die Partie")
	assert_true(scene._result_panel.visible, "Overlay steht")
	assert_eq(scene._result_label.text, I18nService.t("chess.win"))
	assert_true(scene._new_game_button.visible, "Neue Partie angeboten")
	var hooks: Variant = gs.get_value("stickers.hooks", {})
	assert_true(
		hooks is Dictionary and (hooks as Dictionary).has("chess_win"), "chess_win-Hook"
	)
	await _close_scene(ctx)


func test_brett_drehung_fuer_schwarz() -> void:
	var ctx := await _open_scene()
	var scene: ChessScene = ctx["scene"]
	scene._ai_strength = 1
	scene._my_color = ChessLogic.WHITE
	assert_eq(scene._display_to_square(7, 0), 0x00, "Weiß: unten links = a1")
	assert_eq(scene._display_to_square(0, 0), 0x70, "Weiß: oben links = a8")
	scene._my_color = ChessLogic.BLACK
	assert_eq(scene._display_to_square(7, 0), 0x77, "Schwarz: unten links = h8")
	assert_eq(scene._display_to_square(0, 0), 0x07, "Schwarz: oben links = h1")
	await _close_scene(ctx)


func test_multiplayer_session_zug_erscheint() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var session := ChessSession.new()
	tree.root.add_child(session)
	session.setup(rig.client)
	rig.link().push_server(
		{
			"v": 1,
			"t": "BOARD_START",
			"ts": 0,
			"d":
			{
				"room": "board:chess-ui",
				"game": "chess",
				"seed": 1,
				"first": rig.client.friend_code,
				"players":
				[
					{"friendCode": rig.client.friend_code, "name": "Ich", "goobyName": "Gooby"},
					{"friendCode": "GOOBY-PEER", "name": "Mia", "goobyName": "Flauschi"},
				],
			},
		}
	)
	await wait_frames(2)
	rig.link().respond_to("ROOM_JOIN", "OK", {})
	await wait_frames(2)

	var ctx := await _open_scene(session)
	var scene: ChessScene = ctx["scene"]
	assert_eq(scene._mode, "mp", "aktive Session → Mehrspieler")
	assert_eq(scene._opp_label.text, "Flauschi")
	assert_true(scene._is_my_turn(), "Weiß (wir) beginnt")

	scene._on_square_pressed(0x14)
	scene._on_square_pressed(0x34)
	var shot: Dictionary = rig.link().last_sent("ROOM_MSG")
	assert_eq(shot["d"]["kind"], "SHOT", "Zug ging als SHOT raus")
	assert_eq(shot["d"]["body"]["move"], "e2e4")

	rig.link().push_server(
		{
			"v": 1,
			"t": "ROOM_MSG",
			"ts": 0,
			"d":
			{
				"room": "board:chess-ui",
				"kind": "SHOT_RESULT",
				"body": {"n": 1},
				"from": "GOOBY-PEER",
			},
		}
	)
	rig.link().push_server(
		{
			"v": 1,
			"t": "ROOM_MSG",
			"ts": 0,
			"d":
			{
				"room": "board:chess-ui",
				"kind": "SHOT",
				"body": {"n": 2, "move": "e7e5"},
				"from": "GOOBY-PEER",
			},
		}
	)
	await wait_frames(2)
	assert_eq(scene.game_logic().piece_at(4, 4), -ChessLogic.PAWN, "Gegner-Zug auf dem Brett")
	assert_true(scene._is_my_turn(), "wieder wir")
	(ctx["scene"] as Node).queue_free()
	(ctx["services"] as Node).queue_free()
	session.queue_free()
	await wait_frames(2)
	(ctx["gs"] as Node).free()
	await rig.shutdown(tree)


func _fresh_gs() -> Node:
	_dir_seq += 1
	var dir := "user://backlogrest_tests/chess_%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	return gs


func _open_scene(session: ChessSession = null) -> Dictionary:
	var gs := _fresh_gs()
	var services := FakeServices.new()
	services.chess = session
	services.game_state_override = gs
	tree.root.add_child(services)
	var scene := ChessScene.new()
	scene.services_override = services
	tree.root.add_child(scene)
	await wait_frames(1)
	return {"scene": scene, "services": services, "gs": gs}


func _close_scene(ctx: Dictionary) -> void:
	(ctx["scene"] as Node).queue_free()
	(ctx["services"] as Node).queue_free()
	await wait_frames(2)
	(ctx["gs"] as Node).free()
