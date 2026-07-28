extends TestCase
## HAUS-SICHT — Budget: Die Kulisse wird versteckt, wenn die Kamera
## senkrecht in den Raum schaut (kulisse_sichtbar), und alle neuen
## Haus-Anbauten bleiben unter engen Instanz-Deckeln (Wiederhol-Geometrie
## als MultiMesh). Die ECHTEN Draw-Calls unterm GL-Renderer misst
## haussicht_screens.gd / fix3_perf_probe.gd (Ziel: ≤350 Baumodus,
## ≤300 Räume) — hier zählen wir GeometryInstances als Proxy.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

## Deckel: Einzel-MeshInstances ≈ potenzielle Draw-Calls pro Modul.
const MAX_GARTEN_HAUS := 45
const MAX_DACH_INNEN := 2
const MAX_FLUR_BLICK_PRO_TUER := 6
const MAX_GARTEN_DIORAMA := 24

var _seq := 0


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://haussicht_tests/bd_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	HomeState.ensure_initialized(gs)
	HomeState.set_flag(gs, HomeState.FLAG_BED_PLACED, true)
	return gs


func _make_room(gs: Node, room_id: String) -> RoomBase:
	var scene: PackedScene = load(str(RoomDefs.room(room_id)["scene"]))
	var room: RoomBase = scene.instantiate()
	room.game_state_override = gs
	room.stunde_override = 13.0
	tree.root.add_child(room)
	return room


func _cleanup(room: Node, gs: Node) -> void:
	room.queue_free()
	await wait_frames(2)
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()


func _einzel_meshes(node: Node) -> int:
	return node.find_children("*", "MeshInstance3D", true, false).size()


func test_kulisse_sichtbar_mathe() -> void:
	var rect := Rect2(0.0, 0.0, 6.0, 5.0)
	assert_false(
		CitySkyline.kulisse_sichtbar(Vector3(3.0, 12.0, 2.5), Vector3.DOWN, rect),
		"Senkrecht überm Raum: Kulisse unsichtbar"
	)
	assert_true(
		CitySkyline.kulisse_sichtbar(
			Vector3(3.0, 8.0, 12.0), Vector3(0.0, -0.6, -0.8).normalized(), rect
		),
		"Schräger Blick: Kulisse sichtbar"
	)
	assert_true(
		CitySkyline.kulisse_sichtbar(Vector3(40.0, 30.0, 2.5), Vector3.DOWN, rect),
		"Senkrecht, aber NEBEN dem Raum: sichtbar (Draufsicht auf die Stadt)"
	)


func test_kamera_gating_versteckt_die_fern_kulisse() -> void:
	var gs := _fresh_gs()
	var room := _make_room(gs, "living")
	await wait_frames(4)
	room.open_build_mode()
	await wait_frames(2)
	var skyline := room.skyline()
	var fern: Node3D = skyline.get_node("Fern")
	var camera := room.get_viewport().get_camera_3d()
	assert_true(camera != null, "Baumodus hat eine Kamera")
	# Kamera senkrecht über die Raummitte zwingen → Fern-Kulisse schläft.
	var mitte := Vector3(3.0, 14.0, 2.5)
	camera.global_transform = Transform3D(Basis.looking_at(Vector3.DOWN, Vector3.FORWARD), mitte)
	skyline._kamera_gating()
	assert_false(fern.visible, "Draufsicht: Fern-Kulisse (Straße/Nachbarn) schläft")
	# Schräg von außen → alles wieder da.
	camera.global_transform = Transform3D(
		Basis.looking_at((Vector3(3.0, 1.0, 2.5) - Vector3(3.0, 7.0, 14.0)).normalized()),
		Vector3(3.0, 7.0, 14.0)
	)
	skyline._kamera_gating()
	assert_true(fern.visible, "Schrägsicht: Fern-Kulisse wieder sichtbar")
	(room.get_node("BuildMode") as BuildMode).close()
	await _cleanup(room, gs)


func test_instanz_deckel_der_haus_anbauten() -> void:
	var gs := _fresh_gs()
	var garden := _make_room(gs, "garden")
	await wait_frames(4)
	var haus_meshes := _einzel_meshes(garden.get_node("GartenHaus"))
	assert_true(
		haus_meshes <= MAX_GARTEN_HAUS,
		"GartenHaus: %d Einzel-Meshes (max %d)" % [haus_meshes, MAX_GARTEN_HAUS]
	)
	await _cleanup(garden, gs)
	var gs2 := _fresh_gs()
	var bedroom := _make_room(gs2, "bedroom")
	await wait_frames(4)
	var dach: DachInnen = bedroom.get_node("DachInnen")
	assert_true(
		_einzel_meshes(dach) <= MAX_DACH_INNEN,
		(
			"DachInnen: %d Einzel-Meshes (max %d) — Balken/Sparren sind MultiMesh"
			% [_einzel_meshes(dach), MAX_DACH_INNEN]
		)
	)
	assert_true(
		dach.find_children("*", "MultiMeshInstance3D", true, false).size() >= 1,
		"DachInnen bündelt Wiederhol-Geometrie als MultiMesh"
	)
	var blick: FlurBlick = bedroom.get_node("FlurBlick")
	var tueren: int = RoomDefs.room("bedroom").get("doors", []).size()
	assert_true(
		_einzel_meshes(blick) <= MAX_FLUR_BLICK_PRO_TUER * tueren,
		"FlurBlick: %d Einzel-Meshes für %d Türen" % [_einzel_meshes(blick), tueren]
	)
	await _cleanup(bedroom, gs2)


func test_garten_diorama_bleibt_flach_und_billig() -> void:
	var gs := _fresh_gs()
	var kitchen := _make_room(gs, "kitchen")
	await wait_frames(4)
	kitchen.grid.place_wall(FurnitureCatalog.def("window_small"), "N", 4, "haussicht-budget")
	kitchen.rebuild_furniture()
	await wait_frames(2)
	var diorama: Node3D = kitchen.get_node("Diorama_N")
	var einzel := _einzel_meshes(diorama)
	assert_true(
		einzel <= MAX_GARTEN_DIORAMA,
		"GartenDiorama: %d Einzel-Meshes (max %d)" % [einzel, MAX_GARTEN_DIORAMA]
	)
	# Nichts lugt über die Wandkrone in den Raum (Himmel-Rückwand ausgenommen,
	# die steht hinter der Hecke und ist von innen nur durchs Fenster zu sehen).
	for mesh: Node in diorama.find_children("*", "MeshInstance3D", true, false):
		if str(mesh.name) == "Himmel":
			continue
		var instanz := mesh as MeshInstance3D
		var welt_aabb: AABB = instanz.global_transform * instanz.get_aabb()
		assert_true(
			welt_aabb.end.y <= RoomBase.WALL_HEIGHT + 0.1,
			"%s bleibt unter der Wandkrone (%.2fm)" % [str(mesh.name), welt_aabb.end.y]
		)
	await _cleanup(kitchen, gs)
