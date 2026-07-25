extends SceneTree
## W4-P3-Screenshot-Tool (KEIN Test — kein test_-Präfix): rendert die
## WELT-Polish-Artefakte (5 Räume Tag/Nacht + Hochkant-Framing, Stadt
## Tag/Nacht, Tür-Gag Staub + Sternchen-Plopp) und loggt pro Shot die
## Draw-Calls (RenderingServer) gegen das Budget A §7 (≤150/Raum).
## Braucht einen echten Renderer (xvfb):
## xvfb-run -a godot --path . --rendering-method gl_compatibility \
##   --rendering-driver opengl3 --script res://tests/unit/screenshot_w4p3.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/W4P3"
const SETTLE_FRAMES := 24
const QUER := Vector2i(1280, 720)
const HOCHKANT := Vector2i(594, 1280)

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

var _seq := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.theme = ThemeService.theme()
	_resize(QUER)
	for room_id: String in ["living", "kitchen", "bathroom", "bedroom", "garden"]:
		await _shot_raum(room_id, 12.0, "nachher_%s.png" % room_id)
	await _shot_raum("living", 22.0, "nachher_living_nacht.png")
	_resize(HOCHKANT)
	await _shot_raum("living", 12.0, "nachher_living_hochkant.png")
	await _shot_baumodus_hochkant()
	_resize(QUER)
	await _shot_tuer_gag()
	await _shot_stadt(12.0, "nachher_stadt_tag.png")
	await _shot_stadt(22.0, "nachher_stadt_nacht.png")
	await _shot_stadt_fahrt_nacht()
	print("Screenshots fertig → %s" % OUT_DIR)
	quit(0)


func _resize(win_size: Vector2i) -> void:
	DisplayServer.window_set_size(win_size)
	root.size = win_size


## ------------------------------------------------------------------ Räume


func _make_gs(slice_owner: String) -> Node:
	_seq += 1
	var dir := "user://w4p3_shots/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if slice_owner == "home":
		HomeState.register_slice()
	else:
		CityState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	return gs


func _make_room(room_id: String, stunde: float) -> Dictionary:
	var gs := _make_gs("home")
	var scene: PackedScene = load(str(RoomDefs.room(room_id)["scene"]))
	var room: RoomBase = scene.instantiate()
	room.game_state_override = gs
	room.stunde_override = stunde
	root.add_child(room)
	await process_frame
	_pose_gooby(room)
	for _i in 90:
		await process_frame
	return {"room": room, "gs": gs}


## Gooby auf einen freien, gut sichtbaren Platz (untere Raumhälfte) stellen.
func _pose_gooby(room: RoomBase) -> void:
	var gooby := room.gooby()
	gooby.set_wander_enabled(false)
	var free := room.grid.free_cells()
	if free.is_empty():
		return
	var target := Vector2i(room.grid.size.x / 2, room.grid.size.y * 2 / 3)
	free.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return (a - target).length_squared() < (b - target).length_squared()
	)
	gooby.global_position = GridData.world_center(free[0], Vector2i.ONE, 0)


func _teardown_room(ctx: Dictionary) -> void:
	(ctx["room"] as Node).queue_free()
	await process_frame
	await process_frame
	(ctx["gs"] as Node).free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()


func _shot_raum(room_id: String, stunde: float, file: String) -> void:
	var ctx := await _make_room(room_id, stunde)
	await _snap(file)
	await _teardown_room(ctx)


func _shot_baumodus_hochkant() -> void:
	var ctx := await _make_room("living", 12.0)
	var room: RoomBase = ctx["room"]
	room.open_build_mode()
	for _i in 60:
		await process_frame
	await _snap("nachher_baumodus_hochkant.png")
	await _teardown_room(ctx)


func _shot_tuer_gag() -> void:
	var ctx := await _make_room("living", 12.0)
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
	await _snap("nachher_tuer_gag_staub.png")
	# Plopp: letzter Tap → Sternchen-Burst + Squash. Unter xvfb (Software-GL,
	# ~20-30 fps) sind Frames LANG — früh snappen, sonst ist der Burst
	# (0.8 s Lebenszeit) schon ausgefadet.
	door.logic.tap_mash()
	door._pop_through(gooby)
	for _i in 4:
		await process_frame
	await _snap("nachher_tuer_gag_plopp_sterne.png", 0)
	for _i in 40:
		await process_frame
	await _teardown_room(ctx)


## ------------------------------------------------------------------ Stadt


func _teardown_city(node: Node, gs: Node) -> void:
	PanelStack.clear()
	node.queue_free()
	await process_frame
	await process_frame
	gs.free()
	SaveSchema.unregister_slice(CityState.SLICE_ID)
	CityState.reset_for_tests()


func _make_city(stunde: float) -> Dictionary:
	var gs := _make_gs("city")
	var city: CityScene = load("res://scenes/city/city_scene.tscn").instantiate()
	city.game_state_override = gs
	city.stunde_override = stunde
	root.add_child(city)
	for _i in 20:
		await process_frame
	city.auto.set_frozen(true)
	return {"city": city, "gs": gs}


func _shot_stadt(stunde: float, file: String) -> void:
	var ctx := await _make_city(stunde)
	var city: CityScene = ctx["city"]
	city.hud.visible = false
	var top := Camera3D.new()
	city.add_child(top)
	top.position = Vector3(0.0, 150.0, 130.0)
	top.look_at(Vector3(0.0, 0.0, -10.0))
	top.current = true
	await _snap(file)
	await _teardown_city(city, ctx["gs"])


func _shot_stadt_fahrt_nacht() -> void:
	var ctx := await _make_city(22.0)
	var city: CityScene = ctx["city"]
	var strasse: Vector3 = city.karte.tile_zu_welt(Vector2i(5, 1))
	city.auto.teleport(strasse.x, strasse.z, 0.0)
	city.cam.current = true
	city.cam.snap()
	city.auto.set_frozen(false)
	for _i in 80:
		await physics_frame
	city.auto.set_frozen(true)
	await _snap("nachher_stadt_fahrt_nacht.png")
	await _teardown_city(city, ctx["gs"])


func _snap(file: String, settle := SETTLE_FRAMES) -> void:
	for _i in settle:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	var calls := RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
	)
	print(
		(
			"  gespeichert: %s (%dx%d) — draw calls: %d"
			% [file, image.get_width(), image.get_height(), calls]
		)
	)
