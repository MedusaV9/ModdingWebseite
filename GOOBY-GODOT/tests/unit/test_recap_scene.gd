extends TestCase
## FIX-4: RecapScene + RecapService — das Rückblick-Kino läuft headless
## komplett durch (Stationen, Statzeilen, Endkarte), schreibt den atomaren
## Abschluss in den State (History + pendingLevel=0 + recapsSeen), ist ab
## 10 s überspringbar, und der pendingLevel-Handshake queued Meilensteine.

const SceneScript := preload("res://scripts/recap/recap_scene.gd")
const ServiceScript := preload("res://scripts/recap/recap_service.gd")


## GameState-Attrappe: nur state() + update() (Duck-Typing wie im Spiel).
class FakeGameState:
	extends RefCounted
	var s: Dictionary

	func _init(state: Dictionary) -> void:
		s = state

	func state() -> Dictionary:
		return s

	func update(mutator: Callable) -> void:
		mutator.call(s)


func _spiel_state(level := 11, pending := 5) -> Dictionary:
	return {
		"progression": {"level": level, "xp": 0},
		"economy": {"coins": 10, "coinsEarned": 80, "coinsSpent": 20},
		"profile": {"playtimeMin": 5, "distanceM": 120, "photos": 1},
		"minigames": {"plays": {"teaParty": 2}},
		"achievements":
		{"counters": {"feeds": 3, "tickles": 5, "trips": 1, "sleeps": 2, "harvests": 1}},
		"stickers": {"unlocked": {"a": true}},
		"park": {"visits": 0},
		"vacation": {"phase": "none"},
		"recap":
		{
			"history": [],
			"lastRecapLevel": 0,
			"baseline": {},
			"baselineAt": 0.0,
			"pendingLevel": pending
		},
	}


func test_build_liefert_timeline_mit_stationen_und_musik() -> void:
	var gs := FakeGameState.new(_spiel_state())
	var scene: Control = SceneScript.build(gs)
	var timeline: Dictionary = scene.timeline()
	assert_eq(int(timeline["level"]), 5, "pendingLevel 5 wird gespielt.")
	assert_true(
		MusicRegistry.station_track_ids("recap-fm").has(str(timeline["track_id"])),
		"Musik kommt aus Recap-FM."
	)
	var cut_count := 0
	for cue: Dictionary in timeline["cues"]:
		if str(cue["kind"]) == "cut":
			cut_count += 1
	assert_eq(cut_count, RecapEngine.VIGNETTES, "8 Stations-Kamerafahrten.")
	assert_true(float(timeline["total_sec"]) >= RecapEngine.MIN_LENGTH_SEC)
	scene.free()


func test_recap_laeuft_headless_durch_und_schreibt_abschluss() -> void:
	var gs := FakeGameState.new(_spiel_state())
	var scene: Control = SceneScript.build(gs)
	scene.time_scale = 60.0
	var result: Array = []
	scene.finished.connect(func(skipped: bool) -> void: result.append(skipped))
	tree.root.add_child(scene)
	var ok := await wait_until(func() -> bool: return result.size() == 1, 30000)
	assert_true(ok, "Recap muss durchlaufen (finished feuern).")
	if ok:
		assert_false(bool(result[0]), "Volllauf ist kein Skip.")
	var recap := RecapEngine.slice_of(gs.state())
	assert_eq(int(recap["pendingLevel"]), 0, "Abschluss löscht pendingLevel.")
	assert_eq((recap["history"] as Array).size(), 1, "Eine History-Zeile.")
	assert_eq(int(recap["lastRecapLevel"]), 10, "Fold auf höchsten Meilenstein ≤ 11.")
	var counters: Dictionary = gs.state()["achievements"]["counters"]
	assert_eq(int(counters.get("recapsSeen", 0)), 1)
	await wait_frames(2)


func test_recap_ist_ab_10s_ueberspringbar() -> void:
	var gs := FakeGameState.new(_spiel_state())
	var scene: Variant = SceneScript.build(gs)
	scene.time_scale = 40.0
	var result: Array = []
	scene.finished.connect(func(skipped: bool) -> void: result.append(skipped))
	tree.root.add_child(scene)
	scene.skip()
	assert_eq(result.size(), 0, "Vor skip_after_sec passiert beim Tippen nichts.")
	# Schleife statt wait_until-Lambda (REST5, EVAL-2 B2): die Poll-Lambda
	# capturte `scene` — nach deren queue_free loggt JEDER weitere Aufruf
	# "Lambda capture at index 1 was freed" (auch wenn der Codepfad die
	# Szene gar nicht anfasst).
	var deadline := Time.get_ticks_msec() + 30000
	var armed := false
	while Time.get_ticks_msec() < deadline:
		if result.size() == 1:
			armed = true
			break
		if is_instance_valid(scene):
			scene.skip()
		await tree.process_frame
	assert_true(armed, "Skip nach 10 s muss zur Endkarte schneiden und enden.")
	if armed:
		assert_true(bool(result[0]), "Skip endet als skipped=true.")
	var recap := RecapEngine.slice_of(gs.state())
	assert_eq(
		(recap["history"] as Array).size(),
		1,
		"Auch der Skip schreibt den atomaren Abschluss (Web §B5.2)."
	)
	await wait_frames(2)


func test_replay_schreibt_nichts() -> void:
	var state := _spiel_state()
	var row := {"level": 5, "at": 123.0, "stats": [{"id": "days", "value": 2}]}
	(state["recap"]["history"] as Array).append(row)
	var gs := FakeGameState.new(state)
	var scene: Variant = ServiceScript.replay(tree.root, gs, row)
	scene.time_scale = 60.0
	var result: Array = []
	scene.finished.connect(func(skipped: bool) -> void: result.append(skipped))
	var ok := await wait_until(func() -> bool: return result.size() == 1, 30000)
	assert_true(ok, "Replay muss durchlaufen.")
	assert_eq(
		(RecapEngine.slice_of(gs.state())["history"] as Array).size(),
		1,
		"Replay hängt KEINE neue History-Zeile an."
	)
	assert_eq(int(RecapEngine.slice_of(gs.state())["pendingLevel"]), 5, "pending bleibt.")
	await wait_frames(2)


func test_service_queued_meilensteine() -> void:
	var gs := FakeGameState.new(_spiel_state(4, 0))
	assert_eq(ServiceScript.queue_if_milestone(gs, 4, 5), 5)
	assert_eq(ServiceScript.pending_level(gs), 5)
	gs.state()["progression"]["level"] = 11
	assert_eq(
		ServiceScript.queue_if_milestone(gs, 5, 11), 5, "Niedrigerer gequeueter Meilenstein bleibt."
	)
	assert_eq(ServiceScript.pending_level(gs), 5)
	# Meilenstein 5 schon gesehen → 6→7 queued nichts (erst Level 10 wieder).
	var kein_state := _spiel_state(6, 0)
	kein_state["recap"]["lastRecapLevel"] = 5
	var kein := FakeGameState.new(kein_state)
	assert_eq(ServiceScript.queue_if_milestone(kein, 6, 7), 0)
	assert_eq(ServiceScript.pending_level(kein), 0)


func test_service_history_neueste_zuerst() -> void:
	var state := _spiel_state()
	(state["recap"]["history"] as Array).append({"level": 5, "at": 1.0, "stats": []})
	(state["recap"]["history"] as Array).append({"level": 10, "at": 2.0, "stats": []})
	var gs := FakeGameState.new(state)
	var rows := ServiceScript.history(gs)
	assert_eq(rows.size(), 2)
	assert_eq(int((rows[0] as Dictionary)["level"]), 10, "Neueste zuerst.")
