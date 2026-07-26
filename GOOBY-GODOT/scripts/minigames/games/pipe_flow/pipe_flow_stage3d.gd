extends Node3D
## ECHTES 3D-ROHRPANEL für das Rohr-Wirrwarr (FB-4): das Blaupausen-Brett steht
## als 3D-Panel im Garten, die Kacheln sind ECHTE Rohrstücke (Zylinder-Arme +
## Nabe), Wasser läuft als leuchtender Kern durch die Leitung, oben speist ein
## Messinghahn, unten sprüht der Sprenger ins 3D-Blumenbeet und Gooby (echtes
## Rig) schaut zu. Kamera frontal auf die Panel-Ebene z=0 — alle Anker kommen
## als CANVAS-PIXEL aus der View und werden 1:1 in Welt umgerechnet (nur so
## bleiben die Rohr-Arme exakt verbunden). MECHANIK bleibt in pipe_flow.gd.

const Stage3D := preload("res://scripts/minigames/games/_3dc_stage/stage3d.gd")
const Actor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")
const Models := preload("res://scripts/minigames/games/_3dc_stage/models3d.gd")
const DIR := "res://assets/minigames/carrot_catch/"

const CAM_DIST := 10.0
const HALF_H := 4.2
const WATER := Color("4FD8F7")
const PIPE_BODY := Color(0.93, 0.96, 1.0)
const SHEET := Color(0.13, 0.32, 0.55)
const BRASS := Color(0.95, 0.76, 0.31)

var stage: Node3D
var gooby: Node3D

var _vp := Vector2(390.0, 844.0)
var _tiles: Array[Node3D] = []
var _panel: MeshInstance3D
var _panel_frame: Node3D
var _feed: Node3D
var _feed_water: MeshInstance3D
var _drain: Node3D
var _drain_water: MeshInstance3D
var _tap: Node3D
var _tap_wheel: Node3D
var _sprinkler: Node3D
var _bed: Node3D
var _spray: GPUParticles3D
var _drip: GPUParticles3D
var _win_burst: GPUParticles3D

var _mat_pipe: StandardMaterial3D
var _mat_water: StandardMaterial3D


func setup_stage() -> void:
	stage = Stage3D.new()
	add_child(stage)
	(
		stage
		. build(
			{
				# Klarer Gärtnerei-Morgen, NICHT überbelichtet.
				"sky_top": Color(0.5, 0.75, 0.93),
				"sky_horizon": Color(0.87, 0.92, 0.88),
				"ground_horizon": Color(0.64, 0.79, 0.53),
				"ground_bottom": Color(0.47, 0.63, 0.39),
				"sun_dir": Vector3(-0.35, -0.75, -0.45),
				"sun_energy": 0.85,
				"ambient": 0.56,
				"fill_energy": 0.22,
				"glow": 0.3,
				"glow_threshold": 0.82,
				"shadow_distance": 26.0,
				"fog": true,
				"fog_color": Color(0.85, 0.92, 0.88),
				"fog_from": 24.0,
				"fog_to": 60.0,
				"far": 100.0,
			}
		)
	)
	_mat_pipe = Fx.flat(PIPE_BODY)
	_mat_pipe.roughness = 0.35
	_mat_water = Fx.glow(WATER, 0.9)
	_build_backdrop()
	_build_panel()
	_build_plumbing()
	_build_gooby()
	_build_fx()


func _build_backdrop() -> void:
	# Wiese hinter/unter dem Panel + Baumreihe am Horizont.
	var lawn := Fx.ground(Vector2(70.0, 50.0), Color(0.55, 0.75, 0.42))
	lawn.position.y = -4.6
	add_child(lawn)
	var tree_poses: Array = []
	for i in 4:
		tree_poses.append(
			Transform3D(
				Basis(Vector3.UP, float(i) * 1.4),
				Vector3(-13.0 + float(i) * 8.0, -4.6, -14.0 - 2.0 * float(i % 2))
			)
		)
	add_child(Models.swarm(Models.parts(DIR + "tree_default.glb", 4.0), tree_poses))


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


func _build_gooby() -> void:
	gooby = Actor.new()
	add_child(gooby)
	gooby.mount(1.0)
	gooby.base_emotion = "happy"


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
				"amount": 22,
				"lifetime": 0.6,
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


## Kamera frontal auf die Panel-Ebene; Canvas-Pixel → Welt 1:1.
func frame(vp: Vector2) -> void:
	_vp = vp
	stage.apply_size(vp)
	stage.camera.position = Vector3(0.0, 0.0, CAM_DIST)
	stage.camera.rotation = Vector3.ZERO
	stage.set_half_height(HALF_H, CAM_DIST)


## Brett, Rohre, Hahn, Sprenger, Beet und Gooby an die 2D-Anker legen.
func layout(
	origin: Vector2, cell: float, grid: int, src_col: int, goal_col: int, bed_y: float
) -> void:
	while _tiles.size() < grid * grid:
		var tile := _spawn_tile()
		add_child(tile)
		_tiles.append(tile)
	var cw := cell / _ppu()
	for i in _tiles.size():
		var col := i % grid
		var row := i / grid
		var px := origin + Vector2((col + 0.5) * cell, (row + 0.5) * cell)
		_tiles[i].position = Vector3(_wx(px.x), _wy(px.y), 0.0)
		_tiles[i].scale = Vector3.ONE * cw
	var board_px := cell * grid
	var center := origin + Vector2.ONE * (board_px * 0.5)
	_panel.position = Vector3(_wx(center.x), _wy(center.y), -0.24)
	_panel.scale = Vector3(board_px / _ppu() + 0.5, board_px / _ppu() + 0.5, 1.0)
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
	# Steigrohr vom Hahn zur Brettkante, Fallrohr von der Kante ins Beet.
	var feed_x := _wx(origin.x + (float(src_col) + 0.5) * cell)
	var top_y := _wy(origin.y)
	var head_y := _wy(maxf(96.0, origin.y - 108.0))
	_place_run(_feed, feed_x, top_y, head_y)
	_tap.position = Vector3(feed_x, head_y + 0.1, 0.0)
	var drain_x := _wx(origin.x + (float(goal_col) + 0.5) * cell)
	var bottom_y := _wy(origin.y + board_px)
	var bed_wy := _wy(bed_y)
	_place_run(_drain, drain_x, bed_wy, bottom_y)
	_sprinkler.position = Vector3(drain_x, bed_wy + 0.12, 0.4)
	_spray.position = _sprinkler.position + Vector3(0.0, 0.4, 0.2)
	_bed.position = Vector3(_wx(_vp.x * 0.5), bed_wy - 0.15, 0.2)
	_bed.scale = Vector3(_vp.x / _ppu() * 0.98, 1.0, 1.0)
	# Beet-Kinder nicht in x verzerren: Blumen und Erde gegenskaliern.
	var inv := 1.0 / maxf(0.05, _bed.scale.x)
	(_bed.get_node("BlumenRot") as Node3D).scale = Vector3(inv, 1.0, 1.0)
	(_bed.get_node("BlumenGelb") as Node3D).scale = Vector3(inv, 1.0, 1.0)
	gooby.position = Vector3(_wx(_vp.x * 0.82), bed_wy + 0.02, 1.2)
	gooby.scale = Vector3.ONE * clampf(cw * 0.9, 0.5, 1.4)
	gooby.rotation.y = -0.35


## Jeden Frame: Masken/Wasser der Kacheln stellen, Hahn drehen, Sprenger.
func sync(
	tiles: Array, watered: Array[bool], filling: bool, leak_index: int, pulse: float, delta: float
) -> void:
	stage.tick(delta)
	gooby.tick(delta)
	gooby.rotation.z = sin(pulse * 2.3) * 0.03
	for i in _tiles.size():
		var node := _tiles[i]
		if i >= tiles.size():
			node.visible = false
			continue
		node.visible = true
		var tile: Dictionary = tiles[i]
		var mask := PipeFlowLogic.mask_of(str(tile["shape"]), int(tile["rot"]))
		var wet: bool = watered[i]
		for dir in 4:
			var open := (mask & (1 << dir)) != 0
			(node.get_node("Arm%d" % dir) as Node3D).visible = open
			(node.get_node("Wasser%d" % dir) as Node3D).visible = open and wet
		(node.get_node("NabeWasser") as Node3D).visible = wet
	_feed_water.visible = filling
	_drain_water.visible = filling
	_spray.emitting = filling
	if filling:
		_tap_wheel.rotation.y = pulse * 5.0
	_drip.emitting = leak_index >= 0
	if leak_index >= 0 and leak_index < _tiles.size():
		_drip.position = _tiles[leak_index].position + Vector3(0.0, -0.1, 0.3)


func solve_fx(goal_index: int) -> void:
	if goal_index >= 0 and goal_index < _tiles.size():
		Fx.burst(_win_burst, _tiles[goal_index].position + Vector3(0.0, 0.0, 0.4))
	gooby.emote("ecstatic", 1.4)
	gooby.play_for("celebrate", 1.0)
	stage.pulse_glow(0.8)


func leak_fx(index: int) -> void:
	if index >= 0 and index < _tiles.size():
		Fx.burst(_win_burst, _tiles[index].position + Vector3(0.0, -0.2, 0.3))
	gooby.emote("scared", 1.2)


func tap_fx() -> void:
	gooby.emote("happy", 0.4)


## Rohrkachel: Nabe + 4 Richtungs-Arme (N/O/S/W wie PipeFlowLogic.DELTA),
## jeweils mit innenliegendem Wasserkern. sync() schaltet per Maske sichtbar.
func _spawn_tile() -> Node3D:
	var root := Node3D.new()
	var hub := MeshInstance3D.new()
	var hub_mesh := SphereMesh.new()
	hub_mesh.radius = 0.17
	hub_mesh.height = 0.34
	hub_mesh.material = _mat_pipe
	hub.mesh = hub_mesh
	root.add_child(hub)
	var hub_water := MeshInstance3D.new()
	var hub_water_mesh := SphereMesh.new()
	hub_water_mesh.radius = 0.1
	hub_water_mesh.height = 0.2
	hub_water_mesh.material = _mat_water
	hub_water.mesh = hub_water_mesh
	hub_water.name = "NabeWasser"
	hub_water.position.z = 0.09
	hub_water.visible = false
	hub_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(hub_water)
	# DELTA: 0=N, 1=O, 2=S, 3=W (Bildschirm: N zeigt nach oben = +y Welt).
	var dirs: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
	for d in 4:
		var arm := MeshInstance3D.new()
		var arm_mesh := CylinderMesh.new()
		arm_mesh.top_radius = 0.13
		arm_mesh.bottom_radius = 0.13
		arm_mesh.height = 0.5
		arm_mesh.radial_segments = 12
		arm_mesh.material = _mat_pipe
		arm.mesh = arm_mesh
		arm.name = "Arm%d" % d
		arm.position = Vector3(dirs[d].x * 0.25, -dirs[d].y * 0.25, 0.0)
		arm.rotation.z = 0.0 if d % 2 == 0 else PI * 0.5
		root.add_child(arm)
		var water := MeshInstance3D.new()
		var water_mesh := CylinderMesh.new()
		water_mesh.top_radius = 0.07
		water_mesh.bottom_radius = 0.07
		water_mesh.height = 0.52
		water_mesh.radial_segments = 8
		water_mesh.material = _mat_water
		water.mesh = water_mesh
		water.name = "Wasser%d" % d
		water.position = arm.position + Vector3(0.0, 0.0, 0.08)
		water.rotation.z = arm.rotation.z
		water.visible = false
		water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(water)
	return root


## Senkrechter Rohrlauf zwischen zwei Welt-y (layout skaliert/verschiebt ihn).
func _pipe_run(water: bool) -> MeshInstance3D:
	var run := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.07 if water else 0.14
	mesh.bottom_radius = 0.07 if water else 0.14
	mesh.height = 1.0
	mesh.radial_segments = 10
	mesh.material = _mat_water if water else _mat_pipe
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
