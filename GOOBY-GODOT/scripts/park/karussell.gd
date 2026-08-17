class_name Karussell
extends Node3D
## Funkel-Karussell (REST-4): rotierende Plattform mit vier Pastell-Ponys,
## die im Gegentakt auf und ab wippen. Gooby kann als echtes Kind auf
## Pony 0 mitreiten (aufsitzen → eine Runde → absteigen). Alles prozedural
## (Kapsel + Kugel + Stangen) — kein GLB nötig, wenige Draw-Calls.

signal ride_finished

const PONY_FARBEN: Array[Color] = [
	Color("#F781B0"), Color("#9BD7E8"), Color("#F2C14E"), Color("#B58CE4")
]
const RADIUS := 2.6
const TEMPO := 0.7
const RUNDEN := 2.0

var speed_scale := 1.0
var faehrt := false
var rig: GoobyRig

var _teller: Node3D
var _ponys: Array[Node3D] = []
var _winkel := 0.0
var _gefahren := 0.0


func _ready() -> void:
	_baue_plattform()
	_baue_ponys()
	_baue_noten()


func _physics_process(delta: float) -> void:
	simuliere(delta)


func starte_fahrt() -> void:
	faehrt = true
	_gefahren = 0.0
	if rig == null:
		rig = GoobyRig.new()
		rig.scale = Vector3.ONE * 0.55
		_ponys[0].add_child(rig)
		rig.position = Vector3(0.0, 0.62, 0.0)
	rig.visible = true
	rig.play_clip("sit")


## Dreht immer gemütlich weiter (Park-Leben); eine BEZAHLTE Fahrt zählt
## Runden und meldet ride_finished.
func simuliere(delta: float) -> void:
	var schritt := TEMPO * speed_scale * delta
	_winkel += schritt
	_teller.rotation.y = _winkel
	for i in _ponys.size():
		var pony := _ponys[i]
		pony.position.y = 0.55 + sin(_winkel * 2.0 + float(i) * PI * 0.5) * 0.18
	if not faehrt:
		return
	_gefahren += schritt
	if _gefahren >= RUNDEN * TAU:
		faehrt = false
		if rig != null:
			rig.play_clip("celebrate")
			rig.visible = false
		ride_finished.emit()


func gooby_sitz_abstand() -> float:
	if rig == null or _ponys.is_empty():
		return 0.0
	return rig.global_position.distance_to(_ponys[0].to_global(Vector3(0.0, 0.62, 0.0)))


func _baue_plattform() -> void:
	var sockel := MeshInstance3D.new()
	var sockel_mesh := CylinderMesh.new()
	sockel_mesh.top_radius = RADIUS + 0.7
	sockel_mesh.bottom_radius = RADIUS + 0.9
	sockel_mesh.height = 0.3
	var sockel_mat := StandardMaterial3D.new()
	sockel_mat.albedo_color = Color("#B98A62")
	sockel_mesh.material = sockel_mat
	sockel.mesh = sockel_mesh
	sockel.position.y = 0.15
	add_child(sockel)
	_teller = Node3D.new()
	_teller.name = "Teller"
	_teller.position.y = 0.32
	add_child(_teller)
	var boden := MeshInstance3D.new()
	var boden_mesh := CylinderMesh.new()
	boden_mesh.top_radius = RADIUS + 0.5
	boden_mesh.bottom_radius = RADIUS + 0.5
	boden_mesh.height = 0.12
	var boden_mat := StandardMaterial3D.new()
	boden_mat.albedo_color = Color("#F2C14E")
	boden_mesh.material = boden_mat
	boden.mesh = boden_mesh
	_teller.add_child(boden)
	var mast := MeshInstance3D.new()
	var mast_mesh := CylinderMesh.new()
	mast_mesh.top_radius = 0.16
	mast_mesh.bottom_radius = 0.16
	mast_mesh.height = 3.0
	var mast_mat := StandardMaterial3D.new()
	mast_mat.albedo_color = Color("#E8524A")
	mast_mesh.material = mast_mat
	mast.mesh = mast_mesh
	mast.position.y = 1.5
	_teller.add_child(mast)
	var dach := MeshInstance3D.new()
	var dach_mesh := CylinderMesh.new()
	dach_mesh.top_radius = 0.1
	dach_mesh.bottom_radius = RADIUS + 0.7
	dach_mesh.height = 0.9
	var dach_mat := StandardMaterial3D.new()
	dach_mat.albedo_color = Color("#F781B0")
	dach_mesh.material = dach_mat
	dach.mesh = dach_mesh
	dach.position.y = 3.3
	_teller.add_child(dach)


func _baue_ponys() -> void:
	for i in 4:
		var winkel := TAU * float(i) / 4.0
		var pony := Node3D.new()
		pony.name = "Pony%d" % i
		pony.position = Vector3(cos(winkel) * RADIUS, 0.55, sin(winkel) * RADIUS)
		pony.rotation.y = -winkel
		_teller.add_child(pony)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = PONY_FARBEN[i]
		var koerper := MeshInstance3D.new()
		var kapsel := CapsuleMesh.new()
		kapsel.radius = 0.22
		kapsel.height = 0.9
		kapsel.material = mat
		koerper.mesh = kapsel
		koerper.rotation.x = PI / 2.0
		pony.add_child(koerper)
		var kopf := MeshInstance3D.new()
		var kugel := SphereMesh.new()
		kugel.radius = 0.18
		kugel.height = 0.36
		kugel.material = mat
		kopf.mesh = kugel
		kopf.position = Vector3(0.0, 0.25, 0.42)
		pony.add_child(kopf)
		var stange := MeshInstance3D.new()
		var stangen_mesh := CylinderMesh.new()
		stangen_mesh.top_radius = 0.04
		stangen_mesh.bottom_radius = 0.04
		stangen_mesh.height = 2.6
		var stangen_mat := StandardMaterial3D.new()
		stangen_mat.albedo_color = Color("#F0EFE9")
		stangen_mesh.material = stangen_mat
		stange.mesh = stangen_mesh
		stange.position = Vector3(0.0, 1.0, 0.0)
		pony.add_child(stange)
		_ponys.append(pony)


## Noten-Partikel überm Dach (EVAL B §5): ein GPUParticles3D mit einem
## Mini-Noten-Mesh (Kugel-Kopf + Hals) — steigt sacht auf und dreht sich,
## als würde die Karussell-Orgel spielen. Ein Draw-Call, 6 Partikel.
func _baue_noten() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var kopf := SphereMesh.new()
	kopf.radius = 0.11
	kopf.height = 0.22
	kopf.radial_segments = 8
	kopf.rings = 4
	st.append_from(kopf, 0, Transform3D(Basis.IDENTITY, Vector3.ZERO))
	var hals := BoxMesh.new()
	hals.size = Vector3(0.035, 0.42, 0.035)
	st.append_from(hals, 0, Transform3D(Basis.IDENTITY, Vector3(0.09, 0.21, 0.0)))
	var fahne_mesh := BoxMesh.new()
	fahne_mesh.size = Vector3(0.14, 0.08, 0.035)
	st.append_from(fahne_mesh, 0, Transform3D(Basis.IDENTITY, Vector3(0.16, 0.38, 0.0)))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#F781B0")
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var noten := GPUParticles3D.new()
	noten.name = "Noten"
	noten.amount = 6
	noten.lifetime = 3.2
	noten.visibility_aabb = AABB(Vector3(-4.0, -1.0, -4.0), Vector3(8.0, 8.0, 8.0))
	noten.draw_pass_1 = st.commit()
	noten.draw_pass_1.surface_set_material(0, mat)
	var prozess := ParticleProcessMaterial.new()
	prozess.gravity = Vector3(0.0, 0.55, 0.0)
	prozess.initial_velocity_min = 0.25
	prozess.initial_velocity_max = 0.5
	prozess.direction = Vector3(0.0, 1.0, 0.0)
	prozess.spread = 30.0
	prozess.angular_velocity_min = -90.0
	prozess.angular_velocity_max = 90.0
	prozess.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	prozess.emission_sphere_radius = 1.4
	prozess.scale_min = 0.8
	prozess.scale_max = 1.3
	noten.process_material = prozess
	noten.position = Vector3(0.0, 4.2, 0.0)
	add_child(noten)
