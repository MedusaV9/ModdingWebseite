extends Node3D
## ECHTER 3D-Obstgarten für den Möhrenfang (FB-4): Kenney-Food-Modelle fallen
## als 3D-Objekte vom Himmel, Gooby (echtes Rig) rennt mit dem Tiny-Treats-
## Picknickkorb über die Wiese, hinten Möhrenbeete, Zaun und Bäume. Die Kamera
## steht frontal auf die Fallebene z=0 und rahmt EXAKT die 2D-Rechnung des
## Spiels (Weltbreite = 2·WORLD_HALF_W) — Spawn-/Fang-Zahlen unangetastet.
## Die MECHANIK bleibt komplett in carrot_catch.gd/CarrotCatchLogic.

const Stage3D := preload("res://scripts/minigames/games/_3dc_stage/stage3d.gd")
const Actor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")
const Models := preload("res://scripts/minigames/games/_3dc_stage/models3d.gd")
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

var stage: Node3D
var gooby: Node3D

var _basket: Node3D
var _basket_half_w := 0.9
var _pool: Dictionary = {}
var _used: Dictionary = {}
var _halo: MeshInstance3D
var _catch_burst: GPUParticles3D
var _stars: Node3D
var _world_half_h := 5.2
var _last_basket_x := 0.0


func setup_stage(basket_half_w: float) -> void:
	_basket_half_w = basket_half_w
	stage = Stage3D.new()
	add_child(stage)
	(
		stage
		. build(
			{
				# Sommerwiese, NICHT überbelichtet: Sonne fast senkrecht,
				# damit die fallenden Leckereien kompakte Schatten werfen.
				"sky_top": Color(0.5, 0.75, 0.93),
				"sky_horizon": Color(0.88, 0.94, 0.95),
				"ground_horizon": Color(0.62, 0.8, 0.5),
				"ground_bottom": Color(0.44, 0.62, 0.36),
				"sun_dir": Vector3(-0.2, -0.9, -0.3),
				"sun_energy": 0.85,
				"ambient": 0.58,
				"fill_energy": 0.24,
				"glow": 0.28,
				"glow_threshold": 0.85,
				"shadow_distance": 24.0,
				"fog": true,
				"fog_color": Color(0.84, 0.92, 0.9),
				"fog_from": 20.0,
				"fog_to": 60.0,
				"far": 100.0,
			}
		)
	)
	_build_garden()
	_build_basket()
	_build_gooby()
	_build_fx()


func _build_garden() -> void:
	add_child(Fx.ground(Vector2(60.0, 40.0), Color(0.5, 0.74, 0.38)))
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
	# Zaunlinie hinter den Beeten.
	var fence_poses: Array = []
	for i in 12:
		fence_poses.append(Transform3D(Basis.IDENTITY, Vector3(-7.7 + float(i) * 1.4, 0.0, -6.2)))
	add_child(Models.swarm(Models.parts(DIR + "fence_simple.glb", 1.4), fence_poses))
	# Baumreihe dahinter, versetzt für Tiefe.
	var tree_poses: Array = []
	for i in 6:
		var x := -9.0 + float(i) * 3.6
		tree_poses.append(
			Transform3D(
				Basis(Vector3.UP, float(i) * 1.1), Vector3(x, 0.0, -8.5 - 1.6 * float(i % 2))
			)
		)
	add_child(Models.swarm(Models.parts(DIR + "tree_default.glb", 3.2), tree_poses))
	# Blumentupfer auf der Wiese.
	var reds: Array = []
	var yellows: Array = []
	for i in 8:
		var pose := Transform3D(
			Basis.IDENTITY, Vector3(-5.5 + float(i) * 1.6, 0.0, -1.7 - 0.9 * float(i % 3))
		)
		if i % 2 == 0:
			reds.append(pose)
		else:
			yellows.append(pose)
	add_child(Models.swarm(Models.parts(DIR + "flower_redA.glb", 0.42), reds))
	add_child(Models.swarm(Models.parts(DIR + "flower_yellowA.glb", 0.42), yellows))
	# Sonne als Glühscheibe hoch am Himmel.
	var sun := MeshInstance3D.new()
	var sun_mesh := SphereMesh.new()
	sun_mesh.radius = 1.3
	sun_mesh.height = 2.6
	sun_mesh.material = Fx.glow(Color(1.0, 0.88, 0.52), 1.6)
	sun.mesh = sun_mesh
	sun.position = Vector3(7.5, 9.5, -20.0)
	sun.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sun)
	# Zwei weiche Wolken im Fallraum-Himmel.
	for entry: Array in [[-4.0, 7.6, -16.0, 1.5], [3.5, 9.0, -18.0, 1.9]]:
		var cloud := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 1.0
		mesh.height = 1.1
		var mat := Fx.flat(Color(1.0, 1.0, 1.0, 0.9))
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mesh.material = mat
		cloud.mesh = mesh
		cloud.scale = Vector3(float(entry[3]) * 1.8, float(entry[3]) * 0.62, 1.0)
		cloud.position = Vector3(float(entry[0]), float(entry[1]), float(entry[2]))
		cloud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(cloud)


func _build_basket() -> void:
	_basket = Models.node(DIR + "picnic_basket_round.gltf", _basket_half_w * 2.0)
	add_child(_basket)


func _build_gooby() -> void:
	gooby = Actor.new()
	gooby.position = Vector3(0.0, 0.0, -0.85)
	add_child(gooby)
	gooby.mount(1.1)
	gooby.base_emotion = "happy"


func _build_fx() -> void:
	_catch_burst = (
		Fx
		. particles(
			{
				"color": Color(1.0, 0.9, 0.55, 0.95),
				"amount": 16,
				"lifetime": 0.55,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(1.2, 2.6),
				"spread": 55.0,
				"size": Vector2(0.06, 0.15),
				"additive": true,
			}
		)
	)
	add_child(_catch_burst)
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


## Bildschirm-y (Canvas-Pixel) → Welt-y: Boden liegt am unteren Bildrand.
func world_y(y_px: float, vp: Vector2, ppu: float) -> float:
	return (vp.y - y_px) / maxf(1.0, ppu)


## Jeden Frame: Items stellen, Korb + Gooby bewegen.
func sync(
	items: Array[Dictionary],
	basket_x: float,
	dizzy: bool,
	vp: Vector2,
	ppu: float,
	pulse: float,
	delta: float
) -> void:
	stage.tick(delta)
	gooby.tick(delta)
	_basket.position.x = basket_x
	# Gooby rennt hinter dem Korb her: Lauf-Blend aus der echten Korbbewegung,
	# Blick dreht in die Laufrichtung.
	var dx := basket_x - _last_basket_x
	_last_basket_x = basket_x
	gooby.position.x = basket_x
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
	for item in items:
		var key := _pool_key(item)
		var node := _take(key)
		node.visible = true
		node.position = Vector3(float(item["x"]), world_y(float(item["y"]), vp, ppu), 0.0)
		node.rotation.y = pulse * 2.4
		node.rotation.z = sin(pulse * 3.0 + float(item["x"])) * 0.2
		if str(item["kind"]) == "golden":
			golden_at = node.position
	for key: String in _pool:
		var list: Array = _pool[key]
		for i in range(int(_used.get(key, 0)), list.size()):
			(list[i] as Node3D).visible = false
	_halo.visible = golden_at.x != INF
	if _halo.visible:
		_halo.position = golden_at
		_halo.rotation = Vector3(pulse * 2.0, pulse * 3.1, 0.0)


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
	if golden:
		gooby.emote("ecstatic", 1.2)
		gooby.play_for("celebrate", 1.0)
		stage.pulse_glow(0.8)
	else:
		gooby.emote("happy", 0.5)


func junk_fx() -> void:
	gooby.emote("dizzy", 1.4)
