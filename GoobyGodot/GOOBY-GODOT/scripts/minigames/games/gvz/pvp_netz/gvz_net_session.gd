class_name GvzNetSession
extends Node
## Client-Seite des GvZ-Netz-PvP (G5/P26 — Muster GobnomNetSession/W15,
## serverseitig Kopiervorlage gobnommp.js): Einladung über den Freunde-Flow
## (GVZ_INVITE/_ACCEPT wie GOBNOM_INVITE), danach Start-Handshake (beide
## melden GVZ_START_REQ → Server pusht GVZ_START mit SEINEM Seed und den
## Seiten gooby/zombie), Lockstep-Frames/Hashes als ROOM_MSG-Kinds
## (GP_INPUT/GP_HASH), idempotentes Ergebnis (GVZ_RESULT + ACK). Reines
## Protokoll — die Sim lebt in GvzPvpLockstep, die View in gvz_game.gd.
## Ohne /root/Net bleibt alles passiv (Offline = lokale Kampagne).
## Bewusst OHNE Rejoin-Snapshot (PvP-Matches sind kurz; Abbruch bei
## Verbindungsverlust ist der einfache, faire Weg — s. P26-Bericht).

signal invite_incoming(data: Dictionary)
signal invite_declined(data: Dictionary)
signal session_ready(data: Dictionary)
signal game_started(data: Dictionary)
signal frame_received(body: Dictionary)
signal hash_received(tick: int, hash_text: String)
signal result_confirmed(data: Dictionary)
signal desync_reported(tick: int)
signal peer_connection_changed(down: bool, wait_ms: int)
signal session_aborted(reason: String, by_code: String)
signal online_state_changed(online: bool)

var room_id := ""
var players: Array[Dictionary] = []
var my_side := GvzPvpLockstep.SIDE_GOOBY
var partner_code := ""
var partner_name := ""
var partner_gooby_name := "Gooby"
var input_delay := GvzPvpLockstep.INPUT_DELAY
var hash_every_ticks := GvzPvpLockstep.HASH_TICKS
var seed_value := 0
var running := false
var peer_down := false
## Eigener Start-Wunsch schon raus? (Panel zeigt dann „Warte auf …“.)
var start_requested := false
## Offene Ergebnisse aus dem WELCOME (Crash-Nachlieferung, schon geACKt).
var pending_results: Array[Dictionary] = []

var _net: Node = null


func setup(net_client: Node) -> void:
	_net = net_client
	_net.pushed.connect(_on_push)
	if _net.has_signal("status_changed"):
		_net.status_changed.connect(_on_net_status_changed)
	if _net.has_signal("welcome_received"):
		_net.welcome_received.connect(_on_welcome)


func is_online() -> bool:
	return _net != null and _net.has_method("is_online") and _net.is_online()


func my_code() -> String:
	return str(_net.get("friend_code")) if _net != null else ""


## Gepaart = Session steht (Start-Handshake oder Lauf).
func is_paired() -> bool:
	return not room_id.is_empty()


func is_running() -> bool:
	return is_paired() and running


## Online-Freunde fürs „PvP übers Netz“-Gate (leer wenn offline).
func online_friends() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _net == null or not is_online():
		return out
	var friends: Variant = _net.get("friends")
	if friends == null:
		return out
	for row: Variant in friends.get("friends") as Array:
		if row is Dictionary and (row as Dictionary).get("online", false) == true:
			out.append(row)
	return out


## ── Einladung / Beitritt (Freunde-Flow wie GOB-NOM/Battleship) ────────────


func invite(target_code: String) -> Dictionary:
	if not is_online():
		return {"ok": false, "code": "OFFLINE"}
	return await _net.request("GVZ_INVITE", {"target": target_code})


func accept(from_code: String) -> Dictionary:
	if not is_online():
		return {"ok": false, "code": "OFFLINE"}
	var res: Dictionary = await _net.request("GVZ_ACCEPT", {"from": from_code})
	if res["ok"] and res["t"] == "GVZ_READY":
		await _on_ready_payload(res["d"])
	return res


func decline(from_code: String) -> Dictionary:
	if not is_online():
		return {"ok": false, "code": "OFFLINE"}
	return await _net.request("GVZ_DECLINE", {"from": from_code})


## Start bestätigen (beide bereit → Server pusht GVZ_START mit Seed).
func request_start() -> Dictionary:
	if not is_online() or room_id.is_empty():
		return {"ok": false, "code": "OFFLINE"}
	start_requested = true
	return await _net.request("GVZ_START_REQ", {"room": room_id})


## ── Lockstep-Kanäle (fire-and-forget wie GN_INPUT/GN_HASH) ────────────────


func send_frame(frame: Dictionary) -> void:
	_send_room_msg("GP_INPUT", frame)


func send_hash(tick: int, hash_text: String) -> void:
	_send_room_msg("GP_HASH", {"t": tick, "h": hash_text})


## ── Ergebnis (idempotent) + Verlassen ─────────────────────────────────────


func report_result(match_winner: String, tick: int) -> Dictionary:
	if not is_online() or room_id.is_empty():
		return {"ok": false, "code": "OFFLINE"}
	return await _net.request("GVZ_RESULT", {"room": room_id, "winner": match_winner, "tick": tick})


func ack_result(reward_id: String) -> void:
	if _net != null and is_online():
		_net.send("GVZ_RESULT_ACK", {"rewardId": reward_id})


## Sauber gehen: der Server bricht die Session für den Partner ab. Danach
## ist die Session wieder frei für neue Herausforderungen.
func leave() -> void:
	if room_id.is_empty():
		return
	var room := room_id
	_reset()
	if _net != null and is_online():
		_net.send("ROOM_LEAVE", {"room": room})


## ── Push-Verarbeitung ─────────────────────────────────────────────────────


func _on_push(type: String, data: Dictionary) -> void:
	match type:
		"GVZ_INVITED":
			invite_incoming.emit(data)
		"GVZ_DECLINED":
			invite_declined.emit(data)
		"GVZ_READY":
			_on_ready_payload(data)
		"GVZ_START":
			if data.get("room", "") == room_id:
				_on_start(data)
		"GVZ_PEER_DOWN":
			if data.get("room", "") == room_id:
				peer_down = true
				peer_connection_changed.emit(true, int(data.get("waitMs", 0)))
		"GVZ_PEER_UP":
			if data.get("room", "") == room_id:
				peer_down = false
				peer_connection_changed.emit(false, 0)
		"GVZ_DESYNC":
			if data.get("room", "") == room_id:
				running = false
				desync_reported.emit(int(data.get("tick", -1)))
		"GVZ_ABORTED":
			if data.get("room", "") == room_id:
				var reason := str(data.get("reason", ""))
				var by := str(data.get("by", ""))
				_reset()
				session_aborted.emit(reason, by)
		"GVZ_RESULT":
			if data.get("room", "") == room_id:
				running = false
				result_confirmed.emit(data)
				ack_result(str(data.get("rewardId", "")))
		"ROOM_MSG":
			if data.get("room", "") == room_id:
				_on_room_msg(str(data.get("kind", "")), data.get("body", {}))


func _on_room_msg(kind: String, body: Variant) -> void:
	if not (body is Dictionary):
		return
	var data: Dictionary = body
	match kind:
		"GP_INPUT":
			frame_received.emit(data)
		"GP_HASH":
			hash_received.emit(int(data.get("t", -1)), str(data.get("h", "")))


func _on_ready_payload(data: Dictionary) -> void:
	room_id = str(data.get("room", ""))
	input_delay = int(data.get("inputDelay", GvzPvpLockstep.INPUT_DELAY))
	hash_every_ticks = int(data.get("hashEveryTicks", GvzPvpLockstep.HASH_TICKS))
	running = false
	peer_down = false
	start_requested = false
	_apply_players(data.get("players", []))
	if is_online():
		await _net.request("ROOM_JOIN", {"room": room_id})
	session_ready.emit(data)


func _on_start(data: Dictionary) -> void:
	seed_value = int(data.get("seed", 0))
	input_delay = int(data.get("inputDelay", input_delay))
	hash_every_ticks = int(data.get("hashEveryTicks", hash_every_ticks))
	_apply_players(data.get("players", players))
	running = true
	peer_down = false
	start_requested = false
	game_started.emit(data)


func _apply_players(rows: Variant) -> void:
	players = []
	if not (rows is Array):
		return
	for entry: Variant in rows as Array:
		if not (entry is Dictionary):
			continue
		var row: Dictionary = entry
		players.append(row)
		if str(row.get("friendCode", "")) == my_code():
			my_side = str(row.get("side", GvzPvpLockstep.SIDE_GOOBY))
		else:
			partner_code = str(row.get("friendCode", ""))
			partner_name = str(row.get("name", "?"))
			partner_gooby_name = str(row.get("goobyName", "Gooby"))


## Wiederverbindung: zurück in den Raum melden — der Server pusht dem
## Partner GVZ_PEER_UP (ohne Snapshot; ein laufendes Match bricht ab).
func _on_net_status_changed(_status: int) -> void:
	online_state_changed.emit(is_online())
	if room_id.is_empty() or not is_online():
		return
	_net.request("ROOM_JOIN", {"room": room_id})


## Crash-Nachlieferung: offene Ergebnisse aus dem WELCOME ziehen + ACKen.
func _on_welcome(data: Dictionary) -> void:
	var pending: Variant = data.get("gvzPending")
	if not (pending is Array):
		return
	for entry: Variant in pending as Array:
		if not (entry is Dictionary):
			continue
		var row: Dictionary = entry
		pending_results.append(row)
		result_confirmed.emit(row)
		ack_result(str(row.get("rewardId", "")))


func _send_room_msg(kind: String, body: Dictionary) -> void:
	if _net == null or room_id.is_empty() or not is_online():
		return
	_net.send("ROOM_MSG", {"room": room_id, "kind": kind, "body": body})


func _reset() -> void:
	room_id = ""
	players = []
	partner_code = ""
	partner_name = ""
	partner_gooby_name = "Gooby"
	seed_value = 0
	running = false
	peer_down = false
	start_requested = false
