class_name VisitSnapshot
extends RefCounted
## Haus-Snapshot fürs Besuchssystem (W3c VISIT, Doc C §3.4) — PURE.
##
## Baut aus dem W2a-home-Slice (`home.rooms{id:{items:[…]}}`, W2a-Handoff §3)
## das JSON-Layout für `PUT /api/house` (≤ 256 KB, W2c §5) und rekonstruiert
## beim Gast daraus pro Raum ein GridData (read-only Möbel-Rekonstruktion).
## Items behalten EXAKT das W2a-Save-Format — Zellen werden nie übertragen,
## Belegung wird beim Laden aus Katalog-Footprints rekonstruiert.

const VERSION := 1
const MAX_BYTES := 256 * 1024

const REASON_OK := ""
const REASON_NOT_A_DICT := "not_a_dict"
const REASON_NO_ROOMS := "no_rooms"
const REASON_TOO_BIG := "too_big"


## Snapshot aus einem GameState (Duck-Typing: /root/GameState ODER Test-
## Instanz mit get_value()). goobyName reist mit, damit der Gast das Haus
## beschriften kann („Zu Besuch bei …“).
static func build_from_state(gs: Object) -> Dictionary:
	var rooms: Dictionary = {}
	var raw: Variant = gs.get_value("home.rooms", {})
	if raw is Dictionary:
		for room_id: String in raw as Dictionary:
			var entry: Variant = raw[room_id]
			var items: Variant = entry.get("items", []) if entry is Dictionary else []
			rooms[room_id] = {"items": items if items is Array else []}
	return {
		"v": VERSION,
		"goobyName": str(gs.get_value("meta.goobyNickname", "Gooby")),
		"rooms": rooms,
	}


static func to_json(snapshot: Dictionary) -> String:
	return JSON.stringify(snapshot)


static func byte_size(snapshot: Dictionary) -> int:
	return to_json(snapshot).to_utf8_buffer().size()


## Struktur- und Größen-Check (Upload verweigert Übergrößen LOKAL, der
## Server antwortet sonst 413 PAYLOAD_TOO_LARGE).
static func validate(snapshot: Variant) -> Dictionary:
	if not (snapshot is Dictionary):
		return {"ok": false, "reason": REASON_NOT_A_DICT}
	var rooms: Variant = (snapshot as Dictionary).get("rooms")
	if not (rooms is Dictionary) or (rooms as Dictionary).is_empty():
		return {"ok": false, "reason": REASON_NO_ROOMS}
	if byte_size(snapshot) > MAX_BYTES:
		return {"ok": false, "reason": REASON_TOO_BIG}
	return {"ok": true, "reason": REASON_OK}


## JSON-Text → Snapshot (robust: JSON.new().parse, nie Engine-ERROR-Log).
static func parse(text: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(text) != OK or not (parser.data is Dictionary):
		return {"ok": false, "snapshot": {}, "reason": REASON_NOT_A_DICT}
	var verdict := validate(parser.data)
	return {"ok": verdict["ok"], "snapshot": parser.data, "reason": verdict["reason"]}


## Raum-Ids des Snapshots, die es auch in den W2a-RoomDefs gibt (sortiert).
static func room_ids(snapshot: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var rooms: Variant = snapshot.get("rooms", {})
	if rooms is Dictionary:
		for room_id: String in rooms as Dictionary:
			if not RoomDefs.room(room_id).is_empty():
				out.append(room_id)
	out.sort()
	return out


static func room_items(snapshot: Dictionary, room_id: String) -> Array:
	var rooms: Variant = snapshot.get("rooms", {})
	if rooms is Dictionary and (rooms as Dictionary).get(room_id) is Dictionary:
		var items: Variant = (rooms[room_id] as Dictionary).get("items", [])
		if items is Array:
			return items
	return []


## GridData eines Snapshot-Raums rekonstruieren (W2a GridData.from_save —
## Unbekanntes landet in leftovers und wird beim Besuch einfach ignoriert).
static func make_grid(snapshot: Dictionary, room_id: String) -> Dictionary:
	var room_def := RoomDefs.room(room_id)
	if room_def.is_empty():
		return {"grid": null, "leftovers": []}
	return GridData.from_save(
		room_items(snapshot, room_id),
		FurnitureCatalog.defs(),
		room_def.get("grid", Vector2i(8, 8)),
		RoomDefs.blocked_cells(room_def),
		RoomDefs.wall_door_spans(room_def)
	)


## Brettspieltisch-Gate (Plan §2.3): true, wenn irgendwo im Haus (oder Lager)
## das Möbel `brettspieltisch` steht. Solange das Item nicht im W2a-Katalog
## existiert (Catalog-Request an den Orchestrator, W3c-catalog-request.md),
## liefert has_board_table IMMER true — M1-Fallback „immer verfügbar“.
static func has_board_table(gs: Object) -> bool:
	if FurnitureCatalog.def("brettspieltisch").is_empty():
		return true
	var rooms: Variant = gs.get_value("home.rooms", {})
	if rooms is Dictionary:
		for room_id: String in rooms as Dictionary:
			var entry: Variant = rooms[room_id]
			var items: Variant = entry.get("items", []) if entry is Dictionary else []
			if items is Array:
				for item: Variant in items as Array:
					if item is Dictionary and str(item.get("item", "")) == "brettspieltisch":
						return true
	var storage: Variant = gs.get_value("home.storage", [])
	if storage is Array:
		for entry: Variant in storage as Array:
			if entry is Dictionary and str(entry.get("item", "")) == "brettspieltisch":
				return true
	return false
