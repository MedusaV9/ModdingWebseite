class_name RanchCompKatalog
extends RefCounted
## Wettbewerbs-Katalog (RW-5, RANCH-DLC-IDEAS-3 Kap. 5) — PURE. Die EINE
## Wahrheit über Disziplinen, Klassen, Gold-/XP-Zahlen und Richtzeiten.
## Balance kommt aus comp_balance.json (Content-Pack-Namespace "ranchcomp",
## Muster RanchWirtschaft/RanchParcoursLogic) — Code kennt nur Fallbacks.
## Klassen-Leiter: Holz → Bronze → Silber → Gold → Sternenklasse; Gold-
## Faktor ×1,0–×4,0, Einstieg über Pferde-Level (Kap. 5.1), KEIN Abstieg.

const BALANCE_PATH := "res://scripts/ranch/comp/comp_balance.json"

const KLASSEN: Array[String] = ["holz", "bronze", "silber", "gold", "sternenklasse"]
const DISZIPLINEN: Array[String] = [
	"springen", "dressur", "gelaende", "rennen", "trail", "schau", "tonnen"
]
## Fallbacks (== comp_balance.json; Tests sichern die Synchronität).
const KLASSE_AB_LEVEL := {"holz": 1, "bronze": 5, "silber": 10, "gold": 18, "sternenklasse": 25}
const GOLD_FAKTOR := {"holz": 1.0, "bronze": 1.5, "silber": 2.0, "gold": 3.0, "sternenklasse": 4.0}
const XP_JE_TEILNAHME := {
	"holz": 60, "bronze": 90, "silber": 130, "gold": 180, "sternenklasse": 240
}
const BASIS_GOLD := 40
const PLATZ_ANTEIL: Array[float] = [1.0, 0.6, 0.35]
const SCHLEIFE_AB_PLATZ := 3


## Balance laden; registry-Duck-Typing wie RanchParcoursLogic.load_kurse —
## ohne ContentRegistry gilt das eingebaute JSON.
static func load_balance(registry: Object = null) -> Dictionary:
	var daten := RanchWirtschaft.read_json(BALANCE_PATH)
	var reg := registry
	if reg == null:
		var loop := Engine.get_main_loop()
		if loop is SceneTree:
			reg = (loop as SceneTree).root.get_node_or_null("ContentRegistry")
	if reg != null and reg.has_method("get_balance"):
		var overrides: Variant = reg.get_balance("ranchcomp", {})
		if overrides is Dictionary and not (overrides as Dictionary).is_empty():
			var merged := daten.duplicate(true)
			merged.merge(overrides as Dictionary, true)
			return merged
	return daten


## Klassen-Eintrag {id, ab_level, gold_faktor, xp, aufstieg_punkte}.
static func klasse(balance: Dictionary, id: String) -> Dictionary:
	for eintrag: Variant in balance.get("klassen", []):
		if eintrag is Dictionary and str((eintrag as Dictionary).get("id", "")) == id:
			return eintrag
	return {
		"id": id,
		"ab_level": int(KLASSE_AB_LEVEL.get(id, 1)),
		"gold_faktor": float(GOLD_FAKTOR.get(id, 1.0)),
		"xp": int(XP_JE_TEILNAHME.get(id, 60)),
		"aufstieg_punkte": 0,
	}


static func klasse_index(id: String) -> int:
	return maxi(0, KLASSEN.find(id))


## Nächsthöhere Klasse ("" = Sternenklasse ist das Dach).
static func klasse_danach(id: String) -> String:
	var i := KLASSEN.find(id)
	if i < 0 or i >= KLASSEN.size() - 1:
		return ""
	return KLASSEN[i + 1]


## Darf ein Pferd dieses Levels in der Klasse starten? (Kap. 5.1-Gate.)
static func klasse_erlaubt(balance: Dictionary, id: String, pferde_level: int) -> bool:
	return pferde_level >= int(_num(klasse(balance, id).get("ab_level"), 1.0))


## Disziplin-Eintrag {id, wertung: punkte|zeit|platz, stats}.
static func disziplin(balance: Dictionary, id: String) -> Dictionary:
	for eintrag: Variant in balance.get("disziplinen", []):
		if eintrag is Dictionary and str((eintrag as Dictionary).get("id", "")) == id:
			return eintrag
	return {"id": id, "wertung": "punkte", "stats": []}


## Wertungsrichtung: true = kleinere Zahl gewinnt (Zeit-Disziplinen).
static func zeit_gewinnt(balance: Dictionary, disziplin_id: String) -> bool:
	var art := str(disziplin(balance, disziplin_id).get("wertung", "punkte"))
	return art == "zeit" or art == "platz"


## Richtzeit (s) einer Disziplin×Klasse; 0 = Disziplin ohne Richtzeit.
static func richtzeit_s(balance: Dictionary, disziplin_id: String, klasse_id: String) -> float:
	var zeiten: Variant = balance.get("richtzeiten", {})
	if zeiten is Dictionary and (zeiten as Dictionary).get(disziplin_id) is Dictionary:
		return _num(((zeiten as Dictionary)[disziplin_id] as Dictionary).get(klasse_id), 0.0)
	return 0.0


## Gold für eine Platzierung: Basis 40 G × Platz-Anteil (100/60/35 %) ×
## Klassenfaktor (×1,0–×4,0). Ab Platz 4 gibt es Trostgold (10 %).
static func gold_fuer_platz(balance: Dictionary, klasse_id: String, platz: int) -> int:
	var basis := _num(balance.get("basis_gold"), float(BASIS_GOLD))
	var anteile: Variant = balance.get("platz_anteil", PLATZ_ANTEIL)
	var anteil := 0.1
	if anteile is Array and platz >= 1 and platz <= (anteile as Array).size():
		anteil = _num((anteile as Array)[platz - 1], 0.1)
	var faktor := _num(klasse(balance, klasse_id).get("gold_faktor"), 1.0)
	return int(round(basis * anteil * faktor))


## Pferde-XP je Teilnahme (Kap. 5.1: 60–240) — deckungsgleich mit
## RanchHorseLevels.XP_WETTBEWERB (Test sichert die Katalog-Synchronität).
static func xp_fuer_teilnahme(balance: Dictionary, klasse_id: String) -> int:
	return int(_num(klasse(balance, klasse_id).get("xp"), 60.0))


## Turnierschleife gibt es ab Platz 3 (einmalig je Disziplin×Klasse).
static func schleife_verdient(balance: Dictionary, platz: int) -> bool:
	return platz >= 1 and platz <= int(_num(balance.get("schleife_ab_platz"), 3.0))


## Bot-Können-Band [von, bis] einer Klasse (0..1).
static func bot_band(balance: Dictionary, klasse_id: String) -> Array:
	var baender: Variant = balance.get("bot_koennen", {})
	if baender is Dictionary and (baender as Dictionary).get(klasse_id) is Array:
		var band: Array = (baender as Dictionary)[klasse_id]
		if band.size() == 2:
			return [_num(band[0], 0.3), _num(band[1], 0.5)]
	return [0.3, 0.5]


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
