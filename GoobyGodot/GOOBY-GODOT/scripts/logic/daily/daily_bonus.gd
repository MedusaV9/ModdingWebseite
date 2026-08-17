class_name DailyBonus
extends RefCounted
## Tagesbonus (REST-1, Port von GOOBY/src/systems/dailyBonus.js §C8.2):
## pure Streak-Logik, headless testbar. Erster Abholtag zählt als Tag 1;
## Serie Tag 1–7 zahlt REWARD_TABLE, ab Tag 7 bleibt es beim Maximum und
## es kommt 1 zufälliger Snack dazu. Abholen ist Pflicht (Tap) — das bloße
## Öffnen des Popups rührt lastClaimDay nie an.
##
## KULANZ (bewusste Verbesserung gegenüber dem Web, Task REST-1): EIN
## verpasster Tag bricht die Serie nicht — der nächste Claim zählt weiter
## (grace=true, das Popup sagt es dazu). Erst ab zwei verpassten Tagen
## beginnt die Serie wieder bei 1.
##
## Save-Form (v5, unverändert): daily = {lastClaimDay: "YYYY-MM-DD", streak}.

const Economy := preload("res://scripts/logic/economy.gd")
const FoodCatalog := preload("res://scripts/logic/food_catalog.gd")

## Web ECONOMY.DAILY_BONUS verbatim (Tag 1..7).
const REWARD_TABLE: Array[int] = [20, 30, 40, 50, 60, 80, 100]
## Ab diesem Serientag kommt 1 zufälliges Essen dazu (Web verbatim).
const FOOD_FROM_DAY := 7


## Der lokale Kalendertag VOR einem "YYYY-MM-DD"-String (Monats-/
## Jahresgrenzen inklusive; "" bei kaputtem Input).
static func prev_day(day: String) -> String:
	var parts := day.split("-")
	if parts.size() != 3 or not parts[2].is_valid_int():
		return ""
	var dict := {
		"year": int(parts[0]),
		"month": int(parts[1]),
		"day": int(parts[2]),
		"hour": 12,
		"minute": 0,
		"second": 0,
	}
	var unix := Time.get_unix_time_from_datetime_dict(dict)
	var prev := Time.get_datetime_dict_from_unix_time(unix - 86400)
	return "%04d-%02d-%02d" % [prev.year, prev.month, prev.day]


## Erster Öffnen pro lokalem Tag → abholbar (Web isClaimable).
static func is_claimable(daily: Dictionary, day: String) -> bool:
	return str(daily.get("lastClaimDay", "")) != day


## Serientag, als der NÄCHSTE Claim an `day` zählt: {streak, grace}.
## Gestern geclaimt → +1; vorgestern geclaimt → +1 mit grace=true (der
## EINE Kulanztag); älter/nie → 1.
static func next_streak(daily: Dictionary, day: String) -> Dictionary:
	var streak := maxi(0, int(daily.get("streak", 0)))
	var last := str(daily.get("lastClaimDay", ""))
	if last.is_empty() or streak <= 0:
		return {"streak": 1, "grace": false}
	var yesterday := prev_day(day)
	if last == yesterday:
		return {"streak": streak + 1, "grace": false}
	if not yesterday.is_empty() and last == prev_day(yesterday):
		return {"streak": streak + 1, "grace": true}
	return {"streak": 1, "grace": false}


## Belohnung für einen Serientag (Web rewardForStreak verbatim):
## Tag 1–7 zahlt REWARD_TABLE[tag-1]; ab Tag 7 bleibt es beim Tag-7-Wert
## und includes_food wird true.
static func reward_for_streak(streak_day: int) -> Dictionary:
	var idx := clampi(streak_day, 1, REWARD_TABLE.size()) - 1
	return {
		"coins": REWARD_TABLE[idx],
		"includes_food": streak_day >= FOOD_FROM_DAY,
	}


## Der zufällige Bonus-Snack ab Tag 7 (rng_value 0..1 injizierbar).
static func pick_bonus_food(rng_value: float) -> String:
	var ids := FoodCatalog.FOODS.keys()
	ids.sort()
	var i := clampi(int(floorf(rng_value * ids.size())), 0, ids.size() - 1)
	return str(ids[i])


## Heutigen Bonus abholen — mutiert `state` in place (Economy-Muster; der
## Aufrufer steckt das in gs.update()). No-op {ok:false}, wenn heute schon
## geclaimt. Münzen laufen über den EINEN Geld-Pfad (Economy.award).
static func claim(state: Dictionary, day: String, rng_value := -1.0) -> Dictionary:
	if not (state.get("daily") is Dictionary):
		state["daily"] = {"lastClaimDay": "", "streak": 0}
	var daily: Dictionary = state["daily"]
	if not is_claimable(daily, day):
		return {"ok": false}
	var next := next_streak(daily, day)
	var streak_day := int(next["streak"])
	var reward := reward_for_streak(streak_day)
	var food_id := ""
	if bool(reward["includes_food"]):
		var roll := rng_value if rng_value >= 0.0 else randf()
		food_id = pick_bonus_food(roll)
		if not (state.get("inventory") is Dictionary):
			state["inventory"] = {"food": {}, "items": {}}
		var inventory: Dictionary = state["inventory"]
		if not (inventory.get("food") is Dictionary):
			inventory["food"] = {}
		var food: Dictionary = inventory["food"]
		food[food_id] = maxi(0, int(food.get(food_id, 0))) + 1
	if state.get("economy") is Dictionary:
		Economy.award(state["economy"], int(reward["coins"]), "dailyBonus")
	daily["lastClaimDay"] = day
	daily["streak"] = streak_day
	return {
		"ok": true,
		"streak_day": streak_day,
		"coins": int(reward["coins"]),
		"food_id": food_id,
		"grace": bool(next["grace"]),
	}
