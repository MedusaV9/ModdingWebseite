class_name RanchBauVisuals
extends RefCounted
## Billige, footprint-genaue 3D-Optik der Bau-Items (RW-4) — GOOBY-Pastell
## (Palette wie RanchBau/RANCH-1), reine Primitive, wenige MeshInstances
## pro Item (Draw-Call-Budget der Hof-Ansicht: <= 400).
##
## WICHTIG (IDEAS-3 §6): die STUFE ändert die Optik sichtbar — mehr
## Box-Tore, mehr Heuballen, Brunnen statt Trog, zweite Tribünen-Reihe,
## Blumen auf der Kräuterweide. `node_fuer(def, stufe)` ist die einzige
## Tür; der Baumodus hängt das Ergebnis an den Zell-Anker (Min-Ecke).

const SCHEUNE_ROT := Color("#D96C57")
const HOLZ_HELL := Color("#E8C49A")
const HOLZ_DUNKEL := Color("#B58A5F")
const DACH_CREME := Color("#F2E9DC")
const DACH_TEAL := Color("#5FA8A0")
const HAUS_CREME := Color("#F2E3C9")
const HEU_GELB := Color("#E8C96E")
const WIESE_GRUEN := Color(0.58, 0.74, 0.46)
const WIESE_SATT := Color(0.48, 0.7, 0.38)
const SAND := Color(0.89, 0.8, 0.62)
const WASSER_BLAU := Color(0.45, 0.68, 0.82, 0.85)
const SCHOTTER := Color(0.78, 0.74, 0.66)
const PFLASTER := Color(0.72, 0.66, 0.6)
const BLUME_ROSA := Color(0.93, 0.6, 0.7)
const BLUME_GELB := Color(0.95, 0.85, 0.45)
const METALL := Color(0.62, 0.64, 0.68)

const ZELLE := RanchGridData.CELL_SIZE


## Item-Node bauen: Ursprung = Min-Ecke der Ankerzelle, Ausdehnung
## footprint × 3 m in +X/+Z (VOR der Rotation des Baumodus).
static func node_fuer(def: Dictionary, stufe := 1) -> Node3D:
	var fp: Vector2i = def.get("footprint", Vector2i.ONE)
	var groesse := Vector2(fp.x * ZELLE, fp.y * ZELLE)
	var root := Node3D.new()
	root.name = "Item_%s" % str(def.get("id", "item"))
	match str(def.get("id", "")):
		"stallboxen":
			_stallboxen(root, groesse, stufe)
		"weide":
			_weide(root, groesse, stufe)
		"wasserstelle":
			_wasserstelle(root, groesse, stufe)
		"heulager":
			_heulager(root, groesse, stufe)
		"waschplatz":
			_waschplatz(root, groesse, stufe)
		"fuehranlage":
			_fuehranlage(root, groesse, stufe)
		"reithalle":
			_reithalle(root, groesse, stufe)
		"parcours":
			_parcours(root, groesse, stufe)
		"sattelkammer":
			_sattelkammer(root, groesse, stufe)
		"zuchtstall":
			_zuchtstall(root, groesse, stufe)
		"fohlenweide":
			_fohlenweide(root, groesse, stufe)
		"tribuene":
			_tribuene(root, groesse, stufe)
		"beet_blumen":
			_beet(root, BLUME_ROSA)
		"beet_kraeuter":
			_beet(root, WIESE_SATT)
		"bank_holz":
			_bank(root)
		"laterne":
			_laterne(root)
		"fahne":
			_fahne(root)
		"blumenkuebel":
			_kuebel(root)
		"vogelhaus":
			_vogelhaus(root)
		"heuballen_deko":
			_heuballen(root, Vector3(ZELLE * 0.5, 0.0, ZELLE * 0.5))
		"wegweiser":
			_wegweiser(root)
		"strohpuppe":
			_strohpuppe(root)
		"weg_schotter":
			_bodenplatte(root, SCHOTTER)
		"weg_pflaster":
			_bodenplatte(root, PFLASTER)
		"sand":
			_bodenplatte(root, SAND)
		"blumenwiese":
			_blumenwiese(root)
		_:
			_platzhalter(root, groesse)
	return root


## Zaun-Segment einer Kante (3 m entlang +X, Ursprung = Kanten-Mitte).
## Die Weidezaun-Stufe (0..3) hebt die Optik: weiß gestrichen, Doppellatte.
static func zaun_node(weidezaun_stufe := 0) -> Node3D:
	var root := Node3D.new()
	root.name = "Zaun"
	var holz := HOLZ_DUNKEL if weidezaun_stufe < 1 else DACH_CREME
	for seite: float in [-1.0, 1.0]:
		_quader(root, Vector3(seite * ZELLE * 0.5, 0.5, 0.0), Vector3(0.16, 1.0, 0.16), holz)
	_quader(root, Vector3(0.0, 0.82, 0.0), Vector3(ZELLE, 0.12, 0.1), holz)
	if weidezaun_stufe >= 2:
		_quader(root, Vector3(0.0, 0.45, 0.0), Vector3(ZELLE, 0.12, 0.1), holz)
	if weidezaun_stufe >= 3:
		_kugel(root, Vector3(-ZELLE * 0.5, 1.06, 0.0), 0.13, BLUME_ROSA)
		_kugel(root, Vector3(ZELLE * 0.5, 1.06, 0.0), 0.13, BLUME_GELB)
	return root


# ── Anlagen ──────────────────────────────────────────────────────────────────


static func _stallboxen(root: Node3D, g: Vector2, stufe: int) -> void:
	var hoehe := 3.2
	_quader(root, Vector3(g.x / 2, hoehe / 2, g.y / 2), Vector3(g.x, hoehe, g.y), HOLZ_HELL)
	_satteldach(root, g, hoehe, DACH_TEAL)
	# Sichtbare Box-Tore = Kapazität der Stufe (2/4/6/8), gestapelt in Reihen.
	var tore := 2 * maxi(1, stufe)
	for i in tore:
		var reihe := i / 4
		var spalte := i % 4
		_quader(
			root,
			Vector3(g.x * (0.2 + 0.2 * spalte), 0.9 + 1.4 * reihe, g.y + 0.06),
			Vector3(1.0, 1.6, 0.12),
			HOLZ_DUNKEL
		)


static func _weide(root: Node3D, g: Vector2, stufe: int) -> void:
	_platte(root, g, WIESE_SATT if stufe >= 2 else WIESE_GRUEN)
	for i in 6:
		var pos := Vector3(g.x * (0.15 + 0.14 * i), 0.25, g.y * (0.2 + 0.1 * (i % 3)))
		_kugel(root, pos, 0.28, WIESE_SATT)
	if stufe >= 3:
		for i in 8:
			var pos := Vector3(g.x * (0.1 + 0.11 * i), 0.16, g.y * (0.7 - 0.06 * (i % 4)))
			_kugel(root, pos, 0.12, BLUME_ROSA if i % 2 == 0 else BLUME_GELB)


static func _wasserstelle(root: Node3D, g: Vector2, stufe: int) -> void:
	var mitte := Vector3(g.x / 2, 0.0, g.y / 2)
	if stufe >= 3:
		_zylinder(root, mitte + Vector3(0, 0.15, 0), g.x * 0.42, 0.3, HOLZ_DUNKEL)
		_wasserflaeche(root, mitte + Vector3(0, 0.32, 0), Vector2(g.x * 0.7, g.y * 0.7))
	else:
		_quader(root, mitte + Vector3(0, 0.4, 0), Vector3(2.4, 0.8, 1.2), HOLZ_DUNKEL)
		_wasserflaeche(root, mitte + Vector3(0, 0.82, 0), Vector2(2.0, 0.9))
	if stufe >= 2:
		_quader(root, mitte + Vector3(1.1, 0.9, 0), Vector3(0.2, 1.8, 0.2), METALL)
		_kugel(root, mitte + Vector3(1.1, 1.9, 0), 0.2, METALL)


static func _heulager(root: Node3D, g: Vector2, stufe: int) -> void:
	for ecke: Vector2 in [
		Vector2(0.12, 0.12), Vector2(0.88, 0.12), Vector2(0.12, 0.88), Vector2(0.88, 0.88)
	]:
		_quader(
			root, Vector3(g.x * ecke.x, 1.5, g.y * ecke.y), Vector3(0.35, 3.0, 0.35), HOLZ_DUNKEL
		)
	_quader(root, Vector3(g.x / 2, 3.1, g.y / 2), Vector3(g.x, 0.25, g.y), DACH_CREME)
	var ballen := 1 + stufe
	for i in ballen:
		var pos := Vector3(g.x * (0.25 + 0.25 * (i % 3)), 1.0 * (i / 3), g.y * 0.5)
		_heuballen(root, pos)


static func _waschplatz(root: Node3D, g: Vector2, stufe: int) -> void:
	_platte(root, g, PFLASTER)
	_quader(root, Vector3(g.x * 0.2, 1.2, g.y * 0.15), Vector3(0.25, 2.4, 0.25), METALL)
	_quader(root, Vector3(g.x * 0.2 + 0.5, 2.3, g.y * 0.15), Vector3(1.2, 0.15, 0.15), METALL)
	_wasserflaeche(root, Vector3(g.x / 2, 0.16, g.y / 2), Vector2(g.x * 0.5, g.y * 0.5))
	if stufe >= 2:
		_quader(root, Vector3(g.x * 0.85, 0.7, g.y * 0.2), Vector3(0.8, 1.4, 0.5), SCHEUNE_ROT)
	if stufe >= 3:
		_quader(root, Vector3(g.x * 0.85, 0.5, g.y * 0.8), Vector3(1.0, 1.0, 0.6), DACH_TEAL)


static func _fuehranlage(root: Node3D, g: Vector2, stufe: int) -> void:
	var mitte := Vector3(g.x / 2, 0.0, g.y / 2)
	var radius := minf(g.x, g.y) * 0.42
	_zylinder(root, mitte + Vector3(0, 0.06, 0), radius, 0.12, SAND)
	_quader(root, mitte + Vector3(0, 1.6, 0), Vector3(0.3, 3.2, 0.3), HOLZ_DUNKEL)
	var arme := 2 + stufe
	for i in arme:
		var winkel := TAU * float(i) / float(arme)
		var arm := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(radius, 0.12, 0.12)
		mesh.material = _mat(HOLZ_HELL)
		arm.mesh = mesh
		arm.position = mitte + Vector3(cos(winkel) * radius * 0.5, 2.9, sin(winkel) * radius * 0.5)
		arm.rotation.y = -winkel
		root.add_child(arm)


static func _reithalle(root: Node3D, g: Vector2, stufe: int) -> void:
	var hoehe := 5.0
	_quader(root, Vector3(g.x / 2, hoehe / 2, g.y / 2), Vector3(g.x, hoehe, g.y), HAUS_CREME)
	_satteldach(root, g, hoehe, DACH_TEAL)
	_quader(root, Vector3(g.x / 2, 2.2, g.y + 0.08), Vector3(4.2, 4.4, 0.16), HOLZ_DUNKEL)
	# Fensterband ab Stufe 2 (Spiegelwand-Ausbau von außen sichtbar).
	if stufe >= 2:
		_quader(
			root,
			Vector3(g.x / 2, hoehe * 0.72, g.y + 0.06),
			Vector3(g.x * 0.7, 1.0, 0.1),
			Color(0.72, 0.86, 0.92)
		)
	if stufe >= 3:
		_fahne_bei(root, Vector3(g.x * 0.08, hoehe + 0.2, g.y * 0.1))


static func _parcours(root: Node3D, g: Vector2, stufe: int) -> void:
	_platte(root, g, SAND)
	var huerden := 2 + stufe
	for i in huerden:
		var pos := Vector3(g.x * (0.2 + 0.6 * (i % 2)), 0.0, g.y * (0.15 + 0.7 * i / huerden))
		for seite: float in [-0.9, 0.9]:
			_quader(root, pos + Vector3(seite, 0.5, 0), Vector3(0.18, 1.0, 0.18), HOLZ_DUNKEL)
		_quader(
			root,
			pos + Vector3(0, 0.62 + 0.1 * (i % 3), 0),
			Vector3(1.8, 0.14, 0.14),
			SCHEUNE_ROT if i % 2 == 0 else DACH_CREME
		)
	if stufe >= 3:
		_quader(root, Vector3(g.x * 0.94, 1.1, g.y * 0.08), Vector3(0.5, 2.2, 0.5), METALL)


static func _sattelkammer(root: Node3D, g: Vector2, stufe: int) -> void:
	var hoehe := 2.8
	_quader(root, Vector3(g.x / 2, hoehe / 2, g.y / 2), Vector3(g.x, hoehe, g.y), HOLZ_HELL)
	_satteldach(root, g, hoehe, DACH_CREME)
	_quader(root, Vector3(g.x / 2, 1.0, g.y + 0.06), Vector3(1.2, 2.0, 0.12), HOLZ_DUNKEL)
	if stufe >= 2:
		_quader(
			root,
			Vector3(g.x * 0.2, 1.7, g.y + 0.06),
			Vector3(0.9, 0.9, 0.12),
			Color(0.72, 0.86, 0.92)
		)
	if stufe >= 3:
		_strohpuppe_bei(root, Vector3(g.x + 0.6, 0.0, g.y * 0.5))


static func _zuchtstall(root: Node3D, g: Vector2, stufe: int) -> void:
	var hoehe := 3.4
	_quader(root, Vector3(g.x / 2, hoehe / 2, g.y / 2), Vector3(g.x, hoehe, g.y), SCHEUNE_ROT)
	_satteldach(root, g, hoehe, DACH_CREME)
	_quader(root, Vector3(g.x / 2, 1.2, g.y + 0.07), Vector3(2.4, 2.4, 0.14), HOLZ_DUNKEL)
	var herzen := stufe
	for i in herzen:
		_kugel(root, Vector3(g.x * (0.3 + 0.2 * i), hoehe + 0.5, g.y * 0.5), 0.22, BLUME_ROSA)


static func _fohlenweide(root: Node3D, g: Vector2, _stufe: int) -> void:
	_platte(root, g, WIESE_SATT)
	for i in 4:
		_kugel(root, Vector3(g.x * (0.2 + 0.2 * i), 0.2, g.y * 0.5), 0.2, WIESE_GRUEN)
	_kugel(root, Vector3(g.x * 0.5, 0.55, g.y * 0.3), 0.5, HOLZ_HELL)


static func _tribuene(root: Node3D, g: Vector2, stufe: int) -> void:
	var reihen := 1 + stufe
	for i in reihen:
		_quader(
			root,
			Vector3(g.x / 2, 0.3 + 0.6 * i, g.y * (0.75 - 0.22 * i)),
			Vector3(g.x, 0.6, g.y * 0.24),
			HOLZ_HELL if i % 2 == 0 else HOLZ_DUNKEL
		)
	if stufe >= 2:
		_quader(root, Vector3(g.x / 2, 2.6, g.y * 0.35), Vector3(g.x, 0.15, g.y * 0.6), DACH_TEAL)
		for seite: float in [0.06, 0.94]:
			_quader(
				root, Vector3(g.x * seite, 1.3, g.y * 0.35), Vector3(0.2, 2.6, 0.2), HOLZ_DUNKEL
			)


# ── Deko / Böden ─────────────────────────────────────────────────────────────


static func _beet(root: Node3D, farbe: Color) -> void:
	_quader(root, Vector3(ZELLE / 2, 0.15, ZELLE / 2), Vector3(2.2, 0.3, 2.2), HOLZ_DUNKEL)
	for i in 4:
		var pos := Vector3(
			ZELLE / 2 - 0.6 + 0.4 * i, 0.42, ZELLE / 2 + (0.4 if i % 2 == 0 else -0.4)
		)
		_kugel(root, pos, 0.2, farbe)


static func _bank(root: Node3D) -> void:
	var mitte := Vector3(ZELLE / 2, 0.0, ZELLE / 2)
	_quader(root, mitte + Vector3(0, 0.45, 0), Vector3(1.8, 0.12, 0.5), HOLZ_HELL)
	_quader(root, mitte + Vector3(0, 0.75, -0.22), Vector3(1.8, 0.5, 0.1), HOLZ_HELL)
	for seite: float in [-0.7, 0.7]:
		_quader(root, mitte + Vector3(seite, 0.22, 0), Vector3(0.14, 0.44, 0.44), HOLZ_DUNKEL)


static func _laterne(root: Node3D) -> void:
	var mitte := Vector3(ZELLE / 2, 0.0, ZELLE / 2)
	_quader(root, mitte + Vector3(0, 1.1, 0), Vector3(0.14, 2.2, 0.14), METALL)
	_kugel(root, mitte + Vector3(0, 2.35, 0), 0.26, BLUME_GELB)


static func _fahne(root: Node3D) -> void:
	_fahne_bei(root, Vector3(ZELLE / 2, 0.0, ZELLE / 2))


static func _fahne_bei(root: Node3D, fuss: Vector3) -> void:
	_quader(root, fuss + Vector3(0, 1.6, 0), Vector3(0.12, 3.2, 0.12), HOLZ_DUNKEL)
	_quader(root, fuss + Vector3(0.55, 2.9, 0), Vector3(1.0, 0.6, 0.05), SCHEUNE_ROT)


static func _kuebel(root: Node3D) -> void:
	var mitte := Vector3(ZELLE / 2, 0.0, ZELLE / 2)
	_zylinder(root, mitte + Vector3(0, 0.3, 0), 0.4, 0.6, Color(0.8, 0.5, 0.4))
	_kugel(root, mitte + Vector3(0, 0.8, 0), 0.35, BLUME_ROSA)


static func _vogelhaus(root: Node3D) -> void:
	var mitte := Vector3(ZELLE / 2, 0.0, ZELLE / 2)
	_quader(root, mitte + Vector3(0, 0.9, 0), Vector3(0.12, 1.8, 0.12), HOLZ_DUNKEL)
	_quader(root, mitte + Vector3(0, 1.95, 0), Vector3(0.6, 0.5, 0.5), HOLZ_HELL)
	_quader(root, mitte + Vector3(0, 2.3, 0), Vector3(0.75, 0.12, 0.65), DACH_TEAL)


static func _heuballen(root: Node3D, pos: Vector3) -> void:
	var ballen := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.7
	mesh.bottom_radius = 0.7
	mesh.height = 1.2
	mesh.radial_segments = 12
	mesh.material = _mat(HEU_GELB)
	ballen.mesh = mesh
	ballen.position = pos + Vector3(0.0, 0.7, 0.0)
	ballen.rotation.z = PI / 2.0
	root.add_child(ballen)


static func _wegweiser(root: Node3D) -> void:
	var mitte := Vector3(ZELLE / 2, 0.0, ZELLE / 2)
	_quader(root, mitte + Vector3(0, 1.0, 0), Vector3(0.14, 2.0, 0.14), HOLZ_DUNKEL)
	_quader(root, mitte + Vector3(0.4, 1.7, 0), Vector3(0.9, 0.3, 0.08), DACH_CREME)
	_quader(root, mitte + Vector3(-0.35, 1.3, 0), Vector3(0.8, 0.3, 0.08), DACH_CREME)


static func _strohpuppe(root: Node3D) -> void:
	_strohpuppe_bei(root, Vector3(ZELLE / 2, 0.0, ZELLE / 2))


static func _strohpuppe_bei(root: Node3D, fuss: Vector3) -> void:
	_quader(root, fuss + Vector3(0, 0.9, 0), Vector3(0.14, 1.8, 0.14), HOLZ_DUNKEL)
	_quader(root, fuss + Vector3(0, 1.35, 0), Vector3(1.2, 0.12, 0.12), HOLZ_DUNKEL)
	_kugel(root, fuss + Vector3(0, 1.05, 0), 0.42, HEU_GELB)
	_kugel(root, fuss + Vector3(0, 1.85, 0), 0.3, HAUS_CREME)


static func _bodenplatte(root: Node3D, farbe: Color) -> void:
	_platte(root, Vector2(ZELLE, ZELLE), farbe)


static func _blumenwiese(root: Node3D) -> void:
	_platte(root, Vector2(ZELLE, ZELLE), WIESE_SATT)
	for i in 5:
		var pos := Vector3(0.5 + 0.5 * i, 0.14, 0.6 + fposmod(i * 0.9, 1.8))
		_kugel(root, pos, 0.11, BLUME_ROSA if i % 2 == 0 else BLUME_GELB)


static func _platzhalter(root: Node3D, g: Vector2) -> void:
	_quader(root, Vector3(g.x / 2, 0.5, g.y / 2), Vector3(g.x * 0.9, 1.0, g.y * 0.9), HOLZ_HELL)


# ── Helfer ───────────────────────────────────────────────────────────────────


static func _platte(root: Node3D, g: Vector2, farbe: Color) -> void:
	_quader(root, Vector3(g.x / 2, 0.05, g.y / 2), Vector3(g.x - 0.08, 0.1, g.y - 0.08), farbe)


static func _satteldach(root: Node3D, g: Vector2, hoehe: float, farbe: Color) -> void:
	var dach := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = Vector3(g.x + 0.5, minf(g.x, g.y) * 0.35, g.y + 0.5)
	mesh.material = _mat(farbe)
	dach.mesh = mesh
	dach.position = Vector3(g.x / 2, hoehe + mesh.size.y / 2, g.y / 2)
	root.add_child(dach)


static func _quader(root: Node3D, pos: Vector3, groesse: Vector3, farbe: Color) -> void:
	var kiste := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = groesse
	mesh.material = _mat(farbe)
	kiste.mesh = mesh
	kiste.position = pos
	root.add_child(kiste)


static func _kugel(root: Node3D, pos: Vector3, radius: float, farbe: Color) -> void:
	var kugel := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh.material = _mat(farbe)
	kugel.mesh = mesh
	kugel.position = pos
	root.add_child(kugel)


static func _zylinder(
	root: Node3D, pos: Vector3, radius: float, hoehe: float, farbe: Color
) -> void:
	var zyl := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = hoehe
	mesh.radial_segments = 16
	mesh.material = _mat(farbe)
	zyl.mesh = mesh
	zyl.position = pos
	root.add_child(zyl)


static func _wasserflaeche(root: Node3D, pos: Vector3, g: Vector2) -> void:
	var wasser := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = g
	var mat := StandardMaterial3D.new()
	mat.albedo_color = WASSER_BLAU
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.1
	mesh.material = mat
	wasser.mesh = mesh
	wasser.position = pos
	root.add_child(wasser)


static func _mat(farbe: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = farbe
	mat.roughness = 0.9
	return mat
