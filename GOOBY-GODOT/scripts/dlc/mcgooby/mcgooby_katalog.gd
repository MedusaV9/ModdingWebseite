class_name McGoobyKatalog
extends RefCounted
## Daten-Sicht auf das McGooby-Start-Menü (DLC-MCGOOBY §3, Welle A) — PURE +
## static, Muster DlcKatalog. Quelle: `content/dlc/data/mcgooby_menu.json`
## (Rezepte mit Stationen-Schritten, Timing-Fenster pro Station, Balance).
## Läuft die ContentRegistry mit einer `mcgooby`-Domain (späteres Update-Pack),
## überschattet sie die eingebaute Datei — sonst wird direkt gelesen, damit
## Logik, Szene und isolierte Test-SceneTrees ohne Autoloads funktionieren.

const PACK_DOMAIN := "mcgooby"
const PACK_DATEI := "res://content/dlc/data/mcgooby_menu.json"

## Bekannte Stations-Ids (Reihenfolge = Anzeige-Reihenfolge, Doc §2.2).
const STATION_IDS: Array[String] = ["grill", "belegen", "fritteuse", "shake"]

## Tests injizieren hier eine Registry-Attrappe (null = Autoload benutzen).
static var registry_override: Object = null

static var _cache: Dictionary = {}
static var _loaded := false


## Kompletter Daten-Block (tiefe Kopie): {balance, timing, stationen, rezepte}.
static func daten() -> Dictionary:
	if not _loaded:
		_cache = _lade_daten()
		_loaded = true
	return _cache.duplicate(true)


## Alle Start-Rezepte in Pack-Reihenfolge.
static func rezepte() -> Array:
	var raw: Variant = daten().get("rezepte", [])
	return raw if raw is Array else []


## Rezept per id ({} = unbekannt).
static func rezept(id: String) -> Dictionary:
	for kandidat: Variant in rezepte():
		if kandidat is Dictionary and str((kandidat as Dictionary).get("id", "")) == id:
			return kandidat
	return {}


## Rezepte, deren ERSTER Schritt an der Station liegt — die Mini-Schicht
## der Welle A zieht ihre Bestellungen aus `rezepte_fuer("grill")`.
static func rezepte_fuer(station: String) -> Array:
	var out: Array = []
	for kandidat: Variant in rezepte():
		if not (kandidat is Dictionary):
			continue
		var stationen: Variant = (kandidat as Dictionary).get("stationen", [])
		if stationen is Array and (stationen as Array).has(station):
			out.append(kandidat)
	return out


## Balance-Zahlen (Doc §3.1 „Alle Zahlen leben im Pack“) mit Fail-Safe-Defaults.
static func balance() -> Dictionary:
	var raw: Variant = daten().get("balance", {})
	return raw if raw is Dictionary else {}


## Timing-Fenster einer Station: {gar_sec, fenster_sec, nachlauf_sec}.
## Rezepte dürfen das Fenster per `fenster_mult` verengen (Möhren-Pommes!).
static func timing(station: String, rezept_def: Dictionary = {}) -> Dictionary:
	var alle: Variant = daten().get("timing", {})
	var roh: Variant = (alle as Dictionary).get(station, {}) if alle is Dictionary else {}
	var zeile: Dictionary = roh if roh is Dictionary else {}
	var mult := clampf(float(rezept_def.get("fenster_mult", 1.0)), 0.25, 2.0)
	return {
		"gar_sec": maxf(0.0, float(zeile.get("gar_sec", 4.0))),
		"fenster_sec": maxf(0.1, float(zeile.get("fenster_sec", 1.4)) * mult),
		"nachlauf_sec": maxf(0.1, float(zeile.get("nachlauf_sec", 2.0))),
	}


## Lokalisierter Feldzugriff (`name`/`geste` → `<feld>_<locale>`, DE-Fallback).
static func text_von(eintrag: Dictionary, feld: String) -> String:
	var locale := "de"
	if Engine.get_main_loop() is SceneTree:
		locale = I18nService.get_locale()
	var wert: Variant = eintrag.get("%s_%s" % [feld, locale])
	if wert is String and not (wert as String).is_empty():
		return wert
	return str(eintrag.get("%s_de" % feld, ""))


## Schema-Check eines Rezepts (Tests + Fail-fast beim Laden künftiger Packs).
static func ist_gueltig(rezept_def: Dictionary) -> bool:
	if str(rezept_def.get("id", "")).is_empty():
		return false
	for feld: String in ["name_de", "name_en"]:
		if str(rezept_def.get(feld, "")).is_empty():
			return false
	var stationen: Variant = rezept_def.get("stationen", [])
	if not (stationen is Array) or (stationen as Array).is_empty():
		return false
	for station: Variant in stationen:
		if not STATION_IDS.has(str(station)):
			return false
	var schritte: Variant = rezept_def.get("schritte", [])
	if not (schritte is Array) or (schritte as Array).is_empty():
		return false
	for schritt: Variant in schritte:
		if not (schritt is Dictionary):
			return false
		if not STATION_IDS.has(str((schritt as Dictionary).get("station", ""))):
			return false
	return true


## Cache leeren (Tests / nach Pack-Update per content_reloaded).
static func reset_cache() -> void:
	_cache = {}
	_loaded = false


static func _lade_daten() -> Dictionary:
	var registry := _registry()
	if registry != null and registry.has_method("get_items"):
		var raw: Variant = registry.get_items(PACK_DOMAIN)
		# Domain-Konvention: genau EIN Item = der komplette Daten-Block.
		if raw is Array and not (raw as Array).is_empty() and (raw as Array)[0] is Dictionary:
			return (raw as Array)[0]
	return _lade_pack_datei()


static func _lade_pack_datei() -> Dictionary:
	if not FileAccess.file_exists(PACK_DATEI):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PACK_DATEI))
	if not (parsed is Dictionary):
		push_warning("McGooby-Menü-Datei kaputt: %s" % PACK_DATEI)
		return {}
	return parsed


static func _registry() -> Object:
	if registry_override != null:
		return registry_override
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("/root/ContentRegistry")
	return null
