class_name GvzLogic
extends RefCounted
## PURE Simulation von Goobys vs Zombies (Doc G §4) — node-frei, headless,
## deterministisch: 20-Hz-Fixed-Tick, NUR int-Arithmetik (Positionen in
## Milli-Zellen, Zeiten in Ticks — PvP-ready laut Doc G §R3), Zufall
## ausschließlich über GoobyRng. Die Szene (gvz_game.gd) rendert nur den
## State und ruft die Aktions-Funktionen; Turm-/Zombie-Verhalten liegt in
## GvzCombat/GvzZombies (gleicher State, gleiche Regeln).
##
## Koordinaten: Reihe (lane) 0..4 von oben, Spalte (col) 0..8; x in
## Milli-Zellen (Zelle c überdeckt [c*1000, (c+1)*1000)). Zombies laufen
## rechts→links (x 9000 → 0); Haus/Panik-Gooby bei x < 0.

## Zellenbreite in Milli-Einheiten.
const CELL_MM := 1000
## Spielfeld-Spalten (Doc G §4.1).
const COLS := 9
## Spawn-x neuer Zombies (knapp hinter dem rechten Rand).
const SPAWN_X := 9200
## Niederlage erst, wenn KEIN Panik-Gooby mehr helfen kann und der Zombie
## wirklich im Haus steht.
const HOUSE_X := -500


## Frischer Lauf. opts: {"goldi": bool} (Code-Gate Doc G §4.2).
static func new_run(
	level: Dictionary, balance: Dictionary, difficulty := "normal", seed_value := 1, opts := {}
) -> Dictionary:
	var diff := difficulty if balance.get("difficulty", {}).has(difficulty) else "normal"
	var diff_row: Dictionary = balance.get("difficulty", {}).get(diff, {})
	var economy: Dictionary = balance.get("economy", {})
	var lanes: Array = level.get("lanes", [0, 1, 2, 3, 4]).duplicate()
	var mods: Dictionary = level.get("mods", {})
	var mowers := {}
	for lane: Variant in lanes:
		mowers[int(lane)] = {"used": false, "active": false, "x": 0}
	var state := {
		"tick": 0,
		"rng": GoobyRng.new(seed_value),
		"seed": seed_value,
		"level": level,
		"balance": balance,
		"diff": diff,
		"lanes": lanes,
		"mods": mods,
		"nutella":
		(
			int(level.get("start_nutella", economy.get("start_nutella", 50)))
			+ int(diff_row.get("start_nutella_bonus", 0))
		),
		"towers": {},
		"zombies": [],
		"projectiles": [],
		"drops": [],
		"mowers": mowers,
		"cooldowns": {},
		"conveyor": _init_conveyor(level),
		"boss": {},
		"spawn_plan": _plan_spawns(level),
		"wave_plan": _plan_waves(level),
		"spawn_idx": 0,
		"wave_idx": 0,
		"next_drop_tick": _first_drop_tick(mods, economy),
		"kills": 0,
		"score": 0,
		"outcome": "",
		"next_id": 1,
		"goldi": bool(opts.get("goldi", false)),
		"events": [],
		# Run-Statistik für die Sticker-Counter (W13/GVZ, stickers.json):
		# deterministisch in der Sim gezählt, von der Szene am Rundenende in
		# achievements.counters gebucht. NICHT Teil von state_hash (PvP-safe).
		"stats": {"drops_collected": 0, "eis_placed": 0, "bert_placed": 0, "moehren_shots": 0},
	}
	return state


## Ein 20-Hz-Tick. Mutiert state und liefert die Ereignisse des Ticks
## (kind: spawn/die/hit/boom/wave/mower/collect/produce/conveyor/…).
static func tick(state: Dictionary) -> Array:
	state["events"] = []
	if state["outcome"] != "":
		return state["events"]
	state["tick"] = int(state["tick"]) + 1
	_economy_tick(state)
	_conveyor_tick(state)
	_spawner_tick(state)
	GvzCombat.act_towers(state)
	GvzCombat.step_projectiles(state)
	GvzZombies.step(state)
	GvzZombies.step_boss(state)
	GvzZombies.step_mowers(state)
	_check_outcome(state)
	return state["events"]


## Platzierungs-Prüfung OHNE Seiteneffekte: {ok, reason}.
## reason: locked|code_gate|lane|col|cell_occupied|cooldown|nutella|
## conveyor_missing|outcome|unknown_tower.
static func can_place(state: Dictionary, type: String, lane: int, col: int) -> Dictionary:
	if state["outcome"] != "":
		return {"ok": false, "reason": "outcome"}
	var towers: Dictionary = state["balance"].get("towers", {})
	if not towers.has(type):
		return {"ok": false, "reason": "unknown_tower"}
	if not available_towers(state).has(type):
		var gate := "code_gate" if bool(towers[type].get("code_gate", false)) else "locked"
		return {"ok": false, "reason": gate}
	if not (state["lanes"] as Array).has(lane):
		return {"ok": false, "reason": "lane"}
	if col < 0 or col >= COLS:
		return {"ok": false, "reason": "col"}
	if (state["towers"] as Dictionary).has(cell_key(lane, col)):
		return {"ok": false, "reason": "cell_occupied"}
	if not (state["conveyor"] as Dictionary).is_empty():
		# Band-Items sind gratis und cooldown-frei — auch im Hybrid-Modus
		# (sonst verstopft das Band, sobald das Nutella knapp wird).
		if (state["conveyor"]["queue"] as Array).has(type):
			return {"ok": true, "reason": ""}
		if _conveyor_only(state):
			return {"ok": false, "reason": "conveyor_missing"}
	if cooldown_left(state, type) > 0:
		return {"ok": false, "reason": "cooldown"}
	if int(state["nutella"]) < tower_cost(state, type):
		return {"ok": false, "reason": "nutella"}
	return {"ok": true, "reason": ""}


## Turm setzen (Kosten/Cooldown bzw. Förderband). {ok, reason}.
static func place_tower(state: Dictionary, type: String, lane: int, col: int) -> Dictionary:
	var check := can_place(state, type, lane, col)
	if not check["ok"]:
		return check
	var queue: Array = state["conveyor"].get("queue", []) if state["conveyor"] else []
	if queue.has(type):
		queue.erase(type)
	elif _conveyor_only(state):
		return {"ok": false, "reason": "conveyor_missing"}
	else:
		var row: Dictionary = state["balance"]["towers"][type]
		state["nutella"] = int(state["nutella"]) - tower_cost(state, type)
		state["cooldowns"][type] = int(state["tick"]) + int(row.get("cooldown_ticks", 0))
	var tower := _make_tower(state, type, lane, col)
	state["towers"][cell_key(lane, col)] = tower
	if type == "eis_gooby":
		bump_stat(state, "eis_placed")
	elif type == "dicker_bert":
		bump_stat(state, "bert_placed")
	push_event(state, "place", {"type": type, "lane": lane, "col": col})
	return {"ok": true, "reason": ""}


## Turm entfernen (Schaufel-Äquivalent, keine Erstattung).
static func remove_tower(state: Dictionary, lane: int, col: int) -> bool:
	var key := cell_key(lane, col)
	if not (state["towers"] as Dictionary).has(key):
		return false
	destroy_tower(state, key, "removed")
	return true


## Turm zerstören (Fressen/Brocken/Mülltonne) + Event.
static func destroy_tower(state: Dictionary, key: int, cause: String) -> void:
	var tower: Dictionary = (state["towers"] as Dictionary).get(key, {})
	if tower.is_empty():
		return
	(state["towers"] as Dictionary).erase(key)
	push_event(
		state,
		"tower_gone",
		{"type": tower["type"], "lane": tower["lane"], "col": tower["col"], "cause": cause}
	)


## Nutella-Klecks einsammeln → Betrag (oder -1, wenn weg/unbekannt).
static func collect_drop(state: Dictionary, drop_id: int) -> int:
	var drops: Array = state["drops"]
	for i in drops.size():
		if int(drops[i]["id"]) == drop_id:
			var amount := int(drops[i]["amount"])
			var max_n := int(state["balance"]["economy"].get("max_nutella", 9975))
			state["nutella"] = mini(max_n, int(state["nutella"]) + amount)
			bump_stat(state, "drops_collected")
			push_event(
				state,
				"collect",
				{"lane": drops[i]["lane"], "col": drops[i]["col"], "amount": amount}
			)
			drops.remove_at(i)
			return amount
	return -1


## Freigeschaltete Türme dieses Levels (Goldi nur mit Code-Flag).
static func available_towers(state: Dictionary) -> Array:
	var out: Array = (state["level"].get("unlock_towers", []) as Array).duplicate()
	if bool(state["goldi"]) and (state["balance"]["towers"] as Dictionary).has("goldi"):
		out.append("goldi")
	return out


static func tower_cost(state: Dictionary, type: String) -> int:
	return int(state["balance"]["towers"].get(type, {}).get("cost", 0))


## Verbleibende Karten-Abklingzeit in Ticks (0 = bereit).
static func cooldown_left(state: Dictionary, type: String) -> int:
	var ready := int((state["cooldowns"] as Dictionary).get(type, 0))
	return maxi(0, ready - int(state["tick"]))


static func is_over(state: Dictionary) -> bool:
	return state["outcome"] != ""


static func cell_key(lane: int, col: int) -> int:
	return lane * COLS + col


## Zelle zu einer x-Position (geklemmt auf 0..COLS-1).
static func col_of(x: int) -> int:
	return clampi(_idiv(x, CELL_MM), 0, COLS - 1)


## Deterministischer State-Hash für Replays/PvP-Drift-Checks (schließt
## rng/level/balance/events aus — deren Wirkung steckt in den Feldern).
static func state_hash(state: Dictionary) -> int:
	var parts := PackedStringArray()
	for key: String in [
		"tick",
		"nutella",
		"towers",
		"zombies",
		"projectiles",
		"drops",
		"mowers",
		"cooldowns",
		"conveyor",
		"boss",
		"spawn_idx",
		"wave_idx",
		"kills",
		"score",
		"outcome",
	]:
		parts.append(var_to_str(state[key]))
	return hash("\n".join(parts))


## Run-Statistik-Zähler erhöhen (auch von GvzCombat; Keys s. new_run).
static func bump_stat(state: Dictionary, key: String, amount := 1) -> void:
	if not (state.get("stats") is Dictionary):
		state["stats"] = {}
	var stats: Dictionary = state["stats"]
	stats[key] = int(stats.get(key, 0)) + amount


## Ereignis an den Tick-Report anhängen (auch von GvzCombat/GvzZombies).
static func push_event(state: Dictionary, kind: String, data := {}) -> void:
	var event := data.duplicate()
	event["kind"] = kind
	(state["events"] as Array).append(event)


## Frische Id für Zombies/Projektile/Drops.
static func next_id(state: Dictionary) -> int:
	var id := int(state["next_id"])
	state["next_id"] = id + 1
	return id


static func _make_tower(state: Dictionary, type: String, lane: int, col: int) -> Dictionary:
	var row: Dictionary = state["balance"]["towers"][type]
	var diff: Dictionary = state["balance"]["difficulty"].get(str(state["diff"]), {})
	# Difficulty wirkt auch turmseitig (E11-Monotonie): auf easy halten Türme
	# spürbar mehr Bisse aus — das macht schlampige Baupläne verzeihbar,
	# OHNE die Bot-Entscheidungen zu kippen (keine Heuristik liest Turm-HP).
	var hp := _idiv(int(row.get("hp", 300)) * int(diff.get("tower_hp_pct", 100)), 100)
	var tick_now := int(state["tick"])
	var tower := {
		"id": next_id(state),
		"type": type,
		"lane": lane,
		"col": col,
		"hp": hp,
		"max_hp": hp,
		"next_act":
		tick_now + int(row.get("produce_interval_ticks", row.get("fire_interval_ticks", 0))),
	}
	if row.has("charges"):
		tower["charges"] = int(row["charges"])
	if row.has("arm_ticks"):
		tower["armed_at"] = tick_now + int(row["arm_ticks"])
	if row.has("fuse_ticks"):
		tower["fuse_at"] = tick_now + int(row["fuse_ticks"])
	if row.has("steal_interval_ticks"):
		tower["next_act"] = tick_now + int(row["steal_interval_ticks"])
	if row.has("gust_interval_ticks"):
		tower["next_act"] = tick_now + int(row["gust_interval_ticks"])
	return tower


## Himmels-Nutella + Klecks-Verfall (Nacht: nichts vom Himmel, Doc G §4.4 L6).
static func _economy_tick(state: Dictionary) -> void:
	var economy: Dictionary = state["balance"]["economy"]
	var tick_now := int(state["tick"])
	if int(state["next_drop_tick"]) > 0 and tick_now >= int(state["next_drop_tick"]):
		state["next_drop_tick"] = tick_now + int(economy.get("sky_drop_interval_ticks", 200))
		var rng: GoobyRng = state["rng"]
		var lanes: Array = state["lanes"]
		var lane := int(lanes[rng.next_u32() % lanes.size()])
		var col := int(rng.next_u32() % COLS)
		_spawn_drop(state, lane, col, int(economy.get("sky_drop_amount", 25)), "sky")
	var drops: Array = state["drops"]
	for i in range(drops.size() - 1, -1, -1):
		if tick_now >= int(drops[i]["expires"]):
			push_event(state, "drop_gone", {"lane": drops[i]["lane"], "col": drops[i]["col"]})
			drops.remove_at(i)


## Klecks erzeugen (Himmel ODER Sammler-Produktion; source: sky|produce).
static func _spawn_drop(
	state: Dictionary, lane: int, col: int, amount: int, source: String
) -> void:
	var economy: Dictionary = state["balance"]["economy"]
	var lifetime := int(economy.get("sky_drop_lifetime_ticks", 160))
	if bool(state["mods"].get("rain", false)):
		lifetime = int(economy.get("rain_drop_lifetime_ticks", 90))
	if source == "produce":
		lifetime *= 2
	var drop := {
		"id": next_id(state),
		"lane": lane,
		"col": col,
		"amount": amount,
		"expires": int(state["tick"]) + lifetime,
	}
	(state["drops"] as Array).append(drop)
	push_event(state, "drop", {"lane": lane, "col": col, "amount": amount, "source": source})


static func _conveyor_tick(state: Dictionary) -> void:
	var conveyor: Dictionary = state["conveyor"]
	if conveyor.is_empty():
		return
	var queue: Array = conveyor["queue"]
	if (
		int(state["tick"]) < int(conveyor["next_tick"])
		or queue.size() >= int(conveyor["max_queue"])
	):
		return
	conveyor["next_tick"] = int(state["tick"]) + int(conveyor["interval"])
	var pool: Array = conveyor["pool"]
	var rng: GoobyRng = state["rng"]
	var type := str(pool[rng.next_u32() % pool.size()])
	queue.append(type)
	push_event(state, "conveyor", {"type": type})


## Wellen-Banner + geskriptete Spawns (aus dem Level-Plan) + Boss-Einzug.
static func _spawner_tick(state: Dictionary) -> void:
	var tick_now := int(state["tick"])
	var waves: Array = state["wave_plan"]
	while int(state["wave_idx"]) < waves.size():
		var wave: Dictionary = waves[int(state["wave_idx"])]
		if tick_now < int(wave["tick"]):
			break
		state["wave_idx"] = int(state["wave_idx"]) + 1
		push_event(state, "wave", {"n": int(state["wave_idx"]), "huge": bool(wave["huge"])})
	var plan: Array = state["spawn_plan"]
	while int(state["spawn_idx"]) < plan.size():
		var entry: Dictionary = plan[int(state["spawn_idx"])]
		if tick_now < int(entry["tick"]):
			break
		state["spawn_idx"] = int(state["spawn_idx"]) + 1
		var lane := int(entry["lane"])
		if lane < 0:
			var lanes: Array = state["lanes"]
			var rng: GoobyRng = state["rng"]
			lane = int(lanes[rng.next_u32() % lanes.size()])
		GvzZombies.spawn(state, str(entry["type"]), lane, SPAWN_X)
	var boss_def: Variant = state["level"].get("boss")
	if boss_def is Dictionary and (state["boss"] as Dictionary).is_empty():
		if tick_now >= int(boss_def.get("enter_at", 0)) * _tps(state):
			GvzZombies.boss_enter(state, boss_def)


static func _check_outcome(state: Dictionary) -> void:
	if state["outcome"] != "":
		return
	var boss: Dictionary = state["boss"]
	if not boss.is_empty() and int(boss.get("hp", 1)) <= 0:
		state["outcome"] = "won"
		push_event(state, "won", {"boss": true})
		return
	var boss_def: Variant = state["level"].get("boss")
	var boss_pending: bool = boss_def is Dictionary and boss.is_empty()
	var spawns_done: bool = int(state["spawn_idx"]) >= (state["spawn_plan"] as Array).size()
	if (
		spawns_done
		and (state["zombies"] as Array).is_empty()
		and boss.is_empty()
		and not boss_pending
	):
		state["outcome"] = "won"
		push_event(state, "won", {"boss": false})


static func _init_conveyor(level: Dictionary) -> Dictionary:
	var def: Variant = level.get("conveyor")
	if not (def is Dictionary):
		return {}
	return {
		"queue": [],
		"pool": (def.get("pool", []) as Array).duplicate(),
		"interval": int(def.get("interval_ticks", 130)),
		"max_queue": int(def.get("max_queue", 5)),
		"next_tick": int(def.get("start_delay_ticks", 20)),
	}


## Reines Förderband-Level (L9) — Hybrid (L15) erlaubt zusätzlich Nutella.
static func _conveyor_only(state: Dictionary) -> bool:
	var mods: Dictionary = state["mods"]
	return bool(mods.get("conveyor", false)) and not bool(mods.get("conveyor_hybrid", false))


static func _first_drop_tick(mods: Dictionary, economy: Dictionary) -> int:
	if bool(mods.get("night", false)):
		return -1
	return int(economy.get("sky_drop_first_ticks", 120))


static func _plan_spawns(level: Dictionary) -> Array:
	var plan: Array = []
	for spawn: Variant in level.get("spawns", []):
		(
			plan
			. append(
				{
					"tick": int(floorf(float(spawn.get("t", 0.0)) * 20.0)),
					"lane": int(spawn.get("lane", -1)),
					"type": str(spawn.get("type", "schlurfi")),
				}
			)
		)
	return plan


static func _plan_waves(level: Dictionary) -> Array:
	var plan: Array = []
	for wave: Variant in level.get("waves", []):
		(
			plan
			. append(
				{
					"tick": int(floorf(float(wave.get("t", 0.0)) * 20.0)),
					"huge": bool(wave.get("huge", false)),
				}
			)
		)
	return plan


static func _tps(state: Dictionary) -> int:
	return int(state["balance"].get("ticks_per_second", 20))


@warning_ignore("integer_division")
static func _idiv(a: int, b: int) -> int:
	return a / b
