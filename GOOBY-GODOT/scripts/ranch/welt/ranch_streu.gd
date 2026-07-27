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

## Streu-Sorten: glb, anzahl (Basis-Dichte), cluster, min_abstand,
## skala, klein (Kleinteil-Culling), optional rect ("wald"), hoehe_min.
const SORTEN: Array[Dictionary] = [
	{
		"glb": "natur/tree_oak.glb",
		"anzahl": 150,
		"cluster": {"anzahl": 14, "radius": 55.0},
		"min_abstand": 9.0,
		"skala_min": 7.0,
		"skala_max": 11.0,
		"einsenken": -0.25,
		"klein": false,
	},
	{
		"glb": "natur/tree_default.glb",
		"anzahl": 130,
		"cluster": {"anzahl": 12, "radius": 48.0},
		"min_abstand": 9.0,
		"skala_min": 7.5,
		"skala_max": 12.0,
		"einsenken": -0.25,
		"klein": false,
	},
	{
		"glb": "natur/tree_detailed.glb",
		"anzahl": 115,
		"cluster": {"anzahl": 11, "radius": 44.0},
		"min_abstand": 9.0,
		"skala_min": 7.0,
		"skala_max": 11.5,
		"einsenken": -0.25,
		"klein": false,
	},
	{
		"glb": "natur/plant_bushLarge.glb",
		"anzahl": 360,
		"cluster": {"anzahl": 34, "radius": 26.0},
		"min_abstand": 4.0,
		"skala_min": 2.4,
		"skala_max": 4.4,
		"klein": true,
	},
	{
		"glb": "natur/plant_bush.glb",
		"anzahl": 250,
		"cluster": {"anzahl": 40, "radius": 22.0},
		"min_abstand": 3.0,
		"skala_min": 2.0,
		"skala_max": 3.6,
		"klein": true,
	},
	{
		"glb": "natur/flower_yellowA.glb",
		"anzahl": 240,
		"cluster": {"anzahl": 20, "radius": 15.0},
		"min_abstand": 2.2,
		"skala_min": 2.2,
		"skala_max": 3.2,
		"klein": true,
	},
	{
		"glb": "natur/flower_redA.glb",
		"anzahl": 180,
		"cluster": {"anzahl": 16, "radius": 14.0},
		"min_abstand": 2.2,
		"skala_min": 2.2,
		"skala_max": 3.2,
		"klein": true,
	},
	{
		"glb": "natur/flower_purpleA.glb",
		"anzahl": 180,
		"cluster": {"anzahl": 16, "radius": 14.0},
		"min_abstand": 2.2,
		"skala_min": 2.2,
		"skala_max": 3.2,
		"klein": true,
	},
	{
		"glb": "natur/grass_large.glb",
		"anzahl": 460,
		"cluster": {"anzahl": 44, "radius": 20.0},
		"min_abstand": 2.0,
		"skala_min": 2.2,
		"skala_max": 3.6,
		"klein": true,
	},
	{
		"glb": "natur/rock_smallA.glb",
		"anzahl": 140,
		"cluster": {"anzahl": 20, "radius": 18.0},
		"min_abstand": 5.0,
		"skala_min": 1.4,
		"skala_max": 3.2,
		"klein": true,
	},
	{
		"glb": "natur/rock_largeA.glb",
		"anzahl": 90,
		"cluster": {"anzahl": 12, "radius": 26.0},
		"min_abstand": 10.0,
		"skala_min": 2.0,
		"skala_max": 4.6,
		"hoehe_min": 9.0,
		"klein": false,
	},
	{
		"glb": "natur/stump_round.glb",
		"anzahl": 54,
		"cluster": {"anzahl": 12, "radius": 20.0},
		"min_abstand": 8.0,
		"skala_min": 2.2,
		"skala_max": 3.2,
		"klein": true,
	},
	{
		"glb": "natur/log.glb",
		"anzahl": 26,
		"cluster": {"anzahl": 9, "radius": 22.0},
		"min_abstand": 10.0,
		"skala_min": 2.4,
		"skala_max": 3.6,
		"klein": true,
	},
]

## Fundorte bekommen diesen Freihalte-Radius (Landmarke bleibt lesbar —
## Review-Iteration: bei 12 m stand ein Streu-Baum direkt in der Anreise-
## Sichtachse; 26 m hält auch die Kamera-Distanz der Entdeckungs-Shots frei).
const FUNDORT_FREI_M := 26.0
## Abstand der Streu zu Karten-Wegen (zusätzlich zur halben Wegbreite).
const WEG_FREI_M := 4.0


## Kompletter Streuplan (deterministisch): je Sorte {glb, klein, transforms}.
static func plaene(dichte_faktor := 1.0) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var dichte := clampf(dichte_faktor, 0.0, 1.0)
	var basis := _regeln_basis()
	var seed_wert := RanchKarte.seed_wert()
	for i in SORTEN.size():
		var sorte: Dictionary = SORTEN[i]
		var regeln := basis.duplicate()
		for key: String in sorte:
			if key != "glb" and key != "anzahl" and key != "klein":
				regeln[key] = sorte[key]
		regeln["anzahl"] = maxi(0, int(round(float(sorte["anzahl"]) * dichte)))
		var transforms := WeltStreu.verteile(regeln, seed_wert + 7000 + i * 13)
		if transforms.is_empty():
			continue
		(
			out
			. append(
				{
					"glb": str(sorte["glb"]),
					"klein": bool(sorte["klein"]),
					"transforms": transforms,
				}
			)
		)
	return out


## Streuplan als MultiMesh-Gruppen unter `wurzel` einhängen.
## Rückgabe: Anzahl gebauter Gruppen (für Budget-Checks).
static func baue(wurzel: Node3D, dichte_faktor := 1.0, sicht_faktor := 1.0) -> int:
	var bau := RanchBau.new(wurzel)
	var gruppen := 0
	var gruppe := Node3D.new()
	gruppe.name = "Streu"
	wurzel.add_child(gruppe)
	for plan: Dictionary in plaene(dichte_faktor):
		var sicht := 0.0
		if bool(plan["klein"]):
			sicht = RanchBau.KLEINTEIL_SICHT_M * clampf(sicht_faktor, 0.25, 4.0)
		bau.baue_multimesh(gruppe, "%s/%s" % [ASSETS, plan["glb"]], plan["transforms"], "", sicht)
		gruppen += 1
	return gruppen


## Draw-Call-Schätzung der Ranch-Ansicht: gemessener Sockel + Kosten je
## Streu-Gruppe. Der echte Nachweis kommt aus dem Screenshot-Lauf.
static func draw_call_schaetzung(streu_plaene: Array[Dictionary]) -> int:
	return DRAW_CALL_SOCKEL + streu_plaene.size() * DRAW_CALLS_JE_GRUPPE


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
