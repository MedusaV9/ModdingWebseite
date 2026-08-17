extends Node3D
## ECHTER 3D-NACHTHIMMEL für die Sternenlaterne (FB-4, MP-D-Tiefenpolitur):
## eine leuchtende Papierlaterne (flackernder Kerzenkern) trägt Gooby
## (echtes Rig, Wunderkerzen-Stab in der Pfote) im Körbchen durch 3D-Ringe,
## Glühwürmchen und mondbeschienene Wolken. Drei GEFÄRBTE Sternschichten
## parallaxieren mit der Steighöhe, der Mond glüht mit weichem Hof, unten
## liegt ein DORF am SEE: zwei Hügelsilhouetten, warme Fensterlichter und
## ein Wasserband, auf dem Mondstreif und Laternenschein mitwandern —
## dazu steigen ferne Festlaternen auf. Die Kamera steht frontal auf die
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
var _core: MeshInstance3D
var _lake_shine: MeshInstance3D
var _festival: MultiMeshInstance3D
var _festival_seeds: Array[Vector3] = []
## Auffächernder Belohnungsring am Treffer-Punkt (skaliert + blendet aus).
var _award_ring: MeshInstance3D
var _award_ring_mat: StandardMaterial3D
var _award_ring_t := 0.0
## Kurzer Freuden-Puls des Laternenlichts nach einem Gold-Ring.
var _light_boost := 0.0
## Sternschnuppe: zieht alle paar Sekunden still über den oberen Himmel.
var _shooting_star: MeshInstance3D
var _star_mat: StandardMaterial3D
var _star_t := -4.0
var _star_from := Vector3.ZERO
var _star_dir := Vector3.ZERO
## Spielpose der Kamera aus frame() — Basis für den Intro-Anflug (W17/G5).
var _cam_base := Vector3(0.0, 0.0, CAM_DIST)


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
				"sky_horizon": Color(0.19, 0.13, 0.3),
				"ground_horizon": Color(0.19, 0.13, 0.3),
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
	_build_award_ring()
	_build_shooting_star()


## Auffächernder Torus am Treffer-Punkt — der Ring-Gewinn liest sich als
## Welle, nicht nur als Funkenstoß.
func _build_award_ring() -> void:
	_award_ring = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.42
	torus.outer_radius = 0.5
	torus.rings = 24
	torus.ring_segments = 6
	_award_ring_mat = Fx.glow(GOLD, 1.2)
	_award_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	torus.material = _award_ring_mat
	_award_ring.mesh = torus
	_award_ring.rotation_degrees.x = 90.0
	_award_ring.visible = false
	_award_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_award_ring)


## Dünner Leuchtstrich, den sync() alle paar Sekunden über den oberen
## Himmel ziehen lässt — stiller Nachtzauber, keine Mechanik.
func _build_shooting_star() -> void:
	_shooting_star = MeshInstance3D.new()
	var streak := BoxMesh.new()
	streak.size = Vector3(1.4, 0.05, 0.05)
	_star_mat = Fx.glow(Color(1.0, 0.97, 0.85), 1.6)
	_star_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	streak.material = _star_mat
	_shooting_star.mesh = streak
	_shooting_star.visible = false
	_shooting_star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shooting_star)


func _build_sky() -> void:
	# Drei Sternschichten (nah/mittel/fern) — jede EINE MultiMesh, die mit der
	# Steighöhe nach unten wandert und über ein 16-m-Raster gekachelt wrappt.
	# Jede Schicht hat ihre eigene Farbe (warmweiß/eisblau/goldgelb) — der
	# Himmel bekommt Tiefe statt Einheits-Punkten.
	var star_tints: Array[Color] = [
		Color(1.0, 0.97, 0.85), Color(0.78, 0.88, 1.0), Color(1.0, 0.88, 0.6)
	]
	var depths: Array[float] = [0.5, 0.8, 1.2]
	for d in depths.size():
		var depth := depths[d]
		var layer := MultiMeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.035 + depth * 0.045
		mesh.height = mesh.radius * 2.0
		mesh.radial_segments = 6
		mesh.rings = 3
		mesh.material = Fx.glow(star_tints[d], 0.5 + depth * 0.5)
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
	_build_moon()
	_build_village()
	_build_lake()
	_build_festival()


## Mond mit weichem Hof (transparente Hüllkugel statt hartem Rand).
func _build_moon() -> void:
	var moon := MeshInstance3D.new()
	var moon_mesh := SphereMesh.new()
	moon_mesh.radius = 1.1
	moon_mesh.height = 2.2
	moon_mesh.material = Fx.glow(Color(1.0, 0.96, 0.82), 1.1)
	moon.mesh = moon_mesh
	moon.position = Vector3(4.5, 6.0, -18.0)
	moon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(moon)
	var halo := MeshInstance3D.new()
	var halo_mesh := SphereMesh.new()
	halo_mesh.radius = 1.9
	halo_mesh.height = 3.8
	var halo_mat := Fx.glow(Color(1.0, 0.93, 0.72, 0.14), 0.35)
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mesh.material = halo_mat
	halo.mesh = halo_mesh
	halo.position = Vector3(4.5, 6.0, -18.2)
	halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(halo)


## Dorf am Seeufer: ZWEI Hügelsilhouetten (nah dunkel, fern violett) und
## warme Fensterlichter — die Welt unter der Laterne lebt. Bleibt fix im Bild.
## WICHTIG (2 Fallen): (a) das Band liegt bei y ≈ −4…−7 — tiefer fiel es in
## BEIDEN Orientierungen unter die Bildkante; (b) die Hügel-KUGELN reichen
## bis z=−7 nach VORN — Lichter/See müssen z ≥ −6,9 liegen, sonst stecken
## sie IN den Kugeln und werden verdeckt.
func _build_village() -> void:
	var hills := MultiMeshInstance3D.new()
	var hill_mesh := SphereMesh.new()
	hill_mesh.radius = 1.0
	hill_mesh.height = 2.0
	# Leises Eigenleuchten: reine flat-Silhouetten rendern in der Nacht
	# (Sonne 0,35) als konturloses Schwarz — so lesen sie als mondblaue Hügel.
	# Matt stellen: Fx.glow bringt Metallic/Glanz mit, das las sich als
	# Seifenblasen-Glint auf jeder Kuppe.
	var hill_mat := Fx.glow(Color(0.1, 0.13, 0.22), 0.3)
	hill_mat.metallic = 0.0
	hill_mat.roughness = 0.95
	hill_mesh.material = hill_mat
	var hill_mm := MultiMesh.new()
	hill_mm.transform_format = MultiMesh.TRANSFORM_3D
	hill_mm.mesh = hill_mesh
	hill_mm.instance_count = 9
	for i in 9:
		var b := Basis.IDENTITY.scaled(Vector3(1.9, 0.9 + 0.35 * float(i % 3), 1.0))
		hill_mm.set_instance_transform(
			i, Transform3D(b, Vector3(-9.6 + float(i) * 2.4, -4.6, -8.0))
		)
	hills.multimesh = hill_mm
	hills.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(hills)
	var far_hills := MultiMeshInstance3D.new()
	var far_mm := MultiMesh.new()
	far_mm.transform_format = MultiMesh.TRANSFORM_3D
	var far_mesh := SphereMesh.new()
	far_mesh.radius = 1.0
	far_mesh.height = 2.0
	var far_mat := Fx.glow(Color(0.13, 0.11, 0.26), 0.26)
	far_mat.metallic = 0.0
	far_mat.roughness = 0.95
	far_mesh.material = far_mat
	far_mm.mesh = far_mesh
	far_mm.instance_count = 7
	for i in 7:
		var b := Basis.IDENTITY.scaled(Vector3(3.0, 1.5 + 0.5 * float(i % 2), 1.0))
		far_mm.set_instance_transform(
			i, Transform3D(b, Vector3(-11.0 + float(i) * 3.8, -6.0, -11.0))
		)
	far_hills.multimesh = far_mm
	far_hills.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(far_hills)
	# Fensterlichter zwischen den Hügeln — EIN MultiMesh warmer Punkte.
	# Groß genug, dass sie auf 18 m Distanz noch als Fenster lesen.
	var lights := MultiMeshInstance3D.new()
	var dot := BoxMesh.new()
	dot.size = Vector3(0.16, 0.2, 0.05)
	dot.material = Fx.glow(Color(1.0, 0.82, 0.5), 1.6)
	var light_mm := MultiMesh.new()
	light_mm.transform_format = MultiMesh.TRANSFORM_3D
	light_mm.mesh = dot
	light_mm.instance_count = 8
	var rng := RandomNumberGenerator.new()
	rng.seed = 815
	for i in 8:
		light_mm.set_instance_transform(
			i,
			Transform3D(
				Basis.IDENTITY,
				Vector3(rng.randf_range(-5.2, 5.2), rng.randf_range(-5.1, -4.5), -6.9)
			)
		)
	lights.multimesh = light_mm
	lights.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lights)


## Wasserband unterm Dorf: dunkler See mit Mondstreif; der Laternenschein
## (_lake_shine) wandert in sync() mit der Laterne mit. Der See steht klar
## VOR den Hügelkugeln (z −6,5; die Kugeln reichen bis z −7) — die Oberkante
## des Bands (y ≈ −5,3) bildet das Ufer am unteren Bildrand.
func _build_lake() -> void:
	var water := MeshInstance3D.new()
	var water_mesh := BoxMesh.new()
	water_mesh.size = Vector3(30.0, 4.0, 0.1)
	# 0,5 statt 0,18: darunter war das Band vom Nachtblau nicht unterscheidbar.
	var water_mat := Fx.glow(Color(0.12, 0.15, 0.32), 0.5)
	water_mat.roughness = 0.25
	water_mesh.material = water_mat
	water.mesh = water_mesh
	water.position = Vector3(0.0, -7.3, -6.5)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(water)
	var moon_streak := MeshInstance3D.new()
	var streak_mesh := BoxMesh.new()
	streak_mesh.size = Vector3(0.7, 3.6, 0.08)
	var streak_mat := Fx.glow(Color(1.0, 0.93, 0.7, 0.32), 0.55)
	streak_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	streak_mesh.material = streak_mat
	moon_streak.mesh = streak_mesh
	moon_streak.position = Vector3(3.4, -7.05, -6.45)
	moon_streak.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(moon_streak)
	_lake_shine = MeshInstance3D.new()
	var shine_mesh := BoxMesh.new()
	shine_mesh.size = Vector3(0.5, 2.6, 0.08)
	var shine_mat := Fx.glow(Color(1.0, 0.76, 0.42, 0.3), 0.6)
	shine_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shine_mesh.material = shine_mat
	_lake_shine.mesh = shine_mesh
	_lake_shine.position = Vector3(0.0, -6.55, -6.4)
	_lake_shine.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_lake_shine)


## Ferne Festlaternen steigen still hinterm Dorf auf (EIN MultiMesh,
## sync() lässt sie wrappen und seitlich schaukeln).
func _build_festival() -> void:
	var body := CylinderMesh.new()
	body.top_radius = 0.09
	body.bottom_radius = 0.13
	body.height = 0.24
	body.radial_segments = 8
	body.material = Fx.glow(Color(1.0, 0.7, 0.38), 1.4)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = body
	mm.instance_count = 7
	_festival = MultiMeshInstance3D.new()
	_festival.multimesh = mm
	_festival.extra_cull_margin = 40.0
	_festival.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_festival)
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	for i in 7:
		# x: Grundposition, y: Steig-Phase 0..1, z: Schaukel-Phase.
		_festival_seeds.append(
			Vector3(rng.randf_range(-8.0, 8.0), rng.randf(), rng.randf_range(0.0, TAU))
		)


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
	_core = MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.12
	core_mesh.height = 0.24
	core_mesh.material = Fx.glow(Color(1.0, 0.95, 0.65), 2.4)
	_core.mesh = core_mesh
	_core.position.y = 0.26
	_lantern.add_child(_core)
	_lantern_light = OmniLight3D.new()
	_lantern_light.light_color = Color(1.0, 0.8, 0.5)
	_lantern_light.light_energy = 1.4
	_lantern_light.omni_range = 4.5
	_lantern_light.position.y = 0.3
	_lantern.add_child(_lantern_light)
	# Körbchen an Schnüren, Gooby sitzt darin und schaut in die Nacht.
	# (W13C-Leak-Gate: hier hing ein nie eingehängtes MeshInstance3D —
	# ein Waisen-Node + Renderer-RID pro Stage-Aufbau. Die Schnüre sind
	# die beiden `line`-Nodes unten, `string_mesh` wird geteilt.)
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
	gooby.mount(0.66)
	gooby.base_emotion = "happy"
	# Wunderkerzen-Stab in der Pfote — Gooby feiert die Nacht sichtbar mit.
	gooby.hold(
		_sparkler_prop(),
		"arm.R",
		Transform3D(Basis(Vector3.RIGHT, -0.9), Vector3(0.0, -0.05, 0.04))
	)


## Kleiner Wunderkerzen-Stab: Holzgriff + goldglühende Sternkugel.
func _sparkler_prop() -> Node3D:
	var holder := Node3D.new()
	var stick := MeshInstance3D.new()
	var stick_mesh := CylinderMesh.new()
	stick_mesh.top_radius = 0.012
	stick_mesh.bottom_radius = 0.012
	stick_mesh.height = 0.22
	stick_mesh.radial_segments = 5
	stick_mesh.material = Fx.flat(Color(0.6, 0.44, 0.3))
	stick.mesh = stick_mesh
	holder.add_child(stick)
	var spark := MeshInstance3D.new()
	var spark_mesh := SphereMesh.new()
	spark_mesh.radius = 0.045
	spark_mesh.height = 0.09
	spark_mesh.radial_segments = 8
	spark_mesh.rings = 4
	spark_mesh.material = Fx.glow(GOLD, 2.2)
	spark.mesh = spark_mesh
	spark.position.y = 0.13
	holder.add_child(spark)
	return holder


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
			# Mondbeschienener Saum: leichtes Eigenleuchten hebt die Wolke
			# als Hindernis vom Nachtblau ab.
			puff_mesh.material = Fx.glow(Color(0.6, 0.62, 0.8), 0.14)
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
	_cam_base = Vector3(0.0, cam_y, CAM_DIST)
	stage.camera.position = _cam_base
	stage.camera.rotation = Vector3.ZERO
	stage.set_half_height(half_h, CAM_DIST)


## W17/G5 M1: Intro-Totale — die Kamera startet gesenkt Richtung Dorf und
## See (dort startet die Laterne ihre Fahrt) und hebt in die Spielpose.
## k läuft 0 → 1; bei k=1 steht EXAKT die frame()-Pose (kein Ruck beim
## Übergang in die Runde). Reduced Motion ruft mit k=1 auf (kein Flug).
func establish(k: float) -> void:
	var e := 1.0 - ease(clampf(k, 0.0, 1.0), 0.4)
	stage.camera.position = _cam_base + Vector3(0.0, -2.6, -1.6) * e
	stage.camera.rotation_degrees = Vector3(-7.0 * e, 0.0, 0.0)


## Sieg-Feier am Rundenende (W17/G5, NUR Präsentation): Gooby jubelt im
## Körbchen, die Laterne strahlt. Hüpfer + Funkenstoß entfallen unter
## Reduced Motion (Q2-Regel: Gate an der Call-Site, das Fx-Kit bleibt tabu).
func celebrate(reduced := false) -> void:
	gooby.play_for("celebrate", 1.2)
	gooby.emote("ecstatic", 1.6)
	_light_boost = 1.0
	stage.pulse_glow(0.9)
	if reduced:
		return
	gooby.hop(0.4, 0.24)
	Fx.burst(_burst, _lantern.position + Vector3(0.0, 0.4, 0.25))


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
	# Kerze flackert lebendig; getroffen blinkt die Laterne deutlich,
	# nach einem Gold-Ring strahlt sie kurz heller (Freuden-Puls).
	var candle := 0.92 + 0.08 * sin(pulse * 9.0) * sin(pulse * 4.7 + 1.3)
	var flicker := candle if invuln <= 0.0 else (0.35 + 0.65 * absf(sin(invuln * 22.0)))
	_light_boost = maxf(0.0, _light_boost - delta * 1.8)
	_lantern_light.light_energy = 1.4 * flicker + 1.3 * _light_boost
	_core.scale = Vector3.ONE * (0.9 + 0.2 * flicker + 0.25 * _light_boost)
	# Laternenschein wandert auf dem See mit und atmet mit der Kerze.
	_lake_shine.position.x = lantern_x
	_lake_shine.scale = Vector3(0.85 + 0.3 * flicker, 1.0, 1.0)
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
	_drift_festival(pulse)
	_tick_award_ring(delta)
	_tick_shooting_star(delta)


## Belohnungsring fächert auf (Skala hoch, Alpha runter) und erlischt.
func _tick_award_ring(delta: float) -> void:
	if _award_ring_t <= 0.0:
		_award_ring.visible = false
		return
	_award_ring_t = maxf(0.0, _award_ring_t - delta)
	var frac := 1.0 - _award_ring_t / 0.55
	_award_ring.visible = true
	_award_ring.scale = Vector3.ONE * (0.5 + 2.2 * frac)
	var tint := _award_ring_mat.emission
	_award_ring_mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.85 * (1.0 - frac))


## Sternschnuppe: alle paar Sekunden zieht ein Leuchtstrich schräg über den
## oberen Himmel (reine Kulisse, eigener Takt — kein Spiel-RNG).
func _tick_shooting_star(delta: float) -> void:
	_star_t += delta
	if _star_t < 0.0:
		_shooting_star.visible = false
		return
	if _star_t > 0.9:
		_shooting_star.visible = false
		_star_t = -randf_range(5.0, 10.0)
		return
	if not _shooting_star.visible:
		var right := randf() < 0.5
		_star_from = Vector3(randf_range(-7.0, 1.0) * (1.0 if right else -1.0), 7.5, -9.5)
		_star_dir = Vector3(3.6 if right else -3.6, -1.8, 0.0)
		_shooting_star.rotation.z = atan2(_star_dir.y, _star_dir.x)
		_shooting_star.visible = true
	var frac := _star_t / 0.9
	_shooting_star.position = _star_from + _star_dir * (frac * 2.4)
	_star_mat.albedo_color = Color(1.0, 0.97, 0.85, 0.9 * sin(frac * PI))


## Ferne Festlaternen steigen langsam auf, schaukeln leicht und wrappen
## unterhalb des Sees wieder ein — stiller Bilduntergrund, keine Mechanik.
func _drift_festival(pulse: float) -> void:
	var mm := _festival.multimesh
	for i in _festival_seeds.size():
		var sd := _festival_seeds[i]
		var t := fposmod(sd.y + pulse * 0.02, 1.0)
		var y := lerpf(-8.0, 4.0, t)
		var x := sd.x + 0.6 * sin(pulse * 0.7 + sd.z)
		var s := lerpf(1.0, 0.55, t)
		mm.set_instance_transform(
			i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * s), Vector3(x, y, -6.7))
		)


## Bildschirmanker (Canvas-Einheiten) an einer Weltposition relativ zur Fahrt.
func to_screen(wx: float, wy_minus_travel: float) -> Vector2:
	return stage.to_screen(Vector3(wx, wy_minus_travel, 0.0))


## `reduced` (W17/G5, Q2): der Partikel-Burst und der Hüpfer entfallen unter
## Reduced Motion — Gate an DIESER Call-Site, das Fx-Kit selbst bleibt tabu.
## Belohnungsring, Emote und Licht-Puls bleiben als statisches Feedback.
func award_fx(wx: float, wy_minus_travel: float, gold: bool, reduced := false) -> void:
	if not reduced:
		Fx.burst(_burst, Vector3(wx, wy_minus_travel, 0.2))
	# Auffächernder Ring am Treffer-Punkt: Gold warm, Blau kühl.
	var tint := GOLD if gold else BLUE
	_award_ring_mat.emission = tint
	_award_ring_mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.85)
	_award_ring.position = Vector3(wx, wy_minus_travel, 0.25)
	_award_ring_t = 0.55
	if gold:
		gooby.emote("ecstatic", 1.0)
		gooby.play_for("celebrate", 0.9)
		if not reduced:
			gooby.hop(0.4, 0.22)
		_light_boost = 1.0
		stage.pulse_glow(0.9)
	else:
		gooby.emote("happy", 0.6)
		if not reduced:
			gooby.hop(0.3, 0.12)
		_light_boost = maxf(_light_boost, 0.45)
		stage.pulse_glow(0.35)


func bump_fx() -> void:
	gooby.emote("scared", 1.2)
	gooby.swing(0.4, 16.0, Vector3.BACK)
