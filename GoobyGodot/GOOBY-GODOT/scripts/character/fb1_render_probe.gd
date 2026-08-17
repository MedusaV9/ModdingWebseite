extends SceneTree
## FB1-Render-Probe: rendert res://assets/character/gooby.glb aus denselben
## Kamerawinkeln wie die Web-Referenz (GOOBY/fb1-ref-Setup: Orbit r=2.6,
## Höhe 0.55, LookAt (0, 0.5, 0), FOV 35) und misst die Proportionen direkt
## aus den Mesh-Vertices (Palette-UV-Zellen unterscheiden die Körperteile).
##
## Aufruf:
##   xvfb-run -a godot --path GOOBY-GODOT --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --resolution 700x700 \
##     --script res://scripts/character/fb1_render_probe.gd -- \
##     --out=/tmp/shots --label=vorher
##
## Nur Mess-/Beweis-Werkzeug — kein Spielcode hängt hieran.

const GLB_PATH := "res://assets/character/gooby.glb"
const ANGLES := {"front": 0.0, "tq": 38.0, "side": 90.0, "back": 180.0}
const ORBIT_R := 2.6
const CAM_H := 0.55
const FOV := 35.0
## Palette-UV-Zellen (gooby_params.PALETTE_ORDER, 4×4-Raster). glTF flippt V
## gegenüber Blender: v_godot = 1 − v_blender (body (0.125,0.875) → 0.125).
const UV_CELL_EYE := Vector2(0.375, 0.375)
const UV_CELL_BODY := Vector2(0.125, 0.125)

var _out_dir := "/tmp/fb1_shots"
var _label := "probe"


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			_out_dir = arg.trim_prefix("--out=")
		elif arg.begins_with("--label="):
			_label = arg.trim_prefix("--label=")
	_run()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(_out_dir)
	var stage := _build_stage()
	root.add_child(stage)
	var model: Node3D = (load(GLB_PATH) as PackedScene).instantiate()
	stage.add_child(model)

	var measures := _measure(model)
	print("[fb1] MESSWERTE %s: %s" % [_label, JSON.stringify(measures)])
	var caption := (
		(
			"GODOT %s\nhoehe gesamt   %.3f\nkoerper breite %.3f\n"
			+ "kopf breite    %.3f  kopf/koerper %.3f\n"
			+ "auge breite    %.3f  auge/kopf    %.3f\nkopf-pivot y   %.3f"
		)
		% [
			_label,
			measures["hoehe"],
			measures["koerper_breite"],
			measures["kopf_breite"],
			measures["kopf_koerper"],
			measures["auge_breite"],
			measures["auge_kopf"],
			measures["kopf_pivot_y"],
		]
	)
	var label := _build_caption(caption)
	root.add_child(label)

	var camera := Camera3D.new()
	camera.fov = FOV
	stage.add_child(camera)
	camera.current = true

	for angle_name: String in ANGLES:
		var yaw: float = deg_to_rad(ANGLES[angle_name])
		camera.position = Vector3(sin(yaw) * ORBIT_R, CAM_H, cos(yaw) * ORBIT_R)
		camera.look_at_from_position(camera.position, Vector3(0.0, 0.5, 0.0))
		await _shoot("%s/godot_%s_%s.png" % [_out_dir, _label, angle_name])
	# Kopf-Nahaufnahme wie die Web-Referenz (zoom=head)
	camera.position = Vector3(0.0, 0.75, ORBIT_R * 0.55)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.68, 0.0))
	await _shoot("%s/godot_%s_head_zoom.png" % [_out_dir, _label])

	var json_file := FileAccess.open("%s/messwerte_%s.json" % [_out_dir, _label], FileAccess.WRITE)
	json_file.store_string(JSON.stringify(measures, "  "))
	json_file.close()
	quit(0)


func _shoot(path: String) -> void:
	for _i in range(6):
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png(path)
	print("[fb1] Screenshot: %s" % path)


func _build_stage() -> Node3D:
	var stage := Node3D.new()
	# Himmel + Wiese als UNSHADED Flächen mit den exakten Pixelfarben der
	# Web-Referenz — der Environment-BG-Pfad rendert in diesem Capture-Modus
	# (xvfb + gl_compatibility + --script) nicht farbtreu, unshaded Albedo
	# schon. Nur der Charakter bleibt beleuchtet; die Energien sind so
	# abgestimmt, dass die Körperfarbe die Web-Pixelwerte trifft.
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 28.0, 0.0)
	sun.light_energy = 0.33
	stage.add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-12.0, -140.0, 0.0)
	fill.light_energy = 0.1
	stage.add_child(fill)
	var env := Environment.new()
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#f4f1ec")
	env.ambient_light_energy = 0.31
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	stage.add_child(world_env)
	var sky_mesh := MeshInstance3D.new()
	var sky_sphere := SphereMesh.new()
	sky_sphere.radius = 15.0
	sky_sphere.height = 30.0
	var sky_mat := StandardMaterial3D.new()
	sky_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sky_mat.cull_mode = BaseMaterial3D.CULL_FRONT
	sky_mat.albedo_color = Color(223.0 / 255.0, 238.0 / 255.0, 247.0 / 255.0)
	sky_sphere.material = sky_mat
	sky_mesh.mesh = sky_sphere
	stage.add_child(sky_mesh)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(28.0, 28.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(164.0 / 255.0, 187.0 / 255.0, 131.0 / 255.0)
	plane.material = mat
	floor_mesh.mesh = plane
	stage.add_child(floor_mesh)
	return stage


func _build_caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.position = Vector2(6.0, 4.0)
	label.add_theme_color_override("font_color", Color(0.2, 0.2, 0.2))
	label.add_theme_font_size_override("font_size", 12)
	return label


## Misst Proportionen aus den Mesh-Vertices. Körperteile werden über die
## Palette-UV-Zelle unterschieden (build_mesh.py: 1 Zelle pro Teil).
func _measure(model: Node3D) -> Dictionary:
	var mesh_instance: MeshInstance3D = null
	for child in model.find_children("*", "MeshInstance3D", true, false):
		mesh_instance = child
		break
	var arrays := mesh_instance.get_mesh().surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var min_y := INF
	var max_y := -INF
	var body_max_x := 0.0
	var head_max_x := 0.0
	var eye_min := Vector3(INF, INF, INF)
	var eye_max := Vector3(-INF, -INF, -INF)
	for i in range(verts.size()):
		var v := verts[i]
		min_y = minf(min_y, v.y)
		max_y = maxf(max_y, v.y)
		if uvs[i].distance_to(UV_CELL_BODY) < 0.01:
			# Lathe-Körper = breitestes Band unten, nur RÜCKSEITE (z < −0.03):
			# Ärmchen/Füße teilen die body-Palette-Zelle, liegen aber vorn.
			# Kopf = Band um das Kopfzentrum (0.48–0.62), Ohren reichen da
			# nicht hin.
			if v.y < 0.45 and v.z < -0.03:
				body_max_x = maxf(body_max_x, absf(v.x))
			elif v.y >= 0.48 and v.y <= 0.62:
				head_max_x = maxf(head_max_x, absf(v.x))
		if uvs[i].distance_to(UV_CELL_EYE) < 0.01 and v.x < 0.0:
			eye_min = eye_min.min(v)
			eye_max = eye_max.max(v)
	var kopf_breite := head_max_x * 2.0
	var koerper_breite := body_max_x * 2.0
	var auge_breite := eye_max.x - eye_min.x
	var head_pivot_y := 0.0
	var skeleton: Skeleton3D = null
	for child in model.find_children("*", "Skeleton3D", true, false):
		skeleton = child
		break
	if skeleton != null:
		var head_idx := skeleton.find_bone("head")
		if head_idx >= 0:
			head_pivot_y = skeleton.get_bone_global_rest(head_idx).origin.y
	return {
		"hoehe": max_y - min_y,
		"koerper_breite": koerper_breite,
		"kopf_breite": kopf_breite,
		"kopf_koerper": kopf_breite / koerper_breite if koerper_breite > 0.0 else 0.0,
		"auge_breite": auge_breite,
		"auge_kopf": auge_breite / kopf_breite if kopf_breite > 0.0 else 0.0,
		"kopf_pivot_y": head_pivot_y,
	}
