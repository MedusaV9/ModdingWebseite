class_name Autoscooter
extends Node3D
## Autoscooter-Arena (REST-4): drei Kenney-Flitzer stupsen sich auf einer
## flachen Arena in versetzten Ellipsen — reines Park-Leben zum Zuschauen
## (Goobys Pfoten reichen nicht ans Pedal, sagt das Schild). Deterministisch
## ohne Physik: Ellipsenbahnen mit Phasenversatz, dadurch kein Clipping.

const AUTOS := "res://assets/city/autos"
const MODELLE: Array[String] = ["hatchback-sports", "sedan", "taxi"]
const TINTS: Array[Color] = [Color("#E8524A"), Color("#4E79D6"), Color("#8FD06C")]
const ARENA := Vector2(7.0, 5.0)

var _wagen: Array[Dictionary] = []
var _zeit := 0.0


func _ready() -> void:
	_baue_arena()
	_baue_wagen()


func _physics_process(delta: float) -> void:
	_zeit += delta
	for eintrag in _wagen:
		var node: Node3D = eintrag["node"]
		var phase := float(eintrag["phase"])
		var richtung := float(eintrag["richtung"])
		var t := _zeit * 0.55 * richtung + phase
		var a := (ARENA.x * 0.5 - 1.0) * float(eintrag["skala"])
		var b := (ARENA.y * 0.5 - 1.0) * float(eintrag["skala"])
		var pos := Vector3(cos(t) * a, 0.12, sin(t) * b)
		var tangente := Vector3(-sin(t) * a, 0.0, cos(t) * b) * richtung
		node.position = pos
		if tangente.length_squared() > 0.001:
			node.rotation.y = atan2(tangente.x, tangente.z)


func _baue_arena() -> void:
	var boden := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(ARENA.x, 0.14, ARENA.y)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#4A3B36")
	mat.roughness = 0.35
	box.material = mat
	boden.mesh = box
	boden.position.y = 0.07
	add_child(boden)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var pfosten := BoxMesh.new()
	pfosten.size = Vector3(0.16, 0.7, 0.16)
	var pfosten_mat := StandardMaterial3D.new()
	pfosten_mat.albedo_color = Color("#F2C14E")
	pfosten.material = pfosten_mat
	mm.mesh = pfosten
	var punkte: Array[Vector3] = []
	var nx := 6
	var nz := 4
	for i in nx:
		var x := -ARENA.x * 0.5 + ARENA.x * float(i) / float(nx - 1)
		punkte.append(Vector3(x, 0.35, -ARENA.y * 0.5))
		punkte.append(Vector3(x, 0.35, ARENA.y * 0.5))
	for i in nz:
		var z := -ARENA.y * 0.5 + ARENA.y * float(i) / float(nz - 1)
		punkte.append(Vector3(-ARENA.x * 0.5, 0.35, z))
		punkte.append(Vector3(ARENA.x * 0.5, 0.35, z))
	mm.instance_count = punkte.size()
	for i in punkte.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, punkte[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)
	_baue_girlanden()


## Girlanden über der Arena (EVAL B §4 „Autoscooter-Arena mit Girlanden"):
## vier Eckmasten + EIN Birnchen-MultiMesh mit Durchhang zwischen den
## Masten — bunt, unshaded, liest tags wie Kirmes und funkelt nachts.
func _baue_girlanden() -> void:
	var mast_mesh := CylinderMesh.new()
	mast_mesh.top_radius = 0.06
	mast_mesh.bottom_radius = 0.08
	mast_mesh.height = 2.6
	mast_mesh.radial_segments = 8
	var mast_mat := StandardMaterial3D.new()
	mast_mat.albedo_color = Color("#F0EFE9")
	mast_mesh.material = mast_mat
	var ecken: Array[Vector3] = [
		Vector3(-ARENA.x * 0.5, 0.0, -ARENA.y * 0.5),
		Vector3(ARENA.x * 0.5, 0.0, -ARENA.y * 0.5),
		Vector3(ARENA.x * 0.5, 0.0, ARENA.y * 0.5),
		Vector3(-ARENA.x * 0.5, 0.0, ARENA.y * 0.5),
	]
	for ecke in ecken:
		var mast := MeshInstance3D.new()
		mast.mesh = mast_mesh
		mast.position = ecke + Vector3(0.0, 1.3, 0.0)
		add_child(mast)
	var birne := SphereMesh.new()
	birne.radius = 0.11
	birne.height = 0.22
	birne.radial_segments = 8
	birne.rings = 4
	var birnen_mat := StandardMaterial3D.new()
	birnen_mat.vertex_color_use_as_albedo = true
	birnen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	birne.material = birnen_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = birne
	var punkte: Array[Vector3] = []
	for seite in 4:
		var von: Vector3 = ecken[seite] + Vector3(0.0, 2.55, 0.0)
		var bis: Vector3 = ecken[(seite + 1) % 4] + Vector3(0.0, 2.55, 0.0)
		for i in 6:
			var t := (float(i) + 0.5) / 6.0
			punkte.append(von.lerp(bis, t) - Vector3(0.0, sin(t * PI) * 0.35, 0.0))
	mm.instance_count = punkte.size()
	for i in punkte.size():
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, punkte[i]))
		mm.set_instance_color(i, TINTS[i % TINTS.size()].lightened(0.35))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Girlanden"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


func _baue_wagen() -> void:
	for i in MODELLE.size():
		var pfad := "%s/%s.glb" % [AUTOS, MODELLE[i]]
		if not ResourceLoader.exists(pfad):
			continue
		var szene: PackedScene = load(pfad)
		if szene == null:
			continue
		var node: Node3D = szene.instantiate()
		node.scale = Vector3.ONE * 0.9
		add_child(node)
		_faerbe(node, TINTS[i % TINTS.size()])
		(
			_wagen
			. append(
				{
					"node": node,
					"phase": TAU * float(i) / float(MODELLE.size()),
					"richtung": 1.0 if i % 2 == 0 else -1.0,
					"skala": 1.0 - float(i) * 0.18,
				}
			)
		)


func _faerbe(node: Node3D, farbe: Color) -> void:
	for mesh in node.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = mesh
		if mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var mat: Material = mi.mesh.surface_get_material(i)
			if mat is StandardMaterial3D:
				var kopie: StandardMaterial3D = mat.duplicate()
				kopie.albedo_color = kopie.albedo_color.lerp(farbe, 0.5)
				mi.set_surface_override_material(i, kopie)
