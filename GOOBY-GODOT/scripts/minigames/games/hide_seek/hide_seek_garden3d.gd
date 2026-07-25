extends "res://scripts/minigames/games/_3dc_stage/stage3d.gd"
## Guck-guck-Garten — 3D-Gartenbühne (Agent 3D-C). Gooby ist der SUCHER: er
## steht groß im Vordergrund auf der Wiese, schaut über die Beete (Clip
## `idle_lookaround`) und wechselt die Miene, wenn ein Tierchen lugt oder eine
## Welle abläuft. Die Verstecke sind echte Nature-Kit-Requisiten (Busch,
## Baumstumpf, Blumentopf) auf einer Erdscheibe; über dem Hangrücken stehen
## Baumkronen im Himmel.
##
## Verankerung: das Spiel rechnet sein Raster weiter in BILDSCHIRMPIXELN
## (`spot_center`, `_spot_at`). Die Bühne strahlt genau diese Punkte auf den
## Gartenhang zurück und skaliert jede Requisite über die projizierte
## Zellbreite — jedes 3D-Versteck sitzt exakt auf seiner Tippfläche und ist in
## beiden Orientierungen gleich groß.
##
## Warum ein STEILER Hang (Neigung 1,35) und eine flache Kamera (−16°): der
## Hang steht damit fast senkrecht zur Blickachse. Auf einem waagerechten Boden
## läge die oberste Rasterreihe nahe am Horizont — dort wären Requisiten
## zwanzig Meter entfernt und müssten grotesk hochskaliert werden. So liegen
## alle vier Reihen zwischen 12,7 m und 15,2 m: gleiche Größe, gleiche Schärfe.

const Models := preload("res://scripts/minigames/games/_3dc_stage/models3d.gd")
const Puff := preload("res://scripts/minigames/games/_3dc_stage/puff3d.gd")
const DIR := "res://assets/minigames/hide_seek/"

const CAM_POS := Vector3(0.0, 3.6, 12.0)
const CAM_PITCH := -16.0
## Sichtbare halbe Bildhöhe in CAM_REF Metern Entfernung (≈ 52° senkrecht).
const CAM_HALF_H := 6.34
const CAM_REF := 13.0
## Hangebene: y + SLOPE·z = BASE, oben abgeschnitten bei BED_TOP_Z.
const SLOPE := 1.35
const BASE := -0.65
const BED_TOP_Z := -3.9
const BED_LEN := 13.0
## Bezugsbreite einer Rasterzelle in Bühnen-Einheiten (Requisiten sind auf
## ~1,5 Einheiten gebaut und füllen damit gut die halbe Zelle).
const CELL_REF := 1.75
## Gooby-Anker (Bildschirmanteil) und Wunschhöhe (Anteil der Bildhöhe).
const GOOBY_ANCHOR := Vector2(0.22, 0.90)
const GOOBY_HEIGHT := 0.2
const RIG_HEIGHT := 1.132

var gooby: GoobyRig

var _spots: Array[Node3D] = []
var _props: Array[Node3D] = []
var _critters: Array[Node3D] = []
var _leaves: GPUParticles3D
var _gooby_shade: MeshInstance3D
var _emotion := "happy"


func setup_stage(spot_count: int) -> void:
	build(
		{
			"sky_top": Color(0.36, 0.66, 0.93),
			"sky_horizon": Color(0.88, 0.95, 0.92),
			"ground_horizon": Color(0.66, 0.83, 0.56),
			"ground_bottom": Color(0.44, 0.64, 0.38),
			"sky_energy": 0.9,
			"ambient": 0.5,
			"sun_color": Color(1.0, 0.95, 0.82),
			"sun_energy": 1.35,
			"sun_dir": Vector3(-0.44, -0.7, -0.56),
			"fill_color": Color(0.66, 0.84, 1.0),
			"fill_energy": 0.34,
			"shadows": false,
			"glow": 0.2,
			"glow_bloom": 0.02,
			"glow_threshold": 1.1,
			"fog": true,
			"fog_color": Color(0.8, 0.9, 0.84),
			"fog_from": 22.0,
			"fog_to": 60.0,
			"far": 120.0,
		}
	)
	set_half_height(CAM_HALF_H, CAM_REF)
	camera.position = CAM_POS
	camera.rotation_degrees = Vector3(CAM_PITCH, 0.0, 0.0)
	_build_bank()
	_build_skyline()
	_build_gooby()
	for i in spot_count:
		_build_spot(i)
	_build_effects()


## Raster neu einmessen: jeder Bildschirmmittelpunkt wird auf den Hang
## gestrahlt, die projizierte Zellbreite bestimmt die Requisitengröße.
func layout(centers: Array, cell: Vector2, size: Vector2) -> void:
	for i in mini(_spots.size(), centers.size()):
		var screen: Vector2 = centers[i]
		var here := bed_point(screen)
		var side := bed_point(screen + Vector2(cell.x * 0.5, 0.0))
		var below := bed_point(screen + Vector2(0.0, cell.y * 0.5))
		# KLEINERE der beiden projizierten Zellkanten: quer sind die Zellen breit
		# und flach, nach der Breite skaliert liefen die Erdscheiben senkrecht
		# ineinander. Der Faktor 1,35 auf die Höhe hält die Scheiben trotzdem so
		# groß wie hochkant (dort greift immer die Breite).
		var span := minf(here.distance_to(side), here.distance_to(below) * 1.35)
		_spots[i].position = here
		_spots[i].scale = Vector3.ONE * (maxf(0.3, span) / CELL_REF)
	_place_gooby(size)


## Tierchen-Aufsteiger je Versteck (0 = versteckt, 1 = ganz draußen).
func sync(rises: Array, elapsed: float) -> void:
	for i in mini(_critters.size(), rises.size()):
		var rise := float(rises[i])
		var critter := _critters[i]
		critter.visible = rise > 0.001
		if not critter.visible:
			continue
		critter.position.y = -1.0 + rise * 1.35
		critter.rotation.y = sin(elapsed * 2.2 + i) * 0.4


## Requisiten-Wackler beim Tippen (Feedback am Versteck selbst).
func wobble(spot: int, amount: float) -> void:
	if spot < 0 or spot >= _props.size():
		return
	_props[spot].rotation.z = 0.0 if amount <= 0.0 else sin(amount * 42.0) * 0.5 * amount


## Gooby-Emotion setzen (nur bei Wechsel, sonst flackert der Blend).
func feel(emotion: String) -> void:
	if gooby == null or _emotion == emotion:
		return
	_emotion = emotion
	gooby.set_emotion(emotion)


## Gooby-Clip (Winken beim geräumten Beet).
func cheer(clip: String) -> void:
	if gooby != null:
		gooby.play_clip(clip)


## Blätterwirbel an einem Versteck.
func poof(spot: int, color: Color) -> void:
	if spot < 0 or spot >= _spots.size():
		return
	Puff.fire(_leaves, _spots[spot].position + Vector3(0.0, 0.7, 0.7), color)


## Bildschirmpunkt → Punkt auf dem Gartenhang (y + SLOPE·z = BASE).
func bed_point(screen: Vector2) -> Vector3:
	var origin := camera.project_ray_origin(screen)
	var dir := camera.project_ray_normal(screen)
	var denom := dir.y + SLOPE * dir.z
	if absf(denom) < 0.0005:
		return origin
	var t := (BASE - origin.y - SLOPE * origin.z) / denom
	return origin + dir * clampf(t, 0.5, 90.0)


# ── Aufbau ────────────────────────────────────────────────────────────────


## Der Hang selbst: eine ENDLICHE Fläche, die unten aus dem Bild läuft und
## oben am Rücken abbricht — darüber bleibt Himmel für die Baumkronen.
func _build_bank() -> void:
	var ang := atan(SLOPE)
	var top := Vector3(0.0, BASE - SLOPE * BED_TOP_Z, BED_TOP_Z)
	var down := Vector3(0.0, -sin(ang), cos(ang))
	var bank := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(70.0, BED_LEN)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.74, 0.42)
	mat.roughness = 1.0
	plane.material = mat
	bank.mesh = plane
	bank.rotation.x = ang
	bank.position = top + down * (BED_LEN * 0.5)
	add_child(bank)
	_mow_stripes(ang)
	_scatter("grass_large.glb", 110, 0.5, Vector2(-16.0, 16.0), Vector2(-3.6, 5.4), 0.7, 1.4)
	for flower in ["flower_redA.glb", "flower_yellowA.glb", "flower_purpleA.glb"]:
		_scatter(flower, 20, 0.42, Vector2(-14.0, 14.0), Vector2(-3.5, 5.0), 0.8, 1.4)
	_scatter("mushroom_red.glb", 9, 0.3, Vector2(-11.0, 11.0), Vector2(-3.2, 4.4), 0.9, 1.3)
	# KEINE großen Requisiten vor der letzten Rasterreihe: dort steht Gooby, und
	# die Nahebene vergrößert selbst einen 1-m-Busch auf halbe Bildbreite.
	_scatter("flower_redA.glb", 8, 0.4, Vector2(-6.0, 6.0), Vector2(3.4, 5.2), 0.9, 1.5)


## Mähstreifen: hellere Bahnen auf dem Hang. Ohne sie ist die Wiese eine
## einzige grüne Fläche und die Bühne wirkt wieder flach — ein MultiMesh, ein
## Draw-Call, und der Hang bekommt sofort Richtung und Maßstab.
func _mow_stripes(ang: float) -> void:
	var stripe := PlaneMesh.new()
	stripe.size = Vector2(1.45, BED_LEN)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.57, 0.79, 0.46)
	mat.roughness = 1.0
	stripe.material = mat
	var down := Vector3(0.0, -sin(ang), cos(ang))
	var lift := Vector3(0.0, cos(ang), sin(ang)) * 0.02
	var mid := Vector3(0.0, BASE - SLOPE * BED_TOP_Z, BED_TOP_Z) + down * (BED_LEN * 0.5) + lift
	var basis := Basis(Vector3.RIGHT, ang)
	var poses: Array = []
	for i in 12:
		poses.append(Transform3D(basis, mid + Vector3(-19.25 + i * 3.5, 0.0, 0.0)))
	add_child(Models.swarm([{"mesh": stripe, "xform": Transform3D.IDENTITY}], poses, 40.0))


## Massenrequisiten auf den Hang streuen (1 Draw-Call je Teilmesh).
func _scatter(
	file: String,
	count: int,
	size: float,
	span_x: Vector2,
	span_z: Vector2,
	scale_min: float,
	scale_max: float
) -> void:
	var parts := Models.parts(DIR + file, size, true)
	if parts.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(file)
	var poses: Array = []
	for _i in count:
		var z := rng.randf_range(span_z.x, span_z.y)
		var pos := Vector3(rng.randf_range(span_x.x, span_x.y), BASE - SLOPE * z - 0.12, z)
		var basis := Basis.IDENTITY.rotated(Vector3.UP, rng.randf() * TAU).scaled(
			Vector3.ONE * rng.randf_range(scale_min, scale_max)
		)
		poses.append(Transform3D(basis, pos))
	add_child(Models.swarm(parts, poses, 30.0))


## Über dem Hangrücken: Baumkronen, Zaunkrone und ein Vogel im Himmel. Die
## Stämme verschwinden hinter dem Rücken — genau wie an einem echten Hang.
func _build_skyline() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 33117
	# Ferne Hügelkette als Silhouette — gibt dem schmalen Himmelband Tiefe.
	for entry: Array in [[-16.0, 13.0, 9.0], [3.0, 17.0, 11.0], [21.0, 12.0, 8.0]]:
		var hill := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.0
		cone.bottom_radius = float(entry[1])
		cone.height = float(entry[2])
		cone.radial_segments = 7
		var hill_mat := StandardMaterial3D.new()
		hill_mat.albedo_color = Color(0.62, 0.8, 0.72)
		hill_mat.roughness = 1.0
		cone.material = hill_mat
		hill.mesh = cone
		hill.position = Vector3(float(entry[0]), -1.5, -34.0)
		add_child(hill)
	for i in 11:
		var file := "tree_default.glb" if i % 2 == 0 else "tree_fat.glb"
		var tree := Models.node_by_height(DIR + file, rng.randf_range(8.0, 11.0), true)
		tree.position = Vector3(-21.0 + i * 4.2 + rng.randf_range(-1.1, 1.1), 0.0, -9.4)
		tree.rotation.y = rng.randf() * TAU
		add_child(tree)
	var fence := Models.parts(DIR + "fence_simple.glb", 2.6, true)
	if not fence.is_empty():
		var poses: Array = []
		for i in 22:
			poses.append(Transform3D(Basis.IDENTITY, Vector3(-26.0 + i * 2.6, 3.1, -7.2)))
		add_child(Models.swarm(fence, poses, 30.0))
	var fountain := Models.node_by_height(DIR + "tinytreats/fountain.gltf", 2.4, true)
	fountain.position = Vector3(-7.6, 3.1, -6.4)
	add_child(fountain)
	var bench := Models.node_by_height(DIR + "tinytreats/bench.gltf", 1.4, true)
	bench.position = Vector3(6.8, 3.1, -6.2)
	bench.rotation_degrees = Vector3(0.0, -18.0, 0.0)
	add_child(bench)
	var lantern := Models.node_by_height(DIR + "tinytreats/street_lantern.gltf", 4.6, true)
	lantern.position = Vector3(11.4, 3.1, -6.6)
	add_child(lantern)
	var bird := Models.node_by_height(DIR + "tinytreats/bird.gltf", 0.6, true)
	bird.position = Vector3(-9.4, 7.4, -6.0)
	bird.rotation_degrees = Vector3(0.0, 138.0, 0.0)
	add_child(bird)


func _build_gooby() -> void:
	gooby = GoobyRig.new()
	gooby.name = "GoobySeeker"
	gooby.rotation_degrees = Vector3(0.0, 24.0, 0.0)
	add_child(gooby)
	# Kontaktschatten von Hand (Sonnenschatten kosten hier zu viele Draw-Calls).
	var shade := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.52
	disc.bottom_radius = 0.52
	disc.height = 0.02
	disc.radial_segments = 16
	var shade_mat := StandardMaterial3D.new()
	shade_mat.albedo_color = Color(0.16, 0.3, 0.14, 0.3)
	shade_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shade_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material = shade_mat
	shade.mesh = disc
	shade.rotation.x = atan(SLOPE)
	_gooby_shade = shade
	add_child(shade)
	gooby.set_emotion(_emotion)
	gooby.play_clip("idle_lookaround")


## Gooby auf einen festen BILDSCHIRM-Anker stellen: so steht der Sucher in
## beiden Orientierungen unten links im Bild, unter der letzten Rasterreihe.
func _place_gooby(size: Vector2) -> void:
	if gooby == null or size.y <= 1.0:
		return
	var anchor := Vector2(size.x * GOOBY_ANCHOR.x, size.y * GOOBY_ANCHOR.y)
	var feet := bed_point(anchor)
	# Wie viele Pixel misst ein Meter an dieser Stelle? Damit wird Gooby in
	# jeder Orientierung genau GOOBY_HEIGHT der Bildhöhe hoch.
	var per_metre := absf(anchor.y - camera.unproject_position(feet + Vector3.UP).y)
	var factor := size.y * GOOBY_HEIGHT / maxf(1.0, per_metre) / RIG_HEIGHT
	gooby.position = feet
	gooby.scale = Vector3.ONE * factor
	if _gooby_shade != null:
		_gooby_shade.position = feet + Vector3(0.0, 0.05, 0.05)
		_gooby_shade.scale = Vector3.ONE * factor


func _build_spot(index: int) -> void:
	var holder := Node3D.new()
	add_child(holder)
	_spots.append(holder)
	holder.add_child(_make_bed())
	var critter := _make_critter(index)
	critter.visible = false
	holder.add_child(critter)
	_critters.append(critter)
	var prop := Node3D.new()
	prop.position = Vector3(0.0, -0.2, 0.0)
	holder.add_child(prop)
	_props.append(prop)
	var kinds: Array[String] = ["bush", "stump", "pot"]
	match kinds[index % kinds.size()]:
		"bush":
			prop.add_child(Models.node(DIR + "plant_bushLarge.glb", 1.7, true))
			for entry: Array in [[-0.62, 0.34], [0.58, 0.18], [0.02, 0.62]]:
				var flower := Models.node(DIR + "flower_yellowA.glb", 0.5, true)
				flower.position = Vector3(float(entry[0]), 0.1, float(entry[1]))
				prop.add_child(flower)
		"stump":
			prop.add_child(Models.node(DIR + "stump_round.glb", 1.4, true))
			var log_node := Models.node(DIR + "log.glb", 1.2, true)
			log_node.position = Vector3(0.66, 0.05, 0.42)
			log_node.rotation_degrees = Vector3(0.0, 28.0, 0.0)
			prop.add_child(log_node)
			var shroom := Models.node(DIR + "mushroom_red.glb", 0.4, true)
			shroom.position = Vector3(-0.64, 0.08, 0.4)
			prop.add_child(shroom)
		_:
			prop.add_child(Models.node(DIR + "pot_large.glb", 1.35, true))
			var small := Models.node(DIR + "pot_small.glb", 0.72, true)
			small.position = Vector3(0.7, 0.05, 0.38)
			prop.add_child(small)


## Erdscheibe unter jedem Versteck: markiert die Tippfläche im Grün. Sie liegt
## FLACH AUF DEM HANG, die Requisiten darauf stehen senkrecht.
func _make_bed() -> MeshInstance3D:
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.86
	mesh.bottom_radius = 0.86
	mesh.height = 0.12
	mesh.radial_segments = 18
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.53, 0.4, 0.29)
	mat.roughness = 1.0
	mesh.material = mat
	disc.mesh = mesh
	disc.rotation.x = atan(SLOPE)
	disc.position = Vector3(0.0, 0.05, 0.05)
	return disc


## Verstecktes Tierchen: kleine Pastellfigur, die hinter der Requisite aufsteigt.
func _make_critter(index: int) -> Node3D:
	const TINTS: Array[Color] = [
		Color(1.0, 0.66, 0.78),
		Color(0.5, 0.83, 0.76),
		Color(1.0, 0.85, 0.48),
		Color(0.73, 0.66, 1.0),
		Color(1.0, 0.69, 0.54),
	]
	var holder := Node3D.new()
	holder.position = Vector3(0.0, -1.0, 0.72)
	var fur := StandardMaterial3D.new()
	fur.albedo_color = TINTS[index % TINTS.size()]
	fur.roughness = 0.95
	var body := MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.46
	body_mesh.height = 0.8
	body_mesh.radial_segments = 12
	body_mesh.rings = 7
	body_mesh.material = fur
	body.mesh = body_mesh
	body.position = Vector3(0.0, 0.4, 0.0)
	holder.add_child(body)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.34
	head_mesh.height = 0.66
	head_mesh.radial_segments = 12
	head_mesh.rings = 7
	head_mesh.material = fur
	head.mesh = head_mesh
	head.position = Vector3(0.0, 0.98, 0.04)
	holder.add_child(head)
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.16, 0.12, 0.18)
	for side in [-1.0, 1.0]:
		var ear := MeshInstance3D.new()
		var ear_mesh := CapsuleMesh.new()
		ear_mesh.radius = 0.1
		ear_mesh.height = 0.7
		ear_mesh.radial_segments = 8
		ear_mesh.rings = 3
		ear_mesh.material = fur
		ear.mesh = ear_mesh
		ear.position = Vector3(side * 0.18, 1.4, -0.02)
		ear.rotation_degrees = Vector3(0.0, 0.0, side * 13.0)
		holder.add_child(ear)
		var eye := MeshInstance3D.new()
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.07
		eye_mesh.height = 0.14
		eye_mesh.radial_segments = 8
		eye_mesh.rings = 5
		eye_mesh.material = eye_mat
		eye.mesh = eye_mesh
		eye.position = Vector3(side * 0.14, 1.04, 0.31)
		holder.add_child(eye)
	return holder


func _build_effects() -> void:
	_leaves = (
		Puff
		. burst(
			DIR + "vfx/star_03.png",
			{
				"amount": 20,
				"lifetime": 0.85,
				"size": 0.5,
				"dir": Vector3.UP,
				"spread": 160.0,
				"speed": Vector2(1.8, 3.6),
				"gravity": Vector3(0.0, -3.4, 0.0),
				"color": Color(0.6, 0.9, 0.5, 1.0),
				"color_end": Color(0.9, 0.95, 0.6, 0.0),
				"add": false,
				"local": false,
			}
		)
	)
	add_child(_leaves)
