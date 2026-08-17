class_name BoardDisplay
extends Node3D
## 10×10-Schiffe-versenken-Brett als 3D-Objekt (W3c VISIT): Zellen-Kacheln
## im Schachbrett-Ton, Marker (Treffer/Wasser/versenkt), Schiffs-Blöcke fürs
## eigene Brett und eine Tap-Fläche (Area3D), die Taps in Zellen übersetzt.
## Liegt lokal in der XZ-Ebene — der Parent stellt das Gegner-Brett aufrecht.

signal cell_tapped(cell: Vector2i)

const BOARD_SIZE := 0.9  # Meter Kantenlänge

var interactive := true

var _cell := BOARD_SIZE / float(BattleshipLogic.GRID)
var _markers: Dictionary = {}  # Vector2i -> Node3D
var _ships: Array[Node3D] = []


func _ready() -> void:
	_build_base()
	_build_tap_area()


## Zellen-Mitte in LOKALEN Koordinaten (y leicht über dem Brett).
func cell_center(cell: Vector2i) -> Vector3:
	var origin := -BOARD_SIZE * 0.5 + _cell * 0.5
	return Vector3(origin + cell.x * _cell, 0.02, origin + cell.y * _cell)


## Schiffs-Blöcke (eigenes Brett) neu zeichnen.
func show_fleet(fleet: Array) -> void:
	for node in _ships:
		node.queue_free()
	_ships = []
	for ship: Dictionary in fleet:
		var cells := BattleshipLogic.ship_cells(ship)
		for cell in cells:
			var block := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = Vector3(_cell * 0.86, 0.035, _cell * 0.86)
			block.mesh = box
			block.material_override = _flat(Color(0.45, 0.52, 0.6))
			block.position = cell_center(cell) + Vector3(0.0, 0.02, 0.0)
			add_child(block)
			_ships.append(block)


## Marker setzen: "hit" (rot), "miss" (weiß), "sunk" (dunkelrot).
func set_marker(cell: Vector2i, kind: String) -> void:
	if _markers.has(cell):
		(_markers[cell] as Node3D).queue_free()
		_markers.erase(cell)
	var marker := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = _cell * 0.3
	sphere.height = _cell * 0.6
	marker.mesh = sphere
	var color := Color(0.95, 0.95, 0.9)
	match kind:
		"hit":
			color = Color(0.9, 0.25, 0.2)
		"sunk":
			color = Color(0.55, 0.08, 0.08)
	marker.material_override = _flat(color)
	marker.position = cell_center(cell) + Vector3(0.0, 0.03, 0.0)
	add_child(marker)
	_markers[cell] = marker


func mark_sunk(cells: Array) -> void:
	for raw: Variant in cells:
		set_marker(BattleshipLogic.to_cell(raw), "sunk")


func clear_board() -> void:
	for cell: Vector2i in _markers:
		(_markers[cell] as Node3D).queue_free()
	_markers = {}
	show_fleet([])


func _build_base() -> void:
	var base := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(BOARD_SIZE + 0.06, 0.03, BOARD_SIZE + 0.06)
	base.mesh = box
	base.material_override = _flat(Color(0.25, 0.42, 0.62))
	base.position = Vector3(0.0, -0.015, 0.0)
	add_child(base)
	for y in BattleshipLogic.GRID:
		for x in BattleshipLogic.GRID:
			var tile := MeshInstance3D.new()
			var quad := BoxMesh.new()
			quad.size = Vector3(_cell * 0.94, 0.012, _cell * 0.94)
			tile.mesh = quad
			var even := (x + y) % 2 == 0
			tile.material_override = _flat(
				Color(0.55, 0.75, 0.92) if even else Color(0.47, 0.68, 0.88)
			)
			tile.position = cell_center(Vector2i(x, y)) - Vector3(0.0, 0.014, 0.0)
			add_child(tile)


func _build_tap_area() -> void:
	var area := Area3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(BOARD_SIZE, 0.08, BOARD_SIZE)
	shape.shape = box
	area.add_child(shape)
	area.input_event.connect(_on_area_input)
	add_child(area)


func _on_area_input(
	_cam: Node, event: InputEvent, world_pos: Vector3, _normal: Vector3, _idx: int
) -> void:
	if not interactive:
		return
	var pressed: bool = (
		(event is InputEventMouseButton and event.pressed)
		or (event is InputEventScreenTouch and event.pressed)
	)
	if not pressed:
		return
	var local := to_local(world_pos)
	var origin := -BOARD_SIZE * 0.5
	var cell := Vector2i(
		int(floor((local.x - origin) / _cell)), int(floor((local.z - origin) / _cell))
	)
	if BattleshipLogic.in_bounds(cell):
		cell_tapped.emit(cell)


func _flat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	return mat
