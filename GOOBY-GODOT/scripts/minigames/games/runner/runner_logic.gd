class_name RunnerLogic
extends RefCounted
## Pure Gooby-Runner-Logik — zahlengleicher Port von
## GOOBY/src/minigames/games/runner.logic.js (§C6.1 #6).
## 3 Spuren, endloser Lauf: Wischen links/rechts = Spur, hoch = Sprung,
## runter = Rutschen. Hindernisse (Hütchen/Kiste/Schranke = springen,
## Überkopf-Gerüst = rutschen, Auto = nur ausweichen) werden IMMER
## überlebbar erzeugt (DP-Validator). Münzen +1 × Kombo-Bonus, Tempo +5 %
## alle 10 s. Erster Treffer = Stolpern, zweiter = Aus.
## Coin-Zeile /15, 4..30, Ziel 380.

## §C6.1 #6 Rampenzahlen + Umsetzungs-Feel-Regler.
const RUNNER := {
	"LANES": 3,
	## Welt-x der Spurmitten (m).
	"LANE_X": [-1.1, 0.0, 1.1],
	"BASE_SPEED": 6.0,
	"SPEED_RAMP_PCT": 0.05,
	"SPEED_RAMP_EVERY_SEC": 10.0,
	"MAX_SPEED": 13.0,
	"LANE_CHANGE_SEC": 0.16,
	"JUMP_SEC": 0.62,
	"JUMP_HEIGHT": 1.0,
	"SLIDE_SEC": 0.65,
	"SLIDE_HEIGHT": 0.5,
	"STAND_HEIGHT": 1.05,
	"PLAYER_HALF_DEPTH": 0.28,
	## Hindernis-Arten → wie sie in DERSELBEN Spur passierbar sind.
	"OBSTACLES":
	{
		"cone": {"pass": "jump", "clearY": 0.45, "halfDepth": 0.22},
		"box": {"pass": "jump", "clearY": 0.55, "halfDepth": 0.3},
		"barrier": {"pass": "jump", "clearY": 0.6, "halfDepth": 0.22},
		"overhead": {"pass": "slide", "gapY": 0.72, "halfDepth": 0.24},
		"car": {"pass": "none", "halfDepth": 0.95},
	},
	"ROW_GAP_M": {"start": 13.0, "end": 8.5},
	"DIFFICULTY_FULL_SEC": 90.0,
	"DOUBLE_BLOCK_CHANCE": {"start": 0.25, "end": 0.62},
	## Reihenfolge IST relevant (gewichtete Auswahl läuft sie linear ab).
	"KIND_WEIGHTS": {"cone": 3.0, "box": 2.0, "barrier": 2.0, "overhead": 2.2, "car": 1.6},
	"COIN_SCORE_BONUS": 2,
	"COMBO_STEPS": [0, 10, 22],
	"COMBO_MAX_MULT": 3,
	"COIN_LINE": 3,
	"COIN_LINE_CHANCE": 0.75,
	"STUMBLE_INVULN_SEC": 1.6,
	"MAX_HITS": 2,
	## V3 §C10.2 Überraschungskisten.
	"MYSTERY_POWERS":
	{
		"magnet": {"sec": 4.0, "radius": 3.0},
		"x2": {"sec": 6.0},
		"shield": {},
	},
	"MYSTERY_FIRST_M": 45.0,
	"MYSTERY_GAP_M": 70.0,
	## F4 P2-4 Anti-Tunneling: größter Hindernis-Vorschub je Kollisionsprobe.
	"MAX_SWEEP_STEP_M": 0.35,
	"DENSITY_MULT": 1.0,
	"SPEED_MULT": 1.0,
	"SCORE_MULT": 1.0,
	"COIN_RATE": 1.0,
	"RENDER_SCALE_MULT": 1.0,
	"ENDLESS": false,
	"BOT_MISS_CHANCE": 0.025,
}

const RUNNER_DIFFICULTY := {
	"easy": {"speed": 0.85, "density": 0.85, "extraHits": 1, "endless": false},
	"normal": {"speed": 1.0, "density": 1.0, "extraHits": 0, "endless": false},
	"hard": {"speed": 1.2, "density": 1.15, "extraHits": 0, "endless": false},
	"endless": {"speed": 1.2, "density": 1.15, "extraHits": 1, "endless": true},
}

## GP3-Juice — reine Feier-Regler, nie Spiel-Mathe.
const RUNNER_JUICE := {"MILESTONE_EVERY_M": 100.0, "LANDING_PUFF_COUNT": 5}


## Abgeleitetes Tune; `normal` liefert exakt die Basis-Tabelle.
static func apply_difficulty(tune := RUNNER, mode := "normal") -> Dictionary:
	var id := mode if RUNNER_DIFFICULTY.has(mode) else "normal"
	if id == "normal":
		return tune
	var row: Dictionary = RUNNER_DIFFICULTY[id]
	var speed := float(row["speed"])
	var density := float(row["density"])
	var base_max := float(tune["MAX_SPEED"])
	var gap: Dictionary = tune["ROW_GAP_M"]
	var out := tune.duplicate()
	out["BASE_SPEED"] = float(tune["BASE_SPEED"]) * speed
	out["MAX_SPEED"] = base_max * 1.4 if bool(row["endless"]) else base_max * speed
	out["ROW_GAP_M"] = {"start": float(gap["start"]) / density, "end": float(gap["end"]) / density}
	out["MAX_HITS"] = int(tune["MAX_HITS"]) + int(row["extraHits"])
	out["DENSITY_MULT"] = density
	out["SPEED_MULT"] = speed
	out["ENDLESS"] = bool(row["endless"])
	out["BOT_MISS_CHANCE"] = _bot_miss_for(id, tune)
	out["MODE"] = id
	return out


static func _bot_miss_for(id: String, tune: Dictionary) -> float:
	if id == "easy":
		return 0.008
	if id == "hard" or id == "endless":
		return 0.035
	return float(tune["BOT_MISS_CHANCE"])


## §C-SYS4.3 Münzregen-/Turbo-/Riesen-Gooby-Haken (Modifikatoren).
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
		return out
	if kind == "riesenGooby":
		out["PLAYER_HALF_DEPTH"] = (
			float(tune["PLAYER_HALF_DEPTH"]) * maxf(0.1, _num(modifier.get("hitboxMult"), 1.0))
		)
		out["RENDER_SCALE_MULT"] = maxf(0.1, _num(modifier.get("scale"), 1.0))
		return out
	return tune


## Vorwärtstempo: +5 % (zinseszins) alle 10 s, gedeckelt bei MAX_SPEED.
static func speed_at(elapsed: float, tune := RUNNER) -> float:
	var steps := floorf(maxf(0.0, elapsed) / float(tune["SPEED_RAMP_EVERY_SEC"]))
	return minf(
		float(tune["MAX_SPEED"]),
		float(tune["BASE_SPEED"]) * pow(1.0 + float(tune["SPEED_RAMP_PCT"]), steps)
	)


## Schwierigkeitsrampe 0..1 (Zeilenabstand + Doppelblock-Chance hängen dran).
static func difficulty_at(elapsed: float, tune := RUNNER) -> float:
	return minf(1.0, maxf(0.0, elapsed / float(tune["DIFFICULTY_FULL_SEC"])))


static func _ramp(knob: Dictionary, d: float) -> float:
	var start := float(knob["start"])
	return start + (float(knob["end"]) - start) * d


## Abstand (m) bis zur nächsten Hindernis-Zeile.
static func row_gap_at(difficulty: float, tune := RUNNER) -> float:
	return _ramp(tune["ROW_GAP_M"], difficulty)


## Münzen einer Linie; gebrochene COIN_RATE via EINEM Bernoulli-Zug.
static func coin_line_count(rng: GoobyRng, tune := RUNNER) -> int:
	var expected := maxf(0.0, float(tune["COIN_LINE"]) * float(tune["COIN_RATE"]))
	var whole := int(floor(expected))
	var fraction := expected - whole
	return whole + (1 if (fraction > 0.0 and rng.next() < fraction) else 0)


## Kombo-Multiplikator ×1..×3 aus der ununterbrochenen Münzserie.
static func combo_multiplier(coin_streak: int, tune := RUNNER) -> int:
	var mult := 0
	for step in tune["COMBO_STEPS"]:
		if coin_streak >= int(step):
			mult += 1
	return mini(int(tune["COMBO_MAX_MULT"]), maxi(1, mult))


## §C6.1 #6 Punkte = floor(Meter) + Münzpunkte.
static func runner_score(meters: float, coin_points: float) -> int:
	return maxi(0, int(floor(meters)) + MinigameFrameworkLogic.js_round(coin_points))


static func final_runner_score(meters: float, coin_points: float, tune := RUNNER) -> int:
	return maxi(
		0,
		MinigameFrameworkLogic.js_round(
			float(runner_score(meters, coin_points)) * float(tune["SCORE_MULT"])
		)
	)


## Passiert die Aktion das Hindernis in DERSELBEN Spur?
static func action_passes(kind: String, action: String, tune := RUNNER) -> bool:
	var obstacles: Dictionary = tune["OBSTACLES"]
	if not obstacles.has(kind):
		return true
	var def: Dictionary = obstacles[kind]
	if str(def["pass"]) == "jump":
		return action == "jump"
	if str(def["pass"]) == "slide":
		return action == "slide"
	return false


## Kollisionstest eines Frames. player: {lane, y, sliding}; obstacle: {lane, kind, z}.
static func hits_obstacle(player: Dictionary, obstacle: Dictionary, tune := RUNNER) -> bool:
	if int(player["lane"]) != int(obstacle["lane"]):
		return false
	var def: Dictionary = tune["OBSTACLES"][str(obstacle["kind"])]
	var reach := float(def["halfDepth"]) + float(tune["PLAYER_HALF_DEPTH"])
	if absf(float(obstacle["z"])) > reach:
		return false
	if str(def["pass"]) == "jump":
		return float(player["y"]) < float(def["clearY"])
	if str(def["pass"]) == "slide":
		var under := (
			bool(player["sliding"])
			and float(player["y"]) + float(tune["SLIDE_HEIGHT"]) <= float(def["gapY"])
		)
		return not under
	return true


## F4 P2-4 Anti-Tunneling: den Frame-Vorschub in ≤ MAX_SWEEP_STEP_M abtasten.
static func sweep_hits_obstacle(
	player: Dictionary, obstacle: Dictionary, dz: float, tune := RUNNER
) -> bool:
	var steps := maxi(1, int(ceil(absf(dz) / float(tune["MAX_SWEEP_STEP_M"]))))
	for i in range(1, steps + 1):
		var probe := obstacle.duplicate()
		probe["z"] = float(obstacle["z"]) + dz * i / steps
		if hits_obstacle(player, probe, tune):
			return true
	return false


## Gesäter Überraschungskisten-Wurf: Magnet / ×2 / Stolper-Schild.
static func roll_mystery_power(rng: GoobyRng) -> String:
	var kinds := ["magnet", "x2", "shield"]
	return kinds[mini(kinds.size() - 1, int(floor(rng.next() * kinds.size())))]


## Ein Powerup aktivieren, ohne die anderen zu stören.
static func activate_mystery_power(state: Dictionary, kind: String, tune := RUNNER) -> Dictionary:
	var out := state.duplicate()
	var powers: Dictionary = tune["MYSTERY_POWERS"]
	if kind == "magnet":
		out["magnetT"] = float((powers["magnet"] as Dictionary)["sec"])
	elif kind == "x2":
		out["x2T"] = float((powers["x2"] as Dictionary)["sec"])
	else:
		out["shield"] = true
	return out


## ×2 verdoppelt den kombo-skalierten Wert jeder eingesammelten Münze.
static func mystery_coin_points(combo_mult: int, x2_active: bool, tune := RUNNER) -> int:
	return int(tune["COIN_SCORE_BONUS"]) * combo_mult * (2 if x2_active else 1)


## Magnet-Reichweite (3 m, wie shoppingSurf).
static func magnet_collects(coin: Vector3, player: Vector3, active: bool, tune := RUNNER) -> bool:
	if not active:
		return false
	var powers: Dictionary = tune["MYSTERY_POWERS"]
	var radius := float((powers["magnet"] as Dictionary)["radius"])
	var dx := coin.x - player.x
	var dy := coin.y - player.y
	var dz := coin.z - player.z
	return sqrt(dx * dx + dy * dy + dz * dz) <= radius


## Treffer atomar auflösen. state: {hits, shield, invulnT}.
static func resolve_runner_hit(state: Dictionary, tune := RUNNER) -> Dictionary:
	if float(state["invulnT"]) > 0.0:
		var ignored := state.duplicate()
		ignored["outcome"] = "ignored"
		return ignored
	if bool(state["shield"]):
		return {
			"hits": int(state["hits"]),
			"shield": false,
			"invulnT": float(tune["STUMBLE_INVULN_SEC"]),
			"outcome": "shielded",
		}
	var hits := int(state["hits"]) + 1
	return {
		"hits": hits,
		"shield": false,
		"invulnT": float(tune["STUMBLE_INVULN_SEC"]),
		"outcome": "wipeout" if hits >= int(tune["MAX_HITS"]) else "stumble",
	}


## Wie viele Spuren schafft man auf `gap_m` Metern bei `speed`?
static func max_lane_shift(gap_m: float, speed: float, tune := RUNNER) -> int:
	var time := gap_m / maxf(0.001, speed)
	var per_change := float(tune["LANE_CHANGE_SEC"]) + 0.22
	return maxi(0, mini(2, int(floor(time / per_change))))


## Welche Spuren einer Zeile sind überhaupt passierbar?
static func passable_lanes(row: Dictionary, tune := RUNNER) -> Array:
	var out: Array[bool] = []
	for kind in row["lanes"]:
		if kind == null:
			out.append(true)
		else:
			var k := str(kind)
			out.append(action_passes(k, "jump", tune) or action_passes(k, "slide", tune))
	return out


## §C6.1 #6 Überlebbarkeits-Validator: DP-Erreichbarkeit über die Zeilen.
static func is_pattern_survivable(rows: Array, speed: float, tune := RUNNER) -> bool:
	var lanes := int(tune["LANES"])
	var reachable: Array[bool] = []
	for _i in lanes:
		reachable.append(true)
	for row in rows:
		var shift := max_lane_shift(float(row["gap"]), speed, tune)
		var pass_flags := passable_lanes(row, tune)
		var next: Array[bool] = []
		for _i in lanes:
			next.append(false)
		for to in lanes:
			if not bool(pass_flags[to]):
				continue
			for from in lanes:
				if reachable[from] and absi(to - from) <= shift:
					next[to] = true
					break
		reachable = next
		if not reachable.has(true):
			return false
	return true


## Gewichtete Hindernis-Auswahl (Einfügereihenfolge von KIND_WEIGHTS).
static func _pick_kind(rng: GoobyRng, tune: Dictionary) -> String:
	var weights: Dictionary = tune["KIND_WEIGHTS"]
	var total := 0.0
	for w in weights.values():
		total += float(w)
	var roll := rng.next() * total
	var last := ""
	for kind in weights:
		last = str(kind)
		roll -= float(weights[kind])
		if roll <= 0.0:
			return last
	return last


## `[0, 1, 2].sort(() => rng() - 0.5)` — V8-treue Nachbildung.
##
## ABWEICHUNG-FREI, ABER NICHT OFFENSICHTLICH: das Web verlässt sich auf V8s
## TimSort (Lauf-Erkennung + binäre Einfügesortierung), die für n = 3 je nach
## Vergleichsergebnis 2–4 rng-Züge verbraucht. Ein naives Sortieren würde
## andere Permutationen UND einen anderen rng-Verbrauch liefern, wodurch alle
## folgenden Würfe auseinanderlaufen. Der Entscheidungsbaum unten ist genau
## V8s Ablauf und mit Node gegengeprüft (tests/unit/test_mg3_runner.gd).
static func shuffle_lane_order(rng: GoobyRng) -> Array:
	# 1. Vergleich: countRunAndMakeAscending vergleicht a[1] mit a[0].
	if rng.next() - 0.5 < 0.0:
		# Absteigender Lauf: a[2] gegen a[1].
		if rng.next() - 0.5 < 0.0:
			return [2, 1, 0]
		# Lauf der Länge 2 umgedreht → [1, 0, 2]; jetzt 2 binär einsortieren.
		if rng.next() - 0.5 >= 0.0:
			return [1, 0, 2]
		return [2, 1, 0] if rng.next() - 0.5 < 0.0 else [1, 2, 0]
	# Aufsteigender Lauf: a[2] gegen a[1].
	if rng.next() - 0.5 >= 0.0:
		return [0, 1, 2]
	if rng.next() - 0.5 >= 0.0:
		return [0, 1, 2]
	return [2, 0, 1] if rng.next() - 0.5 < 0.0 else [0, 2, 1]


## Nächste Hindernis-Zeile, garantiert überlebbar (12 Versuche, dann Rückfall).
static func generate_row(
	rng: GoobyRng, elapsed: float, recent_rows: Array, tune := RUNNER
) -> Dictionary:
	var lanes_n := int(tune["LANES"])
	var d := difficulty_at(elapsed, tune)
	var speed := speed_at(elapsed, tune)
	var gap := row_gap_at(d, tune) * (0.9 + rng.next() * 0.25)
	var window := recent_rows.slice(maxi(0, recent_rows.size() - 4))

	for _attempt in 12:
		var lanes: Array = []
		for _i in lanes_n:
			lanes.append(null)
		var block_count := 2 if rng.next() < _ramp(tune["DOUBLE_BLOCK_CHANCE"], d) else 1
		var lane_order := shuffle_lane_order(rng)
		for b in block_count:
			lanes[int(lane_order[b])] = _pick_kind(rng, tune)
		var row := {"lanes": lanes, "gap": gap}
		var probe := window.duplicate()
		probe.append(row)
		if is_pattern_survivable(probe, speed, tune):
			return row
	# Rückfall: ein Hütchen außen — trivial überlebbar.
	var fallback: Array = []
	for _i in lanes_n:
		fallback.append(null)
	fallback[0] = "cone"
	return {"lanes": fallback, "gap": gap}


## Von diesem Frame überschrittener Meter-Meilenstein (0 = keiner).
static func crossed_runner_milestone(prev_meters: float, meters: float, every_m := -1.0) -> int:
	var step := every_m if every_m > 0.0 else float(RUNNER_JUICE["MILESTONE_EVERY_M"])
	var prev := floorf(maxf(0.0, prev_meters) / step)
	var now := floorf(maxf(0.0, meters) / step)
	return int(now * step) if now > prev else 0


## Deterministische Bot-Zertifizierung des moduskundigen Live-Piloten.
static func simulate_autoplay(mode := "normal", seed_value := 1, max_sec := 180.0) -> Dictionary:
	var tune := apply_difficulty(RUNNER, mode)
	var rng := GoobyRng.new(seed_value)
	var elapsed := 0.0
	var meters := 0.0
	var hits := 0
	var coin_points := 0.0
	var streak := 0
	while elapsed < max_sec and hits < int(tune["MAX_HITS"]):
		var d := difficulty_at(elapsed, tune)
		var gap := row_gap_at(d, tune) * (0.9 + rng.next() * 0.25)
		var speed := speed_at(elapsed, tune)
		elapsed += gap / speed
		meters += gap
		if rng.next() < float(tune["BOT_MISS_CHANCE"]):
			hits += 1
			streak = 0
		elif rng.next() < float(tune["COIN_LINE_CHANCE"]):
			var coins := coin_line_count(rng, tune)
			for _i in coins:
				streak += 1
				coin_points += mystery_coin_points(combo_multiplier(streak, tune), false, tune)
	return {
		"score": final_runner_score(meters, coin_points, tune),
		"elapsed": elapsed,
		"meters": meters,
		"hits": hits,
	}


static func _num(value: Variant, fallback: float) -> float:
	match typeof(value):
		TYPE_INT, TYPE_FLOAT:
			return float(value)
		_:
			return fallback
