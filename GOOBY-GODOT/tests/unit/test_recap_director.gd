extends TestCase
## FIX-4: RecapDirector — Stationen aus dem GameState (erreichte Orte),
## deterministischer Track-Pick, kompletter Cue-Zeitplan (Kontrakt wie im
## Web systems/recapDirector.js).


func test_stationen_default_sind_8_und_starten_zuhause() -> void:
	var stations := RecapDirector.stations_for({})
	assert_eq(stations.size(), RecapEngine.VIGNETTES)
	assert_eq(str((stations[0] as Dictionary)["id"]), "home")
	for station: Dictionary in stations:
		assert_true(
			RecapDirector.STATION_CATALOG.has(station["id"]),
			"Unbekannte Station: %s" % station["id"]
		)
		assert_true(
			I18nService.table("de").has(str(station["label_key"])),
			"DE-Label fehlt: %s" % station["label_key"]
		)
		assert_true(
			I18nService.table("en").has(str(station["label_key"])),
			"EN-Label fehlt: %s" % station["label_key"]
		)


func test_stationen_aus_der_history_des_states() -> void:
	var state := {
		"achievements":
		{"counters": {"trips": 2, "harvests": 3, "sleeps": 4, "feeds": 1, "washes": 1}},
		"minigames": {"plays": {"teaParty": 1}},
		"park": {"visits": 1},
		"vacation": {"phase": "none", "tripsDone": 1},
	}
	var stations := RecapDirector.stations_for(state)
	assert_eq(stations.size(), RecapEngine.VIGNETTES)
	var ids: Array = []
	for station: Dictionary in stations:
		ids.append(str(station["id"]))
	assert_true(ids.has("city"), "trips>0 → Stadt-Station.")
	assert_true(ids.has("garden"), "harvests>0 → Garten-Station.")
	assert_true(ids.has("arcade"), "plays → Arcade-Station.")
	assert_eq(ids[ids.size() - 1], "night", "sleeps>0 → Gute-Nacht-Finale.")


func test_pick_track_deterministisch() -> void:
	var track_ids := MusicRegistry.station_track_ids("recap-fm")
	var first := RecapDirector.pick_track(track_ids, 12345)
	assert_eq(RecapDirector.pick_track(track_ids, 12345), first, "Gleicher Seed, gleiche Wahl.")
	assert_true(track_ids.has(first), "Pick muss aus der Liste kommen.")
	assert_eq(RecapDirector.pick_track([], 1), "", "Leere Liste → leer.")


func test_build_timeline_kontrakt() -> void:
	var lines := [
		{"id": "days", "value": 3, "weight": 999},
		{"id": "games", "value": 5, "weight": 10},
		{"id": "coinsEarned", "value": 120, "weight": 9},
		{"id": "feeds", "value": 4, "weight": 8},
	]
	var timeline := (
		RecapDirector
		. build_timeline(
			{
				"beats": {"bpm": 120.0, "offset_sec": 0.0, "beats_per_bar": 4},
				"duration_sec": 90.0,
				"lines": lines,
				"stations": RecapDirector.stations_for({}),
				"level": 10,
				"track_id": "recap-abenteuer",
			}
		)
	)
	assert_eq(int(timeline["v"]), 1)
	assert_eq(int(timeline["level"]), 10)
	assert_eq(str(timeline["track_id"]), "recap-abenteuer")
	assert_almost(float(timeline["skip_after_sec"]), RecapEngine.SKIP_AFTER_SEC)
	var cues: Array = timeline["cues"]
	assert_eq(str((cues[0] as Dictionary)["kind"]), "intro", "Intro ist Cue 0 (t=0).")
	var cut_count := 0
	var text_cues: Array = []
	var prev_t := -1.0
	for cue: Dictionary in cues:
		assert_true(float(cue["t"]) >= prev_t, "Cues nach t sortiert.")
		prev_t = float(cue["t"])
		match str(cue["kind"]):
			"cut":
				cut_count += 1
				assert_true((cue["station"] as Dictionary).has("label_key"))
			"text":
				text_cues.append(cue)
	assert_eq(cut_count, RecapEngine.VIGNETTES)
	assert_eq(text_cues.size(), lines.size(), "Jede Zeile bekommt einen Slot.")
	var intro_text: Dictionary = text_cues[0]
	assert_eq(str(intro_text["line_id"]), "days", "days-Zeile liegt auf dem Intro-Slot.")
	assert_eq(int(intro_text["vignette"]), -1)
	for cue: Dictionary in text_cues:
		assert_false(str(cue["text"]).is_empty(), "Text-Cue trägt den fertigen String.")
	var end_card: Dictionary = timeline["end_card"]
	assert_almost(float(end_card["min_show_sec"]), RecapEngine.END_CARD_MIN_SEC)
	assert_true(float(end_card["t"]) > 0.0)


func test_build_timeline_deterministisch() -> void:
	var opts := {
		"beats": {"bpm": 94.3, "offset_sec": 0.13, "beats_per_bar": 4},
		"duration_sec": 83.4,
		"lines": [{"id": "days", "value": 1, "weight": 999}],
		"level": 5,
		"track_id": "recap-bonus-stage-blitz",
	}
	var a := RecapDirector.build_timeline(opts)
	var b := RecapDirector.build_timeline(opts)
	assert_eq(JSON.stringify(a), JSON.stringify(b), "Gleiche Eingaben → identischer Zeitplan.")


func test_zeilen_ueberlauf_wird_verworfen() -> void:
	var lines: Array = [{"id": "days", "value": 1, "weight": 999}]
	for row: Dictionary in RecapEngine.STAT_CATALOG:
		if str(row["id"]) != "days":
			lines.append({"id": row["id"], "value": 7, "weight": row["weight"]})
	var timeline := (
		RecapDirector
		. build_timeline(
			{
				"beats": {"bpm": 60.0, "offset_sec": 0.0, "beats_per_bar": 4},
				"duration_sec": 60.0,
				"lines": lines,
				"level": 5,
			}
		)
	)
	var text_count := 0
	for cue: Dictionary in timeline["cues"]:
		if str(cue["kind"]) == "text":
			text_count += 1
	assert_true(text_count <= RecapEngine.MAX_LINES, "Mehr Zeilen als Slots → verworfen.")
