extends SceneTree
## HAUS-SICHT-Screenshot-Tool (KEIN Test — kein test_-Präfix): rendert die
## Review-Artefakte für den Umbau „Räume/Garten als Teil eines Hauses +
## Vorstadt-Kulisse im Baumodus". Phasen über HAUSSICHT_PHASE:
##   vorher  — Ist-Zustand der Baumodus-Kulisse (3 Winkel) + Garten
##   nachher — Garten mit Haus (2 Winkel), Fensterblick in den Garten,
##             Raum mit Nachbarraum-Andeutung/Dachschräge, Baumodus-Kulisse
##             (3 Winkel), Übergang Garten→Haus. Zusätzlich Draw-Call-Zahlen
##             (RENDER_TOTAL_DRAW_CALLS_IN_FRAME) pro Motiv.
## Aufruf:
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/unit/haussicht_screens.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/HAUSSICHT"
const SETTLE := 40

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

var _phase := "nachher"
var _gs: Node


func _init() -> void:
	_phase = OS.get_environment("HAUSSICHT_PHASE")
	if _phase == "":
		_phase = "nachher"
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	var dir := "user://haussicht_shots/%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	_gs = GameStateScript.new()
	_gs.initialize(dir + "/save_v5.json")
	HomeState.ensure_initialized(_gs)
	HomeState.set_flag(_gs, HomeState.FLAG_BED_PLACED, true)
	# Ein erkennbarer, gekaufter Stil — der Garten-Screenshot muss zeigen,
	# dass HouseStyleState wirklich übernommen wird.
	_gs.update(
		func(state: Dictionary) -> void:
			state["home"]["style"] = {
				"haus":
				{
					"fassade": "butter",
					"dachForm": "sattel",
					"dachFarbe": "ziegelrot",
					"tuerFarbe": "teal",
					"vordach": "markise_gestreift",
					"vordachFarbe": "rose",
					"hausnummerZahl": 7,
				},
				"grundstueck": {"zaun": "latten", "zaunFarbe": "weiss"},
			}
	)
	await _baumodus_shots("living", _phase)
	await _garten_shots()
	if _phase == "nachher":
		await _baumodus_garten()
		await _fenster_shots()
		await _raum_shots()
		await _uebergang_shots()
	print("Screenshots fertig -> %s" % OUT_DIR)
	_gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()
	quit(0)


## Baumodus-Kulisse aus 3 Kamerawinkeln (frei schwenkbare Kamera!).
func _baumodus_shots(room_id: String, prefix: String) -> void:
	var room := await _open_room(room_id, "")
	room.open_build_mode()
	var build: BuildMode = room.get_node("BuildMode")
	var cam := build.build_camera()
	# Rauszoomen, damit die Kulisse im Bild ist.
	for _i in 4:
		cam.zoom_um(1.0 / 1.25)
	var winkel: Array = [0.0, PI * 0.72, -PI * 0.45]
	for i in winkel.size():
		cam.rotate_um(float(winkel[i]) - cam.yaw())
		await _settle(70)
		_print_draw_calls("baumodus %s winkel%d" % [prefix, i + 1])
		await _shot("baumodus_%s_winkel%d.png" % [prefix, i + 1])
	build.close()
	await _close_room(room)


## Baumodus im GARTEN: Haus + Kulisse zusammen — der Draw-Call-Peak.
func _baumodus_garten() -> void:
	var room := await _open_room("garden", "garten_living")
	room.open_build_mode()
	var build: BuildMode = room.get_node("BuildMode")
	var cam := build.build_camera()
	for _i in 3:
		cam.zoom_um(1.0 / 1.25)
	cam.rotate_um(PI * 0.6 - cam.yaw())
	await _settle(70)
	_print_draw_calls("baumodus garten")
	await _shot("baumodus_%s_garten.png" % _phase)
	build.close()
	await _close_room(room)


## Garten: Haus mit Dach steht am Nordrand (nachher) bzw. Ist-Zustand.
func _garten_shots() -> void:
	var room := await _open_room("garden", "garten_living")
	var rig: HomeCameraRig = room.camera_rig()
	rig.set_process(false)
	# Winkel 1: von Süd-Ost schräg auf Haus + Garten.
	rig.camera.global_position = Vector3(11.5, 5.4, 11.0)
	rig.camera.look_at(Vector3(7.0, 1.4, -1.5))
	await _settle(SETTLE)
	_print_draw_calls("garten winkel1")
	await _shot("garten_haus_%s_winkel1.png" % _phase)
	# Winkel 2: tief von Süd-West auf die Eingangstür.
	rig.camera.global_position = Vector3(3.2, 1.9, 7.6)
	rig.camera.look_at(Vector3(7.0, 1.7, -1.0))
	await _settle(20)
	await _shot("garten_haus_%s_winkel2.png" % _phase)
	await _close_room(room)


## Blick aus dem Küchenfenster in den Garten (echtes Fenster einhängen).
func _fenster_shots() -> void:
	var room := await _open_room("kitchen", "")
	var def := FurnitureCatalog.def("window_small")
	room.grid.place_wall(def, "N", 4, "haussicht-fenster")
	room.rebuild_furniture()
	await _settle(SETTLE)
	var rig: HomeCameraRig = room.camera_rig()
	rig.set_process(false)
	rig.camera.global_position = Vector3(2.25, 1.55, 3.4)
	rig.camera.look_at(Vector3(2.25, 1.35, -3.0))
	await _settle(20)
	_print_draw_calls("kueche fensterblick")
	await _shot("raumfenster_garten.png")
	await _close_room(room)


## Schlafzimmer (Dachgeschoss): Dachschräge + Blick zur offenen Tür.
func _raum_shots() -> void:
	var room := await _open_room("bedroom", "schlafzimmer_living")
	await _settle(SETTLE)
	var rig: HomeCameraRig = room.camera_rig()
	rig.set_process(false)
	rig.camera.global_position = Vector3(2.5, 4.4, 7.6)
	rig.camera.look_at(Vector3(2.5, 1.2, 0.6))
	await _settle(20)
	_print_draw_calls("schlafzimmer")
	await _shot("raum_dachschraege.png")
	# Tür öffnen: dahinter der angedeutete Nachbarraum (Wohnzimmer).
	var tuer: DoorTransition = room.get_node("Door_schlafzimmer_living")
	tuer._open_panel()
	await _settle(30)
	rig.camera.global_position = Vector3(2.2, 2.1, 3.4)
	rig.camera.look_at(Vector3(5.4, 1.0, 1.9))
	await _settle(20)
	await _shot("raum_nachbarraum_hinter_tuer.png")
	await _close_room(room)


## Übergang Garten→Haus: Gooby steht an der Tür, die auch außen sichtbar ist.
func _uebergang_shots() -> void:
	var room := await _open_room("garden", "garten_living")
	var rig: HomeCameraRig = room.camera_rig()
	rig.set_process(false)
	rig.camera.global_position = Vector3(7.0, 2.6, 6.0)
	rig.camera.look_at(Vector3(7.0, 1.4, -0.5))
	await _settle(SETTLE)
	await _shot("uebergang_1_garten_vor_tuer.png")
	var tuer: DoorTransition = room.get_node("Door_garten_living")
	tuer._open_panel()
	await _settle(24)
	await _shot("uebergang_2_tuer_offen.png")
	await _close_room(room)
	# Drüben: im Wohnzimmer an der Gartentür (to_door living_garten).
	var living := await _open_room("living", "living_garten")
	await _settle(SETTLE)
	await _shot("uebergang_3_wohnzimmer_an_gartentuer.png")
	await _close_room(living)


func _open_room(room_id: String, door_id: String) -> RoomBase:
	var pfad: String = RoomDefs.room(room_id)["scene"]
	var scene: PackedScene = load(pfad)
	var room: RoomBase = scene.instantiate()
	room.game_state_override = _gs
	room.stunde_override = 13.0
	if door_id != "":
		room.receive_params({"door_id": door_id})
	root.add_child(room)
	await _settle(60)
	return room


func _close_room(room: Node) -> void:
	root.remove_child(room)
	room.queue_free()
	await _settle(4)


func _print_draw_calls(label: String) -> void:
	var calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	print("  draw_calls[%s] = %d" % [label, calls])


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame


func _shot(file: String) -> void:
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("shot: %s" % file)
