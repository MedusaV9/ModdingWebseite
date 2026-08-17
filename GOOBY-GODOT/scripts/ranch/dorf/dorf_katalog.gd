class_name DorfKatalog
extends RefCounted
## Waren-Katalog des Reit-Dorfs Hufingen (RW-4) — PURE Daten-Sicht auf
## `dorf_waren.json`, über den Balance-Namespace "ranchdorf" der
## ContentRegistry Content-Pack-updatebar (Muster RanchWirtschaft).
##
## Läden: Reitladen (Sättel/Trensen/Decken — Katalog kommt aus
## RanchWirtschaft.gear_katalog, EINE Wahrheit mit RANCH-2), Futterhof
## (Heu/Hafer/Leckerli + Ankauf), Möbel-Scheune (Ranch-Deko → Bau-Lager,
## Möbel → Haus-Lager), Pferdehändlerin (rotierendes Angebot, alles kehrt
## wieder — kein FOMO), Schmiede (Hufeisen-Cosmetics + Ausbau-Aufträge).

const BALANCE_PATH := "res://scripts/ranch/dorf/dorf_waren.json"
const BALANCE_NAMESPACE := "ranchdorf"

const LADEN_IDS: Array[String] = [
	"reitladen", "futterhof", "moebelscheune", "pferdehaendlerin", "schmiede"
]


## Effektive Waren-Daten: eingebautes JSON + Registry-Override (Deep-Merge).
static func load_balance(registry: Object = null) -> Dictionary:
	var balance := read_json(BALANCE_PATH)
	var reg := registry if registry != null else _autoload_registry()
	if reg != null and reg.has_method("get_balance"):
		var overrides: Variant = reg.get_balance(BALANCE_NAMESPACE, {})
		if overrides is Dictionary and not (overrides as Dictionary).is_empty():
			_deep_merge(balance, overrides)
	return balance


## Laden-Ids in Dorf-Reihenfolge.
static func laeden(balance: Dictionary) -> Array:
	var raw: Variant = balance.get("laeden")
	if raw is Array and not (raw as Array).is_empty():
		return raw
	return LADEN_IDS.duplicate()


## Futterhof-Warenliste ([{id, preis, menge}]).
static func futter_waren(balance: Dictionary) -> Array:
	var raw: Variant = _dict(balance, "futterhof").get("waren")
	return raw if raw is Array else []


## Ankaufspreise des Futterhofs ({heu, apfel} — unter dem Kaufpreis, damit
## Kaufen→Verkaufen nie Gewinn macht).
static func futter_ankauf(balance: Dictionary) -> Dictionary:
	return _dict(_dict(balance, "futterhof"), "ankauf")


## Möbel-Scheune: Haus-Möbel ([{id, preis}] — ids aus FurnitureCatalog).
static func moebel(balance: Dictionary) -> Array:
	var raw: Variant = _dict(balance, "moebelscheune").get("moebel")
	return raw if raw is Array else []


## Möbel-Scheune: Ranch-Deko-Ids (Preise stehen im Bau-Katalog).
static func ranch_deko_ids(balance: Dictionary) -> Array:
	var raw: Variant = _dict(balance, "moebelscheune").get("ranch_deko")
	return raw if raw is Array else []


## Pferde-Pool der Händlerin (rotiert täglich, JEDES kehrt wieder).
static func pferde_pool(balance: Dictionary) -> Array:
	var raw: Variant = _dict(balance, "pferdehaendlerin").get("pool")
	return raw if raw is Array else []


## Größe des Tagesangebots der Händlerin.
static func angebot_anzahl(balance: Dictionary) -> int:
	return maxi(1, int(_num(_dict(balance, "pferdehaendlerin").get("angebot_anzahl"), 3.0)))


## Wiederverkaufs-Anteil (0..1) beim Pferdeverkauf.
static func verkauf_anteil(balance: Dictionary) -> float:
	return clampf(_num(_dict(balance, "pferdehaendlerin").get("verkauf_anteil"), 0.5), 0.0, 1.0)


## Basiswert eines Pferds ohne gemerkten Kaufpreis (Start-/Pack-Pferde).
static func basis_wert(balance: Dictionary) -> int:
	return maxi(0, int(_num(_dict(balance, "pferdehaendlerin").get("basis_wert"), 300.0)))


## Schmiede-Warenliste ([{id, preis}] — Hufeisen-Cosmetics).
static func schmiede_waren(balance: Dictionary) -> Array:
	var raw: Variant = _dict(balance, "schmiede").get("waren")
	return raw if raw is Array else []


## JSON-Datei als Dictionary lesen ({} bei Fehler).
static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("DorfKatalog: Datei fehlt: %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_error("DorfKatalog: JSON kaputt: %s" % path)
		return {}
	return parsed


static func _autoload_registry() -> Object:
	var loop := Engine.get_main_loop()
	if loop is SceneTree:
		return (loop as SceneTree).root.get_node_or_null("ContentRegistry")
	return null


static func _deep_merge(base: Dictionary, overrides: Dictionary) -> void:
	for k: Variant in overrides.keys():
		if base.get(k) is Dictionary and overrides[k] is Dictionary:
			_deep_merge(base[k], overrides[k])
		else:
			base[k] = overrides[k]


static func _dict(source: Dictionary, key: String) -> Dictionary:
	return source[key] if source.get(key) is Dictionary else {}


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
