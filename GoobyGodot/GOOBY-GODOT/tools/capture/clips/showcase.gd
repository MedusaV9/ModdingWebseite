extends "res://tools/capture/clip_driver.gd"
## Clip: der neue 3D-Gooby (Rig-Showcase) — Winken, Hüpfer, Jubel, Lauf.
## Eigene Kino-Kamera fährt langsam heran.

const SCENE := "res://scripts/character/gooby_showcase.tscn"


func _setup() -> void:
	duration = 7.0
	var packed: PackedScene = load(SCENE)
	var showcase: Node3D = packed.instantiate()
	var prog: Array[Dictionary] = [
		{"clip": "wave", "emotion": "happy", "text": "Hallo hallo!"},
		{"clip": "hop", "emotion": "ecstatic"},
		{"clip": "walk", "emotion": "happy"},
		{"clip": "celebrate", "emotion": "ecstatic", "text": "Juhu!"},
		{"clip": "idle", "emotion": "happy"},
	]
	showcase._program = prog
	add_child(showcase)
	# Langsame Heranfahrt — überstimmt die statische Showcase-Kamera.
	cine_camera(Vector3(0.9, 0.95, 2.7), Vector3(0.0, 0.55, 0.0), 45.0)
	move_camera(Vector3(-0.4, 0.72, 2.0), Vector3(0.0, 0.52, 0.0), duration)
