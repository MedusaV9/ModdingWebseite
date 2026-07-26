extends SceneTree
## FIX-3-Screenshot-Tool (KEIN Test — kein test_-Präfix): rendert die
## Review-Artefakte — Baumodus mit geschwenkter Kamera (3 Winkel), die
## Stadt-Kulisse mit Auto + Gooby-Passant, den Tür-Bestätigungs-Dialog und
## den Raum mit den echten GLB-Assets. Aufruf (echter Renderer):
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/unit/fix3_screenshots.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/FIX3"
const SETTLE := 45

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	var dir := "user://fix3_shots/%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	HomeState.ensure_initialized(gs)
	for item: String in ["chair", "table", "pottedPlant"]:
		HomeState.store_item(gs, item)
	HomeState.set_flag(gs, HomeState.FLAG_BED_PLACED, true)
	var scene: PackedScene = load("res://scenes/home/wohnzimmer.tscn")
	var room: RoomBase = scene.instantiate()
	room.game_state_override = gs
	room.stunde_override = 13.0
	room.tuer_confirm_override = 1
	root.add_child(room)
	await _settle(90)
	# 1) Raum mit echten GLB-Assets (Tür + Fußmatte, Sockelleisten,
	#    Fensterbank-Deko, Boden-Dielen).
	await _shot("raum_glb_assets.png")
	# 2) Tür-Bestätigungs-Dialog.
	room._on_door_tapped("living_kueche")
	await _settle(10)
	await _shot("tuer_dialog.png")
	if room._choice != null:
		var knoepfe := room._choice.find_children("*", "Button", true, false)
		(knoepfe[1] as Button).pressed.emit()  # Nein
	await _settle(5)
	# 3) Baumodus, Winkel 1: Standard-Schrägsicht.
	room.open_build_mode()
	var build: BuildMode = room.get_node("BuildMode")
	var cam := build.build_camera()
	await _settle(SETTLE)
	await _shot("baumodus_winkel1_schraeg.png")
	# 4) Winkel 2: 90° gedreht + zur Seite geschwenkt.
	cam.schnapp_90(1)
	cam.pan_screen(Vector2(640, 360), Vector2(760, 420))
	await _settle(SETTLE)
	await _shot("baumodus_winkel2_gedreht_geschwenkt.png")
	# 5) Winkel 3: Draufsicht.
	cam.set_draufsicht(true)
	await _settle(SETTLE)
	await _shot("baumodus_winkel3_draufsicht.png")
	# 6) Stadt-Kulisse: Schrägsicht, ganz rausgezoomt — Autos + Passanten
	#    im Bild (Positionen werden zur Kontrolle geloggt).
	cam.set_draufsicht(false)
	cam.schnapp_90(-1)
	for _i in 12:
		cam.zoom_um(1.0 / BuildCamera.ZOOM_SCHRITT)
	await _settle(SETTLE + 15)
	_log_kulisse(room)
	await _shot("stadt_kulisse_schraeg.png")
	# 7) Stadt von oben, ganz rausgezoomt: der komplette Ring mit allen
	#    Autos, Passanten, Häusern und Bäumen ohne Perspektiv-Verzerrung.
	cam.set_draufsicht(true)
	await _settle(SETTLE + 15)
	_log_kulisse(room)
	await _shot("stadt_kulisse_draufsicht_auto_npc.png")
	print("Screenshots fertig -> %s" % OUT_DIR)
	build.close()
	room.queue_free()
	await process_frame
	await process_frame
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()
	quit(0)


func _log_kulisse(room: RoomBase) -> void:
	var kamera: Camera3D = room.camera_rig().camera
	var skyline := room.skyline()
	for auto: Dictionary in skyline._autos:
		var node: Node3D = auto["node"]
		if not kamera.is_position_behind(node.global_position):
			print(
				(
					"  auto im Bild: %s @ %s"
					% [node.name, kamera.unproject_position(node.global_position)]
				)
			)
	for npc: Dictionary in skyline._npcs:
		var node: Node3D = npc["node"]
		if not kamera.is_position_behind(node.global_position):
			print(
				(
					"  npc im Bild: %s @ %s"
					% [node.name, kamera.unproject_position(node.global_position)]
				)
			)


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame


func _shot(file: String) -> void:
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("shot: %s" % file)
