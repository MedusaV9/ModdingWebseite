class_name RQuestKatalog
extends RefCounted
## Daten-Sicht auf die Quest-Domain des `content/ranch_quests`-Packs (RW-3)
## — PURE + static, Muster RanchKatalog. Quests kommen über die
## ContentRegistry-Merge-Sicht (Domain `ranch_quests`, append-by-id): ein
## per Updater nachgeliefertes Pack mit höherer Priorität überschattet
## einzelne Quests, neue kommen additiv dazu.
##
## Fallback: läuft die Registry nicht (isolierte Test-SceneTrees, Probes),
## wird die eingebaute Pack-Datei direkt gelesen — das Spiel bleibt
## funktionsfähig, die Merge-Semantik greift dann eben nicht.

const PACK_DOMAIN := "ranch_quests"
const EINGEBAUT := "res://content/ranch_quests/data/ranch_quests.json"

const TYP_HAUPT := "haupt"
const TYP_NEBEN := "neben"
const TYP_TAEGLICH := "taeglich"
## Alle bekannten Ziel-Typen der Engine (RQuestEngine wertet sie aus).
const ZIEL_TYPEN: Array[String] = [
	"gehe_zu",
	"sprich_mit",
	"sammle",
	"pflege",
	"reite_strecke",
	"gewinne_wettbewerb",
	"warte_bis",
]
## Wie viele Tagesaufgaben gleichzeitig angeboten werden.
const TAGES_SLOTS := 3

## Tests injizieren hier eine Registry-Attrappe (null = Autoload benutzen).
static var registry_override: Object = null

static var _cache: Dictionary = {}
static var _loaded := false


## Alle Quest-Einträge in Pack-Reihenfolge (tiefe Kopien).
static func alle() -> Array:
	var out: Array = []
	for eintrag: Dictionary in _items():
		out.append(eintrag.duplicate(true))
	return out


## Quest-Eintrag per id ({} = unbekannt).
static func quest(id: String) -> Dictionary:
	var eintrag: Variant = _items_by_id().get(id, {})
	return eintrag.duplicate(true) if eintrag is Dictionary else {}


## Haupt-Questreihe, nach Kapitel sortiert.
static func hauptreihe() -> Array:
	var out: Array = []
	for eintrag: Dictionary in _items():
		if str(eintrag.get("typ", "")) == TYP_HAUPT:
			out.append(eintrag.duplicate(true))
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("kapitel", 0)) < int(b.get("kapitel", 0))
	)
	return out


## Alle Nebenquests (Pack-Reihenfolge).
static func nebenquests() -> Array:
	var out: Array = []
	for eintrag: Dictionary in _items():
		if str(eintrag.get("typ", "")) == TYP_NEBEN:
			out.append(eintrag.duplicate(true))
	return out


## Der Tagesaufgaben-Pool (Pack-Reihenfolge).
static func tagespool() -> Array:
	var out: Array = []
	for eintrag: Dictionary in _items():
		if str(eintrag.get("typ", "")) == TYP_TAEGLICH:
			out.append(eintrag.duplicate(true))
	return out


## Die TAGES_SLOTS Tagesaufgaben eines Kalendertags — deterministisch aus
## dem Datum geseedet (kein Streak, kein Verfall: wer wegbleibt, verpasst
## nichts, C5-Designregel).
static func tagesaufgaben(datum: String) -> Array:
	var pool := tagespool()
	if pool.size() <= TAGES_SLOTS:
		return pool
	var rng := RandomNumberGenerator.new()
	rng.seed = datum.hash()
	var indizes: Array = range(pool.size())
	var out: Array = []
	for _i in TAGES_SLOTS:
		out.append(pool[indizes.pop_at(rng.randi_range(0, indizes.size() - 1))])
	return out


## Konsistenzprobleme eines Quest-Eintrags (leer = gültig) — für Tests
## und den Pack-Merge-Check.
static func quest_probleme(eintrag: Dictionary) -> Array[String]:
	var probleme: Array[String] = []
	var id := str(eintrag.get("id", ""))
	if id.is_empty():
		probleme.append("Quest ohne id")
		return probleme
	if not [TYP_HAUPT, TYP_NEBEN, TYP_TAEGLICH].has(str(eintrag.get("typ", ""))):
		probleme.append("%s: unbekannter typ" % id)
	if str(eintrag.get("geber", "")).is_empty():
		probleme.append("%s: geber fehlt" % id)
	var ziele: Variant = eintrag.get("ziele")
	if not (ziele is Array) or (ziele as Array).is_empty():
		probleme.append("%s: ziele fehlen" % id)
		return probleme
	for ziel: Variant in ziele:
		if not (ziel is Dictionary):
			probleme.append("%s: Ziel ist kein Dictionary" % id)
			continue
		var typ := str((ziel as Dictionary).get("typ", ""))
		if not ZIEL_TYPEN.has(typ):
			probleme.append("%s: unbekannter Ziel-Typ '%s'" % [id, typ])
		if typ == "warte_bis" and int((ziel as Dictionary).get("dauerMin", 0)) <= 0:
			probleme.append("%s: warte_bis ohne dauerMin" % id)
	return probleme


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
	if registry != null and registry.has_method("get_items"):
		var raw: Variant = registry.get_items(PACK_DOMAIN)
		if raw is Array and not (raw as Array).is_empty():
			return raw
	return eingebaute_items(EINGEBAUT)


## Eingebaute Pack-Datei direkt lesen (Registry-Fallback; auch der
## Schwester-Katalog RNpcKatalog nutzt diesen Helfer).
static func eingebaute_items(pfad: String) -> Array:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(pfad))
	if parsed is Dictionary and (parsed as Dictionary).get("items") is Array:
		return (parsed as Dictionary)["items"]
	push_warning("RW-3-Pack-Datei fehlt/kaputt: %s" % pfad)
	return []
