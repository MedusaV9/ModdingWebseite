extends RefCounted
## Küchen-Kulisse für GOB NOM (MP-G): Wand, Fliesen-Spiegel, Regalbretter
## voller Vorratsgläser, Fenster mit Blick ins Grüne und Süßigkeiten auf der
## Arbeitsplatte. Statische Fabrik — gobnom_stage3d.gd hängt den Knoten ein;
## hier lebt NUR Kulisse (keine Spielobjekte, keine Anker-Mathematik).

const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")
const Models := preload("res://scripts/minigames/games/_3dc_stage/models3d.gd")
const DIR := "res://assets/minigames/carrot_catch/"

## Farb-Kanon wie gobnom_stage3d.gd (dort bleibt COUNTER_WOOD für die Platte).
const WOOD := Color("#A9744B")
const WOOD_DARK := Color("#7C5433")
const NUTELLA := Color("#5C3A21")
const KITCHEN_WALL := Color("#EBD8B4")


## Küchenwand mit TIEFE hinter der Spielebene: Fliesen-Spiegel über der
## Arbeitsplatte, zwei Regalbretter voller Gläser, ein Fenster mit Blick
## ins Grüne — und vorne auf der Platte ein paar Süßigkeiten.
static func build(backdrop: Node3D) -> void:
	var wall := MeshInstance3D.new()
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(56.0, 22.0, 0.4)
	wall_mesh.material = Fx.flat(KITCHEN_WALL)
	wall.mesh = wall_mesh
	wall.position = Vector3(0.0, 10.0, -7.2)
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	backdrop.add_child(wall)
	_tiles(backdrop)
	_shelves(backdrop)
	_window(backdrop)
	# Süßigkeiten auf der Arbeitsplatte (die Nascherei bleibt das Thema).
	var sweets := ["cupcake.glb", "donut-sprinkles.glb", "cake.glb"]
	for i in 3:
		var prop := Models.node(DIR + sweets[i], 1.5)
		prop.position = Vector3(-9.0 + float(i) * 8.2, 0.0, -4.6 - float(i % 2) * 0.8)
		prop.rotation.y = 0.6 * float(i)
		backdrop.add_child(prop)


## Fliesen-Spiegel: EIN MultiMesh, Schachbrett aus zwei Pastelltönen.
static func _tiles(backdrop: Node3D) -> void:
	var tile_mesh := BoxMesh.new()
	tile_mesh.size = Vector3(1.16, 1.16, 0.06)
	var tile_mat := Fx.flat(Color.WHITE, 0.55)
	tile_mat.vertex_color_use_as_albedo = true
	tile_mesh.material = tile_mat
	var tiles := MultiMeshInstance3D.new()
	var tmm := MultiMesh.new()
	tmm.transform_format = MultiMesh.TRANSFORM_3D
	tmm.use_colors = true
	tmm.mesh = tile_mesh
	# 21 Spalten decken die volle sichtbare Wandbreite (±12 Einheiten) —
	# mit 17 riss der Fliesen-Spiegel rechts unter dem Fenster sichtbar ab.
	tmm.instance_count = 42
	for i in 42:
		var col := i % 21
		var row := i / 21
		tmm.set_instance_transform(
			i,
			Transform3D(
				Basis.IDENTITY, Vector3(-12.0 + float(col) * 1.2, 0.62 + float(row) * 1.2, -6.95)
			)
		)
		tmm.set_instance_color(i, Color("#C4DECE") if (col + row) % 2 == 0 else Color("#EFE7CF"))
	tiles.multimesh = tmm
	tiles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	backdrop.add_child(tiles)


## Zwei Regalbretter + Vorratsgläser (EIN MultiMesh, Instanzfarben).
static func _shelves(backdrop: Node3D) -> void:
	var board_mesh := BoxMesh.new()
	board_mesh.size = Vector3(11.0, 0.3, 1.0)
	board_mesh.material = Fx.flat(WOOD)
	for board_y: float in [4.4, 7.2]:
		var board := MeshInstance3D.new()
		board.mesh = board_mesh
		board.position = Vector3(-5.4, board_y, -6.6)
		board.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		backdrop.add_child(board)
	var jar_mesh := CylinderMesh.new()
	jar_mesh.top_radius = 0.34
	jar_mesh.bottom_radius = 0.3
	jar_mesh.height = 0.9
	jar_mesh.radial_segments = 10
	var jar_mat := Fx.flat(Color.WHITE, 0.5)
	jar_mat.vertex_color_use_as_albedo = true
	jar_mesh.material = jar_mat
	var jars := MultiMeshInstance3D.new()
	var jmm := MultiMesh.new()
	jmm.transform_format = MultiMesh.TRANSFORM_3D
	jmm.use_colors = true
	jmm.mesh = jar_mesh
	jmm.instance_count = 12
	var pantry: Array = [
		NUTELLA, Color("#C94F4F"), Color("#E8B84C"), Color("#7FA95A"), Color("#B87333"), NUTELLA
	]
	for i in 12:
		var shelf := i / 6
		var slot := i % 6
		var s := 0.85 + 0.3 * float((i * 5) % 3) * 0.5
		jmm.set_instance_transform(
			i,
			Transform3D(
				Basis.IDENTITY.scaled(Vector3(s, s, s)),
				Vector3(
					-9.8 + float(slot) * 1.75 + 0.3 * float(shelf),
					(4.55 if shelf == 0 else 7.35) + 0.45 * s,
					-6.55
				)
			)
		)
		jmm.set_instance_color(i, pantry[(i * 7 + shelf) % pantry.size()])
	jars.multimesh = jmm
	jars.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	backdrop.add_child(jars)


## Fenster rechts: Holzrahmen + „Blick ins Grüne" als sanfter Verlauf.
static func _window(backdrop: Node3D) -> void:
	var frame := MeshInstance3D.new()
	var frame_mesh := BoxMesh.new()
	frame_mesh.size = Vector3(6.4, 7.4, 0.3)
	frame_mesh.material = Fx.flat(WOOD_DARK)
	frame.mesh = frame_mesh
	frame.position = Vector3(7.6, 5.4, -6.9)
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	backdrop.add_child(frame)
	var pane := MeshInstance3D.new()
	var pane_mesh := BoxMesh.new()
	pane_mesh.size = Vector3(5.6, 6.6, 0.2)
	pane_mesh.material = Fx.glow(Color(0.72, 0.88, 0.78), 0.28)
	pane.mesh = pane_mesh
	# z = -6.82, NICHT -6.85: sonst liegt die Scheiben-Vorderseite exakt in
	# der Rahmen-Ebene (-6.75) und z-fightet — mal grün, mal Vollholz.
	pane.position = Vector3(7.6, 5.4, -6.82)
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	backdrop.add_child(pane)
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(0.28, 6.6, 0.24)
	bar_mesh.material = Fx.flat(WOOD_DARK)
	var bar := MeshInstance3D.new()
	bar.mesh = bar_mesh
	bar.position = Vector3(7.6, 5.4, -6.8)
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	backdrop.add_child(bar)
