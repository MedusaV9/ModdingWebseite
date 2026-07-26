class_name CityGruen
extends RefCounted
## Stadt-Grün-Planer (FB-2 „Der Stadt fehlt auch Szenerie") — PURE +
## headless-testbar. Plant zusätzliches Grün über die ganze Stadt:
## Straßenbäume in regelmäßigen Reihen, Hecken in den Wohnvierteln,
## Blumenkästen im Zentrum/Gewerbe, Grünstreifen mit Gras + Blumen,
## Efeu an den Orts-Fassaden und Blumenampeln an den Laternen. Der Park
## und die Grünflächen werden zusätzlich über die Streu-Bibliothek
## (WeltStreu, Cluster-Regeln) verdichtet.
##
## Einträge kommen im CityKulisse-Schema zurück ({glb, pos, rot_grad,
## scale, tint, kategorie, klein}) und werden von CityBau MIT dem
## Kulissen-Plan gebündelt — gleiche glb|tint-Sorten landen im selben
## MultiMesh und kosten damit KEINE zusätzlichen Draw-Calls.

## Abstand der Baum-/Heckenreihe von der Straßen-Tile-Mitte (hinter dem
## Gehweg, vor den Fassaden — s. CityKulisse MOEBEL_ABSTAND_M = 8,4).
const BAUM_ABSTAND_M := 10.6
const HECKE_ABSTAND_M := 9.6

const STRASSENBAUM_GLB := "vorstadt/tree-large.glb"
const HECKE_GLB := "natur/plant_bush.glb"
const KASTEN_GLB := "vorstadt/planter.glb"
const GRAS_GLB := "natur/grass_large.glb"
const EFEU_GLB := "natur/plant_bush.glb"
const BLUMEN_POOL: Array[String] = [
	"natur/flower_redA.glb", "natur/flower_yellowA.glb", "natur/flower_purpleA.glb"
]
const PARK_STREU_POOL: Array[Dictionary] = [
	{"glb": "natur/plant_bushLarge.glb", "anzahl": 34, "skala": 4.6},
	{"glb": "natur/flower_redA.glb", "anzahl": 38, "skala": 2.8},
	{"glb": "natur/flower_yellowA.glb", "anzahl": 38, "skala": 2.8},
	{"glb": "natur/grass_large.glb", "anzahl": 44, "skala": 3.2},
]


## Kompletter Grün-Plan der Karte (deterministisch über `seed_wert`).
static func plaene(karte: CityMap, seed_wert: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if karte == null or not karte.ist_geladen():
		return out
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_wert
	_plane_strassenbaeume(karte, rng, out)
	_plane_hecken_und_kaesten(karte, rng, out)
	_plane_gruenstreifen(karte, rng, out)
	_plane_efeu(karte, out)
	_plane_blumenampeln(karte, out)
	_plane_park_streu(karte, seed_wert, out)
	return out


## ------------------------------------------------------------ Straßenrand


## Straßenbäume: jede ~2. Straßenzelle bekommt auf der Gehwegseite einen
## Baum — dichte Allee-Anmutung, Orts-Eingänge bleiben frei. (Review-
## Iteration: jede 4. Zelle + Skala <9,5 war aus der Übersicht unsichtbar.)
static func _plane_strassenbaeume(
	karte: CityMap, rng: RandomNumberGenerator, out: Array[Dictionary]
) -> void:
	var sperren := _gesperrte_seiten(karte)
	for tile in _sortierte_strassen(karte):
		if karte.ist_kreisel(tile) or (tile.x * 5 + tile.y * 3) % 2 != 1:
			continue
		var mitte := karte.tile_zu_welt(tile)
		for seite in _offene_seiten(karte, tile):
			if sperren.has("%s|%s" % [tile, seite]):
				continue
			var v := Vector3(float(seite.y), 0.0, float(seite.x))
			var laengs := Vector3(v.z, 0.0, -v.x)
			(
				out
				. append(
					{
						"glb": STRASSENBAUM_GLB,
						"pos": mitte + v * BAUM_ABSTAND_M + laengs * rng.randf_range(-2.0, 2.0),
						"rot_grad": rng.randf_range(0.0, 360.0),
						"scale": rng.randf_range(9.0, 11.5),
						"kategorie": "gruen",
					}
				)
			)


## Hecken (Wohnviertel) + Blumenkästen (Zentrum/Gewerbe): kurze Reihen an
## der Gehwegkante — die Viertel bekommen dadurch klar lesbare Ränder.
static func _plane_hecken_und_kaesten(
	karte: CityMap, rng: RandomNumberGenerator, out: Array[Dictionary]
) -> void:
	var sperren := _gesperrte_seiten(karte)
	for tile in _sortierte_strassen(karte):
		if karte.ist_kreisel(tile) or (tile.x + tile.y * 2) % 3 != 0:
			continue
		var distrikt := karte.distrikt_von(tile)
		var mitte := karte.tile_zu_welt(tile)
		for seite in _offene_seiten(karte, tile):
			if sperren.has("%s|%s" % [tile, seite]):
				continue
			var v := Vector3(float(seite.y), 0.0, float(seite.x))
			var laengs := Vector3(v.z, 0.0, -v.x)
			var blick_rot := rad_to_deg(atan2(-v.x, -v.z))
			if distrikt == "wohnen":
				for schritt: float in [-3.6, -1.2, 1.2, 3.6]:
					(
						out
						. append(
							{
								"glb": HECKE_GLB,
								"pos": mitte + v * HECKE_ABSTAND_M + laengs * schritt,
								"rot_grad": rng.randf_range(0.0, 360.0),
								"scale": rng.randf_range(3.2, 4.2),
								"kategorie": "gruen",
								"klein": true,
							}
						)
					)
			elif distrikt == "zentrum" or distrikt == "gewerbe":
				var kasten_pos := mitte + v * HECKE_ABSTAND_M + laengs * 2.0
				(
					out
					. append(
						{
							"glb": KASTEN_GLB,
							"pos": kasten_pos + Vector3(0.0, 0.05, 0.0),
							"rot_grad": blick_rot,
							"scale": 4.0,
							"kategorie": "gruen",
							"klein": true,
						}
					)
				)
				(
					out
					. append(
						{
							"glb": BLUMEN_POOL[(tile.x + tile.y) % BLUMEN_POOL.size()],
							"pos": kasten_pos + Vector3(0.0, 0.55, 0.0),
							"rot_grad": rng.randf_range(0.0, 360.0),
							"scale": 2.2,
							"kategorie": "gruen",
							"klein": true,
						}
					)
				)


## Grünstreifen: Gras-Büschel + gelegentliche Blume zwischen Gehweg und
## Fahrbahn — nimmt den Straßen die sterile Kante.
static func _plane_gruenstreifen(
	karte: CityMap, rng: RandomNumberGenerator, out: Array[Dictionary]
) -> void:
	var sperren := _gesperrte_seiten(karte)
	for tile in _sortierte_strassen(karte):
		if karte.ist_kreisel(tile) or (tile.x * 3 + tile.y) % 2 != 0:
			continue
		var mitte := karte.tile_zu_welt(tile)
		for seite in _offene_seiten(karte, tile):
			if sperren.has("%s|%s" % [tile, seite]):
				continue
			var v := Vector3(float(seite.y), 0.0, float(seite.x))
			var laengs := Vector3(v.z, 0.0, -v.x)
			for schritt: float in [-6.6, -4.4, -2.2, 0.0, 2.2, 4.4, 6.6]:
				if rng.randf() < 0.2:
					continue
				var gras := rng.randf() < 0.72
				(
					out
					. append(
						{
							"glb":
							(
								GRAS_GLB
								if gras
								else BLUMEN_POOL[rng.randi_range(0, BLUMEN_POOL.size() - 1)]
							),
							"pos": mitte + v * 8.9 + laengs * schritt,
							"rot_grad": rng.randf_range(0.0, 360.0),
							"scale": 3.2 if gras else 2.6,
							"kategorie": "gruen",
							"klein": true,
						}
					)
				)


## ------------------------------------------------------------- Fassaden


## Efeu an Wänden: gestaffelte Grün-Bälle an den Straßenfassaden der Orte
## (unten dicht, oben lockerer = Kletter-Anmutung im Pastell-Stil).
static func _plane_efeu(karte: CityMap, out: Array[Dictionary]) -> void:
	var orte: Array = karte.orte()
	for i in orte.size():
		var eintrag: Dictionary = orte[i]
		if i % 2 != 0:
			continue
		var tiles: Array = eintrag.get("tiles", [])
		if tiles.is_empty():
			continue
		var mitte := Vector3.ZERO
		for tile_raw: Array in tiles:
			mitte += karte.tile_zu_welt(CityMap._tile_von(tile_raw))
		mitte /= float(tiles.size())
		var strasse := karte.tile_zu_welt(CityMap._tile_von(eintrag.get("strasse", [0, 0])))
		var richtung := (strasse - mitte).normalized()
		var laengs := Vector3(richtung.z, 0.0, -richtung.x)
		var front := mitte + richtung * (karte.tile_m * 0.42)
		for stufe: Array in [[0.4, 2.6, -3.2], [1.9, 2.0, -2.6], [3.3, 1.5, -3.0]]:
			var hoehe := float(stufe[0])
			var skala := float(stufe[1])
			var quer := float(stufe[2]) + float(i % 3)
			(
				out
				. append(
					{
						"glb": EFEU_GLB,
						"pos": front + laengs * quer + Vector3(0.0, hoehe, 0.0),
						"rot_grad": float((i * 63) % 360),
						"scale": skala,
						"kategorie": "gruen",
						"klein": true,
					}
				)
			)


## Blumenampeln: kleine Pflanzkästen mit Blume am Laternenmast (gleiche
## Platzierungs-Regel wie CityBau.baue_laternen, versetzt auf ~3,4 m).
static func _plane_blumenampeln(karte: CityMap, out: Array[Dictionary]) -> void:
	for tile in _sortierte_strassen(karte):
		if karte.ist_kreisel(tile) or (tile.x + tile.y) % 3 != 0:
			continue
		var mast := karte.tile_zu_welt(tile) + Vector3(7.0, 0.4, 7.0)
		(
			out
			. append(
				{
					"glb": KASTEN_GLB,
					"pos": mast + Vector3(0.7, 3.4, 0.0),
					"rot_grad": 90.0,
					"scale": 1.6,
					"kategorie": "gruen",
					"klein": true,
				}
			)
		)
		(
			out
			. append(
				{
					"glb": BLUMEN_POOL[(tile.x * 7 + tile.y) % BLUMEN_POOL.size()],
					"pos": mast + Vector3(0.7, 3.62, 0.0),
					"rot_grad": float((tile.x * 40) % 360),
					"scale": 1.4,
					"kategorie": "gruen",
					"klein": true,
				}
			)
		)


## ------------------------------------------------------------------ Park


## Park-/Grünflächen über die Streu-Bibliothek verdichten: Cluster von
## Büschen, Blumen und Gras in den Park-Zonen (Straßen bleiben frei).
static func _plane_park_streu(karte: CityMap, seed_wert: int, out: Array[Dictionary]) -> void:
	var zonen: Array = karte.daten.get("distrikte", {}).get("park", {}).get("zonen", [])
	for z in zonen.size():
		var zone: Array = zonen[z]
		var von := karte.welt_von(float(zone[0]), float(zone[1]))
		var bis := karte.welt_von(float(zone[2]), float(zone[3]))
		var halb := karte.tile_m / 2.0
		var rect := Rect2(
			Vector2(minf(von.x, bis.x) - halb, minf(von.z, bis.z) - halb),
			Vector2(absf(bis.x - von.x) + halb * 2.0, absf(bis.z - von.z) + halb * 2.0)
		)
		var frei := func(p: Vector2) -> bool:
			return not karte.ist_strasse(karte.welt_zu_tile(Vector3(p.x, 0.0, p.y)))
		for s in PARK_STREU_POOL.size():
			var sorte: Dictionary = PARK_STREU_POOL[s]
			var regeln := {
				"rect": rect,
				"anzahl": int(sorte["anzahl"]),
				"cluster": {"anzahl": 5, "radius": 11.0},
				"min_abstand": 2.4,
				"skala_min": float(sorte["skala"]) * 0.8,
				"skala_max": float(sorte["skala"]) * 1.2,
				"frei_fn": frei,
			}
			var salz := seed_wert + 3100 + z * 31 + s * 7
			for t: Transform3D in WeltStreu.verteile(regeln, salz):
				(
					out
					. append(
						{
							"glb": str(sorte["glb"]),
							"pos": t.origin + Vector3(0.0, 0.05, 0.0),
							"rot_grad": rad_to_deg(t.basis.get_euler().y),
							"scale": t.basis.get_scale().x,
							"kategorie": "gruen",
							"klein": true,
						}
					)
				)


## ------------------------------------------------------------------ intern


static func _sortierte_strassen(karte: CityMap) -> Array[Vector2i]:
	var tiles := karte.strassen_tiles()
	tiles.sort()
	return tiles


## Gehwegseiten eines Straßen-Tiles (delegiert an CityKulisse — EINE
## Wahrheit für „wo ist der Bordstein" in Kulisse UND Grün).
static func _offene_seiten(karte: CityMap, tile: Vector2i) -> Array[Vector2i]:
	return CityKulisse._offene_seiten(karte, tile)


## Straßenseiten, die frei bleiben müssen (Orts-Eingänge + Hausausfahrt).
static func _gesperrte_seiten(karte: CityMap) -> Dictionary:
	return CityKulisse._gesperrte_seiten(karte)
