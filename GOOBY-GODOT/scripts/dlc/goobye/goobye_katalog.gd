class_name GoobyeKatalog
extends RefCounted
## Daten-Sicht auf das „Goo und Bye“-Sortiment-Pack (G5/P24 DLC-GOOBYE-A) —
## PURE + static, Muster RanchKatalog/DlcKatalog. Quellen:
##   - Domain `goobye_sortiment` (append-by-id, content/dlc/data/): Warengruppen
##     (typ "gruppe", Form + Farbe kodiert — §2.5, nie nur Farbe) und Waren
##     (typ "ware", vk = Richtwert-Verkaufspreis, IDs = rehwei_sortiment §4.1).
##   - Domain `balance` (deep-merge): `gooundbye.preis`/`freischalt_level`/
##     Margen-Stellschrauben (§2.2) — per Pack-Update live nachsteuerbar.
## Läuft die Registry nicht (isolierte Test-SceneTrees), wird die eingebaute
## Pack-Datei direkt gelesen — Laden und Tests bleiben funktionsfähig.

const PACK_DOMAIN := "goobye_sortiment"
const PACK_DATEI := "res://content/dlc/data/goobye_sortiment.json"

## Balance-Defaults (Doc §7.2/§2.2) — greifen ohne Registry.
const DEFAULT_PREIS := 2500
const DEFAULT_FREISCHALT_LEVEL := 12
const DEFAULT_EK_FAKTOR := 0.6
const DEFAULT_PREIS_SPANNE := 0.3
const DEFAULT_EIGENMARKE_RABATT := 0.2
const DEFAULT_BIO_AUFSCHLAG := 0.1

## Tests injizieren hier eine Registry-Attrappe (null = Autoload benutzen).
static var registry_override: Object = null

static var _cache: Dictionary = {}
static var _loaded := false


## Kaufpreis des DLC in ᴳ (Balance-Domain, nachlieferbar).
static func preis() -> int:
	return maxi(0, int(_balance("gooundbye.preis", DEFAULT_PREIS)))


## Freischalt-Level (Balance-Domain, Default 12 — Doc §7.2).
static func freischalt_level() -> int:
	return maxi(1, int(_balance("gooundbye.freischalt_level", DEFAULT_FREISCHALT_LEVEL)))


## Großmarkt-Einkauf = dieser Anteil des empfohlenen Verkaufspreises (§2.2).
static func ek_faktor() -> float:
	return clampf(float(_balance("gooundbye.ek_faktor", DEFAULT_EK_FAKTOR)), 0.05, 1.0)


## Preis-Schieber-Spanne ±x um den Richtwert (§2.2, Default ±30 %).
static func preis_spanne() -> float:
	return clampf(float(_balance("gooundbye.preis_spanne", DEFAULT_PREIS_SPANNE)), 0.0, 0.9)


## Eigenmarken-Rabatt auf den Richtwert (§4.1, Default −20 %).
static func eigenmarke_rabatt() -> float:
	return clampf(
		float(_balance("gooundbye.eigenmarke_rabatt", DEFAULT_EIGENMARKE_RABATT)), 0.0, 0.9
	)


## Bio-Aufschlag fürs Gooby-Beet-Regal (§2.2, Default +10 % — Welle B nutzt ihn).
static func bio_aufschlag() -> float:
	return clampf(float(_balance("gooundbye.bio_aufschlag", DEFAULT_BIO_AUFSCHLAG)), 0.0, 0.9)


## Alle Warengruppen (typ "gruppe") in Pack-Reihenfolge (tiefe Kopien).
static func gruppen() -> Array:
	return _vom_typ("gruppe")


## Gruppe per id ({} = unbekannt).
static func gruppe(id: String) -> Dictionary:
	var eintrag: Variant = _items_by_id().get(id, {})
	if eintrag is Dictionary and str((eintrag as Dictionary).get("typ", "")) == "gruppe":
		return (eintrag as Dictionary).duplicate(true)
	return {}


## Alle Waren (typ "ware") in Pack-Reihenfolge (tiefe Kopien).
static func waren() -> Array:
	return _vom_typ("ware")


## Ware per id ({} = unbekannt).
static func ware(id: String) -> Dictionary:
	var eintrag: Variant = _items_by_id().get(id, {})
	if eintrag is Dictionary and str((eintrag as Dictionary).get("typ", "")) == "ware":
		return (eintrag as Dictionary).duplicate(true)
	return {}


## Waren einer Gruppe in Pack-Reihenfolge.
static func waren_der_gruppe(gruppe_id: String) -> Array:
	var out: Array = []
	for eintrag: Dictionary in waren():
		if str(eintrag.get("gruppe", "")) == gruppe_id:
			out.append(eintrag)
	return out


## Startlager des Eröffnungspakets (§2.2 Warengutschein): ware_id → Stückzahl
## aus den `start`-Feldern des Packs.
static func startlager() -> Dictionary:
	var out: Dictionary = {}
	for eintrag: Dictionary in waren():
		var menge := int(eintrag.get("start", 0))
		if menge > 0:
			out[str(eintrag["id"])] = menge
	return out


## Gebrabbel-Tonhöhe der Kassen-Melodie für eine Ware (§1.2) — kommt von
## ihrer Warengruppe, Fallback 1.0.
static func ton_fuer(ware_id: String) -> float:
	var w := ware(ware_id)
	if w.is_empty():
		return 1.0
	var g := gruppe(str(w.get("gruppe", "")))
	return clampf(float(g.get("ton", 1.0)), 0.9, 1.6)


## Cache leeren (Tests / nach Pack-Update per content_reloaded).
static func reset_cache() -> void:
	_cache = {}
	_loaded = false


static func _vom_typ(typ: String) -> Array:
	var out: Array = []
	for eintrag: Variant in _items():
		if eintrag is Dictionary and str((eintrag as Dictionary).get("typ", "")) == typ:
			out.append((eintrag as Dictionary).duplicate(true))
	return out


static func _items() -> Array:
	if not _loaded:
		_cache = {"items": _lade_items(), "by_id": {}}
		for eintrag: Variant in _cache["items"]:
			if eintrag is Dictionary and (eintrag as Dictionary).has("id"):
				_cache["by_id"][str(eintrag["id"])] = eintrag
		_loaded = true
	return _cache["items"]


static func _items_by_id() -> Dictionary:
	_items()
	return _cache["by_id"]


static func _lade_items() -> Array:
	var registry := _registry()
	if registry != null and registry.has_method("get_items"):
		var raw: Variant = registry.get_items(PACK_DOMAIN)
		if raw is Array and not (raw as Array).is_empty():
			return raw
	return _lade_pack_datei()


## Fallback ohne Registry: die eingebaute Pack-Datei direkt lesen.
static func _lade_pack_datei() -> Array:
	if not FileAccess.file_exists(PACK_DATEI):
		return []
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PACK_DATEI))
	if not (parsed is Dictionary):
		push_warning("Goo-und-Bye-Pack-Datei kaputt: %s" % PACK_DATEI)
		return []
	var items: Variant = (parsed as Dictionary).get("items", [])
	return items if items is Array else []


static func _registry() -> Object:
	if registry_override != null:
		return registry_override
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("/root/ContentRegistry")
	return null


static func _balance(key: String, default_value: Variant) -> Variant:
	var registry := _registry()
	if registry == null or not registry.has_method("get_balance"):
		return default_value
	return registry.get_balance(key, default_value)
