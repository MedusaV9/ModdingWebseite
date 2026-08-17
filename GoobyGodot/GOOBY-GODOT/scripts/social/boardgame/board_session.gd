class_name BoardSession
extends Node
## Brettspiel-Session (W3c VISIT, W2c §4.6): Client-Seite des Server-Turn-
## Relays für Schiffe versenken. Spiegelt die Server-Zustandsmaschine aus
## boardgames.js (Turn-Ownership, n exakt, Runde = exchanges/2) mit
## BattleshipLogic.Turn und hält eigenes Brett (BattleshipLogic) + Gegner-
## Sicht (Tracker) + Tomaten-Limit (TomatoTracker) zusammen.
##
## Fehler auf fire-and-forget-ROOM_MSGs (NOT_YOUR_TURN, TOMATO_LIMIT, …)
## kommen als ERROR mit re — wir merken uns die seq jeder gesendeten
## Spiel-Message und hören auf message_received (kein blockierendes await).

signal invite_incoming(data: Dictionary)
signal invite_declined(data: Dictionary)
signal game_started(data: Dictionary)
signal game_resumed(data: Dictionary)
signal opponent_shot(n: int, cell: Vector2i, result: Dictionary)
signal shot_result(n: int, cell: Vector2i, hit: bool, sunk: bool)
signal opponent_emote(emote_id: String)
signal tomato_incoming
signal tomato_rejected(code: String)
signal send_rejected(kind: String, code: String)
signal game_over(winner_code: String, i_won: bool)
signal opponent_forfeit(data: Dictionary)
signal rematch_requested_by_opponent
signal rematch_declined
signal peer_connection_changed(down: bool, wait_ms: int)

const GAME_BATTLESHIP := "battleship"

var room_id := ""
var game := ""
var seed_value := 0
var players: Array[Dictionary] = []
var opponent_code := ""
var opponent_name := ""
var opponent_gooby_name := ""

var board: BattleshipLogic = null
var tracker: BattleshipLogic.Tracker = null
var turn: BattleshipLogic.Turn = null
var tomatoes := BoardEmotes.TomatoTracker.new()
var finished := false
var winner := ""
## FIX-6 Revanche-Zustand (nach GAME_OVER): eigener/gegnerischer Wunsch.
var rematch_mine := false
var rematch_theirs := false
## FIX-6: Gegner gerade getrennt? (BOARD_PEER_DOWN bis _UP/RESUME)
var peer_down := false

var _net: Node = null
var _pending_shot := Vector2i(-1, -1)
var _sent_kinds: Dictionary = {}  # seq -> kind (Fehler-Korrelation)


func setup(net_client: Node) -> void:
	_net = net_client
	_net.pushed.connect(_on_push)
	_net.message_received.connect(_on_envelope)
	if _net.has_signal("status_changed"):
		_net.status_changed.connect(_on_net_status_changed)


## FIX-6 Wiederverbindung: sobald der Client wieder online ist, automatisch
## zurück in den laufenden Raum — der Server antwortet mit BOARD_RESUME
## (History-Replay, _on_board_resume) und pusht dem Gegner BOARD_PEER_UP.
## Ohne diesen Rejoin lief das 120-s-Forfeit-Fenster einfach ab.
func _on_net_status_changed(_status: int) -> void:
	if room_id.is_empty() or not is_online():
		return
	_net.request("ROOM_JOIN", {"room": room_id})


func is_online() -> bool:
	return _net != null and _net.has_method("is_online") and _net.is_online()


func is_active() -> bool:
	return not room_id.is_empty() and not finished


func my_code() -> String:
	return str(_net.get("friend_code")) if _net != null else ""


func my_turn() -> bool:
	return turn != null and turn.can_shoot(my_code())


## Deterministischer Flotten-Seed pro Spieler: Server-Seed + FriendCode-Hash
## — beide Geräte können BEIDE Flotten reproduzieren (Integrationstests,
## Rejoin-Replay).
static func fleet_seed(server_seed: int, code: String) -> int:
	return (server_seed + code.hash()) & 0x7FFFFFFF


func invite(target_code: String) -> Dictionary:
	if not is_online():
		return {"ok": false, "code": "OFFLINE"}
	return await _net.request("BOARD_INVITE", {"target": target_code, "game": GAME_BATTLESHIP})


## Annahme: BOARD_START kommt als ANTWORT (re) — direkt verarbeiten.
## Der Einladende bekommt BOARD_START als Push (_on_push).
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


## Eigene Flotte setzen (Standard: deterministisch aus dem Server-Seed).
func set_fleet(fleet: Array) -> bool:
	if board == null:
		board = BattleshipLogic.new()
	return board.setup(fleet)


func default_fleet() -> Array[Dictionary]:
	return BattleshipLogic.auto_fleet(fleet_seed(seed_value, my_code()))


## Schuss aufs Gegner-Brett. false = nicht dran / Zelle schon beschossen /
## kein Spiel. Ergebnis kommt asynchron als shot_result-Signal.
func shoot(cell: Vector2i) -> bool:
	if not is_active() or turn == null or not turn.can_shoot(my_code()):
		return false
	if tracker == null or not tracker.is_new_target(cell):
		return false
	var body := {"n": turn.n, "cell": BattleshipLogic.cell_to_ref(cell)}
	if not _send_game_msg("SHOT", body):
		return false
	_pending_shot = cell
	turn.on_shot()
	return true


func send_emote(emote_id: String) -> bool:
	if not BoardEmotes.is_valid(emote_id):
		return false
	return _send_game_msg("EMOTE", {"id": emote_id})


## Tomate (1×/Runde — Client-Check spiegelt nur die Server-Regel).
func throw_tomato() -> bool:
	if not is_active() or turn == null:
		return false
	if not tomatoes.can_throw(turn.round_index()):
		return false
	if not _send_game_msg("TOMATO", {}):
		return false
	tomatoes.mark_thrown(turn.round_index())
	return true


## Sauber gehen: bei laufendem Spiel wertet der Server das als Forfeit für
## den Gegner (gewollt). Nach GAME_OVER ist es nur Cleanup.
func leave() -> Dictionary:
	if room_id.is_empty():
		return {"ok": true}
	var room := room_id
	_reset()
	if not is_online():
		return {"ok": false, "code": "OFFLINE"}
	return await _net.request("ROOM_LEAVE", {"room": room})


## FIX-6 Aufgeben: EXPLIZITE Kapitulation mitten im Spiel — der Gegner
## gewinnt sofort (GAME_OVER mit seinem Code läuft durch die Server-History,
## Rejoin-Replays sehen es also auch). Anders als leave() bleibt die Session
## im Raum → Revanche ist direkt möglich. true = Aufgabe verschickt.
func surrender() -> bool:
	if not is_active() or opponent_code.is_empty():
		return false
	finished = true
	winner = opponent_code
	_send_game_msg_finished("GAME_OVER", {"winner": winner})
	game_over.emit(winner, false)
	return true


## FIX-6 Revanche anfragen (nach GAME_OVER, solange beide im Raum sind).
## Server startet ein frisches Spiel, sobald BEIDE wollen (BOARD_START).
## {"ok", "waiting": bool} — waiting=true heißt „der Gegner muss noch“.
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
		# Beide wollten schon → Antwort IST der Start (wie bei accept()).
		await _on_board_start(res["d"])
		return {"ok": true, "waiting": false}
	return {"ok": true, "waiting": bool((res["d"] as Dictionary).get("waiting", false))}


func _send_game_msg(kind: String, body: Dictionary) -> bool:
	if _net == null or not is_active():
		return false
	var seq: int = _net.send("ROOM_MSG", {"room": room_id, "kind": kind, "body": body})
	if seq < 0:
		return false
	_sent_kinds[seq] = kind
	return true


func _on_push(type: String, data: Dictionary) -> void:
	match type:
		"BOARD_INVITED":
			# Andere Spiele (Schach → ChessSession) laufen an dieser Session vorbei.
			if str(data.get("game", GAME_BATTLESHIP)) == GAME_BATTLESHIP:
				invite_incoming.emit(data)
		"BOARD_DECLINED":
			invite_declined.emit(data)
		"BOARD_START":
			if str(data.get("game", GAME_BATTLESHIP)) == GAME_BATTLESHIP:
				_on_board_start(data)
		"BOARD_RESUME":
			if data.get("room", "") == room_id:
				_on_board_resume(data)
		"BOARD_FORFEIT":
			if data.get("room", "") == room_id:
				finished = true
				winner = str(data.get("winner", ""))
				opponent_forfeit.emit(data)
				game_over.emit(winner, winner == my_code())
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
				_on_room_msg(str(data.get("kind", "")), data.get("body", {}), data.get("from", {}))


## ERROR-Antworten auf unsere fire-and-forget-Spielzüge abfangen.
func _on_envelope(envelope: Dictionary) -> void:
	if str(envelope.get("t", "")) != "ERROR" or not envelope.has("re"):
		return
	var seq := int(envelope["re"])
	if not _sent_kinds.has(seq):
		return
	var kind: String = _sent_kinds[seq]
	_sent_kinds.erase(seq)
	var code := str((envelope.get("d", {}) as Dictionary).get("code", "ERROR"))
	if kind == "SHOT":
		# Server hat den Schuss abgelehnt → lokalen Spiegel zurückdrehen.
		_pending_shot = Vector2i(-1, -1)
		if turn != null and turn.phase == "result":
			turn.phase = "shot"
	if kind == "TOMATO":
		tomatoes.reset()
		tomato_rejected.emit(code)
	send_rejected.emit(kind, code)


func _on_board_start(data: Dictionary) -> void:
	room_id = str(data.get("room", ""))
	game = str(data.get("game", GAME_BATTLESHIP))
	seed_value = int(data.get("seed", 0))
	finished = false
	winner = ""
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
	var codes: Array[String] = []
	for entry in players:
		codes.append(str(entry.get("friendCode", "")))
	turn = BattleshipLogic.Turn.new(str(data.get("first", "")), codes)
	board = BattleshipLogic.new()
	tracker = BattleshipLogic.Tracker.new()
	tomatoes.reset()
	_pending_shot = Vector2i(-1, -1)
	_sent_kinds.clear()
	if is_online():
		await _net.request("ROOM_JOIN", {"room": room_id})
	game_started.emit(data)


## Rejoin: Server liefert die komplette ROOM_MSG-History. Flotten sind
## deterministisch (fleet_seed) → beide Bretter aus der History replayen.
func _on_board_resume(data: Dictionary) -> void:
	board = BattleshipLogic.new()
	board.setup(default_fleet())
	tracker = BattleshipLogic.Tracker.new()
	var codes: Array[String] = []
	for entry in players:
		codes.append(str(entry.get("friendCode", "")))
	var first := ""
	for entry in players:
		first = str(entry.get("friendCode", ""))
		break
	turn = BattleshipLogic.Turn.new(first, codes)
	var pending := Vector2i(-1, -1)
	var pending_from := ""
	for item: Variant in data.get("history", []):
		if not (item is Dictionary):
			continue
		var kind := str((item as Dictionary).get("kind", ""))
		var body: Variant = (item as Dictionary).get("body", {})
		var from := str((item as Dictionary).get("from", ""))
		if kind == "SHOT" and body is Dictionary:
			pending = BattleshipLogic.ref_to_cell(str((body as Dictionary).get("cell", "")))
			pending_from = from
			turn.turn_code = from
			turn.on_shot()
		elif kind == "SHOT_RESULT" and body is Dictionary:
			if pending_from == my_code():
				tracker.record(
					pending,
					bool((body as Dictionary).get("hit", false)),
					bool((body as Dictionary).get("sunk", false))
				)
			elif BattleshipLogic.in_bounds(pending):
				board.receive_shot(pending)
			turn.on_result()
		elif kind == "GAME_OVER" and body is Dictionary:
			finished = true
			winner = str((body as Dictionary).get("winner", ""))
	# Server-Zustand ist die Autorität für turn/n.
	turn.turn_code = str(data.get("turn", turn.turn_code))
	turn.n = int(data.get("n", turn.n))
	turn.phase = "shot"
	_pending_shot = Vector2i(-1, -1)
	peer_down = false
	game_resumed.emit(data)


func _on_room_msg(kind: String, body: Variant, _from: Variant) -> void:
	if not (body is Dictionary):
		return
	var data: Dictionary = body
	match kind:
		"SHOT":
			_answer_shot(int(data.get("n", 0)), str(data.get("cell", "")))
		"SHOT_RESULT":
			_apply_shot_result(data)
		"EMOTE":
			opponent_emote.emit(str(data.get("id", "")))
		"TOMATO":
			tomato_incoming.emit()
		"GAME_OVER":
			if not finished:
				finished = true
				winner = str(data.get("winner", ""))
				game_over.emit(winner, winner == my_code())


## Gegner hat geschossen → EIGENES Brett auswerten + SHOT_RESULT antworten
## (der Beschossene antwortet, gleiches n — W2c §4.6).
func _answer_shot(n: int, cell_ref: String) -> void:
	if board == null or turn == null:
		return
	var cell := BattleshipLogic.ref_to_cell(cell_ref)
	turn.on_shot()
	var result := board.receive_shot(cell)
	_send_game_msg(
		"SHOT_RESULT", {"n": n, "hit": bool(result["hit"]), "sunk": bool(result["sunk"])}
	)
	turn.on_result()
	opponent_shot.emit(n, cell, result)
	if bool(result["all_sunk"]):
		finished = true
		winner = opponent_code
		game_over.emit(winner, false)


## Antwort auf UNSEREN Schuss.
func _apply_shot_result(data: Dictionary) -> void:
	if tracker == null or turn == null or not BattleshipLogic.in_bounds(_pending_shot):
		return
	var cell := _pending_shot
	_pending_shot = Vector2i(-1, -1)
	var hit := bool(data.get("hit", false))
	var sunk := bool(data.get("sunk", false))
	tracker.record(cell, hit, sunk)
	turn.on_result()
	shot_result.emit(int(data.get("n", 0)), cell, hit, sunk)
	if tracker.has_won():
		finished = true
		winner = my_code()
		_send_game_msg_finished("GAME_OVER", {"winner": winner})
		game_over.emit(winner, true)


## GAME_OVER darf auch nach finished=true raus (is_active wäre da false).
func _send_game_msg_finished(kind: String, body: Dictionary) -> void:
	if _net != null and not room_id.is_empty():
		_net.send("ROOM_MSG", {"room": room_id, "kind": kind, "body": body})


func _reset() -> void:
	room_id = ""
	game = ""
	seed_value = 0
	players = []
	opponent_code = ""
	opponent_name = ""
	opponent_gooby_name = ""
	board = null
	tracker = null
	turn = null
	finished = false
	winner = ""
	rematch_mine = false
	rematch_theirs = false
	peer_down = false
	_pending_shot = Vector2i(-1, -1)
	_sent_kinds.clear()
	tomatoes.reset()
