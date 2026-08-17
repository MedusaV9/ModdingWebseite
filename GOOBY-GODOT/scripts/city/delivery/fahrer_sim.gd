class_name GooberandoFahrerSim
extends RefCounted
## Deterministische GOOBERANDO-Fahrer-Simulation (W13B, Doc E §5.2): der
## Fahrer startet am Restaurant-Straßenknoten, fährt die A*-Route des
## road_graph (scripts/city/road_graph.gd, NUR LESEN) zum Haus, und seine
## Position ist eine REINE Funktion der Save-Timestamps — App zu/auf/
## Neustart egal, gleiche Zeit = gleiche Position (kein RNG, kein Node).
##
## Zeitmodell (kompatibel zur bestehenden GooberandoLogic, deren `fertigAt`
## die Haustür-Ankunft ist): Abfahrt = fertigAt − Fahrzeit, geklammert auf
## bestelltAt. Vor der Abfahrt goobyt die Küche (Fahrer steht am
## Restaurant), danach wandert er die Route entlang, ab fertigAt steht er
## vor der Tür.

## Doc E §5.2: fahrzeit = routenlänge / 8 m/s.
const TEMPO_M_S := 8.0

const PHASE_KUECHE := "kueche"
const PHASE_UNTERWEGS := "unterwegs"
const PHASE_DA := "da"


## Welt-Polyline der Fahrt: A*-Pfad Restaurant-Knoten → Haus-Knoten,
## Tile-Mitten in Weltkoordinaten. Leer, wenn die Karte kein Netz hat.
static func route_welt(
	karte: CityMap, graph: CityRoadGraph, start: Vector2i, ziel: Vector2i
) -> PackedVector3Array:
	var punkte := PackedVector3Array()
	if karte == null or graph == null or graph.knoten_anzahl() == 0:
		return punkte
	for tile in graph.pfad(graph.naechste_strasse(start), graph.naechste_strasse(ziel)):
		punkte.append(karte.tile_zu_welt(tile))
	return punkte


static func fahrzeit_s(route: PackedVector3Array) -> float:
	return CityRoadGraph.polyline_laenge(route) / TEMPO_M_S


## Abfahrtszeitpunkt (ms): so spät wie möglich losfahren, damit die Ankunft
## exakt auf fertigAt fällt — nie vor der Bestellung.
static func abfahrt_ms(bestellt_ms: int, fertig_ms: int, route: PackedVector3Array) -> int:
	return maxi(bestellt_ms, fertig_ms - int(fahrzeit_s(route) * 1000.0))


## Fahrer-Zustand zur Uhrzeit now_ms — DETERMINISTISCH.
## Rückgabe: {phase, punkt: Vector3, richtung: Vector3, fortschritt: 0..1}.
static func status(
	route: PackedVector3Array, bestellt_ms: int, fertig_ms: int, now_ms: int
) -> Dictionary:
	if route.is_empty():
		var phase := PHASE_DA if now_ms >= fertig_ms else PHASE_KUECHE
		return {
			"phase": phase,
			"punkt": Vector3.ZERO,
			"richtung": Vector3(1, 0, 0),
			"fortschritt": 1.0 if now_ms >= fertig_ms else 0.0,
		}
	var los := abfahrt_ms(bestellt_ms, fertig_ms, route)
	if now_ms <= los:
		return {
			"phase": PHASE_KUECHE,
			"punkt": route[0],
			"richtung": Vector3(1, 0, 0),
			"fortschritt": 0.0,
		}
	if now_ms >= fertig_ms or fertig_ms <= los:
		return {
			"phase": PHASE_DA,
			"punkt": route[route.size() - 1],
			"richtung": Vector3(1, 0, 0),
			"fortschritt": 1.0,
		}
	var fortschritt := float(now_ms - los) / float(fertig_ms - los)
	var laenge := CityRoadGraph.polyline_laenge(route)
	var bei := CityRoadGraph.punkt_bei_laenge(route, fortschritt * laenge)
	return {
		"phase": PHASE_UNTERWEGS,
		"punkt": bei["punkt"],
		"richtung": bei["richtung"],
		"fortschritt": fortschritt,
	}
