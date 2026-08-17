class_name CraftMaterials
extends RefCounted
## Material-Katalog (Doc D §5.1) — Stöcke/Blätter aus dem Garten, Holz vom
## eigenen Baum, Eisen/Nägel aus dem Baumarkt. Reine Daten (Content-Pack-fähig
## über HomePackData), statisch + headless-testbar.
##
## Normalisierte Def-Keys: id, name_de, name_en, quelle
## ("garten-spawn"|"baum-ernte"|"baumarkt"), preis (0 = nicht käuflich),
## icon (Id für HomeIcons).
##
## Der Baumarkt-Ort gehört dem ORTE-Agenten — DIESE Datei ist der
## Datenvertrag: `baumarkt_angebot()` liefert Ids + Preise, gekauft wird über
## `CraftState.add_material()` / `add_blueprint()`.
## Handoff: /tmp/gooby-godot/handoffs/HAUS-baumarkt-api.md

const FILE_NAME := "materials.json"
const BASE_PATH := "res://scripts/home/data/materials.json"
const QUELLEN: Array[String] = ["garten-spawn", "baum-ernte", "baumarkt"]

static var _defs: Dictionary = {}
static var _baumarkt: Array = []
static var _loaded := false


static func defs() -> Dictionary:
	_ensure_loaded()
	return _defs


static func def(material_id: String) -> Dictionary:
	return defs().get(material_id, {})


static func ids() -> Array:
	var out := defs().keys()
	out.sort()
	return out


static func display_name(material_id: String, locale := "de") -> String:
	var row := def(material_id)
	if row.is_empty():
		return material_id
	return str(row.get("name_en", row["name_de"]) if locale == "en" else row["name_de"])


## Herkunfts-Hinweis fürs Crafting-UI („im Garten finden!“).
static func quelle_key(material_id: String) -> String:
	return "craft.quelle.%s" % str(def(material_id).get("quelle", "garten-spawn"))


## Datenvertrag für den Baumarkt (ORTE): [{art, id, preis}] mit
## art ∈ {material, bauplan, struktur}.
static func baumarkt_angebot() -> Array:
	_ensure_loaded()
	return _baumarkt.duplicate(true)


## Preis eines Baumarkt-Eintrags (0 = nicht im Sortiment).
static func baumarkt_preis(art: String, entry_id: String) -> int:
	for row: Dictionary in baumarkt_angebot():
		if row.get("art", "") == art and row.get("id", "") == entry_id:
			return int(row.get("preis", 0))
	return 0


static func reset_cache() -> void:
	_defs = {}
	_baumarkt = []
	_loaded = false


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_loaded = true
	var docs := HomePackData.documents(BASE_PATH, FILE_NAME)
	_defs = HomePackData.merge_by_id(docs, "materials", _normalize)
	_baumarkt = []
	for doc: Dictionary in docs:
		var rows: Variant = doc.get("baumarkt")
		if rows is Array:
			_baumarkt = rows.duplicate(true)


static func _normalize(raw: Dictionary) -> Dictionary:
	var id := str(raw.get("id", ""))
	if id == "":
		push_error("Material ohne id: %s" % str(raw))
		return {}
	var quelle := str(raw.get("quelle", "garten-spawn"))
	if not QUELLEN.has(quelle):
		quelle = "garten-spawn"
	return {
		"id": id,
		"name_de": str(raw.get("name_de", id)),
		"name_en": str(raw.get("name_en", raw.get("name_de", id))),
		"quelle": quelle,
		"preis": maxi(0, int(raw.get("preis", 0))),
		"icon": str(raw.get("icon", id)),
	}
