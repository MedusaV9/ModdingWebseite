class_name CitySortiment
extends RefCounted
## Sortiment-Loader (W3a CITY): lädt Händler-Warenlisten aus JSON
## (rehwei_sortiment.json, goobytheke_sortiment.json) und liefert die
## GOOBERANDO-Gerichte (Doc E §5.1: 3 Gerichte aus dem REHWEI-Sortiment).

const REHWEI_PFAD := "res://scripts/city/data/rehwei_sortiment.json"
const GOOBYTHEKE_PFAD := "res://scripts/city/data/goobytheke_sortiment.json"


## Warenliste laden (Array of Dictionary, [] bei kaputter Datei).
static func laden(pfad: String) -> Array:
	return _liste(pfad, "waren")


## Bücher-Kategorie laden (W13B, Doc F §3.2: Geschichten-Bücher bei REHWEI —
## `inventar` = Buch-Id aus content/books, Kauf landet in inventory.items).
static func buecher(pfad: String) -> Array:
	return _liste(pfad, "buecher")


static func _liste(pfad: String, feld: String) -> Array:
	var raw := FileAccess.get_file_as_string(pfad)
	var json := JSON.new()
	if json.parse(raw) != OK or not (json.data is Dictionary):
		push_error("Sortiment kaputt: %s" % pfad)
		return []
	var liste: Variant = json.data.get(feld, [])
	return liste if liste is Array else []


static func ware(waren: Array, id: String) -> Dictionary:
	for eintrag: Dictionary in waren:
		if str(eintrag.get("id", "")) == id:
			return eintrag
	return {}


## Die GOOBERANDO-Gerichte (gooberando:true im REHWEI-Sortiment).
static func gooberando_gerichte() -> Array:
	var out: Array = []
	for eintrag: Dictionary in laden(REHWEI_PFAD):
		if bool(eintrag.get("gooberando", false)):
			out.append(eintrag)
	return out
