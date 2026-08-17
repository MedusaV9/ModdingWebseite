extends TestCase
## HAUS-SICHT — Raumkontext: Innenräume fühlen sich als Teil eines Hauses
## an. Dachgeschoss-Räume tragen die Dachschräge (außer bei Flachdach),
## Erdgeschoss-Räume Deckenbalken; hinter jeder Tür liegt eine Flur-Nische
## in den Farben des Zielraums; Garten-Fenster bekommen das Garten-Diorama,
## Straßen-Fenster das Straßen-Diorama; im Baumodus schläft alles davon.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

var _seq := 0


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://haussicht_tests/rk_%d_%d" % [Time.get_ticks_usec(), _seq]
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


func _dach(room: RoomBase) -> DachInnen:
	return room.get_node_or_null("DachInnen") as DachInnen


func _blick(room: RoomBase) -> FlurBlick:
	return room.get_node_or_null("FlurBlick") as FlurBlick


func _fenster_einhaengen(room: RoomBase, wall: String, offset: int) -> void:
	room.grid.place_wall(FurnitureCatalog.def("window_small"), wall, offset, "haussicht-test")
	room.rebuild_furniture()


func test_dachgeschoss_hat_schraege_erdgeschoss_balken() -> void:
	var gs := _fresh_gs()
	var bedroom := _make_room(gs, "bedroom")
	await wait_frames(4)
	var dach := _dach(bedroom)
	assert_true(dach != null, "Schlafzimmer trägt DachInnen")
	assert_true(dach.hat_schraege(), "Dachgeschoss: Dachschräge")
	assert_true(dach.find_child("Dachschraege", true, false) != null, "… als Platte")
	assert_true(dach.find_child("Sparren", true, false) != null, "… mit Sparren")
	await _cleanup(bedroom, gs)
	var gs2 := _fresh_gs()
	var living := _make_room(gs2, "living")
	await wait_frames(4)
	assert_false(_dach(living).hat_schraege(), "Erdgeschoss: keine Schräge")
	assert_true(
		_dach(living).find_child("Deckenbalken", true, false) != null, "Erdgeschoss: Deckenbalken"
	)
	await _cleanup(living, gs2)


func test_flachdach_nimmt_die_schraege_weg() -> void:
	var gs := _fresh_gs()
	gs.update(
		func(state: Dictionary) -> void:
			state["home"]["style"] = {"haus": {"dachForm": "flach"}, "grundstueck": {}}
	)
	var bedroom := _make_room(gs, "bedroom")
	await wait_frames(4)
	assert_false(_dach(bedroom).hat_schraege(), "Flachdach: keine Dachschräge")
	await _cleanup(bedroom, gs)


func test_hinter_jeder_tuer_liegt_eine_nische() -> void:
	var gs := _fresh_gs()
	var living := _make_room(gs, "living")
	await wait_frames(4)
	var blick := _blick(living)
	assert_true(blick != null, "Wohnzimmer trägt FlurBlick")
	var tueren: Array = RoomDefs.room("living").get("doors", [])
	assert_eq(blick.get_child_count(), tueren.size(), "Eine Nische pro Tür")
	for door_def: Dictionary in tueren:
		var nische := blick.get_node_or_null("Nische_%s" % str(door_def["id"]))
		assert_true(nische != null, "Nische hinter %s" % str(door_def["id"]))
	# Nischen-Farbe = Zielraum-Farbe (leicht abgedunkelt): Küche hinter der
	# Küchen-Tür, nicht irgendein Grau.
	var kueche_nische := blick.get_node("Nische_living_kueche")
	var rueckwand: MeshInstance3D = kueche_nische.get_node("Rueckwand")
	var erwartet: Color = RoomDefs.room("kitchen")["wall_color"]
	var ist := (rueckwand.material_override as StandardMaterial3D).albedo_color
	assert_eq(ist, erwartet.darkened(FlurBlick.SCHATTEN), "Nische trägt Zielraum-Farbe")
	await _cleanup(living, gs)


func test_diorama_weiche_garten_vs_strasse() -> void:
	# Küche (Vista garten): Garten-Diorama; Wohnzimmer (strasse): Straße.
	var gs := _fresh_gs()
	var kitchen := _make_room(gs, "kitchen")
	await wait_frames(4)
	_fenster_einhaengen(kitchen, "N", 4)
	await wait_frames(2)
	var diorama := kitchen.get_node_or_null("Diorama_N")
	assert_true(diorama is GartenDiorama, "Garten-Vista: GartenDiorama")
	assert_true((diorama as Node3D).find_child("Hecke", true, false) != null, "… mit Gartenhecke")
	await _cleanup(kitchen, gs)
	var gs2 := _fresh_gs()
	var living := _make_room(gs2, "living")
	await wait_frames(4)
	_fenster_einhaengen(living, "N", 4)
	await wait_frames(2)
	assert_true(
		living.get_node_or_null("Diorama_N") is StreetDiorama, "Straßen-Vista: StreetDiorama"
	)
	await _cleanup(living, gs2)


func test_baumodus_schlaefert_hauskontext_ein() -> void:
	var gs := _fresh_gs()
	var bedroom := _make_room(gs, "bedroom")
	await wait_frames(4)
	_fenster_einhaengen(bedroom, "N", 2)
	await wait_frames(2)
	var dach := _dach(bedroom)
	var blick := _blick(bedroom)
	var diorama: Node3D = bedroom.get_node("Diorama_N")
	assert_true(dach.visible and blick.visible and diorama.visible, "Spielmodus: alles da")
	bedroom.open_build_mode()
	assert_false(dach.visible, "Baumodus: Balken/Schräge weg (Draufsicht!)")
	assert_false(blick.visible, "Baumodus: Nischen weg (ragen aus der Fassade)")
	assert_false(diorama.visible, "Baumodus: Diorama weg (Kulisse übernimmt)")
	(bedroom.get_node("BuildMode") as BuildMode).close()
	assert_true(dach.visible and blick.visible and diorama.visible, "Danach: alles zurück")
	await _cleanup(bedroom, gs)


func test_garten_haus_bleibt_in_der_baumodus_kulisse() -> void:
	# Das Garten-Haus IST die Kulisse des Gartens — es darf im Baumodus
	# nicht verschwinden (die Vorstadt-Straße liegt dahinter).
	var gs := _fresh_gs()
	var garden := _make_room(gs, "garden")
	await wait_frames(4)
	var haus: GartenHaus = garden.get_node("GartenHaus")
	garden.open_build_mode()
	assert_true(haus.visible, "Garten-Haus steht auch im Baumodus")
	(garden.get_node("BuildMode") as BuildMode).close()
	await _cleanup(garden, gs)
