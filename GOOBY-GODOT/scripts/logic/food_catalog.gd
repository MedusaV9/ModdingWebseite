class_name FoodCatalog
extends RefCounted
## Lebensmittel-Katalog + pure Fütter-Logik (EF-1, EVAL-1 D1+D3).
##
## Vereint ALLE Nahrungs-Ids, die im Godot-Spiel in `inventory.food` landen
## können: Starter-Kühlschrank (save_schema STARTER_FOOD), REHWEI-Sortiment
## (scripts/city/data/rehwei_sortiment.json — IDs/Werte 1:1 gespiegelt),
## die Garten-Ernten (scripts/home/data/garden_crops.json, deutsche Ids)
## und die Funkelpark-Naschgasse (park_state.gd STALLS, Web V6_PARK_FOODS).
## Vorlage der Werte: Web GOOBY/src/data/foods.js (38 Speisen) — hier nur
## die Teilmenge, die im Godot-Spiel wirklich erreichbar ist.
##
## Deltas nutzen die Web-Stat-Keys verbatim (hunger/fun/energy/hygiene),
## damit Stats.apply_deltas direkt arbeitet. `junk` speist Gewicht +
## junkScore (Web §B5-Light), `favorit` gibt den Extra-Freuden-Squeak.
## Unbekannte Ids (feindliche Saves) fallen auf den generischen Snack
## zurück — Füttern darf NIE crashen.

const Stats := preload("res://scripts/logic/stats.gd")
const HealthLogic := preload("res://scripts/logic/health.gd")
const WeightLogic := preload("res://scripts/logic/weight.gd")

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
	# ── FERTIG-1 (EVAL D1, Web-Parität): drei weitere FOOD_TABLE-Speisen,
	# deren Kenney-GLBs schon im Repo liegen (donut/hot-dog/pancakes) ──
	"donut-sprinkles": {"hunger": 10, "fun": 10, "junk": true},
	"hot-dog": {"hunger": 25, "fun": 4},
	"pancakes": {"hunger": 28, "fun": 6},
	# ── FERTIG-1: Funkelpark-Naschgasse (Web V6_PARK_FOODS) — die Stände
	# verkaufen diese Ids in inventory.food; ohne Katalog-Eintrag fielen
	# sie beim Füttern auf den generischen Snack zurück ──
	"cottonCandy": {"hunger": 5, "fun": 16, "energy": 2, "hygiene": -2, "junk": true},
	"softServe": {"hunger": 7, "fun": 15, "energy": 4, "hygiene": -1, "junk": true},
	"waffle": {"hunger": 22, "fun": 8, "energy": 3, "hygiene": -1},
	# ── Garten-Ernten (deutsche Ids aus garden_crops.json) ──
	"tomate": {"hunger": 12, "fun": 1},
	"melone": {"hunger": 14, "fun": 4},
	"salat": {"hunger": 20, "hygiene": 2},
	"pilz": {"hunger": 12, "fun": 2, "energy": 1},
	"ananas": {"hunger": 14, "fun": 7},
	"chili": {"hunger": 6, "fun": 8, "energy": 4},
	# ── W13/FOOD (P1 Punkte 2+17, Web-Parität 32→39): sechs FOOD_TABLE-
	# Speisen, deren GLBs jetzt unter assets/city/essen/ liegen, plus
	# `nutella` (Web foods.js V3/G35: teuerster Treat UND Treibstoff der
	# Nougatschleuse — s. scripts/logic/nougat_logic.gd). Deltas verbatim
	# aus GOOBY/src/data/constants.js FOOD_TABLE bzw. foods.js. ──
	"ice-cream": {"hunger": 6, "fun": 15, "energy": 5, "junk": true},
	"cake": {"hunger": 30, "fun": 20, "junk": true},
	"pumpkin": {"hunger": 26, "fun": 4},
	"sundae": {"hunger": 7, "fun": 14, "energy": 3, "junk": true},
	"cinnamonRoll": {"hunger": 16, "fun": 8, "energy": 3, "hygiene": -2, "junk": true},
	"cupcakePink": {"hunger": 10, "fun": 10, "energy": 2, "hygiene": -2, "junk": true},
	"nutella": {"hunger": 18, "fun": 6, "energy": 2, "hygiene": -4, "junk": true},
	# ── W13B/INTEGRATE (SAMMLUNG-Request): die letzten zwei treats-Lücken —
	# candy-bar + lollypop (Web FOOD_TABLE verbatim, Ids Web-identisch,
	# Bezugsquelle REHWEI; apply_feed bucht sie damit ins treats-Set). ──
	"candy-bar": {"hunger": 4, "fun": 11, "junk": true},
	"lollypop": {"hunger": 2, "fun": 8, "junk": true},
	# ── W13B/RAUMSTATION: Astro-Snack-Automat (raumstation.gd MOEHRE_ID)
	# verkauft weltraumMoehre in inventory.food — analog carrot, nur
	# festlicher (Anzeigename via rewards.food.weltraumMoehre). ──
	"weltraumMoehre": {"hunger": 12, "fun": 6, "energy": 2, "favorit": true},
}

## Fallback für unbekannte Inventar-Ids: generischer kleiner Snack.
const FALLBACK := {"hunger": 10, "fun": 2}

## W14/FRIDGE (additiv): Regal-Kategorien fürs Kühlschrank-Grid. Bewusst als
## SEPARATE Tabelle statt Feld in FOODS — die Web-Delta-Einträge bleiben
## verbatim 1:1 vergleichbar (test_w13_food_nougat). `getraenke` ist reserviert
## (Katalog führt noch kein Getränk); die Chips blenden leere Kategorien aus.
const KATEGORIEN: Array[String] = ["gemuese", "suesses", "warm", "getraenke"]
const FOOD_KATEGORIE := {
	# ── Gemüse & Obst (Frisches, inkl. Garten-Ernten + Weltraum-Möhre) ──
	"carrot": "gemuese",
	"apple": "gemuese",
	"banana": "gemuese",
	"tomato": "gemuese",
	"strawberry": "gemuese",
	"grapes": "gemuese",
	"watermelon": "gemuese",
	"corn": "gemuese",
	"salad": "gemuese",
	"pumpkin": "gemuese",
	"tomate": "gemuese",
	"melone": "gemuese",
	"salat": "gemuese",
	"pilz": "gemuese",
	"ananas": "gemuese",
	"chili": "gemuese",
	"weltraumMoehre": "gemuese",
	# ── Süßes (Treats — deckt sich mit den junk-Naschereien) ──
	"cupcake": "suesses",
	"cookie": "suesses",
	"chocolate": "suesses",
	"muffin": "suesses",
	"donut-sprinkles": "suesses",
	"cottonCandy": "suesses",
	"softServe": "suesses",
	"ice-cream": "suesses",
	"cake": "suesses",
	"sundae": "suesses",
	"cinnamonRoll": "suesses",
	"cupcakePink": "suesses",
	"nutella": "suesses",
	"candy-bar": "suesses",
	"lollypop": "suesses",
	# ── Warmes & Herzhaftes ──
	"bread": "warm",
	"cheese": "warm",
	"croissant": "warm",
	"fries": "warm",
	"sandwich": "warm",
	"burger": "warm",
	"pizza": "warm",
	"hot-dog": "warm",
	"pancakes": "warm",
	"waffle": "warm",
}


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


## W14/FRIDGE (additiv): Regal-Kategorie einer Speise. Unbekannte/feindliche
## Ids werden hergeleitet (junk → Süßes, sonst Gemüse) — nie leer.
static func kategorie(food_id: String) -> String:
	if FOOD_KATEGORIE.has(food_id):
		return str(FOOD_KATEGORIE[food_id])
	return "suesses" if is_junk(food_id) else "gemuese"


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
		# REST-3: Füttern speist die ECHTEN Pflege-Module (Web §B5) — vorher
		# stand hier eine Inline-Näherung nur für Junk. Jetzt: Gewicht Junk
		# +2.0 / gesund +0.5, Krankheits-Slice junkScore +1 bzw. −0.5 samt
		# tummyWarning-Rampe (der Ticker feuert das Event beim nächsten Takt).
		var junk := is_junk(food_id)
		gooby["weight"] = WeightLogic.on_eat(gooby.get("weight", WeightLogic.DEFAULT), junk)
		gooby["health"] = HealthLogic.on_eat(gooby.get("health"), junk)
	var counters := _counters(state)
	counters["feeds"] = int(_num(counters.get("feeds"))) + 1
	# W13/SAMMLUNG: Süßes füllt das treats-Album-Set (Web interactions.js
	# isTreat-Pfad); Foods ohne Set-Pendant sind ein No-Op.
	CollectionsLogic.award_in_state(state, "treats", CollectionsLogic.treat_entry_for_food(food_id))
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
