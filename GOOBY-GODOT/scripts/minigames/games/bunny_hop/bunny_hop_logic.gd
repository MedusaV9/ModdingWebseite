class_name BunnyHopLogic
extends RefCounted
## Hasenhüpfer (bunnyHop) — PURE Logik, zahlengleicher Port von
## GOOBY/src/minigames/games/bunnyHop.logic.js (§C6.1 #3). Tippen = Hüpfen,
## Score = passierte Tore, Tempo +2 % je Tor, Hitbox 70 % der Optik, die
## Lücke wird alle 10 Tore enger. Ab Sekunde 6 kommt Wind: erst Warnung,
## dann ein 0,4-Bahnen-Schubs — währenddessen zählen Tore doppelt.
## Coin-Zeile: /2, 3..25, Ziel 45.

## Bindende §C6.1-#3-Zahlen + G8-Tuning (Weltgeometrie, Hüpf-Gefühl).
const HOP := {
	"SPEED_RAMP_PCT": 0.02,
	"GAP_NARROW_EVERY_GATES": 10,
	"HITBOX_SCALE": 0.7,
	"BASE_SPEED": 1.55,
	"PILLAR_SPACING_X": 2.7,
	"GAP_BASE": 2.15,
	"GAP_NARROW_STEP": 0.16,
	"GAP_MIN": 1.5,
	"HOP_VY": 3.1,
	"GRAVITY": -8.5,
	"FLOOR_Y": -3.1,
	"CEILING_Y": 3.9,
	"BODY_HALF_W": 0.34,
	"BODY_HALF_H": 0.42,
	"PILLAR_HALF_W": 0.34,
	"GAP_MAX_CLIMB": 1.4,
	"GAP_MAX_DIVE": 1.9,
	"GUST_FIRST_SEC": 6.0,
	"GUST_EVERY_SEC": 10.0,
	"GUST_TELEGRAPH_SEC": 1.5,
	"GUST_DURATION_SEC": 2.0,
	"GUST_SHIFT_LANES": 0.4,
	"LANE_HEIGHT": 1.0,
	"TOLERANCE_MULT": 1.0,
	"SPEED_MULT": 1.0,
	"SCORE_MULT": 1.0,
	"COIN_RATE": 1.0,
	"COIN_SPAWN_CHANCE": 0.32,
	"RENDER_SCALE_MULT": 1.0,
	"ENDLESS": false,
}

## V4/G71 §G5.3 Physik-/Skill-Zeile.
const HOP_DIFFICULTY := {
	"easy": {"tolerance": 1.25, "endless": false},
	"normal": {"tolerance": 1.0, "endless": false},
	"hard": {"tolerance": 0.8, "endless": false},
	"endless": {"tolerance": 0.8, "endless": true},
}

## GP3-Juice — nur Optik/Feier, nie Gameplay-Mathematik.
const HOP_JUICE := {"HOP_PUFF_COUNT": 2, "COIN_WOBBLE_RAD": 0.55, "COIN_WOBBLE_HZ": 2.2}


## §G5.3 Difficulty; `normal` liefert die Basistabelle unverändert.
static func apply_difficulty(tune: Dictionary = HOP, mode := "normal") -> Dictionary:
	var id := mode if HOP_DIFFICULTY.has(mode) else "normal"
	if id == "normal":
		return tune
	var row: Dictionary = HOP_DIFFICULTY[id]
	var tolerance := maxf(0.55, float(row["tolerance"]))
	var out := tune.duplicate()
	out["GAP_BASE"] = float(tune["GAP_BASE"]) * tolerance
	out["GAP_NARROW_STEP"] = float(tune["GAP_NARROW_STEP"]) * tolerance
	out["GAP_MIN"] = float(tune["GAP_MIN"]) * tolerance
	out["TOLERANCE_MULT"] = tolerance
	out["ENDLESS"] = bool(row["endless"])
	# §G5.4: Endlos hat ab dem Auftakt Wind und deckelt Tore nie.
	out["GUST_FIRST_SEC"] = (
		float(tune["GUST_TELEGRAPH_SEC"]) if bool(row["endless"]) else float(tune["GUST_FIRST_SEC"])
	)
	out["MODE"] = id
	return out


## Scrolltempo nach `gates` Toren: +2 % je Tor, kumulativ.
static func speed_at_gate(gates: int, tune: Dictionary = HOP) -> float:
	return (
		float(tune["BASE_SPEED"]) * pow(1.0 + float(tune["SPEED_RAMP_PCT"]), float(maxi(0, gates)))
	)


## Lückenhöhe nach `gates` Toren: alle 10 Tore eine Stufe enger, mit Boden.
static func gap_at_gate(gates: int, tune: Dictionary = HOP) -> float:
	var steps := floorf(float(maxi(0, gates)) / float(tune["GAP_NARROW_EVERY_GATES"]))
	var narrowed := float(tune["GAP_BASE"]) - float(tune["GAP_NARROW_STEP"]) * steps
	return maxf(float(tune["GAP_MIN"]), narrowed)


## Verzeihender Collider: 70 % der optischen Halb-Ausdehnung.
static func forgiving_half(visual_half: float, tune: Dictionary = HOP) -> float:
	return visual_half * float(tune["HITBOX_SCALE"])


## Ein Physikschritt (semi-implizites Euler), an der Decke geklemmt.
static func step_physics(state: Dictionary, dt: float, tune: Dictionary = HOP) -> Dictionary:
	var vy := float(state["vy"]) + float(tune["GRAVITY"]) * dt
	var y := float(state["y"]) + vy * dt
	if y > float(tune["CEILING_Y"]):
		return {"y": float(tune["CEILING_Y"]), "vy": 0.0}
	return {"y": y, "vy": vy}


## AABB-Kollision Gooby (verzeihende Hitbox) gegen ein Säulenpaar.
static func collides(gooby: Dictionary, pillar: Dictionary, tune: Dictionary = HOP) -> bool:
	var half_w := forgiving_half(float(tune["BODY_HALF_W"]), tune)
	var half_h := forgiving_half(float(tune["BODY_HALF_H"]), tune)
	if float(gooby["y"]) - half_h <= float(tune["FLOOR_Y"]):
		return true
	var pillar_half := float(tune["PILLAR_HALF_W"])
	if absf(float(gooby["x"]) - float(pillar["x"])) > half_w + pillar_half:
		return false
	var gap_top := float(pillar["gapCenterY"]) + float(pillar["gapHeight"]) / 2.0
	var gap_bottom := float(pillar["gapCenterY"]) - float(pillar["gapHeight"]) / 2.0
	return float(gooby["y"]) + half_h > gap_top or float(gooby["y"]) - half_h < gap_bottom


## Lückenmitte der nächsten Säule — im Feld UND in Steig-/Sink-Reichweite.
static func roll_gap_center(
	rng: GoobyRng, gap_height: float, prev_center := INF, tune: Dictionary = HOP
) -> float:
	var margin := 0.45
	var lo := float(tune["FLOOR_Y"]) + margin + gap_height / 2.0
	var hi := float(tune["CEILING_Y"]) - margin - gap_height / 2.0
	if is_finite(prev_center):
		lo = maxf(lo, prev_center - float(tune["GAP_MAX_DIVE"]))
		hi = minf(hi, prev_center + float(tune["GAP_MAX_CLIMB"]))
	return lo + rng.next() * (hi - lo)


## Windfahrplan; Richtungen wechseln, damit kein Lauf zu einer Kante driftet.
static func gust_phase_at(elapsed: float, tune: Dictionary = HOP) -> Dictionary:
	var local := elapsed - float(tune["GUST_FIRST_SEC"])
	var cycle := local + float(tune["GUST_TELEGRAPH_SEC"])
	if cycle < 0.0:
		return {"phase": "none", "index": -1, "direction": 1}
	var index := int(floor(cycle / float(tune["GUST_EVERY_SEC"])))
	var start := float(tune["GUST_FIRST_SEC"]) + float(index) * float(tune["GUST_EVERY_SEC"])
	var direction := 1 if index % 2 == 0 else -1
	if elapsed >= start - float(tune["GUST_TELEGRAPH_SEC"]) and elapsed < start:
		return {"phase": "telegraph", "index": index, "direction": direction}
	if elapsed >= start and elapsed < start + float(tune["GUST_DURATION_SEC"]):
		return {"phase": "gust", "index": index, "direction": direction}
	return {"phase": "none", "index": index, "direction": direction}


## Den einen Windschubs anwenden — nie in den sofortigen Tod hinein.
static func apply_gust_shift(y: float, direction: int, tune: Dictionary = HOP) -> float:
	var half_h := forgiving_half(float(tune["BODY_HALF_H"]), tune)
	var shifted := (
		y + float(direction) * float(tune["GUST_SHIFT_LANES"]) * float(tune["LANE_HEIGHT"])
	)
	return maxf(
		float(tune["FLOOR_Y"]) + half_h + 0.01, minf(float(tune["CEILING_Y"]) - half_h, shifted)
	)


## Tore zählen doppelt, solange der Windstoß läuft (§C10.2).
static func gate_points(gusting: bool) -> int:
	return 2 if gusting else 1


## Münzregen würfelt die Pickup-Dichte, nicht die Auszahlung (§C-SYS4.2).
static func coin_spawns(roll: float, tune: Dictionary = HOP) -> bool:
	return roll < minf(1.0, float(tune["COIN_SPAWN_CHANCE"]) * float(tune["COIN_RATE"]))


## Endstand mit dem optionalen Turbo-Score-Multiplikator.
static func final_hop_score(score: int, tune: Dictionary = HOP) -> int:
	return maxi(0, int(round(float(score) * float(tune.get("SCORE_MULT", 1.0)))))


## True, wenn dieses Tor die NÄCHSTE Lücke wirklich enger gemacht hat.
static func gap_narrows_at_gate(gates_passed: int, tune: Dictionary = HOP) -> bool:
	if gates_passed <= 0 or gates_passed % int(tune["GAP_NARROW_EVERY_GATES"]) != 0:
		return false
	return gap_at_gate(gates_passed, tune) < gap_at_gate(gates_passed - 1, tune)


## Deterministische Bot-Zertifizierung (Aufmerksamkeitsdeckel wie im Web).
static func simulate_autoplay(seed_value := 1, mode := "normal") -> Dictionary:
	var tune := apply_difficulty(HOP, mode)
	var rng := GoobyRng.new(seed_value)
	var base := 55
	if mode == "easy":
		base = 62
	elif mode == "hard" or mode == "endless":
		base = 48
	var gates := base + int(floor(rng.next() * 10.0))
	var score := 0
	for i in gates:
		var at := (float(i) * float(tune["PILLAR_SPACING_X"])) / speed_at_gate(i, tune)
		var gust := gust_phase_at(at, tune)
		score += gate_points(gust["phase"] == "gust")
		if coin_spawns(rng.next(), tune) and rng.next() < 0.86:
			score += 1
	return {
		"seed": seed_value,
		"mode": mode,
		"score": final_hop_score(score, tune),
		"gates": gates,
	}
