extends SceneTree
## PT-3-DIAGNOSE-WERKZEUG (Welle H, Befund B1 in docs/playtest/
## G8-PT3-minispiele.md): Minimal-Repro OHNE Spielcode für „ScrollContainer
## pannt nicht, wenn der Drag auf einem Button startet“. Baut einen nackten
## ScrollContainer voller Buttons und synthetisiert (a) reine ScreenTouch/
## ScreenDrag-Züge und (b) Maus-Drags (die emulate_touch_from_mouse in
## Touch-Events spiegelt) — je auf Knopf/Rand, mit/ohne scroll_deadzone,
## mit STOP- und PASS-mouse_filter. Läuft mit den ECHTEN Projekt-Settings.
## Aufruf: tools/ci/run_godot_isolated.sh xvfb-run -a godot --path GOOBY-GODOT \
##   --rendering-method gl_compatibility --audio-driver Dummy \
##   --resolution 800x600 --script res://tests/tools/playtest_flows/pt3_scroll_probe.gd

var _scroll: ScrollContainer


func _initialize() -> void:
	_lauf()


func _lauf() -> void:
	await process_frame
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(50, 50)
	_scroll.size = Vector2(400, 500)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(box)
	for i in 40:
		var knopf := Button.new()
		knopf.text = "Knopf %d" % i
		knopf.custom_minimum_size = Vector2(300, 60)
		box.add_child(knopf)
	root.add_child(_scroll)
	await process_frame
	await process_frame
	print(
		(
			"[probe] max=%.0f page=%.0f"
			% [_scroll.get_v_scroll_bar().max_value, _scroll.get_v_scroll_bar().page]
		)
	)

	await _drag(Vector2(200, 400), Vector2(200, 150))
	print(
		(
			"[probe] Knopf-Drag, deadzone=%d -> scroll_vertical=%d"
			% [_scroll.scroll_deadzone, _scroll.scroll_vertical]
		)
	)

	_scroll.scroll_deadzone = 24
	await _drag(Vector2(200, 400), Vector2(200, 150))
	print("[probe] Knopf-Drag, deadzone=24 -> scroll_vertical=%d" % _scroll.scroll_vertical)

	# Rand: x=430 liegt IM Scroller, aber rechts NEBEN den 300px-Knöpfen.
	await _drag(Vector2(430, 400), Vector2(430, 150))
	print("[probe] Rand-Drag, deadzone=24 -> scroll_vertical=%d" % _scroll.scroll_vertical)

	_scroll.scroll_deadzone = 0
	await _drag(Vector2(430, 400), Vector2(430, 150))
	print("[probe] Rand-Drag, deadzone=0 -> scroll_vertical=%d" % _scroll.scroll_vertical)

	# DER Kandidaten-Fix: Buttons auf MOUSE_FILTER_PASS — der Touch-Press
	# erreicht den ScrollContainer (armt das Panning), der Knopf drückt
	# trotzdem (und NOTIFICATION_SCROLL_BEGIN bricht den Press beim Rollen ab).
	for knopf: Button in _scroll.get_child(0).get_children():
		knopf.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.scroll_deadzone = 24
	await _drag(Vector2(200, 400), Vector2(200, 150))
	print("[probe] Knopf-Drag, PASS + deadzone=24 -> scroll_vertical=%d" % _scroll.scroll_vertical)

	# Gegenprobe: drückt ein PASS-Knopf noch normal? (Tap ohne Bewegung.)
	var gedrueckt := {"n": 0}
	for knopf: Button in _scroll.get_child(0).get_children():
		knopf.pressed.connect(func() -> void: gedrueckt["n"] += 1)
	await _tipp(Vector2(200, 100))
	print("[probe] Tap auf PASS-Knopf -> pressed-Signale: %d" % gedrueckt["n"])

	# ── MAUS-Pfad (wie die Harness UND wie emulate_touch_from_mouse ihn
	# in echte Touch-Events übersetzt — der in-Game nachweislich pannt) ──
	for knopf: Button in _scroll.get_child(0).get_children():
		knopf.mouse_filter = Control.MOUSE_FILTER_STOP
	_scroll.scroll_vertical = 0
	await _maus_drag(Vector2(200, 400), Vector2(200, 150))
	print("[probe] MAUS-Drag auf STOP-Knopf -> scroll_vertical=%d" % _scroll.scroll_vertical)

	for knopf: Button in _scroll.get_child(0).get_children():
		knopf.mouse_filter = Control.MOUSE_FILTER_PASS
	_scroll.scroll_vertical = 0
	await _maus_drag(Vector2(200, 400), Vector2(200, 150))
	print("[probe] MAUS-Drag auf PASS-Knopf -> scroll_vertical=%d" % _scroll.scroll_vertical)

	gedrueckt["n"] = 0
	await _maus_tipp(Vector2(200, 100))
	print("[probe] MAUS-Tap auf PASS-Knopf -> pressed-Signale: %d" % gedrueckt["n"])
	quit(0)


func _maus_drag(von: Vector2, nach: Vector2) -> void:
	var runter := InputEventMouseButton.new()
	runter.button_index = MOUSE_BUTTON_LEFT
	runter.pressed = true
	runter.position = von
	runter.global_position = von
	runter.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(runter)
	var pos := von
	var schritt := (nach - von) / 12.0
	for i in 12:
		await process_frame
		pos += schritt
		var zug := InputEventMouseMotion.new()
		zug.position = pos
		zug.global_position = pos
		zug.relative = schritt
		zug.button_mask = MOUSE_BUTTON_MASK_LEFT
		Input.parse_input_event(zug)
	var hoch := InputEventMouseButton.new()
	hoch.button_index = MOUSE_BUTTON_LEFT
	hoch.pressed = false
	hoch.position = pos
	hoch.global_position = pos
	Input.parse_input_event(hoch)
	await process_frame
	await process_frame


func _maus_tipp(pos: Vector2) -> void:
	var runter := InputEventMouseButton.new()
	runter.button_index = MOUSE_BUTTON_LEFT
	runter.pressed = true
	runter.position = pos
	runter.global_position = pos
	runter.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(runter)
	await process_frame
	await process_frame
	var hoch := InputEventMouseButton.new()
	hoch.button_index = MOUSE_BUTTON_LEFT
	hoch.pressed = false
	hoch.position = pos
	hoch.global_position = pos
	Input.parse_input_event(hoch)
	await process_frame
	await process_frame


func _tipp(pos: Vector2) -> void:
	var runter := InputEventScreenTouch.new()
	runter.index = 0
	runter.pressed = true
	runter.position = pos
	Input.parse_input_event(runter)
	await process_frame
	await process_frame
	var hoch := InputEventScreenTouch.new()
	hoch.index = 0
	hoch.pressed = false
	hoch.position = pos
	Input.parse_input_event(hoch)
	await process_frame
	await process_frame


func _drag(von: Vector2, nach: Vector2) -> void:
	var runter := InputEventScreenTouch.new()
	runter.index = 0
	runter.pressed = true
	runter.position = von
	Input.parse_input_event(runter)
	var pos := von
	var schritt := (nach - von) / 12.0
	for i in 12:
		await process_frame
		pos += schritt
		var zug := InputEventScreenDrag.new()
		zug.index = 0
		zug.position = pos
		zug.relative = schritt
		Input.parse_input_event(zug)
	var hoch := InputEventScreenTouch.new()
	hoch.index = 0
	hoch.pressed = false
	hoch.position = pos
	Input.parse_input_event(hoch)
	await process_frame
	await process_frame
