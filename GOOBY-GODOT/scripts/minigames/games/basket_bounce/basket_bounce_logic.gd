class_name BasketBounceLogic
extends RefCounted
## Pure Korbjagd-Logik — zahlengleicher Port von
## GOOBY/src/minigames/games/basketBounce.logic.js (§C6.1 #7 / §C10.2).
## Flick wirft den Ball, der ballistische Bogen prallt an Ring + Brett ab,
## Korb +3, Brett-Korb +2 extra, Swish-Serie +2 (im Wander-Modus ×2). Alle
## Positionen sind 3D-Meter (die Szene projiziert das in 2D) — bewusst als
## einzelne float-Keys statt Vector3, weil Godots Vector3 nur 32-Bit-Floats
## hält und der Port sonst vom Web abweichen würde.

## Bindende §C6.1-#7-Zahlen + V3-Wander-Ring; Coin-Zeile 3/4/26, Ziel 65.
const BASKET := {
	"DURATION_SEC": 60.0,
	"POINTS_BASKET": 3,
	"POINTS_BANK_EXTRA": 2,
	"POINTS_SWISH_EXTRA": 2,
	"SWISH_STREAK_FROM": 2,
	"SLIDE_AFTER_BASKETS": 10,
	"SLIDE_AMPLITUDE": 1.0,
	"SLIDE_PERIOD_SEC": 3.6,
	"MOVING_SWISH_MULT": 2,
	"DIST_START": 5.2,
	"DIST_PER_BASKET": 0.35,
	"DIST_MAX": 8.0,
	"BALL_R": 0.24,
	"RIM_R": 0.46,
	"RIM_TUBE": 0.035,
	"RIM_Y": 2.6,
	"BOARD_GAP": 0.62,
	"BOARD_W": 1.9,
	"BOARD_H": 1.35,
	"BOARD_BOTTOM_Y": 2.35,
	"SPAWN": {"x": 0.0, "y": 1.1, "z": 4.6},
	"GRAVITY": 9.8,
	"RIM_RESTITUTION": 0.5,
	"BOARD_RESTITUTION": 0.55,
	"FLICK":
	{
		"VEL_Y_SCALE": 0.0042,
		"VEL_Z_SCALE": 0.003,
		"VEL_X_SCALE": 0.0035,
		"MIN_UP_VEL": 320.0,
		"MAX_SPEED": 13.5,
	},
	"SIM_DT": 1.0 / 120.0,
	"SIM_TIMEOUT_SEC": 5.0,
	"MAX_SWEEP_STEP_M": 0.1,
	"FLOOR_Y": 0.0,
	"SPAWN_INTERVAL_MULT": 1.0,
	"WINDOW_MULT": 1.0,
	"DURATION_MULT": 1.0,
	"SCORE_RADIUS_SCALE": 1.0,
	"SHOT_RESET_SEC": 0.55,
	"AUTO_INTERVAL_MIN_SEC": 0.5,
	"AUTO_INTERVAL_RANGE_SEC": 0.5,
	"ENDLESS": false,
	"ENDLESS_CONSECUTIVE_MISSES": 3,
}

## §G5.3 Timed-Arena-Zeilen; Endlos = Schwer-Parameter ohne Rundenuhr.
const BASKET_DIFFICULTY := {
	"easy": {"spawn": 1.2, "window": 1.25, "duration": 1.2, "endless": false},
	"normal": {"spawn": 1.0, "window": 1.0, "duration": 1.0, "endless": false},
	"hard": {"spawn": 0.85, "window": 0.8, "duration": 1.0, "endless": false},
	"endless": {"spawn": 0.85, "window": 0.8, "duration": 1.0, "endless": true},
}

## GP3-Juice (rein visuell — nie Gameplay-Mathematik).
const BASKET_JUICE := {"ON_FIRE_FROM": 3, "NET_PULSE_SEC": 0.45, "RIM_WOBBLE_SEC": 0.35}


## Abgeleitetes Tune; `normal` liefert exakt die Basis-Tabelle (§G5.3).
static func apply_difficulty(tune: Dictionary = BASKET, mode := "normal") -> Dictionary:
	var id := mode if BASKET_DIFFICULTY.has(mode) else "normal"
	if id == "normal":
		return tune
	var row: Dictionary = BASKET_DIFFICULTY[id]
	var window := maxf(0.55, float(row["window"]))
	var out := tune.duplicate()
	out["DURATION_SEC"] = float(tune["DURATION_SEC"]) * float(row["duration"])
	out["SCORE_RADIUS_SCALE"] = window
	out["SHOT_RESET_SEC"] = float(tune["SHOT_RESET_SEC"]) * float(row["spawn"])
	out["AUTO_INTERVAL_MIN_SEC"] = float(tune["AUTO_INTERVAL_MIN_SEC"]) * float(row["spawn"])
	out["AUTO_INTERVAL_RANGE_SEC"] = float(tune["AUTO_INTERVAL_RANGE_SEC"]) * float(row["spawn"])
	out["SPAWN_INTERVAL_MULT"] = float(row["spawn"])
	out["WINDOW_MULT"] = window
	out["DURATION_MULT"] = float(row["duration"])
	out["ENDLESS"] = bool(row["endless"])
	out["MODE"] = id
	return out


## Seitliches Wandern des Rings (erst ab SLIDE_AFTER_BASKETS Körben).
static func hoop_slide_x(elapsed_slide: float, baskets_made: int, tune := BASKET) -> float:
	if baskets_made < int(tune["SLIDE_AFTER_BASKETS"]):
		return 0.0
	var phase := (elapsed_slide / float(tune["SLIDE_PERIOD_SEC"])) * PI * 2.0
	return float(tune["SLIDE_AMPLITUDE"]) * sin(phase)


## Ring-Entfernung nach n Körben (Wurfdistanz-Rampe, gedeckelt).
static func hoop_distance(baskets_made: int, tune := BASKET) -> float:
	return minf(
		float(tune["DIST_MAX"]),
		float(tune["DIST_START"]) + baskets_made * float(tune["DIST_PER_BASKET"])
	)


## Wischgeste → Abwurfgeschwindigkeit (m/s); {} = zu schwach geflickt.
static func flick_to_velocity(vx: float, vy: float, tune := BASKET) -> Dictionary:
	var flick: Dictionary = tune["FLICK"]
	var up := -vy
	if up < float(flick["MIN_UP_VEL"]):
		return {}
	var out := {
		"x": vx * float(flick["VEL_X_SCALE"]),
		"y": up * float(flick["VEL_Y_SCALE"]),
		"z": -up * float(flick["VEL_Z_SCALE"]),
	}
	var speed := _hypot3(float(out["x"]), float(out["y"]), float(out["z"]))
	if speed > float(flick["MAX_SPEED"]):
		var k := float(flick["MAX_SPEED"]) / speed
		out["x"] = float(out["x"]) * k
		out["y"] = float(out["y"]) * k
		out["z"] = float(out["z"]) * k
	return out


## Frischer Ball am Abwurfpunkt (Dictionary wird von step_ball mutiert).
static func make_ball(vel: Dictionary, tune := BASKET) -> Dictionary:
	var spawn: Dictionary = tune["SPAWN"]
	return {
		"px": float(spawn["x"]),
		"py": float(spawn["y"]),
		"pz": float(spawn["z"]),
		"vx": float(vel.get("x", 0.0)),
		"vy": float(vel.get("y", 0.0)),
		"vz": float(vel.get("z", 0.0)),
		"rim": false,
		"board": false,
	}


## Abstand + Außennormale vom Ballmittelpunkt zum Ringkreis.
static func ring_distance(ball: Dictionary, hoop: Dictionary, tune := BASKET) -> Dictionary:
	var dx := float(ball["px"]) - float(hoop["x"])
	var dz := float(ball["pz"]) - float(hoop["z"])
	var horiz := sqrt(dx * dx + dz * dz)
	if horiz < 1e-9:
		dx = 1.0
		dz = 0.0
		horiz = 1.0
	var cx := float(hoop["x"]) + (dx / horiz) * float(tune["RIM_R"])
	var cz := float(hoop["z"]) + (dz / horiz) * float(tune["RIM_R"])
	var nx := float(ball["px"]) - cx
	var ny := float(ball["py"]) - float(tune["RIM_Y"])
	var nz := float(ball["pz"]) - cz
	var dist := _hypot3(nx, ny, nz)
	if dist == 0.0:
		dist = 1e-9
	return {"dist": dist, "nx": nx / dist, "ny": ny / dist, "nz": nz / dist}


## Ein Integrationsschritt: Schwerkraft, Korb-, Ring- und Brett-Test.
static func step_ball(ball: Dictionary, dt: float, hoop: Dictionary, tune := BASKET) -> Dictionary:
	var ev := {"rim": false, "board": false, "basket": false, "dead": false}
	var y_before := float(ball["py"])
	var r_before := _hypot2(
		float(ball["px"]) - float(hoop["x"]), float(ball["pz"]) - float(hoop["z"])
	)
	ball["vy"] = float(ball["vy"]) - float(tune["GRAVITY"]) * dt
	ball["px"] = float(ball["px"]) + float(ball["vx"]) * dt
	ball["py"] = float(ball["py"]) + float(ball["vy"]) * dt
	ball["pz"] = float(ball["pz"]) + float(ball["vz"]) * dt

	var r_after := _hypot2(
		float(ball["px"]) - float(hoop["x"]), float(ball["pz"]) - float(hoop["z"])
	)
	var rim_y := float(tune["RIM_Y"])
	if y_before > rim_y and float(ball["py"]) <= rim_y and float(ball["vy"]) < 0.0:
		var r_at_cross := (r_before + r_after) / 2.0
		var gate := (
			float(tune["RIM_R"]) * float(tune["SCORE_RADIUS_SCALE"]) - float(tune["BALL_R"]) * 0.35
		)
		if r_at_cross < gate:
			ev["basket"] = true
			return ev

	_bounce_rim(ball, ev, hoop, tune)
	_bounce_board(ball, ev, hoop, tune)
	var board_z := float(hoop["z"]) - float(tune["BOARD_GAP"])
	if (
		float(ball["py"]) < float(tune["FLOOR_Y"]) + float(tune["BALL_R"])
		or float(ball["pz"]) < board_z - 3.0
		or absf(float(ball["px"])) > 8.0
	):
		ev["dead"] = true
	return ev


## Frame-Integrator mit Sweep (kein Tunneln durch den dünnen Ring).
static func step_ball_swept(
	ball: Dictionary, dt: float, hoop: Dictionary, tune := BASKET
) -> Dictionary:
	var travel := _hypot3(float(ball["vx"]), float(ball["vy"]), float(ball["vz"])) * maxf(0.0, dt)
	var steps := maxi(1, int(ceil(travel / float(tune["MAX_SWEEP_STEP_M"]))))
	var h := dt / steps
	var total := {"rim": false, "board": false, "basket": false, "dead": false}
	for _i in steps:
		var ev := step_ball(ball, h, hoop, tune)
		for key: String in total:
			total[key] = bool(total[key]) or bool(ev[key])
		if bool(ev["basket"]) or bool(ev["dead"]):
			break
	return total


## Kompletten Wurf vorausrechnen (Bot-Solver + Tests).
static func simulate_shot(vel: Dictionary, hoop: Dictionary, tune := BASKET) -> Dictionary:
	var ball := make_ball(vel, tune)
	var t := 0.0
	while t < float(tune["SIM_TIMEOUT_SEC"]):
		var ev := step_ball_swept(ball, float(tune["SIM_DT"]), hoop, tune)
		t += float(tune["SIM_DT"])
		if bool(ev["basket"]):
			return {
				"result": "basket",
				"bank": bool(ball["board"]),
				"swish": not bool(ball["rim"]) and not bool(ball["board"]),
				"flightSec": t,
			}
		if bool(ev["dead"]):
			break
	return {"result": "miss", "bank": false, "swish": false, "flightSec": t}


## Wurf werten: +3, Brett +2, Swish-Serie +2, Wander-Swish ×2.
static func score_shot(
	shot: Dictionary, swish_streak: int, moving := false, tune := BASKET
) -> Dictionary:
	if not bool(shot.get("basket", false)):
		return {"points": 0, "swishStreak": 0}
	var points := int(tune["POINTS_BASKET"])
	if bool(shot.get("bank", false)):
		points += int(tune["POINTS_BANK_EXTRA"])
	var streak := 0
	var swish := bool(shot.get("swish", false))
	if swish:
		streak = swish_streak + 1
		if streak >= int(tune["SWISH_STREAK_FROM"]):
			points += int(tune["POINTS_SWISH_EXTRA"])
	if moving and swish:
		points *= int(tune["MOVING_SWISH_MULT"])
	return {"points": points, "swishStreak": streak}


## Wander-Phase (ab dem zehnten Korb).
static func is_moving_hoop(baskets_made: int, tune := BASKET) -> bool:
	return baskets_made >= int(tune["SLIDE_AFTER_BASKETS"])


## Bot-Solver: Wurf-Fächer abtasten, ersten Treffer behalten ({} = keiner).
static func solve_basket_velocity(hoop: Dictionary, rng: GoobyRng, tune := BASKET) -> Dictionary:
	var spawn: Dictionary = tune["SPAWN"]
	var dist := float(spawn["z"]) - float(hoop["z"])
	var rise := float(tune["RIM_Y"]) - float(spawn["y"])
	for _attempt in 60:
		var up_base := 5.6 + dist * 0.62
		var vy := up_base * (0.92 + rng.next() * 0.16)
		var disc := vy * vy - 2.0 * float(tune["GRAVITY"]) * rise
		if disc <= 0.0:
			continue
		var flight := (vy + sqrt(disc)) / float(tune["GRAVITY"])
		var vz := -(dist / maxf(0.3, flight)) * (0.97 + rng.next() * 0.06)
		var vx := (
			((float(hoop["x"]) - float(spawn["x"])) / maxf(0.3, flight)) * (0.95 + rng.next() * 0.1)
		)
		var cand := {"x": vx, "y": vy, "z": vz}
		if str(simulate_shot(cand, hoop, tune)["result"]) == "basket":
			return cand
	return {}


## Zeitmodi laufen auf Zeit, Endlos endet nach 3 Fehlwürfen in Folge.
static func is_round_over(elapsed: float, miss_streak: int, tune := BASKET) -> bool:
	if bool(tune["ENDLESS"]):
		return miss_streak >= int(tune["ENDLESS_CONSECUTIVE_MISSES"])
	return elapsed >= float(tune["DURATION_SEC"])


## On-Fire-Banner (rein visuell, ändert die Wertung nicht).
static func is_on_fire(swish_streak: int) -> bool:
	return swish_streak >= int(BASKET_JUICE["ON_FIRE_FROM"])


## Deterministische Bot-Zertifizierung (identisch zum Web-Release-Bot).
static func simulate_autoplay(mode := "normal", seed_value := 1) -> Dictionary:
	var tune := apply_difficulty(BASKET, mode)
	var rng := GoobyRng.new(seed_value)
	var accuracy := 0.87
	if mode == "easy":
		accuracy = 0.94
	elif mode == "hard" or mode == "endless":
		accuracy = 0.78
	var elapsed := 0.0
	var miss_streak := 0
	var swish_streak := 0
	var baskets := 0
	var score := 0
	while not is_round_over(elapsed, miss_streak, tune) and elapsed < 240.0:
		var made := rng.next() < accuracy
		var swish := made and rng.next() < 0.62
		var bank := made and not swish and rng.next() < 0.35
		var shot := score_shot(
			{"basket": made, "swish": swish, "bank": bank},
			swish_streak,
			is_moving_hoop(baskets, tune),
			tune
		)
		swish_streak = int(shot["swishStreak"])
		score += int(shot["points"])
		if made:
			baskets += 1
			miss_streak = 0
		else:
			miss_streak += 1
		elapsed += (
			1.35
			+ float(tune["SHOT_RESET_SEC"])
			+ float(tune["AUTO_INTERVAL_MIN_SEC"])
			+ rng.next() * float(tune["AUTO_INTERVAL_RANGE_SEC"])
		)
	return {
		"seed": seed_value,
		"mode": mode,
		"score": score,
		"elapsed": elapsed,
		"missStreak": miss_streak,
		"baskets": baskets,
	}


## Ring-Abprall (Kugel gegen den Torus-Ring).
static func _bounce_rim(
	ball: Dictionary, ev: Dictionary, hoop: Dictionary, tune: Dictionary
) -> void:
	var ring := ring_distance(ball, hoop, tune)
	var reach := float(tune["BALL_R"]) + float(tune["RIM_TUBE"])
	if float(ring["dist"]) >= reach:
		return
	var nx := float(ring["nx"])
	var ny := float(ring["ny"])
	var nz := float(ring["nz"])
	var vn := float(ball["vx"]) * nx + float(ball["vy"]) * ny + float(ball["vz"]) * nz
	if vn >= 0.0:
		return
	var k := -(1.0 + float(tune["RIM_RESTITUTION"])) * vn
	ball["vx"] = float(ball["vx"]) + nx * k
	ball["vy"] = float(ball["vy"]) + ny * k
	ball["vz"] = float(ball["vz"]) + nz * k
	var push := reach - float(ring["dist"]) + 0.005
	ball["px"] = float(ball["px"]) + nx * push
	ball["py"] = float(ball["py"]) + ny * push
	ball["pz"] = float(ball["pz"]) + nz * push
	ball["rim"] = true
	ev["rim"] = true


## Brett-Abprall (Ebene hinter dem Ring, zum Spieler gerichtet).
static func _bounce_board(
	ball: Dictionary, ev: Dictionary, hoop: Dictionary, tune: Dictionary
) -> void:
	var board_z := float(hoop["z"]) - float(tune["BOARD_GAP"])
	var within := (
		absf(float(ball["px"]) - float(hoop["x"])) < float(tune["BOARD_W"]) / 2.0
		and float(ball["py"]) > float(tune["BOARD_BOTTOM_Y"])
		and float(ball["py"]) < float(tune["BOARD_BOTTOM_Y"]) + float(tune["BOARD_H"])
	)
	if not within:
		return
	if float(ball["pz"]) - float(tune["BALL_R"]) >= board_z or float(ball["vz"]) >= 0.0:
		return
	ball["pz"] = board_z + float(tune["BALL_R"])
	ball["vz"] = -float(ball["vz"]) * float(tune["BOARD_RESTITUTION"])
	ball["board"] = true
	ev["board"] = true


static func _hypot2(a: float, b: float) -> float:
	return sqrt(a * a + b * b)


static func _hypot3(a: float, b: float, c: float) -> float:
	return sqrt(a * a + b * b + c * c)
