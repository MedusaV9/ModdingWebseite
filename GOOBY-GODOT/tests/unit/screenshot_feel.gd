extends SceneTree
## POLISH-A Foto-/Clip-Werkzeug (KEIN Test): spielt memoryMatch mit einem
## perfekten Paar-Bot durch den kompletten Belohnungsbogen — Countdown,
## Combo-Serie, absichtlicher Fehlgriff, Sieg (Zeitlupe), Results mit
## Count-Up/Sternen/„Neuer Rekord!“/Münz-Regen — und legt PNGs + Frame-Folgen
## für ffmpeg-Clips ab. Braucht einen echten Renderer (xvfb):
##   xvfb-run -a godot --path GOOBY-GODOT --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --script res://tests/unit/screenshot_feel.gd
## Nebenbei misst es die Draw-Calls (Budget ≤250) je Phase.

const OUT_DIR := "/tmp/gooby-godot/artifacts/POLISHA"
const HOST_SCENE := "res://scripts/minigames/minigame_host.tscn"
const PORTRAIT := Vector2i(720, 1160)
const GAME_ID := "memoryMatch"

var _host: MinigameHost
var _viewport: SubViewport
var _game: Node
var _phase := ""
var _frame_no := 0
var _phase_frames := {}
var _phase_started_ms := {}
var _phase_elapsed_ms := {}
var _max_draw_calls := {}
var _shot_sieg := false


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	for sub in ["", "/frames_countdown", "/frames_gameplay", "/frames_results"]:
		DirAccess.make_dir_recursive_absolute(OUT_DIR + sub)
	root.theme = ThemeService.theme()
	DisplayServer.window_set_size(PORTRAIT)
	root.size = PORTRAIT
	_refill_energy()
	_reset_best()
	_host = (load(HOST_SCENE) as PackedScene).instantiate()
	_host.auto_navigate = false
	_host.receive_params(
		{"game_id": GAME_ID, "difficulty": "normal", "seed": 4242, "orientation": "portrait"}
	)
	root.add_child(_host)
	await _phase_countdown()
	await _phase_gameplay()
	await _phase_results()
	for phase: String in _max_draw_calls:
		print(
			(
				"PERF %s: frames=%d elapsed=%dms max_draw_calls=%d"
				% [phase, _phase_frames[phase], _phase_elapsed_ms[phase], _max_draw_calls[phase]]
			)
		)
	print("Feel-Screenshots fertig → %s" % OUT_DIR)
	quit(0)


## Countdown 3-2-1-GO: jedes Frame aufzeichnen, „3“ und „GO“ als Fotos.
func _phase_countdown() -> void:
	_begin_phase("countdown")
	var label: Label = _host.get("_countdown_label")
	var shot_three := false
	var shot_go := false
	var budget := Time.get_ticks_msec() + 12000
	while Time.get_ticks_msec() < budget:
		await process_frame
		_record_frame()
		if label == null or not is_instance_valid(label):
			break
		if not shot_three and label.text == "3" and _frame_no >= 2:
			shot_three = true
			await _snap("screenshot_countdown.png")
		if not shot_go and not str(label.text).is_valid_int() and label.text != "":
			shot_go = true
			await _snap("screenshot_countdown_go.png")
		if not label.visible:
			break
	_viewport = _sub_viewport()
	_game = _game_node()
	_end_phase()


## Perfekter Paar-Bot: 3 Treffer in Serie (Combo ×3), dann ein absichtlicher
## Fehlgriff (Fehler-Feedback), dann den Rest lösen → Sieg + Results.
func _phase_gameplay() -> void:
	_begin_phase("gameplay")
	await _wait_until(func() -> bool: return float(_game.get("reveal_left")) <= 0.0, 8000)
	for i in 3:
		await _play_pair(true)
	await _frames(2)
	await _snap("screenshot_combo.png")
	await _play_pair(false)
	for _i in 40:
		if bool(_game.get("finished")):
			break
		await _play_pair(true)
	_end_phase()


## Results-Screen: ~7 s Wanduhr aufzeichnen (Count-Up → Sterne → Rekord-
## Konfetti → Münz-Regen); Fotos in der Count-Up- und der Rekord-Phase.
func _phase_results() -> void:
	_begin_phase("results")
	var results: Control = _host.get("_results")
	await _wait_until(func() -> bool: return results.visible, 8000)
	var started := Time.get_ticks_msec()
	var shot_count := false
	var shot_record := false
	while Time.get_ticks_msec() - started < 7000:
		await process_frame
		_record_frame()
		var spent := Time.get_ticks_msec() - started
		if not shot_count and spent >= 400:
			shot_count = true
			await _snap("screenshot_ergebnis.png")
		if not shot_record and spent >= 2100:
			shot_record = true
			await _snap("screenshot_rekord.png")
	_end_phase()


## Ein Kartenpaar spielen: matching=true tippt ein echtes Paar an,
## matching=false absichtlich zwei verschiedene (Fehler-Moment + Foto).
func _play_pair(matching: bool) -> void:
	var pick := _find_pick(matching)
	if pick.is_empty():
		return
	_tap_card(pick[0])
	await _wait_until(func() -> bool: return str(_card(pick[0])["state"]) == "up", 4000)
	_tap_card(pick[1])
	if not matching:
		await _frames(2)
		await _snap("screenshot_fehler.png")
	await _wait_until(func() -> bool: return (_game.get("picked") as Array).is_empty(), 6000)
	# Siegmoment SOFORT einfangen (Zeitlupe + Jubel-Text laufen nur während
	# der 0.9-s-Atempause, ehe der Results-Screen sie zudeckt) — ohne die
	# langsamen Aufzeichnungs-Frames dazwischen.
	if not _shot_sieg and bool(_game.get("finished")):
		_shot_sieg = true
		await process_frame
		_snap_now("screenshot_sieg.png")
		await process_frame
		_snap_now("screenshot_sieg_b.png")
	await _frames(1)


## Zwei „down“-Karten: passend (is_match) oder absichtlich unpassend.
func _find_pick(matching: bool) -> Array[int]:
	var cards: Array = _game.get("cards")
	var down: Array[int] = []
	for i in cards.size():
		if str((cards[i] as Dictionary)["state"]) == "down":
			down.append(i)
	for a in down.size():
		for b in range(a + 1, down.size()):
			var hit := MemoryMatchLogic.is_match(
				int(_card(down[a])["face"]), int(_card(down[b])["face"])
			)
			if hit == matching:
				return [down[a], down[b]]
	return []


func _card(index: int) -> Dictionary:
	return (_game.get("cards") as Array)[index]


func _tap_card(index: int) -> void:
	var pos: Vector2 = _game.call("_card_pos", index)
	pos += Vector2(_game.get("_card_size")) * 0.5
	for pressed in [true, false]:
		var touch := InputEventScreenTouch.new()
		touch.pressed = pressed
		touch.position = pos
		_viewport.push_input(touch, true)


func _begin_phase(phase: String) -> void:
	_phase = phase
	_frame_no = 0
	_phase_frames[phase] = 0
	_phase_started_ms[phase] = Time.get_ticks_msec()
	_max_draw_calls[phase] = 0


func _end_phase() -> void:
	_phase_elapsed_ms[_phase] = Time.get_ticks_msec() - int(_phase_started_ms[_phase])
	_phase_frames[_phase] = _frame_no


func _record_frame() -> void:
	var calls := int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	_max_draw_calls[_phase] = maxi(int(_max_draw_calls[_phase]), calls)
	var image := root.get_texture().get_image()
	image.save_png("%s/frames_%s/f%04d.png" % [OUT_DIR, _phase, _frame_no])
	_frame_no += 1


func _frames(count: int) -> void:
	for _i in count:
		await process_frame
		_record_frame()


func _wait_until(predicate: Callable, budget_ms: int) -> void:
	var deadline := Time.get_ticks_msec() + budget_ms
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return
		await process_frame
		_record_frame()


func _snap(file: String) -> void:
	await process_frame
	_snap_now(file)


func _snap_now(file: String) -> void:
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("  gespeichert: %s" % file)


func _sub_viewport() -> SubViewport:
	var found := _host.find_children("*", "SubViewport", true, false)
	return null if found.is_empty() else found[0] as SubViewport


func _game_node() -> Node:
	if _viewport == null or _viewport.get_child_count() == 0:
		return null
	return _viewport.get_child(_viewport.get_child_count() - 1)


func _refill_energy() -> void:
	var gs := root.get_node_or_null(^"/root/GameState")
	if gs != null and gs.has_method("set_value"):
		gs.call("set_value", "gooby.stats.energy", 100.0)


## Bestwert löschen, damit die Runde sicher „Neuer Rekord!“ feiert.
func _reset_best() -> void:
	var gs := root.get_node_or_null(^"/root/GameState")
	if gs == null or not gs.has_method("update"):
		return
	gs.call(
		"update",
		func(state: Dictionary) -> void:
			var legacy: Dictionary = (state["minigames"] as Dictionary)["legacy"]
			(legacy["best"] as Dictionary).erase(GAME_ID)
	)
