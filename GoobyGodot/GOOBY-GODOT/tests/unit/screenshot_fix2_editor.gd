extends SceneTree
## FIX2-Screenshot-Tool (KEIN Test — kein test_-Präfix): rendert den neuen
## 3D-Char-Editor als Review-Artefakte — Default-Ansicht, Regler-Extreme
## (live am Modell) und die per Drag gedrehte Bühne. Aufruf (echter Renderer):
## xvfb-run -a godot --rendering-method gl_compatibility \
##   --rendering-driver opengl3 --audio-driver Dummy --path . \
##   --script res://tests/unit/screenshot_fix2_editor.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/FIX2"
const SETTLE_FRAMES := 24

var _flow_scene := preload("res://scripts/ui/onboarding/onboarding_flow.tscn")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.theme = ThemeService.theme()
	RenderingServer.set_default_clear_color(AcTokens.BG_CREAM)
	DisplayServer.window_set_size(Vector2i(1280, 800))
	root.size = Vector2i(1280, 800)
	var flow: OnboardingFlow = _flow_scene.instantiate()
	root.add_child(flow)
	await process_frame
	# Bis zum Editor-Schritt klicken.
	(flow.get_node("%NameEdit") as LineEdit).text = "Mia"
	(flow.get_node("%WelcomeNext") as Button).pressed.emit()
	(flow.get_node("%NicknameNext") as Button).pressed.emit()
	var preview: GoobyPreview = flow.get_node("%GoobyPreview")
	# Auto-Drehung fuer reproduzierbare Fotos anhalten.
	preview._spin_pause = 9999.0
	await _settle()
	await _shot("editor_default.png")
	# Regler-Extreme: lange Ohren, grosse Augen, pausbaeckig — live am Modell.
	_set_slider(flow, "SliderEarLen", 1.4)
	_set_slider(flow, "SliderEyeScale", 1.4)
	_set_slider(flow, "SliderChubby", 1.0)
	_set_slider(flow, "SliderEyesApart", 0.6)
	await _settle()
	await _shot("editor_regler_max.png")
	# Gegenrichtung: kurze Ohren, kleine enge Augen.
	_set_slider(flow, "SliderEarLen", 0.7)
	_set_slider(flow, "SliderEyeScale", 0.7)
	_set_slider(flow, "SliderChubby", 0.0)
	_set_slider(flow, "SliderEyesApart", -0.8)
	await _settle()
	await _shot("editor_regler_min.png")
	# Drehen ueber den echten Input-Pfad (simulierter Touch-Drag).
	_set_slider(flow, "SliderEarLen", 1.2)
	_set_slider(flow, "SliderEyeScale", 1.1)
	_set_slider(flow, "SliderChubby", 0.5)
	_set_slider(flow, "SliderEyesApart", 0.0)
	var drag := InputEventScreenDrag.new()
	drag.relative = Vector2(220.0, 0.0)
	preview._gui_input(drag)
	preview._spin_pause = 9999.0
	await _settle()
	await _shot("editor_gedreht.png")
	print("Screenshots fertig -> %s" % OUT_DIR)
	quit(0)


func _set_slider(flow: OnboardingFlow, slider_name: String, value: float) -> void:
	var slider: HSlider = flow.get_node("%SliderRows").find_child(slider_name, true, false)
	slider.value = value


func _settle() -> void:
	for _i in SETTLE_FRAMES:
		await process_frame


func _shot(file: String) -> void:
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("shot: %s" % file)
