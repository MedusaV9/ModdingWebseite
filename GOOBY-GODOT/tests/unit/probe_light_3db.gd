extends SceneTree
## 3D-B-Hilfswerkzeug (KEIN Test): misst, wie hell eine sonnenabgewandte Fläche
## unter der 3D-B-Bühne wirklich wird (Umgebungslicht-Eichung).
##
##   xvfb-run -a godot --path GOOBY-GODOT --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --script res://tests/unit/probe_light_3db.gd

const Stage3D := preload("res://scripts/minigames/games/_3db_stage/stage3d.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.size = Vector2i(320, 240)
	var stage: Node3D = Stage3D.new()
	root.add_child(stage)
	(
		stage
		. call(
			"build",
			{
				"sun_dir": Vector3(-0.35, -0.79, -0.53),
				"ambient_color": Color(0.861, 0.81, 0.753),
				"ambient": 1.0,
				"fog": false,
				"glow": 0.0,
			}
		)
	)
	# Zwei Wände: eine der Sonne zugewandt (+x-Normale), eine abgewandt.
	for i in 2:
		var wall := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.2, 6.0, 6.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.9, 0.9, 0.9)
		mat.roughness = 1.0
		mesh.material = mat
		wall.mesh = mesh
		wall.position = Vector3(-4.0 if i == 0 else 4.0, 0.0, -6.0)
		stage.add_child(wall)
	var cam: Camera3D = stage.get("camera")
	cam.position = Vector3(0.0, 0.6, 2.0)
	for _i in 12:
		await process_frame
	var img := root.get_texture().get_image()
	print("Sonnenseite  (links,  +x-Normale): ", img.get_pixel(60, 120))
	print("Schattenseite(rechts, -x-Normale): ", img.get_pixel(260, 120))
	print("ambient_source=", stage.get("environment").ambient_light_source)
	print("ambient_energy=", stage.get("environment").ambient_light_energy)
	quit(0)
