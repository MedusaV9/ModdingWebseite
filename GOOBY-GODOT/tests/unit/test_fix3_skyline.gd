extends TestCase
## FIX-3 — Stadt-Kulisse ums Haus (User: „beim Bauen die ganze Stadt sehen,
## mit fahrenden Autos und laufenden NPCs"): Kulisse existiert, ist NUR im
## Baumodus aktiv, Autos fahren, Gooby-Passanten laufen, und die Instanz-
## Zahl bleibt im Budget (Wiederhol-Geometrie als MultiMesh). Die echten
## Draw-Calls unterm GL-Renderer misst fix3_perf_probe.gd.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")
## Budget-Proxy: einzelne GeometryInstance3D ≈ potenzielle Draw-Calls der
## Kulisse. Ziel ≤ 350 Draw-Calls im GANZEN Baumodus — die Kulisse darf
## davon nur einen Teil belegen.
const MAX_EINZEL_INSTANZEN := 120

var _seq := 0


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://fix3_tests/sky_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	HomeState.ensure_initialized(gs)
	HomeState.set_flag(gs, HomeState.FLAG_BED_PLACED, true)
	return gs


func _make_room(gs: Node) -> RoomBase:
	var scene: PackedScene = load("res://scenes/home/wohnzimmer.tscn")
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


func test_ring_punkt_mathe() -> void:
	var rect := Rect2(0.0, 0.0, 10.0, 6.0)
	var start := CitySkyline.ring_punkt(rect, 0.0)
	assert_eq(start["pos"], Vector3(0.0, 0.0, 0.0), "t=0: linke obere Ecke")
	var oben := CitySkyline.ring_punkt(rect, 5.0)
	assert_eq(oben["pos"], Vector3(5.0, 0.0, 0.0), "Nordkante läuft in +x")
	var rechts := CitySkyline.ring_punkt(rect, 13.0)
	assert_eq(rechts["pos"], Vector3(10.0, 0.0, 3.0), "Ostkante läuft in +z")
	var wrap := CitySkyline.ring_punkt(rect, 32.0)
	assert_eq(wrap["pos"], start["pos"], "t wrapt am Umfang")


func test_nur_im_baumodus_aktiv() -> void:
	var gs := _fresh_gs()
	var room := _make_room(gs)
	await wait_frames(6)
	var skyline := room.skyline()
	assert_true(skyline != null, "Kulisse hängt am Raum")
	assert_false(skyline.visible, "Ohne Baumodus: unsichtbar")
	assert_false(skyline.is_processing(), "… und kein _process (Budget)")
	room.open_build_mode()
	assert_true(skyline.visible, "Baumodus: sichtbar")
	assert_true(skyline.is_processing(), "… und Verkehr läuft")
	(room.get_node("BuildMode") as BuildMode).close()
	assert_false(skyline.visible, "Nach close: wieder unsichtbar")
	await _cleanup(room, gs)


func test_autos_fahren_und_npcs_laufen() -> void:
	var gs := _fresh_gs()
	var room := _make_room(gs)
	await wait_frames(6)
	var skyline := room.skyline()
	assert_true(skyline._autos.size() >= 2, "Mindestens 2 Autos unterwegs")
	assert_true(skyline._npcs.size() >= 2, "Mindestens 2 Gooby-Passanten")
	room.open_build_mode()
	var auto_vorher: Vector3 = (skyline._autos[0]["node"] as Node3D).position
	var npc_vorher: Vector3 = (skyline._npcs[0]["node"] as Node3D).position
	skyline._process(0.5)
	skyline._process(0.5)
	var auto_weg := ((skyline._autos[0]["node"] as Node3D).position - auto_vorher).length()
	var npc_weg := ((skyline._npcs[0]["node"] as Node3D).position - npc_vorher).length()
	assert_true(auto_weg > 0.5, "Auto fährt (%.2fm in 1s)" % auto_weg)
	assert_true(npc_weg > 0.1, "Passant läuft (%.2fm in 1s)" % npc_weg)
	(room.get_node("BuildMode") as BuildMode).close()
	await _cleanup(room, gs)


func test_budget_wiederholgeometrie_ist_multimesh() -> void:
	var gs := _fresh_gs()
	var room := _make_room(gs)
	await wait_frames(6)
	var skyline := room.skyline()
	var multis := skyline.find_children("*", "MultiMeshInstance3D", true, false)
	assert_true(multis.size() >= 2, "Straße/Bäume laufen über MultiMesh")
	var strassen_instanzen := 0
	for multi: Node in multis:
		if str(multi.name).begins_with("Strasse"):
			strassen_instanzen = (multi as MultiMeshInstance3D).multimesh.instance_count
			break
	assert_true(strassen_instanzen >= 8, "Straßen-Geraden gebündelt (1 Draw-Call)")
	var einzel := skyline.find_children("*", "MeshInstance3D", true, false)
	assert_true(
		einzel.size() <= MAX_EINZEL_INSTANZEN,
		"Kulissen-Budget: %d Einzel-Meshes (max %d)" % [einzel.size(), MAX_EINZEL_INSTANZEN]
	)
	print("    kulisse: %d MeshInstance3D + %d MultiMesh" % [einzel.size(), multis.size()])
	await _cleanup(room, gs)
