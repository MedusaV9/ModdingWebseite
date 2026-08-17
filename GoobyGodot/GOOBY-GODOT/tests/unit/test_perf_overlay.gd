extends TestCase
## W4-P5 (INFRA) — Smoke für scripts/dev/perf_overlay.gd: unsichtbar per
## Default, 3-Finger-Tap toggelt (mit Cooldown), Setting-Sync, snapshot()
## liefert alle Metrik-Keys (headless = Dummy-Renderer = 0en, aber Vertrag).

const PerfOverlayScript := preload("res://scripts/dev/perf_overlay.gd")


func _touch(index: int, pressed: bool) -> InputEventScreenTouch:
	var ev := InputEventScreenTouch.new()
	ev.index = index
	ev.pressed = pressed
	ev.position = Vector2(100, 100)
	return ev


func _make_overlay() -> CanvasLayer:
	var overlay: CanvasLayer = PerfOverlayScript.new()
	tree.root.add_child(overlay)
	return overlay


func _cleanup(overlay: CanvasLayer) -> void:
	overlay.queue_free()
	await wait_frames(1)


func test_default_unsichtbar_und_snapshot_vertrag() -> void:
	var overlay := _make_overlay()
	await wait_frames(1)
	assert_false(overlay.is_shown(), "Overlay startet unsichtbar")
	var m: Dictionary = overlay.snapshot()
	for key in ["fps", "frame_ms", "draw_calls", "primitives", "nodes", "vram_mb"]:
		assert_true(m.has(key), "snapshot-Key %s" % key)
	assert_true(int(m["nodes"]) > 0, "Node-Zähler lebt auch headless")
	await _cleanup(overlay)


func test_drei_finger_tap_togglet_mit_cooldown() -> void:
	var overlay := _make_overlay()
	await wait_frames(1)
	# 2 Finger: nichts.
	overlay._input(_touch(0, true))
	overlay._input(_touch(1, true))
	assert_false(overlay.is_shown(), "2 Finger reichen nicht")
	# 3. Finger: an.
	overlay._input(_touch(2, true))
	assert_true(overlay.is_shown(), "3-Finger-Tap → sichtbar")
	# Finger lösen + sofort wieder 3 Finger: Cooldown verhindert Doppel-Toggle.
	for i in 3:
		overlay._input(_touch(i, false))
	for i in 3:
		overlay._input(_touch(i, true))
	assert_true(overlay.is_shown(), "Cooldown hält den Zustand")
	await _cleanup(overlay)


func test_set_shown_und_setting_sync() -> void:
	var overlay := _make_overlay()
	await wait_frames(1)
	var settings := tree.root.get_node_or_null("/root/AppSettings")
	overlay.set_shown(true)
	assert_true(overlay.is_shown())
	if settings != null:
		assert_true(
			settings.get_setting("dev.perf_overlay", false) == true,
			"Toggle persistiert ins Debug-Setting"
		)
	overlay.set_shown(false)
	assert_false(overlay.is_shown())
	if settings != null:
		assert_false(settings.get_setting("dev.perf_overlay", true) == true)
		# Setting-Weg: setting_changed steuert das Overlay.
		settings.set_setting("dev.perf_overlay", true)
		assert_true(overlay.is_shown(), "Setting → Overlay an")
		settings.set_setting("dev.perf_overlay", false)
		assert_false(overlay.is_shown(), "Setting → Overlay aus")
	await _cleanup(overlay)
