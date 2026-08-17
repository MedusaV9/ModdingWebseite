extends SceneTree
## W15-Beleg-Tool (KEIN Test): rendert ein GOB-NOM-Coop-Level im NETZ-Modus
## mit sichtbarem Partner-Cursor. Der komplette echte Pfad läuft über das
## FakeLink-Rig: GOBNOM_READY → ROOM_JOIN → GOBNOM_START (Server-Seed) →
## GN_INPUT-Fence → GN_CURSOR-Push des Partners. Aufruf:
## xvfb-run -a godot --rendering-method gl_compatibility \
##   --rendering-driver opengl3 --path GOOBY-GODOT \
##   --script res://tests/tools/w15_gobnom_netz_screenshot.gd

const OUT_FILE := "/tmp/gooby-godot/artifacts/w15_gobnom_coop.png"
const ROOM := "gobnom:shot-w15"
const TICK := 1.0 / 60.0

var _game_scene := preload("res://scripts/minigames/games/gobnom/gobnom_game.tscn")


## GameState-Double (Duck-Typing, Muster screenshot_gobnom.gd).
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
	DirAccess.make_dir_recursive_absolute(OUT_FILE.get_base_dir())
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.theme = ThemeService.theme()
	RenderingServer.set_default_clear_color(AcTokens.BG_CREAM)
	DisplayServer.window_set_size(Vector2i(1280, 800))
	root.size = Vector2i(1280, 800)

	# Netz-Rig + Spielszene: net_override VOR setup() (Muster game_state).
	var rig := NetTestRig.boot(self)
	await rig.go_online(self)
	var game: MinigameBase = _game_scene.instantiate()
	game.set("game_state_override", FakeState.new())
	game.set("net_override", rig.client)
	var ctx := MinigameCtx.new()
	ctx.game_id = "gobnom"
	ctx.difficulty = "normal"
	ctx.orientation = "landscape"
	ctx.run_seed = 7
	root.add_child(game)
	game.setup(ctx)
	game.start()
	await process_frame

	# Handshake wie vom Server: READY (Push) → ROOM_JOIN → START mit Seed.
	var players := [
		{"friendCode": "GOOBY-TEST", "side": "a", "name": "Ich", "goobyName": "Gooby"},
		{"friendCode": "GOOBY-PART", "side": "b", "name": "Timo", "goobyName": "Flauschi"},
	]
	_push(
		rig,
		"GOBNOM_READY",
		{"room": ROOM, "players": players, "inputDelay": 4, "hashEveryTicks": 60}
	)
	for _i in 4:
		await process_frame
	rig.link().respond_to("ROOM_JOIN", "OK", {"room": ROOM})
	for _i in 4:
		await process_frame
	_push(
		rig,
		"GOBNOM_START",
		{
			"room": ROOM,
			"level": 4,
			"seed": 987_654,
			"inputDelay": 4,
			"hashEveryTicks": 60,
			"players": players,
		}
	)
	for _i in 4:
		await process_frame

	# Partner-Fence öffnen + Sim ein Stück laufen lassen, dann sein Cursor.
	_push(
		rig,
		"ROOM_MSG",
		{
			"room": ROOM,
			"from": "GOOBY-PART",
			"kind": "GN_INPUT",
			"body": {"n": 1, "upTo": 240, "a": []}
		}
	)
	for _i in 4:
		await process_frame
	game.set_process(false)
	for _i in 30:
		game._process(TICK)
	_push(
		rig,
		"ROOM_MSG",
		{"room": ROOM, "from": "GOOBY-PART", "kind": "GN_CURSOR", "body": {"x": 620, "y": 390}}
	)
	for _i in 4:
		await process_frame
	# Cursor-Frische auffüllen (Muster Funken-TTL in screenshot_gobnom.gd):
	# die Settle-Frames würden den 1,5-s-Fade sonst ausbleichen.
	game.set("_netz_partner_cursor_at", Time.get_ticks_msec() / 1000.0)
	game.queue_redraw()
	await process_frame
	await process_frame

	var netz_aktiv := bool(game.get("_netz_active"))
	var image := root.get_texture().get_image()
	image.save_png(OUT_FILE)
	print(
		(
			"netz_active=%s → %s (%dx%d)"
			% [netz_aktiv, OUT_FILE, image.get_width(), image.get_height()]
		)
	)
	game.free()
	await rig.shutdown(self)
	quit(0 if netz_aktiv else 1)


func _push(rig: NetTestRig, type: String, data: Dictionary) -> void:
	rig.link().push_server({"v": 1, "t": type, "ts": 0, "d": data})
