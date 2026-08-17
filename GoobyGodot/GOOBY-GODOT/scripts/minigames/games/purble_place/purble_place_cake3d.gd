extends RefCounted
## Torten-Baukasten der 3D-Backstube (Agent 3D-C). Eine Bandform ist ein
## einziger Pool-Knoten, in dem ALLE Varianten fertig hängen — Formkörper,
## Gussdeckel, Deko und vier Kerzen. `dress()` blendet nur um, statt Meshes neu
## zu bauen; unsichtbare Meshes kosten keinen Draw-Call.
##
## Die Farbwerte kommen aus `purble_place_cake.gd`, damit die 3D-Torte auf dem
## Band und die 2D-Torte auf dem Auftragskärtchen garantiert dieselbe Sprache
## sprechen (§C9.2-Merkmale: Form, Teig, Guss, Deko, Kerzen, Backgrad).

const Cake := preload("res://scripts/minigames/games/purble_place/purble_place_cake.gd")

const SHAPES: Array[String] = ["round", "square", "heart"]


## Neue Pool-Torte. `w` ist die volle Breite in Metern.
static func make(w: float) -> Node3D:
	var root := Node3D.new()
	var tray := MeshInstance3D.new()
	var tray_mesh := CylinderMesh.new()
	tray_mesh.top_radius = w * 0.56
	tray_mesh.bottom_radius = w * 0.52
	tray_mesh.height = 0.05
	tray_mesh.radial_segments = 18
	var tray_mat := StandardMaterial3D.new()
	tray_mat.albedo_color = Color(0.78, 0.76, 0.79)
	tray_mat.metallic = 0.4
	tray_mat.roughness = 0.35
	tray_mesh.material = tray_mat
	tray.mesh = tray_mesh
	tray.position = Vector3(0.0, 0.025, 0.0)
	root.add_child(tray)

	var bodies := Node3D.new()
	bodies.name = "bodies"
	bodies.position = Vector3(0.0, 0.05, 0.0)
	root.add_child(bodies)
	var icings := Node3D.new()
	icings.name = "icings"
	icings.position = Vector3(0.0, 0.29, 0.0)
	root.add_child(icings)
	for shape in SHAPES:
		var body := _shape(shape, w, 0.24)
		body.name = shape
		body.visible = false
		bodies.add_child(body)
		var lid := _shape(shape, w * 1.04, 0.06)
		lid.name = shape
		lid.visible = false
		icings.add_child(lid)

	var topping := Node3D.new()
	topping.name = "topping"
	topping.position = Vector3(0.0, 0.33, 0.0)
	root.add_child(topping)
	topping.add_child(_cherry())
	topping.add_child(_berries())
	topping.add_child(_sprinkles())
	var candles := Node3D.new()
	candles.name = "candles"
	candles.position = Vector3(0.0, 0.33, 0.0)
	root.add_child(candles)
	for i in 4:
		var candle := _candle()
		candle.position = Vector3((float(i) - 1.5) * w * 0.21, 0.0, 0.0)
		candle.visible = false
		candles.add_child(candle)
	return root


## Pool-Torte auf den Zustand einer Bandform umfärben.
static func dress(root: Node3D, pan: Dictionary) -> void:
	var shape := str(pan.get("shape", "round"))
	var body_col := Cake.sponge_color(pan.get("sponge", null), pan.get("bake", null))
	for child: Node3D in root.get_node("bodies").get_children():
		child.visible = child.name == shape
		if child.visible:
			(child.get_meta("mat") as StandardMaterial3D).albedo_color = body_col
	var icing: Variant = pan.get("icing", null)
	var has_icing := icing != null and str(icing) != "none"
	for child: Node3D in root.get_node("icings").get_children():
		child.visible = has_icing and child.name == shape
		if child.visible:
			(child.get_meta("mat") as StandardMaterial3D).albedo_color = Cake.ICING[str(icing)]
	var topping := str(pan.get("topping", "none"))
	var deck: Node3D = root.get_node("topping")
	deck.position.y = 0.33 if has_icing else 0.29
	for child: Node3D in deck.get_children():
		child.visible = child.name == topping
	var count := int(pan.get("candles", 0))
	var candles: Node3D = root.get_node("candles")
	candles.position.y = deck.position.y
	for i in candles.get_child_count():
		(candles.get_child(i) as Node3D).visible = i < count


## Grundkörper je Tortenform (`h` = Höhe). Das Herz besteht aus zwei Zylindern
## und einem um 45° gedrehten Kasten — lauter konvexe Teile.
static func _shape(shape: String, w: float, h: float) -> Node3D:
	var node := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.roughness = 0.8
	node.set_meta("mat", mat)
	if shape == "square":
		node.add_child(_part(_box(Vector3(w * 0.88, h, w * 0.88)), mat, Vector3(0.0, h * 0.5, 0.0)))
		return node
	if shape == "heart":
		for side in [-1.0, 1.0]:
			var cyl := CylinderMesh.new()
			cyl.top_radius = w * 0.27
			cyl.bottom_radius = w * 0.27
			cyl.height = h
			cyl.radial_segments = 16
			node.add_child(_part(cyl, mat, Vector3(side * w * 0.22, h * 0.5, -w * 0.18)))
		var tip := _part(_box(Vector3(w * 0.62, h, w * 0.62)), mat, Vector3(0.0, h * 0.5, w * 0.06))
		tip.rotation_degrees = Vector3(0.0, 45.0, 0.0)
		node.add_child(tip)
		return node
	var disc := CylinderMesh.new()
	disc.top_radius = w * 0.47
	disc.bottom_radius = w * 0.45
	disc.height = h
	disc.radial_segments = 20
	node.add_child(_part(disc, mat, Vector3(0.0, h * 0.5, 0.0)))
	return node


static func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


static func _part(mesh: Mesh, mat: Material, at: Vector3) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	return node


static func _cherry() -> Node3D:
	var node := Node3D.new()
	node.name = "cherry"
	node.visible = false
	var mesh := SphereMesh.new()
	mesh.radius = 0.07
	mesh.height = 0.14
	mesh.radial_segments = 12
	mesh.rings = 7
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Cake.DEKO["cherry"]
	mat.roughness = 0.3
	mesh.material = mat
	node.add_child(_part(mesh, mat, Vector3(0.0, 0.07, 0.0)))
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.35, 0.5, 0.24)
	var stem := _part(_box(Vector3(0.015, 0.1, 0.015)), smat, Vector3(0.02, 0.18, 0.0))
	stem.rotation_degrees = Vector3(0.0, 0.0, -18.0)
	node.add_child(stem)
	return node


static func _berries() -> Node3D:
	var node := Node3D.new()
	node.name = "berries"
	node.visible = false
	var mesh := SphereMesh.new()
	mesh.radius = 0.055
	mesh.height = 0.11
	mesh.radial_segments = 10
	mesh.rings = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Cake.DEKO["berries"]
	mat.roughness = 0.35
	for i in 3:
		node.add_child(
			_part(mesh, mat, Vector3((float(i) - 1.0) * 0.12, 0.055, 0.05 if i == 1 else -0.03))
		)
	return node


static func _sprinkles() -> Node3D:
	var node := Node3D.new()
	node.name = "sprinkles"
	node.visible = false
	var mesh := _box(Vector3(0.055, 0.02, 0.02))
	for i in 8:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Cake.SPRINKLES[i % Cake.SPRINKLES.size()]
		mat.roughness = 0.4
		var a := float(i) * 0.9
		var bit := _part(mesh, mat, Vector3(cos(a) * 0.13, 0.02, sin(a) * 0.11))
		bit.rotation_degrees = Vector3(0.0, a * 40.0, 0.0)
		node.add_child(bit)
	return node


static func _candle() -> Node3D:
	var node := Node3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.018
	cyl.bottom_radius = 0.018
	cyl.height = 0.17
	cyl.radial_segments = 8
	var wax := StandardMaterial3D.new()
	wax.albedo_color = Color(0.98, 0.95, 0.86)
	node.add_child(_part(cyl, wax, Vector3(0.0, 0.085, 0.0)))
	var ball := SphereMesh.new()
	ball.radius = 0.028
	ball.height = 0.07
	ball.radial_segments = 8
	ball.rings = 5
	var fire := StandardMaterial3D.new()
	fire.albedo_color = Color(1.0, 0.82, 0.32)
	fire.emission_enabled = true
	fire.emission = Color(1.0, 0.7, 0.25)
	fire.emission_energy_multiplier = 3.5
	node.add_child(_part(ball, fire, Vector3(0.0, 0.2, 0.0)))
	return node
