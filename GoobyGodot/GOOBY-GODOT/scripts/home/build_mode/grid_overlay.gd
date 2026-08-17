class_name GridOverlay
extends Node3D
## Grid-Overlay des Baumodus (W2a HOUSE, Doc D §2.1): Zell-Linien (jede 2.
## Linie kräftiger = 1-m-Raster), schraffierte Tür-Freihaltezonen und die
## grün/rote Gültigkeits-Tönung unter dem Ghost.

const LINE_SOFT := Color(1.0, 1.0, 1.0, 0.18)
const LINE_STRONG := Color(1.0, 1.0, 1.0, 0.38)
const BLOCKED_TINT := Color(1.0, 0.45, 0.35, 0.28)
const VALID_TINT := Color(0.45, 0.95, 0.5, 0.4)
const INVALID_TINT := Color(0.98, 0.35, 0.3, 0.45)
const LINE_Y := 0.015
const CELL_Y := 0.012
const HIGHLIGHT_Y := 0.02

var _grid: GridData
var _lines: MeshInstance3D
var _blocked: MeshInstance3D
var _highlight: MeshInstance3D


func setup(grid: GridData) -> void:
	_grid = grid
	_lines = _make_mesh_child("Lines")
	_blocked = _make_mesh_child("Blocked")
	_highlight = _make_mesh_child("Highlight")
	_build_lines()
	_fill_cells(_blocked, _grid.blocked.keys(), BLOCKED_TINT, CELL_Y)
	visible = false


## Zellen unterm Ghost grün/rot tönen.
func highlight(cells: Array[Vector2i], valid: bool) -> void:
	_fill_cells(_highlight, cells, VALID_TINT if valid else INVALID_TINT, HIGHLIGHT_Y)


## W13B Decken-Modus: hebt das komplette Overlay auf die Decken-Höhe — das
## Decken-Raster ist das Boden-Raster, gespiegelt an der Raumdecke
## (Doc D §2.1). Türzonen-Schraffur ist ein Boden-Konzept und wird oben
## ausgeblendet.
func set_ebene_hoehe(hoehe: float) -> void:
	position.y = hoehe
	_blocked.visible = hoehe <= 0.001


func clear_highlight() -> void:
	(_highlight.mesh as ImmediateMesh).clear_surfaces()


func _make_mesh_child(child_name: String) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	mesh.name = child_name
	mesh.mesh = ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mesh.material_override = mat
	add_child(mesh)
	return mesh


func _build_lines() -> void:
	var mesh := _lines.mesh as ImmediateMesh
	mesh.clear_surfaces()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var w := _grid.size.x * GridData.CELL_SIZE
	var d := _grid.size.y * GridData.CELL_SIZE
	for x in _grid.size.x + 1:
		mesh.surface_set_color(LINE_STRONG if x % 2 == 0 else LINE_SOFT)
		mesh.surface_add_vertex(Vector3(x * GridData.CELL_SIZE, LINE_Y, 0))
		mesh.surface_add_vertex(Vector3(x * GridData.CELL_SIZE, LINE_Y, d))
	for y in _grid.size.y + 1:
		mesh.surface_set_color(LINE_STRONG if y % 2 == 0 else LINE_SOFT)
		mesh.surface_add_vertex(Vector3(0, LINE_Y, y * GridData.CELL_SIZE))
		mesh.surface_add_vertex(Vector3(w, LINE_Y, y * GridData.CELL_SIZE))
	mesh.surface_end()


func _fill_cells(target: MeshInstance3D, cells: Array, tint: Color, height: float) -> void:
	var mesh := target.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if cells.is_empty():
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	mesh.surface_set_color(tint)
	for cell: Vector2i in cells:
		var x0 := cell.x * GridData.CELL_SIZE
		var z0 := cell.y * GridData.CELL_SIZE
		var x1 := x0 + GridData.CELL_SIZE
		var z1 := z0 + GridData.CELL_SIZE
		mesh.surface_add_vertex(Vector3(x0, height, z0))
		mesh.surface_add_vertex(Vector3(x1, height, z0))
		mesh.surface_add_vertex(Vector3(x1, height, z1))
		mesh.surface_add_vertex(Vector3(x0, height, z0))
		mesh.surface_add_vertex(Vector3(x1, height, z1))
		mesh.surface_add_vertex(Vector3(x0, height, z1))
	mesh.surface_end()
