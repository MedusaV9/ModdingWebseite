class_name ShoppingSurfLogic
extends RefCounted
## Reine Einkaufs-Surf-Logik — zahlengleicher Port von
## GOOBY/src/minigames/games/shoppingSurf.logic.js (§C8).
## Gooby rennt die Einkaufsstraße hinunter: 3 Spuren à 1,6 m, Wischen wechselt
## die Spur, Sprung über Einkaufswagen/Lücken, Rutschen unter Markisen.
## Münzen +1 (×2 mit Power-up), Beinahe-Treffer +2, Tempo 8 → 16 m/s.
## Dieser Teil hält Tuning, Straßenbausteine, den Überlebbarkeits-Validator
## und die Wertung; die Lauf-Simulation liegt in `shopping_surf_run.gd`.

## §C8 verbindliche Zahlen + Umsetzungs-Regler.
const SURF := {
	"LANES": 3,
	## §C8.1: Spurbreite 1,6 m, Mitten x = −1,6 / 0 / +1,6.
	"LANE_W": 1.6,
	"LANE_X": [-1.6, 0.0, 1.6],
	## §C8.5 Temporampe: Basis 8 m/s, +0,25 m/s alle 5 s, Deckel 16 m/s.
	"BASE_SPEED": 8.0,
	"SPEED_STEP": 0.25,
	"SPEED_EVERY_SEC": 5.0,
	"MAX_SPEED": 16.0,
	## §C8.2 Steuerung.
	"LANE_CHANGE_SEC": 0.12,
	"JUMP_SEC": 0.55,
	"JUMP_HEIGHT": 1.35,
	"SLIDE_SEC": 0.5,
	"SLIDE_HEIGHT": 0.5,
	"STAND_HEIGHT": 1.05,
	## Schnellfall-Sinkrate beim Wisch-nach-unten in der Luft (m/s).
	"FAST_DROP_SPEED": 10.0,
	## §C8.2: genau 1 gepufferte Aktion, 250-ms-Fenster.
	"BUFFER_SEC": 0.25,
	## Spieler-Trefferbox (großzügige ~80 %).
	"PLAYER_HALF_W": 0.42,
	"PLAYER_HALF_DEPTH": 0.3,
	## §C8.3 Crash-Regeln.
	"STUMBLE_SEC": 0.8,
	"INVULN_SEC": 1.5,
	"ARCADE_MAX_CRASHES": 3,
	## Während des Stolperns torkelt Gooby im halben Tempo.
	"STUMBLE_SPEED_MULT": 0.5,
	## §C8.3 Beinahe-Treffer: unter 0,35 m vorbei = +2 + Serie.
	"NEAR_MISS_M": 0.35,
	## §C8.1 Straßenbausteine.
	"CHUNK_LEN_M": 30.0,
	## Wie weit vor Gooby Dinge auftauchen (m).
	"SPAWN_AHEAD_M": 70.0,
	## Ab dieser Strecke hinter Gooby wird recycelt (m).
	"DESPAWN_Z": 8.0,
	## §C8.3: Bordstein-Lücken erst ab 800 m.
	"GAP_MIN_DISTANCE_M": 800.0,
	## §C8.3 Hindernistabelle (pass = wie dieselbe Spur frei wird).
	"OBSTACLES":
	{
		"cart":
		{
			"pass": "jump",
			"clearY": 0.55,
			"halfW": 0.55,
			"halfDepth": 0.5,
			"ownSpeed": 2.0,
			"telegraphSec": 0.9,
		},
		"crate": {"pass": "none", "halfW": 0.6, "halfDepth": 0.45, "ownSpeed": 0.0},
		"npc":
		{
			"pass": "jump",
			"clearY": 0.75,
			"halfW": 0.38,
			"halfDepth": 0.32,
			"ownSpeed": 0.0,
			"crossSpeed": 1.2,
		},
		"awning": {"pass": "slide", "gapY": 0.88, "halfDepth": 0.18, "ownSpeed": 0.0},
		"puddle":
		{
			"pass": "soft",
			"halfW": 0.65,
			"halfDepth": 0.5,
			"ownSpeed": 0.0,
			"slowMult": 0.9,
			"slowSec": 2.0,
		},
		"gap": {"pass": "jump", "halfDepth": 1.1, "ownSpeed": 0.0},
	},
	## §C8.4 Power-ups.
	"POWERUPS":
	{
		"magnet": {"sec": 6.0, "radius": 3.0},
		"x2": {"sec": 8.0},
		"shield": {},
		"turbo": {"sec": 2.5, "speedMult": 1.4, "minGapM": 400.0},
	},
	## §C8.4: ein Power-up alle 180–260 m, gesät.
	"POWERUP_GAP_MIN_M": 180.0,
	"POWERUP_GAP_MAX_M": 260.0,
	## Münz-Geometrie.
	"COIN_Y": 0.55,
	"COIN_STEP_M": 1.1,
	## Magnet-Münzen fliegen mit diesem Tempo (m/s).
	"MAGNET_PULL_SPEED": 14.0,
	## §C8.6 Reisemodus („Laufen").
	"TRAVEL": {"DISTANCE_M": 700.0, "JOG_SPEED": 7.0, "COIN_CAP": 30, "CLEAN_BONUS": 5},
	## Anti-Tunneling-Abtastschritt (m): kleinstes z-Fenster ist eine Markise
	## (2×(0,18+0,3) = 0,96 m) — 0,32 m kann keines überspringen.
	"MAX_SWEEP_STEP_M": 0.32,
	## §C8.7 Validator-Margen (konservatives Reaktionsmodell).
	"VALIDATOR":
	{
		"REACT_SEC": 0.18,
		"LANE_COST_SEC": 0.22,
		"ACTION_LEAD_SEC": 0.35,
		"ROW_EPS_SEC": 0.4,
	},
	## §G5.3 abgeleitete Modus-Regler (Mittel-Identität).
	"DENSITY_MULT": 1.0,
	"DENSITY_CAP": 1.0,
	"DENSITY_RAMP_FULL_M": 1500.0,
	"SPEED_MULT": 1.0,
	"SCORE_MULT": 1.0,
	"COIN_RATE": 1.0,
	"RENDER_SCALE_MULT": 1.0,
	"GATED_SPAWNS": false,
	"ENDLESS": false,
	"BOT_MISS_CHANCE": 0.012,
}

## §G5.3 Renn-Zeilen. Schwer-Deckel ist das verbindliche 16 → 18 m/s,
## Endlos rampt auf 20 m/s mit Dichte-Deckel ×1,5 und endet wie Arcade.
const SURF_DIFFICULTY := {
	"easy":
	{
		"speed": 0.85,
		"capMult": 0.85,
		"density": 0.85,
		"extraCrashes": 1,
		"endless": false,
		"botMiss": 0.005,
	},
	"normal":
	{
		"speed": 1.0,
		"capMult": 1.0,
		"density": 1.0,
		"extraCrashes": 0,
		"endless": false,
		"botMiss": 0.012,
	},
	"hard":
	{
		"speed": 1.2,
		"capMult": 1.125,
		"density": 1.15,
		"extraCrashes": 0,
		"endless": false,
		"botMiss": 0.07,
	},
	"endless":
	{
		"speed": 1.2,
		"capMult": 1.25,
		"density": 1.15,
		"densityCap": 1.5,
		"extraCrashes": 0,
		"endless": true,
		"botMiss": 0.07,
	},
}

## §C8.1 Bausteinpool — 12 handgebaute 30-m-Abschnitte.
## Regeln (vom §C8.7-Validator gesichert): Hindernisse liegen in atM ∈ [8, 24],
## Kistenreihen sperren nie alle 3 Spuren, gleiche Aktions-Hindernisse ≥ 13 m
## auseinander, `minM` staffelt schwere Abschnitte nach hinten.
const CHUNKS := [
	{
		"name": "warmup",
		"minM": 0.0,
		"hazards": [{"atM": 15.0, "kind": "cart", "lane": 1}],
		"coins": [{"atM": 15.0, "lane": 1, "n": 5, "arc": true}, {"atM": 22.0, "lane": 2, "n": 4}],
	},
	{
		"name": "cratePair",
		"minM": 0.0,
		"hazards":
		[
			{"atM": 10.0, "kind": "crate", "lane": 0},
			{"atM": 10.0, "kind": "crate", "lane": 1},
			{"atM": 23.0, "kind": "awning", "lanes": [0, 1]},
		],
		"coins": [{"atM": 10.0, "lane": 2, "n": 5}, {"atM": 23.0, "lane": 2, "n": 4}],
	},
	{
		"name": "cartsStagger",
		"minM": 60.0,
		"hazards":
		[{"atM": 9.0, "kind": "cart", "lane": 2}, {"atM": 22.0, "kind": "cart", "lane": 0}],
		"coins": [{"atM": 9.0, "lane": 2, "n": 5, "arc": true}, {"atM": 16.0, "lane": 1, "n": 4}],
	},
	{
		"name": "shopperCross",
		"minM": 60.0,
		"hazards": [{"atM": 8.0, "kind": "crate", "lane": 1}, {"atM": 21.0, "kind": "npc"}],
		"coins": [{"atM": 14.0, "lane": 0, "n": 4}, {"atM": 26.0, "lane": 1, "n": 4}],
	},
	{
		"name": "slideRow",
		"minM": 120.0,
		"hazards":
		[
			{"atM": 10.0, "kind": "awning", "lanes": [1, 2]},
			{"atM": 10.0, "kind": "crate", "lane": 0},
			{"atM": 24.0, "kind": "cart", "lane": 1},
		],
		"coins": [{"atM": 15.0, "lane": 2, "n": 5}, {"atM": 24.0, "lane": 1, "n": 5, "arc": true}],
	},
	{
		"name": "puddleAlley",
		"minM": 120.0,
		"hazards":
		[
			{"atM": 12.0, "kind": "crate", "lane": 0},
			{"atM": 12.0, "kind": "puddle", "lane": 1},
			{"atM": 12.0, "kind": "crate", "lane": 2},
		],
		"coins": [{"atM": 18.0, "lane": 1, "n": 5}, {"atM": 24.0, "lane": 0, "n": 3}],
	},
	{
		"name": "actionWall",
		"minM": 200.0,
		"hazards":
		[
			{"atM": 13.0, "kind": "cart", "lane": 0},
			{"atM": 13.0, "kind": "cart", "lane": 1},
			{"atM": 13.0, "kind": "awning", "lanes": [2]},
		],
		"coins": [{"atM": 13.0, "lane": 1, "n": 5, "arc": true}, {"atM": 20.0, "lane": 2, "n": 4}],
	},
	{
		"name": "shopperCrates",
		"minM": 200.0,
		"hazards":
		[
			{"atM": 9.0, "kind": "npc"},
			{"atM": 22.0, "kind": "crate", "lane": 1},
			{"atM": 22.0, "kind": "crate", "lane": 2},
		],
		"coins": [{"atM": 15.0, "lane": 1, "n": 4}, {"atM": 22.0, "lane": 0, "n": 5}],
	},
	{
		"name": "zigzag",
		"minM": 300.0,
		"hazards":
		[
			{"atM": 8.0, "kind": "crate", "lane": 0},
			{"atM": 16.0, "kind": "crate", "lane": 2},
			{"atM": 24.0, "kind": "crate", "lane": 1},
		],
		"coins": [{"atM": 12.0, "lane": 1, "n": 3}, {"atM": 20.0, "lane": 0, "n": 3}],
	},
	{
		"name": "doubleSlide",
		"minM": 300.0,
		"hazards":
		[
			{"atM": 9.0, "kind": "awning", "lanes": [0, 1]},
			{"atM": 23.0, "kind": "awning", "lanes": [1, 2]},
		],
		"coins": [{"atM": 16.0, "lane": 1, "n": 5}],
	},
	{
		"name": "curbBreak",
		"minM": 800.0,
		"hazards": [{"atM": 10.0, "kind": "gap"}, {"atM": 24.0, "kind": "cart", "lane": 1}],
		"coins": [{"atM": 10.0, "lane": 1, "n": 5, "arc": true}, {"atM": 18.0, "lane": 0, "n": 4}],
	},
	{
		"name": "gauntlet",
		"minM": 400.0,
		"hazards":
		[
			{"atM": 8.0, "kind": "cart", "lane": 1},
			{"atM": 21.0, "kind": "crate", "lane": 0},
			{"atM": 21.0, "kind": "puddle", "lane": 1},
		],
		"coins": [{"atM": 14.0, "lane": 2, "n": 4}, {"atM": 26.0, "lane": 2, "n": 4}],
	},
]

const POWERUP_KINDS := ["magnet", "x2", "shield", "turbo"]


## Abgeleitetes Tune (§G5.3); `normal` liefert exakt die Basis-Tabelle.
static func apply_difficulty(tune := SURF, mode := "normal") -> Dictionary:
	var id := mode if SURF_DIFFICULTY.has(mode) else "normal"
	if id == "normal":
		return tune
	var row: Dictionary = SURF_DIFFICULTY[id]
	var max_speed := float(tune["MAX_SPEED"]) * float(row["capMult"])
	var density := float(row["density"])
	var out := tune.duplicate()
	out["BASE_SPEED"] = float(tune["BASE_SPEED"]) * float(row["speed"])
	out["MAX_SPEED"] = max_speed
	out["ARCADE_MAX_CRASHES"] = int(tune["ARCADE_MAX_CRASHES"]) + int(row["extraCrashes"])
	out["DENSITY_MULT"] = density
	out["DENSITY_CAP"] = float(row.get("densityCap", density))
	out["SPEED_MULT"] = float(row["speed"])
	out["GATED_SPAWNS"] = density != 1.0 or max_speed > float(tune["MAX_SPEED"])
	out["ENDLESS"] = bool(row["endless"])
	out["BOT_MISS_CHANCE"] = float(row["botMiss"])
	out["MODE"] = id
	return out


## §C-SYS4.3 Modifikatoren: Münzregen / Turbo / Riesen-Gooby.
static func apply_modifier(tune: Dictionary, modifier: Dictionary) -> Dictionary:
	if modifier.is_empty():
		return tune
	var kind := str(modifier.get("type", ""))
	var out := tune.duplicate()
	if kind == "muenzregen":
		out["COIN_RATE"] = maxf(0.0, _num(modifier.get("coinRate"), 1.0))
		return out
	if kind == "turbo":
		var speed_mult := maxf(0.1, _num(modifier.get("speedMult"), 1.0))
		out["BASE_SPEED"] = float(tune["BASE_SPEED"]) * speed_mult
		out["MAX_SPEED"] = float(tune["MAX_SPEED"]) * speed_mult
		out["SPEED_MULT"] = float(tune["SPEED_MULT"]) * speed_mult
		out["SCORE_MULT"] = maxf(0.0, _num(modifier.get("scoreMult"), 1.0))
		out["GATED_SPAWNS"] = bool(tune["GATED_SPAWNS"]) or speed_mult > 1.0
		return out
	if kind == "riesenGooby":
		var hitbox := maxf(0.1, _num(modifier.get("hitboxMult"), 1.0))
		out["PLAYER_HALF_W"] = float(tune["PLAYER_HALF_W"]) * hitbox
		out["PLAYER_HALF_DEPTH"] = float(tune["PLAYER_HALF_DEPTH"]) * hitbox
		out["RENDER_SCALE_MULT"] = maxf(0.1, _num(modifier.get("scale"), 1.0))
		return out
	return tune


## Reise-Start-Modus („Laufen"); `surfTravel` ist der Alias aus dem Web.
static func is_travel_mode(mode: String) -> bool:
	return mode == "travel" or mode == "surfTravel"


## §C8.5 Vorwärtstempo nach `ramp_sec` ununterbrochenem Lauf (m/s).
static func speed_ramp_at(ramp_sec: float, tune := SURF) -> float:
	var steps := floorf(maxf(0.0, ramp_sec) / float(tune["SPEED_EVERY_SEC"]))
	return minf(
		float(tune["MAX_SPEED"]), float(tune["BASE_SPEED"]) + float(tune["SPEED_STEP"]) * steps
	)


## §C8.5 Punkte: floor(Meter) + Münzen×2 + Beinahe×2.
static func surf_score(distance_m: float, coins: int, near_misses: int) -> int:
	return maxi(0, int(floor(distance_m)) + coins * 2 + near_misses * 2)


## §C8.6 Reise-Belohnung: Münzen gedeckelt bei 30, +5 für einen sauberen Lauf.
static func travel_reward(coins_collected: int, crashes: int, tune := SURF) -> Dictionary:
	var travel: Dictionary = tune["TRAVEL"]
	var clean := maxi(0, crashes) == 0
	var capped := mini(int(travel["COIN_CAP"]), maxi(0, coins_collected))
	return {"coins": capped + (int(travel["CLEAN_BONUS"]) if clean else 0), "clean": clean}


## In-Frage-kommende Bausteine an `start_m` (ohne Vorgänger, minM/Lücken-Gate).
static func _eligible_chunks(start_m: float, last_index: int, tune: Dictionary) -> Array:
	var eligible: Array[int] = []
	for i in CHUNKS.size():
		if i == last_index:
			continue
		var def: Dictionary = CHUNKS[i]
		if start_m < float(def["minM"]):
			continue
		if _has_gap(def) and start_m < float(tune["GAP_MIN_DISTANCE_M"]):
			continue
		eligible.append(i)
	return eligible


static func _has_gap(def: Dictionary) -> bool:
	for h: Dictionary in def["hazards"]:
		if str(h["kind"]) == "gap":
			return true
	return false


## §C8.1 gesäte Bausteinwahl: der Aufwärmabschnitt eröffnet jeden Lauf.
static func pick_next_chunk(rng: GoobyRng, start_m: float, last_index: int, tune := SURF) -> int:
	if start_m <= 0.0:
		return 0
	var eligible := _eligible_chunks(start_m, last_index, tune)
	return int(eligible[int(floor(rng.next() * eligible.size())) % eligible.size()])


## Baustein auf absolute Strecken auffalten.
static func expand_chunk(def: Dictionary, start_m: float) -> Dictionary:
	var hazards: Array[Dictionary] = []
	for h: Dictionary in def["hazards"]:
		var copy := h.duplicate()
		copy["atM"] = start_m + float(h["atM"])
		hazards.append(copy)
	var coins: Array[Dictionary] = []
	for c: Dictionary in def["coins"]:
		var copy := c.duplicate()
		copy["atM"] = start_m + float(c["atM"])
		coins.append(copy)
	return {"hazards": hazards, "coins": coins}


## Hindernisdichte an einer Strecke; nur Endlos rampt bis DENSITY_CAP.
static func density_mult_at(distance_m: float, tune := SURF) -> float:
	var base := float(tune["DENSITY_MULT"])
	var cap := float(tune["DENSITY_CAP"])
	if not bool(tune["ENDLESS"]) or cap <= base:
		return base
	var t := clampf(distance_m / float(tune["DENSITY_RAMP_FULL_M"]), 0.0, 1.0)
	return base + (cap - base) * t


## Alle Rampentempi eines Tunes (BASIS → MAX) — die Prüfmenge des Validators.
static func validator_probe_speeds(tune := SURF) -> Array[float]:
	var speeds: Array[float] = []
	var max_speed := float(tune["MAX_SPEED"])
	var step := float(tune["SPEED_STEP"])
	var v := float(tune["BASE_SPEED"])
	while v <= max_speed + 1e-9:
		speeds.append(v)
		v += step
	if speeds[speeds.size() - 1] < max_speed - 1e-9:
		speeds.append(max_speed)
	return speeds


## Validator-gesicherte Bausteinwahl (dichte Modi): derselbe eine gesäte Zug
## wie oben, dann Rotation durch den Pool bis ein Kandidat bei JEDEM
## Rampentempo überlebbar ist — inklusive der noch lebenden Hindernisse davor.
## −1 = nichts passt; der Aufrufer schiebt eine Verschnaufpause ein.
static func pick_next_survivable_chunk(
	rng: GoobyRng, start_m: float, last_index: int, recent_hazards: Array, tune := SURF
) -> int:
	if start_m <= 0.0:
		return 0
	var eligible := _eligible_chunks(start_m, last_index, tune)
	var first := int(floor(rng.next() * eligible.size())) % eligible.size()
	var speeds := validator_probe_speeds(tune)
	for k in eligible.size():
		var idx := int(eligible[(first + k) % eligible.size()])
		var seq: Array = recent_hazards.duplicate()
		seq.append_array(expand_chunk(CHUNKS[idx], start_m)["hazards"])
		var ok := true
		for v in speeds:
			if not is_sequence_survivable(seq, v, tune):
				ok = false
				break
		if ok:
			return idx
	return -1


## Absolute Hindernisse zu Ankunfts-Zeilen bei konstantem Prüftempo bündeln.
## Rollende Wagen tauchen erst am Horizont auf und rollen DANN entgegen, daher
## der geklammerte Treffpunkt. Passanten und Lücken sperren alle Spuren
## (konservativ), Pfützen sind weich und werden ignoriert.
static func hazard_rows(hazards: Array, speed: float, tune := SURF) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var obstacles: Dictionary = tune["OBSTACLES"]
	for h: Dictionary in hazards:
		var kind := str(h["kind"])
		if not obstacles.has(kind):
			continue
		var def: Dictionary = obstacles[kind]
		if str(def["pass"]) == "soft":
			continue
		var own := float(def["ownSpeed"])
		var at_m := float(h["atM"])
		var meet_m := maxf(
			at_m * speed / (speed + own), at_m - float(tune["SPAWN_AHEAD_M"]) * own / (speed + own)
		)
		var lanes: Array = []
		if kind == "npc" or kind == "gap":
			lanes = [0, 1, 2]
		elif kind == "awning":
			lanes = h["lanes"]
		else:
			lanes = [int(h["lane"])]
		events.append({"t": meet_m / speed, "lanes": lanes, "pass": str(def["pass"])})
	events.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["t"] < b["t"])
	return _group_rows(events, tune)


static func _group_rows(events: Array[Dictionary], tune: Dictionary) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	var eps := float((tune["VALIDATOR"] as Dictionary)["ROW_EPS_SEC"])
	for ev: Dictionary in events:
		var merged := not rows.is_empty() and float(ev["t"]) - float(rows[-1]["t"]) <= eps
		var target: Dictionary = rows[-1] if merged else _blank_row(float(ev["t"]), tune)
		var slots: Array = target["lanes"]
		for lane in ev["lanes"]:
			var prev: Variant = slots[int(lane)]
			if prev == "none":
				continue
			# Strengste Anforderung gewinnt; Sprung + Rutschen gleichzeitig ist
			# widersprüchlich → gesperrt.
			if ev["pass"] == "none" or (prev != null and prev != ev["pass"]):
				slots[int(lane)] = "none"
			else:
				slots[int(lane)] = ev["pass"]
		if not merged:
			rows.append(target)
	return rows


static func _blank_row(t: float, tune: Dictionary) -> Dictionary:
	var slots: Array = []
	for _i in int(tune["LANES"]):
		slots.append(null)
	return {"t": t, "lanes": slots}


## §C8.7 Nie-unmöglich-Beweis: DP-Erreichbarkeit über die Spuren je Zeile.
## Eine Kante existiert, wenn die Zeit für Reaktion + Spurwechsel + (bei
## Aktions-Spuren) den Sprung-/Rutsch-Vorlauf reicht. Zusätzlich sperrt die
## Dauer der VORIGEN Aktion einen neuen Sprung/Rutsch (stepRun-Regel).
static func is_sequence_survivable(hazards: Array, speed: float, tune := SURF) -> bool:
	var v: Dictionary = tune["VALIDATOR"]
	var lanes := int(tune["LANES"])
	var rows := hazard_rows(hazards, speed, tune)
	var react := float(v["REACT_SEC"])
	var lane_cost := float(v["LANE_COST_SEC"])
	var lead := float(v["ACTION_LEAD_SEC"])
	var dur := {"jump": float(tune["JUMP_SEC"]), "slide": float(tune["SLIDE_SEC"])}
	var reachable: Array[bool] = []
	var prev_action: Array = []
	for _i in lanes:
		reachable.append(true)
		prev_action.append(null)
	var prev_t := -react
	for row: Dictionary in rows:
		var dt := float(row["t"]) - prev_t
		var next: Array[bool] = []
		var next_action: Array = []
		for _i in lanes:
			next.append(false)
			next_action.append(null)
		for to in lanes:
			var need: Variant = (row["lanes"] as Array)[to]
			if need == "none":
				continue
			for from in lanes:
				if not reachable[from]:
					continue
				var busy := 0.0
				if need != null and prev_action[from] != null:
					busy = float(dur[prev_action[from]])
				var cost := maxf(react, busy) + lane_cost * absi(to - from)
				if need != null:
					cost += lead
				if dt >= cost:
					next[to] = true
					if need == "jump" or need == "slide":
						next_action[to] = need
					break
		reachable = next
		prev_action = next_action
		if not reachable.has(true):
			return false
		prev_t = float(row["t"])
	return true


## §C8.4 nächste Power-up-Art: nie zweimal dieselbe, Turbo höchstens je 400 m.
static func plan_powerup_kind(
	rng: GoobyRng, last_kind: Variant, since_turbo_m: float, tune := SURF
) -> String:
	var turbo_gap := float((tune["POWERUPS"] as Dictionary)["turbo"]["minGapM"])
	var pool: Array[String] = []
	for k in POWERUP_KINDS:
		if k == last_kind:
			continue
		if k == "turbo" and since_turbo_m < turbo_gap:
			continue
		pool.append(str(k))
	return pool[int(floor(rng.next() * pool.size())) % pool.size()]


## §C8.4 gesäter Abstand zum nächsten Power-up (180–260 m).
static func plan_powerup_gap(rng: GoobyRng, tune := SURF) -> float:
	var lo := float(tune["POWERUP_GAP_MIN_M"])
	return lo + rng.next() * (float(tune["POWERUP_GAP_MAX_M"]) - lo)


## Münzregen: gebrochene COIN_RATE über EINEN gesäten Bernoulli-Zug.
## COIN_RATE 1 zieht NICHTS — der Mittel-Strom bleibt bit-identisch.
static func coin_row_count(rng: GoobyRng, n: int, tune := SURF) -> int:
	var expected := maxf(0.0, n * float(tune.get("COIN_RATE", 1.0)))
	var whole := int(floor(expected))
	var fraction := expected - whole
	return whole + (1 if (fraction > 0.0 and rng.next() < fraction) else 0)


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
