class_name RocketRescueEngine
extends RefCounted
## Deterministische Lander-Zustandsmaschine der Raketen-Rettung — zahlengleicher
## Port von `createEngine()` aus rocketRescue.logic.js. `step()` integriert
## EINEN Frame und liefert semantische Ereignisse für die Ansicht/Tests:
##   liftoff · landing{where,vy,kind} · bunnyPickup{platform} · rescue{count} ·
##   hardLanding{vy} · fuelPickup{index,amount} · fuelLow · outOfFuel · towed ·
##   windTelegraph{dir} · windGust{dir} · bunnyRespawn · ended{reason}
##
## `landedOn`/`departedFrom`/`lastLandedOn` sind `"pad"`, ein Plattform-Index
## (int) oder `null` (in der Luft) — genau wie im Web.

const Logic := preload("res://scripts/minigames/games/rocket_rescue/rocket_rescue_logic.gd")

var tune: Dictionary
var layout: Dictionary
var state: Dictionary

var _rng: Callable


func _init(rng: Callable, tune_in := Logic.ROCKET) -> void:
	_rng = rng
	tune = tune_in
	layout = Logic.create_layout(rng, tune)
	var pad: Dictionary = layout["pad"]
	var span := float(tune["WIND_EVERY_MAX_SEC"]) - float(tune["WIND_EVERY_MIN_SEC"])
	state = {
		"x": float(pad["x"]),
		"y": float(pad["y"]),
		"vx": 0.0,
		"vy": 0.0,
		"tilt": 0.0,
		"fuel": float(tune["FUEL_MAX"]),
		"carrying": false,
		"rescued": 0,
		"softLandings": 0,
		"hardLandings": 0,
		"landedOn": "pad",
		"departedFrom": null,
		"lastLandedOn": "pad",
		"towing": false,
		"ended": false,
		"endReason": null,
		"elapsed": 0.0,
		"fuelLowFired": false,
		"wind":
		{
			"phase": "idle",
			"dir": 1,
			"t": 0.0,
			"nextAt": float(tune["WIND_EVERY_MIN_SEC"]) + float(_rng.call()) * span,
		},
	}


## Einen Frame integrieren. `input` = {"thrust": bool, "tiltDir": int}.
func step(input: Dictionary, dt: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	if bool(state["ended"]):
		return events
	var step_dt := minf(float(tune["MAX_DT"]), maxf(0.0, dt))
	state["elapsed"] = float(state["elapsed"]) + step_dt
	# §G5.4: Endlos hat keine Rundenuhr — es endet am leeren Tank.
	if not bool(tune["ENDLESS"]) and float(state["elapsed"]) >= float(tune["DURATION_SEC"]):
		_end_run("time", events)
		return events
	_tick_respawns(step_dt)
	if bool(state["towing"]):
		_tow(step_dt, events)
		return events
	_slew_tilt(input, step_dt)
	var thrusting := bool(input.get("thrust", false)) and float(state["fuel"]) > 0.0
	if state["landedOn"] != null and not thrusting:
		state["vx"] = 0.0
		state["vy"] = 0.0
	else:
		_fly(thrusting, step_dt, events)
	_tick_wind(step_dt, events)
	_check_fuel(events)
	return events


## Alle landbaren Flächen: die Station plus jede Plattform.
func surfaces() -> Array[Dictionary]:
	var pad: Dictionary = layout["pad"]
	var list: Array[Dictionary] = [
		{"id": "pad", "x": float(pad["x"]), "y": float(pad["y"]), "halfW": float(pad["halfW"])}
	]
	var platforms: Array = layout["platforms"]
	for i in platforms.size():
		var p: Dictionary = platforms[i]
		list.append({"id": i, "x": float(p["x"]), "y": float(p["y"]), "halfW": float(p["halfW"])})
	return list


## Punktestand des laufenden Zustands (30·gerettet + Sprit/2 + 5·sanft).
func score() -> int:
	return Logic.round_score(
		int(state["rescued"]), float(state["fuel"]), int(state["softLandings"]), tune
	)


func _end_run(reason: String, events: Array[Dictionary]) -> void:
	if bool(state["ended"]):
		return
	state["ended"] = true
	state["endReason"] = reason
	events.append({"type": "ended", "reason": reason})


func _tick_respawns(dt: float) -> void:
	for f: Dictionary in layout["fuelPickups"]:
		if not bool(f["taken"]):
			continue
		f["respawnT"] = float(f["respawnT"]) - dt
		if float(f["respawnT"]) <= 0.0:
			f["taken"] = false


## Abschleppen nach Spritmangel: zurück zur Station, dann endet die Runde.
func _tow(dt: float, events: Array[Dictionary]) -> void:
	var pad: Dictionary = layout["pad"]
	var dx := float(pad["x"]) - float(state["x"])
	var dy := float(pad["y"]) - float(state["y"])
	var dist := Logic.hypot(dx, dy)
	var step_m := float(tune["TOW_SPEED"]) * dt
	if dist <= step_m or dist < 0.05:
		state["x"] = float(pad["x"])
		state["y"] = float(pad["y"])
		events.append({"type": "towed"})
		_end_run("fuel", events)
	else:
		state["x"] = float(state["x"]) + (dx / dist) * step_m
		state["y"] = float(state["y"]) + (dy / dist) * step_m


func _slew_tilt(input: Dictionary, dt: float) -> void:
	var target := clampf(float(input.get("tiltDir", 0)), -1.0, 1.0) * float(tune["TILT_MAX_RAD"])
	var d_tilt := target - float(state["tilt"])
	var max_slew := float(tune["TILT_RATE"]) * dt
	state["tilt"] = (
		float(state["tilt"]) + (d_tilt if absf(d_tilt) <= max_slew else signf(d_tilt) * max_slew)
	)


func _fly(thrusting: bool, dt: float, events: Array[Dictionary]) -> void:
	if state["landedOn"] != null and thrusting:
		state["departedFrom"] = state["landedOn"]
		state["landedOn"] = null
		events.append({"type": "liftoff"})
	var ax := 0.0
	var ay := -float(tune["GRAVITY"])
	if thrusting:
		ax += sin(float(state["tilt"])) * float(tune["THRUST_ACCEL"])
		ay += cos(float(state["tilt"])) * float(tune["THRUST_ACCEL"])
		state["fuel"] = maxf(0.0, float(state["fuel"]) - float(tune["FUEL_BURN_PER_SEC"]) * dt)
	var wind: Dictionary = state["wind"]
	if str(wind["phase"]) == "gust":
		ax += int(wind["dir"]) * float(tune["WIND_ACCEL"])
	state["vx"] = float(state["vx"]) + ax * dt
	state["vy"] = float(state["vy"]) + ay * dt
	var prev_y := float(state["y"])
	state["x"] = float(state["x"]) + float(state["vx"]) * dt
	state["y"] = float(state["y"]) + float(state["vy"]) * dt
	_clamp_walls()
	_collect_fuel(events)
	_release_departed()
	if float(state["vy"]) <= 0.0:
		_try_land(prev_y, events)


func _clamp_walls() -> void:
	var wall_x := float(tune["WORLD_HALF_W"]) - 0.4
	if float(state["x"]) < -wall_x:
		state["x"] = -wall_x
		state["vx"] = absf(float(state["vx"])) * float(tune["WALL_RESTITUTION"])
	elif float(state["x"]) > wall_x:
		state["x"] = wall_x
		state["vx"] = -absf(float(state["vx"])) * float(tune["WALL_RESTITUTION"])
	if float(state["y"]) > float(tune["CEILING_Y"]):
		state["y"] = float(tune["CEILING_Y"])
		state["vy"] = minf(0.0, float(state["vy"]))


func _collect_fuel(events: Array[Dictionary]) -> void:
	var pickups: Array = layout["fuelPickups"]
	for i in pickups.size():
		var f: Dictionary = pickups[i]
		if bool(f["taken"]):
			continue
		var d := Logic.hypot(float(f["x"]) - float(state["x"]), float(f["y"]) - float(state["y"]))
		if d > float(tune["FUEL_PICKUP_RADIUS"]):
			continue
		f["taken"] = true
		f["respawnT"] = float(tune["FUEL_RESPAWN_SEC"])
		# §G5.4-Endlosrampe: die Füllmenge dünnt um 10 % je geretteten Hasen aus.
		var thin := 1.0
		if bool(tune["ENDLESS"]):
			thin = maxf(0.0, 1.0 - float(tune["ENDLESS_THIN_PER_RESCUE"]) * int(state["rescued"]))
		var amount := float(tune["FUEL_PICKUP_AMOUNT"]) * thin
		state["fuel"] = minf(float(tune["FUEL_MAX"]), float(state["fuel"]) + amount)
		state["fuelLowFired"] = false
		events.append({"type": "fuelPickup", "index": i, "amount": amount})


## Die eben verlassene Fläche fängt erst wieder, wenn das Schiff sie frei hat.
func _release_departed() -> void:
	if state["departedFrom"] == null:
		return
	var s: Dictionary = (
		layout["pad"]
		if state["departedFrom"] is String
		else (layout["platforms"] as Array)[int(state["departedFrom"])]
	)
	var cleared := float(state["y"]) >= float(s["y"]) + float(tune["DEPART_CLEAR_M"])
	if cleared or absf(float(state["x"]) - float(s["x"])) > float(s["halfW"]):
		state["departedFrom"] = null


func _try_land(prev_y: float, events: Array[Dictionary]) -> void:
	for s in surfaces():
		if Logic.same_id(s["id"], state["departedFrom"]):
			continue
		var overlaps := absf(float(state["x"]) - float(s["x"])) <= float(s["halfW"])
		if not (prev_y >= float(s["y"]) and float(state["y"]) <= float(s["y"]) and overlaps):
			continue
		var vy_abs := absf(float(state["vy"]))
		var kind := Logic.classify_landing(vy_abs, tune)
		if kind == "hard":
			_bounce(s, vy_abs, events)
		else:
			_touch_down(s, vy_abs, kind, events)
		return


## §C10.1: harte Landung = Abpraller + 10 Sprit Strafe, niemals Tod.
func _bounce(s: Dictionary, vy_abs: float, events: Array[Dictionary]) -> void:
	state["y"] = float(s["y"]) + 0.02
	state["vy"] = vy_abs * float(tune["BOUNCE_RESTITUTION"])
	state["vx"] = float(state["vx"]) * 0.6
	state["hardLandings"] = int(state["hardLandings"]) + 1
	state["fuel"] = maxf(0.0, float(state["fuel"]) - float(tune["HARD_FUEL_PENALTY"]))
	events.append({"type": "hardLanding", "vy": vy_abs, "where": s["id"]})


func _touch_down(s: Dictionary, vy_abs: float, kind: String, events: Array[Dictionary]) -> void:
	state["y"] = float(s["y"])
	state["vx"] = 0.0
	state["vy"] = 0.0
	state["landedOn"] = s["id"]
	state["departedFrom"] = null
	var platforms: Array = layout["platforms"]
	var rescue_work := false
	if (
		s["id"] is int
		and bool((platforms[int(s["id"])] as Dictionary)["bunny"])
		and not bool(state["carrying"])
	):
		(platforms[int(s["id"])] as Dictionary)["bunny"] = false
		state["carrying"] = true
		rescue_work = true
	elif s["id"] is String and bool(state["carrying"]):
		state["carrying"] = false
		state["rescued"] = int(state["rescued"]) + 1
		rescue_work = true
	# Anti-Farm: nur neue Flächen oder echte Rettungsarbeit zählen für den Bonus.
	var eligible := rescue_work or not Logic.same_id(s["id"], state["lastLandedOn"])
	state["lastLandedOn"] = s["id"]
	if kind == "soft" and eligible:
		state["softLandings"] = int(state["softLandings"]) + 1
	(
		events
		. append(
			{
				"type": "landing",
				"where": s["id"],
				"vy": vy_abs,
				"kind": kind,
				"bonusEligible": kind == "soft" and eligible,
			}
		)
	)
	if not rescue_work:
		return
	if bool(state["carrying"]):
		events.append({"type": "bunnyPickup", "platform": s["id"]})
		return
	events.append({"type": "rescue", "count": int(state["rescued"])})
	if bool(tune["ENDLESS"]):
		_rearm_bunnies(events)
	elif int(state["rescued"]) >= int(tune["PLATFORM_COUNT"]):
		_end_run("complete", events)


## §G5.4: ein leergeräumtes Feld bestückt sich neu — der Lauf geht weiter.
func _rearm_bunnies(events: Array[Dictionary]) -> void:
	for p: Dictionary in layout["platforms"]:
		if bool(p["bunny"]):
			return
	for p: Dictionary in layout["platforms"]:
		p["bunny"] = true
	events.append({"type": "bunnyRespawn"})


## Windböen (§C10.1: erst ab 2 geretteten Hasen, immer angekündigt).
func _tick_wind(dt: float, events: Array[Dictionary]) -> void:
	if int(state["rescued"]) < int(tune["WIND_FROM_RESCUES"]) or bool(state["ended"]):
		return
	var wind: Dictionary = state["wind"]
	var phase := str(wind["phase"])
	if phase == "idle":
		var due := float(state["elapsed"]) >= float(wind["nextAt"])
		if due and state["landedOn"] == null:
			wind["phase"] = "telegraph"
			wind["dir"] = -1 if float(_rng.call()) < 0.5 else 1
			wind["t"] = 0.0
			events.append({"type": "windTelegraph", "dir": int(wind["dir"])})
		return
	wind["t"] = float(wind["t"]) + dt
	if phase == "telegraph":
		if float(wind["t"]) >= float(tune["WIND_TELEGRAPH_SEC"]):
			wind["phase"] = "gust"
			wind["t"] = 0.0
			events.append({"type": "windGust", "dir": int(wind["dir"])})
	elif float(wind["t"]) >= float(tune["WIND_GUST_SEC"]):
		wind["phase"] = "idle"
		var span := float(tune["WIND_EVERY_MAX_SEC"]) - float(tune["WIND_EVERY_MIN_SEC"])
		wind["nextAt"] = (
			float(state["elapsed"]) + float(tune["WIND_EVERY_MIN_SEC"]) + float(_rng.call()) * span
		)


## Leerer Tank → Abschleppen (niemals Tod), sonst die Spritwarnung.
func _check_fuel(events: Array[Dictionary]) -> void:
	var fuel := float(state["fuel"])
	if fuel <= 0.0 and not bool(state["towing"]) and not bool(state["ended"]):
		if state["landedOn"] is String:
			_end_run("fuel", events)
		else:
			state["towing"] = true
			state["landedOn"] = null
			events.append({"type": "outOfFuel"})
	elif not bool(state["fuelLowFired"]) and fuel > 0.0 and fuel <= 20.0:
		state["fuelLowFired"] = true
		events.append({"type": "fuelLow"})
