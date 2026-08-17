extends SceneTree
## WELT2-Screenshot-Tool (KEIN Test — kein test_-Präfix): rendert Vorher/
## Nachher-Artefakte für den Asset-Tausch (User: „warum so vieles nur
## Primitives?"). Feste Kameras pro Raum + Nahaufnahmen der ersetzten
## Objekte — identische Posen in beiden Phasen. Aufruf (echter Renderer):
##   WELT2_PHASE=vorher xvfb-run -a godot --path . \
##     --rendering-method gl_compatibility --rendering-driver opengl3 \
##     --audio-driver Dummy --script res://tests/unit/welt2_screens.gd
##
## Phase „nachher" nach dem Asset-Tausch mit WELT2_PHASE=nachher.

const OUT_ROOT := "/tmp/gooby-godot/artifacts/WELT2"
const SETTLE := 40

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

var _out_dir := ""
var _seq := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var phase := OS.get_environment("WELT2_PHASE")
	if phase == "":
		phase = "vorher"
	_out_dir = "%s/%s" % [OUT_ROOT, phase]
	DirAccess.make_dir_recursive_absolute(_out_dir)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	await _raum_shots(
		"living",
		[
			["raum_living", Vector3(3.0, 5.2, 9.6), Vector3(3.0, 0.6, 2.4)],
			["nah_tuer", Vector3(1.5, 1.6, 2.8), Vector3(1.5, 1.0, 0.0)],
			["nah_fenster_attrappe", Vector3(4.5, 1.7, 2.6), Vector3(4.5, 1.4, 0.0)],
			["nah_fenster_modul", Vector3(2.9, 1.9, 2.7), Vector3(2.9, 1.6, 0.0)],
		],
		func(room: RoomBase) -> void: _fenster_einbauen(room)
	)
	await _raum_shots(
		"kitchen",
		[
			["raum_kitchen", Vector3(2.5, 4.6, 8.0), Vector3(2.5, 0.6, 2.0)],
			["nah_kueche_zeile", Vector3(2.4, 1.4, 2.6), Vector3(2.4, 0.8, 0.2)],
		],
		Callable()
	)
	await _raum_shots(
		"bathroom",
		[
			["raum_bathroom", Vector3(2.0, 4.2, 7.0), Vector3(2.0, 0.6, 1.75)],
			["nah_dusche_vorhang", Vector3(3.0, 1.5, 3.4), Vector3(3.0, 0.9, 0.5)],
		],
		func(room: RoomBase) -> void: _vorhang_zeigen(room)
	)
	await _raum_shots(
		"bedroom",
		[
			["raum_bedroom", Vector3(2.5, 4.6, 8.0), Vector3(2.5, 0.6, 2.0)],
		],
		Callable()
	)
	await _raum_shots(
		"garden",
		[
			["raum_garden", Vector3(7.0, 9.5, 17.5), Vector3(7.0, 0.3, 5.5)],
			["nah_shed", Vector3(3.3, 2.2, 7.6), Vector3(3.3, 1.0, 4.9)],
			["nah_werkstatt", Vector3(6.6, 2.4, 8.2), Vector3(6.6, 1.0, 4.9)],
			["nah_gewaechshaus", Vector3(9.6, 2.2, 9.4), Vector3(9.6, 1.0, 6.4)],
			["nah_sprinkler_beete", Vector3(5.5, 1.6, 9.9), Vector3(5.5, 0.25, 8.3)],
			# Nachher-Extra: der Sprinkler selbst (Zelle (2,4) → Welt (4.5, 6.5));
			# Blick von Norden, damit Gooby (spawnt südlich) nicht verdeckt.
			["nah_sprinkler", Vector3(4.5, 1.2, 5.1), Vector3(4.5, 0.35, 6.5)],
		],
		func(room: RoomBase) -> void: _garten_bestuecken(room)
	)
	print("WELT2-Screenshots fertig -> %s" % _out_dir)
	quit(0)


## Einen Raum mit frischem Save laden, deterministisch stellen, Shots machen.
func _raum_shots(room_id: String, shots: Array, vorbereiten: Callable) -> void:
	_seq += 1
	var dir := "user://welt2_shots/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	HomeState.ensure_initialized(gs)
	var scene: PackedScene = load(str(RoomDefs.room(room_id)["scene"]))
	var room: RoomBase = scene.instantiate()
	room.game_state_override = gs
	room.stunde_override = 13.0
	root.add_child(room)
	await _settle(20)
	var gooby := room.gooby()
	if gooby != null:
		gooby.set_wander_enabled(false)
		var size := Vector2(
			(room.room_def()["grid"] as Vector2i).x * GridData.CELL_SIZE,
			(room.room_def()["grid"] as Vector2i).y * GridData.CELL_SIZE
		)
		gooby.global_position = Vector3(size.x * 0.32, 0.0, size.y * 0.62)
	if vorbereiten.is_valid():
		vorbereiten.call(room)
	await _settle(SETTLE)
	var cam := Camera3D.new()
	cam.fov = 45.0
	room.add_child(cam)
	cam.make_current()
	for shot: Array in shots:
		cam.global_position = shot[1]
		cam.look_at(shot[2])
		await _settle(6)
		await _shot(str(shot[0]))
	room.queue_free()
	await process_frame
	await process_frame
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()


## Wohnzimmer: ein gekauftes Fenster-Modul an die Nordwand hängen (Offset 5,
## neben der Attrappe) — zeigt HomeProps.fenster inkl. Wand-Ausschnitt.
func _fenster_einbauen(room: RoomBase) -> void:
	var def := FurnitureCatalog.def("window_small")
	room.grid.place_wall(def, "N", 5, "welt2-fenster")
	room.rebuild_furniture()


## Bad: Dusch-Routine-Optik erzwingen (Vorhang + Silhouette sichtbar).
func _vorhang_zeigen(room: RoomBase) -> void:
	var host := InteractablesHost.attach_to(room)
	for child in host.get_children():
		if child is KloDusche:
			child._show_curtain(true)
			return


## Garten: Grid erweitern, alle Bauten setzen, Beete bepflanzen, Spots legen.
func _garten_bestuecken(room: RoomBase) -> void:
	var gs := room.game_state()
	GardenState.erweitern(gs)
	GardenState.erweitern(gs)
	gs.update(func(state: Dictionary) -> void: state["home"]["shedStufe"] = 2)
	var grid := GardenState.grid(gs)
	grid.place_structure("shed", Vector2i(0, 0))
	grid.place_structure("werkstatt", Vector2i(3, 0))
	grid.place_structure("gewaechshaus", Vector2i(8, 2), 0, Vector2i(8, 2))
	grid.place_structure("sprinkler", Vector2i(2, 4))
	grid.place_structure("baum", Vector2i(6, 5))
	GardenState.save_grid(gs, grid)
	for eintrag: Array in [
		[Vector2i(0, 4), "carrot", 3],
		[Vector2i(1, 4), "tomate", 2],
		[Vector2i(0, 5), "salat", 2],
		[Vector2i(1, 5), "pilz", 1],
		[Vector2i(3, 4), "melone", 4],
		[Vector2i(4, 4), "chili", 3],
		[Vector2i(3, 5), "ananas", 2],
		[Vector2i(4, 5), "carrot", 1],
	]:
		GardenState.pflanzen(gs, eintrag[0], str(eintrag[1]))
		var beet_grid := GardenState.grid(gs)
		var data := beet_grid.cell(eintrag[0])
		if not data.is_empty():
			data["stage"] = int(eintrag[2])
			beet_grid.set_cell(eintrag[0], data)
			GardenState.save_grid(gs, beet_grid)
	gs.update(
		func(state: Dictionary) -> void:
			state["garden"]["spots"] = [
				{"at": [6, 6], "material": "stock"},
				{"at": [2, 6], "material": "blatt"},
			]
	)
	var host: GardenHost = room.get_node_or_null("GardenHost")
	if host != null:
		host.view().rebuild(
			Vector2(
				(room.room_def()["grid"] as Vector2i).x * GridData.CELL_SIZE,
				(room.room_def()["grid"] as Vector2i).y * GridData.CELL_SIZE
			)
		)


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame


func _shot(file: String) -> void:
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s.png" % [_out_dir, file])
	print("shot: %s" % file)
