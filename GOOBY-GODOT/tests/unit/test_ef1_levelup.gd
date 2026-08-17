extends TestCase
## EF-1 (EVAL-1 D8) — Level-Up feiern: MinigameAward liefert das NEUE Level
## im Breakdown, die LevelUpFeier baut Gold-Titel + Bonus-Zeile, und der
## Results-Screen zeigt die Feier nach dem Count-Up (nur bei levelsGained).

const GameStateScript := preload("res://scripts/state/game_state.gd")

const NOW_MS := 1768478400000
const META := {"id": "teaParty", "coin_table": {"divisor": 4, "min": 4, "max": 26}, "target": 40}

var _seq := 0


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://ef1_tests/lvl_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	return gs


func test_award_breakdown_traegt_neues_level() -> void:
	var gs := _fresh_gs()
	var holder: Array[Dictionary] = []
	gs.update(
		func(state: Dictionary) -> void:
			# Kurz vor Level 2 (100 XP nötig, Minigame gibt mindestens 10).
			state["progression"]["xp"] = 95.0
			holder.append(MinigameAward.award(state, META, 60, "normal", "2026-01-15"))
	)
	var breakdown := holder[0]
	assert_true(breakdown.has("level"), "Breakdown trägt das Level für die Feier")
	assert_eq(int(breakdown["levelsGained"]), 1, "Level-Up passiert")
	assert_eq(int(breakdown["level"]), 2, "neues Level = 2")
	assert_eq(
		int(breakdown["level"]),
		int(gs.get_value("progression.level", 1)),
		"Breakdown-Level = persistiertes Level"
	)
	assert_eq(int(breakdown["coinsFromLevels"]), 50, "25 × neues Level Münzen")
	gs.free()


func test_feier_baut_gold_titel_und_bonus_zeile() -> void:
	var host := Control.new()
	tree.root.add_child(host)
	var feier := LevelUpFeier.zeige_in(host, 4, 50)
	await wait_frames(1)
	var texte := _label_texte(feier)
	assert_true(texte.has(I18nService.t("rewards.levelup.titel", {"level": 4})), "%s" % [texte])
	assert_true(
		texte.has(I18nService.t("rewards.levelup.untertitel", {"coins": 50})),
		"Bonus-Zeile nennt die Münzen"
	)
	host.queue_free()
	await wait_frames(1)


func test_results_zeigt_feier_nach_count_up() -> void:
	var results := MinigameResults.new()
	tree.root.add_child(results)
	var breakdown := {
		"score": 50,
		"coins": 8,
		"best": 40,
		"newBest": false,
		"xp": 4,
		"levelsGained": 1,
		"coinsFromLevels": 50,
		"level": 3,
		"firstToday": false,
		"dayCapReached": false,
		"beatTarget": false,
	}
	results.show_results(breakdown, {"title_key": "mg.results.title"})
	assert_true(results.get_node_or_null("LevelUpFeier") == null, "Feier kommt NACH dem Count-Up")
	var ok := await wait_until(
		func() -> bool: return results.get_node_or_null("LevelUpFeier") != null, 5000
	)
	assert_true(ok, "LevelUpFeier erscheint im Results-Screen")
	results.queue_free()
	await wait_frames(1)


func test_results_ohne_levelup_keine_feier() -> void:
	var results := MinigameResults.new()
	tree.root.add_child(results)
	var breakdown := {
		"score": 10,
		"coins": 4,
		"best": 40,
		"newBest": false,
		"xp": 4,
		"levelsGained": 0,
		"coinsFromLevels": 0,
		"level": 1,
		"firstToday": false,
		"dayCapReached": false,
		"beatTarget": false,
	}
	results.show_results(breakdown, {"title_key": "mg.results.title"})
	await wait_frames(3)
	assert_true(results.get_node_or_null("LevelUpFeier") == null, "keine Feier ohne Level-Up")
	results.queue_free()
	await wait_frames(1)


func _label_texte(root: Node) -> Array[String]:
	var out: Array[String] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is Label:
			out.append((node as Label).text)
		for child in node.get_children():
			stack.append(child)
	return out
