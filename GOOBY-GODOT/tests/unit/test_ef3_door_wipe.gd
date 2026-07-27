extends TestCase
## EF-3 F1 (EVAL-1: „jede Haustür = 1 s Schwarzblende“): DOOR_TRAVEL nutzt
## den kurzen Tür-Wisch statt des Vollveils — Mindestanzeige 0, Wisch-Blende
## unter dem 350-ms-Budget, keine Panel-Klänge (F9), und der volle
## Ladebildschirm bleibt exklusiv den langen VEIL-Reisen (RW-8-Regeln).

const ROUTER_SCRIPT := preload("res://scripts/core/scene_router.gd")
const VEIL_SCENE := preload("res://scripts/core/loading_veil.tscn")

const ROOM_A := "res://tests/fixtures/room_a.tscn"
const ROOM_B := "res://tests/fixtures/room_b.tscn"


func test_wisch_blende_unter_budget() -> void:
	# Das sichtbare Wisch-Paar (rein + raus) bleibt unter 350 ms.
	assert_true(
		LoadingVeil.DOOR_COVER_DURATION + LoadingVeil.DOOR_REVEAL_DURATION <= 0.35,
		(
			"Tür-Wisch über Budget: %.2f s"
			% (LoadingVeil.DOOR_COVER_DURATION + LoadingVeil.DOOR_REVEAL_DURATION)
		)
	)
	# Der Vollveil behält seinen W1a-Wert (Ehrlichkeits-Contract RW-8).
	var router: Node = ROUTER_SCRIPT.new()
	assert_eq(int(router.min_shown_ms), 600, "VEIL-Mindestanzeige bleibt 600 ms.")
	assert_eq(int(router.door_min_shown_ms), 0, "DOOR-Mindestanzeige ist 0.")
	router.free()


func test_door_travel_deutlich_schneller_als_veil_travel() -> void:
	var ctx := await _make_router_with_real_veil()
	var router: Node = ctx["router"]
	var finished: Array = []
	router.travel_finished.connect(func(target: StringName) -> void: finished.append(target))

	# Aufwärmen (erste Reise lädt die Fixture-Szene).
	router.goto(&"room_a", {}, ROUTER_SCRIPT.TravelType.DOOR_TRAVEL)
	await wait_until(func() -> bool: return finished.size() == 1, 10_000)

	var t_door := Time.get_ticks_msec()
	router.goto(&"room_b", {}, ROUTER_SCRIPT.TravelType.DOOR_TRAVEL)
	await wait_until(func() -> bool: return finished.size() == 2, 10_000)
	var door_ms := Time.get_ticks_msec() - t_door

	var t_veil := Time.get_ticks_msec()
	router.goto(&"room_a", {}, ROUTER_SCRIPT.TravelType.VEIL_TRAVEL)
	await wait_until(func() -> bool: return finished.size() == 3, 10_000)
	var veil_ms := Time.get_ticks_msec() - t_veil

	assert_true(
		door_ms < 700, "Türwechsel über Zeitbudget: %d ms (Ziel deutlich unter 700)" % door_ms
	)
	assert_true(veil_ms >= 600, "VEIL-Reise unterschreitet min_shown_ms: %d ms" % veil_ms)
	assert_true(
		door_ms < veil_ms - 200,
		"Tür (%d ms) muss klar schneller sein als Vollveil (%d ms)." % [door_ms, veil_ms]
	)
	await _cleanup(ctx)


func test_door_travel_zeigt_wisch_statt_vollveil() -> void:
	var ctx := await _make_router_with_real_veil()
	var router: Node = ctx["router"]
	var veil: LoadingVeil = ctx["veil"]
	var root_sichtbar_im_cover: Array = []
	var wipe_da_im_cover: Array = []
	veil.covered.connect(
		func() -> void:
			root_sichtbar_im_cover.append((veil.get_node("Root") as Control).visible)
			var wipe: Control = veil.get_node_or_null("DoorWipe")
			wipe_da_im_cover.append(wipe != null and wipe.visible)
	)
	var finished: Array = []
	router.travel_finished.connect(func(target: StringName) -> void: finished.append(target))
	router.goto(&"room_a", {}, ROUTER_SCRIPT.TravelType.DOOR_TRAVEL)
	await wait_until(func() -> bool: return finished.size() == 1, 10_000)
	assert_eq(root_sichtbar_im_cover, [false] as Array, "Kein Vollveil (Root bleibt aus).")
	assert_eq(wipe_da_im_cover, [true] as Array, "Der Tür-Wisch deckt ab.")
	assert_false(veil.visible, "Veil nach der Reise wieder unsichtbar.")
	assert_true(
		(veil.get_node("Root") as Control).visible,
		"Root ist für die nächste VEIL-Reise wiederhergestellt."
	)
	await _cleanup(ctx)


func test_door_reise_spielt_keine_panel_klaenge() -> void:
	var audio := tree.root.get_node_or_null("/root/Audio")
	if audio == null:
		return
	var ctx := await _make_router_with_real_veil()
	var router: Node = ctx["router"]
	var finished: Array = []
	router.travel_finished.connect(func(target: StringName) -> void: finished.append(target))
	var played: Dictionary = audio.get("_last_played_msec")
	var close_vorher := int(played.get("ui_close", -1))
	var open_vorher := int(played.get("ui_open", -1))
	router.goto(&"room_a", {}, ROUTER_SCRIPT.TravelType.DOOR_TRAVEL)
	await wait_until(func() -> bool: return finished.size() == 1, 10_000)
	played = audio.get("_last_played_msec")
	assert_eq(int(played.get("ui_close", -1)), close_vorher, "F9: Tür-Reise spielt kein ui_close.")
	assert_eq(int(played.get("ui_open", -1)), open_vorher, "F9: Tür-Reise spielt kein ui_open.")
	# VEIL-Reisen bekommen stattdessen ihr eigenes Whoosh-Paar (F9).
	router.goto(&"room_b", {}, ROUTER_SCRIPT.TravelType.VEIL_TRAVEL)
	await wait_until(func() -> bool: return finished.size() == 2, 10_000)
	played = audio.get("_last_played_msec")
	assert_true(played.has("travel_whoosh_zu"), "F9: VEIL-Reise whoosht beim Abdecken.")
	assert_true(played.has("travel_whoosh_auf"), "F9: VEIL-Reise whoosht beim Freigeben.")
	assert_eq(int(played.get("ui_close", -1)), close_vorher, "F9: auch VEIL ohne ui_close.")
	assert_eq(int(played.get("ui_open", -1)), open_vorher, "F9: auch VEIL ohne ui_open.")
	await _cleanup(ctx)


func test_reduced_motion_tuer_ist_instantan_und_signalisiert() -> void:
	var veil: LoadingVeil = VEIL_SCENE.instantiate()
	tree.root.add_child(veil)
	await wait_frames(1)
	var events: Array = []
	veil.covered.connect(func() -> void: events.append("covered"))
	veil.revealed.connect(func() -> void: events.append("revealed"))
	veil.prepare_for_travel(&"room_a", LoadingScreenRules.DOOR_TRAVEL)
	await veil.cover(true)
	assert_true(veil.visible, "Wisch deckt (reduced motion) sofort.")
	await veil.reveal(true)
	assert_false(veil.visible, "Wisch gibt sofort wieder frei.")
	assert_eq(events, ["covered", "revealed"] as Array, "Signal-Contract bleibt.")
	veil.queue_free()
	await wait_frames(1)


func test_ladebildschirm_nur_bei_langen_veil_wegen() -> void:
	var veil: LoadingVeil = VEIL_SCENE.instantiate()
	tree.root.add_child(veil)
	await wait_frames(1)
	# Kurzer Hausweg als DOOR: Wisch an, kein Ranch-Vollbild.
	veil.prepare_for_travel(&"home/kitchen", LoadingScreenRules.DOOR_TRAVEL)
	assert_true(bool(veil.get("_door_aktiv")), "Hausweg per Tür = Wisch-Modus.")
	assert_false(bool(veil.get("_ranch_aktiv")), "Hausweg bekommt keinen Vollbild-Schirm.")
	# Selbst ein Ranch-Ziel per DOOR bekommt NIE den vollen Schirm (RW-8).
	veil.prepare_for_travel(&"ranch/hof", LoadingScreenRules.DOOR_TRAVEL)
	assert_true(bool(veil.get("_door_aktiv")), "DOOR bleibt Wisch, auch Richtung Ranch.")
	assert_false(bool(veil.get("_ranch_aktiv")), "DOOR_TRAVEL nie Vollbild (RW-8).")
	# Lange VEIL-Reise: Vollbild-Schirm an, Wisch aus.
	veil.prepare_for_travel(&"ranch/hof", 0)
	assert_false(bool(veil.get("_door_aktiv")), "VEIL-Reise nutzt keinen Wisch.")
	assert_true(bool(veil.get("_ranch_aktiv")), "Lange Reise behält den Ladebildschirm.")
	veil.queue_free()
	await wait_frames(1)


func _make_router_with_real_veil() -> Dictionary:
	var router: Node = ROUTER_SCRIPT.new()
	var mount := Node.new()
	tree.root.add_child(mount)
	tree.root.add_child(router)
	await wait_frames(1)
	router.set_mount_point(mount)
	router.register_route(&"room_a", ROOM_A)
	router.register_route(&"room_b", ROOM_B)
	var veil: LoadingVeil = null
	for child in router.get_children():
		if child is LoadingVeil:
			veil = child
	assert_true(veil != null, "Router baut sein echtes Veil.")
	return {"router": router, "mount": mount, "veil": veil}


func _cleanup(ctx: Dictionary) -> void:
	(ctx["mount"] as Node).queue_free()
	(ctx["router"] as Node).queue_free()
	await wait_frames(1)
