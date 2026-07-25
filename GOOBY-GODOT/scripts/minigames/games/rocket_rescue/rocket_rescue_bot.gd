class_name RocketRescueBot
extends RefCounted
## PD-Autopilot der Raketen-Rettung — zahlengleicher Port von `createBot()`
## aus rocketRescue.logic.js. Wählt den nächsten Hasen (bzw. die Station beim
## Tragen), macht bei niedrigem Tank einen gerasteten Tank-Umweg, kreuzt mit
## Sicherheitshöhe über dem Ziel ein und sinkt dann mit Abfangbogen in das
## Sanftlandeband. Waagerecht: P auf Position → Sollgeschwindigkeit → Neigung;
## senkrecht: Zweipunkt-Schub auf den vy-Sollwert.

const Logic := preload("res://scripts/minigames/games/rocket_rescue/rocket_rescue_logic.gd")
const Lander := preload("res://scripts/minigames/games/rocket_rescue/rocket_rescue_engine.gd")

var tune: Dictionary

## Hysterese-Riegel (BOT_REFUEL_ENTER/_EXIT) — ohne ihn pendelt der Bot.
var _refueling := false


func _init(tune_in := Logic.ROCKET) -> void:
	tune = tune_in


## Ein Steuerbefehl {"thrust": bool, "tiltDir": int} für den aktuellen Zustand.
func control(state: Dictionary, layout: Dictionary) -> Dictionary:
	if bool(state["ended"]) or bool(state["towing"]):
		return {"thrust": false, "tiltDir": 0}
	if state["landedOn"] != null:
		return _parked_command(state, layout)
	var target := _pick_target(state, layout)
	var tx := float(target["x"])
	var ty := float(target["y"])
	var is_canister := bool(target["canister"])
	var dx := tx - float(state["x"])
	var height_above := float(state["y"]) - ty
	var aligned := (
		not is_canister
		and absf(dx) <= float(tune["BOT_ALIGN_X_M"])
		and absf(float(state["vx"])) <= float(tune["BOT_ALIGN_VX"])
	)
	var setpoint := (
		_descend_setpoint(dx, height_above)
		if aligned and height_above >= -0.1
		else _align_setpoint(state, dx, ty, is_canister)
	)
	# Seitliche Autorität gibt es NUR unter Schub — ein großer vx-Fehler
	# zündet das Triebwerk deshalb mit (ein gleitendes Schiff kann nicht lenken).
	var dvx := float(setpoint["vx"]) - float(state["vx"])
	var vy := float(state["vy"])
	var thrust := (
		vy < float(setpoint["vy"]) or (absf(dvx) > 1.2 and vy < float(tune["BOT_MAX_RISE"]))
	)
	var deadband := float(tune["BOT_TILT_DEADBAND"])
	var tilt_dir := 0
	if dvx > deadband:
		tilt_dir = 1
	elif dvx < -deadband:
		tilt_dir = -1
	return {"thrust": thrust, "tiltDir": tilt_dir}


## Geparkt: abheben, solange es noch etwas zu tun gibt.
func _parked_command(state: Dictionary, layout: Dictionary) -> Dictionary:
	var bunnies_left := false
	for p: Dictionary in layout["platforms"]:
		if bool(p["bunny"]):
			bunnies_left = true
			break
	var should_go := (
		not Logic.same_id(state["landedOn"], "pad") if bool(state["carrying"]) else bunnies_left
	)
	return {"thrust": should_go and float(state["fuel"]) > 0.0, "tiltDir": 0}


## Zielwahl: nächster Hase (bzw. Station beim Tragen), ggf. Tank-Umweg.
func _pick_target(state: Dictionary, layout: Dictionary) -> Dictionary:
	var pad: Dictionary = layout["pad"]
	var tx := float(pad["x"])
	var ty := float(pad["y"])
	if not bool(state["carrying"]):
		var best_d := INF
		for p: Dictionary in layout["platforms"]:
			if not bool(p["bunny"]):
				continue
			var d := (
				absf(float(p["x"]) - float(state["x"]))
				+ absf(float(p["y"]) - float(state["y"])) * 0.6
			)
			if d < best_d:
				best_d = d
				tx = float(p["x"])
				ty = float(p["y"])
	var final_descent := (
		absf(tx - float(state["x"])) <= float(tune["BOT_ALIGN_X_M"]) * 2.0
		and float(state["y"]) - ty < float(tune["BOT_REFUEL_SKIP_BELOW_M"])
	)
	var fuel := float(state["fuel"])
	if not _refueling and fuel < float(tune["BOT_REFUEL_ENTER"]):
		_refueling = true
	elif _refueling and fuel >= float(tune["BOT_REFUEL_EXIT"]):
		_refueling = false
	if not _refueling or final_descent:
		return {"x": tx, "y": ty, "canister": false}
	var best_d := INF
	var best: Dictionary = {}
	for f: Dictionary in layout["fuelPickups"]:
		if bool(f["taken"]):
			continue
		var d := Logic.hypot(float(f["x"]) - float(state["x"]), float(f["y"]) - float(state["y"]))
		if d < best_d:
			best_d = d
			best = f
	if best.is_empty() or best_d >= float(tune["BOT_REFUEL_RANGE_M"]):
		return {"x": tx, "y": ty, "canister": false}
	# Kanister werden direkt angeflogen (keine Landehöhe, kein Abfangbogen).
	return {"x": float(best["x"]), "y": float(best["y"]), "canister": true}


## Einkreuzen: über dem Ziel bremsen/steuern, vx folgt einem √(2·a·d)-Profil.
func _align_setpoint(state: Dictionary, dx: float, ty: float, is_canister: bool) -> Dictionary:
	var y_des := (
		ty
		if is_canister
		else maxf(ty + float(tune["BOT_CRUISE_CLEARANCE_M"]), float(state["y"]) - 1.4)
	)
	var vy_des := maxf(
		-1.1,
		minf(float(tune["BOT_MAX_RISE"]), (y_des - float(state["y"])) * float(tune["BOT_VY_GAIN"]))
	)
	var brake := sqrt(2.0 * float(tune["BOT_LAT_ACCEL_EFF"]) * absf(dx)) * 0.85
	var vx_des := (
		signf(dx)
		* minf(minf(float(tune["BOT_MAX_VX"]), brake), absf(dx) * float(tune["BOT_VX_GAIN"]) + 0.15)
	)
	return {"vy": vy_des, "vx": vx_des}


## Sinkflug: der Sollwert schrumpft mit der Höhe bis ins Sanftlandeband.
func _descend_setpoint(dx: float, height_above: float) -> Dictionary:
	var drop := minf(float(tune["BOT_MAX_DESCEND"]), 0.45 * height_above + 0.25)
	var vy_des := (
		-float(tune["BOT_SOFT_DESCEND"])
		if height_above < float(tune["BOT_FLARE_BELOW_M"])
		else -drop
	)
	var limit := float(tune["BOT_DESCEND_VX"])
	return {"vy": vy_des, "vx": maxf(-limit, minf(limit, dx * 2.0))}


## Kopfloser Volllauf (Tests/Tuning): Engine + PD-Bot bei festem dt.
static func simulate_round(
	seed_value: int, tune_in := Logic.ROCKET, dt := 1.0 / 60.0
) -> Dictionary:
	var guard := int(ceil((float(tune_in["DURATION_SEC"]) + 30.0) / dt))
	return _run(seed_value, tune_in, dt, guard)


## §G5.4-Zertifizierungslauf: eine volle Bot-Runde im gewählten Modus.
static func simulate_autoplay(mode := "normal", seed_value := 1, max_sec := 1800.0) -> Dictionary:
	var tune_in := Logic.apply_difficulty(Logic.ROCKET, mode)
	var dt := 1.0 / 60.0
	return _run(seed_value, tune_in, dt, int(ceil(max_sec / dt)))


static func _run(seed_value: int, tune_in: Dictionary, dt: float, guard: int) -> Dictionary:
	var rng := GoobyRng.new(seed_value)
	var engine := Lander.new(func() -> float: return rng.next(), tune_in)
	var bot := RocketRescueBot.new(tune_in)
	var left := guard
	while not bool(engine.state["ended"]) and left > 0:
		engine.step(bot.control(engine.state, engine.layout), dt)
		left -= 1
	var s: Dictionary = engine.state
	return {
		"score":
		Logic.round_score(int(s["rescued"]), float(s["fuel"]), int(s["softLandings"]), tune_in),
		"rescued": int(s["rescued"]),
		"softLandings": int(s["softLandings"]),
		"hardLandings": int(s["hardLandings"]),
		"fuelLeft": float(s["fuel"]),
		"elapsed": float(s["elapsed"]),
		"endReason": s["endReason"],
	}
