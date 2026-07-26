extends Node3D
## ECHTER 3D-DISCO-CLUB für die Tanzparty (FB-4): Noten fallen als leuchtende
## 3D-Kugeln durch drei Glasbahnen auf Trefferringe, darüber dreht eine echte
## Spiegelkugel, Scheinwerferkegel schwenken im Takt, und Gooby (echtes Rig)
## tanzt auf einem pulsierenden Kachelboden. Die Kamera steht frontal auf die
## Notenebene z=0; alle Anker kommen als CANVAS-PIXEL aus der View und werden
## 1:1 in Weltkoordinaten umgerechnet — Timing/Punkte bleiben komplett in
## dance_party.gd/DancePartyLogic.

const Stage3D := preload("res://scripts/minigames/games/_3dc_stage/stage3d.gd")
const Actor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")

const CAM_DIST := 10.0
const HALF_H := 4.2
const LANE_COLORS: Array[Color] = [
	Color(1.0, 0.48, 0.66),
	Color(0.35, 0.79, 0.73),
	Color(1.0, 0.82, 0.4),
]

var stage: Node3D
var gooby: Node3D

var _vp := Vector2(390.0, 844.0)
var _lanes: Array[MeshInstance3D] = []
var _rings: Array[MeshInstance3D] = []
var _cones: Array[MeshInstance3D] = []
var _note_pool: Array[Array] = [[], [], []]
var _ball: Node3D
var _ball_mesh: MeshInstance3D
var _floor_tiles: MultiMeshInstance3D
var _hit_burst: GPUParticles3D
var _encore_light: OmniLight3D
var _hit_ring_r := 0.5


func setup_stage() -> void:
	stage = Stage3D.new()
	add_child(stage)
	(
		stage
		. build(
			{
				# Dunkler Club: Farbhintergrund statt Himmel, kühles Restlicht,
				# der Glow trägt Noten, Ringe und Spiegelkugel.
				"space": true,
				"bg": Color(0.07, 0.05, 0.14),
				"ambient_color": Color(0.5, 0.42, 0.7),
				"ambient": 0.55,
				"sun_dir": Vector3(0.2, -0.9, -0.4),
				"sun_color": Color(0.8, 0.75, 1.0),
				"sun_energy": 0.4,
				"fill_color": Color(0.9, 0.6, 0.9),
				"fill_energy": 0.18,
				"glow": 0.5,
				"glow_threshold": 0.6,
				"shadows": false,
				"far": 80.0,
			}
		)
	)
	_build_club()
	_build_gooby()
	for i in 3:
		var lane := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		quad.material = Fx.glass(Color(LANE_COLORS[i], 0.1), true)
		lane.mesh = quad
		lane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(lane)
		_lanes.append(lane)
		var ring := Fx.ring(0.5, 0.06, LANE_COLORS[i])
		add_child(ring)
		_rings.append(ring)
	_hit_burst = (
		Fx
		. particles(
			{
				"color": Color(1.0, 0.95, 0.7, 0.95),
				"amount": 18,
				"lifetime": 0.5,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(1.5, 3.2),
				"spread": 180.0,
				"gravity": Vector3(0.0, -1.5, 0.0),
				"size": Vector2(0.05, 0.13),
				"additive": true,
			}
		)
	)
	add_child(_hit_burst)
	_encore_light = OmniLight3D.new()
	_encore_light.light_color = Color(1.0, 0.8, 0.4)
	_encore_light.light_energy = 0.0
	_encore_light.omni_range = 14.0
	_encore_light.position = Vector3(0.0, 2.0, 2.0)
	add_child(_encore_light)


func _build_club() -> void:
	# Pulsierender Kachelboden: zwei Violett-Töne im Schachbrett.
	_floor_tiles = MultiMeshInstance3D.new()
	var tile := BoxMesh.new()
	tile.size = Vector3(1.16, 0.1, 1.16)
	tile.material = Fx.flat(Color(0.22, 0.14, 0.34))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = tile
	mm.instance_count = 60
	for i in 60:
		var col := i % 10
		var row := i / 10
		mm.set_instance_transform(
			i,
			Transform3D(
				Basis.IDENTITY, Vector3(-5.4 + float(col) * 1.2, 0.0, -0.6 - float(row) * 1.2)
			)
		)
		mm.set_instance_color(
			i, Color(1.0, 1.0, 1.0) if (col + row) % 2 == 0 else Color(0.55, 0.4, 0.75)
		)
	var tile_mat := tile.material as StandardMaterial3D
	tile_mat.vertex_color_use_as_albedo = true
	_floor_tiles.multimesh = mm
	_floor_tiles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_floor_tiles)
	# Spiegelkugel: metallische Kugel + Aufhängung.
	_ball = Node3D.new()
	add_child(_ball)
	var rod := MeshInstance3D.new()
	var rod_mesh := CylinderMesh.new()
	rod_mesh.top_radius = 0.02
	rod_mesh.bottom_radius = 0.02
	rod_mesh.height = 2.0
	rod_mesh.material = Fx.flat(Color(0.5, 0.5, 0.6))
	rod.mesh = rod_mesh
	rod.position.y = 1.2
	_ball.add_child(rod)
	_ball_mesh = MeshInstance3D.new()
	var ball_sphere := SphereMesh.new()
	ball_sphere.radius = 0.42
	ball_sphere.height = 0.84
	var ball_mat := StandardMaterial3D.new()
	ball_mat.albedo_color = Color(0.85, 0.88, 1.0)
	ball_mat.metallic = 0.9
	ball_mat.roughness = 0.16
	ball_mat.emission_enabled = true
	ball_mat.emission = Color(0.5, 0.55, 0.8)
	ball_mat.emission_energy_multiplier = 0.4
	ball_sphere.material = ball_mat
	_ball_mesh.mesh = ball_sphere
	_ball.add_child(_ball_mesh)
	# Glitzer-Nieten auf der Kugel.
	var stud_mesh := SphereMesh.new()
	stud_mesh.radius = 0.05
	stud_mesh.height = 0.1
	stud_mesh.material = Fx.glow(Color(1.0, 1.0, 1.0), 1.6)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var stud := MeshInstance3D.new()
		stud.mesh = stud_mesh
		stud.position = Vector3(cos(a) * 0.42, sin(a * 2.0) * 0.18, sin(a) * 0.42)
		stud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ball_mesh.add_child(stud)
	# Drei Scheinwerferkegel, die im Takt schwenken.
	for i in 3:
		var cone := MeshInstance3D.new()
		var cone_mesh := CylinderMesh.new()
		cone_mesh.top_radius = 0.1
		cone_mesh.bottom_radius = 1.4
		cone_mesh.height = 9.0
		cone_mesh.radial_segments = 12
		var mat := Fx.glass(Color(LANE_COLORS[i], 0.08), true)
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		cone_mesh.material = mat
		cone.mesh = cone_mesh
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(cone)
		_cones.append(cone)


func _build_gooby() -> void:
	gooby = Actor.new()
	add_child(gooby)
	gooby.mount(1.5)
	gooby.base_emotion = "happy"


## Kamera frontal auf die Notenebene; Anker (Canvas-Pixel) → Welt.
func frame(vp: Vector2) -> void:
	_vp = vp
	stage.apply_size(vp)
	stage.camera.position = Vector3(0.0, 0.0, CAM_DIST)
	stage.camera.rotation = Vector3.ZERO
	stage.set_half_height(HALF_H, CAM_DIST)


## Bahnen, Ringe, Kugel, Boden und Gooby an die 2D-Anker legen.
func layout(lane_xs: Array[float], top_px: float, hit_px: float, span_px: float) -> void:
	var hit_y := _wy(hit_px)
	var top_y := _wy(top_px)
	_hit_ring_r = span_px * 0.34 / _ppu()
	for i in _lanes.size():
		var x := _wx(lane_xs[i])
		var lane := _lanes[i]
		(lane.mesh as QuadMesh).size = Vector2(span_px * 0.92 / _ppu(), top_y - hit_y)
		lane.position = Vector3(x, (top_y + hit_y) * 0.5, -0.3)
		var ring := _rings[i]
		var torus := ring.mesh as TorusMesh
		torus.inner_radius = _hit_ring_r - 0.07
		torus.outer_radius = _hit_ring_r
		ring.position = Vector3(x, hit_y, 0.0)
	# Boden dort, wo Gooby tanzt (85 % Bildhöhe), Kugel am oberen Anker.
	var floor_y := _wy(_vp.y * 0.92)
	_floor_tiles.position = Vector3(0.0, floor_y, 0.0)
	gooby.position = Vector3(0.0, floor_y, 1.2)
	_ball.position = Vector3(0.0, _wy(_vp.y * 0.055), -1.5)
	_encore_light.position = Vector3(0.0, hit_y + 2.0, 2.0)
	for i in _cones.size():
		_cones[i].position = Vector3(_wx(lane_xs[i]), _wy(_vp.y * 0.05), -2.5)


## Jeden Frame: sichtbare Noten (lane, y_px) aus dem Pool stellen, Takt tanzen.
func sync(
	visible_notes: Array[Dictionary],
	flash: Array[float],
	tier: int,
	beat: float,
	spin: float,
	ball_pop: float,
	encore: bool,
	pulse: float,
	delta: float
) -> void:
	stage.tick(delta)
	gooby.tick(delta)
	var used := [0, 0, 0]
	for note in visible_notes:
		var lane := int(note["lane"])
		var node := _take_note(lane)
		used[lane] += 1
		node.visible = true
		node.position = Vector3(_wx(float(note["x"])), _wy(float(note["y"])), 0.0)
		node.scale = Vector3.ONE * (_hit_ring_r / 0.5) * 0.88
		node.rotation.y = pulse * 2.0
	for lane in 3:
		var list: Array = _note_pool[lane]
		for i in range(int(used[lane]), list.size()):
			(list[i] as Node3D).visible = false
	for i in _rings.size():
		var flash_f := clampf(flash[i] / 0.18, 0.0, 1.0)
		_rings[i].scale = Vector3.ONE * (1.0 + flash_f * 0.35)
	# Spiegelkugel: Drehung (Logic-Tempo) + Pop, Kegel schwenken im Takt.
	_ball_mesh.rotation.y = spin
	_ball_mesh.scale = Vector3.ONE * (1.0 + ball_pop * 0.4)
	for i in _cones.size():
		var phase := pulse * 0.7 + float(i) * TAU / 3.0
		_cones[i].rotation.z = sin(phase) * 0.45
	# Gooby tanzt: Hüpfer im Takt, mit der Serienstufe wird alles größer.
	var energy := 1.0 + 0.35 * float(tier)
	gooby.position.y = _floor_tiles.position.y + absf(beat) * 0.14 * energy
	gooby.rotation.y = beat * 0.24 * energy
	gooby.rotation.z = sin(pulse * 2.2) * 0.05 * energy
	if tier >= 2:
		gooby.set_mood("ecstatic")
	else:
		gooby.set_mood("happy")
	_encore_light.light_energy = (1.2 + 0.5 * sin(pulse * 10.0)) if encore else 0.0


func hit_fx(lane_x_px: float, perfect: bool) -> void:
	var at := Vector3(_wx(lane_x_px), _rings[0].position.y, 0.3)
	Fx.burst(_hit_burst, at)
	if perfect:
		stage.pulse_glow(0.5)
	gooby.hop(0.3, 0.16)


func miss_fx() -> void:
	gooby.emote("scared", 0.9)


func encore_fx() -> void:
	gooby.emote("ecstatic", 2.0)
	gooby.play_for("celebrate", 1.2)
	stage.pulse_glow(1.0)


func _take_note(lane: int) -> Node3D:
	var list: Array = _note_pool[lane]
	for node: Node3D in list:
		if not node.visible:
			return node
	var fresh := _spawn_note(lane)
	add_child(fresh)
	list.append(fresh)
	return fresh


func _spawn_note(lane: int) -> Node3D:
	var root := Node3D.new()
	var glow_ball := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.material = Fx.glow(LANE_COLORS[lane], 1.1)
	glow_ball.mesh = mesh
	glow_ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glow_ball)
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.26
	core_mesh.height = 0.52
	core_mesh.material = Fx.glow(Color(1.0, 1.0, 1.0), 1.5)
	core.mesh = core_mesh
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	return root


func _ppu() -> float:
	return _vp.y / (HALF_H * 2.0)


func _wx(px: float) -> float:
	return (px - _vp.x * 0.5) / _ppu()


func _wy(py: float) -> float:
	return (_vp.y * 0.5 - py) / _ppu()
