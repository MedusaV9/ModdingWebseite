extends "res://tools/capture/clips/_mg_base.gd"
## Clip: Minigolf (3D) — liest Ball-/Loch-Lage aus dem Spiel und zieht den
## Slingshot-Drag automatisch (Zug ENTGEGEN der Zielrichtung).

var _next_putt := 0.0


func _setup() -> void:
	game_id = "miniGolf"
	duration = 10.0
	seed_value = 4242
	super._setup()


func _drive(_delta: float) -> void:
	var g := game()
	if g == null or g.finished:
		return
	if str(g.phase) != "aim" or t < _next_putt:
		return
	_next_putt = t + 2.6
	# Ziel: Richtung Ball → Loch (Welt XZ), Zug in Gegenrichtung auf dem
	# Schirm. Screen-Mapping über die 3D-Bühne des Spiels.
	var hole: Dictionary = g.current_hole()
	var ball: Dictionary = g.ball
	var von := Vector2(float(ball["x"]), float(ball["z"]))
	var ziel_d: Dictionary = hole.get("hole", {})
	var nach := Vector2(float(ziel_d.get("x", 0.0)), float(ziel_d.get("z", 3.0)))
	# Ecken-Löcher: erst zum nächsten Waypoint spielen.
	for wp: Dictionary in hole.get("waypoints", []):
		var wpv := Vector2(float(wp["x"]), float(wp["z"]))
		if von.distance_to(wpv) > 0.45 and von.distance_to(nach) > wpv.distance_to(nach):
			nach = wpv
			break
	var dist := von.distance_to(nach)
	var stage: Node = g._stage
	var ball_px: Vector2 = stage.to_screen(Vector3(von.x, 0.05, von.y))
	var cup_px: Vector2 = stage.to_screen(Vector3(nach.x, 0.05, nach.y))
	var dir_px := (cup_px - ball_px).normalized()
	var pull_len := clampf(dist * 55.0, 90.0, 300.0)
	var start := to_window(ball_px)
	var ziel := to_window(ball_px - dir_px * pull_len)
	drag(start, ziel, 0.55)
