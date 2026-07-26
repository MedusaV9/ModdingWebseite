extends "res://tools/capture/clips/_mg_base.gd"
## Clip: Angelteich (3D) — Senken (halten), Anhieb (loslassen), Einkurbeln
## (schnell tippen). Reagiert auf die Spiel-Phase.

var _hold_until := -1.0
var _next_tap := 0.0


func _setup() -> void:
	game_id = "fishingPond"
	duration = 11.0
	seed_value = 555
	super._setup()


func _drive(_delta: float) -> void:
	var g := game()
	if g == null or g.finished:
		return
	var phase := str(g.phase)
	var mitte := stage_pos(0.5, 0.6)
	match phase:
		"idle":
			if _hold_until < 0.0:
				hold("rute", mitte)
				_hold_until = t + 1.05
		"lower":
			if _hold_until > 0.0 and t >= _hold_until:
				release_hold("rute")
				_hold_until = -1.0
		"reel":
			if t >= _next_tap:
				tap(mitte)
				_next_tap = t + 0.16
		_:
			if _hold_until > 0.0:
				release_hold("rute")
				_hold_until = -1.0
