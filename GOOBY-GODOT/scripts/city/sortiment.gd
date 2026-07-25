class_name CitySortiment
extends RefCounted
## Sortiment-Loader (W3a CITY): lädt Händler-Warenlisten aus JSON
## (rehwei_sortiment.json, goobytheke_sortiment.json) und liefert die
## GOOBERANDO-Gerichte (Doc E §5.1: 3 Gerichte aus dem REHWEI-Sortiment).

const REHWEI_PFAD := "res://scripts/city/data/rehwei_sortiment.json"
const GOOBYTHEKE_PFAD := "res://scripts/city/data/goobytheke_sortiment.json"


## Warenliste laden (Array of Dictionary, [] bei kaputter Datei).
static func laden(pfad: String) -> Array:
	var raw := FileAccess.get_file_as_string(pfad)
	var json := JSON.new()
	if json.parse(raw) != OK or not (json.data is Dictionary):
		push_error("Sortiment kaputt: %s" % pfad)
		return []
	return json.data.get("waren", [])


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
