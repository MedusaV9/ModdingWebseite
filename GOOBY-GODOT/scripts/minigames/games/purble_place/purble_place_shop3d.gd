extends RefCounted
## Kulisse der 3D-Backstube (Agent 3D-C): Wand mit Pastellstreifen, Kachel-
## spiegel, Dielenboden, Wandregal mit echtem Kenney-Gebäck, Hängelampen,
## Wimpelkette und Ladenschild. Alles steht STILL — es wird einmal an die Bühne
## gehängt und danach nie wieder angefasst.
##
## Eigene Datei, damit `purble_place_stage3d.gd` unter der 1000-Zeilen-Grenze
## bleibt. Massenware (Streifen, Kacheln, Wimpel) läuft über MultiMesh, das
## ganze Paket kostet gut zwei Dutzend Draw-Calls.

const Models := preload("res://scripts/minigames/games/_3dc_stage/models3d.gd")
const DIR := "res://assets/minigames/purble_place/"

## Rückwand, Kachelspiegel und Boden (Weltmeter, y = 0 ist die Bandoberkante).
const WALL_Z := -4.2
const COUNTER_Z := -2.05
const FLOOR_Y := -0.55


static func build(stage: Node3D) -> void:
	var wall := MeshInstance3D.new()
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(20.0, 9.0, 0.3)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.99, 0.92, 0.84)
	mat.roughness = 1.0
	wall_mesh.material = mat
	wall.mesh = wall_mesh
	wall.position = Vector3(3.0, 3.4, WALL_Z)
	stage.add_child(wall)

	# Senkrechte Pastellstreifen (Web-Tapete) als EIN MultiMesh.
	var stripe := BoxMesh.new()
	stripe.size = Vector3(0.62, 9.0, 0.06)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.97, 0.85, 0.76)
	smat.roughness = 1.0
	stripe.material = smat
	var poses: Array = []
	for i in 16:
		poses.append(Transform3D(Basis.IDENTITY, Vector3(-4.6 + i * 1.24, 3.4, WALL_Z + 0.18)))
	stage.add_child(Models.swarm([{"mesh": stripe, "xform": Transform3D.IDENTITY}], poses, 24.0))

	_tiles(stage)

	var floor_node := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(22.0, 12.0)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.83, 0.71, 0.61)
	fmat.roughness = 1.0
	plane.material = fmat
	floor_node.mesh = plane
	floor_node.position = Vector3(3.0, FLOOR_Y, -1.4)
	stage.add_child(floor_node)
	_backdrop(stage)


## Kachelsockel direkt hinter dem Band — bewusst NIEDRIG (0,7 m): eine höhere
## Wand würde die Gäste an der Theke dahinter komplett verschlucken.
static func _tiles(stage: Node3D) -> void:
	var tile := BoxMesh.new()
	tile.size = Vector3(0.28, 0.28, 0.05)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.94, 0.87, 0.83)
	mat.roughness = 0.55
	tile.material = mat
	var poses: Array = []
	for row in 3:
		for col in 32:
			poses.append(
				Transform3D(
					Basis.IDENTITY, Vector3(-1.35 + col * 0.3, -0.42 + row * 0.3, COUNTER_Z + 0.34)
				)
			)
	stage.add_child(Models.swarm([{"mesh": tile, "xform": Transform3D.IDENTITY}], poses, 24.0))


## Alles über der Schiene: Wandregal mit echtem Gebäck, Hängelampen, Wimpel,
## Ladenschild. Hochkant füllt das die obere Bildhälfte, quer liegt es außerhalb.
static func _backdrop(stage: Node3D) -> void:
	var shelf := MeshInstance3D.new()
	var board := BoxMesh.new()
	board.size = Vector3(9.0, 0.14, 0.62)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.78, 0.56, 0.4)
	wood.roughness = 0.9
	board.material = wood
	shelf.mesh = board
	shelf.position = Vector3(3.0, 1.95, WALL_Z + 0.72)
	stage.add_child(shelf)
	var treats := [
		["cake-birthday.glb", -3.2, 0.5],
		["cupcake.glb", -2.3, 0.32],
		["pie.glb", -1.4, 0.4],
		["donut-sprinkles.glb", -0.5, 0.3],
		["cake.glb", 0.45, 0.48],
		["croissant.glb", 1.35, 0.3],
		["muffin.glb", 2.15, 0.3],
		["cookie.glb", 2.95, 0.26],
		["waffle.glb", 3.7, 0.3],
	]
	for entry: Array in treats:
		var prop := Models.node(DIR + str(entry[0]), float(entry[2]), true)
		prop.position = Vector3(3.0 + float(entry[1]), 2.02, WALL_Z + 0.72)
		stage.add_child(prop)

	_lamps(stage)
	_bunting(stage)

	var sign_board := MeshInstance3D.new()
	var sbox := BoxMesh.new()
	sbox.size = Vector3(2.2, 0.5, 0.14)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.86, 0.42, 0.52)
	smat.roughness = 0.75
	sbox.material = smat
	sign_board.mesh = sbox
	# Rechts oben, ÜBER den Lampenschirmen (Oberkante y = 2,95) und rechts an der
	# Auftragsblase vorbei — mittig auf Schirmhöhe wäre die Schrift verdeckt.
	sign_board.position = Vector3(4.8, 3.38, WALL_Z + 0.3)
	stage.add_child(sign_board)
	var label := Label3D.new()
	label.text = "BACKSTUBE"
	label.font_size = 64
	label.pixel_size = 0.0027
	label.modulate = Color(1.0, 0.96, 0.92)
	label.position = Vector3(4.8, 3.38, WALL_Z + 0.4)
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	stage.add_child(label)


## Drei Hängelampen — zwei davon mit echtem Licht (Perf: nicht mehr).
static func _lamps(stage: Node3D) -> void:
	var shade_mat := StandardMaterial3D.new()
	shade_mat.albedo_color = Color(0.96, 0.55, 0.5)
	shade_mat.roughness = 0.6
	var bulb_mat := StandardMaterial3D.new()
	bulb_mat.albedo_color = Color(1.0, 0.93, 0.76)
	bulb_mat.emission_enabled = true
	bulb_mat.emission = Color(1.0, 0.88, 0.66)
	bulb_mat.emission_energy_multiplier = 3.2
	for i in 3:
		var x := 0.9 + i * 2.1
		var cord := MeshInstance3D.new()
		var cbox := BoxMesh.new()
		cbox.size = Vector3(0.04, 1.1, 0.04)
		cbox.material = shade_mat
		cord.mesh = cbox
		cord.position = Vector3(x, 3.5, -1.6)
		stage.add_child(cord)
		var shade := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.1
		cone.bottom_radius = 0.46
		cone.height = 0.42
		cone.radial_segments = 14
		cone.material = shade_mat
		shade.mesh = cone
		shade.position = Vector3(x, 2.74, -1.6)
		stage.add_child(shade)
		var bulb := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.12
		ball.height = 0.24
		ball.radial_segments = 10
		ball.rings = 6
		ball.material = bulb_mat
		bulb.mesh = ball
		bulb.position = Vector3(x, 2.52, -1.6)
		stage.add_child(bulb)
		if i == 1:
			continue
		var lamp := OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.87, 0.68)
		lamp.light_energy = 3.6
		lamp.omni_range = 5.5
		lamp.position = Vector3(x, 2.35, -1.2)
		stage.add_child(lamp)


## Wimpelkette quer durch den Laden (MultiMesh + Schnur).
static func _bunting(stage: Node3D) -> void:
	const FLAGS: Array[Color] = [
		Color(0.95, 0.5, 0.6),
		Color(1.0, 0.84, 0.45),
		Color(0.55, 0.8, 0.75),
		Color(0.76, 0.66, 0.93),
	]
	var cord := MeshInstance3D.new()
	var cbox := BoxMesh.new()
	cbox.size = Vector3(12.0, 0.04, 0.04)
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.6, 0.48, 0.42)
	cbox.material = cmat
	cord.mesh = cbox
	# 25 cm höher als die Wimpelspitzen: darunter braucht das Ladenschild Luft.
	cord.position = Vector3(3.0, 4.3, -2.4)
	stage.add_child(cord)
	for i in FLAGS.size():
		var tri := CylinderMesh.new()
		tri.top_radius = 0.0
		tri.bottom_radius = 0.2
		tri.height = 0.38
		tri.radial_segments = 3
		var mat := StandardMaterial3D.new()
		mat.albedo_color = FLAGS[i]
		mat.roughness = 0.95
		tri.material = mat
		var poses: Array = []
		var index := i
		while index < 24:
			var t := float(index) / 23.0
			poses.append(
				Transform3D(
					Basis(Vector3.RIGHT, PI),
					Vector3(-2.8 + t * 11.6, 4.11 - sin(t * PI) * 0.28, -2.4)
				)
			)
			index += FLAGS.size()
		stage.add_child(Models.swarm([{"mesh": tri, "xform": Transform3D.IDENTITY}], poses, 20.0))
