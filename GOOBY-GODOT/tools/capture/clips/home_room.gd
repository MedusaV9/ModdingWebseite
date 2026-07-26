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
	schedule(0.8, _spaziergang)
	schedule(4.2, _winken)


func _spaziergang() -> void:
	var gooby: Node3D = room._gooby
	if gooby == null:
		return
	gooby.set_wander_enabled(false)
	gooby.walk_to(Vector3(1.2, 0.0, 1.6))


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
