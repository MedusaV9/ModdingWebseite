extends TestCase
## Minigolf (miniGolf) — Logik-Parität zum Web (MG-2, Batch 2).
## Goldwerte aus `node` auf GOOBY/src/minigames/games/miniGolf.logic.js.

const Logic := preload("res://scripts/minigames/games/mini_golf/mini_golf_logic.gd")
const Course := preload("res://scripts/minigames/games/mini_golf/mini_golf_course.gd")

## Der Bot spielt skriptete Schlagzahlen — der Score hängt nur am Modus.
const GOLD := {"easy": 150, "normal": 140, "hard": 132, "endless": 132}


func _course(seed_value: int, tune: Dictionary) -> Array[Dictionary]:
	var state := {"seed": seed_value}
	return Course.generate_course(func() -> float: return Logic._lcg(state), tune)


func test_constants_match_web() -> void:
	var t: Dictionary = Logic.GOLF
	assert_eq(int(t["HOLE_COUNT"]), 6)
	assert_almost(float(t["BALL_R"]), 0.08)
	assert_almost(float(t["RAIL"]), 0.055)
	assert_almost(float(t["FRICTION_PER_FRAME"]), 0.985)
	assert_almost(float(t["ROLL_DECEL"]), 0.22)
	assert_almost(float(t["STOP_SPEED"]), 0.01)
	assert_almost(float(t["MAX_POWER"]), 6.5)
	assert_almost(float(t["HOLE_R"]), 0.13)
	assert_almost(float(t["CAPTURE_SPEED"]), 2.8)
	assert_eq(int(t["MAX_STROKES"]), 10)
	assert_almost(float(t["WALL_RESTITUTION"]), 0.82)
	assert_almost(float(t["BUMP_R"]), 0.19)
	assert_almost(float(t["BUMP_RESTITUTION"]), 0.95)
	assert_almost(float(t["WINDMILL_RPS"]), 0.12)
	assert_almost(float(t["WINDMILL_BLOCK_FRAC"]), 0.45)
	assert_almost(float(t["RAMP_ACCEL"]), 2.6)
	assert_eq(int(t["SCORE_ACE"]), 30)
	assert_eq(int(t["SCORE_PAR"]), 20)
	assert_eq(int(t["SCORE_BOGEY"]), 12)
	assert_eq(int(t["SCORE_OTHER"]), 6)
	assert_eq(int(t["ENDLESS_OVER_PAR_LIMIT"]), 3)
	assert_almost(float(Logic.GOLF_JUICE["RING_LIFE_SEC"]), 0.55)


func test_autoplay_matches_web_gold() -> void:
	for mode: String in GOLD:
		for seed_value in range(1, 6):
			var got: int = int(Logic.simulate_autoplay(seed_value, mode)["score"])
			assert_eq(got, int(GOLD[mode]), "%s seed %d" % [mode, seed_value])


func test_autoplay_is_deterministic() -> void:
	for mode: String in ["easy", "normal", "hard", "endless"]:
		assert_eq(Logic.simulate_autoplay(9, mode), Logic.simulate_autoplay(9, mode), mode)
	var run: Dictionary = Logic.simulate_autoplay(7, "normal")
	assert_eq(int(run["overPar"]), 0)
	assert_eq((run["results"] as Array).size(), 6)


func test_difficulty_is_monotone() -> void:
	assert_true(GOLD["easy"] > GOLD["normal"], "leicht > normal")
	assert_true(GOLD["normal"] > GOLD["hard"], "normal > schwer")
	var hard: Dictionary = Logic.apply_difficulty(Logic.GOLF, "hard")
	var easy: Dictionary = Logic.apply_difficulty(Logic.GOLF, "easy")
	assert_almost(float(hard["HOLE_R"]), 0.10400000000000001)
	assert_almost(float(hard["CAPTURE_SPEED"]), 2.2399999999999998)
	assert_eq(int(hard["PAR_BONUS"]), 0)
	assert_almost(float(easy["HOLE_R"]), 0.1625)
	assert_almost(float(easy["CAPTURE_SPEED"]), 3.5)
	assert_eq(int(easy["PAR_BONUS"]), 1, "leicht spendiert einen Schlag Par")
	assert_eq(Logic.apply_difficulty(Logic.GOLF, "kaputt"), Logic.GOLF, "Fallback = normal")


func test_hard_bot_reaches_target() -> void:
	# §G5.4-Ziel für miniGolf ist 110 — der Schwer-Bot spielt 132.
	assert_true(GOLD["hard"] >= 110, "Schwer-Bot verfehlt Ziel 110")


func test_endless_ends_on_three_over_par() -> void:
	var tune: Dictionary = Logic.apply_difficulty(Logic.GOLF, "endless")
	assert_true(bool(tune["ENDLESS"]))
	var state: Dictionary = Logic.create_endless_state()
	assert_eq(int(state["limit"]), 3)
	assert_false(Logic.record_hole(state, 2, 3), "unter Par zählt nicht")
	assert_false(Logic.record_hole(state, 4, 3))
	assert_false(Logic.record_hole(state, 4, 3))
	assert_true(Logic.record_hole(state, 4, 3), "drittes Loch über Par beendet")
	assert_eq(int(state["overPar"]), 3)


func test_hole_score_edges() -> void:
	assert_eq(Logic.hole_score(1, 3), 30, "Ass")
	assert_eq(Logic.hole_score(2, 3), 20, "unter Par")
	assert_eq(Logic.hole_score(3, 3), 20, "Par")
	assert_eq(Logic.hole_score(4, 3), 12, "Bogey")
	assert_eq(Logic.hole_score(10, 3), 6, "10-Schlag-Abbruch = Trostpunkte")
	assert_eq(Logic.hole_score(1, 2), 30, "Ass schlägt Par")


func test_roll_physics_matches_web() -> void:
	assert_almost(Logic.friction_factor(1.0 / 60.0), 0.985, 1e-12)
	assert_almost(Logic.roll_speed(3.0, 1.0 / 60.0), 2.9513333333333334, 1e-12)
	assert_eq(Logic.roll_speed(0.001, 1.0), 0.0, "nie negativ")
	assert_almost(Logic.roll_distance(3.0), 2.636121244696345, 1e-9)
	assert_almost(Logic.power_for_distance(3.0), 3.3524878350086516, 1e-9)
	assert_almost(Logic.roll_time_to_distance(4.0, 2.0), 0.6833333333333338, 1e-9)
	assert_eq(Logic.roll_time_to_distance(0.5, 50.0), INF, "kommt nie an")


func test_drag_power_mapping() -> void:
	assert_almost(Logic.max_drag_px_for_viewport(390.0, 844.0), 148.2, 1e-9)
	assert_almost(Logic.max_drag_px_for_viewport(200.0, 200.0), 96.0, 1e-9, "Boden 96 px")
	assert_almost(Logic.max_drag_px_for_viewport(0.0, 0.0), 150.0, 1e-9)
	assert_almost(Logic.power_from_drag(75.0, 390.0, 844.0), 3.2894736842105265, 1e-9)
	assert_eq(Logic.power_from_drag(-40.0, 390.0, 844.0), 0.0)
	assert_almost(Logic.power_from_drag(9999.0, 390.0, 844.0), 6.5, 1e-9, "gedeckelt")


func test_reflect_and_windmill() -> void:
	var r: Dictionary = Logic.reflect({"vx": 2.0, "vz": 1.0}, -1.0, 0.0)
	assert_almost(float(r["vx"]), -1.6399999999999997, 1e-12)
	assert_almost(float(r["vz"]), 1.0, 1e-12)
	assert_true(Logic.windmill_blocked(0.0))
	assert_true(Logic.windmill_blocked(0.2))
	assert_false(Logic.windmill_blocked(0.4))
	assert_false(Logic.windmill_blocked(0.7))
	assert_false(Logic.windmill_blocked(1.0))
	assert_true(Logic.windmill_blocked(-0.1), "negative Winkel wickeln korrekt")


func test_capture_needs_slow_ball() -> void:
	assert_true(Logic.is_captured(0.05, 1.0))
	assert_false(Logic.is_captured(0.05, 3.0), "schnelle Bälle springen drüber")
	assert_false(Logic.is_captured(0.2, 1.0), "zu weit weg")


func test_course_generation_matches_web() -> void:
	var course := _course(7, Logic.GOLF)
	assert_eq(course.size(), 6)
	var ids := PackedStringArray()
	var pars := PackedInt32Array()
	for hole in course:
		ids.append(str(hole["id"]))
		pars.append(int(hole["par"]))
	assert_eq(ids, PackedStringArray(["straight", "corner", "ramp", "bump", "windmill", "tunnel"]))
	assert_eq(pars, PackedInt32Array([2, 2, 3, 2, 3, 3]))
	assert_eq(course[1]["cells"], [[0, 0], [0, 1], [0, 2], [1, 2], [2, 2]], "Dogleg Seed 7")
	assert_almost(float((course[3]["bump"] as Dictionary)["z"]), 3.0)
	assert_almost(float((course[3]["waypoints"] as Array)[0]["x"]), -0.3)
	assert_almost(float((course[4]["windmill"] as Dictionary)["phase"]), 5.8243962840895245, 1e-9)
	assert_almost(float((course[2]["ramp"] as Dictionary)["h"]), 0.1)
	# Leicht hebt jedes Par um 1.
	var easy := _course(7, Logic.apply_difficulty(Logic.GOLF, "easy"))
	assert_eq(int(easy[0]["par"]), 3)


func test_cell_roles_and_height() -> void:
	var course := _course(7, Logic.GOLF)
	var roles := func(h: Dictionary) -> PackedStringArray:
		var out := PackedStringArray()
		for row in Course.cell_roles(h):
			out.append(str(row["role"]))
		return out
	assert_eq(
		roles.call(course[4]),
		PackedStringArray(["start", "straight", "windmill", "straight", "hole"])
	)
	assert_eq(
		roles.call(course[3]), PackedStringArray(["start", "straight", "straight", "bump", "hole"])
	)
	assert_eq(
		roles.call(course[1]),
		PackedStringArray(["start", "straight", "corner", "straight", "hole"])
	)
	assert_almost(Course.height_at(course[2], 0.0, 2.0), 0.05)
	assert_almost(Course.height_at(course[2], 0.0, 2.5), 0.1, 1e-9, "Plateau")
	assert_almost(Course.height_at(course[2], 0.0, 1.4), 0.0)
	assert_almost(Course.height_at(course[0], 0.0, 2.0), 0.0, 1e-9, "ohne Rampe flach")
	assert_true(Course.on_ramp(course[2], 0.1, 2.2))
	assert_false(Course.on_ramp(course[2], 0.1, 3.2))


func test_can_be_at_respects_rails() -> void:
	var course := _course(7, Logic.GOLF)
	var hole: Dictionary = course[0]
	assert_true(Course.can_be_at(hole, 0.0, 0.0))
	assert_false(Course.can_be_at(hole, 0.4, 0.0), "Bande links/rechts")
	assert_false(Course.can_be_at(hole, 0.0, 3.4), "Bande hinter dem Loch")
	assert_false(Course.can_be_at(hole, 0.0, -0.4), "Bande hinter dem Abschlag")
	assert_true(Course.can_be_at(hole, 0.0, 1.4), "offene Kante zur Nachbarzelle")
	# JS-Rundung bei negativen Zellen (Dogleg nach links).
	assert_eq(Course.js_round(-0.5), 0, "JS rundet .5 nach +unendlich")
	assert_eq(Course.js_round(-1.5), -1)
	assert_eq(Course.js_round(0.5), 1)


func test_step_ball_sinks_and_banks() -> void:
	var course := _course(7, Logic.GOLF)
	var hole: Dictionary = course[0]
	var ball := {"x": 0.0, "z": 0.0, "vx": 0.0, "vz": Logic.power_for_distance(3.0)}
	var theta := 0.0
	var frames := 0
	var holed := false
	while frames < 900 and not bool(ball.get("done", false)):
		if Logic.step_ball(hole, ball, 1.0 / 60.0, theta).has("holed"):
			holed = true
		theta += PI * 2.0 * float(Logic.GOLF["WINDMILL_RPS"]) / 60.0
		frames += 1
	assert_true(holed, "Putt auf Zieldistanz fällt")
	assert_eq(frames, 134, "gleiche Flugdauer wie im Web")
	assert_almost(float(ball["z"]), 3.0)
	# Seitlicher Putt bankt zweimal von den Banden ab.
	var b2 := {"x": 0.0, "z": 0.5, "vx": 3.0, "vz": 0.0}
	var events: Array[String] = []
	for i in 40:
		events.append_array(Logic.step_ball(hole, b2, 1.0 / 60.0, 0.0))
	assert_eq(events, ["bank", "bank"] as Array[String])
	assert_almost(float(b2["x"]), -0.22732736813333426, 1e-9)
	assert_almost(float(b2["vx"]), 1.0092211078566264, 1e-9)


func test_bonus_hole_seven() -> void:
	var state := {"seed": 7}
	var rng := func() -> float: return Logic._lcg(state)
	for i in 4:
		rng.call()
	var bonus: Dictionary = Course.create_nougat_loop_hole(rng, Logic.GOLF)
	assert_eq(str(bonus["id"]), "nougatLoop")
	assert_eq(int(bonus["par"]), 3)
	assert_almost(float((bonus["nougat"] as Dictionary)["phase"]), 0.3100197473040081, 1e-9)
	assert_almost(Course.nougat_x_at(bonus, 0.0), 0.0732185861770762, 1e-9)
	assert_eq(Course.nougat_x_at({}, 0.0), INF, "ohne Schleuse kein x")
	assert_true(Course.qualifies_nougat_loop(Logic.simulate_autoplay(1, "normal")["results"]))
	assert_false(Course.qualifies_nougat_loop([]), "unvollständige Runde qualifiziert nicht")
	var bad: Array = Logic.simulate_autoplay(1, "normal")["results"].duplicate(true)
	bad[0]["strokes"] = 9
	assert_false(Course.qualifies_nougat_loop(bad))
