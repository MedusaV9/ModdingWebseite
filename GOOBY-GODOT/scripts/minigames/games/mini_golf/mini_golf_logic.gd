class_name MiniGolfLogic
extends RefCounted
## Pure Minigolf-Physik + Wertung — zahlengleicher Port von
## GOOBY/src/minigames/games/miniGolf.logic.js (PLAN2 §C1.2 #6).
## Reibung 0.985 pro 60-fps-Frame, Bandenabpraller, rhythmisches Windmühlentor,
## Kuppel- und Nougat-Hindernisse, Loch-Einfang nur langsam genug.
## Die Bahn-Erzeugung/Geometrie liegt in `mini_golf_course.gd` (gdlint-Limit
## von 20 öffentlichen Methoden pro Klasse).

const Course := preload("res://scripts/minigames/games/mini_golf/mini_golf_course.gd")

## Bindende §C1.2-#6-Zahlen (Längen in Zelleinheiten = m).
const GOLF := {
	"HOLE_COUNT": 6,
	"CELL_M": 1.0,
	"BALL_R": 0.08,
	"RAIL": 0.055,
	"FRICTION_PER_FRAME": 0.985,
	"ROLL_DECEL": 0.22,
	"STOP_SPEED": 0.01,
	"MAX_POWER": 6.5,
	"MAX_DRAG_PX": 150.0,
	"MIN_MAX_DRAG_PX": 96.0,
	"MAX_DRAG_VIEWPORT_RATIO": 0.38,
	"HOLE_R": 0.13,
	"CAPTURE_SPEED": 2.8,
	"MAX_STROKES": 10,
	"WALL_RESTITUTION": 0.82,
	"BUMP_R": 0.19,
	"BUMP_RESTITUTION": 0.95,
	"WINDMILL_RPS": 0.12,
	"WINDMILL_BLOCK_FRAC": 0.45,
	"RAMP_ACCEL": 2.6,
	"RAMP_H": 0.1,
	"SCORE_ACE": 30,
	"SCORE_PAR": 20,
	"SCORE_BOGEY": 12,
	"SCORE_OTHER": 6,
	"BONUS_HOLE_COUNT": 7,
	"NOUGAT_R": 0.18,
	"NOUGAT_AMPLITUDE": 0.24,
	"NOUGAT_RESTITUTION": 0.88,
	"PAR_BONUS": 0,
	"ENDLESS": false,
	"ENDLESS_OVER_PAR_LIMIT": 3,
}

## V4/GAME-POLISH-4 Präsentations-Tuning (nur Optik, keine Physik).
const GOLF_JUICE := {
	"RING_LIFE_SEC": 0.55,
	"RING_SCALE_SINK": 3.2,
	"RING_SCALE_ACE": 5.0,
	"FLAG_POP_SCALE": 1.45,
	"FLAG_POP_SEC": 0.5,
	"PUTT_SQUASH": 0.62,
	"PUTT_SQUASH_SEC": 0.22,
	"BANK_SPARKLES": 3,
	"ACE_SPARKLES": 14,
}


## §G5 Physik/Skill-Difficulty; Schwer bleibt über 55 % der Mittel-Toleranz.
static func apply_difficulty(tune := GOLF, mode := "normal") -> Dictionary:
	if mode == "normal" or not ["easy", "hard", "endless"].has(mode):
		return tune
	var hard := mode == "hard" or mode == "endless"
	var tolerance := 0.8 if hard else 1.25
	var out := tune.duplicate()
	out["HOLE_R"] = maxf(float(tune["HOLE_R"]) * 0.55, float(tune["HOLE_R"]) * tolerance)
	out["CAPTURE_SPEED"] = maxf(
		float(tune["CAPTURE_SPEED"]) * 0.55, float(tune["CAPTURE_SPEED"]) * tolerance
	)
	out["PAR_BONUS"] = 0 if hard else 1
	out["ENDLESS"] = mode == "endless"
	out["MODE"] = mode
	return out


## Endlos: 3 Löcher über Par beenden den Lauf.
static func create_endless_state(limit := int(GOLF["ENDLESS_OVER_PAR_LIMIT"])) -> Dictionary:
	return {"overPar": 0, "limit": limit, "ended": false}


## Ein abgeschlossenes Loch verbuchen; true = Endlos-Lauf ist vorbei.
static func record_hole(state: Dictionary, strokes: int, par: int) -> bool:
	if strokes > par and not bool(state["ended"]):
		state["overPar"] = int(state["overPar"]) + 1
	state["ended"] = int(state["overPar"]) >= int(state["limit"])
	return bool(state["ended"])


## Loch-Wertung: Ass +30, ≤ Par +20, Par+1 +12, sonst +6.
static func hole_score(strokes: int, par: int, tune := GOLF) -> int:
	if strokes == 1:
		return int(tune["SCORE_ACE"])
	if strokes <= par:
		return int(tune["SCORE_PAR"])
	if strokes == par + 1:
		return int(tune["SCORE_BOGEY"])
	return int(tune["SCORE_OTHER"])


## Reibungsfaktor über dt Sekunden (×0.985 pro 60-fps-Frame).
static func friction_factor(dt: float) -> float:
	return pow(float(GOLF["FRICTION_PER_FRAME"]), dt * 60.0)


## Ein Reibungsschritt: Exponentialabfall + Rollwiderstand, bei 0 abgefangen.
static func roll_speed(speed: float, dt: float) -> float:
	return maxf(0.0, speed * friction_factor(dt) - float(GOLF["ROLL_DECEL"]) * dt)


## Rollweite (m) aus einer Anfangsgeschwindigkeit (60-fps-Integration).
static func roll_distance(v0: float) -> float:
	var v := v0
	var d := 0.0
	var h := 1.0 / 60.0
	while v > float(GOLF["STOP_SPEED"]) and d < 100.0:
		d += v * h
		v = roll_speed(v, h)
	return d


## Sekunden, bis ein Putt mit v0 `dist` Meter zurückgelegt hat (INF = bleibt liegen).
static func roll_time_to_distance(v0: float, dist: float) -> float:
	var v := v0
	var d := 0.0
	var t := 0.0
	var h := 1.0 / 60.0
	while v > float(GOLF["STOP_SPEED"]) and t < 30.0:
		d += v * h
		t += h
		if d >= dist:
			return t
		v = roll_speed(v, h)
	return INF


## Anfangsgeschwindigkeit für eine Zielweite (Binärsuche über roll_distance).
static func power_for_distance(dist: float) -> float:
	var lo := 0.15
	var hi := float(GOLF["MAX_POWER"])
	if roll_distance(hi) < dist:
		return hi
	for i in 28:
		var mid := (lo + hi) / 2.0
		if roll_distance(mid) < dist:
			lo = mid
		else:
			hi = mid
	return (lo + hi) / 2.0


## Volle Zugkraft-Distanz (px) für ein Viewport — kleine Schirme bleiben spielbar.
static func max_drag_px_for_viewport(width: float, height: float, tune := GOLF) -> float:
	if not (width > 0.0) or not (height > 0.0):
		return float(tune["MAX_DRAG_PX"])
	return minf(
		float(tune["MAX_DRAG_PX"]),
		maxf(
			float(tune["MIN_MAX_DRAG_PX"]),
			minf(width, height) * float(tune["MAX_DRAG_VIEWPORT_RATIO"])
		)
	)


## Zuglänge (px) → Putt-Kraft (m/s), gedeckelt.
static func power_from_drag(drag_px: float, width: float, height: float) -> float:
	var max_drag := max_drag_px_for_viewport(width, height)
	return minf(
		float(GOLF["MAX_POWER"]), maxf(0.0, drag_px) * (float(GOLF["MAX_POWER"]) / max_drag)
	)


## Achsparallele Bande: Normalkomponente mit WALL_RESTITUTION spiegeln.
static func reflect(v: Dictionary, nx: float, nz: float) -> Dictionary:
	var dot := float(v["vx"]) * nx + float(v["vz"]) * nz
	var k := (1.0 + float(GOLF["WALL_RESTITUTION"])) * dot
	return {"vx": float(v["vx"]) - k * nx, "vz": float(v["vz"]) - k * nz}


## Rhythmisches Windmühlentor: 4 Flügel, 45 % jeder Viertelumdrehung blockiert.
static func windmill_blocked(theta: float) -> bool:
	var period := PI / 2.0
	var phase := fposmod(theta, period)
	var d := minf(phase, period - phase)
	return d < (period * float(GOLF["WINDMILL_BLOCK_FRAC"])) / 2.0


## Loch-Einfang: nah genug UND langsam genug (schnelle Bälle springen drüber).
static func is_captured(dist: float, speed: float, tune := GOLF) -> bool:
	return dist < float(tune["HOLE_R"]) and speed < float(tune["CAPTURE_SPEED"])


## Einen Frame simulieren; mutiert `ball` und liefert die Ereignisse
## ('bank'|'windmill'|'bump'|'nougat'|'holed') dieses Frames.
static func step_ball(
	hole: Dictionary, ball: Dictionary, dt: float, theta: float, tune := GOLF
) -> Array[String]:
	var events: Array[String] = []
	if bool(ball.get("done", false)):
		return events

	if Course.on_ramp(hole, float(ball["x"]), float(ball["z"])):
		var dir: Array = (hole["ramp"] as Dictionary)["dir"]
		ball["vx"] = float(ball["vx"]) - float(dir[0]) * float(GOLF["RAMP_ACCEL"]) * dt
		ball["vz"] = float(ball["vz"]) - float(dir[1]) * float(GOLF["RAMP_ACCEL"]) * dt

	var speed := _hypot(float(ball["vx"]), float(ball["vz"]))
	if speed > 0.0:
		var ns := roll_speed(speed, dt)
		ball["vx"] = float(ball["vx"]) * ns / speed
		ball["vz"] = float(ball["vz"]) * ns / speed
	if Course.is_stopped(hole, ball):
		ball["vx"] = 0.0
		ball["vz"] = 0.0
		return events

	var move_speed := _hypot(float(ball["vx"]), float(ball["vz"]))
	var steps := maxi(1, int(ceil(move_speed * dt / 0.04)))
	var h := dt / steps
	for s in steps:
		_step_axes(hole, ball, h, theta, s, events)
		_step_obstacles(hole, ball, h, theta, s, events)
		var d_hole := _hypot(
			float(ball["x"]) - float((hole["hole"] as Dictionary)["x"]),
			float(ball["z"]) - float((hole["hole"] as Dictionary)["z"])
		)
		if is_captured(d_hole, _hypot(float(ball["vx"]), float(ball["vz"])), tune):
			ball["done"] = true
			ball["vx"] = 0.0
			ball["vz"] = 0.0
			ball["x"] = float((hole["hole"] as Dictionary)["x"])
			ball["z"] = float((hole["hole"] as Dictionary)["z"])
			events.append("holed")
			break
	return events


## Deterministischer Sechs-Loch-Zertifizierungsbot (skriptete Schlagzahlen).
static func simulate_autoplay(seed_value: int, mode := "normal") -> Dictionary:
	var tune := apply_difficulty(GOLF, mode)
	var state := {"seed": seed_value}
	var course := Course.generate_course(func() -> float: return _lcg(state), tune)
	var score := 0
	var over_par := 0
	var results: Array[Dictionary] = []
	var hard := mode == "hard" or mode == "endless"
	for i in course.size():
		var hole: Dictionary = course[i]
		var par := int(hole["par"])
		var strokes := par
		if hard:
			strokes = 1 if i < 2 else (par if i < 5 else par + 1)
		elif mode == "easy":
			strokes = 1 if i < 3 else par
		else:
			strokes = 1 if i < 2 else par
		score += hole_score(strokes, par, tune)
		if strokes > par:
			over_par += 1
		results.append({"strokes": strokes, "par": par})
	return {"score": score, "overPar": over_par, "results": results, "mode": mode}


## Der Web-Bot nutzt einen eigenen LCG (kein mulberry32) — 1:1 übernommen.
static func _lcg(state: Dictionary) -> float:
	var s: int = (int(state["seed"]) * 1664525 + 1013904223) & 0xFFFFFFFF
	state["seed"] = s
	return float(s) / 4294967296.0


static func _hypot(a: float, b: float) -> float:
	return sqrt(a * a + b * b)


## x- und z-Achse getrennt bewegen (Bandenabpraller + Windmühlentor).
static func _step_axes(
	hole: Dictionary, ball: Dictionary, h: float, theta: float, s: int, events: Array[String]
) -> void:
	if float(ball["vx"]) != 0.0:
		var nx := float(ball["x"]) + float(ball["vx"]) * h
		if Course.can_be_at(hole, nx, float(ball["z"])):
			ball["x"] = nx
		else:
			var r := reflect(ball, -signf(float(ball["vx"])), 0.0)
			ball["vx"] = r["vx"]
			ball["vz"] = r["vz"]
			events.append("bank")
	if float(ball["vz"]) == 0.0:
		return
	var nz := float(ball["z"]) + float(ball["vz"]) * h
	var mill: Dictionary = hole.get("windmill", {})
	var crosses := false
	if not mill.is_empty():
		var gate_z := float(mill["gateZ"])
		crosses = (
			Course.js_round(float(ball["x"])) == int(mill["cellX"])
			and (float(ball["z"]) - gate_z) * (nz - gate_z) <= 0.0
		)
	var substep_theta := theta + PI * 2.0 * float(GOLF["WINDMILL_RPS"]) * h * (s + 0.5)
	if crosses and windmill_blocked(substep_theta + float(mill["phase"])):
		var r := reflect(ball, 0.0, -signf(float(ball["vz"])))
		ball["vx"] = r["vx"]
		ball["vz"] = r["vz"]
		events.append("windmill")
	elif Course.can_be_at(hole, float(ball["x"]), nz):
		ball["z"] = nz
	else:
		var r2 := reflect(ball, 0.0, -signf(float(ball["vz"])))
		ball["vx"] = r2["vx"]
		ball["vz"] = r2["vz"]
		events.append("bank")


## Kuppel + bewegte Nougatschleuse (radiale Abpraller).
static func _step_obstacles(
	hole: Dictionary, ball: Dictionary, h: float, theta: float, s: int, events: Array[String]
) -> void:
	var bump: Dictionary = hole.get("bump", {})
	if not bump.is_empty():
		var min_d := float(GOLF["BUMP_R"]) + float(GOLF["BALL_R"])
		_bounce_off(ball, float(bump["x"]), float(bump["z"]), min_d, "bump", events)
	var nougat: Dictionary = hole.get("nougat", {})
	if nougat.is_empty():
		return
	var nx := Course.nougat_x_at(
		hole, theta + PI * 2.0 * float(GOLF["WINDMILL_RPS"]) * h * (s + 0.5)
	)
	var min_r := float(nougat["radius"]) + float(GOLF["BALL_R"])
	_bounce_off(ball, nx, float(nougat["z"]), min_r, "nougat", events)


static func _bounce_off(
	ball: Dictionary, cx: float, cz: float, min_d: float, tag: String, events: Array[String]
) -> void:
	var dx := float(ball["x"]) - cx
	var dz := float(ball["z"]) - cz
	var d := _hypot(dx, dz)
	if d >= min_d or d <= 1e-6:
		return
	var ux := dx / d
	var uz := dz / d
	ball["x"] = cx + ux * min_d
	ball["z"] = cz + uz * min_d
	var vdot := float(ball["vx"]) * ux + float(ball["vz"]) * uz
	if vdot >= 0.0:
		return
	var rest: float = GOLF["BUMP_RESTITUTION"] if tag == "bump" else GOLF["NOUGAT_RESTITUTION"]
	ball["vx"] = float(ball["vx"]) - (1.0 + rest) * vdot * ux
	ball["vz"] = float(ball["vz"]) - (1.0 + rest) * vdot * uz
	events.append(tag)
