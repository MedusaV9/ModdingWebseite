extends Node3D
## ECHTER 3D-OBSTGARTEN für den Möhrenfang (FB-4, MP-B-Politur): Kenney-Food-
## Modelle fallen als 3D-Objekte vom Himmel, Gooby (echtes Rig) rennt mit dem
## Tiny-Treats-Picknickkorb über die Wiese und schaut dem tiefsten Stück
## entgegen. Dahinter staffeln sich Möhrenbeete, Zaun, gemischte Obstbäume,
## Büsche und eine Hügelkette im Fog; Schmetterlinge flattern über den Blumen.
## Die Kamera steht frontal auf die Fallebene z=0 und rahmt EXAKT die
## 2D-Rechnung des Spiels (Weltbreite = 2·WORLD_HALF_W) — Spawn-/Fang-Zahlen
## unangetastet. Die MECHANIK bleibt in carrot_catch.gd/CarrotCatchLogic.
##
## W17/G4-Politur (NUR Präsentation): Vogelzug + zwei Drachen füllen das
## obere Bilddrittel (M2, hochkant war der halbe Bildschirm leerer Himmel),
## ein Staubpuff quittiert durchgefallene Ware (M3) und establish() fliegt
## die Kamera im Intro-Beat in die Spielpose (M1).

const Stage3D := preload("res://scripts/minigames/games/_3dc_stage/stage3d.gd")
const Actor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")
const Models := preload("res://scripts/minigames/games/_3dc_stage/models3d.gd")
const Kit := preload("res://scripts/minigames/games/carrot_catch/mpb_garden_kit.gd")
const DIR := "res://assets/minigames/carrot_catch/"

const CAM_DIST := 9.0
## Modellgröße je Item-Schlüssel (Meter, größte Kante).
const ITEM_SIZE := {
	"carrot": 0.52,
	"apple": 0.42,
	"banana": 0.5,
	"cheese": 0.46,
	"watermelon": 0.62,
	"donut-sprinkles": 0.46,
	"cupcake": 0.44,
	"burger": 0.5,
	"ice-cream": 0.5,
	"cake": 0.55,
	"soda-can-crushed": 0.4,
	"fish-bones": 0.52,
}
## Korb-Squash nach einem Fang (Sekunden).
const BASKET_POP_SEC := 0.22
## W17 M2: Himmels-Schmuck — Zugvögel in V-Formation + Drachen (Tiefe/Anzahl).
const SKY_Z := -14.0
const BIRDS := 7
## Referenz-Halbhöhe (Hochkant-Phone): der Himmels-Maßstab ist darauf geeicht.
const SKY_REF_HALF_H := 7.0

var stage: Node3D
var gooby: Node3D

var _basket: Node3D
var _basket_half_w := 0.9
var _pool: Dictionary = {}
var _used: Dictionary = {}
var _halo: MeshInstance3D
var _catch_burst: GPUParticles3D
var _junk_burst: GPUParticles3D
var _miss_burst: GPUParticles3D
var _stars: Node3D
var _butterflies: MultiMeshInstance3D
var _look_proxy: Node3D
var _pulses: Array = []
var _basket_pop := 0.0
var _world_half_h := 5.2
var _last_basket_x := 0.0
var _sky: Node3D
var _birds: MultiMeshInstance3D
var _kites: Array = []


func setup_stage(basket_half_w: float) -> void:
	_basket_half_w = basket_half_w
	stage = Stage3D.new()
	add_child(stage)
	(
		stage
		. build(
			{
				# Goldene Sommerwiese, NICHT überbelichtet: weniger Ambient und
				# sattere Grüntöne — die erste Fassung war ~40 Luma zu hell.
				"sky_top": Color(0.42, 0.68, 0.91),
				"sky_horizon": Color(0.82, 0.9, 0.86),
				"ground_horizon": Color(0.48, 0.68, 0.38),
				"ground_bottom": Color(0.36, 0.54, 0.29),
				"sun_dir": Vector3(-0.35, -0.8, -0.4),
				"sun_color": Color(1.0, 0.95, 0.84),
				"sun_energy": 0.88,
				"ambient": 0.28,
				"fill_energy": 0.24,
				"glow": 0.26,
				"glow_threshold": 0.85,
				"shadow_distance": 26.0,
				"fog": true,
				"fog_color": Color(0.74, 0.84, 0.75),
				"fog_from": 24.0,
				"fog_to": 80.0,
				"far": 100.0,
			}
		)
	)
	_build_garden()
	_build_props()
	_build_sky()
	_build_basket()
	_build_gooby()
	_build_fx()


func _build_garden() -> void:
	# Große Wiese: die Fernkante verschwindet im Fog statt als Band zu stehen.
	add_child(Fx.ground(Vector2(140.0, 90.0), Color(0.38, 0.58, 0.28)))
	# Gemähte Bahnen geben dem Rasen Richtung und Tiefe.
	var stripes := MultiMeshInstance3D.new()
	var stripe_mesh := PlaneMesh.new()
	stripe_mesh.size = Vector2(70.0, 1.9)
	stripe_mesh.material = Fx.flat(Color(0.34, 0.53, 0.24))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = stripe_mesh
	mm.instance_count = 6
	for i in 6:
		mm.set_instance_transform(
			i, Transform3D(Basis.IDENTITY, Vector3(0.0, 0.012, 1.4 - float(i) * 3.6))
		)
	stripes.multimesh = mm
	stripes.extra_cull_margin = 40.0
	stripes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(stripes)
	# Hügelkette am Horizont schließt das Bild nach hinten.
	add_child(
		Kit.hills([[-16.0, -34.0, 15.0, 3.4], [8.0, -40.0, 20.0, 4.4]], Color(0.36, 0.55, 0.3))
	)
	# Möhrenbeete: Erdkacheln + Möhrengrün als Massen-Requisite (MultiMesh).
	var dirt_poses: Array = []
	var crop_poses: Array = []
	for row in 2:
		for i in 10:
			var at := Vector3(-6.3 + float(i) * 1.4, 0.0, -3.4 - float(row) * 1.5)
			dirt_poses.append(Transform3D(Basis.IDENTITY, at))
			if (i + row) % 2 == 0:
				crop_poses.append(Transform3D(Basis.IDENTITY, at + Vector3(0.0, 0.02, 0.0)))
	add_child(Models.swarm(Models.parts(DIR + "crops_dirtSingle.glb", 1.3), dirt_poses))
	add_child(Models.swarm(Models.parts(DIR + "crop_carrot.glb", 0.8), crop_poses))
	# Zaunlinie hinter den Beeten — mit Gartentor als Blickfang.
	var fence_poses: Array = []
	for i in 12:
		if i == 7:
			continue
		fence_poses.append(Transform3D(Basis.IDENTITY, Vector3(-7.7 + float(i) * 1.4, 0.0, -6.2)))
	add_child(Models.swarm(Models.parts(DIR + "fence_simple.glb", 1.4), fence_poses))
	var gate := Kit.prop("fence_gate.glb", 1.5)
	gate.position = Vector3(2.1, 0.0, -6.2)
	add_child(gate)
	# Gemischte Obstbaumreihen, versetzt für Tiefenstaffelung.
	var default_poses: Array = []
	for i in 4:
		default_poses.append(
			Transform3D(
				Basis(Vector3.UP, float(i) * 1.1),
				Vector3(-9.0 + float(i) * 5.2, 0.0, -8.5 - 1.6 * float(i % 2))
			)
		)
	add_child(Models.swarm(Models.parts(DIR + "tree_default.glb", 3.2), default_poses))
	var oak_poses: Array = [
		Transform3D(Basis(Vector3.UP, 0.6), Vector3(-5.6, 0.0, -10.5)),
		Transform3D(Basis(Vector3.UP, 2.1), Vector3(6.4, 0.0, -9.2)),
		Transform3D(Basis(Vector3.UP, 3.6), Vector3(11.5, 0.0, -12.5)),
	]
	add_child(Models.swarm(Kit.prop_parts("tree_oak.glb", 4.0), oak_poses))
	var fat_poses: Array = [
		Transform3D(Basis(Vector3.UP, 1.4), Vector3(-11.0, 0.0, -13.0)),
		Transform3D(Basis(Vector3.UP, 4.2), Vector3(2.0, 0.0, -14.5)),
	]
	add_child(Models.swarm(Kit.prop_parts("tree_fat.glb", 4.6), fat_poses))
	# Büsche zwischen Zaun und Bäumen füllen die Mitteldistanz.
	var bush_poses: Array = []
	for i in 5:
		bush_poses.append(
			Transform3D(
				Basis(Vector3.UP, float(i) * 0.8),
				Vector3(-8.6 + float(i) * 3.9, 0.0, -7.4 - 0.6 * float(i % 2))
			)
		)
	add_child(Models.swarm(Kit.prop_parts("plant_bush.glb", 1.1), bush_poses))
	# Grasbüschel über die Spielwiese streuen (deterministisch).
	var grass_poses: Array = []
	for i in 12:
		var gx := -6.8 + float(i) * 1.23 + 0.5 * float(i % 3)
		var gz := -0.4 - 0.85 * float(i % 4)
		grass_poses.append(Transform3D(Basis(Vector3.UP, float(i) * 1.2), Vector3(gx, 0.0, gz)))
	add_child(Models.swarm(Kit.prop_parts("grass_large.glb", 0.5), grass_poses))
	# Blumentupfer in drei Farben.
	var reds: Array = []
	var yellows: Array = []
	var purples: Array = []
	for i in 12:
		var pose := Transform3D(
			Basis.IDENTITY, Vector3(-6.2 + float(i) * 1.15, 0.0, -1.5 - 0.9 * float(i % 3))
		)
		if i % 3 == 0:
			reds.append(pose)
		elif i % 3 == 1:
			yellows.append(pose)
		else:
			purples.append(pose)
	add_child(Models.swarm(Models.parts(DIR + "flower_redA.glb", 0.42), reds))
	add_child(Models.swarm(Models.parts(DIR + "flower_yellowA.glb", 0.42), yellows))
	add_child(Models.swarm(Kit.prop_parts("flower_purpleA.glb", 0.42), purples))
	# Sonne hoch am Himmel, klein und warm statt ausgewaschen.
	var sun := MeshInstance3D.new()
	var sun_mesh := SphereMesh.new()
	sun_mesh.radius = 1.0
	sun_mesh.height = 2.0
	sun_mesh.material = Fx.glow(Color(1.0, 0.86, 0.48), 1.3)
	sun.mesh = sun_mesh
	sun.position = Vector3(8.5, 12.5, -26.0)
	sun.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sun)
	# Weiche Wolken hoch über dem Fallraum.
	for entry: Array in [
		[-5.0, 10.2, -20.0, 1.5], [4.0, 12.4, -22.0, 1.9], [-1.0, 14.0, -24.0, 1.3]
	]:
		var cloud := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 1.0
		mesh.height = 1.1
		var mat := Fx.flat(Color(1.0, 1.0, 1.0, 0.85))
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material = mat
		cloud.mesh = mesh
		cloud.scale = Vector3(float(entry[3]) * 1.8, float(entry[3]) * 0.62, 1.0)
		cloud.position = Vector3(float(entry[0]), float(entry[1]), float(entry[2]))
		cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(cloud)


## Einzel-Requisiten: Bank, Baumstumpf, Steine, Vogel auf dem Zaun,
## Schmetterlinge über den Blumen.
func _build_props() -> void:
	var bench := Kit.prop("bench.glb", 1.4)
	bench.position = Vector3(-4.9, 0.0, -5.5)
	bench.rotation.y = 0.18
	add_child(bench)
	var stump := Kit.prop("stump_round.glb", 0.8)
	stump.position = Vector3(5.6, 0.0, -4.7)
	add_child(stump)
	var rock := Kit.prop("rock_smallA.glb", 0.55)
	rock.position = Vector3(-7.2, 0.0, -2.2)
	add_child(rock)
	var bird := Kit.prop("bird.gltf", 0.34)
	bird.position = Vector3(2.95, 0.78, -6.15)
	bird.rotation.y = -0.5
	add_child(bird)
	_butterflies = Kit.butterflies(
		[Vector3(-3.9, 0.0, -1.6), Vector3(1.8, 0.0, -2.4), Vector3(4.6, 0.0, -1.5)],
		Color(0.98, 0.75, 0.35)
	)
	add_child(_butterflies)


## W17 M2: Vogelzug + Drachen füllen das obere Bilddrittel (hochkant stand
## dort nur leerer Himmel). Alles deterministisch aus Index-Trigonometrie
## (kein RNG); unter Reduced Motion friert _animate_sky per pulse=0 ein —
## die Silhouetten bleiben als statische Füllung stehen.
func _build_sky() -> void:
	_sky = Node3D.new()
	_sky.position = Vector3(0.0, _world_half_h * 2.45, SKY_Z)
	add_child(_sky)
	var quad := QuadMesh.new()
	quad.size = Vector2(0.34, 0.2)
	var mat := Fx.flat(Color(0.25, 0.3, 0.36))
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = BIRDS * 2
	_birds = MultiMeshInstance3D.new()
	_birds.multimesh = mm
	_birds.extra_cull_margin = 60.0
	_birds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sky.add_child(_birds)
	for i in 2:
		var kite := _build_kite(Color(0.94, 0.42, 0.36) if i == 0 else Color(0.42, 0.62, 0.9))
		kite.position = Vector3(-2.7 + 5.4 * float(i), -1.2 - 0.5 * float(i), 0.6)
		kite.set_meta("base_y", kite.position.y)
		_sky.add_child(kite)
		_kites.append(kite)
	_animate_sky(0.0)


## Papierdrachen: Rauten-Quad (45° gedreht, dann senkrecht gestreckt) plus
## Schweif aus drei Schleifchen — alles unshaded, ohne Schattenwurf.
func _build_kite(color: Color) -> Node3D:
	var root := Node3D.new()
	var body := Node3D.new()
	body.scale = Vector3(0.78, 1.3, 1.0)
	root.add_child(body)
	var mat := Fx.flat(color)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var diamond := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.62, 0.62)
	quad.material = mat
	diamond.mesh = quad
	diamond.rotation.z = PI * 0.25
	diamond.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	body.add_child(diamond)
	var tail_mat := Fx.flat(Color(1.0, 0.97, 0.88))
	tail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	for k in 3:
		var bow := MeshInstance3D.new()
		var bow_quad := QuadMesh.new()
		bow_quad.size = Vector2(0.16, 0.1)
		bow_quad.material = tail_mat
		bow.mesh = bow_quad
		bow.position = Vector3(0.04 * float(k % 2), -0.68 - 0.28 * float(k), 0.0)
		bow.rotation.z = 0.5 if k % 2 == 0 else -0.5
		bow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(bow)
	return root


## Vogelzug in V-Formation zieht langsam übers Bild (wrappt an den Rändern),
## die Drachen pendeln an ihrer Schnur. Rein deterministisch aus dem Puls —
## Reduced Motion ruft mit pulse=0 auf und alles steht still.
func _animate_sky(pulse: float) -> void:
	if _birds == null:
		return
	var mm := _birds.multimesh
	var drift := wrapf(pulse * 0.45, -7.0, 7.0)
	for i in BIRDS:
		@warning_ignore("integer_division")
		var rank := (i + 1) / 2
		var side := -1.0 if i % 2 == 1 else 1.0
		var bob := sin(pulse * 0.9 + float(i)) * 0.08
		var pos := Vector3(drift + side * 0.62 * float(rank), -0.3 * float(rank) + bob, 0.0)
		var flap := sin(pulse * 6.0 + float(i) * 0.7) * 0.55
		for wing in 2:
			var sign_f := 1.0 if wing == 0 else -1.0
			var roll := Basis(Vector3(0.0, 0.0, 1.0), flap * sign_f)
			var wing_pos := pos + roll * Vector3(sign_f * 0.16, 0.0, 0.0)
			mm.set_instance_transform(i * 2 + wing, Transform3D(roll, wing_pos))
	for k in _kites.size():
		var kite := _kites[k] as Node3D
		var phase := float(k) * 2.1
		kite.rotation.z = sin(pulse * 0.8 + phase) * 0.16
		kite.position.y = float(kite.get_meta("base_y", -1.2)) + sin(pulse * 1.3 + phase) * 0.18


## Der Himmels-Schmuck hängt IMMER im oberen Bilddrittel: Anker und Maßstab
## folgen der sichtbaren Halbhöhe (hochkant hoch oben, quer schmaler Streifen).
func _frame_sky() -> void:
	if _sky == null:
		return
	_sky.position = Vector3(0.0, _world_half_h * 2.45, SKY_Z)
	_sky.scale = Vector3.ONE * maxf(0.32, _world_half_h / SKY_REF_HALF_H)


func _build_basket() -> void:
	_basket = Models.node(DIR + "picnic_basket_round.gltf", _basket_half_w * 2.0)
	add_child(_basket)
	_basket.add_child(Fx.blob_shadow(_basket_half_w * 0.9, 0.26))


func _build_gooby() -> void:
	gooby = Actor.new()
	# NEBEN dem Korb, nicht dahinter: frontal gesehen stand Gooby sonst
	# mitten IM Korb (gleiche x, kaum Tiefenversatz).
	gooby.position = Vector3(-1.2, 0.0, -0.5)
	add_child(gooby)
	gooby.mount(1.1)
	gooby.base_emotion = "happy"
	_look_proxy = Node3D.new()
	_look_proxy.position = Vector3(0.0, 4.0, 0.0)
	add_child(_look_proxy)
	gooby.rig.look_at_target = _look_proxy


func _build_fx() -> void:
	_catch_burst = (
		Fx
		. particles(
			{
				"color": Color(1.0, 0.9, 0.55, 0.95),
				"amount": 18,
				"lifetime": 0.55,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(1.4, 2.8),
				"spread": 55.0,
				"size": Vector2(0.06, 0.15),
				"additive": true,
			}
		)
	)
	add_child(_catch_burst)
	_junk_burst = (
		Fx
		. particles(
			{
				"color": Color(0.62, 0.5, 0.4, 0.9),
				"amount": 12,
				"lifetime": 0.45,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(1.0, 2.0),
				"spread": 70.0,
				"size": Vector2(0.05, 0.12),
			}
		)
	)
	add_child(_junk_burst)
	# W17 M3: Staubpuff am Boden, wenn im Zeitmodus gute Ware durchfällt.
	_miss_burst = (
		Fx
		. particles(
			{
				"color": Color(0.72, 0.62, 0.48, 0.85),
				"amount": 10,
				"lifetime": 0.5,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(0.8, 1.6),
				"spread": 75.0,
				"size": Vector2(0.05, 0.14),
			}
		)
	)
	add_child(_miss_burst)
	# Goldene Möhre: Leuchtring, der um das Item kreist.
	_halo = Fx.ring(0.5, 0.06, Color(1.0, 0.82, 0.25))
	_halo.visible = false
	add_child(_halo)
	# Dizzy-Sternchen über dem Korb nach Junk.
	_stars = Node3D.new()
	for i in 3:
		var star := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 0.05
		mesh.height = 0.1
		mesh.material = Fx.glow(Color(1.0, 0.85, 0.35), 1.5)
		star.mesh = mesh
		star.position = Vector3(
			cos(TAU * float(i) / 3.0) * 0.3, 0.0, sin(TAU * float(i) / 3.0) * 0.3
		)
		star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_stars.add_child(star)
	_stars.visible = false
	add_child(_stars)


## Kamera frontal auf die Fallebene: sichtbare Breite = 2·WORLD_HALF_W wie in
## der 2D-Rechnung; die Höhe folgt dem Seitenverhältnis (Canvas-Einheiten).
func frame(vp: Vector2, ppu: float) -> void:
	stage.apply_size(vp)
	_world_half_h = vp.y * 0.5 / maxf(1.0, ppu)
	stage.camera.position = Vector3(0.0, _world_half_h, CAM_DIST)
	stage.camera.rotation = Vector3.ZERO
	stage.set_half_height(_world_half_h, CAM_DIST)
	_frame_sky()


## W17 M1: Intro-Anflug — die Kamera schwebt aus einer leicht erhöhten
## Garten-Totale in die frontale Spielpose; k=1 == exakte Rahmung von frame().
func establish(k: float) -> void:
	var e := 1.0 - ease(clampf(k, 0.0, 1.0), 0.4)
	stage.camera.position = Vector3(0.0, _world_half_h, CAM_DIST) + Vector3(0.0, 2.4, 3.2) * e
	stage.camera.rotation_degrees = Vector3(-9.0 * e, 0.0, 0.0)


## W17 M3: Staubpuff am Boden, wo gute Ware durchgefallen ist (Zeitmodus).
func miss_fx(x: float) -> void:
	Fx.burst(_miss_burst, Vector3(x, 0.12, 0.25))


## Bildschirm-y (Canvas-Pixel) → Welt-y: Boden liegt am unteren Bildrand.
func world_y(y_px: float, vp: Vector2, ppu: float) -> float:
	return (vp.y - y_px) / maxf(1.0, ppu)


## Jeden Frame: Items stellen, Korb + Gooby bewegen, Blick aufs tiefste Stück.
## `reduced` friert den Himmels-Schmuck ein (Reduced Motion, W17 M2).
func sync(
	items: Array[Dictionary],
	basket_x: float,
	dizzy: bool,
	vp: Vector2,
	ppu: float,
	pulse: float,
	delta: float,
	reduced := false
) -> void:
	stage.tick(delta)
	gooby.tick(delta)
	Kit.animate_butterflies(_butterflies, pulse)
	Kit.tick_pulses(_pulses, delta)
	_animate_sky(0.0 if reduced else pulse)
	_basket.position.x = basket_x
	# Fang-Squash: der Korb hüpft kurz, wenn etwas hineinfällt.
	if _basket_pop > 0.0:
		_basket_pop = maxf(0.0, _basket_pop - delta)
		var f := 1.0 - _basket_pop / BASKET_POP_SEC
		var squash := sin(f * PI) * 0.18
		_basket.scale = Vector3(1.0 + squash, 1.0 - squash * 0.7, 1.0 + squash)
	else:
		_basket.scale = Vector3.ONE
	# Gooby rennt NEBEN dem Korb mit: Lauf-Blend aus der echten Korbbewegung,
	# Blick dreht in die Laufrichtung. Am linken Rand wechselt er die Seite,
	# damit er nie aus dem Bild geschoben wird.
	var dx := basket_x - _last_basket_x
	_last_basket_x = basket_x
	var half: float = stage.half_width()
	var side := -1.2 if basket_x > -half + 2.2 else 1.2
	gooby.position.x = lerpf(gooby.position.x, basket_x + side, minf(1.0, delta * 10.0))
	gooby.run(clampf(absf(dx) / maxf(0.001, delta) / 5.0, 0.0, 1.0))
	gooby.face(clampf(dx * 30.0, -0.55, 0.55))
	if dizzy:
		_stars.visible = true
		_stars.position = Vector3(basket_x, 1.5, -0.4)
		_stars.rotation.y = pulse * 4.0
	else:
		_stars.visible = false
	# Item-Pool: je Schlüssel Knoten wiederverwenden, Rest verstecken.
	for key: String in _used:
		_used[key] = 0
	var golden_at := Vector3(INF, 0.0, 0.0)
	var look_at := Vector3(INF, 0.0, 0.0)
	for item in items:
		var key := _pool_key(item)
		var node := _take(key)
		node.visible = true
		node.position = Vector3(float(item["x"]), world_y(float(item["y"]), vp, ppu), 0.0)
		node.rotation.y = pulse * 2.4
		node.rotation.z = sin(pulse * 3.0 + float(item["x"])) * 0.2
		if str(item["kind"]) == "golden":
			golden_at = node.position
		var is_good := str(item["kind"]) == "good" or str(item["kind"]) == "golden"
		if is_good and (look_at.x == INF or node.position.y < look_at.y):
			look_at = node.position
	for key: String in _pool:
		var list: Array = _pool[key]
		for i in range(int(_used.get(key, 0)), list.size()):
			(list[i] as Node3D).visible = false
	_halo.visible = golden_at.x != INF
	if _halo.visible:
		_halo.position = golden_at
		_halo.rotation = Vector3(pulse * 2.0, pulse * 3.1, 0.0)
	# Vorfreude: Gooby schaut dem tiefsten guten Stück entgegen.
	if look_at.x != INF:
		_look_proxy.position = look_at
	else:
		_look_proxy.position = Vector3(basket_x, 4.0, 0.0)


func _pool_key(item: Dictionary) -> String:
	var kind := str(item["kind"])
	if kind == "golden":
		return "golden"
	if kind == "rotten":
		return "rotten"
	return str(item["key"])


func _take(key: String) -> Node3D:
	if not _pool.has(key):
		_pool[key] = []
		_used[key] = 0
	var list: Array = _pool[key]
	var idx := int(_used[key])
	_used[key] = idx + 1
	if idx < list.size():
		return list[idx]
	var node := _spawn(key)
	add_child(node)
	list.append(node)
	return node


func _spawn(key: String) -> Node3D:
	if key == "golden":
		var golden := Models.node(DIR + "carrot.glb", float(ITEM_SIZE["carrot"]) * 1.15, false)
		Models.tint(golden, Color(1.0, 0.8, 0.2), 0.5)
		return golden
	if key == "rotten":
		var rotten := Models.node(DIR + "carrot.glb", float(ITEM_SIZE["carrot"]), false)
		Models.tint(rotten, Color(0.45, 0.38, 0.2))
		return rotten
	return Models.node(DIR + key + ".glb", float(ITEM_SIZE.get(key, 0.45)), false)


## Bildschirmanker (Canvas-Einheiten) über dem Korb für float_text.
func basket_screen() -> Vector2:
	return stage.to_screen(_basket.global_position + Vector3(0.0, 1.1, 0.0))


func catch_fx(golden: bool) -> void:
	Fx.burst(_catch_burst, _basket.global_position + Vector3(0.0, 0.7, 0.0))
	_basket_pop = BASKET_POP_SEC
	var ring_color := Color(1.0, 0.82, 0.25) if golden else Color(1.0, 0.97, 0.8)
	Kit.spawn_pulse(
		self, _pulses, _basket.global_position + Vector3(0.0, 0.75, 0.3), ring_color, 1.1
	)
	if golden:
		gooby.emote("ecstatic", 1.2)
		gooby.play_for("celebrate", 1.0)
		gooby.hop(0.5, 0.4)
		stage.pulse_glow(0.8)
	else:
		gooby.emote("happy", 0.5)


func junk_fx() -> void:
	Fx.burst(_junk_burst, _basket.global_position + Vector3(0.0, 0.7, 0.0))
	_basket_pop = BASKET_POP_SEC
	gooby.emote("dizzy", 1.4)
