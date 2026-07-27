extends Node3D
## ECHTES 3D-BEET für den Gießkannen-Wirbel (FB-4, MP-B-Politur): Terrakotta-
## Töpfe mit wachsenden 3D-Sprossen und stacheligem Unkraut stehen in einem
## plankengerahmten Hochbeet; beim Perfekt-Guss öffnet sich sichtbar eine
## Blüte im Topf. Dahinter staffeln sich Gewächshaus, Zaun mit Vogel, Bäume,
## Hügelkette und Schmetterlinge im Fog. Gooby (echtes Rig) gießt mit einer
## echten Kanne: beim Halten dreht er sich zum Topf und ein Wasserstrahl
## plätschert hinein. Die Töpfe werden per ground_point-Raycast EXAKT unter
## die 2D-Tap-Rechtecke gelegt — Eingabe und Trefferflächen bleiben
## zahlengleich. Die MECHANIK bleibt komplett in garden_rush.gd/
## GardenRushLogic; der Füllring beim Halten bleibt als 2D-Overlay.

const Stage3D := preload("res://scripts/minigames/games/_3dc_stage/stage3d.gd")
const Actor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")
const Models := preload("res://scripts/minigames/games/_3dc_stage/models3d.gd")
const Kit := preload("res://scripts/minigames/games/carrot_catch/mpb_garden_kit.gd")
const DIR := "res://assets/minigames/carrot_catch/"

const POT_CLAY := Color(0.72, 0.45, 0.29)
const SOIL := Color(0.34, 0.24, 0.17)
const SPROUT := Color(0.33, 0.6, 0.26)
const LEAF := Color(0.46, 0.74, 0.32)
const WEED := Color(0.19, 0.36, 0.17)
## Wie lange die Belohnungs-Blüte nach dem Perfekt-Guss offen bleibt.
const BLOOM_SEC := 1.4

## Geteilte Balken-Materialien (grün = Zeit übrig, rot = gleich verwelkt).
static var _bar_ok: StandardMaterial3D = null
static var _bar_bad: StandardMaterial3D = null

var stage: Node3D
var gooby: Node3D

var _pots: Array[Node3D] = []
var _pot_pos: Array[Vector3] = []
var _pot_r: Array[float] = []
var _blooms: Dictionary = {}
var _bed: MeshInstance3D
var _bed_frame: Array[MeshInstance3D] = []
var _bed_rows: MultiMeshInstance3D
var _bed_cells: MultiMeshInstance3D
var _sprinkler: Node3D
var _sprinkler_ring: MeshInstance3D
var _butterflies: MultiMeshInstance3D
var _splash_burst: GPUParticles3D
var _leaf_burst: GPUParticles3D
var _bloom_burst: GPUParticles3D
var _stream: GPUParticles3D
var _pulses: Array = []
var _gooby_yaw := -0.3


func setup_stage() -> void:
	stage = Stage3D.new()
	add_child(stage)
	(
		stage
		. build(
			{
				# Warmes Vormittagslicht überm Gemüsebeet, NICHT überbelichtet:
				# deutlich weniger Ambient und sattere Töne — die erste Fassung
				# war ~40 Luma zu hell und las sich als ausgewaschenes Mint.
				"sky_top": Color(0.43, 0.69, 0.91),
				"sky_horizon": Color(0.82, 0.89, 0.83),
				"ground_horizon": Color(0.48, 0.68, 0.39),
				"ground_bottom": Color(0.36, 0.54, 0.3),
				"sun_dir": Vector3(0.3, -0.85, -0.35),
				"sun_color": Color(1.0, 0.95, 0.84),
				"sun_energy": 0.88,
				"ambient": 0.28,
				"fill_energy": 0.24,
				"glow": 0.26,
				"glow_threshold": 0.86,
				"shadow_distance": 30.0,
				"fog": true,
				"fog_color": Color(0.74, 0.84, 0.75),
				"fog_from": 26.0,
				"fog_to": 85.0,
				"far": 110.0,
			}
		)
	)
	add_child(Fx.ground(Vector2(120.0, 80.0), Color(0.38, 0.58, 0.28)))
	_build_backdrop()
	_build_bed()
	_build_gooby()
	_build_sprinkler()
	_build_fx()


func _build_backdrop() -> void:
	# Gemähte Bahnen: dunklere Streifen quer über die Wiese.
	var stripes := MultiMeshInstance3D.new()
	var stripe_mesh := PlaneMesh.new()
	stripe_mesh.size = Vector2(60.0, 2.6)
	stripe_mesh.material = Fx.flat(Color(0.34, 0.53, 0.24))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = stripe_mesh
	mm.instance_count = 6
	for i in 6:
		mm.set_instance_transform(
			i, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.012, -18.0 + float(i) * 5.4))
		)
	stripes.multimesh = mm
	stripes.extra_cull_margin = 40.0
	stripes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stripes)
	# Hügelkette am Horizont schließt das Bild nach hinten.
	add_child(
		Kit.hills([[-18.0, -36.0, 18.0, 4.2], [14.0, -37.0, 20.0, 4.6]], Color(0.36, 0.55, 0.31))
	)
	# Zaun mit Tor + Vogel, dahinter gemischte Baumreihe.
	var fence_poses: Array = []
	for i in 14:
		if i == 4:
			continue
		fence_poses.append(Transform3D(Basis.IDENTITY, Vector3(-11.7 + float(i) * 1.8, 0.0, -17.0)))
	add_child(Models.swarm(Models.parts(DIR + "fence_simple.glb", 1.8), fence_poses))
	var gate := Kit.prop("fence_gate.glb", 1.9)
	gate.position = Vector3(-4.5, 0.0, -17.0)
	add_child(gate)
	var bird := Kit.prop("bird.gltf", 0.4)
	bird.position = Vector3(3.9, 1.0, -16.9)
	bird.rotation.y = -0.5
	add_child(bird)
	var tree_poses: Array = []
	for i in 5:
		tree_poses.append(
			Transform3D(
				Basis(Vector3.UP, float(i) * 1.3),
				Vector3(-12.0 + float(i) * 6.0, 0.0, -20.0 - 2.0 * float(i % 2))
			)
		)
	add_child(Models.swarm(Models.parts(DIR + "tree_default.glb", 4.2), tree_poses))
	var oak_poses: Array = [
		Transform3D(Basis(Vector3.UP, 1.1), Vector3(-9.0, 0.0, -23.0)),
		Transform3D(Basis(Vector3.UP, 2.8), Vector3(10.5, 0.0, -22.5)),
	]
	add_child(Models.swarm(Kit.prop_parts("tree_oak.glb", 5.2), oak_poses))
	# Gewächshaus rechts, Gärtner-Ecke links (Töpfe + Stumpf) — Zonen im Bild.
	var greenhouse := Kit.greenhouse(3.6, 2.4, 2.3)
	greenhouse.position = Vector3(8.0, 0.0, -14.8)
	greenhouse.rotation.y = -0.24
	add_child(greenhouse)
	var big_pot := Kit.prop("pot_large.glb", 0.9)
	big_pot.position = Vector3(-8.2, 0.0, -13.8)
	add_child(big_pot)
	var small_pot := Kit.prop("pot_small.glb", 0.7)
	small_pot.position = Vector3(-7.2, 0.0, -13.2)
	add_child(small_pot)
	var stump := Kit.prop("stump_round.glb", 1.0)
	stump.position = Vector3(-9.6, 0.0, -14.6)
	add_child(stump)
	var mushroom := Kit.prop("mushroom_red.glb", 0.5)
	mushroom.position = Vector3(-10.4, 0.0, -13.4)
	add_child(mushroom)
	# Büsche NUR auf den Flanken — mittig stünden sie auf dem Beet, das in
	# Hochkant fast die ganze Bildmitte füllt.
	var bush_poses: Array = [
		Transform3D(Basis(Vector3.UP, 0.6), Vector3(-10.4, 0.0, -15.6)),
		Transform3D(Basis(Vector3.UP, 2.2), Vector3(9.8, 0.0, -15.2)),
		Transform3D(Basis(Vector3.UP, 3.4), Vector3(11.6, 0.0, -12.6)),
	]
	add_child(Models.swarm(Kit.prop_parts("plant_bush.glb", 1.3), bush_poses))
	# Blumentupfer NUR auf den Flanken: das Topffeld füllt in Hochkant fast
	# die ganze Bildmitte — mittige Deko stünde sonst mitten im Beet.
	var reds: Array = []
	var yellows: Array = []
	var purples: Array = []
	for i in 12:
		var side := -1.0 if i % 2 == 0 else 1.0
		var pose := Transform3D(
			Basis.IDENTITY,
			Vector3(
				side * (7.2 + 1.1 * float(i % 3) + float(i) * 0.22), 0.0, -6.0 - float(i) * 0.85
			)
		)
		if i % 3 == 0:
			reds.append(pose)
		elif i % 3 == 1:
			yellows.append(pose)
		else:
			purples.append(pose)
	add_child(Models.swarm(Models.parts(DIR + "flower_redA.glb", 0.5), reds))
	add_child(Models.swarm(Models.parts(DIR + "flower_yellowA.glb", 0.5), yellows))
	add_child(Models.swarm(Kit.prop_parts("flower_purpleA.glb", 0.5), purples))
	# Grasbüschel auf den Flanken lockern die Wiese auf.
	var grass_poses: Array = []
	for i in 10:
		var g_side := -1.0 if i % 2 == 0 else 1.0
		var gx := g_side * (6.6 + 1.4 * float(i % 3))
		var gz := -4.5 - float(i) * 1.05
		grass_poses.append(Transform3D(Basis(Vector3.UP, float(i) * 1.1), Vector3(gx, 0.0, gz)))
	add_child(Models.swarm(Kit.prop_parts("grass_large.glb", 0.55), grass_poses))
	_butterflies = Kit.butterflies(
		[Vector3(-7.4, 0.0, -8.2), Vector3(7.8, 0.0, -10.4), Vector3(-8.6, 0.0, -12.8)],
		Color(0.95, 0.68, 0.85),
		0.24
	)
	add_child(_butterflies)


func _build_bed() -> void:
	# Erdfläche unter dem Topffeld — layout() schiebt und skaliert sie.
	_bed = MeshInstance3D.new()
	var bed_mesh := BoxMesh.new()
	bed_mesh.size = Vector3(1.0, 0.12, 1.0)
	bed_mesh.material = Fx.flat(Color(0.42, 0.31, 0.22))
	_bed.mesh = bed_mesh
	_bed.position = Vector3(0.0, 0.05, -1.0)
	add_child(_bed)
	# Gepflügte Reihen: dunklere Erd-Streifen quer über das Beet — die große
	# Fläche las sich sonst als monotone Sandplatte. layout() setzt die Maße.
	_bed_rows = MultiMeshInstance3D.new()
	var row_mesh := PlaneMesh.new()
	row_mesh.size = Vector2(1.0, 1.0)
	row_mesh.material = Fx.flat(Color(0.36, 0.26, 0.18))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = row_mesh
	mm.instance_count = 6
	_bed_rows.multimesh = mm
	_bed_rows.extra_cull_margin = 30.0
	_bed_rows.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bed_rows)
	# Pflanzstellen: dunkle Erd-Teller unter JEDEM Topf-Slot — markieren, wo
	# Töpfe erscheinen (Klarheit), und brechen die große Beetfläche auf.
	_bed_cells = MultiMeshInstance3D.new()
	var cell_mesh := CylinderMesh.new()
	cell_mesh.top_radius = 1.0
	cell_mesh.bottom_radius = 1.0
	cell_mesh.height = 0.03
	cell_mesh.radial_segments = 18
	cell_mesh.material = Fx.flat(Color(0.32, 0.23, 0.16))
	var cells := MultiMesh.new()
	cells.transform_format = MultiMesh.TRANSFORM_3D
	cells.mesh = cell_mesh
	_bed_cells.multimesh = cells
	_bed_cells.extra_cull_margin = 30.0
	_bed_cells.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bed_cells)
	# Plankenrahmen (Hochbeet): vier Bretter, layout() setzt Maße und Lage.
	var plank_mat := Fx.flat(Color(0.58, 0.42, 0.27))
	for _i in 4:
		var plank := MeshInstance3D.new()
		var plank_mesh := BoxMesh.new()
		plank_mesh.size = Vector3(1.0, 0.3, 0.12)
		plank_mesh.material = plank_mat
		plank.mesh = plank_mesh
		add_child(plank)
		_bed_frame.append(plank)


func _build_gooby() -> void:
	gooby = Actor.new()
	add_child(gooby)
	gooby.mount(1.15)
	gooby.base_emotion = "happy"
	# Gießkanne in der Pfote: Körper + Tülle.
	var can := Node3D.new()
	var body := MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.1
	body_mesh.bottom_radius = 0.12
	body_mesh.height = 0.16
	body_mesh.material = Fx.flat(Color(0.5, 0.72, 0.85))
	body.mesh = body_mesh
	can.add_child(body)
	var spout := MeshInstance3D.new()
	var spout_mesh := CylinderMesh.new()
	spout_mesh.top_radius = 0.02
	spout_mesh.bottom_radius = 0.03
	spout_mesh.height = 0.2
	spout_mesh.material = Fx.flat(Color(0.5, 0.72, 0.85))
	spout.mesh = spout_mesh
	spout.rotation.z = 1.1
	spout.position = Vector3(0.14, 0.05, 0.0)
	can.add_child(spout)
	gooby.hold(can, "arm.R", Transform3D(Basis.IDENTITY, Vector3(0.0, -0.06, 0.06)))


func _build_sprinkler() -> void:
	_sprinkler = Node3D.new()
	var base := MeshInstance3D.new()
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.3
	base_mesh.bottom_radius = 0.4
	base_mesh.height = 0.3
	base_mesh.material = Fx.glow(Color(1.0, 0.82, 0.4), 0.7)
	base.mesh = base_mesh
	base.position.y = 0.15
	_sprinkler.add_child(base)
	var head := MeshInstance3D.new()
	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.22
	head_mesh.height = 0.44
	head_mesh.material = Fx.flat(Color(0.45, 0.72, 0.92))
	head.mesh = head_mesh
	head.position.y = 0.42
	_sprinkler.add_child(head)
	# Zwei Sprüharme, die sich mitdrehen — liest sich sofort als Sprinkler.
	var arm_mesh := CylinderMesh.new()
	arm_mesh.top_radius = 0.03
	arm_mesh.bottom_radius = 0.03
	arm_mesh.height = 0.5
	arm_mesh.material = Fx.flat(Color(0.45, 0.72, 0.92))
	for side: float in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		arm.mesh = arm_mesh
		arm.rotation.z = PI * 0.5
		arm.position = Vector3(side * 0.25, 0.52, 0.0)
		_sprinkler.add_child(arm)
	# Pulsierender Bodenring: "Tipp mich!" — sync() lässt ihn atmen.
	_sprinkler_ring = Fx.ring(0.55, 0.05, Color(1.0, 0.85, 0.4))
	_sprinkler_ring.rotation.x = PI * 0.5
	_sprinkler_ring.position.y = 0.06
	_sprinkler.add_child(_sprinkler_ring)
	_sprinkler.visible = false
	add_child(_sprinkler)


func _build_fx() -> void:
	_splash_burst = (
		Fx
		. particles(
			{
				"color": Color(0.55, 0.8, 0.95, 0.95),
				"amount": 20,
				"lifetime": 0.55,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(1.2, 2.8),
				"spread": 60.0,
				"size": Vector2(0.05, 0.13),
			}
		)
	)
	add_child(_splash_burst)
	_leaf_burst = (
		Fx
		. particles(
			{
				"color": Color(0.6, 0.5, 0.35, 0.9),
				"amount": 12,
				"lifetime": 0.5,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(0.8, 2.0),
				"spread": 70.0,
				"size": Vector2(0.05, 0.12),
			}
		)
	)
	add_child(_leaf_burst)
	# Blütenkonfetti beim Perfekt-Guss: rosa Blätter stieben aus dem Topf.
	_bloom_burst = (
		Fx
		. particles(
			{
				"color": Color(0.98, 0.72, 0.82, 0.95),
				"amount": 16,
				"lifetime": 0.65,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(1.0, 2.4),
				"spread": 75.0,
				"size": Vector2(0.06, 0.14),
				"additive": true,
			}
		)
	)
	add_child(_bloom_burst)
	# Dauerstrahl aus der Gießkanne: läuft nur, solange gehalten wird.
	_stream = (
		Fx
		. particles(
			{
				"color": Color(0.6, 0.83, 0.96, 0.9),
				"amount": 24,
				"lifetime": 0.4,
				"speed": Vector2(1.6, 2.4),
				"spread": 14.0,
				"size": Vector2(0.04, 0.09),
			}
		)
	)
	_stream.emitting = false
	add_child(_stream)


## Kamera: schräg von oben aufs Beet — flach genug, dass hinter dem Topffeld
## Wiese, Zaun und Bäume als Kulisse ins Bild kommen (wie carrot_guard).
func frame(vp: Vector2) -> void:
	stage.apply_size(vp)
	stage.camera.position = Vector3(0.0, 10.5, 8.0)
	stage.camera.rotation_degrees = Vector3(-40.0, 0.0, 0.0)
	stage.set_half_height(4.9, 10.0)


## Töpfe per Raycast unter die 2D-Rechtecke legen; Sprinkler + Gooby am Rand.
func layout(pot_rects: Array[Rect2], sprinkler_rect: Rect2) -> void:
	while _pots.size() < pot_rects.size():
		var pot := _spawn_pot()
		add_child(pot)
		_pots.append(pot)
	_pot_pos.clear()
	_pot_r.clear()
	var lo := Vector3(INF, 0.0, INF)
	var hi := Vector3(-INF, 0.0, -INF)
	for i in pot_rects.size():
		var rect := pot_rects[i]
		var center: Vector3 = stage.ground_point(rect.get_center())
		var edge: Vector3 = stage.ground_point(rect.get_center() + Vector2(rect.size.x * 0.5, 0.0))
		var radius := clampf(center.distance_to(edge) * 0.62, 0.3, 3.0)
		_pot_pos.append(center)
		_pot_r.append(radius)
		_pots[i].position = center
		_pots[i].scale = Vector3.ONE * radius
		lo.x = minf(lo.x, center.x)
		lo.z = minf(lo.z, center.z)
		hi.x = maxf(hi.x, center.x)
		hi.z = maxf(hi.z, center.z)
	var sprinkler_at: Vector3 = stage.ground_point(sprinkler_rect.get_center())
	_sprinkler.position = sprinkler_at
	_sprinkler.scale = Vector3.ONE * clampf(_pot_r[0] * 1.1, 0.7, 2.2)
	var back_r := _pot_r[0] if not _pot_r.is_empty() else 1.0
	var front_r := _pot_r[_pot_r.size() - 1] if not _pot_r.is_empty() else 1.0
	# Erdfläche knapp unter das Topffeld legen (schmaler Rand — die alte
	# 4-Radien-Marge machte das Beet zur bildfüllenden Sandplatte),
	# Plankenrahmen drumherum, gepflügte Reihen quer darüber.
	var bed_w := hi.x - lo.x + back_r * 3.0
	var bed_d := maxf(1.0, hi.z - lo.z + back_r * 1.4 + front_r * 1.4)
	var bed_c := Vector3((lo.x + hi.x) * 0.5, 0.0, (lo.z + hi.z) * 0.5)
	_bed.position = bed_c + Vector3(0.0, 0.05, 0.0)
	_bed.scale = Vector3(bed_w, 1.0, bed_d)
	var rows := _bed_rows.multimesh
	for i in rows.instance_count:
		var f := (float(i) + 0.5) / float(rows.instance_count)
		var basis := Basis.IDENTITY.scaled(Vector3(bed_w * 0.94, 1.0, front_r * 0.36))
		rows.set_instance_transform(
			i, Transform3D(basis, bed_c + Vector3(0.0, 0.115, (f - 0.5) * bed_d * 0.94))
		)
	var cells := _bed_cells.multimesh
	if cells.instance_count != _pot_pos.size():
		cells.instance_count = _pot_pos.size()
	for i in _pot_pos.size():
		var disc := Basis.IDENTITY.scaled(Vector3.ONE * _pot_r[i] * 1.4)
		cells.set_instance_transform(
			i, Transform3D(disc, Vector3(_pot_pos[i].x, 0.14, _pot_pos[i].z))
		)
	for i in _bed_frame.size():
		var plank := _bed_frame[i]
		var mesh := plank.mesh as BoxMesh
		if i < 2:
			var side_z := -1.0 if i == 0 else 1.0
			mesh.size = Vector3(bed_w + 0.24, 0.3, 0.12)
			plank.position = bed_c + Vector3(0.0, 0.15, side_z * (bed_d * 0.5 + 0.06))
		else:
			var side_x := -1.0 if i == 2 else 1.0
			mesh.size = Vector3(0.12, 0.3, bed_d + 0.24)
			plank.position = bed_c + Vector3(side_x * (bed_w * 0.5 + 0.06), 0.15, 0.0)
	# Gooby als Gärtner an der linken Beetkante — per Bildrand-Raycast in den
	# sichtbaren Ausschnitt geklemmt (Hochkant reicht das Feld fast bis zum
	# Rand, dort stand er sonst halb abgeschnitten).
	var left_lim: Vector3 = stage.ground_point(Vector2(8.0, pot_rects[0].get_center().y))
	gooby.position = Vector3(
		maxf(lo.x - back_r * 1.7, left_lim.x + back_r), 0.0, lo.z - back_r * 0.55
	)
	gooby.scale = Vector3.ONE * clampf(back_r * 1.15, 0.7, 2.2)
	_gooby_yaw = 0.5
	gooby.rotation.y = _gooby_yaw


## Jeden Frame: Topf-Zustände spiegeln (Spross wächst, Unkraut wuchert,
## Timer-Balken läuft grün → rot), Gooby dreht sich zum gehaltenen Topf und
## der Gießstrahl plätschert hinein.
func sync(
	pots: Array[Dictionary], active_pots: int, hold_index: int, pulse: float, delta: float
) -> void:
	stage.tick(delta)
	gooby.tick(delta)
	Kit.animate_butterflies(_butterflies, pulse)
	Kit.tick_pulses(_pulses, delta)
	gooby.rotation.z = sin(pulse * 2.2) * 0.03
	# Gooby wendet sich dem gehaltenen Topf zu — Vorfreude aufs Gießen.
	var want_yaw := _gooby_yaw
	if hold_index >= 0 and hold_index < _pot_pos.size():
		var to_pot := _pot_pos[hold_index] - gooby.position
		want_yaw = atan2(to_pot.x, to_pot.z)
	gooby.rotation.y = lerp_angle(gooby.rotation.y, want_yaw, minf(1.0, delta * 8.0))
	_tick_stream(hold_index)
	_tick_blooms(delta)
	for i in _pots.size():
		var node := _pots[i]
		if i >= pots.size():
			node.visible = false
			continue
		node.visible = i < active_pots
		if not node.visible:
			continue
		var pot: Dictionary = pots[i]
		var state := str(pot["state"])
		var sprout := node.get_node("Spross") as Node3D
		var weed := node.get_node("Unkraut") as Node3D
		var bar := node.get_node("Balken") as MeshInstance3D
		sprout.visible = state == "sprout"
		weed.visible = state == "weed"
		bar.visible = state == "sprout"
		if state == "sprout":
			var window := maxf(0.05, float(pot["window"]))
			var ratio := clampf(float(pot["remaining"]) / window, 0.0, 1.0)
			bar.scale = Vector3(maxf(0.02, ratio), 1.0, 1.0)
			(bar.mesh as BoxMesh).material = _bar_mat(ratio > 0.35)
			sprout.rotation.z = sin(pulse * 2.0 + float(i)) * 0.08
			# Der gehaltene Topf wippt sichtbar mit.
			sprout.scale = Vector3.ONE * (1.1 if hold_index == i else 1.0)
		elif state == "weed":
			weed.rotation.y = pulse * 0.8
			weed.scale = Vector3.ONE * (1.25 if bool(pot.get("grown", false)) else 1.0)
	_sprinkler.rotation.y = pulse * 1.6
	if _sprinkler.visible:
		var breathe := 1.0 + 0.14 * sin(pulse * 5.0)
		_sprinkler_ring.scale = Vector3.ONE * breathe
		_sprinkler_ring.transparency = 0.25 + 0.25 * sin(pulse * 5.0)


## Gießstrahl an den gehaltenen Topf hängen (läuft nur beim Halten).
func _tick_stream(hold_index: int) -> void:
	var active := hold_index >= 0 and hold_index < _pot_pos.size()
	_stream.emitting = active
	if active:
		_stream.position = (_pot_pos[hold_index] + Vector3(0.0, _pot_r[hold_index] * 1.4, 0.0))


## Belohnungs-Blüten nach dem Perfekt-Guss wieder einziehen.
func _tick_blooms(delta: float) -> void:
	for key: int in _blooms.keys():
		var left := float(_blooms[key]) - delta
		var bloom := _pots[key].get_node("Bluete") as Node3D
		if left <= 0.0:
			bloom.visible = false
			_blooms.erase(key)
			continue
		_blooms[key] = left
		# Aufpoppen (0,2 s), offen halten, am Ende sanft schrumpfen.
		var open := clampf((BLOOM_SEC - left) / 0.2, 0.0, 1.0)
		var fade := clampf(left / 0.3, 0.0, 1.0)
		bloom.scale = Vector3.ONE * (open * fade)


static func _bar_mat(ok: bool) -> StandardMaterial3D:
	if _bar_ok == null:
		_bar_ok = Fx.glow(Color(0.36, 0.72, 0.28), 0.55)
		_bar_bad = Fx.glow(Color(0.9, 0.32, 0.24), 0.8)
	return _bar_ok if ok else _bar_bad


func set_sprinkler_visible(on: bool) -> void:
	_sprinkler.visible = on


func water_fx(index: int, perfect: bool) -> void:
	if index < 0 or index >= _pot_pos.size():
		return
	var at := _pot_pos[index] + Vector3(0.0, _pot_r[index] * 0.8, 0.0)
	Fx.burst(_splash_burst, at)
	gooby.swing(0.4, 30.0, Vector3.BACK)
	if perfect:
		# Perfekt-Guss: Blüte öffnet sich im Topf + Blütenkonfetti + Ring.
		Fx.burst(_bloom_burst, at)
		Kit.spawn_pulse(self, _pulses, at, Color(0.98, 0.75, 0.85), _pot_r[index] * 1.2)
		var bloom := _pots[index].get_node("Bluete") as Node3D
		bloom.visible = true
		bloom.scale = Vector3.ZERO
		_blooms[index] = BLOOM_SEC
		gooby.emote("ecstatic", 1.0)
		gooby.hop(0.4, 0.3)
		stage.pulse_glow(0.6)
	else:
		Kit.spawn_pulse(self, _pulses, at, Color(0.6, 0.84, 0.95), _pot_r[index] * 0.9)
		gooby.emote("happy", 0.5)


func weed_fx(index: int) -> void:
	if index < 0 or index >= _pot_pos.size():
		return
	Fx.burst(_leaf_burst, _pot_pos[index] + Vector3(0.0, _pot_r[index] * 0.7, 0.0))
	gooby.emote("dizzy", 1.1)


func wilt_fx(index: int) -> void:
	if index < 0 or index >= _pot_pos.size():
		return
	Fx.burst(_leaf_burst, _pot_pos[index] + Vector3(0.0, _pot_r[index] * 0.6, 0.0))
	gooby.emote("scared", 1.1)


func sprinkler_fx() -> void:
	Fx.burst(_splash_burst, _sprinkler.global_position + Vector3(0.0, 0.6, 0.0))
	# Regenbogen über dem ganzen Beet: jeder Topf bekommt seinen Wasserring.
	for i in _pot_pos.size():
		Kit.spawn_pulse(
			self,
			_pulses,
			_pot_pos[i] + Vector3(0.0, _pot_r[i] * 0.6, 0.0),
			Color(0.6, 0.84, 0.95),
			_pot_r[i]
		)
	gooby.emote("ecstatic", 1.4)
	gooby.play_for("celebrate", 1.0)
	stage.pulse_glow(0.9)


func _spawn_pot() -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var body_mesh := CylinderMesh.new()
	body_mesh.top_radius = 0.62
	body_mesh.bottom_radius = 0.45
	body_mesh.height = 0.5
	body_mesh.material = Fx.flat(POT_CLAY)
	body.mesh = body_mesh
	body.position.y = 0.25
	root.add_child(body)
	var rim := MeshInstance3D.new()
	var rim_mesh := CylinderMesh.new()
	rim_mesh.top_radius = 0.68
	rim_mesh.bottom_radius = 0.68
	rim_mesh.height = 0.14
	rim_mesh.material = Fx.flat(POT_CLAY.darkened(0.22))
	rim.mesh = rim_mesh
	rim.position.y = 0.5
	root.add_child(rim)
	var soil := MeshInstance3D.new()
	var soil_mesh := CylinderMesh.new()
	soil_mesh.top_radius = 0.56
	soil_mesh.bottom_radius = 0.56
	soil_mesh.height = 0.06
	soil_mesh.material = Fx.flat(SOIL)
	soil.mesh = soil_mesh
	soil.position.y = 0.54
	soil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(soil)
	root.add_child(_spawn_sprout())
	root.add_child(_spawn_weed())
	root.add_child(_spawn_bloom())
	# Timer-Balken über dem Topf (grün → rot, Breite = Restzeit).
	var bar := MeshInstance3D.new()
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(1.1, 0.1, 0.1)
	bar_mesh.material = _bar_mat(true)
	bar.mesh = bar_mesh
	bar.name = "Balken"
	bar.position.y = 1.7
	bar.visible = false
	bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(bar)
	return root


func _spawn_sprout() -> Node3D:
	var sprout := Node3D.new()
	sprout.name = "Spross"
	sprout.visible = false
	var stem := MeshInstance3D.new()
	var stem_mesh := CylinderMesh.new()
	stem_mesh.top_radius = 0.05
	stem_mesh.bottom_radius = 0.07
	stem_mesh.height = 1.0
	stem_mesh.radial_segments = 8
	stem_mesh.material = Fx.flat(SPROUT)
	stem.mesh = stem_mesh
	stem.position.y = 1.05
	sprout.add_child(stem)
	var leaf_mesh := SphereMesh.new()
	leaf_mesh.radius = 0.2
	leaf_mesh.height = 0.24
	leaf_mesh.material = Fx.flat(LEAF)
	for i in 3:
		var leaf := MeshInstance3D.new()
		leaf.mesh = leaf_mesh
		var side := 1.0 if i % 2 == 0 else -1.0
		leaf.position = Vector3(side * 0.26, 0.9 + float(i) * 0.26, 0.0)
		leaf.scale = Vector3(1.4, 0.6, 1.0)
		sprout.add_child(leaf)
	var bud := MeshInstance3D.new()
	var bud_mesh := SphereMesh.new()
	bud_mesh.radius = 0.15
	bud_mesh.height = 0.3
	bud_mesh.material = Fx.flat(Color(0.98, 0.7, 0.77))
	bud.mesh = bud_mesh
	bud.position.y = 1.66
	sprout.add_child(bud)
	return sprout


func _spawn_weed() -> Node3D:
	var weed := Node3D.new()
	weed.name = "Unkraut"
	weed.visible = false
	var blade_mesh := CylinderMesh.new()
	blade_mesh.top_radius = 0.0
	blade_mesh.bottom_radius = 0.07
	blade_mesh.height = 0.7
	blade_mesh.radial_segments = 6
	blade_mesh.material = Fx.flat(WEED)
	for i in 5:
		var blade := MeshInstance3D.new()
		blade.mesh = blade_mesh
		var a := TAU * float(i) / 5.0
		blade.position = Vector3(cos(a) * 0.18, 0.85, sin(a) * 0.18)
		blade.rotation.z = cos(a) * 0.5
		blade.rotation.x = sin(a) * 0.5
		weed.add_child(blade)
	var warn := Label3D.new()
	warn.text = "!"
	warn.font_size = 140
	warn.modulate = Color(0.9, 0.3, 0.25)
	warn.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	warn.no_depth_test = true
	warn.position.y = 1.7
	warn.pixel_size = 0.005
	weed.add_child(warn)
	return weed


## Belohnungs-Blüte: öffnet sich beim Perfekt-Guss kurz über dem Topf.
func _spawn_bloom() -> Node3D:
	var bloom := Node3D.new()
	bloom.name = "Bluete"
	bloom.visible = false
	bloom.position.y = 1.1
	var petal_mesh := SphereMesh.new()
	petal_mesh.radius = 0.16
	petal_mesh.height = 0.22
	petal_mesh.material = Fx.flat(Color(0.98, 0.66, 0.78))
	for i in 5:
		var petal := MeshInstance3D.new()
		petal.mesh = petal_mesh
		var a := TAU * float(i) / 5.0
		petal.position = Vector3(cos(a) * 0.2, 0.0, sin(a) * 0.2)
		petal.scale = Vector3(1.3, 0.5, 1.0)
		petal.rotation.y = -a
		petal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		bloom.add_child(petal)
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.12
	core_mesh.height = 0.24
	core_mesh.material = Fx.glow(Color(1.0, 0.9, 0.5), 0.6)
	core.mesh = core_mesh
	core.position.y = 0.04
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	bloom.add_child(core)
	return bloom
