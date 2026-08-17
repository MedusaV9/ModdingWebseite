class_name CarrotCatchLogic
extends RefCounted
## Pure Möhrenfang-Logik — zahlengleicher Port von
## GOOBY/src/minigames/games/carrotCatch.logic.js (§C6.1/G8). 60-s-Runde,
## gutes Essen +1–3 nach Seltenheit, Junk −2 + 0.5 s Dizzy, Fallspeed
## +8 %/10 s (gestuft), Junk-Quote 10 %→30 %, 1× goldene Möhre +10.
## Tune-Dictionaries behalten die Web-Key-Namen für die Bot-Zertifizierung
## (tests/expected/carrotCatch.json aus tools/cross_check.mjs).

## Bindende §C6.1-Zahlen + G8-Tuning (Coin-Zeile: divisor 3, min 4, max 25).
const CATCH := {
	"DURATION_SEC": 60.0,
	"FALL_RAMP_PCT": 0.08,
	"FALL_RAMP_EVERY_SEC": 10.0,
	"JUNK_RATIO_START": 0.1,
	"JUNK_RATIO_END": 0.3,
	"JUNK_PENALTY": -2,
	"DIZZY_SEC": 0.5,
	"GOLDEN_POINTS": 10,
	"GOLDEN_SPEED_MULT": 1.5,
	"GOLDEN_WINDOW_START_SEC": 15.0,
	"GOLDEN_WINDOW_END_SEC": 35.0,
	"GOLDEN_FALL_LEAD_SEC": 5.0,
	"ROTTEN_RATIO_OF_JUNK": 0.35,
	"BASKET_HALF_WIDTH": 0.62,
	"SPAWN_EDGE_PAD": 0.5,
	"FALL_BASE_SPEED": 2.3,
	"SPAWN_BASE_SEC": 1.05,
	"SPAWN_END_FRACTION": 0.72,
	"SPAWN_INTERVAL_MULT": 1.0,
	"WINDOW_MULT": 1.0,
	"DURATION_MULT": 1.0,
	"SPEED_MULT": 1.0,
	"SCORE_MULT": 1.0,
	"ENDLESS": false,
	"ENDLESS_MISSED_CARROTS": 3,
}

## §G5.3 Timed-Arena-Zeile; Endlos = Schwer-Parameter ohne Timer.
const CATCH_DIFFICULTY := {
	"easy": {"spawn": 1.2, "window": 1.25, "duration": 1.2, "endless": false},
	"normal": {"spawn": 1.0, "window": 1.0, "duration": 1.0, "endless": false},
	"hard": {"spawn": 0.85, "window": 0.8, "duration": 1.0, "endless": false},
	"endless": {"spawn": 0.85, "window": 0.8, "duration": 1.0, "endless": true},
}

## Gutes-Essen-Tabelle (§C6.1: +1–3 nach Seltenheit; Gewichte summieren 100).
const GOOD_FOODS: Array[Dictionary] = [
	{"key": "carrot", "value": 1, "weight": 26},
	{"key": "apple", "value": 1, "weight": 15},
	{"key": "banana", "value": 1, "weight": 14},
	{"key": "cheese", "value": 2, "weight": 8},
	{"key": "watermelon", "value": 2, "weight": 8},
	{"key": "donut-sprinkles", "value": 2, "weight": 7},
	{"key": "cupcake", "value": 2, "weight": 7},
	{"key": "burger", "value": 3, "weight": 6},
	{"key": "ice-cream", "value": 3, "weight": 5},
	{"key": "cake", "value": 3, "weight": 4},
]

## Junk-Items (§C6.1: zerdrückte Dose, Fischgräten).
const JUNK_FOODS: Array[String] = ["soda-can-crushed", "fish-bones"]

## Streak-Feier-Kadenz (nur Juice, KEINE Punkte — §C6.1 bleibt unberührt).
const COMBO_MILESTONE_EVERY := 5


## Abgeleitetes Per-Modus-Tuning; Mittel liefert die Live-Tabelle selbst.
static func apply_difficulty(tune: Dictionary = CATCH, mode := "normal") -> Dictionary:
	var id := mode if CATCH_DIFFICULTY.has(mode) else "normal"
	if id == "normal":
		return tune
	var row: Dictionary = CATCH_DIFFICULTY[id]
	var out := tune.duplicate()
	out["DURATION_SEC"] = float(tune["DURATION_SEC"]) * float(row["duration"])
	out["SPAWN_BASE_SEC"] = float(tune["SPAWN_BASE_SEC"]) * float(row["spawn"])
	out["BASKET_HALF_WIDTH"] = maxf(
		float(tune["BASKET_HALF_WIDTH"]) * 0.55,
		float(tune["BASKET_HALF_WIDTH"]) * float(row["window"])
	)
	out["SPAWN_INTERVAL_MULT"] = float(row["spawn"])
	out["WINDOW_MULT"] = float(row["window"])
	out["DURATION_MULT"] = float(row["duration"])
	out["ENDLESS"] = bool(row["endless"])
	out["MODE"] = id
	return out


## Einziger zulässiger Gameplay-Modifier: Turbo (§C-SYS4.3).
static func apply_modifier(tune: Dictionary, modifier: Dictionary) -> Dictionary:
	if modifier.get("type") != "turbo":
		return tune
	var speed_mult := maxf(0.1, _num_or(modifier.get("speedMult"), 1.0))
	var out := tune.duplicate()
	out["FALL_BASE_SPEED"] = float(tune["FALL_BASE_SPEED"]) * speed_mult
	out["SPAWN_BASE_SEC"] = float(tune["SPAWN_BASE_SEC"]) / speed_mult
	out["SPEED_MULT"] = speed_mult
	out["SCORE_MULT"] = maxf(0.0, _num_or(modifier.get("scoreMult"), 1.0))
	return out


## Fallspeed-Multiplikator: +8 % pro VOLLEN 10 s (gestuft, nicht stetig).
static func fall_speed_mult_at(elapsed: float, tune: Dictionary = CATCH) -> float:
	var steps := maxi(0, int(floor(elapsed / float(tune["FALL_RAMP_EVERY_SEC"]))))
	return pow(1.0 + float(tune["FALL_RAMP_PCT"]), steps)


static func fall_speed_at(elapsed: float, tune: Dictionary = CATCH) -> float:
	return float(tune["FALL_BASE_SPEED"]) * fall_speed_mult_at(elapsed, tune)


## Junk-Wahrscheinlichkeit im Rundenverlauf: linear 10 % → 30 % (§C6.1).
static func junk_ratio_at(elapsed: float, duration := 60.0) -> float:
	var t := minf(1.0, maxf(0.0, elapsed / duration))
	var start := float(CATCH["JUNK_RATIO_START"])
	return start + (float(CATCH["JUNK_RATIO_END"]) - start) * t


## Sekunden bis zum nächsten Spawn (Kadenz zieht über die Runde an).
static func spawn_interval_at(elapsed: float, duration := 60.0, tune: Dictionary = CATCH) -> float:
	var t := minf(1.0, maxf(0.0, elapsed / duration))
	return float(tune["SPAWN_BASE_SEC"]) * (1.0 - (1.0 - float(tune["SPAWN_END_FRACTION"])) * t)


## Nächstes Fall-Item würfeln: Junk mit junk_ratio_at-Wahrscheinlichkeit,
## sonst gewichteter Seltenheits-Pick aus GOOD_FOODS.
static func roll_item(rng: GoobyRng, elapsed: float, tune: Dictionary = CATCH) -> Dictionary:
	if rng.next() < junk_ratio_at(elapsed, float(tune["DURATION_SEC"])):
		if rng.next() < float(tune["ROTTEN_RATIO_OF_JUNK"]):
			return {"kind": "rotten", "key": "carrot", "value": int(tune["JUNK_PENALTY"])}
		var idx := mini(JUNK_FOODS.size() - 1, int(floor(rng.next() * JUNK_FOODS.size())))
		return {"kind": "junk", "key": JUNK_FOODS[idx], "value": int(tune["JUNK_PENALTY"])}
	var total := 0.0
	for f in GOOD_FOODS:
		total += float(f["weight"])
	var roll := rng.next() * total
	for f in GOOD_FOODS:
		roll -= float(f["weight"])
		if roll < 0.0:
			return {"kind": "good", "key": f["key"], "value": int(f["value"])}
	var last: Dictionary = GOOD_FOODS[GOOD_FOODS.size() - 1]
	return {"kind": "good", "key": last["key"], "value": int(last["value"])}


## Catch auf den Score anwenden: −2-Junk floort bei 0, nie negativ.
static func apply_catch(score: int, value: int) -> int:
	return maxi(0, score + value)


## Garantierten Golden-Spawn in der Laufmitte würfeln.
static func golden_spawn_at(rng: GoobyRng, duration := 60.0, tune: Dictionary = CATCH) -> float:
	var latest := maxf(
		0.0,
		minf(float(tune["GOLDEN_WINDOW_END_SEC"]), duration - float(tune["GOLDEN_FALL_LEAD_SEC"]))
	)
	var earliest := minf(float(tune["GOLDEN_WINDOW_START_SEC"]), latest)
	return earliest + rng.next() * (latest - earliest)


## Fallspeed pro Item-Art. Die eine goldene Möhre fällt exakt 1.5×.
static func item_fall_speed(elapsed: float, kind: String, tune: Dictionary = CATCH) -> float:
	var mult := float(tune["GOLDEN_SPEED_MULT"]) if kind == "golden" else 1.0
	return fall_speed_at(elapsed, tune) * mult


## Uniformes Edge-to-Edge-Spawn-Mapping (Welt-Koordinaten, UI-scale-frei).
static func spawn_x_for_roll(roll: float, half_w: float) -> float:
	var bound := maxf(0.0, half_w - float(CATCH["SPAWN_EDGE_PAD"]))
	return (minf(1.0, maxf(0.0, roll)) * 2.0 - 1.0) * bound


## Korb-Hitbox in Weltkoordinaten (UI-Skalierung kann das nie beeinflussen).
static func basket_catches_x(item_x: float, basket_x: float, tune: Dictionary = CATCH) -> bool:
	return absf(item_x - basket_x) <= float(tune["BASKET_HALF_WIDTH"]) + 1.7763568394002505e-15


## Item auf Score/Streak anwenden; faule Möhren + Junk brechen die Combo.
static func apply_catch_state(state: Dictionary, item: Dictionary) -> Dictionary:
	var score := apply_catch(int(state["score"]), int(item["value"]))
	var good: bool = item["kind"] == "good" or item["kind"] == "golden"
	return {
		"score": score,
		"combo": int(state["combo"]) + 1 if good else 0,
		"delta": score - int(state["score"]),
	}


## §G5.4: Endlos stoppt nach 3 Boden-Möhren; Timed-Runden bei duration_sec.
static func is_catch_round_over(
	state: Dictionary, tune: Dictionary = CATCH, duration_sec := -1.0
) -> bool:
	var dur := float(tune["DURATION_SEC"]) if duration_sec < 0.0 else duration_sec
	if bool(tune["ENDLESS"]):
		return int(state["missedCarrots"]) >= int(tune["ENDLESS_MISSED_CARROTS"])
	return float(state["elapsed"]) >= dur


## Turbo-Score-Multiplikator wird EINMAL am Ende gerundet (§C-SYS4.2).
static func final_catch_score(score: int, tune: Dictionary = CATCH) -> int:
	var mult := _num_or(tune.get("SCORE_MULT"), 1.0)
	return maxi(0, MinigameFrameworkLogic.js_round(float(score) * mult))


## True bei ×5-Meilensteinen einer sauberen Fang-Serie (5, 10, 15, …).
static func combo_milestone(combo: int) -> bool:
	return combo > 0 and combo % COMBO_MILESTONE_EVERY == 0


## Deterministische Bot-Zertifizierung (identisch zur Web-Autoplay-Policy).
static func simulate_autoplay(mode := "normal", seed_value := 1) -> Dictionary:
	var tune := apply_difficulty(CATCH, mode)
	var rng := GoobyRng.new(seed_value)
	var skill := 0.94
	if mode == "easy":
		skill = 0.98
	elif mode == "hard" or mode == "endless":
		skill = 0.76
	var score := 0
	var missed_carrots := 0
	var elapsed := 0.0
	var limit := 240.0 if bool(tune["ENDLESS"]) else float(tune["DURATION_SEC"])
	while elapsed < limit:
		var item := roll_item(rng, elapsed, tune)
		var good: bool = item["kind"] == "good"
		var caught := rng.next() < (skill if good else 0.04)
		if caught:
			score = apply_catch(score, int(item["value"]))
		elif bool(tune["ENDLESS"]) and good and item["key"] == "carrot":
			missed_carrots += 1
		elapsed += spawn_interval_at(elapsed, float(tune["DURATION_SEC"]), tune)
		if is_catch_round_over({"elapsed": elapsed, "missedCarrots": missed_carrots}, tune):
			break
	# Die Live-Runde garantiert eine goldene Möhre; der Bot fängt sie mit
	# demselben Modus-Skill.
	if not bool(tune["ENDLESS"]) and rng.next() < skill:
		score += int(tune["GOLDEN_POINTS"])
	return {
		"score": final_catch_score(score, tune),
		"elapsed": elapsed,
		"missedCarrots": missed_carrots,
	}


static func _num_or(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
