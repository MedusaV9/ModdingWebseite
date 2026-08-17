class_name CollectionsLogic
extends RefCounted
## Sammlungssets (W13/SAMMLUNG) — pure Logik über dem migrierten Save-Slice
## `collections` ({entries: {"<setId>.<entryId>": count}, claimedSets:
## {"<setId>": timestampMs}}). 1:1-Port der Web-Semantik aus
## GOOBY/src/systems/collections.js + data/collections.js (§C6):
## Einträge sammeln → Set voll → EINMAL claimen → Belohnung (Münzen + Deko +
## 50 XP). Alle Zahlen sind Web-verbatim (constants.js COLLECTIONS/LEVELING).
##
## Schreibzugriffe laufen ausschließlich über die eingefrorene GameState-API
## (update/notify_slice_changed) in apply_claim(); Zeit wird injiziert
## (now_ms/day-Parameter — keine eigene Uhr). Die Deko-Belohnung landet wie
## bei der v4-Migration als `proc:*`-Item im Hauslager (home.storage).

const Economy := preload("res://scripts/logic/economy.gd")
const Leveling := preload("res://scripts/logic/leveling.gd")

## §C5.2: Set-Vervollständigung gibt +50 XP (LEVELING.XP_SET_COMPLETE).
const XP_SET_COMPLETE := 50

## Godot-Garten-Crop-Id → veggies-Set-Eintrag (Web-Id). Nur Aliasse, die vom
## Web-Namen abweichen; Crops ohne Set-Pendant (pilz/ananas/chili) mappen
## auf "" (kein Award). W15/CROPS: radish/corn/eggplant/pumpkin sind jetzt
## Garten-Crops mit WEB-IDENTISCHEN Ids — sie buchen über den Identitäts-
## Fallback in veggie_entry_for_crop, brauchen also KEINEN Alias. Damit ist
## das veggies-Set 8/8 erspielbar (Wache: tests/unit/test_w15_crops.gd).
const VEGGIE_BY_CROP := {"tomate": "tomato", "melone": "watermelon", "salat": "salad"}

## Godot-Food-Katalog-Id → treats-Set-Eintrag (Web-Id). Nur Aliasse; Foods
## ohne Set-Pendant (z. B. carrot/pizza) mappen auf "" (kein Award).
const TREAT_BY_FOOD := {"cupcakePink": "cupcake"}

## Die 4 Web-Sets (§C6 verbatim, Reihenfolge wie constants.js COLLECTIONS):
## id, entries (8/8/6/10 Sticker-IDs), Münz-Belohnung, Deko-Belohnung.
const SETS: Array[Dictionary] = [
	{
		"id": "fish",
		"entries":
		[
			"sunnyCarp",
			"blueDace",
			"pinkKoi",
			"stripeBass",
			"tinyMinnow",
			"bigWhopper",
			"nightEel",
			"goldenFish",
		],
		"coins": 200,
		"furniture": "proc:goldfishBowl",
	},
	{
		"id": "veggies",
		"entries":
		[
			"radish",
			"carrot",
			"salad",
			"tomato",
			"corn",
			"eggplant",
			"pumpkin",
			"watermelon",
		],
		"coins": 150,
		"furniture": "proc:goldenWateringCan",
	},
	{
		"id": "landmarks",
		"entries": ["shop", "vetClinic", "fountain", "skyTower", "parkGazebo", "windmillCafe"],
		"coins": 150,
		"furniture": "proc:toyCity",
	},
	{
		"id": "treats",
		"entries":
		[
			"donut-sprinkles",
			"cupcake",
			"ice-cream",
			"cake",
			"cookie",
			"candy-bar",
			"lollypop",
			"sundae",
			"chocolate",
			"muffin",
		],
		"coins": 150,
		"furniture": "proc:candyJar",
	},
]


## Alle 4 Set-Definitionen in §C6-Reihenfolge (const — nur lesen).
static func sets() -> Array[Dictionary]:
	return SETS


static func set_def(set_id: String) -> Dictionary:
	for def: Dictionary in SETS:
		if str(def["id"]) == set_id:
			return def
	return {}


## Der entries-Map-Schlüssel eines Stickers (Web §B2: "<setId>.<entryId>").
static func entry_key(set_id: String, entry_id: String) -> String:
	return "%s.%s" % [set_id, entry_id]


## Sticker verdienen (Web §B7 award): erhöht entries["<setId>.<entryId>"] um n.
## "first" ist nur beim allerersten Exemplar true — der Aufrufer zeigt genau
## dann den Sticker-Toast. Liefert {"c": neue Slice-Kopie, "first": bool};
## bei n <= 0 oder leeren Ids bleibt die Eingabe-Slice unverändert (Web-verbatim
## KEINE Set-Zugehörigkeits-Prüfung). Award-Verdrahtung der Spielsysteme
## (Angeln/Garten/Stadt/Füttern) passiert bei deren Besitzern — siehe Handoff.
static func award(c: Dictionary, set_id: String, entry_id: String, n := 1) -> Dictionary:
	var amount := int(floor(_num(n, 0.0)))
	if set_id.is_empty() or entry_id.is_empty() or amount <= 0:
		return {"c": c, "first": false}
	var prev := count_of(c, set_id, entry_id)
	var next := normalize_slice(c)
	next["entries"][entry_key(set_id, entry_id)] = prev + amount
	return {"c": next, "first": prev == 0}


## Einbaupunkt-Helfer für die Quellsysteme (INNERHALB von GameState.update
## aufrufen): bucht EINEN Award direkt in den State. entry_id == "" ist ein
## No-Op (unmappte Crop-/Food-Ids); first_only überspringt schon Besessenes
## (Web-firstOnly für landmarks). Liefert das award-first-Flag.
static func award_in_state(
	state: Dictionary, set_id: String, entry_id: String, first_only := false
) -> bool:
	if entry_id.is_empty():
		return false
	var c := normalize_slice(state.get("collections"))
	if first_only and count_of(c, set_id, entry_id) > 0:
		return false
	var res := award(c, set_id, entry_id)
	state["collections"] = res["c"]
	return bool(res["first"])


## Minigame-Host-Helfer (INNERHALB von GameState.update aufrufen): bucht das
## optionale report_end-Feld result["collections"] = {set_id: [entry_ids]}.
## landmarks laufen firstOnly (Web framework.js: firstOnly nur für landmarks).
static func award_report(state: Dictionary, result: Dictionary) -> void:
	var payload: Variant = result.get("collections")
	if not (payload is Dictionary):
		return
	for set_id: Variant in payload:
		var entries: Variant = payload[set_id]
		if not (entries is Array):
			continue
		for entry_id: Variant in entries:
			award_in_state(state, str(set_id), str(entry_id), str(set_id) == "landmarks")


static func veggie_entry_for_crop(crop_id: String) -> String:
	return _entry_in_set("veggies", str(VEGGIE_BY_CROP.get(crop_id, crop_id)))


static func treat_entry_for_food(food_id: String) -> String:
	return _entry_in_set("treats", str(TREAT_BY_FOOD.get(food_id, food_id)))


static func _entry_in_set(set_id: String, entry_id: String) -> String:
	var ids: Array = set_def(set_id).get("entries", [])
	return entry_id if ids.has(entry_id) else ""


## Kaputte/fremde Slices heilen (self-heal wie Web-mergeDefaults): liefert
## IMMER {"entries": {String: int >= 1}, "claimedSets": {String: int ms}} —
## Nicht-Dicts, leere Keys und Counts < 1 fliegen raus; ein vorhandener
## claimedSets-Key bleibt IMMER erhalten (nie versehentlich ent-claimen).
static func normalize_slice(raw: Variant) -> Dictionary:
	var out := {"entries": {}, "claimedSets": {}}
	if not (raw is Dictionary):
		return out
	var entries: Variant = (raw as Dictionary).get("entries")
	if entries is Dictionary:
		for key: Variant in entries:
			var count := int(_num(entries[key], 0.0))
			if key is String and not (key as String).is_empty() and count >= 1:
				out["entries"][key] = count
	var claimed: Variant = (raw as Dictionary).get("claimedSets")
	if claimed is Dictionary:
		for key: Variant in claimed:
			if key is String and not (key as String).is_empty():
				out["claimedSets"][key] = int(_num(claimed[key], 0.0))
	return out


## Besitz-Anzahl eines Eintrags (Wiederholungs-Badges im Album).
static func count_of(c: Dictionary, set_id: String, entry_id: String) -> int:
	var entries: Variant = c.get("entries")
	if not (entries is Dictionary):
		return 0
	return int(_num((entries as Dictionary).get(entry_key(set_id, entry_id)), 0.0))


## Ist jeder Sticker des Sets mindestens einmal da (Web isSetComplete)?
static func is_set_complete(c: Dictionary, set_id: String) -> bool:
	var def := set_def(set_id)
	var ids: Array = def.get("entries", [])
	if ids.is_empty():
		return false
	for entry_id: String in ids:
		if count_of(c, set_id, entry_id) < 1:
			return false
	return true


## Fortschritt eines Sets: {"have": verschiedene besessene, "total": Setgröße}.
static func set_progress(c: Dictionary, set_id: String) -> Dictionary:
	var ids: Array = set_def(set_id).get("entries", [])
	var have := 0
	for entry_id: String in ids:
		if count_of(c, set_id, entry_id) >= 1:
			have += 1
	return {"have": have, "total": ids.size()}


## Gesamt-Fortschritt über alle 4 Sets (Album-Kopfzeile, Web n/32).
static func total_progress(c: Dictionary) -> Dictionary:
	var have := 0
	var total := 0
	for def: Dictionary in SETS:
		var p := set_progress(c, str(def["id"]))
		have += int(p["have"])
		total += int(p["total"])
	return {"have": have, "total": total}


static func is_claimed(c: Dictionary, set_id: String) -> bool:
	var claimed: Variant = c.get("claimedSets")
	return claimed is Dictionary and (claimed as Dictionary).has(set_id)


## Belohnung eines Sets (Web-Zahlen: Münzen + proc-Deko + 50 XP).
static func reward_of(set_id: String) -> Dictionary:
	var def := set_def(set_id)
	if def.is_empty():
		return {}
	return {
		"coins": int(def["coins"]),
		"furniture": str(def["furniture"]),
		"xp": XP_SET_COMPLETE,
	}


## Pure Claim-Prüfung (Web claimSet): Set muss voll und noch nicht geclaimt
## sein. Mutiert NICHTS — liefert {"ok": false} oder {"ok": true,
## "c": neuer Slice (mit claimedSets-Zeitstempel), "reward": {...}}.
static func claim_set(c: Dictionary, set_id: String, now_ms: int) -> Dictionary:
	if is_claimed(c, set_id):
		return {"ok": false}
	if not is_set_complete(c, set_id):
		return {"ok": false}
	var next := normalize_slice(c)
	next["claimedSets"][set_id] = now_ms
	return {"ok": true, "c": next, "reward": reward_of(set_id)}


## Claim über die GameState-API buchen (idempotent — zweiter Aufruf liefert
## {} und zahlt nichts): claimedSets-Zeitstempel, Münzen (reason "album" wie
## Web), +50 XP inkl. Level-Up-Münzen, Deko ins Hauslager (home.storage).
## `now_ms`/`day` werden injiziert (Aufrufer nimmt die GameState-Uhr).
static func apply_claim(gs: Object, set_id: String, now_ms: int, day := "") -> Dictionary:
	if gs == null:
		return {}
	var current := normalize_slice(gs.state().get("collections"))
	var res := claim_set(current, set_id, now_ms)
	if not bool(res.get("ok", false)):
		return {}
	var reward: Dictionary = res["reward"]
	gs.update(
		func(state: Dictionary) -> void:
			state["collections"] = res["c"]
			_store_furniture(state, str(reward["furniture"]))
			if state.get("economy") is Dictionary:
				var econ: Dictionary = state["economy"]
				Economy.award(econ, int(reward["coins"]), "album", day)
				_grant_xp(state, econ, int(reward["xp"]), day)
	)
	gs.notify_slice_changed("collections")
	return reward


## XP über den vorhandenen Leveling-Pfad buchen (Level-Up-Münzen inklusive —
## Muster quest_service._pay, kein zweites Belohnungssystem).
static func _grant_xp(state: Dictionary, econ: Dictionary, xp: int, day: String) -> void:
	if xp <= 0 or not (state.get("progression") is Dictionary):
		return
	var prog: Dictionary = state["progression"]
	var res := Leveling.apply_xp(
		{"xp": float(_num(prog.get("xp"), 0.0)), "level": int(_num(prog.get("level"), 1.0))},
		float(xp)
	)
	prog["xp"] = res["xp"]
	prog["level"] = res["level"]
	if int(res["coinsAwarded"]) > 0:
		Economy.award(econ, res["coinsAwarded"], "levelUp", day)


## Deko-Belohnung ins Hauslager legen (wie die v4-Migration: `proc:*`-IDs
## verbatim in home.storage — StorageLogic behandelt unbekannte IDs mit
## Gewicht 1). Einmal pro Set-Claim, daher kein Dedupe nötig.
static func _store_furniture(state: Dictionary, furniture_id: String) -> void:
	if furniture_id.is_empty() or not (state.get("home") is Dictionary):
		return
	var home: Dictionary = state["home"]
	if not (home.get("storage") is Array):
		home["storage"] = []
	StorageLogic.add(home["storage"], furniture_id)


static func _num(value: Variant, fallback: float) -> float:
	return float(value) if (value is int or value is float) else fallback
