extends TestCase
## BACKLOG-REST — ChessLogic: Perft gegen die Standard-Teststellungen
## (Startstellung, Kiwipete, Pos. 3/4/5 — decken Rochade, en passant und
## Umwandlung ab), FEN-Roundtrip, Rochade-/ep-/Umwandlungs-Regeln im Detail,
## Matt/Patt/Remis-Erkennung (50 Züge, Wiederholung, totes Material) und
## der play/undo-Partie-Pfad.

const KIWIPETE := "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1"
const POS3 := "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1"
const POS4 := "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1"
const POS5 := "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8"


func test_startstellung_grundwerte() -> void:
	var logic := ChessLogic.new()
	assert_eq(logic.legal_moves().size(), 20, "20 Eröffnungszüge")
	assert_eq(logic.to_fen(), ChessLogic.START_FEN, "FEN-Roundtrip Start")
	assert_eq(logic.piece_at(4, 0), ChessLogic.KING, "weißer König auf e1")
	assert_eq(logic.piece_at(3, 7), -ChessLogic.QUEEN, "schwarze Dame auf d8")
	assert_false(logic.in_check())
	assert_eq(logic.result(), ChessLogic.RESULT_RUNNING)


func test_perft_startstellung() -> void:
	var logic := ChessLogic.new()
	assert_eq(logic.perft(1), 20, "perft(1)")
	assert_eq(logic.perft(2), 400, "perft(2)")
	assert_eq(logic.perft(3), 8902, "perft(3)")
	assert_eq(logic.perft(4), 197281, "perft(4)")
	assert_eq(logic.to_fen(), ChessLogic.START_FEN, "make/unmake hinterlässt nichts")


func test_perft_kiwipete() -> void:
	var logic := ChessLogic.new()
	assert_true(logic.from_fen(KIWIPETE), "Kiwipete-FEN lädt")
	assert_eq(logic.perft(1), 48, "Kiwipete perft(1)")
	assert_eq(logic.perft(2), 2039, "Kiwipete perft(2)")
	assert_eq(logic.perft(3), 97862, "Kiwipete perft(3)")
	assert_eq(logic.to_fen(), KIWIPETE, "Zustand unverändert")


func test_perft_position_3_en_passant() -> void:
	var logic := ChessLogic.new()
	assert_true(logic.from_fen(POS3))
	assert_eq(logic.perft(1), 14, "Pos3 perft(1)")
	assert_eq(logic.perft(2), 191, "Pos3 perft(2)")
	assert_eq(logic.perft(3), 2812, "Pos3 perft(3)")


func test_perft_position_4_umwandlungen() -> void:
	var logic := ChessLogic.new()
	assert_true(logic.from_fen(POS4))
	assert_eq(logic.perft(1), 6, "Pos4 perft(1)")
	assert_eq(logic.perft(2), 264, "Pos4 perft(2)")


func test_perft_position_5() -> void:
	var logic := ChessLogic.new()
	assert_true(logic.from_fen(POS5))
	assert_eq(logic.perft(1), 44, "Pos5 perft(1)")
	assert_eq(logic.perft(2), 1486, "Pos5 perft(2)")


func test_fen_roundtrip_diverse() -> void:
	for fen: String in [KIWIPETE, POS3, POS4, POS5]:
		var logic := ChessLogic.new()
		assert_true(logic.from_fen(fen), fen)
		assert_eq(logic.to_fen(), fen, "Roundtrip: " + fen)
	assert_false(ChessLogic.new().from_fen("quatsch"), "Müll-FEN lehnt ab")


func test_rochade_kurz_und_lang() -> void:
	var logic := ChessLogic.new()
	assert_true(logic.from_fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"))
	var ucis := _uci_set(logic)
	assert_true(ucis.has("e1g1"), "kurze Rochade möglich")
	assert_true(ucis.has("e1c1"), "lange Rochade möglich")
	assert_true(logic.play_uci("e1g1"))
	assert_eq(logic.piece_at(6, 0), ChessLogic.KING, "König auf g1")
	assert_eq(logic.piece_at(5, 0), ChessLogic.ROOK, "Turm auf f1")
	var black := _uci_set(logic)
	assert_true(black.has("e8c8"), "Schwarz darf noch lang")
	assert_true(logic.play_uci("e8c8"))
	assert_eq(logic.piece_at(2, 7), -ChessLogic.KING, "König auf c8")
	assert_eq(logic.piece_at(3, 7), -ChessLogic.ROOK, "Turm auf d8")


func test_rochade_verboten_durch_schach_und_rechteverlust() -> void:
	var logic := ChessLogic.new()
	# Schwarzer Turm auf e4 gibt Schach auf der e-Linie → keine Rochade.
	assert_true(logic.from_fen("r3k2r/8/8/8/4r3/8/8/R3K2R w KQkq - 0 1"))
	var ucis := _uci_set(logic)
	assert_false(ucis.has("e1g1"), "im Schach keine Rochade")
	assert_false(ucis.has("e1c1"), "im Schach keine Rochade (lang)")
	# Turm auf f4 beherrscht f1 → König zöge durch Schach.
	assert_true(logic.from_fen("r3k2r/8/8/8/5r2/8/8/R3K2R w KQkq - 0 1"))
	assert_false(_uci_set(logic).has("e1g1"), "durch bedrohtes Feld keine Rochade")
	assert_true(_uci_set(logic).has("e1c1"), "lange Seite bleibt erlaubt")
	# Nach einem Königszug sind beide Rechte weg — für immer.
	assert_true(logic.from_fen("r3k2r/8/8/8/8/8/8/R3K2R w KQkq - 0 1"))
	assert_true(logic.play_uci("e1d1"))
	assert_true(logic.play_uci("a8b8"))
	assert_true(logic.play_uci("d1e1"))
	assert_true(logic.play_uci("b8a8"))
	var later := _uci_set(logic)
	assert_false(later.has("e1g1"), "Rechte kommen nicht zurück")
	assert_false(later.has("e1c1"), "Rechte kommen nicht zurück (lang)")


func test_rochade_recht_faellt_mit_geschlagenem_turm() -> void:
	var logic := ChessLogic.new()
	assert_true(logic.from_fen("r3k2r/8/8/8/8/8/6b1/R3K2R b KQkq - 0 1"))
	assert_true(logic.play_uci("g2h1"), "Läufer schlägt Turm h1")
	assert_true(logic.play_uci("a1a2"))
	assert_true(logic.play_uci("h1g2"))
	var ucis := _uci_set(logic)
	assert_false(ucis.has("e1g1"), "ohne Turm h1 keine kurze Rochade")


func test_en_passant_nur_sofort() -> void:
	var logic := ChessLogic.new()
	assert_true(logic.from_fen("4k3/2p5/8/1P6/8/8/8/4K3 b - - 0 1"))
	assert_true(logic.play_uci("c7c5"), "Doppelschritt setzt ep-Feld")
	var ucis := _uci_set(logic)
	assert_true(ucis.has("b5c6"), "en passant angeboten")
	assert_true(logic.play_uci("b5c6"))
	assert_eq(logic.piece_at(2, 4), 0, "geschlagener Bauer c5 ist WEG")
	assert_eq(logic.piece_at(2, 5), ChessLogic.PAWN, "eigener Bauer auf c6")
	# Gleiche Stellung, aber ein Wartezug dazwischen → Recht verfällt.
	assert_true(logic.from_fen("4k3/2p5/8/1P6/8/8/8/4K3 b - - 0 1"))
	assert_true(logic.play_uci("c7c5"))
	assert_true(logic.play_uci("e1d1"))
	assert_true(logic.play_uci("e8d8"))
	assert_false(_uci_set(logic).has("b5c6"), "ep verfällt nach einem Zug")


func test_umwandlung_alle_vier_und_schlagend() -> void:
	var logic := ChessLogic.new()
	assert_true(logic.from_fen("6n1/5P2/8/8/8/8/1K6/7k w - - 0 1"))
	var ucis := _uci_set(logic)
	for suffix: String in ["q", "r", "b", "n"]:
		assert_true(ucis.has("f7f8" + suffix), "Umwandlung " + suffix)
		assert_true(ucis.has("f7g8" + suffix), "schlagende Umwandlung " + suffix)
	assert_true(logic.play_uci("f7g8q"))
	assert_eq(logic.piece_at(6, 7), ChessLogic.QUEEN, "Dame steht auf g8")
	assert_eq(logic.to_move, ChessLogic.BLACK)


func test_narrenmatt_als_partie() -> void:
	var logic := ChessLogic.new()
	for uci: String in ["f2f3", "e7e5", "g2g4", "d8h4"]:
		assert_true(logic.play_uci(uci), uci)
	assert_eq(logic.result(), ChessLogic.RESULT_CHECKMATE, "Narrenmatt")
	assert_true(logic.in_check())
	assert_eq(logic.to_move, ChessLogic.WHITE, "Weiß ist matt (am Zug)")
	assert_true(logic.legal_moves().is_empty())


func test_patt_und_grundreihenmatt() -> void:
	var logic := ChessLogic.new()
	assert_true(logic.from_fen("7k/5Q2/6K1/8/8/8/8/8 b - - 0 1"))
	assert_eq(logic.result(), ChessLogic.RESULT_STALEMATE, "klassisches Patt")
	assert_false(logic.in_check())
	assert_true(logic.from_fen("6k1/5ppp/8/8/8/8/8/R5K1 w - - 0 1"))
	assert_true(logic.play_uci("a1a8"))
	assert_eq(logic.result(), ChessLogic.RESULT_CHECKMATE, "Grundreihenmatt")


func test_remis_50_zuege_und_totes_material() -> void:
	var logic := ChessLogic.new()
	assert_true(logic.from_fen("4k3/8/8/8/8/8/8/4KR2 w - - 100 80"))
	assert_eq(logic.result(), ChessLogic.RESULT_DRAW_50, "100 Halbzüge = Remis")
	assert_true(logic.from_fen("4k3/8/8/8/8/8/8/4K3 w - - 0 1"))
	assert_eq(logic.result(), ChessLogic.RESULT_DRAW_MATERIAL, "K vs K")
	assert_true(logic.from_fen("4k3/8/8/8/8/8/8/3NK3 w - - 0 1"))
	assert_eq(logic.result(), ChessLogic.RESULT_DRAW_MATERIAL, "K+S vs K")
	assert_true(logic.from_fen("3bk3/8/8/8/8/8/8/2B1K3 w - - 0 1"))
	assert_eq(logic.result(), ChessLogic.RESULT_DRAW_MATERIAL, "gleichfarbige Läufer")
	assert_true(logic.from_fen("2b1k3/8/8/8/8/8/8/2B1K3 w - - 0 1"))
	assert_eq(logic.result(), ChessLogic.RESULT_RUNNING, "ungleichfarbige Läufer: läuft")
	assert_true(logic.from_fen("4k3/7p/8/8/8/8/8/4K3 w - - 0 1"))
	assert_eq(logic.result(), ChessLogic.RESULT_RUNNING, "Bauer reicht zum Spielen")


func test_remis_dreifache_wiederholung() -> void:
	var logic := ChessLogic.new()
	for cycle in 2:
		for uci: String in ["g1f3", "g8f6", "f3g1", "f6g8"]:
			assert_true(logic.play_uci(uci), uci)
	# Startstellung jetzt zum 3. Mal auf dem Brett (inkl. Anfangsstellung).
	assert_eq(logic.result(), ChessLogic.RESULT_DRAW_REPETITION, "3× dieselbe Stellung")


func test_play_pfad_validiert_und_undo() -> void:
	var logic := ChessLogic.new()
	assert_false(logic.play_uci("e2e5"), "illegaler Zug wird abgelehnt")
	assert_false(logic.play_uci("e7e5"), "Gegner-Figur nicht ziehbar")
	assert_eq(logic.to_fen(), ChessLogic.START_FEN, "abgelehnt = unverändert")
	assert_true(logic.play_uci("e2e4"))
	var after := logic.to_fen()
	assert_true(logic.play_uci("c7c5"))
	assert_true(logic.undo_play(), "Zug zurücknehmen")
	assert_eq(logic.to_fen(), after, "undo stellt FEN wieder her")
	assert_eq(logic.uci_to_move("x9y9"), 0, "Unsinn-UCI = 0")
	assert_eq(ChessLogic.move_to_uci(logic.uci_to_move("g8f6")), "g8f6", "UCI-Roundtrip")


func test_schach_erkennung_und_zugzwang() -> void:
	var logic := ChessLogic.new()
	assert_true(logic.from_fen("4k3/8/8/8/8/8/4q3/4K3 w - - 0 1"))
	assert_true(logic.in_check(), "Dame gibt Schach auf der e-Linie")
	for m in logic.legal_moves():
		logic.make_move(m)
		var still := logic.is_square_attacked(logic.board.find(ChessLogic.KING), ChessLogic.BLACK)
		logic.unmake_move()
		assert_false(still, "kein legaler Zug lässt den König im Schach")


func _uci_set(logic: ChessLogic) -> Dictionary:
	var out: Dictionary = {}
	for m in logic.legal_moves():
		out[ChessLogic.move_to_uci(m)] = true
	return out
