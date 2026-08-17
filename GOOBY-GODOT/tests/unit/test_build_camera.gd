extends TestCase
## FIX-3 — freie Baumodus-Kamera: Klemmung an die Raumgrenzen, Zoom-Grenzen,
## 90°-Schnapp, Draufsicht/Schrägsicht und die Greifen-vs-Schwenken-
## Unterscheidung (Trefferprüfung zuerst, sonst Kameraschwenk).

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

var _seq := 0


func test_offset_mathe() -> void:
	var offset := BuildCamera.offset_fuer(0.0, PI * 0.25, 10.0)
	assert_almost(offset.x, 0.0, 1e-5, "yaw 0: kein x-Anteil")
	assert_almost(offset.y, 10.0 * sin(PI * 0.25), 1e-5)
	assert_almost(offset.z, 10.0 * cos(PI * 0.25), 1e-5)
	var gedreht := BuildCamera.offset_fuer(PI * 0.5, PI * 0.25, 10.0)
	assert_almost(gedreht.x, 10.0 * cos(PI * 0.25), 1e-5, "yaw 90°: Offset zeigt nach +x")
	assert_almost(gedreht.z, 0.0, 1e-5)


func test_pivot_klemmung() -> void:
	var raum := Vector2(6.0, 5.0)
	var drin := BuildCamera.clamp_pivot(Vector3(3.0, 0.0, 2.0), raum)
	assert_eq(drin, Vector3(3.0, 0.0, 2.0), "Innen bleibt unangetastet")
	var links := BuildCamera.clamp_pivot(Vector3(-4.0, 0.0, 2.0), raum)
	assert_eq(links, Vector3(0.0, 0.0, 2.0), "Links geklemmt")
	var unten := BuildCamera.clamp_pivot(Vector3(2.0, 0.5, 99.0), raum)
	assert_eq(unten, Vector3(2.0, 0.0, 5.0), "Unten geklemmt, y auf 0")


func test_schnapp_90() -> void:
	assert_almost(BuildCamera.schnapp_yaw(0.0, 1), PI * 0.5)
	assert_almost(BuildCamera.schnapp_yaw(0.0, -1), -PI * 0.5)
	assert_almost(BuildCamera.schnapp_yaw(0.3, 1), PI * 0.5, 1e-5, "schnappt aufs Raster")
	assert_almost(BuildCamera.schnapp_yaw(PI * 0.5 + 0.1, -1), 0.0, 1e-5)


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://fix3_tests/cam_%d_%d" % [Time.get_ticks_usec(), _seq]
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


func test_schwenken_bewegt_und_klemmt_den_pivot() -> void:
	var gs := _fresh_gs()
	var room := _make_room(gs)
	await wait_frames(6)
	var build: BuildMode = room.get_node("BuildMode")
	build.open()
	# Kamera einschwingen lassen, sonst projizieren die Rays am Ziel vorbei.
	await wait_frames(30)
	var cam := build.build_camera()
	var start := cam.pivot()
	# Leere Raumecke statt Bildmitte — in der Mitte kann Möbel stehen, und
	# ein Treffer würde (korrekt!) greifen statt schwenken.
	var frei := room.camera_rig().camera.unproject_position(Vector3(0.3, 0.0, 0.3))
	build._finger_runter(0, frei)
	assert_true(build._pan_index == 0, "Leerer Boden → Schwenk-Finger")
	build._finger_zieht(0, frei + Vector2(120, 0))
	assert_true((cam.pivot() - start).length() > 0.05, "Drag verschiebt den Pivot")
	# Weit über den Raum hinaus ziehen → Klemmung hält den Pivot im Raum.
	for i in 40:
		build._finger_zieht(0, Vector2(760 + i * 30 % 600, 360))
		build._finger_zieht(0, Vector2(160, 360))
	var geklemmt := cam.pivot()
	var raum := Vector2(room.grid.size.x * 0.5, room.grid.size.y * 0.5)
	assert_true(geklemmt.x >= -0.001 and geklemmt.x <= raum.x + 0.001, "Pivot-x im Raum")
	assert_true(geklemmt.z >= -0.001 and geklemmt.z <= raum.y + 0.001, "Pivot-z im Raum")
	build._finger_hoch(0)
	build.close()
	await _cleanup(room, gs)


func test_pinch_zoomt_und_dreht_in_grenzen() -> void:
	var gs := _fresh_gs()
	var room := _make_room(gs)
	await wait_frames(6)
	var build: BuildMode = room.get_node("BuildMode")
	build.open()
	var cam := build.build_camera()
	var dist_start := cam.distanz()
	build._finger_runter(0, Vector2(500, 360))
	build._finger_runter(1, Vector2(700, 360))
	# Auseinanderziehen = ranzoomen.
	build._finger_zieht(0, Vector2(400, 360))
	build._finger_zieht(1, Vector2(800, 360))
	assert_true(cam.distanz() < dist_start, "Pinch-Auf zoomt ran")
	# Extrem-Pinch → Klemmung an DIST_MIN.
	for _i in 30:
		build._finger_zieht(0, Vector2(400, 360))
		build._finger_zieht(1, Vector2(800, 360))
		build._finger_zieht(0, Vector2(599, 360))
		build._finger_zieht(1, Vector2(601, 360))
	assert_true(cam.distanz() >= BuildCamera.DIST_MIN - 0.001, "Zoom klemmt bei DIST_MIN")
	# Zwei-Finger-Drehung: beide Finger rotieren um den Mittelpunkt.
	var yaw_start := cam.yaw()
	build._finger_hoch(0)
	build._finger_hoch(1)
	build._finger_runter(0, Vector2(500, 360))
	build._finger_runter(1, Vector2(700, 360))
	build._finger_zieht(0, Vector2(600, 260))
	build._finger_zieht(1, Vector2(600, 460))
	assert_true(absf(wrapf(cam.yaw() - yaw_start, -PI, PI)) > 0.5, "Twist dreht die Kamera")
	build._finger_hoch(0)
	build._finger_hoch(1)
	build.close()
	await _cleanup(room, gs)


func test_greifen_schlaegt_schwenken() -> void:
	var gs := _fresh_gs()
	var room := _make_room(gs)
	await wait_frames(6)
	var build: BuildMode = room.get_node("BuildMode")
	build.open()
	await wait_frames(40)
	# Screen-Position eines echten Möbels suchen (Kamera-Projektion).
	var items := room.grid.to_items_array()
	var ziel_pos := Vector2.INF
	var kamera := room.camera_rig().camera
	for entry: Dictionary in items:
		if entry.has("wall"):
			continue
		var def := FurnitureCatalog.def(str(entry["item"]))
		if def.is_empty() or int(def["layer"]) != GridData.Layer.FLOOR:
			continue
		var at := Vector2i(int(entry["at"][0]), int(entry["at"][1]))
		var welt := GridData.world_center(at, def["footprint"], int(entry.get("rot", 0)))
		if not kamera.is_position_behind(welt):
			ziel_pos = kamera.unproject_position(welt)
			break
	assert_true(ziel_pos != Vector2.INF, "Testaufbau: ein Möbel ist im Bild")
	build._finger_runter(0, ziel_pos)
	assert_true(build._dragging, "Tap auf Möbel greift (Trefferprüfung zuerst)")
	assert_eq(build._pan_index, -1, "… und startet KEINEN Kameraschwenk")
	assert_eq(build._ghost_state.get("mode", ""), "move", "Move-Ghost aufgenommen")
	build._finger_hoch(0)
	build._cancel_ghost()
	# Gegentest: leere Ecke → Schwenk, kein Ghost.
	var frei := kamera.unproject_position(Vector3(0.3, 0.0, 0.3))
	build._finger_runter(0, frei)
	assert_eq(build._pan_index, 0, "Leere Stelle → Kameraschwenk")
	assert_true(build._ghost_state.is_empty(), "… ohne Ghost")
	build._finger_hoch(0)
	build.close()
	await _cleanup(room, gs)


func test_ansicht_knoepfe() -> void:
	var gs := _fresh_gs()
	var room := _make_room(gs)
	await wait_frames(6)
	var build: BuildMode = room.get_node("BuildMode")
	build.open()
	var cam := build.build_camera()
	assert_false(cam.ist_draufsicht(), "Start: Schrägsicht")
	cam.set_draufsicht(true)
	assert_true(cam.ist_draufsicht(), "Draufsicht-Knopf")
	cam.set_draufsicht(false)
	assert_false(cam.ist_draufsicht(), "Schrägsicht-Knopf")
	var yaw_vorher := cam.yaw()
	cam.schnapp_90(1)
	assert_almost(wrapf(cam.yaw() - yaw_vorher, -PI, PI), PI * 0.5, 1e-4, "90° rechts")
	cam.schnapp_90(-1)
	cam.schnapp_90(-1)
	assert_almost(wrapf(cam.yaw() - yaw_vorher, -PI, PI), -PI * 0.5, 1e-4, "2×90° links")
	build.close()
	await _cleanup(room, gs)
