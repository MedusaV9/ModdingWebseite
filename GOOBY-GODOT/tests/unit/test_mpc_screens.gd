extends SceneTree
## MP-C Screenshot-/Bot-Werkzeug (KEIN Test — der Haupt-Runner überspringt
## Nicht-TestCase-Dateien mit SKIP). Montiert die vier MP-C-Spiele (bunnyHop,
## trampoline, danceParty, veggieChop) DIREKT, spielt sie mit einem einfachen
## Frame-Bot und fotografiert Bühne + Belohnungsmomente. Braucht einen echten
## Renderer (xvfb):
##   xvfb-run -a godot --path GOOBY-GODOT --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --fixed-fps 60 \
##     --script res://tests/unit/test_mpc_screens.gd -- [before|after] \
##     [landscape] [ids...]
## `--fixed-fps 60` ist PFLICHT: der Software-Renderer schafft nur ~7 fps.

const OUT_BASE := "/tmp/gooby-godot/artifacts/MPC"
const PORTRAIT := Vector2i(720, 1160)
const LANDSCAPE := Vector2i(1160, 720)
const GAMES: Array[String] = ["bunnyHop", "trampoline", "danceParty", "veggieChop"]

var _phase := "before"
var _landscape := false
var _juice: JuiceKit
var _overlay: Control
var _game: Node
var _snap_count := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.theme = ThemeService.theme()
	var ids: Array[String] = []
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		if text == "before" or text == "after":
			_phase = text
		elif text == "landscape":
			_landscape = true
		else:
			ids.append(text)
	if ids.is_empty():
		ids = GAMES
	DirAccess.make_dir_recursive_absolute("%s/%s" % [OUT_BASE, _phase])
	for id in ids:
		await _shoot(id)
	print("MPC-Screenshots fertig → %s/%s" % [OUT_BASE, _phase])
	quit(0)


func _shoot(game_id: String) -> void:
	_resize(LANDSCAPE if _landscape else PORTRAIT)
	await _mount(game_id)
	match game_id:
		"bunnyHop":
			await _play_bunny_hop()
		"trampoline":
			await _play_trampoline()
		"danceParty":
			await _play_dance_party()
		"veggieChop":
			await _play_veggie_chop()
	_teardown()
	await process_frame


func _mount(game_id: String) -> void:
	_snap_count = 0
	var meta := MinigameRegistry.get_game(game_id)
	var ctx := MinigameCtx.new()
	ctx.game_id = game_id
	ctx.difficulty = "normal"
	ctx.orientation = "landscape" if _landscape else "portrait"
	ctx.run_seed = 4242
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_overlay)
	_juice = JuiceKit.new()
	_juice.float_text_parent = _overlay
	root.add_child(_juice)
	ctx.juice = _juice
	_game = (load(str(meta["scene"])) as PackedScene).instantiate()
	root.add_child(_game)
	root.move_child(_overlay, root.get_child_count() - 1)
	_game.call("setup", ctx)
	await process_frame
	_game.call("start")
	if _game.has_method("apply_view"):
		_game.call("apply_view", root.get_visible_rect().size)
	for _i in 8:
		await process_frame


func _teardown() -> void:
	_game.queue_free()
	_juice.queue_free()
	_overlay.queue_free()


# ── Bots ──────────────────────────────────────────────────────────────────


## Flatter-Bot: hüpft, sobald Gooby unter das Lückenzentrum der nächsten
## Säule fällt. Fotos: Belohnung (Tor passiert), Mitte des Laufs.
func _play_bunny_hop() -> void:
	var reward_shot := false
	var reward_wait := -1
	var prev_gates := 0
	for frame in 720:
		if not bool(_game.get("finished")):
			# Tore zählen im SPIEL-Frame hoch — über Schleifendurchläufe
			# vergleichen, nicht um den Bot-Aufruf herum.
			var gates := int(_game.get("gates"))
			if reward_wait < 0 and not reward_shot and gates > prev_gates and gates >= 2:
				reward_wait = 6
			prev_gates = gates
			_bunny_bot(frame)
		if reward_wait > 0:
			reward_wait -= 1
		elif reward_wait == 0:
			reward_wait = -1
			reward_shot = true
			await _snap("bunnyHop_reward")
		if frame == 430 or (_landscape and frame == 240):
			await _snap("bunnyHop_mid")
			if _landscape:
				return
		await process_frame


func _bunny_bot(frame: int) -> void:
	if frame == 20:
		_tap(Vector2(0.5, 0.6))
		return
	if not bool(_game.get("started")):
		return
	var gooby_y := float(_game.get("gooby_y"))
	var gooby_vy := float(_game.get("gooby_vy"))
	var scroll := float(_game.get("scroll"))
	var gooby_x: float = _game.call("_gooby_world_x")
	var target := 0.6
	for pillar: Dictionary in _game.get("pillars"):
		if float(pillar["x"]) - scroll > gooby_x - 0.4:
			target = float(pillar["gapCenterY"])
			break
	if gooby_vy < 0.4 and gooby_y < target - 0.1:
		_tap(Vector2(0.5, 0.6))


## Trampolin-Bot: tippt im Landefenster (Boost) und wischt in der Luft
## (Tricks). Fotos: Trick-Belohnung, Boost-Moment, Mitte des Laufs.
func _play_tramp_swipe(kind: int) -> void:
	var mid := root.get_visible_rect().size * 0.5
	var deltas: Array[Vector2] = [Vector2(-70, 0), Vector2(70, 0), Vector2(0, -70)]
	var delta: Vector2 = deltas[kind % 3]
	var touch := InputEventScreenTouch.new()
	touch.position = mid
	touch.pressed = true
	root.push_input(touch, true)
	var drag := InputEventScreenDrag.new()
	drag.position = mid + delta
	root.push_input(drag, true)
	var up := InputEventScreenTouch.new()
	up.position = mid + delta
	up.pressed = false
	root.push_input(up, true)


func _play_trampoline() -> void:
	var trick_shot := false
	var boost_shot := false
	var wait_kind := ""
	var wait := -1
	var flight := 0
	var tricked := false
	var tune: Dictionary = _game.get("tune")
	for frame in 720:
		if not bool(_game.get("finished")):
			var score_before := int(_game.get("score"))
			var vy := float(_game.get("vy"))
			var height := float(_game.get("height"))
			var apex := float(_game.get("apex"))
			if vy > 0.0 and height < 0.2:
				flight += 1
				tricked = false
			if vy < 0.0:
				var tti: float = TrampolineLogic.time_to_impact(height, vy, float(tune["GRAVITY"]))
				var window: float = TrampolineLogic.window_sec_for(apex, tune)
				if tti <= window * 0.55 and str(_game.get("armed")).is_empty():
					_tap(Vector2(0.5, 0.55))
			elif not tricked and height > apex * 0.5 and frame > 90:
				tricked = true
				_play_tramp_swipe(flight)
			if wait < 0 and not trick_shot and int(_game.get("score")) > score_before:
				wait = 6
				wait_kind = "trampoline_reward_trick"
			if wait < 0 and not boost_shot and float(_game.get("_shock")) > 0.9 and vy < 0.0:
				# Mattenkontakt gerade passiert — Boost sichtbar, wenn die
				# neue Steiggeschwindigkeit über BASE_VY liegt.
				if float(_game.get("vy")) > float(tune["BASE_VY"]) + 0.3:
					wait = 5
					wait_kind = "trampoline_reward_boost"
		if wait > 0:
			wait -= 1
		elif wait == 0:
			wait = -1
			if wait_kind.ends_with("trick"):
				trick_shot = true
			else:
				boost_shot = true
			await _snap(wait_kind)
		if frame == 430 or (_landscape and frame == 240):
			await _snap("trampoline_mid")
			if _landscape:
				return
		await process_frame


## Tanz-Bot: tippt jede Note im Perfekt-Fenster. Fotos: Combo-Belohnung,
## Zugabe (Encore), Mitte des Laufs.
func _play_dance_party() -> void:
	var combo_shot := false
	var encore_shot := false
	var tapped: Array = []
	for frame in 900:
		if not bool(_game.get("finished")):
			var song_time := float(_game.get("song_time"))
			var notes: Array = _game.get("notes")
			var head := int(_game.get("_head"))
			for i in range(head, mini(notes.size(), head + 12)):
				var note: Dictionary = notes[i]
				if bool(note["hit"]) or bool(note["missed"]) or tapped.has(i):
					continue
				if absf(float(note["time"]) - song_time) <= 0.024:
					tapped.append(i)
					var x: float = _game.call("lane_x", int(note["lane"]))
					_tap(Vector2(x / root.get_visible_rect().size.x, 0.74))
					break
			var tally: Dictionary = _game.get("tally")
			if not combo_shot and int(tally["combo"]) >= 6:
				combo_shot = true
				await _snap("danceParty_reward_combo")
			var fever: Dictionary = _game.get("fever")
			if not encore_shot and DancePartyLogic.encore_active(fever, song_time):
				encore_shot = true
				for _i in 10:
					await process_frame
				await _snap("danceParty_reward_encore")
		if frame == 500 or (_landscape and frame == 300):
			await _snap("danceParty_mid")
			if _landscape:
				return
		await process_frame


## Schnippel-Bot: wischt durch Gemüse nahe des Scheitels (nie durch Müll).
## Fotos: Wisch-Combo, Frenzy (Zeit wird vorgespult), Mitte des Laufs.
func _play_veggie_chop() -> void:
	var combo_shot := false
	var frenzy_shot := false
	var swipe_cool := 0
	for frame in 1100:
		if not bool(_game.get("finished")):
			swipe_cool = maxi(0, swipe_cool - 1)
			if swipe_cool == 0 and _veggie_swipe():
				swipe_cool = 14
			if not combo_shot and int(_game.get("swipe_combo")) >= 2:
				combo_shot = true
				for _i in 4:
					await process_frame
				await _snap("veggieChop_reward_combo")
			if frame == 620 and not _landscape:
				# Zeitraffer zum ersten Frenzy (25 s) — nur fürs Foto.
				_game.set("elapsed", 24.4)
			if not frenzy_shot and int(_game.get("frenzy_left")) > 0:
				frenzy_shot = true
				for _i in 30:
					await process_frame
				await _snap("veggieChop_reward_frenzy")
		if frame == 380 or (_landscape and frame == 300):
			await _snap("veggieChop_mid")
			if _landscape:
				return
		await process_frame


func _veggie_swipe() -> bool:
	var best_screen := Vector2.ZERO
	var found := false
	for entry: Dictionary in _game.get("items"):
		var item: Dictionary = entry["item"]
		if str(item["kind"]) != "veggie":
			continue
		var pos: Vector2 = entry["pos"]
		if pos.y < 0.4:
			continue
		best_screen = _game.call("_to_screen", pos)
		found = true
		break
	if not found:
		return false
	var size := root.get_visible_rect().size
	var from := best_screen + Vector2(-70, 55)
	var to := best_screen + Vector2(70, -55)
	if from.x < 4.0 or to.x > size.x - 4.0:
		return false
	var touch := InputEventScreenTouch.new()
	touch.position = from
	touch.pressed = true
	root.push_input(touch, true)
	var drag := InputEventScreenDrag.new()
	drag.position = best_screen
	root.push_input(drag, true)
	var drag2 := InputEventScreenDrag.new()
	drag2.position = to
	root.push_input(drag2, true)
	var up := InputEventScreenTouch.new()
	up.position = to
	up.pressed = false
	root.push_input(up, true)
	return true


# ── Eingabe/Foto ──────────────────────────────────────────────────────────


func _tap(rel: Vector2) -> void:
	var pos := root.get_visible_rect().size * rel
	var down := InputEventScreenTouch.new()
	down.position = pos
	down.pressed = true
	root.push_input(down, true)
	var up := InputEventScreenTouch.new()
	up.position = pos
	up.pressed = false
	root.push_input(up, true)


func _snap(name: String) -> void:
	for _i in 3:
		await process_frame
	var draws := RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
	)
	var suffix := "_landscape" if _landscape else ""
	var file := "%s/%s/%s%s.png" % [OUT_BASE, _phase, name, suffix]
	var image := root.get_texture().get_image()
	image.save_png(file)
	_snap_count += 1
	print("  Foto %s (%dx%d) Draw-Calls=%d" % [file, image.get_width(), image.get_height(), draws])


func _resize(size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	root.size = size
