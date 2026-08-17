class_name HarborHopperLogic
extends RefCounted
## Pure Hafen-Hopser-Logik — zahlengleicher Port von
## GOOBY/src/minigames/games/harborHopper.logic.js (PLAN3 §C10.1 #4).
## Fischkutter fährt automatisch den Hafenkanal hinunter (6 m/s), Ziehen
## lenkt träge zur Seite. Kisten +4, Netzringe +2, Bojen/Molen −3 + Slow.
## Wellenbänder rollen entgegen: mittig auf dem Schaumkamm = +30 % für 2 s
## (kettbar). Möwe klaut nach > 4 s Spurstillstand die oberste Kiste
## (Warnruf vorher). Fischkutter-Horn räumt Bojen im 6-m-Kegel, 2 Ladungen.
## Coin-Zeile /5, 4..30, Ziel 110.

## §C10.1 #4 Bindezahlen + V3/G42-Feel-Regler.
const HARBOR := {
	"DURATION_SEC": 120.0,
	"BASE_SPEED": 6.0,
	"CHANNEL_HALF_W": 3.2,
	"LANES": 3,
	"STEER_ACCEL": 6.5,
	"STEER_DAMPING": 2.6,
	"MAX_LATERAL_SPEED": 3.4,
	"CRATE_POINTS": 4,
	"RING_POINTS": 2,
	"CRATE_RADIUS": 0.8,
	"RING_RADIUS": 0.85,
	"BUMP_PENALTY": -3,
	"HITBOX_SCALE": 0.7,
	"BUOY_RADIUS": 0.75,
	"BOAT_RADIUS": 0.6,
	"PIER_REACH_M": 2.1,
	"PIER_DEPTH_M": 1.1,
	"SLOW_FACTOR": 0.55,
	"SLOW_SEC": 1.4,
	"BUMP_IFRAMES_SEC": 1.0,
	"BUMP_SHOVE": 2.2,
	"ROW_GAP_M": {"min": 11.0, "max": 15.0},
	"CRATE_CHANCE": 0.44,
	"RING_CHANCE": 0.2,
	"BUOY_CHANCE": 0.26,
	"PIER_EVERY_M": {"min": 70.0, "max": 110.0},
	"LOOKAHEAD_M": 60.0,
	"WAVE_EVERY_SEC": 6.0,
	"WAVE_SPEED": 2.5,
	"WAVE_SPAWN_AHEAD_M": 34.0,
	"SWEET_HALF_W": 1.05,
	"BOOST_FACTOR": 1.3,
	"BOOST_SEC": 2.0,
	"GULL_IDLE_SEC": 4.0,
	"GULL_WARN_SEC": 1.5,
	"HORN_CHARGES": 2,
	"HORN_CONE_M": 6.0,
	"HORN_CONE_BASE": 0.9,
	"HORN_CONE_SPREAD": 0.45,
	"MAX_DT": 1.0 / 20.0,
	"BOT_SCAN_M": 16.0,
	"BOT_DODGE_M": 6.5,
	"BOT_WAVE_M": 12.0,
	"BOT_HORN_M": 4.5,
	"BOT_CRATE_VALUE": 4.0,
	"BOT_RING_VALUE": 2.0,
	"BOT_REACH_X_PER_M": 0.5,
	"BOT_GULL_DODGE_AT_SEC": 4.6,
	"ENDLESS": false,
	"ENDLESS_BUMP_LIMIT": 3,
	"ENDLESS_ACCEL_PER_M": 0.004,
	"ENDLESS_MAX_SPEED": 9.6,
	"VALIDATOR_REACT_SEC": 0.35,
	"VALIDATOR_DODGE_MARGIN_M": 0.35,
	"PICKUP_RATE": 1.0,
	"SCORE_MULT": 1.0,
	"PICKUP_RADIUS_MULT": 1.0,
	"RENDER_SCALE_MULT": 1.0,
	"BOT_FOCUS_SEC": 1.9,
	"BOT_LAPSE_EVERY_SEC": 14.0,
}

## §G5.3-Zeilen (Tempo, Dichte, Rundenzeit, Bot-Mensch-Modell).
const HARBOR_DIFFICULTY := {
	"easy": {"speed": 0.85, "density": 0.85, "duration": 1.2, "botFocus": 1.5, "botLapse": 34.0},
	"normal": {"speed": 1.0, "density": 1.0, "duration": 1.0, "botFocus": 1.9, "botLapse": 14.0},
	"hard": {"speed": 1.2, "density": 1.15, "duration": 1.0, "botFocus": 1.9, "botLapse": 12.5},
	"endless": {"speed": 1.2, "density": 1.15, "duration": 1.0, "botFocus": 1.9, "botLapse": 12.5},
}

## GP3-Juice — reine Feier-Regler, nie Spiel-Mathe.
const HARBOR_JUICE := {"CRATE_POP_SEC": 0.35}


## Abgeleitetes Tune; `normal` liefert exakt die Basis-Tabelle.
static func apply_difficulty(tune := HARBOR, mode := "normal") -> Dictionary:
	if mode == "normal" or not HARBOR_DIFFICULTY.has(mode):
		return tune
	var row: Dictionary = HARBOR_DIFFICULTY[mode]
	var density := float(row["density"])
	var out := tune.duplicate(true)
	out["BASE_SPEED"] = float(tune["BASE_SPEED"]) * float(row["speed"])
	out["DURATION_SEC"] = float(tune["DURATION_SEC"]) * float(row["duration"])
	out["BUOY_CHANCE"] = float(tune["BUOY_CHANCE"]) * density
	var pier: Dictionary = tune["PIER_EVERY_M"]
	out["PIER_EVERY_M"] = {
		"min": float(pier["min"]) / density,
		"max": float(pier["max"]) / density,
	}
	out["BOT_FOCUS_SEC"] = float(row["botFocus"])
	out["BOT_LAPSE_EVERY_SEC"] = float(row["botLapse"])
	out["ENDLESS"] = mode == "endless"
	out["MODE"] = mode
	return out


## §C-SYS4.3-Modifikatoren (muenzregen / turbo / riesenGooby).
static func apply_modifier(tune: Dictionary, modifier: Dictionary) -> Dictionary:
	if modifier.is_empty():
		return tune
	var kind := str(modifier.get("type", ""))
	var out := tune.duplicate(true)
	if kind == "muenzregen":
		out["PICKUP_RATE"] = maxf(0.1, float(modifier.get("coinRate", 1.0)))
		return out
	if kind == "turbo":
		var speed_mult := maxf(0.1, float(modifier.get("speedMult", 1.0)))
		out["BASE_SPEED"] = float(tune["BASE_SPEED"]) * speed_mult
		out["SCORE_MULT"] = maxf(0.0, float(modifier.get("scoreMult", 1.0)))
		return out
	if kind == "riesenGooby":
		var hitbox := maxf(0.1, float(modifier.get("hitboxMult", 1.0)))
		out["CRATE_RADIUS"] = float(tune["CRATE_RADIUS"]) * hitbox
		out["RING_RADIUS"] = float(tune["RING_RADIUS"]) * hitbox
		out["PICKUP_RADIUS_MULT"] = hitbox
		out["RENDER_SCALE_MULT"] = maxf(0.1, float(modifier.get("scale", 1.0)))
		return out
	return tune


## §G5.3-Leitplanke: passt zwischen zwei Reihen ein voller Bojen-Ausweicher?
## ≥ 1 = immer vermeidbar.
static func row_reachability(tune := HARBOR) -> float:
	var max_base := float(tune["BASE_SPEED"])
	if bool(tune["ENDLESS"]):
		max_base = maxf(max_base, float(tune["ENDLESS_MAX_SPEED"]))
	var worst_speed := max_base * float(tune["BOOST_FACTOR"])
	var row_sec := float((tune["ROW_GAP_M"] as Dictionary)["min"]) / worst_speed
	var dodge_m := (
		(float(tune["BUOY_RADIUS"]) + float(tune["BOAT_RADIUS"])) * float(tune["HITBOX_SCALE"])
		+ float(tune["VALIDATOR_DODGE_MARGIN_M"])
	)
	var need_sec := float(tune["VALIDATOR_REACT_SEC"]) + dodge_m / float(tune["MAX_LATERAL_SPEED"])
	return row_sec / need_sec


## Endpunktzahl (Turbo ×1.5 an dieser EINEN Naht).
static func hopper_score(state: Dictionary, tune := HARBOR) -> int:
	return int(round(float(state["score"]) * float(tune["SCORE_MULT"])))


## Spur 0·1·2 quer über den Kanal (nur Möwen-Stillstandserkennung).
static func lane_of(x: float, tune := HARBOR) -> int:
	var half_w := float(tune["CHANNEL_HALF_W"])
	var lanes := int(tune["LANES"])
	var w := (half_w * 2.0) / lanes
	return maxi(0, mini(lanes - 1, int(floorf((x + half_w) / w))))


## Aktuelles Vorwärtstempo: Basis × Boost × Slow.
static func speed_of(state: Dictionary, tune := HARBOR) -> float:
	var v := float(tune["BASE_SPEED"])
	if bool(tune["ENDLESS"]):
		v = minf(
			float(tune["ENDLESS_MAX_SPEED"]),
			v + float(state.get("z", 0.0)) * float(tune["ENDLESS_ACCEL_PER_M"])
		)
	if float(state["boostT"]) > 0.0:
		v *= float(tune["BOOST_FACTOR"])
	if float(state["slowT"]) > 0.0:
		v *= float(tune["SLOW_FACTOR"])
	return v


## Kreis-gegen-Kreis mit der 70-%-Hindernis-Kulanz.
static func hits(
	boat: Dictionary, item: Dictionary, radius: float, forgiving: bool, tune := HARBOR
) -> bool:
	var r := radius * float(tune["HITBOX_SCALE"]) if forgiving else radius
	var dx := float(item["x"]) - float(boat["x"])
	var dz := float(item["z"]) - float(boat["z"])
	return dx * dx + dz * dz <= r * r


## Molenfinger: greift PIER_REACH_M von `side` in den Kanal, Tiefe PIER_DEPTH_M.
static func hits_pier(boat: Dictionary, pier: Dictionary, tune := HARBOR) -> bool:
	var depth := (
		(float(tune["PIER_DEPTH_M"]) / 2.0 + float(tune["BOAT_RADIUS"]))
		* float(tune["HITBOX_SCALE"])
	)
	if absf(float(boat["z"]) - float(pier["z"])) > depth:
		return false
	var inner_edge := (
		float(tune["CHANNEL_HALF_W"]) - float(tune["PIER_REACH_M"]) * float(tune["HITBOX_SCALE"])
	)
	if int(pier["side"]) < 0:
		return float(boat["x"]) <= -inner_edge
	return float(boat["x"]) >= inner_edge


## Hornkegel (6 m voraus).
static func in_horn_cone(boat: Dictionary, buoy: Dictionary, tune := HARBOR) -> bool:
	var dz := float(buoy["z"]) - float(boat["z"])
	if dz < -0.5 or dz > float(tune["HORN_CONE_M"]):
		return false
	return (
		absf(float(buoy["x"]) - float(boat["x"]))
		<= float(tune["HORN_CONE_BASE"]) + maxf(0.0, dz) * float(tune["HORN_CONE_SPREAD"])
	)


## Punktedelta mit der geteilten Null-Untergrenze.
static func apply_score(score: int, delta: int) -> int:
	return maxi(0, score + delta)


## Deterministische Hafen-Maschine (Web `createEngine`). Die View treibt
## DIESELBE Klasse — dadurch bleibt sie zahlengleich zum Bot.
class HarborEngine:
	extends RefCounted

	var state: Dictionary
	var items: Array[Dictionary] = []
	var piers: Array[Dictionary] = []
	var waves: Array[Dictionary] = []

	var _tune: Dictionary
	var _rng: GoobyRng
	var _gen_z := 14.0
	var _next_pier_z := 0.0
	var _next_wave_at := 0.0

	func _init(rng: GoobyRng, tune := HARBOR) -> void:
		_rng = rng
		_tune = tune
		state = {
			"x": 0.0,
			"vx": 0.0,
			"z": 0.0,
			"score": 0,
			"crates": 0,
			"rings": 0,
			"bumps": 0,
			"steals": 0,
			"boostT": 0.0,
			"boostChain": 0,
			"slowT": 0.0,
			"iframesT": 0.0,
			"hornCharges": int(tune["HORN_CHARGES"]),
			"idleT": 0.0,
			"lane": HarborHopperLogic.lane_of(0.0, tune),
			"gull": {"phase": "idle", "t": 0.0},
			"elapsed": 0.0,
			"ended": false,
		}
		var pier: Dictionary = tune["PIER_EVERY_M"]
		_next_pier_z = float(pier["min"]) + _rng.next() * (float(pier["max"]) - float(pier["min"]))
		_next_wave_at = float(tune["WAVE_EVERY_SEC"]) * 0.6
		_generate_ahead(float(tune["LOOKAHEAD_M"]))

	## Ein Frame; liefert die semantischen Ereignisse für View + Tests.
	func step(input: Dictionary, dt: float) -> Array[Dictionary]:
		var events: Array[Dictionary] = []
		if bool(state["ended"]):
			return events
		dt = minf(float(_tune["MAX_DT"]), maxf(0.0, dt))
		state["elapsed"] = float(state["elapsed"]) + dt
		if not bool(_tune["ENDLESS"]) and float(state["elapsed"]) >= float(_tune["DURATION_SEC"]):
			state["ended"] = true
			events.append({"type": "ended"})
			return events

		if float(state["boostT"]) > 0.0:
			state["boostT"] = maxf(0.0, float(state["boostT"]) - dt)
		if float(state["boostT"]) == 0.0:
			state["boostChain"] = 0
		if float(state["slowT"]) > 0.0:
			state["slowT"] = maxf(0.0, float(state["slowT"]) - dt)
		if float(state["iframesT"]) > 0.0:
			state["iframesT"] = maxf(0.0, float(state["iframesT"]) - dt)

		if bool(input.get("horn", false)):
			if int(state["hornCharges"]) > 0:
				state["hornCharges"] = int(state["hornCharges"]) - 1
				var cleared := 0
				var bow := {"x": float(state["x"]), "z": float(state["z"])}
				for item in items:
					if bool(item["gone"]) or str(item["type"]) != "buoy":
						continue
					if HarborHopperLogic.in_horn_cone(bow, item, _tune):
						item["gone"] = true
						cleared += 1
				events.append({"type": "buoyCleared", "count": cleared})
			else:
				events.append({"type": "hornEmpty"})

		var target_x: Variant = input.get("targetX", null)
		if target_x != null:
			var half_w := float(_tune["CHANNEL_HALF_W"])
			var target := maxf(-half_w + 0.35, minf(half_w - 0.35, float(target_x)))
			var err := target - float(state["x"])
			state["vx"] = (
				float(state["vx"])
				+ maxf(-1.0, minf(1.0, err / 0.9)) * float(_tune["STEER_ACCEL"]) * dt
			)
		state["vx"] = (
			float(state["vx"]) - float(state["vx"]) * minf(1.0, float(_tune["STEER_DAMPING"]) * dt)
		)
		var cap := float(_tune["MAX_LATERAL_SPEED"])
		state["vx"] = maxf(-cap, minf(cap, float(state["vx"])))
		state["x"] = float(state["x"]) + float(state["vx"]) * dt
		var wall_x := float(_tune["CHANNEL_HALF_W"]) - 0.35
		if float(state["x"]) < -wall_x:
			state["x"] = -wall_x
			state["vx"] = absf(float(state["vx"])) * 0.25
		elif float(state["x"]) > wall_x:
			state["x"] = wall_x
			state["vx"] = -absf(float(state["vx"])) * 0.25

		var prev_boat_z := float(state["z"])
		state["z"] = float(state["z"]) + HarborHopperLogic.speed_of(state, _tune) * dt
		_generate_ahead(float(state["z"]) + float(_tune["LOOKAHEAD_M"]))

		if float(state["elapsed"]) >= _next_wave_at:
			var sweet_x := (
				(_rng.next() * 2.0 - 1.0)
				* (float(_tune["CHANNEL_HALF_W"]) - float(_tune["SWEET_HALF_W"]))
			)
			(
				waves
				. append(
					{
						"z": float(state["z"]) + float(_tune["WAVE_SPAWN_AHEAD_M"]),
						"sweetX": sweet_x,
						"ridden": false,
					}
				)
			)
			events.append({"type": "waveSpawn", "sweetX": sweet_x})
			_next_wave_at += float(_tune["WAVE_EVERY_SEC"])
		for wave in waves:
			var prev_z := float(wave["z"])
			wave["z"] = prev_z - float(_tune["WAVE_SPEED"]) * dt
			if (
				not bool(wave["ridden"])
				and prev_z >= prev_boat_z
				and float(wave["z"]) <= float(state["z"])
			):
				if (
					absf(float(state["x"]) - float(wave["sweetX"])) <= float(_tune["SWEET_HALF_W"])
					and float(state["slowT"]) == 0.0
				):
					state["boostChain"] = int(state["boostChain"]) + 1
					state["boostT"] = float(_tune["BOOST_SEC"])
					events.append({"type": "boost", "chain": int(state["boostChain"])})
				wave["ridden"] = true
		for i in range(waves.size() - 1, -1, -1):
			if float(waves[i]["z"]) < float(state["z"]) - 8.0:
				waves.remove_at(i)

		var boat := {"x": float(state["x"]), "z": float(state["z"])}
		for item in items:
			if (
				bool(item["gone"])
				or float(item["z"]) < float(state["z"]) - 2.0
				or float(item["z"]) > float(state["z"]) + 3.0
			):
				continue
			var kind := str(item["type"])
			if (
				kind == "crate"
				and HarborHopperLogic.hits(
					boat,
					item,
					float(_tune["CRATE_RADIUS"]) + float(_tune["BOAT_RADIUS"]),
					false,
					_tune
				)
			):
				item["gone"] = true
				state["crates"] = int(state["crates"]) + 1
				state["score"] = HarborHopperLogic.apply_score(
					int(state["score"]), int(_tune["CRATE_POINTS"])
				)
				events.append({"type": "crate", "item": item})
			elif (
				kind == "ring"
				and HarborHopperLogic.hits(
					boat,
					item,
					float(_tune["RING_RADIUS"]) + float(_tune["BOAT_RADIUS"]),
					false,
					_tune
				)
			):
				item["gone"] = true
				state["rings"] = int(state["rings"]) + 1
				state["score"] = HarborHopperLogic.apply_score(
					int(state["score"]), int(_tune["RING_POINTS"])
				)
				events.append({"type": "ring", "item": item})
			elif (
				kind == "buoy"
				and float(state["iframesT"]) == 0.0
				and HarborHopperLogic.hits(
					boat,
					item,
					float(_tune["BUOY_RADIUS"]) + float(_tune["BOAT_RADIUS"]),
					true,
					_tune
				)
			):
				var away := -1.0 if float(state["x"]) <= float(item["x"]) else 1.0
				state["vx"] = away * float(_tune["BUMP_SHOVE"])
				_bump(events, "buoy")
		if float(state["iframesT"]) == 0.0:
			for pier in piers:
				if absf(float(pier["z"]) - float(state["z"])) > 3.0:
					continue
				if HarborHopperLogic.hits_pier(boat, pier, _tune):
					pier["hit"] = true
					state["vx"] = -float(pier["side"]) * float(_tune["BUMP_SHOVE"])
					_bump(events, "pier")
		for i in range(items.size() - 1, -1, -1):
			if float(items[i]["z"]) < float(state["z"]) - 10.0:
				items.remove_at(i)

		var gull: Dictionary = state["gull"]
		var lane := HarborHopperLogic.lane_of(float(state["x"]), _tune)
		if lane != int(state["lane"]):
			state["lane"] = lane
			state["idleT"] = 0.0
			if str(gull["phase"]) == "warn":
				gull["phase"] = "idle"
				gull["t"] = 0.0
				events.append({"type": "gullLeave"})
		elif int(state["crates"]) > 0:
			state["idleT"] = float(state["idleT"]) + dt
			if (
				str(gull["phase"]) == "idle"
				and float(state["idleT"]) >= float(_tune["GULL_IDLE_SEC"])
			):
				gull["phase"] = "warn"
				gull["t"] = 0.0
				events.append({"type": "gullWarn"})
			elif str(gull["phase"]) == "warn":
				gull["t"] = float(gull["t"]) + dt
				if float(gull["t"]) >= float(_tune["GULL_WARN_SEC"]):
					gull["phase"] = "idle"
					gull["t"] = 0.0
					state["idleT"] = 0.0
					state["crates"] = int(state["crates"]) - 1
					state["steals"] = int(state["steals"]) + 1
					state["score"] = HarborHopperLogic.apply_score(
						int(state["score"]), -int(_tune["CRATE_POINTS"])
					)
					events.append({"type": "gullSteal"})
		else:
			state["idleT"] = 0.0
			if str(gull["phase"]) == "warn":
				gull["phase"] = "idle"
				gull["t"] = 0.0
				events.append({"type": "gullLeave"})

		return events

	func _bump(events: Array[Dictionary], what: String) -> void:
		state["score"] = HarborHopperLogic.apply_score(
			int(state["score"]), int(_tune["BUMP_PENALTY"])
		)
		state["bumps"] = int(state["bumps"]) + 1
		state["slowT"] = float(_tune["SLOW_SEC"])
		state["iframesT"] = float(_tune["BUMP_IFRAMES_SEC"])
		state["boostT"] = 0.0
		state["boostChain"] = 0
		events.append({"type": "bump", "what": what})
		if bool(_tune["ENDLESS"]) and int(state["bumps"]) >= int(_tune["ENDLESS_BUMP_LIMIT"]):
			state["ended"] = true
			events.append({"type": "ended", "reason": "bumps"})

	func _generate_ahead(until_z: float) -> void:
		var gap_row: Dictionary = _tune["ROW_GAP_M"]
		var pier_row: Dictionary = _tune["PIER_EVERY_M"]
		var half_w := float(_tune["CHANNEL_HALF_W"])
		var crate_chance := float(_tune["CRATE_CHANCE"])
		var ring_chance := float(_tune["RING_CHANCE"])
		var buoy_chance := float(_tune["BUOY_CHANCE"])
		while _gen_z < until_z:
			var roll := _rng.next()
			var x := (_rng.next() * 2.0 - 1.0) * (half_w - 0.55)
			if roll < crate_chance:
				items.append({"type": "crate", "x": x, "z": _gen_z, "gone": false})
			elif roll < crate_chance + ring_chance:
				items.append({"type": "ring", "x": x, "z": _gen_z, "gone": false})
			elif roll < crate_chance + ring_chance + buoy_chance:
				items.append({"type": "buoy", "x": x, "z": _gen_z, "gone": false})
			var gap := (
				float(gap_row["min"])
				+ _rng.next() * (float(gap_row["max"]) - float(gap_row["min"]))
			)
			_gen_z += gap
			if (
				float(_tune["PICKUP_RATE"]) > 1.0
				and (
					_rng.next() < (float(_tune["PICKUP_RATE"]) - 1.0) * (crate_chance + ring_chance)
				)
			):
				var px := (_rng.next() * 2.0 - 1.0) * (half_w - 0.55)
				var is_crate := _rng.next() < crate_chance / (crate_chance + ring_chance)
				(
					items
					. append(
						{
							"type": "crate" if is_crate else "ring",
							"x": px,
							"z": _gen_z - gap / 2.0,
							"gone": false,
						}
					)
				)
			if _gen_z >= _next_pier_z:
				var side := 0
				if piers.size() % 2 == 0:
					side = -1 if _rng.next() < 0.5 else 1
				else:
					side = -int(piers[piers.size() - 1]["side"])
				piers.append({"side": side, "z": _next_pier_z, "hit": false})
				_next_pier_z += (
					float(pier_row["min"])
					+ _rng.next() * (float(pier_row["max"]) - float(pier_row["min"]))
				)


## Gieriger Autoplay-Skipper (§C10.1: Kistenpfad + Kammzentrierung).
class Bot:
	extends RefCounted

	var _tune: Dictionary
	var _reach_per_m: float
	var _dodge_to_lane := -1

	func _init(tune := HARBOR) -> void:
		_tune = tune
		_reach_per_m = (
			float(tune["BOT_REACH_X_PER_M"])
			* (float(HARBOR["BASE_SPEED"]) / float(tune["BASE_SPEED"]))
		)

	func control(state: Dictionary, items: Array, piers: Array, waves: Array) -> Dictionary:
		var half_w := float(_tune["CHANNEL_HALF_W"])
		var target_x := 0.0
		var has_target := false

		var best_wave: Dictionary = {}
		for wave: Dictionary in waves:
			if bool(wave["ridden"]) or float(wave["z"]) < float(state["z"]):
				continue
			var dz := float(wave["z"]) - float(state["z"])
			if (
				dz <= float(_tune["BOT_WAVE_M"])
				and (best_wave.is_empty() or dz < float(best_wave["z"]) - float(state["z"]))
			):
				best_wave = wave
		if not best_wave.is_empty():
			target_x = float(best_wave["sweetX"])
			has_target = true

		if not has_target:
			var best: Dictionary = {}
			var best_score := -INF
			for item: Dictionary in items:
				if bool(item["gone"]) or str(item["type"]) == "buoy":
					continue
				var dz := float(item["z"]) - float(state["z"])
				if dz < 1.0 or dz > float(_tune["BOT_SCAN_M"]):
					continue
				var reach := (
					absf(float(item["x"]) - float(state["x"])) / maxf(1.0, dz * _reach_per_m)
				)
				if reach > 1.15:
					continue
				var base := (
					float(_tune["BOT_CRATE_VALUE"])
					if str(item["type"]) == "crate"
					else float(_tune["BOT_RING_VALUE"])
				)
				var value := base - dz * 0.12 - reach
				if value > best_score:
					best_score = value
					best = item
			target_x = float(best["x"]) if not best.is_empty() else float(state["x"]) * 0.6

		var horn := false
		for item: Dictionary in items:
			if bool(item["gone"]) or str(item["type"]) != "buoy":
				continue
			var dz := float(item["z"]) - float(state["z"])
			if dz < 0.4 or dz > float(_tune["BOT_DODGE_M"]):
				continue
			var clearance := (
				(
					(float(_tune["BUOY_RADIUS"]) + float(_tune["BOAT_RADIUS"]))
					* float(_tune["HITBOX_SCALE"])
				)
				+ 0.35
			)
			if absf(float(item["x"]) - target_x) < clearance:
				var off := -clearance if float(state["x"]) <= float(item["x"]) else clearance
				target_x = float(item["x"]) + off
			if (
				dz <= float(_tune["BOT_HORN_M"])
				and absf(float(item["x"]) - float(state["x"])) < clearance * 0.8
				and int(state["hornCharges"]) > 0
			):
				horn = true
		for pier: Dictionary in piers:
			var dz := float(pier["z"]) - float(state["z"])
			if dz < 0.0 or dz > float(_tune["BOT_DODGE_M"]):
				continue
			var inner_edge := half_w - float(_tune["PIER_REACH_M"]) - 0.45
			if int(pier["side"]) < 0:
				target_x = maxf(target_x, -inner_edge)
			else:
				target_x = minf(target_x, inner_edge)

		var gull: Dictionary = state["gull"]
		var lanes := int(_tune["LANES"])
		if (
			_dodge_to_lane < 0
			and int(state["crates"]) > 0
			and (
				str(gull["phase"]) == "warn"
				or float(state["idleT"]) >= float(_tune["BOT_GULL_DODGE_AT_SEC"])
			)
		):
			var lane := HarborHopperLogic.lane_of(float(state["x"]), _tune)
			if lane == 0:
				_dodge_to_lane = 1
			elif lane == lanes - 1:
				_dodge_to_lane = lanes - 2
			else:
				_dodge_to_lane = lane + 1 if target_x >= float(state["x"]) else lane - 1
		if _dodge_to_lane >= 0:
			if float(state["idleT"]) < 0.2 or int(state["crates"]) == 0:
				_dodge_to_lane = -1
			else:
				var lane_w := (half_w * 2.0) / lanes
				target_x = -half_w + lane_w * (_dodge_to_lane + 0.5)

		return {
			"targetX": maxf(-half_w + 0.4, minf(half_w - 0.4, target_x)),
			"horn": horn,
		}


## Kopflose Vollrunde (Tests/Tuning): Maschine + gieriger Bot bei festem dt.
static func simulate_round(seed_value: int, tune := HARBOR, dt := 1.0 / 60.0) -> Dictionary:
	var engine := HarborEngine.new(GoobyRng.new(seed_value), tune)
	var bot := Bot.new(tune)
	var boosts := 0
	var guard := int(ceil((float(tune["DURATION_SEC"]) + 10.0) / dt))
	while not bool(engine.state["ended"]) and guard > 0:
		var c := bot.control(engine.state, engine.items, engine.piers, engine.waves)
		for ev in engine.step(c, dt):
			if str(ev["type"]) == "boost":
				boosts += 1
		guard -= 1
	var s := engine.state
	return {
		"score": int(s["score"]),
		"crates": int(s["crates"]),
		"rings": int(s["rings"]),
		"bumps": int(s["bumps"]),
		"steals": int(s["steals"]),
		"boosts": boosts,
		"distanceM": int(floorf(float(s["z"]))),
		"hornsUsed": int(tune["HORN_CHARGES"]) - int(s["hornCharges"]),
	}


## §G5.4-Zertifikatslauf: eine volle Bot-Runde mit Aufmerksamkeits-Modell
## (Fokus-Abklingzeit nach Aufsammeln + gesäte kurze Steuer-Aussetzer).
static func simulate_autoplay(
	mode := "normal", seed_value := 1, max_sec := 900.0, modifier := {}
) -> Dictionary:
	var tune := apply_modifier(apply_difficulty(HARBOR, mode), modifier)
	var engine := HarborEngine.new(GoobyRng.new(seed_value), tune)
	var bot := Bot.new(tune)
	var lapse := GoobyRng.new((seed_value ^ 0x9D2C5681) & 0xFFFFFFFF)
	var lapse_every := float(tune["BOT_LAPSE_EVERY_SEC"])
	if lapse_every <= 0.0:
		lapse_every = INF
	var next_lapse := lapse_every * (0.5 + lapse.next())
	var lapse_t := 0.0
	var boosts := 0
	var focus_t := 0.0
	var dt := 1.0 / 60.0
	var guard := int(ceil(max_sec / dt))
	while not bool(engine.state["ended"]) and guard > 0:
		var seen: Array = engine.items
		if focus_t > 0.0:
			var only_buoys: Array[Dictionary] = []
			for item in engine.items:
				if str(item["type"]) == "buoy":
					only_buoys.append(item)
			seen = only_buoys
		var c := bot.control(engine.state, seen, engine.piers, engine.waves)
		next_lapse -= dt
		if next_lapse <= 0.0 and lapse_t <= 0.0:
			lapse_t = 0.7 + lapse.next() * 0.9
			next_lapse = lapse_every * (0.5 + lapse.next())
		if lapse_t > 0.0:
			lapse_t -= dt
			c["targetX"] = null
			c["horn"] = false
		for ev in engine.step(c, dt):
			var kind := str(ev["type"])
			if kind == "boost":
				boosts += 1
			if kind == "crate" or kind == "ring":
				focus_t = float(tune["BOT_FOCUS_SEC"])
		if focus_t > 0.0:
			focus_t -= dt
		guard -= 1
	var s := engine.state
	return {
		"score": hopper_score(s, tune),
		"crates": int(s["crates"]),
		"rings": int(s["rings"]),
		"bumps": int(s["bumps"]),
		"steals": int(s["steals"]),
		"boosts": boosts,
		"distanceM": int(floorf(float(s["z"]))),
		"elapsed": float(s["elapsed"]),
	}
