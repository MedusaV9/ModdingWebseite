class_name RanchTerrain
extends RefCounted
## Gelände-Bauer der Ranch-Region (RW-1): setzt RanchGelaende.hoehe in
## Chunk-Meshes um (7×7 Chunks über die Kartengrenzen, geteiltes Pastell-
## Material mit Wiesen-Textur + Vertex-Farben), dazu Feldweg-Bänder entlang
## der Karten-Wege, Trampelpfade zu den Fundorten (FB-2), See-Wasserfläche
## und das Bach-Wasserband. Ein Draw-Call je Chunk/Weg/Wasserfläche.
## FB-2 Bodentextur-Variation: die Vertex-Tints mischen zusätzlich
## Grasbüschel-Flecken, Erdstellen, Kies am Wegrand und Trampelpfad-Erde
## in die Wiesen-Textur (deterministische Sinus-Flecken, kein RNG).

const TEX_WIESE := "res://assets/ranch/texturen/wiese.png"
const TEX_FELDWEG := "res://assets/ranch/texturen/feldweg.png"
const TEX_WASSER := "res://assets/ranch/texturen/wasser.png"

const CHUNKS := 7
const ZELLEN_JE_CHUNK := 40

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

## Trampelpfad-Tint reicht so weit über die Pfadkante hinaus (m).
const TRAMPEL_RAND_M := 2.5

var terrain_material: StandardMaterial3D
var weg_material: StandardMaterial3D
var trampel_material: StandardMaterial3D
var wasser_material: StandardMaterial3D

var _pfad_segmente: Array[Dictionary] = []


func _init() -> void:
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
	for pfad: Dictionary in RanchEntdeckungen.PFADE:
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


## Baut alle Gelände-Chunks unter `wurzel` (Namen: Chunk_x_z).
func baue_chunks(wurzel: Node3D) -> void:
	var grenzen := RanchKarte.grenzen()
	var breite := grenzen.size.x / float(CHUNKS)
	var tiefe := grenzen.size.y / float(CHUNKS)
	for cx in CHUNKS:
		for cz in CHUNKS:
			var min_x := grenzen.position.x + float(cx) * breite
			var min_z := grenzen.position.y + float(cz) * tiefe
			var chunk := _baue_chunk(min_x, min_z, breite, tiefe)
			chunk.name = "Chunk_%d_%d" % [cx, cz]
			wurzel.add_child(chunk)


## Feldweg-Bänder für ALLE Karten-Wege (je Weg ein Mesh).
func baue_wege(wurzel: Node3D) -> void:
	for weg: Dictionary in RanchKarte.wege():
		var punkte := RanchKarte.wegpunkte(str(weg["von"]), str(weg["nach"]))
		var band := _baue_band(punkte, float(weg["breite"]), 0.12, weg_material, false)
		band.name = "Weg_%s" % weg["id"]
		wurzel.add_child(band)


## Trampelpfade zu den Fundorten (FB-2): schmale Erdspuren, die sichtbar
## „irgendwohin führen" — gleiche Band-Technik, dunkleres Material.
func baue_trampelpfade(wurzel: Node3D) -> void:
	for pfad: Dictionary in RanchEntdeckungen.PFADE:
		var punkte: Array[Vector3] = []
		for paar: Array in pfad["punkte"]:
			var x := float(paar[0])
			var z := float(paar[1])
			punkte.append(Vector3(x, RanchGelaende.hoehe(x, z), z))
		var band := _baue_band(punkte, float(pfad["breite"]), 0.08, trampel_material, false)
		band.name = "Pfad_%s" % pfad["id"]
		wurzel.add_child(band)


## See-Wasserfläche (Kreis auf WASSER_HOEHE) + Bach-Wasserband.
func baue_wasser(wurzel: Node3D) -> void:
	var see := RanchKarte.zone("see")
	var mitte: Array = see["see_mitte"]
	var scheibe := MeshInstance3D.new()
	scheibe.name = "SeeWasser"
	var mesh := CylinderMesh.new()
	mesh.top_radius = float(see["see_radius"]) * 1.9
	mesh.bottom_radius = mesh.top_radius
	mesh.height = 0.05
	mesh.radial_segments = 40
	mesh.material = wasser_material
	scheibe.mesh = mesh
	scheibe.position = Vector3(float(mitte[0]), RanchGelaende.WASSER_HOEHE, float(mitte[1]))
	scheibe.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wurzel.add_child(scheibe)
	var bach: Dictionary = RanchKarte.karte()["bach"]
	var punkte: Array[Vector3] = []
	for paar: Array in bach["punkte"]:
		var x := float(paar[0])
		var z := float(paar[1])
		punkte.append(Vector3(x, RanchGelaende.bach_wasserspiegel(x, z), z))
	var band := _baue_band(punkte, float(bach["breite"]) + 2.5, 0.0, wasser_material, true)
	band.name = "BachWasser"
	band.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wurzel.add_child(band)


## ----------------------------------------------------------------- intern


## Ein Chunk: Höhen-Raster (+1 Rand für Normalen), Vertex-Farben nach
## Zonen-Charakter, UV in Weltmetern.
func _baue_chunk(min_x: float, min_z: float, breite: float, tiefe: float) -> MeshInstance3D:
	var n := ZELLEN_JE_CHUNK
	var dx := breite / float(n)
	var dz := tiefe / float(n)
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
			st.add_vertex(Vector3(x, h, z))
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
	var mesh := st.commit()
	mesh.surface_set_material(0, terrain_material)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi


func _vertex_tint(x: float, z: float, h: float, wald_rect: Rect2) -> Color:
	var tint := TINT_WIESE
	# FB-2 Bodentextur-Variation: erst die Wiesen-Flecken, dann gewinnt
	# der Zonen-Charakter (Wald/Fels/Ufer) wie gehabt.
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
	if h > 14.0:
		tint = tint.lerp(TINT_FELS, clampf((h - 14.0) / 10.0, 0.0, 0.85))
	var ueber_wasser := h - RanchGelaende.WASSER_HOEHE
	if ueber_wasser < 1.2:
		tint = tint.lerp(TINT_UFER, clampf(1.0 - ueber_wasser / 1.2, 0.0, 1.0))
	elif RanchGelaende.bach_kerbe(x, z) > 0.3:
		tint = tint.lerp(TINT_UFER, 0.6)
	return tint


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


## Band-Mesh entlang einer Punktliste: Segmente alle ~7 m unterteilt,
## Querschnitt folgt dem Gelände (`anheben` m darüber) bzw. bleibt bei
## Wasser auf den übergebenen y-Werten (`glatt` = y linear interpolieren).
func _baue_band(
	punkte: Array[Vector3], band_breite: float, anheben: float, mat: Material, glatt: bool
) -> MeshInstance3D:
	var pfad: Array[Vector3] = []
	for i in punkte.size() - 1:
		var von := punkte[i]
		var bis := punkte[i + 1]
		var schritte := maxi(1, int(von.distance_to(bis) / 7.0))
		for s in schritte:
			pfad.append(von.lerp(bis, float(s) / float(schritte)))
	pfad.append(punkte[punkte.size() - 1])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var halb := band_breite / 2.0
	var laenge := 0.0
	for i in pfad.size():
		var p := pfad[i]
		var vor := pfad[mini(i + 1, pfad.size() - 1)] - pfad[maxi(i - 1, 0)]
		vor.y = 0.0
		var quer := Vector3(-vor.z, 0.0, vor.x).normalized() * halb
		if i > 0:
			laenge += Vector2(p.x - pfad[i - 1].x, p.z - pfad[i - 1].z).length()
		for seite: float in [1.0, -1.0]:
			var v := p + quer * seite
			if glatt:
				v.y = p.y
			else:
				v.y = RanchGelaende.hoehe(v.x, v.z) + anheben
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(0.0 if seite < 0.0 else 1.0, laenge / band_breite))
			st.add_vertex(v)
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	return mi


func _textur(pfad: String) -> Texture2D:
	if ResourceLoader.exists(pfad):
		return load(pfad)
	return null
