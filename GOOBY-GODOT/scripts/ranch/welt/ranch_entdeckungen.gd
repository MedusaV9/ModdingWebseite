class_name RanchEntdeckungen
extends RefCounted
## Entdeckungsorte der Ranch-Region (FB-2 „Dinge zum Erkunden") — PURE +
## headless-testbar. Feste Fundorte (Wasserfall, Höhle, alter Baum,
## Steinkreis, Aussichtspunkte, versteckte Truhen) mit kleiner Münz-
## Belohnung und Entdeckungs-Toast. Gefundene Orte landen ADDITIV im
## `ranch.welt`-Save (Schlüssel `funde`, Muster RanchWeltState — unbekannte
## Unterschlüssel überleben normalize_welt verbatim, geheilt wird beim
## Lesen). Die Visuals baut RanchFundorteBau; die Trampelpfade dorthin
## zeichnet RanchTerrain.

## Entdeckungs-Radius in Metern (Reiter muss wirklich hinreiten).
const FUND_RADIUS_M := 16.0

## Fundorte: id, name_key (rwelt.fund.*), pos [x, z], blick [x, z]
## (Anreise-/Kamera-Richtung für Screenshots), muenzen (Belohnung).
const ORTE: Array[Dictionary] = [
	{
		"id": "wasserfall",
		"name_key": "rwelt.fund.wasserfall",
		"pos": [252.0, -470.0],
		"blick": [226.0, -414.0],
		"muenzen": 40,
	},
	{
		"id": "hoehle",
		"name_key": "rwelt.fund.hoehle",
		"pos": [95.0, -335.0],
		"blick": [58.0, -296.0],
		"muenzen": 40,
	},
	{
		"id": "alter_baum",
		"name_key": "rwelt.fund.alter_baum",
		"pos": [-500.0, -20.0],
		"blick": [-455.0, 16.0],
		"muenzen": 30,
	},
	{
		"id": "steinkreis",
		"name_key": "rwelt.fund.steinkreis",
		"pos": [60.0, 250.0],
		"blick": [22.0, 214.0],
		"muenzen": 30,
	},
	{
		"id": "aussicht_kamm",
		"name_key": "rwelt.fund.aussicht_kamm",
		"pos": [160.0, -510.0],
		"blick": [140.0, -462.0],
		"muenzen": 25,
	},
	{
		"id": "aussicht_see",
		"name_key": "rwelt.fund.aussicht_see",
		"pos": [598.0, 88.0],
		"blick": [556.0, 120.0],
		"muenzen": 25,
	},
	{
		"id": "truhe_wald",
		"name_key": "rwelt.fund.truhe_wald",
		"pos": [-448.0, -428.0],
		"blick": [-420.0, -400.0],
		"muenzen": 60,
	},
	{
		"id": "truhe_scheune",
		"name_key": "rwelt.fund.truhe_scheune",
		"pos": [-520.0, 498.0],
		"blick": [-492.0, 474.0],
		"muenzen": 60,
	},
	{
		"id": "truhe_ufer",
		"name_key": "rwelt.fund.truhe_ufer",
		"pos": [592.0, 352.0],
		"blick": [556.0, 322.0],
		"muenzen": 60,
	},
]

## NEUE Fundorte des Welt-Ausbaus (WELT-1) — separat von ORTE, weil der
## Bestand-Vertrag exakt neun alte Orte garantiert; Abfragen laufen über
## alle_orte()/fundort(), die BEIDE Listen kennen.
const ORTE_NEU: Array[Dictionary] = [
	{
		"id": "gipfelkreuz",
		"name_key": "rwelt.fund.gipfelkreuz",
		"pos": [-80.0, -1085.0],
		"blick": [30.0, -1030.0],
		"muenzen": 80,
	},
	{
		"id": "bergsee_perle",
		"name_key": "rwelt.fund.bergsee_perle",
		"pos": [100.0, -1064.0],
		"blick": [120.0, -1044.0],
		"muenzen": 50,
	},
	{
		"id": "ruine_schatz",
		"name_key": "rwelt.fund.ruine_schatz",
		"pos": [700.0, -500.0],
		"blick": [666.0, -474.0],
		"muenzen": 70,
	},
	{
		"id": "moor_irrlicht",
		"name_key": "rwelt.fund.moor_irrlicht",
		"pos": [842.0, -172.0],
		"blick": [806.0, -142.0],
		"muenzen": 50,
	},
	{
		"id": "strand_muschel",
		"name_key": "rwelt.fund.strand_muschel",
		"pos": [812.0, 322.0],
		"blick": [846.0, 292.0],
		"muenzen": 45,
	},
	{
		"id": "lavendel_bienen",
		"name_key": "rwelt.fund.lavendel_bienen",
		"pos": [-846.0, 46.0],
		"blick": [-812.0, 74.0],
		"muenzen": 40,
	},
	{
		"id": "kornkreis",
		"name_key": "rwelt.fund.kornkreis",
		"pos": [-470.0, 748.0],
		"blick": [-446.0, 776.0],
		"muenzen": 55,
	},
]

## Trampelpfade, die zu Fundorten führen (schmale Erdspuren im Gelände):
## Punktlisten in Weltkoordinaten — Start liegt an einem Karten-Weg.
const PFADE: Array[Dictionary] = [
	{
		"id": "pfad_alter_baum",
		"breite": 2.0,
		"punkte": [[-320.0, 60.0], [-400.0, 30.0], [-460.0, 4.0], [-500.0, -20.0]],
	},
	{
		"id": "pfad_steinkreis",
		"breite": 2.0,
		"punkte": [[30.0, 190.0], [44.0, 220.0], [60.0, 250.0]],
	},
	{
		"id": "pfad_wasserfall",
		"breite": 2.0,
		"punkte": [[210.0, -380.0], [232.0, -424.0], [248.0, -456.0]],
	},
	{
		"id": "pfad_aussicht_see",
		"breite": 2.0,
		"punkte": [[520.0, 60.0], [560.0, 74.0], [598.0, 88.0]],
	},
	{
		"id": "pfad_truhe_ufer",
		"breite": 1.8,
		"punkte": [[520.0, 396.0], [556.0, 376.0], [592.0, 352.0]],
	},
]

## Trampelpfade zu den NEUEN Fundorten (WELT-1) — jeder startet an einem
## Karten-Weg und endet am Fundort.
const PFADE_NEU: Array[Dictionary] = [
	{
		"id": "pfad_gipfelkreuz",
		"breite": 2.0,
		"punkte": [[60.0, -1004.0], [4.0, -1042.0], [-80.0, -1085.0]],
	},
	{
		"id": "pfad_moor_irrlicht",
		"breite": 1.8,
		"punkte": [[800.0, -130.0], [824.0, -152.0], [842.0, -172.0]],
	},
	{
		"id": "pfad_strand_muschel",
		"breite": 1.8,
		"punkte": [[810.0, 260.0], [808.0, 292.0], [812.0, 322.0]],
	},
	{
		"id": "pfad_lavendel_bienen",
		"breite": 1.8,
		"punkte": [[-810.0, 90.0], [-830.0, 68.0], [-846.0, 46.0]],
	},
	{
		"id": "pfad_kornkreis",
		"breite": 1.8,
		"punkte": [[-440.0, 780.0], [-456.0, 764.0], [-470.0, 748.0]],
	},
]


## Alle Fundorte (Kopie — Aufrufer dürfen nichts kaputtmachen).
static func orte() -> Array[Dictionary]:
	return ORTE.duplicate(true)


## ALLE Fundorte inkl. Welt-Ausbau (WELT-1) — Bau, Streu-Freihaltung und
## fund_bei laufen hierüber.
static func alle_orte() -> Array[Dictionary]:
	var out := ORTE.duplicate(true)
	out.append_array(ORTE_NEU.duplicate(true))
	return out


## Alle Trampelpfade (Bestand + Welt-Ausbau) — Terrain/Streu nutzen das.
static func alle_pfade() -> Array[Dictionary]:
	var out := PFADE.duplicate(true)
	out.append_array(PFADE_NEU.duplicate(true))
	return out


## Fundort-Daten zu einer Id ({} wenn unbekannt) — kennt BEIDE Listen.
static func fundort(id: String) -> Dictionary:
	for liste: Array in [ORTE, ORTE_NEU]:
		for eintrag: Dictionary in liste:
			if str(eintrag["id"]) == id:
				return eintrag.duplicate(true)
	return {}


## Fundort-Position als Vector2 (x, z).
static func position_von(eintrag: Dictionary) -> Vector2:
	var pos: Array = eintrag["pos"]
	return Vector2(float(pos[0]), float(pos[1]))


## Bereits gefundene Fundort-Ids aus dem Save.
static func gefunden(gs: Object) -> Array[String]:
	var out: Array[String] = []
	if gs == null:
		return out
	var welt: Dictionary = RanchWeltState.welt_daten(gs)
	var roh: Variant = welt.get("funde")
	if roh is Array:
		for eintrag: Variant in roh:
			var id := str(eintrag)
			if not out.has(id) and not fundort(id).is_empty():
				out.append(id)
	return out


## Fundort als gefunden markieren + Münzen gutschreiben.
## Rückgabe: {"neu": bool, "muenzen": int, "name_key": String}.
static func entdecke(gs: Object, id: String) -> Dictionary:
	var eintrag := fundort(id)
	if gs == null or eintrag.is_empty():
		return {"neu": false, "muenzen": 0, "name_key": ""}
	if gefunden(gs).has(id):
		return {"neu": false, "muenzen": 0, "name_key": str(eintrag["name_key"])}
	var welt: Dictionary = RanchWeltState.welt_daten(gs)
	var funde: Array = welt.get("funde") if welt.get("funde") is Array else []
	funde.append(id)
	welt["funde"] = funde
	gs.set_value(RanchWeltState.WELT_KEY, welt)
	var muenzen := maxi(0, int(eintrag.get("muenzen", 0)))
	if muenzen > 0 and gs.has_method("update"):
		gs.update(
			func(state: Dictionary) -> void:
				if state.get("economy") is Dictionary:
					var economy: Dictionary = state["economy"]
					economy["coins"] = int(economy.get("coins", 0)) + muenzen
		)
	return {"neu": true, "muenzen": muenzen, "name_key": str(eintrag["name_key"])}


## Erster noch nicht gefundener Fundort im FUND_RADIUS um `pos`
## ({} wenn keiner) — die Szene ruft das im Zonen-Takt auf.
static func fund_bei(gs: Object, pos: Vector3) -> Dictionary:
	var p := Vector2(pos.x, pos.z)
	var schon := gefunden(gs)
	for eintrag: Dictionary in alle_orte():
		if schon.has(str(eintrag["id"])):
			continue
		if p.distance_to(position_von(eintrag)) <= FUND_RADIUS_M:
			return eintrag.duplicate(true)
	return {}
