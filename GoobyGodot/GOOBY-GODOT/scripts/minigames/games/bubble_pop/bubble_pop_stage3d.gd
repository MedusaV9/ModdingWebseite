extends Node3D
## ECHTES 3D-UNTERWASSER für den Blasen-Platzer (FB-4, MP-B-Politur):
## Kenney-Food-Modelle schweben in Glasblasen durch ein Pastell-Aquarium —
## Sandboden mit Korallen, Seetang und versunkenem Tontopf, Fischschwarm und
## Lichtschächte, die Wasserlinie liegt als schmales Leuchtband oben im Bild.
## Gooby taucht als echtes Rig mit und schaut der gesuchten Sorte hinterher;
## unter dem Ziel-Banner rotiert das Ziel-Essen als 3D-Abzeichen. Die Kamera
## steht frontal auf die Aufstiegsebene z=0 und rahmt EXAKT die 2D-Rechnung
## (halbe Bildhöhe = WORLD_HALF_H) — alle MECHANIK-Zahlen bleiben in
## bubble_pop.gd/BubblePopLogic.

const Stage3D := preload("res://scripts/minigames/games/_3dc_stage/stage3d.gd")
const Actor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")
const Models := preload("res://scripts/minigames/games/_3dc_stage/models3d.gd")
const Kit := preload("res://scripts/minigames/games/carrot_catch/mpb_garden_kit.gd")
const DIR := "res://assets/minigames/carrot_catch/"

const CAM_DIST := 10.0
## Halbe sichtbare Welthöhe (Web: tan(45°/2)·10) — Pflichtwert aus der View.
const HALF_H := 4.142135623730951
const BUBBLE_R := 0.42
const SPIKY_R := 0.5
## Food-Modellgröße in der Blase (muss in BUBBLE_R passen).
const FOOD_SIZE := 0.52
## Ebene des Ziel-Abzeichens (vor der Blasen-Ebene, nah an der Kamera).
const BADGE_Z := 6.5

var stage: Node3D
var gooby: Node3D

var _pool: Dictionary = {}
var _used: Dictionary = {}
var _plants: Array[Node3D] = []
var _pop_burst: GPUParticles3D
var _bad_burst: GPUParticles3D
var _fish: MultiMeshInstance3D
var _look_proxy: Node3D
var _badge: Node3D
var _badge_ring: MeshInstance3D
var _badge_foods: Dictionary = {}
var _badge_px := Vector2(360.0, 190.0)
var _pulses: Array = []
var _gooby_base := Vector3(-1.55, -3.05, -1.2)


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
				"sky_top": Color(0.4, 0.7, 0.85),
				"sky_horizon": Color(0.36, 0.64, 0.78),
				"ground_horizon": Color(0.36, 0.64, 0.78),
				"ground_bottom": Color(0.24, 0.46, 0.6),
				"sun_dir": Vector3(-0.15, -0.9, -0.35),
				"sun_color": Color(0.92, 0.98, 1.0),
				"sun_energy": 0.7,
				"ambient": 0.6,
				"fill_color": Color(0.7, 0.9, 1.0),
				"fill_energy": 0.24,
				"glow": 0.32,
				"glow_threshold": 0.8,
				"shadows": false,
				# Fog DUNKLER als der Himmel eingestellt: gemessen rendert die
				# gefogte Ferne ~35 Luma heller als der Sky am Horizont — mit
				# (0.25,0.52,0.68) treffen sich beide ohne sichtbare Naht.
				"fog": true,
				"fog_color": Color(0.25, 0.52, 0.68),
				"fog_from": 9.0,
				"fog_to": 34.0,
				"far": 90.0,
			}
		)
	)
	_build_seabed()
	_build_corals()
	_build_water()
	_build_gooby()
	_build_badge()
	_build_fx()


func _build_seabed() -> void:
	# Sand kühl abgetönt — reines Beige las sich wie ein Strand ÜBER Wasser.
	add_child(Fx.ground(Vector2(200.0, 120.0), Color(0.66, 0.7, 0.58), -HALF_H - 0.15))
	# Sandhügel als flache Kugeln.
	var mounds := MultiMeshInstance3D.new()
	var mound_mesh := SphereMesh.new()
	mound_mesh.radius = 1.0
	mound_mesh.height = 2.0
	mound_mesh.material = Fx.flat(Color(0.74, 0.69, 0.54))
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
	rock_mesh.material = Fx.flat(Color(0.56, 0.6, 0.66))
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
	# Versunkener Tontopf mit Felsen — kleine Geschichte am Boden.
	var pot := Kit.prop("pot_large.glb", 0.9)
	pot.position = Vector3(2.6, -HALF_H - 0.12, -2.6)
	pot.rotation.z = 1.15
	pot.rotation.y = 0.5
	add_child(pot)
	var rock := Kit.prop("rock_largeA.glb", 1.3)
	Models.tint(rock, Color(0.45, 0.55, 0.62))
	rock.position = Vector3(-3.6, -HALF_H - 0.14, -3.4)
	add_child(rock)
	# Seetang: schwankende Kapsel-Pflanzen (im sync animiert).
	var kelp_tones: Array[Color] = [
		Color(0.28, 0.58, 0.4), Color(0.36, 0.68, 0.44), Color(0.3, 0.52, 0.5)
	]
	for i in 7:
		var plant := Node3D.new()
		plant.position = Vector3(-5.8 + float(i) * 2.0, -HALF_H - 0.1, -1.4 - 1.1 * float(i % 3))
		for leaf in 3:
			var blade := MeshInstance3D.new()
			var capsule := CapsuleMesh.new()
			capsule.radius = 0.08
			capsule.height = 1.3 + 0.5 * float(i % 3) + 0.35 * float(leaf)
			capsule.material = Fx.flat(kelp_tones[leaf])
			blade.mesh = capsule
			blade.position = Vector3(0.12 * float(leaf) - 0.12, capsule.height * 0.5, 0.0)
			blade.rotation.z = 0.1 * float(leaf) - 0.1
			blade.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			plant.add_child(blade)
		add_child(plant)
		_plants.append(plant)


## Korallenbänke: Kegel-Äste in zwei Pastelltönen, je Farbe EIN MultiMesh.
func _build_corals() -> void:
	var groups := [
		[Color(0.95, 0.62, 0.62), [-4.6, -1.8, 0.55], [-4.1, -2.2, 0.4], [3.9, -1.6, 0.5]],
		[Color(0.98, 0.78, 0.5), [4.6, -2.4, 0.6], [5.1, -1.9, 0.42], [-2.2, -3.2, 0.36]],
	]
	for group: Array in groups:
		var cone := CylinderMesh.new()
		cone.top_radius = 0.02
		cone.bottom_radius = 0.09
		cone.height = 1.0
		cone.radial_segments = 8
		cone.material = Fx.flat(group[0] as Color)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = cone
		var poses: Array = []
		for gi in range(1, group.size()):
			var entry: Array = group[gi]
			var base := Vector3(float(entry[0]), -HALF_H, float(entry[1]))
			var size := float(entry[2])
			for branch in 5:
				var lean := -0.55 + 0.275 * float(branch)
				var b := Basis(Vector3(0.0, 0.0, 1.0), lean).scaled(
					Vector3(size, size * (0.8 + 0.2 * float(branch % 3)), size)
				)
				poses.append(
					Transform3D(b, base + Vector3(lean * 0.4, size * 0.4, 0.06 * float(branch % 2)))
				)
		mm.instance_count = poses.size()
		for i in poses.size():
			mm.set_instance_transform(i, poses[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.extra_cull_margin = 20.0
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


func _build_water() -> void:
	# Wasserlinie: schmales Leuchtband knapp über der Oberkante. Die frühere
	# 120-m-Platte stand als riesige Wand mitten im Bild — die Fernkante einer
	# Fläche ÜBER der Kamera wandert im Bild Richtung Horizont (Bildmitte).
	var surface := Fx.ground(Vector2(200.0, 14.0), Color(0.95, 1.0, 1.0, 0.5), HALF_H + 0.3)
	surface.position.z = 5.0
	(surface.mesh as PlaneMesh).material = Fx.glass(Color(0.95, 1.0, 1.0, 0.3), true)
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
	# Fischschwarm zieht in der Tiefe seine Bahnen.
	_fish = Kit.fish(7, Vector3(0.0, -1.0, -5.5), Vector3(6.5, 1.6, 2.0), Color(1.0, 0.62, 0.4))
	add_child(_fish)
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
	# Blickziel: die nächste Blase der gesuchten Sorte (sync schiebt es nach).
	_look_proxy = Node3D.new()
	_look_proxy.position = Vector3(1.0, 0.0, 0.0)
	add_child(_look_proxy)
	gooby.rig.look_at_target = _look_proxy
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


## Ziel-Abzeichen: goldener Ring + rotierendes Essen, hängt unter dem Banner
## (Pixel-Anker aus der View) auf einer Ebene VOR den Blasen.
func _build_badge() -> void:
	_badge = Node3D.new()
	add_child(_badge)
	_badge_ring = Fx.ring(0.21, 0.035, Color(1.0, 0.9, 0.55))
	_badge.add_child(_badge_ring)


func set_badge_anchor(px: Vector2) -> void:
	_badge_px = px


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


## W17 M1: Intro-Tauchfahrt — die Kamera startet unten am Riff (Korallen,
## Seetang, Tontopf) mit Blick nach oben und steigt zur frontalen Spielpose,
## deren Bildoberkante das Ziel-Abzeichen trägt; k=1 == exakte Rahmung von
## frame(), damit der Übergang in die Runde ohne Ruck sitzt.
func establish(k: float) -> void:
	var e := 1.0 - ease(clampf(k, 0.0, 1.0), 0.4)
	stage.camera.position = Vector3(0.0, 0.0, CAM_DIST) + Vector3(0.0, -HALF_H * 0.62, -2.6) * e
	stage.camera.rotation_degrees = Vector3(10.0 * e, 0.0, 0.0)


## Jeden Frame: Blasen aus dem Pool stellen, Zielsorte markieren, Tang wiegen,
## Fische ziehen lassen, Abzeichen nachführen.
func sync(bubbles: Array[Dictionary], target: String, pulse: float, delta: float) -> void:
	stage.tick(delta)
	gooby.tick(delta)
	Kit.animate_fish(_fish, pulse)
	Kit.tick_pulses(_pulses, delta)
	gooby.position = _gooby_base + Vector3(0.0, sin(pulse * 1.6) * 0.12, 0.0)
	gooby.rotation.z = sin(pulse * 1.1) * 0.06
	for i in _plants.size():
		_plants[i].rotation.z = sin(pulse * 1.3 + float(i) * 1.7) * 0.12
	_sync_badge(target, pulse)
	for key: String in _used:
		_used[key] = 0
	var look_at := Vector3(INF, 0.0, 0.0)
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
			# Gooby schaut der nächstgelegenen Zielblase hinterher.
			if look_at.x == INF or node.position.y < look_at.y:
				look_at = node.position
	for key: String in _pool:
		var list: Array = _pool[key]
		for i in range(int(_used.get(key, 0)), list.size()):
			(list[i] as Node3D).visible = false
	if look_at.x != INF:
		_look_proxy.position = look_at


## Abzeichen unter dem Banner: Pixel-Anker → Punkt auf der BADGE_Z-Ebene.
func _sync_badge(target: String, pulse: float) -> void:
	if not _badge_foods.has(target):
		var model := Models.node(DIR + target + ".glb", 0.26, false)
		_badge.add_child(model)
		_badge_foods[target] = model
	for key: String in _badge_foods:
		(_badge_foods[key] as Node3D).visible = key == target
		if key == target:
			(_badge_foods[key] as Node3D).rotation.y = pulse * 1.8
	_badge.position = stage.wall_point(_badge_px, BADGE_Z)
	_badge_ring.scale = Vector3.ONE * (1.0 + sin(pulse * 3.2) * 0.05)


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
	sphere.material = Fx.flat(Color(0.56, 0.46, 0.62))
	body.mesh = sphere
	body.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(body)
	var spike_mesh := CylinderMesh.new()
	spike_mesh.top_radius = 0.0
	spike_mesh.bottom_radius = 0.07
	spike_mesh.height = SPIKY_R * 0.6
	spike_mesh.radial_segments = 6
	spike_mesh.material = Fx.flat(Color(0.4, 0.32, 0.48))
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
		Kit.spawn_pulse(self, _pulses, Vector3(wx, wy, 0.35), Color(0.7, 0.95, 1.0), 1.0)
		gooby.emote("happy", 0.6)
	else:
		Fx.burst(_bad_burst, Vector3(wx, wy, 0.3))
		gooby.emote("scared", 1.0)


func chain_fx(wx: float, wy: float) -> void:
	Fx.burst(_pop_burst, Vector3(wx, wy, 0.3))
	Kit.spawn_pulse(self, _pulses, Vector3(wx, wy, 0.35), Color(1.0, 0.85, 0.4), 2.2)
	gooby.emote("ecstatic", 1.2)
	gooby.play_for("celebrate", 0.9)
	gooby.hop(0.5, 0.35)
	stage.pulse_glow(0.9)
