extends SceneTree
## MG-2-Screenshot-Werkzeug (KEIN Test): montiert den MinigameHost für die
## Batch-2-Spiele, spielt ein paar Sekunden mit simulierten Touch-Eingaben und
## legt PNGs ab. Braucht einen echten Renderer (xvfb):
##   xvfb-run -a godot --path GOOBY-GODOT --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --script res://tests/unit/screenshot_mg2.gd
## Optional: --  <spiel-id> [weitere ids]  (ohne Argument: alle + Arcade).

const OUT_DIR := "/tmp/gooby-godot/artifacts/MG2"
const HOST_SCENE := "res://scripts/minigames/minigame_host.tscn"
const PORTRAIT := Vector2i(720, 1160)
const LANDSCAPE := Vector2i(1160, 720)

## id → {sec: Spielzeit vor dem Foto, taps: [[frame, rel_x, rel_y, gedrückt]]}.
## rel_* sind Anteile der Spielfläche; „gedrückt“ false = Finger heben.
const PLANS := {
	"basketBounce":
	{
		"sec": 1.7,
		"taps":
		[
			[40, 0.5, 0.82, true],
			[44, 0.5, 0.74, null],
			[48, 0.5, 0.66, null],
			[52, 0.5, 0.58, null],
			[54, 0.5, 0.54, false],
		],
	},
	"pancakeTower": {"sec": 16.0, "taps": []},
	"miniGolf":
	{
		"sec": 4.0,
		"taps":
		[
			[60, 0.5, 0.72, true],
			[70, 0.5, 0.82, null],
			[80, 0.5, 0.9, null],
			[84, 0.5, 0.9, false],
		],
	},
	"fishingPond":
	{
		"sec": 6.5,
		"taps":
		[
			[30, 0.5, 0.5, true],
			[95, 0.5, 0.5, false],
			[200, 0.5, 0.5, true],
			[204, 0.5, 0.5, false],
			[214, 0.5, 0.5, true],
			[218, 0.5, 0.5, false],
			[228, 0.5, 0.5, true],
			[232, 0.5, 0.5, false],
		],
	},
	"goalieGooby":
	{
		"sec": 4.6,
		"taps": [[150, 0.5, 0.6, true], [156, 0.28, 0.42, false]],
	},
	"starHopper": {"sec": 3.4, "taps": []},
	"rocketRescue": {"sec": 4.5, "taps": [[30, 0.46, 0.7, true]]},
	"danceParty": {"sec": 30.0, "taps": []},
	# Der Buh-Wellen-Moment bei 25 s zeigt fünf Geister auf einmal.
	"ghostHunt": {"sec": 25.4, "taps": []},
}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.theme = ThemeService.theme()
	var ids: Array = []
	for arg in OS.get_cmdline_user_args():
		ids.append(str(arg))
	if ids.is_empty():
		ids = PLANS.keys()
		ids.append("arcade")
	for id: String in ids:
		if id == "arcade":
			await _shoot_arcade()
		else:
			await _shoot_game(id)
	print("Screenshots fertig → %s" % OUT_DIR)
	quit(0)


func _shoot_game(game_id: String) -> void:
	var meta := MinigameRegistry.get_game(game_id)
	if meta.is_empty():
		print("  ÜBERSPRUNGEN (nicht in der Registry): %s" % game_id)
		return
	var landscape := str(meta.get("orientation", "portrait")) == "landscape"
	_resize(LANDSCAPE if landscape else PORTRAIT)
	var host: MinigameHost = (load(HOST_SCENE) as PackedScene).instantiate()
	host.auto_navigate = false
	host.countdown_step_sec = 0.01
	host.receive_params({"game_id": game_id, "difficulty": "normal", "seed": 4242})
	root.add_child(host)
	for _i in 16:
		await process_frame
	var plan: Dictionary = PLANS.get(game_id, {"sec": 5.0, "taps": []})
	var taps: Array = plan["taps"]
	for frame in int(float(plan["sec"]) * 60.0):
		for entry: Array in taps:
			if int(entry[0]) == frame:
				_touch(host, Vector2(float(entry[1]), float(entry[2])), entry[3])
		_autoplay(host, game_id)
		await process_frame
		if _is_photogenic(host, game_id):
			break
	await _snap("%s.png" % game_id)
	host.queue_free()
	await process_frame


func _shoot_arcade() -> void:
	_resize(PORTRAIT)
	var screen: Control = (
		(load("res://scripts/minigames/arcade_screen.tscn") as PackedScene).instantiate()
	)
	if "auto_navigate" in screen:
		screen.set("auto_navigate", false)
	root.add_child(screen)
	for _i in 24:
		await process_frame
	await _snap("arcade_grid.png")
	screen.queue_free()
	await process_frame


## Früher auslösen, sobald die Szene den gewünschten Moment zeigt (sonst
## erwischt das Foto eine Notenlücke oder den schon eingeblendeten Abspann).
func _is_photogenic(host: MinigameHost, game_id: String) -> bool:
	var viewport := _sub_viewport(host)
	if viewport == null or viewport.get_child_count() == 0:
		return false
	var game := viewport.get_child(viewport.get_child_count() - 1)
	if game_id == "danceParty":
		var now := float(game.get("song_time"))
		var live := 0
		for note: Dictionary in game.get("notes"):
			var delta := float(note["time"]) - now
			if delta > 0.2 and delta < 1.3 and not bool(note.get("hit", false)):
				live += 1
		return live >= 2 and int(game.get("score")) > 8
	if game_id == "pancakeTower":
		return (game.get("layers") as Array).size() >= 7
	return false


## Spiele, deren Foto einen echten Spielstand braucht, werden pro Frame vom
## Zustand der Szene aus gesteuert (blindes Tippen nach Frame-Nummer trifft
## bei Rhythmus-/Timing-Spielen nichts).
func _autoplay(host: MinigameHost, game_id: String) -> void:
	var viewport := _sub_viewport(host)
	if viewport == null or viewport.get_child_count() == 0:
		return
	var game := viewport.get_child(viewport.get_child_count() - 1)
	if game_id == "danceParty":
		_autoplay_dance(host, game)
	elif game_id == "pancakeTower":
		_autoplay_pancake(host, game)


## Die Note treffen, sobald sie im Perfekt-Fenster steht.
func _autoplay_dance(host: MinigameHost, game: Node) -> void:
	var now := float(game.get("song_time"))
	for note: Dictionary in game.get("notes"):
		if bool(note.get("hit", false)) or bool(note.get("missed", false)):
			continue
		var delta := float(note["time"]) - now
		if delta > 0.02:
			break
		if delta < -0.02:
			continue
		var x: float = game.call("lane_x", int(note["lane"])) / float(game.get("view_size").x)
		_touch(host, Vector2(x, 0.8), true)
		_touch(host, Vector2(x, 0.8), false)
		return


## Den Pfannkuchen fallen lassen, wenn er über der Stapelmitte steht.
func _autoplay_pancake(host: MinigameHost, game: Node) -> void:
	if bool(game.get("falling")):
		return
	var logic: GDScript = load("res://scripts/minigames/games/pancake_tower/pancake_tower_logic.gd")
	var index: int = game.call("_current_index")
	var phase := float(game.get("slide_phase"))
	var tune: Dictionary = game.get("tune")
	var t := float(game.get("slide_t"))
	var x: float = logic.slide_x(t, index, phase, tune)
	var next: float = logic.slide_x(t + 1.0 / 60.0, index, phase, tune)
	# Der Stapelmittelpunkt wandert mit jedem Versatz — auf IHN muss gezielt
	# werden. Pro Frame springt der Pfannkuchen weit, also im lokalen Minimum
	# des Abstands auslösen statt in einem festen Toleranzband.
	var target := float((game.get("stack") as Dictionary)["center"])
	if absf(x - target) > 0.2 or absf(x - target) > absf(next - target):
		return
	_touch(host, Vector2(0.5, 0.5), true)
	_touch(host, Vector2(0.5, 0.5), false)


## `pressed` null = Ziehen, true = Auflegen, false = Abheben.
func _touch(host: MinigameHost, rel: Vector2, pressed: Variant) -> void:
	var viewport := _sub_viewport(host)
	if viewport == null:
		return
	var pos := Vector2(viewport.size) * rel
	var event: InputEvent
	if pressed == null:
		var drag := InputEventScreenDrag.new()
		drag.position = pos
		event = drag
	else:
		var touch := InputEventScreenTouch.new()
		touch.position = pos
		touch.pressed = bool(pressed)
		event = touch
	viewport.push_input(event, true)


func _sub_viewport(host: MinigameHost) -> SubViewport:
	var found := host.find_children("*", "SubViewport", true, false)
	return null if found.is_empty() else found[0] as SubViewport


func _resize(size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	root.size = size


func _snap(file: String) -> void:
	for _i in 4:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("  gespeichert: %s (%dx%d)" % [file, image.get_width(), image.get_height()])
