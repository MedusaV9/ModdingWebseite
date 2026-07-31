extends TestCase
## W13/HUD-WIRES — Interaktions-Auge (P5-Befund F11: `eye_toggled` /
## `is_eye_active` ohne Wirkung): pure Marker-Platzierung (Onscreen-Icon,
## Rand-Pfeil, Hinter-der-Kamera-Spiegelung), Rim-Overlay-Auf-/Abbau mit
## Fake-Zielen, Reduced-Motion ohne Puls, Auto-Aus beim Baumodus, lautloses
## HUD-Auge-Zurücksetzen und der Ziel-Scan im echten Wohnzimmer.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")
const HUD_SCENE := preload("res://scripts/ui/hud.tscn")

var _seq := 0


## Fake-Raum: nur das Baumodus-Signal, an das der Spotlight sich hängt.
class FakeRoom:
	extends Node3D

	signal build_mode_toggled(active: bool)

	func toggle_build(active: bool) -> void:
		build_mode_toggled.emit(active)


func test_marker_platzierung_pure() -> void:
	var viewport := Vector2(1280, 720)
	var drin := InteractionSpotlight.marker_platzierung(Vector2(640, 300), false, viewport, 30.0)
	assert_false(bool(drin["offscreen"]), "sichtbarer Punkt → Icon")
	assert_eq(drin["pos"], Vector2(640, 300), "Icon sitzt auf der Projektion")
	var rechts := InteractionSpotlight.marker_platzierung(Vector2(2000, 360), false, viewport, 30.0)
	assert_true(bool(rechts["offscreen"]), "rechts draußen → Pfeil")
	assert_eq(rechts["pos"], Vector2(1250, 360), "Pfeil klemmt an den rechten Rand")
	assert_almost(float(rechts["winkel"]), 0.0, 1e-4, "Pfeil zeigt nach rechts")
	var oben := InteractionSpotlight.marker_platzierung(Vector2(640, -200), false, viewport, 30.0)
	assert_eq(oben["pos"], Vector2(640, 30), "Pfeil klemmt an den oberen Rand")
	assert_almost(float(oben["winkel"]), -PI / 2.0, 1e-4, "Pfeil zeigt nach oben")
	var hinter := InteractionSpotlight.marker_platzierung(Vector2(200, 360), true, viewport, 30.0)
	assert_true(bool(hinter["offscreen"]), "hinter der Kamera → immer Pfeil")
	assert_almost(float(hinter["winkel"]), 0.0, 1e-4, "Spiegelung: Pfeil zeigt nach rechts")


func test_spotlight_markiert_und_raeumt_auf() -> void:
	var room := FakeRoom.new()
	tree.root.add_child(room)
	var ziele: Array[Node3D] = [_fake_ziel(room, "ZielA"), _fake_ziel(room, "ZielB")]
	var spot := InteractionSpotlight.attach_to(room)
	assert_eq(InteractionSpotlight.attach_to(room), spot, "attach_to ist idempotent")
	spot.reduced_motion_override = 0
	spot.ziel_provider = func() -> Array[Node3D]: return ziele
	var aus_signale: Array = []
	spot.deaktiviert.connect(func() -> void: aus_signale.append(true))
	spot.set_aktiv(true)
	assert_true(spot.ist_aktiv(), "Spotlight ist an")
	assert_eq(spot.ziel_anzahl(), 2, "beide Ziele markiert")
	assert_true(spot.puls_anteil() > 0.0, "normaler Modus pulsiert")
	var meshes: Array[MeshInstance3D] = []
	for ziel in ziele:
		for mesh: Variant in ziel.find_children("*", "MeshInstance3D", true, false):
			meshes.append(mesh as MeshInstance3D)
	assert_eq(meshes.size(), 2, "Testaufbau: je Ziel ein Mesh")
	for mesh in meshes:
		assert_true(mesh.material_overlay != null, "Rim-Overlay liegt auf %s" % mesh.get_path())
	spot.set_aktiv(false)
	assert_false(spot.ist_aktiv(), "Spotlight ist aus")
	assert_eq(spot.ziel_anzahl(), 0, "Marker abgeräumt")
	for mesh in meshes:
		assert_true(mesh.material_overlay == null, "Overlay entfernt auf %s" % mesh.get_path())
	assert_eq(aus_signale.size(), 1, "deaktiviert-Signal genau einmal")
	room.queue_free()
	await wait_frames(1)


func test_reduced_motion_ohne_puls() -> void:
	var room := FakeRoom.new()
	tree.root.add_child(room)
	var ziele: Array[Node3D] = [_fake_ziel(room, "Ziel")]
	var spot := InteractionSpotlight.attach_to(room)
	spot.reduced_motion_override = 1
	spot.ziel_provider = func() -> Array[Node3D]: return ziele
	spot.set_aktiv(true)
	assert_almost(spot.puls_anteil(), 0.0, 1e-6, "Reduced Motion: Saum steht still")
	spot.set_aktiv(false)
	room.queue_free()
	await wait_frames(1)


func test_auto_aus_bei_baumodus() -> void:
	var room := FakeRoom.new()
	tree.root.add_child(room)
	var ziele: Array[Node3D] = [_fake_ziel(room, "Ziel")]
	var spot := InteractionSpotlight.attach_to(room)
	spot.reduced_motion_override = 0
	spot.ziel_provider = func() -> Array[Node3D]: return ziele
	spot.set_aktiv(true)
	room.toggle_build(true)
	assert_false(spot.ist_aktiv(), "Baumodus schaltet das Auge ab")
	room.toggle_build(false)
	assert_false(spot.ist_aktiv(), "Baumodus-Ende schaltet NICHT wieder an")
	room.queue_free()
	await wait_frames(1)


func test_hud_set_eye_active_lautlos() -> void:
	var hud: Hud = HUD_SCENE.instantiate()
	tree.root.add_child(hud)
	await tree.process_frame
	var signale: Array = []
	hud.eye_toggled.connect(func(an: bool) -> void: signale.append(an))
	var eye := hud.get_node("EyeButton") as Button
	eye.button_pressed = true
	assert_eq(signale, [true], "echter Toggle feuert eye_toggled")
	assert_true(hud.is_eye_active(), "Auge ist an")
	hud.set_eye_active(false)
	assert_false(hud.is_eye_active(), "set_eye_active(false) setzt den Knopf zurück")
	assert_eq(signale, [true], "… OHNE eye_toggled erneut zu feuern")
	hud.queue_free()
	await wait_frames(1)


func test_ziel_scan_im_wohnzimmer() -> void:
	var gs := _fresh_gs()
	var room: RoomBase = await _make_living_room(gs)
	InteractablesHost.attach_to(room)
	await wait_frames(2)
	var spot := InteractionSpotlight.attach_to(room)
	spot.reduced_motion_override = 0
	spot.set_aktiv(true)
	var tueren := 0
	for child in room.get_children():
		if child is DoorTransition:
			tueren += 1
	assert_true(tueren >= 2, "Wohnzimmer hat Türen (%d)" % tueren)
	assert_true(
		spot.ziel_anzahl() >= tueren,
		"Scan findet mindestens alle Türen (%d Ziele)" % spot.ziel_anzahl()
	)
	spot.set_aktiv(false)
	await _cleanup(room, gs)


func _fake_ziel(parent: Node, ziel_name: String) -> Node3D:
	var ziel := Node3D.new()
	ziel.name = ziel_name
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	ziel.add_child(mesh)
	parent.add_child(ziel)
	return ziel


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://w13_tests/auge_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	return gs


func _make_living_room(gs: Node) -> RoomBase:
	var scene: PackedScene = load("res://scenes/home/wohnzimmer.tscn")
	var room: RoomBase = scene.instantiate()
	room.game_state_override = gs
	room.stunde_override = 13.0
	tree.root.add_child(room)
	await wait_frames(3)
	await wait_until(func() -> bool: return not room._rebake_pending, 4000)
	await tree.physics_frame
	return room


func _cleanup(room: Node, gs: Node) -> void:
	room.queue_free()
	await wait_frames(2)
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()
