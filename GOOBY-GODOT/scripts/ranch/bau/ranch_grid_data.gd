class_name RanchGridData
extends RefCounted
## Außen-Grid der Ranch (RW-4, Gooby-Ranch-DLC — IDEAS-1 D1, IDEAS-3 §6):
## das PURE Datenmodell des Hof-Baumodus, Muster = home/grid_data.gd
## (erprobt, „das einzig Gute“), übertragen auf den Außenbereich.
##
## Unterschiede zum Haus-Grid:
## - Zellgröße 3 m (16×16 Zellen Hof; Logik rechnet NUR in Zellen).
## - Layer BODEN (Wege/Beläge — Objekte dürfen DRAUF stehen) und OBJEKT
##   (Anlagen/Deko — kollidieren untereinander).
## - ZÄUNE sind KANTEN-Items (User-Auftrag: „Zäune als Kanten, nicht als
##   Zellen“): jede Kante wird auf Nord/West normalisiert (S(x,y) = N(x,y+1),
##   E(x,y) = W(x+1,y)) — eine Kante, EINE Wahrheit.
## - Zonen statt Türzonen: nur freigeschaltete Zellen (Start 10×10,
##   Erweiterung Nord/Ost per Gold) sind bebaubar.
##
## Save-Format (ranch.bau.grid.items — RanchBauState):
##   Zelle: {"uid", "item", "at": [x, y], "rot": 0..3}
##   Kante: {"uid", "item", "kante": "N|W", "at": [x, y]}
## Belegung wird beim Laden aus Items + Katalog rekonstruiert; Unbekanntes
## und Konflikte wandern als Leftover zurück (nie Daten verlieren).

enum Layer { BODEN, OBJEKT }

const CELL_SIZE := 3.0
const KANTEN: Array[String] = ["N", "W"]

const REASON_OK := ""
const REASON_OOB := "out_of_bounds"
const REASON_GESPERRT := "locked_zone"
const REASON_OCCUPIED := "occupied"
const REASON_UNKNOWN_ITEM := "unknown_item"

var size := Vector2i.ZERO
var zonen: Array[Rect2i] = []

var _items: Dictionary = {}  # uid -> Instanz-Dict
var _boden_cells: Dictionary = {}  # Vector2i -> uid
var _objekt_cells: Dictionary = {}  # Vector2i -> uid
var _kanten_slots: Dictionary = {}  # "N:3:4" -> uid


func _init(grid_size := Vector2i(16, 16), frei_zonen: Array = []) -> void:
	size = grid_size
	for zone: Variant in frei_zonen:
		if zone is Rect2i:
			zonen.append(zone)
		elif zone is Array and (zone as Array).size() >= 4:
			zonen.append(Rect2i(int(zone[0]), int(zone[1]), int(zone[2]), int(zone[3])))


## Footprint nach Rotation (rot 1/3 tauschen Breite und Tiefe).
static func rotated_footprint(footprint: Vector2i, rot: int) -> Vector2i:
	if posmod(rot, 2) == 1:
		return Vector2i(footprint.y, footprint.x)
	return footprint


## Alle Zellen eines Items mit Anker `at` (Min-Ecke) und Rotation `rot`.
static func cells_for(at: Vector2i, footprint: Vector2i, rot: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var fp := rotated_footprint(footprint, rot)
	for dy in fp.y:
		for dx in fp.x:
			cells.append(at + Vector2i(dx, dy))
	return cells


## Kante auf die N/W-Normalform bringen: S(x,y) → N(x,y+1), E(x,y) → W(x+1,y).
static func normalize_kante(cell: Vector2i, seite: String) -> Dictionary:
	match seite:
		"S":
			return {"cell": Vector2i(cell.x, cell.y + 1), "seite": "N"}
		"E":
			return {"cell": Vector2i(cell.x + 1, cell.y), "seite": "W"}
		_:
			return {"cell": cell, "seite": seite}


## Kanten-Ring um ein Zell-Rechteck („Weide abstecken“), optional mit
## Tor-Lücke (Kanten-Index entlang des Rings, -1 = keine Lücke).
static func weide_ring(rect: Rect2i, tor_index := -1) -> Array:
	var out: Array = []
	for dx in rect.size.x:
		out.append({"cell": Vector2i(rect.position.x + dx, rect.position.y), "seite": "N"})
	for dy in rect.size.y:
		out.append(normalize_kante(Vector2i(rect.end.x - 1, rect.position.y + dy), "E"))
	for dx in rect.size.x:
		out.append(normalize_kante(Vector2i(rect.end.x - 1 - dx, rect.end.y - 1), "S"))
	for dy in rect.size.y:
		out.append({"cell": Vector2i(rect.position.x, rect.end.y - 1 - dy), "seite": "W"})
	if tor_index >= 0 and tor_index < out.size():
		out.remove_at(tor_index)
	return out


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


## Zelle in einer freigeschalteten Zone?
func ist_frei(cell: Vector2i) -> bool:
	for zone in zonen:
		if zone.has_point(cell):
			return true
	return false


## Kante gültig + freigeschaltet? Eine N-Kante (x,y) grenzt an (x,y-1)/(x,y),
## eine W-Kante (x,y) an (x-1,y)/(x,y) — mindestens EIN Nachbar muss eine
## freigeschaltete Zelle sein (Randkanten der Zonen sind erlaubt).
func kante_erlaubt(cell: Vector2i, seite: String) -> String:
	if not KANTEN.has(seite):
		return REASON_OOB
	var nachbarn: Array[Vector2i] = []
	if seite == "N":
		if cell.x < 0 or cell.x >= size.x or cell.y < 0 or cell.y > size.y:
			return REASON_OOB
		nachbarn = [Vector2i(cell.x, cell.y - 1), cell]
	else:
		if cell.x < 0 or cell.x > size.x or cell.y < 0 or cell.y >= size.y:
			return REASON_OOB
		nachbarn = [Vector2i(cell.x - 1, cell.y), cell]
	for nachbar in nachbarn:
		if in_bounds(nachbar) and ist_frei(nachbar):
			return REASON_OK
	return REASON_GESPERRT


## Kollisionsprüfung Zell-Layer (BODEN/OBJEKT).
## Liefert {"ok": bool, "reason": String}. `ignore_uid` = beim Verschieben.
func can_place(def: Dictionary, at: Vector2i, rot: int, ignore_uid := "") -> Dictionary:
	if def.is_empty() or def.get("kante", false):
		return {"ok": false, "reason": REASON_UNKNOWN_ITEM}
	var layer := int(def["layer"])
	for cell in cells_for(at, def["footprint"], rot):
		var reason := _cell_reason(layer, cell, ignore_uid)
		if reason != REASON_OK:
			return {"ok": false, "reason": reason}
	return {"ok": true, "reason": REASON_OK}


func _cell_reason(layer: int, cell: Vector2i, ignore_uid: String) -> String:
	if not in_bounds(cell):
		return REASON_OOB
	if not ist_frei(cell):
		return REASON_GESPERRT
	var cells_of_layer: Dictionary = [_boden_cells, _objekt_cells][layer]
	var uid: String = cells_of_layer.get(cell, "")
	if uid != "" and uid != ignore_uid:
		return REASON_OCCUPIED
	return REASON_OK


## Platziert ein Zell-Item. Liefert das can_place-Resultat.
func place(def: Dictionary, at: Vector2i, rot: int, uid: String) -> Dictionary:
	var check := can_place(def, at, rot)
	if not check["ok"]:
		return check
	var item := {"uid": uid, "def": def, "at": at, "rot": posmod(rot, 4)}
	_items[uid] = item
	_write_cells(item, uid)
	return check


## Kollisionsprüfung Kanten-Layer (Zäune). Nimmt JEDE Seite (N/E/S/W) an
## und normalisiert selbst.
func can_place_kante(
	def: Dictionary, cell: Vector2i, seite: String, ignore_uid := ""
) -> Dictionary:
	if def.is_empty() or not bool(def.get("kante", false)):
		return {"ok": false, "reason": REASON_UNKNOWN_ITEM}
	var norm := normalize_kante(cell, seite)
	var erlaubt := kante_erlaubt(norm["cell"], norm["seite"])
	if erlaubt != REASON_OK:
		return {"ok": false, "reason": erlaubt}
	var key := _kanten_key(norm["cell"], norm["seite"])
	var uid: String = _kanten_slots.get(key, "")
	if uid != "" and uid != ignore_uid:
		return {"ok": false, "reason": REASON_OCCUPIED}
	return {"ok": true, "reason": REASON_OK}


func place_kante(def: Dictionary, cell: Vector2i, seite: String, uid: String) -> Dictionary:
	var check := can_place_kante(def, cell, seite)
	if not check["ok"]:
		return check
	var norm := normalize_kante(cell, seite)
	var item := {"uid": uid, "def": def, "at": norm["cell"], "rot": 0, "kante": norm["seite"]}
	_items[uid] = item
	_kanten_slots[_kanten_key(norm["cell"], norm["seite"])] = uid
	return check


## Entfernt ein Item (liefert dessen Instanz-Dict oder {}).
func remove_item(uid: String) -> Dictionary:
	if not _items.has(uid):
		return {}
	var item: Dictionary = _items[uid]
	_erase_cells(uid)
	_items.erase(uid)
	return item


## Verschieben/Rotieren in einem Schritt (Zell-Layer).
func move_item(uid: String, at: Vector2i, rot: int) -> Dictionary:
	if not _items.has(uid) or _items[uid].has("kante"):
		return {"ok": false, "reason": REASON_UNKNOWN_ITEM}
	var item: Dictionary = _items[uid]
	var check := can_place(item["def"], at, rot, uid)
	if not check["ok"]:
		return check
	_erase_cells(uid)
	item["at"] = at
	item["rot"] = posmod(rot, 4)
	_write_cells(item, uid)
	return check


func get_item(uid: String) -> Dictionary:
	return _items.get(uid, {})


func items() -> Dictionary:
	return _items


## uid des Items auf `cell` im Layer ("" = frei).
func item_at(cell: Vector2i, layer: int) -> String:
	if layer == Layer.BODEN:
		return _boden_cells.get(cell, "")
	return _objekt_cells.get(cell, "")


## uid des Zauns auf einer (beliebig benannten) Kante ("" = frei).
func kante_item_at(cell: Vector2i, seite: String) -> String:
	var norm := normalize_kante(cell, seite)
	return _kanten_slots.get(_kanten_key(norm["cell"], norm["seite"]), "")


## Serialisierung ins Save-Format — deterministisch nach uid sortiert.
func to_items_array() -> Array:
	var uids := _items.keys()
	uids.sort()
	var out: Array = []
	for uid: String in uids:
		var item: Dictionary = _items[uid]
		var entry := {
			"uid": uid,
			"item": item["def"]["id"],
			"at": [item["at"].x, item["at"].y],
			"rot": item["rot"],
		}
		if item.has("kante"):
			entry["kante"] = item["kante"]
		out.append(entry)
	return out


## Grid aus Save-Items + Katalog-Defs rekonstruieren. Unbekannte Items und
## Konflikte (Katalog-Update!) landen in "leftovers" — weich degradieren,
## nie Daten verlieren (Muster GridData.from_save).
static func from_save(
	entries: Array, defs: Dictionary, grid_size: Vector2i, frei_zonen: Array = []
) -> Dictionary:
	var grid := RanchGridData.new(grid_size, frei_zonen)
	var leftovers: Array = []
	for entry: Variant in entries:
		if not (entry is Dictionary) or not defs.has(str(entry.get("item", ""))):
			leftovers.append(entry)
			continue
		var def: Dictionary = defs[str(entry["item"])]
		var uid := str(entry.get("uid", ""))
		var at_raw: Array = entry.get("at") if entry.get("at") is Array else [0, 0]
		var at := Vector2i(int(at_raw[0]), int(at_raw[1]))
		var ok := false
		if entry.has("kante"):
			ok = bool(grid.place_kante(def, at, str(entry["kante"]), uid)["ok"])
		else:
			ok = bool(grid.place(def, at, int(entry.get("rot", 0)), uid)["ok"])
		if not ok:
			leftovers.append(entry)
	return {"grid": grid, "leftovers": leftovers}


## Welt-Position (hof-lokal, XZ) der Mitte eines Footprints.
static func world_center(at: Vector2i, footprint: Vector2i, rot: int) -> Vector3:
	var fp := rotated_footprint(footprint, rot)
	var center := Vector2(at) + Vector2(fp) * 0.5
	return Vector3(center.x * CELL_SIZE, 0.0, center.y * CELL_SIZE)


## Zelle unter einer (hof-lokalen) Welt-Position.
static func cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(pos.x / CELL_SIZE)), int(floor(pos.z / CELL_SIZE)))


## Welt-Mitte + Y-Drehung einer (normalisierten) Kante: N-Kanten laufen
## entlang X (rot 0), W-Kanten entlang Z (rot PI/2).
static func kante_world(cell: Vector2i, seite: String) -> Dictionary:
	var norm := normalize_kante(cell, seite)
	var c: Vector2i = norm["cell"]
	if norm["seite"] == "N":
		return {
			"pos": Vector3((c.x + 0.5) * CELL_SIZE, 0.0, c.y * CELL_SIZE),
			"rot": 0.0,
		}
	return {
		"pos": Vector3(c.x * CELL_SIZE, 0.0, (c.y + 0.5) * CELL_SIZE),
		"rot": PI / 2.0,
	}


## Nächste Kante zu einer Welt-Position (fürs Ghost-Snapping des Zauns).
static func nearest_kante(pos: Vector3) -> Dictionary:
	var zelle := Vector2(pos.x / CELL_SIZE, pos.z / CELL_SIZE)
	var basis := Vector2i(int(floor(zelle.x)), int(floor(zelle.y)))
	var frac := zelle - Vector2(basis)
	var abstaende := {
		"N": frac.y,
		"S": 1.0 - frac.y,
		"W": frac.x,
		"E": 1.0 - frac.x,
	}
	var beste := "N"
	for seite: String in abstaende:
		if abstaende[seite] < abstaende[beste]:
			beste = seite
	return normalize_kante(basis, beste)


# ── intern ───────────────────────────────────────────────────────────────────


func _kanten_key(cell: Vector2i, seite: String) -> String:
	return "%s:%d:%d" % [seite, cell.x, cell.y]


func _write_cells(item: Dictionary, uid: String) -> void:
	var def: Dictionary = item["def"]
	for cell in cells_for(item["at"], def["footprint"], item["rot"]):
		if int(def["layer"]) == Layer.BODEN:
			_boden_cells[cell] = uid
		else:
			_objekt_cells[cell] = uid


func _erase_cells(uid: String) -> void:
	for map: Dictionary in [_boden_cells, _objekt_cells, _kanten_slots]:
		for key: Variant in map.keys():
			if map[key] == uid:
				map.erase(key)
