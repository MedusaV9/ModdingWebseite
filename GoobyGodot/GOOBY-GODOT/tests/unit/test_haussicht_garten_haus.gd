extends TestCase
## HAUS-SICHT — GartenHaus: Im Garten steht das eigene Haus mit Dach am
## Nordrand, im Stil aus HouseStyleState (Fassadenfarbe, Dachform), die
## Haustür deckt sich mit der begehbaren Garten-Tür, der Garten-Zaun lässt
## die Fassaden-Lücke, und Innenräume bekommen KEIN Garten-Haus.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

var _seq := 0


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://haussicht_tests/gh_%d_%d" % [Time.get_ticks_usec(), _seq]
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


func _haus(room: RoomBase) -> GartenHaus:
	return room.get_node_or_null("GartenHaus") as GartenHaus


func _set_style(gs: Node, haus: Dictionary) -> void:
	gs.update(
		func(state: Dictionary) -> void: state["home"]["style"] = {"haus": haus, "grundstueck": {}}
	)


func test_garten_hat_haus_mit_dach_innenraum_nicht() -> void:
	var gs := _fresh_gs()
	var room := _make_room(gs, "garden")
	await wait_frames(4)
	var haus := _haus(room)
	assert_true(haus != null, "Garten trägt das eigene Haus")
	assert_true(haus.find_child("Dach", true, false) != null, "… mit Dach")
	assert_true(haus.find_child("Fassade", true, false) != null, "… und Fassade")
	# Plot-Doppelgänger sind raus: der Garten IST das Grundstück.
	for teil_name: String in GartenHaus.ENTFERNEN:
		assert_true(
			haus.find_child(teil_name, true, false) == null,
			"%s des Außenmodells entfällt im Garten" % teil_name
		)
	var modell_tuer := haus.find_child("Tuer", true, false)
	assert_true(
		modell_tuer is Node3D and not (modell_tuer as Node3D).visible,
		"Modell-Tür versteckt — die begehbare RoomBase-Tür übernimmt"
	)
	await _cleanup(room, gs)
	var gs2 := _fresh_gs()
	var living := _make_room(gs2, "living")
	await wait_frames(4)
	assert_true(_haus(living) == null, "Innenraum bekommt kein Garten-Haus")
	await _cleanup(living, gs2)


func test_haustuer_deckt_sich_mit_der_garten_tuer() -> void:
	var gs := _fresh_gs()
	var room := _make_room(gs, "garden")
	await wait_frames(4)
	var haus := _haus(room)
	var tuer: Node3D = room.get_node("Door_garten_living")
	assert_true(
		absf(haus.tuer_welt_x() - tuer.position.x) < 0.001,
		"Haustür-X (%.2f) = Garten-Tür-X (%.2f)" % [haus.tuer_welt_x(), tuer.position.x]
	)
	assert_true(absf(tuer.position.z) < 0.001, "Garten-Tür steht auf der Fassaden-Kante (z=0)")
	await _cleanup(room, gs)


func test_stil_aus_house_style_state_wird_uebernommen() -> void:
	var gs := _fresh_gs()
	_set_style(gs, {"fassade": "rose", "dachForm": "sattel", "dachFarbe": "anthrazit"})
	var room := _make_room(gs, "garden")
	await wait_frames(4)
	var haus := _haus(room)
	var fassade: MeshInstance3D = haus.find_child("Fassade", true, false)
	# CustomizeMaterials cached geteilte Instanzen — Stil angewendet ⇔
	# dieselbe Material-Instanz wie teil_material(fassade) des Spieler-Stils.
	var erwartet := HouseExterior.teil_material("fassade", HouseStyleState.style(gs))
	assert_true(fassade.material_override == erwartet, "Fassaden-Material = Spieler-Stil")
	var tint: Color = (fassade.material_override as ShaderMaterial).get_shader_parameter("tint")
	assert_eq(tint, CustomizeMaterials.farbe("rose"), "… in der gewählten Rose-Farbe")
	assert_true(haus.find_child("Schornstein", true, false) != null, "Satteldach trägt Schornstein")
	await _cleanup(room, gs)
	# Flachdach: kein Schornstein (es gibt keinen Giebel, auf dem er säße).
	var gs2 := _fresh_gs()
	_set_style(gs2, {"fassade": "creme", "dachForm": "flach"})
	var room2 := _make_room(gs2, "garden")
	await wait_frames(4)
	assert_true(
		_haus(room2).find_child("Schornstein", true, false) == null, "Flachdach: kein Schornstein"
	)
	await _cleanup(room2, gs2)


func test_garten_zaun_laesst_die_fassaden_luecke() -> void:
	var gs := _fresh_gs()
	var room := _make_room(gs, "garden")
	await wait_frames(4)
	var luecke := HouseLayout.garten_zaun_luecke(RoomDefs.room("garden"))
	var walls := room.find_child("Walls", true, false)
	assert_true(walls != null, "Zaun-Mount existiert")
	for kind in walls.get_children():
		var kname := str(kind.name)
		if not kname.begins_with("Wall_N_"):
			continue
		var teile := kname.split("_")
		var von := int(teile[2])
		var bis := int(teile[3])
		assert_true(
			bis <= luecke[0] or von >= luecke[1],
			(
				"Zaunsegment %s bleibt außerhalb der Haus-Lücke [%d..%d)"
				% [kname, luecke[0], luecke[1]]
			)
		)
	await _cleanup(room, gs)
