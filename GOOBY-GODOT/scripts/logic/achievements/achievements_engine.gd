class_name AchievementsEngine
extends RefCounted
## Erfolgs-Auswertung (REST-1, Port von GOOBY/src/systems/achievementsEngine.js):
## pure, headless testbare Bedingungs-Prüfung der 44 Katalog-Erfolge gegen den
## v5-Save-State. Kein Polling und keine eigenen Zähler — alle Reads gehen
## auf die vorhandenen Slices (achievements.counters, economy, progression,
## cosmetics, home, stickers, collections, park, vacation, daily, minigames).
## Bedingungen, deren Quell-System noch nicht portiert ist (z. B. holeInOnes),
## bleiben einfach bei Fortschritt 0 gesperrt — exakt das Web-Verhalten.
##
## cond-Vokabular (content/achievements/data/achievements.json):
##   counter: achievements.counters[key] >= count
##   special: engine-evaluierte Reads (coins, level, fullOutfit, decor,
##            streak, play12/21, allCrops, stickers, setsClaimed, neverSick,
##            weightMax/Min, holeInOne, stickerCount, parkVisits,
##            coasterRides, wheelRides, parkNight, postcards,
##            vacationDestinations)


## Fortschritt eines Erfolgs: {current, target} — current auf target geklemmt
## (Web progressOf verbatim).
static func progress_of(def: Dictionary, state: Dictionary) -> Dictionary:
	var cond: Dictionary = def.get("cond", {}) if def.get("cond") is Dictionary else {}
	var target := maxi(1, int(cond.get("count", 1)))
	var current := 0
	match str(cond.get("type", "")):
		"counter":
			current = _counter_of(state, str(cond.get("key", "")))
		"special":
			current = _special_value(state, str(cond.get("key", "")), target)
	return {"current": clampi(current, 0, target), "target": target}


static func is_satisfied(def: Dictionary, state: Dictionary) -> bool:
	var p := progress_of(def, state)
	return int(p["current"]) >= int(p["target"])


## Alle noch gesperrten, jetzt erfüllten Defs (ohne zu mutieren) —
## StickerUnlocks.newly_met-Muster.
static func newly_met(catalog: Array, state: Dictionary) -> Array:
	var unlocked := _unlocked_map(state)
	var result: Array = []
	for def: Variant in catalog:
		if not (def is Dictionary):
			continue
		var id := str(def.get("id", ""))
		if id.is_empty() or unlocked.has(id):
			continue
		if is_satisfied(def, state):
			result.append(def)
	return result


static func is_unlocked(state: Dictionary, id: String) -> bool:
	return _unlocked_map(state).has(id)


static func unlocked_count(state: Dictionary, catalog: Array) -> int:
	var count := 0
	for def: Variant in catalog:
		if def is Dictionary and is_unlocked(state, str(def.get("id", ""))):
			count += 1
	return count


## 'decorator'-Fortschritt: platzierte Möbel, deren Item-Id NICHT im
## Default-Layout der Räume vorkommt, plus jede Wand-/Boden-Änderung
## (decor.wallpaper/floor speichert im Godot-Port nur Overrides).
static func count_non_default_decor(state: Dictionary) -> int:
	var defaults := _default_item_set()
	var n := 0
	var rooms: Variant = _dig(state, ["home", "rooms"])
	if rooms is Dictionary:
		for room_id: Variant in rooms:
			var items: Variant = (
				(rooms[room_id] as Dictionary).get("items")
				if rooms[room_id] is Dictionary
				else null
			)
			if not (items is Array):
				continue
			for entry: Variant in items:
				if not (entry is Dictionary):
					continue
				var item_id := str((entry as Dictionary).get("item", ""))
				if not item_id.is_empty() and not defaults.has(item_id):
					n += 1
	n += _dict_size(_dig(state, ["decor", "wallpaper"]))
	n += _dict_size(_dig(state, ["decor", "floor"]))
	return n


static func _special_value(state: Dictionary, key: String, target: int) -> int:
	match key:
		"coins":
			return int(_num(_dig(state, ["economy", "coins"]), 0.0))
		"level":
			return int(_num(_dig(state, ["progression", "level"]), 1.0))
		"fullOutfit":
			return _filled_slots(_dig(state, ["cosmetics", "outfits", "equipped"]))
		"decor":
			return count_non_default_decor(state)
		"streak":
			return int(_num(_dig(state, ["daily", "streak"]), 0.0))
		"play12", "play21":
			return _distinct_plays(state)
		"allCrops":
			return _veggie_entries(state)
		"stickers":
			# Godot-Buch UND migrierte Web-Sammlung zählen (wer eines von
			# beiden hat, hat "seinen ersten Sticker").
			return maxi(_sticker_book_count(state), _collection_entries(state))
		"setsClaimed":
			# Web-claimedSets (Migration) + Godot-Set-Belohnungen (Album).
			return (
				_dict_size(_dig(state, ["collections", "claimedSets"]))
				+ _dict_size(_dig(state, ["stickers", "setRewards"]))
			)
		"neverSick":
			return _never_sick(state)
		"weightMax":
			return int(_num(_dig(state, ["gooby", "weight"]), 50.0))
		"weightMin":
			var w := _num(_dig(state, ["gooby", "weight"]), 50.0)
			return target if w > 0.0 and w <= float(target) else 0
		"holeInOne":
			return _counter_of(state, "holeInOnes")
		"stickerCount":
			return _sticker_book_count(state)
		"parkVisits":
			return int(_num(_dig(state, ["park", "visits"]), 0.0))
		"coasterRides":
			return int(_num(_dig(state, ["park", "rides", "coaster"]), 0.0))
		"wheelRides":
			return int(_num(_dig(state, ["park", "rides", "wheel"]), 0.0))
		"parkNight":
			return 1 if _truthy(_dig(state, ["park", "nightVisit"])) else 0
		"postcards":
			return maxi(
				_array_size(_dig(state, ["vacation", "archive"])),
				int(_num(_dig(state, ["vacation", "postcards"]), 0.0))
			)
		"vacationDestinations":
			return _dict_size(_dig(state, ["vacation", "visited"]))
	# Unbekannte specials (feindliche/zukünftige Packs): nie erfüllt.
	return 0


static func _never_sick(state: Dictionary) -> int:
	var level := int(_num(_dig(state, ["progression", "level"]), 1.0))
	var sick_ever := _counter_of(state, "sickEver")
	return 1 if level >= 10 and sick_ever == 0 else 0


## Anzahl verschiedener gespielter Arcade-Spiele (minigames.plays >= 1).
static func _distinct_plays(state: Dictionary) -> int:
	var plays: Variant = _dig(state, ["minigames", "plays"])
	if not (plays is Dictionary):
		return 0
	var n := 0
	for id: Variant in plays:
		if _num(plays[id], 0.0) >= 1.0:
			n += 1
	return n


## Verschiedene geerntete Gemüse (migrierte Web-Sammlung veggies.*).
static func _veggie_entries(state: Dictionary) -> int:
	var entries: Variant = _dig(state, ["collections", "entries"])
	if not (entries is Dictionary):
		return 0
	var n := 0
	for key: Variant in entries:
		if str(key).begins_with("veggies.") and _num(entries[key], 0.0) >= 1.0:
			n += 1
	return n


## Alle besessenen Web-Sammel-Einträge (collections.entries >= 1).
static func _collection_entries(state: Dictionary) -> int:
	var entries: Variant = _dig(state, ["collections", "entries"])
	if not (entries is Dictionary):
		return 0
	var n := 0
	for key: Variant in entries:
		if _num(entries[key], 0.0) >= 1.0:
			n += 1
	return n


static func _sticker_book_count(state: Dictionary) -> int:
	return _dict_size(_dig(state, ["stickers", "unlocked"]))


static func _default_item_set() -> Dictionary:
	var defaults := {}
	for room_id: String in RoomDefs.ids():
		for entry: Variant in RoomDefs.default_layout(room_id):
			if entry is Dictionary:
				defaults[str((entry as Dictionary).get("item", ""))] = true
	return defaults


static func _unlocked_map(state: Dictionary) -> Dictionary:
	var unlocked: Variant = _dig(state, ["achievements", "unlocked"])
	return unlocked if unlocked is Dictionary else {}


static func _counter_of(state: Dictionary, key: String) -> int:
	var value: Variant = _dig(state, ["achievements", "counters", key])
	return int(value) if value is int or value is float else 0


static func _filled_slots(equipped: Variant) -> int:
	if not (equipped is Dictionary):
		return 0
	var filled := 0
	for slot in ["hat", "glasses", "neck"]:
		if (equipped as Dictionary).get(slot) != null:
			filled += 1
	return filled


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
