class_name ChessSession
extends Node
## Schach-Session (BACKLOG-REST, Doc C §3.5): Client-Seite des Server-Turn-
## Relays für Schach — exakt der BoardSession-Weg (boardgames.js), aber mit
## ChessLogic als Regelinstanz. Der Server kennt KEINE Schachregeln: ein Zug
## reist als ROOM_MSG kind "SHOT" {n, move:"e2e4"}, der Empfänger bestätigt
## mit "SHOT_RESULT" {n} (Auto-Ack) — dadurch greifen Turn-Ownership,
## n-Zähler, History und Rejoin-Replay des Servers unverändert.
## Weiß = first (der Einladende beginnt, Revanche tauscht die Farben).
## Ergebnis-Erkennung ist Client-Sache (beide rechnen dieselbe ChessLogic);
## das GAME_OVER in die History schreibt der EMPFÄNGER des letzten Zugs
## (nach seinem Ack), Remis = winner "".

signal invite_incoming(data: Dictionary)
signal invite_declined(data: Dictionary)
signal game_started(data: Dictionary)
signal game_resumed(data: Dictionary)
signal opponent_moved(uci: String)
signal opponent_emote(emote_id: String)
signal send_rejected(kind: String, code: String)
signal game_over(winner_code: String, i_won: bool, reason: String)
signal opponent_forfeit(data: Dictionary)
signal rematch_requested_by_opponent
signal rematch_declined
signal peer_connection_changed(down: bool, wait_ms: int)

const GAME_CHESS := "chess"
const REASON_SURRENDER := "surrender"

var room_id := ""
var seed_value := 0
var players: Array[Dictionary] = []
var opponent_code := ""
var opponent_name := ""
var opponent_gooby_name := ""
var my_color := ChessLogic.WHITE

var logic: ChessLogic = null
var finished := false
var winner := ""
var reason := ""
var rematch_mine := false
var rematch_theirs := false
var peer_down := false

var _net: Node = null
var _n := 1
var _awaiting_ack := false
var _sent_kinds: Dictionary = {}


func setup(net_client: Node) -> void:
	_net = net_client
	_net.pushed.connect(_on_push)
	_net.message_received.connect(_on_envelope)
	if _net.has_signal("status_changed"):
		_net.status_changed.connect(_on_net_status_changed)


func is_online() -> bool:
	return _net != null and _net.has_method("is_online") and _net.is_online()


func is_active() -> bool:
	return not room_id.is_empty() and not finished


func my_code() -> String:
	return str(_net.get("friend_code")) if _net != null else ""


func my_turn() -> bool:
	return (
		is_active() and logic != null and logic.to_move == my_color and not _awaiting_ack
	)


func invite(target_code: String) -> Dictionary:
	if not is_online():
		return {"ok": false, "code": "OFFLINE"}
	return await _net.request("BOARD_INVITE", {"target": target_code, "game": GAME_CHESS})


func accept(from_code: String) -> Dictionary:
	if not is_online():
		return {"ok": false, "code": "OFFLINE"}
	var res: Dictionary = await _net.request("BOARD_ACCEPT", {"from": from_code})
	if res["ok"] and res["t"] == "BOARD_START":
		await _on_board_start(res["d"])
	return res


func decline(from_code: String) -> Dictionary:
	if not is_online():
		return {"ok": false, "code": "OFFLINE"}
	return await _net.request("BOARD_DECLINE", {"from": from_code})


## Eigenen Zug (UCI) spielen + relayen. false = nicht dran / illegal.
func send_move(uci: String) -> bool:
	if not my_turn() or logic == null:
		return false
	var m := logic.uci_to_move(uci)
	if m == 0:
		return false
	if not _send_game_msg("SHOT", {"n": _n, "move": ChessLogic.move_to_uci(m)}):
		return false
	logic.play_move(m)
	_awaiting_ack = true
	_check_game_end(true)
	return true


func send_emote(emote_id: String) -> bool:
	if not BoardEmotes.is_valid(emote_id):
		return false
	return _send_game_msg("EMOTE", {"id": emote_id})


## Sauber gehen: bei laufendem Spiel wertet der Server das als Forfeit.
func leave() -> Dictionary:
	if room_id.is_empty():
		return {"ok": true}
	var room := room_id
	_reset()
	if not is_online():
		return {"ok": false, "code": "OFFLINE"}
	return await _net.request("ROOM_LEAVE", {"room": room})


## Explizit aufgeben — Gegner gewinnt sofort, Session bleibt im Raum
## (Revanche direkt möglich).
func surrender() -> bool:
	if not is_active() or opponent_code.is_empty():
		return false
	finished = true
	winner = opponent_code
	reason = REASON_SURRENDER
	_send_game_msg_finished("GAME_OVER", {"winner": winner, "reason": REASON_SURRENDER})
	game_over.emit(winner, false, REASON_SURRENDER)
	return true


## Revanche anfragen (nach GAME_OVER). Startet frisch, sobald BEIDE wollen —
## der Server tauscht first, also auch die Farben.
func request_rematch() -> Dictionary:
	if room_id.is_empty() or not finished:
		return {"ok": false, "code": "NO_GAME", "waiting": false}
	if not is_online():
		return {"ok": false, "code": "OFFLINE", "waiting": false}
	rematch_mine = true
	var res: Dictionary = await _net.request("BOARD_REMATCH", {"room": room_id})
	if not res["ok"]:
		rematch_mine = false
		return {"ok": false, "code": str(res["code"]), "waiting": false}
	if res["t"] == "BOARD_START":
		await _on_board_start(res["d"])
		return {"ok": true, "waiting": false}
	return {"ok": true, "waiting": bool((res["d"] as Dictionary).get("waiting", false))}


func _on_net_status_changed(_status: int) -> void:
	if room_id.is_empty() or not is_online():
		return
	_net.request("ROOM_JOIN", {"room": room_id})


func _send_game_msg(kind: String, body: Dictionary) -> bool:
	if _net == null or not is_active():
		return false
	var seq: int = _net.send("ROOM_MSG", {"room": room_id, "kind": kind, "body": body})
	if seq < 0:
		return false
	_sent_kinds[seq] = kind
	return true


## GAME_OVER darf auch nach finished=true raus (is_active wäre da false).
func _send_game_msg_finished(kind: String, body: Dictionary) -> void:
	if _net != null and not room_id.is_empty():
		_net.send("ROOM_MSG", {"room": room_id, "kind": kind, "body": body})


func _on_push(type: String, data: Dictionary) -> void:
	match type:
		"BOARD_INVITED":
			if str(data.get("game", "")) == GAME_CHESS:
				invite_incoming.emit(data)
		"BOARD_DECLINED":
			invite_declined.emit(data)
		"BOARD_START":
			if str(data.get("game", "")) == GAME_CHESS:
				_on_board_start(data)
		"BOARD_RESUME":
			if data.get("room", "") == room_id:
				_on_board_resume(data)
		"BOARD_FORFEIT":
			if data.get("room", "") == room_id:
				finished = true
				winner = str(data.get("winner", ""))
				reason = "forfeit"
				opponent_forfeit.emit(data)
				game_over.emit(winner, winner == my_code(), reason)
		"BOARD_REMATCH_WAIT":
			if data.get("room", "") == room_id:
				rematch_theirs = true
				rematch_requested_by_opponent.emit()
		"BOARD_REMATCH_DECLINED":
			if data.get("room", "") == room_id:
				rematch_mine = false
				rematch_theirs = false
				rematch_declined.emit()
		"BOARD_PEER_DOWN":
			if data.get("room", "") == room_id:
				peer_down = true
				peer_connection_changed.emit(true, int(data.get("waitMs", 0)))
		"BOARD_PEER_UP":
			if data.get("room", "") == room_id:
				peer_down = false
				peer_connection_changed.emit(false, 0)
		"ROOM_MSG":
			if data.get("room", "") == room_id:
				_on_room_msg(str(data.get("kind", "")), data.get("body", {}))


## ERROR-Antworten auf unsere fire-and-forget-Züge: lokalen Zug zurückrollen.
func _on_envelope(envelope: Dictionary) -> void:
	if str(envelope.get("t", "")) != "ERROR" or not envelope.has("re"):
		return
	var seq := int(envelope["re"])
	if not _sent_kinds.has(seq):
		return
	var kind: String = _sent_kinds[seq]
	_sent_kinds.erase(seq)
	var code := str((envelope.get("d", {}) as Dictionary).get("code", "ERROR"))
	if kind == "SHOT" and _awaiting_ack and logic != null:
		logic.undo_play()
		_awaiting_ack = false
	send_rejected.emit(kind, code)


func _on_board_start(data: Dictionary) -> void:
	room_id = str(data.get("room", ""))
	seed_value = int(data.get("seed", 0))
	finished = false
	winner = ""
	reason = ""
	rematch_mine = false
	rematch_theirs = false
	peer_down = false
	players = []
	for entry: Variant in data.get("players", []):
		if entry is Dictionary:
			players.append(entry)
		if entry is Dictionary and str(entry.get("friendCode", "")) != my_code():
			opponent_code = str(entry.get("friendCode", ""))
			opponent_name = str(entry.get("name", ""))
			opponent_gooby_name = str(entry.get("goobyName", "Gooby"))
	my_color = (
		ChessLogic.WHITE if str(data.get("first", "")) == my_code() else ChessLogic.BLACK
	)
	logic = ChessLogic.new()
	_n = 1
	_awaiting_ack = false
	_sent_kinds.clear()
	if is_online():
		await _net.request("ROOM_JOIN", {"room": room_id})
	game_started.emit(data)


## Rejoin: komplette ROOM_MSG-History auf ein frisches Brett replayen.
## Ein SHOT ohne Ack am Ende: Gegner-Zug → wir acken jetzt; eigener Zug →
## der Gegner ackt bei SEINEM Resume.
func _on_board_resume(data: Dictionary) -> void:
	logic = ChessLogic.new()
	finished = false
	winner = ""
	reason = ""
	var last_shot_from := ""
	var last_shot_n := 0
	var acked := true
	for item: Variant in data.get("history", []):
		if not (item is Dictionary):
			continue
		var kind := str((item as Dictionary).get("kind", ""))
		var body: Variant = (item as Dictionary).get("body", {})
		if not (body is Dictionary):
			continue
		if kind == "SHOT":
			logic.play_uci(str((body as Dictionary).get("move", "")))
			last_shot_from = str((item as Dictionary).get("from", ""))
			last_shot_n = int((body as Dictionary).get("n", 0))
			acked = false
		elif kind == "SHOT_RESULT":
			acked = true
		elif kind == "GAME_OVER":
			finished = true
			winner = str((body as Dictionary).get("winner", ""))
			reason = str((body as Dictionary).get("reason", ""))
	_n = int(data.get("n", 1))
	_awaiting_ack = false
	peer_down = false
	if not acked and last_shot_from != my_code() and not finished:
		_send_game_msg("SHOT_RESULT", {"n": last_shot_n})
		_n = last_shot_n + 1
	elif not acked and last_shot_from == my_code():
		_awaiting_ack = true
	game_resumed.emit(data)


func _on_room_msg(kind: String, body: Variant) -> void:
	if not (body is Dictionary):
		return
	var data: Dictionary = body
	match kind:
		"SHOT":
			_apply_opponent_move(int(data.get("n", 0)), str(data.get("move", "")))
		"SHOT_RESULT":
			if _awaiting_ack:
				_awaiting_ack = false
				_n = int(data.get("n", _n)) + 1
		"EMOTE":
			opponent_emote.emit(str(data.get("id", "")))
		"GAME_OVER":
			if not finished:
				finished = true
				winner = str(data.get("winner", ""))
				reason = str(data.get("reason", ""))
				game_over.emit(winner, winner == my_code(), reason)


## Gegner-Zug anwenden + Auto-Ack (SHOT_RESULT mit gleichem n) senden.
func _apply_opponent_move(n: int, uci: String) -> void:
	if logic == null or finished:
		return
	if not logic.play_uci(uci):
		return
	_send_game_msg("SHOT_RESULT", {"n": n})
	_n = n + 1
	opponent_moved.emit(uci)
	_check_game_end(false)


## Nach jedem angewendeten Zug prüfen: Matt/Patt/Remis? Der EMPFÄNGER
## schreibt das GAME_OVER in die Server-History (sein Ack ging schon raus).
func _check_game_end(i_moved: bool) -> void:
	if logic == null or finished:
		return
	var res := logic.result()
	if res == ChessLogic.RESULT_RUNNING:
		return
	finished = true
	reason = res
	if res == ChessLogic.RESULT_CHECKMATE:
		var winner_color := -logic.to_move
		winner = my_code() if winner_color == my_color else opponent_code
	else:
		winner = ""
	if not i_moved:
		_send_game_msg_finished("GAME_OVER", {"winner": winner, "reason": res})
	game_over.emit(winner, not winner.is_empty() and winner == my_code(), res)


func _reset() -> void:
	room_id = ""
	seed_value = 0
	players = []
	opponent_code = ""
	opponent_name = ""
	opponent_gooby_name = ""
	my_color = ChessLogic.WHITE
	logic = null
	finished = false
	winner = ""
	reason = ""
	rematch_mine = false
	rematch_theirs = false
	peer_down = false
	_n = 1
	_awaiting_ack = false
	_sent_kinds.clear()
