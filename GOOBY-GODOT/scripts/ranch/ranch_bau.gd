class_name RanchBau
extends RefCounted
## Kulissen-Bauer der Gooby Ranch (RANCH-1, Muster CityBau): setzt die
## Pläne aus RanchWelt in Nodes um — Licht/Himmel (Tag/Nacht-Profil aus
## CityAmbiente wiederverwendet), Böden, Straße, MultiMesh-Gruppen für
## Zäune/Bäume/Gras/Feldfrüchte (ein Draw-Call je Mesh-Sorte, Budget ≤ 400
## in der Ranch-Ansicht) und die prozeduralen Pastell-Gebäude (Scheune,
## Stall, Ranch-Haus, Heulager, Windrad, Trog, Tor, Schilder).
## Gameplay bleibt in den Szenen; hier nur Statik + `colliders` als
## Bau-Ergebnis für den CarController.

const ASSETS := "res://assets/ranch"

## Pastell-Palette der Ranch (GOOBY-Stil).
const SCHEUNE_ROT := Color("#D96C57")
const HOLZ_HELL := Color("#E8C49A")
const HOLZ_DUNKEL := Color("#B58A5F")
const DACH_CREME := Color("#F2E9DC")
const DACH_TEAL := Color("#5FA8A0")
const HAUS_CREME := Color("#F2E3C9")
const HEU_GELB := Color("#E8C96E")
const WEG_GRAU := Color("#CBBFa6")
const WIESE_GRUEN := Color(0.58, 0.74, 0.46)
const WASSER_BLAU := Color(0.45, 0.68, 0.82, 0.85)
const SCHILD_INK := Color(0.24, 0.2, 0.16)

## Kleinteile (Gras/Blumen/Feldfrüchte) blenden ab dieser Distanz aus.
const KLEINTEIL_SICHT_M := 180.0

## Auto-Kollisions-AABBs {min_x, max_x, min_z, max_z} (Bau-Ergebnis).
var colliders: Array[Dictionary] = []

var _szene: Node3D
var _glb_mesh_cache: Dictionary = {}


func _init(szene: Node3D) -> void:
	_szene = szene


## Tag/Nacht-Licht + Himmel — 24-h-Kurve aus CityAmbiente (POLISH-8),
## damit die Ranch dieselbe Lichtstimmung wie die Stadt hat. Postprocessing
## bleibt mobil-tauglich: nur Sky-Ambient + EIN Ortho-Schatten-Split.
func baue_licht(stunde: float) -> Dictionary:
	var profil := CityAmbiente.licht_profil(stunde)
	var env := WorldEnvironment.new()
	env.name = "Umgebung"
	var e := Environment.new()
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = profil["himmel_oben"]
	sky_mat.sky_horizon_color = profil["himmel_horizont"]
	sky_mat.ground_horizon_color = profil["boden_horizont"]
	sky_mat.ground_bottom_color = profil["boden_unten"]
	sky.sky_material = sky_mat
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = profil["ambient_energie"]
	env.environment = e
	_szene.add_child(env)
	var sonne := DirectionalLight3D.new()
	sonne.name = "Sonne"
	sonne.shadow_enabled = true
	sonne.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	sonne.directional_shadow_max_distance = 190.0
	sonne.rotation_degrees = Vector3(-float(profil["elevation"]), -35.0, 0.0)
	sonne.light_color = profil["sonnen_farbe"]
	sonne.light_energy = profil["sonnen_energie"]
	_szene.add_child(sonne)
	return profil


## Große Wiesen-Bodenplatte (+ Rand, damit kein Horizont-Balken entsteht).
func baue_boden(breite: float, tiefe: float) -> void:
	var boden := MeshInstance3D.new()
	boden.name = "Boden"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(breite + 160.0, tiefe + 160.0)
	mesh.material = _mat(WIESE_GRUEN)
	boden.mesh = mesh
	_szene.add_child(boden)


## Landstraße entlang +z bei x=0 (Plate + Mittelstreifen als MultiMesh).
func baue_strasse(laenge: float, breite: float) -> void:
	var strasse := MeshInstance3D.new()
	strasse.name = "Strasse"
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(breite, laenge)
	mesh.material = _mat(Color(0.42, 0.4, 0.38))
	strasse.mesh = mesh
	strasse.position.y = 0.03
	_szene.add_child(strasse)
	var streifen := MultiMesh.new()
	streifen.transform_format = MultiMesh.TRANSFORM_3D
	var quad := BoxMesh.new()
	quad.size = Vector3(0.25, 0.02, 2.2)
	quad.material = _mat(Color(0.93, 0.9, 0.8))
	streifen.mesh = quad
	var anzahl := int(laenge / 6.0)
	streifen.instance_count = anzahl
	for i in anzahl:
		var t := Transform3D(
			Basis.IDENTITY, Vector3(0.0, 0.05, -laenge / 2.0 + 3.0 + float(i) * 6.0)
		)
		streifen.set_instance_transform(i, t)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "MM_Mittelstreifen"
	mmi.multimesh = streifen
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_szene.add_child(mmi)


## Schotterweg zwischen zwei Punkten (gedrehte Plate).
func baue_weg(von: Vector3, bis: Vector3, breite: float) -> void:
	var mitte := (von + bis) / 2.0
	var laenge := von.distance_to(bis)
	var weg := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(breite, laenge + breite)
	mesh.material = _mat(WEG_GRAU)
	weg.mesh = mesh
	weg.position = Vector3(mitte.x, 0.04, mitte.z)
	weg.rotation.y = atan2(bis.x - von.x, bis.z - von.z)
	_szene.add_child(weg)


## Feld-Patch (Acker/Weide) mit Pastellfarbe; optional Korn-Reihen darauf.
func baue_feld(wurzel: Node3D, pos: Vector3, groesse: Vector2, farbe: Color) -> void:
	var feld := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = groesse
	mesh.material = _mat(farbe)
	feld.mesh = mesh
	feld.position = Vector3(pos.x, 0.02, pos.z)
	wurzel.add_child(feld)


## N Instanzen eines GLBs als MultiMesh (Port des CityBau-Musters).
func baue_multimesh(
	wurzel: Node3D, pfad: String, transforms: Array, tint := "", sicht_ende := 0.0
) -> void:
	if transforms.is_empty():
		return
	var teile := _glb_meshes(pfad)
	if teile.is_empty():
		return
	var mitte := Vector3.ZERO
	for t: Transform3D in transforms:
		mitte += t.origin
	mitte /= float(transforms.size())
	for teil: Dictionary in teile:
		var mesh: Mesh = teil["mesh"]
		if not tint.is_empty():
			mesh = _getoentes_mesh(mesh, Color.from_string(tint, Color.WHITE))
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = transforms.size()
		var rel: Transform3D = teil["xform"]
		for i in transforms.size():
			var welt: Transform3D = (transforms[i] as Transform3D) * rel
			welt.origin -= mitte
			mm.set_instance_transform(i, welt)
		var mmi := MultiMeshInstance3D.new()
		mmi.name = "MM_%s" % pfad.get_file().get_basename()
		mmi.position = mitte
		mmi.multimesh = mm
		if sicht_ende > 0.0:
			mmi.visibility_range_end = sicht_ende
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		wurzel.add_child(mmi)


## ------------------------------------------------------ Ranch-Gebäude


## Scheune: Pastellrot, Satteldach, weißes Tor-Kreuz.
func baue_scheune(pos: Vector3, rot_grad: float) -> void:
	var groesse := RanchWelt.gebaeude_groesse("scheune")
	var wurzel := _gebaeude_wurzel(pos, rot_grad, groesse)
	_quader(
		wurzel,
		Vector3(0.0, groesse.y * 0.36, 0.0),
		Vector3(groesse.x, groesse.y * 0.72, groesse.z),
		SCHEUNE_ROT
	)
	_dach(wurzel, groesse, DACH_CREME)
	# Großes Tor + weiße Rahmen-Balken auf der Südseite.
	_quader(wurzel, Vector3(0.0, 3.1, groesse.z / 2.0 + 0.08), Vector3(6.4, 6.2, 0.2), HOLZ_DUNKEL)
	_quader(wurzel, Vector3(0.0, 3.1, groesse.z / 2.0 + 0.16), Vector3(0.5, 6.2, 0.1), DACH_CREME)
	_quader(wurzel, Vector3(0.0, 6.0, groesse.z / 2.0 + 0.16), Vector3(6.4, 0.5, 0.1), DACH_CREME)


## Stall: offene Boxen-Front nach Westen, Holz-Look.
func baue_stall(pos: Vector3, rot_grad: float) -> void:
	var groesse := RanchWelt.gebaeude_groesse("stall")
	var wurzel := _gebaeude_wurzel(pos, rot_grad, groesse)
	_quader(
		wurzel,
		Vector3(0.0, groesse.y * 0.4, 0.0),
		Vector3(groesse.x, groesse.y * 0.8, groesse.z),
		HOLZ_HELL
	)
	_dach(wurzel, groesse, DACH_TEAL)
	for i in 4:
		var x := -groesse.x / 2.0 + 3.4 + float(i) * 6.4
		_quader(
			wurzel, Vector3(x, 1.6, groesse.z / 2.0 + 0.06), Vector3(2.8, 3.2, 0.15), HOLZ_DUNKEL
		)


## Ranch-Haus: Creme-Wände, Teal-Dach, Veranda-Balken.
func baue_haus(pos: Vector3, rot_grad: float) -> void:
	var groesse := RanchWelt.gebaeude_groesse("haus")
	var wurzel := _gebaeude_wurzel(pos, rot_grad, groesse)
	_quader(
		wurzel,
		Vector3(0.0, groesse.y * 0.38, 0.0),
		Vector3(groesse.x, groesse.y * 0.76, groesse.z),
		HAUS_CREME
	)
	_dach(wurzel, groesse, DACH_TEAL)
	# Veranda: Plattform + zwei Pfosten + Vordach.
	_quader(
		wurzel,
		Vector3(0.0, 0.3, groesse.z / 2.0 + 1.6),
		Vector3(groesse.x * 0.7, 0.6, 3.2),
		HOLZ_DUNKEL
	)
	for seite: float in [-1.0, 1.0]:
		_quader(
			wurzel,
			Vector3(seite * groesse.x * 0.3, 2.4, groesse.z / 2.0 + 2.8),
			Vector3(0.4, 4.2, 0.4),
			HOLZ_DUNKEL
		)
	_quader(
		wurzel,
		Vector3(0.0, 4.6, groesse.z / 2.0 + 1.8),
		Vector3(groesse.x * 0.74, 0.4, 4.0),
		DACH_TEAL
	)
	# Tür + zwei Fenster.
	_quader(wurzel, Vector3(0.0, 1.5, groesse.z / 2.0 + 0.06), Vector3(1.6, 3.0, 0.14), HOLZ_DUNKEL)
	for seite: float in [-1.0, 1.0]:
		_quader(
			wurzel,
			Vector3(seite * 4.6, 2.2, groesse.z / 2.0 + 0.06),
			Vector3(2.0, 1.8, 0.14),
			Color(0.72, 0.86, 0.92)
		)


## Heulager: offener Unterstand mit Heuballen-Stapel.
func baue_heulager(pos: Vector3, rot_grad: float) -> void:
	var groesse := RanchWelt.gebaeude_groesse("heulager")
	var wurzel := _gebaeude_wurzel(pos, rot_grad, groesse)
	for ecke: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		_quader(
			wurzel,
			Vector3(
				ecke.x * (groesse.x / 2.0 - 0.4), groesse.y * 0.42, ecke.y * (groesse.z / 2.0 - 0.4)
			),
			Vector3(0.5, groesse.y * 0.84, 0.5),
			HOLZ_DUNKEL
		)
	_dach(wurzel, groesse, DACH_CREME)
	baue_heuballen(wurzel, Vector3(-2.4, 0.0, 0.0))
	baue_heuballen(wurzel, Vector3(0.6, 0.0, 0.8))
	baue_heuballen(wurzel, Vector3(-1.0, 1.5, 0.4))


## Liegender Heuballen (Zylinder + Spiral-Band).
func baue_heuballen(wurzel: Node3D, pos: Vector3) -> void:
	var ballen := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.85
	mesh.bottom_radius = 0.85
	mesh.height = 1.5
	mesh.radial_segments = 14
	mesh.material = _mat(HEU_GELB)
	ballen.mesh = mesh
	ballen.position = pos + Vector3(0.0, 0.85, 0.0)
	ballen.rotation.z = PI / 2.0
	wurzel.add_child(ballen)
	# Kollider grob an der Weltposition (wurzel liegt direkt in der Szene).
	_collider_bei(wurzel.position + pos, 1.1)


## Wassertrog: Holzrahmen + Wasserfläche.
func baue_trog(pos: Vector3) -> void:
	var wurzel := Node3D.new()
	wurzel.position = pos
	_szene.add_child(wurzel)
	_quader(wurzel, Vector3(0.0, 0.4, 0.0), Vector3(3.0, 0.8, 1.4), HOLZ_DUNKEL)
	var wasser := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(2.6, 1.1)
	mesh.material = _wasser_mat()
	wasser.mesh = mesh
	wasser.position = Vector3(0.0, 0.82, 0.0)
	wurzel.add_child(wasser)
	_collider_bei(pos, 1.6)


## Windrad: Turm + Kopf + Rotor. Gibt den Rotor-Node zurück (Szene dreht
## ihn in _process — sanfte Dauer-Animation wie CityBau.tick).
func baue_windrad(pos: Vector3) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "Windrad"
	wurzel.position = pos
	_szene.add_child(wurzel)
	var turm := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 1.4
	mesh.height = 16.0
	mesh.radial_segments = 10
	mesh.material = _mat(DACH_CREME)
	turm.mesh = mesh
	turm.position.y = 8.0
	wurzel.add_child(turm)
	_quader(wurzel, Vector3(0.0, 16.6, 0.0), Vector3(1.8, 1.6, 2.2), DACH_TEAL)
	var rotor := Node3D.new()
	rotor.name = "Rotor"
	rotor.position = Vector3(0.0, 16.6, 1.4)
	wurzel.add_child(rotor)
	for i in 4:
		var blatt := MeshInstance3D.new()
		var blatt_mesh := BoxMesh.new()
		blatt_mesh.size = Vector3(0.9, 6.4, 0.15)
		blatt_mesh.material = _mat(DACH_CREME)
		blatt.mesh = blatt_mesh
		blatt.position = Vector3(0.0, 0.0, 0.0)
		blatt.rotation.z = float(i) * PI / 2.0
		blatt.position = Vector3(sin(blatt.rotation.z) * -3.4, cos(blatt.rotation.z) * 3.4, 0.0)
		rotor.add_child(blatt)
	_collider_bei(pos, 2.0)
	return rotor


## Bach quer zur Straße + Holzbrücke (Geländer aus dem nature-kit).
func baue_bach(z: float, breite_gesamt: float) -> void:
	var wasser := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(breite_gesamt, 7.0)
	mesh.material = _wasser_mat()
	wasser.mesh = mesh
	wasser.position = Vector3(0.0, 0.015, z)
	_szene.add_child(wasser)
	for seite: float in [-1.0, 1.0]:
		var gelaender := lade_glb("%s/natur/bridge_wood.glb" % ASSETS, 3.2)
		if gelaender == null:
			continue
		gelaender.position = Vector3(seite * 5.4, 0.0, z)
		gelaender.rotation.y = PI / 2.0
		_szene.add_child(gelaender)
		_collider_rect(seite * 5.4, z, 1.2, 4.6)


## Ranch-Tor: zwei Pfosten + Querbalken + Schriftzug (Label3D) auf BEIDEN
## Seiten — die Fahrt kommt von -z an, der Hof blickt von +z aufs Tor.
func baue_tor(pos: Vector3, titel: String) -> void:
	var wurzel := Node3D.new()
	wurzel.name = "RanchTor"
	wurzel.position = pos
	_szene.add_child(wurzel)
	for seite: float in [-1.0, 1.0]:
		_quader(wurzel, Vector3(seite * 7.0, 3.0, 0.0), Vector3(1.0, 6.0, 1.0), HOLZ_DUNKEL)
		_collider_bei(pos + Vector3(seite * 7.0, 0.0, 0.0), 1.0)
	_quader(wurzel, Vector3(0.0, 6.2, 0.0), Vector3(15.6, 1.1, 0.9), HOLZ_HELL)
	for seite: float in [-1.0, 1.0]:
		var schrift := Label3D.new()
		schrift.text = titel
		schrift.font_size = 220
		schrift.pixel_size = 0.01
		schrift.modulate = SCHILD_INK
		schrift.outline_size = 24
		schrift.outline_modulate = DACH_CREME
		schrift.position = Vector3(0.0, 6.25, seite * 0.55)
		schrift.rotation.y = 0.0 if seite > 0.0 else PI
		schrift.no_depth_test = false
		wurzel.add_child(schrift)


## Stadtausfahrt-/Landstraßen-Schild: Pfosten + Tafel + zwei Textzeilen.
func baue_schild(pos: Vector3, zeile1: String, zeile2: String) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.position = pos
	_szene.add_child(wurzel)
	_quader(wurzel, Vector3(0.0, 1.3, 0.0), Vector3(0.22, 2.6, 0.22), HOLZ_DUNKEL)
	_quader(wurzel, Vector3(0.0, 2.9, 0.0), Vector3(4.6, 1.5, 0.18), DACH_CREME)
	var text := Label3D.new()
	text.text = "%s\n%s" % [zeile1, zeile2]
	text.font_size = 96
	text.pixel_size = 0.01
	text.modulate = SCHILD_INK
	text.position = Vector3(0.0, 2.9, 0.12)
	wurzel.add_child(text)
	_collider_bei(pos, 0.5)
	return wurzel


## Reitplatz: Sandfläche + Zaunring + zwei Sprungstangen.
func baue_reitplatz(rect: Rect2) -> void:
	var mitte := rect.get_center()
	var sand := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = rect.size
	mesh.material = _mat(Color(0.89, 0.8, 0.62))
	sand.mesh = mesh
	sand.position = Vector3(mitte.x, 0.03, mitte.y)
	_szene.add_child(sand)
	for i in 2:
		var stange := Node3D.new()
		stange.position = Vector3(mitte.x - 12.0 + float(i) * 24.0, 0.0, mitte.y)
		_szene.add_child(stange)
		_quader(stange, Vector3(-2.0, 0.6, 0.0), Vector3(0.3, 1.2, 0.3), HOLZ_DUNKEL)
		_quader(stange, Vector3(2.0, 0.6, 0.0), Vector3(0.3, 1.2, 0.3), HOLZ_DUNKEL)
		_quader(stange, Vector3(0.0, 0.95, 0.0), Vector3(4.3, 0.22, 0.22), SCHEUNE_ROT)


## Teich: Ellipse aus zwei Wasser-Kreisen + Uferring.
func baue_teich(pos: Vector3) -> void:
	var ufer := MeshInstance3D.new()
	var ufer_mesh := CylinderMesh.new()
	ufer_mesh.top_radius = 14.0
	ufer_mesh.bottom_radius = 14.0
	ufer_mesh.height = 0.04
	ufer_mesh.radial_segments = 26
	ufer_mesh.material = _mat(Color(0.82, 0.76, 0.58))
	ufer.mesh = ufer_mesh
	ufer.position = pos + Vector3(0.0, 0.02, 0.0)
	_szene.add_child(ufer)
	var wasser := MeshInstance3D.new()
	var wasser_mesh := CylinderMesh.new()
	wasser_mesh.top_radius = 12.0
	wasser_mesh.bottom_radius = 12.0
	wasser_mesh.height = 0.04
	wasser_mesh.radial_segments = 26
	wasser_mesh.material = _wasser_mat()
	wasser.mesh = wasser_mesh
	wasser.position = pos + Vector3(0.0, 0.05, 0.0)
	_szene.add_child(wasser)


## ----------------------------------------------------------- Werkzeuge


func lade_glb(pfad: String, groesse: float) -> Node3D:
	if not ResourceLoader.exists(pfad):
		push_warning("Ranch-Asset fehlt: %s" % pfad)
		return null
	var szene: PackedScene = load(pfad)
	if szene == null:
		return null
	var node: Node3D = szene.instantiate()
	node.scale = Vector3.ONE * groesse
	return node


func _gebaeude_wurzel(pos: Vector3, rot_grad: float, groesse: Vector3) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.position = pos
	wurzel.rotation.y = deg_to_rad(rot_grad)
	_szene.add_child(wurzel)
	_collider_rect(pos.x, pos.z, groesse.x / 2.0 + 1.0, groesse.z / 2.0 + 1.0)
	return wurzel


func _dach(wurzel: Node3D, groesse: Vector3, farbe: Color) -> void:
	var dach := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = Vector3(groesse.x + 1.6, groesse.y * 0.34, groesse.z + 1.6)
	mesh.material = _mat(farbe)
	dach.mesh = mesh
	dach.position = Vector3(0.0, groesse.y * 0.72 + groesse.y * 0.17, 0.0)
	wurzel.add_child(dach)


func _quader(wurzel: Node3D, pos: Vector3, groesse: Vector3, farbe: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = groesse
	mesh.material = _mat(farbe)
	mi.mesh = mesh
	mi.position = pos
	wurzel.add_child(mi)
	return mi


## Geteilte Pastell-Materialien (ein Material je Farbton).
func _mat(farbe: Color) -> StandardMaterial3D:
	return RanchPferd.material(farbe)


func _wasser_mat() -> StandardMaterial3D:
	var mat := RanchPferd.material(WASSER_BLAU)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.15
	return mat


func _glb_meshes(pfad: String) -> Array[Dictionary]:
	if _glb_mesh_cache.has(pfad):
		return _glb_mesh_cache[pfad]
	var teile: Array[Dictionary] = []
	if not ResourceLoader.exists(pfad):
		push_warning("Ranch-Asset fehlt: %s" % pfad)
		_glb_mesh_cache[pfad] = teile
		return teile
	var szene: PackedScene = load(pfad)
	if szene != null:
		var proto: Node3D = szene.instantiate()
		for mesh in proto.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = mesh
			var rel := Transform3D.IDENTITY
			var n: Node = mi
			while n != null and n != proto:
				if n is Node3D:
					rel = (n as Node3D).transform * rel
				n = n.get_parent()
			teile.append({"mesh": mi.mesh, "xform": rel})
		proto.free()
	_glb_mesh_cache[pfad] = teile
	return teile


func _getoentes_mesh(mesh: Mesh, farbe: Color) -> Mesh:
	var kopie: Mesh = mesh.duplicate()
	for i in kopie.get_surface_count():
		var mat: Material = kopie.surface_get_material(i)
		if mat is StandardMaterial3D:
			var neu: StandardMaterial3D = mat.duplicate()
			neu.albedo_color = neu.albedo_color.lerp(farbe, 0.65)
			kopie.surface_set_material(i, neu)
	return kopie


func _collider_bei(mitte: Vector3, halb: float) -> void:
	_collider_rect(mitte.x, mitte.z, halb, halb)


func _collider_rect(x: float, z: float, halb_x: float, halb_z: float) -> void:
	colliders.append(
		{"min_x": x - halb_x, "max_x": x + halb_x, "min_z": z - halb_z, "max_z": z + halb_z}
	)
