class_name RanchMultiplayerService
extends Node
## Ranch-Multiplayer-Service (RW-6, RANCH-DLC-IDEAS-4 §2): kapselt den
## kompletten MP-Lebenszyklus über den W2d-NetClient — Einladung → Lobby →
## Countdown → Lauf → Ergebnis → Revanche für Besuch/Ausritt/Rennen/Fangen/
## Parcours, das 10-Hz-Pose-Relay (MG_POSE/MG_PEER_POSE), Reaktions-Relay
## (Herz/Geste/Folge-mir/Entdeckung) und REST für Ranch-Metadaten,
## Bestenlisten und Geister. Offline-first: ohne Verbindung liefern alle
## Aufrufe sofort {ok:false, code:"OFFLINE"}, nichts blockiert je das Spiel.
##
## Anbindung per Duck-Typing (setup(net)) — Tests injizieren einen NetClient
## mit FakeWsLink (Muster VisitService / test_social_visit_service.gd).

signal invited(data: Dictionary)
signal invite_declined(data: Dictionary)
signal session_ready(data: Dictionary)
signal session_ended(data: Dictionary)
signal lobby_updated(data: Dictionary)
signal match_started(data: Dictionary)
signal state_updated(data: Dictionary)
signal result_received(data: Dictionary)
signal snapshot_received(data: Dictionary)
signal peer_pose(from_code: String, pose: Dictionary)
signal peer_down(data: Dictionary)
signal peer_up(data: Dictionary)
signal peer_joined(data: Dictionary)
signal peer_left(data: Dictionary)
signal reaction_received(kind: String, from_code: String, body: Dictionary)
signal rematch_wait(data: Dictionary)
signal rematch_declined(data: Dictionary)

## 10 Hz Pose-Takt (Doc §2.1/§2.4 — Server-Budget: 12/s + Burst).
const POSE_INTERVAL_MS := 100
## Reaktions-Kinds im ROOM_MSG-Relay (Gast-Gesten sind rein kosmetisch).
const REAKTIONEN: Array[String] = ["HERZ", "GESTE", "FOLGE_MIR", "ENTDECKUNG"]

var room_id := ""
var mode := ""
var kurs := ""
var host_code := ""
var players: Array = []
var phase := ""
var seed := 0
var start_at_ms := 0
var ends_at_ms := 0
var server_offset_ms := 0
var it_code := ""
var pending_results: Array = []

## REST-Endpunkte (Ranch-Metadaten/Score/Bestenliste/Geist) — s. RmpRest.
var rest: RmpRest
## Dev-/Testsitzung: Läufe werden serverseitig unranked markiert.
var dev_session := false

var _net: Node = null
var _last_pose_ms := -1
var _pose_seq := 0


func _init() -> void:
	rest = RmpRest.new()
	rest.name = "Rest"
	add_child(rest)
	rest.setup(self)


func setup(net_client: Node) -> void:
	_net = net_client
	_net.pushed.connect(_on_push)
	_net.welcome_received.connect(_on_welcome)


func net() -> Node:
	return _net


func is_online() -> bool:
	return _net != null and _net.has_method("is_online") and _net.is_online()


func is_active() -> bool:
	return not room_id.is_empty()


func my_code() -> String:
	return str(_net.get("friend_code")) if _net != null else ""


## Serverzeit-Schätzung (Offset aus MG_START/MG_SNAPSHOT serverNow).
func server_now_ms() -> int:
	return _now_ms() + server_offset_ms


## Countdown-Rest bis zum Startschuss (<= 0 heißt: läuft).
func countdown_ms() -> int:
	return start_at_ms - server_now_ms()


## ------------------------------------------------ Einladung → Session


## Freund einladen. mode: besuch|ausritt|rennen|fangen|parcours;
## kurs "" = Server-Standardkurs. Start kommt als RANCH_READY-Push.
func invite(target_code: String, game_mode: String, kurs_id := "") -> Dictionary:
	if not is_online():
		return {"ok": false, "code": "OFFLINE"}
	return await _net.request(
		"RANCH_INVITE", {"target": target_code, "mode": game_mode, "kurs": kurs_id}
	)


func accept(from_code: String) -> Dictionary:
	if not is_online():
		return {"ok": false, "code": "OFFLINE"}
	var res: Dictionary = await _net.request("RANCH_ACCEPT", {"from": from_code})
	if res["ok"] and res["t"] == "RANCH_READY":
		await _on_session_ready(res["d"])
	return res


func decline(from_code: String) -> Dictionary:
	if not is_online():
		return {"ok": false, "code": "OFFLINE"}
	return await _net.request("RANCH_DECLINE", {"from": from_code})


## Session verlassen (Match: zählt ab Start als Aufgabe/DNF).
func leave() -> Dictionary:
	if not is_active() or not is_online():
		_reset()
		return {"ok": false, "code": "OFFLINE"}
	var res: Dictionary = await _net.request("ROOM_LEAVE", {"room": room_id})
	_reset()
	return res


## ------------------------------------------------ Lobby / Match


## Bereit melden — schickt den Kurs-Hash (Sync-Kontrakt: Mismatch =>
## unranked, Doc §2.2). Der Start kommt als MG_START-Push, sobald alle bereit.
func set_ready() -> Dictionary:
	if not is_active() or not is_online():
		return {"ok": false, "code": "OFFLINE"}
	var data := {"room": room_id, "kursHash": RmpKurse.kurs_hash(kurs)}
	if dev_session:
		data["devSession"] = true
	return await _net.request("MG_READY", data)


## Eigene Pose ins 10-Hz-Relay (fire-and-forget, client-seitig getaktet —
## der Server drosselt zusätzlich). force=true umgeht den Takt (Start/Sprung).
func send_pose(
	pos: Vector3, yaw: float, speed: float, gait: int, anim := "", jump := false, force := false
) -> bool:
	if not is_active() or _net == null:
		return false
	var now := _now_ms()
	if not force and _last_pose_ms >= 0 and now - _last_pose_ms < POSE_INTERVAL_MS:
		return false
	_last_pose_ms = now
	_pose_seq += 1
	var data := {
		"room": room_id,
		"p": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01), snappedf(pos.z, 0.01)],
		"yaw": snappedf(yaw, 0.01),
		"speed": snappedf(speed, 0.1),
		"gait": gait,
		"poseSeq": _pose_seq,
	}
	if not anim.is_empty():
		data["anim"] = anim
	if jump:
		data["jump"] = true
	_net.send("MG_POSE", data)
	return true


## Match-Ereignis melden — der Server validiert (Doc §2.2). kinds:
##   {"kind":"checkpoint","idx":n}   Reihenfolge + Pose-Nähe geprüft
##   {"kind":"strafe","gate":n}      Parcours, max 1 Strafe je Tor
##   {"kind":"finish"}               Zielzeit rechnet der SERVER
##   {"kind":"tag","target":code}    Fangen, Distanz + Immunität geprüft
func send_event(data: Dictionary) -> Dictionary:
	if not is_active() or not is_online():
		return {"ok": false, "code": "OFFLINE"}
	var payload := data.duplicate()
	payload["room"] = room_id
	return await _net.request("MG_EVENT", payload)


## Reaktions-Relay (Besuch/Ausritt): HERZ, GESTE {id: streicheln|fuettern},
## FOLGE_MIR {an: bool}, ENTDECKUNG {zone}. Rein kosmetisch, kein Gameplay.
func send_reaction(kind: String, body: Dictionary = {}) -> bool:
	if not is_active() or _net == null or not REAKTIONEN.has(kind):
		return false
	_net.send("ROOM_MSG", {"room": room_id, "kind": kind, "body": body})
	return true


## Nach Reconnect: Spielstand-Snapshot anfordern (Rejoin-Fenster 120 s).
## Der Snapshot kommt als ANTWORT (re) — beim Server-initiierten Rejoin
## zusätzlich als Push (beide Wege landen in _on_snapshot).
func resume(target_room: String) -> Dictionary:
	if not is_online():
		return {"ok": false, "code": "OFFLINE"}
	var res: Dictionary = await _net.request("ROOM_JOIN", {"room": target_room})
	if not res["ok"]:
		return res
	room_id = target_room
	var snap: Dictionary = await _net.request("MG_RESUME", {"room": target_room})
	if snap["ok"] and snap["t"] == "MG_SNAPSHOT":
		_on_snapshot(snap["d"])
	return snap


## Revanche anbieten — startet neu, sobald ALLE Anwesenden zustimmen.
func rematch() -> Dictionary:
	if not is_active() or not is_online():
		return {"ok": false, "code": "OFFLINE"}
	return await _net.request("RMP_REMATCH", {"room": room_id})


## Ergebnis quittieren (Server räumt pending auf) + idempotent im Save
## verbuchen (rewardId-Dedupe über RmpState).
func ack_result(result: Dictionary, gs: Object = null) -> void:
	if gs != null:
		RmpState.ergebnis_verbuchen(gs, result)
	var reward_id := str(result.get("rewardId", ""))
	for i in range(pending_results.size() - 1, -1, -1):
		if str((pending_results[i] as Dictionary).get("rewardId", "")) == reward_id:
			pending_results.remove_at(i)
	if is_online() and not reward_id.is_empty():
		_net.send("MG_RESULT_ACK", {"rewardId": reward_id})


## ------------------------------------------------ Fehlertexte (Deutsch)


## Server-/Netz-Fehlercode → freundlicher deutscher Text (EN paritätisch
## über ranch_mp.fehler.* — I18n macht den Locale-Fallback).
static func fehler_text(code: String) -> String:
	var key := "ranch_mp.fehler.%s" % code.to_lower()
	if I18nService.has_key(key):
		return I18nService.t(key)
	return I18nService.t("ranch_mp.fehler.unbekannt", {"code": code})


## ------------------------------------------------ intern


func _on_welcome(data: Dictionary) -> void:
	# Zustellgarantie (GoobyPal-Muster): unbestätigte Ergebnisse kommen im
	# WELCOME erneut — UI zeigt sie, ack_result räumt sie serverseitig ab.
	var pend: Variant = data.get("rmpPending")
	if pend is Array:
		pending_results = (pend as Array).duplicate(true)
		for result: Variant in pending_results:
			if result is Dictionary:
				result_received.emit(result)


func _on_push(type: String, data: Dictionary) -> void:
	match type:
		"RANCH_INVITED":
			invited.emit(data)
		"RANCH_DECLINED":
			invite_declined.emit(data)
		"RANCH_READY":
			_on_session_ready(data)
		"RANCH_ENDED":
			var payload := data
			_reset()
			session_ended.emit(payload)
		"MG_LOBBY":
			if data.get("room", "") == room_id:
				players = data.get("players", []) if data.get("players") is Array else players
				lobby_updated.emit(data)
		"MG_START":
			if data.get("room", "") == room_id:
				_on_start(data)
		"MG_PEER_POSE":
			if data.get("room", "") == room_id:
				peer_pose.emit(str(data.get("from", "")), data)
		"MG_STATE":
			if data.get("room", "") == room_id:
				_on_state(data)
		"MG_RESULT":
			_on_result(data)
		"MG_SNAPSHOT":
			_on_snapshot(data)
		"MG_PEER_DOWN":
			if data.get("room", "") == room_id:
				peer_down.emit(data)
		"MG_PEER_UP":
			if data.get("room", "") == room_id:
				peer_up.emit(data)
		"RMP_REMATCH_WAIT":
			if data.get("room", "") == room_id:
				rematch_wait.emit(data)
		"RMP_REMATCH_DECLINED":
			if data.get("room", "") == room_id:
				rematch_declined.emit(data)
		"ROOM_PEER_JOINED":
			if data.get("room", "") == room_id:
				peer_joined.emit(data)
		"ROOM_PEER_LEFT":
			if data.get("room", "") == room_id:
				peer_left.emit(data)
		"ROOM_MSG":
			if data.get("room", "") == room_id:
				var kind := str(data.get("kind", ""))
				if REAKTIONEN.has(kind):
					var body: Variant = data.get("body", {})
					reaction_received.emit(
						kind, str(data.get("from", "")), body if body is Dictionary else {}
					)


## RANCH_READY (Antwort ODER Push): Session übernehmen + Room beitreten.
## Bei Revanche ersetzt der frische Room den alten (Server hat umgezogen).
func _on_session_ready(data: Dictionary) -> void:
	room_id = str(data.get("room", ""))
	mode = str(data.get("mode", ""))
	kurs = str(data.get("kurs", ""))
	host_code = str(data.get("host", ""))
	players = data.get("players", []) if data.get("players") is Array else []
	phase = "lobby"
	it_code = ""
	start_at_ms = 0
	ends_at_ms = 0
	_last_pose_ms = -1
	_pose_seq = 0
	if is_online():
		await _net.request("ROOM_JOIN", {"room": room_id})
	session_ready.emit(data)


func _on_start(data: Dictionary) -> void:
	phase = "countdown"
	seed = int(_num(data.get("seed"), 0.0))
	start_at_ms = int(_num(data.get("startAt"), 0.0))
	ends_at_ms = int(_num(data.get("endsAt"), 0.0))
	it_code = str(data.get("it", ""))
	players = data.get("players", []) if data.get("players") is Array else players
	var server_now := int(_num(data.get("serverNow"), 0.0))
	if server_now > 0:
		server_offset_ms = server_now - _now_ms()
	match_started.emit(data)


func _on_state(data: Dictionary) -> void:
	if data.get("tag") is Dictionary:
		it_code = str((data["tag"] as Dictionary).get("it", it_code))
	if phase == "countdown" and countdown_ms() <= 0:
		phase = "run"
	state_updated.emit(data)


func _on_result(data: Dictionary) -> void:
	if data.get("room", "") == room_id:
		phase = "done"
	result_received.emit(data)


func _on_snapshot(data: Dictionary) -> void:
	room_id = str(data.get("room", room_id))
	mode = str(data.get("mode", mode))
	kurs = str(data.get("kurs", kurs))
	host_code = str(data.get("host", host_code))
	players = data.get("players", []) if data.get("players") is Array else players
	phase = str(data.get("phase", phase))
	seed = int(_num(data.get("seed"), float(seed)))
	start_at_ms = int(_num(data.get("startAt"), float(start_at_ms)))
	ends_at_ms = int(_num(data.get("endsAt"), float(ends_at_ms)))
	if data.get("tag") is Dictionary:
		it_code = str((data["tag"] as Dictionary).get("it", ""))
	var server_now := int(_num(data.get("serverNow"), 0.0))
	if server_now > 0:
		server_offset_ms = server_now - _now_ms()
	snapshot_received.emit(data)


func _reset() -> void:
	room_id = ""
	mode = ""
	kurs = ""
	host_code = ""
	players = []
	phase = ""
	seed = 0
	start_at_ms = 0
	ends_at_ms = 0
	it_code = ""
	_last_pose_ms = -1
	_pose_seq = 0


func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
