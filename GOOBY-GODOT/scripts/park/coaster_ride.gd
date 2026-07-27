class_name CoasterRide
extends Node3D
## Funkel-Looping — Szene-Knoten (REST-4): rendert die PURE CoasterLogic-
## Simulation 1:1. Baut die Strecke als EIN Ribbon-Mesh (SurfaceTool) plus
## Stützen-MultiMesh (Draw-Call-Budget), einen 2-Wagen-Zug und die
## POV-Verfolgerkamera am vorderen Wagen. Gooby sitzt als ECHTES Kind im
## vorderen Wagen (feste Sitz-Transformation, jeden Physik-Frame nachgezogen)
## — er kann konstruktionsbedingt nicht aus der Gondel fallen (der gemeldete
## Fehler des Vorgänger-Branches). Tests fahren über `simuliere(dt)`
## deterministisch ohne Echtzeit durch die komplette Runde.

signal ride_event(id: String)
signal ride_finished

const SPUR_BREITE := 1.1
const SCHRITT_M := 0.6
const CART_GAP := 1.6
const SITZ_LOKAL := Vector3(0.0, 0.28, 0.0)
const WHEEE_HOLD_SEC := 1.5
const TRACK_FARBE := Color("#E8524A")
const CART_FARBEN: Array[Color] = [Color("#F2C14E"), Color("#4E79D6")]

var curve: Curve3D
var sim: Dictionary = {}
var faehrt := false
var rig: GoobyRig

var _carts: Array[Node3D] = []
var _cam: Camera3D
var _cam_vorher: Camera3D
var _hands_up := false
var _hands_zeit := 0.0
var _wheee_gebucht := false


func _ready() -> void:
	curve = CoasterLogic.make_curve()
	sim = CoasterLogic.neu(curve)
	_baue_strecke()
	_baue_station()
	_baue_zug()
	_setze_zug(0.0)


func _physics_process(delta: float) -> void:
	if faehrt:
		simuliere(delta)


## Fahrt starten: Kamera auf den POV-Verfolger, Gooby setzt sich.
func starte_fahrt() -> void:
	sim = CoasterLogic.neu(curve)
	faehrt = true
	_wheee_gebucht = false
	_hands_zeit = 0.0
	var viewport := get_viewport()
	_cam_vorher = viewport.get_camera_3d() if viewport != null else null
	if _cam != null:
		_cam.current = true
	if rig != null:
		rig.visible = true
		rig.play_clip("sit")


## Deterministischer Simulationsschritt (auch der Test-Einstieg): rückt die
## Wagen, feuert Events, zählt Hände-hoch-Momente.
func simuliere(delta: float) -> void:
	if sim.is_empty() or bool(sim["done"]):
		return
	var events := CoasterLogic.step(sim, delta)
	_setze_zug(float(sim["s"]))
	_zaehle_hands_up(delta)
	for event in events:
		ride_event.emit(event)
		if event == "done":
			_fahrt_beendet()


## „Hände hoch“ halten (HUD-Knopf) — zählt in den erlaubten Zonen.
func set_hands_up(an: bool) -> void:
	_hands_up = an
	if rig == null:
		return
	if an:
		rig.play_clip("wave")


func zone_jetzt() -> String:
	if sim.is_empty():
		return "station"
	return CoasterLogic.zone_bei(sim, float(sim["s"]))


## Sitz-Distanz Gooby ↔ Wagen (Gondel-Test: bleibt konstant klein).
func gooby_sitz_abstand() -> float:
	if rig == null or _carts.is_empty():
		return 0.0
	return rig.global_position.distance_to(_carts[0].to_global(SITZ_LOKAL))


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
	ride_finished.emit()


func _zaehle_hands_up(delta: float) -> void:
	if not _hands_up or _wheee_gebucht:
		return
	if not CoasterLogic.hands_up_erlaubt(zone_jetzt()):
		_hands_zeit = 0.0
		return
	_hands_zeit += delta
	if _hands_zeit >= WHEEE_HOLD_SEC:
		_wheee_gebucht = true
		ride_event.emit("wheee")


## ---------------------------------------------------------------- Aufbau


func _baue_strecke() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var laenge := curve.get_baked_length()
	var schritte := int(ceil(laenge / SCHRITT_M))
	var halb := SPUR_BREITE * 0.5
	for i in schritte:
		var s0 := float(i) * laenge / float(schritte)
		var s1 := float(i + 1) * laenge / float(schritte)
		var t0 := curve.sample_baked_with_rotation(s0, false, true)
		var t1 := curve.sample_baked_with_rotation(s1, false, true)
		var l0 := t0.origin + t0.basis.x * halb
		var r0 := t0.origin - t0.basis.x * halb
		var l1 := t1.origin + t1.basis.x * halb
		var r1 := t1.origin - t1.basis.x * halb
		var n0 := t0.basis.y
		var n1 := t1.basis.y
		st.set_normal(n0)
		st.add_vertex(l0)
		st.set_normal(n0)
		st.add_vertex(r0)
		st.set_normal(n1)
		st.add_vertex(r1)
		st.set_normal(n0)
		st.add_vertex(l0)
		st.set_normal(n1)
		st.add_vertex(r1)
		st.set_normal(n1)
		st.add_vertex(l1)
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = TRACK_FARBE
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.7
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "Strecke"
	mi.mesh = mesh
	add_child(mi)
	_baue_stuetzen()


## Stützen unter der Strecke als EIN MultiMesh (ein Draw-Call).
func _baue_stuetzen() -> void:
	var laenge := curve.get_baked_length()
	var transforms: Array[Transform3D] = []
	var s := 0.0
	while s < laenge:
		var punkt := curve.sample_baked(s)
		if punkt.y > 1.6:
			var hoehe := punkt.y - 0.1
			var t := Transform3D.IDENTITY
			t = t.scaled(Vector3(1.0, hoehe, 1.0))
			t.origin = Vector3(punkt.x, hoehe * 0.5, punkt.z)
			transforms.append(t)
		s += 5.0
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var zylinder := CylinderMesh.new()
	zylinder.top_radius = 0.14
	zylinder.bottom_radius = 0.18
	zylinder.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#F0EFE9")
	zylinder.material = mat
	mm.mesh = zylinder
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Stuetzen"
	mmi.multimesh = mm
	add_child(mmi)


func _baue_station() -> void:
	var plattform := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(9.0, 0.5, 3.2)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color("#B98A62")
	box.material = mat
	plattform.mesh = box
	plattform.position = Vector3(-10.0, 0.25, 12.2)
	add_child(plattform)
	var dach := MeshInstance3D.new()
	var dach_box := BoxMesh.new()
	dach_box.size = Vector3(9.0, 0.24, 4.6)
	var dach_mat := StandardMaterial3D.new()
	dach_mat.albedo_color = Color("#E8524A")
	dach_box.material = dach_mat
	dach.mesh = dach_box
	dach.position = Vector3(-10.0, 3.4, 11.0)
	add_child(dach)


func _baue_zug() -> void:
	for i in 2:
		var cart := Node3D.new()
		cart.name = "Cart%d" % i
		add_child(cart)
		var rumpf := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.9, 0.5, 1.3)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = CART_FARBEN[i % CART_FARBEN.size()]
		box.material = mat
		rumpf.mesh = box
		rumpf.position = Vector3(0.0, 0.25, 0.0)
		cart.add_child(rumpf)
		var lehne := MeshInstance3D.new()
		var lehne_box := BoxMesh.new()
		lehne_box.size = Vector3(0.9, 0.42, 0.2)
		lehne_box.material = mat
		lehne.mesh = lehne_box
		lehne.position = Vector3(0.0, 0.55, 0.55)
		cart.add_child(lehne)
		_carts.append(cart)
	rig = GoobyRig.new()
	rig.position = SITZ_LOKAL
	rig.scale = Vector3.ONE * 0.62
	# Unsichtbar bis zur Fahrt — der Park hat EINEN Plaza-Gooby, der beim
	# Einsteigen "in den Wagen wechselt" (starte_fahrt blendet um).
	rig.visible = false
	_carts[0].add_child(rig)
	_cam = Camera3D.new()
	_cam.name = "PovCam"
	# Wagen-lokal: +Z ist Fahrtrichtung — der Verfolger sitzt dahinter (-Z).
	_cam.position = Vector3(0.0, CoasterLogic.CAM_UP, -CoasterLogic.CAM_BACK)
	_cam.fov = 78.0
	_carts[0].add_child(_cam)


## Zug (beide Wagen) an Bogenlänge s setzen; Gooby-Sitz nachziehen.
func _setze_zug(s: float) -> void:
	var laenge := curve.get_baked_length()
	for i in _carts.size():
		var offset := fposmod(s - float(i) * CART_GAP, laenge)
		var t := curve.sample_baked_with_rotation(offset, false, true)
		# Kurven-Basis blickt mit -Z voraus; Wagen-+Z soll Fahrtrichtung sein.
		_carts[i].global_transform = Transform3D(
			t.basis * Basis(Vector3.UP, PI), t.origin + t.basis.y * 0.15
		)
	if rig != null:
		rig.position = SITZ_LOKAL
		rig.rotation = Vector3.ZERO
	if _cam != null and not _carts.is_empty():
		var vorn := _carts[0]
		var blick_s := fposmod(s + CoasterLogic.CAM_LOOKAHEAD, laenge)
		var ziel := curve.sample_baked(blick_s)
		var auge := vorn.to_global(Vector3(0.0, CoasterLogic.CAM_UP, -CoasterLogic.CAM_BACK))
		var oben := vorn.global_transform.basis.y
		if auge.distance_squared_to(ziel) > 0.01:
			_cam.look_at_from_position(auge, ziel + oben * 0.5, oben)
