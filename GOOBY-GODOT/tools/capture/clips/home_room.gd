extends "res://tools/capture/clip_driver.gd"
## Clip: Zuhause (Wohnzimmer) — Gooby läuft durch den eingerichteten Raum,
## winkt in die Kamera; die Spiel-Kamera (HomeCameraRig) folgt wie im Spiel.

var room: Node3D


func _setup() -> void:
	duration = 8.0
	var packed: PackedScene = load("res://scenes/home/wohnzimmer.tscn")
	room = packed.instantiate()
	room.stunde_override = 15.0
	add_child(room)
	_kamera_flacher()
	schedule(0.8, _spaziergang)
	schedule(4.2, _winken)


## Seit dem HAUS-Update haben Innenräume Deckenbalken (DachInnen) — die
## Standard-Schrägsicht legt sie quer durch die Bildmitte. Flacherer Blick
## fürs Trailer-Framing: Balken bleiben als Feature am oberen Bildrand
## sichtbar, Gooby und Möbel bleiben frei.
func _kamera_flacher() -> void:
	var rig: Node3D = room.camera_rig()
	if rig == null:
		return
	var dist: float = rig._offset.length()
	rig._offset = Vector3(0.0, 2.9, 5.6).normalized() * dist


func _spaziergang() -> void:
	var gooby: Node3D = room._gooby
	if gooby == null:
		return
	gooby.set_wander_enabled(false)
	# _start_walking statt walk_to: dessen Timeout ist Wanduhr-basiert und
	# bricht den Lauf im Movie-Maker (1–6 fps Wandzeit) nach Frames ab.
	gooby.call("_start_walking", Vector3(1.2, 0.0, 1.6))


func _winken() -> void:
	var gooby: Node3D = room._gooby
	if gooby == null:
		return
	gooby.cancel_walk()
	if gooby.rig != null:
		gooby.rig.play_clip("wave")
		gooby.rig.set_emotion("happy")
	schedule(
		t + 1.6,
		func() -> void:
			if gooby.rig != null:
				gooby.rig.play_clip("hop")
				gooby.rig.set_emotion("ecstatic")
	)
