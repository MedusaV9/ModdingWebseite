@tool
class_name GobnomEditorCanvas
extends Control
## W15/TECHKIT (Doc G §5) — Zeichen-/Maus-Schicht des GOB-NOM-Level-Editors.
## Zeigt EIN Level (level ist eine REFERENZ ins Dokument — Mutationen landen
## direkt im doc der Haupt-Szene) in der 960×540-Welt, letterboxed in die
## Control-Fläche. Ziehen mit Snap-Raster läuft über GobnomEditorLogic;
## nach jedem abgeschlossenen Zug feuert level_edited (Properties-Refresh).
## Zusätzlich: Platzier-Modus (placement_kind setzen → nächster Klick legt
## ein Element an) und die grün/rote Candy-Flugbahn des Solver-Laufs.

signal selection_changed(kind: String, index: int)
signal level_edited

const WORLD_FALLBACK := Vector2(960.0, 540.0)
const HANDLE_RADIUS := 7.0
## Element-Farben (kind → Color) fürs Zeichnen.
const KIND_COLORS := {
	"candy": Color(1.0, 0.62, 0.18),
	"mouth": Color(0.91, 0.36, 0.62),
	"ropes": Color(0.82, 0.72, 0.55),
	"bubbles": Color(0.45, 0.75, 1.0),
	"cushions": Color(0.55, 0.85, 0.55),
	"fans": Color(0.65, 0.65, 0.95),
	"shooters": Color(0.95, 0.75, 0.35),
	"spikes": Color(0.95, 0.35, 0.30),
	"clouds": Color(0.75, 0.75, 0.78),
	"jars": Color(0.62, 0.42, 0.25),
}

## Aktuelles Level (Referenz!) + Welt-Größe aus der Balance.
var level: Dictionary = {}
var world := WORLD_FALLBACK
var grid := GobnomEditorLogic.DEFAULT_GRID
## Platzier-Modus: Element-Kind, das der nächste Klick anlegt ("" = aus).
var placement_kind := ""
## Auswahl (kind "", index -2 = nichts; index -1 = candy/mouth).
var selected_kind := ""
var selected_index := -2
## Solver-Flugbahn (Welt-px) + Ampel der letzten Validierung.
var solver_points: Array[Vector2] = []
var solver_ok := false
var solver_shown := false

var _dragging := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(480, 270)
	resized.connect(queue_redraw)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == 1:
		var button := event as InputEventMouseButton
		if button.pressed:
			_press(_to_world(button.position))
		else:
			_release()
		accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_drag(_to_world((event as InputEventMouseMotion).position))
		accept_event()


## Auswahl von außen setzen (Properties-Panel ↔ Canvas synchron halten).
func select_handle(kind: String, index: int) -> void:
	selected_kind = kind
	selected_index = index
	queue_redraw()


## Solver-Flugbahn anzeigen (Validierungs-Knopf) bzw. löschen.
func show_solver(points: Array[Vector2], ok: bool) -> void:
	solver_points = points
	solver_ok = ok
	solver_shown = true
	queue_redraw()


func clear_solver() -> void:
	solver_points = []
	solver_shown = false
	queue_redraw()


## ------------------------------------------------------------------- Maus


func _press(pos: Vector2) -> void:
	clear_solver()
	if not placement_kind.is_empty():
		var index := GobnomEditorLogic.add_element(level, placement_kind, pos, grid)
		var kind := placement_kind
		placement_kind = ""
		if index >= 0:
			selected_kind = kind
			selected_index = index
			selection_changed.emit(kind, index)
			level_edited.emit()
		queue_redraw()
		return
	var handle := GobnomEditorLogic.pick_handle(level, pos, _pick_dist())
	if handle.is_empty():
		selected_kind = ""
		selected_index = -2
		selection_changed.emit("", -2)
	else:
		selected_kind = str(handle["kind"])
		selected_index = int(handle["index"])
		_dragging = true
		selection_changed.emit(selected_kind, selected_index)
	queue_redraw()


func _drag(pos: Vector2) -> void:
	if selected_kind.is_empty():
		return
	GobnomEditorLogic.move_element(level, selected_kind, selected_index, pos, grid)
	queue_redraw()


func _release() -> void:
	if _dragging:
		_dragging = false
		level_edited.emit()


## Griff-Fangradius in Welt-px (bei kleiner Skalierung großzügiger).
func _pick_dist() -> float:
	return 24.0 / maxf(_scale(), 0.001) * maxf(_scale(), 0.001) + 14.0


## -------------------------------------------------------------- Transform


func _scale() -> float:
	if world.x <= 0.0 or world.y <= 0.0:
		return 1.0
	return minf(size.x / world.x, size.y / world.y)


func _offset() -> Vector2:
	return (size - world * _scale()) * 0.5


func _to_world(screen: Vector2) -> Vector2:
	return (screen - _offset()) / maxf(_scale(), 0.001)


func _to_screen(pos: Vector2) -> Vector2:
	return pos * _scale() + _offset()


## ---------------------------------------------------------------- Zeichnen


func _draw() -> void:
	var s := _scale()
	var off := _offset()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.10, 0.09, 0.12))
	draw_rect(Rect2(off, world * s), Color(0.16, 0.14, 0.19))
	_draw_grid(s, off)
	if level.is_empty():
		return
	_draw_rows("clouds", _draw_cloud)
	_draw_rows("spikes", _draw_spike)
	_draw_rows("jars", _draw_jar)
	_draw_rows("shooters", _draw_shooter)
	_draw_rows("fans", _draw_fan)
	_draw_rows("cushions", _draw_cushion)
	_draw_rows("bubbles", _draw_bubble)
	_draw_ropes()
	_draw_point("candy")
	_draw_point("mouth")
	_draw_solver()
	_draw_selection()


func _draw_grid(s: float, off: Vector2) -> void:
	if grid <= 0.0:
		return
	var color := Color(1, 1, 1, 0.05)
	var x := 0.0
	while x <= world.x:
		draw_line(off + Vector2(x * s, 0), off + Vector2(x * s, world.y * s), color)
		x += grid
	var y := 0.0
	while y <= world.y:
		draw_line(off + Vector2(0, y * s), off + Vector2(world.x * s, y * s), color)
		y += grid


func _draw_rows(kind: String, painter: Callable) -> void:
	var rows: Variant = level.get(kind, [])
	if not (rows is Array):
		return
	for row: Variant in rows:
		if row is Dictionary:
			painter.call(row as Dictionary, KIND_COLORS[kind] as Color)


func _draw_cloud(row: Dictionary, color: Color) -> void:
	_draw_box(row, color, Color(color, 0.25))


func _draw_spike(row: Dictionary, color: Color) -> void:
	_draw_box(row, color, Color(color, 0.45))


func _draw_box(row: Dictionary, line: Color, fill: Color) -> void:
	var s := _scale()
	var half := Vector2(_num(row.get("w"), 60.0), _num(row.get("h"), 20.0)) * 0.5 * s
	var center := _to_screen(_pos(row))
	draw_rect(Rect2(center - half, half * 2.0), fill)
	draw_rect(Rect2(center - half, half * 2.0), line, false, 1.5)


func _draw_jar(row: Dictionary, color: Color) -> void:
	draw_circle(_to_screen(_pos(row)), 10.0 * _scale(), Color(color, 0.85))


func _draw_shooter(row: Dictionary, color: Color) -> void:
	var center := _to_screen(_pos(row))
	draw_arc(center, _num(row.get("r"), 90.0) * _scale(), 0.0, TAU, 40, Color(color, 0.35), 1.0)
	draw_circle(center, 5.0 * _scale(), color)


func _draw_fan(row: Dictionary, color: Color) -> void:
	var on := bool(row.get("on", true))
	_draw_beam(row, Color(color, 0.9 if on else 0.35), _num(row.get("range"), 260.0))


func _draw_cushion(row: Dictionary, color: Color) -> void:
	_draw_beam(row, color, 40.0)


func _draw_beam(row: Dictionary, color: Color, length: float) -> void:
	var s := _scale()
	var center := _to_screen(_pos(row))
	var dir := Vector2(_num(row.get("dx"), 1.0), _num(row.get("dy"), 0.0)).normalized()
	var side := dir.orthogonal() * _num(row.get("half_w"), 40.0) * s
	draw_line(center - side, center + side, color, 3.0)
	draw_line(center, center + dir * length * s, Color(color, 0.5), 1.5)


func _draw_bubble(row: Dictionary, color: Color) -> void:
	var center := _to_screen(_pos(row))
	draw_arc(center, _num(row.get("r"), 26.0) * _scale(), 0.0, TAU, 32, color, 2.0)


func _draw_ropes() -> void:
	var color: Color = KIND_COLORS["ropes"]
	var candy := _to_screen(_pos(level.get("candy", {}) as Dictionary))
	var rows: Variant = level.get("ropes", [])
	if not (rows is Array):
		return
	for row: Variant in rows:
		if not (row is Dictionary):
			continue
		var anchor := _to_screen(_pos(row as Dictionary))
		if (row as Dictionary).get("rail") is Dictionary:
			var rail: Dictionary = (row as Dictionary)["rail"]
			var a := _to_screen(Vector2(_num(rail.get("x1")), _num(rail.get("y1"))))
			var b := _to_screen(Vector2(_num(rail.get("x2")), _num(rail.get("y2"))))
			draw_line(a, b, Color(color, 0.4), 2.0)
		if level.get("candy") is Dictionary:
			draw_line(anchor, candy, Color(color, 0.55), 1.5)
		var rest := _num((row as Dictionary).get("rest"), 60.0) * _scale()
		draw_arc(anchor, rest, 0.0, TAU, 40, Color(color, 0.18), 1.0)
		draw_circle(anchor, 4.5 * _scale(), color)


func _draw_point(kind: String) -> void:
	var point: Variant = level.get(kind)
	if not (point is Dictionary):
		return
	var center := _to_screen(_pos(point as Dictionary))
	var color: Color = KIND_COLORS[kind]
	if kind == "mouth":
		draw_arc(center, 16.0 * _scale(), 0.0, TAU, 32, color, 3.0)
	else:
		draw_circle(center, 9.0 * _scale(), color)


func _draw_solver() -> void:
	if not solver_shown or solver_points.size() < 2:
		return
	var color := Color(0.35, 0.9, 0.45, 0.9) if solver_ok else Color(0.95, 0.35, 0.3, 0.9)
	var screen := PackedVector2Array()
	for point in solver_points:
		screen.append(_to_screen(point))
	draw_polyline(screen, color, 2.0)


func _draw_selection() -> void:
	if selected_kind.is_empty():
		return
	for handle in GobnomEditorLogic.handles(level):
		if str(handle["kind"]) == selected_kind and int(handle["index"]) == selected_index:
			var center := _to_screen(handle["pos"] as Vector2)
			draw_arc(center, HANDLE_RADIUS + 6.0, 0.0, TAU, 24, Color(1, 1, 1, 0.9), 2.0)
			return


static func _pos(row: Dictionary) -> Vector2:
	return Vector2(_num(row.get("x")), _num(row.get("y")))


static func _num(value: Variant, fallback := 0.0) -> float:
	if value is float or value is int:
		return float(value)
	return fallback
