class_name I18nService
extends Node
## Strings-Loader (DE führend). Als Autoload „I18n“ gedacht (W1a registriert),
## alle Lese-APIs sind aber static — UI-Code funktioniert auch ohne Autoload.
##
## Quellen pro Locale (werden gemergt, Key-Kollision = push_error):
##   1. `res://strings/<locale>.json`      (W1c legt Struktur an, Domains s. u.)
##   2. `res://strings/<locale>/*.json`    (optionale Domain-Dateien
##      späterer Wellen — Format: flaches ODER verschachteltes Objekt)
## Nested JSON wird zu „domain.key“-Pfaden geflacht; Arrays bleiben Arrays
## (Zugriff über `items()`). Domain-Ownership: `strings/OWNERSHIP.md`.

signal locale_changed(locale: String)

const DEFAULT_LOCALE := "de"
const SUPPORTED_LOCALES: Array[String] = ["de", "en"]
const STRINGS_DIR := "res://strings"

static var _instance: I18nService
static var _locale: String = DEFAULT_LOCALE
static var _tables: Dictionary = {}
## W16/BOOTPERF: Teiltabellen einzelner Domain-Dateien ("<locale>/<domain>"),
## damit der erste Frame nicht die komplette Locale (77 Dateien) parsen muss.
static var _domain_tables: Dictionary = {}


func _ready() -> void:
	_instance = self


## Text zu einem Key, optional mit {platzhalter}-Format-Args.
## Fallback-Kette: aktive Locale → DE → Key selbst (+ push_error).
static func t(key: String, args: Dictionary = {}) -> String:
	var value: Variant = _lookup(key)
	if value == null:
		push_error("Fehlender String-Key: %s (%s)" % [key, _locale])
		return key
	var text := String(value)
	if not args.is_empty():
		text = text.format(args)
	return text


## Array-Wert (z. B. `news.items`). Fehlt der Key → leeres Array + Fehler.
static func items(key: String) -> Array:
	var value: Variant = _lookup(key)
	if value is Array:
		return value
	push_error("String-Key ist kein Array: %s (%s)" % [key, _locale])
	return []


static func has_key(key: String) -> bool:
	return _lookup(key) != null


## W16/BOOTPERF (B3/E8): Array-Wert aus GENAU EINER Domain-Datei
## (`strings/<locale>/<domain>.json`) — für den allerersten Frame des
## Boot-Covers, der nur die Sprüche aus loading.json braucht. Verhält sich
## wie items(): dieselbe Datei, dieselbe Flatten-Logik, gleiche
## DE-Fallback-Kette; ist die volle Tabelle schon im Cache oder fehlt der
## Key in der Domain-Datei, übernimmt der normale items()-Pfad (inklusive
## seiner Fehlermeldungen). Der spätere Voll-Load bleibt unverändert.
static func items_aus_domain(domain: String, key: String) -> Array:
	if _tables.has(_locale):
		return items(key)
	var locales: Array[String] = [_locale]
	if _locale != DEFAULT_LOCALE:
		locales.append(DEFAULT_LOCALE)
	for locale in locales:
		var value: Variant = _domain_table(locale, domain).get(key)
		if value is Array:
			return value
	return items(key)


static func get_locale() -> String:
	return _locale


static func set_locale(locale: String) -> void:
	if not SUPPORTED_LOCALES.has(locale):
		push_error("Nicht unterstützte Locale: %s" % locale)
		return
	if _locale == locale:
		return
	_locale = locale
	if _instance != null:
		_instance.locale_changed.emit(locale)


## Komplette (geflachte) Tabelle einer Locale — für Paritäts-Tests.
static func table(locale: String) -> Dictionary:
	if not _tables.has(locale):
		_tables[locale] = _load_locale(locale)
	return _tables[locale]


## Cache leeren (Tests / Hot-Reload nach Pack-Update).
static func reset_cache() -> void:
	_tables.clear()
	_domain_tables.clear()


static func _lookup(key: String) -> Variant:
	var tbl: Dictionary = table(_locale)
	if tbl.has(key):
		return tbl[key]
	if _locale != DEFAULT_LOCALE:
		var fallback: Dictionary = table(DEFAULT_LOCALE)
		if fallback.has(key):
			return fallback[key]
	return null


static func _domain_table(locale: String, domain: String) -> Dictionary:
	var cache_key := "%s/%s" % [locale, domain]
	if not _domain_tables.has(cache_key):
		var flat: Dictionary = {}
		_merge_file(flat, "%s/%s/%s.json" % [STRINGS_DIR, locale, domain])
		_domain_tables[cache_key] = flat
	return _domain_tables[cache_key]


static func _load_locale(locale: String) -> Dictionary:
	var flat: Dictionary = {}
	_merge_file(flat, "%s/%s.json" % [STRINGS_DIR, locale])
	var dir_path := "%s/%s" % [STRINGS_DIR, locale]
	if DirAccess.dir_exists_absolute(dir_path):
		var dir := DirAccess.open(dir_path)
		if dir != null:
			for file in dir.get_files():
				if file.ends_with(".json"):
					_merge_file(flat, "%s/%s" % [dir_path, file])
	return flat


static func _merge_file(flat: Dictionary, path: String) -> void:
	if not FileAccess.file_exists(path):
		return
	var raw := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(raw)
	if parsed == null or not (parsed is Dictionary):
		push_error("Strings-Datei kaputt/kein Objekt: %s" % path)
		return
	_flatten("", parsed, flat, path)


static func _flatten(prefix: String, node: Dictionary, out: Dictionary, source: String) -> void:
	for key: String in node:
		var full := key if prefix.is_empty() else "%s.%s" % [prefix, key]
		var value: Variant = node[key]
		if value is Dictionary:
			_flatten(full, value, out, source)
			continue
		if out.has(full):
			push_error("String-Key-Kollision: %s (aus %s)" % [full, source])
			continue
		out[full] = value
