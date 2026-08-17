class_name RoomDefs
extends RefCounted
## Raum-Definitionen (W2a HOUSE) — lädt `data/rooms.json` (Raum-Maße, Türen,
## Fenster, Farben) und `data/default_layouts.json` (liebevolles Start-Layout,
## zugleich Migrations-„Umzugstag“-Layout). Statisch + headless-testbar.
##
## Türen sind DOOR_WIDTH Zellen breit; vor jeder Tür liegt eine
## DOOR_DEPTH Zellen tiefe Freihaltezone (Doc D §1.2: nie bebaubar, aber
## begehbar — die Blockade-Erkennung prüft Erreichbarkeit dieser Zone).

const ROOMS_PATH := "res://scripts/home/data/rooms.json"
const LAYOUTS_PATH := "res://scripts/home/data/default_layouts.json"
const DOOR_WIDTH := 2
const DOOR_DEPTH := 2
const ROUTE_PREFIX := "home/"

static var _rooms: Dictionary = {}
static var _layouts: Dictionary = {}
static var _loaded := false


## id -> Raum-Def (grid: Vector2i, doors/windows: Array, Farben als Color).
static func rooms() -> Dictionary:
	_ensure_loaded()
	return _rooms


static func room(room_id: String) -> Dictionary:
	return rooms().get(room_id, {})


static func ids() -> Array:
	var out := rooms().keys()
	out.sort()
	return out


static func door(room_id: String, door_id: String) -> Dictionary:
	for entry: Dictionary in room(room_id).get("doors", []):
		if entry.get("id", "") == door_id:
			return entry
	return {}


## Freihaltezone einer Tür (DOOR_WIDTH × DOOR_DEPTH Zellen im Raum).
static func door_zone(room_def: Dictionary, door_def: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var grid: Vector2i = room_def.get("grid", Vector2i(1, 1))
	var offset := int(door_def.get("offset", 0))
	var wall := str(door_def.get("wall", "N"))
	for i in DOOR_WIDTH:
		for d in DOOR_DEPTH:
			match wall:
				"N":
					cells.append(Vector2i(offset + i, d))
				"S":
					cells.append(Vector2i(offset + i, grid.y - 1 - d))
				"W":
					cells.append(Vector2i(d, offset + i))
				"E":
					cells.append(Vector2i(grid.x - 1 - d, offset + i))
	return cells


## Alle Tür-Freihaltezonen eines Raums (für GridData.blocked).
static func blocked_cells(room_def: Dictionary) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for door_def: Dictionary in room_def.get("doors", []):
		cells.append_array(door_zone(room_def, door_def))
	return cells


## Tür-Spannen pro Wand (für GridData.wall_blocked: Wand-Items ausschließen).
static func wall_door_spans(room_def: Dictionary) -> Dictionary:
	var spans := {}
	for door_def: Dictionary in room_def.get("doors", []):
		var wall := str(door_def.get("wall", "N"))
		var offset := int(door_def.get("offset", 0))
		if not spans.has(wall):
			spans[wall] = []
		spans[wall].append([offset, offset + DOOR_WIDTH])
	return spans


## Außenwände eines Raums: {"N": "strasse"|"garten"|"himmel"}. Nur hier
## dürfen Fenster hängen (Doc D §1.2), und die Vista bestimmt, welches
## Diorama hinter der Scheibe läuft.
static func exterior_walls(room_def: Dictionary) -> Dictionary:
	var raw: Variant = room_def.get("walls", {})
	if not (raw is Dictionary):
		return {}
	var out: Dictionary = {}
	for wall: Variant in raw:
		if GridData.WALLS.has(str(wall)):
			out[str(wall)] = str(raw[wall])
	return out


## Fertig konfiguriertes (leeres) GridData für einen Raum.
static func make_grid(room_id: String) -> GridData:
	var room_def := room(room_id)
	var grid: Vector2i = room_def.get("grid", Vector2i(8, 8))
	return GridData.new(
		grid, blocked_cells(room_def), wall_door_spans(room_def), exterior_walls(room_def)
	)


## Raumlokale Welt-Position der Türmitte (Boden, XZ-Ebene).
static func door_world_pos(room_def: Dictionary, door_def: Dictionary) -> Vector3:
	var grid: Vector2i = room_def.get("grid", Vector2i(1, 1))
	var offset := int(door_def.get("offset", 0))
	var half := DOOR_WIDTH * 0.5 * GridData.CELL_SIZE
	match str(door_def.get("wall", "N")):
		"N":
			return Vector3(offset * GridData.CELL_SIZE + half, 0.0, 0.0)
		"S":
			return Vector3(offset * GridData.CELL_SIZE + half, 0.0, grid.y * GridData.CELL_SIZE)
		"W":
			return Vector3(0.0, 0.0, offset * GridData.CELL_SIZE + half)
	return Vector3(grid.x * GridData.CELL_SIZE, 0.0, offset * GridData.CELL_SIZE + half)


## W15/DOORTRAVEL: Tür-Anker (raumlokal) — Türmitte am Boden plus
## Innenrichtung; Basis der additiven Quell↔Ziel-Ausrichtung der Tür-Fahrt
## (DoorTravelFahrt.ziel_ausrichtung). {} bei unbekannter Tür.
static func door_anker(room_id: String, door_id: String) -> Dictionary:
	var door_def := door(room_id, door_id)
	if door_def.is_empty():
		return {}
	return {
		"pos": door_world_pos(room(room_id), door_def),
		"inward": wall_inward(str(door_def.get("wall", "N"))),
	}


## Richtung von der Wand in den Raum hinein.
static func wall_inward(wall: String) -> Vector3:
	match wall:
		"N":
			return Vector3(0, 0, 1)
		"S":
			return Vector3(0, 0, -1)
		"W":
			return Vector3(1, 0, 0)
	return Vector3(-1, 0, 0)


## Router-Target eines Raums (W1a-SceneRouter-Routen, s. Handoff W2a-house).
static func route_target(room_id: String) -> StringName:
	return StringName(ROUTE_PREFIX + room_id)


## {StringName: scene_path} für SceneRouter.register_routes().
static func route_table() -> Dictionary:
	var routes := {}
	for room_id: String in ids():
		routes[route_target(room_id)] = rooms()[room_id]["scene"]
	return routes


## Default-Platzierungen eines Raums (Save-Format-Einträge OHNE uid).
static func default_layout(room_id: String) -> Array:
	_ensure_loaded()
	return _layouts.get("rooms", {}).get(room_id, [])


## Start-Lager (Umzugstag: Bett liegt HIER, nicht im Schlafzimmer!).
static func default_storage() -> Array:
	_ensure_loaded()
	return _layouts.get("storage", [])


## Cache leeren (Tests / Pack-Hot-Reload).
static func reset_cache() -> void:
	_rooms = {}
	_layouts = {}
	_loaded = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_rooms = _load_rooms()
	_layouts = _load_json(LAYOUTS_PATH)
	_loaded = true


static func _load_rooms() -> Dictionary:
	var out: Dictionary = {}
	var raw := _load_json(ROOMS_PATH)
	for entry: Variant in raw.get("rooms", []):
		if not (entry is Dictionary) or str(entry.get("id", "")) == "":
			continue
		var room_def: Dictionary = entry.duplicate(true)
		var grid_raw: Array = room_def.get("grid", [8, 8])
		room_def["grid"] = Vector2i(int(grid_raw[0]), int(grid_raw[1]))
		room_def["floor_color"] = Color(str(room_def.get("floor_color", "#C9A36B")))
		room_def["wall_color"] = Color(str(room_def.get("wall_color", "#FFF6EC")))
		out[room_def["id"]] = room_def
	return out


static func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Raum-Daten fehlen: %s" % path)
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_error("Raum-Daten kaputt: %s (%s)" % [path, json.get_error_message()])
		return {}
	return json.data if json.data is Dictionary else {}
