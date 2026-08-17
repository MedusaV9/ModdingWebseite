class_name GoobySaysLogic
extends RefCounted
## Gooby sagt (goobySays) — PURE Logik, zahlengleicher Port von
## GOOBY/src/minigames/games/goobySays.logic.js (PLAN2 §C1.2 #1). Sequenz
## startet bei 3 und wächst je Runde um 1; die Wiedergabe zieht 5 % pro Runde
## an (Boden 320 ms), ein Fehler beendet die Runde. Ab Runde 6 hängt ein
## Zwei-Pad-Akkord an. Score = 10·Runden + Speed-Bonus (0–8).
## Coin-Zeile: /5, 4..24, Ziel 70.

## Bindende §C1.2-#1-Zahlen + V2/G24-Tuning.
const SAYS := {
	"PADS": 4,
	"START_LEN": 3,
	"GROW_PER_ROUND": 1,
	"ROUND_POINTS": 10,
	"STEP_DECAY_PCT": 0.05,
	"STEP_FLOOR_MS": 320.0,
	"STEP_BASE_MS": 600.0,
	"SPEED_BONUS_MAX": 8,
	"REACTION_FULL_MS": 500.0,
	"REACTION_ZERO_MS": 1500.0,
	"INPUT_TIMEOUT_MS": 5000.0,
	"AUTOPLAY_TAP_MS": 250.0,
	"AUTOPLAY_ERR_RAMP": 0.0025,
	"AUTOPLAY_ERR_CAP": 0.08,
	"CHORD_FROM_ROUND": 6,
	"CHORD_WINDOW_MS": 250.0,
}

## V4/G73 §G5 Sequenz-Multiplikatoren (die Basistabelle bleibt „Mittel“).
const SAYS_DIFFICULTY := {
	"easy": {"replaySpeed": 0.85, "windowMult": 1.25, "floorSteps": 0, "botErrorMult": 0.75},
	"hard": {"replaySpeed": 1.15, "windowMult": 0.8, "floorSteps": 1, "botErrorMult": 1.15},
	"endless": {"replaySpeed": 1.15, "windowMult": 0.8, "floorSteps": 1, "botErrorMult": 1.15},
}

## V6/C4: rein kosmetische Feel-Knöpfe (die Scoring-Tabelle bleibt frei davon).
const SAYS_JUICE := {
	"PRESS_DIP_Y": 0.08,
	"PRESS_DIP_SEC": 0.2,
	"CONDUCT_BOUNCE_THROTTLE_SEC": 0.55,
	"FAIL_SHAKE_SEC": 0.2,
	"FAIL_SHAKE_AMP": 0.06,
	"GIGGLE_EVERY_ROUNDS": 5,
}


## Abgeleitetes Tune. „Mittel“ liefert die Basistabelle; Endlos nutzt die
## Schwer-Werte, lässt die Kadenz aber unter den 320-ms-Boden rutschen.
static func apply_difficulty(tune: Dictionary = SAYS, mode := "normal") -> Dictionary:
	if mode == "normal" or not SAYS_DIFFICULTY.has(mode):
		return tune
	var row: Dictionary = SAYS_DIFFICULTY[mode]
	var hard_floor := (
		float(tune["STEP_FLOOR_MS"])
		* pow(1.0 - float(tune["STEP_DECAY_PCT"]), float(row["floorSteps"]))
	)
	var out := tune.duplicate()
	out["STEP_BASE_MS"] = float(tune["STEP_BASE_MS"]) / float(row["replaySpeed"])
	if mode == "endless":
		out["STEP_FLOOR_MS"] = 0.0
	elif mode == "easy":
		out["STEP_FLOOR_MS"] = hard_floor / float(row["replaySpeed"])
	else:
		out["STEP_FLOOR_MS"] = hard_floor
	out["INPUT_TIMEOUT_MS"] = maxf(
		350.0, float(tune["INPUT_TIMEOUT_MS"]) * float(row["windowMult"])
	)
	# Das geerbte 250-ms-Akkordfenster liegt unter dem v4-Schwer-Guardrail —
	# hard/endless klemmen auf 350 ms statt unspielbar zu werden.
	if mode == "hard" or mode == "endless":
		out["CHORD_WINDOW_MS"] = maxf(
			350.0, float(tune["CHORD_WINDOW_MS"]) * float(row["windowMult"])
		)
	else:
		out["CHORD_WINDOW_MS"] = float(tune["CHORD_WINDOW_MS"]) * float(row["windowMult"])
	out["REACTION_FULL_MS"] = float(tune["REACTION_FULL_MS"]) * float(row["windowMult"])
	out["REACTION_ZERO_MS"] = float(tune["REACTION_ZERO_MS"]) * float(row["windowMult"])
	out["AUTOPLAY_ERR_MULT"] = float(row["botErrorMult"])
	return out


## Sequenzlänge einer (1-basierten) Runde: 3, 4, 5, …
static func seq_length_at(round_no: int) -> int:
	return int(SAYS["START_LEN"]) + int(SAYS["GROW_PER_ROUND"]) * (maxi(1, round_no) - 1)


## Schrittdauer der Wiedergabe: −5 % pro Runde, auf STEP_FLOOR_MS gebremst.
static func step_ms_at(round_no: int, tune: Dictionary = SAYS) -> float:
	var mult := pow(1.0 - float(tune["STEP_DECAY_PCT"]), float(maxi(1, round_no) - 1))
	return maxf(float(tune["STEP_FLOOR_MS"]), float(tune["STEP_BASE_MS"]) * mult)


## Einen geseedeten Schritt anhängen (ab Runde 6 einen Zwei-Pad-Akkord).
static func extend_sequence(seq: Array, rng: GoobyRng, round_no := 1) -> Array:
	var pads := int(SAYS["PADS"])
	var first := mini(pads - 1, int(floor(rng.next() * float(pads))))
	var out := seq.duplicate()
	if round_no < int(SAYS["CHORD_FROM_ROUND"]):
		out.append(first)
		return out
	# Das zweite Pad kommt aus den übrigen PADS−1 Werten — nie dasselbe zweimal.
	var rolled := mini(pads - 2, int(floor(rng.next() * float(pads - 1))))
	var second := rolled + 1 if rolled >= first else rolled
	out.append([first, second])
	return out


## Ist dieser Sequenzschritt ein V3/G45-Akkord?
static func is_chord_step(step: Variant) -> bool:
	return step is Array and (step as Array).size() == 2 and step[0] != step[1]


## Akkord-Taps bewerten: beide Pads, beliebige Reihenfolge, im Zeitfenster.
static func chord_tap_result(
	step: Variant, first_pad: int, second_pad := -1, gap_ms := 0.0, tune: Dictionary = SAYS
) -> String:
	if not is_chord_step(step) or not (step as Array).has(first_pad):
		return "wrong"
	if second_pad < 0:
		return "waiting"
	if second_pad == first_pad or not (step as Array).has(second_pad):
		return "wrong"
	return "complete" if gap_ms <= float(tune["CHORD_WINDOW_MS"]) else "late"


## Ausrutscher-Wahrscheinlichkeit des Bots je Runde (0 in Runde 1, gedeckelt).
static func autoplay_err_at(round_no: int, tune: Dictionary = SAYS) -> float:
	var mult := float(tune.get("AUTOPLAY_ERR_MULT", 1.0))
	return minf(
		float(tune["AUTOPLAY_ERR_CAP"]),
		float(tune["AUTOPLAY_ERR_RAMP"]) * float(maxi(1, round_no) - 1) * mult
	)


## Speed-Bonus 0–8 aus der Durchschnittsreaktion je Schritt.
static func speed_bonus(avg_reaction_ms: float, tune: Dictionary = SAYS) -> int:
	if not is_finite(avg_reaction_ms):
		return 0
	if avg_reaction_ms <= float(tune["REACTION_FULL_MS"]):
		return int(tune["SPEED_BONUS_MAX"])
	if avg_reaction_ms >= float(tune["REACTION_ZERO_MS"]):
		return 0
	var span := float(tune["REACTION_ZERO_MS"]) - float(tune["REACTION_FULL_MS"])
	var t := (avg_reaction_ms - float(tune["REACTION_FULL_MS"])) / span
	return int(round(float(tune["SPEED_BONUS_MAX"]) * (1.0 - t)))


## Rundenscore: 10·abgeschlossene Runden + Speed-Bonus.
static func round_score(
	rounds_completed: int, avg_reaction_ms: float, tune: Dictionary = SAYS
) -> int:
	if rounds_completed <= 0:
		return 0
	return int(tune["ROUND_POINTS"]) * rounds_completed + speed_bonus(avg_reaction_ms, tune)


## Gooby sagt läuft ohnehin bis zum Fehler — Endlos behält genau das.
static func endless_should_end(mode: String, mistakes: int) -> bool:
	return mode == "endless" and mistakes >= 1


## V6/C4: Jedes 5. Runden-Banner bekommt ein Kichern dazu.
static func giggle_round(round_no: int) -> bool:
	return round_no > 0 and round_no % int(SAYS_JUICE["GIGGLE_EVERY_ROUNDS"]) == 0


## Deterministische, headless-taugliche Fassung der Live-Bot-Entscheidungen.
static func simulate_autoplay(seed_value := 1, mode := "normal") -> Dictionary:
	var tune := apply_difficulty(SAYS, mode)
	var rng := GoobyRng.new(seed_value)
	var completed := 0
	for round_no in range(1, 41):
		var failed := false
		for _step in seq_length_at(round_no):
			if rng.next() < autoplay_err_at(round_no, tune):
				failed = true
				break
		if failed:
			break
		completed = round_no
	var reaction_ms := minf(float(tune["REACTION_FULL_MS"]), float(tune["AUTOPLAY_TAP_MS"]))
	return {
		"seed": seed_value,
		"mode": mode,
		"rounds": completed,
		"score": round_score(completed, reaction_ms, tune),
	}
