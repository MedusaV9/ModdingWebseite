extends SceneTree
## MG-1-Screenshot-Werkzeug (KEIN Test): montiert den MinigameHost für die
## Batch-1-Spiele, spielt sie mit einem kleinen Bot ein paar Sekunden und legt
## PNGs ab. Braucht einen echten Renderer (xvfb):
##   xvfb-run -a godot --path GOOBY-GODOT --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --script res://tests/unit/screenshot_mg1.gd
## Optional: `-- <spiel-id> …` (ohne Argument: alle neun + Arcade-Grid).
## Mit `-- landscape <id> …` schießt es die Querformat-Variante.

const OUT_DIR := "/tmp/gooby-godot/artifacts/MG1"
const HOST_SCENE := "res://scripts/minigames/minigame_host.tscn"
const PORTRAIT := Vector2i(720, 1160)
const LANDSCAPE := Vector2i(1160, 720)
const GAMES: Array[String] = [
	"bubblePop",
	"memoryMatch",
	"goobySays",
	"pipeFlow",
	"carrotGuard",
	"bunnyHop",
	"trampoline",
	"veggieChop",
	"gardenRush",
]
## Sekunden Spielzeit vor dem Foto (der Bot spielt so lange mit).
const SECONDS := {
	"bubblePop": 16.0,
	"memoryMatch": 4.0,
	"goobySays": 7.0,
	"pipeFlow": 6.0,
	"carrotGuard": 6.0,
	"bunnyHop": 7.0,
	"trampoline": 12.0,
	# Erst ab 20 s wirft die Küche zwei Stücke pro Welle (WAVE2_FROM_SEC) —
	# vorher ist das Brett fast immer leer und das Foto nichtssagend.
	"veggieChop": 24.0,
	"gardenRush": 7.0,
}

var _landscape := false
var _pipe_plan: Array[int] = []
var _pipe_puzzle := -1


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.theme = ThemeService.theme()
	var ids: Array[String] = []
	for arg in OS.get_cmdline_user_args():
		if str(arg) == "landscape":
			_landscape = true
		else:
			ids.append(str(arg))
	if ids.is_empty():
		ids = GAMES.duplicate()
		ids.append("arcade")
	for id in ids:
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
	_pipe_plan = []
	_pipe_puzzle = -1
	# Der Software-Renderer schafft nur ~10 fps, also zählt die WANDUHR, nicht
	# die Bildzahl — sonst spielt der Bot ein Vielfaches der geplanten Zeit.
	var budget_ms := int(float(SECONDS.get(game_id, 5.0)) * 1000.0)
	var started_ms := Time.get_ticks_msec()
	var frame := 0
	while true:
		var spent := Time.get_ticks_msec() - started_ms
		if spent >= budget_ms:
			break
		if game == null or not is_instance_valid(game) or _round_over(game):
			break
		_drive(game_id, game, viewport, frame, spent > budget_ms - 700)
		frame += 1
		await process_frame
	# Nachlauf: bis zu 10 s weiterspielen, bis der Moment etwas hergibt (Gooby
	# in der Luft, Karte aufgedeckt, Maulwurf oben …) — leere Bühnen taugen
	# nicht als Beleg. 3 s reichten nicht: Wurfwellen in veggieChop liegen
	# zeitweise weiter auseinander.
	var grace := Time.get_ticks_msec() + 10000
	while game != null and is_instance_valid(game) and not _round_over(game):
		if _photogenic(game_id, game) or Time.get_ticks_msec() > grace:
			break
		_drive(game_id, game, viewport, frame, true)
		frame += 1
		await process_frame
	var suffix := "_landscape" if _landscape else ""
	await _snap("%s%s.png" % [game_id, suffix])
	host.queue_free()
	await process_frame


func _shoot_arcade() -> void:
	# Extra hoch, damit ALLE Kacheln ins Bild passen (bei 1160 px fielen die
	# letzten beiden Reihen unter die Kante).
	_resize(Vector2i(PORTRAIT.x, 1560))
	var screen: Control = (
		(load("res://scripts/minigames/arcade_screen.tscn") as PackedScene).instantiate()
	)
	if "auto_navigate" in screen:
		screen.set("auto_navigate", false)
	root.add_child(screen)
	for _i in 30:
		await process_frame
	await _snap("arcade_grid.png")
	screen.queue_free()
	await process_frame


## Mini-Bot je Spiel: erzeugt echte Touch-Events, damit die Fotos das Spiel
## MITTEN im Geschehen zeigen (und nicht nur den leeren Startzustand).
func _drive(game_id: String, game: Node, viewport: SubViewport, frame: int, near_end: bool) -> void:
	match game_id:
		"bubblePop":
			_drive_bubble_pop(game, viewport, frame)
		"memoryMatch":
			_drive_memory_match(game, viewport, frame)
		"goobySays":
			_drive_gooby_says(game, viewport)
		"pipeFlow":
			_drive_pipe_flow(game, viewport, frame)
		"carrotGuard":
			_drive_carrot_guard(game, viewport, frame)
		"bunnyHop":
			_drive_bunny_hop(game, viewport)
		"trampoline":
			_drive_trampoline(game, viewport, frame)
		"veggieChop":
			_drive_veggie_chop(game, viewport, frame)
		"gardenRush":
			_drive_garden_rush(game, viewport, frame, near_end)
		_:
			pass


## True, sobald die Runde vorbei ist — dann lohnt kein weiterer Bot-Tipp mehr.
func _round_over(game: Node) -> bool:
	return "finished" in game and bool(game.get("finished"))


## Lohnt sich der Auslöser JETZT? Je Spiel der Moment, der die Mechanik zeigt.
func _photogenic(game_id: String, game: Node) -> bool:
	var ready := true
	match game_id:
		"trampoline":
			ready = bool(game.get("airborne")) and float(game.get("height")) > 1.2
		"bunnyHop":
			ready = bool(game.get("started")) and int(game.get("gates")) > 0
		"carrotGuard":
			ready = not (game.get("king") as Dictionary).is_empty() or _mole_is_up(game)
		"veggieChop":
			# Zwei gleichzeitige Würfe (ab 20 s die Regel) — ein einzelnes
			# Stück knapp über der Platte belegt die Mechanik nicht.
			ready = (game.get("items") as Array).size() >= 2
		"memoryMatch":
			# Offene ODER schon gefundene Karten — ein reines Rückseiten-Raster
			# belegt die Mechanik nicht.
			ready = _face_up_cards(game) >= 2
		"goobySays":
			ready = str(game.get("phase")) in ["show", "input"]
		"gardenRush":
			ready = int(game.get("hold_index")) >= 0
		"pipeFlow":
			# `filling` heisst: das Wasser läuft gerade sichtbar durch — genau
			# der Moment, den das Foto zeigen soll (vorher stand hier `not`).
			ready = bool(game.get("filling"))
		"bubblePop":
			# Eine Blase der gesuchten Sorte muss im Bild sein, sonst wirkt die
			# Zielanzeige oben ("Zerplatze: Banane") wie ein Fehler.
			ready = (game.get("bubbles") as Array).size() >= 5 and _target_bubble_visible(game)
	return ready


func _mole_is_up(game: Node) -> bool:
	for mole: Dictionary in game.get("moles"):
		if float(mole["up"]) > 0.7:
			return true
	return false


func _face_up_cards(game: Node) -> int:
	var open := 0
	for card: Dictionary in game.get("cards"):
		if str(card["state"]) != "down":
			open += 1
	return open


func _target_bubble_visible(game: Node) -> bool:
	var wanted: String = game.call("target_food")
	for bubble: Dictionary in game.get("bubbles"):
		if str(bubble.get("food", "")) == wanted:
			return true
	return false


func _drive_bubble_pop(game: Node, viewport: SubViewport, frame: int) -> void:
	if frame % 7 != 0:
		return
	var target: String = game.call("target_food")
	for bubble: Dictionary in game.get("bubbles"):
		if str(bubble.get("food", "")) != target:
			continue
		var world := Vector2(float(bubble["x"]), float(bubble["y"]))
		_tap(viewport, game.call("_to_screen", world))
		return


func _drive_memory_match(game: Node, viewport: SubViewport, frame: int) -> void:
	if frame % 4 != 0 or float(game.get("reveal_left")) > 0.0:
		return
	var cards: Array = game.get("cards")
	for i in cards.size():
		if str((cards[i] as Dictionary)["state"]) == "down":
			_tap(viewport, game.call("_card_pos", i) + Vector2(game.get("_card_size")) * 0.5)
			return


func _drive_gooby_says(game: Node, viewport: SubViewport) -> void:
	if str(game.get("phase")) != "input":
		return
	var sequence: Array = game.get("sequence")
	var step_index := int(game.get("step_index"))
	if step_index >= sequence.size():
		return
	var pads: Array = game.get("_pads")
	var step: Variant = sequence[step_index]
	var pad: int = int(step[0]) if step is Array else int(step)
	if int(game.get("chord_first")) >= 0 and step is Array:
		pad = int(step[1]) if int(game.get("chord_first")) == int(step[0]) else int(step[0])
	if pad < pads.size():
		_tap(viewport, (pads[pad] as Rect2).get_center())


## Rohrpost bekommt die echte Solver-Lösung Tap für Tap serviert.
func _drive_pipe_flow(game: Node, viewport: SubViewport, frame: int) -> void:
	var puzzle := int(game.get("puzzle_no"))
	if puzzle != _pipe_puzzle:
		_pipe_puzzle = puzzle
		var solution: Dictionary = PipeFlowLogic.solve_board(game.get("board"))
		_pipe_plan = []
		for idx: int in solution["taps"]:
			_pipe_plan.append(idx)
	if frame % 10 != 0 or _pipe_plan.is_empty():
		return
	var index: int = _pipe_plan.pop_front()
	_tap(viewport, game.call("_cell_center", index))


func _drive_carrot_guard(game: Node, viewport: SubViewport, frame: int) -> void:
	if frame % 6 != 0:
		return
	var king: Dictionary = game.get("king")
	var holes: Array = game.get("_holes")
	if not king.is_empty():
		_tap(viewport, (holes[int(king["hole"])] as Rect2).get_center())
		return
	for mole: Dictionary in game.get("moles"):
		if float(mole["up"]) > 0.6:
			_tap(viewport, (holes[int(mole["hole"])] as Rect2).get_center())
			return


## Hüpf-Bot 1:1 nach der Web-Autoplay-Routine (bunnyHop.js `autoplayTick`):
## Zielband ist die nächste Lücke, mit Deckel-Check gegen die Oberkante.
func _drive_bunny_hop(game: Node, viewport: SubViewport) -> void:
	if not bool(game.get("started")):
		_tap(viewport, Vector2(200.0, 400.0))
		return
	var tune: Dictionary = game.get("tune")
	var scroll := float(game.get("scroll"))
	var y := float(game.get("gooby_y"))
	var vy := float(game.get("gooby_vy"))
	var gooby_x: float = game.call("_gooby_world_x")
	var half_h := float(tune["BODY_HALF_H"]) * float(tune["HITBOX_SCALE"])
	var hit_dist := float(tune["PILLAR_HALF_W"]) + float(tune["BODY_HALF_W"])
	var speed := BunnyHopLogic.speed_at_gate(int(game.get("gates")), tune)
	var horizon := hit_dist + speed * 0.45
	var next_x := INF
	var target := 0.0
	for pillar: Dictionary in game.get("pillars"):
		var px := float(pillar["x"]) - scroll
		if px + float(tune["PILLAR_HALF_W"]) > gooby_x - 0.2 and px < next_x:
			next_x = px
			target = float(pillar["gapCenterY"]) - float(pillar["gapHeight"]) * 0.1
	var cap_ok := true
	for pillar: Dictionary in game.get("pillars"):
		var dx := float(pillar["x"]) - scroll - gooby_x
		var gap_top := float(pillar["gapCenterY"]) + float(pillar["gapHeight"]) * 0.5
		var gap_bottom := float(pillar["gapCenterY"]) - float(pillar["gapHeight"]) * 0.5
		if dx > -hit_dist and dx < horizon:
			if y + 0.62 + half_h > gap_top:
				cap_ok = false
			target = maxf(target, gap_bottom + half_h + 0.25)
		elif dx >= horizon and is_equal_approx(dx + gooby_x, next_x):
			var arrival := (dx - hit_dist) / speed
			if arrival < 1.1:
				var hop_y := (
					y
					+ float(tune["HOP_VY"]) * arrival
					+ 0.5 * float(tune["GRAVITY"]) * arrival * arrival
				)
				if hop_y + half_h > gap_top - 0.1:
					cap_ok = false
	var lead := maxf(0.0, -vy) * 0.14
	if vy < 0.0 and cap_ok and y < target + lead:
		_tap(viewport, Vector2(200.0, 400.0))


func _drive_trampoline(game: Node, viewport: SubViewport, frame: int) -> void:
	var tune: Dictionary = game.get("tune")
	var tti: float = game.call("_time_to_impact")
	var apex := float(game.get("apex"))
	# Tippen im vollen Boost-Fenster: bei ~10 fps liegen nur ein bis zwei
	# Frames darin, ein Sicherheitsabschlag würde es regelmäßig verfehlen.
	if float(game.get("vy")) < 0.0 and tti <= TrampolineLogic.window_sec_for(apex, tune):
		_tap(viewport, Vector2(200.0, 600.0))
		return
	# Sonst in der Luft wischen (Trick) — nur weit weg von der Matte.
	if frame % 20 == 0 and tti > 0.6:
		if TrampolineLogic.can_trick(bool(game.get("airborne")), tti, false, tune):
			var from := Vector2(200.0, 500.0)
			_swipe(viewport, from, from + Vector2(-140.0, 0.0))


## Hackt das am weitesten gestiegene Gemüse — Müll bleibt liegen. Ohne den
## Höhenfilter der ersten Fassung, sonst rutschen Würfe unbemerkt durch.
func _drive_veggie_chop(game: Node, viewport: SubViewport, frame: int) -> void:
	if frame % 2 != 0:
		return
	var best: Dictionary = {}
	var best_y := -INF
	for entry: Dictionary in game.get("items"):
		var item: Dictionary = entry["item"]
		if str(item["kind"]) == "junk":
			continue
		var pos := Vector2(entry["pos"])
		if pos.y > best_y:
			best_y = pos.y
			best = entry
	if best.is_empty():
		return
	var screen: Vector2 = game.call("_to_screen", Vector2(best["pos"]))
	_swipe(viewport, screen + Vector2(-90.0, 70.0), screen + Vector2(90.0, -70.0))


## Der Gieß-Bot hält den Ring bis kurz vor die grüne Zone und lässt dann los —
## fürs Foto bleibt der letzte Halt offen, damit der Füllring sichtbar ist.
func _drive_garden_rush(game: Node, viewport: SubViewport, frame: int, near_end: bool) -> void:
	var hold_index := int(game.get("hold_index"))
	if hold_index >= 0:
		var fill := GardenRushLogic.hold_fill_fraction(
			float(game.get("hold_sec")), game.get("tune")
		)
		if fill >= 0.98 and not near_end:
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


func _swipe(viewport: SubViewport, from: Vector2, to: Vector2) -> void:
	_press(viewport, from)
	for i in range(1, 6):
		var drag := InputEventScreenDrag.new()
		drag.position = from.lerp(to, float(i) / 5.0)
		viewport.push_input(drag, true)
	_release(viewport, to)


## Jede Runde kostet Energie — nach ein paar Fotos verweigert der Host den
## Start ("Gooby erschöpft"). Für das Werkzeug wird sie vorher aufgefüllt.
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
	# Nur zwei Frames warten: bei ~10 fps wäre ein längerer Vorlauf lang genug,
	# dass der eingefangene Moment schon wieder vorbei ist.
	for _i in 2:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("  gespeichert: %s (%dx%d)" % [file, image.get_width(), image.get_height()])
