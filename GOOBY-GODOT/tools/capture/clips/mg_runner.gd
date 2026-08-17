extends "res://tools/capture/clips/_mg_base.gd"
## Clip: Renner (3D-Endless-Runner) — eingebauter Autoplay-Bot weicht aus
## und springt (Web-Parität ?autoplay=1).


func _setup() -> void:
	game_id = "runner"
	duration = 9.0
	seed_value = 99
	super._setup()


func _on_play_start() -> void:
	game().autoplay = true
