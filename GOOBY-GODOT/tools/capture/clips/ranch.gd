extends "res://tools/capture/clip_driver.gd"
## Clip: Gooby Ranch (Teaser) — Verfolgerkamera reitet außen neben dem
## Lauf-Pferd (Ellipse in der Pferdekoppel) mit und blickt nach innen:
## Koppel, Zäune, die anderen Pferde und die Hof-Gebäude ziehen als
## Kulisse vorbei. HUD ist aus, ab Sekunde 2 galoppiert das Pferd.

var hof: Node3D
var _cam_bereit := false
var _letzte_pos := Vector3.ZERO
var _lauf_dir := Vector3.FORWARD


func _setup() -> void:
	duration = 11.0
	var packed: PackedScene = load("res://scenes/ranch/ranch_hof.tscn")
	hof = packed.instantiate()
	hof.stunde_override = 10.0
	add_child(hof)
	schedule(0.2, func() -> void: _hud_aus())
	# Nur das Lauf-Pferd beschleunigen — die anderen grasen ruhig weiter.
	schedule(
		2.0,
		func() -> void:
			if hof.pferde.size() > 1:
				hof.pferde[1].set_gangart("galopp")
	)


func _hud_aus() -> void:
	for child in hof.get_children():
		if child is CanvasLayer:
			child.visible = false


## Kamera pro Frame ans Lauf-Pferd heften: außerhalb der Bahn (Richtung
## vom Koppel-Zentrum weg) UND ein Stück in Laufrichtung voraus — so
## galoppiert das Pferd in Dreiviertel-Frontansicht an der Kamera vorbei.
func _tick(delta: float) -> void:
	if hof == null or hof.pferde.size() < 2:
		return
	var pferd := hof.pferde[1] as Node3D
	var koppel: Rect2 = hof.plan["koppeln"][0]["rect"]
	var mitte := Vector3(koppel.get_center().x, 0.0, koppel.get_center().y)
	var aussen := pferd.global_position - mitte
	aussen.y = 0.0
	aussen = aussen.normalized()
	var schritt := pferd.global_position - _letzte_pos
	_letzte_pos = pferd.global_position
	schritt.y = 0.0
	if schritt.length() > 0.005:
		_lauf_dir = _lauf_dir.slerp(schritt.normalized(), 0.15)
	var wunsch := pferd.global_position + aussen * 7.0 + _lauf_dir * 5.5 + Vector3(0.0, 2.6, 0.0)
	var blick := pferd.global_position + _lauf_dir * 1.2 + Vector3(0.0, 1.3, 0.0)
	if not _cam_bereit:
		# Erst ab Frame 2 aufsetzen: das Trab-Pferd springt in Frame 1
		# von seinem Standplatz auf die Ellipsenbahn.
		if t < frames(2):
			return
		_cam_bereit = true
		cine_camera(wunsch, blick, 46.0)
		return
	_cine_cam.position = _cine_cam.position.lerp(wunsch, 1.0 - exp(-delta * 6.0))
	_cine_cam.look_at_from_position(_cine_cam.position, blick)
