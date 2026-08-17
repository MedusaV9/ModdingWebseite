extends TestCase
## W2a — Szenen-Smoke (Plan-§2-Regel): alle 5 Raum-Szenen laden headless,
## bauen sich prozedural auf, melden ready_for_reveal (Router-Contract) und
## spawnen Gooby an der receive_params-Tür.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

var _seq := 0


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://w2a_tests/smoke_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	return gs


func _cleanup(room: Node, gs: Node) -> void:
	room.queue_free()
	await wait_frames(2)
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()


func test_alle_raum_szenen_bauen_sich_auf() -> void:
	for room_id: String in RoomDefs.ids():
		var scene: PackedScene = load(str(RoomDefs.room(room_id)["scene"]))
		assert_true(scene != null, "%s: Szene lädt" % room_id)
		var gs := _fresh_gs()
		var room: RoomBase = scene.instantiate()
		assert_eq(room.room_id, room_id, "%s: room_id gesetzt" % room_id)
		room.game_state_override = gs
		var revealed := [false]
		room.ready_for_reveal.connect(func() -> void: revealed[0] = true)
		tree.root.add_child(room)
		var ok := await wait_until(func() -> bool: return revealed[0], 8000)
		assert_true(ok, "%s: ready_for_reveal (Router-Contract)" % room_id)
		assert_true(room.grid != null, "%s: Grid geladen" % room_id)
		assert_true(room.grid.to_items_array().size() >= 8, "%s: Default-Layout bestückt" % room_id)
		assert_true(room.gooby() != null, "%s: Gooby gespawnt" % room_id)
		var doors: int = RoomDefs.room(room_id)["doors"].size()
		var door_nodes := 0
		for child in room.get_children():
			if child is DoorTransition:
				door_nodes += 1
		assert_eq(door_nodes, doors, "%s: Tür-Nodes" % room_id)
		await wait_until(func() -> bool: return not room._rebake_pending, 3000)
		await _cleanup(room, gs)


func test_spawn_an_tuer_via_receive_params() -> void:
	var gs := _fresh_gs()
	var scene: PackedScene = load("res://scenes/home/wohnzimmer.tscn")
	var room: RoomBase = scene.instantiate()
	room.game_state_override = gs
	room.receive_params({"door_id": "living_kueche"})
	tree.root.add_child(room)
	await wait_frames(3)
	var door_def := RoomDefs.door("living", "living_kueche")
	var expected := RoomDefs.door_world_pos(RoomDefs.room("living"), door_def) + Vector3(0, 0, 0.7)
	var dist := (room.gooby().position - expected).length()
	assert_true(dist < 0.01, "Gooby spawnt an der Ziel-Tür (Abstand %f)" % dist)
	await wait_until(func() -> bool: return not room._rebake_pending, 3000)
	await _cleanup(room, gs)


func test_baumodus_platziert_und_speichert() -> void:
	var gs := _fresh_gs()
	var scene: PackedScene = load("res://scenes/home/garten.tscn")
	var room: RoomBase = scene.instantiate()
	room.game_state_override = gs
	tree.root.add_child(room)
	await wait_frames(3)
	var items_vorher: int = room.grid.to_items_array().size()
	assert_true(HomeState.store_item(gs, "chair"), "Test-Stuhl ins Lager")
	# Bett-Quest abhaken, damit close() nicht (korrekt!) verweigert wird.
	HomeState.set_flag(gs, HomeState.FLAG_BED_PLACED, true)
	room.open_build_mode()
	assert_true(room.is_build_mode_active(), "Baumodus offen")
	var build: BuildMode = room.get_node("BuildMode")
	build._begin_new(FurnitureCatalog.def("chair"))
	build._ghost_state["at"] = Vector2i(6, 6)
	build._rebuild_ghost()
	build._confirm_ghost()
	assert_eq(room.grid.to_items_array().size(), items_vorher + 1, "Stuhl platziert")
	var saved: Array = gs.get_value("home.rooms.garden.items")
	assert_eq(saved.size(), items_vorher + 1, "Platzierung im GameState persistiert")
	assert_eq(StorageLogic.count_of(gs.get_value("home.storage"), "chair"), 0, "aus dem Lager")
	build.close()
	assert_false(room.is_build_mode_active())
	await wait_until(func() -> bool: return not room._rebake_pending, 3000)
	await _cleanup(room, gs)
