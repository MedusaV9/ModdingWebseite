class_name GridData
extends RefCounted
## GridData (W2a HOUSE) — das PURE Grid-Datenmodell aus Doc D §1 (FROZEN nach
## W2, Plan §3.2). Kein Node, keine Szene: vollständig headless testbar.
##
## - Zellgröße 0.5 m (CELL_SIZE ist nur die Welt-Abbildung; die Logik rechnet
##   ausschließlich in Zellen).
## - Layer: RUG (Teppiche, Möbel dürfen DRAUF stehen), FLOOR (blockt Gooby per
##   Item-Flag), SURFACE (auf FLOOR-Items mit `surface`-Def), WALL (N/E/S/W,
##   1 Höhenreihe in M1 — Doc D §1.2, Wand-/Decken-Vollausbau = Backlog M2).
## - Footprints [Breite, Tiefe] bei Rotation 0; `rot` in {0,1,2,3} (×90° im
##   Uhrzeigersinn) — bei 1/3 tauschen Breite/Tiefe.
## - `blocked` = Tür-Freihaltezonen: nie bebaubar, aber für Gooby begehbar.
## - Item-Defs kommen aus dem FurnitureCatalog (normalisierte Dictionaries);
##   GridData speichert pro Instanz nur, was Kollision/Save brauchen.
##
## Save-Format (Doc D §1.4, home.rooms[id].items):
##   Boden:  {"uid", "item", "at": [x, y], "rot": 0..3}
##   Wand:   {"uid", "item", "wall": "N|E|S|W", "at": [offset, 0]}
## Zellen werden NIE als belegt gespeichert — Belegung wird beim Laden aus den
## Items + Katalog-Footprints rekonstruiert; Konflikte/Unbekanntes wandert als
## Leftover zurück (HomeState legt es ins Lager).

enum Layer { RUG, FLOOR, SURFACE, WALL }

const CELL_SIZE := 0.5
const WALLS: Array[String] = ["N", "E", "S", "W"]

## Ablehnungsgründe von can_place*/place* (stabile Strings für UI/Tests).
const REASON_OK := ""
const REASON_OOB := "out_of_bounds"
const REASON_BLOCKED := "blocked_zone"
const REASON_OCCUPIED := "occupied"
const REASON_NEEDS_SURFACE := "needs_surface"
const REASON_UNKNOWN_ITEM := "unknown_item"

var size := Vector2i.ZERO
var blocked: Dictionary = {}  # Vector2i -> true (Tür-Freihaltezonen)
var wall_blocked: Dictionary = {}  # "N" -> Array[[von, bis_exklusiv]] (Tür-Spannen)

var _items: Dictionary = {}  # uid -> Instanz-Dict (s. _make_item)
var _rug_cells: Dictionary = {}  # Vector2i -> uid
var _floor_cells: Dictionary = {}  # Vector2i -> uid
var _surface_cells: Dictionary = {}  # Vector2i -> uid
var _wall_slots: Dictionary = {}  # "N:3" -> uid


func _init(grid_size := Vector2i(12, 10), blocked_cells: Array = [], wall_doors := {}) -> void:
	size = grid_size
	for cell: Variant in blocked_cells:
		blocked[_as_cell(cell)] = true
	for wall: String in wall_doors:
		wall_blocked[wall] = wall_doors[wall]


## Footprint nach Rotation (rot 1/3 tauschen Breite und Tiefe).
static func rotated_footprint(footprint: Vector2i, rot: int) -> Vector2i:
	if posmod(rot, 2) == 1:
		return Vector2i(footprint.y, footprint.x)
	return footprint


## Alle Zellen, die ein Item mit Anker `at` (Ursprungs-Ecke) und Rotation
## `rot` belegt. Anker = kleinste x/y-Ecke des rotierten Footprints.
static func cells_for(at: Vector2i, footprint: Vector2i, rot: int) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var fp := rotated_footprint(footprint, rot)
	for dy in fp.y:
		for dx in fp.x:
			cells.append(at + Vector2i(dx, dy))
	return cells


func in_bounds(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < size.x and cell.y < size.y


## Kollisionsprüfung für Boden-Layer (RUG/FLOOR/SURFACE).
## Liefert {"ok": bool, "reason": String}. `ignore_uid` = beim Verschieben.
func can_place(def: Dictionary, at: Vector2i, rot: int, ignore_uid := "") -> Dictionary:
	if def.is_empty() or int(def["layer"]) == Layer.WALL:
		var bad := REASON_UNKNOWN_ITEM if def.is_empty() else REASON_OOB
		return {"ok": false, "reason": bad}
	var layer: int = def["layer"]
	for cell in cells_for(at, def["footprint"], rot):
		var reason := _cell_reason(layer, cell, ignore_uid)
		if reason != REASON_OK:
			return {"ok": false, "reason": reason}
	return {"ok": true, "reason": REASON_OK}


## Ablehnungsgrund für EINE Zelle eines Boden-Layer-Items (REASON_OK = frei).
func _cell_reason(layer: int, cell: Vector2i, ignore_uid: String) -> String:
	if not in_bounds(cell):
		return REASON_OOB
	if layer != Layer.SURFACE and blocked.has(cell):
		return REASON_BLOCKED
	var cells_of_layer: Dictionary = [_rug_cells, _floor_cells, _surface_cells][layer]
	if _taken(cells_of_layer, cell, ignore_uid):
		return REASON_OCCUPIED
	if layer == Layer.SURFACE and not _has_surface_below(cell):
		return REASON_NEEDS_SURFACE
	return REASON_OK


## Platziert ein Boden-Layer-Item. Liefert can_place-Resultat.
func place(def: Dictionary, at: Vector2i, rot: int, uid: String) -> Dictionary:
	var check := can_place(def, at, rot)
	if not check["ok"]:
		return check
	var item := _make_item(def, uid)
	item["at"] = at
	item["rot"] = posmod(rot, 4)
	_items[uid] = item
	_write_cells(item, uid)
	return check


## Kollisionsprüfung Wand-Layer: 1D-Spanne `offset..offset+wall_size` auf der
## Wand `wall` — frei von anderen Wand-Items und Tür-Spannen.
func can_place_wall(def: Dictionary, wall: String, offset: int, ignore_uid := "") -> Dictionary:
	if def.is_empty() or def["layer"] != Layer.WALL:
		return {"ok": false, "reason": REASON_UNKNOWN_ITEM}
	if not WALLS.has(wall):
		return {"ok": false, "reason": REASON_OOB}
	var span: int = def["wall_size"]
	if offset < 0 or offset + span > wall_width(wall):
		return {"ok": false, "reason": REASON_OOB}
	for door_span: Array in wall_blocked.get(wall, []):
		if offset < int(door_span[1]) and offset + span > int(door_span[0]):
			return {"ok": false, "reason": REASON_BLOCKED}
	for slot in span:
		var key := "%s:%d" % [wall, offset + slot]
		if _wall_slots.has(key) and _wall_slots[key] != ignore_uid:
			return {"ok": false, "reason": REASON_OCCUPIED}
	return {"ok": true, "reason": REASON_OK}


func place_wall(def: Dictionary, wall: String, offset: int, uid: String) -> Dictionary:
	var check := can_place_wall(def, wall, offset)
	if not check["ok"]:
		return check
	var item := _make_item(def, uid)
	item["wall"] = wall
	item["at"] = Vector2i(offset, 0)
	item["rot"] = 0
	_items[uid] = item
	_write_cells(item, uid)
	return check


## Entfernt ein Item (liefert dessen Instanz-Dict oder {}).
func remove_item(uid: String) -> Dictionary:
	if not _items.has(uid):
		return {}
	var item: Dictionary = _items[uid]
	_erase_cells(uid)
	_items.erase(uid)
	return item


## Verschieben/Rotieren in einem Schritt (Boden-Layer).
func move_item(uid: String, at: Vector2i, rot: int) -> Dictionary:
	if not _items.has(uid):
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


## uid des Items auf `cell` im gewünschten Layer ("" = frei). Wand-Items
## belegen keine Boden-Zellen — für Layer.WALL siehe wall_item_at().
func item_at(cell: Vector2i, layer: int) -> String:
	match layer:
		Layer.RUG:
			return _rug_cells.get(cell, "")
		Layer.FLOOR:
			return _floor_cells.get(cell, "")
		Layer.SURFACE:
			return _surface_cells.get(cell, "")
	return ""


## uid des Wand-Items, das den Slot `offset` der Wand `wall` belegt
## ("" = frei). Mehrzellige Wand-Items belegen jeden Slot ihrer Spanne.
func wall_item_at(wall: String, offset: int) -> String:
	return _wall_slots.get("%s:%d" % [wall, offset], "")


func wall_width(wall: String) -> int:
	return size.x if (wall == "N" or wall == "S") else size.y


## Begehbar für Gooby: im Raum + kein bewegungsblockendes FLOOR-Item.
## Tür-Freihaltezonen sind begehbar (sie blocken nur den BAU).
func walkable(cell: Vector2i) -> bool:
	if not in_bounds(cell):
		return false
	var uid: String = _floor_cells.get(cell, "")
	if uid == "":
		return true
	return not bool(_items[uid]["def"].get("blocks_movement", true))


## BFS-Erreichbarkeit über begehbare Zellen (4er-Nachbarschaft) — die
## Blockade-Erkennung fürs „BODEN IST LAVA“-Gag (Doc F §7).
func is_reachable(from_cell: Vector2i, to_cell: Vector2i) -> bool:
	if not walkable(from_cell) or not walkable(to_cell):
		return false
	if from_cell == to_cell:
		return true
	var frontier: Array[Vector2i] = [from_cell]
	var seen := {from_cell: true}
	while not frontier.is_empty():
		var cell: Vector2i = frontier.pop_back()
		for step in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = cell + step
			if seen.has(next) or not walkable(next):
				continue
			if next == to_cell:
				return true
			seen[next] = true
			frontier.append(next)
	return false


## Erreicht Gooby von `from_cell` mindestens EINE der Zellen (z. B. Türzone)?
func is_zone_reachable(from_cell: Vector2i, zone: Array) -> bool:
	for cell: Variant in zone:
		if is_reachable(from_cell, _as_cell(cell)):
			return true
	return false


## Freie Standplätze: begehbar, ohne jedes FLOOR-Item, keine Türzone.
func free_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for y in size.y:
		for x in size.x:
			var cell := Vector2i(x, y)
			if blocked.has(cell) or _floor_cells.has(cell):
				continue
			cells.append(cell)
	return cells


## Serialisierung ins Save-Format (Doc D §1.4) — deterministisch sortiert.
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
		if item.has("wall"):
			entry["wall"] = item["wall"]
		out.append(entry)
	return out


## Rekonstruiert ein Grid aus Save-Items + Katalog-Defs. Unbekannte Items und
## Kollisions-Konflikte (Katalog-Update!) landen in "leftovers" — der Aufrufer
## legt sie ins Lager (Doc D §1.4: niemals Daten verlieren, weich degradieren).
##
## Zwei Durchläufe: erst alle Träger (RUG/FLOOR/WALL), dann die
## SURFACE-Aufbauten. `to_items_array` sortiert nach uid — ein SURFACE-Item
## mit kleinerer uid als sein Träger würde in Array-Reihenfolge sonst an
## `needs_surface` scheitern und still im Lager landen (E9 P1-1).
static func from_save(
	entries: Array, defs: Dictionary, grid_size: Vector2i, blocked_cells: Array = [], doors := {}
) -> Dictionary:
	var grid := GridData.new(grid_size, blocked_cells, doors)
	var leftovers: Array = []
	var surface_entries: Array = []
	for entry: Variant in entries:
		if not (entry is Dictionary) or not defs.has(str(entry.get("item", ""))):
			leftovers.append(entry)
			continue
		var def: Dictionary = defs[str(entry["item"])]
		if int(def["layer"]) == Layer.SURFACE:
			surface_entries.append(entry)
			continue
		if not grid._place_saved_entry(def, entry)["ok"]:
			leftovers.append(entry)
	for entry: Dictionary in surface_entries:
		if not grid._place_saved_entry(defs[str(entry["item"])], entry)["ok"]:
			leftovers.append(entry)
	return {"grid": grid, "leftovers": leftovers}


## Ein Save-Entry (Boden ODER Wand) platzieren — Helfer für from_save.
func _place_saved_entry(def: Dictionary, entry: Dictionary) -> Dictionary:
	var uid := str(entry.get("uid", ""))
	var at_raw: Array = entry.get("at", [0, 0])
	if entry.has("wall"):
		return place_wall(def, str(entry["wall"]), int(at_raw[0]), uid)
	var at := Vector2i(int(at_raw[0]), int(at_raw[1]))
	return place(def, at, int(entry.get("rot", 0)), uid)


## Welt-Position (Raum-lokal, XZ-Ebene) der Zellen-Mitte eines Footprints.
## Einzelzellen-Mitte: world_center(cell, Vector2i.ONE, 0).
static func world_center(at: Vector2i, footprint: Vector2i, rot: int) -> Vector3:
	var fp := rotated_footprint(footprint, rot)
	var center := Vector2(at) + Vector2(fp) * 0.5
	return Vector3(center.x * CELL_SIZE, 0.0, center.y * CELL_SIZE)


## Zelle unter einer (raumlokalen) Welt-Position.
static func cell_of(pos: Vector3) -> Vector2i:
	return Vector2i(int(floor(pos.x / CELL_SIZE)), int(floor(pos.z / CELL_SIZE)))


# ── intern ───────────────────────────────────────────────────────────────────


func _make_item(def: Dictionary, uid: String) -> Dictionary:
	return {"uid": uid, "def": def, "at": Vector2i.ZERO, "rot": 0}


func _write_cells(item: Dictionary, uid: String) -> void:
	var def: Dictionary = item["def"]
	if item.has("wall"):
		for slot in int(def["wall_size"]):
			_wall_slots["%s:%d" % [item["wall"], item["at"].x + slot]] = uid
		return
	for cell in cells_for(item["at"], def["footprint"], item["rot"]):
		match int(def["layer"]):
			Layer.RUG:
				_rug_cells[cell] = uid
			Layer.FLOOR:
				_floor_cells[cell] = uid
			Layer.SURFACE:
				_surface_cells[cell] = uid


func _erase_cells(uid: String) -> void:
	for map: Dictionary in [_rug_cells, _floor_cells, _surface_cells, _wall_slots]:
		for key: Variant in map.keys():
			if map[key] == uid:
				map.erase(key)


func _taken(map: Dictionary, cell: Vector2i, ignore_uid: String) -> bool:
	var uid: String = map.get(cell, "")
	return uid != "" and uid != ignore_uid


func _has_surface_below(cell: Vector2i) -> bool:
	var uid: String = _floor_cells.get(cell, "")
	if uid == "":
		return false
	return bool(_items[uid]["def"].get("surface", false))


static func _as_cell(value: Variant) -> Vector2i:
	if value is Vector2i:
		return value
	if value is Array and value.size() >= 2:
		return Vector2i(int(value[0]), int(value[1]))
	return Vector2i(-1, -1)
