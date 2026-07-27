extends Node3D
## ECHTE 3D-Heckenlandschaft für den Hasenhüpfer (FB-4, MP-C-Politur): Gooby
## (echtes Rig) flattert vor Parallax-Hügeln, Pappelreihe und Wolken durch
## Heckensäulen mit Blätterkronen; das NÄCHSTE Tor trägt goldene Kronen und
## einen pulsierenden Gold-Reifen in der Lücke (Timing-Fenster sichtbar).
## Die Kamera rahmt die Spielebene EXAKT wie die 2D-Rechnung (set_half_height
## auf z=0) — Spawn-/Kollisionszahlen bleiben unangetastet. Die MECHANIK
## bleibt komplett in bunny_hop.gd/BunnyHopLogic.

const Stage3D := preload("res://scripts/minigames/games/_3dc_stage/stage3d.gd")
const Actor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")

## Halbe Bildhöhe in Weltmetern = (2·WORLD_HALF_H + 0.6) / 2 der 2D-Sicht.
const HALF_H := 4.2
const CAM_DIST := 10.0
const PILLAR_POOL := 8
const COIN_POOL := 6
const HEDGE := Color(0.42, 0.66, 0.3)
const HEDGE_PALE := Color(0.6, 0.73, 0.54)
const LEAF := Color(0.34, 0.6, 0.24)
const LEAF_PALE := Color(0.56, 0.7, 0.5)
const GATE_GOLD := Color(1.0, 0.8, 0.35)

var stage: Node3D
var gooby: Node3D

var _floor_y := -3.1
var _pillars: Array[Dictionary] = []
var _coins: Array[MeshInstance3D] = []
var _hedge_mat: StandardMaterial3D
var _hedge_pale_mat: StandardMaterial3D
var _leaf_mat: StandardMaterial3D
var _leaf_pale_mat: StandardMaterial3D
var _leaf_gold_mat: StandardMaterial3D
var _tufts: MultiMeshInstance3D
var _flowers: MultiMeshInstance3D
var _hills_near: MultiMeshInstance3D
var _hills_far: MultiMeshInstance3D
var _trees: Node3D
var _clouds: MultiMeshInstance3D
var _shadow: MeshInstance3D
var _burst: GPUParticles3D
var _hop_puff: GPUParticles3D
var _gate_ring: MeshInstance3D
var _gate_ring_mat: StandardMaterial3D
var _stretch := 0.0


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
	# Goldene Torkronen: das NÄCHSTE Tor leuchtet warm — Blickführung.
	_leaf_gold_mat = Fx.glow(GATE_GOLD, 0.35)
	_build_backdrop()
	_build_pools()
	_build_gooby()


func _build_backdrop() -> void:
	# Wiese: statisch, die Bewegung erzählen Grasbüschel + Blumen + Hügel.
	add_child(Fx.ground(Vector2(60.0, 40.0), Color(0.49, 0.74, 0.36), _floor_y))
	var strip := MeshInstance3D.new()
	var strip_mesh := BoxMesh.new()
	strip_mesh.size = Vector3(60.0, 0.1, 0.5)
	strip_mesh.material = Fx.flat(Color(0.4, 0.67, 0.29))
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
	tuft_mesh.material = Fx.flat(Color(0.34, 0.6, 0.25))
	var tuft_mm := MultiMesh.new()
	tuft_mm.transform_format = MultiMesh.TRANSFORM_3D
	tuft_mm.mesh = tuft_mesh
	tuft_mm.instance_count = 30
	for i in 30:
		var wob := 0.75 + 0.5 * float((i * 7) % 3) * 0.5
		tuft_mm.set_instance_transform(
			i,
			Transform3D(
				Basis.IDENTITY.scaled(Vector3(1.0, wob, 1.0)),
				Vector3(-10.0 + float(i % 15) * 1.4, _floor_y + 0.14 * wob, 0.6 if i < 15 else 1.6)
			)
		)
	_tufts.multimesh = tuft_mm
	add_child(_tufts)
	_build_flowers()
	# Hügel: nah = satter und niedrig (Säulen bleiben lesbar), fern = hell.
	_hills_near = _hill_row(1.1, Color(0.42, 0.64, 0.38), -9.0, 2.8, 10, 0.62)
	_hills_far = _hill_row(2.0, Color(0.62, 0.8, 0.6), -16.0, 4.6, 8, 0.85)
	_build_trees()
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
	cloud_mm.instance_count = 6
	for i in 6:
		var b := Basis.IDENTITY.scaled(Vector3(1.7, 0.62, 1.0) * (0.7 + 0.3 * float(i % 3)))
		cloud_mm.set_instance_transform(
			i, Transform3D(b, Vector3(-9.0 + float(i) * 3.6, 2.3 + 1.1 * float(i % 3), -18.0))
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


## Blumentupfer auf der Wiese (eine MultiMesh, scrollt mit den Büscheln).
func _build_flowers() -> void:
	_flowers = MultiMeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.055
	mesh.height = 0.09
	mesh.radial_segments = 6
	mesh.rings = 4
	var mat := Fx.flat(Color(1.0, 1.0, 1.0))
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = 18
	var tints: Array[Color] = [
		Color(1.0, 0.92, 0.95),
		Color(1.0, 0.75, 0.82),
		Color(1.0, 0.88, 0.5),
		Color(0.95, 0.98, 1.0),
	]
	for i in 18:
		var x := -10.0 + float((i * 5) % 18) * 1.17
		var z := 0.35 + 0.35 * float((i * 3) % 5)
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(x, _floor_y + 0.1, z)))
		mm.set_instance_color(i, tints[i % tints.size()])
	_flowers.multimesh = mm
	_flowers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_flowers)


## Pappelreihe am Horizont (Stämme + Kronen als je EINE MultiMesh).
func _build_trees() -> void:
	_trees = Node3D.new()
	add_child(_trees)
	var trunk_mesh := CylinderMesh.new()
	trunk_mesh.top_radius = 0.09
	trunk_mesh.bottom_radius = 0.12
	trunk_mesh.height = 1.2
	trunk_mesh.radial_segments = 6
	trunk_mesh.material = Fx.flat(Color(0.52, 0.4, 0.3))
	var crown_mesh := SphereMesh.new()
	crown_mesh.radius = 0.75
	crown_mesh.height = 2.3
	crown_mesh.radial_segments = 10
	crown_mesh.rings = 6
	crown_mesh.material = Fx.flat(Color(0.38, 0.58, 0.34))
	var trunks := MultiMeshInstance3D.new()
	var crowns := MultiMeshInstance3D.new()
	var trunk_mm := MultiMesh.new()
	var crown_mm := MultiMesh.new()
	trunk_mm.transform_format = MultiMesh.TRANSFORM_3D
	crown_mm.transform_format = MultiMesh.TRANSFORM_3D
	trunk_mm.mesh = trunk_mesh
	crown_mm.mesh = crown_mesh
	trunk_mm.instance_count = 6
	crown_mm.instance_count = 6
	for i in 6:
		var x := -13.0 + float(i) * 5.2
		var s := 0.85 + 0.3 * float((i * 3) % 3) * 0.5
		trunk_mm.set_instance_transform(
			i, Transform3D(Basis.IDENTITY, Vector3(x, _floor_y + 0.6, -12.5))
		)
		crown_mm.set_instance_transform(
			i,
			Transform3D(
				Basis.IDENTITY.scaled(Vector3(s, s, s)), Vector3(x, _floor_y + 1.1 + 1.1 * s, -12.5)
			)
		)
	trunks.multimesh = trunk_mm
	crowns.multimesh = crown_mm
	trunks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	crowns.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_trees.add_child(trunks)
	_trees.add_child(crowns)


func _hill_row(
	radius: float, tint: Color, z: float, step: float, count: int, squash := 1.0
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
		var wobble := (0.85 + 0.3 * float(i % 3) * 0.5) * squash
		var b := Basis.IDENTITY.scaled(Vector3(1.6, wobble, 1.0))
		mm.set_instance_transform(
			i, Transform3D(b, Vector3(float(i - count / 2) * step, _floor_y + radius * 0.18, z))
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
	# Gold-Reifen in der Lücke des NÄCHSTEN Tors: „hier durch!" — pulsiert.
	_gate_ring = Fx.ring(1.0, 0.055, GATE_GOLD)
	_gate_ring_mat = _gate_ring.mesh.material as StandardMaterial3D
	_gate_ring_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_gate_ring.visible = false
	add_child(_gate_ring)


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
	# Flatterwölkchen unter Gooby bei jedem Hüpfer (sofortige Rückmeldung).
	_hop_puff = (
		Fx
		. particles(
			{
				"color": Color(1.0, 1.0, 1.0, 0.7),
				"amount": 6,
				"lifetime": 0.35,
				"one_shot": true,
				"explosiveness": 1.0,
				"direction": Vector3(0.0, -1.0, 0.0),
				"speed": Vector2(0.6, 1.4),
				"spread": 40.0,
				"gravity": Vector3(0.0, -0.5, 0.0),
				"size": Vector2(0.07, 0.16),
			}
		)
	)
	add_child(_hop_puff)


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
	_pose_stretch(gooby_vy, delta)
	_shadow.position.x = gooby.position.x
	var drop := clampf(1.0 - (gooby_y - _floor_y) / 6.0, 0.3, 1.0)
	_shadow.scale = Vector3.ONE * drop
	var next_gate := -1
	for i in pillars.size():
		if not bool((pillars[i] as Dictionary)["passed"]):
			next_gate = i
			break
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
		_pose_crown(slot["crown_top"], gap_top + gap_margin, half_w, passed, i == next_gate)
		_pose_crown(slot["crown_bottom"], gap_bottom - gap_margin, half_w, passed, i == next_gate)
	_pose_gate_ring(pillars, next_gate, ox, scroll, pulse)
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
		coin_node.rotation.z = sin(pulse * 2.2) * 0.2
	# Parallax: Büschel/Blumen voll, Hügel gebremst, Bäume/Wolken hauchzart.
	_tufts.position.x = -fposmod(scroll, 1.4)
	_flowers.position.x = -fposmod(scroll, 1.17 * 3.0)
	_hills_near.position.x = -fposmod(scroll * 0.34, 2.8)
	_hills_far.position.x = -fposmod(scroll * 0.14, 4.6)
	_trees.position.x = -fposmod(scroll * 0.2, 5.2)
	_clouds.position.x = -fposmod(scroll * 0.05, 5.0)


## Quetsch-/Streckpose: Hüpfer streckt, Fallen staucht leicht — plus der
## kurze Hop-Impuls (Antizipation/Überschwingen ohne Mechanik-Einfluss).
func _pose_stretch(gooby_vy: float, delta: float) -> void:
	_stretch = maxf(0.0, _stretch - delta * 4.0)
	var s := clampf(gooby_vy * 0.04, -0.12, 0.16) + _stretch * 0.14
	gooby.scale = Vector3(1.0 - s * 0.55, 1.0 + s, 1.0 - s * 0.55)


func _pose_gate_ring(
	pillars: Array[Dictionary], next_gate: int, ox: float, scroll: float, pulse: float
) -> void:
	if next_gate < 0 or next_gate >= pillars.size():
		_gate_ring.visible = false
		return
	var pillar: Dictionary = pillars[next_gate]
	_gate_ring.visible = true
	var radius := float(pillar["gapHeight"]) * 0.5 - 0.18
	_gate_ring.position = Vector3(
		ox + float(pillar["x"]) - scroll, float(pillar["gapCenterY"]) + 0.4, 0.12
	)
	_gate_ring.scale = Vector3.ONE * maxf(0.3, radius) * (1.0 + 0.04 * sin(pulse * 6.0))
	_gate_ring_mat.albedo_color.a = 0.7 + 0.25 * sin(pulse * 6.0)


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


func _pose_crown(
	crown: MeshInstance3D, at_y: float, half_w: float, passed: bool, next_gate: bool
) -> void:
	crown.scale = Vector3(half_w * 2.6, half_w * 1.7, 1.1)
	crown.position.y = at_y
	if passed:
		crown.material_override = _leaf_pale_mat
	elif next_gate:
		crown.material_override = _leaf_gold_mat
	else:
		crown.material_override = _leaf_mat


## Bildschirmanker über Gooby (float_text).
func gooby_screen() -> Vector2:
	return stage.to_screen(gooby.global_position + Vector3(0.0, 0.7, 0.0))


func hop_fx() -> void:
	gooby.play_for("hop", 0.4)
	_stretch = 1.0
	Fx.burst(_hop_puff, gooby.global_position + Vector3(-0.1, -0.25, 0.15))


func coin_fx(world_x: float, world_y: float) -> void:
	Fx.burst(_burst, Vector3(_origin_x() + world_x, world_y + 0.4, 0.3))


func crash_fx() -> void:
	gooby.emote("dizzy", 1.5)
	Fx.burst(_burst, gooby.global_position + Vector3(0.0, 0.5, 0.0))
	Fx.burst(_hop_puff, gooby.global_position + Vector3(0.0, 0.2, 0.2))
