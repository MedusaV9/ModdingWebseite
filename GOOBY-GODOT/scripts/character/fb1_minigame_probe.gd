extends SceneTree
## FB1-Minispiel-Probe (KEIN Test): montiert den spielenden Gooby über den
## echten 3D-A-`GoobyActor` (mount → face → play), wie ihn Tea-Party/Angeln/
## Goalie benutzen, und schießt ein Kontrollfoto des wiederhergestellten
## Web-Modells in Spielgröße. Aufruf:
##   xvfb-run -a godot --path GOOBY-GODOT --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://scripts/character/fb1_minigame_probe.gd

const OUT := "/tmp/gooby-godot/artifacts/FB1/spielansicht_minigame_actor.png"
const ACTOR_SCRIPT := "res://scripts/minigames/games/_3da_stage/gooby_actor.gd"


func _initialize() -> void:
	_run()


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1024, 768))
	root.size = Vector2i(1024, 768)
	var stage := Node3D.new()
	root.add_child(stage)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40.0, 30.0, 0.0)
	sun.light_energy = 0.55
	stage.add_child(sun)
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#f4f1ec")
	env.ambient_light_energy = 0.45
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	stage.add_child(world_env)
	var sky := MeshInstance3D.new()
	var sky_sphere := SphereMesh.new()
	sky_sphere.radius = 20.0
	sky_sphere.height = 40.0
	var sky_mat := StandardMaterial3D.new()
	sky_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sky_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	sky_mat.albedo_color = Color(223.0 / 255.0, 238.0 / 255.0, 247.0 / 255.0)
	sky_sphere.material = sky_mat
	sky.mesh = sky_sphere
	stage.add_child(sky)
	var boden := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 30.0)
	var boden_mat := StandardMaterial3D.new()
	boden_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	boden_mat.albedo_color = Color(164.0 / 255.0, 187.0 / 255.0, 131.0 / 255.0)
	plane.material = boden_mat
	boden.mesh = plane
	stage.add_child(boden)

	var actor: Node3D = (load(ACTOR_SCRIPT) as GDScript).new()
	stage.add_child(actor)
	actor.mount(1.0, 0.35)
	actor.emote("ecstatic", 5.0)
	actor.play("celebrate")

	var cam := Camera3D.new()
	cam.fov = 38.0
	stage.add_child(cam)
	cam.current = true
	cam.look_at_from_position(Vector3(0.9, 0.85, 2.3), Vector3(0.0, 0.55, 0.0))

	for _i in range(30):
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png(OUT)
	print("[fb1] Minigame-Foto: %s" % OUT)
	quit(0)
