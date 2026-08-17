extends SceneTree
## MP-B-Screenshot-Werkzeug (KEIN TestCase — der Haupt-Runner überspringt es):
## montiert den MinigameHost für die vier MP-B-Spiele (bubblePop, carrotCatch,
## carrotGuard, gardenRush), spielt sie mit einem Bot und legt PNGs samt
## Draw-Call-Messung ab. Braucht einen echten Renderer (xvfb):
##   xvfb-run -a godot --path GOOBY-GODOT --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --script res://tests/unit/test_mpb_screens.gd \
##     -- before
## Argumente: `before`/`after` (Dateipräfix), `landscape`, `reward`
## (zusätzlich auf den Jubelmoment warten), sonst Spiel-Ids.

const Stage3D := preload("res://scripts/minigames/games/_3dc_stage/stage3d.gd")

const OUT_DIR := "/tmp/gooby-godot/artifacts/MPB"
const HOST_SCENE := "res://scripts/minigames/minigame_host.tscn"
const PORTRAIT := Vector2i(720, 1160)
const LANDSCAPE := Vector2i(1160, 720)
const GAMES: Array[String] = ["bubblePop", "carrotCatch", "carrotGuard", "gardenRush"]
## Sekunden Spielzeit vor dem Action-Foto.
const SECONDS := {
	"bubblePop": 14.0,
	"carrotCatch": 9.0,
	"carrotGuard": 8.0,
	"gardenRush": 7.0,
}
## Maximale Wartezeit (Wanduhr) auf den Belohnungsmoment.
const REWARD_BUDGET_MS := 55000

var _prefix := "shot"
var _landscape := false
var _reward := false


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.theme = ThemeService.theme()
	var ids: Array[String] = []
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		if text == "landscape":
			_landscape = true
		elif text == "reward":
			_reward = true
		elif text == "before" or text == "after":
			_prefix = text
		else:
			ids.append(text)
	if ids.is_empty():
		ids = GAMES.duplicate()
	for id in ids:
		await _shoot_game(id)
	print("MPB-Screenshots fertig → %s" % OUT_DIR)
	quit(0)


func _shoot_game(game_id: String) -> void:
	var meta := MinigameRegistry.get_game(game_id)
	if meta.is_empty():
		print("  ÜBERSPRUNGEN (nicht in der Registry): %s" % game_id)
		return
	_refill_energy()
	_resize(LANDSCAPE if _landscape else PORTRAIT)
	var host: MinigameHost = (load(HOST_SCENE) as PackedScene).instantiate()
	host.auto_navigate = false
	host.countdown_step_sec = 0.01
	(
		host
		. receive_params(
			{
				"game_id": game_id,
				"difficulty": "normal",
				"seed": 4242,
				"orientation": "landscape" if _landscape else "portrait",
			}
		)
	)
	root.add_child(host)
	for _i in 20:
		await process_frame
	var viewport := _sub_viewport(host)
	var game := _game_node(viewport)
	var budget_ms := int(float(SECONDS.get(game_id, 6.0)) * 1000.0)
	var started_ms := Time.get_ticks_msec()
	var frame := 0
	while true:
		var spent := Time.get_ticks_msec() - started_ms
		if spent >= budget_ms:
			break
		if game == null or not is_instance_valid(game) or _round_over(game):
			break
		_drive(game_id, game, viewport, frame)
		frame += 1
		await process_frame
	# Nachlauf bis zum fotogenen Moment (etwas MUSS im Bild sein).
	var grace := Time.get_ticks_msec() + 12000
	while game != null and is_instance_valid(game) and not _round_over(game):
		if _photogenic(game_id, game) or Time.get_ticks_msec() > grace:
			break
		_drive(game_id, game, viewport, frame)
		frame += 1
		await process_frame
	var suffix := "_landscape" if _landscape else ""
	await _snap("%s_%s%s.png" % [_prefix, game_id, suffix])
	print("    draw_calls=%d" % Stage3D.draw_calls())
	if _reward and game != null and is_instance_valid(game):
		await _reward_moment(game_id, game, viewport, frame, suffix)
	host.queue_free()
	await process_frame


## Weiterspielen, bis Gooby jubelt (ecstatic = Kette/Golden/König/Sprinkler),
## dann sofort auslösen.
func _reward_moment(
	game_id: String, game: Node, viewport: SubViewport, frame: int, suffix: String
) -> void:
	var deadline := Time.get_ticks_msec() + REWARD_BUDGET_MS
	var got := false
	while Time.get_ticks_msec() < deadline:
		if game == null or not is_instance_valid(game) or _round_over(game):
			break
		if _gooby_emotion(game) == "ecstatic":
			got = true
			break
		_drive(game_id, game, viewport, frame)
		frame += 1
		await process_frame
	if got:
		await _snap("%s_%s_reward%s.png" % [_prefix, game_id, suffix])
	else:
		print("    KEIN Belohnungsmoment für %s im Budget." % game_id)


func _gooby_emotion(game: Node) -> String:
	var stage: Variant = game.get("_stage")
	if stage == null or not (stage is Node):
		return ""
	var gooby: Variant = (stage as Node).get("gooby")
	if gooby == null or not (gooby is Node):
		return ""
	var rig: Variant = (gooby as Node).get("rig")
	if rig == null or not (rig is Node) or not (rig as Node).has_method("get_emotion"):
		return ""
	return str((rig as Node).call("get_emotion"))


func _drive(game_id: String, game: Node, viewport: SubViewport, frame: int) -> void:
	match game_id:
		"bubblePop":
			_drive_bubble_pop(game, viewport, frame)
		"carrotCatch":
			_drive_carrot_catch(game, viewport)
		"carrotGuard":
			_drive_carrot_guard(game, viewport, frame)
		"gardenRush":
			_drive_garden_rush(game, viewport, frame)
		_:
			pass


func _round_over(game: Node) -> bool:
	return "finished" in game and bool(game.get("finished"))


func _photogenic(game_id: String, game: Node) -> bool:
	var ready := true
	match game_id:
		"carrotGuard":
			ready = not (game.get("king") as Dictionary).is_empty() or _mole_is_up(game)
		"gardenRush":
			ready = int(game.get("hold_index")) >= 0
		"bubblePop":
			ready = (game.get("bubbles") as Array).size() >= 5 and _target_bubble_visible(game)
		"carrotCatch":
			ready = (game.get("items") as Array).size() >= 3
	return ready


func _mole_is_up(game: Node) -> bool:
	for mole: Dictionary in game.get("moles"):
		if float(mole["up"]) > 0.7:
			return true
	return false


func _target_bubble_visible(game: Node) -> bool:
	var wanted: String = game.call("target_food")
	for bubble: Dictionary in game.get("bubbles"):
		if str(bubble.get("food", "")) == wanted:
			return true
	return false


func _drive_bubble_pop(game: Node, viewport: SubViewport, frame: int) -> void:
	if frame % 3 != 0:
		return
	var target: String = game.call("target_food")
	for bubble: Dictionary in game.get("bubbles"):
		if str(bubble.get("food", "")) != target:
			continue
		var world := Vector2(float(bubble["x"]), float(bubble["y"]))
		_tap(viewport, game.call("_to_screen", world))
		return


## Korb unter das tiefste gute Stück ziehen — Gold hat Vorrang.
func _drive_carrot_catch(game: Node, viewport: SubViewport) -> void:
	var vp := (viewport as Viewport).get_visible_rect().size
	var best_x := INF
	var best_y := -INF
	var golden_x := INF
	for item: Dictionary in game.get("items"):
		var kind := str(item["kind"])
		if kind == "golden":
			golden_x = float(item["x"])
		if kind != "good" and kind != "golden":
			continue
		if float(item["y"]) > best_y:
			best_y = float(item["y"])
			best_x = float(item["x"])
	var target_x := golden_x if golden_x != INF else best_x
	if target_x == INF:
		return
	var ppu := float(game.call("_px_per_unit", vp))
	var drag := InputEventScreenDrag.new()
	drag.position = Vector2(vp.x * 0.5 + target_x * ppu, vp.y * 0.7)
	viewport.push_input(drag, true)


## Jeden Frame hauen (das Tap-Debounce der Logik drosselt selbst) — unter
## Xvfb-Last laufen wenige FPS, gedrosselte Bots verpassen sonst den König.
func _drive_carrot_guard(game: Node, viewport: SubViewport, _frame: int) -> void:
	var king: Dictionary = game.get("king")
	var holes: Array = game.get("_holes")
	if not king.is_empty():
		_tap(viewport, (holes[int(king["hole"])] as Rect2).get_center())
		return
	var best := -1
	var best_up := 0.3
	for mole: Dictionary in game.get("moles"):
		if float(mole["up"]) > best_up:
			best_up = float(mole["up"])
			best = int(mole["hole"])
	if best >= 0:
		_tap(viewport, (holes[best] as Rect2).get_center())


## Gieß-Bot: Sprinkler antippen, sobald er da ist; sonst Sprossen gießen.
func _drive_garden_rush(game: Node, viewport: SubViewport, frame: int) -> void:
	if bool(game.get("sprinkler_spawned")) and not bool(game.get("sprinkler_used")):
		if int(game.get("hold_index")) < 0:
			_tap(viewport, (game.call("_sprinkler_rect") as Rect2).get_center())
			return
	var hold_index := int(game.get("hold_index"))
	if hold_index >= 0:
		var fill := GardenRushLogic.hold_fill_fraction(
			float(game.get("hold_sec")), game.get("tune")
		)
		if fill >= 0.98:
			_release(viewport, Vector2(200.0, 400.0))
		return
	if frame % 4 != 0:
		return
	var pots: Array = game.get("pots")
	for i in pots.size():
		if str((pots[i] as Dictionary)["state"]) != "sprout":
			continue
		_press(viewport, (game.call("_pot_rect", i) as Rect2).get_center())
		return


func _tap(viewport: SubViewport, pos: Vector2) -> void:
	_press(viewport, pos)
	_release(viewport, pos)


func _press(viewport: SubViewport, pos: Vector2) -> void:
	var down := InputEventScreenTouch.new()
	down.pressed = true
	down.position = pos
	viewport.push_input(down, true)


func _release(viewport: SubViewport, pos: Vector2) -> void:
	var up := InputEventScreenTouch.new()
	up.pressed = false
	up.position = pos
	viewport.push_input(up, true)


func _refill_energy() -> void:
	var gs := root.get_node_or_null(^"/root/GameState")
	if gs != null and gs.has_method("set_value"):
		gs.call("set_value", "gooby.stats.energy", 100.0)


func _sub_viewport(host: MinigameHost) -> SubViewport:
	var found := host.find_children("*", "SubViewport", true, false)
	return null if found.is_empty() else found[0] as SubViewport


func _game_node(viewport: SubViewport) -> Node:
	if viewport == null or viewport.get_child_count() == 0:
		return null
	return viewport.get_child(viewport.get_child_count() - 1)


func _resize(size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	root.size = size


func _snap(file: String) -> void:
	for _i in 2:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("  gespeichert: %s (%dx%d)" % [file, image.get_width(), image.get_height()])
