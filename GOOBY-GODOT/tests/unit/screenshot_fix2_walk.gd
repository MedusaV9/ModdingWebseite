extends SceneTree
## FIX2-Screenshot-Tool (KEIN Test): Gooby läuft im Wohnzimmer quer durch den
## Raum (um Couchtisch/Sofa herum) — 3 Fotos als Movement-Beleg. Aufruf:
## xvfb-run -a godot --rendering-method gl_compatibility \
##   --rendering-driver opengl3 --audio-driver Dummy --path . \
##   --script res://tests/unit/screenshot_fix2_walk.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/FIX2"

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1280, 800))
	root.size = Vector2i(1280, 800)
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
	var t0 := Time.get_ticks_msec()
	while room._rebake_pending and Time.get_ticks_msec() - t0 < 4000:
		await physics_frame
	gooby.global_position = Vector3(5.25, 0.0, 4.5)
	await physics_frame
	await _shot("walk_1_start.png")
	gooby.walk_to(Vector3(0.75, 0.0, 0.75), 20.0)
	for _i in 200:
		await physics_frame
	await _shot("walk_2_unterwegs.png")
	while gooby._walking:
		await physics_frame
	await _shot("walk_3_ziel.png")
	print("fertig, ende pos=%v" % gooby.global_position)
	quit(0)


func _shot(file: String) -> void:
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("shot: %s" % file)
