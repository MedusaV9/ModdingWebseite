class_name ParkDekoBau
extends RefCounted
## Baut den ParkDeko-Plan als echte Nodes (GOOBY-WELT/STADT, EVAL B §4):
## Parkzaun, Schachbrett-Weg, Wimpelketten (EIN vertexgefärbtes Mesh),
## Konfetti, Ballon-Stand mit Verkäufer, Warteschlangen-Pfosten mit Kordel
## und Wiesen-Grün aus dem Stadt-Naturkit — alles MultiMesh/SurfaceTool,
## zusammen ~25 Draw-Calls (Budget ≤ 400 bleibt weit unterschritten).

const ASSETS := "res://assets/city"

const CREME := Color("#F0EFE9")
const ROSA := Color("#F781B0")
const HOLZ := Color("#C89A6A")
const PLATTE_HELL := Color("#E4D4B4")
const PLATTE_DUNKEL := Color("#D9C0A8")


## Kompletter Deko-Pass — hängt alles unter einen "ParkDeko"-Knoten.
static func baue(park: Node3D, seed_wert: int) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "ParkDeko"
	park.add_child(wurzel)
	_baue_zaun(wurzel)
	_baue_platten(wurzel, seed_wert)
	_baue_wimpel(wurzel)
	_baue_konfetti(wurzel, seed_wert + 17)
	_baue_schlangen(wurzel)
	_baue_gruen(wurzel, seed_wert + 33)
	return wurzel


## Ballon-Stand: Wägelchen + Mast + Bündel (MultiMesh) + Schnüre + Schild.
## Liefert den Bündel-Knoten für das sanfte Schaukeln (Funkelpark-Tick).
static func baue_ballon_stand(park: Node3D, seed_wert: int) -> Node3D:
	var stand := Node3D.new()
	stand.name = "BallonStand"
	stand.position = ParkDeko.BALLON_STAND
	park.add_child(stand)
	_box_bei(stand, Vector3(0.0, 0.62, 0.0), Vector3(1.3, 0.7, 0.9), CREME)
	_box_bei(stand, Vector3(0.0, 1.06, 0.0), Vector3(1.42, 0.18, 1.02), ROSA)
	for seite: float in [-1.0, 1.0]:
		var rad := _zyl_bei(stand, Vector3(0.55 * seite, 0.22, 0.5), 0.22, 0.1, Color("#5B4636"))
		rad.rotation.x = PI * 0.5
	_zyl_bei(stand, Vector3(0.0, 1.8, -0.2), 0.035, 1.6, Color("#C8D4DC"))
	var buendel := Node3D.new()
	buendel.name = "Ballons"
	buendel.position = Vector3(0.0, 0.0, -0.2)
	stand.add_child(buendel)
	var plan := ParkDeko.ballons(seed_wert)
	var kugel := SphereMesh.new()
	kugel.radius = 0.32
	kugel.height = 0.64
	kugel.radial_segments = 10
	kugel.rings = 5
	kugel.material = _farben_material()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = kugel
	mm.instance_count = plan.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var schnur := BoxMesh.new()
	schnur.size = Vector3(0.015, 1.0, 0.015)
	for i in plan.size():
		var off: Vector3 = plan[i]["off"]
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, off))
		mm.set_instance_color(i, plan[i]["farbe"])
		var ziel := Vector3(0.0, 2.6, 0.0)
		var mitte := (off - Vector3(0.0, 0.3, 0.0) + ziel) * 0.5
		var d := (off - Vector3(0.0, 0.3, 0.0)) - ziel
		var basis := Basis.IDENTITY
		if d.length() > 0.01:
			var y := d.normalized()
			var x := y.cross(Vector3.FORWARD).normalized()
			if x.length() < 0.5:
				x = Vector3.RIGHT
			basis = Basis(x, y, x.cross(y))
			basis.y *= d.length()
		st.append_from(schnur, 0, Transform3D(basis, mitte))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "BallonKugeln"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	buendel.add_child(mmi)
	var schnuere := MeshInstance3D.new()
	schnuere.name = "Schnuere"
	schnuere.mesh = st.commit()
	schnuere.material_override = _flach_material(Color("#9AA0AC"))
	schnuere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	buendel.add_child(schnuere)
	var schild := Label3D.new()
	schild.text = I18nService.t("park_deko.ballons")
	schild.font_size = 72
	schild.pixel_size = 0.006
	schild.modulate = Color("#5B4636")
	schild.position = Vector3(0.0, 0.75, 0.52)
	stand.add_child(schild)
	var verkaeufer := blob(Color("#FFD166"))
	verkaeufer.position = Vector3(-1.1, 0.0, 0.3)
	verkaeufer.rotation.y = 0.6
	stand.add_child(verkaeufer)
	return buendel


## Pastell-Besucher-Blob (Kapsel + Kopf) — geteilt mit Funkelpark.
static func blob(farbe: Color) -> Node3D:
	var wurzel := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = farbe
	var koerper := MeshInstance3D.new()
	var kapsel := CapsuleMesh.new()
	kapsel.radius = 0.28
	kapsel.height = 0.9
	kapsel.material = mat
	koerper.mesh = kapsel
	koerper.position.y = 0.45
	wurzel.add_child(koerper)
	var kopf := MeshInstance3D.new()
	var kugel := SphereMesh.new()
	kugel.radius = 0.22
	kugel.height = 0.44
	kugel.material = mat
	kopf.mesh = kugel
	kopf.position.y = 1.05
	wurzel.add_child(kopf)
	return wurzel


## ---------------------------------------------------------------- intern


static func _baue_zaun(wurzel: Node3D) -> void:
	var posten := ParkDeko.zaun_posten()
	var pfahl := BoxMesh.new()
	pfahl.size = Vector3(0.14, 1.1, 0.14)
	pfahl.material = _flach_material(CREME)
	var pfahl_transforms: Array[Transform3D] = []
	var kugel_transforms: Array[Transform3D] = []
	for pos in posten:
		pfahl_transforms.append(Transform3D(Basis.IDENTITY, pos + Vector3(0.0, 0.55, 0.0)))
		kugel_transforms.append(
			Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * 0.11), pos + Vector3(0.0, 1.16, 0.0))
		)
	_multimesh(wurzel, "ZaunPfaehle", pfahl, pfahl_transforms)
	var kugel := SphereMesh.new()
	kugel.radius = 1.0
	kugel.height = 2.0
	kugel.radial_segments = 8
	kugel.rings = 4
	kugel.material = _flach_material(ROSA)
	_multimesh(wurzel, "ZaunKugeln", kugel, kugel_transforms)
	var riegel := BoxMesh.new()
	riegel.size = Vector3(0.06, 0.09, 1.0)
	riegel.material = _flach_material(CREME)
	_multimesh(wurzel, "ZaunRiegel", riegel, ParkDeko.zaun_riegel(posten))


static func _baue_platten(wurzel: Node3D, seed_wert: int) -> void:
	var platten := ParkDeko.weg_platten(seed_wert)
	var hell: Array[Transform3D] = []
	var dunkel: Array[Transform3D] = []
	for platte in platten:
		var t := Transform3D(Basis.IDENTITY, platte["pos"])
		if bool(platte["hell"]):
			hell.append(t)
		else:
			dunkel.append(t)
	for paar: Array in [
		[hell, PLATTE_HELL, "PlattenHell"], [dunkel, PLATTE_DUNKEL, "PlattenDunkel"]
	]:
		var box := BoxMesh.new()
		box.size = Vector3(ParkDeko.PLATTE_M - 0.14, 0.05, ParkDeko.PLATTE_M - 0.14)
		box.material = _flach_material(paar[1])
		_multimesh(wurzel, String(paar[2]), box, paar[0])


## Alle Wimpel-Dreiecke als EIN vertexgefärbtes Mesh (1 Draw-Call).
static func _baue_wimpel(wurzel: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for wimpel in ParkDeko.alle_wimpel():
		var pos: Vector3 = wimpel["pos"]
		var rot := float(wimpel["rot"])
		var laengs := Vector3(sin(rot), 0.0, cos(rot)) * 0.21
		var farbe: Color = wimpel["farbe"]
		st.set_color(farbe)
		st.set_normal(Vector3.UP)
		st.add_vertex(pos - laengs)
		st.set_color(farbe)
		st.set_normal(Vector3.UP)
		st.add_vertex(pos + laengs)
		st.set_color(farbe.darkened(0.12))
		st.set_normal(Vector3.UP)
		st.add_vertex(pos + Vector3(0.0, -0.48, 0.0))
	var mi := MeshInstance3D.new()
	mi.name = "Wimpel"
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wurzel.add_child(mi)


static func _baue_konfetti(wurzel: Node3D, seed_wert: int) -> void:
	var plan := ParkDeko.konfetti(seed_wert)
	var scheibe := CylinderMesh.new()
	scheibe.top_radius = 0.12
	scheibe.bottom_radius = 0.12
	scheibe.height = 0.02
	scheibe.radial_segments = 8
	scheibe.material = _farben_material()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = scheibe
	mm.instance_count = plan.size()
	for i in plan.size():
		var eintrag: Dictionary = plan[i]
		mm.set_instance_transform(
			i, Transform3D(Basis(Vector3.UP, float(eintrag["rot"])), eintrag["pos"])
		)
		mm.set_instance_color(i, eintrag["farbe"])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Konfetti"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wurzel.add_child(mmi)


## Warteschlangen: Pfosten (MultiMesh) + Kordel (EIN Mesh) + Schild +
## zwei wartende Blobs an der Coaster-Schlange.
static func _baue_schlangen(wurzel: Node3D) -> void:
	var pfosten_transforms: Array[Transform3D] = []
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var kordel := BoxMesh.new()
	kordel.size = Vector3(0.05, 0.05, 1.0)
	for schlange: Dictionary in ParkDeko.SCHLANGEN:
		var posten: Array = schlange["posten"]
		for i in posten.size():
			var pos: Vector3 = posten[i]
			pfosten_transforms.append(Transform3D(Basis.IDENTITY, pos + Vector3(0.0, 0.5, 0.0)))
			if i == 0:
				continue
			var vorher: Vector3 = posten[i - 1]
			var d: Vector3 = pos - vorher
			var mitte := (pos + vorher) * 0.5 + Vector3(0.0, 0.78, 0.0)
			var basis := Basis(Vector3.UP, atan2(d.x, d.z))
			basis.z *= d.length()
			st.append_from(kordel, 0, Transform3D(basis, mitte))
		var tafel := Label3D.new()
		tafel.text = I18nService.t("park_deko.warte")
		tafel.font_size = 56
		tafel.pixel_size = 0.006
		tafel.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		tafel.modulate = Color("#5B4636")
		tafel.outline_size = 12
		tafel.outline_modulate = Color(1.0, 0.98, 0.92)
		tafel.position = (schlange["schild"] as Vector3) + Vector3(0.0, 1.5, 0.0)
		wurzel.add_child(tafel)
	var pfosten := CylinderMesh.new()
	pfosten.top_radius = 0.055
	pfosten.bottom_radius = 0.075
	pfosten.height = 1.0
	pfosten.radial_segments = 8
	pfosten.material = _flach_material(Color("#F2C14E"))
	_multimesh(wurzel, "SchlangenPfosten", pfosten, pfosten_transforms)
	var kordeln := MeshInstance3D.new()
	kordeln.name = "Kordeln"
	kordeln.mesh = st.commit()
	kordeln.material_override = _flach_material(ROSA)
	kordeln.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wurzel.add_child(kordeln)
	var wartende: Array = ParkDeko.SCHLANGEN[0]["posten"]
	for i in 2:
		var warter := blob(ParkDeko.KONFETTI_FARBEN[i * 2])
		var pos: Vector3 = wartende[i]
		warter.position = pos + Vector3(0.35, 0.0, 0.55)
		warter.rotation.y = PI + float(i) * 0.5
		wurzel.add_child(warter)


## Wiesen-Grün: Blumen/Gras aus dem Stadt-Naturkit als MultiMesh-Gruppen.
static func _baue_gruen(wurzel: Node3D, seed_wert: int) -> void:
	var gruppen: Dictionary = {}
	for eintrag in ParkDeko.wiesen_gruen(seed_wert):
		var glb := str(eintrag["glb"])
		if not gruppen.has(glb):
			gruppen[glb] = [] as Array[Transform3D]
		var basis := Basis(Vector3.UP, float(eintrag["rot"]))
		basis = basis.scaled(Vector3.ONE * float(eintrag["scale"]))
		var liste: Array[Transform3D] = gruppen[glb]
		liste.append(Transform3D(basis, eintrag["pos"]))
	var schluessel: Array = gruppen.keys()
	schluessel.sort()
	for glb: String in schluessel:
		_glb_multimesh(wurzel, "%s/%s" % [ASSETS, glb], gruppen[glb])


## N Instanzen aller Meshes eines GLBs als MultiMesh (wie CityBau, mini).
static func _glb_multimesh(wurzel: Node3D, pfad: String, transforms: Array[Transform3D]) -> void:
	if transforms.is_empty() or not ResourceLoader.exists(pfad):
		return
	var szene: PackedScene = load(pfad)
	if szene == null:
		return
	var proto: Node3D = szene.instantiate()
	for mesh in proto.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = mesh
		var rel := Transform3D.IDENTITY
		var n: Node = mi
		while n != null and n != proto:
			if n is Node3D:
				rel = (n as Node3D).transform * rel
			n = n.get_parent()
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mi.mesh
		mm.instance_count = transforms.size()
		for i in transforms.size():
			mm.set_instance_transform(i, transforms[i] * rel)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "MM_%s" % pfad.get_file().get_basename()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wurzel.add_child(mmi)
	proto.free()


static func _multimesh(
	wurzel: Node3D, mm_name: String, mesh: Mesh, transforms: Array[Transform3D]
) -> void:
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = mm_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wurzel.add_child(mmi)


static func _box_bei(halter: Node3D, pos: Vector3, mass: Vector3, farbe: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = mass
	box.material = _flach_material(farbe)
	mi.mesh = box
	mi.position = pos
	halter.add_child(mi)
	return mi


static func _zyl_bei(
	halter: Node3D, pos: Vector3, radius: float, hoehe: float, farbe: Color
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var zyl := CylinderMesh.new()
	zyl.top_radius = radius
	zyl.bottom_radius = radius
	zyl.height = hoehe
	zyl.radial_segments = 10
	zyl.material = _flach_material(farbe)
	mi.mesh = zyl
	mi.position = pos
	halter.add_child(mi)
	return mi


static func _flach_material(farbe: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = farbe
	mat.roughness = 0.85
	return mat


static func _farben_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.8
	return mat
