extends TestCase
## GvZ-Bot-Zertifizierung (W3b): der Heuristik-Autoplayer BEWEIST die
## Spielbarkeit — L1–L3 mit Standard-Balance über mehrere Seeds (Doc G §4.7)
## plus Boss-Finale L15. Volle 15×10-Zertifizierung läuft separat
## (tests/tmp_gvz_smoke_notest.gd), hier bleibt die Laufzeit im Rahmen.


func test_bot_survives_levels_1_to_3() -> void:
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
			assert_true(int(result["kills"]) > 0, "L%d ohne Kills?" % id)
			assert_eq(
				int(result["stars"]),
				GvzProgress.stars_for(int(result["mowers_used"])),
				"Sterne-Mapping"
			)


func test_bot_beats_boss_knurps() -> void:
	var balance := GvzData.load_balance(null)
	var level := GvzData.level_by_id(GvzData.load_levels(), 15)
	var result := GvzBot.simulate(level, balance, 1, "normal")
	assert_true(
		bool(result["won"]), "Boss-Finale verloren (%s @%d)" % [result["outcome"], result["ticks"]]
	)
	assert_true(int(result["stars"]) >= 1, "Sieg gibt Sterne")


func test_bot_simulation_is_deterministic() -> void:
	var balance := GvzData.load_balance(null)
	var level := GvzData.level_by_id(GvzData.load_levels(), 2)
	var one := GvzBot.simulate(level, balance, 42, "normal")
	var two := GvzBot.simulate(level, balance, 42, "normal")
	assert_eq(one, two, "gleicher Seed = identisches Ergebnis")
	var hard := GvzBot.simulate(level, balance, 42, "hard")
	assert_true(int(hard["ticks"]) != int(one["ticks"]) or hard["won"] != one["won"], "hard wirkt")
