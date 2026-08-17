extends SceneTree
## W4-P2-Screenshot-Tool (KEIN Test — kein test_ui_-Präfix): rendert die
## UI-Polish-Artefakte aus Plan §2.4-3/4/5/17 — LoadingVeil in beiden
## Varianten (Minigame-Cover-Karte / hüpfender Mini-Gooby), HUD mit
## Level-Ring + Badge-Pulse + offenem Stat-Sheet und den
## Onboarding-Konfetti-Moment. Braucht einen echten Renderer (xvfb):
## xvfb-run -a godot --rendering-method gl_compatibility \
##   --rendering-driver opengl3 --script res://tests/unit/screenshot_w4p2.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/W4P2"
const SETTLE_FRAMES := 12
const QUER := Vector2i(1280, 720)
const HOCHKANT := Vector2i(540, 960)

var _veil_scene := preload("res://scripts/core/loading_veil.tscn")
var _hud_scene := preload("res://scripts/ui/hud.tscn")
var _onboarding_scene := preload("res://scripts/ui/onboarding/onboarding_flow.tscn")
var _wallpaper_script := preload("res://scripts/ui/wallpaper.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.theme = ThemeService.theme()
	RenderingServer.set_default_clear_color(AcTokens.BG_CREAM)
	await _shot_veil_home("veil_home_gooby.png")
	await _shot_veil_minigame("veil_minigame_cover.png")
	await _shot_hud_ring_pulse("hud_ring_badge_pulse.png")
	await _shot_hud_sheet("hud_stat_sheet_offen.png")
	await _shot_onboarding_konfetti("onboarding_konfetti.png")
	print("Screenshots fertig → %s" % OUT_DIR)
	quit(0)


func _resize(win_size: Vector2i) -> void:
	DisplayServer.window_set_size(win_size)
	root.size = win_size


## Veil-Default: Drift-Pattern + Karte mit hüpfendem Mini-Gooby + „Lädt…“.
func _shot_veil_home(file: String) -> void:
	_resize(QUER)
	LoadingVeil.clear_travel_hint()
	var veil: LoadingVeil = _veil_scene.instantiate()
	root.add_child(veil)
	await process_frame
	veil.prepare_for_travel(&"home")
	await veil.cover(true)
	# Bounce wieder anwerfen und am Sprung-Scheitel snappen (cover(true)
	# friert ein; Keyframe 32 % = höchste Pose des Web-acui-veil-bounce).
	var sticker := veil.get_node("%Gooby") as LoadingVeilSticker
	sticker.set_animated(true)
	sticker._t = 0.32 * LoadingVeilSticker.BOUNCE_S
	await process_frame
	await _snap(file, 0)
	veil.free()


## Veil-Minigame: Cover + Titel + rotierender Tipp + Progress-Bar.
func _shot_veil_minigame(file: String) -> void:
	_resize(QUER)
	var hint := {
		"game_id": "gvz",
		"title": I18nService.t("mg.gvz.title"),
		"cover": ArcadeScreen.cover_texture("gvz"),
		"targets": [&"mg_pregame"],
	}
	LoadingVeil.set_travel_hint(hint)
	var veil: LoadingVeil = _veil_scene.instantiate()
	root.add_child(veil)
	await process_frame
	veil.prepare_for_travel(&"mg_pregame")
	await veil.cover(true)
	veil.set_progress(0.45)
	await _snap(file)
	veil.free()
	LoadingVeil.clear_travel_hint()


func _make_hud_stage() -> Dictionary:
	var stage := Control.new()
	stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	var wallpaper: ColorRect = _wallpaper_script.new()
	wallpaper.set_anchors_preset(Control.PRESET_FULL_RECT)
	stage.add_child(wallpaper)
	var hud: Hud = _hud_scene.instantiate()
	stage.add_child(hud)
	root.add_child(stage)
	return {"stage": stage, "hud": hud}


## HUD quer: Level-Ring (62 % XP) + Energie 18 → Badge-Pulse mitten drin.
func _shot_hud_ring_pulse(file: String) -> void:
	_resize(QUER)
	var ctx := _make_hud_stage()
	var hud: Hud = ctx["hud"]
	await process_frame
	hud.set_stats({"hunger": 82.0, "energie": 18.0, "hygiene": 91.0, "spass": 73.0})
	hud.set_coins(427)
	hud.set_level(12, 0.62)
	# Coins-Zählen + Puls ein Stück laufen lassen, dann mitten drin snappen.
	for _i in 30:
		await process_frame
	await _snap(file, 0)
	(ctx["stage"] as Node).free()


## HUD hochkant mit offenem Stat-Detail-Sheet (4 Stats groß).
func _shot_hud_sheet(file: String) -> void:
	_resize(HOCHKANT)
	var ctx := _make_hud_stage()
	var hud: Hud = ctx["hud"]
	await process_frame
	hud.set_stats({"hunger": 61.0, "energie": 34.0, "hygiene": 88.0, "spass": 47.0})
	hud.set_coins(427)
	hud.set_level(12, 0.62)
	hud.open_status_sheet()
	await _snap(file)
	PanelStack.clear()
	(ctx["stage"] as Node).free()


## Onboarding bis zur Abschluss-Karte klicken und den Konfetti-Burst snappen.
func _shot_onboarding_konfetti(file: String) -> void:
	_resize(QUER)
	var flow := _onboarding_scene.instantiate()
	root.add_child(flow)
	await process_frame
	(flow.get_node("%NameEdit") as LineEdit).text = "Mia"
	(flow.get_node("%WelcomeNext") as Button).pressed.emit()
	(flow.get_node("%NicknameEdit") as LineEdit).text = "Flausch"
	(flow.get_node("%NicknameNext") as Button).pressed.emit()
	(flow.get_node("%EditorSkip") as Button).pressed.emit()
	# Partikel ein paar Frames fliegen lassen — mitten im Regen snappen.
	for _i in 20:
		await process_frame
	await _snap(file, 0)
	flow.free()


func _snap(file: String, settle := SETTLE_FRAMES) -> void:
	for _i in settle:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("  gespeichert: %s (%dx%d)" % [file, image.get_width(), image.get_height()])
