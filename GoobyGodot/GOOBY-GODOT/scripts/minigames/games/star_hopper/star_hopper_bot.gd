class_name StarHopperBot
extends RefCounted
## Spawn-Tabellen + Bot-Entscheidungen für den Sternenhüpfer — zahlengleicher
## Port der zweiten Hälfte von GOOBY/src/minigames/games/starHopper.logic.js.
## Jede erzeugte Meteorreihe ist garantiert überlebbar (§C1.5), der Bot wählt
## alle 0.4 s die wertvollste sichere Bahn und meidet unsaubere Zwei-Bahn-Wische.
## Physik/Wertung liegen in `star_hopper_logic.gd` (gdlint: max. 20 Methoden).

const Logic := preload("res://scripts/minigames/games/star_hopper/star_hopper_logic.gd")


## Bahnen, die das Schiff über `gap_m` Meter bei `speed` wechseln kann (0..2).
static func max_lane_shift(gap_m: float, speed: float, tune := Logic.HOPPER) -> int:
	var time := gap_m / maxf(0.001, speed)
	var per_change := float(tune["LANE_CHANGE_SEC"]) + 0.22
	return clampi(int(floor(time / per_change)), 0, int(tune["LANES"]) - 1)


## Erreichbarkeits-DP über aufeinanderfolgende Reihen: existiert EIN Pfad?
static func is_chain_survivable(rows: Array, speed: float, tune := Logic.HOPPER) -> bool:
	var lanes := int(tune["LANES"])
	var reachable: Array[bool] = []
	for i in lanes:
		reachable.append(true)
	for row: Dictionary in rows:
		var shift := max_lane_shift(float(row["gap"]), speed, tune)
		var next: Array[bool] = []
		for i in lanes:
			next.append(false)
		for to in lanes:
			if bool(row["blocked"][to]):
				continue
			for from in lanes:
				if reachable[from] and absi(to - from) <= shift:
					next[to] = true
					break
		reachable = next
		if not reachable.has(true):
			return false
	return true


## Nächste Meteorreihe erzeugen — garantiert überlebbar zu den letzten Reihen.
static func generate_row(
	rng: Callable, elapsed: float, recent_rows: Array, tune := Logic.HOPPER
) -> Dictionary:
	var lanes := int(tune["LANES"])
	var d := Logic.difficulty_at(elapsed, tune)
	var speed := Logic.speed_at(elapsed, tune)
	var gap := Logic.row_gap_at(d, tune) * (0.9 + float(rng.call()) * 0.25)
	var window := recent_rows.slice(maxi(0, recent_rows.size() - 4))

	for attempt in 12:
		var blocked: Array[bool] = []
		for i in lanes:
			blocked.append(false)
		var block_count := (
			2 if float(rng.call()) < Logic.ramp(tune["DOUBLE_BLOCK_CHANCE"], d) else 1
		)
		var lane_order := shuffled_lane_order(rng)
		for b in block_count:
			blocked[lane_order[b]] = true
		var row := {"blocked": blocked, "gap": gap}
		if is_chain_survivable(window + [row], speed, tune):
			return row
	# Rückfallreihe: ein einzelner Meteor außen — trivial überlebbar.
	var fallback: Array[bool] = []
	for i in lanes:
		fallback.append(i == 0)
	return {"blocked": fallback, "gap": gap}


## Web: `[0,1,2].sort(() => rng() - 0.5)`. V8 sortiert drei Elemente mit
## TimSort (Lauf-Erkennung + binäre Einfügung) und zieht dabei 2–4 rng-Werte —
## diese Zugzahl gehört zum Stream und ist hier 1:1 nachgebaut.
static func shuffled_lane_order(rng: Callable) -> Array[int]:
	var c1 := float(rng.call()) - 0.5
	var c2 := float(rng.call()) - 0.5
	if c1 < 0.0 and c2 < 0.0:
		return [2, 1, 0]
	if c1 >= 0.0 and c2 >= 0.0:
		return [0, 1, 2]
	# Lauf der Länge 2, dann binäre Einfügung des dritten Elements.
	var head: Array[int] = [0, 1]
	if c1 < 0.0:
		head = [1, 0]
	var c3 := float(rng.call()) - 0.5
	if c3 >= 0.0:
		return [head[0], head[1], 2]
	var c4 := float(rng.call()) - 0.5
	if c4 < 0.0:
		return [2, head[0], head[1]]
	return [head[0], 2, head[1]]


## Gierige Bahnwahl: höchster Wert unter den sicheren Bahnen; Gleichstand
## bevorzugt die aktuelle Bahn, dann den kürzeren Wechsel.
static func choose_lane(current: int, lanes: Array, tune := Logic.HOPPER) -> int:
	var best := -1
	for i in int(tune["LANES"]):
		var row: Dictionary = lanes[i] if i < lanes.size() else {}
		if not bool(row.get("safe", false)):
			continue
		if best == -1:
			best = i
			continue
		var dv := float(row["value"]) - float((lanes[best] as Dictionary)["value"])
		if dv > 0.0:
			best = i
		elif dv == 0.0:
			var keeps_current := i == current and best != current
			var closer := absi(i - current) < absi(best - current)
			if keeps_current or (best != current and closer):
				best = i
	return current if best == -1 else best


## Zeitbasierter Bahnausblick für den Bot (sicher / durchquerbar / Kontaktzeit).
static func lane_outlook(
	threats: Array, traveled: float, horizon_sec: float, transit_sec: float, tune := Logic.HOPPER
) -> Dictionary:
	var lanes := int(tune["LANES"])
	var reach := (
		float(tune["HITBOX_SCALE"]) * (float(tune["PLAYER_HALF_M"]) + float(tune["METEOR_HALF_M"]))
	)
	var safe: Array[bool] = []
	var transit: Array[bool] = []
	var enter: Array[float] = []
	for i in lanes:
		safe.append(true)
		transit.append(true)
		enter.append(INF)
	for th: Dictionary in threats:
		var dist := float(th["m"]) - traveled
		var t_enter := (dist - reach) / float(th["approach"])
		var t_exit := (dist + reach) / float(th["approach"])
		if t_exit < 0.0:
			continue
		var lane := int(th["lane"])
		if t_enter <= horizon_sec:
			safe[lane] = false
		if t_enter <= transit_sec:
			transit[lane] = false
		enter[lane] = minf(enter[lane], maxf(0.0, t_enter))
	return {"safe": safe, "transit": transit, "enter": enter}


## Bot-Zug: choose_lane, aber ein Zwei-Bahn-Wisch nur bei sauberer Mittelbahn.
static func plan_move(current: int, lanes: Array, tune := Logic.HOPPER) -> int:
	var target := choose_lane(current, lanes, tune)
	if absi(target - current) < 2:
		return target
	var mid := (target + current) / 2
	var mid_row: Dictionary = lanes[mid]
	if bool(mid_row.get("transitSafe", false)):
		return target
	if bool((lanes[current] as Dictionary).get("safe", false)):
		return current
	var mid_enter := float(mid_row.get("enter", 0.0))
	var cur_enter := float((lanes[current] as Dictionary).get("enter", 0.0))
	return mid if mid_enter > cur_enter else current
