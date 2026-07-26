extends Node3D
## ECHTE 3D-GARTENWIESE für die Karottenwache (FB-4): neun Erdhügel auf einer
## Sommerwiese, aus denen 3D-Maulwürfe (samt Krönchen-König) auftauchen, hinten
## Zaun, Bäume und das Karottenbeet, Gooby (echtes Rig) hält daneben Wache.
## Die Hügel werden per ground_point-Raycast EXAKT unter die 2D-Tap-Rechtecke
## der View gelegt — Eingabe und Trefferflächen bleiben zahlengleich. Die
## MECHANIK bleibt komplett in carrot_guard.gd/CarrotGuardLogic.

const Stage3D := preload("res://scripts/minigames/games/_3dc_stage/stage3d.gd")
const Actor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")
const Models := preload("res://scripts/minigames/games/_3dc_stage/models3d.gd")
const DIR := "res://assets/minigames/carrot_catch/"

const MOUND := Color(0.66, 0.47, 0.31)
const MOUND_DARK := Color(0.4, 0.29, 0.19)
const MOLE_FUR := Color(0.48, 0.39, 0.33)
const KING_FUR := Color(0.42, 0.31, 0.48)

var stage: Node3D
var gooby: Node3D

var _mounds: Array[Node3D] = []
var _mound_pos: Array[Vector3] = []
var _mound_r: Array[float] = []
var _mole_pool: Array[Node3D] = []
var _king_node: Node3D
var _king_pips: Array[MeshInstance3D] = []
var _bed: Node3D
var _bed_carrots: Array[Node3D] = []
var _dirt_burst: GPUParticles3D
var _star_burst: GPUParticles3D


func setup_stage(total_carrots: int) -> void:
	stage = Stage3D.new()
	add_child(stage)
	(
		stage
		. build(
			{
				# Gartenlicht am Nachmittag, NICHT überbelichtet.
				"sky_top": Color(0.52, 0.76, 0.93),
				"sky_horizon": Color(0.87, 0.93, 0.9),
				"ground_horizon": Color(0.64, 0.8, 0.52),
				"ground_bottom": Color(0.46, 0.64, 0.38),
				"sun_dir": Vector3(-0.35, -0.85, -0.3),
				"sun_energy": 0.85,
				"ambient": 0.56,
				"fill_energy": 0.22,
				"glow": 0.26,
				"glow_threshold": 0.86,
				"shadow_distance": 30.0,
				"fog": true,
				"fog_color": Color(0.85, 0.92, 0.88),
				"fog_from": 26.0,
				"fog_to": 70.0,
				"far": 110.0,
			}
		)
	)
	add_child(Fx.ground(Vector2(80.0, 60.0), Color(0.55, 0.76, 0.42)))
	_build_backdrop()
	_build_bed(total_carrots)
	_build_gooby()
	_build_fx()
	_king_node = _spawn_mole(true)
	_king_node.visible = false
	add_child(_king_node)


func _build_backdrop() -> void:
	# Gemähte Bahnen: dunklere Streifen quer über die Wiese.
	var stripes := MultiMeshInstance3D.new()
	var stripe_mesh := PlaneMesh.new()
	stripe_mesh.size = Vector2(60.0, 2.6)
	stripe_mesh.material = Fx.flat(Color(0.5, 0.72, 0.38))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = stripe_mesh
	mm.instance_count = 5
	for i in 5:
		mm.set_instance_transform(
			i, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.012, -18.0 + float(i) * 5.4))
		)
	stripes.multimesh = mm
	stripes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stripes)
	# Zaun + Baumreihe am Horizont.
	var fence_poses: Array = []
	for i in 14:
		fence_poses.append(Transform3D(Basis.IDENTITY, Vector3(-11.7 + float(i) * 1.8, 0.0, -17.0)))
	add_child(Models.swarm(Models.parts(DIR + "fence_simple.glb", 1.8), fence_poses))
	var tree_poses: Array = []
	for i in 5:
		tree_poses.append(
			Transform3D(
				Basis(Vector3.UP, float(i) * 1.3),
				Vector3(-12.0 + float(i) * 6.0, 0.0, -20.0 - 2.0 * float(i % 2))
			)
		)
	add_child(Models.swarm(Models.parts(DIR + "tree_default.glb", 4.2), tree_poses))
	# Blumentupfer rund um das Spielfeld.
	var reds: Array = []
	var yellows: Array = []
	for i in 10:
		var pose := Transform3D(
			Basis.IDENTITY,
			Vector3(
				-8.0 + float(i) * 1.8, 0.0, (-13.5 if i % 2 == 0 else -14.8) + 0.7 * float(i % 3)
			)
		)
		if i % 2 == 0:
			reds.append(pose)
		else:
			yellows.append(pose)
	add_child(Models.swarm(Models.parts(DIR + "flower_redA.glb", 0.5), reds))
	add_child(Models.swarm(Models.parts(DIR + "flower_yellowA.glb", 0.5), yellows))


func _build_bed(total: int) -> void:
	_bed = Node3D.new()
	add_child(_bed)
	var soil := MeshInstance3D.new()
	var soil_mesh := BoxMesh.new()
	soil_mesh.size = Vector3(float(total) * 0.62 + 0.6, 0.22, 1.0)
	soil_mesh.material = Fx.flat(Color(0.45, 0.33, 0.22))
	soil.mesh = soil_mesh
	soil.position.y = 0.11
	_bed.add_child(soil)
	for i in total:
		var crop := Models.node(DIR + "crop_carrot.glb", 0.55)
		crop.position = Vector3((float(i) - float(total - 1) * 0.5) * 0.62, 0.2, 0.0)
		_bed.add_child(crop)
		_bed_carrots.append(crop)


func _build_gooby() -> void:
	gooby = Actor.new()
	add_child(gooby)
	gooby.mount(1.15)
	gooby.base_emotion = "happy"


func _build_fx() -> void:
	_dirt_burst = (
		Fx
		. particles(
			{
				"color": Color(0.55, 0.42, 0.28, 0.9),
				"amount": 14,
				"lifetime": 0.5,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(1.2, 2.6),
				"spread": 60.0,
				"size": Vector2(0.06, 0.16),
			}
		)
	)
	add_child(_dirt_burst)
	_star_burst = (
		Fx
		. particles(
			{
				"color": Color(1.0, 0.9, 0.5, 0.95),
				"amount": 16,
				"lifetime": 0.55,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(1.4, 3.0),
				"spread": 80.0,
				"size": Vector2(0.06, 0.15),
				"additive": true,
			}
		)
	)
	add_child(_star_burst)


## Kamera: schräg von oben auf das Hügelfeld — flach genug, dass über der
## obersten Hügelreihe Beet, Zaun und Bäume als Kulisse ins Bild kommen.
func frame(vp: Vector2) -> void:
	stage.apply_size(vp)
	stage.camera.position = Vector3(0.0, 10.5, 8.0)
	stage.camera.rotation_degrees = Vector3(-40.0, 0.0, 0.0)
	stage.set_half_height(4.9, 10.0)


## Hügel per Raycast EXAKT unter die 2D-Tap-Rechtecke legen; Beet und Gooby
## richten sich am Feldrand aus. Nach jedem apply_view neu aufrufen.
func layout(holes: Array[Rect2]) -> void:
	while _mounds.size() < holes.size():
		var mound := _spawn_mound()
		add_child(mound)
		_mounds.append(mound)
	_mound_pos.clear()
	_mound_r.clear()
	var lo := Vector3(INF, 0.0, INF)
	var hi := Vector3(-INF, 0.0, -INF)
	for i in holes.size():
		var rect := holes[i]
		var center: Vector3 = stage.ground_point(rect.get_center())
		var edge: Vector3 = stage.ground_point(rect.get_center() + Vector2(rect.size.x * 0.5, 0.0))
		var radius := clampf(center.distance_to(edge) * 0.72, 0.4, 4.0)
		_mound_pos.append(center)
		_mound_r.append(radius)
		_mounds[i].position = center
		_mounds[i].scale = Vector3.ONE * radius
		lo.x = minf(lo.x, center.x)
		lo.z = minf(lo.z, center.z)
		hi.x = maxf(hi.x, center.x)
		hi.z = maxf(hi.z, center.z)
	# Beet hinter der letzten Hügelreihe, Gooby wacht daneben — beide IM Bild
	# (das Hügelfeld füllt die Breite, rechts außen wäre unsichtbar).
	var back_r := _mound_r[0] if not _mound_r.is_empty() else 1.0
	_bed.position = Vector3((lo.x + hi.x) * 0.5 - back_r * 1.4, 0.0, lo.z - back_r * 2.4)
	_bed.scale = Vector3.ONE * clampf(back_r * 0.9, 0.6, 2.4)
	gooby.position = Vector3(hi.x * 0.72, 0.0, lo.z - back_r * 2.0)
	gooby.scale = Vector3.ONE * clampf(back_r * 0.95, 0.5, 2.2)
	gooby.rotation.y = -0.35


## Jeden Frame: Maulwürfe aus dem Pool in ihre Löcher stellen.
func sync(
	moles: Array[Dictionary], king: Dictionary, carrots: int, pulse: float, delta: float
) -> void:
	stage.tick(delta)
	gooby.tick(delta)
	gooby.rotation.z = sin(pulse * 2.6) * 0.03
	for i in _bed_carrots.size():
		_bed_carrots[i].visible = i < carrots
	while _mole_pool.size() < moles.size():
		var mole := _spawn_mole(false)
		add_child(mole)
		_mole_pool.append(mole)
	for i in _mole_pool.size():
		var node := _mole_pool[i]
		if i >= moles.size():
			node.visible = false
			continue
		var mole: Dictionary = moles[i]
		_pose_mole(node, int(mole["hole"]), float(mole["up"]), pulse)
	_king_node.visible = not king.is_empty()
	if _king_node.visible:
		_pose_mole(_king_node, int(king["hole"]), float(king["up"]), pulse)
		var hp := int(king.get("hp", 0))
		for i in _king_pips.size():
			_king_pips[i].visible = i < hp


func _pose_mole(node: Node3D, hole: int, up: float, pulse: float) -> void:
	if hole < 0 or hole >= _mound_pos.size():
		node.visible = false
		return
	var radius := _mound_r[hole]
	node.visible = true
	var rise := lerpf(-1.5, 0.62, clampf(up, 0.0, 1.0))
	node.position = _mound_pos[hole] + Vector3(0.0, rise * radius, 0.0)
	node.scale = Vector3.ONE * radius
	node.rotation.y = sin(pulse * 3.0 + float(hole)) * 0.14


func _spawn_mound() -> Node3D:
	var root := Node3D.new()
	var hill := MeshInstance3D.new()
	var hill_mesh := SphereMesh.new()
	hill_mesh.radius = 1.0
	hill_mesh.height = 2.0
	hill_mesh.material = Fx.flat(MOUND)
	hill.mesh = hill_mesh
	hill.scale = Vector3(1.0, 0.34, 1.0)
	root.add_child(hill)
	var socket := MeshInstance3D.new()
	var socket_mesh := CylinderMesh.new()
	socket_mesh.top_radius = 0.52
	socket_mesh.bottom_radius = 0.52
	socket_mesh.height = 0.3
	socket_mesh.radial_segments = 14
	socket_mesh.material = Fx.flat(MOUND_DARK)
	socket.mesh = socket_mesh
	socket.position.y = 0.24
	socket.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(socket)
	return root


func _spawn_mole(is_king: bool) -> Node3D:
	var root := Node3D.new()
	var fur := KING_FUR if is_king else MOLE_FUR
	var fur_mat := Fx.flat(fur)
	var body := MeshInstance3D.new()
	var body_mesh := CapsuleMesh.new()
	body_mesh.radius = 0.42 if not is_king else 0.5
	body_mesh.height = 1.1 if not is_king else 1.3
	body_mesh.material = fur_mat
	body.mesh = body_mesh
	body.position.y = 0.3
	root.add_child(body)
	var snout := MeshInstance3D.new()
	var snout_mesh := SphereMesh.new()
	snout_mesh.radius = 0.2
	snout_mesh.height = 0.4
	snout_mesh.material = Fx.flat(Color(0.85, 0.72, 0.64))
	snout.mesh = snout_mesh
	snout.position = Vector3(0.0, 0.52, 0.36)
	root.add_child(snout)
	var nose := MeshInstance3D.new()
	var nose_mesh := SphereMesh.new()
	nose_mesh.radius = 0.09
	nose_mesh.height = 0.18
	nose_mesh.material = Fx.flat(Color(0.29, 0.23, 0.21))
	nose.mesh = nose_mesh
	nose.position = Vector3(0.0, 0.56, 0.52)
	root.add_child(nose)
	var eye_mesh := SphereMesh.new()
	eye_mesh.radius = 0.07
	eye_mesh.height = 0.14
	eye_mesh.material = Fx.flat(Color(0.12, 0.1, 0.12))
	var ear_mesh := SphereMesh.new()
	ear_mesh.radius = 0.13
	ear_mesh.height = 0.26
	ear_mesh.material = Fx.flat(fur.darkened(0.2))
	for side: float in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = eye_mesh
		eye.position = Vector3(side * 0.17, 0.72, 0.34)
		root.add_child(eye)
		var ear := MeshInstance3D.new()
		ear.mesh = ear_mesh
		ear.position = Vector3(side * 0.32, 0.86, 0.05)
		root.add_child(ear)
	if is_king:
		_add_crown(root)
	return root


func _add_crown(root: Node3D) -> void:
	var band := MeshInstance3D.new()
	var band_mesh := CylinderMesh.new()
	band_mesh.top_radius = 0.24
	band_mesh.bottom_radius = 0.28
	band_mesh.height = 0.16
	band_mesh.material = Fx.glow(Color(1.0, 0.82, 0.3), 0.5)
	band.mesh = band_mesh
	band.position.y = 1.06
	root.add_child(band)
	var spike_mesh := CylinderMesh.new()
	spike_mesh.top_radius = 0.0
	spike_mesh.bottom_radius = 0.06
	spike_mesh.height = 0.2
	spike_mesh.radial_segments = 6
	spike_mesh.material = Fx.glow(Color(1.0, 0.82, 0.3), 0.5)
	for i in 4:
		var a := TAU * float(i) / 4.0
		var spike := MeshInstance3D.new()
		spike.mesh = spike_mesh
		spike.position = Vector3(cos(a) * 0.2, 1.2, sin(a) * 0.2)
		root.add_child(spike)
	# HP-Punkte über der Krone (sichtbare Anzahl = restliche Taps).
	var pip_mesh := SphereMesh.new()
	pip_mesh.radius = 0.09
	pip_mesh.height = 0.18
	pip_mesh.material = Fx.glow(Color(0.95, 0.35, 0.3), 1.2)
	for i in 3:
		var pip := MeshInstance3D.new()
		pip.mesh = pip_mesh
		pip.position = Vector3((float(i) - 1.0) * 0.26, 1.5, 0.0)
		pip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(pip)
		_king_pips.append(pip)


func bonk_fx(hole: int) -> void:
	if hole < 0 or hole >= _mound_pos.size():
		return
	Fx.burst(_star_burst, _mound_pos[hole] + Vector3(0.0, _mound_r[hole] * 0.8, 0.0))
	gooby.emote("happy", 0.6)
	gooby.swing(0.35, 34.0)


func steal_fx(hole: int) -> void:
	if hole < 0 or hole >= _mound_pos.size():
		return
	Fx.burst(_dirt_burst, _mound_pos[hole] + Vector3(0.0, _mound_r[hole] * 0.4, 0.0))
	gooby.emote("scared", 1.2)


func king_hit_fx(hole: int) -> void:
	if hole < 0 or hole >= _mound_pos.size():
		return
	Fx.burst(_star_burst, _mound_pos[hole] + Vector3(0.0, _mound_r[hole] * 1.0, 0.0))


func king_down_fx(hole: int) -> void:
	king_hit_fx(hole)
	gooby.emote("ecstatic", 1.4)
	gooby.play_for("celebrate", 1.0)
	stage.pulse_glow(0.9)
