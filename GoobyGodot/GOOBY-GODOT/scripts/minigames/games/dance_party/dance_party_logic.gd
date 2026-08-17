class_name DancePartyLogic
extends RefCounted
## Pure Tanzparty-Logik — zahlengleicher Port von
## GOOBY/src/minigames/games/danceParty.logic.js + data/constants.js DANCE
## (§C6.1 #9). 100 BPM, gesetztes 75-s-Notenbild aus PATTERN_SEED, 3 Bahnen,
## Fenster ≤ 70 ms = perfekt (+4) / ≤ 140 ms = gut (+2), Fehler bricht die
## Serie und kostet 2 Punkte, Zugabe (Encore) verdoppelt 5 s lang.
##
## ABWEICHUNG zum Web: `createSongClock` ist NICHT portiert — der Absolutzeit-
## Anker existiert nur, um rAF-Jitter im Browser auszugleichen. Godot liefert
## in `_process(delta)` bereits eine stabile Uhr; die Szene summiert `delta`.

## §C6-Vertragszahlen (data/constants.js DANCE) — Coin-Zeile 6/4/28, Ziel 140.
const DANCE := {
	"BPM": 100.0,
	"PATTERN_SEED": 1002026,
	"DURATION_SEC": 75.0,
	"LANES": 3,
	"PERFECT_MS": 70.0,
	"GOOD_MS": 140.0,
	"PERFECT_PTS": 4,
	"GOOD_PTS": 2,
	"MISS_PENALTY": 2,
}

## G10-Feinabstimmung (Notenbild + Feel).
const DANCE_TUNING := {
	"DURATION_SEC": 75.0,
	"PERFECT_MS": 70.0,
	"GOOD_MS": 140.0,
	"ENDLESS": false,
	"ENDLESS_BREAK_LIMIT": 3,
	"RAMP_FLOOR_STEP": 0,
	"LEAD_IN_SEC": 2.4,
	"NOTE_TRAVEL_SEC": 1.6,
	"SLOTS_PER_BEAT": 2,
	"MIN_GAP_SEC": 0.3,
	"LANE_GAP_SEC": 0.6,
	"DENSITY_START": 0.3,
	"DENSITY_END": 0.55,
	"OFFBEAT_MULT": 0.5,
	"START_BEAT": 4,
	"TAIL_SEC": 2.0,
	"LANE_REPEAT_CHANCE": 0.3,
	"TIER_COMBOS": [4, 8, 16],
	"END_DELAY_SEC": 1.6,
	"ENCORE_PERFECTS": 5,
	"ENCORE_SEC": 5.0,
	"DRIFT_MAX_FRAME_GAP_SEC": 2.0,
}

## V4/GAME-POLISH-4-Juice (nur Optik, nie Timing/Wertung).
const DANCE_JUICE := {
	"BURST_LIFE_SEC": 0.32,
	"BURST_SCALE_PERFECT": 2.7,
	"BURST_SCALE_GOOD": 1.9,
	"BALL_SPIN_BASE": 0.9,
	"BALL_SPIN_PER_TIER": 0.35,
	"BALL_POP_SCALE": 1.4,
	"BALL_POP_SEC": 0.5,
}


## §G5-Difficulty. PATTERN_SEED und BPM bleiben bewusst unberührt (der
## §D6/G14-Musikvertrag): nur Dichte, Anflugzeit und Trefferfenster ändern sich.
static func apply_difficulty(tune := DANCE_TUNING, mode := "normal") -> Dictionary:
	if mode == "normal" or not ["easy", "hard", "endless"].has(mode):
		return tune
	var hard := mode == "hard" or mode == "endless"
	var speed_mult := 1.15 if hard else 0.85
	var window_mult := 0.8 if hard else 1.25
	var out := tune.duplicate(true)
	out["DENSITY_START"] = float(tune["DENSITY_START"]) * speed_mult
	out["DENSITY_END"] = float(tune["DENSITY_END"]) * speed_mult
	out["NOTE_TRAVEL_SEC"] = float(tune["NOTE_TRAVEL_SEC"]) / speed_mult
	out["PERFECT_MS"] = float(tune["PERFECT_MS"]) * window_mult
	out["GOOD_MS"] = float(tune["GOOD_MS"]) * window_mult
	out["RAMP_FLOOR_STEP"] = -1 if hard else 0
	out["ENDLESS"] = mode == "endless"
	return out


## Aus ctx.params abgeleiteten Trefferfenster-Faktor anwenden.
static func with_hitbox(tune: Dictionary, hitbox_mult := 1.0) -> Dictionary:
	var mult := hitbox_mult if is_finite(hitbox_mult) and hitbox_mult > 0.0 else 1.0
	if mult == 1.0:
		return tune
	var out := tune.duplicate(true)
	out["PERFECT_MS"] = float(tune["PERFECT_MS"]) * mult
	out["GOOD_MS"] = float(tune["GOOD_MS"]) * mult
	return out


## §G5.4: drei Abschnitte mit Serienbruch beenden den Endlostanz.
static func create_endless_state(limit := int(DANCE_TUNING["ENDLESS_BREAK_LIMIT"])) -> Dictionary:
	return {"breaks": 0, "limit": limit, "ended": false}


static func record_section(state: Dictionary, missed: bool) -> bool:
	if missed and not bool(state["ended"]):
		state["breaks"] = int(state["breaks"]) + 1
	state["ended"] = int(state["breaks"]) >= int(state["limit"])
	return bool(state["ended"])


## Gesetztes Notenbild (§C6.1 #9): Achtelraster bei `bpm`, Dichterampe,
## gewichteter Bahn-Zufallslauf, Mindestabstände global und je Bahn.
static func generate_pattern(
	seed_value := int(DANCE["PATTERN_SEED"]), tune := DANCE_TUNING, bpm := float(DANCE["BPM"])
) -> Array[Dictionary]:
	var duration := float(tune["DURATION_SEC"])
	var rng := GoobyRng.new(seed_value)
	var beat_sec := 60.0 / bpm
	var slot_sec := beat_sec / float(tune["SLOTS_PER_BEAT"])
	var start_slot := int(tune["START_BEAT"]) * int(tune["SLOTS_PER_BEAT"])
	var end_time := duration - float(tune["TAIL_SEC"])
	var total_slots := int(floor(end_time / slot_sec))
	var lanes := int(DANCE["LANES"])

	var notes: Array[Dictionary] = []
	var last_time := -INF
	var last_lane_time: Array[float] = [-INF, -INF, -INF]
	var lane := int(floor(rng.next() * lanes))

	for slot in range(start_slot, total_slots + 1):
		var time := slot * slot_sec
		if time > end_time:
			break
		var density := _density_at(time / duration, slot, tune)
		if rng.next() >= density:
			continue
		if time - last_time < float(tune["MIN_GAP_SEC"]) - 1e-9:
			continue
		# Bahnlauf: manchmal stehen bleiben, sonst zur Nachbarbahn treten.
		if rng.next() >= float(tune["LANE_REPEAT_CHANCE"]):
			lane = _walk_lane(lane, rng, lanes)
		var chosen := _first_free_lane(lane, time, last_lane_time, tune, lanes)
		if chosen == -1:
			continue
		lane = chosen
		notes.append({"time": time, "lane": lane, "slot": slot})
		last_time = time
		last_lane_time[lane] = time
	return notes


static func _density_at(t: float, slot: int, tune: Dictionary) -> float:
	var start := float(tune["DENSITY_START"])
	var density := start + (float(tune["DENSITY_END"]) - start) * t
	if slot % int(tune["SLOTS_PER_BEAT"]) != 0:
		density *= float(tune["OFFBEAT_MULT"])
	return density


## Randbahnen treten zwingend nach innen; nur die Mittelbahn würfelt.
static func _walk_lane(lane: int, rng: GoobyRng, lanes: int) -> int:
	if lane == 0:
		return 1
	if lane == lanes - 1:
		return lanes - 2
	return lane + (-1 if rng.next() < 0.5 else 1)


static func _first_free_lane(
	lane: int, time: float, last_lane_time: Array[float], tune: Dictionary, lanes: int
) -> int:
	for k in lanes:
		var cand := (lane + k) % lanes
		if time - last_lane_time[cand] >= float(tune["LANE_GAP_SEC"]) - 1e-9:
			return cand
	return -1


## Seed des n-ten Endlos-Chartsegments (Web: PATTERN_SEED + imul(seg, 0x9e3779b1)).
static func segment_seed(segment: int) -> int:
	if segment == 0:
		return int(DANCE["PATTERN_SEED"])
	return (int(DANCE["PATTERN_SEED"]) + segment * 0x9e3779b1) & 0xFFFFFFFF


## §G5.4-Endlos: Abschnittsnummer der Songzeit (12-Sekunden-Blöcke).
static func section_index(song_time: float) -> int:
	return int(floor(song_time / 12.0))


## Trefferklasse aus dem Zeitfehler: ≤ 70 ms perfekt, ≤ 140 ms gut, sonst "".
static func classify_hit(delta_sec: float, tune := DANCE_TUNING) -> String:
	var ms := absf(delta_sec) * 1000.0
	if ms <= float(tune["PERFECT_MS"]):
		return "perfect"
	if ms <= float(tune["GOOD_MS"]):
		return "good"
	return ""


## Note, die ein Bahnen-Tipp greift: die nächste offene Note im Gut-Fenster.
static func judge_tap(
	notes: Array[Dictionary], lane: int, song_time: float, tune := DANCE_TUNING
) -> int:
	var best := -1
	var best_abs := INF
	var window := float(tune["GOOD_MS"]) / 1000.0
	for i in notes.size():
		var n: Dictionary = notes[i]
		if int(n["lane"]) != lane or bool(n.get("hit", false)) or bool(n.get("missed", false)):
			continue
		if float(n["time"]) - song_time > window:
			break
		var d := absf(float(n["time"]) - song_time)
		if d <= window and d < best_abs:
			best = i
			best_abs = d
	return best


## Frische Wertungstafel.
static func create_tally() -> Dictionary:
	return {"perfect": 0, "good": 0, "miss": 0, "combo": 0, "maxCombo": 0, "bonus": 0}


## Eine Wertung buchen: perfekt/gut verlängern die Serie, Fehler setzt zurück.
static func apply_judgment(tally: Dictionary, kind: String) -> Dictionary:
	if kind == "miss":
		tally["miss"] = int(tally["miss"]) + 1
		tally["combo"] = 0
		return tally
	tally[kind] = int(tally[kind]) + 1
	tally["combo"] = int(tally["combo"]) + 1
	if int(tally["combo"]) > int(tally["maxCombo"]):
		tally["maxCombo"] = int(tally["combo"])
	return tally


## Rundenpunkte: perfekt×4 + gut×2 − 2×Fehler + Zugabe-Bonus, mindestens 0.
static func dance_score(tally: Dictionary) -> int:
	return maxi(
		0,
		(
			int(tally["perfect"]) * int(DANCE["PERFECT_PTS"])
			+ int(tally["good"]) * int(DANCE["GOOD_PTS"])
			- int(tally["miss"]) * int(DANCE["MISS_PENALTY"])
			+ int(tally.get("bonus", 0))
		)
	)


## Tanzenergie-Stufe aus der Serie: 0 (Basis) … 3 (Fieber).
static func combo_tier(combo: int) -> int:
	var tiers: Array = DANCE_TUNING["TIER_COMBOS"]
	if combo >= int(tiers[2]):
		return 3
	if combo >= int(tiers[1]):
		return 2
	if combo >= int(tiers[0]):
		return 1
	return 0


## V3/G44-Fieberkette (§C10.2).
static func create_fever_chain() -> Dictionary:
	return {"perfects": 0, "encoreUntil": -INF, "encores": 0}


static func encore_active(chain: Dictionary, song_time: float) -> bool:
	return song_time < float(chain["encoreUntil"])


## Fünf perfekte Treffer in Folge im Fieber starten eine 5-s-Zugabe.
static func advance_fever_chain(
	chain: Dictionary, kind: String, combo: int, song_time: float
) -> Dictionary:
	if encore_active(chain, song_time):
		return {"active": true, "started": false}
	if kind != "perfect" or combo_tier(combo) < 3:
		chain["perfects"] = 0
		return {"active": false, "started": false}
	chain["perfects"] = int(chain["perfects"]) + 1
	if int(chain["perfects"]) < int(DANCE_TUNING["ENCORE_PERFECTS"]):
		return {"active": false, "started": false}
	chain["perfects"] = 0
	chain["encoreUntil"] = song_time + float(DANCE_TUNING["ENCORE_SEC"])
	chain["encores"] = int(chain["encores"]) + 1
	return {"active": true, "started": true}


## Zusatzpunkte der Zugabe (die zweite Kopie der Notenpunkte).
static func encore_bonus(kind: String, active: bool) -> int:
	if not active or kind == "miss":
		return 0
	return int(DANCE["PERFECT_PTS"]) if kind == "perfect" else int(DANCE["GOOD_PTS"])


## Lebenszyklus einer Note: "future" | "visible" | "expired".
static func note_lifecycle(note_time: float, song_time: float, tune := DANCE_TUNING) -> String:
	if song_time - note_time > float(tune["GOOD_MS"]) / 1000.0:
		return "expired"
	if note_time - song_time <= float(tune["NOTE_TRAVEL_SEC"]):
		return "visible"
	return "future"


## Deterministischer Zertifizierungsbot (gesetzter menschlicher Zeitfehler).
static func simulate_autoplay(seed_value: int, mode := "normal") -> Dictionary:
	var tune := apply_difficulty(DANCE_TUNING, mode)
	var notes := generate_pattern(int(DANCE["PATTERN_SEED"]), tune)
	var rng := GoobyRng.new(seed_value)
	var tally := create_tally()
	var miss_chance := 0.08
	if mode == "easy":
		miss_chance = 0.04
	elif mode == "hard" or mode == "endless":
		miss_chance = 0.1
	for note in notes:
		if rng.next() < miss_chance:
			apply_judgment(tally, "miss")
			continue
		var error := (rng.next() + rng.next() + rng.next() - 1.5) * 0.16
		var kind := classify_hit(error, tune)
		apply_judgment(tally, kind if not kind.is_empty() else "miss")
	return {"score": dance_score(tally), "tune": tune, "tally": tally}
