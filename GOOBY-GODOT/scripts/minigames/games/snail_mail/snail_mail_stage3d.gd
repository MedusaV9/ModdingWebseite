extends Node3D
## ECHTER 3D-GARTEN für die Schneckenpost (FB-4, MP-D-Tiefenpolitur):
## Häuschen, Bau, Briefkasten, Pfützen und Blumen stehen als 3D-Modelle auf
## einer gemähten Sommerwiese (Rasenstreifen!); dahinter staffeln sich Zaun,
## Hecke, zwei Baumreihen und weiche Hügelbuckel in den Nebel. WICHTIG: die
## Kamera schaut mit −44° aufs Feld — sichtbar ist hinter dem Feld nur ein
## schmales Band bis ~7 m hinter dem Zaun, alles dahinter liegt außerhalb
## des Bildes (deshalb KEINE Wolken/Fernhügel). Der Wiesenrand ums Spielfeld
## ist mit Grasbüscheln, Steinen und Büschen bewachsen, Blütenblätter treiben
## übers Feld. Die Postschnecke kriecht als 3D-Figur mit Briefumschlag den
## gemalten Weg ab und Gooby (echtes Rig, Umschlag in der Pfote) winkt am
## Briefkasten. ALLE Anker kommen als CANVAS-PIXEL aus der View
## (project()-Ausgabe) und werden per ground_point-Raycast auf den Boden
## gelegt — der gemalte Weg liegt EXAKT unter dem Finger, Eingabe und
## MECHANIK bleiben zahlengleich in snail_mail.gd/SnailMailLogic.

const Stage3D := preload("res://scripts/minigames/games/_3dc_stage/stage3d.gd")
const Actor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")
const Models := preload("res://scripts/minigames/games/_3dc_stage/models3d.gd")
const DIR := "res://assets/minigames/carrot_catch/"
const POND := "res://assets/minigames/fishing_pond/"

const MAX_PATH_DOTS := 320
const PETALS := 7
const WALL_CREAM := Color(0.96, 0.88, 0.74)
const ROOF_RED := Color(0.72, 0.36, 0.3)
const ROOF_TARGET := Color(0.98, 0.6, 0.28)

var stage: Node3D
var gooby: Node3D

var _houses: Array[Node3D] = []
var _puddles: Array[Node3D] = []
var _flowers: Array[Node3D] = []
var _post: Node3D
var _snail: Node3D
var _snail_body: Node3D
var _snail_zzz: Label3D
var _envelope: Node3D
var _target_ring: MeshInstance3D
var _target_arrow: MeshInstance3D
var _arrow_base_y := 0.0
var _start_ring: MeshInstance3D
var _field: MeshInstance3D
var _field_rim: MeshInstance3D
var _stripes: MultiMeshInstance3D
var _post_pad: MeshInstance3D
var _backdrop: Node3D
var _edge_props: Node3D
var _petals: MultiMeshInstance3D
var _petal_seeds: Array[Vector3] = []
var _field_center := Vector3.ZERO
var _field_half := Vector2(4.0, 3.0)
var _path_dots: MultiMeshInstance3D
var _splash_burst: GPUParticles3D
var _bloom_burst: GPUParticles3D
var _gold_burst: GPUParticles3D
## Dach-Materialien EINMAL bauen (das Ziel-Dach leuchtet sanft) — sonst
## entsteht bei jedem Levelwechsel ein frisches Material.
var _mat_roof_plain: StandardMaterial3D
var _mat_roof_target: StandardMaterial3D


func setup_stage() -> void:
	stage = Stage3D.new()
	add_child(stage)
	(
		stage
		. build(
			{
				# Goldener Sommernachmittag, NICHT überbelichtet (satte Wiese).
				# DRITTE Luma-Runde (gemessen): mit Sonne 0,78/Ambient 0,24 lag
				# die Wiese immer noch ~55 Luma über der Albedo — der Himmel
				# speist das Sky-Ambient kräftig mit. Sonne 0,68, Ambient 0,18
				# und ein gedeckterer Horizont holen das Grün zurück.
				"sky_top": Color(0.42, 0.66, 0.88),
				"sky_horizon": Color(0.88, 0.8, 0.6),
				"ground_horizon": Color(0.48, 0.63, 0.42),
				"ground_bottom": Color(0.32, 0.46, 0.27),
				"sun_dir": Vector3(-0.35, -0.8, -0.35),
				"sun_color": Color(1.0, 0.91, 0.74),
				"sun_energy": 0.68,
				"ambient": 0.18,
				"fill_energy": 0.14,
				"glow": 0.26,
				"glow_threshold": 0.86,
				"shadow_distance": 34.0,
				# Nebel ERST hinterm Feld (Kamera→Feldmitte ≈ 17 m) — sonst
				# wäscht er die ganze Wiese pastellblass.
				"fog": true,
				"fog_color": Color(0.66, 0.74, 0.56),
				"fog_from": 23.0,
				"fog_to": 46.0,
				"far": 120.0,
			}
		)
	)
	# Weiche Schatten: Häuser und Bäume stehen fühlbar AUF der Wiese.
	stage.sun.shadow_blur = 1.6
	stage.sun.shadow_opacity = 0.6
	stage.sun.light_angular_distance = 2.2
	add_child(Fx.ground(Vector2(90.0, 70.0), Color(0.29, 0.48, 0.24)))
	# Helle Garten-Insel unterm Spielfeld mit Beet-Einfassung
	# (layout_level passt beide an).
	_field_rim = MeshInstance3D.new()
	var rim_mesh := BoxMesh.new()
	rim_mesh.size = Vector3(1.0, 0.05, 1.0)
	rim_mesh.material = Fx.flat(Color(0.45, 0.34, 0.24))
	_field_rim.mesh = rim_mesh
	_field_rim.position.y = -0.03
	add_child(_field_rim)
	_field = MeshInstance3D.new()
	var field_mesh := BoxMesh.new()
	field_mesh.size = Vector3(1.0, 0.06, 1.0)
	field_mesh.material = Fx.flat(Color(0.4, 0.62, 0.3))
	_field.mesh = field_mesh
	_field.position.y = -0.02
	add_child(_field)
	_build_stripes()
	_build_backdrop()
	_build_pieces()
	_build_gooby()
	_build_fx()


## Tiefenstaffelung hinter dem Feld — ALLES im sichtbaren Band (0 bis −5 m
## hinter dem Zaun): Zaun, Hecke, weiche Hügelbuckel, zwei Baumreihen.
## layout_level schiebt das ganze Paket hinter die Feld-Hinterkante.
func _build_backdrop() -> void:
	_backdrop = Node3D.new()
	add_child(_backdrop)
	var fence_poses: Array = []
	for i in 14:
		fence_poses.append(Transform3D(Basis.IDENTITY, Vector3(-11.7 + float(i) * 1.8, 0.0, 0.0)))
	_backdrop.add_child(Models.swarm(Models.parts(DIR + "fence_simple.glb", 1.8), fence_poses))
	var hedge_poses: Array = []
	for i in 8:
		hedge_poses.append(
			Transform3D(
				Basis(Vector3.UP, float(i) * 0.9), Vector3(-10.2 + float(i) * 2.9, 0.0, -1.2)
			)
		)
	_backdrop.add_child(Models.swarm(Models.parts(POND + "plant_bushLarge.glb", 1.5), hedge_poses))
	_build_mounds()
	var tree_poses: Array = []
	for i in 6:
		tree_poses.append(
			Transform3D(
				Basis(Vector3.UP, float(i) * 1.3),
				Vector3(-13.0 + float(i) * 5.2, 0.0, -2.4 - 1.2 * float(i % 2))
			)
		)
	_backdrop.add_child(Models.swarm(Models.parts(DIR + "tree_default.glb", 3.4), tree_poses))
	var far_trees: Array = []
	for i in 7:
		far_trees.append(
			Transform3D(
				Basis(Vector3.UP, float(i) * 0.8),
				Vector3(-15.6 + float(i) * 5.0, 0.0, -4.2 - 0.8 * float(i % 3))
			)
		)
	_backdrop.add_child(
		_no_shadow(Models.swarm(Models.parts(POND + "tree_fat.glb", 4.6), far_trees))
	)


## Weiche Wiesenbuckel zwischen Hecke und Bäumen — niedrig genug, um im
## schmalen Sichtband hinterm Zaun als Silhouette zu lesen.
func _build_mounds() -> void:
	var mound := SphereMesh.new()
	mound.radius = 3.0
	mound.height = 6.0
	mound.radial_segments = 20
	mound.rings = 10
	mound.material = Fx.flat(Color(0.34, 0.52, 0.28))
	var poses: Array = [
		Transform3D(Basis.IDENTITY.scaled(Vector3(1.8, 0.32, 0.8)), Vector3(-8.0, -0.4, -3.0)),
		Transform3D(Basis.IDENTITY.scaled(Vector3(1.4, 0.4, 0.8)), Vector3(2.5, -0.5, -3.4)),
		Transform3D(Basis.IDENTITY.scaled(Vector3(1.6, 0.28, 0.8)), Vector3(11.0, -0.3, -2.8)),
	]
	var swarm := Models.swarm([{"mesh": mound, "xform": Transform3D.IDENTITY}], poses, 60.0)
	_backdrop.add_child(_no_shadow(swarm))


## Gemähte Rasenstreifen auf der Garten-Insel (EIN MultiMesh, 4 dunklere
## Bahnen) — layout_level spannt sie über die Feldbreite.
func _build_stripes() -> void:
	var band := BoxMesh.new()
	band.size = Vector3(1.0, 0.004, 1.0)
	band.material = Fx.flat(Color(0.35, 0.55, 0.26))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = band
	mm.instance_count = 4
	_stripes = MultiMeshInstance3D.new()
	_stripes.multimesh = mm
	_stripes.extra_cull_margin = 20.0
	_stripes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_stripes)


static func _no_shadow(node: Node) -> Node:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_no_shadow(child)
	return node


func _build_pieces() -> void:
	_mat_roof_plain = Fx.flat(ROOF_RED)
	_mat_roof_target = Fx.glow(ROOF_TARGET, 0.4)
	_post = _spawn_post()
	_post.scale = Vector3.ONE * 1.45
	add_child(_post)
	# Erd-Fleck unterm Briefkasten — die Poststation wirkt festgetreten.
	_post_pad = MeshInstance3D.new()
	var pad_mesh := CylinderMesh.new()
	pad_mesh.top_radius = 0.55
	pad_mesh.bottom_radius = 0.55
	pad_mesh.height = 0.015
	pad_mesh.radial_segments = 20
	pad_mesh.material = Fx.flat(Color(0.56, 0.45, 0.31))
	_post_pad.mesh = pad_mesh
	_post_pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_post_pad)
	_snail = _spawn_snail()
	add_child(_snail)
	_target_ring = Fx.ring(0.62, 0.075, Color(1.0, 0.86, 0.32))
	add_child(_target_ring)
	_start_ring = Fx.ring(0.5, 0.05, Color(1.0, 0.98, 0.8))
	add_child(_start_ring)
	_target_arrow = MeshInstance3D.new()
	var arrow_mesh := CylinderMesh.new()
	arrow_mesh.top_radius = 0.0
	arrow_mesh.bottom_radius = 0.26
	arrow_mesh.height = 0.5
	arrow_mesh.radial_segments = 10
	arrow_mesh.material = Fx.glow(Color(1.0, 0.82, 0.3), 0.85)
	_target_arrow.mesh = arrow_mesh
	_target_arrow.rotation.z = PI
	_target_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_target_arrow)
	# Wegpunkte als EIN MultiMesh (bis zu MAX_PATH_DOTS flache Kugeln).
	_path_dots = MultiMeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.15
	dot.height = 0.14
	dot.material = Fx.glow(Color(1.0, 0.8, 0.4), 0.75)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = dot
	mm.instance_count = MAX_PATH_DOTS
	mm.visible_instance_count = 0
	_path_dots.multimesh = mm
	_path_dots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_path_dots)
	# Wiesenrand-Deko (Grasbüschel, Steine, Büsche) — layout_level legt sie
	# je Level neu um das Feld.
	_edge_props = Node3D.new()
	add_child(_edge_props)
	_build_petals()


## Treibende Blütenblätter überm Feld (EIN MultiMesh, sync bewegt sie).
func _build_petals() -> void:
	var petal := SphereMesh.new()
	petal.radius = 0.06
	petal.height = 0.04
	petal.radial_segments = 8
	petal.rings = 4
	petal.material = Fx.glow(Color(1.0, 0.8, 0.88), 0.35)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = petal
	mm.instance_count = PETALS
	_petals = MultiMeshInstance3D.new()
	_petals.multimesh = mm
	_petals.extra_cull_margin = 30.0
	_petals.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_petals)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for i in PETALS:
		# x: Phase 0..1 der Querung, y: Bahnhöhe, z: Tiefen-Anteil −1..1.
		_petal_seeds.append(
			Vector3(rng.randf(), rng.randf_range(0.5, 1.6), rng.randf_range(-0.9, 0.9))
		)


func _build_gooby() -> void:
	gooby = Actor.new()
	add_child(gooby)
	gooby.mount(1.25)
	gooby.base_emotion = "happy"
	# Der Postbote hält seinen nächsten Brief bereit.
	gooby.hold(
		_mail_prop(), "arm.R", Transform3D(Basis(Vector3.RIGHT, -0.5), Vector3(0.0, -0.06, 0.05))
	)


## Briefumschlag für Goobys Pfote (weißes Kuvert + rotes Siegel).
func _mail_prop() -> Node3D:
	var holder := Node3D.new()
	var paper := MeshInstance3D.new()
	var paper_mesh := BoxMesh.new()
	paper_mesh.size = Vector3(0.26, 0.18, 0.025)
	paper_mesh.material = Fx.flat(Color(1.0, 0.98, 0.9))
	paper.mesh = paper_mesh
	holder.add_child(paper)
	var seal := MeshInstance3D.new()
	var seal_mesh := SphereMesh.new()
	seal_mesh.radius = 0.03
	seal_mesh.height = 0.06
	seal_mesh.radial_segments = 8
	seal_mesh.rings = 5
	seal_mesh.material = Fx.glow(Color(0.93, 0.36, 0.48), 0.4)
	seal.mesh = seal_mesh
	seal.position.z = 0.02
	holder.add_child(seal)
	return holder


func _build_fx() -> void:
	_splash_burst = (
		Fx
		. particles(
			{
				"color": Color(0.55, 0.75, 0.95, 0.95),
				"amount": 18,
				"lifetime": 0.55,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(1.0, 2.4),
				"spread": 70.0,
				"size": Vector2(0.05, 0.12),
			}
		)
	)
	add_child(_splash_burst)
	_bloom_burst = (
		Fx
		. particles(
			{
				"color": Color(1.0, 0.72, 0.85, 0.95),
				"amount": 12,
				"lifetime": 0.5,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(0.8, 2.0),
				"spread": 80.0,
				"size": Vector2(0.05, 0.11),
				"additive": true,
			}
		)
	)
	add_child(_bloom_burst)
	# Goldene Funken NUR für die trockene Zustellung — der große Moment.
	_gold_burst = (
		Fx
		. particles(
			{
				"color": Color(1.0, 0.87, 0.45, 0.95),
				"amount": 22,
				"lifetime": 0.7,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(1.2, 2.8),
				"spread": 75.0,
				"gravity": Vector3(0.0, -2.6, 0.0),
				"size": Vector2(0.06, 0.13),
				"additive": true,
			}
		)
	)
	add_child(_gold_burst)


## Kamera: schräg von oben auf den Garten — die Raycast-Anker halten alle
## Spielfeld-Punkte deckungsgleich mit der 2D-Eingabe.
func frame(vp: Vector2) -> void:
	stage.apply_size(vp)
	stage.camera.position = Vector3(0.0, 10.5, 8.0)
	stage.camera.rotation_degrees = Vector3(-44.0, 0.0, 0.0)
	stage.set_half_height(4.9, 10.0)


## Level-Anker (CANVAS-PIXEL) auf den Boden raycasten. Nach jedem apply_view
## UND jedem Levelwechsel aufrufen.
## houses: [{px, door_px, kind, target}], puddles: [{px, edge_px}],
## flowers: [px], post_px, field: Rect2.
func layout_level(
	houses: Array, puddles: Array, flowers: Array, post_px: Vector2, field: Rect2
) -> void:
	while _houses.size() < houses.size():
		var house := _spawn_house()
		add_child(house)
		_houses.append(house)
	for i in _houses.size():
		var node := _houses[i]
		if i >= houses.size():
			node.visible = false
			continue
		var info: Dictionary = houses[i]
		var at := _ground(info["px"])
		var edge := _ground(Vector2(info["px"]) + Vector2(34.0, 0.0))
		var s := clampf(at.distance_to(edge) * 2.2, 0.9, 3.4)
		node.visible = true
		node.position = at
		node.scale = Vector3.ONE * s
		var burrow := str(info["kind"]) == "burrow"
		(node.get_node("Haus") as Node3D).visible = not burrow
		(node.get_node("Bau") as Node3D).visible = burrow
		var roof := node.get_node("Haus/Dach") as MeshInstance3D
		roof.set_surface_override_material(
			0, _mat_roof_target if bool(info["target"]) else _mat_roof_plain
		)
		if bool(info["target"]):
			var door := _ground(info["door_px"])
			_target_ring.position = door + Vector3(0.0, 0.05, 0.0)
			_arrow_base_y = at.y + s * 1.35
			_target_arrow.position = Vector3(at.x, _arrow_base_y, at.z)
	while _puddles.size() < puddles.size():
		var puddle := _spawn_puddle()
		add_child(puddle)
		_puddles.append(puddle)
	for i in _puddles.size():
		var node := _puddles[i]
		if i >= puddles.size():
			node.visible = false
			continue
		var info: Dictionary = puddles[i]
		var at := _ground(info["px"])
		var rim := _ground(info["edge_px"])
		node.visible = true
		node.position = at + Vector3(0.0, 0.015, 0.0)
		node.scale = Vector3.ONE * maxf(0.2, at.distance_to(rim))
	while _flowers.size() < flowers.size():
		var flower := Models.node(
			DIR + ("flower_redA.glb" if _flowers.size() % 2 == 0 else "flower_yellowA.glb"), 0.55
		)
		add_child(flower)
		_flowers.append(flower)
	for i in _flowers.size():
		var node := _flowers[i]
		if i >= flowers.size():
			node.visible = false
			continue
		node.visible = true
		node.position = _ground(flowers[i])
	var post_at := _ground(post_px)
	# Briefkasten LEICHT versetzt, damit die Schnecke am Start sichtbar bleibt.
	_post.position = post_at + Vector3(0.55, 0.0, -0.35)
	_post_pad.position = post_at + Vector3(0.3, 0.02, -0.2)
	_start_ring.position = post_at + Vector3(0.0, 0.05, 0.0)
	gooby.position = post_at + Vector3(-1.1, 0.0, 0.1)
	gooby.rotation.y = 0.4
	# Garten-Insel unter das Feld legen (Trapez → Box mit Mittelmaßen).
	var tl := _ground(field.position)
	var br := _ground(field.end)
	var tr := _ground(Vector2(field.end.x, field.position.y))
	_field.position = Vector3((tl.x + br.x) * 0.5, -0.02, (tl.z + br.z) * 0.5)
	_field.scale = Vector3(maxf(br.x - tl.x, tr.x - tl.x) + 1.0, 1.0, absf(br.z - tl.z) + 1.0)
	_field_rim.position = Vector3(_field.position.x, -0.03, _field.position.z)
	_field_rim.scale = _field.scale + Vector3(0.9, 0.0, 0.9)
	_field_center = _field.position
	_field_half = Vector2(_field.scale.x * 0.5, _field.scale.z * 0.5)
	# Rasenstreifen über die Insel spannen (Bahnen 1/3/5/7 von 8 dunkler).
	var band_w := _field.scale.x / 8.0
	for i in 4:
		var bx := _field.position.x - _field_half.x + band_w * (float(i) * 2.0 + 1.5)
		_stripes.multimesh.set_instance_transform(
			i,
			Transform3D(
				Basis.IDENTITY.scaled(Vector3(band_w, 1.0, _field.scale.z)),
				Vector3(bx, 0.014, _field.position.z)
			)
		)
	# Kulisse hinter die Feld-Hinterkante schieben (beide Orientierungen).
	var back_z := minf(tl.z, br.z)
	_backdrop.position = Vector3(_field.position.x, 0.0, back_z - 2.6)
	_dress_edges()


## Wiesenrand je Level neu bewachsen: Grasbüschel, Steine, Büsche und ein
## Pilz säumen die Garten-Insel — die leere Rasenfläche bekommt Bodendetail.
func _dress_edges() -> void:
	for child in _edge_props.get_children():
		child.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.seed = 97
	var cx := _field_center.x
	var cz := _field_center.z
	var hx := _field_half.x + 0.55
	var hz := _field_half.y + 0.5
	var grass_poses: Array = []
	for i in 12:
		var t := float(i) / 11.0
		var side := i % 2 == 0
		grass_poses.append(
			Transform3D(
				Basis(Vector3.UP, rng.randf_range(0.0, TAU)),
				Vector3(
					cx + (-hx if side else hx) + rng.randf_range(-0.3, 0.3),
					0.0,
					cz + lerpf(-hz, hz, t) + rng.randf_range(-0.25, 0.25)
				)
			)
		)
	for i in 5:
		grass_poses.append(
			Transform3D(
				Basis(Vector3.UP, rng.randf_range(0.0, TAU)),
				Vector3(
					cx + lerpf(-hx, hx, float(i) / 4.0) + rng.randf_range(-0.3, 0.3),
					0.0,
					cz + hz + rng.randf_range(0.1, 0.5)
				)
			)
		)
	_edge_props.add_child(Models.swarm(Models.parts(POND + "grass_large.glb", 0.5), grass_poses))
	var rock_poses: Array = [
		Transform3D(Basis(Vector3.UP, 0.7), Vector3(cx - hx, 0.0, cz - hz * 0.7)),
		Transform3D(Basis(Vector3.UP, 2.4), Vector3(cx + hx, 0.0, cz + hz * 0.5)),
		Transform3D(Basis(Vector3.UP, 4.0), Vector3(cx + hx * 0.7, 0.0, cz + hz)),
	]
	_edge_props.add_child(Models.swarm(Models.parts(POND + "rock_smallA.glb", 0.36), rock_poses))
	var bush_poses: Array = [
		Transform3D(Basis(Vector3.UP, 0.4), Vector3(cx - hx - 0.4, 0.0, cz + hz * 0.85)),
		Transform3D(Basis(Vector3.UP, 1.9), Vector3(cx + hx + 0.4, 0.0, cz - hz * 0.6)),
	]
	_edge_props.add_child(Models.swarm(Models.parts(POND + "plant_bushLarge.glb", 1.0), bush_poses))
	var shroom := Models.node(POND + "mushroom_red.glb", 0.3)
	shroom.position = Vector3(cx - hx - 0.2, 0.0, cz - hz * 0.2)
	_edge_props.add_child(shroom)
	_dress_clover(rng, cx, cz)


## Klee-Inseln AUF dem Feld (EIN MultiMesh, flache dunklere Scheiben) — die
## Rasenfläche liest sich als gewachsene Wiese statt als grüne Platte.
func _dress_clover(rng: RandomNumberGenerator, cx: float, cz: float) -> void:
	var disc := SphereMesh.new()
	disc.radius = 0.22
	disc.height = 0.03
	disc.radial_segments = 10
	disc.rings = 4
	disc.material = Fx.flat(Color(0.3, 0.49, 0.22))
	var poses: Array = []
	for i in 9:
		poses.append(
			Transform3D(
				Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(
					Vector3.ONE * rng.randf_range(0.7, 1.5)
				),
				Vector3(
					cx + rng.randf_range(-_field_half.x * 0.85, _field_half.x * 0.85),
					0.012,
					cz + rng.randf_range(-_field_half.y * 0.85, _field_half.y * 0.85)
				)
			)
		)
	var swarm := Models.swarm([{"mesh": disc, "xform": Transform3D.IDENTITY}], poses, 30.0)
	_edge_props.add_child(_no_shadow(swarm))


## Jeden Frame: Schnecke, Weg, Ringe und Umschlag stellen.
## path_pts = CANVAS-PIXEL des (Vorschau-)Wegs, snail_px + angle aus der Logic.
func sync(
	snail_px: Vector2,
	snail_angle: float,
	phase: String,
	path_pts: Array[Vector2],
	flower_gone: Array[bool],
	pulse: float,
	delta: float
) -> void:
	stage.tick(delta)
	gooby.tick(delta)
	gooby.rotation.z = sin(pulse * 2.2) * 0.04
	var at := _ground(snail_px)
	var hidden := phase == "retreat"
	_snail.position = at
	_snail.rotation.y = snail_angle
	_snail_body.visible = not hidden
	_snail_zzz.visible = hidden
	_envelope.visible = phase != "beat"
	_snail.scale = Vector3.ONE * (1.25 + 0.06 * sin(pulse * 5.0))
	_start_ring.visible = phase == "draw"
	_start_ring.scale = Vector3.ONE * (1.0 + 0.12 * sin(pulse * 3.0))
	_target_ring.scale = Vector3.ONE * (1.0 + 0.1 * sin(pulse * 3.2))
	_target_arrow.position.y = _arrow_base_y + 0.12 * sin(pulse * 4.0)
	for i in _flowers.size():
		if i < flower_gone.size() and flower_gone[i]:
			_flowers[i].visible = false
	# Wegpunkte auf den Boden raycasten — deckungsgleich mit dem Finger.
	var mm := _path_dots.multimesh
	var count := mini(path_pts.size(), MAX_PATH_DOTS)
	mm.visible_instance_count = count
	for i in count:
		mm.set_instance_transform(
			i, Transform3D(Basis.IDENTITY, _ground(path_pts[i]) + Vector3(0.0, 0.06, 0.0))
		)
	_drift_petals(pulse)


## Blütenblätter treiben langsam quer übers Feld und wippen dabei.
func _drift_petals(pulse: float) -> void:
	var mm := _petals.multimesh
	for i in PETALS:
		var sd := _petal_seeds[i]
		var t := fposmod(sd.x + pulse * 0.03, 1.0)
		var x := lerpf(
			_field_center.x - _field_half.x - 1.2, _field_center.x + _field_half.x + 1.2, t
		)
		var y := sd.y + 0.22 * sin(pulse * 1.6 + sd.z * 7.0)
		var z := _field_center.z + sd.z * _field_half.y
		var basis := Basis(Vector3.UP, pulse * 1.8 + sd.z * 5.0)
		mm.set_instance_transform(i, Transform3D(basis, Vector3(x, y, z)))


func splash_fx(snail_px: Vector2) -> void:
	Fx.burst(_splash_burst, _ground(snail_px) + Vector3(0.0, 0.2, 0.0))
	gooby.emote("scared", 1.2)


func flower_fx(flower_px: Vector2) -> void:
	Fx.burst(_bloom_burst, _ground(flower_px) + Vector3(0.0, 0.25, 0.0))
	gooby.emote("happy", 0.6)


func deliver_fx(door_px: Vector2, dry: bool) -> void:
	var at := _ground(door_px)
	Fx.burst(_bloom_burst, at + Vector3(0.0, 0.3, 0.0))
	if dry:
		Fx.burst(_gold_burst, at + Vector3(0.0, 0.5, 0.0))
		gooby.emote("ecstatic", 1.4)
		gooby.play_for("celebrate", 1.0)
		gooby.hop(0.45, 0.28)
		stage.pulse_glow(1.0)
	else:
		gooby.emote("happy", 1.0)


func _ground(px: Vector2) -> Vector3:
	var at: Vector3 = stage.ground_point(px)
	return at


func _spawn_house() -> Node3D:
	var root := Node3D.new()
	var house := Node3D.new()
	house.name = "Haus"
	root.add_child(house)
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.9, 0.6, 0.7)
	body_mesh.material = Fx.flat(WALL_CREAM)
	body.mesh = body_mesh
	body.position.y = 0.3
	house.add_child(body)
	var roof := MeshInstance3D.new()
	var roof_mesh := PrismMesh.new()
	roof_mesh.size = Vector3(1.1, 0.45, 0.9)
	roof_mesh.material = Fx.flat(ROOF_RED)
	roof.mesh = roof_mesh
	roof.name = "Dach"
	roof.position.y = 0.82
	house.add_child(roof)
	var door := MeshInstance3D.new()
	var door_mesh := BoxMesh.new()
	door_mesh.size = Vector3(0.22, 0.34, 0.05)
	door_mesh.material = Fx.flat(Color(0.6, 0.4, 0.3))
	door.mesh = door_mesh
	door.position = Vector3(0.0, 0.17, 0.36)
	house.add_child(door)
	var win_mesh := BoxMesh.new()
	win_mesh.size = Vector3(0.18, 0.16, 0.05)
	win_mesh.material = Fx.glow(Color(0.63, 0.83, 0.94), 0.25)
	for side: float in [-0.28, 0.28]:
		var win := MeshInstance3D.new()
		win.mesh = win_mesh
		win.position = Vector3(side, 0.4, 0.36)
		win.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		house.add_child(win)
	var burrow := Node3D.new()
	burrow.name = "Bau"
	burrow.visible = false
	root.add_child(burrow)
	var dome := MeshInstance3D.new()
	var dome_mesh := SphereMesh.new()
	dome_mesh.radius = 0.5
	dome_mesh.height = 1.0
	dome_mesh.material = Fx.flat(Color(0.52, 0.4, 0.3))
	dome.mesh = dome_mesh
	dome.scale = Vector3(1.0, 0.55, 1.0)
	burrow.add_child(dome)
	var hole := MeshInstance3D.new()
	var hole_mesh := CylinderMesh.new()
	hole_mesh.top_radius = 0.2
	hole_mesh.bottom_radius = 0.2
	hole_mesh.height = 0.1
	hole_mesh.material = Fx.flat(Color(0.2, 0.14, 0.12))
	hole.mesh = hole_mesh
	hole.rotation.x = PI * 0.42
	hole.position = Vector3(0.0, 0.16, 0.44)
	burrow.add_child(hole)
	return root


func _spawn_puddle() -> Node3D:
	var root := Node3D.new()
	var water := MeshInstance3D.new()
	var water_mesh := CylinderMesh.new()
	water_mesh.top_radius = 1.0
	water_mesh.bottom_radius = 1.0
	water_mesh.height = 0.02
	water_mesh.radial_segments = 22
	water_mesh.material = Fx.glass(Color(0.3, 0.53, 0.78, 0.9), true)
	water.mesh = water_mesh
	water.scale = Vector3(1.0, 1.0, 0.76)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(water)
	var shine := MeshInstance3D.new()
	var shine_mesh := TorusMesh.new()
	shine_mesh.inner_radius = 0.3
	shine_mesh.outer_radius = 0.38
	shine_mesh.material = Fx.glow(Color(0.9, 0.96, 1.0), 0.4)
	shine.mesh = shine_mesh
	shine.position = Vector3(-0.24, 0.02, -0.16)
	shine.scale = Vector3(0.5, 0.3, 0.4)
	shine.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shine)
	return root


func _spawn_post() -> Node3D:
	var root := Node3D.new()
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.04
	pole_mesh.bottom_radius = 0.05
	pole_mesh.height = 0.6
	pole_mesh.material = Fx.flat(Color(0.55, 0.4, 0.28))
	pole.mesh = pole_mesh
	pole.position.y = 0.3
	root.add_child(pole)
	var box := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.34, 0.26, 0.28)
	box_mesh.material = Fx.flat(Color(0.36, 0.6, 0.86))
	box.mesh = box_mesh
	box.position.y = 0.72
	root.add_child(box)
	var slot := MeshInstance3D.new()
	var slot_mesh := BoxMesh.new()
	slot_mesh.size = Vector3(0.2, 0.03, 0.02)
	slot_mesh.material = Fx.flat(Color(0.95, 0.97, 1.0))
	slot.mesh = slot_mesh
	slot.position = Vector3(0.0, 0.76, 0.15)
	slot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(slot)
	return root


## Postschnecke: Fuß + Augenstiele (Körper), Spiralhaus, Umschlag obendrauf.
## Bei Drehung 0 schaut sie Richtung +X (rotation.y = Logik-Winkel).
func _spawn_snail() -> Node3D:
	var root := Node3D.new()
	_snail_body = Node3D.new()
	root.add_child(_snail_body)
	var skin := Fx.flat(Color(0.98, 0.86, 0.72))
	var foot := MeshInstance3D.new()
	var foot_mesh := CapsuleMesh.new()
	foot_mesh.radius = 0.14
	foot_mesh.height = 0.62
	foot_mesh.material = skin
	foot.mesh = foot_mesh
	foot.rotation.z = PI * 0.5
	foot.position = Vector3(0.08, 0.12, 0.0)
	_snail_body.add_child(foot)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.12
	head_mesh.height = 0.24
	head_mesh.material = skin
	head.mesh = head_mesh
	head.position = Vector3(0.34, 0.2, 0.0)
	_snail_body.add_child(head)
	var eye_stalk := CylinderMesh.new()
	eye_stalk.top_radius = 0.02
	eye_stalk.bottom_radius = 0.02
	eye_stalk.height = 0.18
	eye_stalk.material = skin
	var eye_ball := SphereMesh.new()
	eye_ball.radius = 0.04
	eye_ball.height = 0.08
	eye_ball.material = Fx.flat(Color(0.25, 0.18, 0.16))
	for side: float in [-1.0, 1.0]:
		var stalk := MeshInstance3D.new()
		stalk.mesh = eye_stalk
		stalk.position = Vector3(0.4, 0.34, side * 0.06)
		stalk.rotation.x = side * 0.3
		_snail_body.add_child(stalk)
		var eye := MeshInstance3D.new()
		eye.mesh = eye_ball
		eye.position = Vector3(0.42, 0.44, side * 0.09)
		_snail_body.add_child(eye)
	var shell := MeshInstance3D.new()
	var shell_mesh := SphereMesh.new()
	shell_mesh.radius = 0.24
	shell_mesh.height = 0.48
	shell_mesh.material = Fx.flat(Color(0.78, 0.5, 0.26))
	shell.mesh = shell_mesh
	shell.position = Vector3(-0.1, 0.3, 0.0)
	root.add_child(shell)
	# Spiral-Ring FLACH auf die Haus-Flanke gelegt (bei 0,13 ragte er wie
	# ein Heiligenschein aus der Schale heraus).
	var spiral := MeshInstance3D.new()
	var spiral_mesh := TorusMesh.new()
	spiral_mesh.inner_radius = 0.06
	spiral_mesh.outer_radius = 0.13
	spiral_mesh.material = Fx.flat(Color(0.6, 0.38, 0.2))
	spiral.mesh = spiral_mesh
	spiral.rotation.x = PI * 0.5
	spiral.position = Vector3(-0.1, 0.3, 0.21)
	spiral.scale = Vector3(1.0, 0.5, 1.0)
	spiral.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(spiral)
	_envelope = Node3D.new()
	root.add_child(_envelope)
	var paper := MeshInstance3D.new()
	var paper_mesh := BoxMesh.new()
	paper_mesh.size = Vector3(0.3, 0.2, 0.03)
	paper_mesh.material = Fx.flat(Color(1.0, 0.98, 0.9))
	paper.mesh = paper_mesh
	paper.position = Vector3(-0.1, 0.64, 0.0)
	paper.rotation.y = PI * 0.5
	_envelope.add_child(paper)
	var seal := MeshInstance3D.new()
	var seal_mesh := SphereMesh.new()
	seal_mesh.radius = 0.035
	seal_mesh.height = 0.07
	seal_mesh.material = Fx.glow(Color(0.93, 0.36, 0.48), 0.4)
	seal.mesh = seal_mesh
	seal.position = Vector3(-0.1, 0.64, 0.0)
	_envelope.add_child(seal)
	_snail_zzz = Label3D.new()
	_snail_zzz.text = "zZ"
	_snail_zzz.font_size = 120
	_snail_zzz.pixel_size = 0.004
	_snail_zzz.modulate = Color(0.4, 0.45, 0.6, 0.9)
	_snail_zzz.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_snail_zzz.no_depth_test = true
	_snail_zzz.position = Vector3(0.0, 0.75, 0.0)
	_snail_zzz.visible = false
	root.add_child(_snail_zzz)
	return root
