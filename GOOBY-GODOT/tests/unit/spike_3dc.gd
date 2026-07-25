extends SceneTree
## 3D-C-Spike (KEIN Test): prüft, dass eine 3D-Bühne (eigener SubViewport mit
## own_world_3d + Camera3D + GoobyRig) IM MinigameBase-Vertrag rendert und wie
## viele Draw-Calls sie kostet. Läuft nur mit echtem Renderer:
##   xvfb-run -a godot --path GOOBY-GODOT --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --script res://tests/unit/spike_3dc.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/3DC"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(720, 1160))
	root.size = Vector2i(720, 1160)

	var game := Node2D.new()
	root.add_child(game)

	var container := SubViewportContainer.new()
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	container.size = Vector2(720, 1160)
	game.add_child(container)
	var viewport := SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(720, 1160)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)

	var world := Node3D.new()
	viewport.add_child(world)
	var camera := Camera3D.new()
	camera.position = Vector3(0.0, 1.1, 2.6)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.6, 0.0))
	world.add_child(camera)
	camera.current = true
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-42.0, 26.0, 0.0)
	world.add_child(sun)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#2a2350")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#ffe6c9")
	env.ambient_light_energy = 0.8
	env.glow_enabled = true
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	world.add_child(world_env)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(10.0, 10.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#8fd6a6")
	plane.material = mat
	floor_mesh.mesh = plane
	world.add_child(floor_mesh)

	var rig := GoobyRig.new()
	world.add_child(rig)
	rig.set_emotion("happy")

	var label := Label.new()
	label.text = "HUD über 3D"
	label.position = Vector2(24, 24)
	label.add_theme_font_size_override("font_size", 40)
	game.add_child(label)

	for _i in 90:
		await process_frame
	var draws := RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
	)
	print("[spike] Draw-Calls: %d" % draws)
	var image := root.get_texture().get_image()
	image.save_png("%s/spike.png" % OUT_DIR)
	print("[spike] fertig")
	quit(0)
