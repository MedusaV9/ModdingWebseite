extends "res://tools/capture/clips/_mg_base.gd"
## Clip: Geisterjagd (3D, Nacht) — tippt sichtbare Geister an (das Spiel
## liefert den Bildschirmpunkt des ersten sichtbaren Geistes).

var _next_tap := 0.0


func _setup() -> void:
	game_id = "ghostHunt"
	duration = 10.0
	seed_value = 1313
	super._setup()


func _drive(_delta: float) -> void:
	var g := game()
	if g == null or g.finished or t < _next_tap:
		return
	if g.has_visible_ghost():
		tap(to_window(g.first_ghost_screen()))
		_next_tap = t + 0.5
