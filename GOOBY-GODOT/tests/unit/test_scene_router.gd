extends TestCase
## Unit-Tests der SceneRouter-Statemaschine (W1a) — mit Fake-Veil und
## Fixture-Szenen, komplett headless.

const ROUTER_SCRIPT := preload("res://scripts/core/scene_router.gd")
const FAKE_VEIL_SCRIPT := preload("res://tests/fixtures/fake_veil.gd")

const ROOM_A := "res://tests/fixtures/room_a.tscn"
const ROOM_B := "res://tests/fixtures/room_b.tscn"
const ROOM_SLOW := "res://tests/fixtures/room_slow.tscn"
const ROOM_NEVER := "res://tests/fixtures/room_never.tscn"


func test_full_cycle_states_mount_and_signals() -> void:
	var ctx := _make_router()
	var router: Node = ctx["router"]
	var veil: Node = ctx["veil"]
	var states: Array = []
	router.state_changed.connect(func(state: int) -> void: states.append(state))
	var finished: Array = []
	router.travel_finished.connect(func(target: StringName) -> void: finished.append(target))

	router.goto(&"room_a")
	var done := await wait_until(func() -> bool: return finished.size() == 1)
	assert_true(done, "travel_finished kam nicht.")
	assert_eq(finished, [&"room_a"] as Array)
	assert_eq(
		states,
		(
			[
				ROUTER_SCRIPT.State.COVER,
				ROUTER_SCRIPT.State.SWAP,
				ROUTER_SCRIPT.State.WAIT_READY,
				ROUTER_SCRIPT.State.REVEAL,
				ROUTER_SCRIPT.State.IDLE,
			]
			as Array
		),
		"State-Reihenfolge falsch."
	)
	assert_eq(veil.cover_calls, 1, "Veil muss genau 1x covern.")
	assert_eq(veil.reveal_calls, 1, "Veil muss genau 1x revealen.")
	assert_true(is_instance_valid(router.get_current_scene()), "Szene fehlt.")
	assert_eq(router.get_current_scene().get_parent(), ctx["mount"], "Szene nicht im Mount.")
	assert_eq(router.get_current_target(), &"room_a")
	assert_false(router.is_busy())
	await _cleanup(ctx)


func test_swap_replaces_old_scene() -> void:
	var ctx := _make_router()
	var router: Node = ctx["router"]
	var finished: Array = []
	router.travel_finished.connect(func(target: StringName) -> void: finished.append(target))

	router.goto(&"room_a")
	await wait_until(func() -> bool: return finished.size() == 1)
	var first_scene: Node = router.get_current_scene()
	router.goto(&"room_b")
	await wait_until(func() -> bool: return finished.size() == 2)
	assert_false(is_instance_valid(first_scene), "Alte Szene muss freigegeben sein.")
	assert_eq(router.get_current_scene().name, &"RoomB")
	var mount: Node = ctx["mount"]
	assert_eq(mount.get_child_count(), 1, "Genau eine Szene im Mount.")
	await _cleanup(ctx)


func test_waits_for_ready_for_reveal_contract() -> void:
	var ctx := _make_router()
	var router: Node = ctx["router"]
	var ready_at_reveal: Array = []
	var check_ready := func(state: int) -> void:
		if state == ROUTER_SCRIPT.State.REVEAL:
			ready_at_reveal.append(router.get_current_scene().ready_emitted)
	router.state_changed.connect(check_ready)
	var finished: Array = []
	router.travel_finished.connect(func(target: StringName) -> void: finished.append(target))

	router.goto(&"room_slow")
	await wait_until(func() -> bool: return finished.size() == 1)
	assert_eq(ready_at_reveal, [true] as Array, "REVEAL kam vor ready_for_reveal.")
	await _cleanup(ctx)


func test_replace_queue_keeps_only_last_request() -> void:
	var ctx := _make_router()
	var router: Node = ctx["router"]
	var finished: Array = []
	router.travel_finished.connect(func(target: StringName) -> void: finished.append(target))
	var replaced: Array = []
	var on_replaced := func(old_target: StringName, new_target: StringName) -> void:
		replaced.append([old_target, new_target])
	router.travel_replaced.connect(on_replaced)

	router.goto(&"room_a")
	router.goto(&"room_b")
	router.goto(&"room_slow")
	await wait_until(func() -> bool: return finished.size() == 2)
	assert_eq(finished, [&"room_a", &"room_slow"] as Array, "Nur letzte Anfrage darf folgen.")
	assert_eq(replaced, [[&"room_b", &"room_slow"]] as Array, "travel_replaced falsch.")
	await _cleanup(ctx)


func test_hard_timeout_force_reveals() -> void:
	var ctx := _make_router()
	var router: Node = ctx["router"]
	router.hard_timeout_ms = 250
	var forced: Array = []
	router.travel_force_revealed.connect(func(target: StringName) -> void: forced.append(target))
	var finished: Array = []
	router.travel_finished.connect(func(target: StringName) -> void: finished.append(target))

	router.goto(&"room_never")
	var done := await wait_until(func() -> bool: return finished.size() == 1, 10_000)
	assert_true(done, "Force-Reveal muss travel_finished liefern (nie Deadlock).")
	assert_eq(forced, [&"room_never"] as Array, "travel_force_revealed fehlt.")
	assert_false(router.is_busy())
	await _cleanup(ctx)


func test_door_travel_api_skeleton_and_params() -> void:
	var ctx := _make_router()
	var router: Node = ctx["router"]
	var veil: Node = ctx["veil"]
	var started: Array = []
	var on_started := func(target: StringName, travel_type: int) -> void:
		started.append([target, travel_type])
	router.travel_started.connect(on_started)
	var finished: Array = []
	router.travel_finished.connect(func(target: StringName) -> void: finished.append(target))

	router.goto(&"room_a", {"door_id": "north"}, ROUTER_SCRIPT.TravelType.DOOR_TRAVEL)
	await wait_until(func() -> bool: return finished.size() == 1)
	assert_eq(started, [[&"room_a", ROUTER_SCRIPT.TravelType.DOOR_TRAVEL]] as Array)
	assert_eq(
		router.get_current_scene().received_params,
		{"door_id": "north"},
		"receive_params-Contract verletzt."
	)
	assert_eq(veil.cover_calls, 1, "M1-DOOR_TRAVEL nutzt den Veil-Cut.")
	await _cleanup(ctx)


func test_preload_target_then_goto() -> void:
	var ctx := _make_router()
	var router: Node = ctx["router"]
	router.preload_target(&"room_b")
	await wait_frames(3)
	var finished: Array = []
	router.travel_finished.connect(func(target: StringName) -> void: finished.append(target))
	router.goto(&"room_b")
	var done := await wait_until(func() -> bool: return finished.size() == 1)
	assert_true(done, "Reise nach Preload muss ankommen.")
	assert_eq(router.get_current_scene().name, &"RoomB")
	await _cleanup(ctx)


func test_min_shown_ms_is_respected() -> void:
	var ctx := _make_router()
	var router: Node = ctx["router"]
	router.min_shown_ms = 200
	var finished: Array = []
	router.travel_finished.connect(func(target: StringName) -> void: finished.append(target))
	var started_ms := Time.get_ticks_msec()
	router.goto(&"room_a")
	await wait_until(func() -> bool: return finished.size() == 1)
	var elapsed := Time.get_ticks_msec() - started_ms
	assert_true(elapsed >= 200, "min_shown_ms nicht eingehalten (%d ms)." % elapsed)
	await _cleanup(ctx)


func _make_router() -> Dictionary:
	var router: Node = ROUTER_SCRIPT.new()
	var veil: Node = FAKE_VEIL_SCRIPT.new()
	router.install_veil(veil)
	router.min_shown_ms = 0
	var mount := Node.new()
	tree.root.add_child(mount)
	tree.root.add_child(router)
	router.set_mount_point(mount)
	router.register_route(&"room_a", ROOM_A)
	router.register_route(&"room_b", ROOM_B)
	router.register_route(&"room_slow", ROOM_SLOW)
	router.register_route(&"room_never", ROOM_NEVER)
	return {"router": router, "veil": veil, "mount": mount}


func _cleanup(ctx: Dictionary) -> void:
	(ctx["mount"] as Node).queue_free()
	(ctx["router"] as Node).queue_free()
	(ctx["veil"] as Node).free()
	await wait_frames(1)
