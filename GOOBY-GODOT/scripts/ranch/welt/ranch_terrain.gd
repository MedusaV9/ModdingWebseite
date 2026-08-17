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
##
## W19-Perf: Die deterministischen Meshes (Chunks, Weg-/Trampel-/Bach-
## Bänder, Wasserscheiben) liegen in einem STATISCHEN Cache (Schlüssel:
## Karten-Seed + Saison) — jedes erneute Betreten der Welt instanziert
## nur noch MeshInstances statt hunderttausende hoehe()-Aufrufe zu
## wiederholen. Chunks sind über `chunk_plaene()`/`baue_chunk_aus_plan()`
## einzeln baubar (gestückelter Aufbau der Region-Szene). Material hängt
## als material_override an der Instanz (Cache bleibt material-frei).

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
## Lens B (EVAL-2026-08, Befund „neon-helle Wiese"): Basis-Tint von Weiß auf
## ein satteres Grün — die Wiese trägt ~2/3 des Panoramas und muss unter der
## Filmic-Schulter bleiben (Ziel-Luma 0,45–0,55), Weiß ließ sie ausbrennen.
const TINT_WIESE := Color(0.58, 0.74, 0.46)
const TINT_WALD := Color(0.72, 0.82, 0.66)
const TINT_FELS := Color(1.06, 1.02, 0.94)
const TINT_UFER := Color(1.08, 1.0, 0.78)
## FB-2: sattes Grasbüschel-Grün, warme Erdstellen, Kies, Trampel-Erde.
const TINT_GRASFLECK := Color(0.72, 0.88, 0.6)
const TINT_ERDE := Color(1.05, 0.93, 0.72)
## VIS-1 („karg und flach"): tieferes Wiesengrün für großflächige
## Ton-Wellen — gibt Übersichten Farbtiefe, wo Einzel-Flecken verschwimmen.
const TINT_WIESE_TIEF := Color(0.5, 0.7, 0.4)
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

static var _mesh_cache: Dictionary = {}

var terrain_material: StandardMaterial3D
var weg_material: StandardMaterial3D
var trampel_material: StandardMaterial3D
var wasser_material: ShaderMaterial
var moor_material: ShaderMaterial

var saison := "sommer"

var _pfad_strecken: RanchGelaende.Strecken
## Tint-Kontext (W19-Perf): Zonen-Daten EINMAL nachschlagen statt sechs
## RanchKarte.zone()-Scans PRO VERTEX (Werte identisch zum Direktweg).
var _tint_strand: Dictionary = {}
var _tint_moor: Dictionary = {}
var _tint_korn: Dictionary = {}
var _tint_lavendel: Dictionary = {}
var _tint_bergsee: Dictionary = {}


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
	# VIS-1: echte Wasseroberflächen (Wellen, Tiefenverlauf, Schaumsaum)
	# statt flacher blauer Scheiben — Shader + radiale UV, siehe WeltWasser.
	wasser_material = WeltWasser.material("klar")
	moor_material = WeltWasser.material("moor")
	_pfad_strecken = RanchGelaende.Strecken.new()
	for pfad: Dictionary in RanchEntdeckungen.alle_pfade():
		var halb := float(pfad["breite"]) / 2.0
		var punkte: Array = pfad["punkte"]
		for i in punkte.size() - 1:
			var a: Array = punkte[i]
			var b: Array = punkte[i + 1]
			_pfad_strecken.fuege_hinzu(
				Vector2(float(a[0]), float(a[1])),
				Vector2(float(b[0]), float(b[1])),
				halb,
				halb + TRAMPEL_RAND_M + 1.0
			)
	_lade_tint_kontext()


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


## Test-Hook: Mesh-Cache verwerfen (nach RanchKarte.reset_for_tests).
static func reset_for_tests() -> void:
	_mesh_cache = {}


## Chunk-Baupläne (cx, cz, fern, rect) — die Region-Szene kann sie einzeln
## (gestückelt, nach Spawn-Nähe sortiert) abarbeiten.
static func chunk_plaene() -> Array[Dictionary]:
	var grenzen := RanchKarte.grenzen()
	var breite := grenzen.size.x / float(CHUNKS)
	var tiefe := grenzen.size.y / float(CHUNKS)
	var out: Array[Dictionary] = []
	for cx in CHUNKS:
		for cz in CHUNKS:
			var rect := Rect2(
				grenzen.position.x + float(cx) * breite,
				grenzen.position.y + float(cz) * tiefe,
				breite,
				tiefe
			)
			out.append({"cx": cx, "cz": cz, "fern": false, "rect": rect})
			out.append({"cx": cx, "cz": cz, "fern": true, "rect": rect})
	return out


## Baut alle Gelände-Chunks unter `wurzel` (Namen: Chunk_x_z; je Chunk ein
## Nah- und ein Fern-LOD, Umschaltung über visibility_range).
func baue_chunks(wurzel: Node3D) -> void:
	for plan: Dictionary in chunk_plaene():
		baue_chunk_aus_plan(wurzel, plan)


## EIN Chunk-LOD aus dem Plan (Mesh aus dem statischen Cache oder frisch).
func baue_chunk_aus_plan(wurzel: Node3D, plan: Dictionary) -> void:
	var fern: bool = plan["fern"]
	var rect: Rect2 = plan["rect"]
	var key := "chunk|%s|%d|%d|%d" % [saison, plan["cx"], plan["cz"], 1 if fern else 0]
	var zellen := ZELLEN_FERN if fern else ZELLEN_JE_CHUNK
	var eintrag: Dictionary = _cache(
		key,
		func() -> Dictionary:
			return _baue_chunk_mesh(
				rect.position.x, rect.position.y, rect.size.x, rect.size.y, zellen
			)
	)
	var mi := MeshInstance3D.new()
	mi.mesh = eintrag["mesh"]
	mi.position = eintrag["mitte"]
	# Material hängt an der Instanz — der Mesh-Cache bleibt material-frei,
	# damit der Wetter-Controller IMMER das Material DIESES Betretens fährt.
	mi.material_override = terrain_material
	# Budget: Gelände wirft keinen eigenen Schatten (Sonnen-Schatten reicht
	# 190 m — Baum-/Gebäude-Schatten bleiben, der Chunk-Schattenpass fällt).
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if fern:
		mi.name = "ChunkFern_%d_%d" % [plan["cx"], plan["cz"]]
		mi.visibility_range_begin = LOD_WECHSEL_M
	else:
		mi.name = "Chunk_%d_%d" % [plan["cx"], plan["cz"]]
		mi.visibility_range_end = LOD_WECHSEL_M
	wurzel.add_child(mi)


## ALLE Feldwege als EIN gebündeltes Band-Mesh (1 Draw-Call).
func baue_wege(wurzel: Node3D) -> void:
	var mesh: Mesh = _cache("wege", _wege_mesh)
	_haenge_band_ein(wurzel, "Feldwege", mesh, weg_material, false)


## Alle Trampelpfade zu den Fundorten als EIN Mesh (FB-2: schmale
## Erdspuren, die sichtbar „irgendwohin führen").
func baue_trampelpfade(wurzel: Node3D) -> void:
	var mesh: Mesh = _cache("trampelpfade", _trampelpfad_mesh)
	_haenge_band_ein(wurzel, "Trampelpfade", mesh, trampel_material, false)


## Wasserflächen: See + Strand-Bucht + Bergsee (Scheiben), Moor-Tümpel
## (ein MultiMesh) und das Bach-Wasserband.
func baue_wasser(wurzel: Node3D) -> void:
	baue_wasser_flaechen(wurzel)
	baue_bach_wasser(wurzel)


## Wasser-Scheiben (See/Bucht/Bergsee) + Moor-Tümpel + Ufer-Schilf.
func baue_wasser_flaechen(wurzel: Node3D) -> void:
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
	_baue_ufer_schilf(wurzel)


## Bach-Wasserband entlang der Karten-Polyline.
func baue_bach_wasser(wurzel: Node3D) -> void:
	var mesh: Mesh = _cache("bachwasser", _bach_wasser_mesh)
	_haenge_band_ein(wurzel, "BachWasser", mesh, WeltWasser.material("bach"), true)


## ----------------------------------------------------------------- intern


## Mesh-Fabriken laufen nur bei Cache-Miss (Schlüssel: Karten-Seed + Teil).
static func _cache(key_teil: String, fabrik: Callable) -> Variant:
	var key := "%d|%s" % [RanchKarte.seed_wert(), key_teil]
	if not _mesh_cache.has(key):
		_mesh_cache[key] = fabrik.call()
	return _mesh_cache[key]


func _wege_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for weg: Dictionary in RanchKarte.wege():
		var punkte := RanchKarte.wegpunkte(str(weg["von"]), str(weg["nach"]))
		_band_in(st, punkte, float(weg["breite"]), 0.12, false)
	return st.commit()


func _trampelpfad_mesh() -> Mesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for pfad: Dictionary in RanchEntdeckungen.alle_pfade():
		var punkte: Array[Vector3] = []
		for paar: Array in pfad["punkte"]:
			var x := float(paar[0])
			var z := float(paar[1])
			punkte.append(Vector3(x, RanchGelaende.hoehe(x, z), z))
		_band_in(st, punkte, float(pfad["breite"]), 0.08, false)
	return st.commit()


func _bach_wasser_mesh() -> Mesh:
	var bach: Dictionary = RanchKarte.karte()["bach"]
	var punkte: Array[Vector3] = []
	for paar: Array in bach["punkte"]:
		var x := float(paar[0])
		var z := float(paar[1])
		punkte.append(Vector3(x, RanchGelaende.bach_wasserspiegel(x, z), z))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_band_in(st, punkte, float(bach["breite"]) + 2.5, 0.0, true)
	return st.commit()


func _haenge_band_ein(
	wurzel: Node3D, band_name: String, mesh: Mesh, mat: Material, ohne_schatten: bool
) -> void:
	var mi := MeshInstance3D.new()
	mi.name = band_name
	mi.mesh = mesh
	mi.material_override = mat
	if ohne_schatten:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wurzel.add_child(mi)


func _wasser_scheibe(
	wurzel: Node3D, scheiben_name: String, pos: Vector3, radius: float, mat: Material
) -> void:
	var scheibe := MeshInstance3D.new()
	scheibe.name = scheiben_name
	# Ufer-Anteil je Vertex aus der echten Wassertiefe backen — der
	# Tiefenverlauf/Schaumsaum liegt an der SICHTBAREN Uferlinie.
	scheibe.mesh = _cache(
		"scheibe|%s" % scheiben_name,
		func() -> Mesh:
			return WeltWasser.gelaende_scheibe_mesh(
				Vector2(pos.x, pos.z),
				radius,
				pos.y,
				func(x: float, z: float) -> float: return RanchGelaende.hoehe(x, z)
			)
	)
	scheibe.material_override = mat
	scheibe.scale = Vector3(radius, 1.0, radius)
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
	mm.mesh = WeltWasser.scheibe_mesh()
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
	mmi.material_override = moor_material
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wurzel.add_child(mmi)


## Ufer-Schilf (VIS-1 Uferzone): Binsen-Büschel am See- und Buchtsaum —
## der Übergang Wasser→Wiese bekommt eine lesbare Kante (bergsee hat
## bereits Schilf über RanchNeueZonen). EIN MultiMesh je Gewässer.
func _baue_ufer_schilf(wurzel: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = RanchKarte.seed_wert() + 271
	var see := RanchKarte.zone("see")
	var see_mitte: Array = see["see_mitte"]
	_schilf_ring(
		wurzel,
		"SeeUferSchilf",
		Vector2(float(see_mitte[0]), float(see_mitte[1])),
		float(see["see_radius"]) * 1.9,
		44,
		rng
	)
	var strand := RanchKarte.zone("strand")
	if not strand.is_empty():
		var bucht: Array = strand["bucht_mitte"]
		_schilf_ring(
			wurzel,
			"BuchtUferSchilf",
			Vector2(float(bucht[0]), float(bucht[1])),
			float(strand["bucht_radius"]) * 0.85,
			18,
			rng
		)


func _schilf_ring(
	wurzel: Node3D,
	ring_name: String,
	mitte: Vector2,
	radius: float,
	anzahl: int,
	rng: RandomNumberGenerator
) -> void:
	var transforms: Array[Transform3D] = []
	for i in anzahl:
		# Uferlinie je Winkel SUCHEN (von innen nach außen der erste Punkt
		# über dem Wasserspiegel) statt blind auf einem Ring zu würfeln.
		var w := float(i) / float(anzahl) * TAU + rng.randf_range(-0.06, 0.06)
		var richtung := Vector2.from_angle(w)
		var ufer_r := -1.0
		var r := radius * 0.7
		while r < radius * 1.45:
			var h_probe := RanchGelaende.hoehe(mitte.x + richtung.x * r, mitte.y + richtung.y * r)
			if h_probe > RanchGelaende.WASSER_HOEHE - 0.05:
				ufer_r = r
				break
			r += 1.0
		if ufer_r < 0.0:
			continue
		var p := mitte + richtung * (ufer_r + rng.randf_range(-0.6, 0.8))
		var h := RanchGelaende.hoehe(p.x, p.y)
		if h > RanchGelaende.WASSER_HOEHE + 2.0:
			continue
		var basis := Basis(Vector3.UP, w).scaled(Vector3.ONE * rng.randf_range(0.9, 1.4))
		transforms.append(
			Transform3D(basis, Vector3(p.x, maxf(h, RanchGelaende.WASSER_HOEHE) - 0.05, p.y))
		)
	if transforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = WeltFlora.mesh("binse")
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = ring_name
	mmi.multimesh = mm
	mmi.visibility_range_end = 290.0
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	wurzel.add_child(mmi)


## Ein Chunk-LOD: Höhen-Raster (+1 Rand für Normalen), Vertex-Farben nach
## Zonen-Charakter, UV in Weltmetern, Skirt gegen LOD-Risse. Vertizes
## liegen relativ zur Chunk-Mitte (visibility_range misst am Ursprung).
func _baue_chunk_mesh(
	min_x: float, min_z: float, breite: float, tiefe: float, zellen: int
) -> Dictionary:
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
	return {"mesh": st.commit(), "mitte": mitte}


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
	# VIS-1: großflächige Wiesentön-Wellen (~300–500 m Wellenlänge) zuerst,
	# damit auch Mittelgrund und Luftbild Farbabstufung zeigen.
	tint = tint.lerp(TINT_WIESE_TIEF, _weide_ton(x, z) * 0.75)
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
	# W19-Perf: Schlucht-Kerbe EINMAL berechnen (vorher zwei Aufrufe).
	var schlucht := RanchGelaende.schlucht_kerbe(x, z)
	if schlucht > 2.0:
		var wand := clampf((schlucht - 2.0) / 6.0, 0.0, 1.0)
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
## Korngold, warmer Obstgarten, Lavendel-Hauch, Bergsee-Kies — Zonen-Daten
## kommen aus dem in _init geladenen Tint-Kontext (Werte identisch).
func _zonen_tint(x: float, z: float, tint: Color) -> Color:
	var p := Vector2(x, z)
	var out := tint
	if not _tint_strand.is_empty():
		var d: float = p.distance_to(_tint_strand["mitte"])
		var radius: float = _tint_strand["radius"]
		if d < radius * 1.35:
			out = out.lerp(TINT_SAND, clampf(1.0 - (d - radius * 0.5) / (radius * 0.6), 0.0, 1.0))
	if not _tint_moor.is_empty() and (_tint_moor["rect"] as Rect2).has_point(p):
		out = out.lerp(TINT_MOOR, 0.7)
	if not _tint_korn.is_empty() and (_tint_korn["rect"] as Rect2).has_point(p):
		out = out.lerp(TINT_KORN, 0.55)
	if not _tint_lavendel.is_empty() and (_tint_lavendel["rect"] as Rect2).has_point(p):
		out = out.lerp(TINT_LAVENDEL, 0.35)
	if not _tint_bergsee.is_empty():
		var d: float = p.distance_to(_tint_bergsee["mitte"])
		if d < float(_tint_bergsee["radius"]) * 1.5:
			out = out.lerp(TINT_KIES, 0.5)
	return out


## Tint-Kontext einmal aus der Karte laden (statt Zonen-Scans pro Vertex).
func _lade_tint_kontext() -> void:
	var strand := RanchKarte.zone("strand")
	if not strand.is_empty():
		var bucht: Array = strand["bucht_mitte"]
		_tint_strand = {
			"mitte": Vector2(float(bucht[0]), float(bucht[1])),
			"radius": float(strand["bucht_radius"]),
		}
	var moor := RanchKarte.zone("moor")
	if not moor.is_empty():
		_tint_moor = {"rect": RanchKarte.zone_rect(moor)}
	var kornfeld := RanchKarte.zone("kornfeld")
	if not kornfeld.is_empty():
		var feld: Array = kornfeld["feld_rect"]
		_tint_korn = {"rect": Rect2(float(feld[0]), float(feld[1]), float(feld[2]), float(feld[3]))}
	var blumen := RanchKarte.zone("blumenwiese")
	if not blumen.is_empty():
		var lav: Array = blumen["lavendel_rect"]
		_tint_lavendel = {"rect": Rect2(float(lav[0]), float(lav[1]), float(lav[2]), float(lav[3]))}
	var berg := RanchKarte.zone("bergmassiv")
	if not berg.is_empty():
		var bs: Array = berg["bergsee_mitte"]
		_tint_bergsee = {
			"mitte": Vector2(float(bs[0]), float(bs[1])),
			"radius": float(berg["bergsee_radius"]),
		}


## Deterministische Fleck-Maske 0..1 (Sinus-Interferenz, ~30–60-m-Flecken)
## — statisch + PURE, damit Tests die Variation nachrechnen können.
## Großflächige Wiesentön-Welle 0..1 (deterministisch, weiche Übergänge,
## Wellenlänge einige hundert Meter — fürs Luftbild/Mittelgrund).
static func _weide_ton(x: float, z: float) -> float:
	var n := 0.5 + 0.5 * sin(x * 0.017 + sin(z * 0.011) * 1.9)
	n += 0.5 + 0.5 * sin(z * 0.015 + sin(x * 0.009) * 1.7 + 2.3)
	return smoothstep(0.5, 1.6, n)


static func _fleck(x: float, z: float, fx: float, fz: float, phase: float) -> float:
	var n := sin(x * fx + phase) * sin(z * fz + phase * 1.7)
	n += 0.5 * sin(x * fx * 2.3 - phase) * sin(z * fz * 2.1 + 0.6)
	return smoothstep(0.55, 0.95, n)


## Nähe 0..1 zu den Fundort-Trampelpfaden (1 = auf dem Pfad) — Segmente
## mit AABB-Schnellverwurf (außerhalb tragen sie ohnehin 0 bei).
func _trampel_naehe(x: float, z: float) -> float:
	var best := 0.0
	var p := Vector2(x, z)
	var s := _pfad_strecken
	for i in s.a.size():
		if x < s.min_x[i] or x > s.max_x[i] or z < s.min_z[i] or z > s.max_z[i]:
			continue
		var halb := s.halb[i]
		var d := _segment_abstand(p, s.a[i], s.b[i])
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


func _textur(pfad: String) -> Texture2D:
	if ResourceLoader.exists(pfad):
		return load(pfad)
	return null
