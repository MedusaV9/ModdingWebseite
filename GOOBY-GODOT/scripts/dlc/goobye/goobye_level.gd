class_name GoobyeLevel
extends RefCounted
## Laden-Level 1–5 des „Goo und Bye“ (W19 Welle C, Doc §7.1) — PURE + static.
## §7.1 will eine ZUSTANDS-Prüfung, keinen Grind-Zähler: das Level ist eine
## reine Funktion des Save-Stands, es gibt keinen eigenen Level-Zähler im
## Save. Die volle Prüf-Matrix (Attraktivität, Sonderwünsche, Rabatt-Samstag,
## Promi-Besuch) kommt mit ihren Systemen in späteren Wellen — Welle C nimmt
## die zwei EHRLICHEN Größen, die der Laden seit Welle A führt und die nur
## durch echtes Spielen wachsen (Kassensturz §2.3): Markttage (umsatz.tage)
## und Gesamtumsatz (umsatz.gesamt). Beide fallen nie ⇒ das Level auch nicht.

## Stufen 2..5 (Namen nach §7.1): BEIDE Schwellen müssen erfüllt sein.
## Zahlen auf die Welle-A/B-Realität balanciert (2–3 Kunden/Tag, ~20–60 ᴳ
## Tagesumsatz) — Level 5 ist ein ehrliches Mittelfrist-Ziel, kein Grind.
const STUFEN: Array[Dictionary] = [
	{"level": 2, "tage": 2, "gesamt": 60, "name_key": "dlc_goobye.level.minimarkt"},
	{"level": 3, "tage": 5, "gesamt": 200, "name_key": "dlc_goobye.level.frischemarkt"},
	{"level": 4, "tage": 9, "gesamt": 420, "name_key": "dlc_goobye.level.supermarkt"},
	{"level": 5, "tage": 14, "gesamt": 800, "name_key": "dlc_goobye.level.xxl"},
]

const LEVEL_MIN := 1
const LEVEL_MAX := 5
const NAME_KEY_START := "dlc_goobye.level.marktstand"


## Laden-Level aus dem Umsatz-Zettel {tage, gestern, gesamt} (PURE).
static func level_von(umsatz: Dictionary) -> int:
	var tage := maxi(0, int(umsatz.get("tage", 0)))
	var gesamt := maxi(0, int(umsatz.get("gesamt", 0)))
	var level := LEVEL_MIN
	for stufe: Dictionary in STUFEN:
		if tage >= int(stufe["tage"]) and gesamt >= int(stufe["gesamt"]):
			level = int(stufe["level"])
	return level


## Laden-Level für den Spielstand (liest dlc.goobye.umsatz).
static func level_fuer(gs: Object) -> int:
	if gs == null:
		return LEVEL_MIN
	var raw: Variant = gs.get_value("dlc.goobye.umsatz", {})
	return level_von(raw if raw is Dictionary else {})


## String-Key des Stufen-Namens (§7.1: Marktstand … Goo und Bye XXL).
static func name_key(level: int) -> String:
	for stufe: Dictionary in STUFEN:
		if int(stufe["level"]) == clampi(level, LEVEL_MIN, LEVEL_MAX):
			return str(stufe["name_key"])
	return NAME_KEY_START
