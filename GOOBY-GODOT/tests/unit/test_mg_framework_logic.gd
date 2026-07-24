extends TestCase
## Difficulty-/Coin-Policy-Parität gegen die Web-Logik: Goldwerte in
## tests/expected/framework.json (48 Coin-Fälle + effective/orientation/
## rotateGate-Matrizen), erzeugt von tools/cross_check.mjs DIREKT aus
## GOOBY/src/minigames/framework.logic.js.

const COIN_TABLES := {
	"teaParty": {"divisor": 4, "min": 4, "max": 26},
	"carrotCatch": {"divisor": 3, "min": 4, "max": 25},
}


func test_coin_cases_match_web_golden_values() -> void:
	var fixture: Variant = JsonFixtures.load_json("res://tests/expected/framework.json")
	assert_true(fixture is Dictionary, "framework.json fehlt — tools/cross_check.mjs laufen lassen")
	if not (fixture is Dictionary):
		return
	var cases: Array = fixture["coinCases"]
	assert_true(cases.size() >= 48, "erwartet >= 48 Coin-Faelle")
	for c: Dictionary in cases:
		var table: Dictionary = COIN_TABLES[c["game"]]
		var got := MinigameFrameworkLogic.apply_difficulty_coin_base(
			table, c["score"], str(c["mode"])
		)
		assert_eq(
			got, int(c["coins"]), "coinBase(%s, score=%s, %s)" % [c["game"], c["score"], c["mode"]]
		)
	assert_eq(
		MinigameFrameworkLogic.ENDLESS_FLAT_COINS,
		int(fixture["endlessFlatCoins"]),
		"Endlos-Pauschale"
	)
	assert_eq(
		MinigameFrameworkLogic.ENDLESS_MIN_LEVEL, int(fixture["endlessMinLevel"]), "Endlos-Level"
	)
	assert_eq(
		MinigameFrameworkLogic.STRIKES_FOR_TELEPORT,
		int(fixture["strikesForTeleport"]),
		"Teleport-Strikes"
	)


func test_effective_difficulty_matrix() -> void:
	var fixture: Variant = JsonFixtures.load_json("res://tests/expected/framework.json")
	if not (fixture is Dictionary):
		fail_test("framework.json fehlt")
		return
	for c: Dictionary in fixture["effective"]:
		var got := MinigameFrameworkLogic.effective_difficulty(str(c["id"]), c["params"])
		assert_eq(got, str(c["want"]), "effective(%s, %s)" % [c["id"], c["params"]])


func test_orientation_and_rotate_gate_matrix() -> void:
	var fixture: Variant = JsonFixtures.load_json("res://tests/expected/framework.json")
	if not (fixture is Dictionary):
		fail_test("framework.json fehlt")
		return
	for c: Dictionary in fixture["orientation"]:
		assert_eq(
			MinigameFrameworkLogic.normalize_orientation(c["value"]),
			str(c["want"]),
			"normalize_orientation(%s)" % [c["value"]]
		)
	for c: Dictionary in fixture["rotateGate"]:
		assert_eq(
			MinigameFrameworkLogic.should_show_rotate_gate(
				c["orientation"], bool(c["viewportIsLandscape"])
			),
			bool(c["want"]),
			"rotateGate(%s, landscape=%s)" % [c["orientation"], c["viewportIsLandscape"]]
		)


func test_apply_strike_sequence_and_hostile_input() -> void:
	var s1 := MinigameFrameworkLogic.apply_strike(0)
	assert_eq(s1["strikes"], 1)
	assert_false(s1["teleport"], "1. Strike teleportiert nicht")
	var s2 := MinigameFrameworkLogic.apply_strike(s1["strikes"])
	assert_false(s2["teleport"], "2. Strike teleportiert nicht")
	var s3 := MinigameFrameworkLogic.apply_strike(s2["strikes"])
	assert_true(s3["teleport"], "3. Strike teleportiert")
	assert_true(MinigameFrameworkLogic.apply_strike(99)["teleport"], "ueber dem Limit bleibt true")
	assert_eq(MinigameFrameworkLogic.apply_strike(-5)["strikes"], 1, "negativ == 0 behandelt")
	assert_eq(MinigameFrameworkLogic.apply_strike("kaputt")["strikes"], 1, "hostile == 0 behandelt")


func test_orientation_lock_for() -> void:
	assert_eq(MinigameFrameworkLogic.orientation_lock_for("landscape"), "unlock")
	assert_eq(MinigameFrameworkLogic.orientation_lock_for("portrait"), "portrait")
	assert_eq(MinigameFrameworkLogic.orientation_lock_for(null), "portrait")


func test_difficulty_slice_v5_shape() -> void:
	var state := {
		"progression": {"level": 12},
		"minigames":
		{
			"difficulty": {"teaParty": "hard"},
			"legacy":
			{
				"best": {"teaParty": 70},
				"bestByDiff": {"teaParty": {"hard": 88.0}},
				"endlessBest": {"teaParty": 9},
				"beaten": {"teaParty": {"hard": true}},
				"lastPlayDay": {},
			},
		},
	}
	var slice := MinigameFrameworkLogic.difficulty_slice_of(state, "teaParty")
	assert_eq(slice["selected"], "hard")
	assert_eq(slice["best"], 70)
	assert_eq(MinigameFrameworkLogic.best_for_mode(state, "teaParty", "hard"), 88)
	assert_eq(MinigameFrameworkLogic.best_for_mode(state, "teaParty", "endless"), 9)
	assert_eq(MinigameFrameworkLogic.best_for_mode(state, "teaParty", "normal"), 70)
	assert_true(MinigameFrameworkLogic.endless_unlocked(state, "teaParty"))
	# Level < 10 sperrt Endlos trotz beaten.hard.
	state["progression"]["level"] = 9
	assert_false(MinigameFrameworkLogic.endless_unlocked(state, "teaParty"))
	# Hostile/leerer State wirft nie.
	var empty := MinigameFrameworkLogic.difficulty_slice_of({}, "x")
	assert_eq(empty["selected"], "normal")
	assert_eq(empty["best"], 0)
	assert_false(MinigameFrameworkLogic.endless_unlocked({}, "x"))
