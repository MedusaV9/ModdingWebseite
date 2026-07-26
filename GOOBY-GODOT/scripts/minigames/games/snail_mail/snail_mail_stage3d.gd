extends Node3D
## ECHTER 3D-GARTEN für die Schneckenpost (FB-4): Häuschen, Bau, Briefkasten,
## Pfützen und Blumen stehen als 3D-Modelle auf einer Sommerwiese, die
## Postschnecke kriecht als 3D-Figur mit Briefumschlag den gemalten Weg ab und
## Gooby (echtes Rig) winkt am Briefkasten. ALLE Anker kommen als CANVAS-PIXEL
## aus der View (project()-Ausgabe) und werden per ground_point-Raycast auf den
## Boden gelegt — der gemalte Weg liegt EXAKT unter dem Finger, Eingabe und
## MECHANIK bleiben zahlengleich in snail_mail.gd/SnailMailLogic.

const Stage3D := preload("res://scripts/minigames/games/_3dc_stage/stage3d.gd")
const Actor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")
const Models := preload("res://scripts/minigames/games/_3dc_stage/models3d.gd")
const DIR := "res://assets/minigames/carrot_catch/"

const MAX_PATH_DOTS := 320
const WALL_CREAM := Color(0.96, 0.88, 0.74)
const ROOF_RED := Color(0.82, 0.4, 0.32)
const ROOF_TARGET := Color(0.93, 0.55, 0.3)

var stage: Node3D
var gooby: Node3D

var _houses: Array[Node3D] = []
var _puddles: Array[Node3D] = []
var _flowers: Array[Node3D] = []
var _post: Node3D
var _snail: Node3D
var _snail_body: Node3D
var _snail_zzz: Label3D
var _envelope: Node3D
var _target_ring: MeshInstance3D
var _target_arrow: MeshInstance3D
var _arrow_base_y := 0.0
var _start_ring: MeshInstance3D
var _field: MeshInstance3D
var _field_rim: MeshInstance3D
var _backdrop: Node3D
var _path_dots: MultiMeshInstance3D
var _splash_burst: GPUParticles3D
var _bloom_burst: GPUParticles3D


func setup_stage() -> void:
	stage = Stage3D.new()
	add_child(stage)
	(
		stage
		. build(
			{
				# Sommergarten am Vormittag, NICHT überbelichtet (satte Wiese).
				"sky_top": Color(0.42, 0.68, 0.9),
				"sky_horizon": Color(0.8, 0.89, 0.82),
				"ground_horizon": Color(0.52, 0.72, 0.42),
				"ground_bottom": Color(0.38, 0.55, 0.3),
				"sun_dir": Vector3(-0.35, -0.8, -0.35),
				"sun_energy": 0.95,
				"ambient": 0.34,
				"fill_energy": 0.22,
				"glow": 0.26,
				"glow_threshold": 0.86,
				"shadow_distance": 34.0,
				"fog": true,
				"fog_color": Color(0.78, 0.88, 0.78),
				"fog_from": 26.0,
				"fog_to": 70.0,
				"far": 120.0,
			}
		)
	)
	add_child(Fx.ground(Vector2(90.0, 70.0), Color(0.44, 0.66, 0.36)))
	# Helle Garten-Insel unterm Spielfeld mit Beet-Einfassung
	# (layout_level passt beide an).
	_field_rim = MeshInstance3D.new()
	var rim_mesh := BoxMesh.new()
	rim_mesh.size = Vector3(1.0, 0.05, 1.0)
	rim_mesh.material = Fx.flat(Color(0.5, 0.38, 0.27))
	_field_rim.mesh = rim_mesh
	_field_rim.position.y = -0.03
	add_child(_field_rim)
	_field = MeshInstance3D.new()
	var field_mesh := BoxMesh.new()
	field_mesh.size = Vector3(1.0, 0.06, 1.0)
	field_mesh.material = Fx.flat(Color(0.5, 0.74, 0.4))
	_field.mesh = field_mesh
	_field.position.y = -0.02
	add_child(_field)
	_build_backdrop()
	_build_pieces()
	_build_gooby()
	_build_fx()


## Zaun + Baumreihe als Kulisse — layout_level schiebt sie hinter das Feld.
func _build_backdrop() -> void:
	_backdrop = Node3D.new()
	add_child(_backdrop)
	var fence_poses: Array = []
	for i in 14:
		fence_poses.append(Transform3D(Basis.IDENTITY, Vector3(-11.7 + float(i) * 1.8, 0.0, 0.0)))
	_backdrop.add_child(Models.swarm(Models.parts(DIR + "fence_simple.glb", 1.8), fence_poses))
	var tree_poses: Array = []
	for i in 6:
		tree_poses.append(
			Transform3D(
				Basis(Vector3.UP, float(i) * 1.3),
				Vector3(-13.0 + float(i) * 5.2, 0.0, -5.0 - 2.5 * float(i % 2))
			)
		)
	_backdrop.add_child(Models.swarm(Models.parts(DIR + "tree_default.glb", 3.4), tree_poses))


func _build_pieces() -> void:
	_post = _spawn_post()
	_post.scale = Vector3.ONE * 1.45
	add_child(_post)
	_snail = _spawn_snail()
	add_child(_snail)
	_target_ring = Fx.ring(0.5, 0.06, Color(1.0, 0.86, 0.32))
	add_child(_target_ring)
	_start_ring = Fx.ring(0.5, 0.05, Color(1.0, 0.98, 0.8))
	add_child(_start_ring)
	_target_arrow = MeshInstance3D.new()
	var arrow_mesh := CylinderMesh.new()
	arrow_mesh.top_radius = 0.0
	arrow_mesh.bottom_radius = 0.2
	arrow_mesh.height = 0.4
	arrow_mesh.radial_segments = 10
	arrow_mesh.material = Fx.glow(Color(1.0, 0.82, 0.3), 0.7)
	_target_arrow.mesh = arrow_mesh
	_target_arrow.rotation.z = PI
	_target_arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_target_arrow)
	# Wegpunkte als EIN MultiMesh (bis zu MAX_PATH_DOTS flache Kugeln).
	_path_dots = MultiMeshInstance3D.new()
	var dot := SphereMesh.new()
	dot.radius = 0.12
	dot.height = 0.12
	dot.material = Fx.glow(Color(0.98, 0.82, 0.48), 0.5)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = dot
	mm.instance_count = MAX_PATH_DOTS
	mm.visible_instance_count = 0
	_path_dots.multimesh = mm
	_path_dots.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_path_dots)


func _build_gooby() -> void:
	gooby = Actor.new()
	add_child(gooby)
	gooby.mount(1.25)
	gooby.base_emotion = "happy"


func _build_fx() -> void:
	_splash_burst = (
		Fx
		. particles(
			{
				"color": Color(0.55, 0.75, 0.95, 0.95),
				"amount": 18,
				"lifetime": 0.55,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(1.0, 2.4),
				"spread": 70.0,
				"size": Vector2(0.05, 0.12),
			}
		)
	)
	add_child(_splash_burst)
	_bloom_burst = (
		Fx
		. particles(
			{
				"color": Color(1.0, 0.72, 0.85, 0.95),
				"amount": 12,
				"lifetime": 0.5,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(0.8, 2.0),
				"spread": 80.0,
				"size": Vector2(0.05, 0.11),
				"additive": true,
			}
		)
	)
	add_child(_bloom_burst)


## Kamera: schräg von oben auf den Garten — die Raycast-Anker halten alle
## Spielfeld-Punkte deckungsgleich mit der 2D-Eingabe.
func frame(vp: Vector2) -> void:
	stage.apply_size(vp)
	stage.camera.position = Vector3(0.0, 10.5, 8.0)
	stage.camera.rotation_degrees = Vector3(-44.0, 0.0, 0.0)
	stage.set_half_height(4.9, 10.0)


## Level-Anker (CANVAS-PIXEL) auf den Boden raycasten. Nach jedem apply_view
## UND jedem Levelwechsel aufrufen.
## houses: [{px, door_px, kind, target}], puddles: [{px, edge_px}],
## flowers: [px], post_px, field: Rect2.
func layout_level(
	houses: Array, puddles: Array, flowers: Array, post_px: Vector2, field: Rect2
) -> void:
	while _houses.size() < houses.size():
		var house := _spawn_house()
		add_child(house)
		_houses.append(house)
	for i in _houses.size():
		var node := _houses[i]
		if i >= houses.size():
			node.visible = false
			continue
		var info: Dictionary = houses[i]
		var at := _ground(info["px"])
		var edge := _ground(Vector2(info["px"]) + Vector2(34.0, 0.0))
		var s := clampf(at.distance_to(edge) * 2.2, 0.9, 3.4)
		node.visible = true
		node.position = at
		node.scale = Vector3.ONE * s
		var burrow := str(info["kind"]) == "burrow"
		(node.get_node("Haus") as Node3D).visible = not burrow
		(node.get_node("Bau") as Node3D).visible = burrow
		var roof := node.get_node("Haus/Dach") as MeshInstance3D
		roof.set_surface_override_material(
			0, Fx.flat(ROOF_TARGET) if bool(info["target"]) else Fx.flat(ROOF_RED)
		)
		if bool(info["target"]):
			var door := _ground(info["door_px"])
			_target_ring.position = door + Vector3(0.0, 0.05, 0.0)
			_arrow_base_y = at.y + s * 1.35
			_target_arrow.position = Vector3(at.x, _arrow_base_y, at.z)
	while _puddles.size() < puddles.size():
		var puddle := _spawn_puddle()
		add_child(puddle)
		_puddles.append(puddle)
	for i in _puddles.size():
		var node := _puddles[i]
		if i >= puddles.size():
			node.visible = false
			continue
		var info: Dictionary = puddles[i]
		var at := _ground(info["px"])
		var rim := _ground(info["edge_px"])
		node.visible = true
		node.position = at + Vector3(0.0, 0.015, 0.0)
		node.scale = Vector3.ONE * maxf(0.2, at.distance_to(rim))
	while _flowers.size() < flowers.size():
		var flower := Models.node(
			DIR + ("flower_redA.glb" if _flowers.size() % 2 == 0 else "flower_yellowA.glb"), 0.55
		)
		add_child(flower)
		_flowers.append(flower)
	for i in _flowers.size():
		var node := _flowers[i]
		if i >= flowers.size():
			node.visible = false
			continue
		node.visible = true
		node.position = _ground(flowers[i])
	var post_at := _ground(post_px)
	# Briefkasten LEICHT versetzt, damit die Schnecke am Start sichtbar bleibt.
	_post.position = post_at + Vector3(0.55, 0.0, -0.35)
	_start_ring.position = post_at + Vector3(0.0, 0.05, 0.0)
	gooby.position = post_at + Vector3(-1.1, 0.0, 0.1)
	gooby.rotation.y = 0.4
	# Garten-Insel unter das Feld legen (Trapez → Box mit Mittelmaßen).
	var tl := _ground(field.position)
	var br := _ground(field.end)
	var tr := _ground(Vector2(field.end.x, field.position.y))
	_field.position = Vector3((tl.x + br.x) * 0.5, -0.02, (tl.z + br.z) * 0.5)
	_field.scale = Vector3(maxf(br.x - tl.x, tr.x - tl.x) + 1.0, 1.0, absf(br.z - tl.z) + 1.0)
	_field_rim.position = Vector3(_field.position.x, -0.03, _field.position.z)
	_field_rim.scale = _field.scale + Vector3(0.9, 0.0, 0.9)
	# Kulisse hinter die Feld-Hinterkante schieben (beide Orientierungen).
	var back_z := minf(tl.z, br.z)
	_backdrop.position = Vector3(_field.position.x, 0.0, back_z - 2.6)


## Jeden Frame: Schnecke, Weg, Ringe und Umschlag stellen.
## path_pts = CANVAS-PIXEL des (Vorschau-)Wegs, snail_px + angle aus der Logic.
func sync(
	snail_px: Vector2,
	snail_angle: float,
	phase: String,
	path_pts: Array[Vector2],
	flower_gone: Array[bool],
	pulse: float,
	delta: float
) -> void:
	stage.tick(delta)
	gooby.tick(delta)
	gooby.rotation.z = sin(pulse * 2.2) * 0.04
	var at := _ground(snail_px)
	var hidden := phase == "retreat"
	_snail.position = at
	_snail.rotation.y = snail_angle
	_snail_body.visible = not hidden
	_snail_zzz.visible = hidden
	_envelope.visible = phase != "beat"
	_snail.scale = Vector3.ONE * (1.25 + 0.06 * sin(pulse * 5.0))
	_start_ring.visible = phase == "draw"
	_start_ring.scale = Vector3.ONE * (1.0 + 0.12 * sin(pulse * 3.0))
	_target_ring.scale = Vector3.ONE * (1.0 + 0.1 * sin(pulse * 3.2))
	_target_arrow.position.y = _arrow_base_y + 0.12 * sin(pulse * 4.0)
	for i in _flowers.size():
		if i < flower_gone.size() and flower_gone[i]:
			_flowers[i].visible = false
	# Wegpunkte auf den Boden raycasten — deckungsgleich mit dem Finger.
	var mm := _path_dots.multimesh
	var count := mini(path_pts.size(), MAX_PATH_DOTS)
	mm.visible_instance_count = count
	for i in count:
		mm.set_instance_transform(
			i, Transform3D(Basis.IDENTITY, _ground(path_pts[i]) + Vector3(0.0, 0.06, 0.0))
		)


func splash_fx(snail_px: Vector2) -> void:
	Fx.burst(_splash_burst, _ground(snail_px) + Vector3(0.0, 0.2, 0.0))
	gooby.emote("scared", 1.2)


func flower_fx(flower_px: Vector2) -> void:
	Fx.burst(_bloom_burst, _ground(flower_px) + Vector3(0.0, 0.25, 0.0))
	gooby.emote("happy", 0.6)


func deliver_fx(door_px: Vector2, dry: bool) -> void:
	Fx.burst(_bloom_burst, _ground(door_px) + Vector3(0.0, 0.3, 0.0))
	if dry:
		gooby.emote("ecstatic", 1.4)
		gooby.play_for("celebrate", 1.0)
		stage.pulse_glow(0.8)
	else:
		gooby.emote("happy", 1.0)


func _ground(px: Vector2) -> Vector3:
	var at: Vector3 = stage.ground_point(px)
	return at


func _spawn_house() -> Node3D:
	var root := Node3D.new()
	var house := Node3D.new()
	house.name = "Haus"
	root.add_child(house)
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.9, 0.6, 0.7)
	body_mesh.material = Fx.flat(WALL_CREAM)
	body.mesh = body_mesh
	body.position.y = 0.3
	house.add_child(body)
	var roof := MeshInstance3D.new()
	var roof_mesh := PrismMesh.new()
	roof_mesh.size = Vector3(1.1, 0.45, 0.9)
	roof_mesh.material = Fx.flat(ROOF_RED)
	roof.mesh = roof_mesh
	roof.name = "Dach"
	roof.position.y = 0.82
	house.add_child(roof)
	var door := MeshInstance3D.new()
	var door_mesh := BoxMesh.new()
	door_mesh.size = Vector3(0.22, 0.34, 0.05)
	door_mesh.material = Fx.flat(Color(0.6, 0.4, 0.3))
	door.mesh = door_mesh
	door.position = Vector3(0.0, 0.17, 0.36)
	house.add_child(door)
	var win_mesh := BoxMesh.new()
	win_mesh.size = Vector3(0.18, 0.16, 0.05)
	win_mesh.material = Fx.glow(Color(0.63, 0.83, 0.94), 0.25)
	for side: float in [-0.28, 0.28]:
		var win := MeshInstance3D.new()
		win.mesh = win_mesh
		win.position = Vector3(side, 0.4, 0.36)
		win.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		house.add_child(win)
	var burrow := Node3D.new()
	burrow.name = "Bau"
	burrow.visible = false
	root.add_child(burrow)
	var dome := MeshInstance3D.new()
	var dome_mesh := SphereMesh.new()
	dome_mesh.radius = 0.5
	dome_mesh.height = 1.0
	dome_mesh.material = Fx.flat(Color(0.52, 0.4, 0.3))
	dome.mesh = dome_mesh
	dome.scale = Vector3(1.0, 0.55, 1.0)
	burrow.add_child(dome)
	var hole := MeshInstance3D.new()
	var hole_mesh := CylinderMesh.new()
	hole_mesh.top_radius = 0.2
	hole_mesh.bottom_radius = 0.2
	hole_mesh.height = 0.1
	hole_mesh.material = Fx.flat(Color(0.2, 0.14, 0.12))
	hole.mesh = hole_mesh
	hole.rotation.x = PI * 0.42
	hole.position = Vector3(0.0, 0.16, 0.44)
	burrow.add_child(hole)
	return root


func _spawn_puddle() -> Node3D:
	var root := Node3D.new()
	var water := MeshInstance3D.new()
	var water_mesh := CylinderMesh.new()
	water_mesh.top_radius = 1.0
	water_mesh.bottom_radius = 1.0
	water_mesh.height = 0.02
	water_mesh.radial_segments = 22
	water_mesh.material = Fx.glass(Color(0.4, 0.63, 0.84, 0.85), true)
	water.mesh = water_mesh
	water.scale = Vector3(1.0, 1.0, 0.76)
	water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(water)
	var shine := MeshInstance3D.new()
	var shine_mesh := TorusMesh.new()
	shine_mesh.inner_radius = 0.3
	shine_mesh.outer_radius = 0.38
	shine_mesh.material = Fx.glow(Color(0.9, 0.96, 1.0), 0.4)
	shine.mesh = shine_mesh
	shine.position = Vector3(-0.24, 0.02, -0.16)
	shine.scale = Vector3(0.5, 0.3, 0.4)
	shine.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shine)
	return root


func _spawn_post() -> Node3D:
	var root := Node3D.new()
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.04
	pole_mesh.bottom_radius = 0.05
	pole_mesh.height = 0.6
	pole_mesh.material = Fx.flat(Color(0.55, 0.4, 0.28))
	pole.mesh = pole_mesh
	pole.position.y = 0.3
	root.add_child(pole)
	var box := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = Vector3(0.34, 0.26, 0.28)
	box_mesh.material = Fx.flat(Color(0.36, 0.6, 0.86))
	box.mesh = box_mesh
	box.position.y = 0.72
	root.add_child(box)
	var slot := MeshInstance3D.new()
	var slot_mesh := BoxMesh.new()
	slot_mesh.size = Vector3(0.2, 0.03, 0.02)
	slot_mesh.material = Fx.flat(Color(0.95, 0.97, 1.0))
	slot.mesh = slot_mesh
	slot.position = Vector3(0.0, 0.76, 0.15)
	slot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(slot)
	return root


## Postschnecke: Fuß + Augenstiele (Körper), Spiralhaus, Umschlag obendrauf.
## Bei Drehung 0 schaut sie Richtung +X (rotation.y = Logik-Winkel).
func _spawn_snail() -> Node3D:
	var root := Node3D.new()
	_snail_body = Node3D.new()
	root.add_child(_snail_body)
	var skin := Fx.flat(Color(0.98, 0.86, 0.72))
	var foot := MeshInstance3D.new()
	var foot_mesh := CapsuleMesh.new()
	foot_mesh.radius = 0.14
	foot_mesh.height = 0.62
	foot_mesh.material = skin
	foot.mesh = foot_mesh
	foot.rotation.z = PI * 0.5
	foot.position = Vector3(0.08, 0.12, 0.0)
	_snail_body.add_child(foot)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.12
	head_mesh.height = 0.24
	head_mesh.material = skin
	head.mesh = head_mesh
	head.position = Vector3(0.34, 0.2, 0.0)
	_snail_body.add_child(head)
	var eye_stalk := CylinderMesh.new()
	eye_stalk.top_radius = 0.02
	eye_stalk.bottom_radius = 0.02
	eye_stalk.height = 0.18
	eye_stalk.material = skin
	var eye_ball := SphereMesh.new()
	eye_ball.radius = 0.04
	eye_ball.height = 0.08
	eye_ball.material = Fx.flat(Color(0.25, 0.18, 0.16))
	for side: float in [-1.0, 1.0]:
		var stalk := MeshInstance3D.new()
		stalk.mesh = eye_stalk
		stalk.position = Vector3(0.4, 0.34, side * 0.06)
		stalk.rotation.x = side * 0.3
		_snail_body.add_child(stalk)
		var eye := MeshInstance3D.new()
		eye.mesh = eye_ball
		eye.position = Vector3(0.42, 0.44, side * 0.09)
		_snail_body.add_child(eye)
	var shell := MeshInstance3D.new()
	var shell_mesh := SphereMesh.new()
	shell_mesh.radius = 0.24
	shell_mesh.height = 0.48
	shell_mesh.material = Fx.flat(Color(0.78, 0.5, 0.26))
	shell.mesh = shell_mesh
	shell.position = Vector3(-0.1, 0.3, 0.0)
	root.add_child(shell)
	var spiral := MeshInstance3D.new()
	var spiral_mesh := TorusMesh.new()
	spiral_mesh.inner_radius = 0.1
	spiral_mesh.outer_radius = 0.18
	spiral_mesh.material = Fx.flat(Color(0.66, 0.42, 0.24))
	spiral.mesh = spiral_mesh
	spiral.rotation.x = PI * 0.5
	spiral.position = Vector3(-0.1, 0.3, 0.13)
	spiral.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(spiral)
	_envelope = Node3D.new()
	root.add_child(_envelope)
	var paper := MeshInstance3D.new()
	var paper_mesh := BoxMesh.new()
	paper_mesh.size = Vector3(0.3, 0.2, 0.03)
	paper_mesh.material = Fx.flat(Color(1.0, 0.98, 0.9))
	paper.mesh = paper_mesh
	paper.position = Vector3(-0.1, 0.64, 0.0)
	paper.rotation.y = PI * 0.5
	_envelope.add_child(paper)
	var seal := MeshInstance3D.new()
	var seal_mesh := SphereMesh.new()
	seal_mesh.radius = 0.035
	seal_mesh.height = 0.07
	seal_mesh.material = Fx.glow(Color(0.93, 0.36, 0.48), 0.4)
	seal.mesh = seal_mesh
	seal.position = Vector3(-0.1, 0.64, 0.0)
	_envelope.add_child(seal)
	_snail_zzz = Label3D.new()
	_snail_zzz.text = "zZ"
	_snail_zzz.font_size = 120
	_snail_zzz.pixel_size = 0.004
	_snail_zzz.modulate = Color(0.4, 0.45, 0.6, 0.9)
	_snail_zzz.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_snail_zzz.no_depth_test = true
	_snail_zzz.position = Vector3(0.0, 0.75, 0.0)
	_snail_zzz.visible = false
	root.add_child(_snail_zzz)
	return root
