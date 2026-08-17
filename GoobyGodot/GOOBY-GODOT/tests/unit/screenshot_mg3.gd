extends SceneTree
## MG-3-Screenshot-Werkzeug (KEIN Test): montiert den MinigameHost für die
## Batch-3-Spiele, spielt ein paar Sekunden simulierte Zeit und legt PNGs ab.
## Braucht einen echten Renderer (xvfb):
##   xvfb-run -a godot --path GOOBY-GODOT --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --script res://tests/unit/screenshot_mg3.gd
## Optional: --  <spiel-id> [weitere ids]  (ohne Argument: alle + Arcade).
## Ein Suffix ":quer" bzw. ":hoch" erzwingt die andere Orientierung — so
## lässt sich der apply_view()-Vertrag beider Seitenverhältnisse prüfen.

const OUT_DIR := "/tmp/gooby-godot/artifacts/MG3"
const HOST_SCENE := "res://scripts/minigames/minigame_host.tscn"
const PORTRAIT := Vector2i(720, 1160)
const LANDSCAPE := Vector2i(1160, 720)

## id → {sec: Sekunden Spielzeit vor dem Foto, keys: [[frame, keycode]]}.
## Ein dritter Eintrag "down"/"up" hält die Taste (Halte-Eingaben wie Drift).
const PLANS := {
	"runner": {"sec": 7.0, "keys": [[40, KEY_RIGHT], [90, KEY_UP], [150, KEY_LEFT]]},
	"snailMail": {"sec": 4.0, "keys": []},
	"harborHopper": {"sec": 6.0, "keys": [[40, KEY_RIGHT], [120, KEY_LEFT]]},
	"toyRacer":
	{
		"sec": 9.0,
		"keys":
		[
			[60, KEY_SPACE, "down"],
			[150, KEY_SPACE, "up"],
			[240, KEY_SPACE, "down"],
			[380, KEY_SPACE, "up"],
			[430, KEY_ENTER],
		],
	},
	"purblePlace": {"sec": 9.0, "keys": [], "autoplay": true},
	"shoppingSurf": {"sec": 9.0, "keys": [], "autoplay": true},
	"burgerBuild": {"sec": 5.0, "keys": []},
	"deliveryRush": {"sec": 5.0, "keys": []},
	"hideSeek": {"sec": 4.0, "keys": []},
	"lanternFloat": {"sec": 6.0, "keys": []},
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


func _shoot_game(spec: String) -> void:
	var parts := spec.split(":")
	var game_id := parts[0]
	var meta := MinigameRegistry.get_game(game_id)
	if meta.is_empty():
		print("  ÜBERSPRUNGEN (nicht in der Registry): %s" % game_id)
		return
	_refill_energy()
	var landscape := str(meta.get("orientation", "portrait")) == "landscape"
	var suffix := ""
	if parts.size() > 1:
		landscape = parts[1] == "quer"
		suffix = "_%s" % parts[1]
	_resize(LANDSCAPE if landscape else PORTRAIT)
	var host: MinigameHost = (load(HOST_SCENE) as PackedScene).instantiate()
	host.auto_navigate = false
	host.countdown_step_sec = 0.01
	host.receive_params({"game_id": game_id, "difficulty": "normal", "seed": 4242})
	root.add_child(host)
	for _i in 16:
		await process_frame
	var plan: Dictionary = PLANS.get(game_id, {"sec": 5.0, "keys": []})
	if bool(plan.get("autoplay", false)):
		_enable_autoplay(host)
	var frames := int(float(plan["sec"]) * 60.0)
	var keys: Array = plan["keys"]
	for frame in frames:
		for entry: Array in keys:
			if int(entry[0]) == frame:
				_press(host, int(entry[1]), str(entry[2]) if entry.size() > 2 else "")
		if frame == 20 and game_id == "snailMail":
			_draw_snail_route(host)
		await process_frame
	await _snap("%s%s.png" % [game_id, suffix])
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


## Schneckenpost braucht einen gemalten Strich: die Referenzroute der Logik
## wird über die View-Projektion in Touch-Events übersetzt.
func _draw_snail_route(host: MinigameHost) -> void:
	var viewport := _sub_viewport(host)
	if viewport == null:
		return
	if viewport.get_child_count() == 0:
		return
	var game := viewport.get_child(viewport.get_child_count() - 1)
	if game == null or not game.has_method("project"):
		return
	var logic: GDScript = load("res://scripts/minigames/games/snail_mail/snail_mail_logic.gd")
	var route: Dictionary = logic.auto_route(game.get("_level"), game.get("tune"))
	var screen: Array[Vector2] = []
	for pt: Dictionary in route["pts"]:
		screen.append(game.call("project", float(pt["x"]), float(pt["y"])))
	var dense: Array[Vector2] = []
	for i in screen.size() - 1:
		for k in 12:
			dense.append(screen[i].lerp(screen[i + 1], k / 12.0))
	dense.append(screen[screen.size() - 1])
	for i in dense.size():
		var event: InputEvent
		if i == 0:
			var down := InputEventScreenTouch.new()
			down.pressed = true
			down.position = dense[i]
			event = down
		else:
			var drag := InputEventScreenDrag.new()
			drag.position = dense[i]
			event = drag
		viewport.push_input(event, true)
	var up := InputEventScreenTouch.new()
	up.pressed = false
	up.position = dense[dense.size() - 1]
	viewport.push_input(up, true)


## Spiele mit Bot-Hook (Tortenwerkstatt) spielen sich fürs Foto selbst.
func _enable_autoplay(host: MinigameHost) -> void:
	var viewport := _sub_viewport(host)
	if viewport == null or viewport.get_child_count() == 0:
		return
	var game := viewport.get_child(viewport.get_child_count() - 1)
	if game != null and "autoplay" in game:
		game.set("autoplay", true)


## Jede Runde kostet Energie — nach ein paar Fotos verweigert der Host den
## Start ("Gooby erschöpft"). Für das Werkzeug wird sie vorher aufgefüllt.
func _refill_energy() -> void:
	var gs := root.get_node_or_null(^"/root/GameState")
	if gs != null and gs.has_method("set_value"):
		gs.call("set_value", "gooby.stats.energy", 100.0)


func _sub_viewport(host: MinigameHost) -> SubViewport:
	var found := host.find_children("*", "SubViewport", true, false)
	return null if found.is_empty() else found[0] as SubViewport


func _press(host: MinigameHost, keycode: int, mode := "") -> void:
	var viewport := _sub_viewport(host)
	if viewport == null:
		return
	if mode != "up":
		viewport.push_input(_key_event(keycode, true), true)
	if mode == "":
		viewport.push_input(_key_event(keycode, false), true)
	elif mode == "up":
		viewport.push_input(_key_event(keycode, false), true)


func _key_event(keycode: int, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode as Key
	event.physical_keycode = keycode as Key
	event.pressed = pressed
	return event


func _resize(size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	root.size = size


func _snap(file: String) -> void:
	for _i in 4:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("  gespeichert: %s (%dx%d)" % [file, image.get_width(), image.get_height()])
