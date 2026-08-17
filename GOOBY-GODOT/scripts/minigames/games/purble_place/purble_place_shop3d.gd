extends RefCounted
## Kulisse der 3D-Backstube (Agent 3D-C, MP-D-Tiefenpolitur): Wand mit
## Pastellstreifen, ZWEI Sprossenfenster mit Abendblick nach draußen, Kachel-
## spiegel, Dielenboden, Wandregal mit echtem Kenney-Gebäck, TinyTreats-
## Requisiten (Vitrine, Kasse, Küchenmaschine, Waage, Teigroller, Macarons),
## Mehlsäcke, Wanduhr, Hängelampen, Wimpelkette und Ladenschild. Alles steht
## STILL — es wird einmal an die Bühne gehängt und danach nie wieder angefasst.
##
## Eigene Datei, damit `purble_place_stage3d.gd` unter der 1000-Zeilen-Grenze
## bleibt. Massenware (Streifen, Kacheln, Wimpel) läuft über MultiMesh, das
## ganze Paket kostet gut zwei Dutzend Draw-Calls. Seit die Sonne WEICHE
## Schatten wirft, ist die Kulisse vom Schattenwurf ausgenommen (nur die
## Requisiten nahe am Band werfen welche) — hält den Schatten-Pass billig.

const Models := preload("res://scripts/minigames/games/_3dc_stage/models3d.gd")
const DIR := "res://assets/minigames/purble_place/"
const TREATS := "res://assets/minigames/purble_place/tinytreats/"

## Rückwand, Kachelspiegel und Boden (Weltmeter, y = 0 ist die Bandoberkante).
const WALL_Z := -4.2
const COUNTER_Z := -2.05
const FLOOR_Y := -0.55


static func build(stage: Node3D) -> void:
	var wall := MeshInstance3D.new()
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(20.0, 9.0, 0.3)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.97, 0.88, 0.78)
	mat.roughness = 1.0
	wall_mesh.material = mat
	wall.mesh = wall_mesh
	wall.position = Vector3(3.0, 3.4, WALL_Z)
	no_shadow(wall)
	stage.add_child(wall)

	# Senkrechte Pastellstreifen (Web-Tapete) als EIN MultiMesh.
	var stripe := BoxMesh.new()
	stripe.size = Vector3(0.62, 9.0, 0.06)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.94, 0.8, 0.7)
	smat.roughness = 1.0
	stripe.material = smat
	var poses: Array = []
	for i in 16:
		poses.append(Transform3D(Basis.IDENTITY, Vector3(-4.6 + i * 1.24, 3.4, WALL_Z + 0.18)))
	stage.add_child(
		no_shadow(Models.swarm([{"mesh": stripe, "xform": Transform3D.IDENTITY}], poses, 24.0))
	)

	_tiles(stage)

	var floor_node := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(22.0, 12.0)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.8, 0.67, 0.56)
	fmat.roughness = 1.0
	plane.material = fmat
	floor_node.mesh = plane
	floor_node.position = Vector3(3.0, FLOOR_Y, -1.4)
	no_shadow(floor_node)
	stage.add_child(floor_node)
	_windows(stage)
	_backdrop(stage)
	_treat_props(stage)
	_flour_sacks(stage)
	_clock(stage)


## Zwei Sprossenfenster in der Rückwand mit Abendblick nach draußen (Himmel-
## streifen + Hügel + Sonnenfleck): die Backstube bekommt Tiefe und ein
## „draußen“, statt nur Tapete. Links UND rechts — die Kamera schwenkt.
static func _windows(stage: Node3D) -> void:
	# 1,95: am Spielstart (Kamera ganz links) frei sichtbar zwischen den
	# Lampen — bei 0,55 verschwand das Fenster hinter der Auftragskarte.
	for wx in [1.95, 5.45]:
		stage.add_child(_window_at(float(wx)))


static func _window_at(x: float) -> Node3D:
	var holder := Node3D.new()
	holder.position = Vector3(x, 2.95, WALL_Z + 0.22)
	var sky := StandardMaterial3D.new()
	sky.albedo_color = Color(1.0, 0.72, 0.42)
	sky.emission_enabled = true
	sky.emission = Color(1.0, 0.66, 0.34)
	sky.emission_energy_multiplier = 0.7
	var pane := MeshInstance3D.new()
	var pane_mesh := QuadMesh.new()
	pane_mesh.size = Vector2(1.5, 1.7)
	pane_mesh.material = sky
	pane.mesh = pane_mesh
	holder.add_child(pane)
	# Hügelzug im unteren Fensterdrittel + tiefe Abendsonne.
	var hill := MeshInstance3D.new()
	var hill_mesh := SphereMesh.new()
	hill_mesh.radius = 0.85
	hill_mesh.height = 0.8
	hill_mesh.radial_segments = 14
	hill_mesh.rings = 7
	var hill_mat := StandardMaterial3D.new()
	hill_mat.albedo_color = Color(0.38, 0.53, 0.36)
	hill_mesh.material = hill_mat
	hill.mesh = hill_mesh
	hill.scale = Vector3(1.0, 0.5, 0.12)
	hill.position = Vector3(0.25, -0.78, 0.03)
	holder.add_child(hill)
	var sun_dot := MeshInstance3D.new()
	var dot_mesh := SphereMesh.new()
	dot_mesh.radius = 0.16
	dot_mesh.height = 0.32
	dot_mesh.radial_segments = 10
	dot_mesh.rings = 5
	var dot_mat := StandardMaterial3D.new()
	dot_mat.albedo_color = Color(1.0, 0.9, 0.6)
	dot_mat.emission_enabled = true
	dot_mat.emission = Color(1.0, 0.8, 0.45)
	dot_mat.emission_energy_multiplier = 2.2
	dot_mesh.material = dot_mat
	sun_dot.mesh = dot_mesh
	sun_dot.scale = Vector3(1.0, 1.0, 0.1)
	sun_dot.position = Vector3(-0.38, -0.15, 0.04)
	holder.add_child(sun_dot)
	# Rahmen + Kreuzsprossen aus Holz.
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.62, 0.44, 0.32)
	wood.roughness = 0.9
	for bar: Array in [
		[Vector3(1.7, 0.1, 0.08), Vector3(0.0, 0.9, 0.05)],
		[Vector3(1.7, 0.1, 0.08), Vector3(0.0, -0.9, 0.05)],
		[Vector3(0.1, 1.9, 0.08), Vector3(0.8, 0.0, 0.05)],
		[Vector3(0.1, 1.9, 0.08), Vector3(-0.8, 0.0, 0.05)],
		[Vector3(1.6, 0.05, 0.06), Vector3(0.0, 0.0, 0.05)],
		[Vector3(0.05, 1.8, 0.06), Vector3(0.0, 0.0, 0.05)],
	]:
		var rail := MeshInstance3D.new()
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = bar[0]
		rail_mesh.material = wood
		rail.mesh = rail_mesh
		rail.position = bar[1]
		holder.add_child(rail)
	return no_shadow(holder)


## TinyTreats-Requisiten: Vitrine mit Macarons links am Ladeneingang, Kasse
## auf der Theke, Backtisch mit Küchenmaschine/Waage/Teigroller rechts.
static func _treat_props(stage: Node3D) -> void:
	var case_node := Models.node(TREATS + "display_case_short.gltf", 1.15)
	case_node.position = Vector3(-0.15, FLOOR_Y, -1.35)
	case_node.rotation_degrees.y = 8.0
	stage.add_child(case_node)
	var flavors := ["macaron_pink.gltf", "macaron_yellow.gltf", "macaron_blue.gltf"]
	for i in 3:
		var macaron := Models.node(TREATS + flavors[i], 0.17)
		macaron.position = Vector3(-0.42 + 0.27 * float(i), FLOOR_Y + 0.62, -1.32)
		stage.add_child(macaron)
	var register := Models.node(TREATS + "cash_register.gltf", 0.42)
	register.position = Vector3(1.05, FLOOR_Y + 1.4, COUNTER_Z)
	register.rotation_degrees.y = -6.0
	stage.add_child(register)
	# Backtisch rechts: dort arbeitet die Küchenmaschine.
	var table := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(1.3, 0.09, 0.7)
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.76, 0.56, 0.4)
	wood.roughness = 0.9
	slab.material = wood
	table.mesh = slab
	table.position = Vector3(5.35, FLOOR_Y + 0.62, -1.45)
	stage.add_child(table)
	var leg := BoxMesh.new()
	leg.size = Vector3(0.09, 0.62, 0.09)
	leg.material = wood
	var leg_poses: Array = []
	for corner: Vector2 in [
		Vector2(-0.55, -0.25), Vector2(0.55, -0.25), Vector2(-0.55, 0.25), Vector2(0.55, 0.25)
	]:
		leg_poses.append(
			Transform3D(Basis.IDENTITY, Vector3(5.35 + corner.x, FLOOR_Y + 0.31, -1.45 + corner.y))
		)
	stage.add_child(Models.swarm([{"mesh": leg, "xform": Transform3D.IDENTITY}], leg_poses, 20.0))
	var mixer := Models.node(TREATS + "stand_mixer.gltf", 0.44)
	mixer.position = Vector3(5.05, FLOOR_Y + 0.66, -1.45)
	mixer.rotation_degrees.y = 14.0
	stage.add_child(mixer)
	var scale_node := Models.node(TREATS + "scale.gltf", 0.3)
	scale_node.position = Vector3(5.62, FLOOR_Y + 0.66, -1.5)
	stage.add_child(scale_node)
	var roller := Models.node(TREATS + "dough_roller.gltf", 0.4)
	roller.position = Vector3(5.42, FLOOR_Y + 0.67, -1.25)
	roller.rotation_degrees.y = 52.0
	stage.add_child(roller)
	var dough := Models.node(TREATS + "dough_ball.gltf", 0.22)
	dough.position = Vector3(5.7, FLOOR_Y + 0.67, -1.28)
	stage.add_child(dough)


## Zwei pralle Mehlsäcke am Ofensockel (Zylinder + geknoteter Kopf).
static func _flour_sacks(stage: Node3D) -> void:
	var cloth := StandardMaterial3D.new()
	cloth.albedo_color = Color(0.93, 0.88, 0.78)
	cloth.roughness = 1.0
	for sack: Array in [[1.62, -1.3, 0.0], [1.9, -1.42, 14.0]]:
		var holder := Node3D.new()
		holder.position = Vector3(float(sack[0]), FLOOR_Y, float(sack[1]))
		holder.rotation_degrees.z = float(sack[2])
		var body := MeshInstance3D.new()
		var body_mesh := CylinderMesh.new()
		body_mesh.top_radius = 0.14
		body_mesh.bottom_radius = 0.19
		body_mesh.height = 0.42
		body_mesh.radial_segments = 10
		body_mesh.material = cloth
		body.mesh = body_mesh
		body.position.y = 0.21
		holder.add_child(body)
		var knot := MeshInstance3D.new()
		var knot_mesh := SphereMesh.new()
		knot_mesh.radius = 0.09
		knot_mesh.height = 0.14
		knot_mesh.radial_segments = 8
		knot_mesh.rings = 5
		knot_mesh.material = cloth
		knot.mesh = knot_mesh
		knot.position.y = 0.46
		holder.add_child(knot)
		stage.add_child(holder)


## Wanduhr links oben — Requisite, keine echte Zeit.
static func _clock(stage: Node3D) -> void:
	var holder := Node3D.new()
	holder.position = Vector3(0.5, 3.6, WALL_Z + 0.24)
	var rim := MeshInstance3D.new()
	var rim_mesh := TorusMesh.new()
	rim_mesh.inner_radius = 0.24
	rim_mesh.outer_radius = 0.3
	rim_mesh.rings = 16
	rim_mesh.ring_segments = 6
	var rim_mat := StandardMaterial3D.new()
	rim_mat.albedo_color = Color(0.85, 0.5, 0.45)
	rim_mesh.material = rim_mat
	rim.mesh = rim_mesh
	rim.rotation_degrees.x = 90.0
	holder.add_child(rim)
	var face := MeshInstance3D.new()
	var face_mesh := CylinderMesh.new()
	face_mesh.top_radius = 0.25
	face_mesh.bottom_radius = 0.25
	face_mesh.height = 0.03
	face_mesh.radial_segments = 16
	var face_mat := StandardMaterial3D.new()
	face_mat.albedo_color = Color(1.0, 0.97, 0.92)
	face_mesh.material = face_mat
	face.mesh = face_mesh
	face.rotation_degrees.x = 90.0
	holder.add_child(face)
	var hand_mat := StandardMaterial3D.new()
	hand_mat.albedo_color = Color(0.3, 0.24, 0.22)
	for hand: Array in [[0.16, 20.0], [0.11, 120.0]]:
		var bar := MeshInstance3D.new()
		var bar_mesh := BoxMesh.new()
		bar_mesh.size = Vector3(0.03, float(hand[0]), 0.02)
		bar_mesh.material = hand_mat
		bar.mesh = bar_mesh
		bar.rotation_degrees.z = float(hand[1])
		bar.position = (
			Basis(Vector3.BACK, deg_to_rad(float(hand[1])))
			* Vector3(0.0, float(hand[0]) * 0.5, 0.0)
		)
		bar.position.z = 0.03
		holder.add_child(bar)
	stage.add_child(no_shadow(holder))


## Kulisse wirft KEINE Schatten (der weiche Sonnenschatten bleibt den
## Requisiten am Band vorbehalten — hält den Schatten-Pass billig).
static func no_shadow(node: Node) -> Node:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		no_shadow(child)
	return node


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
	stage.add_child(
		no_shadow(Models.swarm([{"mesh": tile, "xform": Transform3D.IDENTITY}], poses, 24.0))
	)


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
		stage.add_child(no_shadow(prop))

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
	bulb_mat.emission_energy_multiplier = 2.4
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
		lamp.light_energy = 2.2
		lamp.omni_range = 4.6
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
		stage.add_child(
			no_shadow(Models.swarm([{"mesh": tri, "xform": Transform3D.IDENTITY}], poses, 20.0))
		)
