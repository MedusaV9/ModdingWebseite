class_name RanchBauOverlay
extends Node3D
## Grid-Overlay des Ranch-Baumodus (RW-4) — Muster GridOverlay (Haus):
## Zell-Linien (3-m-Raster), rote Tönung GESPERRTER Zonen (statt Türzonen)
## und die grün/rote Gültigkeits-Tönung unterm Ghost. NEU: Kanten-
## Hervorhebung für Zaun-Ghosts (dicker Streifen auf der Kante).

const LINE_SOFT := Color(1.0, 1.0, 1.0, 0.16)
const LINE_STRONG := Color(1.0, 1.0, 1.0, 0.34)
const LOCKED_TINT := Color(0.35, 0.3, 0.5, 0.3)
const VALID_TINT := Color(0.45, 0.95, 0.5, 0.4)
const INVALID_TINT := Color(0.98, 0.35, 0.3, 0.45)
const LINE_Y := 0.03
const CELL_Y := 0.024
const HIGHLIGHT_Y := 0.04
const KANTE_BREITE := 0.34

var _grid: RanchGridData
var _lines: MeshInstance3D
var _locked: MeshInstance3D
var _highlight: MeshInstance3D


func setup(grid: RanchGridData) -> void:
	_grid = grid
	if _lines == null:
		_lines = _make_mesh_child("Lines")
		_locked = _make_mesh_child("Locked")
		_highlight = _make_mesh_child("Highlight")
	_build_lines()
	_build_locked()


## Zellen unterm Ghost grün/rot tönen.
func highlight_cells(cells: Array[Vector2i], valid: bool) -> void:
	var mesh := _highlight.mesh as ImmediateMesh
	mesh.clear_surfaces()
	if cells.is_empty():
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	mesh.surface_set_color(VALID_TINT if valid else INVALID_TINT)
	for cell in cells:
		_quad(
			mesh,
			Vector2(cell.x, cell.y) * RanchGridData.CELL_SIZE,
			Vector2(cell.x + 1, cell.y + 1) * RanchGridData.CELL_SIZE
		)
	mesh.surface_end()


## Eine Kante (normalisiert N/W) als dicken Streifen tönen (Zaun-Ghost).
func highlight_kante(cell: Vector2i, seite: String, valid: bool) -> void:
	var mesh := _highlight.mesh as ImmediateMesh
	mesh.clear_surfaces()
	var s := RanchGridData.CELL_SIZE
	var halb := KANTE_BREITE * 0.5
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	mesh.surface_set_color(VALID_TINT if valid else INVALID_TINT)
	if seite == "N":
		_quad(
			mesh,
			Vector2(cell.x * s, cell.y * s - halb),
			Vector2((cell.x + 1) * s, cell.y * s + halb)
		)
	else:
		_quad(
			mesh,
			Vector2(cell.x * s - halb, cell.y * s),
			Vector2(cell.x * s + halb, (cell.y + 1) * s)
		)
	mesh.surface_end()


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
	var s := RanchGridData.CELL_SIZE
	var w := _grid.size.x * s
	var d := _grid.size.y * s
	for x in _grid.size.x + 1:
		mesh.surface_set_color(LINE_STRONG if x % 2 == 0 else LINE_SOFT)
		mesh.surface_add_vertex(Vector3(x * s, LINE_Y, 0))
		mesh.surface_add_vertex(Vector3(x * s, LINE_Y, d))
	for y in _grid.size.y + 1:
		mesh.surface_set_color(LINE_STRONG if y % 2 == 0 else LINE_SOFT)
		mesh.surface_add_vertex(Vector3(0, LINE_Y, y * s))
		mesh.surface_add_vertex(Vector3(w, LINE_Y, y * s))
	mesh.surface_end()


func _build_locked() -> void:
	var mesh := _locked.mesh as ImmediateMesh
	mesh.clear_surfaces()
	var zellen: Array[Vector2i] = []
	for y in _grid.size.y:
		for x in _grid.size.x:
			var cell := Vector2i(x, y)
			if not _grid.ist_frei(cell):
				zellen.append(cell)
	if zellen.is_empty():
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	mesh.surface_set_color(LOCKED_TINT)
	for cell in zellen:
		_quad(
			mesh,
			Vector2(cell.x, cell.y) * RanchGridData.CELL_SIZE,
			Vector2(cell.x + 1, cell.y + 1) * RanchGridData.CELL_SIZE
		)
	mesh.surface_end()


func _quad(mesh: ImmediateMesh, von: Vector2, bis: Vector2) -> void:
	var y := CELL_Y if _locked != null and mesh == _locked.mesh else HIGHLIGHT_Y
	mesh.surface_add_vertex(Vector3(von.x, y, von.y))
	mesh.surface_add_vertex(Vector3(bis.x, y, von.y))
	mesh.surface_add_vertex(Vector3(bis.x, y, bis.y))
	mesh.surface_add_vertex(Vector3(von.x, y, von.y))
	mesh.surface_add_vertex(Vector3(bis.x, y, bis.y))
	mesh.surface_add_vertex(Vector3(von.x, y, bis.y))
