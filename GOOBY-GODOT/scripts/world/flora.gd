class_name WeltFlora
extends RefCounted
## Prozedurale Pflanzen-Meshes (WELT-1) — kleine Low-Poly-Meshes mit
## Vertex-Farben, gebaut aus SurfaceTool-Dreiecken (KEINE Texturen, keine
## Assets). Gedacht als MultiMesh-Füllung für die Vegetations-SCHICHTEN
## der offenen Welt: Lavendel-Büschel, Farnwedel, Pilze, Binsen (Moor),
## Kornhalme und Blüten-Tupfer. Alle Fabriken sind deterministisch
## (Form kommt nur aus Konstanten) und PURE genug für Headless-Tests:
## `beschreibungen()` nennt jede Sorte mit erwarteter Höhe.

const LAVENDEL_LILA := Color(0.62, 0.48, 0.86)
const LAVENDEL_STIEL := Color(0.45, 0.62, 0.42)
const FARN_GRUEN := Color(0.36, 0.58, 0.34)
const PILZ_HUT := Color(0.82, 0.36, 0.3)
const PILZ_FUSS := Color(0.92, 0.88, 0.78)
const BINSE_BRAUN := Color(0.52, 0.44, 0.3)
const BINSE_KOLBEN := Color(0.38, 0.28, 0.18)
const KORN_GOLD := Color(0.89, 0.76, 0.42)
const SEEROSE_GRUEN := Color(0.4, 0.66, 0.42)
const SEEROSE_BLUETE := Color(0.97, 0.82, 0.9)

static var _cache: Dictionary = {}


## Sorten-Katalog: id → erwartete Mesh-Höhe in Metern (fürs Testen und
## fürs Skalieren beim Streuen).
static func beschreibungen() -> Dictionary:
	return {
		"lavendel": 0.75,
		"farn": 0.55,
		"pilz": 0.35,
		"binse": 1.15,
		"korn": 1.05,
		"seerose": 0.08,
	}


## Mesh zu einer Sorten-Id (gecacht; null bei unbekannter Id).
static func mesh(id: String) -> Mesh:
	if _cache.has(id):
		return _cache[id]
	var out: Mesh = null
	match id:
		"lavendel":
			out = _lavendel()
		"farn":
			out = _farn()
		"pilz":
			out = _pilz()
		"binse":
			out = _binse()
		"korn":
			out = _korn()
		"seerose":
			out = _seerose()
	_cache[id] = out
	return out


## Material für Flora-MultiMeshes: Vertex-Farben, matt, beidseitig
## (die Blatt-Quads haben keine Rückseite).
static func material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


static func reset_for_tests() -> void:
	_cache = {}


## ------------------------------------------------------------- Fabriken


## Lavendel: 5 Stiele mit lila Blüten-Rauten obenauf.
static func _lavendel() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 5:
		var w := float(i) / 5.0 * TAU
		var fuss := Vector3(cos(w) * 0.13, 0.0, sin(w) * 0.13)
		var kopf := fuss * 1.6 + Vector3(0.0, 0.55, 0.0)
		_halm(st, fuss, kopf, 0.02, LAVENDEL_STIEL)
		_raute(st, kopf, 0.075, 0.2, LAVENDEL_LILA)
	return _fertig(st)


## Farn: 6 Wedel rundum, jeder als Bogen aus zwei Dreiecken — steigt
## kniehoch auf (~0,55 m) und kippt zur Spitze hin ab.
static func _farn() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 6:
		var w := float(i) / 6.0 * TAU + 0.3
		var richtung := Vector3(cos(w), 0.0, sin(w))
		var quer := Vector3(-richtung.z, 0.0, richtung.x) * 0.1
		var fuss := Vector3(0.0, 0.05, 0.0)
		var knick := richtung * 0.3 + Vector3(0.0, 0.55 - 0.03 * float(i % 3), 0.0)
		var spitze := richtung * 0.66 + Vector3(0.0, 0.34, 0.0)
		var farbe := FARN_GRUEN.lerp(Color.WHITE, 0.08 * float(i % 3))
		_dreieck(st, [fuss + quer, fuss - quer, knick], farbe)
		_dreieck(st, [knick + quer * 0.6, knick - quer * 0.6, spitze], farbe.darkened(0.12))
	return _fertig(st)


## Pilz: heller Fuß-Halm + rotes Hut-Sechseck.
static func _pilz() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_halm(st, Vector3.ZERO, Vector3(0.0, 0.22, 0.0), 0.05, PILZ_FUSS)
	var kopf := Vector3(0.0, 0.24, 0.0)
	var spitze := Vector3(0.0, 0.35, 0.0)
	for i in 6:
		var w0 := float(i) / 6.0 * TAU
		var w1 := float(i + 1) / 6.0 * TAU
		var a := kopf + Vector3(cos(w0), 0.0, sin(w0)) * 0.16
		var b := kopf + Vector3(cos(w1), 0.0, sin(w1)) * 0.16
		_dreieck(st, [a, b, spitze], PILZ_HUT)
		_dreieck(st, [b, a, kopf], PILZ_HUT.darkened(0.25))
	return _fertig(st)


## Binse (Moor): 4 hohe Halme, zwei davon mit braunem Kolben.
static func _binse() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 4:
		var w := float(i) / 4.0 * TAU + 0.6
		var fuss := Vector3(cos(w) * 0.08, 0.0, sin(w) * 0.08)
		var hoch := 1.15 - 0.14 * float(i % 2)
		var kopf := fuss + Vector3(cos(w) * 0.06, hoch, sin(w) * 0.06)
		_halm(st, fuss, kopf, 0.018, BINSE_BRAUN)
		if i % 2 == 0:
			_raute(st, kopf, 0.045, 0.2, BINSE_KOLBEN)
	return _fertig(st)


## Kornhalm: 3 goldene Halme mit Ähren-Rauten.
static func _korn() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 3:
		var w := float(i) / 3.0 * TAU + 1.1
		var fuss := Vector3(cos(w) * 0.07, 0.0, sin(w) * 0.07)
		var kopf := fuss + Vector3(cos(w) * 0.1, 0.92, sin(w) * 0.1)
		_halm(st, fuss, kopf, 0.016, KORN_GOLD.darkened(0.15))
		_raute(st, kopf, 0.05, 0.13, KORN_GOLD)
	return _fertig(st)


## Seerose: flaches Blatt-Sechseck + kleine Blüte (für Moor/Bergsee).
static func _seerose() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mitte := Vector3(0.0, 0.02, 0.0)
	for i in 6:
		var w0 := float(i) / 6.0 * TAU
		var w1 := float(i + 1) / 6.0 * TAU
		var a := Vector3(cos(w0), 0.0, sin(w0)) * 0.34 + mitte
		var b := Vector3(cos(w1), 0.0, sin(w1)) * 0.34 + mitte
		_dreieck(st, [mitte, a, b], SEEROSE_GRUEN)
	_raute(st, Vector3(0.1, 0.03, 0.05), 0.07, 0.05, SEEROSE_BLUETE)
	return _fertig(st)


## ------------------------------------------------------------- Werkzeug


## Halm: zwei gekreuzte Quads von `fuss` nach `kopf`.
static func _halm(st: SurfaceTool, fuss: Vector3, kopf: Vector3, halb: float, farbe: Color) -> void:
	for achse: Vector3 in [Vector3(halb, 0.0, 0.0), Vector3(0.0, 0.0, halb)]:
		_dreieck(st, [fuss - achse, fuss + achse, kopf + achse], farbe)
		_dreieck(st, [fuss - achse, kopf + achse, kopf - achse], farbe)


## Stehende Doppel-Raute (Blüte/Kolben/Ähre) am Punkt `pos`.
static func _raute(st: SurfaceTool, pos: Vector3, halb: float, hoch: float, farbe: Color) -> void:
	var oben := pos + Vector3(0.0, hoch, 0.0)
	var unten := pos - Vector3(0.0, hoch * 0.4, 0.0)
	for achse: Vector3 in [Vector3(halb, 0.0, 0.0), Vector3(0.0, 0.0, halb)]:
		_dreieck(st, [unten, pos + achse, oben], farbe)
		_dreieck(st, [oben, pos - achse, unten], farbe)


static func _dreieck(st: SurfaceTool, punkte: Array, farbe: Color) -> void:
	var normal := Vector3.UP
	var kante_a: Vector3 = punkte[1] - punkte[0]
	var kante_b: Vector3 = punkte[2] - punkte[0]
	var kreuz := kante_a.cross(kante_b)
	if kreuz.length_squared() > 0.000001:
		normal = kreuz.normalized()
	for p: Vector3 in punkte:
		st.set_color(farbe)
		st.set_normal(normal)
		st.add_vertex(p)


static func _fertig(st: SurfaceTool) -> ArrayMesh:
	var mesh := st.commit()
	mesh.surface_set_material(0, material())
	return mesh
