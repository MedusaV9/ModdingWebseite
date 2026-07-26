extends TestCase
## FIX-4: RecapEngine — Port-Treue zum Web (systems/recap.js): Snapshot/Diff,
## ≤-12-Zeilen-Auswahl, Meilenstein-Mathematik, atomarer Abschluss (History
## Kappe 8), Beat-Raster (gerade Takte, monotone Cuts).

const NOW := 1700000000000.0
const DAY := 86400000.0


func _state(level := 7) -> Dictionary:
	return {
		"progression": {"level": level, "xp": 0},
		"economy": {"coins": 50, "coinsEarned": 120, "coinsSpent": 30},
		"profile": {"playtimeMin": 10, "distanceM": 500, "photos": 2},
		"minigames": {"plays": {"teaParty": 3, "carrotCatch": 2}},
		"achievements":
		{
			"counters":
			{
				"feeds": 4,
				"washes": 1,
				"sleeps": 2,
				"tickles": 9,
				"trips": 3,
				"harvests": 5,
				"questsDone": 1,
				"deliveries": 0,
				"cures": 0,
				"nougatGlobs": 0,
				"cakesServed": 0,
				"plantings": 2,
				"waterings": 6,
				"surfRuns": 0,
			}
		},
		"stickers": {"unlocked": {"s1": true, "s2": true}},
		"recap": {"history": []},
	}


func test_snapshot_mappt_godot_pfade() -> void:
	var snap := RecapEngine.snapshot(_state(), NOW)
	assert_eq(int(snap["level"]), 7)
	assert_eq(int(snap["coinsEarned"]), 120)
	assert_eq(int(snap["coinsSpent"]), 30)
	assert_eq(int(snap["distanceM"]), 500)
	assert_eq(int(snap["playsTotal"]), 5, "Σ minigames.plays")
	assert_eq(int(snap["stickerCount"]), 2)
	assert_eq(int(snap["tickles"]), 9)
	assert_almost(float(snap["snapshotAtMs"]), NOW)


func test_snapshot_vertraegt_kaputte_eingaben() -> void:
	var snap := RecapEngine.snapshot({}, NOW)
	assert_eq(int(snap["level"]), 1)
	assert_eq(int(snap["playsTotal"]), 0)
	assert_eq(int(snap["feeds"]), 0)


func test_diff_klemmt_negativ_und_zaehlt_tage() -> void:
	var state := _state()
	var baseline := RecapEngine.snapshot(state, NOW)
	baseline["tickles"] = 99.0
	var lines := RecapEngine.diff(baseline, state, NOW + 2.5 * DAY)
	assert_eq(lines.size(), RecapEngine.STAT_CATALOG.size())
	var by_id := {}
	for line: Dictionary in lines:
		by_id[line["id"]] = line
	assert_eq(str((lines[0] as Dictionary)["id"]), "days", "days ist Zeile 1.")
	assert_eq(int(by_id["days"]["value"]), 3, "2,5 Tage → aufgerundet 3.")
	assert_eq(int(by_id["tickles"]["value"]), 0, "Zähler-Reset wird auf 0 geklemmt.")


func test_select_lines_days_zuerst_dann_top_11() -> void:
	var state := _state()
	var lines := RecapEngine.select_lines(RecapEngine.diff({}, state, NOW))
	assert_true(lines.size() <= RecapEngine.MAX_LINES)
	assert_eq(str((lines[0] as Dictionary)["id"]), "days")
	for i in range(1, lines.size()):
		assert_true(int((lines[i] as Dictionary)["value"]) > 0, "Nur Nicht-Null-Zeilen.")
	for i in range(2, lines.size()):
		var a: Dictionary = lines[i - 1]
		var b: Dictionary = lines[i]
		assert_true(
			(
				int(a["weight"]) > int(b["weight"])
				or (int(a["weight"]) == int(b["weight"]) and int(a["value"]) >= int(b["value"]))
			),
			"Sortierung (weight desc, value desc) verletzt bei %s→%s" % [a["id"], b["id"]]
		)


func test_format_line_singular_und_template() -> void:
	assert_eq(RecapEngine.format_line("days", 1), I18nService.t("recap.stat.days_one"))
	assert_eq(RecapEngine.format_line("games", 12), I18nService.t("recap.stat.games", {"n": 12}))
	assert_eq(RecapEngine.format_line("gibtEsNicht", 3), "")


func test_initial_last_recap_level() -> void:
	assert_eq(RecapEngine.initial_last_recap_level(4), 0)
	assert_eq(RecapEngine.initial_last_recap_level(23), 20)
	assert_eq(RecapEngine.initial_last_recap_level(40), 40)
	assert_eq(RecapEngine.initial_last_recap_level(99), 40)


func test_milestone_crossed() -> void:
	assert_eq(RecapEngine.milestone_crossed(4, 5, 0), 5)
	assert_eq(RecapEngine.milestone_crossed(4, 11, 0), 5, "Mehrfach-Sprung queued den NIEDRIGSTEN.")
	assert_eq(RecapEngine.milestone_crossed(23, 24), 0, "Default-last = Retro-Floor von prev.")
	assert_eq(RecapEngine.milestone_crossed(23, 26, 20), 25)
	assert_eq(RecapEngine.milestone_crossed(38, 45, 35), 40)
	assert_eq(RecapEngine.milestone_crossed(40, 45, 40), 0, "Über 40 gibt es nichts mehr.")
	assert_eq(RecapEngine.milestone_crossed(6, 6, 5), 0)


func test_complete_recap_atomar() -> void:
	var state := _state(11)
	state["recap"] = {"history": [], "pendingLevel": 5, "baseline": {}, "baselineAt": 0}
	var result := RecapEngine.complete_recap(state, NOW)
	var recap: Dictionary = result["recap"]
	assert_eq(int(recap["lastRecapLevel"]), 10, "Fold auf den HÖCHSTEN Meilenstein ≤ Level 11.")
	assert_eq(int(recap["pendingLevel"]), 0)
	assert_almost(float(recap["baselineAt"]), NOW)
	assert_eq((recap["history"] as Array).size(), 1)
	var entry: Dictionary = result["entry"]
	assert_eq(int(entry["level"]), 10)
	assert_true((entry["stats"] as Array).size() > 0)
	assert_eq(str(((entry["stats"] as Array)[0] as Dictionary)["id"]), "days")


func test_history_kappe_8() -> void:
	var state := _state()
	var history: Array = []
	for i in 10:
		history.append({"level": 5, "at": float(i), "stats": []})
	state["recap"] = {"history": history}
	var recap: Dictionary = RecapEngine.complete_recap(state, NOW)["recap"]
	assert_eq((recap["history"] as Array).size(), RecapEngine.HISTORY_MAX)
	var letzte: Dictionary = (recap["history"] as Array)[RecapEngine.HISTORY_MAX - 1]
	assert_almost(float(letzte["at"]), NOW, 1.0, "Neueste Zeile bleibt hinten.")


func test_slice_of_ergaenzt_additive_keys() -> void:
	var slice := RecapEngine.slice_of({"recap": {"history": [{"level": 5}]}})
	assert_eq(int(slice["lastRecapLevel"]), 0)
	assert_eq(int(slice["pendingLevel"]), 0)
	assert_eq((slice["history"] as Array).size(), 1, "Vorhandene History bleibt.")


func test_resolve_beats_fallbacks() -> void:
	var grid := RecapEngine.resolve_beats({})
	assert_almost(float(grid["bpm"]), 100.0)
	assert_eq(int(grid["beats_per_bar"]), 4)
	var custom := RecapEngine.resolve_beats({"bpm": 131.0, "offset_sec": 0.39, "beats_per_bar": 4})
	assert_almost(float(custom["bpm"]), 131.0)
	var absurd := RecapEngine.resolve_beats({"bpm": 9999, "offset_sec": -3, "beats_per_bar": 99})
	assert_almost(float(absurd["bpm"]), 100.0)
	assert_almost(float(absurd["offset_sec"]), 0.0)
	assert_eq(int(absurd["beats_per_bar"]), 4)


func test_beat_grid_geruest() -> void:
	var grid := RecapEngine.beat_grid({"bpm": 120.0, "offset_sec": 0.0, "beats_per_bar": 4}, 90.0)
	assert_almost(float(grid["total_sec"]), 90.0)
	var cuts: Array = []
	var end_bar := -1
	var intro_slots := 0
	for cue: Dictionary in grid["cues"]:
		match str(cue["kind"]):
			"cut":
				cuts.append(int(cue["bar"]))
			"end":
				end_bar = int(cue["bar"])
			"text":
				if int(cue.get("vignette", 0)) == -1:
					intro_slots += 1
	assert_eq(cuts.size(), RecapEngine.VIGNETTES, "Genau 8 Vignetten-Cuts.")
	assert_eq(intro_slots, 1, "Genau 1 Intro-Text-Slot (days).")
	assert_true(int(cuts[0]) >= 2, "Intro besitzt Takt 0–1.")
	for i in cuts.size():
		assert_eq(int(cuts[i]) % 2, 0, "Cuts nur auf GERADEN Takten.")
		if i > 0:
			assert_true(int(cuts[i]) >= int(cuts[i - 1]) + 2, "Cuts monoton +≥2.")
	assert_true(end_bar >= int(cuts[cuts.size() - 1]) + 2, "End-Cue nach dem letzten Cut.")


func test_beat_grid_klemmt_laenge() -> void:
	assert_almost(float(RecapEngine.beat_grid({}, 30.0)["total_sec"]), RecapEngine.MIN_LENGTH_SEC)
	assert_almost(float(RecapEngine.beat_grid({}, 500.0)["total_sec"]), RecapEngine.MAX_LENGTH_SEC)
