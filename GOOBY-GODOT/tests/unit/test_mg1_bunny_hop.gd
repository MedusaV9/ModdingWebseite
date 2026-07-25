extends TestCase
## Hasen-Hüpfer (bunnyHop) — Logik-Parität zum Web (MG-1, Batch 1).
## Goldwerte aus `node` auf GOOBY/src/minigames/games/bunnyHop.logic.js
## (simulateHopAutoplay) — sie sperren Tempo-Rampe, Lückenverengung und den
## Windfahrplan fest.

const Logic := preload("res://scripts/minigames/games/bunny_hop/bunny_hop_logic.gd")
const MANIFEST := "res://scripts/minigames/games/bunny_hop/game.json"

## Web-Goldwerte: simulateHopAutoplay(seed, mode).score für Seeds 1..8.
const GOLD := {
	"easy": [87, 92, 98, 96, 99, 81, 88, 98],
	"normal": [80, 85, 89, 85, 89, 73, 79, 90],
	"hard": [73, 76, 81, 76, 79, 65, 71, 82],
	"endless": [82, 86, 97, 86, 95, 76, 83, 99],
}
const WEB_TARGET := 45


func test_constants_match_web() -> void:
	var t: Dictionary = Logic.HOP
	assert_almost(float(t["BASE_SPEED"]), 1.55)
	assert_almost(float(t["SPEED_RAMP_PCT"]), 0.02)
	assert_almost(float(t["PILLAR_SPACING_X"]), 2.7)
	assert_almost(float(t["GAP_BASE"]), 2.15)
	assert_almost(float(t["GAP_NARROW_STEP"]), 0.16)
	assert_almost(float(t["GAP_MIN"]), 1.5)
	assert_eq(int(t["GAP_NARROW_EVERY_GATES"]), 10)
	assert_almost(float(t["HOP_VY"]), 3.1)
	assert_almost(float(t["GRAVITY"]), -8.5)
	assert_almost(float(t["FLOOR_Y"]), -3.1)
	assert_almost(float(t["CEILING_Y"]), 3.9)
	assert_almost(float(t["HITBOX_SCALE"]), 0.7)
	assert_almost(float(t["BODY_HALF_W"]), 0.34)
	assert_almost(float(t["BODY_HALF_H"]), 0.42)
	assert_almost(float(t["GUST_FIRST_SEC"]), 6.0)
	assert_almost(float(t["GUST_EVERY_SEC"]), 10.0)
	assert_almost(float(t["GUST_TELEGRAPH_SEC"]), 1.5)
	assert_almost(float(t["GUST_DURATION_SEC"]), 2.0)
	assert_almost(float(t["GUST_SHIFT_LANES"]), 0.4)
	assert_almost(float(t["COIN_SPAWN_CHANCE"]), 0.32)


func test_autoplay_matches_web_gold() -> void:
	for mode: String in GOLD:
		var want: Array = GOLD[mode]
		for i in want.size():
			var got: int = int(Logic.simulate_autoplay(i + 1, mode)["score"])
			assert_eq(got, int(want[i]), "%s seed %d" % [mode, i + 1])


func test_autoplay_is_deterministic() -> void:
	for mode: String in ["easy", "normal", "hard", "endless"]:
		assert_eq(Logic.simulate_autoplay(12, mode), Logic.simulate_autoplay(12, mode), mode)
		assert_ne(
			int(Logic.simulate_autoplay(1, mode)["score"]),
			int(Logic.simulate_autoplay(2, mode)["score"]),
			mode
		)


func test_difficulty_is_monotone() -> void:
	var means := {}
	for mode: String in ["easy", "normal", "hard"]:
		var sum := 0
		for seed_value in range(1, 21):
			sum += int(Logic.simulate_autoplay(seed_value, mode)["score"])
		means[mode] = float(sum) / 20.0
	assert_true(means["easy"] > means["normal"], "leicht > normal (%s)" % means)
	assert_true(means["normal"] > means["hard"], "normal > schwer (%s)" % means)


func test_bot_scores_are_plausible() -> void:
	var best := 0
	for seed_value in range(1, 21):
		var run: Dictionary = Logic.simulate_autoplay(seed_value, "hard")
		assert_true(int(run["gates"]) >= 48, "Schwer-Bot schafft mindestens 48 Tore")
		assert_true(int(run["score"]) > 0, "Schwer-Bot punktet (seed %d)" % seed_value)
		# Deckel: 2 Punkte je Tor plus höchstens eine Münze je Tor.
		assert_true(int(run["score"]) <= int(run["gates"]) * 3, "Score bleibt im Rahmen")
		best = maxi(best, int(run["score"]))
	assert_true(best >= WEB_TARGET, "bester Schwer-Score %d < Ziel %d" % [best, WEB_TARGET])


func test_endless_starts_windy_and_ends_only_on_crash() -> void:
	var tune: Dictionary = Logic.apply_difficulty(Logic.HOP, "endless")
	assert_true(bool(tune["ENDLESS"]))
	# §G5.4: Endlos bläst ab dem Auftakt, statt 6 s zu warten.
	assert_almost(float(tune["GUST_FIRST_SEC"]), 1.5)
	assert_eq(str(Logic.gust_phase_at(0.0, tune)["phase"]), "telegraph")
	assert_eq(str(Logic.gust_phase_at(2.0, tune)["phase"]), "gust")
	# Endlos kennt keine Uhr — nur der Aufprall beendet: Boden = Kollision.
	var pillar := {"x": 99.0, "gapCenterY": 0.0, "gapHeight": 2.0}
	assert_true(Logic.collides({"x": 0.0, "y": -3.1}, pillar, tune), "Boden beendet den Lauf")
	assert_false(Logic.collides({"x": 0.0, "y": 0.0}, pillar, tune), "freie Bahn lebt weiter")


func test_score_edges() -> void:
	assert_eq(Logic.gate_points(false), 1)
	assert_eq(Logic.gate_points(true), 2, "im Wind zählt ein Tor doppelt")
	assert_eq(Logic.final_hop_score(10), 10)
	var turbo: Dictionary = Logic.HOP.duplicate()
	turbo["SCORE_MULT"] = 1.5
	assert_eq(Logic.final_hop_score(11, turbo), 17, "Turbo rundet genau einmal")
	assert_eq(Logic.final_hop_score(-4), 0, "nie negativ")
	assert_true(Logic.coin_spawns(0.31))
	assert_false(Logic.coin_spawns(0.32), "genau an der Schwelle kommt keine Münze")


func test_speed_and_gap_ramps() -> void:
	assert_almost(Logic.speed_at_gate(0), 1.55)
	assert_almost(Logic.speed_at_gate(10), 1.55 * pow(1.02, 10.0))
	assert_true(Logic.speed_at_gate(30) > Logic.speed_at_gate(20), "Tempo steigt monoton")
	assert_almost(Logic.gap_at_gate(0), 2.15)
	assert_almost(Logic.gap_at_gate(9), 2.15, 1e-9, "erst das 10. Tor verengt")
	assert_almost(Logic.gap_at_gate(10), 1.99)
	assert_almost(Logic.gap_at_gate(500), 1.5, 1e-9, "Lücke hat einen Boden")
	assert_true(Logic.gap_narrows_at_gate(10))
	assert_false(Logic.gap_narrows_at_gate(11))
	assert_false(Logic.gap_narrows_at_gate(500), "am Boden verengt nichts mehr")
	assert_almost(Logic.forgiving_half(0.42), 0.294)


func test_physics_and_gusts() -> void:
	var step: Dictionary = Logic.step_physics({"y": 0.0, "vy": 3.1}, 0.1)
	assert_almost(float(step["vy"]), 3.1 - 0.85)
	assert_almost(float(step["y"]), (3.1 - 0.85) * 0.1)
	# Die Decke klemmt und nimmt den Schwung mit.
	var ceiling: Dictionary = Logic.step_physics({"y": 3.85, "vy": 9.0}, 0.1)
	assert_almost(float(ceiling["y"]), 3.9)
	assert_almost(float(ceiling["vy"]), 0.0)
	# Windfahrplan: erst Vorwarnung, dann Böe, danach Ruhe; Richtung wechselt.
	assert_eq(str(Logic.gust_phase_at(0.0)["phase"]), "none")
	assert_eq(str(Logic.gust_phase_at(4.6)["phase"]), "telegraph")
	assert_eq(str(Logic.gust_phase_at(6.5)["phase"]), "gust")
	assert_eq(str(Logic.gust_phase_at(9.0)["phase"]), "none")
	assert_eq(int(Logic.gust_phase_at(6.5)["direction"]), 1)
	assert_eq(int(Logic.gust_phase_at(16.5)["direction"]), -1)
	# Der Schubs bleibt immer im lebbaren Band.
	assert_almost(Logic.apply_gust_shift(0.0, 1), 0.4)
	assert_true(Logic.apply_gust_shift(-3.0, -1) > -3.1, "nie in den Boden")
	assert_true(Logic.apply_gust_shift(3.8, 1) <= 3.9, "nie durch die Decke")


func test_gap_centers_stay_reachable() -> void:
	var rng := GoobyRng.new(5)
	var prev := 0.0
	for _i in 40:
		var next := Logic.roll_gap_center(rng, 2.15, prev)
		assert_true(next - prev <= 1.4 + 1e-6, "Steigen bleibt schaffbar")
		assert_true(prev - next <= 1.9 + 1e-6, "Sinken bleibt schaffbar")
		assert_true(next > -3.1 and next < 3.9, "Lücke bleibt im Feld")
		prev = next


func test_manifest_matches_web_metadata() -> void:
	var file := FileAccess.open(MANIFEST, FileAccess.READ)
	assert_true(file != null, "game.json fehlt")
	var manifest: Dictionary = JSON.parse_string(file.get_as_text())
	assert_eq(str(manifest["id"]), "bunnyHop")
	assert_eq(int(manifest["target"]), WEB_TARGET)
	assert_eq(str(manifest["orientation"]), "portrait")
	var coins: Dictionary = manifest["coin_table"]
	assert_eq(int(coins["divisor"]), 2)
	assert_eq(int(coins["min"]), 3)
	assert_eq(int(coins["max"]), 25)
	assert_true(ResourceLoader.exists(str(manifest["scene"])), "Szene fehlt")
