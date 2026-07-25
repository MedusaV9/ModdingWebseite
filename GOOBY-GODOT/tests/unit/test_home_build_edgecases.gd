extends TestCase
## FIX-D (E9 Baumodus-Edgecases) — Szenen-Tests über die ECHTE
## RoomBase/BuildMode-Kette:
## - P0-1: Wandmöbel sind antippbar, einlagerbar und neu platzierbar.
## - P1-1: Möbel auf Tischen überleben den Raumwechsel (Save-Reihenfolge).
## - P1-2: Auto-Fit clampt die Höhe (keine 3,37-m-Stehlampe im 2,5-m-Raum).
## - Regression: Lager-voll-Verweigerung + letztes Pflichtbett bleiben intakt.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

var _seq := 0


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://fixd_tests/case_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	return gs


func _open_room(gs: Node, scene_path: String) -> RoomBase:
	var scene: PackedScene = load(scene_path)
	var room: RoomBase = scene.instantiate()
	room.game_state_override = gs
	tree.root.add_child(room)
	await wait_frames(4)
	return room


func _cleanup(room: Node, gs: Node) -> void:
	if room != null:
		room.queue_free()
	await wait_frames(2)
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()


func _uid_of(room: RoomBase, item_id: String) -> String:
	for entry: Dictionary in room.grid.to_items_array():
		if str(entry["item"]) == item_id:
			return str(entry["uid"])
	return ""


func _furniture_node(room: RoomBase, uid: String) -> FurnitureNode:
	for child in room.find_children("*", "FurnitureNode", true, false):
		if (child as FurnitureNode).uid == uid:
			return child
	return null


## P0-1: Tap auf den Badspiegel wählt ihn aus; einlagern und aus dem Lager
## neu platzieren funktioniert wie bei Bodenmöbeln.
func test_wandmoebel_antippen_einlagern_neu_platzieren() -> void:
	var gs := _fresh_gs()
	var room := await _open_room(gs, "res://scenes/home/bad.tscn")
	HomeState.set_flag(gs, HomeState.FLAG_BED_PLACED, true)
	var build: BuildMode = room.get_node("BuildMode")
	build.open()
	await wait_frames(30)
	var mirror_uid := _uid_of(room, "bathroomMirror")
	assert_ne(mirror_uid, "", "Badspiegel im Startlayout")
	assert_eq(room.grid.wall_item_at("N", 2), mirror_uid, "wall_item_at findet den Slot")
	var mirror_node := _furniture_node(room, mirror_uid)
	assert_true(mirror_node != null, "FurnitureNode des Spiegels existiert")
	var cam: Camera3D = room._camera_rig.camera
	build._on_tap(cam.unproject_position(mirror_node.global_position))
	assert_false(build._ghost_state.is_empty(), "Tap auf den Spiegel wählt ihn aus (E9 P0-1)")
	assert_eq(str(build._ghost_state.get("uid", "")), mirror_uid, "richtige uid gegriffen")
	assert_eq(str(build._ghost_state.get("mode", "")), "move", "als Verschieben")
	# Einlagern: Spiegel verschwindet aus dem Grid und liegt im Lager.
	build._store_ghost()
	assert_eq(_uid_of(room, "bathroomMirror"), "", "Spiegel aus dem Raum")
	assert_eq(room.grid.wall_item_at("N", 2), "", "Wand-Slot wieder frei")
	assert_eq(StorageLogic.count_of(HomeState.storage(gs), "bathroomMirror"), 1, "im Lager")
	# Wieder platzieren (Drawer-Pfad): zurück an die Nordwand.
	build._begin_new(FurnitureCatalog.def("bathroomMirror"))
	build._ghost_state["wall"] = "N"
	build._ghost_state["offset"] = 2
	build._rebuild_ghost()
	build._confirm_ghost()
	var new_uid := _uid_of(room, "bathroomMirror")
	assert_ne(new_uid, "", "Spiegel wieder platziert")
	assert_eq(room.grid.wall_item_at("N", 2), new_uid, "Slot N:2 belegt")
	assert_eq(StorageLogic.count_of(HomeState.storage(gs), "bathroomMirror"), 0, "Lager leer")
	# Gegenprobe: Tap auf leeren Boden mitten im Raum greift KEIN Wand-Item.
	build._cancel_ghost()
	var mitte := GridData.world_center(Vector2i(3, 4), Vector2i.ONE, 0)
	assert_eq(build._wall_item_at_pointer(mitte), "", "Raummitte pickt keine Wand")
	build.close()
	await _cleanup(room, gs)


## P1-1: Beistelltisch einlagern + neu aufstellen (neue uid > Lampen-uid),
## dann Raumwechsel — die Tischlampe bleibt auf dem Tisch statt im Lager.
func test_tischlampe_bleibt_nach_raumwechsel_auf_dem_tisch() -> void:
	var gs := _fresh_gs()
	var room := await _open_room(gs, "res://scenes/home/schlafzimmer.tscn")
	HomeState.set_flag(gs, HomeState.FLAG_BED_PLACED, true)
	var table_uid := _uid_of(room, "sideTable")
	var lamp_uid := _uid_of(room, "lampRoundTable")
	assert_ne(table_uid, "", "Beistelltisch im Startlayout")
	assert_ne(lamp_uid, "", "Tischlampe im Startlayout")
	var build: BuildMode = room.get_node("BuildMode")
	build.open()
	await wait_frames(2)
	build._begin_move(table_uid)
	build._store_ghost()
	assert_eq(_uid_of(room, "sideTable"), "", "Tisch eingelagert")
	build._begin_new(FurnitureCatalog.def("sideTable"))
	build._ghost_state["at"] = Vector2i(0, 0)
	build._rebuild_ghost()
	build._confirm_ghost()
	var new_table_uid := _uid_of(room, "sideTable")
	assert_ne(new_table_uid, "", "neuer Tisch steht")
	assert_true(new_table_uid > lamp_uid, "neuer Tisch hat höhere uid als die Lampe")
	build.close()
	var lamp_stored_before := StorageLogic.count_of(HomeState.storage(gs), "lampRoundTable")
	room.queue_free()
	await wait_frames(2)
	# Raum neu betreten — vor dem Fix wanderte die Lampe hier ins Lager.
	var room2 := await _open_room(gs, "res://scenes/home/schlafzimmer.tscn")
	assert_eq(_uid_of(room2, "lampRoundTable"), lamp_uid, "Lampe steht noch im Raum (E9 P1-1)")
	assert_eq(room2.grid.item_at(Vector2i(0, 0), GridData.Layer.SURFACE), lamp_uid, "auf dem Tisch")
	assert_eq(
		StorageLogic.count_of(HomeState.storage(gs), "lampRoundTable"),
		lamp_stored_before,
		"nichts ins Lager gewandert"
	)
	await _cleanup(room2, gs)


## P1-2: Auto-Fit clampt die Höhe — die Problemfälle aus E9 bleiben unter
## MAX_FIT_HEIGHT, kompakte Möbel behalten ihren Footprint-Fit.
func test_autofit_hoehenclamp() -> void:
	for id: String in ["lampSquareFloor", "lampRoundFloor", "speaker", "kitchenFridge"]:
		var def := FurnitureCatalog.def(id)
		var node := FurnitureNode.create(def, Vector2i(0, 0), 0, "fit-%s" % id)
		assert_true(node != null, "%s: Node baut sich" % id)
		if node == null:
			continue
		assert_true(
			node.top_y() <= FurnitureNode.MAX_FIT_HEIGHT + 0.001,
			"%s: Höhe %.2f m über dem Clamp (E9 P1-2)" % [id, node.top_y()]
		)
		node.free()
	# Die Stehlampe (vorher 3,37 m) sitzt jetzt exakt auf der Obergrenze.
	var lampe := FurnitureNode.create(
		FurnitureCatalog.def("lampSquareFloor"), Vector2i.ZERO, 0, "l"
	)
	assert_almost(lampe.top_y(), FurnitureNode.MAX_FIT_HEIGHT, 0.001, "Stehlampe geclampt")
	lampe.free()
	# Kompaktes Möbel: Clamp greift NICHT, der Footprint-Fit bleibt erhalten.
	var chair_def := FurnitureCatalog.def("chair")
	var chair := FurnitureNode.create(chair_def, Vector2i.ZERO, 0, "c")
	var raw: Node3D = (load(FurnitureCatalog.glb_path(chair_def)) as PackedScene).instantiate()
	var aabb := FurnitureNode._merged_aabb(raw, Transform3D.IDENTITY)
	raw.free()
	var fp: Vector2i = chair_def["footprint"]
	var fill: float = chair_def["fill"]
	var s_xz := minf(
		fp.x * GridData.CELL_SIZE * fill / aabb.size.x,
		fp.y * GridData.CELL_SIZE * fill / aabb.size.z
	)
	assert_almost(chair._model.scale.x, s_xz, 0.001, "Stuhl: XZ-Fit unverändert")
	chair.free()


## E9 Punkt 4 (Katalog-GLB-Bounds-Plausibilität): jedes Katalog-Item baut
## sich, hat plausible Bounds und respektiert den Höhenclamp.
func test_katalog_bounds_plausibel_und_nie_hoeher_als_der_raum() -> void:
	for id: String in FurnitureCatalog.ids():
		var def := FurnitureCatalog.def(id)
		var node: FurnitureNode
		if int(def["layer"]) == GridData.Layer.WALL:
			node = FurnitureNode.create_wall(def, "N", 0, Vector2i(8, 8), "b-%s" % id)
		else:
			node = FurnitureNode.create(def, Vector2i(0, 0), 0, "b-%s" % id)
		assert_true(node != null, "%s: GLB lädt und baut sich" % id)
		if node == null:
			continue
		assert_true(node.top_y() > 0.005, "%s: plausible Höhe (top_y > 0)" % id)
		assert_true(
			node.top_y() <= FurnitureNode.MAX_FIT_HEIGHT + 0.001,
			"%s: nie höher als der Raum (%.2f m)" % [id, node.top_y()]
		)
		node.free()


## Regression (E9 „Was funktioniert“): letztes Pflichtbett bleibt gesperrt,
## volles Lager verweigert das Einlagern — beides über die echte UI-Kette.
func test_letztes_bett_und_lager_voll_regressionen() -> void:
	var gs := _fresh_gs()
	var room := await _open_room(gs, "res://scenes/home/schlafzimmer.tscn")
	HomeState.set_flag(gs, HomeState.FLAG_BED_PLACED, true)
	var bed_def := FurnitureCatalog.def("bedSingle")
	var bed_at := Vector2i(-1, -1)
	for y in room.grid.size.y:
		for x in room.grid.size.x:
			if bed_at.x < 0 and bool(room.grid.can_place(bed_def, Vector2i(x, y), 0)["ok"]):
				bed_at = Vector2i(x, y)
	assert_true(bed_at.x >= 0, "freier Platz fürs Bett")
	assert_true(room.grid.place(bed_def, bed_at, 0, "bed-t")["ok"])
	var build: BuildMode = room.get_node("BuildMode")
	build.open()
	await wait_frames(2)
	build._begin_move("bed-t")
	var storage_before := HomeState.storage(gs).duplicate(true)
	build._store_ghost()
	assert_ne(_uid_of(room, "bedSingle"), "", "letztes Bett bleibt im Raum")
	assert_eq(HomeState.storage(gs), storage_before, "Lager unverändert")
	build._cancel_ghost()
	# Lager exakt voll: Einlagern eines weiteren Items wird verweigert.
	gs.set_value("home.storageCapacity", HomeState.storage_points_used(gs))
	var chair_at := Vector2i(-1, -1)
	var chair_def := FurnitureCatalog.def("chair")
	for y in room.grid.size.y:
		for x in room.grid.size.x:
			if chair_at.x < 0 and bool(room.grid.can_place(chair_def, Vector2i(x, y), 0)["ok"]):
				chair_at = Vector2i(x, y)
	assert_true(chair_at.x >= 0, "freier Platz für den Stuhl")
	room.grid.place(chair_def, chair_at, 0, "chair-t")
	build._begin_move("chair-t")
	build._store_ghost()
	assert_ne(_uid_of(room, "chair"), "", "volles Lager: Stuhl bleibt im Raum")
	assert_eq(StorageLogic.count_of(HomeState.storage(gs), "chair"), 0, "nicht ins Lager")
	build._cancel_ghost()
	build.close()
	await _cleanup(room, gs)
