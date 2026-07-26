extends Node3D
## ECHTES 3D-UNTERWASSER für den Blasen-Platzer (FB-4): Kenney-Food-Modelle
## schweben in Glasblasen durch ein Pastell-Aquarium — Sandboden, schwankender
## Seetang, Lichtschächte von oben, aufsteigender Blasenstrom und Gooby
## (echtes Rig) als tauchender Cameo. Die Kamera steht frontal auf die
## Aufstiegsebene z=0 und rahmt EXAKT die 2D-Rechnung (halbe Bildhöhe =
## WORLD_HALF_H) — alle MECHANIK-Zahlen bleiben in bubble_pop.gd/BubblePopLogic.

const Stage3D := preload("res://scripts/minigames/games/_3dc_stage/stage3d.gd")
const Actor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")
const Models := preload("res://scripts/minigames/games/_3dc_stage/models3d.gd")
const DIR := "res://assets/minigames/carrot_catch/"

const CAM_DIST := 10.0
## Halbe sichtbare Welthöhe (Web: tan(45°/2)·10) — Pflichtwert aus der View.
const HALF_H := 4.142135623730951
const BUBBLE_R := 0.42
const SPIKY_R := 0.5
## Food-Modellgröße in der Blase (muss in BUBBLE_R passen).
const FOOD_SIZE := 0.52

var stage: Node3D
var gooby: Node3D

var _pool: Dictionary = {}
var _used: Dictionary = {}
var _plants: Array[Node3D] = []
var _pop_burst: GPUParticles3D
var _bad_burst: GPUParticles3D
var _gooby_base := Vector3(-2.2, -3.1, -1.2)


func setup_stage() -> void:
	stage = Stage3D.new()
	add_child(stage)
	(
		stage
		. build(
			{
				# Aquarium-Licht: kühles Wasser, Sonne fast senkrecht, ohne
				# Schatten (schwebende Blasen hätten nichts zum Werfen).
				# Der Tiefen-Fog in Wasserfarbe lässt Boden und Wasserspiegel
				# in der Ferne verschwimmen — sonst stehen harte Kanten im Bild.
				"sky_top": Color(0.56, 0.82, 0.9),
				"sky_horizon": Color(0.42, 0.7, 0.82),
				"ground_horizon": Color(0.42, 0.7, 0.82),
				"ground_bottom": Color(0.3, 0.54, 0.68),
				"sun_dir": Vector3(-0.15, -0.9, -0.35),
				"sun_color": Color(0.92, 0.98, 1.0),
				"sun_energy": 0.7,
				"ambient": 0.62,
				"fill_color": Color(0.7, 0.9, 1.0),
				"fill_energy": 0.24,
				"glow": 0.32,
				"glow_threshold": 0.8,
				"shadows": false,
				"fog": true,
				"fog_color": Color(0.45, 0.7, 0.8),
				"fog_from": 10.0,
				"fog_to": 38.0,
				"far": 90.0,
			}
		)
	)
	_build_seabed()
	_build_water()
	_build_gooby()
	_build_fx()


func _build_seabed() -> void:
	# Sand kühl abgetönt — reines Beige las sich wie ein Strand ÜBER Wasser.
	add_child(Fx.ground(Vector2(200.0, 120.0), Color(0.72, 0.74, 0.6), -HALF_H - 0.15))
	# Sandhügel als flache Kugeln.
	var mounds := MultiMeshInstance3D.new()
	var mound_mesh := SphereMesh.new()
	mound_mesh.radius = 1.0
	mound_mesh.height = 2.0
	mound_mesh.material = Fx.flat(Color(0.8, 0.73, 0.55))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mound_mesh
	mm.instance_count = 6
	for i in 6:
		var b := Basis.IDENTITY.scaled(Vector3(1.6 + 0.4 * float(i % 3), 0.35, 1.2))
		mm.set_instance_transform(
			i,
			Transform3D(
				b, Vector3(-6.5 + float(i) * 2.7, -HALF_H - 0.12, -2.0 - 1.4 * float(i % 3))
			)
		)
	mounds.multimesh = mm
	mounds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mounds)
	# Kieselsteine.
	var rocks := MultiMeshInstance3D.new()
	var rock_mesh := SphereMesh.new()
	rock_mesh.radius = 0.22
	rock_mesh.height = 0.34
	rock_mesh.radial_segments = 10
	rock_mesh.rings = 5
	rock_mesh.material = Fx.flat(Color(0.62, 0.64, 0.68))
	var rock_mm := MultiMesh.new()
	rock_mm.transform_format = MultiMesh.TRANSFORM_3D
	rock_mm.mesh = rock_mesh
	rock_mm.instance_count = 8
	for i in 8:
		rock_mm.set_instance_transform(
			i,
			Transform3D(
				Basis(Vector3.UP, float(i) * 0.9),
				Vector3(-5.0 + float(i) * 1.5, -HALF_H - 0.06, -0.8 - 0.9 * float(i % 3))
			)
		)
	rocks.multimesh = rock_mm
	rocks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rocks)
	# Seetang: schwankende Kapsel-Pflanzen (im sync animiert).
	for i in 6:
		var plant := Node3D.new()
		plant.position = Vector3(-5.4 + float(i) * 2.2, -HALF_H - 0.1, -1.4 - 1.1 * float(i % 3))
		for leaf in 2:
			var blade := MeshInstance3D.new()
			var capsule := CapsuleMesh.new()
			capsule.radius = 0.09
			capsule.height = 1.5 + 0.5 * float(i % 3) + 0.3 * float(leaf)
			capsule.material = Fx.flat(
				Color(0.3, 0.62, 0.42) if leaf == 0 else Color(0.38, 0.7, 0.46)
			)
			blade.mesh = capsule
			blade.position = Vector3(0.14 * float(leaf) - 0.07, capsule.height * 0.5, 0.0)
			blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			plant.add_child(blade)
		add_child(plant)
		_plants.append(plant)


func _build_water() -> void:
	# Wasserspiegel oben: helle Fläche knapp über dem Bildrand — groß genug,
	# dass ihre Fernkante im Fog verschwindet statt als Streifen zu stehen.
	var surface := Fx.ground(Vector2(200.0, 120.0), Color(0.95, 1.0, 1.0, 0.55), HALF_H + 0.3)
	(surface.mesh as PlaneMesh).material = Fx.glass(Color(0.95, 1.0, 1.0, 0.28), true)
	add_child(surface)
	# Lichtschächte: schräge, additive Bahnen von oben.
	for i in 4:
		var shaft := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(0.9 + 0.4 * float(i % 2), HALF_H * 2.6)
		var mat := Fx.glass(Color(1.0, 1.0, 1.0, 0.07), true)
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		quad.material = mat
		shaft.mesh = quad
		shaft.position = Vector3(-4.4 + float(i) * 2.9, 0.6, -3.0 - 0.5 * float(i))
		shaft.rotation.z = 0.16
		shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(shaft)
	# Dauerhafter feiner Blasenstrom im Hintergrund.
	var ambient := (
		Fx
		. particles(
			{
				"color": Color(1.0, 1.0, 1.0, 0.4),
				"amount": 26,
				"lifetime": 6.0,
				"radius": 6.0,
				"speed": Vector2(0.5, 1.1),
				"spread": 8.0,
				"gravity": Vector3(0.0, 0.6, 0.0),
				"size": Vector2(0.03, 0.09),
			}
		)
	)
	ambient.position = Vector3(0.0, -HALF_H, -2.5)
	ambient.emitting = true
	add_child(ambient)


func _build_gooby() -> void:
	gooby = Actor.new()
	gooby.position = _gooby_base
	add_child(gooby)
	gooby.mount(1.0)
	gooby.base_emotion = "happy"
	# Taucherblasen über dem Cameo.
	var breath := (
		Fx
		. particles(
			{
				"color": Color(1.0, 1.0, 1.0, 0.55),
				"amount": 8,
				"lifetime": 1.6,
				"radius": 0.08,
				"speed": Vector2(0.6, 1.0),
				"spread": 10.0,
				"gravity": Vector3(0.0, 0.8, 0.0),
				"size": Vector2(0.04, 0.1),
			}
		)
	)
	breath.position = Vector3(0.3, 1.1, 0.0)
	breath.emitting = true
	gooby.add_child(breath)


func _build_fx() -> void:
	_pop_burst = (
		Fx
		. particles(
			{
				"color": Color(1.0, 0.98, 0.8, 0.95),
				"amount": 18,
				"lifetime": 0.55,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(1.4, 3.0),
				"spread": 180.0,
				"gravity": Vector3(0.0, 0.5, 0.0),
				"size": Vector2(0.05, 0.14),
				"additive": true,
			}
		)
	)
	add_child(_pop_burst)
	_bad_burst = (
		Fx
		. particles(
			{
				"color": Color(0.9, 0.4, 0.4, 0.9),
				"amount": 14,
				"lifetime": 0.5,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(1.0, 2.2),
				"spread": 180.0,
				"size": Vector2(0.06, 0.14),
			}
		)
	)
	add_child(_bad_burst)


## Kamera frontal auf die Aufstiegsebene: Bildmitte = Welt-Ursprung, halbe
## Bildhöhe = HALF_H — exakt die 2D-Projektion des Spiels.
func frame(vp: Vector2) -> void:
	stage.apply_size(vp)
	stage.camera.position = Vector3(0.0, 0.0, CAM_DIST)
	stage.camera.rotation = Vector3.ZERO
	stage.set_half_height(HALF_H, CAM_DIST)


## Jeden Frame: Blasen aus dem Pool stellen, Zielsorte markieren, Tang wiegen.
func sync(bubbles: Array[Dictionary], target: String, pulse: float, delta: float) -> void:
	stage.tick(delta)
	gooby.tick(delta)
	gooby.position = _gooby_base + Vector3(0.0, sin(pulse * 1.6) * 0.12, 0.0)
	gooby.rotation.z = sin(pulse * 1.1) * 0.06
	for i in _plants.size():
		_plants[i].rotation.z = sin(pulse * 1.3 + float(i) * 1.7) * 0.12
	for key: String in _used:
		_used[key] = 0
	for bubble in bubbles:
		var key := _pool_key(bubble)
		var node := _take(key)
		var wobble := sin(pulse * 2.2 + float(bubble["wobble"])) * 0.06
		node.visible = true
		node.position = Vector3(float(bubble["x"]) + wobble, float(bubble["y"]), 0.0)
		if key == "spiky":
			node.rotation.z = pulse * 0.4
			continue
		var food := node.get_node("Food") as Node3D
		food.rotation.y = pulse * 1.3 + float(bubble["wobble"])
		var halo := node.get_node("Halo") as Node3D
		halo.visible = str(bubble["food"]) == target
		if halo.visible:
			halo.scale = Vector3.ONE * (1.0 + sin(pulse * 4.0) * 0.06)
			halo.rotation.z = pulse * 1.5
	for key: String in _pool:
		var list: Array = _pool[key]
		for i in range(int(_used.get(key, 0)), list.size()):
			(list[i] as Node3D).visible = false


func _pool_key(bubble: Dictionary) -> String:
	if str(bubble["kind"]) == "spiky":
		return "spiky"
	return str(bubble["food"])


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
	if key == "spiky":
		return _spawn_spiky()
	var root := Node3D.new()
	var shell := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = BUBBLE_R
	sphere.height = BUBBLE_R * 2.0
	sphere.material = Fx.glass(Color(0.85, 0.95, 1.0, 0.3))
	shell.mesh = sphere
	shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(shell)
	var food := Models.node(DIR + key + ".glb", FOOD_SIZE, false)
	food.name = "Food"
	root.add_child(food)
	var halo := Fx.ring(BUBBLE_R * 1.24, 0.05, Color(1.0, 0.95, 0.7))
	halo.name = "Halo"
	halo.visible = false
	root.add_child(halo)
	return root


func _spawn_spiky() -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = SPIKY_R * 0.78
	sphere.height = SPIKY_R * 1.56
	sphere.material = Fx.flat(Color(0.5, 0.47, 0.58))
	body.mesh = sphere
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	var spike_mesh := CylinderMesh.new()
	spike_mesh.top_radius = 0.0
	spike_mesh.bottom_radius = 0.07
	spike_mesh.height = SPIKY_R * 0.6
	spike_mesh.radial_segments = 6
	spike_mesh.material = Fx.flat(Color(0.38, 0.34, 0.46))
	for i in 8:
		var a := TAU * float(i) / 8.0
		var spike := MeshInstance3D.new()
		spike.mesh = spike_mesh
		spike.position = Vector3(cos(a), sin(a), 0.0) * SPIKY_R * 0.86
		spike.rotation.z = a - PI * 0.5
		spike.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(spike)
	return root


## Platz-Effekt an einer Weltposition. `good` = Treffer, sonst roter Puff.
func pop_fx(wx: float, wy: float, good: bool) -> void:
	if good:
		Fx.burst(_pop_burst, Vector3(wx, wy, 0.3))
		gooby.emote("happy", 0.6)
	else:
		Fx.burst(_bad_burst, Vector3(wx, wy, 0.3))
		gooby.emote("scared", 1.0)


func chain_fx(wx: float, wy: float) -> void:
	Fx.burst(_pop_burst, Vector3(wx, wy, 0.3))
	gooby.emote("ecstatic", 1.2)
	gooby.play_for("celebrate", 0.9)
	stage.pulse_glow(0.9)
