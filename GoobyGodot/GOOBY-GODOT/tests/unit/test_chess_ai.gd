extends TestCase
## BACKLOG-REST — ChessAi: alle 3 Stärken ziehen IMMER legal (auch im Schach
## und bei Nur-ein-Zug-Stellungen), Stufe ≥2 findet Matt in 1 und nimmt
## hängende Damen, Stufe 3 findet Matt in 2; gleicher Seed ⇒ gleicher Zug
## (Determinismus), und die Logik bleibt nach der Suche unverändert.

const CHECK_POSITIONS: Array[String] = [
	ChessLogic.START_FEN,
	"r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
	"4k3/8/8/8/8/8/4q3/4K3 w - - 0 1",
	"8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 b - - 0 1",
	"rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
]


func test_alle_staerken_ziehen_legal() -> void:
	for fen in CHECK_POSITIONS:
		for strength in 3:
			var logic := ChessLogic.new()
			assert_true(logic.from_fen(fen), fen)
			var ai := ChessAi.new(1234 + strength)
			var m := ai.pick_move(logic, strength + 1)
			assert_ne(m, 0, "Stufe %d liefert einen Zug: %s" % [strength + 1, fen])
			assert_true(
				logic.legal_moves().has(m), "Stufe %d zieht legal: %s" % [strength + 1, fen]
			)
			assert_eq(logic.to_fen(), fen, "Suche hinterlässt keine Spuren")


func test_matt_patt_liefert_null() -> void:
	var logic := ChessLogic.new()
	assert_true(logic.from_fen("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"))
	assert_eq(ChessAi.new(1).pick_move(logic, 3), 0, "Patt: kein Zug")


func test_einziger_zug_wird_gefunden() -> void:
	var logic := ChessLogic.new()
	# Dame h6 gibt Schach auf der h-Linie — einziges Fluchtfeld ist g8.
	assert_true(logic.from_fen("7k/8/7Q/8/8/8/8/1K6 b - - 0 1"))
	var moves := logic.legal_moves()
	assert_eq(moves.size(), 1, "genau ein legaler Zug")
	for strength in 3:
		assert_eq(
			ChessAi.new(7).pick_move(logic, strength + 1),
			moves[0],
			"Stufe %d nimmt den Zwangszug" % (strength + 1)
		)


func test_stufe2_findet_matt_in_1() -> void:
	var logic := ChessLogic.new()
	# Grundreihenmatt: Ta1-a8 setzt matt.
	assert_true(logic.from_fen("6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1"))
	for strength: int in [2, 3]:
		var m := ChessAi.new(99).pick_move(logic, strength)
		assert_eq(ChessLogic.move_to_uci(m), "a1a8", "Stufe %d mattet sofort" % strength)


func test_stufe2_nimmt_haengende_dame() -> void:
	var logic := ChessLogic.new()
	# Schwarze Dame hängt auf d5, weißer Turm d1 nimmt sie einfach.
	assert_true(logic.from_fen("4k3/8/8/3q4/8/8/8/3RK3 w - - 0 1"))
	for strength: int in [2, 3]:
		var m := ChessAi.new(5).pick_move(logic, strength)
		assert_eq(ChessLogic.move_to_uci(m), "d1d5", "Stufe %d schlägt die Dame" % strength)


func test_stufe3_zwei_turm_matt() -> void:
	var logic := ChessLogic.new()
	# Zwei Türme: Ta7 sperrt die 7. Reihe, Tb8 setzt auf der 8. matt —
	# Stufe 3 findet den Mattzug und die Logik bestätigt das Matt.
	assert_true(logic.from_fen("4k3/R7/8/8/8/8/8/1R2K3 w - - 0 1"))
	var m := ChessAi.new(2026).pick_move(logic, 3)
	assert_eq(ChessLogic.move_to_uci(m), "b1b8", "Stufe 3 spielt den Mattzug")
	assert_true(logic.play_move(m))
	assert_eq(logic.result(), ChessLogic.RESULT_CHECKMATE, "und es ist wirklich Matt")


func test_stufe3_lehnt_vergifteten_bauern_ab() -> void:
	var logic := ChessLogic.new()
	# Dxd5?? exd5 verliert die Dame für einen Bauern — Ruhesuche/Tiefe ≥2
	# sehen den Rückschlag, die gierige Stufe 1 darf ruhig zugreifen.
	assert_true(logic.from_fen("4k3/8/4p3/3p4/8/8/8/3QK3 w - - 0 1"))
	for strength: int in [2, 3]:
		var m := ChessAi.new(11).pick_move(logic, strength)
		assert_ne(ChessLogic.move_to_uci(m), "d1d5", "Stufe %d nimmt den Köder nicht" % strength)


func test_determinismus_pro_seed() -> void:
	for fen in CHECK_POSITIONS:
		var a := _pick(fen, 424242, 1)
		var b := _pick(fen, 424242, 1)
		assert_eq(a, b, "gleicher Seed, gleicher Zug: " + fen)


func test_stufe1_streut_ueber_seeds() -> void:
	var seen: Dictionary = {}
	for seed_value in 12:
		seen[_pick(ChessLogic.START_FEN, seed_value * 31 + 7, 1)] = true
	assert_true(seen.size() >= 2, "Stufe 1 spielt nicht immer denselben Zug")


func test_evaluate_material() -> void:
	var logic := ChessLogic.new()
	assert_eq(ChessAi.new(1).evaluate(logic), 0, "Startstellung ist ausgeglichen")
	assert_true(logic.from_fen("4k3/8/8/8/8/8/8/Q3K3 w - - 0 1"))
	assert_true(ChessAi.new(1).evaluate(logic) >= 900, "Dame plus aus Sicht Weiß")
	assert_true(logic.from_fen("4k3/8/8/8/8/8/8/Q3K3 b - - 0 1"))
	assert_true(ChessAi.new(1).evaluate(logic) <= -900, "aus Sicht Schwarz negativ")


func _pick(fen: String, seed_value: int, strength: int) -> int:
	var logic := ChessLogic.new()
	logic.from_fen(fen)
	return ChessAi.new(seed_value).pick_move(logic, strength)
