extends SceneTree
## G7-P56 EIN-SPIEL-GEFÜHL — Sichtungs-Capture des gemeinsamen RAHMENS über
## mehrere Spiele (Pregame → Countdown → Results, je Spiel derselbe Rahmen).
## Braucht einen echten Renderer (Muster fb3_pause_screens.gd):
##   G7_OUT=/tmp/gooby-godot/artifacts/G7 xvfb-run -a godot --path GOOBY-GODOT \
##     --rendering-method gl_compatibility --rendering-driver opengl3 \
##     --script res://tests/tools/g7_rahmen_screens.gd

const OUT_DEFAULT := "/tmp/gooby-godot/artifacts/G7"
## Querschnitt durch die Arcade: 2 Hochkant-Klassiker, Brett, Runner, 3D-Quer.
const GAMES: Array[String] = ["teaParty", "memoryMatch", "runner", "gvz"]
const WINDOW := Vector2i(1280, 720)

var _out := OUT_DEFAULT


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var env := OS.get_environment("G7_OUT")
	if env != "":
		_out = env
	DirAccess.make_dir_recursive_absolute(_out)
	DisplayServer.window_set_size(WINDOW)
	root.size = WINDOW
	await process_frame
	for game_id in GAMES:
		await _capture_pregame(game_id)
		await _capture_host(game_id)
	quit(0)


func _capture_pregame(game_id: String) -> void:
	var pre: MinigamePregame = (
		(load("res://scripts/minigames/pregame.tscn") as PackedScene).instantiate()
	)
	pre.auto_navigate = false
	pre.receive_params({"game_id": game_id})
	root.add_child(pre)
	await _frames(6)
	await _snap("%s_1_pregame" % game_id)
	pre.queue_free()
	await _frames(2)


func _capture_host(game_id: String) -> void:
	_refill_energy()
	var host: MinigameHost = (
		(load("res://scripts/minigames/minigame_host.tscn") as PackedScene).instantiate()
	)
	host.auto_navigate = false
	host.countdown_step_sec = 0.45
	host.receive_params({"game_id": game_id, "difficulty": "normal", "seed": 4242})
	root.add_child(host)
	await _frames(8)
	await _snap("%s_2_countdown" % game_id)
	# Countdown zu Ende laufen lassen, dann die Runde hart beenden.
	var deadline := Time.get_ticks_msec() + 15_000
	while Time.get_ticks_msec() < deadline:
		var btn: Button = host.get("_pause_button")
		if btn != null and not btn.disabled:
			break
		await process_frame
	var game: MinigameBase = host.get("_game")
	if game != null and game.ctx != null:
		game.ctx.report_end({"score": 123})
	var results: Control = host.get("_results")
	deadline = Time.get_ticks_msec() + 8_000
	while Time.get_ticks_msec() < deadline:
		if results != null and results.visible:
			break
		await process_frame
	await _frames(20)
	await _snap("%s_3_results" % game_id)
	host.queue_free()
	await _frames(4)


func _snap(name: String) -> void:
	await process_frame
	var img := root.get_texture().get_image()
	img.save_png("%s/%s.png" % [_out, name])
	print("[g7] %s.png" % name)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame


func _refill_energy() -> void:
	var gs := root.get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("set_value"):
		gs.call("set_value", "gooby.stats.energy", 100.0)
