class_name StickerUnlocks
extends Node
## Sticker-Unlock-Service (W3d CONTENT): datengetriebene, SIGNAL-basierte
## Auswertung der Katalog-`cond`s gegen den W1d-GameState. Kein Polling —
## der Service hört auf `slice_changed`/`stats_changed`/`level_changed`
## und re-evaluiert nur dann. Neu freigeschaltete Sticker landen in
## `stickers.unlocked{id: ms}` (Web-verbatim, Migration bringt Bestand mit)
## und feuern `sticker_unlocked(def)` — das Album/HUD zeigt Toast+Konfetti.
##
## cond-Vokabular (deklarativ, KEIN Code im Pack — H §3.5):
##   counter: achievements.counters[key] >= count
##   special: engine-evaluierte Reads (level, weightMax, streak, …)
##   event:   einmalige Hooks — fire_event_hook() setzt stickers.hooks[key]
##   code:    codes.redeemed[key] vorhanden (z. B. herzGooby)

signal sticker_unlocked(def: Dictionary)

var _gs: Object = null
var _catalog: Array = []


## Service anbinden: initiale Auswertung + Signal-Abos. `catalog` leer =
## StickerCatalog.all() (Registry).
func attach(gs: Object, catalog: Array = []) -> void:
	_gs = gs
	_catalog = catalog if not catalog.is_empty() else StickerCatalog.all()
	if _gs is Node:
		var node := _gs as Node
		if node.has_signal("slice_changed"):
			node.slice_changed.connect(_on_slice_changed)
		if node.has_signal("stats_changed"):
			node.stats_changed.connect(func(_stats: Dictionary) -> void: _evaluate())
		if node.has_signal("level_changed"):
			node.level_changed.connect(func(_level: int, _ratio: float) -> void: _evaluate())
	_evaluate()


## Einmaligen Event-Hook feuern (Doc H §3.5 event-Vokabular). Persistiert in
## stickers.hooks — slice_changed("stickers") stößt die Auswertung an.
static func fire_event_hook(gs: Object, hook_id: String) -> void:
	gs.update(
		func(state: Dictionary) -> void:
			if not (state.get("stickers") is Dictionary):
				state["stickers"] = {"unlocked": {}, "seen": {}}
			var stickers: Dictionary = state["stickers"]
			if not (stickers.get("hooks") is Dictionary):
				stickers["hooks"] = {}
			stickers["hooks"][hook_id] = true
	)
	gs.notify_slice_changed("stickers")


# ── pure Auswertung (headless testbar) ───────────────────────────────────────


## Ist die Bedingung im Save-State erfüllt?
static func cond_met(cond: Dictionary, state: Dictionary) -> bool:
	var key := str(cond.get("key", ""))
	var count := int(cond.get("count", 1))
	match str(cond.get("type", "")):
		"counter":
			return _counter_of(state, key) >= count
		"special":
			return _special_value(state, key, cond.get("sub", {})) >= count
		"event":
			return _truthy(_dig(state, ["stickers", "hooks", key]))
		"code":
			var redeemed: Variant = _dig(state, ["codes", "redeemed"])
			return redeemed is Dictionary and redeemed.has(key)
	return false


## Alle noch gesperrten, jetzt erfüllten Defs (ohne zu mutieren).
static func newly_met(catalog: Array, state: Dictionary) -> Array:
	var unlocked: Variant = _dig(state, ["stickers", "unlocked"])
	var unlocked_map: Dictionary = unlocked if unlocked is Dictionary else {}
	var result: Array = []
	for def: Variant in catalog:
		if not (def is Dictionary):
			continue
		var id := str(def.get("id", ""))
		if id.is_empty() or unlocked_map.has(id):
			continue
		var cond: Variant = def.get("cond")
		if cond is Dictionary and cond_met(cond, state):
			result.append(def)
	return result


static func is_unlocked(state: Dictionary, id: String) -> bool:
	var unlocked: Variant = _dig(state, ["stickers", "unlocked"])
	return unlocked is Dictionary and unlocked.has(id)


static func unlocked_count(state: Dictionary, catalog: Array) -> int:
	var count := 0
	for def: Variant in catalog:
		if def is Dictionary and not bool(def.get("secret", false)):
			if is_unlocked(state, str(def.get("id", ""))):
				count += 1
	return count


func _evaluate() -> void:
	if _gs == null:
		return
	var fresh := StickerUnlocks.newly_met(_catalog, _gs.state())
	if fresh.is_empty():
		return
	var now_ms := _now_ms()
	_gs.update(
		func(state: Dictionary) -> void:
			if not (state.get("stickers") is Dictionary):
				state["stickers"] = {"unlocked": {}, "seen": {}}
			var stickers: Dictionary = state["stickers"]
			if not (stickers.get("unlocked") is Dictionary):
				stickers["unlocked"] = {}
			for def: Dictionary in fresh:
				stickers["unlocked"][str(def["id"])] = now_ms
	)
	for def: Dictionary in fresh:
		sticker_unlocked.emit(def)


func _on_slice_changed(_slice_id: String, _data: Variant) -> void:
	_evaluate()


func _now_ms() -> int:
	if _gs != null and "clock" in _gs:
		return int(_gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)


static func _counter_of(state: Dictionary, key: String) -> int:
	var value: Variant = _dig(state, ["achievements", "counters", key])
	return int(value) if value is int or value is float else 0


static func _special_value(state: Dictionary, key: String, sub: Variant) -> float:
	var extra: Dictionary = sub if sub is Dictionary else {}
	match key:
		"first_boot":
			return 1.0
		"level":
			return float(_num(_dig(state, ["progression", "level"]), 1.0))
		"weightMax":
			return float(_num(_dig(state, ["gooby", "weight"]), 50.0))
		"streak":
			return float(_num(_dig(state, ["daily", "streak"]), 0.0))
		"playtimeMin":
			return float(_num(_dig(state, ["profile", "playtimeMin"]), 0.0))
		"coinsSpent":
			return float(_num(_dig(state, ["economy", "coinsSpent"]), 0.0))
		"skinsOwned":
			return float(_array_size(_dig(state, ["cosmetics", "fur", "owned"])))
		"outfitsOwned":
			return float(_array_size(_dig(state, ["cosmetics", "outfits", "owned"])))
		"fullOutfit":
			return float(_filled_slots(_dig(state, ["cosmetics", "outfits", "equipped"])))
		"setsClaimed":
			return float(_dict_size(_dig(state, ["collections", "claimedSets"])))
		"collectionEntry":
			var entry := "%s.%s" % [str(extra.get("set", "")), str(extra.get("entry", ""))]
			return float(_num(_dig(state, ["collections", "entries", entry]), 0.0))
		"gameBest":
			var game := str(extra.get("game", ""))
			return float(_num(_dig(state, ["minigames", "legacy", "best", game]), 0.0))
		"vacationTrips":
			return float(_num(_dig(state, ["vacation", "trips"]), 0.0))
		"park":
			var park_key := str(extra.get("key", "visits"))
			if park_key == "nightVisit":
				return 1.0 if _truthy(_dig(state, ["park", "nightVisit"])) else 0.0
			if park_key == "coasterRides":
				return float(_num(_dig(state, ["park", "rides", "coaster"]), 0.0))
			return float(_num(_dig(state, ["park", park_key]), 0.0))
		"decorPlaced":
			var wallpaper := _dict_size(_dig(state, ["decor", "wallpaper"]))
			var floors := _dict_size(_dig(state, ["decor", "floor"]))
			return float(wallpaper + floors)
	# Unbekannte specials (z. B. postcards bis W3a liefert): nie erfüllt.
	return -1.0


## Typ-sicheres „ist wirklich true“ (String == bool ist in GDScript 4 ein
## Laufzeitfehler — feindliche Saves dürfen hier nicht crashen).
static func _truthy(value: Variant) -> bool:
	return value is bool and value


static func _dig(data: Variant, path: Array) -> Variant:
	var current: Variant = data
	for part: String in path:
		if not (current is Dictionary) or not current.has(part):
			return null
		current = current[part]
	return current


static func _num(value: Variant, fallback: float) -> float:
	return float(value) if (value is int or value is float) else fallback


static func _array_size(value: Variant) -> int:
	return (value as Array).size() if value is Array else 0


static func _dict_size(value: Variant) -> int:
	return (value as Dictionary).size() if value is Dictionary else 0


static func _filled_slots(equipped: Variant) -> int:
	if not (equipped is Dictionary):
		return 0
	var filled := 0
	for slot in ["hat", "glasses", "neck"]:
		if equipped.get(slot) != null:
			filled += 1
	return filled
