extends SceneTree
## W21/P1 Nachher-Sichtung: Belege des HUD-rechts/Toast-Redesigns im
## ECHTEN Spiel-Boot (home_entry inkl. Autoloads, Muster fb3_ui_audit) —
## (1) Ruhe-HUD quer (EINE Knopfgröße, icon-only Kachel-Spalte),
## (2) Mehr-Cluster offen (Labels + Stagger-Pop),
## (3) Toast in Blatt-Sprache (RADIUS_CARD, Blatt-Glyphe, EINE Höhe),
## (4) mit W21_HOCH=1: Ruhe-HUD hochkant (Daumen-Dock).
## Braucht einen echten Renderer:
##   W21_OUT=/tmp/gooby-godot/artifacts/W21_P1 xvfb-run -a godot \
##     --path GOOBY-GODOT --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --script res://tests/tools/w21_p1_screens.gd

const OUT_DEFAULT := "/tmp/gooby-godot/artifacts/W21_P1"
const WINDOW := Vector2i(2868, 1320)
const WINDOW_HOCH := Vector2i(1320, 2868)
const SCALE := 3.0
const INSETS_PT: Array[float] = [59.0, 0.0, 59.0, 21.0]
const INSETS_PT_HOCH: Array[float] = [0.0, 59.0, 0.0, 34.0]
const TOAST_TEXT := "Tagesquest geschafft: +40 Münzen!"

var _out := OUT_DEFAULT
var _hoch := false
var _router: Node


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var env := OS.get_environment("W21_OUT")
	if env != "":
		_out = env
	_hoch = OS.get_environment("W21_HOCH") == "1"
	DirAccess.make_dir_recursive_absolute(_out)
	var quality := root.get_node_or_null("Quality")
	if quality != null:
		quality.set("brake_enabled", false)
	var gs := root.get_node("/root/GameState")
	gs.set_value("onboarding.done", true)
	# Tagesbonus für heute als geclaimt markieren — das (korrekt vom
	# Dirigenten serialisierte) Blatt läge sonst über allen HUD-Belegen.
	if "clock" in gs:
		gs.set_value("daily.lastClaimDay", str(gs.clock.local_day()))
	var app := root.get_node_or_null("/root/AppSettings")
	if app != null and app.has_method("set_setting"):
		app.set_setting("hints.hud_actions_seen", true)
	_router = root.get_node("/root/SceneRouter")
	var entry: Node = (load("res://scenes/home/home_entry.tscn") as PackedScene).instantiate()
	root.add_child(entry)
	await _wait_travel_done()
	_pin_leitformat()
	root.size_changed.emit()
	await _frames(30)
	var hud := _find_hud()
	await _snap("w21_p1_nachher_home_ruhe")
	if _hoch:
		quit(0)
		return
	# Mehr-Cluster öffnen: Labels erscheinen, die verborgenen Kacheln
	# federn per MotionKit.stagger_ein auf.
	hud.call("_on_mehr_pressed")
	await _frames(30)
	await _snap("w21_p1_nachher_mehr_offen")
	hud.call("_on_mehr_pressed")
	await _frames(10)
	# Toast in Blatt-Sprache über dem Ruhe-HUD.
	ToastLayer.zeige(hud, TOAST_TEXT)
	var deadline := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline and not _toast_sichtbar():
		await process_frame
	await _frames(8)
	await _snap("w21_p1_nachher_toast")
	quit(0)


func _pin_leitformat() -> void:
	var fenster := WINDOW_HOCH if _hoch else WINDOW
	var insets_pt := INSETS_PT_HOCH if _hoch else INSETS_PT
	UiScale.screen_scale_override = SCALE
	DisplayServer.window_set_size(fenster)
	root.size = fenster
	var canvas := Vector2(root.get_visible_rect().size)
	var pt_kurz := minf(float(fenster.x), float(fenster.y)) / SCALE
	var px_per_pt := minf(canvas.x, canvas.y) / pt_kurz
	var l := insets_pt[0] * px_per_pt
	var t := insets_pt[1] * px_per_pt
	var r := insets_pt[2] * px_per_pt
	var b := insets_pt[3] * px_per_pt
	UiScale.insets_override = Rect2(l, t, canvas.x - l - r, canvas.y - t - b)


func _toast_sichtbar() -> bool:
	for node: Node in get_nodes_in_group(ToastLayer.GROUP):
		if node is ToastLayer and (node as ToastLayer).is_showing():
			return true
	return false


func _snap(name: String) -> void:
	# Transiente Zufalls-Overlays ausblenden (Muster fb3_ui_audit._snap).
	for node: Control in root.find_children("SafeModeBanner", "Control", true, false):
		node.visible = false
	for node: Control in root.find_children("GoobyGespraechChips", "Control", true, false):
		node.visible = false
	for node: Control in root.find_children("EventChoice", "Control", true, false):
		node.visible = false
	await process_frame
	if _hoch:
		name += "_hoch"
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, name])
	print("[w21_p1] %s.png" % name)


func _wait_travel_done() -> void:
	var deadline := Time.get_ticks_msec() + 20000
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if _router != null and not _router.is_busy() and _router.get_current_scene() != null:
			break
	await _frames(20)


func _find_hud() -> Control:
	var huds := root.find_children("*", "Control", true, false).filter(
		func(node: Node) -> bool: return node is Hud
	)
	return huds[0] if not huds.is_empty() else null


func _frames(n: int) -> void:
	for _i in n:
		await process_frame
