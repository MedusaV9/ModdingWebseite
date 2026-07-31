extends "res://scripts/minigames/games/_3dc_stage/stage3d.gd"
## Raketen-Rettung — 3D-Mondbühne (Agent 3D-C). Gooby sitzt als PILOT auf dem
## Lander, unter ihm liegt eine echte Mondebene mit Kratern, Felsen (Kenney
## nature-/space-kit) und schwebenden Rettungsplattformen; darüber Sternenfeld,
## Nebel und ein ferner Ringplanet.
##
## WICHTIG — Projektionsvertrag: die Kamera schaut GERADE auf die Ebene z = 0
## und ist so gerahmt, dass `camera.unproject_position(Vector3(wx, wy, 0))`
## PIXELGENAU dasselbe liefert wie die 2D-Formel des Spiels
## (`view.x/2 + (wx-cam)*scale`, `view.y*0.88 - wy*scale`). Damit bleiben HUD,
## Float-Texte und die getestete Spiellogik unverändert:
##   halbe Bildhöhe  = view.y*0.5/scale  = 0.625*(CEILING_Y+1.4)   (konstant)
##   Kamerahöhe      = view.y*0.38/scale = 0.475*(CEILING_Y+1.4)   (konstant)

const Models := preload("res://scripts/minigames/games/_3dc_stage/models3d.gd")
const Puff := preload("res://scripts/minigames/games/_3dc_stage/puff3d.gd")
const DIR := "res://assets/minigames/rocket_rescue/"

## Kameraabstand zur Spielebene (klein genug für spürbare Tiefe im Hintergrund).
const CAM_DIST := 14.0
## Bildschirmhöhe des Bodens (Anteil von oben) — muss zu GROUND_FRAC passen.
const GROUND_FRAC := 0.88
## Anteil der Viewport-Höhe zwischen Boden und Decke (muss zu WORLD_H_FRAC passen).
const WORLD_H_FRAC := 0.8
const STAR_COUNT := 190
const ROCK_COUNT := 26

var gooby: GoobyRig

var _tune: Dictionary = {}
var _craft: Node3D
var _craft_tilt: Node3D
var _flame: GPUParticles3D
var _dust: GPUParticles3D
var _spark: GPUParticles3D
var _pad: Node3D
var _pad_lights: Array[MeshInstance3D] = []
var _platforms: Array[Node3D] = []
var _bunnies: Array[Node3D] = []
var _cans: Array[Node3D] = []
var _carried: Node3D
var _wind: GPUParticles3D
## W15: großer Feier-Burst für die geglückte Rettung (Audit: Feedback dünn).
var _rescue_burst: GPUParticles3D
var _emotion := "happy"


## Bühne aus Tuning + Layout bauen (einmalig in setup()).
func setup_stage(tune: Dictionary, layout: Dictionary) -> void:
	_tune = tune
	build(
		{
			"space": true,
			"bg": Color(0.03, 0.025, 0.085),
			"ambient_color": Color(0.55, 0.56, 0.85),
			"ambient": 1.05,
			"sun_color": Color(1.0, 0.93, 0.84),
			"sun_energy": 2.3,
			"sun_dir": Vector3(-0.45, -0.72, -0.52),
			"fill_color": Color(0.6, 0.72, 1.0),
			"fill_energy": 0.9,
			"shadows": false,
			"glow": 0.4,
			"glow_bloom": 0.02,
			"glow_threshold": 1.0,
			"far": 160.0,
		}
	)
	var half_h := 0.5 * (float(_tune["CEILING_Y"]) + 1.4) / WORLD_H_FRAC
	set_half_height(half_h, CAM_DIST)
	camera.position = Vector3(0.0, (GROUND_FRAC - 0.5) * 2.0 * half_h, CAM_DIST)
	camera.rotation = Vector3.ZERO
	_build_sky_props()
	_build_ground()
	_build_walls()
	_build_pad(layout["pad"])
	_build_platforms(layout["platforms"])
	_build_cans(layout["fuelPickups"])
	_build_craft()
	_build_effects()


## Kamera seitlich mitziehen (Hochkant folgt dem Schiff).
func track(cam_x: float) -> void:
	camera.position.x = cam_x


## Ganze Bühne aus einem Zustandsschnappschuss nachziehen.
func sync(s: Dictionary, layout: Dictionary, elapsed: float) -> void:
	_sync_craft(s, elapsed)
	_sync_platforms(layout["platforms"])
	_sync_cans(layout["fuelPickups"], elapsed)
	_sync_pad(s, elapsed)
	_sync_wind(s)


## Gooby-Emotion setzen (nur bei Wechsel, sonst flackert der Blend).
func feel(emotion: String) -> void:
	if gooby == null or _emotion == emotion:
		return
	_emotion = emotion
	gooby.set_emotion(emotion)


## Gooby-Clip (Jubel bei geglückter Rettung).
func cheer(clip: String) -> void:
	if gooby != null:
		gooby.play_clip(clip)


## Funkenwolke an einer Weltstelle (Landung, Rettung, Aufsammeln).
func spark_at(wx: float, wy: float, color: Color) -> void:
	Puff.fire(_spark, Vector3(wx, wy, 0.0), color)


## W15: die GROSSE Rettungs-Fontäne über der Station — goldene Sterne
## steigen als Garbe auf und regnen aus (zusätzlich zum kleinen spark_at).
func rescue_burst_at(wx: float, wy: float) -> void:
	Puff.fire(_rescue_burst, Vector3(wx, wy, 0.0))


## Bildschirmpixel eines Weltpunkts (2D-Overlays über der Bühne).
func point(wx: float, wy: float) -> Vector2:
	return to_screen(Vector3(wx, wy, 0.0))


# ── Aufbau ────────────────────────────────────────────────────────────────


func _build_sky_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 771026
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = load(DIR + "vfx/star_03.png")
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = STAR_COUNT
	for i in STAR_COUNT:
		var depth := rng.randf()
		var pos := Vector3(
			rng.randf_range(-46.0, 46.0), rng.randf_range(1.5, 34.0), rng.randf_range(-60.0, -14.0)
		)
		var size := 0.9 + depth * 2.4
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), pos))
		mm.set_instance_color(i, Color(1.0, 0.96, 0.86, 0.45 + depth * 0.7))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.extra_cull_margin = 90.0
	add_child(mmi)
	_build_planet()
	_build_nebula()


func _build_planet() -> void:
	var planet := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 9.0
	ball.height = 18.0
	ball.radial_segments = 24
	ball.rings = 12
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.99, 0.8, 0.55)
	mat.roughness = 1.0
	mat.emission_enabled = true
	mat.emission = Color(0.62, 0.4, 0.3)
	mat.emission_energy_multiplier = 0.5
	ball.material = mat
	planet.mesh = ball
	planet.position = Vector3(16.0, 22.0, -50.0)
	add_child(planet)


func _build_nebula() -> void:
	var tints := [
		[Vector3(-18.0, 12.0, -44.0), 34.0, Color(0.36, 0.22, 0.7, 0.3)],
		[Vector3(12.0, 4.0, -38.0), 26.0, Color(0.24, 0.44, 0.7, 0.26)],
	]
	for entry: Array in tints:
		var quad := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2(float(entry[1]), float(entry[1]))
		quad.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = entry[2]
		mat.albedo_texture = load(DIR + "vfx/circle_05.png")
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		quad.material_override = mat
		quad.position = entry[0]
		add_child(quad)


func _build_ground() -> void:
	var floor_node := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(120.0, 90.0)
	plane.subdivide_width = 1
	plane.subdivide_depth = 1
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.44, 0.4, 0.56)
	mat.roughness = 1.0
	plane.material = mat
	floor_node.mesh = plane
	floor_node.position = Vector3(0.0, 0.0, -26.0)
	add_child(floor_node)
	_build_ridge()
	_build_craters()
	_build_rocks()


## Bergkamm am hinteren Plattenrand: ohne ihn stößt der Mondboden als knallharte
## waagerechte Kante gegen den Weltraum — der einzige Strich im Bild, der wie
## ein Fehler aussieht statt wie Horizont.
func _build_ridge() -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 7.0
	cone.height = 7.0
	cone.radial_segments = 5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.38, 0.35, 0.52)
	mat.roughness = 1.0
	cone.material = mat
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260725
	var poses: Array = []
	for i in 26:
		var height := rng.randf_range(0.34, 1.0)
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(
			Vector3(rng.randf_range(0.7, 1.5), height, 1.0)
		)
		poses.append(
			Transform3D(
				basis,
				Vector3(
					-66.0 + i * 5.3 + rng.randf_range(-2.0, 2.0),
					-0.4,
					rng.randf_range(-71.0, -58.0)
				)
			)
		)
	add_child(Models.swarm([{"mesh": cone, "xform": Transform3D.IDENTITY}], poses, 90.0))


func _build_craters() -> void:
	var ring := CylinderMesh.new()
	ring.top_radius = 1.0
	ring.bottom_radius = 1.35
	ring.height = 0.08
	ring.radial_segments = 14
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.33, 0.48)
	mat.roughness = 1.0
	ring.material = mat
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var poses: Array = []
	for i in 22:
		var scale := rng.randf_range(0.7, 2.4)
		var basis := Basis.IDENTITY.scaled(Vector3(scale, 1.0, scale))
		var pos := Vector3(rng.randf_range(-30.0, 30.0), 0.02, rng.randf_range(-34.0, 5.0))
		poses.append(Transform3D(basis, pos))
	add_child(Models.swarm([{"mesh": ring, "xform": Transform3D.IDENTITY}], poses, 60.0))


func _build_rocks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	for name_part in ["rock_largeA.glb", "rock_smallA.glb", "rock_smallFlatA.glb"]:
		var parts := Models.parts(DIR + name_part, 1.0, true)
		if parts.is_empty():
			continue
		var poses: Array = []
		for i in ROCK_COUNT / 3:
			var far := rng.randf()
			var scale := lerpf(1.1, 3.4, far)
			var basis := Basis.IDENTITY.rotated(Vector3.UP, rng.randf() * TAU).scaled(
				Vector3.ONE * scale
			)
			var pos := Vector3(
				rng.randf_range(-26.0, 26.0),
				0.0,
				lerpf(-6.0, -30.0, far) + rng.randf_range(-2.0, 2.0)
			)
			poses.append(Transform3D(basis, pos))
		# Nature-Kit-Felsen tragen Grasköpfe — auf dem Mond wird daraus Regolith.
		var swarm := Models.swarm(parts, poses, 60.0)
		var moon_rock := StandardMaterial3D.new()
		moon_rock.albedo_color = Color(0.55, 0.51, 0.64)
		moon_rock.roughness = 1.0
		for child in swarm.get_children():
			(child as MultiMeshInstance3D).material_override = moon_rock
		add_child(swarm)


## Leuchtende Begrenzungspfeiler bei ±WORLD_HALF_W (dort prallt das Schiff ab).
func _build_walls() -> void:
	var half_w := float(_tune["WORLD_HALF_W"])
	var height := float(_tune["CEILING_Y"]) + 1.0
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.16, height, 0.16)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.6, 0.85, 1.0, 0.4)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = Color(0.45, 0.78, 1.0)
		mat.emission_energy_multiplier = 1.4
		box.material = mat
		post.mesh = box
		post.position = Vector3(side * half_w, height * 0.5, 0.0)
		add_child(post)


func _build_pad(pad: Dictionary) -> void:
	_pad = Node3D.new()
	_pad.position = Vector3(float(pad["x"]), float(pad["y"]), 0.0)
	add_child(_pad)
	var half := float(pad["halfW"])
	var deck := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(half * 2.0, 0.26, 2.4)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.96, 0.8, 0.4)
	mat.roughness = 0.7
	box.material = mat
	deck.mesh = box
	deck.position = Vector3(0.0, 0.13, 0.0)
	_pad.add_child(deck)
	# Stationshäuschen im Rücken der Plattform — Ziel der Rettungsflüge.
	var hut := MeshInstance3D.new()
	var hut_mesh := BoxMesh.new()
	hut_mesh.size = Vector3(1.2, 0.85, 1.0)
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.92, 0.94, 0.98)
	hut_mesh.material = hmat
	hut.mesh = hut_mesh
	hut.position = Vector3(-half - 1.5, 0.42, -3.2)
	_pad.add_child(hut)
	var roof := MeshInstance3D.new()
	var dome := SphereMesh.new()
	dome.radius = 0.75
	dome.height = 0.8
	dome.is_hemisphere = true
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.55, 0.85, 0.95, 0.55)
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dome.material = dmat
	roof.mesh = dome
	roof.position = Vector3(0.0, 0.42, 0.0)
	hut.add_child(roof)
	for side in [-1.0, 1.0]:
		var light := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.16
		ball.height = 0.32
		ball.radial_segments = 10
		ball.rings = 6
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = Color(1.0, 0.92, 0.55)
		lmat.emission_enabled = true
		lmat.emission = Color(1.0, 0.85, 0.4)
		lmat.emission_energy_multiplier = 3.0
		ball.material = lmat
		light.mesh = ball
		light.position = Vector3(side * half, 0.42, 0.0)
		_pad.add_child(light)
		_pad_lights.append(light)


func _build_platforms(platforms: Array) -> void:
	for p: Dictionary in platforms:
		var holder := Node3D.new()
		holder.position = Vector3(float(p["x"]), float(p["y"]), 0.0)
		add_child(holder)
		var slab := Models.node(DIR + "rock_smallFlatA.glb", float(p["halfW"]) * 2.3, false)
		slab.position.y = -0.18
		Models.tint(slab, Color(0.58, 0.54, 0.68))
		holder.add_child(slab)
		var deck := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(float(p["halfW"]) * 2.0, 0.12, 1.5)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.78, 0.82, 0.92)
		mat.emission_enabled = true
		mat.emission = Color(0.4, 0.6, 0.85)
		mat.emission_energy_multiplier = 0.35
		box.material = mat
		deck.mesh = box
		deck.position = Vector3(0.0, 0.06, 0.0)
		holder.add_child(deck)
		var bunny := _make_bunny()
		bunny.position = Vector3(0.0, 0.12, 0.15)
		holder.add_child(bunny)
		_platforms.append(holder)
		_bunnies.append(bunny)


## Gestrandeter Hase: kleine, warme Kugelfigur (kein zweites Gooby-Rig — das
## Rig ist teuer und Gooby sitzt bereits im Cockpit).
func _make_bunny() -> Node3D:
	var holder := Node3D.new()
	var fur := StandardMaterial3D.new()
	fur.albedo_color = Color(0.99, 0.93, 0.85)
	fur.roughness = 0.95
	var body := MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.3
	body_mesh.height = 0.52
	body_mesh.radial_segments = 12
	body_mesh.rings = 7
	body_mesh.material = fur
	body.mesh = body_mesh
	body.position = Vector3(0.0, 0.26, 0.0)
	holder.add_child(body)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.21
	head_mesh.height = 0.42
	head_mesh.radial_segments = 12
	head_mesh.rings = 7
	head_mesh.material = fur
	head.mesh = head_mesh
	head.position = Vector3(0.0, 0.62, 0.02)
	holder.add_child(head)
	for side in [-1.0, 1.0]:
		var ear := MeshInstance3D.new()
		var ear_mesh := CapsuleMesh.new()
		ear_mesh.radius = 0.065
		ear_mesh.height = 0.44
		ear_mesh.radial_segments = 8
		ear_mesh.rings = 3
		ear_mesh.material = fur
		ear.mesh = ear_mesh
		ear.position = Vector3(side * 0.12, 0.88, -0.02)
		ear.rotation_degrees = Vector3(0.0, 0.0, side * 12.0)
		holder.add_child(ear)
	return holder


func _build_cans(cans: Array) -> void:
	for f: Dictionary in cans:
		var holder := Node3D.new()
		holder.position = Vector3(float(f["x"]), float(f["y"]), 0.0)
		add_child(holder)
		var can := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.24
		mesh.bottom_radius = 0.24
		mesh.height = 0.6
		mesh.radial_segments = 12
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.42, 0.88, 0.6)
		mat.emission_enabled = true
		mat.emission = Color(0.3, 0.85, 0.55)
		mat.emission_energy_multiplier = 0.8
		mesh.material = mat
		can.mesh = mesh
		holder.add_child(can)
		var halo := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(1.6, 1.6)
		halo.mesh = quad
		var hmat := StandardMaterial3D.new()
		hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		hmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		hmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		hmat.albedo_color = Color(0.45, 1.0, 0.7, 0.45)
		hmat.albedo_texture = load(DIR + "vfx/circle_05.png")
		halo.material_override = hmat
		holder.add_child(halo)
		_cans.append(holder)


func _build_craft() -> void:
	_craft = Node3D.new()
	add_child(_craft)
	_craft_tilt = Node3D.new()
	_craft.add_child(_craft_tilt)
	var hull := Models.node(DIR + "craft_speederB.glb", 1.7, false)
	hull.rotation_degrees = Vector3(0.0, 90.0, 0.0)
	hull.position.y = -0.1
	_craft_tilt.add_child(hull)
	gooby = GoobyRig.new()
	gooby.name = "GoobyPilot"
	# Bewusst groß für die Kanzel: der Pilot ist die Hauptfigur der Szene, ein
	# maßstabsgetreu winziger Gooby verschwindet auf dem Handy komplett.
	gooby.scale = Vector3.ONE * 1.06
	gooby.position = Vector3(0.0, 0.16, 0.28)
	_craft_tilt.add_child(gooby)
	gooby.set_emotion(_emotion)
	_carried = _make_bunny()
	_carried.scale = Vector3.ONE * 0.62
	_carried.position = Vector3(0.62, 0.02, 0.3)
	_carried.visible = false
	_craft_tilt.add_child(_carried)


func _build_effects() -> void:
	_flame = (
		Puff
		. stream(
			DIR + "vfx/circle_05.png",
			{
				"amount": 30,
				"lifetime": 0.42,
				"size": 0.34,
				"dir": Vector3.DOWN,
				"spread": 11.0,
				"speed": Vector2(2.6, 4.4),
				"gravity": Vector3.ZERO,
				"color": Color(1.0, 0.76, 0.34, 0.95),
				"color_end": Color(1.0, 0.32, 0.2, 0.0),
				"scale_range": Vector2(0.7, 1.3),
				"emitting": false,
			}
		)
	)
	_flame.position = Vector3(0.0, -0.42, 0.0)
	_craft_tilt.add_child(_flame)
	_dust = (
		Puff
		. stream(
			DIR + "vfx/circle_05.png",
			{
				"amount": 18,
				"lifetime": 0.9,
				"size": 0.5,
				"dir": Vector3.UP,
				"spread": 70.0,
				"speed": Vector2(0.6, 1.6),
				"gravity": Vector3(0.0, -0.6, 0.0),
				"color": Color(0.8, 0.78, 0.9, 0.5),
				"color_end": Color(0.7, 0.7, 0.85, 0.0),
				"add": false,
				"emitting": false,
			}
		)
	)
	_craft.add_child(_dust)
	_spark = (
		Puff
		. burst(
			DIR + "vfx/star_03.png",
			{
				"amount": 24,
				"lifetime": 0.7,
				"size": 0.3,
				"dir": Vector3.UP,
				"spread": 180.0,
				"speed": Vector2(1.4, 3.2),
				"gravity": Vector3(0.0, -1.2, 0.0),
				"color": Color(1.0, 0.9, 0.55, 1.0),
				"color_end": Color(1.0, 0.6, 0.3, 0.0),
				"local": false,
			}
		)
	)
	add_child(_spark)
	_wind = (
		Puff
		. stream(
			DIR + "vfx/star_03.png",
			{
				"amount": 34,
				"lifetime": 1.4,
				"size": 0.22,
				"dir": Vector3.RIGHT,
				"spread": 6.0,
				"speed": Vector2(7.0, 11.0),
				"gravity": Vector3.ZERO,
				"color": Color(0.72, 0.88, 1.0, 0.7),
				"color_end": Color(0.7, 0.85, 1.0, 0.0),
				"box": Vector3(0.4, 5.0, 2.0),
				"local": false,
				"emitting": false,
			}
		)
	)
	_wind.position = Vector3(-11.0, 6.5, 0.0)
	add_child(_wind)
	_rescue_burst = (
		Puff
		. burst(
			DIR + "vfx/star_03.png",
			{
				"amount": 60,
				"lifetime": 1.3,
				"size": 0.42,
				"dir": Vector3.UP,
				"spread": 40.0,
				"speed": Vector2(3.5, 7.0),
				"gravity": Vector3(0.0, -3.4, 0.0),
				"color": Color(1.0, 0.88, 0.5, 1.0),
				"color_end": Color(1.0, 0.55, 0.75, 0.0),
				"scale_range": Vector2(0.8, 1.6),
				"local": false,
			}
		)
	)
	add_child(_rescue_burst)


# ── Takt ──────────────────────────────────────────────────────────────────


func _sync_craft(s: Dictionary, elapsed: float) -> void:
	_craft.position = Vector3(float(s["x"]), float(s["y"]), 0.0)
	_craft_tilt.rotation.z = float(s["tilt"])
	var squash := float(s.get("squash01", 0.0))
	_craft_tilt.scale = Vector3(1.0 + squash * 0.16, 1.0 - squash * 0.18, 1.0)
	var burning := bool(s["thrust"]) and float(s["fuel"]) > 0.0
	_flame.emitting = burning
	_dust.emitting = burning and float(s["y"]) < 1.6
	_carried.visible = bool(s["carrying"])
	if gooby != null:
		gooby.set_locomotion(0.25 + 0.7 * (1.0 if burning else 0.0))
	if _carried.visible:
		_carried.position.y = 0.02 + sin(elapsed * 5.0) * 0.03


func _sync_platforms(platforms: Array) -> void:
	for i in mini(_bunnies.size(), platforms.size()):
		_bunnies[i].visible = bool((platforms[i] as Dictionary)["bunny"])


func _sync_cans(cans: Array, elapsed: float) -> void:
	for i in mini(_cans.size(), cans.size()):
		var f: Dictionary = cans[i]
		var holder := _cans[i]
		holder.visible = not bool(f["taken"])
		if not holder.visible:
			continue
		holder.position.y = float(f["y"]) + sin(elapsed * 2.4 + float(f["x"])) * 0.09
		holder.rotation.y = elapsed * 1.1


func _sync_pad(s: Dictionary, elapsed: float) -> void:
	var pop := 1.0 + 0.35 * absf(sin(elapsed * 4.0)) * (1.0 if bool(s["carrying"]) else 0.35)
	for light in _pad_lights:
		light.scale = Vector3.ONE * pop


func _sync_wind(s: Dictionary) -> void:
	var wind: Dictionary = s["wind"]
	var phase := str(wind["phase"])
	var dir := float(wind["dir"])
	_wind.emitting = phase != "idle"
	if not _wind.emitting:
		return
	_wind.position.x = -11.0 * dir
	var mat := _wind.process_material as ParticleProcessMaterial
	mat.direction = Vector3(dir, 0.0, 0.0)
	_wind.speed_scale = 1.6 if phase == "gust" else 0.8
