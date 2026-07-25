class_name TrampolineLogic
extends RefCounted
## Trampolin-Tricks (trampoline) — PURE Logik, zahlengleicher Port von
## GOOBY/src/minigames/games/trampoline.logic.js (§C6.1 #12). Seitenansicht:
## Tippen im schrumpfenden Landefenster = Boost, Wischen in der Luft =
## Salto/Drehung/Twist (Punkte × Höhenfaktor 1–3), Fenster verpasst = Po-
## Landung und die Höhe fällt zurück. 60 s, Score = nur Trickpunkte.
## Coin-Zeile: /5, 4..26, Ziel 105.

## Bindende §C6.1-#12-Zahlen + G10-Tuning (Sprungphysik, Feel-Knöpfe).
const TRAMP := {
	"DURATION_SEC": 60.0,
	"TIER2_APEX": 2.1,
	"TIER3_APEX": 3.3,
	"WINDOW_BASE_SEC": 0.3,
	"WINDOW_SHRINK_PER_WU": 0.045,
	"WINDOW_MIN_SEC": 0.1,
	"JUDGE_ZONE_SEC": 0.5,
	"GRAVITY": 9.0,
	"BASE_VY": 5.0,
	"BOOST_MULT": 1.16,
	"BOOST_ADD": 0.35,
	"MAX_VY": 8.6,
	"DECAY_MULT": 0.94,
	"MIN_VY": 4.2,
	"TRICK_MIN_AIR_SEC": 0.35,
	"COMBO_TRICKS": 3,
	"COMBO_FLIP_POINTS": 12,
	"BUTT_STAGGER_SEC": 1.1,
	"ENDLESS": false,
	"ENDLESS_FAILURE_LIMIT": 3,
}

## Trick-Basispunkte je Wisch-Richtung (links/rechts/hoch).
const TRICK_PTS := {"flip": 2, "spin": 2, "twist": 3}

## GP3-Juice — nur Optik.
const TRAMP_JUICE := {"SHOCKWAVE_SEC": 0.45, "SHOCKWAVE_SCALE": 2.6}


## §G5 Physik-/Skill-Difficulty; die Toleranz fällt nie unter 55 % von Mittel.
static func apply_difficulty(tune: Dictionary = TRAMP, mode := "normal") -> Dictionary:
	if mode == "normal" or not ["easy", "hard", "endless"].has(mode):
		return tune
	var hard := mode == "hard" or mode == "endless"
	var tolerance := 0.8 if hard else 1.25
	var out := tune.duplicate()
	out["WINDOW_BASE_SEC"] = maxf(
		float(tune["WINDOW_BASE_SEC"]) * 0.55, float(tune["WINDOW_BASE_SEC"]) * tolerance
	)
	out["WINDOW_MIN_SEC"] = maxf(
		float(tune["WINDOW_MIN_SEC"]) * 0.55, float(tune["WINDOW_MIN_SEC"]) * tolerance
	)
	out["JUDGE_ZONE_SEC"] = maxf(0.35, float(tune["JUDGE_ZONE_SEC"]) * tolerance)
	out["ENDLESS"] = mode == "endless"
	return out


## Den einfachen Trefferfenster-Multiplikator aus ctx.params anwenden.
static func with_hitbox(tune: Dictionary, hitbox_mult := 1.0) -> Dictionary:
	var mult := hitbox_mult if is_finite(hitbox_mult) and hitbox_mult > 0.0 else 1.0
	if is_equal_approx(mult, 1.0):
		return tune
	var out := tune.duplicate()
	out["WINDOW_BASE_SEC"] = float(tune["WINDOW_BASE_SEC"]) * mult
	out["WINDOW_MIN_SEC"] = float(tune["WINDOW_MIN_SEC"]) * mult
	out["JUDGE_ZONE_SEC"] = float(tune["JUDGE_ZONE_SEC"]) * mult
	return out


## Landefensterlänge für einen Sprung-Scheitelpunkt (schrumpft mit der Höhe).
static func window_sec_for(apex_h: float, tune: Dictionary = TRAMP) -> float:
	return maxf(
		float(tune["WINDOW_MIN_SEC"]),
		float(tune["WINDOW_BASE_SEC"]) - float(tune["WINDOW_SHRINK_PER_WU"]) * apex_h
	)


## Höhenfaktor ×1–3 für Trickpunkte.
static func height_multiplier(apex_h: float) -> int:
	if apex_h >= float(TRAMP["TIER3_APEX"]):
		return 3
	if apex_h >= float(TRAMP["TIER2_APEX"]):
		return 2
	return 1


## Scheitelhöhe zu einer Absprunggeschwindigkeit: v² / 2g.
static func apex_for(vy: float, g := 9.0) -> float:
	return (vy * vy) / (2.0 * g)


## Volle Flugzeit eines Sprungs (hoch + runter): 2v/g.
static func air_time_for(vy: float, g := 9.0) -> float:
	return (2.0 * vy) / g


## Zeit bis zum nächsten Mattenkontakt, mitten in der Luft.
static func time_to_impact(h: float, vy: float, g := 9.0) -> float:
	return (vy + sqrt(vy * vy + 2.0 * g * maxf(0.0, h))) / g


## Tap im Fallen bewerten: im Fenster Boost, in der Zone Po-Landung, sonst Trick.
static func classify_landing_tap(tti: float, apex_h: float, tune: Dictionary = TRAMP) -> String:
	if tti <= window_sec_for(apex_h, tune):
		return "boost"
	if tti <= float(tune["JUDGE_ZONE_SEC"]):
		return "butt"
	return "ignore"


## Absprunggeschwindigkeit des nächsten Sprungs (Boost/Zerfall/Reset).
static func next_bounce_vy(vy: float, action: String, tune: Dictionary = TRAMP) -> float:
	if action == "boost":
		return minf(
			float(tune["MAX_VY"]), vy * float(tune["BOOST_MULT"]) + float(tune["BOOST_ADD"])
		)
	if action == "butt":
		return float(tune["BASE_VY"])
	return maxf(float(tune["MIN_VY"]), vy * float(tune["DECAY_MULT"]))


## Punkte für einen Trick: Basispunkte × Höhenfaktor.
static func trick_points(kind: String, mult: int) -> int:
	return int(TRICK_PTS[kind]) * mult


## Darf ein Trick starten? Nur in der Luft und nicht kurz vor der Landung.
static func can_trick(airborne: bool, tti: float, tricking: bool, tune: Dictionary = TRAMP) -> bool:
	return airborne and not tricking and tti > float(tune["TRICK_MIN_AIR_SEC"])


## Summe der Trickpunkte = Rundenscore.
static func trampoline_score(points: Array) -> int:
	var total := 0
	for p in points:
		total += int(p)
	return total


## Frische Trick-Kette für einen Flug.
static func create_trick_chain() -> Dictionary:
	return {"seen": [], "awarded": false}


## Trick in den aktuellen Flug buchen; erst Salto+Drehung+Twist zahlt +12.
static func record_trick(chain: Dictionary, kind: String) -> Dictionary:
	var seen: Array = chain["seen"]
	if not seen.has(kind):
		seen.append(kind)
	var triggered := not bool(chain["awarded"]) and seen.size() >= int(TRAMP["COMBO_TRICKS"])
	if triggered:
		chain["awarded"] = true
	return {"triggered": triggered, "bonus": int(TRAMP["COMBO_FLIP_POINTS"]) if triggered else 0}


## Eine scharfgestellte Landung genau einmal verbrauchen.
static func consume_landing_action(armed: String) -> Dictionary:
	return {"action": armed if armed != "" else "none", "armed": ""}


## Nur die fallende Flanke, die die Trampolin-Ebene kreuzt.
static func crossed_mat(previous_h: float, next_h: float, next_vy: float) -> bool:
	return previous_h > 0.0 and next_h <= 0.0 and next_vy < 0.0


## §G5.4 Endlos endet mit der dritten misslungenen Landung.
static func endless_should_end(failed_landings: int, tune: Dictionary = TRAMP) -> bool:
	return bool(tune["ENDLESS"]) and failed_landings >= int(tune["ENDLESS_FAILURE_LIMIT"])


## Deterministische Bot-Zertifizierung (Landetoleranz treibt die Trefferquote).
static func simulate_autoplay(seed_value := 1, mode := "normal") -> Dictionary:
	var tune := apply_difficulty(TRAMP, mode)
	var rng := GoobyRng.new(seed_value)
	var duration := 90.0 if bool(tune["ENDLESS"]) else float(tune["DURATION_SEC"])
	var t := 0.0
	var vy := float(tune["BASE_VY"])
	var score := 0
	var failures := 0
	while t < duration and failures < int(tune["ENDLESS_FAILURE_LIMIT"]):
		var apex := apex_for(vy, float(tune["GRAVITY"]))
		var win := window_sec_for(apex, tune)
		var success := rng.next() < minf(0.96, 0.7 + win * 0.8)
		var mult := height_multiplier(apex)
		if success:
			score += trick_points("twist", mult) + trick_points("flip", mult)
			if rng.next() < 0.55:
				score += int(tune["COMBO_FLIP_POINTS"])
			vy = next_bounce_vy(vy, "boost", tune)
		else:
			failures += 1
			vy = next_bounce_vy(vy, "butt", tune)
		t += air_time_for(vy, float(tune["GRAVITY"]))
		if not success:
			t += float(tune["BUTT_STAGGER_SEC"])
	return {"seed": seed_value, "mode": mode, "score": score, "failures": failures}
