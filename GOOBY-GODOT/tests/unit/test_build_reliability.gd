extends TestCase
## FIX-3 — Zuverlässigkeit des Baumodus (User: „geht nicht mehr zuverlässig,
## laggt am Anfang und Ende"): 20× Öffnen/Schließen in EINEM Lauf ohne
## Fehler, ohne Node-Leck und ohne Zustands-Reste; Platzieren funktioniert
## in jedem Zyklus; die CPU-Kosten pro open() bleiben gedeckelt.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

var _seq := 0


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://fix3_tests/rel_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	HomeState.ensure_initialized(gs)
	# Bett-Quest abhaken: close() verweigert (korrekt) mit Bett im Lager.
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


func test_20x_oeffnen_schliessen_ohne_leck_und_reste() -> void:
	var gs := _fresh_gs()
	HomeState.store_item(gs, "chair")
	var room := _make_room(gs)
	await wait_frames(6)
	var build: BuildMode = room.get_node("BuildMode")
	var mount := room.grid_mount()
	# Referenz NACH einem ersten Zyklus (der Ghost-Warm-up-Probe ist dann
	# sicher abgeräumt) — ab da darf kein Zyklus mehr Nodes ansammeln.
	build.open()
	await wait_frames(2)
	build.close()
	await wait_frames(4)
	var mount_kinder := mount.get_child_count()
	var raum_kinder := room.get_child_count()
	var ui_kinder := room.ui_layer().get_child_count()
	for zyklus in 20:
		var t0 := Time.get_ticks_usec()
		build.open()
		var dauer_ms := (Time.get_ticks_usec() - t0) / 1000.0
		assert_true(build.is_active(), "Zyklus %d: offen" % zyklus)
		assert_true(room.get_node("GridOverlay").visible, "Zyklus %d: Overlay an" % zyklus)
		assert_true(dauer_ms < 100.0, "Zyklus %d: open() dauerte %.1f ms" % [zyklus, dauer_ms])
		await wait_frames(2)
		build.close()
		assert_false(build.is_active(), "Zyklus %d: zu" % zyklus)
		assert_false(room.get_node("GridOverlay").visible, "Zyklus %d: Overlay aus" % zyklus)
		assert_true(build._ghost_state.is_empty(), "Zyklus %d: kein Ghost-Rest" % zyklus)
		assert_true(build._touches.is_empty(), "Zyklus %d: keine Touch-Reste" % zyklus)
		await wait_frames(2)
	await wait_frames(4)
	assert_eq(mount.get_child_count(), mount_kinder, "GridMount sammelt keine Nodes an")
	assert_eq(room.get_child_count(), raum_kinder, "Raum sammelt keine Nodes an")
	assert_eq(room.ui_layer().get_child_count(), ui_kinder, "UI-Layer sammelt keine Nodes an")
	await _cleanup(room, gs)


func test_platzieren_klappt_in_jedem_zyklus() -> void:
	var gs := _fresh_gs()
	for _i in 3:
		HomeState.store_item(gs, "chair")
	var room := _make_room(gs)
	await wait_frames(6)
	var build: BuildMode = room.get_node("BuildMode")
	var vorher: int = room.grid.to_items_array().size()
	for zyklus in 3:
		build.open()
		var def := FurnitureCatalog.def("chair")
		build._begin_new(def)
		var frei := _freie_zelle(room.grid, def)
		assert_true(frei.x >= 0, "Zyklus %d: freie Zelle vorhanden" % zyklus)
		build._ghost_state["at"] = frei
		build._rebuild_ghost()
		build._confirm_ghost()
		assert_eq(
			room.grid.to_items_array().size(),
			vorher + zyklus + 1,
			"Zyklus %d: Stuhl platziert" % zyklus
		)
		build.close()
		assert_false(build.is_active(), "Zyklus %d: close nach Platzieren" % zyklus)
		await wait_frames(2)
	await _cleanup(room, gs)


## Erste Zelle, auf der `def` regulär platzierbar ist (Belegung ändert sich
## pro Zyklus — deshalb suchen statt Koordinaten hartkodieren).
func _freie_zelle(grid: GridData, def: Dictionary) -> Vector2i:
	for y in grid.size.y:
		for x in grid.size.x:
			var at := Vector2i(x, y)
			if bool(grid.can_place(def, at, 0)["ok"]):
				return at
	return Vector2i(-1, -1)


func test_kamera_rig_uebergabe_und_rueckgabe() -> void:
	var gs := _fresh_gs()
	var room := _make_room(gs)
	await wait_frames(6)
	var build: BuildMode = room.get_node("BuildMode")
	var rig := room.camera_rig()
	assert_true(rig.is_processing(), "Vor dem Baumodus läuft das Rig")
	build.open()
	assert_false(rig.is_processing(), "Im Baumodus schläft das Rig (BuildCamera fährt)")
	assert_true(build.build_camera().ist_aktiv(), "BuildCamera aktiv")
	build.close()
	assert_true(rig.is_processing(), "Nach dem Baumodus fährt das Rig wieder")
	assert_false(build.build_camera().ist_aktiv(), "BuildCamera deaktiviert")
	await _cleanup(room, gs)


func test_multitouch_zweiter_finger_bricht_drag_nicht_kaputt() -> void:
	var gs := _fresh_gs()
	HomeState.store_item(gs, "chair")
	var room := _make_room(gs)
	await wait_frames(6)
	var build: BuildMode = room.get_node("BuildMode")
	build.open()
	build._begin_new(FurnitureCatalog.def("chair"))
	await wait_frames(1)
	# Finger 1 greift den Ghost, Finger 2 landet dazu → Pinch statt Chaos:
	# vorher teleportierte der zweite Tap den Ghost quer durch den Raum.
	var mitte := Vector2(640, 360)
	build._finger_runter(0, mitte)
	assert_true(build._dragging, "Finger 1 zieht den Ghost")
	var at_vorher: Vector2i = build._ghost_state["at"]
	build._finger_runter(1, mitte + Vector2(200, 0))
	assert_false(build._dragging, "Pinch beendet den Ghost-Drag kontrolliert")
	assert_eq(build._ghost_state["at"], at_vorher, "Zweiter Finger teleportiert den Ghost nicht")
	assert_false(build._ghost_state.is_empty(), "Ghost bleibt aufgenommen")
	build._finger_hoch(0)
	build._finger_hoch(1)
	build._cancel_ghost()
	build.close()
	await _cleanup(room, gs)
