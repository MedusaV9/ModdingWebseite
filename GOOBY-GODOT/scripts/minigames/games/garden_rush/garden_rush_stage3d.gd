extends Node3D
## ECHTES 3D-BEET für den Gießkannen-Wirbel (FB-4): Terrakotta-Töpfe mit
## wachsenden 3D-Sprossen und stacheligem Unkraut stehen auf einer Gartenerde,
## dahinter Zaun, Bäume und Blumen; Gooby (echtes Rig) gießt mit einer echten
## Kanne. Die Töpfe werden per ground_point-Raycast EXAKT unter die
## 2D-Tap-Rechtecke gelegt — Eingabe und Trefferflächen bleiben zahlengleich.
## Die MECHANIK bleibt komplett in garden_rush.gd/GardenRushLogic; der
## Füllring beim Halten bleibt als 2D-Overlay (Eingabe-Feedback).

const Stage3D := preload("res://scripts/minigames/games/_3dc_stage/stage3d.gd")
const Actor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")
const Models := preload("res://scripts/minigames/games/_3dc_stage/models3d.gd")
const DIR := "res://assets/minigames/carrot_catch/"

const POT_CLAY := Color(0.79, 0.54, 0.36)
const SOIL := Color(0.42, 0.31, 0.23)
const SPROUT := Color(0.35, 0.62, 0.28)
const LEAF := Color(0.49, 0.76, 0.35)
const WEED := Color(0.19, 0.36, 0.17)

## Geteilte Balken-Materialien (grün = Zeit übrig, rot = gleich verwelkt).
static var _bar_ok: StandardMaterial3D = null
static var _bar_bad: StandardMaterial3D = null

var stage: Node3D
var gooby: Node3D

var _pots: Array[Node3D] = []
var _pot_pos: Array[Vector3] = []
var _pot_r: Array[float] = []
var _bed: MeshInstance3D
var _sprinkler: Node3D
var _splash_burst: GPUParticles3D
var _leaf_burst: GPUParticles3D


func setup_stage() -> void:
	stage = Stage3D.new()
	add_child(stage)
	(
		stage
		. build(
			{
				# Vormittagslicht überm Gemüsebeet, NICHT überbelichtet.
				"sky_top": Color(0.53, 0.77, 0.93),
				"sky_horizon": Color(0.88, 0.93, 0.88),
				"ground_horizon": Color(0.66, 0.8, 0.54),
				"ground_bottom": Color(0.48, 0.64, 0.4),
				"sun_dir": Vector3(0.3, -0.85, -0.35),
				"sun_energy": 0.85,
				"ambient": 0.56,
				"fill_energy": 0.22,
				"glow": 0.26,
				"glow_threshold": 0.86,
				"shadow_distance": 30.0,
				"fog": true,
				"fog_color": Color(0.86, 0.92, 0.86),
				"fog_from": 26.0,
				"fog_to": 70.0,
				"far": 110.0,
			}
		)
	)
	add_child(Fx.ground(Vector2(80.0, 60.0), Color(0.56, 0.75, 0.42)))
	_build_backdrop()
	_build_gooby()
	_build_sprinkler()
	_build_fx()


func _build_backdrop() -> void:
	# Erdfläche unter dem Beet — layout() schiebt sie unter das Topffeld.
	_bed = MeshInstance3D.new()
	var bed_mesh := BoxMesh.new()
	bed_mesh.size = Vector3(1.0, 0.12, 1.0)
	bed_mesh.material = Fx.flat(Color(0.5, 0.4, 0.3))
	_bed.mesh = bed_mesh
	_bed.position = Vector3(0.0, 0.05, -1.0)
	add_child(_bed)
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
	var reds: Array = []
	var yellows: Array = []
	for i in 10:
		var pose := Transform3D(
			Basis.IDENTITY, Vector3(-8.0 + float(i) * 1.8, 0.0, -14.0 if i % 2 == 0 else -15.2)
		)
		if i % 2 == 0:
			reds.append(pose)
		else:
			yellows.append(pose)
	add_child(Models.swarm(Models.parts(DIR + "flower_redA.glb", 0.5), reds))
	add_child(Models.swarm(Models.parts(DIR + "flower_yellowA.glb", 0.5), yellows))


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
	_sprinkler.scale = Vector3.ONE * clampf(_pot_r[0] * 0.9, 0.5, 2.0)
	var back_r := _pot_r[0] if not _pot_r.is_empty() else 1.0
	# Erdfläche exakt unter das Topffeld legen (mit Rand), Gooby hinten IM Bild.
	_bed.position = Vector3((lo.x + hi.x) * 0.5, 0.05, (lo.z + hi.z) * 0.5)
	_bed.scale = Vector3(hi.x - lo.x + back_r * 4.0, 1.0, maxf(1.0, hi.z - lo.z + back_r * 4.0))
	gooby.position = Vector3(hi.x * 0.7, 0.0, lo.z - back_r * 2.2)
	gooby.scale = Vector3.ONE * clampf(back_r * 1.0, 0.5, 2.2)
	gooby.rotation.y = -0.3


## Jeden Frame: Topf-Zustände spiegeln (Spross wächst, Unkraut wuchert,
## Timer-Balken läuft grün → rot).
func sync(
	pots: Array[Dictionary], active_pots: int, hold_index: int, pulse: float, delta: float
) -> void:
	stage.tick(delta)
	gooby.tick(delta)
	gooby.rotation.z = sin(pulse * 2.2) * 0.03
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


static func _bar_mat(ok: bool) -> StandardMaterial3D:
	if _bar_ok == null:
		_bar_ok = Fx.glow(Color(0.5, 0.8, 0.4), 0.8)
		_bar_bad = Fx.glow(Color(0.92, 0.4, 0.3), 1.0)
	return _bar_ok if ok else _bar_bad


func set_sprinkler_visible(on: bool) -> void:
	_sprinkler.visible = on


func water_fx(index: int, perfect: bool) -> void:
	if index < 0 or index >= _pot_pos.size():
		return
	Fx.burst(_splash_burst, _pot_pos[index] + Vector3(0.0, _pot_r[index] * 0.8, 0.0))
	gooby.swing(0.4, 30.0, Vector3.BACK)
	if perfect:
		gooby.emote("ecstatic", 1.0)
		stage.pulse_glow(0.6)
	else:
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
	rim_mesh.height = 0.12
	rim_mesh.material = Fx.flat(POT_CLAY.darkened(0.12))
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
	stem_mesh.top_radius = 0.04
	stem_mesh.bottom_radius = 0.06
	stem_mesh.height = 0.8
	stem_mesh.radial_segments = 8
	stem_mesh.material = Fx.flat(SPROUT)
	stem.mesh = stem_mesh
	stem.position.y = 0.95
	sprout.add_child(stem)
	var leaf_mesh := SphereMesh.new()
	leaf_mesh.radius = 0.16
	leaf_mesh.height = 0.2
	leaf_mesh.material = Fx.flat(LEAF)
	for i in 3:
		var leaf := MeshInstance3D.new()
		leaf.mesh = leaf_mesh
		var side := 1.0 if i % 2 == 0 else -1.0
		leaf.position = Vector3(side * 0.22, 0.85 + float(i) * 0.22, 0.0)
		leaf.scale = Vector3(1.4, 0.6, 1.0)
		sprout.add_child(leaf)
	var bud := MeshInstance3D.new()
	var bud_mesh := SphereMesh.new()
	bud_mesh.radius = 0.12
	bud_mesh.height = 0.24
	bud_mesh.material = Fx.flat(Color(0.98, 0.72, 0.78))
	bud.mesh = bud_mesh
	bud.position.y = 1.42
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
