class_name GhostHuntLogic
extends RefCounted
## Pure Geisterjagd-Logik — zahlengleicher Port von
## GOOBY/src/minigames/games/ghostHunt.logic.js (PLAN3 §C10.1 #2).
## Süße Bettlaken-Geister lugen aus Gräbern/Kürbissen/der Gruft, Sichtfenster
## rampt 2.2 s → 0.9 s über die 90-s-Runde, Tippen = Fang +3, Kette +1 je Fang
## innerhalb 1.5 s (Bonus max. +5), Kürbis-Attrappe = −2, alle 25 s eine
## Buh-Welle mit 5 Geistern (≥ 4 gefangen = +10), Laterne (3 s Enthüllung)
## und Netz (3 automatische Kettenfänge) als Aufsammler.
##
## Der Zustand ist ein Dictionary (wie das Web-Objekt), damit die Szene und
## der Bot exakt dieselbe Zustandsmaschine teilen.

## Bindende §C10.1-#2-Zahlen; Coin-Zeile 4/4/28, Ziel 90.
const HUNT := {
	"DURATION_SEC": 90.0,
	"VISIBLE_START_SEC": 2.2,
	"VISIBLE_END_SEC": 0.9,
	"CATCH_POINTS": 3,
	"CHAIN_WINDOW_SEC": 1.5,
	"CHAIN_BONUS_CAP": 5,
	"DECOY_PENALTY": -2,
	"DECOY_FLICKER_SEC": 1.8,
	"DECOY_CHANCE_START": 0.12,
	"DECOY_CHANCE_END": 0.28,
	"BOO_EVERY_SEC": 25.0,
	"BOO_COUNT": 5,
	"BOO_CATCH_MIN": 4,
	"BOO_BONUS": 10,
	"BOO_MIN_VISIBLE_SEC": 1.6,
	"LANTERN_SEC": 3.0,
	"LANTERN_REVEAL_BONUS_SEC": 0.4,
	"NET_CATCHES": 3,
	"TOKEN_VISIBLE_SEC": 5.0,
	"TOKEN_WINDOWS":
	[
		{"kind": "lantern", "from": 12.0, "to": 18.0},
		{"kind": "net", "from": 30.0, "to": 36.0},
		{"kind": "lantern", "from": 52.0, "to": 58.0},
		{"kind": "net", "from": 68.0, "to": 74.0},
	],
	"SPAWN_START_SEC": 2.8,
	"SPAWN_END_SEC": 1.5,
	"FIRST_SPAWN_SEC": 0.8,
	"BOT_REACT_SEC": 0.2,
	"BOT_MIN_GAP_SEC": 0.5,
	"BOT_ENGAGE": 0.4,
	"BOT_WAVE_ENGAGE": 0.62,
	"RISE_FRAC": 0.16,
	"SINK_FRAC": 0.16,
	"ENDLESS": false,
	"ENDLESS_ESCAPE_LIMIT": 3,
}

## §G5.3-Arena-Zeilen; Endlos erbt die Schwer-Arena ohne Rundenuhr.
const HUNT_DIFFICULTY := {
	"easy":
	{
		"interval": 1.2,
		"windows": 1.25,
		"duration": 1.2,
		"botEngage": 0.44,
		"botWaveEngage": 0.66,
		"endless": false
	},
	"normal":
	{
		"interval": 1.0,
		"windows": 1.0,
		"duration": 1.0,
		"botEngage": 0.4,
		"botWaveEngage": 0.62,
		"endless": false
	},
	"hard":
	{
		"interval": 0.85,
		"windows": 0.8,
		"duration": 1.0,
		"botEngage": 0.36,
		"botWaveEngage": 0.58,
		"endless": false
	},
	"endless":
	{
		"interval": 0.85,
		"windows": 0.8,
		"duration": 1.0,
		"botEngage": 0.36,
		"botWaveEngage": 0.58,
		"endless": true
	},
}

## Versteck-Anker der Geister (Weltkoordinaten, mit der Ansicht geteilt).
const SPOTS := [
	{"id": 0, "kind": "grave", "x": -2.1, "z": -1.7},
	{"id": 1, "kind": "pumpkin", "x": -0.7, "z": -1.5},
	{"id": 2, "kind": "grave", "x": 0.8, "z": -1.7},
	{"id": 3, "kind": "grave", "x": 2.1, "z": -1.6},
	{"id": 4, "kind": "pumpkin", "x": -2.3, "z": -3.4},
	{"id": 5, "kind": "grave", "x": -0.9, "z": -3.5},
	{"id": 6, "kind": "grave", "x": 1.0, "z": -3.3},
	{"id": 7, "kind": "pumpkin", "x": 2.3, "z": -3.5},
	{"id": 8, "kind": "grave", "x": -1.7, "z": -5.3},
	{"id": 9, "kind": "crypt", "x": 0.1, "z": -6.4},
	{"id": 10, "kind": "grave", "x": 1.8, "z": -5.2},
	{"id": 11, "kind": "pumpkin", "x": 0.0, "z": -4.9},
]

## Attrappen-Kürbislaternen (§C10.1: sie flackern wie Geister).
const DECOY_SPOTS := [
	{"id": 0, "x": -1.5, "z": -2.5},
	{"id": 1, "x": 1.6, "z": -2.5},
	{"id": 2, "x": -2.3, "z": -4.5},
	{"id": 3, "x": 2.3, "z": -4.4},
]

## Schwebeanker der Aufsammler (je TOKEN_WINDOWS-Index).
const TOKEN_ANCHORS := [
	{"x": -1.1, "z": -2.1},
	{"x": 1.1, "z": -2.1},
	{"x": -1.1, "z": -2.1},
	{"x": 1.1, "z": -2.1},
]


## §G5.3-Modus ableiten; `normal` liefert die Basistabelle unverändert.
static func apply_difficulty(tune := HUNT, mode := "normal") -> Dictionary:
	var id := mode if HUNT_DIFFICULTY.has(mode) else "normal"
	if id == "normal":
		return tune
	var row: Dictionary = HUNT_DIFFICULTY[id]
	var out := tune.duplicate(true)
	out["DURATION_SEC"] = float(tune["DURATION_SEC"]) * float(row["duration"])
	out["SPAWN_START_SEC"] = float(tune["SPAWN_START_SEC"]) * float(row["interval"])
	out["SPAWN_END_SEC"] = float(tune["SPAWN_END_SEC"]) * float(row["interval"])
	out["VISIBLE_START_SEC"] = float(tune["VISIBLE_START_SEC"]) * float(row["windows"])
	out["VISIBLE_END_SEC"] = float(tune["VISIBLE_END_SEC"]) * float(row["windows"])
	out["BOO_MIN_VISIBLE_SEC"] = float(tune["BOO_MIN_VISIBLE_SEC"]) * float(row["windows"])
	out["BOT_ENGAGE"] = float(row["botEngage"])
	out["BOT_WAVE_ENGAGE"] = float(row["botWaveEngage"])
	out["ENDLESS"] = bool(row["endless"])
	out["MODE"] = id
	return out


## §C10.1-Sichtrampe: wie lange ein Geist gerade fangbar bleibt.
static func visible_dur_at(elapsed: float, tune := HUNT) -> float:
	var t := _ramp_t(elapsed, tune)
	var start := float(tune["VISIBLE_START_SEC"])
	return start + (float(tune["VISIBLE_END_SEC"]) - start) * t


## Sekunden bis zum nächsten Auftauchen (Takt zieht über die Runde an).
static func spawn_interval_at(elapsed: float, tune := HUNT) -> float:
	var t := _ramp_t(elapsed, tune)
	var start := float(tune["SPAWN_START_SEC"])
	return start + (float(tune["SPAWN_END_SEC"]) - start) * t


## Wahrscheinlichkeit, dass ein Slot statt eines Geistes eine Attrappe wird.
static func decoy_chance_at(elapsed: float, tune := HUNT) -> float:
	var t := _ramp_t(elapsed, tune)
	var start := float(tune["DECOY_CHANCE_START"])
	return start + (float(tune["DECOY_CHANCE_END"]) - start) * t


static func _ramp_t(elapsed: float, tune: Dictionary) -> float:
	return minf(1.0, maxf(0.0, elapsed / float(tune["DURATION_SEC"])))


## §C10.1-Kettenbonus des n-ten Kettenfangs: 0, dann +1 je Glied, max. +5.
static func chain_bonus(chain: int, tune := HUNT) -> int:
	return mini(int(tune["CHAIN_BONUS_CAP"]), maxi(0, chain - 1))


## Auslösezeitpunkte der Buh-Wellen einer Runde (alle 25 s).
static func boo_wave_times(tune := HUNT) -> Array[float]:
	var times: Array[float] = []
	var every := float(tune["BOO_EVERY_SEC"])
	var t := every
	while t <= float(tune["DURATION_SEC"]) - 10.0:
		times.append(t)
		t += every
	return times


## Gesetzten Jagdzustand erzeugen (§E8: der Rahmen liefert den Seed).
static func create_hunt(seed_value: int, tune := HUNT) -> Dictionary:
	var windows: Array = tune["TOKEN_WINDOWS"]
	var spawned: Array[bool] = []
	var token_at: Array[float] = []
	for i in windows.size():
		spawned.append(false)
		token_at.append(-1.0)
	return {
		"seed": seed_value,
		"tune": tune,
		"rng": GoobyRng.new(seed_value ^ 0x60db15c3),
		"t": 0.0,
		"score": 0,
		"chain": 0,
		"lastCatchT": -99.0,
		"netLeft": 0,
		"lanternT": 0.0,
		"ghosts": [] as Array[Dictionary],
		"flickers": [] as Array[Dictionary],
		"tokens": [] as Array[Dictionary],
		"nextGhostId": 1,
		"nextSpawnT": float(tune["FIRST_SPAWN_SEC"]),
		"booTimes": boo_wave_times(tune),
		"booIdx": 0,
		"booActive": {},
		"tokensSpawned": spawned,
		"tokenAt": token_at,
		"caught": 0,
		"missed": 0,
		"decoysTapped": 0,
		"booBonuses": 0,
		"escapedWaves": 0,
		"events": [] as Array[Dictionary],
		"ended": false,
		"bot": {},
	}


## Die Jagd um dt weiterdrehen: Ablauf, Spawn-Takt, Buh-Wellen, Aufsammler.
static func step_hunt(state: Dictionary, dt: float) -> void:
	if bool(state["ended"]):
		return
	var tune: Dictionary = state["tune"]
	state["t"] = float(state["t"]) + dt
	var t := float(state["t"])
	# §G5.4: Endlos hat keine Rundenuhr — es endet an entwischten Buh-Wellen.
	if not bool(tune["ENDLESS"]) and t >= float(tune["DURATION_SEC"]):
		state["ended"] = true
		(state["events"] as Array).append({"type": "end"})
		return
	state["lanternT"] = maxf(0.0, float(state["lanternT"]) - dt)
	_expire_entities(state, t, tune)
	_spawn_tokens(state, t, tune)
	if bool(tune["ENDLESS"]) and int(state["booIdx"]) >= (state["booTimes"] as Array).size():
		var times: Array = state["booTimes"]
		var last := float(times[times.size() - 1]) if not times.is_empty() else 0.0
		times.append(last + float(tune["BOO_EVERY_SEC"]))
	_run_boo_wave(state, t, tune)
	_run_spawner(state, t, tune)


## Einen Tipp auflösen. `target`: {"kind":"ghost","id"} · {"kind":"decoy",
## "decoy"} · {"kind":"token","window"} · {} (ins Leere getippt).
static func tap_hunt(state: Dictionary, target: Dictionary) -> Dictionary:
	if bool(state["ended"]):
		return {"kind": "ended", "points": 0}
	match str(target.get("kind", "")):
		"ghost":
			return _tap_ghost(state, int(target["id"]))
		"decoy":
			return _tap_decoy(state, int(target["decoy"]))
		"token":
			return _tap_token(state, int(target["window"]))
	# Ins Dunkel getippt — die Kette verpufft (ohne Strafe).
	state["chain"] = 0
	return {"kind": "miss", "points": 0}


## §C10.1-Bot: tippt echte Geister bei Spawn + 200 ms, meidet Attrappen,
## sammelt Aufsammler immer ein. Liefert die gewünschten Tipps dieses Frames.
static func bot_step(state: Dictionary) -> Array[Dictionary]:
	var tune: Dictionary = state["tune"]
	var bot: Dictionary = state["bot"]
	if bot.is_empty():
		bot["rng"] = GoobyRng.new(int(state["seed"]) ^ 0x7f4a7c15)
		bot["nextFreeT"] = 0.0
		bot["marks"] = {}
	var taps: Array[Dictionary] = []
	if bool(state["ended"]):
		return taps
	var marks: Dictionary = bot["marks"]
	var rng: GoobyRng = bot["rng"]
	# Jeden Geist GENAU EINMAL in Spawn-Reihenfolge als go/skip markieren.
	for g: Dictionary in state["ghosts"]:
		if marks.has(g["id"]):
			continue
		var engage := float(tune["BOT_WAVE_ENGAGE"] if g["wave"] != null else tune["BOT_ENGAGE"])
		marks[g["id"]] = rng.next() < engage
	var now := float(state["t"])
	for token: Dictionary in state["tokens"]:
		if now >= float(token["startT"]) + 0.3 and now >= float(bot["nextFreeT"]):
			taps.append({"kind": "token", "window": int(token["window"])})
			bot["nextFreeT"] = now + float(tune["BOT_MIN_GAP_SEC"])
	for g: Dictionary in state["ghosts"]:
		if not bool(marks.get(g["id"], false)):
			continue
		if now < float(g["spawnT"]) + float(tune["BOT_REACT_SEC"]):
			continue
		if now < float(bot["nextFreeT"]):
			break
		taps.append({"kind": "ghost", "id": int(g["id"])})
		bot["nextFreeT"] = now + float(tune["BOT_MIN_GAP_SEC"])
	return taps


## Rundenpunkte (konstruktionsbedingt nie negativ).
static func hunt_score(state: Dictionary) -> int:
	return maxi(0, int(round(float(state["score"]))))


## §G5.4-Zertifizierungslauf: eine volle Bot-Runde bei festen 30 Hz.
static func simulate_autoplay(mode := "normal", seed_value := 1, max_sec := 900.0) -> Dictionary:
	var tune := apply_difficulty(HUNT, mode)
	var state := create_hunt(seed_value, tune)
	var dt := 1.0 / 30.0
	while not bool(state["ended"]) and float(state["t"]) < max_sec:
		step_hunt(state, dt)
		if bool(state["ended"]):
			break
		for tap in bot_step(state):
			tap_hunt(state, tap)
		(state["events"] as Array).clear()
	return {
		"score": hunt_score(state),
		"caught": int(state["caught"]),
		"missed": int(state["missed"]),
		"escapedWaves": int(state["escapedWaves"]),
		"booBonuses": int(state["booBonuses"]),
		"time": float(state["t"]),
	}


## §B3-Meta-Nutzlast (§C10.1: meta ghostsCaught).
static func run_meta(state: Dictionary) -> Dictionary:
	return {
		"ghostsCaught": int(state["caught"]),
		"decoysTapped": int(state["decoysTapped"]),
		"booBonuses": int(state["booBonuses"]),
	}


static func _free_spots(state: Dictionary) -> Array[int]:
	var busy := {}
	for g: Dictionary in state["ghosts"]:
		busy[int(g["spot"])] = true
	var free: Array[int] = []
	for s: Dictionary in SPOTS:
		if not busy.has(int(s["id"])):
			free.append(int(s["id"]))
	return free


## Einen Geist auf einem freien Platz auftauchen lassen (leer = Hof voll).
static func _spawn_ghost(state: Dictionary, wave: Variant, forced_dur: float) -> Dictionary:
	var tune: Dictionary = state["tune"]
	var free := _free_spots(state)
	if free.is_empty():
		return {}
	var rng: GoobyRng = state["rng"]
	var spot: int = free[int(floor(rng.next() * free.size()))]
	var dur := forced_dur
	if dur < 0.0:
		dur = visible_dur_at(float(state["t"]), tune)
		if float(state["lanternT"]) > 0.0:
			dur += float(tune["LANTERN_REVEAL_BONUS_SEC"])
	var ghost := {
		"id": int(state["nextGhostId"]),
		"spot": spot,
		"spawnT": float(state["t"]),
		"dur": dur,
		"wave": wave,
		"revealed": float(state["lanternT"]) > 0.0,
	}
	state["nextGhostId"] = int(state["nextGhostId"]) + 1
	(state["ghosts"] as Array).append(ghost)
	(
		(state["events"] as Array)
		. append(
			{
				"type": "ghostSpawn",
				"id": ghost["id"],
				"spot": spot,
				"wave": wave,
				"revealed": ghost["revealed"],
			}
		)
	)
	return ghost


## Einen abgeschlossenen Wellengeist verbuchen; zahlt den ≥4-Bonus am Ende.
static func _resolve_wave_ghost(state: Dictionary, ghost: Dictionary, was_caught: bool) -> void:
	var wave: Dictionary = state["booActive"]
	if wave.is_empty() or ghost["wave"] == null or int(ghost["wave"]) != int(wave["idx"]):
		return
	wave["resolved"] = int(wave["resolved"]) + 1
	if was_caught:
		wave["caught"] = int(wave["caught"]) + 1
	if int(wave["resolved"]) < int(wave["total"]):
		return
	var tune: Dictionary = state["tune"]
	var events: Array = state["events"]
	if int(wave["caught"]) >= int(tune["BOO_CATCH_MIN"]):
		state["score"] = int(state["score"]) + int(tune["BOO_BONUS"])
		state["booBonuses"] = int(state["booBonuses"]) + 1
		events.append(
			{"type": "booBonus", "caught": int(wave["caught"]), "bonus": int(tune["BOO_BONUS"])}
		)
	else:
		# §G5.4: eine ENTWISCHTE Welle (< 4 Fänge) — drei beenden Endlos.
		state["escapedWaves"] = int(state["escapedWaves"]) + 1
		events.append(
			{"type": "booEnd", "caught": int(wave["caught"]), "escaped": int(state["escapedWaves"])}
		)
		var limit := int(tune["ENDLESS_ESCAPE_LIMIT"])
		if bool(tune["ENDLESS"]) and int(state["escapedWaves"]) >= limit:
			state["ended"] = true
			events.append({"type": "end", "reason": "escapes"})
	state["booActive"] = {}


static func _expire_entities(state: Dictionary, t: float, tune: Dictionary) -> void:
	var ghosts: Array = state["ghosts"]
	var events: Array = state["events"]
	for i in range(ghosts.size() - 1, -1, -1):
		var g: Dictionary = ghosts[i]
		if t - float(g["spawnT"]) < float(g["dur"]):
			continue
		ghosts.remove_at(i)
		state["missed"] = int(state["missed"]) + 1
		events.append({"type": "ghostGone", "id": g["id"], "spot": g["spot"]})
		_resolve_wave_ghost(state, g, false)
	var flickers: Array = state["flickers"]
	for i in range(flickers.size() - 1, -1, -1):
		if t - float((flickers[i] as Dictionary)["startT"]) >= float(tune["DECOY_FLICKER_SEC"]):
			events.append({"type": "flickerEnd", "decoy": (flickers[i] as Dictionary)["decoy"]})
			flickers.remove_at(i)
	var tokens: Array = state["tokens"]
	for i in range(tokens.size() - 1, -1, -1):
		if t - float((tokens[i] as Dictionary)["startT"]) >= float(tune["TOKEN_VISIBLE_SEC"]):
			events.append({"type": "tokenGone", "kind": (tokens[i] as Dictionary)["kind"]})
			tokens.remove_at(i)


static func _spawn_tokens(state: Dictionary, t: float, tune: Dictionary) -> void:
	var windows: Array = tune["TOKEN_WINDOWS"]
	var spawned: Array = state["tokensSpawned"]
	var token_at: Array = state["tokenAt"]
	var rng: GoobyRng = state["rng"]
	for w in windows.size():
		if bool(spawned[w]):
			continue
		var win: Dictionary = windows[w]
		if float(token_at[w]) < 0.0 and t >= float(win["from"]) - 5.0:
			token_at[w] = float(win["from"]) + rng.next() * (float(win["to"]) - float(win["from"]))
		if float(token_at[w]) >= 0.0 and t >= float(token_at[w]):
			spawned[w] = true
			(state["tokens"] as Array).append({"window": w, "kind": win["kind"], "startT": t})
			(state["events"] as Array).append(
				{"type": "tokenSpawn", "kind": win["kind"], "window": w}
			)


## §C10.1-Buh-Welle: alle 25 s tauchen 5 Geister zugleich auf.
static func _run_boo_wave(state: Dictionary, t: float, tune: Dictionary) -> void:
	var times: Array = state["booTimes"]
	var idx := int(state["booIdx"])
	if idx >= times.size() or t < float(times[idx]):
		return
	state["booIdx"] = idx + 1
	var ghosts: Array = state["ghosts"]
	var events: Array = state["events"]
	# Platz schaffen: älteste Normalgeister still abziehen (ohne Fehlerzähler).
	while _free_spots(state).size() < int(tune["BOO_COUNT"]) and not ghosts.is_empty():
		var g: Dictionary = ghosts.pop_front()
		events.append({"type": "ghostGone", "id": g["id"], "spot": g["spot"]})
	var dur := maxf(visible_dur_at(t, tune), float(tune["BOO_MIN_VISIBLE_SEC"]))
	var spawned := 0
	for i in int(tune["BOO_COUNT"]):
		if not _spawn_ghost(state, idx, dur).is_empty():
			spawned += 1
	state["booActive"] = {"idx": idx, "total": spawned, "caught": 0, "resolved": 0}
	events.append({"type": "booWave", "idx": idx, "count": spawned})


static func _run_spawner(state: Dictionary, t: float, tune: Dictionary) -> void:
	if t < float(state["nextSpawnT"]):
		return
	state["nextSpawnT"] = t + spawn_interval_at(t, tune)
	var busy := {}
	for f: Dictionary in state["flickers"]:
		busy[int(f["decoy"])] = true
	var free_decoys: Array[int] = []
	for d: Dictionary in DECOY_SPOTS:
		if not busy.has(int(d["id"])):
			free_decoys.append(int(d["id"]))
	var rng: GoobyRng = state["rng"]
	if rng.next() < decoy_chance_at(t, tune) and not free_decoys.is_empty():
		var decoy: int = free_decoys[int(floor(rng.next() * free_decoys.size()))]
		(state["flickers"] as Array).append({"decoy": decoy, "startT": t})
		(state["events"] as Array).append({"type": "flicker", "decoy": decoy})
	else:
		_spawn_ghost(state, null, -1.0)


static func _tap_ghost(state: Dictionary, id: int) -> Dictionary:
	var tune: Dictionary = state["tune"]
	var ghosts: Array = state["ghosts"]
	var index := -1
	for i in ghosts.size():
		if int((ghosts[i] as Dictionary)["id"]) == id:
			index = i
			break
	if index < 0:
		return {"kind": "miss", "points": 0}
	var ghost: Dictionary = ghosts[index]
	ghosts.remove_at(index)
	var t := float(state["t"])
	var auto := int(state["netLeft"]) > 0
	var chained := auto or t - float(state["lastCatchT"]) <= float(tune["CHAIN_WINDOW_SEC"])
	state["chain"] = int(state["chain"]) + 1 if chained else 1
	if auto:
		state["netLeft"] = int(state["netLeft"]) - 1
	var points := int(tune["CATCH_POINTS"]) + chain_bonus(int(state["chain"]), tune)
	state["score"] = int(state["score"]) + points
	state["lastCatchT"] = t
	state["caught"] = int(state["caught"]) + 1
	(
		(state["events"] as Array)
		. append(
			{
				"type": "catch",
				"id": ghost["id"],
				"spot": ghost["spot"],
				"points": points,
				"chain": int(state["chain"]),
				"auto": auto,
			}
		)
	)
	_resolve_wave_ghost(state, ghost, true)
	return {"kind": "ghost", "points": points, "chain": int(state["chain"])}


static func _tap_decoy(state: Dictionary, decoy: int) -> Dictionary:
	var tune: Dictionary = state["tune"]
	var flickers: Array = state["flickers"]
	var index := -1
	for i in flickers.size():
		if int((flickers[i] as Dictionary)["decoy"]) == decoy:
			index = i
			break
	if index < 0:
		return {"kind": "miss", "points": 0}
	flickers.remove_at(index)
	state["score"] = maxi(0, int(state["score"]) + int(tune["DECOY_PENALTY"]))
	state["chain"] = 0
	state["lastCatchT"] = -99.0
	state["decoysTapped"] = int(state["decoysTapped"]) + 1
	(state["events"] as Array).append(
		{"type": "decoy", "decoy": decoy, "points": int(tune["DECOY_PENALTY"])}
	)
	return {"kind": "decoy", "points": int(tune["DECOY_PENALTY"])}


static func _tap_token(state: Dictionary, window: int) -> Dictionary:
	var tune: Dictionary = state["tune"]
	var tokens: Array = state["tokens"]
	var index := -1
	for i in tokens.size():
		if int((tokens[i] as Dictionary)["window"]) == window:
			index = i
			break
	if index < 0:
		return {"kind": "miss", "points": 0}
	var token: Dictionary = tokens[index]
	tokens.remove_at(index)
	if str(token["kind"]) == "lantern":
		state["lanternT"] = float(tune["LANTERN_SEC"])
	else:
		state["netLeft"] = int(tune["NET_CATCHES"])
	(state["events"] as Array).append({"type": "powerup", "kind": token["kind"]})
	return {"kind": "token", "points": 0, "powerup": token["kind"]}
