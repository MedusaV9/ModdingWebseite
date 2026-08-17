class_name BaumarktKatalog
extends RefCounted
## Warenkatalog des Baumarkts (Doc D §5 / Doc E §2.3, USER §D47) — PURE.
## ORTE liefert Laden + Katalog; das CRAFTING gehört der Werkstatt
## (Haus-Agent) und liest die Baupläne über `werkstatt_id`.
##
## Materialien sind stapelbar (`menge` pro Kauf), Baupläne sind `einmalig`
## (zweiter Kauf wird gesperrt statt Münzen zu verbrennen).

const KATALOG_PFAD := "res://scripts/city/data/baumarkt_katalog.json"


static func daten(pfad := KATALOG_PFAD) -> Dictionary:
	var raw := FileAccess.get_file_as_string(pfad)
	var json := JSON.new()
	if json.parse(raw) != OK or not (json.data is Dictionary):
		push_error("baumarkt_katalog.json kaputt: %s" % pfad)
		return {}
	return json.data


static func materialien(pfad := KATALOG_PFAD) -> Array:
	var raw: Variant = daten(pfad).get("materialien", [])
	return raw if raw is Array else []


static func bauplaene(pfad := KATALOG_PFAD) -> Array:
	var raw: Variant = daten(pfad).get("bauplaene", [])
	return raw if raw is Array else []


## Alle Waren (Materialien + Baupläne) in Anzeige-Reihenfolge.
static func alle(pfad := KATALOG_PFAD) -> Array:
	var out: Array = []
	out.append_array(materialien(pfad))
	out.append_array(bauplaene(pfad))
	return out


static func ware(id: String, pfad := KATALOG_PFAD) -> Dictionary:
	for eintrag: Dictionary in alle(pfad):
		if str(eintrag.get("id", "")) == id:
			return eintrag
	return {}


## Schon im Besitz? Nur `einmalig`-Waren (Baupläne) können „ausverkauft“ sein.
static func schon_gekauft(gs: Object, eintrag: Dictionary) -> bool:
	if gs == null or not bool(eintrag.get("einmalig", false)):
		return false
	var key := str(eintrag.get("inventar", eintrag.get("id", "")))
	return int(gs.get_value("inventory.items.%s" % key, 0)) > 0


static func kann_kaufen(gs: Object, eintrag: Dictionary) -> bool:
	if gs == null or eintrag.is_empty() or schon_gekauft(gs, eintrag):
		return false
	return int(gs.get_value("economy.coins", 0)) >= int(eintrag.get("preis", 0))


## Alle Werkstatt-Rezept-Ids, die der Spieler als Bauplan besitzt
## (Contract für den Haus-Agenten: `BaumarktKatalog.freigeschaltete_rezepte`).
static func freigeschaltete_rezepte(gs: Object, pfad := KATALOG_PFAD) -> Array[String]:
	var out: Array[String] = []
	if gs == null:
		return out
	for eintrag: Dictionary in bauplaene(pfad):
		if schon_gekauft(gs, eintrag):
			out.append(str(eintrag.get("werkstatt_id", "")))
	return out
