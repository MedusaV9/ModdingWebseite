class_name LanternFloatLogic
extends RefCounted
## Pure Sternenlaternen-Logik — zahlengleicher Port von
## GOOBY/src/minigames/games/lanternFloat.logic.js (PLAN6 Wave C/C1).
## Eine Papierlaterne steigt automatisch durch den Nachthimmel, seitliches
## Ziehen steuert sie durch Sternenringe (+2, jeder 5. golden +5), an
## Glühwürmchen vorbei (+1), durch angekündigte Windböen und weiche
## Wolkenrempler (Zeitmodus −3; Endlos: 3 Rempler beenden).
## Coin-Zeile /4, 4..24, Ziel 75.

## Bindende C1-Vertragszahlen + V6-Tuning (Welt, Takt, Böen, Bot).
const LANTERN := {
	"DURATION_SEC": 60.0,
	"HALF_W": 3.1,
	"RING_MARGIN": 0.45,
	"STEER_OVERREACH": 1.25,
	"RISE_SPEED": 2.6,
	"RING_SPACING_START": 4.4,
	"RING_SPACING_END": 3.4,
	"RING_RADIUS": 0.56,
	"GOLD_EVERY": 5,
	"RING_PTS": 2,
	"GOLD_PTS": 5,
	"FIREFLY_PTS": 1,
	"FIREFLY_CHANCE": 0.45,
	"FIREFLY_RADIUS": 0.55,
	"GUST_FIRST_SEC": 7.0,
	"GUST_EVERY_SEC": 9.0,
	"GUST_TELEGRAPH_SEC": 1.1,
	"GUST_DURATION_SEC": 1.4,
	"GUST_FORCE": 1.9,
	"CLOUD_CHANCE": 0.22,
	"CLOUD_MIN_INDEX": 3,
	"CLOUD_HALF_W": 0.85,
	"BUMP_PENALTY": 3,
	"BUMP_INVULN_SEC": 1.2,
	"ENDLESS": false,
	"ENDLESS_MAX_BUMPS": 3,
	"AUTOPLAY_AIM_ERR": 0.9,
	"AUTOPLAY_GUST_DRIFT": 0.35,
	"AUTOPLAY_FIREFLY_RATE": 0.8,
	"AUTOPLAY_BUMP_CHANCE": 0.18,
}

## §G5.3-Zeilen (Leicht: Ring ×1.25, Steigen ×0.8, +20 % Zeit).
const LANTERN_DIFFICULTY := {
	"easy": {"ringMult": 1.25, "riseMult": 0.8, "durationMult": 1.2},
	"hard": {"ringMult": 0.8, "riseMult": 1.2, "durationMult": 1.0},
	"endless": {"ringMult": 0.8, "riseMult": 1.2, "durationMult": 1.0},
}


## Abgeleitetes Tune; `normal` liefert exakt die Basis-Tabelle (§G5.3).
static func apply_difficulty(tune := LANTERN, mode := "normal") -> Dictionary:
	if mode == "normal" or not LANTERN_DIFFICULTY.has(mode):
		return tune
	var row: Dictionary = LANTERN_DIFFICULTY[mode]
	var out := tune.duplicate()
	out["DURATION_SEC"] = float(tune["DURATION_SEC"]) * float(row["durationMult"])
	out["RISE_SPEED"] = float(tune["RISE_SPEED"]) * float(row["riseMult"])
	out["RING_RADIUS"] = float(tune["RING_RADIUS"]) * float(row["ringMult"])
	out["ENDLESS"] = mode == "endless"
	out["MODE"] = mode
	return out


## DIE Steuer-Abbildung — die EINE Eingabe-Grenze (§G2.1 Regel 1 / §G3.1-c).
static func steer_target_from(nx: float, tune := LANTERN) -> float:
	var n := maxf(-1.0, minf(1.0, nx))
	return n * float(tune["HALF_W"]) * float(tune["STEER_OVERREACH"])


static func clamp_lantern_x(x: float, tune := LANTERN) -> float:
	return maxf(-float(tune["HALF_W"]), minf(float(tune["HALF_W"]), x))


## Ringabstand zum Zeitpunkt (Takt zieht linear über die Rundendauer an).
static func ring_spacing_at(elapsed: float, tune := LANTERN) -> float:
	var t := minf(1.0, maxf(0.0, elapsed / float(tune["DURATION_SEC"])))
	var start := float(tune["RING_SPACING_START"])
	return start + (float(tune["RING_SPACING_END"]) - start) * t


## n-ten Sternenring würfeln; jeder GOLD_EVERY-te ist golden (lernbarer Takt).
static func roll_ring(rng: GoobyRng, index: int, tune := LANTERN) -> Dictionary:
	var x := (rng.next() * 2.0 - 1.0) * (float(tune["HALF_W"]) - float(tune["RING_MARGIN"]))
	var gold := (index + 1) % int(tune["GOLD_EVERY"]) == 0
	return {
		"index": index,
		"x": x,
		"gold": gold,
		"points": int(tune["GOLD_PTS"]) if gold else int(tune["RING_PTS"]),
	}


## Ist die Laterne durch den Ring geflogen? Reines seitliches Fenster.
static func ring_hit(lantern_x: float, ring: Dictionary, tune := LANTERN) -> bool:
	return absf(lantern_x - float(ring["x"])) <= float(tune["RING_RADIUS"])


## Die n-te Windböe — vollständig deterministische Fahrplanzeile.
static func gust_at(index: int, tune := LANTERN) -> Dictionary:
	var start_sec := float(tune["GUST_FIRST_SEC"]) + index * float(tune["GUST_EVERY_SEC"])
	var push_sec := start_sec + float(tune["GUST_TELEGRAPH_SEC"])
	var h := GoobyRng._imul(index + 1, 2654435761)
	return {
		"index": index,
		"startSec": start_sec,
		"pushSec": push_sec,
		"endSec": push_sec + float(tune["GUST_DURATION_SEC"]),
		"dir": 1 if (h & 2) == 0 else -1,
	}


## Welche Böe gerade zählt und in welcher Phase sie ist.
static func gust_phase_at(elapsed: float, tune := LANTERN) -> Dictionary:
	var idx := maxi(
		0, int(floor((elapsed - float(tune["GUST_FIRST_SEC"])) / float(tune["GUST_EVERY_SEC"])))
	)
	var gust := gust_at(idx, tune)
	if elapsed >= float(gust["endSec"]):
		gust = gust_at(idx + 1, tune)
	var phase := "idle"
	if elapsed < float(gust["startSec"]):
		phase = "idle"
	elif elapsed < float(gust["pushSec"]):
		phase = "telegraph"
	elif elapsed < float(gust["endSec"]):
		phase = "push"
	return {"gust": gust, "phase": phase}


## Wolkenplatz der n-ten Ringlücke; verbraucht IMMER genau ZWEI rng-Züge.
static func roll_cloud(rng: GoobyRng, index: int, tune := LANTERN) -> Dictionary:
	var present := (
		rng.next() < float(tune["CLOUD_CHANCE"]) and index >= int(tune["CLOUD_MIN_INDEX"])
	)
	var x := (rng.next() * 2.0 - 1.0) * (float(tune["HALF_W"]) - float(tune["RING_MARGIN"]))
	return {"present": present, "x": x}


static func cloud_hit(lantern_x: float, cloud: Dictionary, tune := LANTERN) -> bool:
	return absf(lantern_x - float(cloud["x"])) <= float(tune["CLOUD_HALF_W"])


## Punkte-Delta anwenden, bei 0 abgeschnitten (Rempler gehen nie ins Minus).
static func apply_score(score: int, delta: int) -> int:
	return maxi(0, score + delta)


## §G5.4 Endlos endet am dritten Wolkenrempler.
static func endless_should_end(bumps: int, tune := LANTERN) -> bool:
	return bool(tune["ENDLESS"]) and bumps >= int(tune["ENDLESS_MAX_BUMPS"])


## Deterministische Bot-Zertifizierung (Ereignis-pro-Ring, wie im Web).
static func simulate_autoplay(mode := "normal", seed_value := 1) -> Dictionary:
	var tune := apply_difficulty(LANTERN, mode)
	var rng := GoobyRng.new(seed_value)
	var elapsed := 0.0
	var score := 0
	var hits := 0
	var golds := 0
	var fireflies := 0
	var bumps := 0
	var index := 0
	var limit := 600.0 if bool(tune["ENDLESS"]) else float(tune["DURATION_SEC"])
	while not endless_should_end(bumps, tune):
		elapsed += ring_spacing_at(elapsed, tune) / float(tune["RISE_SPEED"])
		if elapsed >= limit:
			break
		var ring := roll_ring(rng, index, tune)
		var phase_info := gust_phase_at(elapsed, tune)
		var gust: Dictionary = phase_info["gust"]
		var drift := 0.0
		if str(phase_info["phase"]) == "push":
			drift = int(gust["dir"]) * float(tune["AUTOPLAY_GUST_DRIFT"])
		var aim := (
			float(ring["x"]) + (rng.next() * 2.0 - 1.0) * float(tune["AUTOPLAY_AIM_ERR"]) + drift
		)
		if ring_hit(clamp_lantern_x(aim, tune), ring, tune):
			hits += 1
			if bool(ring["gold"]):
				golds += 1
			score = apply_score(score, int(ring["points"]))
		if (
			rng.next() < float(tune["FIREFLY_CHANCE"])
			and rng.next() < float(tune["AUTOPLAY_FIREFLY_RATE"])
		):
			fireflies += 1
			score = apply_score(score, int(tune["FIREFLY_PTS"]))
		var cloud := roll_cloud(rng, index, tune)
		if bool(cloud["present"]) and rng.next() < float(tune["AUTOPLAY_BUMP_CHANCE"]):
			bumps += 1
			if not bool(tune["ENDLESS"]):
				score = apply_score(score, -int(tune["BUMP_PENALTY"]))
		index += 1
	return {
		"seed": seed_value,
		"mode": mode,
		"score": score,
		"rings": index,
		"hits": hits,
		"golds": golds,
		"fireflies": fireflies,
		"bumps": bumps,
		"elapsed": elapsed,
	}
