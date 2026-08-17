extends TestCase
## Geisterjagd (ghostHunt) — Logik-Parität zum Web (MG-2, Batch 2).
## Goldwerte aus `node` auf GOOBY/src/minigames/games/ghostHunt.logic.js.

const Logic := preload("res://scripts/minigames/games/ghost_hunt/ghost_hunt_logic.gd")

## Web-Goldwerte: simulateHuntAutoplay(mode, seed).score für Seeds 1..5.
const GOLD := {
	"easy": [93, 127, 132, 139, 146],
	"normal": [106, 106, 96, 111, 82],
	"hard": [84, 81, 91, 87, 95],
	"endless": [71, 69, 78, 87, 70],
}


func test_constants_match_web() -> void:
	var h: Dictionary = Logic.HUNT
	assert_almost(float(h["DURATION_SEC"]), 90.0)
	assert_almost(float(h["VISIBLE_START_SEC"]), 2.2)
	assert_almost(float(h["VISIBLE_END_SEC"]), 0.9)
	assert_eq(int(h["CATCH_POINTS"]), 3)
	assert_almost(float(h["CHAIN_WINDOW_SEC"]), 1.5)
	assert_eq(int(h["CHAIN_BONUS_CAP"]), 5)
	assert_eq(int(h["DECOY_PENALTY"]), -2)
	assert_almost(float(h["DECOY_FLICKER_SEC"]), 1.8)
	assert_almost(float(h["DECOY_CHANCE_START"]), 0.12)
	assert_almost(float(h["DECOY_CHANCE_END"]), 0.28)
	assert_almost(float(h["BOO_EVERY_SEC"]), 25.0)
	assert_eq(int(h["BOO_COUNT"]), 5)
	assert_eq(int(h["BOO_CATCH_MIN"]), 4)
	assert_eq(int(h["BOO_BONUS"]), 10)
	assert_almost(float(h["BOO_MIN_VISIBLE_SEC"]), 1.6)
	assert_almost(float(h["LANTERN_SEC"]), 3.0)
	assert_almost(float(h["LANTERN_REVEAL_BONUS_SEC"]), 0.4)
	assert_eq(int(h["NET_CATCHES"]), 3)
	assert_almost(float(h["TOKEN_VISIBLE_SEC"]), 5.0)
	assert_almost(float(h["SPAWN_START_SEC"]), 2.8)
	assert_almost(float(h["SPAWN_END_SEC"]), 1.5)
	assert_almost(float(h["FIRST_SPAWN_SEC"]), 0.8)
	assert_eq(int(h["ENDLESS_ESCAPE_LIMIT"]), 3)
	assert_eq(Logic.SPOTS.size(), 12, "12 Verstecke")
	assert_eq(Logic.DECOY_SPOTS.size(), 4)
	assert_eq(Logic.TOKEN_ANCHORS.size(), 4)
	assert_eq((h["TOKEN_WINDOWS"] as Array).size(), 4)


func test_ramps_match_web() -> void:
	assert_almost(Logic.visible_dur_at(0.0), 2.2, 1e-12)
	assert_almost(Logic.visible_dur_at(30.0), 1.7666666666666668, 1e-12)
	assert_almost(Logic.visible_dur_at(90.0), 0.8999999999999999, 1e-12)
	assert_almost(Logic.spawn_interval_at(0.0), 2.8, 1e-12)
	assert_almost(Logic.spawn_interval_at(30.0), 2.3666666666666667, 1e-12)
	assert_almost(Logic.spawn_interval_at(90.0), 1.5, 1e-12)
	assert_almost(Logic.decoy_chance_at(0.0), 0.12, 1e-12)
	assert_almost(Logic.decoy_chance_at(30.0), 0.17333333333333334, 1e-12)
	assert_almost(Logic.decoy_chance_at(90.0), 0.28, 1e-12)
	# Rampe klemmt außerhalb der Runde.
	assert_almost(Logic.visible_dur_at(-5.0), 2.2, 1e-12)
	assert_almost(Logic.visible_dur_at(200.0), 0.8999999999999999, 1e-12)
	assert_eq(Logic.boo_wave_times(), [25.0, 50.0, 75.0] as Array[float])


func test_difficulty_rows_match_web() -> void:
	var easy: Dictionary = Logic.apply_difficulty(Logic.HUNT, "easy")
	assert_almost(float(easy["DURATION_SEC"]), 108.0, 1e-12)
	assert_almost(float(easy["SPAWN_START_SEC"]), 3.36, 1e-12)
	assert_almost(float(easy["SPAWN_END_SEC"]), 1.7999999999999998, 1e-12)
	assert_almost(float(easy["VISIBLE_START_SEC"]), 2.75, 1e-12)
	assert_almost(float(easy["VISIBLE_END_SEC"]), 1.125, 1e-12)
	assert_almost(float(easy["BOO_MIN_VISIBLE_SEC"]), 2.0, 1e-12)
	assert_almost(float(easy["BOT_ENGAGE"]), 0.44, 1e-12)
	assert_false(bool(easy["ENDLESS"]))
	var hard: Dictionary = Logic.apply_difficulty(Logic.HUNT, "hard")
	assert_almost(float(hard["DURATION_SEC"]), 90.0, 1e-12)
	assert_almost(float(hard["SPAWN_START_SEC"]), 2.38, 1e-12)
	assert_almost(float(hard["SPAWN_END_SEC"]), 1.275, 1e-12)
	assert_almost(float(hard["VISIBLE_START_SEC"]), 1.7600000000000002, 1e-12)
	assert_almost(float(hard["VISIBLE_END_SEC"]), 0.7200000000000001, 1e-12)
	assert_almost(float(hard["BOO_MIN_VISIBLE_SEC"]), 1.2800000000000002, 1e-12)
	assert_almost(float(hard["BOT_ENGAGE"]), 0.36, 1e-12)
	assert_true(bool(Logic.apply_difficulty(Logic.HUNT, "endless")["ENDLESS"]))
	assert_eq(Logic.apply_difficulty(Logic.HUNT, "unsinn"), Logic.HUNT, "Fallback = Basis")


func test_autoplay_matches_web_gold() -> void:
	for mode: String in GOLD:
		var want: Array = GOLD[mode]
		for i in want.size():
			var got: int = int(Logic.simulate_autoplay(mode, i + 1)["score"])
			assert_eq(got, int(want[i]), "%s seed %d" % [mode, i + 1])
	var run: Dictionary = Logic.simulate_autoplay("normal", 3)
	assert_eq(int(run["caught"]), 20)
	assert_eq(int(run["missed"]), 29)
	assert_eq(int(run["escapedWaves"]), 3)
	assert_eq(int(run["booBonuses"]), 0)
	assert_almost(float(run["time"]), 90.03333333333079, 1e-9)


func test_autoplay_is_deterministic() -> void:
	for mode: String in ["easy", "normal", "hard", "endless"]:
		assert_eq(Logic.simulate_autoplay(mode, 11), Logic.simulate_autoplay(mode, 11), mode)


func test_difficulty_is_monotone() -> void:
	var means := {}
	for mode: String in ["easy", "normal", "hard"]:
		var sum := 0
		for seed_value in range(1, 31):
			sum += int(Logic.simulate_autoplay(mode, seed_value)["score"])
		means[mode] = float(sum) / 30.0
	assert_true(means["easy"] > means["normal"], "leicht > normal (%s)" % means)
	assert_true(means["normal"] > means["hard"], "normal > schwer (%s)" % means)


func test_bot_is_plausible() -> void:
	# Der Bot fängt nur die Geister, die er markiert (BOT_ENGAGE ≈ 0.4) —
	# also deutlich mehr als nichts, aber weit vom perfekten Lauf entfernt.
	for seed_value in range(1, 6):
		var run: Dictionary = Logic.simulate_autoplay("normal", seed_value)
		var caught := int(run["caught"])
		var missed := int(run["missed"])
		assert_true(caught >= 12, "zu wenig Fänge: %d (seed %d)" % [caught, seed_value])
		assert_true(missed > 0, "ein Bot mit BOT_ENGAGE < 1 lässt Geister ziehen")
		assert_true(
			float(caught) / float(caught + missed) < 0.75,
			"Bot darf nicht perfekt sein (seed %d)" % seed_value
		)


func test_endless_ends_on_three_escaped_waves() -> void:
	for seed_value in range(1, 6):
		var run: Dictionary = Logic.simulate_autoplay("endless", seed_value)
		assert_eq(int(run["escapedWaves"]), 3, "Endlos endet an 3 Wellen (seed %d)" % seed_value)
		assert_true(
			float(run["time"]) < 900.0,
			"Endlos terminiert vor dem Sicherheitsnetz (seed %d)" % seed_value
		)
	# Endlos hat keine Rundenuhr: die Buh-Zeiten wachsen über 90 s hinaus.
	var tune: Dictionary = Logic.apply_difficulty(Logic.HUNT, "endless")
	var state: Dictionary = Logic.create_hunt(4, tune)
	for i in 3000:
		Logic.step_hunt(state, 1.0 / 30.0)
		if bool(state["ended"]):
			break
	assert_true(bool(state["ended"]), "Endlos endet ohne Zutun am Wellen-Limit")


func test_step_trace_matches_web() -> void:
	var state: Dictionary = Logic.create_hunt(42)
	for i in 300:
		Logic.step_hunt(state, 1.0 / 30.0)
	assert_almost(float(state["t"]), 10.0, 1e-9)
	assert_eq((state["ghosts"] as Array).size(), 1)
	assert_eq(int(state["missed"]), 3)
	assert_eq((state["flickers"] as Array).size(), 0)
	assert_almost(float(state["nextSpawnT"]), 11.801407, 1e-6)
	assert_eq(int(state["nextGhostId"]), 5)


func test_tap_semantics_and_score_edges() -> void:
	var state: Dictionary = Logic.create_hunt(42)
	for i in 300:
		Logic.step_hunt(state, 1.0 / 30.0)
	var id := int((state["ghosts"][0] as Dictionary)["id"])
	var hit: Dictionary = Logic.tap_hunt(state, {"kind": "ghost", "id": id})
	assert_eq(str(hit["kind"]), "ghost")
	assert_eq(int(hit["points"]), 3)
	assert_eq(int(hit["chain"]), 1)
	assert_eq(int(state["score"]), 3)
	# Derselbe Geist ist weg — der zweite Tipp geht ins Leere.
	assert_eq(str(Logic.tap_hunt(state, {"kind": "ghost", "id": id})["kind"]), "miss")
	assert_eq(str(Logic.tap_hunt(state, {})["kind"]), "miss")
	assert_eq(int(state["chain"]), 0, "Tipp ins Dunkel bricht die Kette")
	assert_eq(Logic.run_meta(state), {"ghostsCaught": 1, "decoysTapped": 0, "booBonuses": 0})
	# Kettenbonus: erst ab dem zweiten Glied, gedeckelt bei +5.
	assert_eq(
		[0, 1, 2, 3, 6, 7, 20].map(func(n: int) -> int: return Logic.chain_bonus(n)),
		[0, 0, 1, 2, 5, 5, 5]
	)
	# Attrappen kosten 2 Punkte, aber der Score wird nie negativ.
	var fresh: Dictionary = Logic.create_hunt(7)
	(fresh["flickers"] as Array).append({"decoy": 1, "startT": 0.0})
	assert_eq(int(Logic.tap_hunt(fresh, {"kind": "decoy", "decoy": 1})["points"]), -2)
	assert_eq(int(fresh["score"]), 0, "nie negativ")
	assert_eq(Logic.hunt_score(fresh), 0)
	assert_eq(str(Logic.tap_hunt(fresh, {"kind": "decoy", "decoy": 1})["kind"]), "miss")


func test_powerup_tokens() -> void:
	var state: Dictionary = Logic.create_hunt(9)
	(state["tokens"] as Array).append({"window": 0, "kind": "lantern", "startT": 0.0})
	var got: Dictionary = Logic.tap_hunt(state, {"kind": "token", "window": 0})
	assert_eq(str(got["powerup"]), "lantern")
	assert_almost(float(state["lanternT"]), 3.0)
	(state["tokens"] as Array).append({"window": 1, "kind": "net", "startT": 0.0})
	Logic.tap_hunt(state, {"kind": "token", "window": 1})
	assert_eq(int(state["netLeft"]), 3)
	# Das Netz verkettet die nächsten drei Fänge automatisch (ohne 1.5-s-Fenster).
	for i in 3:
		(
			(state["ghosts"] as Array)
			. append(
				{
					"id": 100 + i,
					"spot": i,
					"spawnT": 0.0,
					"dur": 99.0,
					"wave": null,
					"revealed": false,
				}
			)
		)
	state["t"] = 60.0
	for i in 3:
		var hit: Dictionary = Logic.tap_hunt(state, {"kind": "ghost", "id": 100 + i})
		assert_eq(int(hit["chain"]), i + 1, "Netzfang %d verkettet" % i)
	assert_eq(int(state["netLeft"]), 0)
	assert_eq(int(state["score"]), 12, "3 + 4 + 5 (Kettenbonus 0/1/2)")
