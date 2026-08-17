extends Node3D
## ECHTE 3D-KÜCHE für den Pfannkuchenturm (FB-4): Pfannkuchen sind flache
## 3D-Zylinder, die auf einem Teller auf der Arbeitsplatte stapeln, der Turm
## schwankt als ECHTE Rotation um die Basis, und Gooby (echtes Rig) reitet auf
## dem Pendel-Pfannkuchen. Die Kamera fährt mit der Stapelspitze nach oben —
## Abbildung ist 1:1 die Web-Kameramathematik (VIEW_UNITS_X/GROUND_FRAC), die
## MECHANIK bleibt komplett in pancake_tower.gd/PancakeTowerLogic.

const Stage3D := preload("res://scripts/minigames/games/_3dc_stage/stage3d.gd")
const Actor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")
const Models := preload("res://scripts/minigames/games/_3dc_stage/models3d.gd")
const DIR := "res://assets/minigames/carrot_catch/"

const CAM_DIST := 8.0
const CAKE := Color(0.88, 0.6, 0.25)
const CAKE_TOP := Color(0.94, 0.71, 0.38)
const BUTTER := Color(1.0, 0.85, 0.36)
const BERRY := Color(0.93, 0.36, 0.48)
const WOOD := Color(0.66, 0.49, 0.35)
const TREATS := "res://assets/minigames/veggie_chop/tinytreats/"
const SWEETS := "res://assets/minigames/purble_place/"

var stage: Node3D
var gooby: Node3D

var _vp := Vector2(390.0, 844.0)
var _view_units_x := 2.9
var _ground_frac := 0.88
var _tower: Node3D
var _layer_pool: Array[Node3D] = []
var _crumb_pool: Array[MeshInstance3D] = []
var _active: Node3D
var _active_mesh: MeshInstance3D
var _active_berry: MeshInstance3D
var _guide: MeshInstance3D
var _star_burst: GPUParticles3D
var _crumb_burst: GPUParticles3D
var _land_ring: MeshInstance3D
var _ring_age := 99.0

var _mat_cake: StandardMaterial3D
var _mat_topping: StandardMaterial3D
var _layer_h := 0.18


func setup_stage(view_units_x: float, ground_frac: float, layer_h: float) -> void:
	_view_units_x = view_units_x
	_ground_frac = ground_frac
	_layer_h = layer_h
	stage = Stage3D.new()
	add_child(stage)
	(
		stage
		. build(
			{
				# Warmes Küchenlicht am Morgen, NICHT überbelichtet: Ambient
				# kommt aus dem Himmel, sky_energy UND ambient drosseln.
				"sky_top": Color(0.56, 0.72, 0.86),
				"sky_horizon": Color(0.8, 0.78, 0.7),
				"ground_horizon": Color(0.74, 0.68, 0.58),
				"ground_bottom": Color(0.56, 0.5, 0.42),
				"sky_energy": 0.75,
				"sun_dir": Vector3(-0.35, -0.7, -0.55),
				"sun_energy": 0.5,
				"ambient": 0.36,
				"fill_energy": 0.16,
				"glow": 0.24,
				"glow_threshold": 0.88,
				"shadow_distance": 24.0,
				"far": 90.0,
			}
		)
	)
	_mat_cake = Fx.flat(CAKE)
	_mat_topping = Fx.flat(CAKE_TOP)
	_build_kitchen()
	_build_tower()
	_build_active()
	_build_fx()


## Küchenkulisse: Rückwand mit Fenster, Bordüre, Regal mit Backwerk und die
## Arbeitsplatte mit Teller. Alles statisch — die Kamera fährt daran hoch.
func _build_kitchen() -> void:
	var wall := MeshInstance3D.new()
	var wall_mesh := PlaneMesh.new()
	wall_mesh.size = Vector2(34.0, 30.0)
	wall_mesh.orientation = PlaneMesh.FACE_Z
	wall_mesh.material = Fx.flat(Color(0.88, 0.74, 0.58))
	wall.mesh = wall_mesh
	wall.position = Vector3(0.0, 12.0, -2.4)
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wall)
	# Tapetenstreifen als MultiMesh — gibt der Wand Tiefe ohne Draw-Call-Flut.
	var stripes := MultiMeshInstance3D.new()
	var stripe := BoxMesh.new()
	stripe.size = Vector3(0.5, 30.0, 0.01)
	stripe.material = Fx.flat(Color(0.82, 0.66, 0.5))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = stripe
	mm.instance_count = 12
	for i in 12:
		mm.set_instance_transform(
			i, Transform3D(Basis.IDENTITY, Vector3(-8.25 + float(i) * 1.5, 12.0, -2.39))
		)
	stripes.multimesh = mm
	stripes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stripes)
	# Fenster mit Himmelblau + Kreuz und Sims.
	var win := Node3D.new()
	win.position = Vector3(-1.5, 2.6, -2.35)
	add_child(win)
	var glass := MeshInstance3D.new()
	var glass_mesh := PlaneMesh.new()
	glass_mesh.size = Vector2(1.4, 1.1)
	glass_mesh.orientation = PlaneMesh.FACE_Z
	glass_mesh.material = Fx.glow(Color(0.78, 0.9, 0.98), 0.35)
	glass.mesh = glass_mesh
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	win.add_child(glass)
	var frame_mat := Fx.flat(Color(0.86, 0.72, 0.56))
	for bar_pose: Array in [
		[Vector3(0.0, 0.58, 0.01), Vector3(1.56, 0.1, 0.05)],
		[Vector3(0.0, -0.58, 0.01), Vector3(1.56, 0.1, 0.05)],
		[Vector3(-0.75, 0.0, 0.01), Vector3(0.1, 1.26, 0.05)],
		[Vector3(0.75, 0.0, 0.01), Vector3(0.1, 1.26, 0.05)],
		[Vector3(0.0, 0.0, 0.01), Vector3(0.07, 1.26, 0.04)],
		[Vector3(0.0, 0.0, 0.01), Vector3(1.56, 0.07, 0.04)],
	]:
		var bar := MeshInstance3D.new()
		var bar_mesh := BoxMesh.new()
		bar_mesh.size = bar_pose[1]
		bar_mesh.material = frame_mat
		bar.mesh = bar_mesh
		bar.position = bar_pose[0]
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		win.add_child(bar)
	# Regal mit Backwerk (Food-Kit) weiter oben — Belohnung fürs Hochstapeln.
	# KEIN Schattenwurf: sonst legt sich ein Riesenschatten über die Tapete.
	var shelf := MeshInstance3D.new()
	var shelf_mesh := BoxMesh.new()
	shelf_mesh.size = Vector3(2.4, 0.08, 0.5)
	shelf_mesh.material = Fx.flat(WOOD)
	shelf.mesh = shelf_mesh
	shelf.position = Vector3(1.9, 5.2, -2.1)
	shelf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shelf)
	var cake := Models.node(DIR + "cake.glb", 0.75)
	cake.position = Vector3(1.3, 5.25, -2.1)
	_no_shadow(cake)
	add_child(cake)
	var cupcake := Models.node(DIR + "cupcake.glb", 0.55)
	cupcake.position = Vector3(2.5, 5.25, -2.1)
	_no_shadow(cupcake)
	add_child(cupcake)
	# Wimpelkette hoch oben — Ziel-Gefühl für lange Türme.
	var flags := MultiMeshInstance3D.new()
	var flag := PrismMesh.new()
	flag.size = Vector3(0.34, 0.4, 0.03)
	flag.material = Fx.flat(Color(0.95, 0.62, 0.7))
	var fmm := MultiMesh.new()
	fmm.transform_format = MultiMesh.TRANSFORM_3D
	fmm.mesh = flag
	fmm.instance_count = 9
	for i in 9:
		var t := float(i) / 8.0
		var droop := sin(t * PI) * 0.5
		fmm.set_instance_transform(
			i,
			Transform3D(
				Basis(Vector3.BACK, PI + (t - 0.5) * 0.5),
				Vector3(-2.8 + t * 5.6, 6.6 - droop, -2.3)
			)
		)
	flags.multimesh = fmm
	flags.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(flags)
	# Arbeitsplatte + Teller am Weltnullpunkt.
	var counter := MeshInstance3D.new()
	var counter_mesh := BoxMesh.new()
	counter_mesh.size = Vector3(34.0, 3.0, 4.0)
	counter_mesh.material = Fx.flat(WOOD)
	counter.mesh = counter_mesh
	counter.position = Vector3(0.0, -1.53, -1.0)
	add_child(counter)
	var plate := MeshInstance3D.new()
	var plate_mesh := CylinderMesh.new()
	plate_mesh.top_radius = 0.92
	plate_mesh.bottom_radius = 0.72
	plate_mesh.height = 0.08
	plate_mesh.radial_segments = 24
	plate_mesh.material = Fx.flat(Color(0.9, 0.92, 0.97))
	plate.mesh = plate_mesh
	plate.position.y = -0.04
	add_child(plate)
	_build_backsplash()
	_build_counter_props()
	_build_upper_floors()


func _build_backsplash() -> void:
	# Fliesenspiegel hinter der Arbeitsplatte (1 Draw-Call) — Küche statt Wand.
	var tiles := MultiMeshInstance3D.new()
	var tile := BoxMesh.new()
	tile.size = Vector3(0.62, 0.62, 0.02)
	tile.material = Fx.flat(Color(0.93, 0.87, 0.78))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = tile
	mm.instance_count = 20
	for i in 20:
		var col := i % 10
		var row := i / 10
		mm.set_instance_transform(
			i,
			Transform3D(
				Basis.IDENTITY,
				Vector3(
					-3.15 + float(col) * 0.7 + float(row) * 0.35, 0.34 + float(row) * 0.7, -2.32
				)
			)
		)
	tiles.multimesh = mm
	tiles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(tiles)


func _build_counter_props() -> void:
	# Backstube-Requisiten links und rechts vom Teller (Tiny Treats + Food-Kit).
	# Sichtbare Breite ist NUR ±1,45 Einheiten (VIEW_UNITS_X 2,9) — alles
	# außerhalb wäre unsichtbar; die Randfiguren dürfen anschneiden.
	for entry: Array in [
		[TREATS + "pan.gltf", 0.55, Vector3(-1.5, 0.0, -1.9), 0.5],
		[SWEETS + "tinytreats/stand_mixer.gltf", 0.62, Vector3(-1.5, 0.0, -1.55), 0.2],
		[TREATS + "kettle.gltf", 0.5, Vector3(1.5, 0.0, -1.55), -0.4],
		[TREATS + "pot.gltf", 0.42, Vector3(1.62, 0.0, -1.95), 0.0],
		[SWEETS + "waffle.glb", 0.5, Vector3(1.32, 0.0, -0.95), 0.3],
		[SWEETS + "strawberry.glb", 0.35, Vector3(-1.32, 0.0, -0.9), 0.0],
	]:
		var prop := Models.node(str(entry[0]), float(entry[1]))
		prop.position = entry[2]
		prop.rotation.y = float(entry[3])
		_no_shadow(prop)
		add_child(prop)


func _build_upper_floors() -> void:
	# Kulisse für die Kletterhöhe: zweites Fenster, Bord mit Backwerk und eine
	# Uhr — damit oben nicht nur Tapete wartet.
	var win := Node3D.new()
	win.position = Vector3(1.9, 8.6, -2.35)
	add_child(win)
	var glass := MeshInstance3D.new()
	var glass_mesh := PlaneMesh.new()
	glass_mesh.size = Vector2(1.4, 1.1)
	glass_mesh.orientation = PlaneMesh.FACE_Z
	glass_mesh.material = Fx.glow(Color(0.78, 0.9, 0.98), 0.35)
	glass.mesh = glass_mesh
	glass.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	win.add_child(glass)
	var frame_mat := Fx.flat(Color(0.86, 0.72, 0.56))
	for bar_pose: Array in [
		[Vector3(0.0, 0.58, 0.01), Vector3(1.56, 0.1, 0.05)],
		[Vector3(0.0, -0.58, 0.01), Vector3(1.56, 0.1, 0.05)],
		[Vector3(-0.75, 0.0, 0.01), Vector3(0.1, 1.26, 0.05)],
		[Vector3(0.75, 0.0, 0.01), Vector3(0.1, 1.26, 0.05)],
	]:
		var bar := MeshInstance3D.new()
		var bar_mesh := BoxMesh.new()
		bar_mesh.size = bar_pose[1]
		bar_mesh.material = frame_mat
		bar.mesh = bar_mesh
		bar.position = bar_pose[0]
		bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		win.add_child(bar)
	var shelf := MeshInstance3D.new()
	var shelf_mesh := BoxMesh.new()
	shelf_mesh.size = Vector3(2.2, 0.08, 0.5)
	shelf_mesh.material = Fx.flat(WOOD)
	shelf.mesh = shelf_mesh
	shelf.position = Vector3(-1.8, 9.6, -2.1)
	shelf.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shelf)
	for entry: Array in [
		[SWEETS + "muffin.glb", 0.6, Vector3(-2.4, 9.65, -2.1)],
		[SWEETS + "tinytreats/macaron_pink.gltf", 0.4, Vector3(-1.6, 9.65, -2.1)],
		[SWEETS + "pie.glb", 0.65, Vector3(-1.0, 9.65, -2.1)],
	]:
		var treat := Models.node(str(entry[0]), float(entry[1]))
		treat.position = entry[2]
		_no_shadow(treat)
		add_child(treat)
	# Küchenuhr: Zifferblatt + zwei Zeiger.
	var clock := Node3D.new()
	clock.position = Vector3(0.2, 12.4, -2.33)
	add_child(clock)
	var dial := MeshInstance3D.new()
	var dial_mesh := CylinderMesh.new()
	dial_mesh.top_radius = 0.5
	dial_mesh.bottom_radius = 0.5
	dial_mesh.height = 0.06
	dial_mesh.radial_segments = 22
	dial_mesh.material = Fx.flat(Color(0.97, 0.94, 0.88))
	dial.mesh = dial_mesh
	dial.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	dial.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	clock.add_child(dial)
	var hand_mat := Fx.flat(Color(0.4, 0.28, 0.24))
	for hand_pose: Array in [
		[Vector3(0.0, 0.14, 0.04), Vector3(0.05, 0.3, 0.02), 0.0],
		[Vector3(0.09, 0.05, 0.04), Vector3(0.05, 0.22, 0.02), -1.1],
	]:
		var hand := MeshInstance3D.new()
		var hand_mesh := BoxMesh.new()
		hand_mesh.size = hand_pose[1]
		hand_mesh.material = hand_mat
		hand.mesh = hand_mesh
		hand.position = hand_pose[0]
		hand.rotation.z = float(hand_pose[2])
		hand.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		clock.add_child(hand)


func _build_tower() -> void:
	# Turmwurzel am Ursprung — die Schwingung dreht sie als Ganzes.
	_tower = Node3D.new()
	add_child(_tower)


func _build_active() -> void:
	# Pendel-Pfannkuchen samt reitendem Gooby und Ziel-Lichtstrahl.
	_active = Node3D.new()
	add_child(_active)
	_active_mesh = _spawn_cake_mesh()
	_active.add_child(_active_mesh)
	_active_berry = MeshInstance3D.new()
	var berry_mesh := SphereMesh.new()
	berry_mesh.radius = 0.07
	berry_mesh.height = 0.14
	berry_mesh.material = Fx.glow(BERRY, 0.4)
	_active_berry.mesh = berry_mesh
	_active_berry.visible = false
	_active.add_child(_active_berry)
	gooby = Actor.new()
	_active.add_child(gooby)
	gooby.mount(0.62)
	gooby.base_emotion = "happy"
	_guide = MeshInstance3D.new()
	var guide_mesh := BoxMesh.new()
	guide_mesh.size = Vector3(0.02, 1.0, 0.02)
	guide_mesh.material = Fx.glow(Color(0.95, 0.45, 0.66), 0.8)
	_guide.mesh = guide_mesh
	_guide.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_guide)


func _build_fx() -> void:
	_star_burst = (
		Fx
		. particles(
			{
				"color": Color(1.0, 0.82, 0.4, 0.95),
				"amount": 16,
				"lifetime": 0.55,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(0.8, 1.8),
				"spread": 90.0,
				"size": Vector2(0.03, 0.08),
				"additive": true,
			}
		)
	)
	add_child(_star_burst)
	_crumb_burst = (
		Fx
		. particles(
			{
				"color": Color(0.93, 0.74, 0.44, 0.95),
				"amount": 14,
				"lifetime": 0.5,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(0.6, 1.6),
				"spread": 80.0,
				"size": Vector2(0.03, 0.07),
			}
		)
	)
	add_child(_crumb_burst)
	# Landering: pulsiert bei Perfect einmal um die Aufschlagstelle auf.
	_land_ring = MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 0.34
	ring_mesh.outer_radius = 0.4
	ring_mesh.rings = 26
	ring_mesh.ring_segments = 8
	ring_mesh.material = Fx.glow(Color(1.0, 0.78, 0.3), 1.6)
	_land_ring.mesh = ring_mesh
	_land_ring.visible = false
	_land_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_land_ring)


## Kamera: frontal auf die Turmebene z=0, exakt die Web-Kameramathematik
## (Breite = VIEW_UNITS_X Einheiten). Die Höhe folgt in sync() dem Stapel.
func frame(vp: Vector2) -> void:
	_vp = vp
	stage.apply_size(vp)
	stage.camera.rotation = Vector3.ZERO
	stage.camera.position = Vector3(0.0, _cam_center(0.0), CAM_DIST)
	stage.set_half_height(_visible_units() * 0.5, CAM_DIST)


## W17 M1: Intro-Pfannen-Totale — die Kamera schwebt erhöht und zurückgesetzt
## überm Frühstückstresen (Teller, Requisiten und Wimpel im Bild) und senkt
## sich in die frontale Spielpose; k=1 == exakte frame()/sync()-Rahmung
## (Intro läuft VOR der ersten Lage, cam_bottom ist dann 0), kein Ruck.
## NACH sync() aufrufen — sync() stellt die Kamerahöhe jeden Frame neu.
func establish(k: float) -> void:
	var e := 1.0 - ease(clampf(k, 0.0, 1.0), 0.4)
	stage.camera.position = (Vector3(0.0, _cam_center(0.0), CAM_DIST) + Vector3(0.5, 2.4, 3.6) * e)
	stage.camera.rotation_degrees = Vector3(-10.0 * e, 3.0 * e, 0.0)


## Jeden Frame: Lagen, Pendel-Pfannkuchen, Schwingung und Kamera stellen.
func sync(
	layers: Array[Dictionary],
	active: Dictionary,
	wobble_angle: float,
	cam_bottom: float,
	crumbs: Array[Dictionary],
	pulse: float,
	delta: float
) -> void:
	stage.tick(delta)
	gooby.tick(delta)
	stage.camera.position.y = _cam_center(cam_bottom)
	_tower.rotation.z = wobble_angle
	while _layer_pool.size() < layers.size():
		var node := _spawn_layer()
		_tower.add_child(node)
		_layer_pool.append(node)
	for i in _layer_pool.size():
		var node := _layer_pool[i]
		if i >= layers.size():
			node.visible = false
			continue
		var layer: Dictionary = layers[i]
		node.visible = true
		var w := float(layer["width"])
		node.position = Vector3(
			float(layer["center"]), (float(layer["index"]) - 0.5) * _layer_h, 0.0
		)
		node.scale = Vector3(w, 1.0, w)
		var topping := bool(layer["topping"])
		(node.get_node("Teig") as MeshInstance3D).set_surface_override_material(
			0, _mat_topping if topping else _mat_cake
		)
		var berry := node.get_node("Beere") as Node3D
		var butter := node.get_node("Butter") as Node3D
		berry.visible = topping and int(layer["index"]) % 10 == 0
		butter.visible = topping and not berry.visible
	# Pendel-Pfannkuchen: Breite = aktuelle Stapelbreite, Gooby reitet obenauf.
	var aw := float(active["width"])
	_active.visible = bool(active["visible"])
	_active.position = Vector3(float(active["x"]), float(active["y"]) + _layer_h * 0.5, 0.0)
	_active_mesh.scale = Vector3(aw, 1.0, aw)
	_active_berry.visible = bool(active["topping"])
	_active_berry.position.y = _layer_h * 0.6 + 0.07
	gooby.position = Vector3(0.0, _layer_h * 0.55, aw * 0.1)
	gooby.rotation.z = sin(pulse * 3.2) * 0.08
	# Ziel-Lichtstrahl vom Pendel bis zur Stapelspitze (in Weltkoordinaten).
	var top_y := float(active["stack_top"])
	var beam_h := maxf(0.05, float(active["y"]) - top_y)
	_guide.visible = _active.visible
	_guide.position = Vector3(float(active["x"]), top_y + beam_h * 0.5, 0.0)
	_guide.scale = Vector3(1.0, beam_h, 1.0)
	# Krümel: abgeschnittene Stücke fallen als Zylinder mit.
	while _crumb_pool.size() < crumbs.size():
		var crumb := _spawn_cake_mesh()
		add_child(crumb)
		_crumb_pool.append(crumb)
	for i in _crumb_pool.size():
		var node := _crumb_pool[i]
		if i >= crumbs.size():
			node.visible = false
			continue
		var crumb: Dictionary = crumbs[i]
		node.visible = true
		var cw := maxf(0.06, float(crumb["w"]))
		node.position = Vector3(float(crumb["x"]), float(crumb["y"]) + _layer_h * 0.5, 0.1)
		node.scale = Vector3(cw, 1.0, cw)
		node.rotation.z = float(crumb["age"]) * 3.0
	_sync_land_ring(delta)


## Landering: wächst 0,35 s lang auf und verschwindet (Perfect-Stempel).
func _sync_land_ring(delta: float) -> void:
	if _ring_age >= 0.35:
		_land_ring.visible = false
		return
	_ring_age += delta
	var t := clampf(_ring_age / 0.35, 0.0, 1.0)
	var s := 1.0 + t * 1.1
	_land_ring.visible = t < 1.0
	_land_ring.scale = Vector3(s, 1.0, s)


## Perfekt-Feier; `reduced` lässt Emote/Glühen, gatet aber Hüpfer, Landering
## und Partikel (Q2 — Reduced-Motion-Gate an der eigenen Fx.burst-Call-Site).
func perfect_fx(world_x: float, world_y: float, reduced := false) -> void:
	gooby.emote("ecstatic", 0.9)
	stage.pulse_glow(0.6)
	if reduced:
		return
	Fx.burst(_star_burst, Vector3(world_x, world_y + _layer_h, 0.2))
	gooby.hop(0.25, 0.15)
	# Ring zur Kamera drehen (Frontalkamera: flach läge er unsichtbar auf
	# Kante) und VOR den Stapel legen (Pfannkuchen-Vorderkante ≈ z 0,75).
	_land_ring.position = Vector3(world_x, world_y + _layer_h * 0.5, 0.85)
	_land_ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_land_ring.scale = Vector3.ONE
	_ring_age = 0.0


func topping_fx(world_x: float, world_y: float, reduced := false) -> void:
	gooby.emote("happy", 0.8)
	if reduced:
		return
	Fx.burst(_star_burst, Vector3(world_x, world_y + _layer_h, 0.2))


## Schnitt-Krümel; die fallenden Krümel-Zylinder bleiben als STATISCHES
## Feedback auch unter Reduced Motion, nur der Partikel-Burst wird gegated.
func cut_fx(world_x: float, world_y: float, reduced := false) -> void:
	if reduced:
		return
	Fx.burst(_crumb_burst, Vector3(world_x, world_y + _layer_h * 0.5, 0.2))


func topple_fx(world_x: float, world_y: float, reduced := false) -> void:
	gooby.emote("scared", 1.6)
	if reduced:
		return
	Fx.burst(_crumb_burst, Vector3(world_x, world_y, 0.3))


## Sichtbare Welteinheiten senkrecht (aus der Web-ppu-Formel).
func _visible_units() -> float:
	var ppu := _vp.x / _view_units_x
	return _vp.y / ppu


## Kameramitte so, dass Welt-y=cam_bottom auf GROUND_FRAC der Bildhöhe liegt.
func _cam_center(cam_bottom: float) -> float:
	return cam_bottom + _visible_units() * (_ground_frac - 0.5)


func _spawn_layer() -> Node3D:
	var root := Node3D.new()
	var cake := _spawn_cake_mesh()
	cake.name = "Teig"
	root.add_child(cake)
	var butter := MeshInstance3D.new()
	var butter_mesh := BoxMesh.new()
	butter_mesh.size = Vector3(0.3, 0.08, 0.3)
	butter_mesh.material = Fx.glow(BUTTER, 0.25)
	butter.mesh = butter_mesh
	butter.name = "Butter"
	butter.position.y = _layer_h * 0.5 + 0.04
	butter.visible = false
	root.add_child(butter)
	var berry := MeshInstance3D.new()
	var berry_mesh := SphereMesh.new()
	berry_mesh.radius = 0.09
	berry_mesh.height = 0.18
	berry_mesh.material = Fx.glow(BERRY, 0.4)
	berry.mesh = berry_mesh
	berry.name = "Beere"
	berry.position.y = _layer_h * 0.5 + 0.08
	berry.visible = false
	root.add_child(berry)
	return root


## Schattenwurf eines geladenen Modells rekursiv abschalten.
func _no_shadow(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_no_shadow(child)


## Ein Pfannkuchen: flacher Zylinder, Basisdurchmesser 1 — skaliert per Breite.
func _spawn_cake_mesh() -> MeshInstance3D:
	var cake := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.5
	mesh.bottom_radius = 0.46
	mesh.height = _layer_h
	mesh.radial_segments = 20
	mesh.material = _mat_cake
	cake.mesh = mesh
	return cake
