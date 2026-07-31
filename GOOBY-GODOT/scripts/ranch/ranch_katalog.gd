class_name RanchKatalog
extends RefCounted
## Daten-Sicht auf das Gooby-Ranch-DLC-Pack (RANCH-1) — PURE + static.
##
## Die Ranch ist die Blaupause für „Content-Erweiterung per Auto-Update“
## (Doc B §4.2): ALLE Inhalte (Preis, Freischalt-Level, Tiere, Weltdaten)
## liegen als Pack unter `content/ranch/` und kommen über die
## ContentRegistry-Merge-Sicht herein:
##   - Domain `ranch` (append-by-id): Welt-Eintrag + Tiere + Ausbaustufen.
##   - Domain `balance` (deep-merge): `ranch.preis` / `ranch.freischalt_level`.
## Ein per Updater nachgeliefertes Pack mit höherer Priorität überschattet
## die eingebauten Einträge automatisch (gleiche Regel wie CONTENT-B-Möbel).
##
## Fallbacks: läuft die Registry nicht (isolierte Test-SceneTrees), gelten
## die eingebauten Defaults unten — das Spiel bleibt funktionsfähig.

const PACK_DOMAIN := "ranch"
const DEFAULT_PREIS := 2500
const DEFAULT_FREISCHALT_LEVEL := 15

## Tests injizieren hier eine Registry-Attrappe (null = Autoload benutzen).
static var registry_override: Object = null

static var _cache: Dictionary = {}
static var _loaded := false


## Kaufpreis der Ranch in ᴳ (Balance-Domain, nachlieferbar).
static func preis() -> int:
	return maxi(0, int(_balance("ranch.preis", DEFAULT_PREIS)))


## Freischalt-Level (Balance-Domain, Default 15 — User-Wunsch W13).
static func freischalt_level() -> int:
	return maxi(1, int(_balance("ranch.freischalt_level", DEFAULT_FREISCHALT_LEVEL)))


## Der Welt-Eintrag (id "welt") des Packs — Maße/Layout-Parameter.
static func welt() -> Dictionary:
	var eintrag: Variant = _items_by_id().get("welt", {})
	return eintrag.duplicate(true) if eintrag is Dictionary else {}


## Alle Tier-Einträge (typ "tier") in Pack-Reihenfolge.
static func tiere() -> Array:
	var out: Array = []
	for eintrag: Dictionary in _items():
		if str(eintrag.get("typ", "")) == "tier":
			out.append(eintrag.duplicate(true))
	return out


## Tier-Eintrag per id ({} = unbekannt).
static func tier(id: String) -> Dictionary:
	var eintrag: Variant = _items_by_id().get(id, {})
	if eintrag is Dictionary and str((eintrag as Dictionary).get("typ", "")) == "tier":
		return eintrag.duplicate(true)
	return {}


## Alle Ausbau-Einträge (typ "ausbau").
static func ausbauten() -> Array:
	var out: Array = []
	for eintrag: Dictionary in _items():
		if str(eintrag.get("typ", "")) == "ausbau":
			out.append(eintrag.duplicate(true))
	return out


## Cache leeren (Tests / nach Pack-Update per content_reloaded).
static func reset_cache() -> void:
	_cache = {}
	_loaded = false


static func _items() -> Array:
	if not _loaded:
		_cache = {"items": _pack_items(), "by_id": {}}
		for eintrag: Variant in _cache["items"]:
			if eintrag is Dictionary and (eintrag as Dictionary).has("id"):
				_cache["by_id"][str(eintrag["id"])] = eintrag
		_loaded = true
	return _cache["items"]


static func _items_by_id() -> Dictionary:
	_items()
	return _cache["by_id"]


static func _registry() -> Object:
	if registry_override != null:
		return registry_override
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("/root/ContentRegistry")
	return null


static func _pack_items() -> Array:
	var registry := _registry()
	if registry == null or not registry.has_method("get_items"):
		return []
	var raw: Variant = registry.get_items(PACK_DOMAIN)
	return raw if raw is Array else []


static func _balance(key: String, default_value: Variant) -> Variant:
	var registry := _registry()
	if registry == null or not registry.has_method("get_balance"):
		return default_value
	return registry.get_balance(key, default_value)
