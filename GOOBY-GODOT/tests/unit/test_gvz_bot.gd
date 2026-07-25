extends TestCase
## GvZ-Bot-Zertifizierung (W3b, Kurve nachgezogen in W4-P1): der Heuristik-
## Autoplayer BEWEIST die Spielbarkeit (Doc G §4.7). Ziel-Kurve Plan §2.4:
## L1–L3 locker (voller Sieg ohne Panik-Gooby), Mittelfeld fordernd,
## L15 knapp-machbar — Bot-Winrate NIE unter 60 %. Volle 15×10-Telemetrie:
## tests/unit/gvz_telemetry.gd (GVZ_ONLY/GVZ_SEEDS-Env für Feintuning).


func test_bot_cruises_levels_1_to_3() -> void:
	# "Locker" heißt beweisbar: Sieg UND kein einziger Panik-Gooby verbraucht.
	var balance := GvzData.load_balance(null)
	var levels := GvzData.load_levels()
	for id in [1, 2, 3]:
		var level := GvzData.level_by_id(levels, id)
		for seed_value in [1, 2, 3]:
			var result := GvzBot.simulate(level, balance, seed_value, "normal")
			assert_true(
				bool(result["won"]),
				(
					"L%d seed=%d verloren (%s @%d)"
					% [id, seed_value, result["outcome"], result["ticks"]]
				)
			)
			assert_eq(int(result["mowers_used"]), 0, "L%d seed=%d nicht locker" % [id, seed_value])
			assert_true(int(result["kills"]) > 0, "L%d ohne Kills?" % id)
			assert_eq(
				int(result["stars"]),
				GvzProgress.stars_for(int(result["mowers_used"])),
				"Sterne-Mapping"
			)


func test_bot_survives_midgame_pressure() -> void:
	# Fordernd, aber machbar: die nachgezogenen Level L8/L12/L13 bleiben
	# Bot-gewinnbar (L13 ist der bewusste Vor-Boss-Gipfel der Kampagne).
	var balance := GvzData.load_balance(null)
	var levels := GvzData.load_levels()
	for id in [8, 12, 13]:
		var level := GvzData.level_by_id(levels, id)
		var result := GvzBot.simulate(level, balance, 1, "normal")
		assert_true(
			bool(result["won"]), "L%d verloren (%s @%d)" % [id, result["outcome"], result["ticks"]]
		)


func test_bot_beats_boss_knurps_at_least_60_percent() -> void:
	# Knapp-machbar: 9000-hp-Knurps darf einzelne Seeds gewinnen, aber die
	# Bot-Winrate über 5 Seeds bleibt >= 60 % (Plan §2.4-Regel).
	var balance := GvzData.load_balance(null)
	var level := GvzData.level_by_id(GvzData.load_levels(), 15)
	var wins := 0
	var won_with_stars := false
	for seed_value in [1, 2, 3, 4, 5]:
		var result := GvzBot.simulate(level, balance, seed_value, "normal")
		if bool(result["won"]):
			wins += 1
			won_with_stars = won_with_stars or int(result["stars"]) >= 1
	assert_true(wins >= 3, "Boss-Winrate unter 60%% (%d/5)" % wins)
	assert_true(won_with_stars, "Sieg gibt Sterne")


func test_bot_simulation_is_deterministic() -> void:
	var balance := GvzData.load_balance(null)
	var level := GvzData.level_by_id(GvzData.load_levels(), 2)
	var one := GvzBot.simulate(level, balance, 42, "normal")
	var two := GvzBot.simulate(level, balance, 42, "normal")
	assert_eq(one, two, "gleicher Seed = identisches Ergebnis")
	var hard := GvzBot.simulate(level, balance, 42, "hard")
	assert_true(int(hard["ticks"]) != int(one["ticks"]) or hard["won"] != one["won"], "hard wirkt")
