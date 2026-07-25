class_name VisitService
extends Node
## Besuchs-Service (W3c VISIT, Doc C §3.4 / W2c §4.5): kapselt den kompletten
## Besuchs-Lebenszyklus über den W2d-NetClient — Haus-Snapshot-Upload/-Abruf
## per REST, VISIT_REQUEST/ACCEPT/DECLINE/END, ROOM_JOIN und das Live-Relay
## (POS 5 Hz, EMOTE, BUILD_START/BUILD_DELTA). Offline-first: ohne Verbindung
## liefern alle Aufrufe sofort {ok:false, code:"OFFLINE"}, nichts blockiert.
##
## Anbindung per Duck-Typing (setup(net)) — Tests injizieren einen NetClient
## mit FakeWsLink (Muster W2d test_net_client.gd).

signal visit_incoming(data: Dictionary)
signal visit_ready(data: Dictionary)
signal visit_denied(data: Dictionary)
signal visit_ended(data: Dictionary)
signal peer_joined(data: Dictionary)
signal peer_left(data: Dictionary)
signal peer_pos(pos: Vector3, anim: String, room_id: String)
signal peer_emote(emote_id: String)
signal build_warning
signal build_delta_received(delta: Dictionary)

const ROLE_NONE := ""
const ROLE_HOST := "host"
const ROLE_GUEST := "guest"

var room_id := ""
var role := ROLE_NONE
var host_code := ""
var guest_code := ""
var peer_name := ""
var peer_gooby_name := ""
var peer_room_id := ""
var snapshot_rev := 0

## Tests/Integration: REST-Ziel {host, port, tls} statt NetClient-Config.
var rest_override: Dictionary = {}

var _net: Node = null
var _last_pos_ms := -1


func setup(net_client: Node) -> void:
	_net = net_client
	_net.pushed.connect(_on_push)


func net() -> Node:
	return _net


func is_online() -> bool:
	return _net != null and _net.has_method("is_online") and _net.is_online()


func is_active() -> bool:
	return not room_id.is_empty()


func my_code() -> String:
	return str(_net.get("friend_code")) if _net != null else ""


## Eigenes Haus hochladen (PUT /api/house, ≤ 256 KB) — vor VISIT_ACCEPT und
## beim VISIT_END (finale rev, Doc C §3.4 Punkt 5).
func upload_snapshot(gs: Object) -> Dictionary:
	if not is_online():
		return {"ok": false, "code": "OFFLINE"}
	var snapshot := VisitSnapshot.build_from_state(gs)
	var verdict := VisitSnapshot.validate(snapshot)
	if not verdict["ok"]:
		return {"ok": false, "code": str(verdict["reason"])}
	var res := await _rest(HTTPClient.METHOD_PUT, "/api/house", VisitSnapshot.to_json(snapshot))
	if res["ok"]:
		snapshot_rev = int((res["data"] as Dictionary).get("rev", 0))
		return {"ok": true, "rev": snapshot_rev}
	return res


## Haus eines Freundes abrufen (GET /api/house/<code>, nur Freunde).
func fetch_house(friend_code: String) -> Dictionary:
	if not is_online():
		return {"ok": false, "code": "OFFLINE"}
	var res := await _rest(HTTPClient.METHOD_GET, "/api/house/%s" % friend_code, "")
	if not res["ok"]:
		return res
	var data: Dictionary = res["data"]
	var layout: Variant = data.get("layout", {})
	var verdict := VisitSnapshot.validate(layout)
	if not verdict["ok"]:
		return {"ok": false, "code": str(verdict["reason"])}
	return {"ok": true, "rev": int(data.get("rev", 0)), "snapshot": layout}


## Gast: Besuch anfragen. Antwort OK heißt nur „Anfrage zugestellt“ —
## der eigentliche Start kommt als VISIT_READY-Push.
func request_visit(target_code: String) -> Dictionary:
	if not is_online():
		return {"ok": false, "code": "OFFLINE"}
	return await _net.request("VISIT_REQUEST", {"target": target_code})


## Host: Anfrage annehmen (vorher Snapshot hochladen!). VISIT_READY kommt
## an BEIDE (beim Host als Antwort, beim Gast als Push) — _on_visit_ready
## übernimmt Room-Join + Rollen.
func accept_visit(guest: String) -> Dictionary:
	if not is_online():
		return {"ok": false, "code": "OFFLINE"}
	var res: Dictionary = await _net.request("VISIT_ACCEPT", {"guest": guest})
	if res["ok"] and res["t"] == "VISIT_READY":
		await _on_visit_ready(res["d"])
	return res


func decline_visit(guest: String) -> Dictionary:
	if not is_online():
		return {"ok": false, "code": "OFFLINE"}
	return await _net.request("VISIT_DECLINE", {"guest": guest})


## Besuch beenden (beide Seiten dürfen). Der Server schickt VISIT_ENDED an
## alle Mitglieder + räumt den Room — _on_push setzt dann den Zustand zurück.
func end_visit() -> Dictionary:
	if not is_active() or not is_online():
		_reset()
		return {"ok": false, "code": "OFFLINE"}
	return await _net.request("VISIT_END", {"room": room_id})


## Eigene Position ins Relay (fire-and-forget, client-seitig 5 Hz gedrosselt —
## der Server drosselt zusätzlich, W2c §4.4). force=true umgeht den Takt
## (Raumwechsel soll SOFORT sichtbar sein).
func send_pos(world_pos: Vector3, anim: String, my_room_id: String, force := false) -> bool:
	if not is_active():
		return false
	var now := Time.get_ticks_msec()
	if not force and not VisitLogic.should_send_pos(_last_pos_ms, now):
		return false
	_last_pos_ms = now
	_send_room_msg("POS", VisitLogic.pos_payload(world_pos, anim, my_room_id))
	return true


func send_emote(emote_id: String) -> void:
	_send_room_msg("EMOTE", {"id": emote_id})


## Bau-Warnung an beide Seiten (Toast macht die Szene; lokal via Signal).
func send_build_start() -> void:
	_send_room_msg("BUILD_START", {})
	build_warning.emit()


## roomId reist als additives Feld mit (W2c §1: unbekannte Felder sind ok) —
## der Gast wendet Deltas nur auf den passenden Raum an.
func send_build_delta(
	build_room_id: String, op: String, item: String, cell: Vector2i, rot := 0
) -> void:
	_send_room_msg(
		"BUILD_DELTA",
		{"op": op, "item": item, "cell": [cell.x, cell.y], "rot": rot, "roomId": build_room_id}
	)


func _send_room_msg(kind: String, body: Dictionary) -> void:
	if _net != null and is_active():
		_net.send("ROOM_MSG", {"room": room_id, "kind": kind, "body": body})


func _on_push(type: String, data: Dictionary) -> void:
	match type:
		"VISIT_INCOMING":
			visit_incoming.emit(data)
		"VISIT_READY":
			_on_visit_ready(data)
		"VISIT_DENIED":
			visit_denied.emit(data)
		"VISIT_ENDED":
			var payload := data
			_reset()
			visit_ended.emit(payload)
		"ROOM_PEER_JOINED":
			if data.get("room", "") == room_id:
				peer_name = str(data.get("name", ""))
				peer_gooby_name = str(data.get("goobyName", "Gooby"))
				peer_joined.emit(data)
		"ROOM_PEER_LEFT":
			if data.get("room", "") == room_id:
				peer_left.emit(data)
		"ROOM_MSG":
			if data.get("room", "") == room_id:
				_on_room_msg(str(data.get("kind", "")), data.get("body", {}))


func _on_visit_ready(data: Dictionary) -> void:
	room_id = str(data.get("room", ""))
	host_code = str(data.get("host", ""))
	guest_code = str(data.get("guest", ""))
	snapshot_rev = int(data.get("rev", 0))
	role = ROLE_HOST if my_code() == host_code else ROLE_GUEST
	peer_room_id = ""
	_last_pos_ms = -1
	if is_online():
		await _net.request("ROOM_JOIN", {"room": room_id})
	visit_ready.emit(data)


func _on_room_msg(kind: String, body: Variant) -> void:
	match kind:
		"POS":
			var parsed := VisitLogic.parse_pos(body)
			if parsed["ok"]:
				peer_room_id = str(parsed["room_id"])
				peer_pos.emit(parsed["pos"], str(parsed["anim"]), peer_room_id)
		"EMOTE":
			if body is Dictionary:
				peer_emote.emit(str((body as Dictionary).get("id", "")))
		"BUILD_START":
			build_warning.emit()
		"BUILD_DELTA":
			if body is Dictionary:
				build_delta_received.emit(body)


func _reset() -> void:
	room_id = ""
	role = ROLE_NONE
	host_code = ""
	guest_code = ""
	peer_room_id = ""
	_last_pos_ms = -1


## REST-Aufruf mit Bearer-Auth (W2c §5). Eigener HTTPRequest pro Aufruf —
## parallel-sicher und nach dem Await sofort wieder abgeräumt.
func _rest(method: int, path: String, body: String) -> Dictionary:
	var cfg := _rest_config()
	var scheme := "https" if bool(cfg.get("tls", false)) else "http"
	var url := (
		"%s://%s:%d%s" % [scheme, cfg.get("host", "127.0.0.1"), int(cfg.get("port", 8765)), path]
	)
	var identity: Dictionary = _net.identity() if _net.has_method("identity") else {}
	var headers := PackedStringArray(
		[
			(
				"Authorization: Bearer %s:%s"
				% [identity.get("deviceId", ""), identity.get("deviceSecret", "")]
			),
			"Content-Type: application/json",
		]
	)
	var request := HTTPRequest.new()
	add_child(request)
	var err := request.request(url, headers, method, body)
	if err != OK:
		request.queue_free()
		return {"ok": false, "code": "REQUEST_FAILED"}
	var result: Array = await request.request_completed
	request.queue_free()
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "code": "NO_CONNECTION"}
	var parser := JSON.new()
	var text := (result[3] as PackedByteArray).get_string_from_utf8()
	if parser.parse(text) != OK or not (parser.data is Dictionary):
		return {"ok": false, "code": "BAD_RESPONSE"}
	var data: Dictionary = parser.data
	if int(result[1]) >= 400 or not bool(data.get("ok", false)):
		return {"ok": false, "code": str(data.get("code", "HTTP_%d" % int(result[1])))}
	return {"ok": true, "data": data}


## REST-Ziel: Override (Tests) > NetClient-Config-Auflösung (W2b-Contract).
func _rest_config() -> Dictionary:
	if not rest_override.is_empty():
		return rest_override
	if _net != null and _net.has_method("_resolve_net_config"):
		return _net._resolve_net_config()
	return {"host": "127.0.0.1", "port": 8765, "tls": false}
