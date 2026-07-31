class_name LoadingVeilPunkte
extends Control
## W14/LOADING — Fortschritts-Punkte des LoadingVeils: drei weiche Punkte,
## die nacheinander hüpfen (das „Lädt…“-Gefühl statt eines Spinners; der
## Alt-Spinner Root/Spinner bleibt unsichtbar im Baum, W1a-Contract).
## Sobald der ECHTE threaded-Fortschrittsbalken sichtbar wird, blendet das
## Veil die Punkte aus — nie zwei Ladeanzeigen gleichzeitig.
##
## `set_animated(false)` = Reduced Motion: Punkte stehen still (Ruhelage).

const PUNKT_FARBEN: Array[Color] = [
	Color("#FF7BA9"),
	Color("#FFD166"),
	Color("#59C9B9"),
]
const OUTLINE := Color("#4A3B36")
const HOP_HZ := 1.1
const PHASEN_VERSATZ := 0.22

var _t := 0.0
var _animated := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(78.0, 26.0)
	set_process(_animated)


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func set_animated(animated: bool) -> void:
	_animated = animated
	set_process(animated)
	if not animated:
		_t = 0.0
	queue_redraw()


func is_animated() -> bool:
	return _animated


func _draw() -> void:
	var anzahl := PUNKT_FARBEN.size()
	var r := minf(size.y * 0.28, size.x / float(anzahl * 3))
	var abstand := r * 3.0
	var mitte := Vector2(size.x / 2.0, size.y * 0.62)
	var start_x := mitte.x - abstand * float(anzahl - 1) / 2.0
	for i in anzahl:
		var hop := 0.0
		if _animated:
			var phase := _t * HOP_HZ * TAU - float(i) * PHASEN_VERSATZ * TAU
			hop = maxf(0.0, sin(phase)) * size.y * 0.30
		var pos := Vector2(start_x + abstand * float(i), mitte.y - hop)
		draw_circle(pos, r + maxf(1.5, r * 0.28), OUTLINE)
		draw_circle(pos, r, PUNKT_FARBEN[i])
