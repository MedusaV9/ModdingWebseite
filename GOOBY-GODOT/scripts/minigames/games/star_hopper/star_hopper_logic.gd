class_name StarHopperLogic
extends RefCounted
## Pure Sternenhüpfer-Logik — zahlengleicher Port von
## GOOBY/src/minigames/games/starHopper.logic.js (PLAN2 §C1.2 #8, §C10.2).
## 3 Bahnen, Meteore mit 70-%-Hitboxen, Sterne +3 / goldene Karotten +10,
## Tempo +5 % alle 10 s, angekündigte Meteorschauer, EIN Treffer beendet
## (Schild ab Score 60 rettet einmal), Score = Meter/10 + Aufsammler.
## Bot-Hilfen (Reihen-Erzeugung, Bahnwahl) liegen in `star_hopper_bot.gd`.

## Bindende §C1.2-#8-Zahlen; Coin-Zeile 9/4/26, Ziel 190.
const HOPPER := {
	"LANES": 3,
	"LANE_X": [-1.15, 0.0, 1.15],
	"DURATION_SEC": 75.0,
	"BASE_SPEED": 11.0,
	"SPEED_RAMP_PCT": 0.05,
	"SPEED_RAMP_EVERY_SEC": 10.0,
	"MAX_SPEED": 19.0,
	"HITBOX_SCALE": 0.7,
	"PLAYER_HALF_M": 3.2,
	"METEOR_HALF_M": 3.4,
	"STAR_POINTS": 3,
	"GOLD_POINTS": 10,
	"SHIELD_SCORE": 60,
	"DISTANCE_PER_POINT_M": 10.0,
	"LANE_CHANGE_SEC": 0.16,
	"ROW_GAP_M": {"start": 27.0, "end": 18.0},
	"DIFFICULTY_FULL_SEC": 60.0,
	"DOUBLE_BLOCK_CHANCE": {"start": 0.2, "end": 0.55},
	"GOLD_CHANCE": 0.05,
	"STAR_CHANCE": 0.38,
	"SHOWER_EVERY_SEC": 14.0,
	"SHOWER_TELEGRAPH_SEC": 1.3,
	"SHOWER_DURATION_SEC": 2.2,
	"SHOWER_DROP_EVERY_SEC": 0.35,
	"SHOWER_METEOR_SPEED": 38.0,
	"BOT_WINDOW_SEC": 0.4,
	"BOT_GUARD_SEC": 0.5,
	"BOT_TRANSIT_GUARD_SEC": 0.35,
	"BOT_PANIC_SEC": 0.45,
	"MAX_SWEEP_STEP_M": 2.0,
	"SHIELD_POP_INVULN_SEC": 1.2,
	"WORMHOLE_FIRST_SEC": 18.0,
	"WORMHOLE_CHANCE": 0.08,
	"WORMHOLE_SEC": 2.0,
	"WORMHOLE_TICK_SEC": 0.2,
	"WORMHOLE_TICK_POINTS": 1,
	"SWIPE_TAP_SUPPRESS_SEC": 0.18,
	"ENDLESS": false,
	"RAMP_STEP_OFFSET": 0,
	"SPEED_MULT": 1.0,
	"SCORE_MULT": 1.0,
	"COIN_RATE": 1.0,
	"GOOBY_SCALE": 1.0,
}

## GP3-Juice (nur Optik, nie Spielmathematik).
const HOPPER_JUICE := {"BARREL_ROLL_SEC": 0.55, "POP_SEC": 0.28, "POP_SCALE": 1.13}


## §G5 Difficulty; `normal` liefert die Basistabelle unverändert.
static func apply_difficulty(tune := HOPPER, mode := "normal") -> Dictionary:
	if mode == "normal" or not ["easy", "hard", "endless"].has(mode):
		return tune
	var hard := mode == "hard" or mode == "endless"
	var preview_mult := 1.15 if hard else 0.85
	var window_mult := 0.8 if hard else 1.25
	var out := tune.duplicate(true)
	out["SHOWER_EVERY_SEC"] = float(tune["SHOWER_EVERY_SEC"]) / preview_mult
	out["SHOWER_TELEGRAPH_SEC"] = maxf(0.35, float(tune["SHOWER_TELEGRAPH_SEC"]) * window_mult)
	out["BOT_WINDOW_SEC"] = maxf(0.35, float(tune["BOT_WINDOW_SEC"]) * window_mult)
	out["RAMP_STEP_OFFSET"] = 1 if hard else 0
	# §G5.4-Beatability: goldene Karotten spawnen auf Schwer/Endlos doppelt so oft.
	out["GOLD_CHANCE"] = float(tune["GOLD_CHANCE"]) * (2.0 if hard else 1.0)
	out["MAX_SPEED"] = INF if mode == "endless" else float(tune["MAX_SPEED"])
	out["WORMHOLE_CHANCE"] = float(tune["WORMHOLE_CHANCE"]) * (0.5 if mode == "endless" else 1.0)
	out["ENDLESS"] = mode == "endless"
	return out


## Aus ctx.params abgeleitete Laufzeitzahlen (Modifier-Events) anwenden.
static func with_runtime(tune: Dictionary, runtime := {}) -> Dictionary:
	var speed := _positive(float(runtime.get("speedMult", 1.0)))
	var rate := _positive(float(runtime.get("coinRate", 1.0)))
	var out := tune.duplicate(true)
	out["SPEED_MULT"] = speed
	out["SCORE_MULT"] = _positive(float(runtime.get("scoreMult", 1.0)))
	out["COIN_RATE"] = rate
	out["HITBOX_SCALE"] = (
		float(tune["HITBOX_SCALE"]) * _positive(float(runtime.get("hitboxMult", 1.0)))
	)
	out["STAR_CHANCE"] = minf(0.95, float(tune["STAR_CHANCE"]) * rate)
	out["GOLD_CHANCE"] = minf(0.2, float(tune["GOLD_CHANCE"]) * rate)
	out["GOOBY_SCALE"] = _positive(float(runtime.get("goobyScale", 1.0)))
	return out


static func _positive(v: float) -> float:
	return v if is_finite(v) and v > 0.0 else 1.0


## Sternenhüpfer läuft ohnehin bis zum Crash — Endlos endet an demselben Treffer.
static func endless_ended(hit_result: Dictionary) -> bool:
	return bool(hit_result.get("ended", false))


## Steiggeschwindigkeit nach `elapsed` Sekunden (+5 % je 10 s, gedeckelt).
static func speed_at(elapsed: float, tune := HOPPER) -> float:
	var steps := (
		int(floor(maxf(0.0, elapsed) / float(tune["SPEED_RAMP_EVERY_SEC"])))
		+ int(tune.get("RAMP_STEP_OFFSET", 0))
	)
	var raw := float(tune["BASE_SPEED"]) * pow(1.0 + float(tune["SPEED_RAMP_PCT"]), steps)
	return minf(float(tune["MAX_SPEED"]), raw) * float(tune.get("SPEED_MULT", 1.0))


## Schwierigkeitsrampe 0..1 (steuert Reihenabstand + Doppelblock-Chance).
static func difficulty_at(elapsed: float, tune := HOPPER) -> float:
	return clampf(elapsed / float(tune["DIFFICULTY_FULL_SEC"]), 0.0, 1.0)


## Lineare Rampe für {start,end}-Knöpfe.
static func ramp(knob: Dictionary, d: float) -> float:
	return float(knob["start"]) + (float(knob["end"]) - float(knob["start"])) * d


## Meter bis zur nächsten Meteorreihe bei dieser Schwierigkeit.
static func row_gap_at(difficulty: float, tune := HOPPER) -> float:
	return ramp(tune["ROW_GAP_M"], difficulty)


## Rundenpunkte: floor(Meter / 10) + Aufsammlerpunkte.
static func hopper_score(distance_m: float, pickup_points: int, tune := HOPPER) -> int:
	var raw := maxi(0, int(floor(distance_m / float(tune["DISTANCE_PER_POINT_M"]))) + pickup_points)
	return int(round(raw * float(tune.get("SCORE_MULT", 1.0))))


## Bahn nach einem Tippen auf die linke/rechte Bildschirmhälfte (1 Bahn).
static func lane_after_tap(lane: int, side: String, tune := HOPPER) -> int:
	return clampi(lane + (-1 if side == "left" else 1), 0, int(tune["LANES"]) - 1)


## Bahn nach einem Wisch (2 Bahnen, gedeckelt).
static func lane_after_swipe(lane: int, dir: String, tune := HOPPER) -> int:
	return clampi(lane + (-2 if dir == "left" else 2), 0, int(tune["LANES"]) - 1)


## Eine normalisierte Geste auflösen (mit Wisch→Tipp-Unterdrückung).
static func lane_after_gesture(
	lane: int, gesture: Dictionary, suppress_tap := false, tune := HOPPER
) -> int:
	if str(gesture["kind"]) == "tap":
		return lane if suppress_tap else lane_after_tap(lane, str(gesture["side"]), tune)
	return lane_after_swipe(lane, str(gesture["dir"]), tune)


## Trefferprüfung für einen Frame (Meteor-Hitbox auf 70 % geschrumpft).
static func hits_meteor(player: Dictionary, meteor: Dictionary, tune := HOPPER) -> bool:
	if int(player["lane"]) != int(meteor["lane"]):
		return false
	var reach := (
		float(tune["HITBOX_SCALE"]) * (float(tune["PLAYER_HALF_M"]) + float(tune["METEOR_HALF_M"]))
	)
	return absf(float(meteor["m"]) - float(player["m"])) <= reach


## Überstrichene Trefferprüfung (Anti-Tunneling bei niedriger Framerate).
static func sweep_hits_meteor(
	player: Dictionary, meteor: Dictionary, dm: float, tune := HOPPER
) -> bool:
	var steps := maxi(1, int(ceil(absf(dm) / float(tune["MAX_SWEEP_STEP_M"]))))
	for i in range(1, steps + 1):
		var probe := {"lane": int(player["lane"]), "m": float(player["m"]) + dm * i / steps}
		if hits_meteor(probe, meteor, tune):
			return true
	return false


## Aufsammler-Wurf pro Reihe: EIN rng-Zug → goldene Karotte, Stern oder nichts.
static func roll_pickup(rng: Callable, tune := HOPPER) -> Dictionary:
	var r := float(rng.call())
	if r < float(tune["GOLD_CHANCE"]):
		return {"kind": "gold", "points": int(tune["GOLD_POINTS"])}
	if r < float(tune["GOLD_CHANCE"]) + float(tune["STAR_CHANCE"]):
		return {"kind": "star", "points": int(tune["STAR_POINTS"])}
	return {}


## Das EINE Schild spawnt, sobald der Score 60 erreicht.
static func should_spawn_shield(score: int, already_spawned: bool, tune := HOPPER) -> bool:
	return not already_spawned and score >= int(tune["SHIELD_SCORE"])


## Seltenes Wurmloch-Tor: frühestens nach 18 s, höchstens einmal pro Lauf.
static func should_spawn_wormhole(
	rng: Callable, elapsed: float, already_spawned: bool, active: bool, tune := HOPPER
) -> bool:
	if already_spawned or active or elapsed < float(tune["WORMHOLE_FIRST_SEC"]):
		return false
	return float(rng.call()) < float(tune["WORMHOLE_CHANCE"])


## Framerate-unabhängige +1 an jeder 0.2-s-Grenze des Zwei-Sekunden-Tunnels.
static func wormhole_awards(previous_sec: float, next_sec: float, tune := HOPPER) -> int:
	var span := float(tune["WORMHOLE_SEC"])
	var tick := float(tune["WORMHOLE_TICK_SEC"])
	var a := clampf(previous_sec, 0.0, span)
	var b := clampf(next_sec, 0.0, span)
	return maxi(0, int(floor((b + 1e-9) / tick)) - int(floor((a + 1e-9) / tick)))


## Bahnen eines angekündigten Meteorschauers: 2 Gefahr, 1 sicher.
static func pick_shower_lanes(rng: Callable, tune := HOPPER) -> Dictionary:
	var lanes := int(tune["LANES"])
	var safe := mini(lanes - 1, int(floor(float(rng.call()) * lanes)))
	var danger: Array[int] = []
	for i in lanes:
		if i != safe:
			danger.append(i)
	return {"safe": safe, "danger": danger}


## Treffer auflösen: ein Treffer beendet, ein Schild rettet genau einmal.
static func resolve_hit(shielded: bool) -> Dictionary:
	return {"ended": not shielded, "shielded": false}


## Deterministischer Zertifizierungslauf (Web-identischer Release-Bot).
static func simulate_autoplay(seed_value: int, mode := "normal", runtime := {}) -> Dictionary:
	var tune := with_runtime(apply_difficulty(HOPPER, mode), runtime)
	var rng := GoobyRng.new(seed_value)
	var full_duration := 105.0 if bool(tune["ENDLESS"]) else float(tune["DURATION_SEC"])
	# Harte Reihen kürzen manche Seeds statt jedem Seed 75 s zu schenken.
	# JS: (Math.imul(seed, 2654435761) >>> 0) / 2^32 — Multiplikation mod 2^32.
	var survival_roll := float((seed_value * 2654435761) & 0xFFFFFFFF) / 4294967296.0
	var hard := mode == "hard" or mode == "endless"
	var duration := full_duration * 0.68 if hard and survival_roll <= 0.45 else full_duration
	var distance := 0.0
	var pickups := 0
	var next_row := 0.0
	var collection_skill := 0.94
	if mode == "easy":
		collection_skill = 0.98
	elif hard:
		collection_skill = 0.88
	var stream := func() -> float: return rng.next()
	var elapsed := 0.0
	while elapsed < duration:
		distance += speed_at(elapsed, tune) * 0.1
		if distance >= next_row:
			var roll := roll_pickup(stream, tune)
			if not roll.is_empty() and rng.next() < collection_skill:
				pickups += int(roll["points"])
			next_row += row_gap_at(difficulty_at(elapsed, tune), tune)
		elapsed += 0.1
	return {
		"seed": seed_value,
		"mode": mode,
		"score": hopper_score(distance, pickups, tune),
		"distance": distance,
		"pickups": pickups,
	}
