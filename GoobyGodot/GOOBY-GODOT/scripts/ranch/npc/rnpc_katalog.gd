class_name RNpcKatalog
extends RefCounted
## Daten-Sicht auf das NPC-Ensemble des `content/ranch_quests`-Packs (RW-3)
## — PURE + static, Muster RanchKatalog/RQuestKatalog. NPCs kommen über die
## ContentRegistry-Merge-Sicht (Domain `ranch_npcs`, append-by-id); ohne
## Registry wird die eingebaute Pack-Datei direkt gelesen.
##
## NPC-Eintrag: {id, typ:"npc", modell:{art:"gooby"|"glb", ...},
## stimmePitch, dialog (res://-Pfad), routine:[{von, ort, taetigkeit}],
## geschenke:{liebt:[], mag:[]}, freischaltungen:{"1".."5":[...]}}.
## Name/Rolle kommen als I18n-Keys `rnpc.<id>.name` / `rnpc.<id>.rolle`.

const PACK_DOMAIN := "ranch_npcs"
const EINGEBAUT := "res://content/ranch_quests/data/ranch_npcs.json"

## Pflicht-Rollen des Ensembles (Testanker — die Ids müssen existieren).
const PFLICHT_IDS: Array[String] = [
	"rosi",
	"moehrchen",
	"eisenhuf",
	"selma",
	"wilma",
	"punktabzug",
	"timmi",
	"alwin",
	"luna",
	"marta",
	"eilfried",
	"knips",
]

## Tests injizieren hier eine Registry-Attrappe (null = Autoload benutzen).
static var registry_override: Object = null

static var _cache: Dictionary = {}
static var _loaded := false


## Alle NPC-Einträge in Pack-Reihenfolge (tiefe Kopien).
static func alle() -> Array:
	var out: Array = []
	for eintrag: Dictionary in _items():
		if str(eintrag.get("typ", "")) == "npc":
			out.append(eintrag.duplicate(true))
	return out


## NPC-Eintrag per id ({} = unbekannt).
static func npc(id: String) -> Dictionary:
	var eintrag: Variant = _items_by_id().get(id, {})
	return eintrag.duplicate(true) if eintrag is Dictionary else {}


## Alle NPC-Ids (Pack-Reihenfolge).
static func ids() -> Array:
	var out: Array = []
	for eintrag: Dictionary in _items():
		if str(eintrag.get("typ", "")) == "npc":
			out.append(str(eintrag["id"]))
	return out


## Konsistenzprobleme eines NPC-Eintrags (leer = gültig).
static func npc_probleme(eintrag: Dictionary) -> Array[String]:
	var probleme: Array[String] = []
	var id := str(eintrag.get("id", ""))
	if id.is_empty():
		probleme.append("NPC ohne id")
		return probleme
	var modell: Variant = eintrag.get("modell")
	if not (modell is Dictionary):
		probleme.append("%s: modell fehlt" % id)
	else:
		var art := str((modell as Dictionary).get("art", ""))
		if not ["gooby", "glb"].has(art):
			probleme.append("%s: unbekannte modell.art '%s'" % [id, art])
		if art == "glb" and not ResourceLoader.exists(str((modell as Dictionary).get("datei", ""))):
			probleme.append("%s: modell.datei fehlt" % id)
	if not FileAccess.file_exists(str(eintrag.get("dialog", ""))):
		probleme.append("%s: Dialogdatei fehlt" % id)
	var routine: Variant = eintrag.get("routine")
	if not (routine is Array) or (routine as Array).size() < 2:
		probleme.append("%s: Tagesroutine braucht >= 2 Stationen" % id)
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
	return RQuestKatalog.eingebaute_items(EINGEBAUT)
