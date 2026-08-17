extends SceneTree
## UICOZY-Screenshot-Tool (KEIN Test — kein test_-Präfix): rendert HUD, Sheet,
## Status-Liste, Toast und Wallpaper-Kontexte in Web-Referenzgröße (390×844)
## als Vorher/Nachher-Artefakte. Braucht einen echten Renderer (xvfb):
## UICOZY_OUT=<dir> xvfb-run -a godot --rendering-method gl_compatibility \
##   --rendering-driver opengl3 --path . --script res://tests/unit/screenshot_uicozy.gd

const DEFAULT_OUT := "/tmp/gooby-godot/artifacts/UICOZY/after"
const SETTLE_FRAMES := 16
## Web-Referenz-Viewport (390×844 CSS-px @ DPR 1).
const PHONE := Vector2i(390, 844)

var _out_dir := DEFAULT_OUT
var _hud_scene := preload("res://scripts/ui/hud.tscn")
var _sheet_scene := preload("res://scripts/ui/panel_sheet.tscn")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var env := OS.get_environment("UICOZY_OUT")
	if not env.is_empty():
		_out_dir = env
	DirAccess.make_dir_recursive_absolute(_out_dir)
	# Projekt-Stretch (canvas_items + expand) bewusst AKTIV lassen — nur so
	# entspricht der 390×844-Shot dem echten Phone-Rendering (Canvas ~1280 breit).
	root.theme = ThemeService.theme()
	RenderingServer.set_default_clear_color(AcTokens.BG_CREAM)
	await _shot_hud("hud_portrait.png")
	await _shot_status_sheet("list_status_sheet.png")
	await _shot_care_sheet("panel_sheet.png")
	await _shot_toast("toast.png")
	await _shot_wallpapers()
	print("UICOZY-Screenshots fertig -> %s" % _out_dir)
	quit(0)


func _resize(win_size: Vector2i) -> void:
	DisplayServer.window_set_size(win_size)
	root.size = win_size


func _make_stage(pattern := "leaves") -> Control:
	var stage := Control.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	var wallpaper := AcWallpaper.new()
	wallpaper.pattern = pattern
	wallpaper.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.add_child(wallpaper)
	root.add_child(stage)
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	return stage


func _mount_hud(stage: Control) -> Hud:
	var hud: Hud = _hud_scene.instantiate()
	stage.add_child(hud)
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.set_stats({"hunger": 82.0, "energie": 64.0, "hygiene": 91.0, "spass": 73.0})
	hud.set_coins(427)
	hud.set_level(12, 0.6)
	return hud


func _shot_hud(file: String) -> void:
	_resize(PHONE)
	var stage := _make_stage()
	_mount_hud(stage)
	await _snap(file)
	stage.free()


func _shot_status_sheet(file: String) -> void:
	_resize(PHONE)
	var stage := _make_stage()
	var hud := _mount_hud(stage)
	await process_frame
	hud.open_status_sheet()
	await _snap(file)
	stage.free()


func _shot_care_sheet(file: String) -> void:
	_resize(PHONE)
	var stage := _make_stage()
	_mount_hud(stage)
	var sheet: PanelSheet = _sheet_scene.instantiate()
	stage.add_child(sheet)
	sheet.set_title("Gooby-Pflege")
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	var well := PanelContainer.new()
	well.theme_type_variation = "AcWell"
	var well_label := Label.new()
	well_label.text = "Gooby geht es prima!"
	well.add_child(well_label)
	body.add_child(well)
	var b1 := SquishButton.new()
	b1.theme_type_variation = "BtnTeal"
	b1.text = "Medizin aus dem Kühlschrank"
	body.add_child(b1)
	var b2 := SquishButton.new()
	b2.theme_type_variation = "BtnPink"
	b2.text = "Zum Shop fahren"
	body.add_child(b2)
	var b3 := SquishButton.new()
	b3.theme_type_variation = "GhostButton"
	b3.text = "Schließen"
	body.add_child(b3)
	sheet.add_content(body)
	sheet.open()
	await _snap(file)
	stage.free()


func _shot_toast(file: String) -> void:
	_resize(PHONE)
	var stage := _make_stage()
	_mount_hud(stage)
	var toasts := ToastLayer.new()
	stage.add_child(toasts)
	toasts.show_toast("Gooby freut sich!")
	await _snap(file)
	stage.free()


func _shot_wallpapers() -> void:
	# Nachher: for_context-Stimmungen; Vorher: Default-Wallpaper reicht.
	var wallpaper_script: GDScript = load("res://scripts/ui/wallpaper.gd")
	var contexts := ["default", "shop", "arcade", "garten", "ranch", "settings"]
	if not wallpaper_script.has_method("for_context"):
		contexts = ["default"]
	for ctx in contexts:
		_resize(PHONE)
		var stage := Control.new()
		stage.set_anchors_preset(Control.PRESET_FULL_RECT)
		var wallpaper: Control
		if ctx == "default" or not wallpaper_script.has_method("for_context"):
			wallpaper = AcWallpaper.new()
		else:
			wallpaper = wallpaper_script.call("for_context", ctx)
		wallpaper.set_anchors_preset(Control.PRESET_FULL_RECT)
		stage.add_child(wallpaper)
		var tag := Label.new()
		tag.theme_type_variation = "TitleLabel"
		tag.text = "Kontext: %s" % ctx
		tag.set_anchors_preset(Control.PRESET_CENTER_TOP)
		tag.position = Vector2(60, 40)
		stage.add_child(tag)
		root.add_child(stage)
		stage.set_anchors_preset(Control.PRESET_FULL_RECT)
		await _snap("wallpaper_%s.png" % ctx)
		stage.free()


func _snap(file: String) -> void:
	for _i in SETTLE_FRAMES:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [_out_dir, file])
	print("  gespeichert: %s (%dx%d)" % [file, image.get_width(), image.get_height()])
