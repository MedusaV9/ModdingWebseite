extends Node3D
## ECHTE 3D-Heckenlandschaft für den Hasenhüpfer (FB-4): Gooby (echtes Rig)
## flattert vor Parallax-Hügeln durch Heckensäulen mit Blätterkronen, Münzen
## drehen sich als Goldtaler. Die Kamera steht EXAKT so, dass die sichtbare
## Weltbreite der 2D-Mathematik des Spiels entspricht (set_half_height auf die
## Spielebene z=0) — Spawn-/Kollision[szahlen] bleiben unangetastet.
## Die MECHANIK bleibt komplett in bunny_hop.gd/BunnyHopLogic.

const Stage3D := preload("res://scripts/minigames/games/_3dc_stage/stage3d.gd")
const Actor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")

## Halbe Bildhöhe in Weltmetern = (2·WORLD_HALF_H + 0.6) / 2 der 2D-Sicht.
const HALF_H := 4.2
const CAM_DIST := 10.0
const PILLAR_POOL := 8
const COIN_POOL := 6
const HEDGE := Color(0.44, 0.68, 0.32)
const HEDGE_PALE := Color(0.6, 0.73, 0.54)
const LEAF := Color(0.36, 0.63, 0.25)
const LEAF_PALE := Color(0.56, 0.7, 0.5)

var stage: Node3D
var gooby: Node3D

var _floor_y := -3.1
var _pillars: Array[Dictionary] = []
var _coins: Array[MeshInstance3D] = []
var _hedge_mat: StandardMaterial3D
var _hedge_pale_mat: StandardMaterial3D
var _leaf_mat: StandardMaterial3D
var _leaf_pale_mat: StandardMaterial3D
var _tufts: MultiMeshInstance3D
var _hills_near: MultiMeshInstance3D
var _hills_far: MultiMeshInstance3D
var _clouds: MultiMeshInstance3D
var _shadow: MeshInstance3D
var _burst: GPUParticles3D


func setup_stage(floor_y: float) -> void:
	_floor_y = floor_y
	stage = Stage3D.new()
	add_child(stage)
	(
		stage
		. build(
			{
				# Frischer Frühlingstag — NICHT überbelichten (bekannte Falle):
				# Sonne fast senkrecht, damit die Heckensäulen kompakte
				# Schatten werfen statt Riesenbalken über die Wiese zu legen.
				"sky_top": Color(0.52, 0.76, 0.93),
				"sky_horizon": Color(0.85, 0.93, 0.96),
				"ground_horizon": Color(0.6, 0.79, 0.48),
				"ground_bottom": Color(0.42, 0.6, 0.34),
				"sun_dir": Vector3(-0.18, -0.92, -0.28),
				"sun_energy": 0.85,
				"ambient": 0.55,
				"fill_energy": 0.24,
				"glow": 0.28,
				"glow_threshold": 0.85,
				"shadow_distance": 26.0,
				"fog": true,
				"fog_color": Color(0.82, 0.91, 0.94),
				"fog_from": 18.0,
				"fog_to": 48.0,
				"far": 90.0,
			}
		)
	)
	_hedge_mat = Fx.flat(HEDGE)
	_hedge_pale_mat = Fx.flat(HEDGE_PALE)
	_leaf_mat = Fx.flat(LEAF)
	_leaf_pale_mat = Fx.flat(LEAF_PALE)
	_build_backdrop()
	_build_pools()
	_build_gooby()


func _build_backdrop() -> void:
	# Wiese: statisch, die Bewegung erzählen Grasbüschel + Hügel + Säulen.
	add_child(Fx.ground(Vector2(60.0, 40.0), Color(0.49, 0.74, 0.36), _floor_y))
	var strip := MeshInstance3D.new()
	var strip_mesh := BoxMesh.new()
	strip_mesh.size = Vector3(60.0, 0.1, 0.5)
	strip_mesh.material = Fx.flat(Color(0.43, 0.71, 0.31))
	strip.mesh = strip_mesh
	strip.position = Vector3(0.0, _floor_y, 0.9)
	add_child(strip)
	# Grasbüschel als EINE MultiMesh, die mit dem Scroll durchläuft.
	_tufts = MultiMeshInstance3D.new()
	var tuft_mesh := CylinderMesh.new()
	tuft_mesh.top_radius = 0.0
	tuft_mesh.bottom_radius = 0.055
	tuft_mesh.height = 0.3
	tuft_mesh.radial_segments = 5
	tuft_mesh.material = Fx.flat(Color(0.37, 0.64, 0.27))
	var tuft_mm := MultiMesh.new()
	tuft_mm.transform_format = MultiMesh.TRANSFORM_3D
	tuft_mm.mesh = tuft_mesh
	tuft_mm.instance_count = 30
	for i in 30:
		tuft_mm.set_instance_transform(
			i,
			Transform3D(
				Basis.IDENTITY,
				Vector3(-10.0 + float(i % 15) * 1.4, _floor_y + 0.14, 0.6 if i < 15 else 1.6)
			)
		)
	_tufts.multimesh = tuft_mm
	add_child(_tufts)
	_hills_near = _hill_row(1.2, Color(0.47, 0.7, 0.42), -9.0, 2.8, 10)
	_hills_far = _hill_row(2.0, Color(0.58, 0.78, 0.52), -16.0, 4.6, 8)
	# Wolken: weiche Billboards weit hinten.
	_clouds = MultiMeshInstance3D.new()
	var cloud_mesh := SphereMesh.new()
	cloud_mesh.radius = 1.0
	cloud_mesh.height = 1.1
	var cloud_mat := Fx.flat(Color(1.0, 1.0, 1.0, 0.92))
	cloud_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	cloud_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cloud_mesh.material = cloud_mat
	var cloud_mm := MultiMesh.new()
	cloud_mm.transform_format = MultiMesh.TRANSFORM_3D
	cloud_mm.mesh = cloud_mesh
	cloud_mm.instance_count = 4
	for i in 4:
		var b := Basis.IDENTITY.scaled(Vector3(1.7, 0.62, 1.0) * (0.8 + 0.3 * float(i % 2)))
		cloud_mm.set_instance_transform(
			i, Transform3D(b, Vector3(-8.0 + float(i) * 5.0, 2.6 + 0.7 * float(i % 3), -18.0))
		)
	_clouds.multimesh = cloud_mm
	_clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_clouds)
	# Sonne als Glühscheibe rechts oben, weit hinten.
	var sun := MeshInstance3D.new()
	var sun_mesh := SphereMesh.new()
	sun_mesh.radius = 1.5
	sun_mesh.height = 3.0
	sun_mesh.material = Fx.glow(Color(1.0, 0.87, 0.5), 1.7)
	sun.mesh = sun_mesh
	sun.position = Vector3(9.0, 6.5, -24.0)
	sun.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sun)


func _hill_row(
	radius: float, tint: Color, z: float, step: float, count: int
) -> MultiMeshInstance3D:
	var row := MultiMeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.material = Fx.flat(tint)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	for i in count:
		var wobble := 0.85 + 0.3 * float(i % 3) * 0.5
		var b := Basis.IDENTITY.scaled(Vector3(1.6, wobble, 1.0))
		mm.set_instance_transform(
			i, Transform3D(b, Vector3(float(i - count / 2) * step, _floor_y + radius * 0.24, z))
		)
	row.multimesh = mm
	row.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(row)
	return row


func _build_pools() -> void:
	for i in PILLAR_POOL:
		var node := Node3D.new()
		node.visible = false
		add_child(node)
		var top := _hedge_box()
		node.add_child(top)
		var bottom := _hedge_box()
		node.add_child(bottom)
		var crown_top := _crown()
		node.add_child(crown_top)
		var crown_bottom := _crown()
		node.add_child(crown_bottom)
		(
			_pillars
			. append(
				{
					"node": node,
					"top": top,
					"bottom": bottom,
					"crown_top": crown_top,
					"crown_bottom": crown_bottom,
				}
			)
		)
	for i in COIN_POOL:
		var coin := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.24
		mesh.bottom_radius = 0.24
		mesh.height = 0.07
		mesh.radial_segments = 18
		mesh.material = Fx.glow(Color(1.0, 0.8, 0.32), 0.75)
		coin.mesh = mesh
		coin.rotation_degrees.x = 90.0
		coin.visible = false
		add_child(coin)
		_coins.append(coin)


func _hedge_box() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3.ONE
	mi.mesh = mesh
	mi.material_override = _hedge_mat
	return mi


func _crown() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mi.mesh = mesh
	mi.material_override = _leaf_mat
	return mi


func _build_gooby() -> void:
	gooby = Actor.new()
	add_child(gooby)
	gooby.mount(0.95)
	gooby.base_emotion = "happy"
	_shadow = Fx.blob_shadow(0.5, 0.28)
	_shadow.position.y = _floor_y + 0.02
	add_child(_shadow)
	_burst = (
		Fx
		. particles(
			{
				"color": Color(1.0, 0.9, 0.6, 0.9),
				"amount": 14,
				"lifetime": 0.5,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(1.0, 2.4),
				"spread": 60.0,
				"size": Vector2(0.06, 0.14),
				"additive": true,
			}
		)
	)
	add_child(_burst)


## Kamera frontal auf die Spielebene z=0: halbe Bildhöhe = HALF_H Meter, damit
## die sichtbare Weltbreite EXAKT der 2D-Rechnung des Spiels entspricht.
func apply_size(size: Vector2) -> void:
	stage.apply_size(size)
	stage.camera.position = Vector3(0.0, 0.4, CAM_DIST)
	stage.camera.rotation = Vector3.ZERO
	stage.set_half_height(HALF_H, CAM_DIST)


## Linke Bildkante in Welt-x (Spiel rechnet x ab linkem Rand).
func _origin_x() -> float:
	return -stage.half_width()


## Jeden Frame: Säulen/Münzen aus den Spieldaten stellen, Gooby posen.
func sync(
	pillars: Array[Dictionary],
	coins: Array[Dictionary],
	gooby_world_x: float,
	gooby_y: float,
	gooby_vy: float,
	scroll: float,
	half_w: float,
	gap_margin: float,
	pulse: float,
	delta: float
) -> void:
	stage.tick(delta)
	gooby.tick(delta)
	var ox := _origin_x()
	gooby.position = Vector3(ox + gooby_world_x, gooby_y + 0.4, 0.0)
	gooby.rotation.z = clampf(gooby_vy * 0.08, -0.4, 0.4)
	_shadow.position.x = gooby.position.x
	var drop := clampf(1.0 - (gooby_y - _floor_y) / 6.0, 0.3, 1.0)
	_shadow.scale = Vector3.ONE * drop
	for i in _pillars.size():
		var slot: Dictionary = _pillars[i]
		var node: Node3D = slot["node"]
		if i >= pillars.size():
			node.visible = false
			continue
		var pillar: Dictionary = pillars[i]
		node.visible = true
		node.position.x = ox + float(pillar["x"]) - scroll
		var gap_top := float(pillar["gapCenterY"]) + float(pillar["gapHeight"]) * 0.5
		var gap_bottom := float(pillar["gapCenterY"]) - float(pillar["gapHeight"]) * 0.5
		var passed := bool(pillar["passed"])
		_pose_column(slot["top"], gap_top + gap_margin, HALF_H + 1.2, half_w, passed)
		_pose_column(slot["bottom"], _floor_y, gap_bottom - gap_margin, half_w, passed)
		_pose_crown(slot["crown_top"], gap_top + gap_margin, half_w, passed)
		_pose_crown(slot["crown_bottom"], gap_bottom - gap_margin, half_w, passed)
	for i in _coins.size():
		var coin_node := _coins[i]
		if i >= coins.size() or bool(coins[i]["taken"]):
			coin_node.visible = false
			continue
		coin_node.visible = true
		coin_node.position = Vector3(
			ox + float(coins[i]["x"]) - scroll, float(coins[i]["y"]) + 0.4, 0.3
		)
		coin_node.rotation.y = pulse * 3.2
	# Parallax: Büschel voll, Hügel gebremst, Wolken hauchzart.
	_tufts.position.x = -fposmod(scroll, 1.4)
	_hills_near.position.x = -fposmod(scroll * 0.34, 2.8)
	_hills_far.position.x = -fposmod(scroll * 0.14, 4.6)
	_clouds.position.x = -fposmod(scroll * 0.05, 5.0)


func _pose_column(
	column: MeshInstance3D, from_y: float, to_y: float, half_w: float, passed: bool
) -> void:
	var height := to_y - from_y
	if height <= 0.02:
		column.visible = false
		return
	column.visible = true
	column.scale = Vector3(half_w * 2.0, height, 0.9)
	column.position.y = (from_y + to_y) * 0.5
	column.material_override = _hedge_pale_mat if passed else _hedge_mat


func _pose_crown(crown: MeshInstance3D, at_y: float, half_w: float, passed: bool) -> void:
	crown.scale = Vector3(half_w * 2.6, half_w * 1.7, 1.1)
	crown.position.y = at_y
	crown.material_override = _leaf_pale_mat if passed else _leaf_mat


## Bildschirmanker über Gooby (float_text).
func gooby_screen() -> Vector2:
	return stage.to_screen(gooby.global_position + Vector3(0.0, 0.7, 0.0))


func hop_fx() -> void:
	gooby.play_for("hop", 0.4)


func coin_fx(world_x: float, world_y: float) -> void:
	Fx.burst(_burst, Vector3(_origin_x() + world_x, world_y + 0.4, 0.3))


func crash_fx() -> void:
	gooby.emote("dizzy", 1.5)
	Fx.burst(_burst, gooby.global_position + Vector3(0.0, 0.5, 0.0))
