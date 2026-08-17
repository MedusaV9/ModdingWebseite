class_name BurgerBuildLogic
extends RefCounted
## Pure Burger-Bau-Logik — zahlengleicher Port von
## GOOBY/src/minigames/games/burgerBuild.logic.js (§C1.2 #3 / §C10.2 / §G5.3).
## Gesäte 4–7-Lagen-Tickets (Brötchen … Brötchen), Zutaten regnen in 3 Spalten,
## richtige Lage +5, falsche −2, fertiger Burger +15, Fallspeed +8 % je Burger.
## 75 s Runde, Coin-Zeile /4, 4..26, Ziel 85.

## Bindende §C1.2-#3-Zahlen + V2/G24-Tuning (Spawn-Mix, Fall, Bot).
const BURGER := {
	"DURATION_SEC": 75.0,
	"COLUMNS": 3,
	"MIN_LAYERS": 4,
	"MAX_LAYERS": 7,
	"CATCH_PTS": 5.0,
	"WRONG_PTS": -2.0,
	"COMPLETE_PTS": 15.0,
	"FALL_RAMP_PCT": 0.08,
	"FALL_BASE_SPEED": 2.1,
	"SPAWN_SEC": 1.5,
	"NEXT_WEIGHT": 0.24,
	"FORCE_NEXT_SEC": 6.0,
	"BITE_SEC": 2.0,
	"AUTOPLAY_TICK_SEC": 0.3,
	"AUTOPLAY_DISTRACT": 0.42,
	"RUSH_ORDER_NUMBERS": [2, 4],
	"RUSH_SCORE_MULT": 1.5,
	"ORDER_TIMER_SEC": 30.0,
	"RUSH_TIMER_MULT": 0.8,
	"MAX_RUSH_ORDERS": 2,
	"PLATE_HALF_WIDTH": 0.78,
	"ENDLESS": false,
	"ENDLESS_EXPIRES": 3,
	"BOT_SKILL": 0.95,
}

## §G5.3-Zeilen der Timed-Arena-Familie.
const BURGER_DIFFICULTY := {
	"easy":
	{"spawnMult": 1.2, "windowMult": 1.25, "durationMult": 1.2, "botSkill": 0.99, "distract": 0.25},
	"hard":
	{"spawnMult": 0.85, "windowMult": 0.8, "durationMult": 1.0, "botSkill": 0.55, "distract": 0.34},
	"endless":
	{"spawnMult": 0.85, "windowMult": 0.8, "durationMult": 1.0, "botSkill": 0.55, "distract": 0.34},
}

## Die 5 Mittellagen (§C1.2) — Brötchen kommen zusätzlich als Fehlgriff-Köder.
const INGREDIENTS: Array[String] = ["patty", "cheese", "tomato", "salad", "onion"]
## Alles, was regnen kann.
const FALLING_IDS: Array[String] = ["bun", "patty", "cheese", "tomato", "salad", "onion"]


## Abgeleitetes Tune; `normal` liefert exakt die Basis-Tabelle (§G5.3).
## ACHTUNG: Web hat BOT_SKILL nur in den Zeilen — `?? 0.95` ist hier als
## Basiswert eingetragen, damit `normal` denselben Bot fährt.
static func apply_difficulty(tune := BURGER, mode := "normal") -> Dictionary:
	if mode == "normal" or not BURGER_DIFFICULTY.has(mode):
		return tune
	var row: Dictionary = BURGER_DIFFICULTY[mode]
	var out := tune.duplicate()
	out["DURATION_SEC"] = float(tune["DURATION_SEC"]) * float(row["durationMult"])
	out["SPAWN_SEC"] = float(tune["SPAWN_SEC"]) * float(row["spawnMult"])
	out["ORDER_TIMER_SEC"] = maxf(0.35, float(tune["ORDER_TIMER_SEC"]) * float(row["windowMult"]))
	out["PLATE_HALF_WIDTH"] = maxf(
		float(tune["PLATE_HALF_WIDTH"]) * 0.55,
		float(tune["PLATE_HALF_WIDTH"]) * float(row["windowMult"])
	)
	out["ENDLESS"] = mode == "endless"
	out["BOT_SKILL"] = float(row["botSkill"])
	out["AUTOPLAY_DISTRACT"] = float(row["distract"])
	out["MODE"] = mode
	return out


## Gesätes 4–7-Lagen-Ticket (§C1.2): unten→oben, immer brötchengedeckelt.
static func make_ticket(rng: GoobyRng) -> Array[String]:
	var span := int(BURGER["MAX_LAYERS"]) - int(BURGER["MIN_LAYERS"]) + 1
	var total := int(BURGER["MIN_LAYERS"]) + int(floor(rng.next() * span))
	var layers: Array[String] = ["bun"]
	for _i in total - 2:
		var idx := mini(INGREDIENTS.size() - 1, int(floor(rng.next() * INGREDIENTS.size())))
		layers.append(INGREDIENTS[idx])
	layers.append("bun")
	return layers


## Nächste benötigte Lage, "" sobald das Ticket voll ist.
static func next_needed(ticket: Array, placed: int) -> String:
	if placed >= 0 and placed < ticket.size():
		return str(ticket[placed])
	return ""


static func is_complete(ticket: Array, placed: int) -> bool:
	return placed >= ticket.size()


## Fallgeschwindigkeit nach N fertigen Burgern: +8 % je Burger (§C1.2).
static func fall_speed_at(completed_burgers: int, tune := BURGER) -> float:
	return (
		float(tune["FALL_BASE_SPEED"])
		* pow(1.0 + float(tune["FALL_RAMP_PCT"]), float(maxi(0, completed_burgers)))
	)


## Drei datengetriebene Spaltenmitten für jede Hochkant-Ansicht.
static func column_centers(half_w: float) -> Array[float]:
	var spacing := maxf(0.0, minf(2.1, half_w - 0.95))
	return [-spacing, 0.0, spacing]


## Gold-Rush-Tickets sind deterministisch die Bestellungen 2 und 4 (§C10.2).
static func is_rush_order(order_number: int) -> bool:
	return (BURGER["RUSH_ORDER_NUMBERS"] as Array).has(int(floor(order_number)))


## Bestellfrist: Rush-Tickets bekommen exakt 20 % weniger Zeit (§C10.2).
static func order_timer_sec(rush: bool, tune := BURGER) -> float:
	return float(tune["ORDER_TIMER_SEC"]) * (float(tune["RUSH_TIMER_MULT"]) if rush else 1.0)


## Positive Punkte eines Rush-Tickets skalieren ×1.5; Strafen bleiben gleich.
static func order_points(points: float, rush: bool) -> float:
	if points > 0.0 and rush:
		return points * float(BURGER["RUSH_SCORE_MULT"])
	return points


## Id des nächsten fallenden Teils würfeln (Hungerschutz → erzwungene Lage).
static func roll_spawn(
	rng: GoobyRng, needed: String, since_needed_sec: float, tune := BURGER
) -> String:
	if (
		not needed.is_empty()
		and (
			since_needed_sec >= float(tune["FORCE_NEXT_SEC"])
			or rng.next() < float(tune["NEXT_WEIGHT"])
		)
	):
		return needed
	var idx := mini(FALLING_IDS.size() - 1, int(floor(rng.next() * FALLING_IDS.size())))
	return FALLING_IDS[idx]


## Fang werten (bei 0 abgeschnitten): richtig +5 (Rush ×1.5), falsch −2.
static func apply_catch(score: float, correct: bool, rush := false, tune := BURGER) -> float:
	var points := (
		order_points(float(tune["CATCH_PTS"]), rush) if correct else float(tune["WRONG_PTS"])
	)
	return maxf(0.0, score + points)


## §G5.4 Endlos endet nach drei abgelaufenen Bestellungen.
static func endless_should_end(expired: int, tune := BURGER) -> bool:
	return bool(tune["ENDLESS"]) and expired >= int(tune["ENDLESS_EXPIRES"])


## Deterministische Bot-Zertifizierung (identisch zum Web-Release-Bot).
static func simulate_autoplay(seed_value: int, mode := "normal") -> Dictionary:
	var tune := apply_difficulty(BURGER, mode)
	var rng := GoobyRng.new(seed_value)
	var elapsed := 0.0
	var score := 0.0
	var completed := 0
	var expired := 0
	var order_number := 1
	var limit := 600.0 if bool(tune["ENDLESS"]) else float(tune["DURATION_SEC"])
	while elapsed < limit and not endless_should_end(expired, tune):
		var ticket := make_ticket(rng)
		var rush := is_rush_order(order_number)
		var skill := float(tune.get("BOT_SKILL", 0.95))
		var build_sec := (
			ticket.size() * float(tune["SPAWN_SEC"]) * (1.45 + rng.next() * 0.25) / skill
		)
		var deadline := order_timer_sec(rush, tune)
		if build_sec <= deadline:
			elapsed += build_sec + float(tune["BITE_SEC"])
			score += order_points(
				ticket.size() * float(tune["CATCH_PTS"]) + float(tune["COMPLETE_PTS"]), rush
			)
			completed += 1
		else:
			elapsed += deadline
			expired += 1
		order_number += 1
	return {
		"seed": seed_value,
		"mode": mode,
		"score": score,
		"completed": completed,
		"expired": expired,
	}
