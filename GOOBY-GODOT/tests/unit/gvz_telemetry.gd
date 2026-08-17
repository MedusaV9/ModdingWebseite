extends SceneTree
## GvZ-Balance-Telemetrie (KEIN Test — kein test_-Präfix): fährt den
## deterministischen GvzBot über die komplette Kampagne (15 Level × Seeds)
## und druckt die Kurven-Tabelle (Winrate, Restleben = ungenutzte Panik-
## Goobys, Dauer, Score). Grundlage jedes Balance-Passes (Doc G §4.7 /
## Plan §2.4 Ziel 9). Aufruf:
##   godot --headless --path . --script res://tests/unit/gvz_telemetry.gd
## Env-Schalter: GVZ_SEEDS (Default 10), GVZ_DIFF (normal),
## GVZ_ONLY ("13,15" = nur diese Level — schnelles Feintuning).

const DEFAULT_SEEDS := 10


func _init() -> void:
	var seeds := DEFAULT_SEEDS
	var env_seeds := OS.get_environment("GVZ_SEEDS")
	if env_seeds.is_valid_int():
		seeds = maxi(1, int(env_seeds))
	var difficulty := OS.get_environment("GVZ_DIFF")
	if difficulty == "":
		difficulty = "normal"
	var only: Array[int] = []
	for part in OS.get_environment("GVZ_ONLY").split(",", false):
		if part.strip_edges().is_valid_int():
			only.append(int(part.strip_edges()))
	_run(seeds, difficulty, only)
	quit(0)


func _run(seeds: int, difficulty: String, only: Array[int]) -> void:
	var balance := GvzData.load_balance(null)
	var levels := GvzData.load_levels()
	print("GvZ-Telemetrie: %d Seeds pro Level, difficulty=%s" % [seeds, difficulty])
	print(
		(
			"| Level | Reihen | Winrate | Restleben Ø | Restleben min "
			+ "| Ticks Ø (Siege) | Score Ø | Lose-Seeds |"
		)
	)
	print("|---|---|---|---|---|---|---|---|")
	var total_wins := 0
	var total_runs := 0
	for id in range(1, 16):
		if not only.is_empty() and not only.has(id):
			continue
		var level := GvzData.level_by_id(levels, id)
		var lanes := (level.get("lanes", []) as Array).size()
		var wins := 0
		var rest_sum := 0
		var rest_min := 99
		var ticks_sum := 0
		var score_sum := 0
		var lost_seeds: Array[int] = []
		for seed_value in range(1, seeds + 1):
			var result := GvzBot.simulate(level, balance, seed_value, difficulty)
			var rest := lanes - int(result["mowers_used"])
			if bool(result["won"]):
				wins += 1
				rest_sum += rest
				rest_min = mini(rest_min, rest)
				ticks_sum += int(result["ticks"])
				score_sum += int(result["score"])
			else:
				lost_seeds.append(seed_value)
		total_wins += wins
		total_runs += seeds
		var avg_rest := "%.1f" % (float(rest_sum) / wins) if wins > 0 else "-"
		var min_rest := str(rest_min) if wins > 0 else "-"
		var avg_ticks := str(ticks_sum / wins) if wins > 0 else "-"
		var avg_score := str(score_sum / wins) if wins > 0 else "-"
		print(
			(
				"| L%02d | %d | %d%% | %s | %s | %s | %s | %s |"
				% [
					id,
					lanes,
					wins * 100 / seeds,
					avg_rest,
					min_rest,
					avg_ticks,
					avg_score,
					lost_seeds
				]
			)
		)
	print(
		(
			"Gesamt: %d/%d Siege (%d%%)"
			% [total_wins, total_runs, total_wins * 100 / maxi(1, total_runs)]
		)
	)
