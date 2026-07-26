class_name CutsceneLib
extends RefCounted
## Cutscene-Bibliothek (FIX-4) — lädt die datengetriebenen Cutscene-Skripte
## aus scripts/cutscenes/data/*.json und validiert sie (Port der Web-Idee
## src/data/cutscenes.js + systems/cutscene.js compileScript).
##
## Skript-Format:
##   {"id": "...", "music": {...optionaler erster music-op...},
##    "steps": [{"op": "...", ...felder, "keep_on_skip": bool?}]}
## Ops: fade(to,duration) · letterbox(on) · caption(key) · caption_clear ·
##   wait(duration) · camera(move[,pos,look,fov,duration]) · clip(clip) ·
##   emotion(emotion) · walk(to[,timeout]) · place_gooby(at[,face_deg]) ·
##   prop(action,id[,glb,at,rot_deg,scale,to,duration]) · sfx(id[,pitch]) ·
##   music(context|track|stop[,fade]) · stinger(track) · parallel(steps)
## Positionen: [x,z]/[x,y,z] in Weltmetern ODER {"anchor": "center"|"entry"|
##   "gooby", "offset": [dx,dy,dz]} — der Player löst Anker pro Raum auf.
## Abspielen: CutscenePlayer.play_in_room(room, gs, id).

const DATA_DIR := "res://scripts/cutscenes/data"

## Diese Cutscenes MÜSSEN existieren (Test-Kontrakt; User-Meldung 3).
const REQUIRED_IDS: Array[String] = [
	"wake_morning",
	"sleep_night",
	"travel_departure",
	"vacation_arrival",
	"shop_trip",
]

## op → Pflichtfelder.
const KNOWN_OPS := {
	"fade": ["to", "duration"],
	"letterbox": ["on"],
	"caption": ["key"],
	"caption_clear": [],
	"wait": ["duration"],
	"camera": ["move"],
	"clip": ["clip"],
	"emotion": ["emotion"],
	"walk": ["to"],
	"place_gooby": ["at"],
	"prop": ["action", "id"],
	"sfx": ["id"],
	"music": [],
	"stinger": ["track"],
	"parallel": ["steps"],
}

const CAMERA_MOVES: Array[String] = ["fly", "push_in", "restore"]
const PROP_ACTIONS: Array[String] = ["spawn", "glide", "despawn"]

static var _cache: Dictionary = {}


## Alle Cutscene-Definitionen (id → Dictionary), gecacht.
static func all() -> Dictionary:
	if not _cache.is_empty():
		return _cache
	var found: Dictionary = {}
	var dir := DirAccess.open(DATA_DIR)
	if dir == null:
		push_warning("[cutscene] Datenordner fehlt: %s" % DATA_DIR)
		return found
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.ends_with(".json"):
			var def := _load_json("%s/%s" % [DATA_DIR, entry])
			if not def.is_empty():
				found[str(def.get("id", entry.get_basename()))] = def
		entry = dir.get_next()
	dir.list_dir_end()
	_cache = found
	return found


static func get_cutscene(id: String) -> Dictionary:
	return all().get(id, {})


static func ids() -> Array:
	var out: Array = all().keys()
	out.sort()
	return out


## Cache leeren (Tests / Hot-Reload).
static func reset_cache() -> void:
	_cache = {}


## Skript validieren → Fehlerliste ([] = ok). Prüft Ops, Pflichtfelder,
## Kamera-Moves, Prop-Aktionen und rekursiv parallel-Blöcke.
static func validate(def: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if str(def.get("id", "")).is_empty():
		errors.append("id fehlt")
	var steps: Variant = def.get("steps")
	if not (steps is Array) or (steps as Array).is_empty():
		errors.append("steps fehlt/leer")
		return errors
	_validate_steps(steps, str(def.get("id", "?")), errors)
	return errors


static func _validate_steps(steps: Array, ctx: String, errors: PackedStringArray) -> void:
	for i in steps.size():
		var step: Variant = steps[i]
		if not (step is Dictionary):
			errors.append("%s[%d]: Step ist kein Objekt" % [ctx, i])
			continue
		var op := str(step.get("op", ""))
		if not KNOWN_OPS.has(op):
			errors.append("%s[%d]: unbekannter op '%s'" % [ctx, i, op])
			continue
		for field: String in KNOWN_OPS[op]:
			if not step.has(field):
				errors.append("%s[%d]: op '%s' braucht Feld '%s'" % [ctx, i, op, field])
		if op == "camera" and not CAMERA_MOVES.has(str(step.get("move", ""))):
			errors.append("%s[%d]: camera.move '%s' unbekannt" % [ctx, i, step.get("move")])
		if op == "prop" and not PROP_ACTIONS.has(str(step.get("action", ""))):
			errors.append("%s[%d]: prop.action '%s' unbekannt" % [ctx, i, step.get("action")])
		if op == "music" and not (step.has("context") or step.has("track") or step.has("stop")):
			errors.append("%s[%d]: music braucht context|track|stop" % [ctx, i])
		if op == "parallel" and step.get("steps") is Array:
			_validate_steps(step["steps"], "%s[%d].parallel" % [ctx, i], errors)


## Alle caption-Keys eines Skripts (rekursiv) — für String-Tests.
static func caption_keys(def: Dictionary) -> PackedStringArray:
	var keys := PackedStringArray()
	_collect_captions(def.get("steps", []), keys)
	return keys


static func _collect_captions(steps: Variant, keys: PackedStringArray) -> void:
	if not (steps is Array):
		return
	for step: Variant in steps:
		if not (step is Dictionary):
			continue
		if str(step.get("op", "")) == "caption":
			keys.append(str(step.get("key", "")))
		_collect_captions(step.get("steps"), keys)


static func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK or not (json.data is Dictionary):
		push_warning("[cutscene] %s ist kein gültiges JSON-Objekt." % path)
		return {}
	return json.data
