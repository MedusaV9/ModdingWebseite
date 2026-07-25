class_name CarrotGuardLogic
extends RefCounted
## Karottenwache (carrotGuard) — PURE Logik, zahlengleicher Port von
## GOOBY/src/minigames/games/carrotGuard.logic.js (§C6.1 #4). 3×3 Erdhügel,
## Maulwürfe bleiben 0,9 s → 0,5 s oben, 10 Karotten im Beet, Treffer +1,
## jede 5er-Kombo +3, Runde endet nach 45 s oder wenn alle Karotten weg sind.
## Nach je 20 Treffern kommt der Maulwurfkönig (3 Taps, +8 + 2 Münzen).
## Coin-Zeile: /3, 4..25, Ziel 70.

## Bindende §C6.1-#4-Zahlen + G8-Tuning.
const GUARD := {
	"DURATION_SEC": 45.0,
	"GRID": 3,
	"CARROTS": 10,
	"UP_TIME_START": 0.9,
	"UP_TIME_END": 0.5,
	"HIT_POINTS": 1,
	"COMBO_BONUS_AT": 5,
	"COMBO_BONUS": 3,
	"SPAWN_START_SEC": 1.3,
	"SPAWN_END_SEC": 0.75,
	"DOUBLE_CHANCE_END": 0.35,
	"POP_SEC": 0.16,
	"KING_EVERY_BONKS": 20,
	"KING_TAPS": 3,
	"KING_POINTS": 8,
	"KING_COIN_DROP": 2,
	"KING_SCORE_PER_COIN": 3,
	"TAP_DEBOUNCE_SEC": 0.075,
	"WHIFF_COOLDOWN_SEC": 0.18,
	"SPAWN_INTERVAL_MULT": 1.0,
	"WINDOW_MULT": 1.0,
	"DURATION_MULT": 1.0,
	"ENDLESS": false,
	"ENDLESS_STOLEN": 3,
	"BOT_REACTION_SEC": 0.34,
}

const GUARD_DIFFICULTY := {
	"easy": {"spawn": 1.2, "window": 1.25, "duration": 1.2, "endless": false},
	"normal": {"spawn": 1.0, "window": 1.0, "duration": 1.0, "endless": false},
	"hard": {"spawn": 0.85, "window": 0.8, "duration": 1.0, "endless": false},
	"endless": {"spawn": 0.85, "window": 0.8, "duration": 1.0, "endless": true},
}


## §G5 Timed-Arena-Difficulty; `normal` liefert die Basistabelle.
static func apply_difficulty(tune: Dictionary = GUARD, mode := "normal") -> Dictionary:
	var id := mode if GUARD_DIFFICULTY.has(mode) else "normal"
	if id == "normal":
		return tune
	var row: Dictionary = GUARD_DIFFICULTY[id]
	var out := tune.duplicate()
	out["DURATION_SEC"] = float(tune["DURATION_SEC"]) * float(row["duration"])
	out["SPAWN_START_SEC"] = float(tune["SPAWN_START_SEC"]) * float(row["spawn"])
	out["SPAWN_END_SEC"] = float(tune["SPAWN_END_SEC"]) * float(row["spawn"])
	out["UP_TIME_START"] = maxf(0.35, float(tune["UP_TIME_START"]) * float(row["window"]))
	out["UP_TIME_END"] = maxf(0.35, float(tune["UP_TIME_END"]) * float(row["window"]))
	out["SPAWN_INTERVAL_MULT"] = float(row["spawn"])
	out["WINDOW_MULT"] = float(row["window"])
	out["DURATION_MULT"] = float(row["duration"])
	out["ENDLESS"] = bool(row["endless"])
	out["BOT_REACTION_SEC"] = minf(
		float(tune["BOT_REACTION_SEC"]),
		maxf(0.24, float(tune["BOT_REACTION_SEC"]) * float(row["window"]))
	)
	out["MODE"] = id
	return out


## Wie lange ein Maulwurf gerade oben bleibt: linear 0,9 s → 0,5 s.
static func up_time_at(elapsed: float, duration := 45.0, tune: Dictionary = GUARD) -> float:
	var t := minf(1.0, maxf(0.0, elapsed / duration))
	var start := float(tune["UP_TIME_START"])
	return start + (float(tune["UP_TIME_END"]) - start) * t


## Sekunden bis zum nächsten Maulwurf (Kadenz zieht über die Runde an).
static func spawn_interval_at(elapsed: float, duration := 45.0, tune: Dictionary = GUARD) -> float:
	var t := minf(1.0, maxf(0.0, elapsed / duration))
	var start := float(tune["SPAWN_START_SEC"])
	return start + (float(tune["SPAWN_END_SEC"]) - start) * t


## Chance auf einen Doppel-Spawn zum Rundenzeitpunkt (0 → DOUBLE_CHANCE_END).
static func double_chance_at(elapsed: float, duration := 45.0, tune: Dictionary = GUARD) -> float:
	var t := minf(1.0, maxf(0.0, elapsed / duration))
	return float(tune["DOUBLE_CHANCE_END"]) * t


## Kombo-Bonus: zahlt bei JEDEM Vielfachen von 5, nicht bei jedem Treffer >5.
static func combo_bonus(combo: int) -> int:
	if combo > 0 and combo % int(GUARD["COMBO_BONUS_AT"]) == 0:
		return int(GUARD["COMBO_BONUS"])
	return 0


## Treffer buchen: +1 Punkt, Kombo +1, alle 5 zusätzlich +3.
static func apply_bonk(s: Dictionary) -> Dictionary:
	var combo := int(s["combo"]) + 1
	var bonus := combo_bonus(combo)
	return {
		"score": int(s["score"]) + int(GUARD["HIT_POINTS"]) + bonus, "combo": combo, "bonus": bonus
	}


## Entwischter Maulwurf: klaut eine Karotte und bricht die Kombo.
static func apply_escape(s: Dictionary) -> Dictionary:
	return {"carrots": maxi(0, int(s["carrots"]) - 1), "combo": 0}


## Danebengehauen: kein Punktverlust, aber die Kombo ist weg.
static func apply_whiff(_s: Dictionary) -> Dictionary:
	return {"combo": 0}


## Rundenende (§C6.1: 45 s oder alle Karotten weg; Endlos: 3 geklaute).
static func is_round_over(s: Dictionary, duration := 45.0, tune: Dictionary = GUARD) -> bool:
	if bool(tune["ENDLESS"]):
		return int(tune["CARROTS"]) - int(s["carrots"]) >= int(tune["ENDLESS_STOLEN"])
	return float(s["elapsed"]) >= duration or int(s["carrots"]) <= 0


## Nach jedem Block von 20 regulären Treffern steht ein König an.
static func is_king_due(bonks: int, kings_spawned: int) -> bool:
	return bonks >= (kings_spawned + 1) * int(GUARD["KING_EVERY_BONKS"])


## Einen König-Tap auflösen; erst der dritte zahlt +8 plus zwei Münzen.
static func apply_king_tap(state: Dictionary) -> Dictionary:
	var hp := maxi(0, int(state["hp"]) - 1)
	if hp > 0:
		return {
			"score": int(state["score"]),
			"combo": int(state["combo"]),
			"hp": hp,
			"complete": false,
			"bonus": 0,
			"gained": 0,
		}
	var combo := int(state["combo"]) + 1
	var bonus := combo_bonus(combo)
	var gained := (
		int(GUARD["KING_POINTS"])
		+ int(GUARD["KING_COIN_DROP"]) * int(GUARD["KING_SCORE_PER_COIN"])
		+ bonus
	)
	return {
		"score": int(state["score"]) + gained,
		"combo": combo,
		"hp": 0,
		"complete": true,
		"bonus": bonus,
		"gained": gained,
	}


## Debounce für doppelt zugestellte Taps und Leerschlag-Spam.
static func accepts_tap_after(since_last_sec: float, cooldown_sec := 0.075) -> bool:
	return not is_finite(since_last_sec) or since_last_sec >= cooldown_sec


## Deterministische Bot-Zertifizierung (zahlengleich zum Web-Reaktionsmodell).
static func simulate_autoplay(seed_value := 1, mode := "normal") -> Dictionary:
	var tune := apply_difficulty(GUARD, mode)
	var rng := GoobyRng.new(seed_value)
	var accuracy := 0.93
	if mode == "easy":
		accuracy = 0.96
	elif mode == "hard" or mode == "endless":
		accuracy = 0.82
	var elapsed := 0.0
	var carrots := int(tune["CARROTS"])
	var state := {"score": 0, "combo": 0}
	var duration := float(tune["DURATION_SEC"])
	while (
		not is_round_over({"elapsed": elapsed, "carrots": carrots}, duration, tune)
		and elapsed < 240.0
	):
		var count := 1
		if rng.next() < double_chance_at(elapsed, duration, tune):
			count = 2
		for _i in count:
			if rng.next() < accuracy:
				state = apply_bonk(state)
			else:
				var escaped := apply_escape({"carrots": carrots, "combo": int(state["combo"])})
				carrots = int(escaped["carrots"])
				state["combo"] = int(escaped["combo"])
		elapsed += spawn_interval_at(elapsed, duration, tune)
	return {
		"seed": seed_value,
		"mode": mode,
		"score": int(state["score"]),
		"elapsed": elapsed,
		"stolen": int(tune["CARROTS"]) - carrots,
	}
