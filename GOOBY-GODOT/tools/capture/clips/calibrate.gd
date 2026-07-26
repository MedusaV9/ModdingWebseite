extends "res://tools/capture/clip_driver.gd"
## Kalibrier-Clip: klärt EMPIRISCH, wie Input.parse_input_event-Positionen
## unter stretch=canvas_items (Basis 1280x720) interpretiert werden.
## Zwei Buttons an bekannten Canvas-Positionen; Tap 1 = rohe Canvas-Koordinate,
## Tap 2 = Canvas * (Fenster/Canvas). Das Log zeigt, welcher ankommt.

var knopf_a: Button
var knopf_b: Button


func _setup() -> void:
	duration = 3.0
	knopf_a = _mach_knopf("A", Vector2(900.0, 500.0))
	knopf_b = _mach_knopf("B", Vector2(300.0, 200.0))
	schedule(0.5, func() -> void:
		var vp := get_viewport()
		var canvas := vp.get_visible_rect().size
		var fenster := Vector2(vp.size)
		print("[cal] Fenster=%s Canvas=%s" % [fenster, canvas])
		# Tap 1: rohe Canvas-Koordinate von A.
		tap(knopf_a.get_global_rect().get_center()))
	schedule(1.5, func() -> void:
		# Tap 2: B-Canvas-Koordinate skaliert auf Fensterpixel.
		var vp := get_viewport()
		var skala := Vector2(vp.size) / vp.get_visible_rect().size
		tap(knopf_b.get_global_rect().get_center() * skala))


func _mach_knopf(name_kurz: String, pos: Vector2) -> Button:
	var b := Button.new()
	b.text = name_kurz
	b.position = pos - Vector2(60.0, 30.0)
	b.size = Vector2(120.0, 60.0)
	b.pressed.connect(func() -> void: print("[cal] TREFFER auf %s" % name_kurz))
	add_child(b)
	return b
