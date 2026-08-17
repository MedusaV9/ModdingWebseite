class_name ToyRacerLogic
extends RefCounted
## Pure Spielzeug-Rennen-Logik — zahlengleicher Port von
## GOOBY/src/minigames/games/toyRacer.logic.js (PLAN3 §C10.1 #1).
## 3 Runden auf einem gesäten Spielzeug-Kurs (2 Vorlagen × Seeds) gegen
## 3 Gummiband-KI-Karts. Halten = Drift laden, Loslassen = 1,2 s Schub.
## Item-Kisten je ⅓ Runde (Turbo / Schild / Bauklotz). Neben der Strecke
## 40 % langsamer. Punkte = Platzbonus + 2·Überholer + Driftmeter/10.
## Coin-Zeile /6, 5..30, Ziel 150.

## §C10.1 #1 Bindezahlen + G41-Feel-Regler.
const RACER := {
	"LAPS": 3,
	"KARTS": 4,
	"PIECES_PER_LOOP": 8,
	"TRACK_HALF_W": 0.5,
	"LAT_MAX": 0.36,
	"LAT_HARD_MAX": 0.78,
	"TARGET_LAP_SEC": 47.0,
	"MAX_RACE_SEC": 240.0,
	"WORLD_SCALE": 2.6,
	"STEER_RATE": 1.1,
	"DRIFT_STEER_MULT": 1.6,
	"SLIP_GAIN": 0.5,
	"DRIFT_SLIP_MULT": 0.25,
	"DRIFT_BOOST_SEC": 1.2,
	"DRIFT_BOOST_MULT": 1.45,
	"DRIFT_MIN_CHARGE": 0.35,
	"DRIFT_CHARGE_RATE_CURVE": 0.55,
	"DRIFT_CHARGE_RATE_STRAIGHT": 0.12,
	"DRIFT_MIN_KAPPA": 0.12,
	"OFFTRACK_MULT": 0.6,
	"ITEM_ROWS_PER_LAP": 3,
	"ITEM_ROW_FRACTIONS": [0.18, 0.5, 0.82],
	"ITEM_BOX_LATS": [-0.3, 0.0, 0.3],
	"ITEM_RESPAWN_SEC": 2.5,
	"PICKUP_S_WINDOW": 0.35,
	"PICKUP_LAT_WINDOW": 0.24,
	"ITEM_KINDS": ["turbo", "shield", "block"],
	"ITEM_WEIGHTS": [0.4, 0.3, 0.3],
	"TURBO_SEC": 2.0,
	"TURBO_MULT": 1.5,
	"BLOCK_DROP_BEHIND": 0.8,
	"BLOCK_STUN_SEC": 0.9,
	"BLOCK_STUN_MULT": 0.25,
	"BLOCK_HIT_S": 0.28,
	"BLOCK_HIT_LAT": 0.22,
	"MAX_BLOCKS": 6,
	"RUBBER_DIST": 6.0,
	"RUBBER_GAIN": 0.1,
	"RUBBER_MIN": 0.88,
	"RUBBER_MAX": 1.12,
	"AI_SPREAD": 0.04,
	"ACCEL_RATE": 2.0,
	"BRAKE_RATE": 5.0,
	"POSITION_BONUS": [120, 80, 50, 30],
	"OVERTAKE_POINTS": 2,
	"DRIFT_METERS_DIV": 10.0,
	"OVERTAKE_COOLDOWN_SEC": 1.5,
	"BOT_DRIFT_MIN_DEG": 45.0,
	"BOT_CORNER_LOOKAHEAD": 1.0,
	"SAMPLE_STEP": 0.25,
	"GRID_GAP": 0.85,
	"MAX_SUBSTEP": 1.0 / 30.0,
	"AI_EDGE": 0.0,
	"SPEED_MULT": 1.0,
	"SCORE_MULT": 1.0,
	"ITEM_RATE": 1.0,
	"ENDLESS": false,
	"ENDLESS_CHAIN_MAX_RANK": 2,
	"ENDLESS_CHAIN_EDGE_STEP": 0.02,
	"BOT_LAPSE_EVERY_SEC": 0.0,
	"BOT_LAPSE_SEC": 1.6,
}

## §G5.3-Zeilen: Tempo skaliert das ganze Feld, AI-Spread/Edge + Gummiband
## regeln den Pack-Druck. Endlos kettet Rennen (§G5.4).
const RACER_DIFFICULTY := {
	"easy":
	{
		"speed": 0.85,
		"aiSpread": 0.08,
		"aiEdge": -0.02,
		"rubberMin": 0.85,
		"rubberMax": 1.08,
		"botLapse": 0.0,
	},
	"normal":
	{
		"speed": 1.0,
		"aiSpread": 0.04,
		"aiEdge": 0.0,
		"rubberMin": 0.88,
		"rubberMax": 1.12,
		"botLapse": 0.0,
	},
	"hard":
	{
		"speed": 1.2,
		"aiSpread": 0.022,
		"aiEdge": 0.015,
		"rubberMin": 0.92,
		"rubberMax": 1.12,
		"botLapse": 18.0,
	},
	"endless":
	{
		"speed": 1.2,
		"aiSpread": 0.022,
		"aiEdge": 0.015,
		"rubberMin": 0.92,
		"rubberMax": 1.12,
		"botLapse": 18.0,
	},
}

## GP3-Juice — reine Feier-Regler.
const RACER_JUICE := {"BOOST_FLASH_SEC": 0.4}

## Spline-Werkzeug (Streckenbau + Abtastung) — eigene Datei, gleiche Zahlen.
const Track := preload("res://scripts/minigames/games/toy_racer/toy_racer_track.gd")


## Gesäter Kurs (2 Vorlagen × Seeds) inkl. Bogenlängen-Tabelle.
static func build_track(seed_value: int, tune := RACER) -> Dictionary:
	return Track.build_track(seed_value, tune)


## Mittelspline bei Bogenlänge s (läuft rundenweise um).
static func point_at(track: Dictionary, s: float) -> Dictionary:
	return Track.point_at(track, s)


static func in_loop_zone(track: Dictionary, s: float) -> bool:
	return Track.in_loop_zone(track, s)


## Kurvenzone (mit Vorausschau) über minDeg, sonst {}.
static func corner_zone_at(
	track: Dictionary, s: float, lookahead := 0.0, min_deg := 0.0
) -> Dictionary:
	return Track.corner_zone_at(track, s, lookahead, min_deg)


## Abgeleitetes Tune; `normal` liefert exakt die Basis-Tabelle.
static func apply_difficulty(tune := RACER, mode := "normal") -> Dictionary:
	if mode == "normal" or not RACER_DIFFICULTY.has(mode):
		return tune
	var row: Dictionary = RACER_DIFFICULTY[mode]
	var out := tune.duplicate(true)
	out["TARGET_LAP_SEC"] = float(tune["TARGET_LAP_SEC"]) / float(row["speed"])
	out["AI_SPREAD"] = float(row["aiSpread"])
	out["AI_EDGE"] = float(row["aiEdge"])
	out["RUBBER_MIN"] = float(row["rubberMin"])
	out["RUBBER_MAX"] = float(row["rubberMax"])
	out["SPEED_MULT"] = float(row["speed"])
	out["BOT_LAPSE_EVERY_SEC"] = float(row["botLapse"])
	out["ENDLESS"] = mode == "endless"
	out["MODE"] = mode
	return out


## §C-SYS4.3-Modifikatoren (muenzregen / turbo).
static func apply_modifier(tune: Dictionary, modifier: Dictionary) -> Dictionary:
	if modifier.is_empty():
		return tune
	var kind := str(modifier.get("type", ""))
	var out := tune.duplicate(true)
	if kind == "muenzregen":
		var rate := maxf(0.1, float(modifier.get("coinRate", 1.0)))
		out["ITEM_RESPAWN_SEC"] = float(tune["ITEM_RESPAWN_SEC"]) / rate
		out["ITEM_RATE"] = rate
		return out
	if kind == "turbo":
		var speed_mult := maxf(0.1, float(modifier.get("speedMult", 1.0)))
		out["TARGET_LAP_SEC"] = float(tune["TARGET_LAP_SEC"]) / speed_mult
		out["SPEED_MULT"] = float(tune["SPEED_MULT"]) * speed_mult
		out["SCORE_MULT"] = maxf(0.0, float(modifier.get("scoreMult", 1.0)))
		return out
	return tune


## Gummiband-Faktor einer KI: hinter dem Spieler schneller, davor langsamer.
static func compute_rubber(gap: float, tune := RACER) -> float:
	return minf(
		float(tune["RUBBER_MAX"]),
		maxf(
			float(tune["RUBBER_MIN"]),
			1.0 + (gap / float(tune["RUBBER_DIST"])) * float(tune["RUBBER_GAIN"])
		)
	)


## Gewichteter Item-Wurf (Turbo / Schild / Bauklotz).
static func roll_item(rng: GoobyRng, tune := RACER) -> String:
	var r := rng.next()
	var kinds: Array = tune["ITEM_KINDS"]
	var weights: Array = tune["ITEM_WEIGHTS"]
	for i in kinds.size():
		r -= float(weights[i])
		if r < 0.0:
			return str(kinds[i])
	return str(kinds[kinds.size() - 1])


## §C10.1-Punkteformel: Platzbonus + 2·Überholer + Driftmeter/10 (abgerundet).
static func race_score(rank: int, overtakes: int, drift_meters: float, tune := RACER) -> int:
	var bonus_table: Array = tune["POSITION_BONUS"]
	var idx := mini(bonus_table.size(), maxi(1, rank)) - 1
	return (
		int(bonus_table[idx])
		+ int(tune["OVERTAKE_POINTS"]) * overtakes
		+ int(floorf(drift_meters / float(tune["DRIFT_METERS_DIV"])))
	)


## Gesäter Rennzustand.
static func create_race(seed_value: int, tune := RACER) -> Dictionary:
	var track := build_track(seed_value, tune)
	var rng := GoobyRng.new((seed_value ^ 0x9E3779B9) & 0xFFFFFFFF)
	var lap_len := float(track["lapLen"])
	var base_speed := lap_len / float(tune["TARGET_LAP_SEC"])
	var karts: Array[Dictionary] = []
	var lane_spread := [-0.26, 0.0, 0.26]
	for i in int(tune["KARTS"]):
		var is_player := i == 0
		var grid_pos := int(tune["KARTS"]) - 1 if is_player else i - 1
		var grid_offset := 1.0 + grid_pos * float(tune["GRID_GAP"])
		var personality := 1.0
		var lane_bias := 0.0
		if not is_player:
			personality = 1.0 + float(tune["AI_EDGE"]) - rng.next() * float(tune["AI_SPREAD"])
			lane_bias = float(lane_spread[i - 1]) + (rng.next() * 2.0 - 1.0) * 0.05
		(
			karts
			. append(
				{
					"id": i,
					"isPlayer": is_player,
					"s": fmod(fmod(lap_len - grid_offset, lap_len) + lap_len, lap_len),
					"progress": -grid_offset,
					"lateral": -0.22 if grid_pos % 2 == 0 else 0.22,
					"targetLateral": 0.0,
					"speed": 0.0,
					"drifting": false,
					"driftCharge": 0.0,
					"driftMeters": 0.0,
					"boostT": 0.0,
					"boostMult": 1.0,
					"stunT": 0.0,
					"offTrack": false,
					"shield": false,
					"item": "",
					"personality": personality,
					"laneBias": lane_bias,
					"passSign": 0,
					"passCooldown": 0.0,
					"finished": false,
					"finishRank": 0,
				}
			)
		)
	return {
		"seed": seed_value,
		"tune": tune,
		"track": track,
		"rng": rng,
		"baseSpeed": base_speed,
		"karts": karts,
		"blocks": [] as Array[Dictionary],
		"time": 0.0,
		"overtakes": 0,
		"ended": false,
		"finishRank": 0,
		"lastLapBanner": 0,
		"events": [] as Array[Dictionary],
		"raceStartT": 0.0,
		"chainRaces": 0,
		"chainWins": 0,
		"chainScore": 0,
		"chainEdge": 0.0,
	}


## Aktueller Platz 1..4 des Spielers.
static func player_rank(race: Dictionary) -> int:
	var karts: Array = race["karts"]
	var p := float(karts[0]["progress"])
	var rank := 1
	for i in range(1, karts.size()):
		if float(karts[i]["progress"]) > p:
			rank += 1
	return rank


## Angezeigte Rundennummer 1..LAPS.
static func player_lap(race: Dictionary) -> int:
	var track: Dictionary = race["track"]
	var tune: Dictionary = race["tune"]
	var laps := int(floorf(float(race["karts"][0]["progress"]) / float(track["lapLen"]))) + 1
	return mini(int(tune["LAPS"]), maxi(1, laps))


## Vorzeichenbehaftete kürzeste s-Differenz auf dem Ring.
static func s_delta(a: float, b: float, lap_len: float) -> float:
	var d := a - b
	while d > lap_len / 2.0:
		d -= lap_len
	while d < -lap_len / 2.0:
		d += lap_len
	return d


static func _use_item(race: Dictionary, kart: Dictionary) -> void:
	var tune: Dictionary = race["tune"]
	var kind := str(kart["item"])
	if kind.is_empty():
		return
	kart["item"] = ""
	if kind == "turbo":
		kart["boostT"] = maxf(float(kart["boostT"]), float(tune["TURBO_SEC"]))
		kart["boostMult"] = float(tune["TURBO_MULT"])
		race["events"].append({"type": "turbo", "kart": int(kart["id"])})
	elif kind == "shield":
		kart["shield"] = true
		race["events"].append({"type": "shield", "kart": int(kart["id"])})
	else:
		var lap_len := float(race["track"]["lapLen"])
		var s := fmod(
			fmod(float(kart["s"]) - float(tune["BLOCK_DROP_BEHIND"]), lap_len) + lap_len, lap_len
		)
		var blocks: Array = race["blocks"]
		blocks.append({"s": s, "lat": float(kart["lateral"]), "by": int(kart["id"])})
		if blocks.size() > int(tune["MAX_BLOCKS"]):
			blocks.pop_front()
		(
			race["events"]
			. append(
				{
					"type": "blockDrop",
					"kart": int(kart["id"]),
					"s": s,
					"lat": float(kart["lateral"]),
				}
			)
		)


## KI-Entscheidung (Mittelspline + Ideallinie + Item-Suche).
static func ai_input(race: Dictionary, kart: Dictionary) -> Dictionary:
	var tune: Dictionary = race["tune"]
	var track: Dictionary = race["track"]
	var lap_len := float(track["lapLen"])
	var steer := float(kart["laneBias"])
	var zone := corner_zone_at(track, float(kart["s"]), float(tune["BOT_CORNER_LOOKAHEAD"]), 0.0)
	if not zone.is_empty():
		steer = -0.2 + float(kart["laneBias"]) * 0.6
	if str(kart["item"]).is_empty():
		for row: Dictionary in track["itemRows"]:
			var d := s_delta(float(row["s"]), float(kart["s"]), lap_len)
			if d > 0.0 and d < 3.0:
				var best := 0.0
				var has_best := false
				for box: Dictionary in row["boxes"]:
					if float(box["respawnT"]) > 0.0:
						continue
					if (
						not has_best
						or (
							absf(float(box["lat"]) - float(kart["lateral"]))
							< absf(best - float(kart["lateral"]))
						)
					):
						best = float(box["lat"])
						has_best = true
				if has_best:
					steer = best
	for block: Dictionary in race["blocks"]:
		var d := s_delta(float(block["s"]), float(kart["s"]), lap_len)
		if d > 0.0 and d < 2.2 and absf(float(block["lat"]) - float(kart["lateral"])) < 0.3:
			var lat := float(block["lat"])
			steer = lat - 0.45 if lat > 0.0 else lat + 0.45
	var drifting := (
		not zone.is_empty() and float(zone["turnDeg"]) >= float(tune["BOT_DRIFT_MIN_DEG"])
	)
	return {"steer": steer, "drifting": drifting, "useItem": not str(kart["item"]).is_empty()}


## Ein Integrationsschritt eines Karts.
static func step_kart(race: Dictionary, kart: Dictionary, dt: float, input: Dictionary) -> void:
	var tune: Dictionary = race["tune"]
	var track: Dictionary = race["track"]
	var lap_len := float(track["lapLen"])
	var sample := point_at(track, float(kart["s"]))

	var was_drifting := bool(kart["drifting"])
	kart["drifting"] = bool(input.get("drifting", false)) and float(kart["stunT"]) <= 0.0
	if was_drifting and not bool(kart["drifting"]):
		if bool(kart["isPlayer"]) and float(kart["driftCharge"]) >= float(tune["DRIFT_MIN_CHARGE"]):
			kart["boostT"] = maxf(float(kart["boostT"]), float(tune["DRIFT_BOOST_SEC"]))
			kart["boostMult"] = float(tune["DRIFT_BOOST_MULT"])
			(
				race["events"]
				. append(
					{
						"type": "boost",
						"kart": int(kart["id"]),
						"charge": float(kart["driftCharge"]),
					}
				)
			)
		kart["driftCharge"] = 0.0
	if bool(kart["drifting"]) and float(kart["speed"]) > 0.2:
		var curved := absf(float(sample["kappa"])) >= float(tune["DRIFT_MIN_KAPPA"])
		var rate_c := (
			float(tune["DRIFT_CHARGE_RATE_CURVE"])
			if curved
			else float(tune["DRIFT_CHARGE_RATE_STRAIGHT"])
		)
		kart["driftCharge"] = minf(1.0, float(kart["driftCharge"]) + rate_c * dt)
		kart["driftMeters"] = (
			float(kart["driftMeters"]) + float(kart["speed"]) * dt * float(tune["WORLD_SCALE"])
		)

	var target := float(race["baseSpeed"]) * float(kart["personality"])
	if float(kart["boostT"]) > 0.0:
		target *= float(kart["boostMult"])
	if float(kart["stunT"]) > 0.0:
		target *= float(tune["BLOCK_STUN_MULT"])
	if bool(kart["offTrack"]):
		target *= float(tune["OFFTRACK_MULT"])
	if not bool(kart["isPlayer"]):
		target *= compute_rubber(
			float(race["karts"][0]["progress"]) - float(kart["progress"]), tune
		)
	var rate := (
		float(tune["BRAKE_RATE"]) if target < float(kart["speed"]) else float(tune["ACCEL_RATE"])
	)
	kart["speed"] = float(kart["speed"]) + (target - float(kart["speed"])) * minf(1.0, dt * rate)

	var in_loop := in_loop_zone(track, float(kart["s"]))
	var steer: Variant = input.get("steer", null)
	var hard := float(tune["LAT_HARD_MAX"])
	if steer != null and not in_loop:
		kart["targetLateral"] = maxf(-hard, minf(hard, float(steer)))
	if in_loop:
		kart["targetLateral"] = 0.0
	var steer_rate := (
		float(tune["STEER_RATE"])
		* (float(tune["DRIFT_STEER_MULT"]) if bool(kart["drifting"]) else 1.0)
	)
	var d_lat := float(kart["targetLateral"]) - float(kart["lateral"])
	var max_step := steer_rate * dt
	kart["lateral"] = float(kart["lateral"]) + maxf(-max_step, minf(max_step, d_lat))
	var slip := (
		float(sample["kappa"])
		* float(kart["speed"])
		* float(kart["speed"])
		* float(tune["SLIP_GAIN"])
		* (float(tune["DRIFT_SLIP_MULT"]) if bool(kart["drifting"]) else 1.0)
	)
	kart["lateral"] = float(kart["lateral"]) + slip * dt
	kart["lateral"] = maxf(-hard, minf(hard, float(kart["lateral"])))
	var was_off := bool(kart["offTrack"])
	kart["offTrack"] = absf(float(kart["lateral"])) > float(tune["TRACK_HALF_W"]) and not in_loop
	if bool(kart["offTrack"]) and not was_off and bool(kart["isPlayer"]):
		race["events"].append({"type": "offtrack", "kart": int(kart["id"])})

	kart["s"] = fmod(fmod(float(kart["s"]) + float(kart["speed"]) * dt, lap_len) + lap_len, lap_len)
	kart["progress"] = float(kart["progress"]) + float(kart["speed"]) * dt

	for row: Dictionary in track["itemRows"]:
		if (
			absf(s_delta(float(row["s"]), float(kart["s"]), lap_len))
			> float(tune["PICKUP_S_WINDOW"])
		):
			continue
		for box: Dictionary in row["boxes"]:
			if float(box["respawnT"]) > 0.0:
				continue
			if absf(float(box["lat"]) - float(kart["lateral"])) > float(tune["PICKUP_LAT_WINDOW"]):
				continue
			box["respawnT"] = float(tune["ITEM_RESPAWN_SEC"])
			if str(kart["item"]).is_empty():
				kart["item"] = roll_item(race["rng"], tune)
				(
					race["events"]
					. append(
						{
							"type": "pickup",
							"kart": int(kart["id"]),
							"item": str(kart["item"]),
							"s": float(row["s"]),
							"lat": float(box["lat"]),
						}
					)
				)
			else:
				(
					race["events"]
					. append(
						{
							"type": "boxBump",
							"kart": int(kart["id"]),
							"s": float(row["s"]),
							"lat": float(box["lat"]),
						}
					)
				)
			break

	if float(kart["stunT"]) <= 0.0:
		var blocks: Array = race["blocks"]
		for i in range(blocks.size() - 1, -1, -1):
			var block: Dictionary = blocks[i]
			var dist := absf(s_delta(float(block["s"]), float(kart["s"]), lap_len))
			if int(block["by"]) == int(kart["id"]) and dist < 1.2:
				continue
			if dist > float(tune["BLOCK_HIT_S"]):
				continue
			if absf(float(block["lat"]) - float(kart["lateral"])) > float(tune["BLOCK_HIT_LAT"]):
				continue
			blocks.remove_at(i)
			if bool(kart["shield"]):
				kart["shield"] = false
				race["events"].append({"type": "shieldPop", "kart": int(kart["id"])})
			else:
				kart["stunT"] = float(tune["BLOCK_STUN_SEC"])
				kart["driftCharge"] = 0.0
				race["events"].append({"type": "blockHit", "kart": int(kart["id"])})
			break

	if bool(input.get("useItem", false)):
		_use_item(race, kart)
	kart["boostT"] = maxf(0.0, float(kart["boostT"]) - dt)
	kart["stunT"] = maxf(0.0, float(kart["stunT"]) - dt)


## §G5.4 Endlos-Kette: das gefahrene Rennen buchen und das Feld neu aufstellen.
static func reset_race_for_chain(race: Dictionary, rank: int) -> void:
	var tune: Dictionary = race["tune"]
	var track: Dictionary = race["track"]
	var lap_len := float(track["lapLen"])
	var karts: Array = race["karts"]
	race["chainScore"] = (
		int(race["chainScore"])
		+ race_score(rank, int(race["overtakes"]), float(karts[0]["driftMeters"]), tune)
	)
	race["chainRaces"] = int(race["chainRaces"]) + 1
	if rank == 1:
		race["chainWins"] = int(race["chainWins"]) + 1
	race["chainEdge"] = float(race["chainEdge"]) + float(tune["ENDLESS_CHAIN_EDGE_STEP"])
	for i in karts.size():
		var kart: Dictionary = karts[i]
		var grid_pos := int(tune["KARTS"]) - 1 if bool(kart["isPlayer"]) else i - 1
		var grid_offset := 1.0 + grid_pos * float(tune["GRID_GAP"])
		kart["s"] = fmod(fmod(lap_len - grid_offset, lap_len) + lap_len, lap_len)
		kart["progress"] = -grid_offset
		kart["lateral"] = -0.22 if grid_pos % 2 == 0 else 0.22
		kart["targetLateral"] = 0.0
		kart["speed"] = 0.0
		kart["drifting"] = false
		kart["driftCharge"] = 0.0
		kart["driftMeters"] = 0.0
		kart["boostT"] = 0.0
		kart["boostMult"] = 1.0
		kart["stunT"] = 0.0
		kart["offTrack"] = false
		kart["shield"] = false
		kart["item"] = ""
		kart["passSign"] = 0
		kart["passCooldown"] = 0.0
		if not bool(kart["isPlayer"]):
			kart["personality"] = (
				float(kart["personality"]) + float(tune["ENDLESS_CHAIN_EDGE_STEP"])
			)
	(race["blocks"] as Array).clear()
	race["overtakes"] = 0
	race["lastLapBanner"] = 0
	race["raceStartT"] = float(race["time"])
	for row: Dictionary in track["itemRows"]:
		for box: Dictionary in row["boxes"]:
			box["respawnT"] = 0.0
	(
		race["events"]
		. append(
			{
				"type": "chainRace",
				"races": int(race["chainRaces"]),
				"rank": rank,
				"banked": int(race["chainScore"]),
			}
		)
	)


## Rennen um dt weiterrechnen (intern in Teilschritten).
static func step_race(race: Dictionary, dt: float, input := {}) -> void:
	if bool(race["ended"]):
		return
	var tune: Dictionary = race["tune"]
	var track: Dictionary = race["track"]
	var karts: Array = race["karts"]
	var lap_len := float(track["lapLen"])
	var p_steer: Variant = input.get("steer", null)
	var p_drift := bool(input.get("drifting", false))
	var p_use_item := bool(input.get("useItem", false))
	var remaining := minf(dt, 0.25)
	while remaining > 1e-9 and not bool(race["ended"]):
		var h := minf(float(tune["MAX_SUBSTEP"]), remaining)
		remaining -= h
		race["time"] = float(race["time"]) + h

		for row: Dictionary in track["itemRows"]:
			for box: Dictionary in row["boxes"]:
				box["respawnT"] = maxf(0.0, float(box["respawnT"]) - h)

		var player: Dictionary = karts[0]
		step_kart(race, player, h, {"steer": p_steer, "drifting": p_drift, "useItem": p_use_item})
		p_use_item = false
		for i in range(1, karts.size()):
			var kart: Dictionary = karts[i]
			step_kart(race, kart, h, ai_input(race, kart))
			kart["passCooldown"] = maxf(0.0, float(kart["passCooldown"]) - h)
			var sign_v := signf(float(player["progress"]) - float(kart["progress"]))
			if (
				sign_v > 0.0
				and int(kart["passSign"]) < 0
				and float(kart["passCooldown"]) <= 0.0
				and float(race["time"]) > 1.0
			):
				race["overtakes"] = int(race["overtakes"]) + 1
				kart["passCooldown"] = float(tune["OVERTAKE_COOLDOWN_SEC"])
				race["events"].append({"type": "overtake", "total": int(race["overtakes"])})
			if sign_v != 0.0:
				kart["passSign"] = int(sign_v)

		var lap := int(floorf(float(player["progress"]) / lap_len))
		if lap > int(race["lastLapBanner"]) and lap < int(tune["LAPS"]):
			race["lastLapBanner"] = lap
			race["events"].append(
				{"type": "lap", "lap": lap + 1, "final": lap + 1 == int(tune["LAPS"])}
			)

		var timed_out := (
			float(race["time"]) - float(race["raceStartT"]) >= float(tune["MAX_RACE_SEC"])
		)
		if float(player["progress"]) >= int(tune["LAPS"]) * lap_len or timed_out:
			var rank := player_rank(race)
			if (
				bool(tune["ENDLESS"])
				and not timed_out
				and rank <= int(tune["ENDLESS_CHAIN_MAX_RANK"])
			):
				reset_race_for_chain(race, rank)
			else:
				race["ended"] = true
				race["finishRank"] = rank
				race["events"].append({"type": "finish", "rank": rank})


## §C10.1-Bot: folgt dem Mittelspline, driftet Kurven > 45°, nutzt Items sofort.
static func bot_input(race: Dictionary) -> Dictionary:
	var player: Dictionary = race["karts"][0]
	var base := ai_input(race, player)
	var wobble := sin(float(race["time"]) * 1.7) * 0.03
	return {
		"steer": float(base["steer"]) + wobble,
		"drifting": bool(base["drifting"]),
		"useItem": not str(player["item"]).is_empty(),
	}


## Endpunktzahl eines (laufenden oder beendeten) Rennens.
static func run_score(race: Dictionary) -> int:
	var tune: Dictionary = race["tune"]
	var rank := int(race["finishRank"]) if bool(race["ended"]) else player_rank(race)
	var cur := race_score(
		rank, int(race["overtakes"]), float(race["karts"][0]["driftMeters"]), tune
	)
	return int(round(float(int(race["chainScore"]) + cur) * float(tune["SCORE_MULT"])))


## §B3-Meta (races/wins/overtakes).
static func run_meta(race: Dictionary) -> Dictionary:
	var rank := int(race["finishRank"]) if bool(race["ended"]) else player_rank(race)
	return {
		"races": 1 + int(race["chainRaces"]),
		"wins": int(race["chainWins"]) + (1 if rank == 1 else 0),
		"overtakes": int(race["overtakes"]),
	}


## §G5.4-Zertifikatslauf: ein volles Bot-Rennen (oder eine Endlos-Kette)
## bei festen 30 Hz, mit gesäten menschlichen Aussetzern je Modus.
static func simulate_autoplay(mode := "normal", seed_value := 1, max_sec := 3600.0) -> Dictionary:
	var tune := apply_difficulty(RACER, mode)
	var race := create_race(seed_value, tune)
	var lapse := GoobyRng.new((seed_value ^ 0xC0FFEE11) & 0xFFFFFFFF)
	var lapse_t := 0.0
	var lapse_every := float(tune["BOT_LAPSE_EVERY_SEC"])
	var next_lapse := lapse_every * (0.5 + lapse.next()) if lapse_every > 0.0 else INF
	var dt := 1.0 / 30.0
	var release_t := 0.0
	while not bool(race["ended"]) and float(race["time"]) < max_sec:
		var base := bot_input(race)
		var player: Dictionary = race["karts"][0]
		release_t = maxf(0.0, release_t - dt)
		if float(player["driftCharge"]) >= 0.95 and release_t <= 0.0:
			release_t = 2.0 * dt
		var input := {
			"steer": float(base["steer"]),
			"drifting": release_t <= 0.0,
			"useItem": bool(base["useItem"]),
		}
		if lapse_every > 0.0:
			next_lapse -= dt
			if next_lapse <= 0.0 and lapse_t <= 0.0:
				lapse_t = float(tune["BOT_LAPSE_SEC"]) * (0.6 + lapse.next() * 0.8)
				next_lapse = lapse_every * (0.5 + lapse.next())
			if lapse_t > 0.0:
				lapse_t -= dt
				input = {"steer": input["steer"], "drifting": false, "useItem": false}
		step_race(race, dt, input)
	if not bool(race["ended"]):
		race["ended"] = true
		race["finishRank"] = player_rank(race)
	var meta := run_meta(race)
	return {
		"score": run_score(race),
		"rank": int(race["finishRank"]),
		"races": int(meta["races"]),
		"wins": int(meta["wins"]),
		"overtakes": int(race["overtakes"]),
		"driftMeters": float(race["karts"][0]["driftMeters"]),
		"time": float(race["time"]),
	}
