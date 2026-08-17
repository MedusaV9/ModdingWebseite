extends SceneTree
## FIX2-Grid-Dump (KEIN Test): unbegehbare Zellen des Wohnzimmers für den
## Movement-Plot ausgeben.

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
	var grid: GridData = room.gooby().grid
	var belegt := PackedStringArray()
	for y in grid.size.y:
		for x in grid.size.x:
			if not grid.walkable(Vector2i(x, y)):
				belegt.append("%d;%d" % [x, y])
	print("BELEGT %s" % ",".join(belegt))
	quit(0)
