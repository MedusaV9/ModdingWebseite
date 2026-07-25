extends SceneTree
## W3a-Screenshot-Tool (KEIN Test — kein test_-Präfix): rendert die
## CITY-Deliverables als Review-Artefakte: Stadt-Überblick, Fahrt-Moment
## (Chase-Cam + HUD), REHWEI-Laden-Sheet, Arzt-Dialog, Reise-Cutscene
## Taxi-Shot und GOOBERANDO-Sheet (Menü + Liefer-Gooby).
## Braucht einen echten Renderer (xvfb):
## xvfb-run -a godot --path . --rendering-method gl_compatibility \
##   --rendering-driver opengl3 --script res://tests/unit/screenshot_w3a.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/W3a"
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
	await _shot_stadt_und_fahrt()
	await _shot_rehwei()
	await _shot_arzt()
	await _shot_cutscene_taxi()
	await _shot_gooberando()
	print("Screenshots fertig → %s" % OUT_DIR)
	quit(0)


func _resize(win_size: Vector2i) -> void:
	DisplayServer.window_set_size(win_size)
	root.size = win_size


func _make_gs() -> Node:
	_seq += 1
	var dir := "user://w3a_shots/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	CityState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	gs.set_value("economy.coins", 300)
	return gs


func _teardown(node: Node, gs: Node) -> void:
	# Offene Sheets abmelden BEVOR sie gefreed werden — sonst stolpert
	# PanelStack._prune beim nächsten push über die tote Referenz.
	PanelStack.clear()
	node.queue_free()
	await process_frame
	await process_frame
	gs.free()
	SaveSchema.unregister_slice(CityState.SLICE_ID)
	CityState.reset_for_tests()


func _shot_stadt_und_fahrt() -> void:
	var gs := _make_gs()
	var city: CityScene = load("res://scenes/city/city_scene.tscn").instantiate()
	city.game_state_override = gs
	root.add_child(city)
	for _i in 20:
		await process_frame
	# Auto einfrieren, damit es während des Überblicks nicht davonfährt
	# (xvfb rendert langsam — Physik läuft real weiter).
	city.auto.set_frozen(true)
	city.hud.visible = false
	var top := Camera3D.new()
	city.add_child(top)
	top.position = Vector3(0.0, 150.0, 130.0)
	top.look_at(Vector3(0.0, 0.0, -10.0))
	top.current = true
	await _snap("stadt_ueberblick.png")
	# Fahrt-Moment: auf die REHWEI-Straße setzen, kontrolliert ~1,3 s fahren
	# (physics_frame = deterministisch), dann mit Chase-Cam + HUD einfrieren.
	city.hud.visible = true
	top.current = false
	var strasse: Vector3 = city.karte.tile_zu_welt(Vector2i(5, 1))
	city.auto.teleport(strasse.x, strasse.z, 0.0)
	city.cam.current = true
	city.cam.snap()
	city.auto.set_frozen(false)
	for _i in 80:
		await physics_frame
	city.auto.set_frozen(true)
	await _snap("fahrt_moment.png")
	await _teardown(city, gs)


func _shot_rehwei() -> void:
	var gs := _make_gs()
	var ort: OrtScene = load("res://scenes/city/orte/rehwei.tscn").instantiate()
	ort.game_state_override = gs
	root.add_child(ort)
	for _i in 40:
		await process_frame
	ort.oeffne_laden()
	for _i in 50:
		await process_frame
	await _snap("rehwei_laden_sheet.png")
	await _teardown(ort, gs)


func _shot_arzt() -> void:
	var gs := _make_gs()
	var ort: OrtScene = load("res://scenes/city/orte/gouhbus.tscn").instantiate()
	ort.game_state_override = gs
	root.add_child(ort)
	for _i in 50:
		await process_frame
	await _snap("arzt_dialog_bubble.png")
	# Bubble durchblättern → Options-Knöpfe („Gooby ist krank.“ etc.).
	ort.dialog._bubble._advance()
	for _i in 10:
		await process_frame
	ort.dialog._bubble._advance()
	for _i in 20:
		await process_frame
	await _snap("arzt_dialog_optionen.png")
	await _teardown(ort, gs)


func _shot_cutscene_taxi() -> void:
	var cut: ReiseCutscene = load("res://scenes/city/reise_cutscene.tscn").instantiate()
	cut.ziel_id = "beach"
	root.add_child(cut)
	# Shot 3 (Taxi am Bordstein) beginnt bei ~7,2 s; Anfahrt-Tween 2,6 s.
	await create_timer(9.4).timeout
	await _snap("reise_cutscene_taxi.png")
	cut.skip()
	await create_timer(0.5).timeout
	cut.queue_free()
	await process_frame


func _shot_gooberando() -> void:
	var gs := _make_gs()
	var host := Node.new()
	root.add_child(host)
	var app := GooberandoApp.oeffne(host, gs)
	for _i in 50:
		await process_frame
	await _snap("gooberando_sheet.png")
	# Liefer-Moment: Slice auf VOR_DER_TUER → oranger Liefer-Gooby + Klingel.
	var slice := GooberandoLogic.default_slice()
	slice["state"] = GooberandoLogic.STATE_VOR_DER_TUER
	slice["gerichtId"] = "pizza"
	slice["bestelltAt"] = app.now_ms() - 1000
	slice["fertigAt"] = app.now_ms()
	CityState.save_gooberando_slice(gs, slice)
	app._render()
	for _i in 40:
		await process_frame
	await _snap("gooberando_lieferung.png")
	await _teardown(host, gs)


func _snap(file: String) -> void:
	for _i in SETTLE_FRAMES:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("  gespeichert: %s (%dx%d)" % [file, image.get_width(), image.get_height()])
