extends SceneTree
## MP-A-Screenshot-Werkzeug (KEIN TestCase — der Haupt-Runner überspringt es):
## montiert den MinigameHost für die vier MP-A-Spiele (teaParty, goobySays,
## memoryMatch, pancakeTower), spielt sie mit einem deterministischen Bot
## (Seed 4242, --fixed-fps 60) und legt PNGs samt Draw-Call-Messung ab.
## Braucht einen echten Renderer (xvfb):
##   xvfb-run -a godot --path GOOBY-GODOT --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --fixed-fps 60 \
##     --script res://tests/unit/test_mpa_screens.gd -- before
## Argumente: `before`/`after` (Dateipräfix), `landscape`, `reward`
## (zusätzlich den Jubelmoment fotografieren), sonst Spiel-Ids.

const Stage3D := preload("res://scripts/minigames/games/_3dc_stage/stage3d.gd")

const OUT_DIR := "/tmp/gooby-godot/artifacts/MPA"
const HOST_SCENE := "res://scripts/minigames/minigame_host.tscn"
const PORTRAIT := Vector2i(720, 1160)
const LANDSCAPE := Vector2i(1160, 720)
const GAMES: Array[String] = ["teaParty", "goobySays", "memoryMatch", "pancakeTower"]
## Frame-Budget (Spielzeit) für Action- und Belohnungsjagd — Bot ist
## zustandsgetrieben, das Budget ist nur das Sicherheitsnetz.
const ACTION_FRAMES := 5400
const REWARD_FRAMES := 5400

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
	print("MPA-Screenshots fertig → %s" % OUT_DIR)
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
	var bot := {"phase": "action", "step": 0, "hold": false, "wait": 0, "shot_wait": -1}
	for _frame in ACTION_FRAMES:
		if game == null or not is_instance_valid(game) or _round_over(game):
			break
		_drive(game_id, game, viewport, bot)
		if int(bot["shot_wait"]) == 0:
			break
		await process_frame
	var suffix := "_landscape" if _landscape else ""
	await _snap("%s_%s%s.png" % [_prefix, game_id, suffix])
	print("    draw_calls=%d" % Stage3D.draw_calls())
	if _reward and game != null and is_instance_valid(game) and not _round_over(game):
		await _reward_moment(game_id, game, viewport, bot, suffix)
	host.queue_free()
	await process_frame


## Weiterspielen bis zum Jubel (Bot-Phase `reward` endet im Perfect/Match/
## Rundensieg), dann im Feuerwerk auslösen.
func _reward_moment(
	game_id: String, game: Node, viewport: SubViewport, bot: Dictionary, suffix: String
) -> void:
	bot["phase"] = "reward"
	bot["shot_wait"] = -1
	bot["wait"] = 0
	var got := false
	for _frame in REWARD_FRAMES:
		if game == null or not is_instance_valid(game) or _round_over(game):
			break
		_drive(game_id, game, viewport, bot)
		if int(bot["shot_wait"]) == 0:
			got = true
			break
		await process_frame
	if got:
		await _snap("%s_%s_reward%s.png" % [_prefix, game_id, suffix])
		print("    draw_calls(reward)=%d" % Stage3D.draw_calls())
	else:
		print("    KEIN Belohnungsmoment für %s im Budget." % game_id)


func _drive(game_id: String, game: Node, viewport: SubViewport, bot: Dictionary) -> void:
	if int(bot["shot_wait"]) > 0:
		bot["shot_wait"] = int(bot["shot_wait"]) - 1
		return
	match game_id:
		"teaParty":
			_drive_tea(game, viewport, bot)
		"goobySays":
			_drive_says(game, viewport, bot)
		"memoryMatch":
			_drive_memory(game, viewport, bot)
		"pancakeTower":
			_drive_pancake(game, viewport, bot)


## Tee: halten bis kurz vor Bandmitte. Action-Foto MITTEN im Gießstrahl,
## Belohnung: in der Bandmitte loslassen (Perfect) und im Jubel auslösen.
func _drive_tea(game: Node, viewport: SubViewport, bot: Dictionary) -> void:
	if bool(game.get("serving")):
		return
	var center := root.get_visible_rect().size * Vector2(0.5, 0.6)
	if not bool(bot["hold"]):
		_press(viewport, center)
		bot["hold"] = true
		return
	var level := float(game.get("level"))
	var band: Dictionary = game.get("band")
	var band_center := float(band.get("center", 0.7))
	if str(bot["phase"]) == "action":
		# Foto, sobald der Tee im Band steht (Strahl + Dampf + Ring im Bild).
		if level >= band_center - float(band.get("half", 0.07)) * 0.5:
			bot["shot_wait"] = 2
		return
	if level >= band_center - 0.012:
		_release(viewport, center)
		bot["hold"] = false
		bot["shot_wait"] = 6
	elif not bool(game.get("holding")):
		# Sicherheit: Overflow-Auto-Release hat gefeuert — neu ansetzen.
		bot["hold"] = false


## Gooby sagt: die Sequenz korrekt nachtippen. Action-Foto beim Vorspielen
## von Runde 2 (Pad leuchtet, Halo an), Belohnung im Rundensieg-Konfetti.
func _drive_says(game: Node, viewport: SubViewport, bot: Dictionary) -> void:
	var phase := str(game.get("phase"))
	var action := str(bot["phase"]) == "action"
	if action and phase == "watch" and int(game.get("round_no")) >= 2:
		if int(game.get("lit_pad")) >= 0:
			bot["shot_wait"] = 0
			return
	if phase != "input":
		bot["wait"] = 0
		return
	# Zwischen zwei Taps kurz atmen, sonst frisst der Debounce den 2. Akkord-Tap.
	if int(bot["wait"]) > 0:
		bot["wait"] = int(bot["wait"]) - 1
		return
	var sequence: Array = game.get("sequence")
	var step_index := int(game.get("step_index"))
	if step_index >= sequence.size():
		return
	var step: Variant = sequence[step_index]
	var chord_first := int(game.get("chord_first"))
	var pad := -1
	if step is Array:
		pad = int(step[1]) if chord_first >= 0 else int(step[0])
	else:
		pad = int(step)
	_tap(viewport, _says_pad_screen(game, pad))
	bot["wait"] = 3
	var last_step := step_index >= sequence.size() - 1
	if not action and last_step and (not (step is Array) or chord_first >= 0):
		# Letzter Schritt der Runde: gleich knallt das Konfetti.
		bot["shot_wait"] = 5


func _says_pad_screen(game: Node, pad: int) -> Vector2:
	var stage: Node = game.get("_stage")
	var pads: Array = stage.get("_pads")
	var inner: Node3D = stage.get("stage")
	var world: Vector3 = (pads[pad] as Node3D).position + Vector3(0.0, 0.2, 0.0)
	return inner.call("to_screen", world) as Vector2


## Memory: nach dem Reveal ein bekanntes Paar auftippen (Partner gemerkt).
## Action-Foto mit zwei offenen Karten mitten im Flip, Belohnung im Match.
func _drive_memory(game: Node, viewport: SubViewport, bot: Dictionary) -> void:
	if float(game.get("reveal_left")) > 0.0 or float(game.get("resolve_left")) > 0.0:
		return
	if not bool(bot.get("settled", false)):
		# Nach dem Reveal erst die Karten zuklappen lassen (sauberes Foto).
		bot["settled"] = true
		bot["wait"] = 30
		return
	if int(bot["wait"]) > 0:
		bot["wait"] = int(bot["wait"]) - 1
		return
	var picked: Array = game.get("picked")
	if picked.size() >= 2:
		return
	if picked.is_empty():
		var pair := _memory_find_pair(game.get("cards"))
		if pair.is_empty():
			return
		bot["partner"] = int(pair[1])
		_tap(viewport, game.call("_card_center", int(pair[0])))
		bot["wait"] = 3
		return
	_tap(viewport, game.call("_card_center", int(bot["partner"])))
	bot["wait"] = 3
	if str(bot["phase"]) == "action":
		# Beide Karten offen, zweite mitten im Hochklappen.
		bot["shot_wait"] = 3
	elif int(game.get("matched_pairs")) >= 1:
		# Zweites Paar in Folge: Match-Feuerwerk + Combo-Anzeige.
		bot["shot_wait"] = 14


func _memory_find_pair(cards: Array) -> Array:
	var by_face: Dictionary = {}
	for i in cards.size():
		var card: Dictionary = cards[i]
		if str(card["state"]) != "down":
			continue
		var face := int(card["face"])
		if by_face.has(face):
			return [by_face[face], i]
		by_face[face] = i
	return []


## Pfannkuchen: fallen lassen, wenn das Pendel die Stapelmitte kreuzt (nur im
## Perfect-Fenster tippen). Action-Foto mit ≥4 Lagen Turm, Belohnung direkt
## im Perfect-Funkenregen der nächsten Landung.
func _drive_pancake(game: Node, viewport: SubViewport, bot: Dictionary) -> void:
	if bool(game.get("falling")):
		bot["wait"] = 4
		return
	if int(bot["wait"]) > 0:
		bot["wait"] = int(bot["wait"]) - 1
		if int(bot["wait"]) > 0:
			return
		# Gerade gelandet: je nach Phase Foto planen.
		var layers: Array = game.get("layers")
		if str(bot["phase"]) == "action" and layers.size() >= 4:
			bot["shot_wait"] = 1
		elif str(bot["phase"]) == "reward" and int(game.get("perfects")) > int(bot["step"]):
			bot["shot_wait"] = 1
		bot["step"] = int(game.get("perfects"))
		return
	var stack: Dictionary = game.get("stack")
	var stage: Node = game.get("_stage")
	var active: Node3D = stage.get("_active")
	if absf(active.position.x - float(stack["center"])) <= 0.042:
		_tap(viewport, root.get_visible_rect().size * Vector2(0.5, 0.6))
		bot["wait"] = 6


func _round_over(game: Node) -> bool:
	return "finished" in game and bool(game.get("finished"))


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
