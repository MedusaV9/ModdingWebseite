extends SceneTree
## FIX1-Beleg-Treiber (KEIN Test — kein test_-Präfix): bootet das ECHTE Spiel
## (home_entry inkl. Autoloads/Router/HUD) in iPhone-Fenstergrößen und schießt
## Screenshots von Home-HUD, Status-Sheet, Settings, Patchnotes, Arcade, Album
## und Profil/Social. Braucht einen echten Renderer (xvfb):
##   FIX1_OUT=/tmp/gooby-godot/artifacts/FIX1/before xvfb-run -a godot \
##     --path GOOBY-GODOT --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --script res://tests/unit/screenshot_fix1.gd
## FIX1_SIM_IPHONE=1 simuliert zusätzlich den iPhone-Retina-Faktor (2×),
## damit die physische UI-Größe der Screenshots dem Gerät entspricht.

const OUT_ENV := "FIX1_OUT"
const DEFAULT_OUT := "/tmp/gooby-godot/artifacts/FIX1/probe"
const SETTLE_FRAMES := 24
const TRAVEL_TIMEOUT_MS := 15_000

## iPhone-Maße (physische Pixel): 11/XR quer, 15 Pro Max quer, 11/XR hoch.
const SIZES := [
	["quer_1792x828", Vector2i(1792, 828)],
	["quer_2556x1179", Vector2i(2556, 1179)],
	["hoch_828x1792", Vector2i(828, 1792)],
]

var _out_dir := DEFAULT_OUT
var _router: Node
var _entry: Node
var _hud: Control


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var env := OS.get_environment(OUT_ENV)
	if env != "":
		_out_dir = env
	DirAccess.make_dir_recursive_absolute(_out_dir)
	if OS.get_environment("FIX1_SIM_IPHONE") == "1":
		var ui_scale := load("res://scripts/ui/ui_scale.gd")
		if ui_scale != null and "screen_scale_override" in ui_scale:
			ui_scale.screen_scale_override = 2.0
	var gs := root.get_node("/root/GameState")
	gs.set_value("onboarding.done", true)
	# Coachmark-Merker zurücksetzen: der erste Quer-Shot soll den
	# Erststart-Hinweis „Deine Knöpfe“ IMMER zeigen (Beleg für Punkt 6).
	var app := root.get_node_or_null("/root/AppSettings")
	if app != null and app.has_method("set_setting"):
		app.set_setting("hints.hud_actions_seen", false)
	_router = root.get_node("/root/SceneRouter")
	_entry = (load("res://scenes/home/home_entry.tscn") as PackedScene).instantiate()
	root.add_child(_entry)
	await _wait_travel_done()
	_hud = _find_hud()
	if _hud == null:
		print("FIX1: HUD nicht gefunden — Abbruch.")
		quit(1)
		return
	for size_info in SIZES:
		await _capture_size(String(size_info[0]), size_info[1])
	print("FIX1-Screenshots fertig -> %s" % _out_dir)
	quit(0)


func _capture_size(label: String, win_size: Vector2i) -> void:
	# Fenster VOR dem Resize auf dem (virtuellen) Screen zentrieren: sonst
	# behält es die alte Boot-Position, ragt über den Screenrand hinaus und
	# get_display_safe_area() meldet den unsichtbaren Streifen korrekt als
	# „unsafe“ — size_changed feuert direkt nach dem Resize, das HUD fräse
	# sich die aufgeblähten Insets ein (Probe-Befund; kein Bug auf dem
	# Gerät, dort ist das Fenster immer der ganze Screen).
	var screen := DisplayServer.screen_get_size()
	DisplayServer.window_set_position(
		Vector2i(maxi((screen.x - win_size.x) / 2, 0), maxi((screen.y - win_size.y) / 2, 0))
	)
	DisplayServer.window_set_size(win_size)
	root.size = win_size
	await _settle()
	await _settle()
	await _snap("%s_01_home_hud.png" % label)

	# Coachmark („Deine Knöpfe“, FIX1) ist im ersten Home-Shot drauf —
	# danach wegtippen, damit die Folge-Shots sauber sind.
	var coach_ok := _find_button_by_name(root, "CoachmarkOk")
	if coach_ok != null:
		coach_ok.pressed.emit()
		await _settle()

	# Status-Sheet (Tap auf Status-Kapsel).
	if _hud.has_method("open_status_sheet"):
		_hud.open_status_sheet()
		await _settle()
		await _snap("%s_02_status_sheet.png" % label)
		var sheet: Variant = _hud.get("_status_sheet")
		if sheet is Node and (sheet as Node).has_method("close"):
			sheet.close()
		await _settle()

	# Settings via HUD-Zahnrad-Signal (echter Pfad in home_entry).
	_hud.emit_signal("settings_pressed")
	await _settle()
	await _snap("%s_03_settings.png" % label)

	# Patchnotes/News aus den Settings heraus.
	var news_btn := _find_button_by_name(root, "NewsButton")
	if news_btn != null:
		news_btn.pressed.emit()
		await _settle()
		await _snap("%s_04_patchnotes.png" % label)
	var settings: Variant = _entry.get("_settings")
	if settings is Node:
		var news_panel: Variant = (settings as Node).get("_news_panel")
		if news_panel is Node and (news_panel as Node).has_method("close"):
			news_panel.close()
		var back := _find_button_by_name(settings as Node, "BackButton")
		if back == null:
			back = _unique_button(settings as Node, "%BackButton")
		if back != null:
			back.pressed.emit()
		await _settle()

	# Arcade über den echten HUD-Aktionspfad.
	await _open_and_snap(&"arcade", "%s_05_arcade.png" % label)
	# Album.
	await _open_and_snap(&"album", "%s_06_album.png" % label)
	# Profil (Social-Screen).
	await _open_and_snap(&"profil", "%s_07_profil.png" % label)


func _open_and_snap(action: StringName, file: String) -> void:
	_hud.emit_signal("action_pressed", action)
	await _wait_travel_done()
	await _settle()
	await _snap(file)
	await _press_screen_back()
	await _wait_travel_done()


## Zurück-Knopf des aktuellen Vollbild-Screens drücken (echter User-Pfad).
func _press_screen_back() -> void:
	var scene: Node = _router.get_current_scene()
	if scene == null:
		return
	var buttons := scene.find_children("*", "Button", true, false)
	for btn: Button in buttons:
		var variation := String(btn.theme_type_variation)
		if variation == "GhostButton" or variation == "BtnGhost":
			btn.pressed.emit()
			return
	if scene.has_method("_on_back_pressed"):
		scene.call("_on_back_pressed")


func _wait_travel_done() -> void:
	var deadline := Time.get_ticks_msec() + TRAVEL_TIMEOUT_MS
	# Erst warten, bis eine evtl. Reise startet, dann bis sie fertig ist.
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if _router != null and not _router.is_busy() and _router.get_current_scene() != null:
			break
	await _settle()


func _find_hud() -> Control:
	var huds := root.find_children("*", "Control", true, false).filter(
		func(node: Node) -> bool: return node is Hud
	)
	return huds[0] if not huds.is_empty() else null


func _find_button_by_name(from: Node, btn_name: String) -> Button:
	var found := from.find_children(btn_name, "Button", true, false)
	return found[0] if not found.is_empty() else null


func _unique_button(from: Node, unique: String) -> Button:
	return from.get_node_or_null(unique) as Button


func _settle() -> void:
	for i in SETTLE_FRAMES:
		await process_frame


func _snap(file: String) -> void:
	# Offline-„Safe-Mode“-Banner (PackLoader ohne Netz) ausblenden — gehört
	# nicht zu FIX1, kann jederzeit (wieder) auftauchen (Update-Retry) und
	# verdeckt sonst zufällig Zahnrad/Status-Chips.
	for node: Control in root.find_children("SafeModeBanner", "Control", true, false):
		node.visible = false
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [_out_dir, file])
	print("  gespeichert: %s (%dx%d)" % [file, image.get_width(), image.get_height()])
