extends SceneTree
## W2a-Screenshot-Tool (KEIN Test — kein test_-Präfix): rendert die
## HOUSE-Deliverables als Review-Artefakte: Wohnzimmer-Default, Baumodus
## mit grünem/rotem Ghost (Bett-Quest), Tür-Steckenbleib-Gag und Garten.
## Braucht einen echten Renderer (xvfb):
## xvfb-run -a godot --path . --rendering-method gl_compatibility \
##   --rendering-driver opengl3 --script res://tests/unit/screenshot_w2a.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/W2a"
const SETTLE_FRAMES := 24
const CAMERA_FRAMES := 150

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

var _seq := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.theme = ThemeService.theme()
	_resize(Vector2i(1280, 720))
	await _shot_room_default("living", "wohnzimmer_default.png")
	await _shot_build_mode()
	await _shot_door_gag()
	await _shot_room_default("garden", "garten_default.png")
	print("Screenshots fertig → %s" % OUT_DIR)
	quit(0)


func _resize(win_size: Vector2i) -> void:
	DisplayServer.window_set_size(win_size)
	root.size = win_size


func _make_room(room_id: String) -> Dictionary:
	_seq += 1
	var dir := "user://w2a_shots/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	var scene: PackedScene = load(str(RoomDefs.room(room_id)["scene"]))
	var room: RoomBase = scene.instantiate()
	room.game_state_override = gs
	root.add_child(room)
	await process_frame
	_pose_gooby(room)
	for _i in CAMERA_FRAMES:
		await process_frame
	return {"room": room, "gs": gs}


## Gooby auf einen freien, gut sichtbaren Platz (untere Raumhälfte) stellen —
## bevorzugt Zellen mit begehbaren Nachbarn (nicht zwischen Möbeln geklemmt).
func _pose_gooby(room: RoomBase) -> void:
	var gooby := room.gooby()
	gooby.set_wander_enabled(false)
	var free := room.grid.free_cells()
	if free.is_empty():
		return
	var roomy: Array[Vector2i] = []
	for cell in free:
		var clear := true
		for offset: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var neighbor: Vector2i = cell + offset
			if not room.grid.in_bounds(neighbor) or not room.grid.walkable(neighbor):
				clear = false
				break
		if clear:
			roomy.append(cell)
	if roomy.is_empty():
		roomy = free
	var target := Vector2i(room.grid.size.x / 2, room.grid.size.y * 2 / 3)
	roomy.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return (a - target).length_squared() < (b - target).length_squared()
	)
	gooby.global_position = GridData.world_center(roomy[0], Vector2i.ONE, 0)


func _teardown(ctx: Dictionary) -> void:
	(ctx["room"] as Node).queue_free()
	await process_frame
	await process_frame
	(ctx["gs"] as Node).free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()


func _shot_room_default(room_id: String, file: String) -> void:
	var ctx := await _make_room(room_id)
	await _snap(file)
	await _teardown(ctx)


func _shot_build_mode() -> void:
	var ctx := await _make_room("living")
	var room: RoomBase = ctx["room"]
	# Bett-Quest startet automatisch (Bett liegt im Start-Lager) → Bett-Ghost.
	room.open_build_mode()
	var build: BuildMode = room.get_node("BuildMode")
	for _i in 40:
		await process_frame
	if not build._ghost_state.is_empty():
		var def: Dictionary = build._ghost_state["def"]
		build._ghost_state["at"] = _find_ok_at(room.grid, def)
		build._rebuild_ghost()
	await _snap("baumodus_ghost_gruen.png")
	# Ghost auf ein belegtes Möbel schieben → rotes Kollisions-Feedback.
	if not build._ghost_state.is_empty():
		build._ghost_state["at"] = _first_floor_item_at(room.grid)
		build._rebuild_ghost()
	await _snap("baumodus_ghost_rot.png")
	await _teardown(ctx)


func _shot_door_gag() -> void:
	var ctx := await _make_room("living")
	var room: RoomBase = ctx["room"]
	var door: DoorTransition = room._doors["living_kueche"]
	var gooby := room.gooby()
	gooby.set_wander_enabled(false)
	gooby.global_position = door.global_position + door.global_transform.basis.z * 0.12
	# Gag erzwingen (Würfel 0.0 < 12 %) und direkt in den Steck-Moment springen.
	door._busy = true
	door.logic = DoorLogic.new(true, false, 0.0, 0.5)
	door.logic.begin()
	await door._open_panel()
	door.logic.door_opened()
	door.logic.reached_door()
	door._run_stuck_gag(gooby, room._ui_layer)
	for _i in 90:
		await process_frame
	for _i in 4:
		door.logic.tap_mash()
	await _snap("tuer_gag_steckt.png")
	await _teardown(ctx)


## Erste Zelle, auf der `def` regulär platzierbar ist (grüner Ghost).
func _find_ok_at(grid: GridData, def: Dictionary) -> Vector2i:
	for y in grid.size.y:
		for x in grid.size.x:
			var at := Vector2i(x, y)
			if bool(grid.can_place(def, at, 0)["ok"]):
				return at
	return Vector2i.ZERO


## Anker des OBERSTEN FLOOR-Items (garantiert-roter Ghost, nicht von der
## Drawer-UI am unteren Rand verdeckt).
func _first_floor_item_at(grid: GridData) -> Vector2i:
	var best := Vector2i.ZERO
	var found := false
	for entry: Dictionary in grid.to_items_array():
		if entry.has("wall"):
			continue
		var def := FurnitureCatalog.def(str(entry["item"]))
		if int(def.get("layer", -1)) != GridData.Layer.FLOOR:
			continue
		var at := Vector2i(int(entry["at"][0]), int(entry["at"][1]))
		if not found or at.y < best.y:
			best = at
			found = true
	return best


func _snap(file: String) -> void:
	for _i in SETTLE_FRAMES:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("  gespeichert: %s (%dx%d)" % [file, image.get_width(), image.get_height()])
