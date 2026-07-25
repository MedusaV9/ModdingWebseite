extends SceneTree
## GOB-NOM-Screenshot-Tool (KEIN Test — kein test_-Präfix): rendert die
## Review-Artefakte: Level-Select (beide Tracks), Level-1-Start (Seil+Bonbon+
## Gooby), Mitten-im-Schneiden (Swipe-Linie + Schnitt-Funken), Sieg-„NOM!“-
## Moment mit Konfetti und ein Coop-Level (geteilter Screen). Aufruf:
## xvfb-run -a godot --rendering-method gl_compatibility \
##   --rendering-driver opengl3 --path . --script res://tests/unit/screenshot_gobnom.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/GOBNOM"
const SETTLE_FRAMES := 10
const TICK := 1.0 / 60.0

var _game_scene := preload("res://scripts/minigames/games/gobnom/gobnom_game.tscn")


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
	await _shot_mid_cut("mid_cut_swipe.png")
	await _shot_win_nom("win_nom.png")
	await _shot_win_screen("win_screen.png")
	await _shot_coop("coop_split.png")
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
	ctx.game_id = "gobnom"
	ctx.difficulty = "normal"
	ctx.orientation = "landscape"
	ctx.run_seed = seed_value
	root.add_child(game)
	game.setup(ctx)
	game.start()
	await process_frame
	return game


## Gemischter Spielstand: Kampagne L1–L9 geschafft, Coop CN1–CN3.
func _progress_state() -> FakeState:
	var gs := FakeState.new()
	var stars := {}
	var cleared := {}
	var star_row := [3, 3, 2, 3, 1, 2, 3, 2, 3]
	for i in star_row.size():
		stars["c%d" % (i + 1)] = star_row[i]
		cleared["c%d" % (i + 1)] = true
	for i in 3:
		stars["n%d" % (i + 1)] = [2, 3, 1][i]
		cleared["n%d" % (i + 1)] = true
	gs.data = {"gobnom": {"v": 1, "stars": stars, "best": {}, "cleared": cleared}}
	return gs


## Sim der Szene vorspulen — ÜBER _process, damit Events (Funken/Konfetti/
## Overlay) durch den echten View-Pfad laufen. actions: tick → Callable.
func _fast_forward(game: MinigameBase, ticks: int, actions := {}) -> void:
	for i in ticks:
		if actions.has(i):
			(actions[i] as Callable).call(game.get("state"))
		game._process(TICK)


func _shot_level_select(file: String) -> void:
	var game := await _mount_game(_progress_state(), 7)
	await _snap(file)
	game.free()


func _shot_level1_start(file: String) -> void:
	var game := await _mount_game(FakeState.new(), 7)
	game.call("open_level", "campaign", 1)
	_fast_forward(game, 12)
	# Banner ausblenden — er hängt genau vor Seil+Bonbon (das Foto soll die
	# Spielelemente zeigen, der Banner ist im mid_cut-Shot zu sehen).
	game.set("_banner_text", "")
	game.queue_redraw()
	await _snap(file)
	game.free()


## L3 (drei Seile): Swipe-Trail quer durchs mittlere Seil, Funken sichtbar.
func _shot_mid_cut(file: String) -> void:
	var game := await _mount_game(_progress_state(), 7)
	game.call("open_level", "campaign", 3)
	_fast_forward(game, 20)
	var state: Dictionary = game.get("state")
	var candy := GobnomLogic.candy_pos(state)
	var rope: Dictionary = (state["ropes"] as Array)[0]
	var mid: Vector2 = (Vector2(rope["anchor"]) + candy) * 0.5
	# Swipe von links unten quer über das erste Seil ziehen (Zeiger bleibt
	# unten — der Trail wird gezeichnet, der Schnitt-Funke lebt 0.4 s).
	var start := mid + Vector2(-90, 70)
	game.call("_pointer_down", 0, game.call("_to_screen", start))
	for i in range(1, 7):
		var p := start.lerp(mid + Vector2(60, -50), float(i) / 6.0)
		game.call("_pointer_move", 0, game.call("_to_screen", p))
	game._process(TICK)
	var cuts := 0
	for r: Dictionary in state["ropes"]:
		if bool(r["cut"]):
			cuts += 1
	print("  mid_cut: %d Seil(e) durchtrennt" % cuts)
	# Funken auffrischen + Sim einfrieren, damit der 0.4-s-Schnitt-Funke im
	# Foto hell ist (die Settle-Frames würden ihn sonst wegdecayen).
	for spark: Dictionary in game.get("_sparks"):
		spark["ttl"] = spark["ttl_max"]
	game.set_process(false)
	game.queue_redraw()
	await _snap(file, 2)
	game.free()


## L1 bis GENAU zum NOM-Tick spielen: Konfetti frisch, Gooby freut sich —
## das End-Overlay (samt Dim) wird für den Moment-Shot weggeräumt.
func _shot_win_nom(file: String) -> void:
	var game := await _mount_game(FakeState.new(), 7)
	game.call("open_level", "campaign", 1)
	_fast_forward(game, 30)
	GobnomLogic.cut_rope(game.get("state"), 0)
	for _i in 400:
		game._process(TICK)
		if GobnomLogic.is_over(game.get("state")):
			break
	# Konfetti ~0.3 s auffächern lassen (Partikel-Position hängt an t —
	# frisch gespawnt lägen alle 18 noch auf einem Punkt am Mund).
	for _i in 20:
		game._process(TICK)
	# Moment-Foto OHNE End-Overlay: Overlay+Dim weg, phase zurück auf "play"
	# (der Dim hängt an phase != "play") und _process einfrieren, damit die
	# Settle-Frames _on_run_over nicht erneut auslösen (Score ist gemeldet).
	game.call("_clear_overlay")
	game.set("_banner_text", "")
	game.set("phase", "play")
	game.set_process(false)
	game.queue_redraw()
	await _snap(file, 2)
	game.free()


## Gleicher Sieg-Lauf, aber MIT End-Overlay (Sterne/Punkte/Weiter-Knöpfe).
func _shot_win_screen(file: String) -> void:
	var game := await _mount_game(FakeState.new(), 7)
	game.call("open_level", "campaign", 1)
	var actions := {
		30: func(state: Dictionary) -> void: GobnomLogic.cut_rope(state, 0),
	}
	_fast_forward(game, 140, actions)
	game.set("_banner_text", "")
	game.queue_redraw()
	await _snap(file)
	game.free()


## CN4 (Kissen-Volley): geteilter Screen mit A/B-Tönung + beide Kissen.
func _shot_coop(file: String) -> void:
	var game := await _mount_game(_progress_state(), 7)
	game.call("open_level", "coop", 4)
	_fast_forward(game, 16)
	await _snap(file)
	game.free()


func _snap(file: String, settle := SETTLE_FRAMES) -> void:
	for _i in settle:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("  gespeichert: %s (%dx%d)" % [file, image.get_width(), image.get_height()])
