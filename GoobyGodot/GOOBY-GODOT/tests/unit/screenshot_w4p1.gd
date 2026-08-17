extends SceneTree
## W4-P1-Screenshot-Tool (KEIN Test — kein test_-Präfix): rendert die
## Juice-Momente des Polish-Passes als Review-Artefakte: GvZ-Gefecht mit
## Banner/Poofs/Float-Text, GvZ-Boss-Druck und der teaParty-Perfect-Moment
## (Float-Text + Serien-Bonus). Aufruf (echter Renderer nötig):
## xvfb-run -a godot --rendering-method gl_compatibility \
##   --rendering-driver opengl3 --path . --script res://tests/unit/screenshot_w4p1.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/W4P1"
const SETTLE_FRAMES := 6
const TICK := 0.05

var _gvz_scene := preload("res://scripts/minigames/games/gvz/gvz_game.tscn")
var _tea_scene := preload("res://scripts/minigames/games/tea_party/tea_party.tscn")


## GameState-Double (Duck-Typing wie in den Tests).
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
	await _shot_gvz_battle("gvz_battle_juice.png")
	await _shot_gvz_boss("gvz_boss_pressure.png")
	_resize(Vector2i(480, 1040))
	await _shot_tea_perfect("tea_party_perfect_moment.png")
	print("Screenshots fertig → %s" % OUT_DIR)
	quit(0)


func _resize(win_size: Vector2i) -> void:
	DisplayServer.window_set_size(win_size)
	root.size = win_size


## JuiceKit fürs Foto verkabeln (Float-Texts landen im Overlay überm Spiel).
func _make_juice(overlay_parent: Node) -> JuiceKit:
	var juice := JuiceKit.new()
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay_parent.add_child(overlay)
	juice.float_text_parent = overlay
	root.add_child(juice)
	return juice


func _mount_gvz(gs: FakeState, seed_value: int) -> MinigameBase:
	var game: MinigameBase = _gvz_scene.instantiate()
	game.set("game_state_override", gs)
	var ctx := MinigameCtx.new()
	ctx.game_id = "gvz"
	ctx.difficulty = "normal"
	ctx.orientation = "landscape"
	ctx.run_seed = seed_value
	root.add_child(game)
	ctx.juice = _make_juice(root)
	game.setup(ctx)
	game.start()
	await process_frame
	return game


## Kampagnen-Stand: L1–L11 geschafft (L12-Gefecht ist frisch freigespielt).
func _progress_state() -> FakeState:
	var gs := FakeState.new()
	var stars := {}
	var cleared := {}
	for id in range(1, 12):
		stars[str(id)] = 2 + (id % 2)
		cleared[str(id)] = true
	gs.data = {"gvz": {"v": 1, "stars": stars, "best": {}, "cleared": cleared, "goldi": false}}
	return gs


## Bot spielt auf dem Spielzustand weiter, bis predicate greift.
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


func _shot_gvz_battle(file: String) -> void:
	var game := await _mount_gvz(_progress_state(), 11)
	game.call("open_level", 12)
	_fast_forward(game, 2400, func(_state: Dictionary) -> bool: return false)
	var state: Dictionary = game.get("state")
	# Foto-Welle stellen (der Bot räumt sonst zu schnell auf) + Ballon-Druck.
	var wave := [
		["schlurfi", 0, 7400],
		["ballon", 1, 6200],
		["huetchen", 1, 8200],
		["eimer", 2, 6800],
		["schlurfi", 3, 5600],
		["zeitungsopa", 4, 7200],
		["schlurfi", 4, 8500],
	]
	for entry: Array in wave:
		GvzZombies.spawn(state, str(entry[0]), int(entry[1]), int(entry[2]))
	_fast_forward(
		game,
		50,
		func(inner: Dictionary) -> bool: return (inner["projectiles"] as Array).size() >= 2
	)
	state["nutella"] = 275
	# Juice-Momente sichtbar machen: Banner + Nutella-Float + Boom-Poof.
	game.call("_show_banner", I18nService.t("gvz.hud.huge_wave", {"n": 2}))
	(
		game
		. call(
			"_consume_events",
			[
				{"kind": "collect", "lane": 1, "col": 2, "amount": 25},
				{"kind": "blast", "lane": 2, "col": 5},
			]
		)
	)
	await _snap(file)
	game.free()


func _shot_gvz_boss(file: String) -> void:
	var gs := _progress_state()
	for id in range(12, 15):
		(gs.data["gvz"]["cleared"] as Dictionary)[str(id)] = true
		(gs.data["gvz"]["stars"] as Dictionary)[str(id)] = 2
	var game := await _mount_gvz(gs, 7)
	game.call("open_level", 15)
	# Bis der 9000-hp-Knurps angeschlagen mittig patrouilliert und Druck lebt.
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
				and alive >= 2
			)
	)
	game.call("_show_banner", I18nService.t("gvz.hud.boss"))
	await _snap(file)
	game.free()


func _shot_tea_perfect(file: String) -> void:
	var game: MinigameBase = _tea_scene.instantiate()
	var ctx := MinigameCtx.new()
	ctx.game_id = "teaParty"
	ctx.difficulty = "normal"
	ctx.orientation = "portrait"
	ctx.run_seed = 5
	root.add_child(game)
	ctx.juice = _make_juice(root)
	game.setup(ctx)
	game.start()
	await process_frame
	# Perfekten Guss stellen: Füllstand exakt aufs Perfect-Band, Streak 2 →
	# der Release macht daraus Nr. 3 samt Serien-Bonus-Float (+ Bloom/Freeze).
	game.set("serving", false)
	game.set("streak", 2)
	game.set("elapsed", 21.0)
	var band: Dictionary = game.get("band")
	game.set("level", float(band["center"]))
	game.call("_release")
	# Fürs Foto die frische Tasse sofort hinstellen (der Serier-Slide würde
	# sie sonst während der Settle-Frames aus dem Bild schieben).
	game.set("serving", false)
	game.set("cup_slide", 0.0)
	game.queue_redraw()
	await _snap(file)
	game.free()


func _snap(file: String) -> void:
	for _i in SETTLE_FRAMES:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("  gespeichert: %s (%dx%d)" % [file, image.get_width(), image.get_height()])
