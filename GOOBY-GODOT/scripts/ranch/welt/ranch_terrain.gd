class_name RanchTerrain
extends RefCounted
## Gelände-Bauer der Ranch-Region (RW-1, ausgebaut von WELT-1): setzt
## RanchGelaende.hoehe in Chunk-Meshes um — jetzt 8×8 Chunks über die
## GROSSE Karte, jeder Chunk mit ZWEI LOD-Stufen (nah fein / fern grob,
## Umschaltung über visibility_range, Skirts gegen LOD-Risse) und OHNE
## eigenen Schatten-Pass (Budget). Dazu: ALLE Feldwege in EINEM Mesh,
## alle Trampelpfade in einem zweiten (2 Draw-Calls statt ~30), See-,
## Bucht-, Bergsee- und Moortümpel-Wasser sowie das Bach-Wasserband.
## FB-2 Bodentextur-Variation bleibt: Vertex-Tints mischen Grasflecken,
## Erdstellen, Kies und Trampel-Erde; WELT-1 ergänzt Fels-SCHICHTUNG am
## Bergmassiv (Höhenbänder + Schneekappe), Schluchtwände, Sandstrand,
## Moor-Braun, Korngold und eine SAISON-Färbung (deterministisch aus dem
## Datum — Frühling frisch, Herbst bernstein, Winter blass).

const TEX_WIESE := "res://assets/ranch/texturen/wiese.png"
const TEX_FELDWEG := "res://assets/ranch/texturen/feldweg.png"
const TEX_WASSER := "res://assets/ranch/texturen/wasser.png"

const CHUNKS := 8
const ZELLEN_JE_CHUNK := 44
const ZELLEN_FERN := 11

## Ab diesem Abstand (m) übernimmt das grobe Fern-LOD eines Chunks.
const LOD_WECHSEL_M := 430.0

## Skirt-Tiefe (m): versteckt Risse zwischen LOD-Stufen benachbarter Chunks.
const SKIRT_M := 2.2

## Vertex-Tints (modulieren die Wiesen-Textur).
const TINT_WIESE := Color(1.0, 1.0, 1.0)
const TINT_WALD := Color(0.72, 0.82, 0.66)
const TINT_FELS := Color(1.06, 1.02, 0.94)
const TINT_UFER := Color(1.08, 1.0, 0.78)
## FB-2: sattes Grasbüschel-Grün, warme Erdstellen, Kies, Trampel-Erde.
const TINT_GRASFLECK := Color(0.84, 0.97, 0.74)
const TINT_ERDE := Color(1.05, 0.93, 0.72)
const TINT_KIES := Color(0.99, 0.97, 0.9)
const TINT_TRAMPEL := Color(1.02, 0.9, 0.7)
## WELT-1: Bergfels (hell/dunkel für Schichtbänder), Schnee, Sand, Moor,
## Korngold, Lavendel-Hauch.
const TINT_FELS_HELL := Color(0.98, 0.94, 0.88)
const TINT_FELS_DUNKEL := Color(0.72, 0.68, 0.64)
const TINT_SCHNEE := Color(1.22, 1.24, 1.28)
const TINT_SAND := Color(1.18, 1.1, 0.86)
const TINT_MOOR := Color(0.72, 0.69, 0.48)
const TINT_KORN := Color(1.16, 1.05, 0.66)
const TINT_LAVENDEL := Color(0.95, 0.9, 1.02)

## Trampelpfad-Tint reicht so weit über die Pfadkante hinaus (m).
const TRAMPEL_RAND_M := 2.5

## Saison-Multiplikatoren auf die Wiesen-Tints (nur Bewuchs, kein Fels/Sand).
const SAISON_TINT := {
	"fruehling": Color(0.97, 1.03, 0.94),
	"sommer": Color(1.0, 1.0, 1.0),
	"herbst": Color(1.08, 0.98, 0.82),
	"winter": Color(0.96, 0.97, 1.0),
}

var terrain_material: StandardMaterial3D
var weg_material: StandardMaterial3D
var trampel_material: StandardMaterial3D
var wasser_material: StandardMaterial3D
var moor_material: StandardMaterial3D

var saison := "sommer"

var _pfad_segmente: Array[Dictionary] = []


func _init(saison_id := "sommer") -> void:
	saison = saison_id if SAISON_TINT.has(saison_id) else "sommer"
	terrain_material = StandardMaterial3D.new()
	terrain_material.albedo_texture = _textur(TEX_WIESE)
	terrain_material.vertex_color_use_as_albedo = true
	terrain_material.roughness = 0.95
	weg_material = StandardMaterial3D.new()
	weg_material.albedo_texture = _textur(TEX_FELDWEG)
	weg_material.roughness = 0.95
	trampel_material = StandardMaterial3D.new()
	trampel_material.albedo_texture = _textur(TEX_FELDWEG)
	trampel_material.albedo_color = Color(0.86, 0.74, 0.58)
	trampel_material.roughness = 1.0
	wasser_material = StandardMaterial3D.new()
	wasser_material.albedo_texture = _textur(TEX_WASSER)
	wasser_material.albedo_color = Color(0.75, 0.9, 1.0, 0.86)
	wasser_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wasser_material.roughness = 0.12
	moor_material = StandardMaterial3D.new()
	moor_material.albedo_texture = _textur(TEX_WASSER)
	moor_material.albedo_color = Color(0.45, 0.55, 0.5, 0.9)
	moor_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	moor_material.roughness = 0.2
	for pfad: Dictionary in RanchEntdeckungen.alle_pfade():
		var punkte: Array = pfad["punkte"]
		for i in punkte.size() - 1:
			var a: Array = punkte[i]
			var b: Array = punkte[i + 1]
			(
				_pfad_segmente
				. append(
					{
						"a": Vector2(float(a[0]), float(a[1])),
						"b": Vector2(float(b[0]), float(b[1])),
						"halb": float(pfad["breite"]) / 2.0,
					}
				)
			)


## Saison aus einem ISO-Datum (deterministisch, PURE — Tests rechnen nach).
static func saison_von_datum(datum: String) -> String:
	var teile := datum.split("-")
	var monat := 6
	if teile.size() >= 2:
		monat = clampi(int(teile[1]), 1, 12)
	if monat <= 2 or monat == 12:
		return "winter"
	if monat <= 5:
		return "fruehling"
	if monat <= 8:
		return "sommer"
	return "herbst"


## Baut alle Gelände-Chunks unter `wurzel` (Namen: Chunk_x_z; je Chunk ein
## Nah- und ein Fern-LOD, Umschaltung über visibility_range).
func baue_chunks(wurzel: Node3D) -> void:
	var grenzen := RanchKarte.grenzen()
	var breite := grenzen.size.x / float(CHUNKS)
	var tiefe := grenzen.size.y / float(CHUNKS)
	for cx in CHUNKS:
		for cz in CHUNKS:
			var min_x := grenzen.position.x + float(cx) * breite
			var min_z := grenzen.position.y + float(cz) * tiefe
			var nah := _baue_chunk(min_x, min_z, breite, tiefe, ZELLEN_JE_CHUNK)
			nah.name = "Chunk_%d_%d" % [cx, cz]
			nah.visibility_range_end = LOD_WECHSEL_M
			wurzel.add_child(nah)
			var fern := _baue_chunk(min_x, min_z, breite, tiefe, ZELLEN_FERN)
			fern.name = "ChunkFern_%d_%d" % [cx, cz]
			fern.visibility_range_begin = LOD_WECHSEL_M
			wurzel.add_child(fern)


## ALLE Feldwege als EIN gebündeltes Band-Mesh (1 Draw-Call).
func baue_wege(wurzel: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for weg: Dictionary in RanchKarte.wege():
		var punkte := RanchKarte.wegpunkte(str(weg["von"]), str(weg["nach"]))
		_band_in(st, punkte, float(weg["breite"]), 0.12, false)
	var mi := _commit(st, weg_material)
	mi.name = "Feldwege"
	wurzel.add_child(mi)


## Alle Trampelpfade zu den Fundorten als EIN Mesh (FB-2: schmale
## Erdspuren, die sichtbar „irgendwohin führen").
func baue_trampelpfade(wurzel: Node3D) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for pfad: Dictionary in RanchEntdeckungen.alle_pfade():
		var punkte: Array[Vector3] = []
		for paar: Array in pfad["punkte"]:
			var x := float(paar[0])
			var z := float(paar[1])
			punkte.append(Vector3(x, RanchGelaende.hoehe(x, z), z))
		_band_in(st, punkte, float(pfad["breite"]), 0.08, false)
	var mi := _commit(st, trampel_material)
	mi.name = "Trampelpfade"
	wurzel.add_child(mi)


## Wasserflächen: See + Strand-Bucht + Bergsee (Scheiben), Moor-Tümpel
## (ein MultiMesh) und das Bach-Wasserband.
func baue_wasser(wurzel: Node3D) -> void:
	var see := RanchKarte.zone("see")
	var see_mitte: Array = see["see_mitte"]
	_wasser_scheibe(
		wurzel,
		"SeeWasser",
		Vector3(float(see_mitte[0]), RanchGelaende.WASSER_HOEHE, float(see_mitte[1])),
		float(see["see_radius"]) * 1.9,
		wasser_material
	)
	var strand := RanchKarte.zone("strand")
	if not strand.is_empty():
		var bucht: Array = strand["bucht_mitte"]
		_wasser_scheibe(
			wurzel,
			"BuchtWasser",
			Vector3(float(bucht[0]), RanchGelaende.WASSER_HOEHE, float(bucht[1])),
			float(strand["bucht_radius"]) * 0.85,
			wasser_material
		)
	var berg := RanchKarte.zone("bergmassiv")
	if not berg.is_empty():
		var bs: Array = berg["bergsee_mitte"]
		_wasser_scheibe(
			wurzel,
			"BergseeWasser",
			Vector3(float(bs[0]), float(berg["bergsee_wasser"]), float(bs[1])),
			float(berg["bergsee_radius"]),
			wasser_material
		)
	_baue_tuempel(wurzel)
	var bach: Dictionary = RanchKarte.karte()["bach"]
	var punkte: Array[Vector3] = []
	for paar: Array in bach["punkte"]:
		var x := float(paar[0])
		var z := float(paar[1])
		punkte.append(Vector3(x, RanchGelaende.bach_wasserspiegel(x, z), z))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_band_in(st, punkte, float(bach["breite"]) + 2.5, 0.0, true)
	var band := _commit(st, wasser_material)
	band.name = "BachWasser"
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wurzel.add_child(band)


## ----------------------------------------------------------------- intern


func _wasser_scheibe(
	wurzel: Node3D, scheiben_name: String, pos: Vector3, radius: float, mat: Material
) -> void:
	var scheibe := MeshInstance3D.new()
	scheibe.name = scheiben_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.05
	mesh.radial_segments = 40
	mesh.material = mat
	scheibe.mesh = mesh
	scheibe.position = pos
	scheibe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wurzel.add_child(scheibe)


## Moor-Tümpel: dunkle Wasserscheiben als EIN MultiMesh.
func _baue_tuempel(wurzel: Node3D) -> void:
	var moor := RanchKarte.zone("moor")
	if moor.is_empty():
		return
	var punkte: Array = moor["tuempel"]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var scheibe := CylinderMesh.new()
	scheibe.top_radius = 1.0
	scheibe.bottom_radius = 1.0
	scheibe.height = 0.04
	scheibe.radial_segments = 20
	scheibe.material = moor_material
	mm.mesh = scheibe
	mm.instance_count = punkte.size()
	for i in punkte.size():
		var p: Array = punkte[i]
		var x := float(p[0])
		var z := float(p[1])
		var r := RanchGelaende.TUEMPEL_RADIUS_M + 1.5 + float(i % 3)
		var basis := Basis.from_scale(Vector3(r, 1.0, r * (0.8 + 0.1 * float(i % 2))))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(x, -0.66, z)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "MoorTuempel"
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wurzel.add_child(mmi)


## Ein Chunk-LOD: Höhen-Raster (+1 Rand für Normalen), Vertex-Farben nach
## Zonen-Charakter, UV in Weltmetern, Skirt gegen LOD-Risse. Vertizes
## liegen relativ zur Chunk-Mitte (visibility_range misst am Ursprung).
func _baue_chunk(
	min_x: float, min_z: float, breite: float, tiefe: float, zellen: int
) -> MeshInstance3D:
	var n := zellen
	var dx := breite / float(n)
	var dz := tiefe / float(n)
	var mitte := Vector3(min_x + breite / 2.0, 0.0, min_z + tiefe / 2.0)
	var hoehen: Array[PackedFloat32Array] = []
	for iz in n + 3:
		var reihe := PackedFloat32Array()
		reihe.resize(n + 3)
		for ix in n + 3:
			reihe[ix] = RanchGelaende.hoehe(min_x + float(ix - 1) * dx, min_z + float(iz - 1) * dz)
		hoehen.append(reihe)
	var wald_rect := RanchKarte.zone_rect(RanchKarte.zone("waeldchen"))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in n + 1:
		for ix in n + 1:
			var x := min_x + float(ix) * dx
			var z := min_z + float(iz) * dz
			var h := hoehen[iz + 1][ix + 1]
			var d_x := hoehen[iz + 1][ix + 2] - hoehen[iz + 1][ix]
			var d_z := hoehen[iz + 2][ix + 1] - hoehen[iz][ix + 1]
			st.set_normal(Vector3(-d_x, 2.0 * (dx + dz), -d_z).normalized())
			st.set_color(_vertex_tint(x, z, h, wald_rect))
			st.set_uv(Vector2(x, z) / 17.0)
			st.add_vertex(Vector3(x, h, z) - mitte)
	for iz in n:
		for ix in n:
			var a := iz * (n + 1) + ix
			var b := a + 1
			var c := a + n + 1
			var d := c + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(c)
			st.add_index(b)
			st.add_index(d)
			st.add_index(c)
	_skirt_in(st, hoehen, min_x, min_z, dx, dz, n, mitte, wald_rect)
	var mesh := st.commit()
	mesh.surface_set_material(0, terrain_material)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = mitte
	# Budget: Gelände wirft keinen eigenen Schatten (Sonnen-Schatten reicht
	# 190 m — Baum-/Gebäude-Schatten bleiben, der Chunk-Schattenpass fällt).
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Skirt: Randvertizes um SKIRT_M nach unten gezogene Doppelreihe — deckt
## Risse zwischen Nah-/Fern-LOD benachbarter Chunks ab.
func _skirt_in(
	st: SurfaceTool,
	hoehen: Array[PackedFloat32Array],
	min_x: float,
	min_z: float,
	dx: float,
	dz: float,
	n: int,
	mitte: Vector3,
	wald_rect: Rect2
) -> void:
	var start := (n + 1) * (n + 1)
	var rand: Array[Vector2i] = []
	for ix in n + 1:
		rand.append(Vector2i(ix, 0))
	for iz in range(1, n + 1):
		rand.append(Vector2i(n, iz))
	for ix in range(n - 1, -1, -1):
		rand.append(Vector2i(ix, n))
	for iz in range(n - 1, 0, -1):
		rand.append(Vector2i(0, iz))
	for i in rand.size():
		var zelle := rand[i]
		var x := min_x + float(zelle.x) * dx
		var z := min_z + float(zelle.y) * dz
		var h := hoehen[zelle.y + 1][zelle.x + 1]
		var tint := _vertex_tint(x, z, h, wald_rect)
		st.set_normal(Vector3.UP)
		st.set_color(tint)
		st.set_uv(Vector2(x, z) / 17.0)
		st.add_vertex(Vector3(x, h, z) - mitte)
		st.set_normal(Vector3.UP)
		st.set_color(tint)
		st.set_uv(Vector2(x, z) / 17.0)
		st.add_vertex(Vector3(x, h - SKIRT_M, z) - mitte)
	var anzahl := rand.size()
	for i in anzahl:
		var a := start + i * 2
		var b := start + ((i + 1) % anzahl) * 2
		st.add_index(a)
		st.add_index(a + 1)
		st.add_index(b)
		st.add_index(b)
		st.add_index(a + 1)
		st.add_index(b + 1)


func _vertex_tint(x: float, z: float, h: float, wald_rect: Rect2) -> Color:
	var tint := TINT_WIESE
	var bewuchs := 1.0
	# FB-2 Bodentextur-Variation: erst die Wiesen-Flecken, dann gewinnt
	# der Zonen-Charakter (Wald/Fels/Ufer/Sand/Moor/Korn) wie gehabt.
	tint = tint.lerp(TINT_GRASFLECK, _fleck(x, z, 0.043, 0.037, 1.9) * 0.65)
	tint = tint.lerp(TINT_ERDE, _fleck(x, z, 0.029, 0.033, 4.7) * 0.7)
	var weg_faktor := RanchGelaende.weg_glaettung(x, z)
	if weg_faktor < 0.98:
		tint = tint.lerp(TINT_KIES, clampf((1.0 - weg_faktor) * 0.7, 0.0, 0.6))
	var trampel := _trampel_naehe(x, z)
	if trampel > 0.0:
		tint = tint.lerp(TINT_TRAMPEL, trampel * 0.8)
	if wald_rect.has_point(Vector2(x, z)):
		tint = tint.lerp(TINT_WALD, 0.8)
	tint = _zonen_tint(x, z, tint)
	# Bergfels mit SCHICHTUNG: ab ~26 m mischt Fels hinein, Höhenbänder
	# wechseln hell/dunkel, ab ~78 m liegt Schnee.
	if h > 14.0 and h <= 26.0:
		tint = tint.lerp(TINT_FELS, clampf((h - 14.0) / 10.0, 0.0, 0.85))
	elif h > 26.0:
		var fels_anteil := clampf((h - 26.0) / 12.0, 0.0, 1.0)
		var band := 0.5 + 0.5 * sin(h * 0.55 + sin(x * 0.05) * 0.6 + sin(z * 0.045) * 0.6)
		var fels := TINT_FELS_HELL.lerp(TINT_FELS_DUNKEL, band * 0.75)
		tint = tint.lerp(fels, 0.55 + 0.45 * fels_anteil)
		bewuchs = 1.0 - fels_anteil
		if h > 78.0:
			tint = tint.lerp(TINT_SCHNEE, clampf((h - 78.0) / 9.0, 0.0, 0.9))
	if RanchGelaende.schlucht_kerbe(x, z) > 2.0:
		var wand := clampf((RanchGelaende.schlucht_kerbe(x, z) - 2.0) / 6.0, 0.0, 1.0)
		tint = tint.lerp(TINT_FELS_DUNKEL, wand * 0.8)
		bewuchs = minf(bewuchs, 1.0 - wand)
	var ueber_wasser := h - RanchGelaende.WASSER_HOEHE
	if ueber_wasser < 1.2:
		tint = tint.lerp(TINT_UFER, clampf(1.0 - ueber_wasser / 1.2, 0.0, 1.0))
	elif RanchGelaende.bach_kerbe(x, z) > 0.3:
		tint = tint.lerp(TINT_UFER, 0.6)
	if bewuchs > 0.05:
		tint = tint * (Color.WHITE.lerp(SAISON_TINT[saison], bewuchs))
	return tint


## Zonen-Farbstimmung der NEUEN Zonen (WELT-1): Sandstrand, Moor-Oliv,
## Korngold, warmer Obstgarten, Lavendel-Hauch, Bergsee-Kies.
func _zonen_tint(x: float, z: float, tint: Color) -> Color:
	var p := Vector2(x, z)
	var out := tint
	var strand := RanchKarte.zone("strand")
	if not strand.is_empty():
		var bucht: Array = strand["bucht_mitte"]
		var d := p.distance_to(Vector2(float(bucht[0]), float(bucht[1])))
		var radius := float(strand["bucht_radius"])
		if d < radius * 1.35:
			out = out.lerp(TINT_SAND, clampf(1.0 - (d - radius * 0.5) / (radius * 0.6), 0.0, 1.0))
	var moor := RanchKarte.zone("moor")
	if not moor.is_empty() and RanchKarte.zone_rect(moor).has_point(p):
		out = out.lerp(TINT_MOOR, 0.7)
	var kornfeld := RanchKarte.zone("kornfeld")
	if not kornfeld.is_empty():
		var feld: Array = kornfeld["feld_rect"]
		if Rect2(float(feld[0]), float(feld[1]), float(feld[2]), float(feld[3])).has_point(p):
			out = out.lerp(TINT_KORN, 0.55)
	var blumen := RanchKarte.zone("blumenwiese")
	if not blumen.is_empty():
		var lav: Array = blumen["lavendel_rect"]
		if Rect2(float(lav[0]), float(lav[1]), float(lav[2]), float(lav[3])).has_point(p):
			out = out.lerp(TINT_LAVENDEL, 0.35)
	var berg := RanchKarte.zone("bergmassiv")
	if not berg.is_empty():
		var bs: Array = berg["bergsee_mitte"]
		var d := p.distance_to(Vector2(float(bs[0]), float(bs[1])))
		if d < float(berg["bergsee_radius"]) * 1.5:
			out = out.lerp(TINT_KIES, 0.5)
	return out


## Deterministische Fleck-Maske 0..1 (Sinus-Interferenz, ~30–60-m-Flecken)
## — statisch + PURE, damit Tests die Variation nachrechnen können.
static func _fleck(x: float, z: float, fx: float, fz: float, phase: float) -> float:
	var n := sin(x * fx + phase) * sin(z * fz + phase * 1.7)
	n += 0.5 * sin(x * fx * 2.3 - phase) * sin(z * fz * 2.1 + 0.6)
	return smoothstep(0.55, 0.95, n)


## Nähe 0..1 zu den Fundort-Trampelpfaden (1 = auf dem Pfad).
func _trampel_naehe(x: float, z: float) -> float:
	var best := 0.0
	var p := Vector2(x, z)
	for segment: Dictionary in _pfad_segmente:
		var halb := float(segment["halb"])
		var d := _segment_abstand(p, segment["a"], segment["b"])
		if d < halb + TRAMPEL_RAND_M:
			best = maxf(best, 1.0 - maxf(0.0, d - halb) / TRAMPEL_RAND_M)
	return best


static func _segment_abstand(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var laenge2 := ab.length_squared()
	if laenge2 <= 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / laenge2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


## Band entlang einer Punktliste in den SurfaceTool `st` schreiben:
## Segmente alle ~7 m unterteilt, Querschnitt folgt dem Gelände
## (`anheben` m darüber) bzw. bleibt bei Wasser auf den übergebenen
## y-Werten (`glatt` = y linear interpolieren). PRIMITIVE_TRIANGLES,
## damit VIELE Bänder in EINEM Mesh landen können.
func _band_in(
	st: SurfaceTool, punkte: Array[Vector3], band_breite: float, anheben: float, glatt: bool
) -> void:
	if punkte.size() < 2:
		return
	var pfad: Array[Vector3] = []
	for i in punkte.size() - 1:
		var von := punkte[i]
		var bis := punkte[i + 1]
		var schritte := maxi(1, int(von.distance_to(bis) / 7.0))
		for s in schritte:
			pfad.append(von.lerp(bis, float(s) / float(schritte)))
	pfad.append(punkte[punkte.size() - 1])
	var halb := band_breite / 2.0
	var laenge := 0.0
	var vorherige: Array[Vector3] = []
	for i in pfad.size():
		var p := pfad[i]
		var vor := pfad[mini(i + 1, pfad.size() - 1)] - pfad[maxi(i - 1, 0)]
		vor.y = 0.0
		var quer := Vector3(-vor.z, 0.0, vor.x).normalized() * halb
		if i > 0:
			laenge += Vector2(p.x - pfad[i - 1].x, p.z - pfad[i - 1].z).length()
		var aktuelle: Array[Vector3] = []
		var uvs: Array[Vector2] = []
		for seite: float in [1.0, -1.0]:
			var v := p + quer * seite
			if glatt:
				v.y = p.y
			else:
				v.y = RanchGelaende.hoehe(v.x, v.z) + anheben
			aktuelle.append(v)
			uvs.append(Vector2(0.0 if seite < 0.0 else 1.0, laenge / band_breite))
		if not vorherige.is_empty():
			var v_uv := (laenge - 0.0) / band_breite
			_band_quad(st, vorherige, aktuelle, uvs, v_uv)
		vorherige = aktuelle
	return


func _band_quad(
	st: SurfaceTool,
	vorherige: Array[Vector3],
	aktuelle: Array[Vector3],
	uvs: Array[Vector2],
	v_uv: float
) -> void:
	var reihen: Array = [
		[vorherige[0], Vector2(1.0, v_uv - 0.1)],
		[vorherige[1], Vector2(0.0, v_uv - 0.1)],
		[aktuelle[0], uvs[0]],
		[aktuelle[1], uvs[1]],
	]
	for idx: int in [0, 1, 2, 1, 3, 2]:
		var eintrag: Array = reihen[idx]
		st.set_normal(Vector3.UP)
		st.set_uv(eintrag[1])
		st.add_vertex(eintrag[0])


func _commit(st: SurfaceTool, mat: Material) -> MeshInstance3D:
	var mesh := st.commit()
	if mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi


func _textur(pfad: String) -> Texture2D:
	if ResourceLoader.exists(pfad):
		return load(pfad)
	return null
