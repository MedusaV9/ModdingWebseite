class_name HouseExterior
extends RefCounted
## Prozedurales Haus-Außenmodell + Grundstück (HAUS-CUSTOM, User-Wunsch:
## Fassadenfarbe, Dachform/-farbe, Tür-/Fensterrahmenfarbe, Hausnummer,
## Briefkasten, Vordach/Markise, Gras/Boden, Weg, Zaun). Alles aus
## Godot-Primitiven im HomeProps-Stil — Materialien kommen ausschließlich
## aus CustomizeMaterials (geteilte Umfärbe-Materialien, mobiltauglich).
##
## Jedes stilbare Teil trägt `meta["haus_teil"]` — `HouseStyle
## .apply_to_exterior` färbt darüber um, ohne den Baum neu zu bauen.
## STRUKTUR-Wechsel (Dachform, Briefkasten-Variante, Vordach, Weg an/aus,
## Zaun-Stil) brauchen einen Rebuild: einfach `build(style)` neu rufen.

const META := "haus_teil"
## Grundstück (Meter): x-Breite × z-Tiefe, Haus an der Nordkante.
const PLOT := Vector2(14.0, 12.0)
const HAUS_BREITE := 7.0
const HAUS_TIEFE := 4.5
const HAUS_HOEHE := 2.6
## Vorderkante (Süd-Fassade) des Hauses.
const FRONT_Z := 5.1
const TUER_X := 6.0
const WEG_BREITE := 1.4
const ZAUN_HOEHE := 0.55


## Baut Haus + Grundstück komplett aus einem (normalisierten) Stil.
static func build(style: Dictionary) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "HausAussen"
	var haus: Dictionary = style.get("haus", CustomizeCatalog.default_haus())
	var grund: Dictionary = style.get("grundstueck", CustomizeCatalog.default_grundstueck())
	wurzel.add_child(_grund(grund))
	wurzel.add_child(_korpus(haus))
	wurzel.add_child(_dach(haus))
	wurzel.add_child(_tuer(haus))
	for fenster_x: float in [4.2, 8.6]:
		wurzel.add_child(_fenster(haus, fenster_x))
	wurzel.add_child(_hausnummer(haus))
	wurzel.add_child(_briefkasten(haus))
	var vordach := _vordach(haus)
	if vordach != null:
		wurzel.add_child(vordach)
	var weg := _weg(grund)
	if weg != null:
		wurzel.add_child(weg)
	var zaun := _zaun(grund)
	if zaun != null:
		wurzel.add_child(zaun)
	return wurzel


## Material eines Haus-Teils zum aktuellen Stil (auch für apply_to_exterior).
static func teil_material(teil: String, style: Dictionary) -> Material:
	var haus: Dictionary = style.get("haus", CustomizeCatalog.default_haus())
	var grund: Dictionary = style.get("grundstueck", CustomizeCatalog.default_grundstueck())
	match teil:
		"fassade":
			return CustomizeMaterials.surface("uni", str(haus.get("fassade", "creme")))
		"dach":
			return CustomizeMaterials.surface("dielen", str(haus.get("dachFarbe", "ziegelrot")))
		"tuer":
			return CustomizeMaterials.flat(str(haus.get("tuerFarbe", "nussbaum")))
		"fensterrahmen":
			return CustomizeMaterials.flat(str(haus.get("fensterFarbe", "weiss")))
		"briefkasten":
			return CustomizeMaterials.flat(str(haus.get("briefkastenFarbe", "ziegelrot")), 0.6)
		"vordach":
			var muster := (
				"streifen" if str(haus.get("vordach", "")) == "markise_gestreift" else "uni"
			)
			return CustomizeMaterials.surface(muster, str(haus.get("vordachFarbe", "rose")))
		"grund":
			return _flaechen_material("grundBoden", grund, "boden", "bodenFarbe")
		"weg":
			return _flaechen_material("weg", grund, "weg", "wegFarbe")
		"zaun":
			if str(grund.get("zaun", "")) == "hecke":
				return CustomizeMaterials.surface(
					"rasen", str(grund.get("zaunFarbe", "blattgruen"))
				)
			return CustomizeMaterials.flat(str(grund.get("zaunFarbe", "eiche")))
	return null


static func _flaechen_material(
	art: String, grund: Dictionary, key: String, farb_key: String
) -> Material:
	var def := CustomizeCatalog.def(art, str(grund.get(key, "")))
	var muster := str(def.get("muster", "rasen"))
	if muster == "":
		muster = "uni"
	return CustomizeMaterials.surface(muster, str(grund.get(farb_key, "blattgruen")))


# ── Bauteile ─────────────────────────────────────────────────────────────────


static func _grund(grund: Dictionary) -> MeshInstance3D:
	var boden := _box(
		Vector3(PLOT.x, 0.12, PLOT.y),
		_flaechen_material("grundBoden", grund, "boden", "bodenFarbe"),
		"grund"
	)
	boden.name = "Grund"
	boden.position = Vector3(PLOT.x * 0.5, -0.06, PLOT.y * 0.5)
	return boden


static func _korpus(haus: Dictionary) -> MeshInstance3D:
	var korpus := _box(
		Vector3(HAUS_BREITE, HAUS_HOEHE, HAUS_TIEFE),
		CustomizeMaterials.surface("uni", str(haus.get("fassade", "creme"))),
		"fassade"
	)
	korpus.name = "Fassade"
	korpus.position = Vector3(PLOT.x * 0.5, HAUS_HOEHE * 0.5, FRONT_Z - HAUS_TIEFE * 0.5)
	return korpus


static func _dach(haus: Dictionary) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "Dach"
	var material := CustomizeMaterials.surface("dielen", str(haus.get("dachFarbe", "ziegelrot")))
	var mitte_z := FRONT_Z - HAUS_TIEFE * 0.5
	match str(haus.get("dachForm", "sattel")):
		"walm":
			var stufen := [
				Vector3(HAUS_BREITE + 0.7, 0.55, HAUS_TIEFE + 0.7),
				Vector3(HAUS_BREITE - 0.9, 0.55, HAUS_TIEFE - 0.9),
				Vector3(HAUS_BREITE - 2.5, 0.5, HAUS_TIEFE - 2.5),
			]
			var y := HAUS_HOEHE
			for groesse: Vector3 in stufen:
				var stufe := _box(groesse, material, "dach")
				stufe.position = Vector3(PLOT.x * 0.5, y + groesse.y * 0.5, mitte_z)
				wurzel.add_child(stufe)
				y += groesse.y
		"flach":
			var platte := _box(Vector3(HAUS_BREITE + 0.5, 0.3, HAUS_TIEFE + 0.5), material, "dach")
			platte.position = Vector3(PLOT.x * 0.5, HAUS_HOEHE + 0.15, mitte_z)
			wurzel.add_child(platte)
			var kante := _box(Vector3(HAUS_BREITE + 0.5, 0.16, 0.14), material, "dach")
			kante.position = Vector3(PLOT.x * 0.5, HAUS_HOEHE + 0.38, mitte_z + HAUS_TIEFE * 0.5)
			wurzel.add_child(kante)
		_:
			var giebel := MeshInstance3D.new()
			var prisma := PrismMesh.new()
			prisma.size = Vector3(HAUS_TIEFE + 0.7, 1.5, HAUS_BREITE + 0.6)
			giebel.mesh = prisma
			giebel.material_override = material
			giebel.set_meta(META, "dach")
			giebel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			giebel.rotation.y = PI * 0.5
			giebel.position = Vector3(PLOT.x * 0.5, HAUS_HOEHE + 0.75, mitte_z)
			wurzel.add_child(giebel)
	return wurzel


static func _tuer(haus: Dictionary) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "Tuer"
	var rahmen := _box(
		Vector3(1.14, 2.06, 0.06),
		CustomizeMaterials.flat(str(haus.get("fensterFarbe", "weiss"))),
		"fensterrahmen"
	)
	rahmen.position = Vector3(TUER_X, 1.03, FRONT_Z + 0.02)
	wurzel.add_child(rahmen)
	var blatt := _box(
		Vector3(0.95, 1.9, 0.07),
		CustomizeMaterials.flat(str(haus.get("tuerFarbe", "nussbaum"))),
		"tuer"
	)
	blatt.position = Vector3(TUER_X, 0.95, FRONT_Z + 0.06)
	wurzel.add_child(blatt)
	var griff := _box(Vector3(0.05, 0.14, 0.05), CustomizeMaterials.flat("sonnengelb", 0.4), "")
	griff.position = Vector3(TUER_X + 0.34, 1.0, FRONT_Z + 0.11)
	wurzel.add_child(griff)
	return wurzel


static func _fenster(haus: Dictionary, x: float) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "Fenster_%d" % int(x * 10.0)
	var material := CustomizeMaterials.flat(str(haus.get("fensterFarbe", "weiss")))
	var rahmen := _box(Vector3(1.3, 1.1, 0.06), material, "fensterrahmen")
	rahmen.position = Vector3(x, 1.5, FRONT_Z + 0.02)
	wurzel.add_child(rahmen)
	var glas := _box(Vector3(1.1, 0.9, 0.03), CustomizeMaterials.flat("himmel", 0.2), "")
	glas.position = Vector3(x, 1.5, FRONT_Z + 0.06)
	wurzel.add_child(glas)
	var sprosse := _box(Vector3(0.06, 0.9, 0.04), material, "fensterrahmen")
	sprosse.position = Vector3(x, 1.5, FRONT_Z + 0.08)
	wurzel.add_child(sprosse)
	var bank := _box(Vector3(1.4, 0.07, 0.14), material, "fensterrahmen")
	bank.position = Vector3(x, 0.92, FRONT_Z + 0.07)
	wurzel.add_child(bank)
	return wurzel


static func _hausnummer(haus: Dictionary) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "Hausnummer"
	var stil := str(haus.get("hausnummer", "holz"))
	var schild_material: Material
	var text_farbe := Color("#4A3B36")
	match stil:
		"emaille":
			schild_material = CustomizeMaterials.flat("marine", 0.35)
			text_farbe = Color("#FFFFFF")
		"modern":
			schild_material = CustomizeMaterials.flat("anthrazit", 0.5)
			text_farbe = Color("#FFFFFF")
		_:
			schild_material = CustomizeMaterials.flat("eiche")
	var schild := _box(
		Vector3(0.36, 0.28, 0.04) if stil != "modern" else Vector3(0.3, 0.4, 0.03),
		schild_material,
		"hausnummer"
	)
	schild.position = Vector3(TUER_X + 0.85, 1.7, FRONT_Z + 0.03)
	wurzel.add_child(schild)
	var text := Label3D.new()
	text.name = "Zahl"
	text.text = str(int(haus.get("hausnummerZahl", 5)))
	text.font_size = 96
	text.pixel_size = 0.002
	text.modulate = text_farbe
	text.set_meta(META, "hausnummer_text")
	text.position = Vector3(TUER_X + 0.85, 1.7, FRONT_Z + 0.06)
	wurzel.add_child(text)
	return wurzel


static func _briefkasten(haus: Dictionary) -> Node3D:
	var wurzel := Node3D.new()
	wurzel.name = "Briefkasten"
	wurzel.position = Vector3(TUER_X + 2.1, 0.0, PLOT.y - 1.6)
	var material := CustomizeMaterials.flat(str(haus.get("briefkastenFarbe", "ziegelrot")), 0.6)
	var pfosten := _zylinder(0.04, 0.9, CustomizeMaterials.flat("nussbaum"), "")
	pfosten.position.y = 0.45
	wurzel.add_child(pfosten)
	match str(haus.get("briefkasten", "standard")):
		"kugel":
			var kugel := MeshInstance3D.new()
			var mesh := SphereMesh.new()
			mesh.radius = 0.22
			mesh.height = 0.44
			kugel.mesh = mesh
			kugel.material_override = material
			kugel.set_meta(META, "briefkasten")
			kugel.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			kugel.position.y = 1.06
			wurzel.add_child(kugel)
		"holz":
			var kasten := _box(Vector3(0.42, 0.3, 0.3), material, "briefkasten")
			kasten.position.y = 1.02
			wurzel.add_child(kasten)
			var dach := _box(Vector3(0.48, 0.08, 0.36), material, "briefkasten")
			dach.position.y = 1.2
			wurzel.add_child(dach)
		"modern":
			var saeule := _box(Vector3(0.3, 0.62, 0.2), material, "briefkasten")
			saeule.position.y = 1.06
			wurzel.add_child(saeule)
			var schlitz := _box(Vector3(0.22, 0.03, 0.22), CustomizeMaterials.flat("weiss"), "")
			schlitz.position.y = 1.22
			wurzel.add_child(schlitz)
		_:
			var kasten := _box(Vector3(0.44, 0.3, 0.26), material, "briefkasten")
			kasten.position.y = 1.05
			wurzel.add_child(kasten)
			var fahne := _box(Vector3(0.04, 0.16, 0.04), CustomizeMaterials.flat("sonnengelb"), "")
			fahne.position = Vector3(0.24, 1.18, 0.0)
			wurzel.add_child(fahne)
	return wurzel


static func _vordach(haus: Dictionary) -> Node3D:
	var variante := str(haus.get("vordach", "keins"))
	if variante == "keins" or CustomizeCatalog.def("vordach", variante).is_empty():
		return null
	var wurzel := Node3D.new()
	wurzel.name = "Vordach"
	var material := teil_material("vordach", {"haus": haus})
	if variante == "vordach_holz":
		material = CustomizeMaterials.flat(str(haus.get("vordachFarbe", "eiche")))
	var flaeche := _box(Vector3(1.8, 0.05, 0.9), material, "vordach")
	flaeche.position = Vector3(TUER_X, 2.24, FRONT_Z + 0.45)
	flaeche.rotation.x = 0.28
	wurzel.add_child(flaeche)
	if variante == "vordach_holz":
		for seite: float in [-0.8, 0.8]:
			var strebe := _box(Vector3(0.06, 0.5, 0.06), material, "vordach")
			strebe.position = Vector3(TUER_X + seite, 1.95, FRONT_Z + 0.72)
			wurzel.add_child(strebe)
	else:
		var volant := _box(Vector3(1.8, 0.16, 0.03), material, "vordach")
		volant.position = Vector3(TUER_X, 2.06, FRONT_Z + 0.88)
		wurzel.add_child(volant)
	return wurzel


static func _weg(grund: Dictionary) -> MeshInstance3D:
	var weg_id := str(grund.get("weg", "keins"))
	if weg_id == "keins" or CustomizeCatalog.def("weg", weg_id).is_empty():
		return null
	var laenge := PLOT.y - FRONT_Z
	var weg := _box(
		Vector3(WEG_BREITE, 0.05, laenge),
		_flaechen_material("weg", grund, "weg", "wegFarbe"),
		"weg"
	)
	weg.name = "Weg"
	weg.position = Vector3(TUER_X, 0.025, FRONT_Z + laenge * 0.5)
	return weg


static func _zaun(grund: Dictionary) -> Node3D:
	var stil := str(grund.get("zaun", "latten"))
	if stil == "keins" or CustomizeCatalog.def("zaun", stil).is_empty():
		return null
	var wurzel := Node3D.new()
	wurzel.name = "Zaun"
	var tor_links := TUER_X - WEG_BREITE * 0.5 - 0.2
	var tor_rechts := TUER_X + WEG_BREITE * 0.5 + 0.2
	var segmente: Array = [
		[Vector3(0.06, 0.0, 0.0), Vector3(0.06, 0.0, PLOT.y)],
		[Vector3(PLOT.x - 0.06, 0.0, 0.0), Vector3(PLOT.x - 0.06, 0.0, PLOT.y)],
		[Vector3(0.0, 0.0, 0.06), Vector3(PLOT.x, 0.0, 0.06)],
		[Vector3(0.0, 0.0, PLOT.y - 0.06), Vector3(tor_links, 0.0, PLOT.y - 0.06)],
		[Vector3(tor_rechts, 0.0, PLOT.y - 0.06), Vector3(PLOT.x, 0.0, PLOT.y - 0.06)],
	]
	for segment: Array in segmente:
		wurzel.add_child(_zaun_segment(segment[0], segment[1], stil, grund))
	return wurzel


## Ein Zaun-Segment von `from` nach `to` im gewünschten Stil.
static func _zaun_segment(from: Vector3, to: Vector3, stil: String, grund: Dictionary) -> Node3D:
	var wurzel := Node3D.new()
	var laenge := from.distance_to(to)
	var mitte := (from + to) * 0.5
	# Lokale +X-Achse (Längsachse der Latten/Riegel) auf die Segmentrichtung
	# drehen: Yaw θ bildet +X auf (cos θ, 0, -sin θ) ab.
	wurzel.position = mitte
	wurzel.rotation.y = atan2(-(to.z - from.z), to.x - from.x)
	var material := teil_material("zaun", {"grundstueck": grund})
	if stil == "hecke":
		var hecke := _box(Vector3(laenge, ZAUN_HOEHE + 0.1, 0.38), material, "zaun")
		hecke.position.y = (ZAUN_HOEHE + 0.1) * 0.5
		wurzel.add_child(hecke)
		return wurzel
	var dichte: float = {"latten": 0.24, "staketen": 0.32, "metall": 0.15}.get(stil, 0.24)
	var latte_groesse: Vector3 = (
		{
			"latten": Vector3(0.1, ZAUN_HOEHE, 0.03),
			"staketen": Vector3(0.06, ZAUN_HOEHE + 0.08, 0.06),
			"metall": Vector3(0.03, ZAUN_HOEHE + 0.12, 0.03),
		}
		. get(stil, Vector3(0.1, ZAUN_HOEHE, 0.03))
	)
	var mesh := BoxMesh.new()
	mesh.size = latte_groesse
	mesh.material = material
	var anzahl := maxi(1, int(laenge / float(dichte)))
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = anzahl
	for i in anzahl:
		var x := -laenge * 0.5 + (i + 0.5) * laenge / anzahl
		var basis := Basis.IDENTITY
		multi.set_instance_transform(i, Transform3D(basis, Vector3(x, latte_groesse.y * 0.5, 0.0)))
	var latten := MultiMeshInstance3D.new()
	latten.multimesh = multi
	latten.set_meta(META, "zaun")
	latten.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wurzel.add_child(latten)
	var riegel_hoehen: Array = [ZAUN_HOEHE * 0.35, ZAUN_HOEHE * 0.8]
	if stil == "metall":
		riegel_hoehen = [0.08, ZAUN_HOEHE + 0.06]
	for hoehe: Variant in riegel_hoehen:
		var riegel := _box(Vector3(laenge, 0.05, 0.04), material, "zaun")
		riegel.position = Vector3(0.0, float(hoehe), 0.0)
		wurzel.add_child(riegel)
	return wurzel


# ── Helfer ───────────────────────────────────────────────────────────────────


static func _box(size: Vector3, material: Material, teil: String) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := BoxMesh.new()
	shape.size = size
	mesh.mesh = shape
	mesh.material_override = material
	if teil != "":
		mesh.set_meta(META, teil)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh


static func _zylinder(
	radius: float, hoehe: float, material: Material, teil: String
) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var shape := CylinderMesh.new()
	shape.top_radius = radius
	shape.bottom_radius = radius
	shape.height = hoehe
	mesh.mesh = shape
	mesh.material_override = material
	if teil != "":
		mesh.set_meta(META, teil)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mesh
