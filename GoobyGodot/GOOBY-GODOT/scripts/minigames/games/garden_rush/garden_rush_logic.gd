class_name GardenRushLogic
extends RefCounted
## Gießkannen-Wirbel (gardenRush) — PURE Logik, zahlengleicher Port von
## GOOBY/src/minigames/games/gardenRush.logic.js (PLAN2 §C1.2 #2). 8 Töpfe
## (Nr. 7 ab 20 s, Nr. 8 ab 35 s), Welkfenster 6 s → 3 s, Halten füllt den
## 0,8-s-Ring; Loslassen im letzten Viertel = perfekt +3, früher +1,
## verwelkt −2, Unkraut −1. 60 s. Bei 30 s kommt der einmalige Sprinkler.
## Coin-Zeile: /3, 4..25, Ziel 65.

## Bindende §C1.2-#2-Zahlen + V2/G24-Tuning.
const RUSH := {
	"DURATION_SEC": 60.0,
	"POTS": 8,
	"START_POTS": 6,
	"POT7_AT_SEC": 20.0,
	"POT8_AT_SEC": 35.0,
	"WILT_START_SEC": 6.0,
	"WILT_END_SEC": 3.0,
	"FILL_SEC": 0.8,
	"PERFECT_ZONE": 0.25,
	"PERFECT_PTS": 3,
	"EARLY_PTS": 1,
	"WILT_PTS": -2,
	"WEED_PTS": -1,
	"SPAWN_START_SEC": 3.1,
	"SPAWN_END_SEC": 2.0,
	"RESPAWN_SEC": 0.9,
	"WEED_FROM_SEC": 12.0,
	"WEED_CHANCE": 0.18,
	"WEED_LIFE_SEC": 5.0,
	"AUTOPLAY_HOLD_SEC": 0.75,
	"SPRINKLER_AT_SEC": 30.0,
	"SPRINKLER_FILL_FRAC": 0.5,
	"ENDLESS": false,
	"ENDLESS_WILTS": 3,
	"AUTOPLAY_DISTRACT": 0.32,
	"AUTOPLAY_EARLY": 0.18,
}

## V4/G73 Timed-Arena-Multiplikatoren (§G5.3).
const RUSH_DIFFICULTY := {
	"easy":
	{
		"spawnMult": 1.2,
		"windowMult": 1.25,
		"durationMult": 1.2,
		"botSuccess": 0.995,
		"distract": 0.18,
	},
	"hard":
	{
		"spawnMult": 0.85,
		"windowMult": 0.8,
		"durationMult": 1.0,
		"botSuccess": 0.77,
		"distract": 0.26,
	},
	"endless":
	{
		"spawnMult": 0.85,
		"windowMult": 0.8,
		"durationMult": 1.0,
		"botSuccess": 0.77,
		"distract": 0.26,
	},
}


## Abgeleitetes Tune; `normal` liefert die bit-identische Mittel-Tabelle.
static func apply_difficulty(tune: Dictionary = RUSH, mode := "normal") -> Dictionary:
	if mode == "normal" or not RUSH_DIFFICULTY.has(mode):
		return tune
	var row: Dictionary = RUSH_DIFFICULTY[mode]
	var out := tune.duplicate()
	out["DURATION_SEC"] = float(tune["DURATION_SEC"]) * float(row["durationMult"])
	out["SPAWN_START_SEC"] = float(tune["SPAWN_START_SEC"]) * float(row["spawnMult"])
	out["SPAWN_END_SEC"] = float(tune["SPAWN_END_SEC"]) * float(row["spawnMult"])
	out["WILT_START_SEC"] = maxf(0.35, float(tune["WILT_START_SEC"]) * float(row["windowMult"]))
	out["WILT_END_SEC"] = maxf(0.35, float(tune["WILT_END_SEC"]) * float(row["windowMult"]))
	out["FILL_SEC"] = maxf(0.35, float(tune["FILL_SEC"]) * float(row["windowMult"]))
	out["ENDLESS"] = mode == "endless"
	out["ENDLESS_SPAWN_FLOOR_SEC"] = 1.0
	out["ENDLESS_WILT_FLOOR_SEC"] = 1.2
	out["AUTOPLAY_SUCCESS"] = float(row["botSuccess"])
	out["AUTOPLAY_DISTRACT"] = float(row["distract"])
	return out


## Welkfenster zum Rundenzeitpunkt: linear 6 s → 3 s, mit Boden.
static func wilt_window_at(elapsed: float, duration := 60.0, tune: Dictionary = RUSH) -> float:
	var t := _ramp_t(elapsed, duration, tune)
	var start := float(tune["WILT_START_SEC"])
	var value := start + (float(tune["WILT_END_SEC"]) - start) * t
	return maxf(float(tune.get("ENDLESS_WILT_FLOOR_SEC", tune["WILT_END_SEC"])), value)


## Sekunden bis zum nächsten Sprössling/Unkraut (Kadenz zieht an).
static func spawn_interval_at(elapsed: float, duration := 60.0, tune: Dictionary = RUSH) -> float:
	var t := _ramp_t(elapsed, duration, tune)
	var start := float(tune["SPAWN_START_SEC"])
	var value := start + (float(tune["SPAWN_END_SEC"]) - start) * t
	return maxf(float(tune.get("ENDLESS_SPAWN_FLOOR_SEC", tune["SPAWN_END_SEC"])), value)


## Aktive Töpfe zum Rundenzeitpunkt: 6, dann #7 ab 20 s und #8 ab 35 s.
static func active_pots_at(elapsed: float) -> int:
	if elapsed >= float(RUSH["POT8_AT_SEC"]):
		return 8
	if elapsed >= float(RUSH["POT7_AT_SEC"]):
		return 7
	return int(RUSH["START_POTS"])


## Punkte fürs Loslassen bei einem Füllstand: letztes Viertel +3, sonst +1.
static func release_points(fill_frac: float, tune: Dictionary = RUSH) -> int:
	var f := minf(1.0, maxf(0.0, fill_frac))
	if f >= 1.0 - float(tune["PERFECT_ZONE"]):
		return int(tune["PERFECT_PTS"])
	return int(tune["EARLY_PTS"])


## Liegt ein Füllstand in der grünen Zone? (Ring-Rendering + Tests)
static func in_perfect_zone(fill_frac: float, tune: Dictionary = RUSH) -> bool:
	return minf(1.0, maxf(0.0, fill_frac)) >= 1.0 - float(tune["PERFECT_ZONE"])


## Füllanteil aus der echten Haltedauer (nicht auf Frames gerastert).
static func hold_fill_fraction(held_sec: float, tune: Dictionary = RUSH) -> float:
	return minf(1.0, maxf(0.0, held_sec / float(tune["FILL_SEC"])))


## Der Sprinkler füllt den Welkring einer Pflanze um 50 % auf, gedeckelt.
static func sprinkler_refill(remaining_sec: float, window_sec: float) -> float:
	var window := maxf(0.0, window_sec)
	return minf(window, maxf(0.0, remaining_sec) + window * float(RUSH["SPRINKLER_FILL_FRAC"]))


## Einmaliges 30-s-Sprinkler-Tor, auch wenn ein Frame die Schwelle überspringt.
static func should_spawn_sprinkler(elapsed: float, already_spawned: bool) -> bool:
	return not already_spawned and elapsed >= float(RUSH["SPRINKLER_AT_SEC"])


## Soll dieser Spawn ein Täusch-Unkraut sein?
static func roll_weed(rng: GoobyRng, elapsed: float) -> bool:
	if elapsed < float(RUSH["WEED_FROM_SEC"]):
		return false
	return rng.next() < float(RUSH["WEED_CHANCE"])


## Punkte-Event auf den Score anwenden, bei 0 gefloort.
static func apply_points(score: int, points: int) -> int:
	return maxi(0, score + points)


## §G5.4 Endlos endet nach drei verwelkten Töpfen.
static func endless_should_end(withered: int, tune: Dictionary = RUSH) -> bool:
	return bool(tune["ENDLESS"]) and withered >= int(tune["ENDLESS_WILTS"])


## Deterministische, tune-getriebene Bot-Zertifizierung.
static func simulate_autoplay(seed_value := 1, mode := "normal") -> Dictionary:
	var tune := apply_difficulty(RUSH, mode)
	var rng := GoobyRng.new(seed_value)
	var duration := float(tune["DURATION_SEC"])
	var limit := 600.0 if bool(tune["ENDLESS"]) else duration
	var elapsed := 0.0
	var score := 0
	var withered := 0
	var success := float(tune.get("AUTOPLAY_SUCCESS", 0.97))
	while elapsed < limit and not endless_should_end(withered, tune):
		elapsed += spawn_interval_at(elapsed, duration, tune)
		if elapsed > limit:
			break
		if rng.next() < success:
			score += int(tune["PERFECT_PTS"])
		else:
			withered += 1
	return {
		"seed": seed_value,
		"mode": mode,
		"score": score,
		"withered": withered,
		"elapsed": elapsed,
	}


## Gemeinsame Rampen-Zeit: getaktete Modi klemmen bei 1, Endlos wächst weiter.
static func _ramp_t(elapsed: float, duration: float, tune: Dictionary) -> float:
	if bool(tune["ENDLESS"]):
		return maxf(0.0, elapsed / duration)
	return minf(1.0, maxf(0.0, elapsed / duration))
