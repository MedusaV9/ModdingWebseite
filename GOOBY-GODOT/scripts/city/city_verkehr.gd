class_name CityVerkehr
extends RefCounted
## Ambient-Verkehr der Stadt (FIX-5 „Leben"): PURE + headless-testbar —
## Ampel-Phasen an den Kreuzungen, das Anfahren/Bremsen der Loop-Autos
## (halten bei Rot UND hinter dem Vordermann) und die Tageszeit-Menge
## (nachts deutlich weniger Verkehr; nachts blinken die Ampeln gelb und
## regeln nicht). CityScene hängt nur die Meshes ein und ruft `schritt()`.

## Ampel-Umlauf: erste Hälfte Nord/Süd grün, zweite Ost/West — mit
## Alles-Rot-Puffer am Ende jeder Phase (niemand fährt in die Räumzeit).
const ZYKLUS_S := 12.0
const PUFFER_S := 1.5

## So weit voraus schaut ein Auto nach einer roten Ampel (m) …
const BLICK_M := 8.0
## … und so beschleunigt/bremst es (m/s²).
const ACCEL := 4.0
const DECEL := 10.0
## Mindest-Bogenabstand zum Vordermann auf derselben Schleife (m).
const MIN_ABSTAND_M := 8.0

## Verkehrsmenge nach Tageszeit (Autos gesamt, über die Loops verteilt).
const TAG_AUTOS := 9
const NACHT_AUTOS := 3

## Ampel-Leuchtfarben (unshaded, per MultiMesh-Instanzfarbe).
const FARBE_ROT := Color(0.98, 0.22, 0.18)
const FARBE_GRUEN := Color(0.25, 0.92, 0.4)
const FARBE_GELB := Color(1.0, 0.76, 0.18)
const FARBE_AUS := Color(0.16, 0.16, 0.18)
## Nacht-Blinken: Sekunden pro An/Aus-Takt.
const BLINK_TAKT_S := 0.9


## Ampel-Zustand zur (Szenen-)Zeit: welche Achse hat grün?
static func ampel_zustand(zeit: float) -> Dictionary:
	var t := fposmod(zeit, ZYKLUS_S)
	var halb := ZYKLUS_S / 2.0
	return {
		"ns_gruen": t < halb - PUFFER_S,
		"ew_gruen": t >= halb and t < ZYKLUS_S - PUFFER_S,
	}


## Alle Ampel-Kreuzungen der Karte: Vierer- UND T-Kreuzungen (das Lattice
## hat nur 3 echte Kreuze), ohne Kreisel (die regeln sich selbst).
## Sortiert = deterministisch.
static func ampel_tiles(karte: CityMap) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if karte == null or not karte.ist_geladen():
		return out
	for tile in karte.strassen_tiles():
		if karte.ist_kreisel(tile):
			continue
		var nachbarn := 0
		for schritt: Vector2i in [Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1)]:
			if karte.ist_strasse(tile + schritt):
				nachbarn += 1
		if nachbarn >= 3:
			out.append(tile)
	out.sort()
	return out


## Verkehrsmenge zur Stunde: nachts (Laternen an) fahren nur Nachtschwärmer.
static func anzahl(stunde: float) -> int:
	return NACHT_AUTOS if CityAmbiente.lichter_an(stunde) else TAG_AUTOS


## Nachts blinken die Ampeln gelb und regeln NICHT (Kleinstadt-Modus).
static func ampel_blinkt(stunde: float) -> bool:
	return CityAmbiente.ist_nacht(stunde)


## Leuchtfarbe einer Ampel-Birne für die Achse `ew` zur Zeit `zeit`.
static func ampel_farbe(ew: bool, zeit: float, blinkt: bool) -> Color:
	if blinkt:
		var an := fposmod(zeit, BLINK_TAKT_S * 2.0) < BLINK_TAKT_S
		return FARBE_GELB if an else FARBE_AUS
	var zustand := ampel_zustand(zeit)
	var gruen: bool = zustand["ew_gruen"] if ew else zustand["ns_gruen"]
	return FARBE_GRUEN if gruen else FARBE_ROT


## Steht kurz vor dem Wagen eine rote Ampel für SEINE Fahrtrichtung?
## (Wer schon auf der Kreuzung steht, räumt sie — kein Stopp im Kreuz.)
static func rot_voraus(wagen: Dictionary, zeit: float, karte: CityMap, ampeln: Dictionary) -> bool:
	if ampeln.is_empty():
		return false
	var punkte: PackedVector3Array = wagen["punkte"]
	var s := float(wagen["s"])
	var hier := CityRoadGraph.punkt_bei_laenge(punkte, s, true)
	var voraus := CityRoadGraph.punkt_bei_laenge(punkte, s + BLICK_M, true)
	var ziel_tile := karte.welt_zu_tile(voraus["punkt"])
	if not ampeln.has(ziel_tile):
		return false
	if karte.welt_zu_tile(hier["punkt"]) == ziel_tile:
		return false
	var richtung: Vector3 = hier["richtung"]
	var ew := absf(richtung.x) > absf(richtung.z)
	var zustand := ampel_zustand(zeit)
	return not bool(zustand["ew_gruen"] if ew else zustand["ns_gruen"])


## Ein Fahr-Schritt eines Loop-Autos: Zieltempo aus Ampel + Vordermann,
## sanft integriert. `vordermann_m` = Bogenabstand zum nächsten Auto voraus
## (INF, wenn frei). Mutiert `wagen` ({s, tempo}), PURE sonst.
static func schritt(
	wagen: Dictionary,
	dt: float,
	zeit: float,
	karte: CityMap,
	ampeln: Dictionary,
	vordermann_m: float
) -> void:
	var ziel := CityCarFeel.TRAFFIC_SPEED
	if vordermann_m < MIN_ABSTAND_M or rot_voraus(wagen, zeit, karte, ampeln):
		ziel = 0.0
	var tempo := float(wagen.get("tempo", 0.0))
	if tempo < ziel:
		tempo = minf(ziel, tempo + ACCEL * dt)
	else:
		tempo = maxf(ziel, tempo - DECEL * dt)
	wagen["tempo"] = tempo
	wagen["s"] = fposmod(float(wagen["s"]) + tempo * dt, float(wagen["laenge"]))


## Bogenabstand zum nächsten Wagen voraus auf derselben Schleife (m);
## INF, wenn keiner voraus fährt.
static func vordermann_abstand(wagen: Dictionary, andere: Array, laenge: float) -> float:
	var bester := INF
	var s := float(wagen["s"])
	for anderer: Dictionary in andere:
		if is_same(anderer, wagen) or anderer["punkte"] != wagen["punkte"]:
			continue
		var d := fposmod(float(anderer["s"]) - s, laenge)
		if d > 0.01 and d < bester:
			bester = d
	return bester
