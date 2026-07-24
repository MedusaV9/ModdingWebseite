extends SceneTree
## W2d-Screenshot-Tool (KEIN Test — kein test_-Präfix): rendert Arcade-Grid,
## Pregame (Schwierigkeit + Orientierungswahl), teaParty-/carrotCatch-Momente
## und den Freunde-Screen (online + offline) als Review-Artefakte.
## Aufruf (echter Renderer nötig):
## xvfb-run -a godot --rendering-method gl_compatibility \
##   --rendering-driver opengl3 --path . --script res://tests/unit/screenshot_w2d.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/W2d"
const SETTLE_FRAMES := 12

var _arcade_scene := preload("res://scripts/minigames/arcade_screen.tscn")
var _pregame_scene := preload("res://scripts/minigames/pregame.tscn")
var _host_scene := preload("res://scripts/minigames/minigame_host.tscn")
var _friends_scene := preload("res://scripts/ui/friends/friends_screen.tscn")


## Mini-GameState fürs Pregame: Endlos freigeschaltet + Bestwerte vorhanden.
class FakeState:
	extends Node

	var data := {
		"progression": {"level": 12},
		"minigames":
		{
			"difficulty": {"teaParty": "hard"},
			"legacy":
			{
				"beaten": {"teaParty": {"easy": true, "normal": true, "hard": true}},
				"bestByDiff": {"teaParty": {"easy": 38, "hard": 52}},
				"best": {"teaParty": 61},
				"endlessBest": {"teaParty": 44},
			},
		},
	}

	func state() -> Dictionary:
		return data

	func update(mutator: Callable) -> void:
		mutator.call(data)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.theme = ThemeService.theme()
	RenderingServer.set_default_clear_color(AcTokens.BG_CREAM)
	await _shot_arcade(Vector2i(1280, 800), "arcade_grid.png")
	await _shot_pregame(Vector2i(720, 1080), "pregame_teaparty.png")
	# teaParty: nach der Perfekt-Tasse ~0.9 s in die zweite gießen (Füllstand
	# unterm Band, kein Überlauf — FILL_RATE 0.5/s). carrotCatch: länger
	# laufen lassen, damit mehrere Items in der Luft sind.
	await _shot_game("teaParty", Vector2i(540, 960), "tea_party_moment.png", 0.9)
	await _shot_game("carrotCatch", Vector2i(540, 960), "carrot_catch_moment.png", 4.2)
	await _shot_friends_online(Vector2i(720, 1080), "friends_screen.png")
	await _shot_friends_offline(Vector2i(720, 1080), "friends_offline.png")
	print("Screenshots fertig → %s" % OUT_DIR)
	quit(0)


func _resize(win_size: Vector2i) -> void:
	DisplayServer.window_set_size(win_size)
	root.size = win_size


## Direkte Window-Kinder werden nicht automatisch per Anchor gelayoutet —
## die Screens brauchen einmal eine explizite Größe (danach hält sie).
func _mount_fullscreen(screen: Control) -> void:
	root.add_child(screen)
	screen.set_deferred("size", Vector2(root.size))
	await process_frame
	await process_frame


func _shot_arcade(win_size: Vector2i, file: String) -> void:
	_resize(win_size)
	var arcade: ArcadeScreen = _arcade_scene.instantiate()
	arcade.auto_navigate = false
	await _mount_fullscreen(arcade)
	await _snap(file)
	arcade.free()


func _shot_pregame(win_size: Vector2i, file: String) -> void:
	_resize(win_size)
	var pregame: MinigamePregame = _pregame_scene.instantiate()
	pregame.auto_navigate = false
	pregame.state_node = FakeState.new()
	pregame.receive_params({"game_id": "teaParty"})
	await _mount_fullscreen(pregame)
	await _snap(file)
	pregame.state_node.free()
	pregame.free()


func _shot_game(game_id: String, win_size: Vector2i, file: String, play_sec: float) -> void:
	_resize(win_size)
	var host: MinigameHost = _host_scene.instantiate()
	host.auto_navigate = false
	host.countdown_step_sec = 0.05
	host.receive_params({"game_id": game_id, "difficulty": "normal", "seed": 7})
	await _mount_fullscreen(host)
	# Countdown + Servier-Slide abwarten, dann einen „lebendigen“ Moment
	# stellen. Teestube: erst eine PERFEKTE Tasse servieren (Score + Juice),
	# dann die zweite Tasse mitten im Gießen fotografieren.
	await create_timer(1.0).timeout
	var game: MinigameBase = host._game
	if game_id == "teaParty":
		game.set("holding", true)
		var band: Dictionary = game.get("band")
		var deadline := Time.get_ticks_msec() + 4000
		while float(game.get("level")) < float(band["center"]) and Time.get_ticks_msec() < deadline:
			await process_frame
		game.call("_release")
		await create_timer(0.7).timeout
		game.set("holding", true)
	else:
		game.set("target_x", 1.1)
	await create_timer(play_sec).timeout
	await _snap(file)
	host.free()


func _shot_friends_online(win_size: Vector2i, file: String) -> void:
	_resize(win_size)
	var setup := await _boot_fake_net()
	var net: NetClient = setup["net"]
	var link: FakeWsLink = setup["link"]
	(
		link
		. push_server(
			{
				"v": 1,
				"t": "FRIEND_ADDED",
				"ts": 0,
				"d":
				{
					"friendCode": "GOOBY-9ZML",
					"name": "Lena",
					"goobyName": "Knöpfchen",
					"online": true,
					"activity": {"kind": "park", "label": "ist gerade mit Knöpfchen im Park"},
					"coins": 842,
				},
			}
		)
	)
	(
		link
		. push_server(
			{
				"v": 1,
				"t": "FRIEND_ADDED",
				"ts": 0,
				"d":
				{
					"friendCode": "GOOBY-77QP",
					"name": "Timo",
					"goobyName": "Herr Flauschig",
					"online": false,
					"coins": 133,
				},
			}
		)
	)
	(
		link
		. push_server(
			{
				"v": 1,
				"t": "FRIEND_REQUEST_INCOMING",
				"ts": 0,
				"d": {"from": "GOOBY-MMMM", "name": "Mia", "goobyName": "Zimtschnecke", "at": 1},
			}
		)
	)
	for _i in 3:
		await process_frame
	var screen: FriendsScreen = _friends_scene.instantiate()
	screen.net_override = net
	screen.auto_navigate = false
	await _mount_fullscreen(screen)
	screen._add_input.text = "GOOBY-9XKA"
	await _snap(file)
	screen.free()
	net.free()


func _shot_friends_offline(win_size: Vector2i, file: String) -> void:
	_resize(win_size)
	var screen: FriendsScreen = _friends_scene.instantiate()
	screen.auto_navigate = false
	await _mount_fullscreen(screen)
	await _snap(file)
	screen.free()


## NetClient + FakeWsLink online bringen (HELLO/WELCOME) + FriendsService dran.
func _boot_fake_net() -> Dictionary:
	var links: Array[FakeWsLink] = []
	var net := NetClient.new()
	net.auto_connect = false
	net.build_services = false
	net.identity_path = "user://screenshot_netid.json"
	net.config_override = {"host": "fake.test", "port": 1, "tls": false}
	net.link_factory = func() -> FakeWsLink:
		var link := FakeWsLink.new()
		links.append(link)
		return link
	root.add_child(net)
	var friends := FriendsService.new()
	net.add_child(friends)
	friends.setup(net)
	net.friends = friends
	net.connect_now()
	links.back().open()
	for _i in 3:
		await process_frame
	links.back().respond_to("HELLO", "WELCOME", {"friendCode": "GOOBY-4K7Q", "heartbeatSec": 20})
	for _i in 3:
		await process_frame
	return {"net": net, "link": links.back()}


func _snap(file: String) -> void:
	for _i in SETTLE_FRAMES:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("  gespeichert: %s (%dx%d)" % [file, image.get_width(), image.get_height()])
