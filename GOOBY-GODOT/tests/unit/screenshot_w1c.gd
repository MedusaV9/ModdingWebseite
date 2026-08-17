extends SceneTree
## W1c-Screenshot-Tool (KEIN Test — kein test_ui_-Präfix): rendert die
## UIKIT-Deliverables in echten Fenstergrößen und speichert PNGs als
## Review-Artefakte. Braucht einen echten Renderer (xvfb):
## xvfb-run -a godot --rendering-method gl_compatibility \
##   --rendering-driver opengl3 --script res://tests/unit/screenshot_w1c.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/W1c"
const SETTLE_FRAMES := 12

var _wallpaper_script := preload("res://scripts/ui/wallpaper.gd")
var _hud_scene := preload("res://scripts/ui/hud.tscn")
var _onboarding_scene := preload("res://scripts/ui/onboarding/onboarding_flow.tscn")
var _settings_scene := preload("res://scripts/ui/settings_screen.tscn")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.theme = ThemeService.theme()
	RenderingServer.set_default_clear_color(AcTokens.BG_CREAM)
	await _shot_hud(Vector2i(540, 960), "hud_portrait.png")
	await _shot_hud(Vector2i(1280, 720), "hud_landscape.png")
	await _shot_onboarding_welcome(Vector2i(720, 960), "onboarding_welcome.png")
	await _shot_onboarding_editor(Vector2i(1120, 720), "onboarding_editor.png")
	await _shot_settings(Vector2i(1280, 720), "settings.png")
	print("Screenshots fertig → %s" % OUT_DIR)
	quit(0)


func _resize(win_size: Vector2i) -> void:
	DisplayServer.window_set_size(win_size)
	root.size = win_size


func _shot_hud(win_size: Vector2i, file: String) -> void:
	_resize(win_size)
	var stage := Control.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	var wallpaper: ColorRect = _wallpaper_script.new()
	wallpaper.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.add_child(wallpaper)
	var hud: Hud = _hud_scene.instantiate()
	stage.add_child(hud)
	root.add_child(stage)
	await process_frame
	hud.set_stats({"hunger": 82.0, "energie": 64.0, "hygiene": 91.0, "spass": 73.0})
	hud.set_coins(427)
	hud.set_level(12)
	await _snap(file)
	stage.free()


func _shot_onboarding_welcome(win_size: Vector2i, file: String) -> void:
	_resize(win_size)
	var flow := _onboarding_scene.instantiate()
	root.add_child(flow)
	await _snap(file)
	flow.free()


func _shot_onboarding_editor(win_size: Vector2i, file: String) -> void:
	_resize(win_size)
	var flow := _onboarding_scene.instantiate()
	root.add_child(flow)
	await process_frame
	(flow.get_node("%NameEdit") as LineEdit).text = "Mia"
	(flow.get_node("%WelcomeNext") as Button).pressed.emit()
	(flow.get_node("%NicknameEdit") as LineEdit).text = "Flausch"
	(flow.get_node("%NicknameNext") as Button).pressed.emit()
	var slider := flow.get_node("%SliderRows").find_child("SliderEarLen", true, false)
	(slider as HSlider).value = 1.25
	await _snap(file)
	flow.free()


func _shot_settings(win_size: Vector2i, file: String) -> void:
	_resize(win_size)
	var settings := _settings_scene.instantiate()
	root.add_child(settings)
	await _snap(file)
	settings.free()


func _snap(file: String) -> void:
	for i in SETTLE_FRAMES:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("  gespeichert: %s (%dx%d)" % [file, image.get_width(), image.get_height()])
