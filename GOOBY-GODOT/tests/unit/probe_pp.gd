extends SceneTree

const HOST_SCENE := "res://scripts/minigames/minigame_host.tscn"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.theme = ThemeService.theme()
	DisplayServer.window_set_size(Vector2i(720, 1160))
	root.size = Vector2i(720, 1160)
	var gs := root.get_node_or_null(^"/root/GameState")
	if gs != null and gs.has_method("set_value"):
		gs.call("set_value", "gooby.stats.energy", 100.0)
	var host: MinigameHost = (load(HOST_SCENE) as PackedScene).instantiate()
	host.auto_navigate = false
	host.countdown_step_sec = 0.01
	host.receive_params({"game_id": "purblePlace", "difficulty": "normal", "seed": 4242})
	root.add_child(host)
	for _i in 16:
		await process_frame
	var vps := host.find_children("*", "SubViewport", true, false)
	var game: Node = (vps[0] as SubViewport).get_child(0)
	game.set("autoplay", true)
	for _i in 400:
		await process_frame
	print("view_size=", game.get("view_size"))
	print("stage=", game.get("_stage"), " ppm=", game.get("_ppm"), " belt=", game.get("_belt_px"))
	print("strip=", game.get("_strip"), " dock_top=", game.get("_dock_top"))
	var line: Dictionary = game.get("line")
	print("t=", line["t"], " score=", line["score"], " tickets=", (line["tickets"] as Array).size())
	print("pans=", (line["pans"] as Array).size(), " serves=", line["serves"])
	quit(0)
