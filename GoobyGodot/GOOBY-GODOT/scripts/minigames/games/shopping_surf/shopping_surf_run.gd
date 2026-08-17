class_name ShoppingSurfRun
extends RefCounted
## Lauf-Simulation für Einkaufs-Surf — zahlengleicher Port des Simulations-
## teils von GOOBY/src/minigames/games/shoppingSurf.logic.js (§C8.2–§C8.7).
## Reine Mathematik: der View füttert nur Eingaben hinein und spielt die
## zurückgegebene Ereignisliste als Klang/Partikel ab. Tuning, Straßenbau-
## steine und der Überlebbarkeits-Validator liegen in `shopping_surf_logic.gd`.

const Logic := preload("res://scripts/minigames/games/shopping_surf/shopping_surf_logic.gd")


## Frischer Laufzustand. `mode` ist "arcade" oder "travel" (§C8.6).
static func create_run(rng: GoobyRng, mode := "arcade", tune := Logic.SURF) -> Dictionary:
	return {
		"tune": tune,
		"rng": rng,
		"mode": "travel" if Logic.is_travel_mode(mode) else "arcade",
		"elapsed": 0.0,
		"distanceM": 0.0,
		"rampSec": 0.0,
		"speed": float(tune["BASE_SPEED"]),
		"slowT": 0.0,
		# Spieler
		"lane": 1,
		"fromX": float((tune["LANE_X"] as Array)[1]),
		"laneT": 1.0,
		"jumpT": -1.0,
		"slideT": -1.0,
		"fastDrop": false,
		"fastDropY": 0.0,
		"buffered": {},
		# Crash-/Juice-Zustand
		"crashes": 0,
		"stumbleT": 0.0,
		"invulnT": 0.0,
		"coins": 0,
		"nearMisses": 0,
		"nearStreak": 0,
		"powerupsCollected": 0,
		"pu": {"magnetT": 0.0, "x2T": 0.0, "shield": false, "turboT": 0.0},
		"lastPowerupKind": null,
		"lastTurboAtM": -INF,
		"nextPowerupAtM": 0.0,
		# Reise
		"jog": false,
		"finished": false,
		"ended": false,
		# Straßen-Nachschub
		"chunksEndM": 0.0,
		"lastChunk": -1,
		"recentHazards": [],
		"pendingHazards": [],
		"pendingCoins": [],
		"obstacles": [],
		"coinItems": [],
		"powerupItems": [],
		"nextId": 1,
	}


## Geglättete Spur-x-Position des Spielers (m).
static func player_x(run: Dictionary) -> float:
	var t := minf(1.0, float(run["laneT"]))
	var e := t * t * (3.0 - 2.0 * t)
	var target := float((run["tune"]["LANE_X"] as Array)[int(run["lane"])])
	return float(run["fromX"]) + (target - float(run["fromX"])) * e


## Sprunghöhe des Spielers (m).
static func player_y(run: Dictionary) -> float:
	if float(run["jumpT"]) < 0.0:
		return 0.0
	if bool(run["fastDrop"]):
		return float(run["fastDropY"])
	var tune: Dictionary = run["tune"]
	return float(tune["JUMP_HEIGHT"]) * sin(float(run["jumpT"]) / float(tune["JUMP_SEC"]) * PI)


## Aktuelles Vorwärtstempo inkl. Jogging/Turbo/Pfütze/Stolpern (m/s).
static func current_speed(run: Dictionary) -> float:
	var tune: Dictionary = run["tune"]
	if bool(run["ended"]):
		return 0.0
	if bool(run["jog"]):
		return float((tune["TRAVEL"] as Dictionary)["JOG_SPEED"])
	var v := Logic.speed_ramp_at(float(run["rampSec"]), tune)
	if float(run["pu"]["turboT"]) > 0.0:
		v *= float((tune["POWERUPS"] as Dictionary)["turbo"]["speedMult"])
	if float(run["slowT"]) > 0.0:
		v *= float((tune["OBSTACLES"] as Dictionary)["puddle"]["slowMult"])
	if float(run["stumbleT"]) > 0.0:
		v *= float(tune["STUMBLE_SPEED_MULT"])
	return v


## §C8.2 Spurwechsel; mitten im Tween gewischte Eingaben wandern in den Puffer.
static func _try_lane(run: Dictionary, type: String, events: Array) -> bool:
	if float(run["laneT"]) < 0.65:
		return false
	var tune: Dictionary = run["tune"]
	var dir := -1 if type == "left" else 1
	var next := clampi(int(run["lane"]) + dir, 0, int(tune["LANES"]) - 1)
	if next != int(run["lane"]):
		run["fromX"] = player_x(run)
		run["lane"] = next
		run["laneT"] = 0.0
		events.append({"type": "lane", "dir": dir})
	return true


static func _try_slide(run: Dictionary, events: Array) -> bool:
	if float(run["jumpT"]) >= 0.0:
		# §C8.2 Wisch-nach-unten in der Luft = Schnellfall (Höhe VOR dem Flag
		# einfrieren — player_y liest fastDropY, sobald fastDrop gesetzt ist).
		if not bool(run["fastDrop"]):
			run["fastDropY"] = player_y(run)
			run["fastDrop"] = true
			events.append({"type": "fastDrop"})
		return true
	if float(run["slideT"]) >= 0.0:
		return false
	run["slideT"] = 0.0
	events.append({"type": "slide"})
	return true


## Aktion starten (oder ablehnen, dann puffert der Aufrufer).
static func _try_action(run: Dictionary, type: String, events: Array) -> bool:
	if type == "left" or type == "right":
		return _try_lane(run, type, events)
	if type == "jump":
		if float(run["jumpT"]) >= 0.0 or float(run["slideT"]) >= 0.0:
			return false
		run["jumpT"] = 0.0
		run["fastDrop"] = false
		events.append({"type": "jump"})
		return true
	if type == "slide":
		return _try_slide(run, events)
	return false


## Eingaben (flankengetriggert) mit dem 250-ms-Einzelpuffer verarbeiten.
static func _apply_input(run: Dictionary, input: Dictionary, events: Array) -> void:
	if input.is_empty() or bool(run["ended"]) or bool(run["finished"]):
		return
	var wants: Array[String] = []
	for key in ["left", "right", "jump", "slide"]:
		if bool(input.get(key, false)):
			wants.append(str(key))
	for type in wants:
		if not _try_action(run, type, events):
			run["buffered"] = {"type": type, "t": 0.0}
	var buffered: Dictionary = run["buffered"]
	if not buffered.is_empty() and _try_action(run, str(buffered["type"]), events):
		run["buffered"] = {}


## Bausteine in die Warteschlangen schieben (gesät bzw. validator-gesichert).
static func _enqueue_chunks(run: Dictionary) -> void:
	var tune: Dictionary = run["tune"]
	var chunk_len := float(tune["CHUNK_LEN_M"])
	var gated := bool(tune["GATED_SPAWNS"])
	while (
		float(run["chunksEndM"])
		< float(run["distanceM"]) + float(tune["SPAWN_AHEAD_M"]) + chunk_len
	):
		var start_m := float(run["chunksEndM"])
		var idx := -1
		if gated:
			# Dichte Nähte sind genau die Stelle, an der naives Skalieren die
			# Nie-unmöglich-Garantie bricht — daher der Validator im Gate.
			var window: Array = []
			for h: Dictionary in run["recentHazards"]:
				if float(h["atM"]) > start_m - chunk_len * 2.0:
					window.append(h)
			run["recentHazards"] = window
			idx = Logic.pick_next_survivable_chunk(
				run["rng"], start_m, int(run["lastChunk"]), window, tune
			)
			if idx < 0:
				run["chunksEndM"] = start_m + chunk_len * 0.35
				continue
		else:
			idx = Logic.pick_next_chunk(run["rng"], start_m, int(run["lastChunk"]), tune)
		var parts := Logic.expand_chunk(Logic.CHUNKS[idx], start_m)
		(run["pendingHazards"] as Array).append_array(parts["hazards"])
		(run["pendingCoins"] as Array).append_array(parts["coins"])
		run["lastChunk"] = idx
		if gated:
			(run["recentHazards"] as Array).append_array(parts["hazards"])
			run["chunksEndM"] = start_m + chunk_len / Logic.density_mult_at(start_m, tune)
		else:
			run["chunksEndM"] = start_m + chunk_len


## Ein wartendes Hindernis zu einem Welt-Objekt machen.
static func _materialize_hazard(run: Dictionary, h: Dictionary) -> Dictionary:
	var tune: Dictionary = run["tune"]
	var lane_x: Array = tune["LANE_X"]
	var kind := str(h["kind"])
	var def: Dictionary = (tune["OBSTACLES"] as Dictionary)[kind]
	var x := float(lane_x[int(h.get("lane", 1))])
	var half_w := 99.0 if kind == "gap" else float(def.get("halfW", 0.0))
	if kind == "npc":
		x = -(float(lane_x[int(tune["LANES"]) - 1]) + 1.0)  # §C8.3: quert L→R
	elif kind == "awning":
		var lanes: Array = h["lanes"]
		var lo: int = lanes.min()
		var hi: int = lanes.max()
		x = (float(lane_x[lo]) + float(lane_x[hi])) / 2.0
		half_w = ((hi - lo) * float(tune["LANE_W"]) + float(tune["LANE_W"]) * 0.92) / 2.0
	run["nextId"] = int(run["nextId"]) + 1
	return {
		"id": int(run["nextId"]) - 1,
		"kind": kind,
		"def": def,
		"lane": h.get("lane"),
		"lanes": h.get("lanes"),
		"z": -(float(h["atM"]) - float(run["distanceM"])),
		"x": x,
		"halfW": half_w,
		"telegraphed": false,
		"hit": false,
		"minClear": INF,
		"passed": false,
	}


static func _spawn_hazards(run: Dictionary, horizon: float, events: Array) -> void:
	var tune: Dictionary = run["tune"]
	var no_hazards := bool(run["jog"]) or bool(run["finished"])
	var finish_m := float((tune["TRAVEL"] as Dictionary)["DISTANCE_M"])
	var keep: Array = []
	for h: Dictionary in run["pendingHazards"]:
		if float(h["atM"]) > horizon:
			keep.append(h)
			continue
		if no_hazards:
			continue
		# Reise: nie ein Hindernis hinter dem Zielbogen einblenden.
		if run["mode"] == "travel" and float(h["atM"]) >= finish_m - 4.0:
			continue
		var ob := _materialize_hazard(run, h)
		(run["obstacles"] as Array).append(ob)
		events.append({"type": "spawn", "ob": ob})
	run["pendingHazards"] = keep


static func _spawn_coins(run: Dictionary, horizon: float) -> void:
	var tune: Dictionary = run["tune"]
	var lane_x: Array = tune["LANE_X"]
	var step := float(tune["COIN_STEP_M"])
	var keep: Array = []
	for c: Dictionary in run["pendingCoins"]:
		if float(c["atM"]) > horizon:
			keep.append(c)
			continue
		var n := Logic.coin_row_count(run["rng"], int(c["n"]), tune)
		for i in n:
			var z_off := (i - (n - 1) / 2.0) * step
			var y := float(tune["COIN_Y"])
			if bool(c.get("arc", false)):
				var phase := z_off / (n * step / 2.0) * PI / 2.0
				y += float(tune["JUMP_HEIGHT"]) * 0.85 * pow(cos(phase), 2.0)
			run["nextId"] = int(run["nextId"]) + 1
			(
				(run["coinItems"] as Array)
				. append(
					{
						"id": int(run["nextId"]) - 1,
						"lane": int(c["lane"]),
						"x": float(lane_x[int(c["lane"])]),
						"y": y,
						"z": -(float(c["atM"]) - float(run["distanceM"])) + z_off,
						"attracted": false,
					}
				)
			)
	run["pendingCoins"] = keep


static func _spawn_powerup(run: Dictionary, horizon: float) -> void:
	var tune: Dictionary = run["tune"]
	if bool(run["finished"]) or float(run["nextPowerupAtM"]) > horizon:
		return
	var at_m := float(run["nextPowerupAtM"])
	var since_turbo := at_m - float(run["lastTurboAtM"])
	var kind := Logic.plan_powerup_kind(run["rng"], run["lastPowerupKind"], since_turbo, tune)
	var lane := int(floor(run["rng"].next() * int(tune["LANES"]))) % int(tune["LANES"])
	var finish_m := float((tune["TRAVEL"] as Dictionary)["DISTANCE_M"])
	if not (run["mode"] == "travel" and at_m >= finish_m - 6.0):
		run["nextId"] = int(run["nextId"]) + 1
		(
			(run["powerupItems"] as Array)
			. append(
				{
					"id": int(run["nextId"]) - 1,
					"kind": kind,
					"lane": lane,
					"x": float((tune["LANE_X"] as Array)[lane]),
					"z": -(at_m - float(run["distanceM"])),
				}
			)
		)
	if kind == "turbo":
		run["lastTurboAtM"] = at_m
	run["lastPowerupKind"] = kind
	run["nextPowerupAtM"] = at_m + Logic.plan_powerup_gap(run["rng"], tune)


static func _spawn_step(run: Dictionary, events: Array) -> void:
	var tune: Dictionary = run["tune"]
	if float(run["nextPowerupAtM"]) == 0.0:
		run["nextPowerupAtM"] = Logic.plan_powerup_gap(run["rng"], tune)
	_enqueue_chunks(run)
	var horizon := float(run["distanceM"]) + float(tune["SPAWN_AHEAD_M"])
	_spawn_hazards(run, horizon, events)
	_spawn_coins(run, horizon)
	_spawn_powerup(run, horizon)


## Ein-Frame-Trefferprüfung gegen ein Hindernis an seinem AKTUELLEN z.
static func _hits_now(run: Dictionary, ob: Dictionary, px: float, py: float, sliding: bool) -> bool:
	var tune: Dictionary = run["tune"]
	var def: Dictionary = ob["def"]
	if absf(float(ob["z"])) > float(def["halfDepth"]) + float(tune["PLAYER_HALF_DEPTH"]):
		return false
	if ob["kind"] == "gap":
		# Bordstein-Bruch über die ganze Breite: am Boden im Loch = Crash.
		return py < 0.12 and absf(float(ob["z"])) < float(def["halfDepth"])
	if absf(px - float(ob["x"])) >= float(ob["halfW"]) + float(tune["PLAYER_HALF_W"]):
		return false
	var pass_kind := str(def["pass"])
	if pass_kind == "jump":
		return py < float(def["clearY"])
	if pass_kind == "slide":
		return not (sliding and float(tune["SLIDE_HEIGHT"]) <= float(def["gapY"]))
	return (py < 0.1) if pass_kind == "soft" else true


## Abgetasteter Trefferschlauch über den Frame-Vorschub dz (Anti-Tunneling).
static func _sweep_hits(
	run: Dictionary, ob: Dictionary, dz: float, px: float, py: float, sliding: bool
) -> bool:
	var steps := maxi(1, int(ceil(absf(dz) / float(run["tune"]["MAX_SWEEP_STEP_M"]))))
	var z0 := float(ob["z"])
	var hit := false
	for i in range(1, steps + 1):
		ob["z"] = z0 + dz * i / steps
		if _hits_now(run, ob, px, py, sliding):
			hit = true
			break
	ob["z"] = z0
	return hit


## §C8.3 Treffer auflösen (+ §C8.4 Schild/Turbo).
static func _handle_hit(run: Dictionary, ob: Dictionary, events: Array) -> void:
	var tune: Dictionary = run["tune"]
	var pu: Dictionary = run["pu"]
	if ob["kind"] == "puddle":
		if bool(ob["hit"]) or float(pu["turboT"]) > 0.0:
			return
		ob["hit"] = true
		run["slowT"] = float((tune["OBSTACLES"] as Dictionary)["puddle"]["slowSec"])
		events.append({"type": "puddle", "id": ob["id"]})
		return
	if float(pu["turboT"]) > 0.0 or float(run["invulnT"]) > 0.0:
		return
	ob["hit"] = true
	if bool(pu["shield"]):
		pu["shield"] = false
		run["invulnT"] = float(tune["INVULN_SEC"])
		events.append({"type": "shieldPop", "id": ob["id"]})
		return
	run["crashes"] = int(run["crashes"]) + 1
	run["stumbleT"] = float(tune["STUMBLE_SEC"])
	run["invulnT"] = float(tune["INVULN_SEC"])
	run["rampSec"] = 0.0  # §C8.3: Tempo fällt auf die Basis zurück
	run["nearStreak"] = 0
	events.append(
		{"type": "crash", "id": ob["id"], "kind": ob["kind"], "crashes": int(run["crashes"])}
	)
	var max_crashes := int(tune["ARCADE_MAX_CRASHES"])
	if run["mode"] == "arcade" and int(run["crashes"]) >= max_crashes:
		run["ended"] = true
		events.append({"type": "wipeout"})
	elif run["mode"] == "travel" and int(run["crashes"]) >= max_crashes and not bool(run["jog"]):
		# §C8.6 Nachsicht: feste 7 m/s im Trab, keine Hindernisse mehr.
		run["jog"] = true
		(run["obstacles"] as Array).clear()
		(run["pendingHazards"] as Array).clear()
		events.append({"type": "jogStart"})


## Alterung des Eingabepuffers — läuft VOR der Eingabeverarbeitung.
static func _age_buffer(run: Dictionary, dt: float) -> void:
	var buffered: Dictionary = run["buffered"]
	if buffered.is_empty():
		return
	buffered["t"] = float(buffered["t"]) + dt
	if float(buffered["t"]) > float(run["tune"]["BUFFER_SEC"]):
		run["buffered"] = {}


## Ablaufende Zeitgeber (Unverwundbarkeit, Stolpern, Pfütze, Power-ups).
static func _step_timers(run: Dictionary, dt: float, events: Array) -> void:
	run["invulnT"] = maxf(0.0, float(run["invulnT"]) - dt)
	run["stumbleT"] = maxf(0.0, float(run["stumbleT"]) - dt)
	run["slowT"] = maxf(0.0, float(run["slowT"]) - dt)
	var pu: Dictionary = run["pu"]
	for key in ["magnetT", "x2T", "turboT"]:
		if float(pu[key]) <= 0.0:
			continue
		pu[key] = float(pu[key]) - dt
		if float(pu[key]) <= 0.0:
			pu[key] = 0.0
			events.append({"type": "powerupEnd", "kind": str(key).trim_suffix("T")})


static func _step_player(run: Dictionary, dt: float, events: Array) -> void:
	var tune: Dictionary = run["tune"]
	if float(run["jumpT"]) >= 0.0:
		var landed := false
		if bool(run["fastDrop"]):
			run["fastDropY"] = float(run["fastDropY"]) - float(tune["FAST_DROP_SPEED"]) * dt
			landed = float(run["fastDropY"]) <= 0.0
		else:
			run["jumpT"] = float(run["jumpT"]) + dt
			landed = float(run["jumpT"]) >= float(tune["JUMP_SEC"])
		if landed:
			run["jumpT"] = -1.0
			run["fastDrop"] = false
			events.append({"type": "land"})
			_flush_buffer(run, events)
	if float(run["slideT"]) >= 0.0:
		run["slideT"] = float(run["slideT"]) + dt
		if float(run["slideT"]) >= float(tune["SLIDE_SEC"]):
			run["slideT"] = -1.0
			_flush_buffer(run, events)
	if float(run["laneT"]) < 1.0:
		run["laneT"] = minf(1.0, float(run["laneT"]) + dt / float(tune["LANE_CHANGE_SEC"]))


static func _flush_buffer(run: Dictionary, events: Array) -> void:
	var buffered: Dictionary = run["buffered"]
	if not buffered.is_empty() and _try_action(run, str(buffered["type"]), events):
		run["buffered"] = {}


## Beinahe-Treffer-Buchführung (nur Wagen/Kisten/Passanten — §C8.3).
static func _track_near_miss(
	run: Dictionary, ob: Dictionary, px: float, py: float, events: Array
) -> void:
	var tune: Dictionary = run["tune"]
	var def: Dictionary = ob["def"]
	var window := float(def["halfDepth"]) + float(tune["PLAYER_HALF_DEPTH"]) + 0.4
	var z := float(ob["z"])
	if absf(z) <= window:
		var lat_clear := (
			absf(px - float(ob["x"])) - (float(ob["halfW"]) + float(tune["PLAYER_HALF_W"]))
		)
		var clear := INF
		if lat_clear > 0.0:
			clear = lat_clear
		elif str(def["pass"]) == "jump" and py > float(def["clearY"]):
			clear = py - float(def["clearY"])
		ob["minClear"] = minf(float(ob["minClear"]), clear)
	elif z > window and not bool(ob["passed"]):
		ob["passed"] = true
		var min_clear := float(ob["minClear"])
		if min_clear > 0.0 and min_clear <= float(tune["NEAR_MISS_M"]):
			run["nearMisses"] = int(run["nearMisses"]) + 1
			run["nearStreak"] = int(run["nearStreak"]) + 1
			events.append({"type": "nearMiss", "id": ob["id"], "streak": int(run["nearStreak"])})


static func _step_obstacles(run: Dictionary, dt: float, speed: float, events: Array) -> void:
	var tune: Dictionary = run["tune"]
	var px := player_x(run)
	var py := player_y(run)
	var sliding := float(run["slideT"]) >= 0.0
	var obstacles: Array = run["obstacles"]
	var i := obstacles.size() - 1
	while i >= 0:
		var ob: Dictionary = obstacles[i]
		var def: Dictionary = ob["def"]
		var approach := speed + float(def["ownSpeed"])
		var telegraph := float(def.get("telegraphSec", 0.0))
		if (
			not bool(ob["telegraphed"])
			and telegraph > 0.0
			and -float(ob["z"]) / maxf(0.001, approach) <= telegraph
		):
			ob["telegraphed"] = true
			events.append({"type": "telegraph", "id": ob["id"], "kind": ob["kind"]})
		var dz := approach * dt
		var soft := str(def["pass"]) == "soft"
		var hit := (
			not bool(run["finished"])
			and not bool(ob["hit"])
			and (soft or float(run["invulnT"]) <= 0.0)
			and _sweep_hits(run, ob, dz, px, py, sliding)
		)
		ob["z"] = float(ob["z"]) + dz
		if ob["kind"] == "npc":
			ob["x"] = float(ob["x"]) + float(def["crossSpeed"]) * dt
		if not bool(ob["hit"]) and ob["kind"] in ["cart", "crate", "npc"]:
			_track_near_miss(run, ob, px, py, events)
		if hit:
			_handle_hit(run, ob, events)
		# _handle_hit kann die Welt mitten in der Schleife beenden (Arcade-Aus)
		# oder run["obstacles"] leeren (3. Reise-Crash) — dann ist der Zeiger
		# veraltet und wir brechen ab.
		if bool(run["ended"]) or i >= obstacles.size():
			break
		if float(ob["z"]) > float(tune["DESPAWN_Z"]):
			obstacles.remove_at(i)
		i -= 1


static func _step_coins(run: Dictionary, dt: float, speed: float, events: Array) -> void:
	var tune: Dictionary = run["tune"]
	var pu: Dictionary = run["pu"]
	var px := player_x(run)
	var py := player_y(run)
	var coin_value := 2 if float(pu["x2T"]) > 0.0 else 1
	var magnet_r := (
		float((tune["POWERUPS"] as Dictionary)["magnet"]["radius"])
		if float(pu["magnetT"]) > 0.0
		else 0.0
	)
	var coins: Array = run["coinItems"]
	var i := coins.size() - 1
	while i >= 0:
		var c: Dictionary = coins[i]
		if not bool(c["attracted"]):
			c["z"] = float(c["z"]) + speed * dt
			var d := _hypot3(float(c["x"]) - px, float(c["z"]), float(c["y"]) - (py + 0.6))
			if magnet_r > 0.0 and d < magnet_r:
				c["attracted"] = true
			elif (
				float(pu["turboT"]) > 0.0
				and absf(float(c["x"]) - px) < 1.0
				and float(c["z"]) > -2.5
				and float(c["z"]) < 1.0
			):
				c["attracted"] = true
		else:
			_pull_coin(c, px, py + 0.6, float(tune["MAGNET_PULL_SPEED"]) * dt, speed * dt * 0.2)
		var collected := false
		if bool(c["attracted"]):
			collected = (
				_hypot3(float(c["x"]) - px, float(c["z"]), float(c["y"]) - (py + 0.6)) < 0.55
			)
		else:
			collected = (
				absf(float(c["z"])) < 0.6
				and absf(float(c["x"]) - px) < 0.7
				and absf(py + float(tune["COIN_Y"]) - float(c["y"])) < 0.85
			)
		if collected:
			run["coins"] = int(run["coins"]) + coin_value
			events.append(
				{"type": "coin", "x": c["x"], "y": c["y"], "z": c["z"], "value": coin_value}
			)
			coins.remove_at(i)
		elif float(c["z"]) > float(tune["DESPAWN_Z"]):
			coins.remove_at(i)
		i -= 1


static func _pull_coin(c: Dictionary, tx: float, ty: float, step: float, drift: float) -> void:
	var dx := tx - float(c["x"])
	var dy := ty - float(c["y"])
	var dz := -float(c["z"])
	var d := _hypot3(dx, dy, dz)
	if d == 0.0:
		d = 1.0
	c["x"] = float(c["x"]) + dx / d * step
	c["y"] = float(c["y"]) + dy / d * step
	c["z"] = float(c["z"]) + dz / d * step + drift


static func _step_powerups(run: Dictionary, dt: float, speed: float, events: Array) -> void:
	var tune: Dictionary = run["tune"]
	var powers: Dictionary = tune["POWERUPS"]
	var pu: Dictionary = run["pu"]
	var px := player_x(run)
	var py := player_y(run)
	var items: Array = run["powerupItems"]
	var i := items.size() - 1
	while i >= 0:
		var p: Dictionary = items[i]
		p["z"] = float(p["z"]) + speed * dt
		if absf(float(p["z"])) < 0.8 and absf(float(p["x"]) - px) < 0.9 and py < 1.6:
			var kind := str(p["kind"])
			if kind == "magnet":
				pu["magnetT"] = float((powers["magnet"] as Dictionary)["sec"])
			elif kind == "x2":
				pu["x2T"] = float((powers["x2"] as Dictionary)["sec"])
			elif kind == "shield":
				pu["shield"] = true
			elif kind == "turbo":
				pu["turboT"] = float((powers["turbo"] as Dictionary)["sec"])
			run["powerupsCollected"] = int(run["powerupsCollected"]) + 1
			events.append({"type": "powerup", "kind": kind})
			items.remove_at(i)
		elif float(p["z"]) > float(tune["DESPAWN_Z"]):
			items.remove_at(i)
		i -= 1


## Den Lauf um dt Sekunden weiterdrehen; liefert die Ereignisse für den View:
## lane/jump/slide/fastDrop · spawn · telegraph · crash · wipeout · jogStart ·
## shieldPop · puddle · nearMiss · coin · powerup · powerupEnd · finish.
static func step_run(run: Dictionary, dt: float, input := {}) -> Array:
	var tune: Dictionary = run["tune"]
	var events: Array = []
	if bool(run["ended"]):
		return events
	run["elapsed"] = float(run["elapsed"]) + dt
	if not bool(run["finished"]):
		run["rampSec"] = float(run["rampSec"]) + dt
	_age_buffer(run, dt)
	_apply_input(run, input, events)
	_step_timers(run, dt, events)
	_step_player(run, dt, events)

	var speed := current_speed(run)
	run["speed"] = speed
	run["distanceM"] = float(run["distanceM"]) + speed * dt

	# §C8.6 Zielbogen
	var finish_m := float((tune["TRAVEL"] as Dictionary)["DISTANCE_M"])
	if (
		run["mode"] == "travel"
		and not bool(run["finished"])
		and float(run["distanceM"]) >= finish_m
	):
		run["finished"] = true
		events.append(
			{"type": "finish", "coinsCollected": int(run["coins"]), "crashes": int(run["crashes"])}
		)

	_spawn_step(run, events)
	_step_obstacles(run, dt, speed, events)
	if bool(run["ended"]):
		return events
	_step_coins(run, dt, speed, events)
	_step_powerups(run, dt, speed, events)
	return events


## §C8.5 Punktestand (× Turbo-SCORE_MULT).
static func run_score(run: Dictionary) -> int:
	var raw := Logic.surf_score(float(run["distanceM"]), int(run["coins"]), int(run["nearMisses"]))
	return MinigameFrameworkLogic.js_round(raw * float(run["tune"].get("SCORE_MULT", 1.0)))


## §B3 Meta-Nutzlast für onEnd (beide Modi).
static func run_meta(run: Dictionary) -> Dictionary:
	return {
		"distanceM": MinigameFrameworkLogic.js_round(float(run["distanceM"])),
		"coins": int(run["coins"]),
		"coinsCollected": int(run["coins"]),
		"nearMisses": int(run["nearMisses"]),
		"powerups": int(run["powerupsCollected"]),
		"crashes": int(run["crashes"]),
		"surfRun": true,
	}


## Wie bedrohlich ist ein Hindernis für eine Spur-x-Position gerade jetzt?
static func _blocks_lane_at(
	ob: Dictionary, lane_x: float, tune: Dictionary, ahead_sec: float, speed: float
) -> Dictionary:
	var def: Dictionary = ob["def"]
	if str(def["pass"]) == "soft":
		return {}
	var tta := -float(ob["z"]) / maxf(0.001, speed + float(def["ownSpeed"]))
	if tta < -0.05 or tta > ahead_sec:
		return {}
	var x := float(ob["x"])
	if ob["kind"] == "npc":
		x += float(def["crossSpeed"]) * tta  # wo er SEIN WIRD
	var half_w := 99.0 if ob["kind"] == "gap" else float(ob["halfW"])
	if absf(x - lane_x) >= half_w + float(tune["PLAYER_HALF_W"]) + 0.05:
		return {}
	return {"tta": tta, "pass": str(def["pass"])}


static func _threat_table(run: Dictionary, plan_sec: float, speed: float) -> Array:
	var tune: Dictionary = run["tune"]
	var lane_x: Array = tune["LANE_X"]
	var threats: Array = []
	for lane in int(tune["LANES"]):
		var best := {}
		for ob: Dictionary in run["obstacles"]:
			var b := _blocks_lane_at(ob, float(lane_x[lane]), tune, plan_sec, speed)
			if not b.is_empty() and (best.is_empty() or float(b["tta"]) < float(best["tta"])):
				best = b
		threats.append(best)
	return threats


## Sofort nötige Aktion in der eigenen Spur (leer = nichts Dringendes).
static func _bot_urgent(run: Dictionary, threats: Array) -> Dictionary:
	var tune: Dictionary = run["tune"]
	var my_lane := int(run["lane"])
	var my: Dictionary = threats[my_lane]
	var free := float(run["jumpT"]) < 0.0 and float(run["slideT"]) < 0.0
	if my.is_empty():
		return {}
	var tta := float(my["tta"])
	if my["pass"] == "jump" and tta <= float(tune["JUMP_SEC"]) * 0.5 and free:
		return {"jump": true}
	if my["pass"] == "slide" and tta <= float(tune["SLIDE_SEC"]) * 0.55 and free:
		return {"slide": true}
	if my["pass"] != "none":
		return {}
	var v: Dictionary = tune["VALIDATOR"]
	if tta > float(v["REACT_SEC"]) + float(v["LANE_COST_SEC"]) + 0.7:
		return {}
	# Harter Blocker (Kistenwand) — zum besten Nachbarn ausweichen.
	var options: Array[int] = []
	for l in [my_lane - 1, my_lane + 1]:
		if l >= 0 and l < int(tune["LANES"]):
			options.append(l)
	# Web: aufsteigend nach tta sortieren, DANN umdrehen — bei Gleichstand
	# ergibt das die umgekehrte Ausgangsreihenfolge (rechts vor links).
	options.sort_custom(
		func(a: int, b: int) -> bool: return _tta_of(threats[a]) < _tta_of(threats[b])
	)
	options.reverse()
	for l in options:
		var t: Dictionary = threats[l]
		if t.is_empty() or _tta_of(t) > tta + 0.5 or t["pass"] != "none":
			return {"left": true} if l < my_lane else {"right": true}
	return {}  # komplett eingekesselt (der Validator schließt das aus)


static func _tta_of(threat: Dictionary) -> float:
	return 99.0 if threat.is_empty() else float(threat["tta"])


## Wert der Spuren (Münzen, dann Power-ups) für die Sammel-Drift.
static func _bot_drift(run: Dictionary, threats: Array) -> Dictionary:
	var tune: Dictionary = run["tune"]
	var lanes := int(tune["LANES"])
	var value: Array[int] = []
	for _i in lanes:
		value.append(0)
	for c: Dictionary in run["coinItems"]:
		if float(c["z"]) > -14.0 and float(c["z"]) < -2.0 and float(c["y"]) < 0.9:
			value[int(c["lane"])] += 1
	for p: Dictionary in run["powerupItems"]:
		if float(p["z"]) > -18.0 and float(p["z"]) < -2.0:
			value[int(p["lane"])] += 6
	var v: Dictionary = tune["VALIDATOR"]
	var action_gap := (
		float(tune["LANE_CHANGE_SEC"]) + float(v["REACT_SEC"]) + float(v["ACTION_LEAD_SEC"]) + 0.25
	)
	var my_lane := int(run["lane"])
	var target := my_lane
	for l in [my_lane, my_lane - 1, my_lane + 1]:
		if l < 0 or l >= lanes:
			continue
		var t: Dictionary = threats[l]
		# Eine Aktions-Spur zählt nur als sicher, wenn der Tween UND der
		# Sprung/Rutsch noch reinpassen — sonst rennt der Bot in den Wagen.
		var actionable: bool = t.is_empty() or t["pass"] == "jump" or t["pass"] == "slide"
		var safe := (
			t.is_empty() or float(t["tta"]) > 1.4 or (actionable and float(t["tta"]) > action_gap)
		)
		if safe and value[l] > value[target] + (0 if l == my_lane else 1):
			target = l
	if target == my_lane:
		return {}
	return {"left": true} if target < my_lane else {"right": true}


## §C8.7 deterministische Bot-Eingabe: sichere Spur halten (rund einen
## Baustein vorausplanend), Sprünge/Rutscher timen, sonst zu Münzen driften.
static func bot_input(run: Dictionary) -> Dictionary:
	var tune: Dictionary = run["tune"]
	if bool(run["ended"]) or bool(run["finished"]):
		return {}
	var speed := maxf(1.0, float(run["speed"]))
	var threats := _threat_table(run, float(tune["CHUNK_LEN_M"]) / speed, speed)
	var lane_changing := float(run["laneT"]) < 1.0
	if not lane_changing:
		var urgent := _bot_urgent(run, threats)
		if not urgent.is_empty():
			return urgent
	var my: Dictionary = threats[int(run["lane"])]
	var calm := my.is_empty() or float(my["tta"]) > 1.6
	if lane_changing or float(run["jumpT"]) >= 0.0 or float(run["slideT"]) >= 0.0 or not calm:
		return {}
	return _bot_drift(run, threats)


## Kopflose Simulation für die §C8.7-Beweise (Bot-Schnitt, Reise-Determinismus).
static func simulate_run(
	rng: GoobyRng, mode := "arcade", max_sec := 120.0, dt := 1.0 / 30.0, tune := Logic.SURF
) -> Dictionary:
	var run := create_run(rng, mode, tune)
	var events := 0
	for _i in int(ceil(max_sec / dt)):
		events += step_run(run, dt, bot_input(run)).size()
		if bool(run["ended"]) or (run["mode"] == "travel" and bool(run["finished"])):
			break
	return {"run": run, "events": events, "score": run_score(run)}


## Modus-kundige Zertifizierungs-Simulation: der Pilot plus gesäte
## Aussetzer (BOT_MISS_CHANCE je 0,5-s-Fenster unterdrückt 0,55 s Eingabe),
## damit die Bot-Schnitte mit Tempo/Dichte fallen (leicht ≥ mittel ≥ schwer).
static func simulate_autoplay(mode := "normal", seed_value := 1, max_sec := 180.0) -> Dictionary:
	var tune := Logic.apply_difficulty(Logic.SURF, mode)
	var run := create_run(GoobyRng.new(seed_value * 2654435761 + 7), "arcade", tune)
	var lapse := GoobyRng.new(seed_value ^ 0x5F356495)
	var dt := 1.0 / 30.0
	var fumble_t := 0.0
	var next_roll_t := 0.0
	for _i in int(ceil(max_sec / dt)):
		if float(run["elapsed"]) >= next_roll_t:
			next_roll_t += 0.5
			if lapse.next() < float(tune["BOT_MISS_CHANCE"]):
				fumble_t = 0.55
		var input := {} if fumble_t > 0.0 else bot_input(run)
		fumble_t -= dt
		step_run(run, dt, input)
		if bool(run["ended"]):
			break
	return {
		"score": run_score(run),
		"distanceM": float(run["distanceM"]),
		"coins": int(run["coins"]),
		"crashes": int(run["crashes"]),
		"elapsed": float(run["elapsed"]),
		"ended": bool(run["ended"]),
	}


static func _hypot3(a: float, b: float, c: float) -> float:
	return sqrt(a * a + b * b + c * c)
