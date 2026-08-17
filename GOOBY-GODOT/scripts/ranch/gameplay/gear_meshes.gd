class_name RanchGearMeshes
extends RefCounted
## Einfache 3D-Meshes der Pferde-Ausrüstung (RANCH-2, Daten-Katalog in
## wirtschaft.json): Sattel, Decke, Halfter — als Primitive gebaut, damit
## Attrappe UND späteres RANCH-1-Modell dieselben Aufsätze tragen können.
## Jede Farbe ist ein Material; Draw-Calls: Sattel 2, Decke 1, Halfter 1.

## Gear-Farb-Ids → Albedo (Katalog-Ids "sattel_rot" usw.).
const FARBEN := {
	"rot": Color("#D9534F"),
	"blau": Color("#4A7EC2"),
	"gruen": Color("#5FA052"),
	"lila": Color("#9A6BC4"),
	"gold": Color("#E8B23A"),
}


## Aufsatz für einen Slot bauen (Wurzel-Node3D, Name "Gear_<slot>").
## Unbekannter Slot/Farbe → null.
static func build(slot: String, farbe: String) -> Node3D:
	if not FARBEN.has(farbe):
		return null
	var color: Color = FARBEN[farbe]
	var root: Node3D = null
	match slot:
		"sattel":
			root = _sattel(color)
		"decke":
			root = _decke(color)
		"halfter":
			root = _halfter(color)
	if root != null:
		root.name = "Gear_%s" % slot
	return root


## Gemeinsames, mattes Material (eine Instanz pro Aufsatz).
static func material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	mat.metallic = 0.0
	return mat


static func _sattel(color: Color) -> Node3D:
	var root := Node3D.new()
	var mat := material(color)
	var sitz := MeshInstance3D.new()
	var sitz_mesh := CapsuleMesh.new()
	sitz_mesh.radius = 0.16
	sitz_mesh.height = 0.52
	sitz.mesh = sitz_mesh
	sitz.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	sitz.scale = Vector3(1.0, 1.0, 0.55)
	sitz.material_override = mat
	root.add_child(sitz)
	var gurt := MeshInstance3D.new()
	var gurt_mesh := BoxMesh.new()
	gurt_mesh.size = Vector3(0.74, 0.34, 0.1)
	gurt.mesh = gurt_mesh
	gurt.position = Vector3(0.0, -0.18, 0.0)
	gurt.material_override = mat
	root.add_child(gurt)
	return root


static func _decke(color: Color) -> Node3D:
	var root := Node3D.new()
	var decke := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.78, 0.05, 0.7)
	decke.mesh = mesh
	decke.material_override = material(color)
	root.add_child(decke)
	return root


static func _halfter(color: Color) -> Node3D:
	## Nasenband: Ring, dessen Loch-Achse auf +z zeigt (Schnauzen-Richtung im
	## RanchPferd-Kopfraum) und der die Schnauze (Radius ~0.24/0.18) umschließt.
	var root := Node3D.new()
	var band := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.2
	mesh.outer_radius = 0.26
	band.mesh = mesh
	band.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	band.scale = Vector3(1.15, 1.0, 1.0)
	band.position = Vector3(0.0, -0.04, 0.1)
	band.material_override = material(color)
	root.add_child(band)
	return root
