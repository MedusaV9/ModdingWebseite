extends TestCase
## PURE-Tests für BattleshipLogic (W3c VISIT): Flotten-Setup/Validierung,
## Zellen-Notation, Schuss-Auswertung (Treffer/versenkt/Wasser/Wiederholung),
## Sieg, Tracker (Gegner-Sicht) und der Turn-Spiegel der Server-Regeln.

const CODE_A := "GOOBY-AAAA"
const CODE_B := "GOOBY-BBBB"


func _valid_fleet() -> Array:
	return [
		{"at": [0, 0], "len": 5, "horizontal": true},
		{"at": [0, 2], "len": 4, "horizontal": true},
		{"at": [0, 4], "len": 3, "horizontal": true},
		{"at": [0, 6], "len": 3, "horizontal": true},
		{"at": [0, 8], "len": 2, "horizontal": true},
	]


func test_ship_cells_richtungen() -> void:
	var horizontal := {"at": [2, 3], "len": 3, "horizontal": true}
	assert_eq(
		BattleshipLogic.ship_cells(horizontal),
		[Vector2i(2, 3), Vector2i(3, 3), Vector2i(4, 3)] as Array[Vector2i]
	)
	var vertical := {"at": [9, 7], "len": 3, "horizontal": false}
	assert_eq(
		BattleshipLogic.ship_cells(vertical),
		[Vector2i(9, 7), Vector2i(9, 8), Vector2i(9, 9)] as Array[Vector2i]
	)


func test_validate_fleet_ok_und_fehler() -> void:
	assert_true(BattleshipLogic.validate_fleet(_valid_fleet())["ok"])
	assert_eq(BattleshipLogic.validate_fleet([])["reason"], BattleshipLogic.REASON_WRONG_COUNT)
	var wrong_lengths := _valid_fleet()
	wrong_lengths[0] = {"at": [0, 0], "len": 6, "horizontal": true}
	assert_eq(
		BattleshipLogic.validate_fleet(wrong_lengths)["reason"],
		BattleshipLogic.REASON_WRONG_LENGTHS
	)
	var oob := _valid_fleet()
	oob[0] = {"at": [7, 0], "len": 5, "horizontal": true}
	assert_eq(BattleshipLogic.validate_fleet(oob)["reason"], BattleshipLogic.REASON_OUT_OF_BOUNDS)
	var overlap := _valid_fleet()
	overlap[4] = {"at": [0, 0], "len": 2, "horizontal": false}
	assert_eq(BattleshipLogic.validate_fleet(overlap)["reason"], BattleshipLogic.REASON_OVERLAP)


func test_auto_fleet_deterministisch_und_gueltig() -> void:
	var a := BattleshipLogic.auto_fleet(12345)
	var b := BattleshipLogic.auto_fleet(12345)
	var c := BattleshipLogic.auto_fleet(54321)
	assert_eq(a, b, "gleicher Seed muss gleiche Flotte liefern")
	assert_ne(a, c, "anderer Seed sollte andere Flotte liefern")
	assert_true(BattleshipLogic.validate_fleet(a)["ok"])
	assert_true(BattleshipLogic.validate_fleet(c)["ok"])


func test_zellen_notation() -> void:
	assert_eq(BattleshipLogic.cell_to_ref(Vector2i(1, 3)), "B4")
	assert_eq(BattleshipLogic.ref_to_cell("B4"), Vector2i(1, 3))
	assert_eq(BattleshipLogic.ref_to_cell("j10"), Vector2i(9, 9))
	assert_eq(BattleshipLogic.cell_to_ref(Vector2i(0, 0)), "A1")
	assert_eq(BattleshipLogic.ref_to_cell("Z9"), Vector2i(-1, -1))
	assert_eq(BattleshipLogic.ref_to_cell("A0"), Vector2i(-1, -1))
	assert_eq(BattleshipLogic.ref_to_cell("A11"), Vector2i(-1, -1))
	assert_eq(BattleshipLogic.ref_to_cell(""), Vector2i(-1, -1))
	assert_eq(BattleshipLogic.cell_to_ref(Vector2i(10, 0)), "")
	for x in BattleshipLogic.GRID:
		for y in BattleshipLogic.GRID:
			var cell := Vector2i(x, y)
			assert_eq(
				BattleshipLogic.ref_to_cell(BattleshipLogic.cell_to_ref(cell)),
				cell,
				"Roundtrip %s" % cell
			)


func test_setup_und_schuesse() -> void:
	var board := BattleshipLogic.new()
	assert_false(board.setup([]), "leere Flotte darf nicht aufgehen")
	assert_false(board.is_ready())
	assert_true(board.setup(_valid_fleet()))
	assert_true(board.is_ready())
	assert_eq(board.remaining_ships(), 5)

	var miss := board.receive_shot(Vector2i(9, 9))
	assert_false(miss["hit"])
	assert_false(miss["repeat"])

	var hit := board.receive_shot(Vector2i(0, 8))
	assert_true(hit["hit"])
	assert_false(hit["sunk"])

	var repeat := board.receive_shot(Vector2i(0, 8))
	assert_true(repeat["repeat"])
	assert_true(repeat["hit"])
	assert_eq(board.remaining_ships(), 5, "angeschossen zählt noch als schwimmend")

	var sunk := board.receive_shot(Vector2i(1, 8))
	assert_true(sunk["sunk"], "2er-Schiff nach 2 Treffern versenkt")
	assert_eq((sunk["sunk_cells"] as Array).size(), 2)
	assert_false(sunk["all_sunk"])
	assert_eq(board.remaining_ships(), 4)

	var oob := board.receive_shot(Vector2i(-1, 4))
	assert_false(oob["hit"])


func test_sieg_alle_versenkt() -> void:
	var board := BattleshipLogic.new()
	board.setup(_valid_fleet())
	var last := {}
	for ship: Dictionary in _valid_fleet():
		for cell in BattleshipLogic.ship_cells(ship):
			last = board.receive_shot(cell)
	assert_true(last["sunk"])
	assert_true(last["all_sunk"], "letzter Treffer muss den Sieg melden")
	assert_eq(board.remaining_ships(), 0)


func test_tracker_gegner_sicht() -> void:
	var tracker := BattleshipLogic.Tracker.new()
	assert_true(tracker.is_new_target(Vector2i(0, 0)))
	assert_false(tracker.is_new_target(Vector2i(-1, 0)), "außerhalb nie gültig")
	tracker.record(Vector2i(0, 0), true, false)
	assert_false(tracker.is_new_target(Vector2i(0, 0)), "keine Doppel-Schüsse")
	assert_false(tracker.has_won())
	for i in BattleshipLogic.FLEET.size():
		tracker.record(Vector2i(i, 9), true, true)
	assert_true(tracker.has_won(), "5 versenkte Schiffe = Sieg")


func test_turn_spiegel_serverregeln() -> void:
	var turn := BattleshipLogic.Turn.new(CODE_A, [CODE_A, CODE_B])
	assert_true(turn.can_shoot(CODE_A))
	assert_false(turn.can_shoot(CODE_B))
	assert_false(turn.can_answer(CODE_B), "vor dem Schuss keine Antwort")
	assert_eq(turn.n, 1)
	assert_eq(turn.round_index(), 0)

	turn.on_shot()
	assert_false(turn.can_shoot(CODE_A), "nach dem Schuss ist phase=result")
	assert_true(turn.can_answer(CODE_B), "der Beschossene antwortet")
	assert_false(turn.can_answer(CODE_A))

	turn.on_result()
	assert_eq(turn.n, 2)
	assert_true(turn.can_shoot(CODE_B), "nach SHOT_RESULT wechselt der Zug")
	assert_eq(turn.round_index(), 0, "Runde erst nach BEIDEN Paaren fertig")

	turn.on_shot()
	turn.on_result()
	assert_eq(turn.round_index(), 1, "exchanges/2 wie boardgames.js")
	assert_true(turn.can_shoot(CODE_A))
