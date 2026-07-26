class_name ChessLogic
extends RefCounted
## Schach — PURE Zug-Logik (Doc C §3.5, BACKLOG-REST): 0x88-Brett mit
## vollständiger Legalität (Rochade, en passant, Umwandlung), Matt/Patt und
## Remis-Erkennung (50-Züge-Regel, dreifache Stellungswiederholung, totes
## Material). Dazu FEN-Import/-Export, UCI-Züge ("e2e4", "a7a8q") und
## perft() für die Standard-Teststellungen. KEINE Godot-Nodes — der Server
## bleibt reines Turn-Relay (wie bei BattleshipLogic), beide Clients rechnen
## dieselben Regeln.
##
## Zug-Kodierung (int): from | to<<7 | promo<<14 | flags<<17.
## make_move/unmake_move sind der schnelle Suchpfad (perft/KI, KEIN
## Wiederholungs-Tracking); play_move/undo_play sind der Partie-Pfad
## (validiert Legalität + zählt Stellungen für die Remis-Regel).

const WHITE := 1
const BLACK := -1

const PAWN := 1
const KNIGHT := 2
const BISHOP := 3
const ROOK := 4
const QUEEN := 5
const KING := 6

const CASTLE_WK := 1
const CASTLE_WQ := 2
const CASTLE_BK := 4
const CASTLE_BQ := 8

const FLAG_EP := 1
const FLAG_CASTLE := 2
const FLAG_DOUBLE := 4

const START_FEN := "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

const RESULT_RUNNING := ""
const RESULT_CHECKMATE := "checkmate"
const RESULT_STALEMATE := "stalemate"
const RESULT_DRAW_50 := "draw_50"
const RESULT_DRAW_REPETITION := "draw_repetition"
const RESULT_DRAW_MATERIAL := "draw_material"

const _FEN_PIECES := "PNBRQK"
const _KNIGHT_OFFSETS: Array[int] = [18, 33, 31, 14, -18, -33, -31, -14]
const _KING_OFFSETS: Array[int] = [1, -1, 16, -16, 15, 17, -15, -17]
const _BISHOP_DIRS: Array[int] = [15, 17, -15, -17]
const _ROOK_DIRS: Array[int] = [1, -1, 16, -16]

var board := PackedInt32Array()
var to_move := WHITE
var castling := 0
var ep_square := -1
var halfmove := 0
var fullmove := 1

var _undo: Array[Dictionary] = []
var _keys: Dictionary = {}
var _played: Array[String] = []
var _king_white := -1
var _king_black := -1
var _castle_masks := PackedInt32Array()


func _init() -> void:
	_castle_masks.resize(128)
	_castle_masks.fill(15)
	_castle_masks[0x04] = 15 - CASTLE_WK - CASTLE_WQ
	_castle_masks[0x00] = 15 - CASTLE_WQ
	_castle_masks[0x07] = 15 - CASTLE_WK
	_castle_masks[0x74] = 15 - CASTLE_BK - CASTLE_BQ
	_castle_masks[0x70] = 15 - CASTLE_BQ
	_castle_masks[0x77] = 15 - CASTLE_BK
	reset()


func reset() -> void:
	from_fen(START_FEN)


## FEN einlesen. false = unbrauchbare FEN (Zustand dann undefiniert lassen).
func from_fen(fen: String) -> bool:
	var parts := fen.strip_edges().split(" ", false)
	if parts.size() < 4:
		return false
	board = PackedInt32Array()
	board.resize(128)
	_king_white = -1
	_king_black = -1
	var ranks := parts[0].split("/")
	if ranks.size() != 8:
		return false
	for rank_idx in 8:
		var rank := 7 - rank_idx
		var file := 0
		for ch in ranks[rank_idx]:
			if ch.is_valid_int():
				file += int(ch)
				continue
			if file > 7:
				return false
			var kind := _FEN_PIECES.find(ch.to_upper()) + 1
			if kind == 0:
				return false
			var color := WHITE if ch == ch.to_upper() else BLACK
			var sq := rank * 16 + file
			board[sq] = kind * color
			if kind == KING:
				if color == WHITE:
					_king_white = sq
				else:
					_king_black = sq
			file += 1
	to_move = WHITE if parts[1] == "w" else BLACK
	castling = 0
	if parts[2].contains("K"):
		castling |= CASTLE_WK
	if parts[2].contains("Q"):
		castling |= CASTLE_WQ
	if parts[2].contains("k"):
		castling |= CASTLE_BK
	if parts[2].contains("q"):
		castling |= CASTLE_BQ
	ep_square = _parse_square(parts[3])
	halfmove = int(parts[4]) if parts.size() > 4 else 0
	fullmove = int(parts[5]) if parts.size() > 5 else 1
	_undo.clear()
	_keys.clear()
	_played.clear()
	var key := _position_key()
	_keys[key] = 1
	return _king_white >= 0 and _king_black >= 0


func to_fen() -> String:
	var rows: Array[String] = []
	for rank_idx in 8:
		var rank := 7 - rank_idx
		var row := ""
		var empty := 0
		for file in 8:
			var piece := board[rank * 16 + file]
			if piece == 0:
				empty += 1
				continue
			if empty > 0:
				row += str(empty)
				empty = 0
			var letter := _FEN_PIECES[absi(piece) - 1]
			row += letter if piece > 0 else letter.to_lower()
		if empty > 0:
			row += str(empty)
		rows.append(row)
	var rights := ""
	if castling & CASTLE_WK != 0:
		rights += "K"
	if castling & CASTLE_WQ != 0:
		rights += "Q"
	if castling & CASTLE_BK != 0:
		rights += "k"
	if castling & CASTLE_BQ != 0:
		rights += "q"
	var ep := "-" if ep_square < 0 else _square_name(ep_square)
	return "%s %s %s %s %d %d" % [
		"/".join(rows),
		"w" if to_move == WHITE else "b",
		rights if not rights.is_empty() else "-",
		ep,
		halfmove,
		fullmove,
	]


## Figur aus UI-Sicht: file 0..7 (a..h), rank 0..7 (1..8).
func piece_at(file: int, rank: int) -> int:
	return board[rank * 16 + file]


static func mv_from(m: int) -> int:
	return m & 127


static func mv_to(m: int) -> int:
	return (m >> 7) & 127


static func mv_promo(m: int) -> int:
	return (m >> 14) & 7


static func move_to_uci(m: int) -> String:
	var uci := _square_name(m & 127) + _square_name((m >> 7) & 127)
	var promo := (m >> 14) & 7
	if promo != 0:
		uci += "nbrq"[promo - 2]
	return uci


## Legalen Zug zur UCI finden; 0 = kein legaler Zug mit dieser Notation.
func uci_to_move(uci: String) -> int:
	var text := uci.strip_edges().to_lower()
	if text.length() < 4:
		return 0
	var from := _parse_square(text.substr(0, 2))
	var to := _parse_square(text.substr(2, 2))
	if from < 0 or to < 0:
		return 0
	var promo := 0
	if text.length() >= 5:
		promo = "nbrq".find(text[4]) + 2
		if promo == 1:
			return 0
	for m in legal_moves():
		if (m & 127) == from and ((m >> 7) & 127) == to and ((m >> 14) & 7) == promo:
			return m
	return 0


## Alle legalen Züge der Seite am Zug.
func legal_moves() -> Array[int]:
	var out: Array[int] = []
	for m in _pseudo_moves():
		make_move(m)
		var king_sq := _king_white if to_move == BLACK else _king_black
		if not is_square_attacked(king_sq, to_move):
			out.append(m)
		unmake_move()
	return out


func legal_moves_from(sq: int) -> Array[int]:
	var out: Array[int] = []
	for m in legal_moves():
		if (m & 127) == sq:
			out.append(m)
	return out


func in_check() -> bool:
	var king_sq := _king_white if to_move == WHITE else _king_black
	return is_square_attacked(king_sq, -to_move)


## Greift `by` (WHITE/BLACK) das Feld an? 0x88-Standardabtastung.
func is_square_attacked(sq: int, by: int) -> bool:
	for d: int in [15, 17]:
		var p := sq - d * by
		if (p & 0x88) == 0 and board[p] == PAWN * by:
			return true
	for d in _KNIGHT_OFFSETS:
		var p := sq + d
		if (p & 0x88) == 0 and board[p] == KNIGHT * by:
			return true
	for d in _KING_OFFSETS:
		var p := sq + d
		if (p & 0x88) == 0 and board[p] == KING * by:
			return true
	for d in _BISHOP_DIRS:
		var p := sq + d
		while (p & 0x88) == 0:
			var piece := board[p]
			if piece != 0:
				if piece == BISHOP * by or piece == QUEEN * by:
					return true
				break
			p += d
	for d in _ROOK_DIRS:
		var p := sq + d
		while (p & 0x88) == 0:
			var piece := board[p]
			if piece != 0:
				if piece == ROOK * by or piece == QUEEN * by:
					return true
				break
			p += d
	return false


## Schneller Suchpfad (perft/KI): Zug muss pseudo-legal sein, KEIN
## Wiederholungs-Tracking. Für Partien play_move benutzen.
func make_move(m: int) -> void:
	var from := m & 127
	var to := (m >> 7) & 127
	var promo := (m >> 14) & 7
	var flags := m >> 17
	var piece := board[from]
	var captured_sq := to
	if flags & FLAG_EP != 0:
		captured_sq = to - 16 * to_move
	var captured := board[captured_sq]
	_undo.append(
		{
			"m": m,
			"captured": captured,
			"captured_sq": captured_sq,
			"castling": castling,
			"ep": ep_square,
			"halfmove": halfmove,
		}
	)
	if captured != 0:
		board[captured_sq] = 0
	board[from] = 0
	board[to] = piece if promo == 0 else promo * to_move
	if flags & FLAG_CASTLE != 0:
		var base := from & 0x70
		if to > from:
			board[base + 5] = board[base + 7]
			board[base + 7] = 0
		else:
			board[base + 3] = board[base]
			board[base] = 0
	if piece == KING * to_move:
		if to_move == WHITE:
			_king_white = to
		else:
			_king_black = to
	ep_square = (from + to) >> 1 if flags & FLAG_DOUBLE != 0 else -1
	castling = castling & _castle_masks[from] & _castle_masks[to]
	halfmove = 0 if captured != 0 or absi(piece) == PAWN else halfmove + 1
	if to_move == BLACK:
		fullmove += 1
	to_move = -to_move


func unmake_move() -> void:
	var u: Dictionary = _undo.pop_back()
	var m: int = u["m"]
	var from := m & 127
	var to := (m >> 7) & 127
	var promo := (m >> 14) & 7
	var flags := m >> 17
	to_move = -to_move
	if to_move == BLACK:
		fullmove -= 1
	var piece := board[to]
	if promo != 0:
		piece = PAWN * to_move
	board[from] = piece
	board[to] = 0
	var captured: int = u["captured"]
	if captured != 0:
		board[u["captured_sq"]] = captured
	if flags & FLAG_CASTLE != 0:
		var base := from & 0x70
		if to > from:
			board[base + 7] = board[base + 5]
			board[base + 5] = 0
		else:
			board[base] = board[base + 3]
			board[base + 3] = 0
	if piece == KING * to_move:
		if to_move == WHITE:
			_king_white = from
		else:
			_king_black = from
	castling = u["castling"]
	ep_square = u["ep"]
	halfmove = u["halfmove"]


## Partie-Pfad: validiert Legalität + zählt die Stellung für die
## Wiederholungs-Remis-Regel. false = illegaler Zug (nichts passiert).
func play_move(m: int) -> bool:
	if not legal_moves().has(m):
		return false
	make_move(m)
	var key := _position_key()
	_keys[key] = int(_keys.get(key, 0)) + 1
	_played.append(key)
	return true


func play_uci(uci: String) -> bool:
	var m := uci_to_move(uci)
	return m != 0 and play_move(m)


## Letzten play_move zurücknehmen (Server hat den Zug abgelehnt o. Ä.).
func undo_play() -> bool:
	if _played.is_empty() or _undo.is_empty():
		return false
	var key: String = _played.pop_back()
	var count := int(_keys.get(key, 0)) - 1
	if count <= 0:
		_keys.erase(key)
	else:
		_keys[key] = count
	unmake_move()
	return true


## Partie-Ergebnis: "" = läuft, sonst checkmate/stalemate/draw_*.
## Bei checkmate hat die Seite verloren, die am Zug ist.
func result() -> String:
	if legal_moves().is_empty():
		return RESULT_CHECKMATE if in_check() else RESULT_STALEMATE
	if halfmove >= 100:
		return RESULT_DRAW_50
	if int(_keys.get(_position_key(), 0)) >= 3:
		return RESULT_DRAW_REPETITION
	if _insufficient_material():
		return RESULT_DRAW_MATERIAL
	return RESULT_RUNNING


## Knotenzähler für die Standard-Teststellungen (Legalitätsbeweis).
func perft(depth: int) -> int:
	if depth <= 0:
		return 1
	var moves := legal_moves()
	if depth == 1:
		return moves.size()
	var count := 0
	for m in moves:
		make_move(m)
		count += perft(depth - 1)
		unmake_move()
	return count


static func _square_name(sq: int) -> String:
	return "%s%d" % [char(97 + (sq & 7)), (sq >> 4) + 1]


static func _parse_square(text: String) -> int:
	if text.length() != 2:
		return -1
	var file := text.unicode_at(0) - 97
	var rank := text.unicode_at(1) - 49
	if file < 0 or file > 7 or rank < 0 or rank > 7:
		return -1
	return rank * 16 + file


static func _encode(from: int, to: int, promo: int, flags: int) -> int:
	return from | to << 7 | promo << 14 | flags << 17


func _pseudo_moves() -> Array[int]:
	var out: Array[int] = []
	for sq in 128:
		if sq & 0x88 != 0:
			continue
		var piece := board[sq]
		if piece == 0 or signi(piece) != to_move:
			continue
		match absi(piece):
			PAWN:
				_pawn_moves(sq, out)
			KNIGHT:
				_leaper_moves(sq, _KNIGHT_OFFSETS, out)
			BISHOP:
				_slider_moves(sq, _BISHOP_DIRS, out)
			ROOK:
				_slider_moves(sq, _ROOK_DIRS, out)
			QUEEN:
				_slider_moves(sq, _KING_OFFSETS, out)
			KING:
				_leaper_moves(sq, _KING_OFFSETS, out)
				_castle_moves(out)
	return out


func _pawn_moves(sq: int, out: Array[int]) -> void:
	var dir := 16 * to_move
	var start_rank := 1 if to_move == WHITE else 6
	var promo_rank := 7 if to_move == WHITE else 0
	var one := sq + dir
	if (one & 0x88) == 0 and board[one] == 0:
		_push_pawn(sq, one, promo_rank, 0, out)
		var two := one + dir
		if (sq >> 4) == start_rank and board[two] == 0:
			out.append(_encode(sq, two, 0, FLAG_DOUBLE))
	for side: int in [dir - 1, dir + 1]:
		var to := sq + side
		if to & 0x88 != 0:
			continue
		if board[to] != 0 and signi(board[to]) != to_move:
			_push_pawn(sq, to, promo_rank, 0, out)
		elif to == ep_square:
			out.append(_encode(sq, to, 0, FLAG_EP))


func _push_pawn(from: int, to: int, promo_rank: int, flags: int, out: Array[int]) -> void:
	if (to >> 4) == promo_rank:
		for promo: int in [QUEEN, ROOK, BISHOP, KNIGHT]:
			out.append(_encode(from, to, promo, flags))
	else:
		out.append(_encode(from, to, 0, flags))


func _leaper_moves(sq: int, offsets: Array[int], out: Array[int]) -> void:
	for d in offsets:
		var to := sq + d
		if to & 0x88 != 0:
			continue
		if board[to] == 0 or signi(board[to]) != to_move:
			out.append(_encode(sq, to, 0, 0))


func _slider_moves(sq: int, dirs: Array[int], out: Array[int]) -> void:
	for d in dirs:
		var to := sq + d
		while (to & 0x88) == 0:
			var piece := board[to]
			if piece == 0:
				out.append(_encode(sq, to, 0, 0))
			else:
				if signi(piece) != to_move:
					out.append(_encode(sq, to, 0, 0))
				break
			to += d


## Rochade: Rechte + freie Felder + König zieht nicht durch Schach.
func _castle_moves(out: Array[int]) -> void:
	var enemy := -to_move
	var base := 0x00 if to_move == WHITE else 0x70
	var king_side := CASTLE_WK if to_move == WHITE else CASTLE_BK
	var queen_side := CASTLE_WQ if to_move == WHITE else CASTLE_BQ
	if (
		castling & king_side != 0
		and board[base + 5] == 0
		and board[base + 6] == 0
		and board[base + 7] == ROOK * to_move
		and not is_square_attacked(base + 4, enemy)
		and not is_square_attacked(base + 5, enemy)
		and not is_square_attacked(base + 6, enemy)
	):
		out.append(_encode(base + 4, base + 6, 0, FLAG_CASTLE))
	if (
		castling & queen_side != 0
		and board[base + 3] == 0
		and board[base + 2] == 0
		and board[base + 1] == 0
		and board[base] == ROOK * to_move
		and not is_square_attacked(base + 4, enemy)
		and not is_square_attacked(base + 3, enemy)
		and not is_square_attacked(base + 2, enemy)
	):
		out.append(_encode(base + 4, base + 2, 0, FLAG_CASTLE))


## Stellungs-Schlüssel für die Wiederholungs-Regel (Brett+Zugrecht+
## Rochade+ep — die FIDE-relevanten Bestandteile).
func _position_key() -> String:
	var cells := PackedStringArray()
	for rank in 8:
		for file in 8:
			cells.append(str(board[rank * 16 + file]))
	return "%s|%d|%d|%d" % [",".join(cells), to_move, castling, ep_square]


## Totes Material: K vs K, K+Leichtfigur vs K, K+L vs K+L (gleiche Feldfarbe).
func _insufficient_material() -> bool:
	var minors: Array[int] = []
	for sq in 128:
		if sq & 0x88 != 0:
			continue
		var kind := absi(board[sq])
		if kind == 0 or kind == KING:
			continue
		if kind == PAWN or kind == ROOK or kind == QUEEN:
			return false
		minors.append(sq)
		if minors.size() > 2:
			return false
	if minors.size() <= 1:
		return true
	var a := minors[0]
	var b := minors[1]
	if absi(board[a]) != BISHOP or absi(board[b]) != BISHOP:
		return false
	if signi(board[a]) == signi(board[b]):
		return false
	return ((a >> 4) + (a & 7)) % 2 == ((b >> 4) + (b & 7)) % 2
