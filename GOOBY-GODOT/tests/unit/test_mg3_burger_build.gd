extends TestCase
## Burger-Bau (burgerBuild) — Logik-Parität zum Web (MG-3, Batch 3).
## Goldwerte aus `node` auf GOOBY/src/minigames/games/burgerBuild.logic.js.

const Logic := preload("res://scripts/minigames/games/burger_build/burger_build_logic.gd")

## Web-Goldwerte: simulateAutoplay(seed, mode).score für Seeds 1..5.
const GOLD := {
	"easy": [272.5, 290.0, 262.5, 270.0, 280.0],
	"normal": [272.5, 290.0, 262.5, 270.0, 280.0],
	"hard": [147.5, 132.5, 87.5, 75.0, 0.0],
	"endless": [427.5, 212.5, 87.5, 120.0, 0.0],
}


func test_constants_match_web() -> void:
	var t: Dictionary = Logic.BURGER
	assert_eq(float(t["DURATION_SEC"]), 75.0)
	assert_eq(int(t["COLUMNS"]), 3)
	assert_eq(int(t["MIN_LAYERS"]), 4)
	assert_eq(int(t["MAX_LAYERS"]), 7)
	assert_almost(float(t["CATCH_PTS"]), 5.0)
	assert_almost(float(t["WRONG_PTS"]), -2.0)
	assert_almost(float(t["COMPLETE_PTS"]), 15.0)
	assert_almost(float(t["FALL_RAMP_PCT"]), 0.08)
	assert_almost(float(t["FALL_BASE_SPEED"]), 2.1)
	assert_almost(float(t["SPAWN_SEC"]), 1.5)
	assert_almost(float(t["NEXT_WEIGHT"]), 0.24)
	assert_almost(float(t["ORDER_TIMER_SEC"]), 30.0)
	assert_almost(float(t["RUSH_SCORE_MULT"]), 1.5)
	assert_almost(float(t["PLATE_HALF_WIDTH"]), 0.78)
	assert_eq(int(t["ENDLESS_EXPIRES"]), 3)
	assert_eq(Logic.INGREDIENTS.size(), 5)
	assert_eq(Logic.FALLING_IDS.size(), 6)


func test_autoplay_matches_web_gold() -> void:
	for mode: String in GOLD:
		var want: Array = GOLD[mode]
		for i in want.size():
			var got: float = float(Logic.simulate_autoplay(i + 1, mode)["score"])
			assert_almost(got, float(want[i]), 1e-9, "%s seed %d" % [mode, i + 1])


func test_autoplay_is_deterministic() -> void:
	for mode: String in ["easy", "normal", "hard", "endless"]:
		var a: Dictionary = Logic.simulate_autoplay(7, mode)
		var b: Dictionary = Logic.simulate_autoplay(7, mode)
		assert_eq(a, b, mode)


func test_difficulty_is_monotone() -> void:
	# ACHTUNG: leicht und normal fahren denselben RNG-Strom und dieselben
	# Tickets — der Unterschied (Bot-Skill 0.99 vs. 0.95, Dauer 90 vs. 75 s)
	# schlägt erst im Mittel durch. Deshalb Mittelwerte über 40 Seeds.
	var means := {}
	for mode: String in ["easy", "normal", "hard"]:
		var sum := 0.0
		for seed_value in range(1, 41):
			sum += float(Logic.simulate_autoplay(seed_value, mode)["score"])
		means[mode] = sum / 40.0
	assert_true(means["easy"] > means["normal"], "leicht > normal (%s)" % means)
	assert_true(means["normal"] > means["hard"], "normal > schwer (%s)" % means)


func test_hard_bot_reaches_target() -> void:
	var best := 0.0
	for seed_value in range(1, 6):
		best = maxf(best, float(Logic.simulate_autoplay(seed_value, "hard")["score"]))
	assert_true(best >= 85.0, "bester Schwer-Score %f < Ziel 85" % best)


func test_make_ticket_matches_web() -> void:
	# Web mit Seed 1: drei Tickets hintereinander aus demselben RNG-Strom.
	var rng := GoobyRng.new(1)
	assert_eq(Logic.make_ticket(rng), ["bun", "onion", "tomato", "bun"] as Array[String])
	assert_eq(
		Logic.make_ticket(rng),
		["bun", "cheese", "patty", "tomato", "cheese", "onion", "bun"] as Array[String]
	)
	assert_eq(Logic.make_ticket(rng), ["bun", "onion", "cheese", "bun"] as Array[String])
	# Immer 4..7 Lagen und immer brötchengedeckelt.
	for seed_value in range(1, 40):
		var ticket := Logic.make_ticket(GoobyRng.new(seed_value))
		assert_true(ticket.size() >= 4 and ticket.size() <= 7, "Lagenzahl %d" % ticket.size())
		assert_eq(ticket[0], "bun")
		assert_eq(ticket[ticket.size() - 1], "bun")


func test_next_needed_and_complete() -> void:
	var ticket: Array[String] = ["bun", "patty", "bun"]
	assert_eq(Logic.next_needed(ticket, 0), "bun")
	assert_eq(Logic.next_needed(ticket, 1), "patty")
	assert_eq(Logic.next_needed(ticket, 3), "", "fertig = kein Bedarf")
	assert_false(Logic.is_complete(ticket, 2))
	assert_true(Logic.is_complete(ticket, 3))


func test_fall_ramp_and_columns() -> void:
	assert_almost(Logic.fall_speed_at(0), 2.1)
	assert_almost(Logic.fall_speed_at(1), 2.268, 1e-9)
	assert_almost(Logic.fall_speed_at(5), 3.0855889612800014, 1e-9)
	assert_almost(Logic.fall_speed_at(-3), 2.1, 1e-9, "negativ = keine Rampe")
	assert_eq(Logic.column_centers(3.4), [-2.1, 0.0, 2.1] as Array[float])
	var narrow := Logic.column_centers(1.0)
	assert_almost(narrow[0], -0.05, 1e-9)
	assert_almost(narrow[2], 0.05, 1e-9)


func test_rush_orders() -> void:
	assert_false(Logic.is_rush_order(1))
	assert_true(Logic.is_rush_order(2))
	assert_false(Logic.is_rush_order(3))
	assert_true(Logic.is_rush_order(4))
	assert_false(Logic.is_rush_order(6), "höchstens zwei Rush-Tickets")
	assert_almost(Logic.order_timer_sec(false), 30.0)
	assert_almost(Logic.order_timer_sec(true), 24.0)
	assert_almost(Logic.order_points(5.0, true), 7.5)
	assert_almost(Logic.order_points(-2.0, true), -2.0, 1e-9, "Strafen bleiben")


func test_score_edges() -> void:
	var t: Dictionary = Logic.BURGER
	assert_almost(Logic.apply_catch(0.0, true, false, t), 5.0)
	assert_almost(Logic.apply_catch(0.0, true, true, t), 7.5)
	assert_almost(Logic.apply_catch(0.0, false, false, t), 0.0, 1e-9, "nie negativ")
	assert_almost(Logic.apply_catch(1.0, false, true, t), 0.0, 1e-9)
	assert_almost(Logic.apply_catch(10.0, false, false, t), 8.0)


func test_roll_spawn_starvation_guard() -> void:
	var t: Dictionary = Logic.BURGER
	# Über FORCE_NEXT_SEC kommt IMMER die benötigte Lage — ohne rng-Verbrauch.
	var rng := GoobyRng.new(3)
	assert_eq(Logic.roll_spawn(rng, "cheese", 6.0, t), "cheese")
	assert_eq(Logic.roll_spawn(rng, "cheese", 99.0, t), "cheese")
	# Ohne Bedarf (Ticket voll) fällt nur aus dem allgemeinen Topf.
	for _i in 20:
		assert_true(Logic.FALLING_IDS.has(Logic.roll_spawn(rng, "", 0.0, t)))


func test_difficulty_rows() -> void:
	var easy: Dictionary = Logic.apply_difficulty(Logic.BURGER, "easy")
	assert_almost(float(easy["DURATION_SEC"]), 90.0)
	assert_almost(float(easy["ORDER_TIMER_SEC"]), 37.5)
	assert_almost(float(easy["BOT_SKILL"]), 0.99)
	var hard: Dictionary = Logic.apply_difficulty(Logic.BURGER, "hard")
	assert_almost(float(hard["SPAWN_SEC"]), 1.275)
	assert_almost(float(hard["ORDER_TIMER_SEC"]), 24.0)
	assert_almost(float(hard["PLATE_HALF_WIDTH"]), 0.624, 1e-9)
	assert_eq(Logic.apply_difficulty(Logic.BURGER, "normal"), Logic.BURGER)


func test_endless_ends_on_three_expired() -> void:
	var tune: Dictionary = Logic.apply_difficulty(Logic.BURGER, "endless")
	assert_true(bool(tune["ENDLESS"]))
	assert_false(Logic.endless_should_end(2, tune))
	assert_true(Logic.endless_should_end(3, tune))
	assert_false(Logic.endless_should_end(9, Logic.BURGER))
	for seed_value in range(1, 21):
		var run: Dictionary = Logic.simulate_autoplay(seed_value, "endless")
		assert_true(int(run["expired"]) <= 3, "Endlos stoppt am dritten Strike")
