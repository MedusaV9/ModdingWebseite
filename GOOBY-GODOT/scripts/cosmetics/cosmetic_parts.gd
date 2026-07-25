class_name CosmeticParts
extends RefCounted
## Bauklötzchen für die prozeduralen Cosmetic-Meshes (CONTENT-A).
##
## Alle Builder arbeiten im **Rezept-Raum** der Web-Referenz
## (`GOOBY/src/character/outfitAttach.js`) — die dortigen Zahlen sind mit
## Screenshots eingemessen und können hier 1:1 übernommen werden. Die
## Umrechnung in Godot-Einheiten macht ausschließlich der Anker in
## `cosmetic_attach.gd` über seine Skalierung (Kopf 0.7044, Körper 0.6522);
## KEIN Builder rechnet selbst um.
##
## Konvention: jede Funktion hängt das Teil direkt an `parent` und gibt es
## zurück, damit der Aufrufer noch drehen/skalieren kann:
##     var krempe := CosmeticParts.zyl(hut, 0.19, 0.2, 0.015, stroh)
##     krempe.scale.z = 0.92
##
## Materialien sind gecacht (Farbe+Rauheit+Metall+Alpha) und werden zwischen
## allen Items geteilt — ein Wardrobe-Grid mit 90 Vorschauen soll nicht 300
## Materialien anlegen.

## Kenney/GOOBY-Look: kaum Glanz, keine harten Speculars.
const RAUH_STOFF := 0.85
const RAUH_LACK := 0.45
const RAUH_STANDARD := 0.6

static var _mat_cache: Dictionary = {}


## Geteiltes Flat-Material. `metall` > 0 macht Gold/Silber, `alpha` < 1
## schaltet Transparenz (Helmglas, Feenflügel).
static func mat(farbe: Color, rauheit := RAUH_STANDARD, metall := 0.0, alpha := 1.0) -> Material:
	var key := "%s|%.2f|%.2f|%.2f" % [farbe.to_html(false), rauheit, metall, alpha]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(farbe, alpha)
	material.roughness = rauheit
	material.metallic = metall
	material.metallic_specular = 0.35 if metall > 0.0 else 0.2
	if alpha < 1.0:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Viele Teile sind flach (Krempe, Flügel, Gläser) — beidseitig zeichnen.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat_cache[key] = material
	return material


static func box(
	parent: Node3D, groesse: Vector3, farbe: Color, pos := Vector3.ZERO, rauheit := RAUH_STANDARD
) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = groesse
	return _add(parent, mesh, farbe, pos, rauheit)


static func zyl(
	parent: Node3D,
	r_oben: float,
	r_unten: float,
	hoehe: float,
	farbe: Color,
	pos := Vector3.ZERO,
	rauheit := RAUH_STANDARD
) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = r_oben
	mesh.bottom_radius = r_unten
	mesh.height = hoehe
	mesh.radial_segments = 20
	mesh.rings = 1
	return _add(parent, mesh, farbe, pos, rauheit)


static func kugel(
	parent: Node3D, radius: float, farbe: Color, pos := Vector3.ZERO, rauheit := RAUH_STANDARD
) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 16
	mesh.rings = 8
	return _add(parent, mesh, farbe, pos, rauheit)


## Halbkugel (Kappen, Helme, Panzer) — flache Unterseite auf y = pos.y.
static func dom(
	parent: Node3D, radius: float, farbe: Color, pos := Vector3.ZERO, rauheit := RAUH_STANDARD
) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius
	mesh.is_hemisphere = true
	mesh.radial_segments = 18
	mesh.rings = 8
	return _add(parent, mesh, farbe, pos, rauheit)


static func kegel(
	parent: Node3D,
	radius: float,
	hoehe: float,
	farbe: Color,
	pos := Vector3.ZERO,
	rauheit := RAUH_STANDARD
) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = radius
	mesh.height = hoehe
	mesh.radial_segments = 16
	mesh.rings = 1
	return _add(parent, mesh, farbe, pos, rauheit)


## Liegender Ring (Loch zeigt nach oben) — Hutbänder, Halsbänder, Kränze.
static func ring(
	parent: Node3D,
	radius: float,
	dicke: float,
	farbe: Color,
	pos := Vector3.ZERO,
	rauheit := RAUH_STANDARD
) -> MeshInstance3D:
	var mesh := TorusMesh.new()
	mesh.inner_radius = maxf(0.001, radius - dicke)
	mesh.outer_radius = radius + dicke
	mesh.rings = 20
	mesh.ring_segments = 10
	return _add(parent, mesh, farbe, pos, rauheit)


## Stehende Kapsel (Ärmel, Riemen, Stiele).
static func kapsel(
	parent: Node3D,
	radius: float,
	hoehe: float,
	farbe: Color,
	pos := Vector3.ZERO,
	rauheit := RAUH_STANDARD
) -> MeshInstance3D:
	var mesh := CapsuleMesh.new()
	mesh.radius = radius
	mesh.height = maxf(hoehe, radius * 2.0 + 0.001)
	mesh.radial_segments = 12
	mesh.rings = 4
	return _add(parent, mesh, farbe, pos, rauheit)


## Flacher Kreisring (Krempe, Kragenteller) MIT echten Aussparungen.
##
## Godot-Primitive können keine Kreissektoren, und genau die braucht ein Hut
## auf einem Hasen: eine volle Krempe geht bei jeder Breite entweder durch die
## Ohren oder durch den Schädel. `luecken` schneidet Sektoren heraus (jeweils
## Vector2(start, ende) im Bogenmaß, Winkel = atan2(x, z), 0 = vorn) — der Hut
## bekommt damit zwei Ohrlöcher statt einer Durchdringung.
static func teller(
	parent: Node3D,
	r_innen: float,
	r_aussen: float,
	dicke: float,
	farbe: Color,
	luecken: Array = [],
	pos := Vector3.ZERO,
	rauheit := RAUH_STOFF
) -> MeshInstance3D:
	var segmente := 64
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var oben := dicke * 0.5
	var unten := -dicke * 0.5
	for i in segmente:
		var a0 := TAU * float(i) / float(segmente)
		var a1 := TAU * float(i + 1) / float(segmente)
		if _in_luecke((a0 + a1) * 0.5, luecken):
			continue
		var i0 := Vector2(sin(a0) * r_innen, cos(a0) * r_innen)
		var i1 := Vector2(sin(a1) * r_innen, cos(a1) * r_innen)
		var o0 := Vector2(sin(a0) * r_aussen, cos(a0) * r_aussen)
		var o1 := Vector2(sin(a1) * r_aussen, cos(a1) * r_aussen)
		_quad(st, _p(i0, oben), _p(o0, oben), _p(o1, oben), _p(i1, oben))
		_quad(st, _p(i1, unten), _p(o1, unten), _p(o0, unten), _p(i0, unten))
		_quad(st, _p(o0, oben), _p(o0, unten), _p(o1, unten), _p(o1, oben))
		_quad(st, _p(i1, oben), _p(i1, unten), _p(i0, unten), _p(i0, oben))
		# Stirnflächen nur dort, wo wirklich eine Lücke anschließt.
		if _in_luecke(a0 - TAU / float(segmente) * 0.5, luecken):
			_quad(st, _p(i0, oben), _p(i0, unten), _p(o0, unten), _p(o0, oben))
		if _in_luecke(a1 + TAU / float(segmente) * 0.5, luecken):
			_quad(st, _p(o1, oben), _p(o1, unten), _p(i1, unten), _p(i1, oben))
	st.generate_normals()
	var node := MeshInstance3D.new()
	node.mesh = st.commit()
	node.material_override = mat(farbe, rauheit)
	node.position = pos
	parent.add_child(node)
	return node


## Flaches Herz aus zwei Kugeln + Kegel (Herzbrille, Herzkette).
static func herz(parent: Node3D, groesse: float, farbe: Color, pos := Vector3.ZERO) -> Node3D:
	var wurzel := Node3D.new()
	parent.add_child(wurzel)
	wurzel.position = pos
	for sx in [-1.0, 1.0]:
		var lappen := kugel(
			wurzel, groesse * 0.55, farbe, Vector3(sx * groesse * 0.42, groesse * 0.36, 0.0)
		)
		lappen.scale = Vector3(1.0, 1.0, 0.45)
	var spitze := kegel(wurzel, groesse * 0.95, groesse * 1.5, farbe, Vector3(0.0, -0.02, 0.0))
	spitze.rotation.z = PI
	spitze.scale = Vector3(1.0, 1.0, 0.45)
	return wurzel


## Flacher fünfzackiger Stern (Sternenbrille, Zauberhut-Deko).
static func stern(parent: Node3D, groesse: float, farbe: Color, pos := Vector3.ZERO) -> Node3D:
	var wurzel := Node3D.new()
	parent.add_child(wurzel)
	wurzel.position = pos
	for i in 5:
		var zacke := kegel(wurzel, groesse * 0.34, groesse * 1.05, farbe)
		zacke.rotation.z = -TAU * float(i) / 5.0
		zacke.position = Vector3(
			sin(TAU * float(i) / 5.0) * groesse * 0.42,
			cos(TAU * float(i) / 5.0) * groesse * 0.42,
			0.0
		)
		zacke.scale = Vector3(1.0, 1.0, 0.32)
	return wurzel


## Farbe Nr. `index` aus der Item-Definition (fällt weich auf `fallback`).
static func farbe_von(def: Dictionary, index: int, fallback: Color) -> Color:
	var farben: Variant = def.get("farben", [])
	if farben is Array and index < (farben as Array).size():
		var wert := str((farben as Array)[index]).strip_edges()
		if wert.is_valid_html_color():
			return Color(wert)
	return fallback


## Builder-Parameter mit Default (`params` aus der Item-Definition).
static func param(def: Dictionary, key: String, fallback: Variant) -> Variant:
	var params: Variant = def.get("params", {})
	if params is Dictionary and (params as Dictionary).has(key):
		return (params as Dictionary)[key]
	return fallback


static func _p(xz: Vector2, y: float) -> Vector3:
	return Vector3(xz.x, y, xz.y)


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for punkt in [a, b, c, a, c, d]:
		st.add_vertex(punkt)


static func _in_luecke(winkel: float, luecken: Array) -> bool:
	var w := fposmod(winkel, TAU)
	for luecke: Variant in luecken:
		if not (luecke is Vector2):
			continue
		var start := fposmod((luecke as Vector2).x, TAU)
		var ende := fposmod((luecke as Vector2).y, TAU)
		if start <= ende:
			if w >= start and w <= ende:
				return true
		elif w >= start or w <= ende:
			return true
	return false


static func _add(
	parent: Node3D, mesh: Mesh, farbe: Color, pos: Vector3, rauheit: float
) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat(farbe, rauheit)
	node.position = pos
	parent.add_child(node)
	return node
