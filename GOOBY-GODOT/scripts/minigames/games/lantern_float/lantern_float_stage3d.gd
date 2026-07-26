extends Node3D
## ECHTER 3D-NACHTHIMMEL für die Sternenlaterne (FB-4): eine leuchtende
## Papierlaterne trägt Gooby (echtes Rig) in einem Körbchen durch 3D-Ringe,
## Glühwürmchen und Wolken; drei Sternschichten parallaxieren mit der
## Steighöhe, der Mond glüht hinten. Die Kamera steht frontal auf die
## Flugebene z=0 und rahmt EXAKT die 2D-Projektion des Spiels — alle
## MECHANIK-Zahlen bleiben in lantern_float.gd/LanternFloatLogic.

const Stage3D := preload("res://scripts/minigames/games/_3dc_stage/stage3d.gd")
const Actor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")

const CAM_DIST := 10.0
const RING_POOL := 8
const GOLD := Color(1.0, 0.83, 0.35)
const BLUE := Color(0.66, 0.9, 1.0)

var stage: Node3D
var gooby: Node3D

var _ring_radius := 1.0
var _cloud_half_w := 1.0
var _lantern: Node3D
var _lantern_light: OmniLight3D
var _slots: Array[Dictionary] = []
var _gold_mat: StandardMaterial3D
var _blue_mat: StandardMaterial3D
var _gold_done: StandardMaterial3D
var _blue_done: StandardMaterial3D
var _star_layers: Array[MultiMeshInstance3D] = []
var _burst: GPUParticles3D
var _anchor_y := 0.0


func setup_stage(ring_radius: float, cloud_half_w: float) -> void:
	_ring_radius = ring_radius
	_cloud_half_w = cloud_half_w
	stage = Stage3D.new()
	add_child(stage)
	(
		stage
		. build(
			{
				# Tiefe Sommernacht: Mondlicht kühl, Glow trägt Laterne+Ringe.
				# Boden-Hälfte der Sky = Nachtblau wie oben: die Kamera schaut
				# frontal, ein andersfarbiger "Boden" stünde sonst als harte
				# Linie mitten im Bild.
				"sky_top": Color(0.05, 0.06, 0.16),
				"sky_horizon": Color(0.16, 0.12, 0.28),
				"ground_horizon": Color(0.16, 0.12, 0.28),
				"ground_bottom": Color(0.07, 0.07, 0.2),
				"sun_dir": Vector3(0.35, -0.8, -0.45),
				"sun_color": Color(0.72, 0.8, 1.0),
				"sun_energy": 0.35,
				"ambient": 0.5,
				"fill_color": Color(0.55, 0.6, 0.95),
				"fill_energy": 0.2,
				"glow": 0.5,
				"glow_threshold": 0.62,
				"shadows": false,
				"far": 120.0,
			}
		)
	)
	_gold_mat = Fx.glow(GOLD, 1.3)
	_blue_mat = Fx.glow(BLUE, 1.0)
	_gold_done = Fx.glow(Color(GOLD.r, GOLD.g, GOLD.b, 0.25), 0.2)
	_gold_done.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_blue_done = Fx.glow(Color(BLUE.r, BLUE.g, BLUE.b, 0.25), 0.15)
	_blue_done.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_build_sky()
	_build_lantern()
	_build_slots()
	_burst = (
		Fx
		. particles(
			{
				"color": Color(1.0, 0.9, 0.55, 0.9),
				"amount": 20,
				"lifetime": 0.7,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(1.0, 2.6),
				"spread": 80.0,
				"gravity": Vector3(0.0, -1.2, 0.0),
				"size": Vector2(0.05, 0.13),
				"additive": true,
			}
		)
	)
	add_child(_burst)


func _build_sky() -> void:
	# Drei Sternschichten (nah/mittel/fern) — jede EINE MultiMesh, die mit der
	# Steighöhe nach unten wandert und über ein 16-m-Raster gekachelt wrappt.
	for depth: float in [0.5, 0.8, 1.2]:
		var layer := MultiMeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.035 + depth * 0.045
		mesh.height = mesh.radius * 2.0
		mesh.radial_segments = 6
		mesh.rings = 3
		mesh.material = Fx.glow(Color(1.0, 0.97, 0.85), 0.5 + depth * 0.5)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = 44
		var seed_rng := RandomNumberGenerator.new()
		seed_rng.seed = int(depth * 1000.0)
		for i in 22:
			var x := seed_rng.randf_range(-9.0, 9.0)
			var y := seed_rng.randf_range(-8.0, 8.0)
			var z := -6.0 - depth * 8.0
			mm.set_instance_transform(2 * i, Transform3D(Basis.IDENTITY, Vector3(x, y, z)))
			mm.set_instance_transform(
				2 * i + 1, Transform3D(Basis.IDENTITY, Vector3(x, y + 16.0, z))
			)
		layer.multimesh = mm
		layer.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		layer.set_meta("depth", depth)
		add_child(layer)
		_star_layers.append(layer)
	# Mond mit weichem Hof.
	var moon := MeshInstance3D.new()
	var moon_mesh := SphereMesh.new()
	moon_mesh.radius = 1.1
	moon_mesh.height = 2.2
	moon_mesh.material = Fx.glow(Color(1.0, 0.96, 0.82), 1.1)
	moon.mesh = moon_mesh
	moon.position = Vector3(4.5, 6.0, -18.0)
	moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(moon)
	# Gartensilhouette tief unten (dunkle Baumkugeln), bleibt fix im Bild.
	var hills := MultiMeshInstance3D.new()
	var hill_mesh := SphereMesh.new()
	hill_mesh.radius = 1.0
	hill_mesh.height = 2.0
	hill_mesh.material = Fx.flat(Color(0.07, 0.13, 0.13))
	var hill_mm := MultiMesh.new()
	hill_mm.transform_format = MultiMesh.TRANSFORM_3D
	hill_mm.mesh = hill_mesh
	hill_mm.instance_count = 9
	for i in 9:
		var b := Basis.IDENTITY.scaled(Vector3(1.9, 0.9 + 0.35 * float(i % 3), 1.0))
		hill_mm.set_instance_transform(
			i, Transform3D(b, Vector3(-9.6 + float(i) * 2.4, -7.4, -8.0))
		)
	hills.multimesh = hill_mm
	hills.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(hills)


func _build_lantern() -> void:
	_lantern = Node3D.new()
	add_child(_lantern)
	# Papierkörper: konischer Zylinder, warm glühend.
	var body := MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.26
	body_mesh.bottom_radius = 0.36
	body_mesh.height = 0.62
	body_mesh.radial_segments = 12
	var paper := Fx.glow(Color(1.0, 0.72, 0.42), 0.9)
	paper.roughness = 0.7
	body_mesh.material = paper
	body.mesh = body_mesh
	body.position.y = 0.3
	_lantern.add_child(body)
	# Deckel + Kerzenkern.
	var cap := MeshInstance3D.new()
	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 0.18
	cap_mesh.bottom_radius = 0.28
	cap_mesh.height = 0.09
	cap_mesh.material = Fx.flat(Color(0.5, 0.26, 0.2))
	cap.mesh = cap_mesh
	cap.position.y = 0.66
	_lantern.add_child(cap)
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.12
	core_mesh.height = 0.24
	core_mesh.material = Fx.glow(Color(1.0, 0.95, 0.65), 2.4)
	core.mesh = core_mesh
	core.position.y = 0.26
	_lantern.add_child(core)
	_lantern_light = OmniLight3D.new()
	_lantern_light.light_color = Color(1.0, 0.8, 0.5)
	_lantern_light.light_energy = 1.4
	_lantern_light.omni_range = 4.5
	_lantern_light.position.y = 0.3
	_lantern.add_child(_lantern_light)
	# Körbchen an Schnüren, Gooby sitzt darin und schaut in die Nacht.
	var strings := MeshInstance3D.new()
	var string_mesh := CylinderMesh.new()
	string_mesh.top_radius = 0.012
	string_mesh.bottom_radius = 0.012
	string_mesh.height = 0.5
	string_mesh.radial_segments = 5
	string_mesh.material = Fx.flat(Color(0.65, 0.5, 0.34))
	for side: float in [-0.2, 0.2]:
		var line := MeshInstance3D.new()
		line.mesh = string_mesh
		line.position = Vector3(side, -0.25, 0.0)
		_lantern.add_child(line)
	var basket := MeshInstance3D.new()
	var basket_mesh := CylinderMesh.new()
	basket_mesh.top_radius = 0.3
	basket_mesh.bottom_radius = 0.24
	basket_mesh.height = 0.26
	basket_mesh.radial_segments = 10
	basket_mesh.material = Fx.flat(Color(0.62, 0.44, 0.28))
	basket.mesh = basket_mesh
	basket.position.y = -0.58
	_lantern.add_child(basket)
	gooby = Actor.new()
	gooby.position = Vector3(0.0, -0.52, 0.05)
	_lantern.add_child(gooby)
	gooby.mount(0.6)
	gooby.base_emotion = "happy"


func _build_slots() -> void:
	for i in RING_POOL:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = _ring_radius - 0.07
		torus.outer_radius = _ring_radius
		torus.rings = 32
		torus.ring_segments = 8
		torus.material = _blue_mat
		ring.mesh = torus
		# Torus liegt flach in xz — um x kippen, damit er der Kamera zugewandt
		# steht und die Laterne durch die Öffnung fliegt.
		ring.rotation_degrees.x = 90.0
		ring.visible = false
		ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(ring)
		var firefly := MeshInstance3D.new()
		var fly_mesh := SphereMesh.new()
		fly_mesh.radius = 0.11
		fly_mesh.height = 0.22
		fly_mesh.material = Fx.glow(Color(1.0, 0.97, 0.6), 2.0)
		firefly.mesh = fly_mesh
		firefly.visible = false
		firefly.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(firefly)
		var cloud := Node3D.new()
		for p in 4:
			var puff := MeshInstance3D.new()
			var puff_mesh := SphereMesh.new()
			puff_mesh.radius = _cloud_half_w * 0.52
			puff_mesh.height = _cloud_half_w * 0.84
			puff_mesh.material = Fx.flat(Color(0.62, 0.64, 0.8))
			puff.mesh = puff_mesh
			puff.position = Vector3(
				(-0.55 + 0.37 * float(p)) * _cloud_half_w * 2.0,
				sin(float(p) * 1.3) * _cloud_half_w * 0.16,
				0.0
			)
			puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			cloud.add_child(puff)
		cloud.visible = false
		add_child(cloud)
		_slots.append({"ring": ring, "firefly": firefly, "cloud": cloud})


## Kamera frontal auf die Flugebene: Bildmaßstab wie die 2D-Projektion
## (`scale` Pixel je Weltmeter, Laterne bei 72 %/68 % Bildhöhe).
func frame(vp: Vector2, world_scale: float, landscape: bool) -> void:
	stage.apply_size(vp)
	var half_h := vp.y * 0.5 / maxf(1.0, world_scale)
	_anchor_y = (0.72 if not landscape else 0.68) * vp.y
	var cam_y := (_anchor_y - vp.y * 0.5) / maxf(1.0, world_scale)
	stage.camera.position = Vector3(0.0, cam_y, CAM_DIST)
	stage.camera.rotation = Vector3.ZERO
	stage.set_half_height(half_h, CAM_DIST)


## Jeden Frame: Laterne, Ringe/Glühwürmchen/Wolken und Sterne stellen.
func sync(
	rings: Array[Dictionary],
	travel: float,
	lantern_x: float,
	invuln: float,
	pulse: float,
	delta: float
) -> void:
	stage.tick(delta)
	gooby.tick(delta)
	# Seitliche Fahrt neigt die Laterne leicht dagegen (Pendel am Körbchen).
	var prev_x := _lantern.position.x
	_lantern.position = Vector3(lantern_x, sin(pulse * 2.4) * 0.05, 0.0)
	var tilt := clampf((prev_x - lantern_x) * 6.0, -0.22, 0.22)
	_lantern.rotation.z = lerpf(_lantern.rotation.z, tilt, minf(1.0, 10.0 * delta))
	# Getroffen: Laterne blinkt über die Kern-Emission.
	var flicker := 1.0 if invuln <= 0.0 else (0.35 + 0.65 * absf(sin(invuln * 22.0)))
	_lantern_light.light_energy = 1.4 * flicker
	for i in _slots.size():
		var slot := _slots[i]
		var ring_node: MeshInstance3D = slot["ring"]
		var firefly: MeshInstance3D = slot["firefly"]
		var cloud: Node3D = slot["cloud"]
		if i >= rings.size():
			ring_node.visible = false
			firefly.visible = false
			cloud.visible = false
			continue
		var ring: Dictionary = rings[i]
		var dy := float(ring["y"]) - travel
		ring_node.visible = true
		ring_node.position = Vector3(float(ring["x"]), dy, 0.0)
		ring_node.rotation.z = pulse * (1.4 if bool(ring["gold"]) else 0.6)
		var done := bool(ring["done"])
		if bool(ring["gold"]):
			ring_node.mesh.material = _gold_done if done else _gold_mat
		else:
			ring_node.mesh.material = _blue_done if done else _blue_mat
		firefly.visible = bool(ring["firefly"]) and not bool(ring["firefly_done"])
		if firefly.visible:
			firefly.position = Vector3(float(ring["firefly_x"]), dy - 1.6, 0.1)
			firefly.scale = Vector3.ONE * (0.7 + 0.4 * absf(sin(pulse * 7.0 + float(i))))
		var cloud_info: Dictionary = ring["cloud"]
		cloud.visible = bool(cloud_info["present"]) and not bool(ring["cloud_done"])
		if cloud.visible:
			cloud.position = Vector3(float(cloud_info["x"]), dy - 0.8, 0.2)
	# Sternschichten wandern mit der Steighöhe nach unten (Parallax + Wrap).
	for layer in _star_layers:
		var depth := float(layer.get_meta("depth"))
		layer.position.y = -fposmod(travel * depth, 16.0)


## Bildschirmanker (Canvas-Einheiten) an einer Weltposition relativ zur Fahrt.
func to_screen(wx: float, wy_minus_travel: float) -> Vector2:
	return stage.to_screen(Vector3(wx, wy_minus_travel, 0.0))


func award_fx(wx: float, wy_minus_travel: float, gold: bool) -> void:
	Fx.burst(_burst, Vector3(wx, wy_minus_travel, 0.2))
	if gold:
		gooby.emote("ecstatic", 1.0)
		gooby.play_for("celebrate", 0.9)
		stage.pulse_glow(0.9)
	else:
		stage.pulse_glow(0.35)


func bump_fx() -> void:
	gooby.emote("scared", 1.2)
