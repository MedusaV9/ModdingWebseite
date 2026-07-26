extends SceneTree
## FIX2-Movement-Probe (KEIN Test): startet den Wohnraum headless, beobachtet
## Gooby über viele Physics-Frames und schreibt ein Positions-Log als CSV
## (frame, x, z, dist_pro_frame, walking, nav_finished) nach /tmp.
## Aufruf:
##   godot --headless --path GOOBY-GODOT --script res://tests/unit/fix2_move_probe.gd

const OUT_DEFAULT := "/tmp/gooby-godot/artifacts/FIX2/move_probe.csv"
const FRAMES := 900

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var out := OS.get_environment("FIX2_OUT")
	if out == "":
		out = OUT_DEFAULT
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
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
	var lines := PackedStringArray()
	lines.append("frame,x,z,dist,walking,nav_finished,target_x,target_z")
	var prev := gooby.global_position
	var max_jump := 0.0
	var total := 0.0
	for frame in FRAMES:
		await physics_frame
		var pos := gooby.global_position
		var dist := Vector2(pos.x - prev.x, pos.z - prev.z).length()
		total += dist
		max_jump = maxf(max_jump, dist)
		var target: Vector3 = gooby._target
		lines.append(
			(
				"%d,%.4f,%.4f,%.5f,%s,%s,%.3f,%.3f"
				% [
					frame,
					pos.x,
					pos.z,
					dist,
					gooby._walking,
					gooby._path_index >= gooby._path.size(),
					target.x,
					target.z
				]
			)
		)
		prev = pos
	var f := FileAccess.open(out, FileAccess.WRITE)
	f.store_string("\n".join(lines))
	f.close()
	print("PROBE frames=%d total_dist=%.3f max_jump_pro_frame=%.4f" % [FRAMES, total, max_jump])
	print("CSV → %s" % out)
	room.queue_free()
	await process_frame
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()
	quit(0)
