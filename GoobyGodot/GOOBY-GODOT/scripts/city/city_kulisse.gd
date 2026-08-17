class_name CityKulisse
extends RefCounted
## Kulissen-Planer der Stadt (FIX-5 „Die Stadt ist leer"): PURE + headless-
## testbar — hier entstehen nur die PLATZIERUNGEN (welches Kenney-GLB steht
## wo, wie gedreht, wie groß, wie getönt), die Meshes hängt CityScene als
## MultiMesh-Gruppen ein (ein Draw-Call pro Mesh-Sorte statt pro Exemplar,
## Budget ≤ 400 Draw-Calls in der Stadtansicht).
##
## Gefüllt wird ALLES, was die Karte frei lässt: Gewerbe-/Zentrums-Blöcke
## mit Häuserzeilen (Variation über Pool + Tint), Wohnviertel mit Gärten
## (Zaun, Weg, Baum, Blumen), der Park mit Bäumen/Bänken/Wegen, die
## Stadtränder mit Grün — plus Straßenmöblierung (Bänke, Hydranten,
## Pflanzkübel, Schilder, Absperrungen), Bordstein-Parker und die
## Kreisel-Inseln. Seed-deterministisch (Karten-Deko-Seed).

## Bordstein-Abstände von der Straßen-Tile-Mitte (Fahrbahnplatte ~12 m breit,
## Gehwegkante bei ~6 m, Fußgänger-Linie bei 7,5 m — Möbel dahinter).
const MOEBEL_ABSTAND_M := 8.4
const PARKEN_ABSTAND_M := 6.3
const GRUEN_ABSTAND_M := 9.2

## Draw-Call-Heuristik: ein Kulissen-MultiMesh kostet ~1 Draw-Call pro Mesh
## im GLB (Kenney-Kulissen: 1, Autos: 5–6). Der Sockel deckt den Rest der
## Szene (Straßen-MultiMeshes, Orte, Verkehr, Goobys, HUD, Nacht-Extras).
const DRAW_CALLS_JE_GRUPPE := 2
const DRAW_CALLS_JE_AUTO_GRUPPE := 6
const DRAW_CALL_SOCKEL := 190
const DRAW_CALL_BUDGET := 400

## Fenster-Glühen (nachts): Anteil beleuchteter Fenster je Fassade.
const FENSTER_LEUCHT_ANTEIL := 0.55

## Fenster-Layout je Modell-BASENAME (W18/J4): die CC0-Häuser sind breiter/
## flacher als die Kenney-Commercial-Würfel — `front` = halbe Modelltiefe
## plus Epsilon (Quad knapp VOR der Fassade, Werte aus der AABB-Vermessung),
## `reihen` = Fensterhöhen als Anteil der Skala. Ohne Eintrag gilt das alte
## Commercial-Layout (front 0.492, Reihen 0.35/0.55).
const FENSTER_KONFIG := {
	"building_type_a": {"front": 0.55, "reihen": [0.24]},
	"building_type_b": {"front": 0.60, "reihen": [0.26, 0.62]},
	"building_type_c": {"front": 0.55, "reihen": [0.24, 0.56]},
	"building_type_d": {"front": 0.55, "reihen": [0.26, 0.66]},
	"building_type_e": {"front": 0.55, "reihen": [0.26, 0.62]},
	"building_type_f": {"front": 0.73, "reihen": [0.24, 0.60]},
	"building_type_g": {"front": 0.62, "reihen": [0.24]},
	"building_type_h": {"front": 0.49, "reihen": [0.22]},
	"building_type_j": {"front": 0.49, "reihen": [0.24, 0.56]},
	"building_type_m": {"front": 0.74, "reihen": [0.24]},
	"building_type_n": {"front": 0.72, "reihen": [0.26, 0.62]},
	"building_type_o": {"front": 0.55, "reihen": [0.26, 0.62]},
	"building_type_p": {"front": 0.53, "reihen": [0.24, 0.50]},
	"building_type_s": {"front": 0.57, "reihen": [0.24, 0.60]},
	"building_i": {"front": 0.68, "reihen": [0.35, 0.75, 1.15]},
	"building_j": {"front": 0.70, "reihen": [0.35, 0.75, 1.15]},
	"building_l": {"front": 0.73, "reihen": [0.4, 0.9, 1.4, 1.9]},
	"building_m": {"front": 0.65, "reihen": [0.5, 1.1, 1.7, 2.3, 2.9]},
	"building_n": {"front": 0.94, "reihen": [0.4, 0.9, 1.4, 1.9]},
}

## CC0-Modellwurzeln (W18/J4): echte Kenney-Vorstadt-Wohnhäuser + Commercial-
## Lückenfüller — liegen NICHT unter assets/city, darum volle res://-Pfade
## (CityBau.glb_pfad reicht sie unverändert durch). Alle Modelle sind laut
## AABB-Vermessung XZ-zentriert mit min_y = 0 (keine Ecke-Ursprung-Falle).
const CC0_VORSTADT := "res://assets/models/cc0/kenney_city_suburban"
const CC0_COMMERCIAL := "res://assets/models/cc0/kenney_city_commercial"

const GEWERBE_POOL: Array[Dictionary] = [
	{"glb": "gebaeude/building-b.glb", "scale": 9.0},
	{"glb": "gebaeude/building-g.glb", "scale": 9.0},
	{"glb": "gebaeude/building-h.glb", "scale": 9.0},
	{"glb": CC0_COMMERCIAL + "/building_i.glb", "scale": 7.0},
	{"glb": CC0_COMMERCIAL + "/building_m.glb", "scale": 5.0},
	{"glb": CC0_COMMERCIAL + "/building_n.glb", "scale": 5.0},
	{"glb": "gebaeude/low-detail-building-b.glb", "scale": 8.0},
	{"glb": "gebaeude/low-detail-building-c.glb", "scale": 8.0},
	{"glb": "gebaeude/low-detail-building-d.glb", "scale": 8.0},
	{"glb": "gebaeude/low-detail-building-f.glb", "scale": 8.0},
]
const ZENTRUM_POOL: Array[Dictionary] = [
	{"glb": "gebaeude/building-a.glb", "scale": 9.0},
	{"glb": "gebaeude/building-b.glb", "scale": 9.0},
	{"glb": "gebaeude/building-c.glb", "scale": 9.0},
	{"glb": "gebaeude/building-f.glb", "scale": 9.0},
	{"glb": "gebaeude/building-e.glb", "scale": 9.0},
	{"glb": CC0_COMMERCIAL + "/building_j.glb", "scale": 5.0},
	{"glb": CC0_COMMERCIAL + "/building_l.glb", "scale": 7.0},
]
## Wohnviertel-Pool: 7 ECHTE Vorstadt-Haustypen (statt der drei
## Commercial-Blöcke) — Fußabdrücke auf 7–9 m normiert (Tile = 20 m,
## Vorgarten braucht Platz), Drehung bleibt im 90°-Raster.
const HAUS_POOL: Array[Dictionary] = [
	{"glb": CC0_VORSTADT + "/building_type_a.glb", "scale": 6.0},
	{"glb": CC0_VORSTADT + "/building_type_c.glb", "scale": 6.0},
	{"glb": CC0_VORSTADT + "/building_type_f.glb", "scale": 5.5},
	{"glb": CC0_VORSTADT + "/building_type_h.glb", "scale": 6.0},
	{"glb": CC0_VORSTADT + "/building_type_m.glb", "scale": 5.5},
	{"glb": CC0_VORSTADT + "/building_type_n.glb", "scale": 5.0},
	{"glb": CC0_VORSTADT + "/building_type_s.glb", "scale": 6.0},
]
const GEWERBE_TINTS: Array[String] = ["", "#CFD8E3", "#DCE4EC", "#C9D6CF"]
const ZENTRUM_TINTS: Array[String] = ["", "#F2C14E", "#8FD0E8", "#FF9E7D", "#B5E48C", "#F5D6E0"]
const HAUS_TINTS: Array[String] = ["#FFE2B8", "#CDE7FF", "#FFD9D0", "#E4F1D0", "#F5E6FF", ""]
const MARKISEN_TINTS: Array[String] = ["#E8524A", "#4FBF8B", "#4E79D6", "#F2C14E"]

const PARK_BAUM_POOL: Array[Dictionary] = [
	{"glb": "natur/tree_detailed.glb", "scale": 6.0},
	{"glb": "natur/tree_oak.glb", "scale": 6.5},
	{"glb": "natur/tree_fat.glb", "scale": 6.0},
	{"glb": "natur/tree_pineTallA.glb", "scale": 5.5},
]
const RAND_BAUM_POOL: Array[Dictionary] = [
	{"glb": "natur/tree_default.glb", "scale": 5.5},
	{"glb": "natur/tree_pineRoundA.glb", "scale": 6.0},
	{"glb": "natur/tree_oak.glb", "scale": 6.0},
	{"glb": "vorstadt/tree-large.glb", "scale": 9.0},
]
const BLUMEN_POOL: Array[String] = [
	"natur/flower_redA.glb", "natur/flower_yellowA.glb", "natur/flower_purpleA.glb"
]
const PARKAUTO_POOL: Array[String] = [
	"autos/sedan.glb",
	"autos/van.glb",
	"autos/suv.glb",
	"autos/taxi.glb",
	"autos/sedan-sports.glb",
	"autos/truck.glb",
]
## Modell-Skalierung Kenney-car-kit → Weltmeter (wie CityCarFeel.CAR_SCALE).
const PARKAUTO_SCALE := 1.8


## Kompletter Kulissen-Plan der Karte (deterministisch über `seed_wert`).
## Rückgabe je Eintrag: {glb, pos, rot_grad, scale, tint, kategorie, klein}.
static func plaene(karte: CityMap, seed_wert: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if karte == null or not karte.ist_geladen():
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_wert
	var belegt := _belegte_tiles(karte)
	_plane_bloecke(karte, rng, belegt, out)
	_plane_strassenraender(karte, rng, out)
	_plane_parker(karte, rng, out)
	_plane_kreisel_inseln(karte, out)
	_plane_zuhause_einfahrt(karte, out)
	return out


## Plan-Einträge nach MultiMesh-Gruppe bündeln (Schlüssel "glb|tint").
## Rückgabe je Gruppe: {glb, tint, klein, transforms: Array[Transform3D]}.
static func gruppen(eintraege: Array[Dictionary]) -> Dictionary:
	var out: Dictionary = {}
	for eintrag in eintraege:
		var schluessel := "%s|%s" % [eintrag["glb"], eintrag.get("tint", "")]
		if not out.has(schluessel):
			out[schluessel] = {
				"glb": str(eintrag["glb"]),
				"tint": str(eintrag.get("tint", "")),
				"klein": bool(eintrag.get("klein", false)),
				"transforms": [] as Array[Transform3D],
			}
		var liste: Array[Transform3D] = out[schluessel]["transforms"]
		liste.append(transform_von(eintrag))
	return out


## Platzierungs-Transform eines Plan-Eintrags (Y-Rotation + uniforme Skala).
static func transform_von(eintrag: Dictionary) -> Transform3D:
	var basis := Basis(Vector3.UP, deg_to_rad(float(eintrag.get("rot_grad", 0.0))))
	basis = basis.scaled(Vector3.ONE * float(eintrag.get("scale", 1.0)))
	return Transform3D(basis, eintrag.get("pos", Vector3.ZERO))


## Draw-Call-Schätzung der Stadtansicht: Sockel (Straßen/Orte/Verkehr/HUD)
## plus ~konstante Kosten je MultiMesh-Gruppe — NICHT je Exemplar. Tests
## halten das gegen DRAW_CALL_BUDGET; der echte Nachweis kommt aus dem
## Screenshot-Lauf (RenderingServer-Zähler).
static func draw_call_schaetzung(eintraege: Array[Dictionary]) -> int:
	var summe := DRAW_CALL_SOCKEL
	for schluessel: String in gruppen(eintraege):
		if schluessel.begins_with("autos/"):
			summe += DRAW_CALLS_JE_AUTO_GRUPPE
		else:
			summe += DRAW_CALLS_JE_GRUPPE
	return summe


## Fenster-Layout eines Gebäudes über den GLB-Basename ({} = Default).
static func fenster_konfig(glb: String) -> Dictionary:
	return FENSTER_KONFIG.get(glb.get_file().get_basename(), {})


## Nacht-Fenster: warme Leucht-Quads auf den Straßenfassaden der Gebäude
## (`gebaeude`: {pos, rot_grad, scale, glb?}). Ein MultiMesh, EIN Draw-Call.
## W18/J4: das Layout (Fassaden-Abstand + Reihenhöhen) kommt je Modell aus
## FENSTER_KONFIG — die CC0-Häuser haben andere Proportionen als die
## Kenney-Commercial-Würfel.
static func fenster_transforms(gebaeude: Array[Dictionary], seed_wert: int) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_wert
	for haus in gebaeude:
		var s := float(haus.get("scale", 9.0))
		var rot := deg_to_rad(float(haus.get("rot_grad", 0.0)))
		var basis := Basis(Vector3.UP, rot)
		var pos: Vector3 = haus.get("pos", Vector3.ZERO)
		var konfig := fenster_konfig(str(haus.get("glb", "")))
		var front := float(konfig.get("front", 0.492))
		var reihen: Array = konfig.get("reihen", [0.35, 0.55])
		for spalte: float in [-0.22, 0.0, 0.22]:
			for reihe: float in reihen:
				if rng.randf() > FENSTER_LEUCHT_ANTEIL:
					continue
				var lokal := Vector3(spalte * s, float(reihe) * s, front * s)
				var fenster_basis := basis.scaled(Vector3(0.09 * s, 0.07 * s, 1.0))
				out.append(Transform3D(fenster_basis, pos + basis * lokal))
	return out


## ------------------------------------------------------------- Blöcke


static func _belegte_tiles(karte: CityMap) -> Dictionary:
	var belegt := {}
	for eintrag: Dictionary in karte.orte():
		for tile_raw: Array in eintrag.get("tiles", []):
			belegt[CityMap._tile_von(tile_raw)] = true
	for eintrag: Dictionary in karte.deko():
		var tile: Array = eintrag.get("tile", [0, 0])
		# Gebrochene Deko-Tiles (IKEA steht auf 2×2) belegen ALLE
		# überlappten Tiles — sonst baut die Kulisse mitten hinein.
		var r0 := floori(float(tile[0]))
		var c0 := floori(float(tile[1]))
		for r in range(r0, ceili(float(tile[0])) + 1):
			for c in range(c0, ceili(float(tile[1])) + 1):
				belegt[Vector2i(r, c)] = true
	belegt[karte.zuhause_tile()] = true
	return belegt


static func _plane_bloecke(
	karte: CityMap, rng: RandomNumberGenerator, belegt: Dictionary, out: Array[Dictionary]
) -> void:
	for r in karte.reihen:
		for c in karte.spalten:
			var tile := Vector2i(r, c)
			if karte.ist_strasse(tile) or belegt.has(tile):
				continue
			match karte.distrikt_von(tile):
				"gewerbe":
					_plane_gebaeude(karte, rng, tile, GEWERBE_POOL, GEWERBE_TINTS, out, false)
				"zentrum":
					_plane_gebaeude(karte, rng, tile, ZENTRUM_POOL, ZENTRUM_TINTS, out, true)
				"wohnen":
					_plane_vorgarten_haus(karte, rng, tile, out)
				"park":
					_plane_park_tile(karte, rng, tile, out)
				_:
					_plane_stadtrand(karte, rng, tile, out)


static func _plane_gebaeude(
	karte: CityMap,
	rng: RandomNumberGenerator,
	tile: Vector2i,
	pool: Array[Dictionary],
	tints: Array[String],
	out: Array[Dictionary],
	markise_ok: bool
) -> void:
	var wahl: Dictionary = pool[rng.randi_range(0, pool.size() - 1)]
	var tint: String = tints[rng.randi_range(0, tints.size() - 1)]
	var richtung := _richtung_zur_strasse(karte, tile)
	var rot := rad_to_deg(atan2(richtung.x, richtung.z))
	var mitte := karte.tile_zu_welt(tile)
	var s := float(wahl["scale"])
	(
		out
		. append(
			{
				"glb": str(wahl["glb"]),
				"pos": Vector3(mitte.x, 0.05, mitte.z),
				"rot_grad": rot,
				"scale": s,
				"tint": tint,
				"kategorie": "gebaeude",
			}
		)
	)
	if markise_ok and rng.randf() < 0.4 and str(wahl["glb"]).find("low-detail") < 0:
		var markisen_tint: String = MARKISEN_TINTS[rng.randi_range(0, MARKISEN_TINTS.size() - 1)]
		(
			out
			. append(
				{
					"glb": "gebaeude/detail-awning.glb",
					"pos": mitte + richtung * (0.52 * s) + Vector3(0.0, 0.32 * s + 0.05, 0.0),
					"rot_grad": rot,
					"scale": s,
					"tint": markisen_tint,
					"kategorie": "moebel",
					"klein": true,
				}
			)
		)


static func _plane_vorgarten_haus(
	karte: CityMap, rng: RandomNumberGenerator, tile: Vector2i, out: Array[Dictionary]
) -> void:
	var wahl: Dictionary = HAUS_POOL[rng.randi_range(0, HAUS_POOL.size() - 1)]
	var tint: String = HAUS_TINTS[rng.randi_range(0, HAUS_TINTS.size() - 1)]
	var richtung := _richtung_zur_strasse(karte, tile)
	var quer := Vector3(richtung.z, 0.0, -richtung.x)
	var rot := rad_to_deg(atan2(richtung.x, richtung.z))
	var mitte := karte.tile_zu_welt(tile)
	(
		out
		. append(
			{
				"glb": str(wahl["glb"]),
				"pos": Vector3(mitte.x, 0.05, mitte.z) - richtung * 1.5,
				"rot_grad": rot,
				"scale": float(wahl["scale"]),
				"tint": tint,
				"kategorie": "haus",
			}
		)
	)
	# Vorgarten: Gartenweg zur Tür, niedriger Zaun links/rechts davon,
	# ein Hausbaum und ein Blumen-Tupfer — jedes Tile leicht anders.
	(
		out
		. append(
			{
				"glb": "vorstadt/path-stones-long.glb",
				"pos": mitte + richtung * 4.6 + Vector3(0.0, 0.06, 0.0),
				"rot_grad": rot,
				"scale": 9.0,
				"kategorie": "moebel",
				"klein": true,
			}
		)
	)
	for seite: float in [-1.0, 1.0]:
		(
			out
			. append(
				{
					"glb": "vorstadt/fence-low.glb",
					"pos": mitte + richtung * 6.2 + quer * (4.4 * seite) + Vector3(0.0, 0.05, 0.0),
					"rot_grad": rot + 90.0,
					"scale": 4.5,
					"kategorie": "zaun",
					"klein": true,
				}
			)
		)
	var baum: Dictionary = RAND_BAUM_POOL[rng.randi_range(0, RAND_BAUM_POOL.size() - 1)]
	(
		out
		. append(
			{
				"glb": str(baum["glb"]),
				"pos": mitte - richtung * 2.0 + quer * (6.5 * (1.0 if rng.randf() < 0.5 else -1.0)),
				"rot_grad": rng.randf_range(0.0, 360.0),
				"scale": float(baum["scale"]) * rng.randf_range(0.85, 1.15),
				"kategorie": "gruen",
			}
		)
	)
	(
		out
		. append(
			{
				"glb": BLUMEN_POOL[rng.randi_range(0, BLUMEN_POOL.size() - 1)],
				"pos": mitte + richtung * 5.8 + quer * rng.randf_range(-2.0, 2.0),
				"rot_grad": rng.randf_range(0.0, 360.0),
				"scale": 2.5,
				"kategorie": "gruen",
				"klein": true,
			}
		)
	)


static func _plane_park_tile(
	karte: CityMap, rng: RandomNumberGenerator, tile: Vector2i, out: Array[Dictionary]
) -> void:
	var mitte := karte.tile_zu_welt(tile)
	for _i in rng.randi_range(2, 3):
		var baum: Dictionary = PARK_BAUM_POOL[rng.randi_range(0, PARK_BAUM_POOL.size() - 1)]
		(
			out
			. append(
				{
					"glb": str(baum["glb"]),
					"pos": mitte + Vector3(rng.randf_range(-7, 7), 0.0, rng.randf_range(-7, 7)),
					"rot_grad": rng.randf_range(0.0, 360.0),
					"scale": float(baum["scale"]) * rng.randf_range(0.85, 1.2),
					"kategorie": "gruen",
				}
			)
		)
	for _i in rng.randi_range(2, 4):
		(
			out
			. append(
				{
					"glb": BLUMEN_POOL[rng.randi_range(0, BLUMEN_POOL.size() - 1)],
					"pos": mitte + Vector3(rng.randf_range(-8, 8), 0.0, rng.randf_range(-8, 8)),
					"rot_grad": rng.randf_range(0.0, 360.0),
					"scale": 2.5,
					"kategorie": "gruen",
					"klein": true,
				}
			)
		)
	(
		out
		. append(
			{
				"glb": "natur/grass_large.glb",
				"pos": mitte + Vector3(rng.randf_range(-8, 8), 0.0, rng.randf_range(-8, 8)),
				"rot_grad": rng.randf_range(0.0, 360.0),
				"scale": 3.0,
				"kategorie": "gruen",
				"klein": true,
			}
		)
	)
	if (tile.x + tile.y) % 2 == 0:
		var richtung := _richtung_zur_strasse(karte, tile)
		(
			out
			. append(
				{
					"glb": "deko/bench.gltf",
					"pos": mitte + richtung * 6.0 + Vector3(0.0, 0.05, 0.0),
					"rot_grad": rad_to_deg(atan2(richtung.x, richtung.z)),
					"scale": 5.0,
					"kategorie": "moebel",
					"klein": true,
				}
			)
		)
	else:
		(
			out
			. append(
				{
					"glb": "natur/rock_smallA.glb",
					"pos": mitte + Vector3(rng.randf_range(-6, 6), 0.0, rng.randf_range(-6, 6)),
					"rot_grad": rng.randf_range(0.0, 360.0),
					"scale": 4.0,
					"kategorie": "gruen",
					"klein": true,
				}
			)
		)


static func _plane_stadtrand(
	karte: CityMap, rng: RandomNumberGenerator, tile: Vector2i, out: Array[Dictionary]
) -> void:
	var mitte := karte.tile_zu_welt(tile)
	if rng.randf() < 0.75:
		for _i in rng.randi_range(1, 2):
			var baum: Dictionary = RAND_BAUM_POOL[rng.randi_range(0, RAND_BAUM_POOL.size() - 1)]
			(
				out
				. append(
					{
						"glb": str(baum["glb"]),
						"pos": mitte + Vector3(rng.randf_range(-7, 7), 0.0, rng.randf_range(-7, 7)),
						"rot_grad": rng.randf_range(0.0, 360.0),
						"scale": float(baum["scale"]) * rng.randf_range(0.8, 1.25),
						"kategorie": "gruen",
					}
				)
			)
	if rng.randf() < 0.5:
		(
			out
			. append(
				{
					"glb": "natur/plant_bushLarge.glb",
					"pos": mitte + Vector3(rng.randf_range(-8, 8), 0.0, rng.randf_range(-8, 8)),
					"rot_grad": rng.randf_range(0.0, 360.0),
					"scale": 4.5,
					"kategorie": "gruen",
					"klein": true,
				}
			)
		)


## ------------------------------------------------------ Straßenränder


## Seiten (dr, dc) eines Straßen-Tiles, die KEINE Straße sind (= Gehwegseite).
static func _offene_seiten(karte: CityMap, tile: Vector2i) -> Array[Vector2i]:
	var seiten: Array[Vector2i] = []
	for schritt: Vector2i in [Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1)]:
		if not karte.ist_strasse(tile + schritt):
			seiten.append(schritt)
	return seiten


## Straßenseiten, die frei bleiben müssen (Orts-Eingänge + Hausausfahrt).
static func _gesperrte_seiten(karte: CityMap) -> Dictionary:
	var sperren := {}
	for eintrag: Dictionary in karte.orte():
		var strasse := CityMap._tile_von(eintrag.get("strasse", [0, 0]))
		var erste := CityMap._tile_von(eintrag.get("tiles", [[0, 0]])[0])
		sperren["%s|%s" % [strasse, _einheits_schritt(erste - strasse)]] = true
	var zuhause: Vector2i = karte.zuhause_einfahrt()["strasse_tile"]
	var haus := karte.zuhause_tile()
	sperren["%s|%s" % [zuhause, _einheits_schritt(haus - zuhause)]] = true
	return sperren


static func _einheits_schritt(diff: Vector2i) -> Vector2i:
	return Vector2i(signi(diff.x), signi(diff.y))


static func _plane_strassenraender(
	karte: CityMap, rng: RandomNumberGenerator, out: Array[Dictionary]
) -> void:
	var sperren := _gesperrte_seiten(karte)
	var tiles := karte.strassen_tiles()
	tiles.sort()
	for tile in tiles:
		if karte.ist_kreisel(tile):
			continue
		var mitte := karte.tile_zu_welt(tile)
		var seiten := _offene_seiten(karte, tile)
		for i in seiten.size():
			var seite := seiten[i]
			if sperren.has("%s|%s" % [tile, seite]):
				continue
			var v := Vector3(float(seite.y), 0.0, float(seite.x))
			var laengs := Vector3(v.z, 0.0, -v.x)
			var blick_rot := rad_to_deg(atan2(-v.x, -v.z))
			var muster := (tile.x * 31 + tile.y * 17 + i * 7) % 5
			match muster:
				0:
					(
						out
						. append(
							{
								"glb": "deko/bench.gltf",
								"pos": mitte + v * MOEBEL_ABSTAND_M + Vector3(0.0, 0.05, 0.0),
								"rot_grad": blick_rot,
								"scale": 5.0,
								"kategorie": "moebel",
								"klein": true,
							}
						)
					)
				1:
					(
						out
						. append(
							{
								"glb": "deko/firehydrant.gltf",
								"pos":
								(
									mitte
									+ v * (MOEBEL_ABSTAND_M - 0.6)
									+ laengs * 3.0
									+ Vector3(0.0, 0.05, 0.0)
								),
								"rot_grad": blick_rot,
								"scale": 4.0,
								"kategorie": "moebel",
								"klein": true,
							}
						)
					)
				2:
					(
						out
						. append(
							{
								"glb": "vorstadt/planter.glb",
								"pos": mitte + v * MOEBEL_ABSTAND_M + Vector3(0.0, 0.05, 0.0),
								"rot_grad": blick_rot,
								"scale": 4.0,
								"kategorie": "moebel",
								"klein": true,
							}
						)
					)
				3:
					(
						out
						. append(
							{
								"glb": BLUMEN_POOL[rng.randi_range(0, BLUMEN_POOL.size() - 1)],
								"pos":
								mitte + v * GRUEN_ABSTAND_M + laengs * rng.randf_range(-4, 4),
								"rot_grad": rng.randf_range(0.0, 360.0),
								"scale": 2.5,
								"kategorie": "gruen",
								"klein": true,
							}
						)
					)
				_:
					pass
			if rng.randf() < 0.35:
				(
					out
					. append(
						{
							"glb": "natur/grass_large.glb",
							"pos": mitte + v * GRUEN_ABSTAND_M + laengs * rng.randf_range(-6, 6),
							"rot_grad": rng.randf_range(0.0, 360.0),
							"scale": 3.0,
							"kategorie": "gruen",
							"klein": true,
						}
					)
				)


## Bordstein-Parker: stehende Autos an geraden Straßenstücken — Modelle
## variieren, Blickrichtung wechselt, Orts-Eingänge bleiben frei.
static func _plane_parker(
	karte: CityMap, rng: RandomNumberGenerator, out: Array[Dictionary]
) -> void:
	var sperren := _gesperrte_seiten(karte)
	var tiles := karte.strassen_tiles()
	tiles.sort()
	for tile in tiles:
		if karte.ist_kreisel(tile) or (tile.x + tile.y) % 3 != 1:
			continue
		var seiten := _offene_seiten(karte, tile)
		if seiten.size() != 2:
			continue
		var seite := seiten[(tile.x + tile.y) % seiten.size()]
		if sperren.has("%s|%s" % [tile, seite]):
			continue
		var v := Vector3(float(seite.y), 0.0, float(seite.x))
		var laengs := Vector3(v.z, 0.0, -v.x)
		var richtung := 1.0 if (tile.x * 13 + tile.y) % 2 == 0 else -1.0
		var mitte := karte.tile_zu_welt(tile)
		(
			out
			. append(
				{
					"glb": PARKAUTO_POOL[(tile.x * 7 + tile.y * 3) % PARKAUTO_POOL.size()],
					"pos":
					(
						mitte
						+ v * PARKEN_ABSTAND_M
						+ laengs * rng.randf_range(-2.0, 2.0)
						+ Vector3(0.0, CityCarFeel.ROAD_Y, 0.0)
					),
					"rot_grad": rad_to_deg(atan2(laengs.x, laengs.z)) + (90.0 - richtung * 90.0),
					"scale": PARKAUTO_SCALE,
					"kategorie": "parkauto",
					"klein": true,
				}
			)
		)


## Kreisel-Inseln: ein dicker Baum + Blumenkranz in der Mitte.
static func _plane_kreisel_inseln(karte: CityMap, out: Array[Dictionary]) -> void:
	var tiles := karte.strassen_tiles()
	tiles.sort()
	for tile in tiles:
		if not karte.ist_kreisel(tile):
			continue
		var mitte := karte.tile_zu_welt(tile)
		(
			out
			. append(
				{
					"glb": "natur/tree_fat.glb",
					"pos": mitte + Vector3(0.0, 0.4, 0.0),
					"rot_grad": float(tile.x * 45),
					"scale": 5.0,
					"kategorie": "gruen",
				}
			)
		)
		for i in 4:
			var winkel := float(i) * TAU / 4.0
			(
				out
				. append(
					{
						"glb": BLUMEN_POOL[i % BLUMEN_POOL.size()],
						"pos": mitte + Vector3(cos(winkel) * 2.4, 0.4, sin(winkel) * 2.4),
						"rot_grad": rad_to_deg(winkel),
						"scale": 2.2,
						"kategorie": "gruen",
						"klein": true,
					}
				)
			)


## Hausausfahrt des Spielerhauses: sichtbare Einfahrt-Platte vom Bordstein
## bis vor die Haustür, Vorgarten-Zaun links/rechts, Hausbaum + Blumen —
## der Fahrt-Start (FIX-5) parkt das Auto GENAU hier.
static func _plane_zuhause_einfahrt(karte: CityMap, out: Array[Dictionary]) -> void:
	var einfahrt := karte.zuhause_einfahrt()
	var richtung: Vector3 = einfahrt["richtung_haus"]
	var quer := Vector3(richtung.z, 0.0, -richtung.x)
	var strasse: Vector3 = einfahrt["strasse_pos"]
	var rot := rad_to_deg(atan2(richtung.x, richtung.z))
	(
		out
		. append(
			{
				"glb": "vorstadt/driveway-short.glb",
				"pos": strasse + richtung * 11.2 + Vector3(0.0, 0.07, 0.0),
				"rot_grad": rot - 90.0,
				"scale": 26.0,
				"kategorie": "moebel",
			}
		)
	)
	for seite: float in [-1.0, 1.0]:
		(
			out
			. append(
				{
					"glb": "vorstadt/fence-low.glb",
					"pos":
					strasse + richtung * 6.4 + quer * (5.4 * seite) + Vector3(0.0, 0.05, 0.0),
					"rot_grad": rot + 90.0,
					"scale": 4.5,
					"kategorie": "zaun",
					"klein": true,
				}
			)
		)
	(
		out
		. append(
			{
				"glb": "vorstadt/tree-large.glb",
				"pos": strasse + richtung * 15.5 + quer * 7.0,
				"rot_grad": 120.0,
				"scale": 9.0,
				"kategorie": "gruen",
			}
		)
	)
	for i in 3:
		(
			out
			. append(
				{
					"glb": BLUMEN_POOL[i % BLUMEN_POOL.size()],
					"pos": strasse + richtung * (7.0 + float(i)) + quer * -3.6,
					"rot_grad": float(i * 60),
					"scale": 2.4,
					"kategorie": "gruen",
					"klein": true,
				}
			)
		)


## Einheitsvektor vom Tile zur nächstgelegenen angrenzenden Straße
## (deterministisch N→O→S→W; ohne Straßen-Nachbar: Richtung Weltmitte).
static func _richtung_zur_strasse(karte: CityMap, tile: Vector2i) -> Vector3:
	for schritt: Vector2i in [Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1)]:
		if karte.ist_strasse(tile + schritt):
			return Vector3(float(schritt.y), 0.0, float(schritt.x))
	var mitte := karte.tile_zu_welt(tile)
	if mitte.length() < 0.01:
		return Vector3.BACK
	return -mitte.normalized()
