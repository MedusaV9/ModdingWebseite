class_name RoomBase
extends Node3D
## Basis aller Raum-Szenen (W2a HOUSE). Baut den Raum PROZEDURAL aus
## RoomDefs-Daten (Boden/Wände/Fenster-Platzhalter, Tür-Nodes, Grid-Mount,
## Gooby-Spawn, NavigationRegion3D, Kamera-Rig, warmes Licht) und verdrahtet
## Baumodus + Tür-Reisen + Blockade-Gag.
##
## Router-Verträge (W1a): `ready_for_reveal` nach dem Aufbau,
## `receive_params({door_id})` vor add_child → Gooby spawnt an dieser Tür.

signal ready_for_reveal
signal door_tapped(door_id: String)
signal build_mode_toggled(active: bool)

const WALL_HEIGHT := 2.5
const WALL_THICKNESS := 0.1
const FENCE_HEIGHT := 0.55
const REBAKE_DEBOUNCE_S := 0.5

@export var room_id := "living"

## Tests injizieren hier ein frisches GameState (statt /root/GameState).
var game_state_override: Object = null
var grid: GridData

var _room_def: Dictionary = {}
var _gs: Object = null
var _spawn_door_id := ""
var _gooby: GoobyHome
var _doors: Dictionary = {}
var _furniture: Dictionary = {}
var _nav_region: NavigationRegion3D
var _blockers: Node3D
var _grid_mount: Node3D
var _overlay: GridOverlay
var _camera_rig: HomeCameraRig
var _build_mode: BuildMode
var _ui_layer: CanvasLayer
var _bubble: DialogBubble
var _choice: Control
var _rebake_pending := false
var _uid_seq := 0


func _ready() -> void:
	_room_def = RoomDefs.room(room_id)
	if _room_def.is_empty():
		push_error("Unbekannter Raum: %s" % room_id)
		return
	HomeState.register_slice()
	_resolve_game_state()
	_load_grid()
	_build_environment()
	_build_nav_and_floor()
	_build_walls()
	_build_doors()
	_build_grid_mount()
	rebuild_furniture()
	_build_camera()
	_build_ui()
	_spawn_gooby()
	_announce_moving_day()
	_emit_ready_for_reveal.call_deferred()


## Router-Params-Contract (W1a): {door_id} = Ziel-Tür im NEUEN Raum.
func receive_params(params: Dictionary) -> void:
	_spawn_door_id = str(params.get("door_id", ""))


func game_state() -> Object:
	return _gs


func grid_mount() -> Node3D:
	return _grid_mount


func gooby() -> GoobyHome:
	return _gooby


func room_def() -> Dictionary:
	return _room_def


func open_build_mode() -> void:
	_build_mode.open()


func is_build_mode_active() -> bool:
	return _build_mode != null and _build_mode.is_active()


## Gooby-Bubble (W1c DialogBubble).
func say(text: String) -> void:
	_bubble.show_lines([text])


func set_furniture_visible(uid: String, furniture_visible: bool) -> void:
	if _furniture.has(uid):
		(_furniture[uid] as Node3D).visible = furniture_visible


## Trägerhöhe für SURFACE-Items auf einer Zelle.
func surface_height_at(cell: Vector2i) -> float:
	var uid := grid.item_at(cell, GridData.Layer.FLOOR)
	if uid != "" and _furniture.has(uid):
		return (_furniture[uid] as FurnitureNode).top_y()
	return 0.4


## Alle Möbel-Nodes aus dem Grid neu aufbauen (nach Bau-Commits).
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
	request_rebake()


## Navmesh-Rebake, debounced (Doc F §7). Synchron gebaked (Räume sind klein;
## async-Bake + Szenen-Freigabe wäre ein Race — M2-Optimierung).
func request_rebake() -> void:
	if _rebake_pending or _nav_region == null or not is_inside_tree():
		return
	_rebake_pending = true
	get_tree().create_timer(REBAKE_DEBOUNCE_S).timeout.connect(_on_rebake_timeout)


func _on_rebake_timeout() -> void:
	_rebake_pending = false
	if is_inside_tree():
		_nav_region.bake_navigation_mesh(false)


## Hammer-Aufbau-Gag (Doc D §3.1): Gooby hämmert, Qualm, Jubel.
func play_hammer_gag(world_pos: Vector3) -> void:
	if _gooby == null:
		return
	_gooby.set_wander_enabled(false)
	await _gooby.walk_to(world_pos + Vector3(0.5, 0.0, 0.5), 3.0)
	_gooby.rig.play_clip("build_hammer")
	var smoke := _make_smoke(world_pos)
	# Sound-Platzhalter: Hammer-SFX folgt (Asset-Backlog W4-POLISH).
	await get_tree().create_timer(1.8).timeout
	smoke.emitting = false
	_gooby.rig.play_clip("celebrate")
	_gooby.rig.set_emotion("ecstatic")
	say(I18nService.t("build.hammer_fertig"))
	await get_tree().create_timer(1.2).timeout
	smoke.queue_free()
	_gooby.rig.set_emotion("happy")
	_gooby.set_wander_enabled(not is_build_mode_active())


func _resolve_game_state() -> void:
	_gs = game_state_override
	if _gs == null:
		var autoload := get_node_or_null("/root/GameState")
		if autoload != null and autoload.is_loaded():
			_gs = autoload


func _load_grid() -> void:
	if _gs != null:
		HomeState.ensure_initialized(_gs)
		grid = HomeState.load_room_grid(_gs, room_id)
		return
	grid = RoomDefs.make_grid(room_id)
	for entry: Dictionary in RoomDefs.default_layout(room_id):
		var def := FurnitureCatalog.def(str(entry.get("item", "")))
		if def.is_empty():
			continue
		_uid_seq += 1
		var uid := "room-%04d" % _uid_seq
		if entry.has("wall"):
			grid.place_wall(def, str(entry["wall"]), int(entry["at"][0]), uid)
		else:
			var at := Vector2i(int(entry["at"][0]), int(entry["at"][1]))
			grid.place(def, at, int(entry.get("rot", 0)), uid)


# ── Aufbau ───────────────────────────────────────────────────────────────────


func _world_size() -> Vector2:
	var cells: Vector2i = _room_def["grid"]
	return Vector2(cells.x * GridData.CELL_SIZE, cells.y * GridData.CELL_SIZE)


func _is_outdoor() -> bool:
	return bool(_room_def.get("outdoor", false))


func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#BFE3F2") if _is_outdoor() else Color("#FFF1DC")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Draußen neutral-kühl (Gras bleibt grün), drinnen warm-gemütlich.
	env.ambient_light_color = (Color(0.92, 0.97, 1.0) if _is_outdoor() else Color(1.0, 0.93, 0.84))
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.light_color = (Color(1.0, 0.98, 0.92) if _is_outdoor() else Color(1.0, 0.9, 0.75))
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
	# MUSS zur Default-Map passen (0.25) — sonst lehnt der NavServer den Bake ab.
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	_nav_region.navigation_mesh = nav_mesh
	add_child(_nav_region)
	var size := _world_size()
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.name = "Floor"
	var box := BoxMesh.new()
	box.size = Vector3(size.x, 0.12, size.y)
	floor_mesh.mesh = box
	floor_mesh.material_override = _flat_material(_room_def["floor_color"])
	floor_mesh.position = Vector3(size.x * 0.5, -0.06, size.y * 0.5)
	_nav_region.add_child(floor_mesh)
	_blockers = Node3D.new()
	_blockers.name = "Blockers"
	_nav_region.add_child(_blockers)


func _build_walls() -> void:
	var spans: Dictionary = RoomDefs.wall_door_spans(_room_def)
	# S-Wand (Kameraseite) bleibt innen offen, damit die Sicht frei ist.
	var walls: Array[String] = ["N", "W", "E"]
	if _is_outdoor():
		walls.append("S")
	for wall: String in walls:
		_build_wall_segments(wall, spans.get(wall, []))
	for window: Dictionary in _room_def.get("windows", []):
		_build_window(window)


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


## Wand-Quader von Zelle `from` bis `to` (exklusiv), von y0 bis y1.
func _add_wall_box(wall: String, from: int, to: int, y0: float, y1: float) -> void:
	if to <= from or y1 <= y0:
		return
	var length := (to - from) * GridData.CELL_SIZE
	var mid := (from + to) * 0.5 * GridData.CELL_SIZE
	var size := _world_size()
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
	mesh.name = "Wall_%s_%d_%d" % [wall, from, to]
	add_child(mesh)


## Fenster-Platzhalter: heller Emissive-Quad AUF der Wand (Doc D §1.2 —
## kein CSG; Vista-Diorama = M2-Backlog).
func _build_window(window: Dictionary) -> void:
	var wall := str(window.get("wall", "N"))
	var offset := int(window.get("offset", 0))
	var cells := int(window.get("size", 2))
	var width := cells * GridData.CELL_SIZE
	var mesh := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(width, 0.9)
	mesh.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#CFEFFF")
	mat.emission_enabled = true
	mat.emission = Color("#BFE8FF")
	mat.emission_energy_multiplier = 0.8
	mesh.material_override = mat
	var along := offset * GridData.CELL_SIZE + width * 0.5
	var size := _world_size()
	var y := 1.5
	match wall:
		"N":
			mesh.position = Vector3(along, y, 0.02)
		"S":
			mesh.position = Vector3(along, y, size.y - 0.02)
			mesh.rotation.y = PI
		"W":
			mesh.position = Vector3(0.02, y, along)
			mesh.rotation.y = -PI / 2.0
		"E":
			mesh.position = Vector3(size.x - 0.02, y, along)
			mesh.rotation.y = PI / 2.0
	var frame := MeshInstance3D.new()
	var frame_box := BoxMesh.new()
	frame_box.size = Vector3(width + 0.1, 1.0, 0.04)
	frame.mesh = frame_box
	frame.material_override = _flat_material(Color(0.95, 0.9, 0.82))
	frame.position = Vector3(0.0, 0.0, -0.03)
	mesh.add_child(frame)
	add_child(mesh)


func _build_doors() -> void:
	for door_def: Dictionary in _room_def.get("doors", []):
		var door := DoorTransition.new()
		door.setup(
			str(door_def["id"]), str(door_def.get("to", "")), str(door_def.get("to_door", ""))
		)
		door.position = RoomDefs.door_world_pos(_room_def, door_def)
		door.rotation.y = _inward_yaw(str(door_def.get("wall", "N")))
		door.tapped.connect(_on_door_tapped)
		door.stuck_started.connect(func() -> void: say(I18nService.t("home.tuer.stuck")))
		add_child(door)
		_doors[str(door_def["id"])] = door


func _build_grid_mount() -> void:
	_grid_mount = Node3D.new()
	_grid_mount.name = "GridMount"
	add_child(_grid_mount)
	_overlay = GridOverlay.new()
	_overlay.name = "GridOverlay"
	add_child(_overlay)
	_overlay.setup(grid)


func _build_camera() -> void:
	_camera_rig = HomeCameraRig.new()
	_camera_rig.name = "CameraRig"
	add_child(_camera_rig)
	_camera_rig.setup(_world_size())


func _build_ui() -> void:
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 5
	add_child(_ui_layer)
	var bubble_scene: PackedScene = load("res://scripts/ui/dialog_bubble.tscn")
	_bubble = bubble_scene.instantiate()
	_ui_layer.add_child(_bubble)
	_build_mode = BuildMode.new()
	_build_mode.name = "BuildMode"
	add_child(_build_mode)
	_build_mode.setup(self, grid, _overlay, _ui_layer, _camera_rig)
	_build_mode.furniture_changed.connect(rebuild_furniture)
	_build_mode.opened.connect(_on_build_opened)
	_build_mode.closed.connect(_on_build_closed)


func _spawn_gooby() -> void:
	_gooby = GoobyHome.new()
	_gooby.name = "Gooby"
	_gooby.grid = grid
	add_child(_gooby)
	_camera_rig.follow_target = _gooby
	var spawn := Vector3.ZERO
	var door_def := RoomDefs.door(room_id, _spawn_door_id)
	if not door_def.is_empty():
		var inward := RoomDefs.wall_inward(str(door_def.get("wall", "N")))
		spawn = RoomDefs.door_world_pos(_room_def, door_def) + inward * 0.7
	else:
		var free := grid.free_cells()
		var center := Vector2i(grid.size.x / 2, grid.size.y / 2)
		var best := center
		if not free.is_empty():
			free.sort_custom(
				func(a: Vector2i, b: Vector2i) -> bool:
					return (a - center).length_squared() < (b - center).length_squared()
			)
			best = free[0]
		spawn = GridData.world_center(best, Vector2i.ONE, 0)
	_gooby.position = spawn


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
	if bool(def.get("blocks_movement", false)) and not entry.has("wall"):
		_blockers.add_child(node)
	else:
		_grid_mount.add_child(node)
	_furniture[uid] = node


# ── Türen & Blockade-Gag ─────────────────────────────────────────────────────


func _on_door_tapped(door_id: String) -> void:
	if is_build_mode_active() or _choice != null:
		return
	var door: DoorTransition = _doors.get(door_id)
	var door_def := RoomDefs.door(room_id, door_id)
	if door == null or door.is_busy() or door_def.is_empty():
		return
	door_tapped.emit(door_id)
	var zone := RoomDefs.door_zone(_room_def, door_def)
	if not grid.is_zone_reachable(_gooby.current_cell(), zone):
		_blocked_flow()
		return
	var router := get_node_or_null("/root/SceneRouter")
	if router != null:
		router.preload_target(RoomDefs.route_target(door.target_room))
	_gooby.set_wander_enabled(false)
	door.travel(_gooby, _ui_layer)


## Doc F §6: Beschwerde-Bubble + Choice „Ich baue um“ / „BODEN IST LAVA“.
func _blocked_flow() -> void:
	_gooby.set_wander_enabled(false)
	_gooby.rig.set_emotion("sad")
	say(I18nService.t("home.blocked.bubble"))
	_choice = PanelContainer.new()
	_choice.theme_type_variation = "AcCard"
	_choice.set_anchors_preset(Control.PRESET_CENTER)
	_choice.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_choice.grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_choice.add_child(box)
	var rebuild := Button.new()
	rebuild.text = I18nService.t("home.blocked.umbauen")
	rebuild.theme_type_variation = "PrimaryButton"
	rebuild.pressed.connect(_on_blocked_choice.bind(false))
	box.add_child(rebuild)
	var lava := Button.new()
	lava.text = I18nService.t("home.blocked.lava")
	lava.theme_type_variation = "AccentButton"
	lava.pressed.connect(_on_blocked_choice.bind(true))
	box.add_child(lava)
	_ui_layer.add_child(_choice)


func _on_blocked_choice(lava: bool) -> void:
	_choice.queue_free()
	_choice = null
	if lava:
		_spidergooby_flow()
		return
	_gooby.set_wander_enabled(true)
	open_build_mode()


func _spidergooby_flow() -> void:
	say(I18nService.t("home.blocked.spidergooby"))
	await _gooby.spidergooby_gag()
	open_build_mode()


func _on_build_opened() -> void:
	build_mode_toggled.emit(true)
	_gooby.set_wander_enabled(false)
	_gooby.rig.play_clip("sit")
	say(I18nService.t("home.gooby.watch"))


func _on_build_closed() -> void:
	build_mode_toggled.emit(false)
	_gooby.rig.play_clip("idle")
	_gooby.set_wander_enabled(true)


func _unhandled_input(event: InputEvent) -> void:
	var pressed: bool = (
		(event is InputEventMouseButton and event.pressed)
		or (event is InputEventScreenTouch and event.pressed)
	)
	if not pressed:
		return
	for door_id: String in _doors:
		var door: DoorTransition = _doors[door_id]
		if door.is_busy():
			door.skip()


func _announce_moving_day() -> void:
	if _gs != null and bool(_gs.get_value("home.movingDay", false)):
		say(I18nService.t("home.umzug"))
		_gs.set_value("home.movingDay", false)


func _emit_ready_for_reveal() -> void:
	await get_tree().process_frame
	ready_for_reveal.emit()


func _inward_yaw(wall: String) -> float:
	match wall:
		"N":
			return 0.0
		"S":
			return PI
		"W":
			return PI / 2.0
	return -PI / 2.0


func _make_smoke(world_pos: Vector3) -> GPUParticles3D:
	var smoke := GPUParticles3D.new()
	smoke.amount = 20
	smoke.lifetime = 0.9
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 40.0
	mat.initial_velocity_min = 0.4
	mat.initial_velocity_max = 0.9
	mat.gravity = Vector3.ZERO
	mat.scale_min = 0.6
	mat.scale_max = 1.4
	smoke.process_material = mat
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	smoke.draw_pass_1 = mesh
	smoke.position = world_pos + Vector3(0, 0.4, 0)
	smoke.emitting = true
	add_child(smoke)
	return smoke


func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.9
	return mat
