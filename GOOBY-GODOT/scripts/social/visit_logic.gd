class_name VisitLogic
extends RefCounted
## Besuchs-Regeln (W3c VISIT) — PURE: POS-Takt (5 Hz), POS-Payload-Schema,
## Raum-Sichtbarkeit (anderer Gooby nur im gleichen Raum sichtbar) und die
## Best-Effort-Anwendung von BUILD_DELTA beim Gast inkl. Konfliktregel
## „Gast steht auf der Zelle → Tür-Teleport“ (Doc C §3.4 Punkt 5).

## 5 Hz — passt exakt zum Server-Bucket (rooms.js: Bucket 10, Refill 5/s).
const POS_INTERVAL_MS := 200

const REASON_OK := ""
const REASON_BAD_DELTA := "bad_delta"
const REASON_UNKNOWN_ITEM := "unknown_item"
const REASON_NOT_FOUND := "not_found"


## Sende-Takt: true = jetzt senden (letzter Send >= 200 ms her).
static func should_send_pos(last_sent_ms: int, now_ms: int) -> bool:
	return last_sent_ms < 0 or now_ms - last_sent_ms >= POS_INTERVAL_MS


## POS-Body (W2c §4.5): {pos:[x,z], anim, roomId} — Welt-XZ, y ist im Haus
## immer 0 (Möbel-Höhen macht die Szene selbst).
static func pos_payload(world_pos: Vector3, anim: String, room_id: String) -> Dictionary:
	return {
		"pos": [snappedf(world_pos.x, 0.001), snappedf(world_pos.z, 0.001)],
		"anim": anim,
		"roomId": room_id,
	}


## POS-Body robust parsen (unbekannte Felder ignorieren, W2c §1).
static func parse_pos(body: Variant) -> Dictionary:
	var out := {"ok": false, "pos": Vector3.ZERO, "anim": "idle", "room_id": ""}
	if not (body is Dictionary):
		return out
	var data: Dictionary = body
	var pos: Variant = data.get("pos")
	if not (pos is Array) or (pos as Array).size() < 2:
		return out
	out["ok"] = true
	out["pos"] = Vector3(float(pos[0]), 0.0, float(pos[1]))
	out["anim"] = str(data.get("anim", "idle"))
	out["room_id"] = str(data.get("roomId", ""))
	return out


## Sichtbarkeitsregel: der andere Gooby ist nur sichtbar, wenn beide im
## selben Raum sind (Doc C §3.4 Punkt 4).
static func peer_visible(my_room_id: String, peer_room_id: String) -> bool:
	return not my_room_id.is_empty() and my_room_id == peer_room_id


## BUILD_DELTA {op:"place"|"remove", item, cell:[x,y]} auf ein GridData
## anwenden (Best-Effort — Fehler werden geschluckt, Warnung kam ja schon).
## `occupant_cell` = Zelle des eigenen Goobys: wird auf eine gerade
## platzierte Fläche gebaut → {"teleport": true} (Szene teleportiert zur Tür).
static func apply_build_delta(
	grid: GridData, delta: Variant, occupant_cell: Vector2i, uid_hint := ""
) -> Dictionary:
	var out := {"ok": false, "reason": REASON_BAD_DELTA, "teleport": false, "uid": ""}
	if grid == null or not (delta is Dictionary):
		return out
	var data: Dictionary = delta
	var op := str(data.get("op", ""))
	var cell := BattleshipLogic.to_cell(data.get("cell", []))
	if op == "place":
		var def := FurnitureCatalog.def(str(data.get("item", "")))
		if def.is_empty():
			out["reason"] = REASON_UNKNOWN_ITEM
			return out
		var uid := uid_hint if not uid_hint.is_empty() else "visit-%d-%d" % [cell.x, cell.y]
		var rot := int(data.get("rot", 0))
		var placed := grid.place(def, cell, rot, uid)
		if not placed["ok"]:
			out["reason"] = str(placed["reason"])
			return out
		out["ok"] = true
		out["reason"] = REASON_OK
		out["uid"] = uid
		for taken in GridData.cells_for(cell, def["footprint"], rot):
			if taken == occupant_cell:
				out["teleport"] = true
				break
		return out
	if op == "remove":
		for layer in [GridData.Layer.SURFACE, GridData.Layer.FLOOR, GridData.Layer.RUG]:
			var uid := grid.item_at(cell, layer)
			if uid != "":
				grid.remove_item(uid)
				out["ok"] = true
				out["reason"] = REASON_OK
				out["uid"] = uid
				return out
		out["reason"] = REASON_NOT_FOUND
		return out
	return out


## Anim-Name fürs POS-Relay aus dem Bewegungszustand.
static func anim_for(moving: bool) -> String:
	return "walk" if moving else "idle"
