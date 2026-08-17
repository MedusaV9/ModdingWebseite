extends SceneTree
## FIX2-Wegpunkt-Probe (KEIN Test): loggt get_next_path_position() inkl. Y
## und den 3D-Abstand Gooby→Wegpunkt, um den Pfad-Index-Stall zu belegen.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var dir := "user://fix2_probe/%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	HomeState.ensure_initialized(gs)
	var scene: PackedScene = load(str(RoomDefs.room("living")["scene"]))
	var room: RoomBase = scene.instantiate()
	room.game_state_override = gs
	room.stunde_override = 13.0
	root.add_child(room)
	await process_frame
	var gooby: GoobyHome = room.gooby()
	gooby.set_wander_enabled(false)
	# Warten bis der Navmesh-Bake (0.5 s Debounce) durch ist.
	for _i in 90:
		await physics_frame
	gooby.walk_to(Vector3(0.75, 0.0, 0.75), 4.0)
	for frame in 240:
		await physics_frame
		if not gooby._walking:
			print("f=%03d ANGEKOMMEN pos=%v" % [frame, gooby.global_position])
			break
		var pos := gooby.global_position
		var path: PackedVector3Array = gooby._path
		var idx: int = gooby._path_index
		var next := pos
		if idx < path.size():
			next = path[idx]
		if frame % 10 == 0 or frame > 100:
			print(
				(
					"f=%03d pos=(%.3f,%.3f,%.3f) next=(%.3f,%.3f,%.3f) d3d=%.3f idx=%d/%d"
					% [
						frame,
						pos.x,
						pos.y,
						pos.z,
						next.x,
						next.y,
						next.z,
						pos.distance_to(next),
						idx,
						path.size()
					]
				)
			)
		if frame > 130:
			break
	room.queue_free()
	await process_frame
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()
	quit(0)
