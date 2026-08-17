class_name ChessAi
extends RefCounted
## Einzelspieler-Gegner für Schach (Doc C §3.5, BACKLOG-REST): Negamax mit
## Alpha-Beta über der PUREN ChessLogic — Materialbewertung + kleine
## Zentrumsboni. 3 Stärken:
##   1 = „Gemütlich"  — 1 Halbzug + kräftiges Bewertungsrauschen (patzt).
##   2 = „Munter"     — 2 Halbzüge, findet Matt in 1 und hängende Figuren.
##   3 = „Knifflig"   — 3 Halbzüge + Schlagzug-Ruhesuche, findet Matt in 2.
## Deterministisch pro Seed (GoobyRng) — gleiche Stellung + gleicher Seed
## ⇒ gleicher Zug (Testbarkeit). Läuft komplett auf make/unmake, die
## übergebene Logik ist danach unverändert.

const MATE_SCORE := 100000

const _DEPTH_BY_STRENGTH: Array[int] = [1, 1, 2, 3]
const _NOISE_BY_STRENGTH: Array[int] = [60, 60, 0, 0]
const _QUIESCENCE_BY_STRENGTH: Array[int] = [0, 0, 0, 4]
const _PIECE_VALUES: Array[int] = [0, 100, 320, 330, 500, 900, 0]
const _CENTER_BONUS: Array[int] = [0, 1, 2, 3, 3, 2, 1, 0]

var _rng: GoobyRng
var _noise := 0
var _quiescence := 0


func _init(seed_value: int = 1) -> void:
	_rng = GoobyRng.new(seed_value)


## Besten Zug für die Seite am Zug wählen; 0 = kein legaler Zug (Matt/Patt).
func pick_move(logic: ChessLogic, strength: int) -> int:
	var level := clampi(strength, 1, 3)
	var depth := _DEPTH_BY_STRENGTH[level]
	_noise = _NOISE_BY_STRENGTH[level]
	_quiescence = _QUIESCENCE_BY_STRENGTH[level]
	var moves := _ordered_moves(logic)
	if moves.is_empty():
		return 0
	var best_move := 0
	var best_score := -MATE_SCORE * 2
	for m in moves:
		logic.make_move(m)
		var score := -_negamax(logic, depth - 1, -MATE_SCORE * 2, -best_score)
		logic.unmake_move()
		if _noise > 0:
			score += int(_rng.next() * float(_noise * 2)) - _noise
		if score > best_score or (score == best_score and _rng.next() < 0.5):
			best_score = score
			best_move = m
	return best_move


## Materialbilanz in Centipawns aus Sicht der Seite am Zug (fürs HUD).
func evaluate(logic: ChessLogic) -> int:
	var score := 0
	for sq in 128:
		if sq & 0x88 != 0:
			continue
		var piece: int = logic.board[sq]
		if piece == 0:
			continue
		var kind := absi(piece)
		var value := _PIECE_VALUES[kind]
		if kind == ChessLogic.PAWN or kind == ChessLogic.KNIGHT:
			value += _CENTER_BONUS[sq & 7] + _CENTER_BONUS[sq >> 4]
		score += value if piece > 0 else -value
	return score * logic.to_move


func _negamax(logic: ChessLogic, depth: int, alpha: int, beta: int) -> int:
	var moves := _ordered_moves(logic)
	if moves.is_empty():
		return -MATE_SCORE - depth if logic.in_check() else 0
	if depth <= 0:
		if _quiescence > 0:
			return _quiesce(logic, _quiescence, alpha, beta)
		return evaluate(logic)
	var best := -MATE_SCORE * 2
	for m in moves:
		logic.make_move(m)
		var score := -_negamax(logic, depth - 1, -beta, -maxi(alpha, best))
		logic.unmake_move()
		if score > best:
			best = score
			if best >= beta:
				break
	return best


## Ruhesuche nur über Schlagzüge — verhindert Horizont-Patzer der Stufe 3.
func _quiesce(logic: ChessLogic, depth: int, alpha: int, beta: int) -> int:
	var stand := evaluate(logic)
	if depth <= 0 or stand >= beta:
		return stand
	var best := maxi(stand, alpha)
	for m in logic.legal_moves():
		if not _is_capture(logic, m):
			continue
		logic.make_move(m)
		var score := -_quiesce(logic, depth - 1, -beta, -best)
		logic.unmake_move()
		if score > best:
			best = score
			if best >= beta:
				break
	return best


## Schlagzüge zuerst (Opfer wertvoll vor Angreifer billig) — bessere Schnitte.
func _ordered_moves(logic: ChessLogic) -> Array[int]:
	var moves := logic.legal_moves()
	var scored: Array[Vector2i] = []
	for i in moves.size():
		var m := moves[i]
		var target: int = logic.board[ChessLogic.mv_to(m)]
		var order := 0
		if target != 0 or (m >> 17) & ChessLogic.FLAG_EP != 0:
			var victim := _PIECE_VALUES[absi(target)] if target != 0 else 100
			var attacker: int = _PIECE_VALUES[absi(logic.board[ChessLogic.mv_from(m)])]
			order = 10000 + victim * 10 - attacker
		if ChessLogic.mv_promo(m) != 0:
			order += 9000
		scored.append(Vector2i(-order, i))
	scored.sort()
	var out: Array[int] = []
	for entry in scored:
		out.append(moves[entry.y])
	return out


func _is_capture(logic: ChessLogic, m: int) -> bool:
	return logic.board[ChessLogic.mv_to(m)] != 0 or (m >> 17) & ChessLogic.FLAG_EP != 0
