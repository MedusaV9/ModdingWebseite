extends TestCase
## FIX-3 — Tür-Bestätigung (User: „Für Türen im Haus sollte eine Bestätigung
## angeboten werden, per Settings ausschaltbar"): Dialog erscheint bei AN,
## „Nein" bricht ab, „Ja" startet die Reise; bei AUS reist Gooby direkt.
## Der AppSettings-Schalter (Default an) ist mitgeprüft.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")
const AppSettingsScript := preload("res://scripts/core/app_settings.gd")
const TUER := "living_kueche"

var _seq := 0


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://fix3_tests/tuer_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	HomeState.ensure_initialized(gs)
	HomeState.set_flag(gs, HomeState.FLAG_BED_PLACED, true)
	return gs


func _make_room(gs: Node, confirm: int) -> RoomBase:
	var scene: PackedScene = load("res://scenes/home/wohnzimmer.tscn")
	var room: RoomBase = scene.instantiate()
	room.game_state_override = gs
	room.stunde_override = 13.0
	room.tuer_confirm_override = confirm
	tree.root.add_child(room)
	return room


func _cleanup(room: Node, gs: Node) -> void:
	room.queue_free()
	await wait_frames(2)
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()


## Knopf im Bestätigungs-Dialog: Index 0 = Ja, 1 = Nein (Aufbau-Reihenfolge).
func _dialog_knopf(room: RoomBase, index: int) -> Button:
	var knoepfe := room._choice.find_children("*", "Button", true, false)
	return knoepfe[index] as Button


func test_appsettings_schalter_default_an() -> void:
	# Frische Settings-Instanz mit eigenem Pfad — das Autoload bleibt in Ruhe.
	var pfad := "user://fix3_tests/settings_%d.json" % Time.get_ticks_usec()
	var settings: Node = AppSettingsScript.new(pfad)
	assert_true(settings.is_door_confirmation_enabled(), "Default: Bestätigung AN")
	settings.set_setting("door_confirmation", false)
	assert_false(settings.is_door_confirmation_enabled(), "Abschaltbar")
	settings.set_setting("door_confirmation", true)
	assert_true(settings.is_door_confirmation_enabled(), "Wieder einschaltbar")
	settings.free()


func test_dialog_erscheint_und_nein_bricht_ab() -> void:
	var gs := _fresh_gs()
	var room := _make_room(gs, 1)
	await wait_frames(6)
	var door: DoorTransition = room._doors[TUER]
	room._on_door_tapped(TUER)
	assert_true(room._choice != null, "Bestätigungs-Dialog erscheint")
	assert_eq(room._choice.name, "TuerConfirm", "… als Tür-Dialog")
	assert_false(door.is_busy(), "Reise startet NICHT vor der Bestätigung")
	_dialog_knopf(room, 1).pressed.emit()
	assert_true(room._choice == null, "Nein räumt den Dialog weg")
	assert_false(door.is_busy(), "Nein bricht die Reise ab")
	await _cleanup(room, gs)


func test_ja_startet_die_reise() -> void:
	var gs := _fresh_gs()
	var room := _make_room(gs, 1)
	await wait_frames(6)
	var door: DoorTransition = room._doors[TUER]
	room._on_door_tapped(TUER)
	assert_true(room._choice != null, "Dialog offen")
	_dialog_knopf(room, 0).pressed.emit()
	assert_true(room._choice == null, "Ja räumt den Dialog weg")
	assert_true(door.is_busy(), "Ja startet die Tür-Reise")
	await _cleanup(room, gs)


func test_aus_reist_direkt_ohne_dialog() -> void:
	var gs := _fresh_gs()
	var room := _make_room(gs, 0)
	await wait_frames(6)
	var door: DoorTransition = room._doors[TUER]
	room._on_door_tapped(TUER)
	assert_true(room._choice == null, "AUS: kein Dialog")
	assert_true(door.is_busy(), "AUS: Reise startet sofort")
	await _cleanup(room, gs)
