extends SceneTree
## ORTE-Screenshot-Tool (KEIN Test — kein test_-Präfix): rendert die M2-ORTE-
## Deliverables als Review-Artefakte: IGohbie-Handy (Grid + eine App), die
## vier neuen Läden mit ihrem Händler-UI, den Wochenmarkt unter freiem
## Himmel, einen Dialog und die Stadt bei Nacht (Schilder-Glow + Minimap).
## Braucht einen echten Renderer (xvfb):
## xvfb-run -a godot --path . --rendering-method gl_compatibility \
##   --rendering-driver opengl3 --script res://tests/unit/screenshot_orte.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/ORTE"
const SETTLE_FRAMES := 24

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

var _seq := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.theme = ThemeService.theme()
	_resize(Vector2i(1280, 720))
	await _shot_handy()
	await _shot_ort("pow", "pow", true)
	await _shot_ort("autohaus", "autohaus", true)
	await _shot_ort("baumarkt", "baumarkt", true)
	await _shot_ort("wochenmarkt", "wochenmarkt", true)
	await _shot_ort("post", "post_dialog", false)
	await _shot_stadt_nacht()
	print("Screenshots fertig → %s" % OUT_DIR)
	quit(0)


func _resize(win_size: Vector2i) -> void:
	DisplayServer.window_set_size(win_size)
	root.size = win_size


func _make_gs() -> Node:
	_seq += 1
	var dir := "user://orte_shots/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	CityState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	gs.set_value("economy.coins", 900)
	# Erntekorb füllen, damit der Wochenmarkt etwas zu kaufen hat.
	gs.update(
		func(state: Dictionary) -> void:
			var food: Dictionary = state["inventory"]["food"]
			food["carrot"] = 12
			food["pumpkin"] = 3
			food["tomato"] = 7
	)
	return gs


func _teardown(node: Node, gs: Node) -> void:
	PanelStack.clear()
	node.queue_free()
	await process_frame
	await process_frame
	gs.free()
	SaveSchema.unregister_slice(CityState.SLICE_ID)
	CityState.reset_for_tests()


## Ein Ort: Innenraum + (optional) sein Händler-UI, sonst der Dialog.
func _shot_ort(ort_id: String, datei: String, mit_laden: bool) -> void:
	var gs := _make_gs()
	var ort: OrtScene = load("res://scenes/city/orte/%s.tscn" % ort_id).instantiate()
	ort.game_state_override = gs
	root.add_child(ort)
	for _i in 40:
		await process_frame
	if mit_laden:
		ort.oeffne_laden()
		for _i in 50:
			await process_frame
	await _snap("%s.png" % datei)
	await _teardown(ort, gs)


## IGohbie: App-Grid (Kamera gesperrt), dann dieselbe Shell mit gekaufter
## Kamera und offener Guber-App.
func _shot_handy() -> void:
	var gs := _make_gs()
	var host := Node.new()
	root.add_child(host)
	var shell := PhoneShell.oeffne(host, gs)
	for _i in 45:
		await process_frame
	await _snap("handy_grid.png")
	gs.update(func(state: Dictionary) -> void: state["inventory"]["items"]["kamera"] = 1)
	shell.zeige_grid()
	for _i in 20:
		await process_frame
	await _snap("handy_grid_mit_kamera.png")
	shell.oeffne_app("guber")
	for _i in 40:
		await process_frame
	await _snap("handy_guber.png")
	await _teardown(host, gs)


## Stadt nach Sonnenuntergang: leuchtende Ladenschilder, Laternen, Minimap.
func _shot_stadt_nacht() -> void:
	var gs := _make_gs()
	var city: CityScene = load("res://scenes/city/city_scene.tscn").instantiate()
	city.game_state_override = gs
	city.stunde_override = 21.5
	root.add_child(city)
	for _i in 30:
		await process_frame
	# Weit genug vor Rehwei/Goobytheke, damit beide Leuchtschilder ganz im
	# Bild stehen und nicht hinter der Minimap kleben.
	var strasse: Vector3 = city.karte.tile_zu_welt(Vector2i(3, 1))
	city.auto.teleport(strasse.x, strasse.z, 0.0)
	city.cam.snap()
	for _i in 60:
		await physics_frame
	city.auto.set_frozen(true)
	await _snap("stadt_nacht_schilder.png")
	await _teardown(city, gs)


func _snap(file: String) -> void:
	for _i in SETTLE_FRAMES:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("  gespeichert: %s (%dx%d)" % [file, image.get_width(), image.get_height()])
