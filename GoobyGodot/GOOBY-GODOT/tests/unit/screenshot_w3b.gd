extends SceneTree
## W3b-Screenshot-Tool (KEIN Test — kein test_-Präfix): rendert GvZ-Momente
## als Review-Artefakte: Level-Select, Level-1-Start, Gefecht, Boss-Level-15
## und Sieg-Screen. Aufruf (echter Renderer nötig):
## xvfb-run -a godot --rendering-method gl_compatibility \
##   --rendering-driver opengl3 --path . --script res://tests/unit/screenshot_w3b.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/W3b"
const SETTLE_FRAMES := 12
const TICK := 0.05

var _game_scene := preload("res://scripts/minigames/games/gvz/gvz_game.tscn")


## GameState-Double (Duck-Typing wie in den Tests): get_value/update reichen.
class FakeState:
	extends RefCounted
	var data := {}

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var cursor: Variant = data
		for part in path.split("."):
			if cursor is Dictionary and (cursor as Dictionary).has(part):
				cursor = cursor[part]
			else:
				return fallback
		return cursor

	func update(mutator: Callable) -> void:
		mutator.call(data)

	func notify_slice_changed(_slice_id: String) -> void:
		pass


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.theme = ThemeService.theme()
	RenderingServer.set_default_clear_color(AcTokens.BG_CREAM)
	_resize(Vector2i(1280, 800))
	await _shot_level_select("level_select.png")
	await _shot_level1_start("level1_start.png")
	await _shot_battle("battle_moment.png")
	await _shot_boss("boss_level15.png")
	await _shot_win("win_screen.png")
	print("Screenshots fertig → %s" % OUT_DIR)
	quit(0)


func _resize(win_size: Vector2i) -> void:
	DisplayServer.window_set_size(win_size)
	root.size = win_size


## Spielszene mit Fortschritts-Double mounten (Phase = Level-Select).
func _mount_game(gs: FakeState, seed_value: int) -> MinigameBase:
	var game: MinigameBase = _game_scene.instantiate()
	game.set("game_state_override", gs)
	var ctx := MinigameCtx.new()
	ctx.game_id = "gvz"
	ctx.difficulty = "normal"
	ctx.orientation = "landscape"
	ctx.run_seed = seed_value
	root.add_child(game)
	game.setup(ctx)
	game.start()
	await process_frame
	return game


## Kampagnen-Stand für den Select-Screen: L1–L8 geschafft, gemischte Sterne.
func _progress_state() -> FakeState:
	var gs := FakeState.new()
	var stars := {"1": 3, "2": 3, "3": 2, "4": 3, "5": 1, "6": 2, "7": 3, "8": 2}
	var cleared := {}
	for key: String in stars:
		cleared[key] = true
	gs.data = {"gvz": {"v": 1, "stars": stars, "best": {}, "cleared": cleared, "goldi": false}}
	return gs


## Bot spielt auf dem Spielzustand der Szene weiter, bis predicate greift.
func _fast_forward(game: MinigameBase, max_ticks: int, predicate: Callable) -> void:
	var state: Dictionary = game.get("state")
	var guard := 0
	while guard < max_ticks and not GvzLogic.is_over(state):
		GvzLogic.tick(state)
		GvzBot.act(state)
		guard += 1
		if predicate.call(state):
			break
	game.queue_redraw()


func _shot_level_select(file: String) -> void:
	var game := await _mount_game(_progress_state(), 7)
	await _snap(file)
	game.free()


func _shot_level1_start(file: String) -> void:
	var game := await _mount_game(FakeState.new(), 7)
	game.call("open_level", 1)
	# Ein paar Sekunden anspielen: Sammler + erster Schütze stehen schon.
	_fast_forward(
		game,
		500,
		func(state: Dictionary) -> bool: return (state["towers"] as Dictionary).size() >= 2
	)
	await _snap(file)
	game.free()


func _shot_battle(file: String) -> void:
	var game := await _mount_game(_progress_state(), 11)
	game.call("open_level", 5)
	# Abwehr aufbauen lassen; der Bot räumt aber so schnell auf, dass nie
	# viele Zombies gleichzeitig leben → Welle für den Foto-Moment STELLEN
	# (wie die W2d-Screenshots): Angreifer mitten im Feld einsetzen und ein
	# paar Ticks laufen lassen, bis Möhren in der Luft sind.
	_fast_forward(game, 2600, func(_state: Dictionary) -> bool: return false)
	var state: Dictionary = game.get("state")
	var wave := [
		["schlurfi", 0, 7600],
		["huetchen", 1, 6400],
		["schlurfi", 1, 8300],
		["eimer", 2, 6900],
		["schlurfi", 3, 5800],
		["sprinter", 4, 7400],
		["schlurfi", 4, 8600],
	]
	for entry: Array in wave:
		GvzZombies.spawn(state, str(entry[0]), int(entry[1]), int(entry[2]))
	_fast_forward(
		game,
		40,
		func(inner: Dictionary) -> bool: return (inner["projectiles"] as Array).size() >= 2
	)
	state["nutella"] = 240
	game.call("_show_banner", I18nService.t("gvz.hud.huge_wave", {"n": 3}))
	await _snap(file)
	game.free()


func _shot_boss(file: String) -> void:
	var gs := _progress_state()
	for id in range(9, 15):
		(gs.data["gvz"]["cleared"] as Dictionary)[str(id)] = true
		(gs.data["gvz"]["stars"] as Dictionary)[str(id)] = 2
	var game := await _mount_game(gs, 7)
	game.call("open_level", 15)
	# Bis Knurps' Müllwagen angeschlagen in einer mittleren Reihe patrouilliert
	# (er bleibt konstruktionsbedingt an der rechten Kante, x ≈ 8600+).
	_fast_forward(
		game,
		14000,
		func(state: Dictionary) -> bool:
			var boss: Dictionary = state["boss"]
			if boss.is_empty() or int(boss["hp"]) <= 0:
				return false
			var alive := 0
			for zombie: Dictionary in state["zombies"]:
				if not bool(zombie["dead"]):
					alive += 1
			return (
				int(boss["hp"]) < int(boss["max_hp"])
				and int(boss["lane"]) >= 1
				and int(boss["lane"]) <= 3
				and alive >= 1
			)
	)
	game.call("_show_banner", I18nService.t("gvz.hud.boss"))
	await _snap(file)
	game.free()


func _shot_win(file: String) -> void:
	var game := await _mount_game(FakeState.new(), 7)
	game.call("open_level", 1)
	_fast_forward(game, 14400, func(state: Dictionary) -> bool: return GvzLogic.is_over(state))
	# _process erkennt das Ende und baut das Sieg-Overlay (Sterne + Score);
	# der alte Level-Banner würde die Sterne überlagern → weg damit.
	game._process(TICK)
	game.set("_banner_text", "")
	game.queue_redraw()
	await _snap(file)
	game.free()


func _snap(file: String) -> void:
	for _i in SETTLE_FRAMES:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("  gespeichert: %s (%dx%d)" % [file, image.get_width(), image.get_height()])
