extends SceneTree
## LICHT/HUD Nachher-Belege (EVAL-2026-08 Lens B Befund 18) im ECHTEN
## Spiel-Boot — dieselbe iPhone-Leitperspektive wie Eval-Shot
## `17_ui_iphone_hud_2340x1080.png`:
##   (1) RUHE-HUD quer: Auge + Gooby-Lupe ruhen hinter „Mehr“,
##   (2) Sprechblasen-Pop mit dem Eval-Spruch: Zeile 1 steht KOMPLETT
##       (vorher: „Kannst du kurz be“ mitten im Wort abgerissen),
##   (3) fertige Blase: mehrzeilig umgebrochen, klemmt vor der
##       Cockpit-Spalte,
##   (4) Mehr-Cluster offen: Auge + Lupe erscheinen in der Safe-Area.
## Braucht einen echten Renderer:
##   LICHT_HUD_OUT=/tmp/gooby-godot/artifacts/LICHT_HUD xvfb-run -a godot \
##     --path GOOBY-GODOT --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/tools/licht_hud_screens.gd

const OUT_DEFAULT := "/tmp/gooby-godot/artifacts/LICHT_HUD"
const WINDOW := Vector2i(2340, 1080)
const SCALE := 3.0
const INSETS_PT: Array[float] = [59.0, 0.0, 59.0, 21.0]
## Der lange Fixture-Spruch aus test_hud_bubble_formate — der Wortlaut
## spiegelt den abgerissenen Eval-Shot („Kannst du kurz …“).
const SPRUCH := (
	"Kannst du kurz bei mir bleiben? Ich wollte dir nämlich unbedingt"
	+ " erzählen, was ich heute im Garten unter der Wäscheleine gefunden"
	+ " habe — du glaubst es nie, ein glitzernder Kieselstein!"
)

var _out := OUT_DEFAULT
var _router: Node


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var env := OS.get_environment("LICHT_HUD_OUT")
	if env != "":
		_out = env
	DirAccess.make_dir_recursive_absolute(_out)
	var quality := root.get_node_or_null("Quality")
	if quality != null:
		quality.set("brake_enabled", false)
	var gs := root.get_node("/root/GameState")
	gs.set_value("onboarding.done", true)
	# Guide-Tour über ihren Save-Slice abschalten (Muster flow_j3_leben_tour:
	# die Karte spawnt sonst über allen HUD-Belegen).
	gs.set_value("onboarding.guide", {"done": true, "skipped": true, "step": 0, "base": {}})
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
	var room: Node = _router.get_current_scene()
	var gooby: Node = room.call("gooby")
	if gooby != null:
		gooby.call("set_wander_enabled", false)
	await _snap("after_17_hud_ruhe")
	# Blasen-Vertrag: Pop zeigt die komplette erste Zeile, danach tippt
	# der Typewriter WORT-weise weiter, bis der Spruch fertig umbricht.
	AcBubble.warteschlange = AcBubble.Warteschlange.new()
	var bubble := AcBubble.show_bubble(
		room.call("ui_layer"), SPRUCH, {"speaker_3d": gooby, "dauer_s": 60.0}
	)
	await _frames(14)
	await _snap("after_17_hud_bubble_pop")
	var label := bubble.get_node("Kapsel/BubbleText") as Label
	var deadline := Time.get_ticks_msec() + 30000
	while Time.get_ticks_msec() < deadline and label.visible_characters != -1:
		await process_frame
	await _frames(6)
	await _snap("after_17_hud_bubble_fertig")
	bubble.dismiss()
	await _frames(12)
	# Mehr-Cluster offen: Auge + Gooby-Lupe federn in die Safe-Area.
	var hud := _find_hud()
	hud.call("_on_mehr_pressed")
	await _frames(30)
	await _snap("after_17_hud_mehr_offen")
	quit(0)


func _pin_leitformat() -> void:
	UiScale.screen_scale_override = SCALE
	DisplayServer.window_set_size(WINDOW)
	root.size = WINDOW
	var canvas := Vector2(root.get_visible_rect().size)
	var pt_kurz := minf(float(WINDOW.x), float(WINDOW.y)) / SCALE
	var px_per_pt := minf(canvas.x, canvas.y) / pt_kurz
	var l := INSETS_PT[0] * px_per_pt
	var t := INSETS_PT[1] * px_per_pt
	var r := INSETS_PT[2] * px_per_pt
	var b := INSETS_PT[3] * px_per_pt
	UiScale.insets_override = Rect2(l, t, canvas.x - l - r, canvas.y - t - b)


func _snap(name: String) -> void:
	# Transiente Zufalls-Overlays ausblenden (Muster fb3_ui_audit._snap).
	for node: Control in root.find_children("SafeModeBanner", "Control", true, false):
		node.visible = false
	for node: Control in root.find_children("GoobyGespraechChips", "Control", true, false):
		node.visible = false
	for node: Control in root.find_children("EventChoice", "Control", true, false):
		node.visible = false
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, name])
	print("[licht_hud] %s.png" % name)


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
