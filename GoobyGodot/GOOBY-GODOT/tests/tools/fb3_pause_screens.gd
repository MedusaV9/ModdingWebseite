extends SceneTree
## FB3-Wegwerf-Capture: Pause-Modal in 3 verschiedenen ECHTEN Spielen
## (gemeinsamer MinigameHost-Pfad). Braucht einen echten Renderer:
##   FB3_OUT=/tmp/gooby-godot/artifacts/FB3 xvfb-run -a godot --path . \
##     --rendering-method gl_compatibility --rendering-driver opengl3 \
##     --script res://tests/tools/fb3_pause_screens.gd

const OUT_DEFAULT := "/tmp/gooby-godot/artifacts/FB3"
const GAMES: Array[String] = ["teaParty", "carrotCatch", "memoryMatch"]
const WINDOW := Vector2i(2556, 1179)
const SCREEN_SCALE := 3.0
## iPhone quer: Notch links/rechts 59 pt, Home-Indicator 21 pt.
const INSETS_PT: Array[float] = [59.0, 0.0, 59.0, 21.0]

var _out := OUT_DEFAULT


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var env := OS.get_environment("FB3_OUT")
	if env != "":
		_out = env
	DirAccess.make_dir_recursive_absolute(_out)
	UiScale.screen_scale_override = SCREEN_SCALE
	DisplayServer.window_set_size(WINDOW)
	root.size = WINDOW
	await process_frame
	var canvas := Vector2(root.get_visible_rect().size)
	var pt_short := minf(float(WINDOW.x), float(WINDOW.y)) / SCREEN_SCALE
	var px := minf(canvas.x, canvas.y) / pt_short
	UiScale.insets_override = Rect2(
		INSETS_PT[0] * px,
		INSETS_PT[1] * px,
		canvas.x - (INSETS_PT[0] + INSETS_PT[2]) * px,
		canvas.y - (INSETS_PT[1] + INSETS_PT[3]) * px
	)
	_refill_energy()
	for game_id in GAMES:
		await _capture(game_id)
	UiScale.screen_scale_override = 0.0
	UiScale.insets_override = Rect2()
	quit(0)


func _capture(game_id: String) -> void:
	_refill_energy()
	var host: MinigameHost = (
		(load("res://scripts/minigames/minigame_host.tscn") as PackedScene).instantiate()
	)
	host.auto_navigate = false
	host.countdown_step_sec = 0.05
	host.receive_params({"game_id": game_id, "difficulty": "normal", "seed": 4242})
	root.add_child(host)
	var deadline := Time.get_ticks_msec() + 15_000
	while Time.get_ticks_msec() < deadline:
		var btn: Button = host.get("_pause_button")
		if btn != null and not btn.disabled:
			break
		await process_frame
	# Kurz laufen lassen, damit das Spiel sichtbar ist, dann pausieren.
	for _i in 30:
		await process_frame
	host._on_pause_pressed()
	for _i in 40:
		await process_frame
	await _snap("pause_modal_%s.png" % game_id)
	host.queue_free()
	await process_frame
	await process_frame


func _snap(file_name: String) -> void:
	await process_frame
	var img := root.get_viewport().get_texture().get_image()
	img.save_png("%s/%s" % [_out, file_name])
	print("  gespeichert: %s" % file_name)


func _refill_energy() -> void:
	var gs := root.get_node_or_null("/root/GameState")
	if gs == null or not gs.has_method("update"):
		return
	gs.update(
		func(state: Dictionary) -> void:
			var gooby: Variant = state.get("gooby")
			if gooby is Dictionary and (gooby as Dictionary).get("stats") is Dictionary:
				((gooby as Dictionary)["stats"] as Dictionary)["energy"] = 100.0
	)
