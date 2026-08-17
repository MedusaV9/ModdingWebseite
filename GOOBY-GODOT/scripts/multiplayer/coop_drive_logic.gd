class_name CoopDriveLogic
extends RefCounted
## Coop-Fahrt (W13B COUCH-COOP, Doc C §3.6 / P3-backend Punkt 6) — PURE.
## Einer fährt (Gastgeber), einer fährt mit und steuert das Radio (Gast).
## Der Server ist fertig vorbereitet: rooms.js erlaubt `drive:`-Räume (max 2,
## kein Join-Guard), das Relay reicht Kinds DRIVE/RADIO/POS unverändert durch
## — hier stehen nur Room-Id, Payload-Schemata, der deterministische
## Track-Pick und die Offset-Rechnung.
##
## Sync-Vertrag Radio: jede Aktion reist als {op:"set", station, trackId,
## atMs} an BEIDE Seiten; beide setzen denselben Sender/Track. Der
## Startzeit-Offset (now−atMs) ist berechnet, aber die öffentliche
## MusicDirector-API kann (noch) nicht mitten im Track starten — leichte
## Drift ist laut Design ok (Request für einen Seek-Hook liegt beim
## RADIO-Owner, s. W13-requests.md Tag COUCH-COOP).

## Kind der Einladungs-/Absage-Nachricht im BESUCHS-Room.
const KIND_DRIVE := "DRIVE"
## Kind der Radio-Sync-Nachricht im drive:-Room.
const KIND_RADIO := "RADIO"
## Auto-Position reist als POS (Server drosselt POS-Kind auf 5 Hz).
const KIND_POS := "POS"
const ANIM_FAHRT := "drive"

const OP_EINLADUNG := "invite"
const OP_ABSAGE := "decline"
const OP_RADIO_SET := "set"
const OP_RADIO_STOP := "stop"


## drive:-Room-Id: Host-Code + Nonce (Room-RE des Servers:
## ^drive:[A-Za-z0-9._-]{1,64}$ — Freundes-Codes passen).
static func drive_room_id(host_code: String, nonce: int) -> String:
	return "drive:%s-%d" % [host_code, absi(nonce)]


## Einladung des Fahrers (im Besuchs-Room): Room-Id + ob der GASTGEBER das
## Radio besitzt (Gate-API Welle A: RadioLogic.besitzt_radio — nur der Host
## kennt seinen Save, der Beifahrer bekommt das Flag mitgeliefert).
static func einladung_payload(room_id: String, radio_owned: bool, von: String) -> Dictionary:
	return {"op": OP_EINLADUNG, "room": room_id, "radio": radio_owned, "von": von}


static func absage_payload() -> Dictionary:
	return {"op": OP_ABSAGE}


static func parse_drive(body: Variant) -> Dictionary:
	var out := {"ok": false, "op": "", "room": "", "radio": false, "von": ""}
	if not (body is Dictionary):
		return out
	var data: Dictionary = body
	var op := str(data.get("op", ""))
	if op != OP_EINLADUNG and op != OP_ABSAGE:
		return out
	out["ok"] = true
	out["op"] = op
	out["room"] = str(data.get("room", ""))
	out["radio"] = data.get("radio", false) is bool and bool(data.get("radio", false))
	out["von"] = str(data.get("von", ""))
	if op == OP_EINLADUNG and not str(out["room"]).begins_with("drive:"):
		out["ok"] = false
	return out


## Auto-Position (Fahrer → Beifahrer, 5 Hz): Welt-XZ + Tempo fürs
## Mitfahr-Gefühl. `anim:"drive"` unterscheidet die Fahrt vom Fuß-POS.
static func auto_pos_payload(world_pos: Vector3, tempo: float) -> Dictionary:
	return {
		"pos": [snappedf(world_pos.x, 0.001), snappedf(world_pos.z, 0.001)],
		"anim": ANIM_FAHRT,
		"tempo": snappedf(tempo, 0.01),
	}


static func parse_auto_pos(body: Variant) -> Dictionary:
	var out := {"ok": false, "pos": Vector3.ZERO, "tempo": 0.0}
	if not (body is Dictionary):
		return out
	var data: Dictionary = body
	var pos: Variant = data.get("pos")
	if not (pos is Array) or (pos as Array).size() < 2:
		return out
	out["ok"] = true
	out["pos"] = Vector3(float(pos[0]), 0.0, float(pos[1]))
	var tempo: Variant = data.get("tempo", 0.0)
	out["tempo"] = float(tempo) if (tempo is float or tempo is int) else 0.0
	return out


## Radio-Aktion (Beifahrer → beide): Sender + konkreter Track + Sendezeit.
static func radio_payload(station_id: String, track_id: String, at_ms: int) -> Dictionary:
	return {"op": OP_RADIO_SET, "station": station_id, "trackId": track_id, "atMs": at_ms}


static func radio_stop_payload(at_ms: int) -> Dictionary:
	return {"op": OP_RADIO_STOP, "atMs": at_ms}


static func parse_radio(body: Variant) -> Dictionary:
	var out := {"ok": false, "op": "", "station": "", "track_id": "", "at_ms": 0}
	if not (body is Dictionary):
		return out
	var data: Dictionary = body
	var op := str(data.get("op", ""))
	if op != OP_RADIO_SET and op != OP_RADIO_STOP:
		return out
	out["op"] = op
	out["station"] = str(data.get("station", ""))
	out["track_id"] = str(data.get("trackId", ""))
	var at: Variant = data.get("atMs", 0)
	out["at_ms"] = int(at) if (at is int or at is float) else 0
	out["ok"] = op == OP_RADIO_STOP or (out["station"] != "" and out["track_id"] != "")
	return out


## Deterministischer Track-Pick: beide Seiten haben dieselben Content-Packs,
## also reicht die Registry-Reihenfolge — erster Track beim Senderwechsel,
## zyklisch weiter beim Skip. (Level-Schlösser gelten hier bewusst nicht:
## das Gate ist der Radio-BESITZ des Gastgebers, Doc C §3.6.)
static func erster_track(station_id: String) -> String:
	var tracks := MusicRegistry.station_track_ids(station_id)
	return str(tracks[0]) if not tracks.is_empty() else ""


static func naechster_track(station_id: String, aktueller_track: String) -> String:
	var tracks := MusicRegistry.station_track_ids(station_id)
	if tracks.is_empty():
		return ""
	var idx := tracks.find(aktueller_track)
	return str(tracks[(idx + 1) % tracks.size()])


## Startzeit-Offset in Sekunden (nie negativ — Uhren können auseinanderliegen).
static func offset_sec(at_ms: int, now_ms: int) -> float:
	return maxf(0.0, float(now_ms - at_ms) / 1000.0)


## Beifahrer-Gate: Sender/Skip nur, wenn der GASTGEBER das Radio besitzt —
## exakt die Welle-A-Matrix (RadioLogic.aktion_erlaubt, nur LESEN).
static func beifahrer_aktion_erlaubt(host_radio_owned: bool, aktion: String) -> bool:
	return RadioLogic.aktion_erlaubt(host_radio_owned, aktion)
