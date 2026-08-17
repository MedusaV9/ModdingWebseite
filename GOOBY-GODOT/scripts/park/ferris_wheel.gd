class_name FerrisWheel
extends Node3D
## Riesenrad (REST-4, Web-Vorbild GOOBY/src/park/ferrisWheel.js): sanfte
## Runde hoch über den Funkelpark. Rad = Felge (TorusMesh) + Speichen
## (EIN MultiMesh) + 8 Pastell-Gondeln; die Gondeln hängen als Kinder des
## Rades und werden jeden Frame AUFRECHT gehalten (Gegenrotation) — Gooby
## sitzt als echtes Kind in Gondel 0 und kann nicht herausfallen.
## `speed_scale` beschleunigt Tests/Screenshots deterministisch.

signal ride_event(id: String)
signal ride_finished

const RADIUS := 6.5
const NABE_HOEHE := 7.6
const GONDELN := 8
const GONDEL_FARBEN: Array[Color] = [
	Color("#F781B0"),
	Color("#9BD7E8"),
	Color("#F2C14E"),
	Color("#8FD06C"),
	Color("#B58CE4"),
	Color("#E8524A"),
	Color("#4E79D6"),
	Color("#FFD166"),
]
## Eine Runde (rad/s) — ca. 26 s Fahrt.
const TEMPO := 0.24
const RUNDEN := 1.0
## Leerlauf-Drehung (EVAL B §5 „Riesenrad dreht"): das Rad dreht auch ohne
## Fahrgast gemütlich weiter — Park wirkt in Betrieb statt eingefroren.
const IDLE_TEMPO := 0.05

var speed_scale := 1.0
var faehrt := false
## Leerlauf abschaltbar (Tests frieren das Rad deterministisch ein).
var idle_dreht := true
var rig: GoobyRig

var _rad: Node3D
var _gondeln: Array[Node3D] = []
var _winkel := 0.0
var _gefahren := 0.0
var _apex_gefeuert := false
var _cam: Camera3D
var _cam_vorher: Camera3D


func _ready() -> void:
	_baue_gestell()
	_baue_rad()
	_baue_gondeln()
	_setze_rad()


func _physics_process(delta: float) -> void:
	if faehrt:
		simuliere(delta)
	elif idle_dreht:
		_winkel += IDLE_TEMPO * delta
		_setze_rad()


func starte_fahrt() -> void:
	faehrt = true
	_gefahren = 0.0
	_apex_gefeuert = false
	var viewport := get_viewport()
	_cam_vorher = viewport.get_camera_3d() if viewport != null else null
	if _cam != null:
		_cam.current = true
	if rig != null:
		rig.visible = true
		rig.play_clip("sit")
	ride_event.emit("board")


## Deterministischer Schritt (Test-Einstieg): dreht das Rad, hält Gondeln
## aufrecht, feuert apex/done.
func simuliere(delta: float) -> void:
	if not faehrt:
		return
	var schritt := TEMPO * speed_scale * delta
	_winkel += schritt
	_gefahren += schritt
	_setze_rad()
	var ziel := RUNDEN * TAU
	if not _apex_gefeuert and _gefahren >= ziel * 0.5:
		_apex_gefeuert = true
		if rig != null:
			rig.play_clip("wave")
		ride_event.emit("apex")
	if _gefahren >= ziel:
		_fahrt_beendet()


func gooby_gondel() -> Node3D:
	return _gondeln[0] if not _gondeln.is_empty() else null


## Gondel-Test: Abstand Gooby ↔ Gondel-Sitz bleibt konstant klein.
func gooby_sitz_abstand() -> float:
	var gondel := gooby_gondel()
	if rig == null or gondel == null:
		return 0.0
	return rig.global_position.distance_to(gondel.to_global(Vector3(0.0, 0.1, 0.0)))


func kamera() -> Camera3D:
	return _cam


func _fahrt_beendet() -> void:
	faehrt = false
	if _cam_vorher != null and is_instance_valid(_cam_vorher):
		_cam_vorher.current = true
	elif _cam != null:
		_cam.current = false
	if rig != null:
		rig.play_clip("celebrate")
		rig.visible = false
	ride_event.emit("done")
	ride_finished.emit()


## ---------------------------------------------------------------- Aufbau


func _baue_gestell() -> void:
	for seite: float in [-1.0, 1.0]:
		var bein := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.35, NABE_HOEHE, 0.35)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color("#F0EFE9")
		box.material = mat
		bein.mesh = box
		bein.position = Vector3(0.0, NABE_HOEHE * 0.5, seite * 1.1)
		bein.rotation.x = seite * 0.16
		add_child(bein)


func _baue_rad() -> void:
	_rad = Node3D.new()
	_rad.name = "Rad"
	_rad.position = Vector3(0.0, NABE_HOEHE, 0.0)
	add_child(_rad)
	var felge := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = RADIUS - 0.14
	torus.outer_radius = RADIUS + 0.14
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#F2C14E")
	torus.material = mat
	felge.mesh = torus
	# Torus liegt in XZ — fürs stehende Rad um X kippen (Radebene = XY).
	felge.rotation.x = PI / 2.0
	_rad.add_child(felge)
	var nabe := MeshInstance3D.new()
	var zyl := CylinderMesh.new()
	zyl.top_radius = 0.4
	zyl.bottom_radius = 0.4
	zyl.height = 1.4
	var nabe_mat := StandardMaterial3D.new()
	nabe_mat.albedo_color = Color("#E8524A")
	zyl.material = nabe_mat
	nabe.mesh = zyl
	nabe.rotation.x = PI / 2.0
	_rad.add_child(nabe)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var speiche := BoxMesh.new()
	speiche.size = Vector3(0.1, RADIUS, 0.1)
	var speichen_mat := StandardMaterial3D.new()
	speichen_mat.albedo_color = Color("#F0EFE9")
	speiche.material = speichen_mat
	mm.mesh = speiche
	mm.instance_count = GONDELN
	for i in GONDELN:
		var winkel := TAU * float(i) / float(GONDELN)
		var t := Transform3D(Basis(Vector3.FORWARD, winkel), Vector3.ZERO)
		t.origin = t.basis.y * RADIUS * 0.5
		mm.set_instance_transform(i, t)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	_rad.add_child(mmi)
	_baue_felgen_lichter()


## Bunte Birnchen auf der Felge (EVAL B §4 „Fahrgeschäfte mit Lichtern"):
## EIN MultiMesh, dreht als Kind des Rads mit — leicht emissiv, damit die
## Punkte auch tagsüber als Kirmes-Deko lesen (nachts funkeln sie).
func _baue_felgen_lichter() -> void:
	var kugel := SphereMesh.new()
	kugel.radius = 0.16
	kugel.height = 0.32
	kugel.radial_segments = 8
	kugel.rings = 4
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	kugel.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = kugel
	mm.instance_count = 16
	for i in 16:
		var winkel := TAU * float(i) / 16.0
		var pos := Vector3(cos(winkel), sin(winkel), 0.0) * RADIUS
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, pos))
		mm.set_instance_color(i, GONDEL_FARBEN[i % GONDEL_FARBEN.size()].lightened(0.25))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "FelgenLichter"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rad.add_child(mmi)


func _baue_gondeln() -> void:
	for i in GONDELN:
		var gondel := Node3D.new()
		gondel.name = "Gondel%d" % i
		_rad.add_child(gondel)
		var korb := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.1, 0.7, 0.9)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = GONDEL_FARBEN[i % GONDEL_FARBEN.size()]
		box.material = mat
		korb.mesh = box
		korb.position = Vector3(0.0, -0.1, 0.0)
		gondel.add_child(korb)
		var dach := MeshInstance3D.new()
		var dach_mesh := CylinderMesh.new()
		dach_mesh.top_radius = 0.05
		dach_mesh.bottom_radius = 0.75
		dach_mesh.height = 0.5
		dach_mesh.material = mat
		dach.mesh = dach_mesh
		dach.position = Vector3(0.0, 0.85, 0.0)
		gondel.add_child(dach)
		_gondeln.append(gondel)
	rig = GoobyRig.new()
	# 0.8 statt 0.6: Kopf + Ohren gucken über den Korbrand (Korb-Oberkante
	# y=0.25), bleiben aber unter dem Dach (Unterkante y=0.6) — sichtbar,
	# ohne zu clippen.
	rig.scale = Vector3.ONE * 0.8
	rig.position = Vector3(0.0, 0.1, 0.0)
	# Unsichtbar bis zur Fahrt (ein Plaza-Gooby, s. coaster_ride.gd).
	rig.visible = false
	_gondeln[0].add_child(rig)
	_cam = Camera3D.new()
	_cam.name = "GondelCam"
	_cam.position = Vector3(0.0, 0.9, 1.6)
	_cam.fov = 72.0
	_gondeln[0].add_child(_cam)
	_cam.look_at_from_position(
		_gondeln[0].to_global(Vector3(0.0, 0.9, 1.6)),
		_gondeln[0].to_global(Vector3(0.0, 0.3, -4.0)),
		Vector3.UP
	)


## Gondel-Positionen am Rad + AUFRECHT-Haltung (Gegenrotation zum Rad).
func _setze_rad() -> void:
	_rad.rotation = Vector3(0.0, 0.0, _winkel)
	for i in _gondeln.size():
		var winkel := TAU * float(i) / float(GONDELN)
		_gondeln[i].position = Vector3(cos(winkel), sin(winkel), 0.0) * RADIUS
		# global aufrecht: Gondel-Basis = Identität in Weltkoordinaten.
		_gondeln[i].global_rotation = Vector3.ZERO
	if rig != null:
		rig.position = Vector3(0.0, 0.1, 0.0)
		rig.rotation = Vector3.ZERO
