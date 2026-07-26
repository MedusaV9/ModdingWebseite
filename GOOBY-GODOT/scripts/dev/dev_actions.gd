class_name DevActions
extends RefCounted
## RW-7 — Dev-Menü-Aktionen (Doc §5.2/§5.3) als pure/duck-typed Helfer.
## ALLE mutierenden Aktionen laufen über die normalen GameState-APIs
## (set_value/update/notify_slice_changed), markieren den Spielstand über
## den additiven „dev“-Slice (dev.touched) und legen VORHER einen
## atomischen Snapshot ab — nichts kann den Spielstand zerstören.
##
## Der „dev“-Slice wird über die FROZEN Slice-API registriert (additiv,
## survivet SaveSchema.normalize) — Registrierung passiert LAZY beim ersten
## Aktivieren, damit normale Läufe die Registry nicht verändern.

const SLICE_ID := "dev"
const SNAPSHOT_DIR := "user://dev/snapshots"
const EXPORT_DIR := "user://dev/exports"
const SNAPSHOT_KEEP := 10
const GOLD_MAX := 9_999_999
const MAX_ACTIONS_LOG := 50
## Schlüssel, die im Netzwerk-Log IMMER redigiert werden (Doc §5.2/§5.3:
## schon beim Erfassen entfernen, nicht erst in der UI).
const REDACT_KEYS: Array[String] = [
	"token", "secret", "devicesecret", "auth", "session", "sessionid", "password", "text"
]


static func default_slice() -> Dictionary:
	return {"touched": false, "touchedAt": 0, "actions": []}


static func normalize_slice(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		return default_slice()
	var dict: Dictionary = raw
	var actions: Array = dict.get("actions", []) if dict.get("actions") is Array else []
	return {
		"touched": bool(dict.get("touched", false)),
		"touchedAt": int(dict.get("touchedAt", 0)),
		"actions": actions.slice(maxi(0, actions.size() - MAX_ACTIONS_LOG)),
	}


## Slice-Registrierung (idempotent; via FROZEN GameState.register_slice).
static func ensure_slice(gs: Object) -> void:
	if gs != null and gs.has_method("register_slice"):
		gs.register_slice(SLICE_ID, default_slice, normalize_slice)


## Spielstand als manipuliert markieren + Aktion protokollieren.
static func mark_touched(gs: Object, action: String, now_ms: int) -> void:
	ensure_slice(gs)
	gs.update(
		func(state: Dictionary) -> void:
			if not (state.get(SLICE_ID) is Dictionary):
				state[SLICE_ID] = default_slice()
			var dev: Dictionary = state[SLICE_ID]
			dev["touched"] = true
			if int(dev.get("touchedAt", 0)) == 0:
				dev["touchedAt"] = now_ms
			var actions: Array = dev.get("actions", [])
			actions.append({"a": action, "at": now_ms})
			dev["actions"] = actions.slice(maxi(0, actions.size() - MAX_ACTIONS_LOG))
	)


static func is_touched(gs: Object) -> bool:
	return gs != null and bool(gs.get_value(SLICE_ID + ".touched", false))


## Atomischer Snapshot VOR riskanten Aktionen (Doc §5.3: Schema-Version +
## SHA-256). Behält die letzten SNAPSHOT_KEEP Dateien. Gibt den Pfad zurück
## ("" = Fehler).
static func snapshot(gs: Object, label: String, now_ms: int) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SNAPSHOT_DIR))
	# Kanonisierung ueber einen JSON-Roundtrip: parse_string liest Zahlen als
	# float — der gespeicherte Hash muss zum GESPEICHERTEN state passen, sonst
	# schlaegt jede spaetere Integritaetspruefung nach dem Einlesen fehl.
	var canonical: Variant = JSON.parse_string(JSON.stringify(gs.state()))
	var digest := hash_of(JSON.stringify(canonical))
	var file_name := "snap_%d_%s.json" % [now_ms, label]
	var path := "%s/%s" % [SNAPSHOT_DIR, file_name]
	var payload := {
		"v": int(gs.get_value("v", 5)),
		"sha256": digest,
		"label": label,
		"at": now_ms,
		"state": canonical,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(payload))
	file.close()
	_prune_snapshots()
	return path


static func hash_of(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode()


## Gold setzen (Clamp 0..GOLD_MAX) — Snapshot + Markierung inklusive.
static func set_gold(gs: Object, value: int, now_ms: int) -> int:
	var clamped := clampi(value, 0, GOLD_MAX)
	snapshot(gs, "gold", now_ms)
	gs.set_value("economy.coins", clamped)
	mark_touched(gs, "gold=%d" % clamped, now_ms)
	return clamped


## Level setzen (Clamp 1..MAX_LEVEL; XP auf 0) — Snapshot + Markierung.
static func set_level(gs: Object, value: int, now_ms: int) -> int:
	var leveling: Variant = load("res://scripts/logic/leveling.gd")
	var max_level := 40
	if leveling != null:
		max_level = int(leveling.MAX_LEVEL)
	var clamped := clampi(value, 1, max_level)
	snapshot(gs, "level", now_ms)
	gs.set_value("progression.level", clamped)
	gs.set_value("progression.xp", 0)
	mark_touched(gs, "level=%d" % clamped, now_ms)
	return clamped


## Alle Sticker freischalten (StickerCatalog-Registry) — Anzahl zurück.
static func unlock_all_stickers(gs: Object, now_ms: int) -> int:
	snapshot(gs, "sticker", now_ms)
	var items: Array = StickerCatalog.all()
	gs.update(
		func(state: Dictionary) -> void:
			if not (state.get("stickers") is Dictionary):
				state["stickers"] = {"unlocked": {}, "seen": {}}
			var unlocked: Dictionary = state["stickers"].get("unlocked", {})
			for def: Dictionary in items:
				var id := str(def.get("id", ""))
				if not id.is_empty() and not unlocked.has(id):
					unlocked[id] = now_ms
			state["stickers"]["unlocked"] = unlocked
	)
	gs.notify_slice_changed("stickers")
	mark_touched(gs, "sticker_alle", now_ms)
	return items.size()


## Pferd am sicheren Ort erzeugen: Daten-Spawn in ranch.tiere.pferde
## (erscheint im Stall). Allowlist-Farben; Deckel gegen Massen-Spawn.
static func spawn_horse(gs: Object, horse_name: String, farbe: String, now_ms: int) -> bool:
	if not ResourceLoader.exists("res://scripts/ranch/data/ranch_play_slices.gd"):
		return false
	var slices: Variant = load("res://scripts/ranch/data/ranch_play_slices.gd")
	if slices == null:
		return false
	var farben: Array = ["braun", "weiss", "schwarz", "fuchs"]
	if not farben.has(farbe):
		farbe = "braun"
	slices.ensure_registered()
	var pferde: Variant = gs.get_value("ranch.tiere.pferde", {})
	if pferde is Dictionary and (pferde as Dictionary).size() >= 24:
		return false
	snapshot(gs, "pferd", now_ms)
	var pferd: Dictionary = slices.neues_pferd(horse_name, farbe)
	gs.update(
		func(state: Dictionary) -> void:
			if not (state.get("ranch") is Dictionary):
				state["ranch"] = {}
			var ranch: Dictionary = state["ranch"]
			if not (ranch.get("tiere") is Dictionary):
				ranch["tiere"] = {}
			var tiere: Dictionary = ranch["tiere"]
			if not (tiere.get("pferde") is Dictionary):
				tiere["pferde"] = {}
			tiere["pferde"]["dev_%d" % now_ms] = pferd
	)
	gs.notify_slice_changed("ranch")
	mark_touched(gs, "pferd=%s" % horse_name, now_ms)
	return true


## Warte-Timer aller wartenden Quests auf 10 s ab jetzt stellen.
static func quest_warte_verkuerzen(gs: Object, now_ms: int) -> int:
	var geaendert := {"n": 0}
	snapshot(gs, "quest", now_ms)
	gs.update(
		func(state: Dictionary) -> void:
			var ranch: Variant = state.get("ranch")
			if not (ranch is Dictionary):
				return
			var quests: Variant = (ranch as Dictionary).get("quests")
			if not (quests is Dictionary):
				return
			var aktiv: Variant = (quests as Dictionary).get("aktiv")
			if not (aktiv is Dictionary):
				return
			for quest_id: String in aktiv:
				var lauf: Variant = aktiv[quest_id]
				if lauf is Dictionary and (lauf as Dictionary).has("bereitAt"):
					lauf["bereitAt"] = now_ms + 10_000
					geaendert["n"] += 1
	)
	if geaendert["n"] > 0:
		gs.notify_slice_changed("ranch")
		mark_touched(gs, "quest_warte_10s", now_ms)
	return geaendert["n"]


## Zeit/Wetter-Override auf die AKTUELLE Szene anwenden (Duck-Typing auf
## die öffentlichen Override-Properties der Ranch-Szenen). Transient, kein
## Save-Eingriff. stunde < 0 bzw. wetter == "" heißt „zur Simulation zurück“.
static func apply_time_weather(scene_root: Node, stunde: float, wetter: String) -> int:
	if scene_root == null:
		return 0
	var touched := 0
	for prop in ["stunde_override", "n_override"]:
		if prop in scene_root:
			scene_root.set(prop, stunde)
			touched += 1
	if "wetter_override" in scene_root:
		scene_root.set("wetter_override", wetter)
		touched += 1
	for child in scene_root.get_children():
		touched += apply_time_weather(child, stunde, wetter)
	return touched


## Spielstand-Export in user://dev/exports (JSON) — Pfad zurück ("" Fehler).
static func export_save(gs: Object, now_ms: int) -> String:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(EXPORT_DIR))
	var path := "%s/export_%d.json" % [EXPORT_DIR, now_ms]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(JSON.stringify(gs.state(), "\t"))
	file.close()
	return path


## Netzwerk-Payload redigieren (rekursiv; Geheimnisse/Chattext raus).
static func redact(value: Variant) -> Variant:
	if value is Dictionary:
		var out := {}
		for key: Variant in value:
			var lower := str(key).to_lower()
			var hit := false
			for bad in REDACT_KEYS:
				if lower.contains(bad):
					hit = true
					break
			out[key] = "[redigiert]" if hit else redact(value[key])
		return out
	if value is Array:
		var arr := []
		for item: Variant in value:
			arr.append(redact(item))
		return arr
	return value


static func _prune_snapshots() -> void:
	var dir := DirAccess.open(SNAPSHOT_DIR)
	if dir == null:
		return
	var files: Array[String] = []
	for file in dir.get_files():
		if file.begins_with("snap_") and file.ends_with(".json"):
			files.append(file)
	files.sort()
	while files.size() > SNAPSHOT_KEEP:
		dir.remove(files.pop_front())
