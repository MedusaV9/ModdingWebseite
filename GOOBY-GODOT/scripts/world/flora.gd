class_name WeltFlora
extends RefCounted
## Prozedurale Pflanzen-Meshes (WELT-1, VIS-1-Überarbeitung nach Trailer-
## Review „Korn sieht aus wie gelbe Pfeile"): Korn und Lavendel sind jetzt
## texturierte BILLBOARD-BÜSCHEL (drei gekreuzte Quads, Ähren-/Blüten-
## Textur aus tools/blender/props/gen_flora_billboards.py, Wind-Shader
## flora_wind.gdshader) — echte Halme mit Ähre, unten grün, oben golden,
## statt Rauten-Spitzen auf Stangen. Farn, Pilz, Binse und Seerose bleiben
## kleine Low-Poly-Meshes mit Vertex-Farben (SurfaceTool, keine Texturen).
## Alle Fabriken sind deterministisch und PURE genug für Headless-Tests:
## `beschreibungen()` nennt jede Sorte mit erwarteter Höhe. Der
## RanchWetterController treibt `wind_materialien()` (Böen-Uniform).

const FARN_GRUEN := Color(0.36, 0.58, 0.34)
const PILZ_HUT := Color(0.82, 0.36, 0.3)
const PILZ_FUSS := Color(0.92, 0.88, 0.78)
const BINSE_GRUEN := Color(0.44, 0.54, 0.34)
const BINSE_BRAUN := Color(0.52, 0.44, 0.3)
const BINSE_KOLBEN := Color(0.38, 0.28, 0.18)
const KORN_GOLD := Color(0.89, 0.76, 0.42)
const SEEROSE_GRUEN := Color(0.4, 0.66, 0.42)
const SEEROSE_BLUETE := Color(0.97, 0.82, 0.9)

const WIND_SHADER := "res://scripts/ranch/welt/flora_wind.gdshader"
const KORN_TEXTUR := "res://assets/ranch/welt/korn_bueschel.png"
const LAVENDEL_TEXTUR := "res://assets/ranch/welt/lavendel_busch.png"

static var _cache: Dictionary = {}
static var _wind_mats: Array[ShaderMaterial] = []


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
			out = _bueschel(LAVENDEL_TEXTUR, 0.85, 0.75)
		"farn":
			out = _farn()
		"pilz":
			out = _pilz()
		"binse":
			out = _binse()
		"korn":
			out = _bueschel(KORN_TEXTUR, 1.3, 1.05)
		"seerose":
			out = _seerose()
	_cache[id] = out
	return out


## Material für Vertex-Farben-Flora: matt, beidseitig (Blatt-Quads haben
## keine Rückseite).
static func material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## Alle Wind-Shader-Materialien der Billboard-Sorten — der Wetter-
## Controller setzt hier pro Tick die Böen-Stärke (`wind`).
static func wind_materialien() -> Array[ShaderMaterial]:
	return _wind_mats


static func reset_for_tests() -> void:
	_cache = {}
	_wind_mats = []


## ------------------------------------------------------------- Fabriken


## Billboard-Büschel: drei um 60° gekreuzte Quads mit Alphatextur und
## Wind-Shader — aus jeder Blickrichtung ein dichtes Pflanzenbüschel.
static func _bueschel(textur_pfad: String, breite: float, hoch: float) -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 3:
		var w := float(i) * PI / 3.0
		var achse := Vector3(cos(w), 0.0, sin(w)) * (breite / 2.0)
		# UV: v=0 = Texturoberkante, die Pflanzen-Basis liegt bei v=1.
		var ecken: Array[Vector3] = [
			-achse + Vector3(0.0, hoch, 0.0),
			achse + Vector3(0.0, hoch, 0.0),
			achse,
			-achse,
		]
		var uvs: Array[Vector2] = [
			Vector2(0.0, 0.0), Vector2(1.0, 0.0), Vector2(1.0, 1.0), Vector2(0.0, 1.0)
		]
		for idx: int in [0, 1, 2, 0, 2, 3]:
			st.set_normal(Vector3.UP)
			st.set_uv(uvs[idx])
			st.add_vertex(ecken[idx])
	var mesh := st.commit()
	mesh.surface_set_material(0, _wind_material(textur_pfad, hoch))
	return mesh


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


## Binse (Moor, VIS-1 voller): 7 Halme mit Farbverlauf grün→braun, drei
## davon tragen einen DICKEN Rohrkolben (kurzer brauner Doppel-Halm) mit
## heller Spitze — Schilfbüschel statt dünner Stangen.
static func _binse() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 7:
		var w := float(i) / 7.0 * TAU + 0.6
		var radius := 0.09 + 0.03 * float(i % 2)
		var fuss := Vector3(cos(w) * radius, 0.0, sin(w) * radius)
		var hoch := 1.15 - 0.16 * float(i % 3)
		var kopf := fuss + Vector3(cos(w) * 0.1, hoch, sin(w) * 0.1)
		_halm_verlauf(st, fuss, kopf, 0.02, BINSE_GRUEN, BINSE_BRAUN)
		if i % 2 == 0:
			var kolben_fuss := kopf - Vector3(0.0, 0.02, 0.0)
			var kolben_kopf := kopf + Vector3(0.0, 0.16, 0.0)
			_halm(st, kolben_fuss, kolben_kopf, 0.045, BINSE_KOLBEN)
			_halm(st, kolben_kopf, kolben_kopf + Vector3(0.0, 0.07, 0.0), 0.012, BINSE_BRAUN)
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


## Wind-ShaderMaterial je Textur (gecacht + in der Wind-Registry).
static func _wind_material(textur_pfad: String, hoch: float) -> Material:
	var mat := ShaderMaterial.new()
	mat.shader = load(WIND_SHADER)
	if ResourceLoader.exists(textur_pfad):
		mat.set_shader_parameter("albedo_tex", load(textur_pfad))
	mat.set_shader_parameter("hoehe", hoch)
	_wind_mats.append(mat)
	return mat


## Halm: zwei gekreuzte Quads von `fuss` nach `kopf`.
static func _halm(st: SurfaceTool, fuss: Vector3, kopf: Vector3, halb: float, farbe: Color) -> void:
	for achse: Vector3 in [Vector3(halb, 0.0, 0.0), Vector3(0.0, 0.0, halb)]:
		_dreieck(st, [fuss - achse, fuss + achse, kopf + achse], farbe)
		_dreieck(st, [fuss - achse, kopf + achse, kopf - achse], farbe)


## Halm mit Farbverlauf: unten `farbe_fuss`, oben `farbe_kopf`.
static func _halm_verlauf(
	st: SurfaceTool, fuss: Vector3, kopf: Vector3, halb: float, farbe_fuss: Color, farbe_kopf: Color
) -> void:
	for achse: Vector3 in [Vector3(halb, 0.0, 0.0), Vector3(0.0, 0.0, halb)]:
		_dreieck_farben(
			st, [fuss - achse, fuss + achse, kopf + achse], [farbe_fuss, farbe_fuss, farbe_kopf]
		)
		_dreieck_farben(
			st, [fuss - achse, kopf + achse, kopf - achse], [farbe_fuss, farbe_kopf, farbe_kopf]
		)


## Stehende Doppel-Raute (Blüte/Kolben) am Punkt `pos`.
static func _raute(st: SurfaceTool, pos: Vector3, halb: float, hoch: float, farbe: Color) -> void:
	var oben := pos + Vector3(0.0, hoch, 0.0)
	var unten := pos - Vector3(0.0, hoch * 0.4, 0.0)
	for achse: Vector3 in [Vector3(halb, 0.0, 0.0), Vector3(0.0, 0.0, halb)]:
		_dreieck(st, [unten, pos + achse, oben], farbe)
		_dreieck(st, [oben, pos - achse, unten], farbe)


static func _dreieck(st: SurfaceTool, punkte: Array, farbe: Color) -> void:
	_dreieck_farben(st, punkte, [farbe, farbe, farbe])


static func _dreieck_farben(st: SurfaceTool, punkte: Array, farben: Array) -> void:
	var normal := Vector3.UP
	var kante_a: Vector3 = punkte[1] - punkte[0]
	var kante_b: Vector3 = punkte[2] - punkte[0]
	var kreuz := kante_a.cross(kante_b)
	if kreuz.length_squared() > 0.000001:
		normal = kreuz.normalized()
	for i in 3:
		st.set_color(farben[i])
		st.set_normal(normal)
		st.add_vertex(punkte[i])


static func _fertig(st: SurfaceTool) -> ArrayMesh:
	var mesh := st.commit()
	mesh.surface_set_material(0, material())
	return mesh
