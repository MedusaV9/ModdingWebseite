extends "res://tools/capture/clips/_mg_base.gd"
## Clip: Toy Racer (3D-Kart) — der eingebaute Autoplay-Bot fährt das Rennen
## (Web-Parität ?autoplay=1), wir drücken nur ab und zu den Item-Knopf.


func _setup() -> void:
	game_id = "toyRacer"
	duration = 9.0
	seed_value = 777
	super._setup()


func _on_play_start() -> void:
	var g := game()
	g.autoplay = true
	# Items zünden für Action (ENTER = Item, Web-Tastenlayout).
	schedule(t + 2.0, func() -> void: key_tap(KEY_ENTER))
	schedule(t + 4.5, func() -> void: key_tap(KEY_ENTER))
	schedule(t + 6.5, func() -> void: key_tap(KEY_ENTER))
