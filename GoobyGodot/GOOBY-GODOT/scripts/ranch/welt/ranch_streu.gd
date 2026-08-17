class_name RanchStreu
extends RefCounted
## Szenerie-Dichte der Ranch-Region (FB-2 „viele Regionen sehen kahl aus"):
## plant über die Streu-Bibliothek (WeltStreu) zusätzliche Bäume, Büsche,
## Blumen, Farne, Steine, Stümpfe und Stämme über die GANZE Region —
## Cluster statt Gleichverteilung, Mindestabstände, Wege/Plateaus/Wasser/
## Fundorte bleiben frei. PURE Planung (headless-testbar) + dünner
## Bau-Schritt über RanchBau.baue_multimesh (ein Draw-Call je Sorte).
## Dichte skaliert über den Qualitäts-Partikelfaktor, Kleinteil-Sichtweiten
## über den Sichtweiten-Faktor.

const ASSETS := "res://assets/ranch"

## Draw-Call-Heuristik je MultiMesh-Gruppe (Mesh + Schatten-Pass).
const DRAW_CALLS_JE_GRUPPE := 2
## Sockel: gemessene Ranch-Ansicht VOR der Streu (Übersicht, xvfb-Lauf).
const DRAW_CALL_SOCKEL := 290
const DRAW_CALL_BUDGET := 400

## Kantenlänge der Kleinteil-Zellen (VIS-1 „Außenwelt wirkt karg"): jede
## Zelle ist ein eigenes MultiMesh mit LOKALEM Distanz-Culling. Vorher
## cullte EIN map-weites MultiMesh über seinen Zentroid — am Kartenrand
## verschwand damit auch das Gras direkt vor der Kamera.
const ZELLE_M := 240.0
## Obergrenze gleichzeitig sichtbarer Zellen je Kleinteil-Sorte (Kreis
## mit Radius Sichtweite + Zell-Marge über der Zellfläche).
const ZELLEN_SICHTBAR_MAX := 11
## Kleinteil-Sichtweite = KLEINTEIL_SICHT_M × dieser Faktor — dank
## Zellen-Culling darf sie weiter tragen als das alte map-weite Limit.
const KLEIN_SICHT_FAKTOR := 1.8

## Streu-Sorten: glb, anzahl (Basis-Dichte), cluster, min_abstand,
## skala, klein (Kleinteil-Culling), optional rect ("wald"), hoehe_min.
const SORTEN: Array[Dictionary] = [
	{
		"glb": "natur/tree_oak.glb",
		"anzahl": 220,
		"cluster": {"anzahl": 17, "radius": 55.0},
		"min_abstand": 9.0,
		"skala_min": 7.0,
		"skala_max": 11.0,
		"einsenken": -0.25,
		"klein": false,
	},
	{
		"glb": "natur/tree_default.glb",
		"anzahl": 190,
		"cluster": {"anzahl": 15, "radius": 48.0},
		"min_abstand": 9.0,
		"skala_min": 7.5,
		"skala_max": 12.0,
		"einsenken": -0.25,
		"klein": false,
	},
	{
		"glb": "natur/tree_detailed.glb",
		"anzahl": 170,
		"cluster": {"anzahl": 14, "radius": 44.0},
		"min_abstand": 9.0,
		"skala_min": 7.0,
		"skala_max": 11.5,
		"einsenken": -0.25,
		"klein": false,
	},
	{
		"glb": "natur/plant_bushLarge.glb",
		"anzahl": 560,
		"cluster": {"anzahl": 50, "radius": 26.0},
		"min_abstand": 4.0,
		"skala_min": 2.4,
		"skala_max": 4.4,
		"klein": false,
	},
	{
		"glb": "natur/plant_bush.glb",
		"anzahl": 450,
		"cluster": {"anzahl": 62, "radius": 22.0},
		"min_abstand": 3.0,
		"skala_min": 2.0,
		"skala_max": 3.6,
		"klein": true,
	},
	{
		"glb": "natur/flower_yellowA.glb",
		"anzahl": 430,
		"cluster": {"anzahl": 34, "radius": 15.0},
		"min_abstand": 2.2,
		"skala_min": 2.2,
		"skala_max": 3.2,
		"klein": true,
	},
	{
		"glb": "natur/flower_redA.glb",
		"anzahl": 340,
		"cluster": {"anzahl": 28, "radius": 14.0},
		"min_abstand": 2.2,
		"skala_min": 2.2,
		"skala_max": 3.2,
		"klein": true,
	},
	{
		"glb": "natur/flower_purpleA.glb",
		"anzahl": 340,
		"cluster": {"anzahl": 28, "radius": 14.0},
		"min_abstand": 2.2,
		"skala_min": 2.2,
		"skala_max": 3.2,
		"klein": true,
	},
	{
		"glb": "natur/grass_large.glb",
		"anzahl": 2000,
		"cluster": {"anzahl": 110, "radius": 26.0},
		"min_abstand": 2.0,
		"skala_min": 2.2,
		"skala_max": 3.6,
		"klein": true,
	},
	{
		"glb": "natur/rock_smallA.glb",
		"anzahl": 240,
		"cluster": {"anzahl": 32, "radius": 18.0},
		"min_abstand": 5.0,
		"skala_min": 1.4,
		"skala_max": 3.2,
		"klein": true,
	},
	{
		"glb": "natur/tree_fat.glb",
		"anzahl": 90,
		"cluster": {"anzahl": 10, "radius": 40.0},
		"min_abstand": 9.0,
		"skala_min": 6.5,
		"skala_max": 10.0,
		"einsenken": -0.25,
		"klein": false,
	},
	{
		"glb": "natur/rock_largeA.glb",
		"anzahl": 112,
		"cluster": {"anzahl": 14, "radius": 26.0},
		"min_abstand": 10.0,
		"skala_min": 2.0,
		"skala_max": 4.6,
		"hoehe_min": 9.0,
		"klein": false,
	},
	{
		"glb": "natur/stump_round.glb",
		"anzahl": 70,
		"cluster": {"anzahl": 15, "radius": 20.0},
		"min_abstand": 8.0,
		"skala_min": 2.2,
		"skala_max": 3.2,
		"klein": false,
	},
	{
		"glb": "natur/log.glb",
		"anzahl": 38,
		"cluster": {"anzahl": 12, "radius": 22.0},
		"min_abstand": 10.0,
		"skala_min": 2.4,
		"skala_max": 3.6,
		"klein": false,
	},
]

## Fundorte bekommen diesen Freihalte-Radius (Landmarke bleibt lesbar —
## Review-Iteration: bei 12 m stand ein Streu-Baum direkt in der Anreise-
## Sichtachse; 26 m hält auch die Kamera-Distanz der Entdeckungs-Shots frei).
const FUNDORT_FREI_M := 26.0
## Abstand der Streu zu Karten-Wegen (zusätzlich zur halben Wegbreite).
const WEG_FREI_M := 4.0

## W19-Perf: Streupläne sind deterministisch (Seed + Dichte + Sorte) —
## einmal rechnen, bei jedem weiteren Betreten der Welt wiederverwenden.
## Die Pläne werden nach dem Bau nie mutiert (nur gelesen).
static var _plan_cache: Dictionary = {}


## Test-Hook: Plan-Cache verwerfen (Determinismus-Vergleiche).
static func reset_for_tests() -> void:
	_plan_cache = {}


## Kompletter Streuplan (deterministisch): je Sorte {glb, klein, transforms}.
static func plaene(dichte_faktor := 1.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for i in SORTEN.size():
		var plan := plan_sorte(i, dichte_faktor)
		if not plan.is_empty():
			out.append(plan)
	return out


## Streuplan EINER Sorte (statisch gecacht) — {} wenn die Sorte bei
## dieser Dichte leer bleibt. Die Sorten sind unabhängig voneinander
## (eigener Seed je Sorte), deshalb kann die Region-Szene sie einzeln
## über das Frame-Budget planen UND bauen.
static func plan_sorte(index: int, dichte_faktor := 1.0) -> Dictionary:
	var dichte := clampf(dichte_faktor, 0.0, 1.0)
	var cache_key := "%d|%.4f|%d" % [RanchKarte.seed_wert(), dichte, index]
	if _plan_cache.has(cache_key):
		var im_cache: Dictionary = _plan_cache[cache_key]
		return im_cache
	var sorte: Dictionary = SORTEN[index]
	var regeln := _regeln_basis()
	for key: String in sorte:
		if key != "glb" and key != "anzahl" and key != "klein":
			regeln[key] = sorte[key]
	regeln["anzahl"] = maxi(0, int(round(float(sorte["anzahl"]) * dichte)))
	var transforms := WeltStreu.verteile(regeln, RanchKarte.seed_wert() + 7000 + index * 13)
	var plan := {}
	if not transforms.is_empty():
		plan = {"glb": str(sorte["glb"]), "klein": bool(sorte["klein"]), "transforms": transforms}
	_plan_cache[cache_key] = plan
	return plan


## Streuplan als MultiMesh-Gruppen unter `wurzel` einhängen.
## Rückgabe: Anzahl gebauter Gruppen (für Budget-Checks).
static func baue(wurzel: Node3D, dichte_faktor := 1.0, sicht_faktor := 1.0) -> int:
	var gruppen := 0
	for schritt: Callable in bau_schritte(wurzel, dichte_faktor, sicht_faktor):
		gruppen += schritt.call()
	return gruppen


## W19-Perf: der Streu-Bau als einzelne Schritte (einer je Sorte, plant
## UND baut) — die Region-Szene streamt sie nach dem Reveal über das
## Frame-Budget. Jeder Schritt liefert die Anzahl gebauter Gruppen.
static func bau_schritte(
	wurzel: Node3D, dichte_faktor := 1.0, sicht_faktor := 1.0
) -> Array[Callable]:
	var bau := RanchBau.new(wurzel)
	var gruppe := Node3D.new()
	gruppe.name = "Streu"
	wurzel.add_child(gruppe)
	var out: Array[Callable] = []
	for i in SORTEN.size():
		out.append(_baue_sorte.bind(bau, gruppe, i, dichte_faktor, sicht_faktor))
	return out


static func _baue_sorte(
	bau: RanchBau, gruppe: Node3D, index: int, dichte_faktor: float, sicht_faktor: float
) -> int:
	var plan := plan_sorte(index, dichte_faktor)
	if plan.is_empty():
		return 0
	var pfad := "%s/%s" % [ASSETS, plan["glb"]]
	if bool(plan["klein"]):
		# VIS-1 („Außenwelt wirkt karg"): Kleinteile tragen weiter in
		# den Mittelgrund UND liegen in Boden-Zellen — nahe Zellen
		# bleiben sichtbar, ferne kosten keine Draw-Calls (Culling je
		# Zell-Zentroid statt map-weit).
		var sicht := (
			RanchBau.KLEINTEIL_SICHT_M * KLEIN_SICHT_FAKTOR * clampf(sicht_faktor, 0.25, 4.0)
		)
		var gruppen := 0
		for zelle: Array in zellen(plan["transforms"]):
			bau.baue_multimesh(gruppe, pfad, zelle, "", sicht + ZELLE_M * 0.5)
			gruppen += 1
		return gruppen
	bau.baue_multimesh(gruppe, pfad, plan["transforms"])
	return 1


## Kleinteil-Transforms in Boden-Gitterzellen (Kantenlänge ZELLE_M)
## aufteilen — deterministische Reihenfolge über sortierte Zell-Schlüssel.
static func zellen(transforms: Array) -> Array:
	var karte: Dictionary = {}
	for t: Transform3D in transforms:
		var key := Vector2i(floori(t.origin.x / ZELLE_M), floori(t.origin.z / ZELLE_M))
		if not karte.has(key):
			karte[key] = []
		(karte[key] as Array).append(t)
	var schluessel: Array = karte.keys()
	schluessel.sort()
	var out: Array = []
	for key: Vector2i in schluessel:
		out.append(karte[key])
	return out


## Draw-Call-Schätzung der Ranch-Ansicht: gemessener Sockel + Kosten je
## Streu-Sorte. Kleinteile rendern ohne Schatten, aber je sichtbarer
## Zelle ein Call; Großteile map-weit mit Schatten-Pass. Der echte
## Nachweis kommt aus dem Screenshot-Lauf.
static func draw_call_schaetzung(streu_plaene: Array[Dictionary]) -> int:
	var calls := DRAW_CALL_SOCKEL
	for plan: Dictionary in streu_plaene:
		if bool(plan["klein"]):
			calls += ZELLEN_SICHTBAR_MAX
		else:
			calls += DRAW_CALLS_JE_GRUPPE
	return calls


## ------------------------------------------------------------------ intern


## Gemeinsame Sperr-Regeln: Bau-Plateaus, See, Fundorte (ALLE — auch die
## neuen), Wege, Wasser, dazu die WELT-1-Sonderflächen (Lavendel-Feld,
## Kornfeld, Obst-Raster, Bucht, Bergsee, Schlucht).
static func _regeln_basis() -> Dictionary:
	var meide_rects: Array[Rect2] = []
	for zone_id: String in ["hof", "turnierplatz", "hufingen"]:
		meide_rects.append(RanchKarte.zone_rect(RanchKarte.zone(zone_id)).grow(6.0))
	for eintrag: Array in [
		["blumenwiese", "lavendel_rect"], ["kornfeld", "feld_rect"], ["obstgarten", "baumraster"]
	]:
		var zone := RanchKarte.zone(str(eintrag[0]))
		if zone.is_empty():
			continue
		var feld: Array = zone[str(eintrag[1])]
		meide_rects.append(
			Rect2(float(feld[0]), float(feld[1]), float(feld[2]), float(feld[3])).grow(4.0)
		)
	var meide_kreise: Array[Dictionary] = []
	var see := RanchKarte.zone("see")
	var see_mitte: Array = see["see_mitte"]
	(
		meide_kreise
		. append(
			{
				"mitte": Vector2(float(see_mitte[0]), float(see_mitte[1])),
				"radius": float(see["see_radius"]) + 14.0,
			}
		)
	)
	_neue_gewaesser_kreise(meide_kreise)
	for eintrag: Dictionary in RanchEntdeckungen.alle_orte():
		meide_kreise.append(
			{"mitte": RanchEntdeckungen.position_von(eintrag), "radius": FUNDORT_FREI_M}
		)
	var segmente := WeltStreu.weg_segmente(RanchKarte.wege(), WEG_FREI_M)
	for pfad: Dictionary in RanchEntdeckungen.alle_pfade():
		segmente.append_array(WeltStreu.weg_segmente([pfad], 2.0))
	var schlucht: Dictionary = RanchKarte.karte().get("schlucht", {})
	if not schlucht.is_empty():
		var halb := float(schlucht["breite"]) / 2.0 + 5.0
		segmente.append_array(
			WeltStreu.weg_segmente([{"punkte": schlucht["punkte"], "breite": 0.0}], halb)
		)
	return {
		"rect": RanchKarte.grenzen().grow(-30.0),
		"meide_rects": meide_rects,
		"meide_kreise": meide_kreise,
		"meide_segmente": segmente,
		"hoehe_fn": func(x: float, z: float) -> float: return RanchGelaende.hoehe(x, z),
		"frei_fn": func(p: Vector2) -> bool: return not RanchGelaende.ist_wasser(p.x, p.y),
	}


## Bucht + Bergsee + Moor-Tümpel als Sperr-Kreise.
static func _neue_gewaesser_kreise(meide_kreise: Array[Dictionary]) -> void:
	var strand := RanchKarte.zone("strand")
	if not strand.is_empty():
		var bucht: Array = strand["bucht_mitte"]
		(
			meide_kreise
			. append(
				{
					"mitte": Vector2(float(bucht[0]), float(bucht[1])),
					"radius": float(strand["bucht_radius"]) + 10.0,
				}
			)
		)
	var berg := RanchKarte.zone("bergmassiv")
	if not berg.is_empty():
		var bs: Array = berg["bergsee_mitte"]
		(
			meide_kreise
			. append(
				{
					"mitte": Vector2(float(bs[0]), float(bs[1])),
					"radius": float(berg["bergsee_radius"]) + 8.0,
				}
			)
		)
	var moor := RanchKarte.zone("moor")
	if not moor.is_empty():
		for paar: Array in moor["tuempel"]:
			(
				meide_kreise
				. append(
					{
						"mitte": Vector2(float(paar[0]), float(paar[1])),
						"radius": RanchGelaende.TUEMPEL_RADIUS_M + 3.0,
					}
				)
			)
