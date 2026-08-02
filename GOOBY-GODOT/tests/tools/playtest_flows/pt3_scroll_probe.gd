extends SceneTree
## PT-3-DIAGNOSE + FIX-7-REGRESSIONS-GATE (Welle H, Befund B1 HOCH in
## docs/playtest/G8-PT3-minispiele.md): Minimal-Repro OHNE Spielcode für
## „ScrollContainer pannt nicht, wenn der Drag auf einem Button startet“.
## Baut einen nackten ScrollContainer voller Buttons (echte Projekt-Settings)
## und läuft in zwei Phasen:
##   A) OHNE Helfer (Engine-Stand, reine Doku): Touch- und Maus-Drag auf
##      einem Knopf pannen NIE — der Knopf konsumiert den Press, das native
##      Panning armt nicht (so wurde B1 diagnostiziert; vorher „rot“).
##   B) MIT DragScroll.anbinden() (der B1-Fix) — HARTE Erwartungen:
##      Touch-Drag auf Knopf pannt, Maus-Drag auf Knopf pannt, WÄHREND des
##      Pannens feuert kein pressed, und Taps (Touch + Maus, ohne Bewegung)
##      drücken weiterhin exakt 1×.
## Exit 0 = alle Erwartungen erfüllt, Exit 1 = mindestens eine verletzt.
## Aufruf: tools/ci/run_godot_isolated.sh xvfb-run -a godot --path GOOBY-GODOT \
##   --rendering-method gl_compatibility --audio-driver Dummy \
##   --resolution 800x600 --script res://tests/tools/playtest_flows/pt3_scroll_probe.gd

const DRAG_HOEHE := 250.0
const DRAG_SCHRITTE := 12

var _scroll: ScrollContainer
var _gedrueckt := {"n": 0}
var _fehler: Array[String] = []


func _initialize() -> void:
	_lauf()


func _lauf() -> void:
	await process_frame
	_scroll = ScrollContainer.new()
	_scroll.position = Vector2(50, 50)
	_scroll.size = Vector2(400, 500)
	# Arcade-Parität: dieselbe Deadzone wie das Grid (Taps wackeln straflos).
	_scroll.scroll_deadzone = 24
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(box)
	for i in 40:
		var knopf := Button.new()
		knopf.text = "Knopf %d" % i
		knopf.custom_minimum_size = Vector2(300, 60)
		knopf.pressed.connect(func() -> void: _gedrueckt["n"] += 1)
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

	# ── Phase A: OHNE Helfer (Engine-Stand — dokumentiert den B1-Befund) ──
	await _drag(_knopf_punkt())
	print(
		"[probe] OHNE Helfer: Touch-Drag auf Knopf -> scroll_vertical=%d" % _scroll.scroll_vertical
	)
	_scroll.scroll_vertical = 0
	await _maus_drag(_knopf_punkt())
	print(
		"[probe] OHNE Helfer: Maus-Drag auf Knopf -> scroll_vertical=%d" % _scroll.scroll_vertical
	)
	_scroll.scroll_vertical = 0
	await process_frame

	# ── Phase B: MIT DragScroll (der B1-Fix) — harte Erwartungen ──
	DragScroll.anbinden(_scroll)
	await process_frame

	_gedrueckt["n"] = 0
	await _drag(_knopf_punkt())
	_pruefe(
		_scroll.scroll_vertical > 100,
		"Touch-Drag auf Knopf pannt (scroll_vertical=%d)" % _scroll.scroll_vertical
	)
	_pruefe(_gedrueckt["n"] == 0, "Touch-Drag feuert KEIN pressed (n=%d)" % int(_gedrueckt["n"]))

	_scroll.scroll_vertical = 0
	await process_frame
	_gedrueckt["n"] = 0
	await _maus_drag(_knopf_punkt())
	_pruefe(
		_scroll.scroll_vertical > 100,
		"Maus-Drag auf Knopf pannt (scroll_vertical=%d)" % _scroll.scroll_vertical
	)
	_pruefe(_gedrueckt["n"] == 0, "Maus-Drag feuert KEIN pressed (n=%d)" % int(_gedrueckt["n"]))

	_scroll.scroll_vertical = 0
	await process_frame
	_gedrueckt["n"] = 0
	var stand_vor_tap := _scroll.scroll_vertical
	await _tipp(_knopf_punkt())
	_pruefe(_gedrueckt["n"] == 1, "Touch-Tap drückt exakt 1× (n=%d)" % int(_gedrueckt["n"]))
	_pruefe(
		_scroll.scroll_vertical == stand_vor_tap,
		"Touch-Tap scrollt nicht (scroll_vertical=%d)" % _scroll.scroll_vertical
	)

	_gedrueckt["n"] = 0
	await _maus_tipp(_knopf_punkt())
	_pruefe(_gedrueckt["n"] == 1, "Maus-Tap drückt exakt 1× (n=%d)" % int(_gedrueckt["n"]))

	if _fehler.is_empty():
		print("[probe] ERGEBNIS: PASS (alle Erwartungen erfüllt)")
		quit(0)
		return
	for zeile in _fehler:
		print("[probe] FEHLGESCHLAGEN: %s" % zeile)
	print("[probe] ERGEBNIS: FAIL (%d Erwartungen verletzt)" % _fehler.size())
	quit(1)


func _pruefe(ok: bool, was: String) -> void:
	print("[probe] %s — %s" % ["ok" if ok else "FAIL", was])
	if not ok:
		_fehler.append(was)


## Fenster-px der Mitte eines Knopfs, dessen Mitte GERADE SICHTBAR im
## Scroller liegt (Canvas → Fenster wie die Playtest-Harness).
func _knopf_punkt() -> Vector2:
	var fenster := _scroll.get_global_rect()
	for kind in _scroll.get_child(0).get_children():
		if not (kind is Button):
			continue
		var mitte := (kind as Control).get_global_rect().get_center()
		if fenster.has_point(mitte):
			return _px(mitte)
	return _px(fenster.get_center())


func _px(canvas: Vector2) -> Vector2:
	return canvas * (Vector2(root.size) / root.get_visible_rect().size)


func _drag(von: Vector2) -> void:
	var schritt := Vector2(0.0, -_px(Vector2(0.0, DRAG_HOEHE)).y / float(DRAG_SCHRITTE))
	var runter := InputEventScreenTouch.new()
	runter.index = 0
	runter.pressed = true
	runter.position = von
	Input.parse_input_event(runter)
	var pos := von
	for i in DRAG_SCHRITTE:
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


func _maus_drag(von: Vector2) -> void:
	var runter := InputEventMouseButton.new()
	runter.button_index = MOUSE_BUTTON_LEFT
	runter.pressed = true
	runter.position = von
	runter.global_position = von
	runter.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(runter)
	var schritt := Vector2(0.0, -_px(Vector2(0.0, DRAG_HOEHE)).y / float(DRAG_SCHRITTE))
	var pos := von
	for i in DRAG_SCHRITTE:
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


func _maus_tipp(pos: Vector2) -> void:
	var beweg := InputEventMouseMotion.new()
	beweg.position = pos
	beweg.global_position = pos
	Input.parse_input_event(beweg)
	await process_frame
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
