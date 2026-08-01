extends Node3D
## ECHTES 3D-ROHRPANEL für das Rohr-Wirrwarr (MP-D-Tiefenpolitur): das
## Blaupausen-Brett steht als 3D-Panel in einer Gärtnerei mit Hügeln, Hecke,
## Zaun und Wolken (PipeFlowScenery), die Kacheln sind echte Rohrstücke,
## Wasser leuchtet als Kern durch die Leitung, unten sprüht der Sprenger ins
## Beet und Gooby (echtes Rig) schraubt mit. Kamera frontal auf die
## Panel-Ebene z=0 — alle Anker kommen als CANVAS-PIXEL aus der View und
## werden 1:1 in Welt umgerechnet. MECHANIK bleibt in pipe_flow.gd.
##
## Draw-Call-Diät: ALLE 25 Kacheln rendern über vier MultiMeshes (Arme, Naben,
## Wasserkerne) statt ~250 einzelner MeshInstances — die Kulisse durfte dafür
## wachsen. Antippen dreht die Kachel SICHTBAR (90°-Tween + Pop, Zahlen aus
## PipeFlowLogic.PIPE_JUICE), und alles, was schon am Hahn hängt, ist blass
## blau eingefärbt: sichtbarer Fortschritt statt Rätselraten.

const Stage3D := preload("res://scripts/minigames/games/_3dc_stage/stage3d.gd")
const Actor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")
const Models := preload("res://scripts/minigames/games/_3dc_stage/models3d.gd")
const Scenery := preload("res://scripts/minigames/games/pipe_flow/pipe_flow_scenery.gd")
const DIR := "res://assets/minigames/carrot_catch/"

const CAM_DIST := 10.0
const HALF_H := 4.2
const WATER := Color("4FD8F7")
const PIPE_BODY := Color(0.95, 0.97, 1.0)
## Blasses Wasserblau für Rohre, die schon am Hahn hängen (Fortschritt).
const PIPE_REACHED := Color(0.62, 0.86, 0.98)
const SHEET := Color(0.12, 0.3, 0.52)
const BRASS := Color(0.95, 0.76, 0.31)
## Dreh-Tween + Pop je Tap (Zahlen aus PipeFlowLogic.PIPE_JUICE).
const ROTATE_SEC := 0.16
const POP_SCALE := 0.14
## Fluss-Puls-Kette (G5): Versatz je Anschluss-Tiefe + Dauer/Stärke eines
## Kachel-Pulses, wenn das Wasser losläuft.
const FLOW_STEP_SEC := 0.07
const FLOW_PULSE_SEC := 0.3
const FLOW_PULSE_SCALE := 0.16

var stage: Node3D
var gooby: Node3D

var _vp := Vector2(390.0, 844.0)
var _grid := 5
var _cell_w := 0.5
var _tile_pos: Array[Vector3] = []
var _spin: PackedFloat32Array = PackedFloat32Array()
## Fluss-Puls-Kette: Uhr (−1 = aus) + Anschluss-Tiefen des gelösten Bretts.
var _flow_t := -1.0
var _flow_depths: Dictionary = {}
var _mm_arms: MultiMesh
var _mm_hubs: MultiMesh
var _mm_arm_water: MultiMesh
var _mm_hub_water: MultiMesh
var _grid_lines: MultiMeshInstance3D
var _panel: MeshInstance3D
var _panel_frame: Node3D
var _shelf: Node3D
var _feed: Node3D
var _feed_water: MeshInstance3D
var _drain: Node3D
var _drain_water: MeshInstance3D
var _tap: Node3D
var _tap_wheel: Node3D
var _src_ring: MeshInstance3D
var _goal_ring: MeshInstance3D
var _goal_arrow: MeshInstance3D
var _goal_base := Vector3.ZERO
var _sprinkler: Node3D
var _bed: Node3D
var _rainbow: Node3D
var _rainbow_mats: Array[StandardMaterial3D] = []
var _rainbow_t := 0.0
var _spray: GPUParticles3D
var _drip: GPUParticles3D
var _win_burst: GPUParticles3D
var _gold_burst: GPUParticles3D

var _mat_pipe: StandardMaterial3D
var _mat_water: StandardMaterial3D


func setup_stage() -> void:
	stage = Stage3D.new()
	add_child(stage)
	(
		stage
		. build(
			{
				# Goldener Gärtnerei-Nachmittag, NICHT überbelichtet.
				"sky_top": Color(0.45, 0.71, 0.92),
				"sky_horizon": Color(0.93, 0.9, 0.78),
				"ground_horizon": Color(0.66, 0.8, 0.52),
				"ground_bottom": Color(0.46, 0.62, 0.38),
				"sun_dir": Vector3(-0.35, -0.7, -0.5),
				"sun_color": Color(1.0, 0.93, 0.78),
				"sun_energy": 0.9,
				"ambient": 0.54,
				"fill_color": Color(0.78, 0.86, 1.0),
				"fill_energy": 0.22,
				"glow": 0.32,
				"glow_threshold": 0.8,
				"shadow_distance": 26.0,
				"fog": true,
				"fog_color": Color(0.86, 0.9, 0.8),
				"fog_from": 22.0,
				"fog_to": 55.0,
				"far": 110.0,
			}
		)
	)
	# Weiche Schatten statt harter Blaupausen-Flecken.
	stage.sun.shadow_blur = 1.6
	stage.sun.shadow_opacity = 0.55
	stage.sun.light_angular_distance = 2.5
	_mat_pipe = Fx.flat(PIPE_BODY)
	_mat_pipe.roughness = 0.35
	_mat_pipe.vertex_color_use_as_albedo = true
	_mat_water = Fx.glow(WATER, 0.9)
	Scenery.build(self)
	_build_panel()
	_build_tiles()
	_build_plumbing()
	_build_markers()
	_build_gooby()
	_build_fx()


func _build_panel() -> void:
	# Blaupausen-Brett: layout() setzt Position und Größe.
	_panel = MeshInstance3D.new()
	var sheet := BoxMesh.new()
	sheet.size = Vector3(1.0, 1.0, 0.12)
	sheet.material = Fx.flat(SHEET)
	_panel.mesh = sheet
	_panel.position.z = -0.2
	add_child(_panel)
	_panel_frame = Node3D.new()
	add_child(_panel_frame)
	var wood := Fx.flat(Color(0.62, 0.45, 0.3))
	for i in 4:
		var rail := MeshInstance3D.new()
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = Vector3(1.0, 0.14, 0.16)
		rail_mesh.material = wood
		rail.mesh = rail_mesh
		rail.name = "Rahmen%d" % i
		_panel_frame.add_child(rail)
	# Feines Blaupausen-Raster (EIN MultiMesh) — die Zellen sind ablesbar.
	_grid_lines = MultiMeshInstance3D.new()
	var line := BoxMesh.new()
	line.size = Vector3(1.0, 1.0, 0.01)
	line.material = Fx.flat(Color(0.3, 0.5, 0.72))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = line
	mm.instance_count = 12
	mm.visible_instance_count = 0
	_grid_lines.multimesh = mm
	_grid_lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_grid_lines)
	# Werkbank-Bord mit Blumentöpfen sitzt auf der oberen Rahmenleiste.
	_shelf = Scenery.shelf_props()
	add_child(_shelf)


## Vier MultiMeshes ersetzen ~250 Einzel-Meshes: Arme + Naben (mit Fortschritts-
## Farbe je Instanz) sowie die leuchtenden Wasserkerne beim Füllen.
func _build_tiles() -> void:
	var arm := CylinderMesh.new()
	arm.top_radius = 0.13
	arm.bottom_radius = 0.13
	arm.height = 0.5
	arm.radial_segments = 12
	arm.material = _mat_pipe
	_mm_arms = _make_mm(arm, 100, true)
	var hub := SphereMesh.new()
	hub.radius = 0.17
	hub.height = 0.34
	hub.radial_segments = 12
	hub.rings = 6
	hub.material = _mat_pipe
	_mm_hubs = _make_mm(hub, 25, true)
	var core := CylinderMesh.new()
	core.top_radius = 0.07
	core.bottom_radius = 0.07
	core.height = 0.52
	core.radial_segments = 8
	core.material = _mat_water
	_mm_arm_water = _make_mm(core, 100, false)
	var hub_core := SphereMesh.new()
	hub_core.radius = 0.1
	hub_core.height = 0.2
	hub_core.radial_segments = 8
	hub_core.rings = 4
	hub_core.material = _mat_water
	_mm_hub_water = _make_mm(hub_core, 25, false)


func _make_mm(mesh: Mesh, count: int, colors: bool) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = colors
	mm.mesh = mesh
	mm.instance_count = count
	mm.visible_instance_count = 0
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.extra_cull_margin = 16.0
	if not colors:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	return mm


func _build_plumbing() -> void:
	# Steigrohr (Hahn → Brett) und Fallrohr (Brett → Sprenger), je mit
	# innenliegendem Wasserkern, der nur beim Füllen leuchtet.
	_feed = Node3D.new()
	add_child(_feed)
	_feed.add_child(_pipe_run(false))
	_feed_water = _pipe_run(true)
	_feed.add_child(_feed_water)
	_drain = Node3D.new()
	add_child(_drain)
	_drain.add_child(_pipe_run(false))
	_drain_water = _pipe_run(true)
	_drain.add_child(_drain_water)
	# Messinghahn mit Handrad (dreht beim Füllen).
	_tap = Node3D.new()
	add_child(_tap)
	var body := MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.16
	body_mesh.bottom_radius = 0.2
	body_mesh.height = 0.34
	body_mesh.material = Fx.glow(BRASS, 0.2)
	body.mesh = body_mesh
	_tap.add_child(body)
	_tap_wheel = Node3D.new()
	_tap_wheel.position.y = 0.3
	_tap.add_child(_tap_wheel)
	var wheel := MeshInstance3D.new()
	var wheel_mesh := TorusMesh.new()
	wheel_mesh.inner_radius = 0.18
	wheel_mesh.outer_radius = 0.26
	wheel_mesh.material = Fx.glow(BRASS, 0.2)
	wheel.mesh = wheel_mesh
	_tap_wheel.add_child(wheel)
	var spoke_mesh := BoxMesh.new()
	spoke_mesh.size = Vector3(0.44, 0.05, 0.05)
	spoke_mesh.material = Fx.flat(Color(0.78, 0.6, 0.2))
	for i in 3:
		var spoke := MeshInstance3D.new()
		spoke.mesh = spoke_mesh
		spoke.rotation.y = TAU * float(i) / 3.0
		_tap_wheel.add_child(spoke)
	# Sprenger + Blumenbeet: layout() stellt beides unter das Fallrohr.
	_sprinkler = Node3D.new()
	add_child(_sprinkler)
	var s_base := MeshInstance3D.new()
	var s_base_mesh := BoxMesh.new()
	s_base_mesh.size = Vector3(0.5, 0.22, 0.3)
	s_base_mesh.material = Fx.glow(BRASS, 0.2)
	s_base.mesh = s_base_mesh
	_sprinkler.add_child(s_base)
	var s_head := MeshInstance3D.new()
	var s_head_mesh := SphereMesh.new()
	s_head_mesh.radius = 0.2
	s_head_mesh.height = 0.4
	s_head_mesh.material = Fx.flat(Color(0.45, 0.78, 0.75))
	s_head.mesh = s_head_mesh
	s_head.position.y = 0.28
	_sprinkler.add_child(s_head)
	_build_bed()


func _build_bed() -> void:
	_bed = Node3D.new()
	add_child(_bed)
	var soil := MeshInstance3D.new()
	var soil_mesh := BoxMesh.new()
	soil_mesh.size = Vector3(1.0, 0.3, 1.6)
	soil_mesh.material = Fx.flat(Color(0.43, 0.29, 0.2))
	soil.mesh = soil_mesh
	soil.name = "Erde"
	_bed.add_child(soil)
	var reds: Array = []
	var yellows: Array = []
	for i in 8:
		var pose := Transform3D(
			Basis(Vector3.UP, float(i) * 0.9),
			Vector3(-0.42 + float(i) * 0.12, 0.15, -0.4 if i % 2 == 0 else 0.35)
		)
		if i % 2 == 0:
			reds.append(pose)
		else:
			yellows.append(pose)
	var red_swarm := Models.swarm(Models.parts(DIR + "flower_redA.glb", 0.55), reds)
	red_swarm.name = "BlumenRot"
	_bed.add_child(red_swarm)
	var yellow_swarm := Models.swarm(Models.parts(DIR + "flower_yellowA.glb", 0.55), yellows)
	yellow_swarm.name = "BlumenGelb"
	_bed.add_child(yellow_swarm)
	var props := Scenery.bed_props()
	props.name = "Deko"
	_bed.add_child(props)
	# ECHTER Regenbogen über dem Beet — erscheint nur im Lösungsmoment: drei
	# ineinandergelegte Farbbögen (Rosé/Gold/Himmelblau) statt eines weißen
	# Torus, der sich vorher als kaputte Streifen las. Tori liegen roh flach
	# in xz; um x kippen, damit die Bögen zur Kamera stehen.
	_rainbow = Node3D.new()
	var bands: Array = [
		[1.32, Color(0.98, 0.62, 0.62)],
		[1.18, Color(1.0, 0.86, 0.5)],
		[1.04, Color(0.6, 0.86, 0.98)],
	]
	for band: Array in bands:
		var arc_mesh := TorusMesh.new()
		arc_mesh.inner_radius = float(band[0]) - 0.13
		arc_mesh.outer_radius = float(band[0])
		arc_mesh.rings = 24
		arc_mesh.ring_segments = 6
		var tint: Color = band[1]
		var mat := Fx.glow(tint, 0.8)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.6)
		arc_mesh.material = mat
		_rainbow_mats.append(mat)
		var arc := MeshInstance3D.new()
		arc.mesh = arc_mesh
		arc.rotation_degrees.x = 90.0
		arc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_rainbow.add_child(arc)
	_rainbow.visible = false
	add_child(_rainbow)


## Start- und Ziel-Marker: Ringe an Einlauf und Auslauf plus Bobbel-Pfeil —
## in drei Sekunden lesbar, wo das Wasser rein- und rauswill.
func _build_markers() -> void:
	# Fx.ring liegt roh flach in xz — um x kippen, damit er zur Kamera steht.
	_src_ring = Fx.ring(0.3, 0.045, Color(0.62, 0.9, 1.0))
	_src_ring.rotation_degrees.x = 90.0
	add_child(_src_ring)
	_goal_ring = Fx.ring(0.3, 0.045, Color(1.0, 0.85, 0.4))
	_goal_ring.rotation_degrees.x = 90.0
	add_child(_goal_ring)
	_goal_arrow = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.14
	cone.height = 0.28
	cone.radial_segments = 10
	cone.material = Fx.glow(Color(1.0, 0.85, 0.4), 0.7)
	_goal_arrow.mesh = cone
	_goal_arrow.rotation.z = PI
	_goal_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_goal_arrow)


func _build_gooby() -> void:
	gooby = Actor.new()
	add_child(gooby)
	gooby.mount(1.0)
	gooby.base_emotion = "happy"
	gooby.hold(
		Scenery.wrench(),
		"arm.R",
		Transform3D(Basis(Vector3.RIGHT, -0.9), Vector3(0.0, -0.08, 0.04))
	)
	var stool := Scenery.stool()
	stool.name = "Hocker"
	add_child(stool)


func _build_fx() -> void:
	_spray = (
		Fx
		. particles(
			{
				"color": Color(WATER, 0.9),
				"amount": 26,
				"lifetime": 0.7,
				"speed": Vector2(2.0, 3.2),
				"spread": 50.0,
				"gravity": Vector3(0.0, -5.0, 0.0),
				"size": Vector2(0.04, 0.09),
				"additive": true,
			}
		)
	)
	_spray.emitting = false
	add_child(_spray)
	_drip = (
		Fx
		. particles(
			{
				"color": Color(WATER, 0.85),
				"amount": 4,
				"lifetime": 0.6,
				"speed": Vector2(0.2, 0.5),
				"spread": 12.0,
				"gravity": Vector3(0.0, -3.0, 0.0),
				"size": Vector2(0.04, 0.07),
				"additive": true,
			}
		)
	)
	_drip.emitting = false
	add_child(_drip)
	_win_burst = (
		Fx
		. particles(
			{
				"color": Color(0.55, 0.9, 0.95, 0.95),
				"amount": 30,
				"lifetime": 0.65,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(1.6, 3.4),
				"spread": 80.0,
				"size": Vector2(0.05, 0.12),
				"additive": true,
			}
		)
	)
	add_child(_win_burst)
	# Zweite Farbe für den Lösungsmoment: goldene Funken zum Wasserblau.
	_gold_burst = (
		Fx
		. particles(
			{
				"color": Color(1.0, 0.86, 0.45, 0.95),
				"amount": 18,
				"lifetime": 0.75,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(1.2, 2.8),
				"spread": 85.0,
				"gravity": Vector3(0.0, -2.4, 0.0),
				"size": Vector2(0.06, 0.13),
				"additive": true,
			}
		)
	)
	add_child(_gold_burst)


## Kamera frontal auf die Panel-Ebene; Canvas-Pixel → Welt 1:1.
func frame(vp: Vector2) -> void:
	_vp = vp
	stage.apply_size(vp)
	stage.camera.position = Vector3(0.0, 0.0, CAM_DIST)
	stage.camera.rotation = Vector3.ZERO
	stage.set_half_height(HALF_H, CAM_DIST)


## W17 M1: Intro-Puzzle-Totale — die Kamera startet unten am Blumenbeet
## (Sprenger + Gooby im Bild) mit Blick hoch zum Blaupausen-Brett und steigt
## in die frontale Spielpose; k=1 == exakte frame()-Rahmung, kein Ruck.
func establish(k: float) -> void:
	var e := 1.0 - ease(clampf(k, 0.0, 1.0), 0.4)
	stage.camera.position = (Vector3(0.0, 0.0, CAM_DIST) + Vector3(0.0, -HALF_H * 0.55, 2.2) * e)
	stage.camera.rotation_degrees = Vector3(8.0 * e, 0.0, 0.0)


## Brett, Raster, Rohre, Hahn, Sprenger, Beet, Bord und Gooby an die 2D-Anker.
func layout(
	origin: Vector2, cell: float, grid: int, src_col: int, goal_col: int, bed_y: float
) -> void:
	_grid = grid
	_cell_w = cell / _ppu()
	# Neues Brett/Relayout: eine laufende Fluss-Puls-Kette gehört zum ALTEN
	# Brett — abbrechen statt fremde Kacheln pulsen zu lassen.
	_flow_t = -1.0
	_flow_depths = {}
	if _tile_pos.size() != grid * grid:
		_tile_pos.resize(grid * grid)
		_spin.resize(grid * grid)
		for i in grid * grid:
			_spin[i] = 0.0
	for i in grid * grid:
		var col := i % grid
		var row := i / grid
		var px := origin + Vector2((col + 0.5) * cell, (row + 0.5) * cell)
		_tile_pos[i] = Vector3(_wx(px.x), _wy(px.y), 0.0)
	var board_px := cell * grid
	var center := origin + Vector2.ONE * (board_px * 0.5)
	_panel.position = Vector3(_wx(center.x), _wy(center.y), -0.24)
	_panel.scale = Vector3(board_px / _ppu() + 0.5, board_px / _ppu() + 0.5, 1.0)
	_layout_frame(board_px)
	_layout_grid_lines(origin, cell, grid)
	# Steigrohr vom Hahn zur Brettkante, Fallrohr von der Kante ins Beet.
	var feed_x := _wx(origin.x + (float(src_col) + 0.5) * cell)
	var top_y := _wy(origin.y)
	var head_y := _wy(maxf(96.0, origin.y - 108.0))
	_place_run(_feed, feed_x, top_y, head_y)
	_tap.position = Vector3(feed_x, head_y + 0.1, 0.0)
	_src_ring.position = Vector3(feed_x, top_y, 0.1)
	var drain_x := _wx(origin.x + (float(goal_col) + 0.5) * cell)
	var bottom_y := _wy(origin.y + board_px)
	var bed_wy := _wy(bed_y)
	_place_run(_drain, drain_x, bed_wy, bottom_y)
	_goal_ring.position = Vector3(drain_x, bottom_y, 0.1)
	_goal_base = Vector3(drain_x, bottom_y + 0.42, 0.15)
	_goal_arrow.position = _goal_base
	_sprinkler.position = Vector3(drain_x, bed_wy + 0.12, 0.4)
	_spray.position = _sprinkler.position + Vector3(0.0, 0.4, 0.2)
	# Bogen-Mitte tief ansetzen: nur die obere Regenbogen-Hälfte ragt ins Bild.
	# z=−0,1: VOR der Wandtafel (−0,24), hinter den Rohren (0,0) — bei −0,6
	# verschluckte die Tafel den Bogenscheitel, es blieben zwei Säulen übrig.
	_rainbow.position = Vector3(_wx(_vp.x * 0.5), bed_wy - 1.3, -0.1)
	_layout_bed(bed_wy)
	gooby.position = Vector3(_wx(_vp.x * 0.86), bed_wy + 0.3, 1.1)
	gooby.scale = Vector3.ONE * clampf(_cell_w * 0.9, 0.5, 1.4)
	gooby.rotation.y = -0.35
	var stool := get_node("Hocker") as Node3D
	stool.position = gooby.position + Vector3(0.05, -0.34, -0.12)
	stool.scale = gooby.scale


func _layout_frame(board_px: float) -> void:
	var half := board_px * 0.5 / _ppu() + 0.32
	for i in 4:
		var rail := _panel_frame.get_node("Rahmen%d" % i) as MeshInstance3D
		var vertical := i >= 2
		rail.rotation.z = PI * 0.5 if vertical else 0.0
		rail.scale = Vector3(half * 2.0 + 0.14, 1.0, 1.0)
		var off := half if i % 2 == 0 else -half
		rail.position = (
			_panel.position + (Vector3(off, 0.0, 0.14) if vertical else Vector3(0.0, off, 0.14))
		)
	# Bord (Töpfe) auf die obere Leiste — lugt in den Himmelsstreifen.
	var top_rail := _panel_frame.get_node("Rahmen0") as MeshInstance3D
	_shelf.position = top_rail.position + Vector3(half * 0.55, 0.07, 0.05)
	_shelf.scale = Vector3.ONE * clampf(_cell_w * 1.15, 0.6, 1.2)


func _layout_grid_lines(origin: Vector2, cell: float, grid: int) -> void:
	var mm := _grid_lines.multimesh
	var board_w := cell * grid / _ppu()
	var count := 0
	for i in grid - 1:
		var px := origin + Vector2((float(i) + 1.0) * cell, cell * grid * 0.5)
		var v_basis := Basis.IDENTITY.scaled(Vector3(0.015, board_w, 1.0))
		mm.set_instance_transform(count, Transform3D(v_basis, Vector3(_wx(px.x), _wy(px.y), -0.17)))
		count += 1
		var py := origin + Vector2(cell * grid * 0.5, (float(i) + 1.0) * cell)
		var h_basis := Basis.IDENTITY.scaled(Vector3(board_w, 0.015, 1.0))
		mm.set_instance_transform(count, Transform3D(h_basis, Vector3(_wx(py.x), _wy(py.y), -0.17)))
		count += 1
	mm.visible_instance_count = count


func _layout_bed(bed_wy: float) -> void:
	_bed.position = Vector3(_wx(_vp.x * 0.5), bed_wy - 0.15, 0.2)
	_bed.scale = Vector3(_vp.x / _ppu() * 0.98, 1.0, 1.0)
	# Beet-Kinder nicht in x verzerren: Blumen und Deko gegenskalieren.
	var inv := 1.0 / maxf(0.05, _bed.scale.x)
	(_bed.get_node("BlumenRot") as Node3D).scale = Vector3(inv, 1.0, 1.0)
	(_bed.get_node("BlumenGelb") as Node3D).scale = Vector3(inv, 1.0, 1.0)
	(_bed.get_node("Deko") as Node3D).scale = Vector3(inv, 1.0, 1.0)


## Jeden Frame: MultiMesh-Kacheln stellen, Hahn drehen, Marker pulsieren.
## `reached` = water_reach-Tiefen (Fortschritts-Tint), `watered` = Füllwelle.
func sync(
	tiles: Array,
	watered: Array[bool],
	reached: Dictionary,
	filling: bool,
	leak_index: int,
	pulse: float,
	delta: float
) -> void:
	stage.tick(delta)
	gooby.tick(delta)
	Scenery.drift(delta)
	gooby.rotation.z = sin(pulse * 2.3) * 0.03
	if _flow_t >= 0.0:
		_flow_t += delta
		if _flow_t > _flow_end():
			_flow_t = -1.0
			_flow_depths = {}
	_sync_tiles(tiles, watered, reached, delta)
	_feed_water.visible = filling
	_drain_water.visible = filling
	_spray.emitting = filling
	if filling:
		_tap_wheel.rotation.y = pulse * 5.0
	_drip.emitting = leak_index >= 0
	if leak_index >= 0 and leak_index < _tile_pos.size():
		_drip.position = _tile_pos[leak_index] + Vector3(0.0, -0.1, 0.3)
	# Marker atmen; der Zielpfeil bobbelt zum Auslauf.
	var beat := 1.0 + 0.1 * sin(pulse * 3.0)
	_src_ring.scale = Vector3.ONE * beat
	_goal_ring.scale = Vector3.ONE * (1.0 + 0.14 * sin(pulse * 3.4))
	_goal_arrow.position = _goal_base + Vector3(0.0, 0.08 * sin(pulse * 4.0), 0.0)
	if _rainbow_t > 0.0:
		_rainbow_t = maxf(0.0, _rainbow_t - delta)
		var fade := clampf(_rainbow_t / 0.4, 0.0, 1.0)
		var grow := clampf((2.2 - _rainbow_t) * 3.0, 0.05, 1.0)
		_rainbow.visible = true
		_rainbow.scale = Vector3.ONE * (grow * 2.4)
		for i in _rainbow_mats.size():
			var mat := _rainbow_mats[i]
			var tint := mat.emission
			mat.albedo_color = Color(tint.r, tint.g, tint.b, 0.6 * fade)
	else:
		_rainbow.visible = false


## Kachel-Instanzen neu schreiben: Drehung/Pop des Tap-Tweens, Fortschritts-
## Farbe (am Hahn = blass blau) und Wasserkerne der Füllwelle.
func _sync_tiles(tiles: Array, watered: Array[bool], reached: Dictionary, delta: float) -> void:
	var arm_count := 0
	var water_count := 0
	var hub_water_count := 0
	var dirs: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
	for i in mini(tiles.size(), _tile_pos.size()):
		if _spin[i] > 0.0:
			_spin[i] = maxf(0.0, _spin[i] - delta)
		var frac := _spin[i] / ROTATE_SEC
		var ang := frac * PI * 0.5
		var pop := 1.0 + POP_SCALE * sin((1.0 - frac) * PI) * (1.0 if frac > 0.0 else 0.0)
		pop += _flow_pop(i)
		var tile_basis := Basis(Vector3.BACK, ang).scaled(Vector3.ONE * (_cell_w * pop))
		var tile_xf := Transform3D(tile_basis, _tile_pos[i])
		var tile: Dictionary = tiles[i]
		var mask := PipeFlowLogic.mask_of(str(tile["shape"]), int(tile["rot"]))
		var wet: bool = watered[i]
		var color := PIPE_REACHED if reached.has(i) else Color(1, 1, 1)
		_mm_hubs.set_instance_transform(i, tile_xf)
		_mm_hubs.set_instance_color(i, color)
		if wet:
			_mm_hub_water.set_instance_transform(
				hub_water_count, tile_xf * Transform3D(Basis.IDENTITY, Vector3(0.0, 0.0, 0.09))
			)
			hub_water_count += 1
		for d in 4:
			if (mask & (1 << d)) == 0:
				continue
			var rot_z := 0.0 if d % 2 == 0 else PI * 0.5
			var off := Vector3(dirs[d].x * 0.25, -dirs[d].y * 0.25, 0.0)
			var local := Transform3D(Basis(Vector3.BACK, rot_z), off)
			_mm_arms.set_instance_transform(arm_count, tile_xf * local)
			_mm_arms.set_instance_color(arm_count, color)
			arm_count += 1
			if wet:
				var core_local := Transform3D(
					Basis(Vector3.BACK, rot_z), off + Vector3(0.0, 0.0, 0.08)
				)
				_mm_arm_water.set_instance_transform(water_count, tile_xf * core_local)
				water_count += 1
	_mm_hubs.visible_instance_count = mini(tiles.size(), _tile_pos.size())
	_mm_arms.visible_instance_count = arm_count
	_mm_arm_water.visible_instance_count = water_count
	_mm_hub_water.visible_instance_count = hub_water_count


## Tap-Bestätigung: 90°-Dreh-Tween + Pop auf der Kachel, Gooby schraubt mit.
func tap_fx(index: int) -> void:
	if index >= 0 and index < _spin.size():
		_spin[index] = ROTATE_SEC
	gooby.play_for("build_hammer", 0.5)
	gooby.swing(0.3, 16.0, Vector3.RIGHT)


## Fluss-Start-Moment (G5): eine Puls-Kette läuft in Anschluss-Reihenfolge
## (water_reach-Tiefen) durch die gelegte Leitung — Aufrufer gatet Reduced
## Motion an der Call-Site, der statische Fortschritts-Tint bleibt dort.
func flow_fx(depths: Dictionary) -> void:
	_flow_depths = depths.duplicate()
	_flow_t = 0.0


## Kachel-Pop der Fluss-Kette: jede angeschlossene Kachel pulst einmal kurz,
## versetzt um ihre Anschluss-Tiefe (0 = am Hahn).
func _flow_pop(index: int) -> float:
	if _flow_t < 0.0 or not _flow_depths.has(index):
		return 0.0
	var local := _flow_t - float(int(_flow_depths[index])) * FLOW_STEP_SEC
	if local < 0.0 or local > FLOW_PULSE_SEC:
		return 0.0
	return FLOW_PULSE_SCALE * sin(local / FLOW_PULSE_SEC * PI)


## Ende der Puls-Kette: tiefste Kachel + eine Puls-Dauer.
func _flow_end() -> float:
	var max_depth := 0
	for value: int in _flow_depths.values():
		max_depth = maxi(max_depth, value)
	return float(max_depth) * FLOW_STEP_SEC + FLOW_PULSE_SEC


## Lösungs-Feier; `reduced` lässt Emote/Glühen/Regenbogen, gatet aber Hüpfer
## und Partikel (Q2 — Reduced-Motion-Gate an der eigenen Fx.burst-Call-Site).
func solve_fx(goal_index: int, reduced := false) -> void:
	gooby.emote("ecstatic", 1.4)
	gooby.play_for("celebrate", 1.0)
	stage.pulse_glow(0.8)
	_rainbow_t = 2.2
	if reduced:
		return
	gooby.hop(0.45, 0.3)
	if goal_index >= 0 and goal_index < _tile_pos.size():
		var at := _tile_pos[goal_index] + Vector3(0.0, 0.0, 0.4)
		Fx.burst(_win_burst, at)
		# Goldfunken obendrauf: der Lösungsmoment liest sich als Belohnung.
		Fx.burst(_gold_burst, at + Vector3(0.0, 0.15, 0.1))


## Leck-Reaktion; der Tropf-Emitter bleibt als Countdown-Feedback, nur der
## Platsch-Burst wird gegated (Q2).
func leak_fx(index: int, reduced := false) -> void:
	gooby.emote("scared", 1.2)
	gooby.play_for("idle_lookaround", 1.0)
	if reduced:
		return
	if index >= 0 and index < _tile_pos.size():
		Fx.burst(_win_burst, _tile_pos[index] + Vector3(0.0, -0.2, 0.3))


## Senkrechter Rohrlauf zwischen zwei Welt-y (layout skaliert/verschiebt ihn).
func _pipe_run(water: bool) -> MeshInstance3D:
	var run := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.07 if water else 0.14
	mesh.bottom_radius = 0.07 if water else 0.14
	mesh.height = 1.0
	mesh.radial_segments = 10
	mesh.material = _mat_water if water else Fx.flat(PIPE_BODY, 0.35)
	run.mesh = mesh
	if water:
		run.visible = false
		run.position.z = 0.06
		run.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return run


func _place_run(run: Node3D, x: float, y_lo: float, y_hi: float) -> void:
	var h := maxf(0.1, y_hi - y_lo)
	run.position = Vector3(x, (y_lo + y_hi) * 0.5, 0.0)
	run.scale = Vector3(1.0, h, 1.0)


func _ppu() -> float:
	return _vp.y / (HALF_H * 2.0)


func _wx(px: float) -> float:
	return (px - _vp.x * 0.5) / _ppu()


func _wy(py: float) -> float:
	return (_vp.y * 0.5 - py) / _ppu()
