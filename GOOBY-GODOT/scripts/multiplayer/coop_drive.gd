class_name CoopDrive
extends Node
## Coop-Fahrt-Session (W13B COUCH-COOP, Doc C §3.6): beide Besuchs-Partner
## joinen einen `drive:`-Room (Server fertig: rooms.js, max 2, kein Guard).
## FAHRER = Gastgeber (fährt normal, meldet die Auto-Position 5 Hz übers
## POS-Kind — Server-Drossel inklusive), BEIFAHRER = Gast (Mitfahr-Kamera
## über `auto_pos_updated`, steuert das Radio). Jede Radio-Aktion reist als
## ROOM_MSG kind:RADIO an beide → beide setzen denselben Sender/Track über
## die öffentliche MusicDirector-API (Startzeit-Offset berechnet; ohne
## Seek-Hook startet der Track bei 0 — leichte Drift ok, s. Request).
##
## Einladung läuft übers BESUCHS-Relay (kind:DRIVE) — kein neues Server-Kind
## nötig, das generische Relay reicht Kinds unverändert durch.
## Verlassen/Disconnect degradiert sauber: Beifahrer-UI weg, Fahrer fährt
## weiter (fahrt_beendet nur bei der Seite, die wirklich aussteigt).

signal einladung_erhalten(data: Dictionary)
signal einladung_abgelehnt
signal fahrt_gestartet(rolle: String)
signal peer_dabei(data: Dictionary)
signal peer_gegangen(data: Dictionary)
signal fahrt_beendet(grund: String)
signal auto_pos_updated(pos: Vector3, tempo: float)
signal radio_gesetzt(station_id: String, track_id: String, offset_s: float)

const ROLLE_KEINE := ""
const ROLLE_FAHRER := "fahrer"
const ROLLE_BEIFAHRER := "beifahrer"

## Presence-Kind der Fahrt (Server-Template + net.presence.drive existieren).
const PRESENCE_KIND := "drive"

var rolle := ROLLE_KEINE
var room_id := ""
## Gate aus Welle A: besitzt der GASTGEBER das Radio? (Fahrer setzt es beim
## Start, Beifahrer bekommt es mit der Einladung.)
var host_radio_owned := false
var von_name := ""

## Injektion (Tests): Wanduhr in ms (Unix — muss zwischen Clients vergleichbar
## sein, Engine-Ticks sind es nicht).
var now_ms_provider := Callable(self, "_unix_ms")
## Injektion (Tests): Nonce für die Room-Id.
var nonce_provider := Callable(self, "_zufalls_nonce")
## Injektion (Tests): Radio-Anwendung (Duck: sender_setzen(station, track,
## offset_s)). Default: öffentlicher MusicDirector-Adapter.
var radio_api: Object = null
## Injektion (Tests): Presence-Duck (set_kind/current_kind) statt net.l.
var presence_override: Node = null

var _net: Node = null
var _visit_room := ""
var _pending_invite: Dictionary = {}
var _pending_invite_room := ""
var _last_auto_ms := -1
var _radio_station := ""
var _radio_track := ""
var _prev_presence_kind := ""


## Öffentlicher MusicDirector-Adapter (nur radio_play/play_track/
## current_track_id — scripts/audio bleibt unangetastet). Ohne Seek-API
## startet der Track bei 0; der Offset ist bewusst ignoriert (Request an
## den RADIO-Owner, leichte Drift laut Design ok).
class MusicRadioAdapter:
	extends RefCounted

	var from: Node

	func _init(node: Node) -> void:
		from = node

	func sender_setzen(station_id: String, track_id: String, _offset_s: float) -> void:
		var music := MusicDirector.get_or_create(from)
		music.radio_play(station_id)
		if music.current_track_id() != track_id:
			music.play_track(track_id, MusicDirector.RADIO_FADE_S, false)


func setup(net_client: Node) -> void:
	_net = net_client
	_net.pushed.connect(_on_push)
	if _net.has_signal("status_changed"):
		_net.status_changed.connect(_on_status_changed)


func is_aktiv() -> bool:
	return rolle != ROLLE_KEINE


func is_online() -> bool:
	return _net != null and _net.has_method("is_online") and _net.is_online()


# ── Fahrer (Gastgeber) ───────────────────────────────────────────────────────


## „Gemeinsam fahren“: Einladung ins Besuchs-Relay + selbst den drive:-Room
## joinen. Antwort ist das ROOM_JOIN-Ergebnis ({ok:false, code:"OFFLINE"}
## ohne Netz — Offline-first wie der VisitService).
func starte_als_fahrer(visit_room: String, radio_owned: bool, von: String) -> Dictionary:
	if not is_online() or visit_room.is_empty():
		return {"ok": false, "code": "OFFLINE"}
	var room := CoopDriveLogic.drive_room_id(
		str(_net.get("friend_code")), int(nonce_provider.call())
	)
	_visit_room = visit_room
	(
		_net
		. send(
			"ROOM_MSG",
			{
				"room": visit_room,
				"kind": CoopDriveLogic.KIND_DRIVE,
				"body": CoopDriveLogic.einladung_payload(room, radio_owned, von),
			}
		)
	)
	var res: Dictionary = await _net.request("ROOM_JOIN", {"room": room})
	if res["ok"]:
		room_id = room
		rolle = ROLLE_FAHRER
		host_radio_owned = radio_owned
		von_name = von
		_presence_setzen()
		fahrt_gestartet.emit(rolle)
	return res


## Auto-Position ins Relay (Fahrer, 5 Hz client-seitig — POS-Kind drosselt
## der Server zusätzlich). Die Mitfahr-Kamera des Gastes hängt am Signal.
func melde_auto(world_pos: Vector3, tempo: float) -> bool:
	if rolle != ROLLE_FAHRER:
		return false
	var now := Time.get_ticks_msec()
	if not VisitLogic.should_send_pos(_last_auto_ms, now):
		return false
	_last_auto_ms = now
	_sende_room_msg(CoopDriveLogic.KIND_POS, CoopDriveLogic.auto_pos_payload(world_pos, tempo))
	return true


# ── Beifahrer (Gast) ─────────────────────────────────────────────────────────


## Einladung annehmen: den angebotenen drive:-Room joinen.
func beitreten() -> Dictionary:
	if _pending_invite.is_empty():
		return {"ok": false, "code": "NO_INVITE"}
	if not is_online():
		return {"ok": false, "code": "OFFLINE"}
	var room := str(_pending_invite["room"])
	var res: Dictionary = await _net.request("ROOM_JOIN", {"room": room})
	if res["ok"]:
		room_id = room
		rolle = ROLLE_BEIFAHRER
		host_radio_owned = bool(_pending_invite["radio"])
		von_name = str(_pending_invite["von"])
		_pending_invite = {}
		_presence_setzen()
		fahrt_gestartet.emit(rolle)
	return res


## Einladung ablehnen (freundliche Absage übers Besuchs-Relay).
func ablehnen() -> void:
	if _pending_invite.is_empty():
		return
	if _net != null and not _pending_invite_room.is_empty():
		(
			_net
			. send(
				"ROOM_MSG",
				{
					"room": _pending_invite_room,
					"kind": CoopDriveLogic.KIND_DRIVE,
					"body": CoopDriveLogic.absage_payload(),
				}
			)
		)
	_pending_invite = {}


## Beifahrer-Radio: Senderwechsel (nur mit Gastgeber-Radio, Welle-A-Gate).
func radio_sender(station_id: String) -> bool:
	if rolle != ROLLE_BEIFAHRER:
		return false
	if not CoopDriveLogic.beifahrer_aktion_erlaubt(host_radio_owned, "sender"):
		return false
	var track := CoopDriveLogic.erster_track(station_id)
	if track.is_empty():
		return false
	_radio_aktion(station_id, track)
	return true


## Beifahrer-Radio: nächster Track im aktuellen Sender.
func radio_skip() -> bool:
	if rolle != ROLLE_BEIFAHRER or _radio_station.is_empty():
		return false
	if not CoopDriveLogic.beifahrer_aktion_erlaubt(host_radio_owned, "skip"):
		return false
	var track := CoopDriveLogic.naechster_track(_radio_station, _radio_track)
	if track.is_empty():
		return false
	_radio_aktion(_radio_station, track)
	return true


# ── Gemeinsames ──────────────────────────────────────────────────────────────


## Fahrt selbst verlassen (Knopf/Disconnect-Aufräumer). Der Peer degradiert
## über ROOM_PEER_LEFT sauber weiter.
func verlasse_fahrt() -> void:
	if not is_aktiv():
		return
	if is_online():
		_net.send("ROOM_LEAVE", {"room": room_id})
	_ende("selbst")


func _radio_aktion(station_id: String, track_id: String) -> void:
	var at_ms := int(now_ms_provider.call())
	_sende_room_msg(
		CoopDriveLogic.KIND_RADIO, CoopDriveLogic.radio_payload(station_id, track_id, at_ms)
	)
	# Der Server relayt nur an die ANDERE Seite — lokal sofort anwenden.
	_radio_anwenden(station_id, track_id, 0.0)


func _radio_anwenden(station_id: String, track_id: String, offset_s: float) -> void:
	_radio_station = station_id
	_radio_track = track_id
	var api := radio_api
	if api == null:
		api = MusicRadioAdapter.new(self)
	api.call("sender_setzen", station_id, track_id, offset_s)
	radio_gesetzt.emit(station_id, track_id, offset_s)


func _sende_room_msg(kind: String, body: Dictionary) -> void:
	if _net != null and is_aktiv():
		_net.send("ROOM_MSG", {"room": room_id, "kind": kind, "body": body})


func _on_push(type: String, data: Dictionary) -> void:
	match type:
		"ROOM_MSG":
			_on_room_msg(str(data.get("room", "")), str(data.get("kind", "")), data.get("body"))
		"ROOM_PEER_JOINED":
			if data.get("room", "") == room_id:
				peer_dabei.emit(data)
		"ROOM_PEER_LEFT":
			if data.get("room", "") == room_id:
				_on_peer_left(data)


func _on_room_msg(room: String, kind: String, body: Variant) -> void:
	if kind == CoopDriveLogic.KIND_DRIVE:
		_on_drive_msg(room, body)
		return
	if room != room_id or not is_aktiv():
		return
	match kind:
		CoopDriveLogic.KIND_RADIO:
			var radio := CoopDriveLogic.parse_radio(body)
			if radio["ok"] and radio["op"] == CoopDriveLogic.OP_RADIO_SET:
				var offset := CoopDriveLogic.offset_sec(
					int(radio["at_ms"]), int(now_ms_provider.call())
				)
				_radio_anwenden(str(radio["station"]), str(radio["track_id"]), offset)
		CoopDriveLogic.KIND_POS:
			var auto := CoopDriveLogic.parse_auto_pos(body)
			if auto["ok"] and rolle == ROLLE_BEIFAHRER:
				auto_pos_updated.emit(auto["pos"], float(auto["tempo"]))


func _on_drive_msg(room: String, body: Variant) -> void:
	var parsed := CoopDriveLogic.parse_drive(body)
	if not parsed["ok"]:
		return
	if parsed["op"] == CoopDriveLogic.OP_EINLADUNG and not is_aktiv():
		_pending_invite = {"room": parsed["room"], "radio": parsed["radio"], "von": parsed["von"]}
		_pending_invite_room = room
		einladung_erhalten.emit(_pending_invite)
	elif parsed["op"] == CoopDriveLogic.OP_ABSAGE and rolle == ROLLE_FAHRER:
		einladung_abgelehnt.emit()


## Peer weg: Beifahrer ohne Fahrer steigt aus (Fahrt vorbei); der Fahrer
## fährt weiter — nur das Beifahrer-Ende wird gemeldet (Doc C §3.6).
func _on_peer_left(data: Dictionary) -> void:
	if rolle == ROLLE_BEIFAHRER:
		if is_online():
			_net.send("ROOM_LEAVE", {"room": room_id})
		_ende("fahrer_weg")
	else:
		peer_gegangen.emit(data)


func _on_status_changed(status: int) -> void:
	if is_aktiv() and status != NetClient.Status.ONLINE:
		_ende("offline")


func _ende(grund: String) -> void:
	rolle = ROLLE_KEINE
	room_id = ""
	_radio_station = ""
	_radio_track = ""
	_last_auto_ms = -1
	_presence_zuruecksetzen()
	fahrt_beendet.emit(grund)


# ── Presence (kind-basiert, Welle-A-i18n: Client übersetzt net.presence.*) ──


func _presence() -> Node:
	if presence_override != null:
		return presence_override
	if _net != null:
		var service: Variant = _net.get("l")
		if service is Node:
			return service
	return null


func _presence_setzen() -> void:
	var presence := _presence()
	if presence == null:
		return
	if presence.has_method("current_kind"):
		_prev_presence_kind = str(presence.call("current_kind"))
	if presence.has_method("set_kind"):
		presence.call("set_kind", PRESENCE_KIND)


func _presence_zuruecksetzen() -> void:
	var presence := _presence()
	if presence == null or _prev_presence_kind.is_empty():
		return
	if presence.has_method("set_kind"):
		presence.call("set_kind", _prev_presence_kind)
	_prev_presence_kind = ""


func _unix_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)


func _zufalls_nonce() -> int:
	return randi() % 1_000_000
