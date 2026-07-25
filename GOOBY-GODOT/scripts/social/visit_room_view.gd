class_name VisitRoomView
extends Node3D
## Read-only-Rekonstruktion EINES Raums aus einem Haus-Snapshot (W3c VISIT,
## Doc C §3.4 Punkt 3): Boden/Wände/Türen aus den W2a-RoomDefs, Möbel aus dem
## Snapshot-Grid (FurnitureNode). Kein Baumodus, keine Tür-Reisen — Türen
## melden nur `door_tapped`, den Raumwechsel macht die Besuchs-Szene.
##
## Für „Bauen während Besuch“ (Host) und BUILD_DELTA (Gast) gibt es
## place_item/remove_at/apply_remote_delta — Best-Effort, Doc C §3.4 Punkt 5.

signal door_tapped(door_id: String)

const WALL_HEIGHT := 2.5
const WALL_THICKNESS := 0.1
const FENCE_HEIGHT := 0.55

var room_id := ""
var grid: GridData

var _room_def: Dictionary = {}
var _furniture: Dictionary = {}
var _grid_mount: Node3D
var _nav_region: NavigationRegion3D
var _delta_seq := 0


## Baut den Raum komplett auf (vor add_child rufen oder danach — egal,
## alles ist Code-only).
func build(p_room_id: String, snapshot: Dictionary) -> bool:
	room_id = p_room_id
	_room_def = RoomDefs.room(room_id)
	if _room_def.is_empty():
		return false
	var made := VisitSnapshot.make_grid(snapshot, room_id)
	grid = made["grid"]
	_build_environment()
	_build_nav_and_floor()
	_build_walls()
	_build_doors()
	_grid_mount = Node3D.new()
	_grid_mount.name = "GridMount"
	add_child(_grid_mount)
	rebuild_furniture()
	return true


func world_size() -> Vector2:
	var cells: Vector2i = _room_def.get("grid", Vector2i(8, 8))
	return Vector2(cells.x * GridData.CELL_SIZE, cells.y * GridData.CELL_SIZE)


func room_def() -> Dictionary:
	return _room_def


## Spawn-Punkt: erste Tür (+ Stück in den Raum) oder freie Zelle nahe Mitte.
func spawn_pos(door_id := "") -> Vector3:
	var door_def := RoomDefs.door(room_id, door_id)
	if door_def.is_empty():
		var doors: Array = _room_def.get("doors", [])
		if not doors.is_empty():
			door_def = doors[0]
	if not door_def.is_empty():
		var inward := RoomDefs.wall_inward(str(door_def.get("wall", "N")))
		return RoomDefs.door_world_pos(_room_def, door_def) + inward * 0.7
	var free := grid.free_cells()
	if free.is_empty():
		return GridData.world_center(Vector2i(grid.size.x / 2, grid.size.y / 2), Vector2i.ONE, 0)
	var center := Vector2i(grid.size.x / 2, grid.size.y / 2)
	free.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return (a - center).length_squared() < (b - center).length_squared()
	)
	return GridData.world_center(free[0], Vector2i.ONE, 0)


func rebuild_furniture() -> void:
	for uid: String in _furniture:
		(_furniture[uid] as Node).queue_free()
	_furniture = {}
	var surface_entries: Array = []
	for entry: Dictionary in grid.to_items_array():
		var def := FurnitureCatalog.def(str(entry["item"]))
		if def.is_empty():
			continue
		if int(def["layer"]) == GridData.Layer.SURFACE:
			surface_entries.append(entry)
		else:
			_spawn_furniture(entry, def)
	for entry: Dictionary in surface_entries:
		_spawn_furniture(entry, FurnitureCatalog.def(str(entry["item"])))
	_bake_nav()


## Host-Bau während Besuch: platzieren (liefert {ok, reason, uid}).
func place_item(item_id: String, cell: Vector2i, rot := 0) -> Dictionary:
	var def := FurnitureCatalog.def(item_id)
	if def.is_empty():
		return {"ok": false, "reason": GridData.REASON_UNKNOWN_ITEM, "uid": ""}
	_delta_seq += 1
	var uid := "visit-h-%d" % _delta_seq
	var placed := grid.place(def, cell, rot, uid)
	if placed["ok"]:
		rebuild_furniture()
	return {"ok": placed["ok"], "reason": placed["reason"], "uid": uid}


## Host-Bau: oberstes Item auf der Zelle entfernen ({ok, item, uid}).
func remove_at(cell: Vector2i) -> Dictionary:
	for layer in [GridData.Layer.SURFACE, GridData.Layer.FLOOR, GridData.Layer.RUG]:
		var uid := grid.item_at(cell, layer)
		if uid != "":
			var item := grid.remove_item(uid)
			rebuild_furniture()
			return {"ok": true, "item": str(item["def"]["id"]), "uid": uid}
	return {"ok": false, "item": "", "uid": ""}


## Gast: BUILD_DELTA anwenden (Best-Effort, Konfliktregel Tür-Teleport).
func apply_remote_delta(delta: Dictionary, occupant_cell: Vector2i) -> Dictionary:
	var res := VisitLogic.apply_build_delta(grid, delta, occupant_cell)
	if res["ok"]:
		rebuild_furniture()
	return res


func surface_height_at(cell: Vector2i) -> float:
	var uid := grid.item_at(cell, GridData.Layer.FLOOR)
	if uid != "" and _furniture.has(uid):
		return (_furniture[uid] as FurnitureNode).top_y()
	return 0.4


# ── Aufbau (kompakte Variante der RoomBase-Optik) ────────────────────────────


func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#BFE3F2") if _is_outdoor() else Color("#FFF1DC")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = (Color(0.92, 0.97, 1.0) if _is_outdoor() else Color(1.0, 0.93, 0.84))
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.98, 0.92) if _is_outdoor() else Color(1.0, 0.9, 0.75)
	sun.light_energy = 0.7
	sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	sun.shadow_enabled = true
	add_child(sun)


func _build_nav_and_floor() -> void:
	_nav_region = NavigationRegion3D.new()
	_nav_region.name = "NavRegion"
	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_radius = 0.28
	nav_mesh.agent_height = 1.0
	nav_mesh.agent_max_climb = 0.3
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	_nav_region.navigation_mesh = nav_mesh
	add_child(_nav_region)
	var size := world_size()
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"
	var box := BoxMesh.new()
	box.size = Vector3(size.x, 0.12, size.y)
	floor_mesh.mesh = box
	floor_mesh.material_override = _flat_material(_room_def["floor_color"])
	floor_mesh.position = Vector3(size.x * 0.5, -0.06, size.y * 0.5)
	_nav_region.add_child(floor_mesh)


func _build_walls() -> void:
	var spans: Dictionary = RoomDefs.wall_door_spans(_room_def)
	var walls: Array[String] = ["N", "W", "E"]
	if _is_outdoor():
		walls.append("S")
	for wall: String in walls:
		_build_wall_segments(wall, spans.get(wall, []))


func _build_wall_segments(wall: String, door_spans: Array) -> void:
	var width := grid.wall_width(wall)
	var height := FENCE_HEIGHT if _is_outdoor() else WALL_HEIGHT
	var spans_sorted := door_spans.duplicate()
	spans_sorted.sort_custom(func(a: Array, b: Array) -> bool: return int(a[0]) < int(b[0]))
	var cursor := 0
	for span: Array in spans_sorted:
		_add_wall_box(wall, cursor, int(span[0]), 0.0, height)
		if not _is_outdoor():
			_add_wall_box(wall, int(span[0]), int(span[1]), DoorTransition.DOOR_HEIGHT, height)
		cursor = int(span[1])
	_add_wall_box(wall, cursor, width, 0.0, height)


func _add_wall_box(wall: String, from: int, to: int, y0: float, y1: float) -> void:
	if to <= from or y1 <= y0:
		return
	var length := (to - from) * GridData.CELL_SIZE
	var mid := (from + to) * 0.5 * GridData.CELL_SIZE
	var size := world_size()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	var wall_color: Color = _room_def["wall_color"]
	if _is_outdoor():
		wall_color = Color(0.55, 0.4, 0.28)
	var along_x := wall == "N" or wall == "S"
	box.size = (
		Vector3(length, y1 - y0, WALL_THICKNESS)
		if along_x
		else Vector3(WALL_THICKNESS, y1 - y0, length)
	)
	mesh.mesh = box
	mesh.material_override = _flat_material(wall_color)
	var y := (y0 + y1) * 0.5
	match wall:
		"N":
			mesh.position = Vector3(mid, y, -WALL_THICKNESS * 0.5)
		"S":
			mesh.position = Vector3(mid, y, size.y + WALL_THICKNESS * 0.5)
		"W":
			mesh.position = Vector3(-WALL_THICKNESS * 0.5, y, mid)
		"E":
			mesh.position = Vector3(size.x + WALL_THICKNESS * 0.5, y, mid)
	add_child(mesh)


## Türen: W2a-Optik + Tap, aber KEINE travel()-Reise — nur Signal.
func _build_doors() -> void:
	for door_def: Dictionary in _room_def.get("doors", []):
		var door := DoorTransition.new()
		door.setup(
			str(door_def["id"]), str(door_def.get("to", "")), str(door_def.get("to_door", ""))
		)
		door.position = RoomDefs.door_world_pos(_room_def, door_def)
		door.rotation.y = _inward_yaw(str(door_def.get("wall", "N")))
		door.tapped.connect(func(door_id: String) -> void: door_tapped.emit(door_id))
		add_child(door)


func _spawn_furniture(entry: Dictionary, def: Dictionary) -> void:
	var uid := str(entry["uid"])
	var node: FurnitureNode
	if entry.has("wall"):
		node = FurnitureNode.create_wall(
			def, str(entry["wall"]), int(entry["at"][0]), grid.size, uid
		)
	else:
		var at := Vector2i(int(entry["at"][0]), int(entry["at"][1]))
		node = FurnitureNode.create(def, at, int(entry.get("rot", 0)), uid)
		if node != null and int(def["layer"]) == GridData.Layer.SURFACE:
			node.position.y = surface_height_at(at)
	if node == null:
		return
	_grid_mount.add_child(node)
	_furniture[uid] = node


func _bake_nav() -> void:
	if _nav_region != null and is_inside_tree():
		_nav_region.bake_navigation_mesh(false)


func _is_outdoor() -> bool:
	return bool(_room_def.get("outdoor", false))


func _inward_yaw(wall: String) -> float:
	match wall:
		"N":
			return 0.0
		"S":
			return PI
		"W":
			return PI / 2.0
	return -PI / 2.0


func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	return mat
