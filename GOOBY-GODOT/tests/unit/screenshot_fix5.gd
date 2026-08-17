extends SceneTree
## FIX5-Screenshot-Tool (KEIN Test — kein test_-Präfix): rendert die
## Stadt-Deliverables des „Stadt ist leer“-Fixes als Review-Artefakte:
## Stadt bei Tag (Übersicht + Straßenniveau), Stadt bei Nacht, Fahrt-Start
## an der Hausausfahrt, drei Ladenfassaden, Verkehr + Fußgänger. Druckt je
## Shot die Draw-Calls des Frames (Budget-Nachweis ≤ 400).
## Braucht einen echten Renderer (xvfb):
## FIX5_MODE=vorher|nachher xvfb-run -a godot --path . \
##   --rendering-method gl_compatibility --rendering-driver opengl3 \
##   --script res://tests/unit/screenshot_fix5.gd
## FIX5_MODE=vorher macht nur die „leere Stadt“-Referenz-Shots.

const OUT_DIR := "/tmp/gooby-godot/artifacts/FIX5"
const SETTLE_FRAMES := 24

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

var _seq := 0
var _prefix := "nachher"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.theme = ThemeService.theme()
	_resize(Vector2i(1280, 720))
	var modus := OS.get_environment("FIX5_MODE")
	_prefix = "vorher" if modus == "vorher" else "nachher"
	await _shot_stadt_tag()
	await _shot_stadt_nacht()
	if _prefix != "vorher":
		await _shot_ausfahrt()
		await _shot_fassaden()
	print("FIX5-Screenshots fertig → %s" % OUT_DIR)
	quit(0)


func _resize(win_size: Vector2i) -> void:
	DisplayServer.window_set_size(win_size)
	root.size = win_size


func _make_gs() -> Node:
	_seq += 1
	var dir := "user://fix5_shots/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	CityState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	gs.set_value("economy.coins", 300)
	return gs


func _teardown(node: Node, gs: Node) -> void:
	PanelStack.clear()
	node.queue_free()
	await process_frame
	await process_frame
	gs.free()
	SaveSchema.unregister_slice(CityState.SLICE_ID)
	CityState.reset_for_tests()


func _stadt(stunde: float, gs: Node) -> CityScene:
	var city: CityScene = load("res://scenes/city/city_scene.tscn").instantiate()
	city.game_state_override = gs
	city.stunde_override = stunde
	root.add_child(city)
	for _i in 20:
		await process_frame
	return city


## Tag: Übersicht von oben + Straßenniveau im Zentrum + Verkehr/Fußgänger.
func _shot_stadt_tag() -> void:
	var gs := _make_gs()
	var city: CityScene = await _stadt(11.0, gs)
	city.auto.set_frozen(true)
	city.hud.visible = false
	var top := Camera3D.new()
	city.add_child(top)
	top.position = Vector3(0.0, 165.0, 135.0)
	top.look_at(Vector3(0.0, 0.0, -10.0))
	top.current = true
	await _snap("%s_stadt_tag_uebersicht.png" % _prefix)
	# Straßenniveau: Blick die Zentrums-Straße (Reihe 5/6) entlang.
	var strasse: Vector3 = city.karte.tile_zu_welt(Vector2i(4, 6))
	top.position = strasse + Vector3(0.0, 3.2, 26.0)
	top.look_at(strasse + Vector3(0.0, 1.6, -30.0))
	await _snap("%s_stadt_tag_strassenniveau.png" % _prefix)
	# Verkehr + Fußgänger: Blick AUF der REHWEI-Straße entlang (Spalte 1) —
	# Kamera steht auf der Fahrbahn, nicht in der Kulisse.
	var ecke: Vector3 = city.karte.tile_zu_welt(Vector2i(5, 1))
	top.position = ecke + Vector3(2.0, 5.0, 28.0)
	top.look_at(ecke + Vector3(0.0, 1.0, -25.0))
	await _snap("%s_verkehr_und_fussgaenger.png" % _prefix)
	await _teardown(city, gs)


## Nacht: Übersicht + Straßenniveau (Laternen, Fenster, Schilder-Glow).
func _shot_stadt_nacht() -> void:
	var gs := _make_gs()
	var city: CityScene = await _stadt(22.0, gs)
	city.auto.set_frozen(true)
	city.hud.visible = false
	var top := Camera3D.new()
	city.add_child(top)
	top.position = Vector3(0.0, 165.0, 135.0)
	top.look_at(Vector3(0.0, 0.0, -10.0))
	top.current = true
	await _snap("%s_stadt_nacht_uebersicht.png" % _prefix)
	var strasse: Vector3 = city.karte.tile_zu_welt(Vector2i(5, 3))
	top.position = strasse + Vector3(-4.0, 3.0, 30.0)
	top.look_at(strasse + Vector3(2.0, 2.0, -20.0))
	await _snap("%s_stadt_nacht_strassenniveau.png" % _prefix)
	await _teardown(city, gs)


## Fahrt-Start: Chase-Cam-Blick direkt nach dem Spawn in der Einfahrt.
func _shot_ausfahrt() -> void:
	var gs := _make_gs()
	var city: CityScene = await _stadt(11.0, gs)
	city.auto.set_frozen(true)
	await _snap("nachher_fahrtstart_einfahrt.png")
	# … und der Moment des Rückwärts-Ausparkens (Sequenz kurz laufen lassen).
	city.auto.set_frozen(false)
	for _i in 55:
		await physics_frame
	city.auto.set_frozen(true)
	await _snap("nachher_fahrtstart_ausparken.png")
	await _teardown(city, gs)


## Drei Ladenfassaden aus Fußgänger-Sicht: REHWEI, Autohaus, Baumarkt.
func _shot_fassaden() -> void:
	var gs := _make_gs()
	var city: CityScene = await _stadt(11.0, gs)
	city.auto.set_frozen(true)
	city.hud.visible = false
	var cam := Camera3D.new()
	city.add_child(cam)
	cam.current = true
	var ziele := [
		{"ort": "rehwei", "datei": "nachher_fassade_rehwei.png"},
		{"ort": "autohaus", "datei": "nachher_fassade_autohaus.png"},
		{"ort": "baumarkt", "datei": "nachher_fassade_baumarkt.png"},
	]
	for ziel: Dictionary in ziele:
		var eintrag: Dictionary = city.karte.ort(str(ziel["ort"]))
		var mitte: Vector3 = city.karte.tile_zu_welt(
			CityMap._tile_von(eintrag.get("tiles", [[0, 0]])[0])
		)
		var strasse: Vector3 = city.karte.tile_zu_welt(
			CityMap._tile_von(eintrag.get("strasse", [0, 0]))
		)
		var richtung := (strasse - mitte).normalized()
		cam.position = mitte + richtung * 24.0 + Vector3(0.0, 3.4, 0.0)
		cam.look_at(mitte + Vector3(0.0, 4.5, 0.0))
		await _snap(str(ziel["datei"]))
	await _teardown(city, gs)


func _snap(file: String) -> void:
	for _i in SETTLE_FRAMES:
		await process_frame
	var draw_calls := RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
	)
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print(
		(
			"  gespeichert: %s (%dx%d) — draw_calls=%d"
			% [file, image.get_width(), image.get_height(), draw_calls]
		)
	)
