extends TestCase
## GOB-NOM-Level-Daten (Doc G §5.3/§5.4): alle 15 Kampagnen- + 10 Coop-Level
## laden + validieren, Element-Einführungs-Kurve nach der Doc-Tabelle, und —
## der Kern — der maschinelle LÖSBARKEITS-BEWEIS: der Auto-Solver gewinnt
## JEDES der 25 Level über den eingebetteten Lösungs-Plan (full_clear-Level
## sammeln dabei alle 3 Gläser, Coop-Läufe ohne einzige verweigerte Aktion).

const SOLVER_SEED := 1


func _balance() -> Dictionary:
	return GobnomData.load_balance(null)


func test_levels_load_and_validate() -> void:
	var campaign := GobnomData.load_campaign()
	var coop := GobnomData.load_coop()
	assert_eq(campaign.size(), 15, "genau 15 Kampagnen-Level")
	assert_eq(coop.size(), 10, "genau 10 Coop-Level")
	var errors := GobnomData.validate_levels(campaign, coop, _balance())
	assert_eq(errors.size(), 0, "Validierung: %s" % "; ".join(errors))


func test_campaign_intro_curve_matches_doc() -> void:
	var campaign := GobnomData.load_campaign()
	for level: Dictionary in campaign:
		var id := int(level["id"])
		assert_eq(
			str(level.get("intro", "")),
			str(GobnomData.CAMPAIGN_INTRO.get(id, "")),
			"L%d führt das Element laut Doc-G-Tabelle ein" % id
		)


func test_all_campaign_levels_solvable() -> void:
	var balance := _balance()
	for level: Dictionary in GobnomData.load_campaign():
		var id := int(level["id"])
		var result := GobnomSolver.run_solution(level, balance, SOLVER_SEED)
		assert_true(bool(result["won"]), "L%02d lösbar (outcome=%s)" % [id, result["outcome"]])
		if bool((level.get("solution", {}) as Dictionary).get("full_clear", false)):
			assert_eq(int(result["jars"]), 3, "L%02d sammelt alle Gläser" % id)


func test_all_coop_levels_solvable_without_denials() -> void:
	var balance := _balance()
	for level: Dictionary in GobnomData.load_coop():
		var id := int(level["id"])
		var result := GobnomSolver.run_solution(level, balance, SOLVER_SEED)
		assert_true(bool(result["won"]), "CN%d lösbar (outcome=%s)" % [id, result["outcome"]])
		assert_eq(int(result["denied"]), 0, "CN%d: Plan respektiert die Ownership" % id)
		if bool((level.get("solution", {}) as Dictionary).get("full_clear", false)):
			assert_eq(int(result["jars"]), 3, "CN%d sammelt alle Gläser" % id)


func test_coop_solutions_need_both_players() -> void:
	for level: Dictionary in GobnomData.load_coop():
		var players := {}
		for action: Dictionary in level.get("solution", {}).get("actions", []):
			players[str(action.get("player", ""))] = true
		assert_true(
			players.has("a") and players.has("b"),
			"CN%d: beide Spieler tragen zur Lösung bei" % int(level["id"])
		)


func test_coop_swapped_players_get_denied() -> void:
	# Gegenprobe zum Ownership-Beweis: CN1 mit VERTAUSCHTEN Spielern muss
	# verweigerte Aktionen produzieren (und gewinnt nicht).
	var level: Dictionary = (GobnomData.load_coop()[0] as Dictionary).duplicate(true)
	for action: Dictionary in level["solution"]["actions"]:
		action["player"] = "b" if str(action["player"]) == "a" else "a"
	var result := GobnomSolver.run_solution(level, _balance(), SOLVER_SEED)
	assert_true(int(result["denied"]) > 0, "vertauschte Spieler werden verweigert")
	assert_false(bool(result["won"]), "und der Lauf gewinnt so nicht")


func test_solver_runs_are_deterministic() -> void:
	var balance := _balance()
	var level: Dictionary = GobnomData.load_campaign()[10]
	var first := GobnomSolver.run_solution(level, balance, SOLVER_SEED)
	var second := GobnomSolver.run_solution(level, balance, SOLVER_SEED)
	assert_eq(first, second, "Solver-Replays sind bit-identisch")


func test_greedy_fallback_solves_level_one() -> void:
	var level: Dictionary = GobnomData.load_campaign()[0]
	var result := GobnomSolver.run_greedy(level, _balance(), SOLVER_SEED)
	assert_true(bool(result["won"]), "L1 fällt auch ohne Plan (Greedy) in den Mund")


func test_every_level_stays_in_world_bounds() -> void:
	var world: Dictionary = _balance().get("world", {})
	var w := float(world.get("w", 960.0))
	var h := float(world.get("h", 540.0))
	for track: Array in [GobnomData.load_campaign(), GobnomData.load_coop()]:
		for level: Dictionary in track:
			for key in ["candy", "mouth"]:
				var row: Dictionary = level.get(key, {})
				var x := float(row.get("x", -1.0))
				var y := float(row.get("y", -1.0))
				assert_true(
					x >= 0.0 and x <= w and y >= 0.0 and y <= h,
					"%s in L%d liegt in der Welt" % [key, int(level["id"])]
				)
