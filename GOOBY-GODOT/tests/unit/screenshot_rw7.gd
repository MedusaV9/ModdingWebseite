extends SceneTree
## RW-7-Screenshot-Tool (KEIN Test): Belege fuer Settings-Abschnitte,
## Dev-Menü, Perf-Overlay, Credits und Qualitaet Niedrig vs. Hoch. Aufruf:
## xvfb-run -a godot --rendering-method gl_compatibility \
##   --rendering-driver opengl3 --audio-driver Dummy --path . \
##   --script res://tests/unit/screenshot_rw7.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/RW7"

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SETTINGS_SCENE := preload("res://scripts/ui/settings_screen.tscn")

var _prev_preset: Variant
var _prev_dev_enabled: Variant
var _prev_dev_active: Variant
var _prev_overlay: Variant


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	var app := root.get_node_or_null("/root/AppSettings")
	if app == null:
		print("FEHLER: AppSettings fehlt")
		quit(1)
		return
	_prev_preset = app.value_of("graphics.preset")
	_prev_dev_enabled = app.get_setting("dev.enabled", false)
	_prev_dev_active = app.get_setting("dev.was_active", false)
	_prev_overlay = app.get_setting("dev.perf_overlay", false)
	await _shoot_settings_sections()
	# Qualitaetsvergleich VOR dem Dev-Teil: kein DEV-Badge und kein
	# Notbremsen-Banner im Bild (die Notbremse feuert im Dev-Teil absichtlich,
	# weil xvfb-llvmpipe weit unter dem Auto-Ziel liegt — guter Beleg dort).
	await _shoot_quality_compare(app)
	await _shoot_dev_menu()
	_restore(app)
	print("RW7-Screenshots fertig: %s" % OUT_DIR)
	quit(0)


## Settings-Screen hochkant mounten und zu jeder Sektion scrollen.
func _shoot_settings_sections() -> void:
	_set_window(Vector2i(900, 1600))
	var screen: Control = SETTINGS_SCENE.instantiate()
	root.add_child(screen)
	await process_frame
	await process_frame
	var scroll := screen.get_node("Margin/Layout/Scroll") as ScrollContainer
	var sections := screen.find_child("SectionsVBox", true, false) as VBoxContainer
	for card: Control in sections.get_children():
		scroll.scroll_vertical = int(card.position.y)
		await process_frame
		await process_frame
		var slug := card.name.replace("Section", "").to_lower()
		await _shot("settings_%s.png" % slug)
	# Credits ganz ans Ende scrollen (CC-BY-Namensnennungen komplett im Bild).
	scroll.scroll_vertical = 1 << 20
	await process_frame
	await process_frame
	await _shot("settings_credits_ende.png")
	screen.queue_free()
	await process_frame


## Dev-Modus aktivieren, Menü öffnen, Perf-Overlay einschalten.
func _shoot_dev_menu() -> void:
	_set_window(Vector2i(900, 1600))
	var dev := root.get_node_or_null("/root/Dev")
	if dev == null:
		print("FEHLER: Dev-Autoload fehlt")
		return
	dev.enable()
	await process_frame
	dev.open_menu()
	await process_frame
	await process_frame
	await _shot("dev_menu.png")
	var menu: Variant = dev.get("_menu")
	if menu != null:
		var scroll := (menu as Control).find_child("Scroll", true, false)
		if scroll is ScrollContainer:
			(scroll as ScrollContainer).scroll_vertical = 1 << 20
			await process_frame
			await process_frame
			await _shot("dev_menu_ende.png")
	dev.close_menu()
	await process_frame
	var overlay := root.get_node_or_null("/root/PerfOverlay")
	if overlay != null and overlay.has_method("set_shown"):
		overlay.set_shown(true)
		# Zwei Refresh-Zyklen abwarten, damit Zahlen im Overlay stehen.
		for _i in 40:
			await process_frame
		await _shot("dev_perf_overlay.png")
		overlay.set_shown(false)
	await process_frame


## Dieselbe 3D-Szene (Wohnzimmer) bei Qualitaet Niedrig vs. Hoch.
func _shoot_quality_compare(app: Node) -> void:
	_set_window(Vector2i(1280, 800))
	var dir := "user://rw7_shots/%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	HomeState.ensure_initialized(gs)
	var scene: PackedScene = load(str(RoomDefs.room("living")["scene"]))
	var room: Node = scene.instantiate()
	room.set("game_state_override", gs)
	room.set("stunde_override", 13.0)
	root.add_child(room)
	await process_frame
	var t0 := Time.get_ticks_msec()
	while bool(room.get("_rebake_pending")) and Time.get_ticks_msec() - t0 < 4000:
		await physics_frame
	# Kamera-Intro ausklingen lassen, damit beide Bilder dieselbe
	# Perspektive zeigen und NUR die Qualitaet sich unterscheidet.
	for _i in 90:
		await process_frame
	app.set_setting("graphics.preset", "niedrig")
	for _i in 5:
		await process_frame
	await _shot("qualitaet_niedrig.png")
	app.set_setting("graphics.preset", "hoch")
	for _i in 5:
		await process_frame
	await _shot("qualitaet_hoch.png")
	room.queue_free()
	await process_frame
	gs.free()


func _restore(app: Node) -> void:
	app.set_setting("graphics.preset", _prev_preset)
	app.set_setting("dev.perf_overlay", _prev_overlay)
	var dev := root.get_node_or_null("/root/Dev")
	if dev != null and dev.has_method("disable") and not bool(_prev_dev_enabled):
		dev.disable()
	app.set_setting("dev.enabled", _prev_dev_enabled)
	app.set_setting("dev.was_active", _prev_dev_active)


func _set_window(size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	root.size = size


func _shot(file: String) -> void:
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("shot: %s" % file)
