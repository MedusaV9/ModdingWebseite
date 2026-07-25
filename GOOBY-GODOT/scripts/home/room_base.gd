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
## Wand-Ausschnitt eines Außenfensters (Doc D §1.2): genau so hoch, dass das
## Fenster-Modul (FurnitureNode-Lift 1.35 m) darin sitzt und der Blick auf das
## Straßen-Diorama frei ist.
const FENSTER_Y0 := 1.28
const FENSTER_Y1 := 2.3

@export var room_id := "living"

## Tests injizieren hier ein frisches GameState (statt /root/GameState).
var game_state_override: Object = null
## Tests/Screenshots erzwingen eine Uhrzeit (< 0 = echte Systemzeit).
var stunde_override := -1.0
var grid: GridData

var _room_def: Dictionary = {}
var _gs: Object = null
var _spawn_door_id := ""
var _gooby: GoobyHome
var _doors: Dictionary = {}
var _furniture: Dictionary = {}
var _dioramas: Dictionary = {}
var _nav_region: NavigationRegion3D
var _blockers: Node3D
var _grid_mount: Node3D
var _wall_mount: Node3D
var _overlay: GridOverlay
var _camera_rig: HomeCameraRig
var _build_mode: BuildMode
var _ui_layer: CanvasLayer
var _bubble: DialogBubble
var _choice: Control
var _rebake_pending := false
var _uid_seq := 0
var _fenster_energie := HomeLicht.FENSTER_TAG
var _fenster_stand := ""


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
	# Garten 2.0 (Doc D §6): Beete/Bauten/Sammel-Spots liegen NICHT im
	# Möbel-Grid, sondern im eigenen Garten-Grid — der Host baut sie auf.
	GardenHost.attach_to(self)
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


## UI-Ebene des Raums (Panels von Werkstatt/Goobay/Garten hängen sich hier ein).
func ui_layer() -> CanvasLayer:
	return _ui_layer


func camera_rig() -> HomeCameraRig:
	return _camera_rig


## Navmesh-Blocker-Mount (Garten-Bauten hängen sich hier ein, damit Gooby
## nicht durch Shed und Gewächshaus läuft).
func blockers() -> Node3D:
	return _blockers


func open_build_mode() -> void:
	_build_mode.open()


func is_build_mode_active() -> bool:
	return _build_mode != null and _build_mode.is_active()


## Gooby-Bubble (W1c DialogBubble).
func say(text: String) -> void:
	_bubble.show_lines([text])


func set_furniture_visible(uid: String, furniture_visible: bool) -> void:
	var node: Variant = _furniture.get(uid)
	if is_instance_valid(node) and node is Node3D:
		(node as Node3D).visible = furniture_visible


## Trägerhöhe für SURFACE-Items auf einer Zelle.
func surface_height_at(cell: Vector2i) -> float:
	var node: Variant = _furniture.get(grid.item_at(cell, GridData.Layer.FLOOR))
	if is_instance_valid(node) and node is FurnitureNode:
		return (node as FurnitureNode).top_y()
	return 0.4


## Alle Möbel-Nodes aus dem Grid neu aufbauen (nach Bau-Commits).
func rebuild_furniture() -> void:
	# Beim Szenen-Abbau kann ein Möbel-Node schon weg sein, während ein
	# nachgereichtes `furniture_changed` noch hier landet — nie hart casten.
	for node: Variant in _furniture.values():
		if is_instance_valid(node) and node is Node:
			(node as Node).queue_free()
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
	# Ein neu gehängtes Außenfenster schneidet ein Loch in die Wand — deshalb
	# nach jedem Bau-Commit prüfen, ob die Wände neu gesetzt werden müssen.
	if _fenster_signatur() != _fenster_stand:
		_build_walls()
	_rebuild_dioramas()
	request_rebake()


## Fenster-Dioramen (Doc D §1.2): pro Außenwand höchstens eins, und nur
## solange dort wirklich ein Fenster hängt — nach jedem Bau-Commit neu.
func _rebuild_dioramas() -> void:
	for diorama: Variant in _dioramas.values():
		if is_instance_valid(diorama) and diorama is Node:
			(diorama as Node).queue_free()
	_dioramas = {}
	var exterior := RoomDefs.exterior_walls(_room_def)
	for wall: String in exterior:
		var diorama := StreetDiorama.attach_if_needed(
			self, grid, _world_size(), wall, str(exterior[wall])
		)
		if diorama != null:
			_dioramas[wall] = diorama


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
## Reduced Motion (W4-P3 POLISH-16): kein Qualm, stark verkürzte Pausen.
func play_hammer_gag(world_pos: Vector3) -> void:
	if _gooby == null:
		return
	var reduced := _reduced_motion()
	_gooby.set_wander_enabled(false)
	await _gooby.walk_to(world_pos + Vector3(0.5, 0.0, 0.5), 3.0)
	_gooby.rig.play_clip("build_hammer")
	var smoke: GPUParticles3D = null
	if not reduced:
		smoke = _make_smoke(world_pos)
	AudioDirector.try_play(self, "build_hammer")
	await get_tree().create_timer(0.3 if reduced else 1.8).timeout
	if smoke != null:
		smoke.emitting = false
	_gooby.rig.play_clip("celebrate")
	_gooby.rig.set_emotion("ecstatic")
	say(I18nService.t("build.hammer_fertig"))
	await get_tree().create_timer(0.2 if reduced else 1.2).timeout
	if smoke != null:
		smoke.queue_free()
	_gooby.rig.set_emotion("happy")
	_gooby.set_wander_enabled(not is_build_mode_active())


func _reduced_motion() -> bool:
	var settings := get_node_or_null("/root/AppSettings")
	return settings != null and settings.is_reduced_motion()


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


## Raum-Licht (W4-P3 POLISH-6): HomeLicht-Profil pro Raum + Tageszeit-Lerp.
## Sonnen-Schatten bleiben AUS (Mobile-Budget A §7) — Gooby erdet ein
## Blob-Shadow (GoobyHome), das Füll-Licht bringt die Gemütlichkeit.
func _build_environment() -> void:
	var profil := HomeLicht.profil(room_id, _is_outdoor(), _stunde())
	var world_env := WorldEnvironment.new()
	world_env.name = "RaumLicht"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = profil["hintergrund"]
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = profil["ambient_farbe"]
	env.ambient_light_energy = profil["ambient_energie"]
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world_env.environment = env
	add_child(world_env)
	var sun := DirectionalLight3D.new()
	sun.name = "Sonne"
	sun.light_color = profil["sonnen_farbe"]
	sun.light_energy = profil["sonnen_energie"]
	sun.rotation_degrees = profil["sonnen_rotation"]
	sun.shadow_enabled = false
	add_child(sun)
	var fuell := OmniLight3D.new()
	fuell.name = "FuellLicht"
	fuell.light_color = profil["fuell_farbe"]
	fuell.light_energy = profil["fuell_energie"]
	var size := _world_size()
	fuell.omni_range = maxf(size.x, size.y) * 1.1
	fuell.omni_attenuation = 1.4
	fuell.position = Vector3(size.x * 0.5, WALL_HEIGHT * 0.9, size.y * 0.55)
	fuell.shadow_enabled = false
	add_child(fuell)
	_fenster_energie = profil["fenster_energie"]


## Uhrzeit mit Bruchteilen (Tests/Screenshots setzen stunde_override).
func _stunde() -> float:
	if stunde_override >= 0.0:
		return stunde_override
	var jetzt := Time.get_time_dict_from_system()
	return float(jetzt["hour"]) + float(jetzt["minute"]) / 60.0


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
	if _wall_mount != null:
		# Erst umbenennen, sonst bekommt der neue Mount einen Suffix-Namen
		# (der alte hängt bis zum Frame-Ende noch im Baum).
		_wall_mount.name = "WallsAlt"
		_wall_mount.queue_free()
	_wall_mount = Node3D.new()
	_wall_mount.name = "Walls"
	add_child(_wall_mount)
	_fenster_stand = _fenster_signatur()
	var spans: Dictionary = RoomDefs.wall_door_spans(_room_def)
	# S-Wand (Kameraseite) bleibt innen offen, damit die Sicht frei ist.
	var walls: Array[String] = ["N", "W", "E"]
	if _is_outdoor():
		walls.append("S")
	for wall: String in walls:
		_build_wall_segments(wall, spans.get(wall, []))
	for window: Dictionary in _room_def.get("windows", []):
		if not _fenster_verdeckt(window):
			_build_window(window)


## Wand aus Segmenten: Türen und Außenfenster lassen jeweils eine Öffnung
## frei (Fenster nur in Brüstungshöhe, damit das Diorama sichtbar wird).
func _build_wall_segments(wall: String, door_spans: Array) -> void:
	var width := grid.wall_width(wall)
	var height := FENCE_HEIGHT if _is_outdoor() else WALL_HEIGHT
	var oeffnungen: Array[Dictionary] = []
	for span: Array in door_spans:
		var oben := height if _is_outdoor() else DoorTransition.DOOR_HEIGHT
		oeffnungen.append({"von": int(span[0]), "bis": int(span[1]), "y0": 0.0, "y1": oben})
	for span: Array in _fenster_spans(wall):
		oeffnungen.append(
			{"von": int(span[0]), "bis": int(span[1]), "y0": FENSTER_Y0, "y1": FENSTER_Y1}
		)
	oeffnungen.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["von"] < b["von"])
	var cursor := 0
	for loch: Dictionary in oeffnungen:
		_add_wall_box(wall, cursor, int(loch["von"]), 0.0, height)
		_add_wall_box(wall, int(loch["von"]), int(loch["bis"]), 0.0, float(loch["y0"]))
		_add_wall_box(wall, int(loch["von"]), int(loch["bis"]), float(loch["y1"]), height)
		cursor = maxi(cursor, int(loch["bis"]))
	_add_wall_box(wall, cursor, width, 0.0, height)


## Fingerabdruck aller Fenster-Ausschnitte — ändert er sich, müssen die
## Wandsegmente neu gebaut werden.
func _fenster_signatur() -> String:
	var teile: Array[String] = []
	for wall: String in GridData.WALLS:
		for span: Array in _fenster_spans(wall):
			teile.append("%s%d-%d" % [wall, int(span[0]), int(span[1])])
	return "|".join(teile)


## Spannen aller Außenfenster (WALL-Items mit `exterior`) auf einer Wand.
func _fenster_spans(wall: String) -> Array[Array]:
	var spans: Array[Array] = []
	var offset := 0
	while offset < grid.wall_width(wall):
		var uid := grid.wall_item_at(wall, offset)
		if uid == "":
			offset += 1
			continue
		var def: Dictionary = grid.get_item(uid).get("def", {})
		var span := maxi(1, int(def.get("wall_size", 1)))
		if bool(def.get("exterior", false)):
			spans.append([offset, offset + span])
		offset += span
	return spans


## Steht auf der Fensterattrappe aus rooms.json schon ein echtes Fenster?
func _fenster_verdeckt(window: Dictionary) -> bool:
	var wall := str(window.get("wall", "N"))
	var von := int(window.get("offset", 0))
	var bis := von + int(window.get("size", 2))
	for span: Array in _fenster_spans(wall):
		if von < int(span[1]) and bis > int(span[0]):
			return true
	return false


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
	mesh.name = "Wall_%s_%d_%d_%d" % [wall, from, to, int(y0 * 100.0)]
	_wall_mount.add_child(mesh)


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
	# Tags hell strahlend, nachts fast dunkel (HomeLicht-Tageszeit-Lerp).
	mat.albedo_color = Color("#CFEFFF").lerp(Color("#1E2A4A"), 1.0 - _fenster_energie)
	mat.emission_enabled = true
	mat.emission = Color("#BFE8FF")
	mat.emission_energy_multiplier = _fenster_energie
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
	_wall_mount.add_child(mesh)


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
	# W3d-Bugreport: Controls unter CanvasLayer erben das Window-Theme nicht.
	_bubble.theme = ThemeService.theme()
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
	_choice.theme = ThemeService.theme()
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
