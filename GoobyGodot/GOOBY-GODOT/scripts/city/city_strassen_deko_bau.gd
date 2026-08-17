class_name CityStrassenDekoBau
extends RefCounted
## Baut den CityStrassenDeko-Plan als echte Nodes (GOOBY-WELT/STADT, EVAL B
## §2 „mehr Leben und Vielfalt"): Zebrastreifen als EIN MultiMesh, Mülltonnen
## als zwei Instanzfarben-MultiMeshes (Tonne + Deckel), Tauben als EIN
## MultiMesh (Körper+Kopf-Kugeln, Pick-Neigung in der Transform), zwei
## Bushaltestellen-Häuschen und die Café-Terrasse am Stadtpark (Tische +
## Sonnenschirme + Bänke). Gesamtkosten ≈ 20 Draw-Calls — Budget ≤ 400.

const TONNEN_RADIUS := 0.36
const TONNEN_HOEHE := 0.95
const TAUBE := Color("#8D93A1")
const TAUBE_HELL := Color("#B9BEC9")

var _bau: CityBau


func _init(bau: CityBau) -> void:
	_bau = bau


func baue(szene: Node3D, karte: CityMap) -> void:
	var wurzel := Node3D.new()
	wurzel.name = "Strassenbild"
	szene.add_child(wurzel)
	_baue_zebras(wurzel, karte)
	_baue_tonnen(wurzel, karte)
	_baue_tauben(wurzel, karte)
	for eintrag in CityStrassenDeko.bushaltestellen(karte):
		_baue_haltestelle(wurzel, eintrag)
	_baue_cafe(wurzel, karte)


## ------------------------------------------------------------ MultiMeshes


func _baue_zebras(wurzel: Node3D, karte: CityMap) -> void:
	var transforms := CityStrassenDeko.zebra_transforms(karte)
	if transforms.is_empty():
		return
	var box := BoxMesh.new()
	box.size = CityStrassenDeko.ZEBRA_MASS
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.94, 0.94, 0.9)
	mat.roughness = 0.9
	box.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = box
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Zebrastreifen"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wurzel.add_child(mmi)


func _baue_tonnen(wurzel: Node3D, karte: CityMap) -> void:
	var tonnen := CityStrassenDeko.muelltonnen(karte)
	if tonnen.is_empty():
		return
	var koerper := CylinderMesh.new()
	koerper.top_radius = TONNEN_RADIUS
	koerper.bottom_radius = TONNEN_RADIUS - 0.05
	koerper.height = TONNEN_HOEHE
	koerper.radial_segments = 10
	var deckel := CylinderMesh.new()
	deckel.top_radius = TONNEN_RADIUS - 0.06
	deckel.bottom_radius = TONNEN_RADIUS + 0.05
	deckel.height = 0.14
	deckel.radial_segments = 10
	for teil: Array in [
		[koerper, TONNEN_HOEHE * 0.5, "Tonnen"], [deckel, TONNEN_HOEHE + 0.06, "Deckel"]
	]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = teil[0]
		(teil[0] as Mesh).surface_set_material(0, _instanzfarben_material())
		mm.instance_count = tonnen.size()
		for i in tonnen.size():
			var eintrag: Dictionary = tonnen[i]
			var basis := Basis(Vector3.UP, float(eintrag["rot"]))
			var pos: Vector3 = eintrag["pos"] + Vector3(0.0, float(teil[1]), 0.0)
			mm.set_instance_transform(i, Transform3D(basis, pos))
			var farbe: Color = eintrag["farbe"]
			mm.set_instance_color(i, farbe if String(teil[2]) == "Tonnen" else farbe.darkened(0.25))
		var mmi := MultiMeshInstance3D.new()
		mmi.name = String(teil[2])
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mmi.visibility_range_end = CityBau.KLEINTEIL_SICHT_M
		wurzel.add_child(mmi)


## Tauben-Grüppchen: Körper (gestreckte Kugel) + Kopf (kleine Kugel) landen
## im SELBEN MultiMesh — pickende Tauben neigen sich per Transform nach vorn.
func _baue_tauben(wurzel: Node3D, karte: CityMap) -> void:
	var tauben := CityStrassenDeko.tauben(karte, karte.deko_seed() + 4711)
	if tauben.is_empty():
		return
	var kugel := SphereMesh.new()
	kugel.radius = 1.0
	kugel.height = 2.0
	kugel.radial_segments = 10
	kugel.rings = 5
	kugel.material = _instanzfarben_material()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = kugel
	mm.instance_count = tauben.size() * 2
	for i in tauben.size():
		var eintrag: Dictionary = tauben[i]
		var pickt := bool(eintrag["pickt"])
		var rot := float(eintrag["rot"])
		var basis := Basis(Vector3.UP, rot)
		if pickt:
			basis = basis * Basis(Vector3.RIGHT, 0.5)
		var pos: Vector3 = eintrag["pos"]
		# Lokal skalieren (Körper länger als breit) — scaled() wäre global.
		var koerper := basis * Basis.from_scale(Vector3(0.13, 0.11, 0.18))
		mm.set_instance_transform(i * 2, Transform3D(koerper, pos + Vector3(0.0, 0.12, 0.0)))
		var kopf := basis.scaled(Vector3(0.07, 0.07, 0.07))
		var kopf_lokal := Vector3(0.0, 0.1 if pickt else 0.2, 0.16)
		mm.set_instance_transform(i * 2 + 1, Transform3D(kopf, pos + basis * kopf_lokal))
		var ton := TAUBE if i % 3 != 0 else TAUBE_HELL
		mm.set_instance_color(i * 2, ton)
		mm.set_instance_color(i * 2 + 1, ton.darkened(0.2))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Tauben"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visibility_range_end = 110.0
	wurzel.add_child(mmi)


## --------------------------------------------------------- Einzel-Bauten


## Bushaltestelle: zwei Pfosten + Dach + Glasrückwand + Bank + H-Schild —
## kleine, lesbare Wartehäuschen an Markt- und Parkstrecke.
func _baue_haltestelle(wurzel: Node3D, eintrag: Dictionary) -> void:
	var halte := Node3D.new()
	halte.name = "Bushaltestelle"
	halte.position = eintrag["pos"]
	halte.rotation.y = float(eintrag["rot"])
	wurzel.add_child(halte)
	for seite: float in [-1.55, 1.55]:
		_box(halte, Vector3(seite, 1.25, -0.6), Vector3(0.14, 2.5, 0.14), "#5B6470")
	_box(halte, Vector3(0.0, 2.56, -0.25), Vector3(3.6, 0.12, 1.7), "#E8524A")
	var glas := _box(halte, Vector3(0.0, 1.3, -0.72), Vector3(3.3, 1.9, 0.06), "#BFD9E4")
	glas.material_override = _glas_material()
	_box(halte, Vector3(0.0, 0.55, -0.42), Vector3(2.6, 0.1, 0.5), "#C89A6A")
	for seite: float in [-1.1, 1.1]:
		_box(halte, Vector3(seite, 0.27, -0.42), Vector3(0.1, 0.55, 0.4), "#5B6470")
	_box(halte, Vector3(1.9, 1.5, 0.2), Vector3(0.08, 3.0, 0.08), "#5B6470")
	var schild := _box(halte, Vector3(1.9, 2.8, 0.2), Vector3(0.62, 0.62, 0.1), "#F2C14E")
	schild.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var text := Label3D.new()
	text.text = I18nService.t("stadt.bus.schild")
	text.font_size = 96
	text.pixel_size = 0.004
	text.modulate = Color("#2E3440")
	text.position = Vector3(1.9, 2.8, 0.26)
	halte.add_child(text)


## Café-Terrasse am Stadtpark: zwei runde Tische mit Sonnenschirmen, Bänke,
## Pflanzkübel und ein kleines Namensschild („Café Krümel").
func _baue_cafe(wurzel: Node3D, karte: CityMap) -> void:
	var plan := CityStrassenDeko.cafe(karte)
	if plan.is_empty():
		return
	var cafe := Node3D.new()
	cafe.name = "CafeTerrasse"
	cafe.position = plan["pos"]
	cafe.rotation.y = float(plan["rot"])
	wurzel.add_child(cafe)
	var schirm_farben: Array[String] = ["#E8524A", "#F2C14E"]
	for i in 2:
		var x := -2.2 + float(i) * 4.4
		var tisch := _bau.lade_glb("%s/innen/table_round_A.gltf" % CityBau.ASSETS, 0.85)
		if tisch != null:
			tisch.position = Vector3(x, 0.0, -1.4)
			cafe.add_child(tisch)
		_zyl(cafe, Vector3(x, 1.6, -1.4), 0.04, 3.2, "#F0EFE9")
		var schirm := _zyl(cafe, Vector3(x, 2.9, -1.4), 1.5, 0.55, schirm_farben[i])
		(schirm.mesh as CylinderMesh).top_radius = 0.06
	for seite: float in [-1.0, 1.0]:
		var bank := _bau.lade_glb("%s/deko/bench.gltf" % CityBau.ASSETS, 4.5)
		if bank != null:
			bank.position = Vector3(3.4 * seite, 0.0, 0.4)
			bank.rotation.y = PI
			cafe.add_child(bank)
	var kuebel := _bau.lade_glb("%s/vorstadt/planter.glb" % CityBau.ASSETS, 4.0)
	if kuebel != null:
		kuebel.position = Vector3(0.0, 0.0, 0.8)
		cafe.add_child(kuebel)
	var schild := Label3D.new()
	schild.text = I18nService.t("stadt.cafe.name")
	schild.font_size = 110
	schild.pixel_size = 0.006
	schild.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	schild.modulate = Color("#5B4636")
	schild.outline_size = 18
	schild.outline_modulate = Color(1.0, 0.98, 0.92)
	schild.position = Vector3(0.0, 3.9, -1.4)
	cafe.add_child(schild)


## ------------------------------------------------------------ Werkzeuge


func _box(halter: Node3D, pos: Vector3, mass: Vector3, farbe: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = mass
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(farbe)
	mat.roughness = 0.85
	box.material = mat
	mi.mesh = box
	mi.position = pos
	halter.add_child(mi)
	return mi


func _zyl(
	halter: Node3D, pos: Vector3, radius: float, hoehe: float, farbe: String
) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var zyl := CylinderMesh.new()
	zyl.top_radius = radius
	zyl.bottom_radius = radius
	zyl.height = hoehe
	zyl.radial_segments = 12
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(farbe)
	mat.roughness = 0.85
	zyl.material = mat
	mi.mesh = zyl
	mi.position = pos
	halter.add_child(mi)
	return mi


func _glas_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.85, 0.9, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.2
	return mat


func _instanzfarben_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.85
	return mat
