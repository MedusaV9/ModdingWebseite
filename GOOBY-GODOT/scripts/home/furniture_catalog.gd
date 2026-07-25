class_name FurnitureCatalog
extends RefCounted
## Möbel-Katalog (W2a HOUSE) — lädt `data/furniture_catalog.json` und liefert
## NORMALISIERTE Defs (Doc D §1.3: Möbel = reine Daten + GLB). Statische API,
## headless-testbar; Pack-Merge (user://packs) ist M2-Backlog und ändert die
## Signaturen nicht.
##
## Normalisierte Def-Keys (Konsumenten-Vertrag):
##   id: String, name_de/name_en: String, glb: String (relativ zu ASSETS_DIR),
##   footprint: Vector2i, layer: int (GridData.Layer), preis: int,
##   lagerwert: int (1–4), pflicht: String (""|"bett"|"couch"|"kuehlschrank"),
##   kategorie: String, surface: bool, blocks_movement: bool,
##   can_toggle_light: bool, wall_size: int (nur WALL), fill: float (Auto-Fit),
##   verkaufswert: int (Goobay-Basiswert, 0 = aus dem Preis ableiten),
##   exterior: bool + vista: String (Fenster brauchen eine Außenwand und
##   zeigen deren Diorama — Doc D §1.2), proc: String (prozedurales Mesh
##   statt GLB, z. B. "fenster" — HomeProcMeshes).

const CATALOG_PATH := "res://scripts/home/data/furniture_catalog.json"
const ASSETS_DIR := "res://assets/furniture"
const MANDATORY_SLOTS: Array[String] = ["bett", "couch", "kuehlschrank"]

## Standard-Füllgrad beim Auto-Fit (Möbel berühren sich nicht ganz).
const DEFAULT_FILL := 0.94

const LAYER_NAMES := {
	"RUG": GridData.Layer.RUG,
	"FLOOR": GridData.Layer.FLOOR,
	"SURFACE": GridData.Layer.SURFACE,
	"WALL": GridData.Layer.WALL,
}

static var _defs: Dictionary = {}
static var _loaded := false


## id -> normalisierte Def. Lädt beim ersten Zugriff (gecacht).
static func defs() -> Dictionary:
	if not _loaded:
		_defs = _load_catalog()
		_loaded = true
	return _defs


## Def zu einer id ({} wenn unbekannt — Aufrufer degradiert weich).
static func def(item_id: String) -> Dictionary:
	return defs().get(item_id, {})


static func ids() -> Array:
	var out := defs().keys()
	out.sort()
	return out


static func by_category(kategorie: String) -> Array:
	var out: Array = []
	for id: String in ids():
		if defs()[id]["kategorie"] == kategorie:
			out.append(defs()[id])
	return out


## Absoluter res://-Pfad zum GLB einer Def.
static func glb_path(item_def: Dictionary) -> String:
	return "%s/%s" % [ASSETS_DIR, item_def.get("glb", "")]


static func display_name(item_def: Dictionary, locale := "de") -> String:
	if locale == "en":
		return item_def.get("name_en", item_def.get("name_de", "?"))
	return item_def.get("name_de", "?")


## Zählt platzierte Items pro Pflicht-Slot (Doc D §2.4) über ein
## Save-Items-Array (`[{"item": id, ...}]`).
static func mandatory_counts(items: Array) -> Dictionary:
	var counts := {}
	for slot in MANDATORY_SLOTS:
		counts[slot] = 0
	for entry: Variant in items:
		if not (entry is Dictionary):
			continue
		var item_def := def(str(entry.get("item", "")))
		var slot: String = item_def.get("pflicht", "")
		if slot != "":
			counts[slot] = int(counts.get(slot, 0)) + 1
	return counts


## Doc D §2.4: Das LETZTE platzierte Item eines Pflicht-Slots darf weder
## eingelagert noch verkauft werden.
static func is_last_of_mandatory_slot(items: Array, uid: String) -> bool:
	var target := {}
	for entry: Variant in items:
		if entry is Dictionary and str(entry.get("uid", "")) == uid:
			target = def(str(entry.get("item", "")))
			break
	var slot: String = target.get("pflicht", "")
	if slot == "":
		return false
	return int(mandatory_counts(items).get(slot, 0)) <= 1


## Cache leeren (Tests / Pack-Hot-Reload).
static func reset_cache() -> void:
	_defs = {}
	_loaded = false


static func _load_catalog() -> Dictionary:
	var out: Dictionary = {}
	if not FileAccess.file_exists(CATALOG_PATH):
		push_error("Möbel-Katalog fehlt: %s" % CATALOG_PATH)
		return out
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(CATALOG_PATH)) != OK:
		push_error("Möbel-Katalog kaputt: %s (%s)" % [CATALOG_PATH, json.get_error_message()])
		return out
	var raw: Variant = json.data
	if not (raw is Dictionary) or not (raw.get("items") is Array):
		push_error("Möbel-Katalog: unerwartete Struktur")
		return out
	for entry: Variant in raw["items"]:
		if not (entry is Dictionary):
			continue
		var normalized := _normalize_def(entry)
		if normalized.is_empty():
			continue
		out[normalized["id"]] = normalized
	return out


static func _normalize_def(raw: Dictionary) -> Dictionary:
	var id := str(raw.get("id", ""))
	var layer_name := str(raw.get("layer", ""))
	if id == "" or not LAYER_NAMES.has(layer_name):
		push_error("Katalog-Item ungültig: %s" % str(raw))
		return {}
	var fp_raw: Array = raw.get("footprint", [1, 1])
	var layer: int = LAYER_NAMES[layer_name]
	var footprint := Vector2i(maxi(1, int(fp_raw[0])), maxi(1, int(fp_raw[1])))
	var blocks_default := layer == GridData.Layer.FLOOR
	return {
		"id": id,
		"name_de": str(raw.get("name_de", id)),
		"name_en": str(raw.get("name_en", raw.get("name_de", id))),
		"glb": str(raw.get("glb", "")),
		"footprint": footprint,
		"layer": layer,
		"preis": maxi(0, int(raw.get("preis", 0))),
		"lagerwert": clampi(int(raw.get("lagerwert", 1)), 1, 4),
		"pflicht": str(raw.get("pflicht", "")),
		"kategorie": str(raw.get("kategorie", "deko")),
		"surface": bool(raw.get("surface", false)),
		"blocks_movement": bool(raw.get("blocks_movement", blocks_default)),
		"can_toggle_light": bool(raw.get("can_toggle_light", false)),
		"wall_size": maxi(1, int(raw.get("wall_size", footprint.x))),
		"fill": clampf(float(raw.get("fill", DEFAULT_FILL)), 0.5, 1.0),
		"verkaufswert": maxi(0, int(raw.get("verkaufswert", 0))),
		"exterior": bool(raw.get("exterior", false)),
		"vista": str(raw.get("vista", "")),
		"proc": str(raw.get("proc", "")),
	}
