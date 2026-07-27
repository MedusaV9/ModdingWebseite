class_name FoodCatalog
extends RefCounted
## Lebensmittel-Katalog + pure Fütter-Logik (EF-1, EVAL-1 D1+D3).
##
## Vereint ALLE Nahrungs-Ids, die im Godot-Spiel in `inventory.food` landen
## können: Starter-Kühlschrank (save_schema STARTER_FOOD), REHWEI-Sortiment
## (scripts/city/data/rehwei_sortiment.json — IDs/Werte 1:1 gespiegelt) und
## die Garten-Ernten (scripts/home/data/garden_crops.json, deutsche Ids).
## Vorlage der Werte: Web GOOBY/src/data/foods.js (38 Speisen) — hier nur
## die Teilmenge, die im Godot-Spiel wirklich erreichbar ist.
##
## Deltas nutzen die Web-Stat-Keys verbatim (hunger/fun/energy/hygiene),
## damit Stats.apply_deltas direkt arbeitet. `junk` speist Gewicht +
## junkScore (Web §B5-Light), `favorit` gibt den Extra-Freuden-Squeak.
## Unbekannte Ids (feindliche Saves) fallen auf den generischen Snack
## zurück — Füttern darf NIE crashen.

const Stats := preload("res://scripts/logic/stats.gd")

## Gewichtszunahme pro Junk-Fütterung (Web weight.onEat: +2, Deckel 95).
const JUNK_WEIGHT_GAIN := 2.0
const WEIGHT_MAX := 95.0
## Ist Gooby praktisch satt, lehnt er höflich ab (kein Essen verschwenden).
const SATT_AB := 99.5

## id → {hunger, fun, energy, hygiene, junk, favorit} (fehlende Keys = 0/false).
const FOODS := {
	# ── Starter-Kühlschrank + REHWEI-Sortiment ──
	"carrot": {"hunger": 10, "fun": 2, "favorit": true},
	"apple": {"hunger": 10, "fun": 1},
	"cupcake": {"hunger": 10, "fun": 9, "hygiene": -1, "junk": true},
	"banana": {"hunger": 11},
	"tomato": {"hunger": 12, "fun": 1},
	"strawberry": {"hunger": 6, "fun": 6},
	"cookie": {"hunger": 5, "fun": 8, "junk": true},
	"grapes": {"hunger": 8, "fun": 5},
	"chocolate": {"hunger": 5, "fun": 9, "junk": true},
	"bread": {"hunger": 18},
	"corn": {"hunger": 15, "fun": 2},
	"cheese": {"hunger": 16, "fun": 2},
	"watermelon": {"hunger": 14, "fun": 4},
	"croissant": {"hunger": 14, "fun": 4, "energy": 2, "hygiene": -1},
	"muffin": {"hunger": 10, "fun": 8, "junk": true},
	"salad": {"hunger": 20, "hygiene": 2},
	"fries": {"hunger": 12, "fun": 9, "hygiene": -1, "junk": true},
	"sandwich": {"hunger": 24, "fun": 3},
	"burger": {"hunger": 40, "fun": 6},
	"pizza": {"hunger": 45, "fun": 8, "hygiene": -2, "junk": true},
	# ── Garten-Ernten (deutsche Ids aus garden_crops.json) ──
	"tomate": {"hunger": 12, "fun": 1},
	"melone": {"hunger": 14, "fun": 4},
	"salat": {"hunger": 20, "hygiene": 2},
	"pilz": {"hunger": 12, "fun": 2, "energy": 1},
	"ananas": {"hunger": 14, "fun": 7},
	"chili": {"hunger": 6, "fun": 8, "energy": 4},
}

## Fallback für unbekannte Inventar-Ids: generischer kleiner Snack.
const FALLBACK := {"hunger": 10, "fun": 2}


static func all() -> Dictionary:
	return FOODS


static func def(food_id: String) -> Dictionary:
	var raw: Variant = FOODS.get(food_id)
	return raw if raw is Dictionary else FALLBACK


## Anzeigename über die rewards-Strings; unbekannte Ids zeigen die Id.
static func display_name(food_id: String) -> String:
	var key := "rewards.food." + food_id
	if I18nService.has_key(key):
		return I18nService.t(key)
	return food_id


## Stat-Deltas eines Essens (web-keyed, direkt für Stats.apply_deltas).
static func deltas(food_id: String) -> Dictionary:
	var d := def(food_id)
	return {
		"hunger": float(d.get("hunger", 0)),
		"fun": float(d.get("fun", 0)),
		"energy": float(d.get("energy", 0)),
		"hygiene": float(d.get("hygiene", 0)),
	}


static func is_junk(food_id: String) -> bool:
	return bool(def(food_id).get("junk", false))


static func is_favorite(food_id: String) -> bool:
	return bool(def(food_id).get("favorit", false))


## Vorrat als sortierte Liste [{id, count}] (count > 0; meiste zuerst,
## dann alphabetisch — stabil für das Kühlschrank-Panel).
static func inventory_entries(state: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var food: Variant = state.get("inventory", {}).get("food")
	if not (food is Dictionary):
		return out
	for id: Variant in food:
		var count := int(_num(food[id]))
		if count > 0:
			out.append({"id": str(id), "count": count})
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if int(a["count"]) != int(b["count"]):
				return int(a["count"]) > int(b["count"])
			return str(a["id"]) < str(b["id"])
	)
	return out


## Ist Gooby zu satt für eine weitere Fütterung?
static func too_full(state: Dictionary) -> bool:
	var stats: Variant = state.get("gooby", {}).get("stats")
	if not (stats is Dictionary):
		return false
	return float(_num(stats.get("hunger"))) >= SATT_AB


## PURE Fütterung: mutiert `state` (Vorrat −1, Stats +Deltas, Junk-Gewicht,
## feeds-Counter +1). Rückgabe {} wenn nichts gefüttert wurde (kein Vorrat/
## zu satt), sonst {id, deltas, hunger_gain, junk, favorit, feeds}.
## Der Aufrufer ruft danach gs.notify_slice_changed("achievements") für die
## globale Sticker-Auswertung (RewardHub).
static func apply_feed(state: Dictionary, food_id: String) -> Dictionary:
	var inventory: Variant = state.get("inventory", {})
	if not (inventory is Dictionary) or not (inventory.get("food") is Dictionary):
		return {}
	var food: Dictionary = inventory["food"]
	if int(_num(food.get(food_id))) <= 0:
		return {}
	if too_full(state):
		return {}
	var rest := int(_num(food[food_id])) - 1
	if rest <= 0:
		food.erase(food_id)
	else:
		food[food_id] = rest
	var gooby: Variant = state.get("gooby", {})
	var before: Dictionary = gooby.get("stats", {}) if gooby is Dictionary else {}
	var d := deltas(food_id)
	var after := Stats.apply_deltas(before, d)
	if gooby is Dictionary:
		gooby["stats"] = after
		if is_junk(food_id):
			gooby["weight"] = minf(WEIGHT_MAX, float(_num(gooby.get("weight", 50.0))) + 2.0)
			var health: Variant = gooby.get("health")
			if health is Dictionary:
				health["junkScore"] = int(_num(health.get("junkScore"))) + 1
	var counters := _counters(state)
	counters["feeds"] = int(_num(counters.get("feeds"))) + 1
	return {
		"id": food_id,
		"deltas": d,
		"hunger_gain": float(after.get("hunger", 0.0)) - float(_num(before.get("hunger"))),
		"junk": is_junk(food_id),
		"favorit": is_favorite(food_id),
		"feeds": int(counters["feeds"]),
	}


static func _counters(state: Dictionary) -> Dictionary:
	if not (state.get("achievements") is Dictionary):
		state["achievements"] = {"counters": {}}
	var achievements: Dictionary = state["achievements"]
	if not (achievements.get("counters") is Dictionary):
		achievements["counters"] = {}
	return achievements["counters"]


static func _num(value: Variant) -> float:
	return float(value) if (value is int or value is float) else 0.0
