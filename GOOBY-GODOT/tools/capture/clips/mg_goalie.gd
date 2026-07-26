extends "res://tools/capture/clips/_mg_base.gd"
## Clip: Torwart-Gooby (3D) — liest den Schuss (Bahn + Art) aus dem Spiel
## und hechtet mit einem passenden Wisch zur richtigen Seite.

## Winkel-Mitten der fünf Bahnen (INNER 18° / OUTER 54° — siehe GoalieLogic).
const LANE_DEG := [-65.0, -35.0, 0.0, 35.0, 65.0]

var _dived_for := -1.0


func _setup() -> void:
	game_id = "goalieGooby"
	duration = 10.0
	seed_value = 31337
	super._setup()


func _drive(_delta: float) -> void:
	var g := game()
	if g == null or g.finished or g.kick.is_empty():
		return
	if g.kick_start == _dived_for:
		return
	var arrive: float = g.kick_start + float(g.kick["telegraph"]) + float(g.kick["flight"])
	if g.elapsed < arrive - 0.22:
		return
	_dived_for = g.kick_start
	var lane := int(g.kick["lane"])
	var kind := str(g.kick["kind"])
	var dy := 22.0
	if kind == "lob":
		dy = -130.0
	elif kind == "roller":
		dy = 130.0
	var dx := tan(deg_to_rad(LANE_DEG[lane])) * absf(dy)
	var start := stage_pos(0.5, 0.72)
	drag(start, start + Vector2(dx, dy), 0.12)
