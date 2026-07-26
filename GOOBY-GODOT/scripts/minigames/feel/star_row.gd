class_name FeelStarRow
extends Control
## Sterne-Reihe für den Results-Screen (POLISH-A): zeichnet bis zu drei
## Sterne als Vektor-Polygone (kein Font-Glyph nötig) und lässt sie unter
## Motion nacheinander einploppen — jeder Stern klingt mit steigender
## Tonhöhe (game_star). Unter Reduced Motion stehen sie sofort still da.

## Wie viele Sterne insgesamt gezeichnet werden (leer = grauer Umriss).
const SLOTS := 3
const STAR_RADIUS := 26.0
const GAP := 24.0
const FILL := Color(1.0, 0.8, 0.2)
const RIM := Color(0.85, 0.55, 0.1)
const EMPTY := Color(0.55, 0.48, 0.42, 0.35)

var _earned := 0
var _pop: Array[float] = []
var _animating := false


func _ready() -> void:
	custom_minimum_size = Vector2(SLOTS * (STAR_RADIUS * 2.0 + GAP), STAR_RADIUS * 2.4)


## Startet die Einblendung: earned Sterne (0..3) ploppen gestaffelt ein.
func reveal(earned: int, reduced_motion: bool) -> void:
	_earned = clampi(earned, 0, SLOTS)
	_pop = []
	for i in SLOTS:
		_pop.append(1.0 if reduced_motion else 0.0)
	queue_redraw()
	if reduced_motion:
		if _earned > 0:
			FeelSfx.play(self, "game_star")
		return
	_animating = true
	for i in _earned:
		var tween := create_tween()
		tween.tween_interval(0.28 * i + 0.1)
		tween.tween_callback(_ping.bind(i))
		tween.tween_method(_set_pop.bind(i), 0.0, 1.0, 0.34).set_trans(Tween.TRANS_BACK).set_ease(
			Tween.EASE_OUT
		)


func _ping(index: int) -> void:
	FeelSfx.play(self, "game_star", 1.0 + 0.14 * index)


func _set_pop(value: float, index: int) -> void:
	if index < _pop.size():
		_pop[index] = value
		queue_redraw()


func _draw() -> void:
	var total_w := SLOTS * STAR_RADIUS * 2.0 + (SLOTS - 1) * GAP
	var start_x := (size.x - total_w) * 0.5 + STAR_RADIUS
	var cy := size.y * 0.55
	for i in SLOTS:
		var center := Vector2(start_x + i * (STAR_RADIUS * 2.0 + GAP), cy)
		if i < _earned:
			var scale_f: float = _pop[i] if i < _pop.size() else 1.0
			if scale_f <= 0.01:
				continue
			_draw_star(center, STAR_RADIUS * scale_f, FILL, RIM)
		else:
			_draw_star(center, STAR_RADIUS * 0.82, Color(0, 0, 0, 0), EMPTY)


func _draw_star(center: Vector2, radius: float, fill: Color, rim: Color) -> void:
	var points := PackedVector2Array()
	for i in 10:
		var angle := -PI * 0.5 + TAU * i / 10.0
		var dist := radius if i % 2 == 0 else radius * 0.45
		points.append(center + Vector2(cos(angle), sin(angle)) * dist)
	if fill.a > 0.0:
		draw_colored_polygon(points, fill)
	draw_polyline(points + PackedVector2Array([points[0]]), rim, 3.0)
