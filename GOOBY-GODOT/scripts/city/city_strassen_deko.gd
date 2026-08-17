class_name CityStrassenDeko
extends RefCounted
## Straßenbild-Planer (GOOBY-WELT/STADT, EVAL B §2 „mehr Leben und
## Vielfalt") — PURE + headless-testbar: Zebrastreifen an den Ampel-
## Kreuzungen, zwei Bushaltestellen, Mülltonnen-Vielfalt entlang der
## Bordsteine, Tauben-Grüppchen an Markt und Stadtpark und die kleine
## Café-Terrasse am Park. Hier entstehen nur POSITIONEN/Transforms —
## die Nodes baut CityStrassenDekoBau (MultiMesh, Draw-Call-Budget).

## Zebrastreifen: Abstand der Streifenmitte von der Kreuzungsmitte (m),
## Streifenmaß (quer × hoch × längs) und Streifen je Übergang.
const ZEBRA_ABSTAND_M := 7.6
const ZEBRA_STREIFEN := 7
const ZEBRA_MASS := Vector3(0.62, 0.04, 1.7)
const ZEBRA_SCHRITT_M := 1.24

## Mülltonnen: jedes 4. Straßen-Tile, seitlich am Bordstein, drei Farben.
const TONNEN_ABSTAND_M := 8.9
const TONNEN_FARBEN: Array[Color] = [Color("#5F7161"), Color("#4E79D6"), Color("#7A7F87")]

## Bushaltestellen: feste Straßen-Tiles + Gehwegseite (dr, dc).
const HALTESTELLEN := [
	{"tile": Vector2i(4, 8), "seite": Vector2i(1, 0)},
	{"tile": Vector2i(10, 4), "seite": Vector2i(-1, 0)},
]

## Tauben-Grüppchen: Wochenmarkt-Platz + Stadtpark (Tile-Koordinaten).
const TAUBEN_PLAETZE := [Vector2(6.0, 7.5), Vector2(8.4, 8.2)]
const TAUBEN_JE_PLATZ := 5

## Café-Terrasse: Straßen-Tile + Gehwegseite Richtung Stadtpark.
const CAFE_TILE := Vector2i(7, 8)
const CAFE_SEITE := Vector2i(1, 0)


## Zebrastreifen-Transforms (EIN weißes Box-MultiMesh): an jeder Ampel-
## Kreuzung ein Übergang je Straßen-Zufahrt, Streifen längs zur Fahrbahn.
static func zebra_transforms(karte: CityMap) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	if karte == null or not karte.ist_geladen():
		return out
	for tile in CityVerkehr.ampel_tiles(karte):
		var mitte := karte.tile_zu_welt(tile)
		for schritt: Vector2i in [Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1)]:
			if not karte.ist_strasse(tile + schritt):
				continue
			var v := Vector3(float(schritt.y), 0.0, float(schritt.x))
			var quer := Vector3(v.z, 0.0, -v.x)
			var rot := atan2(v.x, v.z)
			for i in ZEBRA_STREIFEN:
				var q := (float(i) - float(ZEBRA_STREIFEN - 1) * 0.5) * ZEBRA_SCHRITT_M
				var basis := Basis(Vector3.UP, rot)
				var pos := mitte + v * ZEBRA_ABSTAND_M + quer * q
				pos.y = CityCarFeel.ROAD_Y + 0.03
				out.append(Transform3D(basis, pos))
	return out


## Mülltonnen-Plätze: {pos, rot, farbe} — deterministisch, am Bordstein,
## NIE vor einer Orts-Zufahrt (gleiche Sperren wie die Kulissen-Möbel).
static func muelltonnen(karte: CityMap) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if karte == null or not karte.ist_geladen():
		return out
	var sperren := CityKulisse._gesperrte_seiten(karte)
	var tiles := karte.strassen_tiles()
	tiles.sort()
	for tile in tiles:
		if karte.ist_kreisel(tile) or (tile.x * 5 + tile.y) % 4 != 2:
			continue
		var seiten := CityKulisse._offene_seiten(karte, tile)
		if seiten.is_empty():
			continue
		var seite := seiten[(tile.x + tile.y * 3) % seiten.size()]
		if sperren.has("%s|%s" % [tile, seite]):
			continue
		var v := Vector3(float(seite.y), 0.0, float(seite.x))
		var laengs := Vector3(v.z, 0.0, -v.x)
		var mitte := karte.tile_zu_welt(tile)
		var pos := mitte + v * TONNEN_ABSTAND_M + laengs * float((tile.x * 7 + tile.y) % 9 - 4)
		(
			out
			. append(
				{
					"pos": pos + Vector3(0.0, 0.05, 0.0),
					"rot": atan2(-v.x, -v.z) + float(tile.y % 3 - 1) * 0.35,
					"farbe": TONNEN_FARBEN[(tile.x + tile.y) % TONNEN_FARBEN.size()],
				}
			)
		)
	return out


## Bushaltestellen: {pos, rot} — Rückwand zeigt vom Bordstein weg.
static func bushaltestellen(karte: CityMap) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if karte == null or not karte.ist_geladen():
		return out
	for eintrag: Dictionary in HALTESTELLEN:
		var tile: Vector2i = eintrag["tile"]
		if not karte.ist_strasse(tile):
			continue
		var seite: Vector2i = eintrag["seite"]
		var v := Vector3(float(seite.y), 0.0, float(seite.x))
		var pos := karte.tile_zu_welt(tile) + v * (CityKulisse.MOEBEL_ABSTAND_M + 0.6)
		out.append({"pos": pos + Vector3(0.0, 0.05, 0.0), "rot": atan2(-v.x, -v.z)})
	return out


## Tauben: {pos, rot, pickt} — Grüppchen mit deterministischem Streu-Jitter.
static func tauben(karte: CityMap, seed_wert: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if karte == null or not karte.ist_geladen():
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_wert
	for platz: Vector2 in TAUBEN_PLAETZE:
		var mitte := karte.welt_von(platz.x, platz.y)
		for _i in TAUBEN_JE_PLATZ:
			(
				out
				. append(
					{
						"pos":
						(
							mitte
							+ Vector3(rng.randf_range(-4.5, 4.5), 0.05, rng.randf_range(-4.5, 4.5))
						),
						"rot": rng.randf_range(0.0, TAU),
						"pickt": rng.randf() < 0.5,
					}
				)
			)
	return out


## Café-Terrasse am Stadtpark: {pos, rot} (leer, wenn das Tile keine
## Straße ist — Karten-Wächter für Tests).
static func cafe(karte: CityMap) -> Dictionary:
	if karte == null or not karte.ist_geladen() or not karte.ist_strasse(CAFE_TILE):
		return {}
	var v := Vector3(float(CAFE_SEITE.y), 0.0, float(CAFE_SEITE.x))
	var pos := karte.tile_zu_welt(CAFE_TILE) + v * (CityKulisse.MOEBEL_ABSTAND_M + 1.2)
	return {"pos": pos + Vector3(0.0, 0.05, 0.0), "rot": atan2(-v.x, -v.z)}
