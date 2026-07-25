extends Node3D
## 3D-Welt des Hafen-Hüpfers (Agent 3D-B): ein Morgenkanal zwischen zwei
## Kaimauern — dieselbe Bauart wie die Web-Fassung
## (GOOBY/src/minigames/games/harborHopper.js), nur mit MultiMesh-Bändern
## statt N Szenenknoten.
##
## Achsen: x = quer (Logik-Meter), y = hoch, −z = fahrtrichtung. Die Logik
## zählt `rel = item.z − boat.z` NACH VORNE positiv; der View spiegelt das
## beim Setzen (world_z = −rel) und fasst keine Zahl an.
##
## Kulisse (recycelt): Wasser + Schaumstreifen, Kaimauern mit Kappe,
## Poller-Reihen, Hafenstädtchen hinter der Mauer.
## Requisiten (feste Pools): Kisten, Netzringe, Bojen, Molen, Wellenkämme.

const Models := preload("res://scripts/minigames/games/_3db_stage/model_bank.gd")
const MultiProp := preload("res://scripts/minigames/games/_3db_stage/multi_prop.gd")
const ScrollBand := preload("res://scripts/minigames/games/_3db_stage/scroll_band.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")

const LOOP_LEN := 96.0
const DESPAWN_Z := 8.0
## Kaimauer: Oberkante 1,28 m, Breite 2,3 m (Web-Maße).
const WALL_W := 2.3
const WALL_H := 1.5
const WALL_LEN := 200.0
const CAP_H := 0.18
## Web: `WALL_X = CHANNEL_HALF_W + 1.15`.
const QUAY_PAD := 1.15

## Web-Wasser: `#2F8F8A` auf einem MeshBasicMaterial — also UNBELEUCHTET.
## Genau daran hing der Unterschied: als beleuchtete Fläche multipliziert
## Godot die Sonne drauf und der Kanal kippte in ein dunkles Tintenblau,
## während das Web ein helles Morgen-Türkis zeigt.
const WATER := Color(0.184, 0.561, 0.541)
const WATER_FAR := Color(0.28, 0.64, 0.62)
const QUAY := Color(0.79, 0.7, 0.57)
const QUAY_TOP := Color(0.72, 0.63, 0.51)
const POST := Color(0.48, 0.36, 0.26)
## Wie weit hinter der Kaimauer das Hafenstädtchen steht (m). Das Web malt
## dort nur eine flache Silhouette bei z = 46; echte Häuser dürfen es besser
## machen — aber erst SO weit draußen liest sich der Kanal als Kanal und nicht
## als Häuserschlucht, und der Tiefennebel nimmt ihnen die harte Schattenseite.
const TOWN_OFFSET := 21.0
## Farbe des Hafenstädtchens im Morgendunst.
const MIST := Color(0.8, 0.88, 0.88)

const BUOY := "res://assets/minigames/harbor_hopper/watercraft-kit/buoy.glb"
const BUOY_FLAG := "res://assets/minigames/harbor_hopper/watercraft-kit/buoy-flag.glb"
const CRATE := "res://assets/minigames/harbor_hopper/car-kit/box.glb"
const TOWN: Array[String] = [
	"res://assets/city/gebaeude/building-b.glb",
	"res://assets/city/gebaeude/building-d.glb",
	"res://assets/city/gebaeude/building-f.glb",
	"res://assets/city/gebaeude/building-h.glb",
]

var band: RefCounted

var crate_prop: Node3D
var ring_prop: Node3D
var buoy_prop: Node3D
var pier_prop: Node3D
var wave_prop: Node3D
var foam_prop: Node3D

var _wall_x := 3.95
var _water_mat: StandardMaterial3D


## `half_w` = CHANNEL_HALF_W der Logik; die Mauern stehen genau daneben.
func build(half_w: float, ring_radius: float) -> void:
	_wall_x = half_w + QUAY_PAD
	_build_water()
	_build_walls()
	_build_band()
	_build_props(ring_radius)


func layer_count() -> int:
	var total: int = band.call("layer_count") + 5
	for prop in _all_props():
		total += prop.call("layer_count")
	return total


func begin_props() -> void:
	for prop in _all_props():
		prop.call("begin")


func flush_props() -> void:
	for prop in _all_props():
		prop.call("flush")


func push_item(kind: String, x: float, z: float, bob: float, spin: float) -> void:
	match kind:
		"crate":
			crate_prop.call("push", _pose(x, 0.16 + bob, z, spin))
		"ring":
			ring_prop.call("push", _pose(x, 0.22 + bob, z, spin * 0.4))
		_:
			buoy_prop.call("push", _pose(x, bob, z, spin * 0.3))


## Mole: ein Steg, der von der Mauer in den Kanal ragt.
func push_pier(side: float, z: float, reach: float, depth: float, half_w: float) -> void:
	var length := reach + QUAY_PAD + WALL_W * 0.5
	var basis := Basis.IDENTITY.scaled(Vector3(length, 1.0, depth))
	var cx := side * (half_w - reach + length * 0.5)
	pier_prop.call("push", Transform3D(basis, Vector3(cx, 0.34, z)))


## Wellenkamm quer über den Kanal plus Schaum-Sweetspot.
func push_wave(z: float, half_w: float, sweet_x: float, sweet_half: float, ridden: bool) -> void:
	var basis := Basis.IDENTITY.scaled(Vector3(half_w * 2.0, 1.0, 1.0))
	wave_prop.call("push", Transform3D(basis, Vector3(0.0, 0.18, z)))
	if ridden:
		return
	var foam := Basis.IDENTITY.scaled(Vector3(sweet_half * 2.0, 1.0, 1.0))
	foam_prop.call("push", Transform3D(foam, Vector3(sweet_x, 0.3, z)))


func _all_props() -> Array[Node3D]:
	return [crate_prop, ring_prop, buoy_prop, pier_prop, wave_prop, foam_prop]


func _pose(x: float, y: float, z: float, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(x, y, z))


## Wasser: unbeleuchtete Fläche mit gekachelter Kräuseltextur, die pro Frame
## unter dem Boot durchläuft (`scroll_water`). Das ersetzt die Web-Canvas-
## Textur eins zu eins, nur ohne Canvas.
func _build_water() -> void:
	var water := Fx.ground(Vector2(_wall_x * 2.0 + 40.0, 220.0), Color.WHITE, 0.0)
	_water_mat = water.mesh.surface_get_material(0) as StandardMaterial3D
	_water_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Der Türkiston steckt IN der Textur, nicht in `albedo_color`: eine
	# Multiplikation kann nur abdunkeln, damit blieben die hellen Kräusel-
	# bänder unsichtbar und der Kanal wirkte wie lackiertes Blech.
	_water_mat.albedo_texture = _ripple_texture()
	_water_mat.uv1_scale = Vector3(3.4, 22.0, 1.0)
	_water_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	water.position.z = -80.0
	add_child(water)
	# Zweite, hellere Fläche weit draußen: das offene Meer hinter dem Hafen.
	var sea := Fx.ground(Vector2(400.0, 300.0), WATER_FAR, -0.05)
	(sea.mesh.surface_get_material(0) as StandardMaterial3D).shading_mode = (
		BaseMaterial3D.SHADING_MODE_UNSHADED
	)
	sea.position.z = -200.0
	add_child(sea)
	_build_sun()


## Kräuselbänder + Morgenfunkeln (Web: `makeWaterTexture`, 1:1 nachgebaut).
func _ripple_texture() -> ImageTexture:
	var image := Image.create_empty(128, 256, false, Image.FORMAT_RGBA8)
	image.fill(WATER)
	var ripple := Color(0.863, 0.98, 0.961)
	for y in range(0, 256, 8):
		var a := 0.05 + 0.05 * sin(float(y) * 0.4)
		image.fill_rect(Rect2i(0, y, 128, 3), WATER.lerp(ripple, a * 1.3))
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5EA
	var spark := Color(1.0, 0.957, 0.839)
	for _i in 40:
		var sx := rng.randi_range(0, 122)
		var sy := rng.randi_range(0, 254)
		var sw := rng.randi_range(2, 6)
		image.fill_rect(Rect2i(sx, sy, sw, 1), WATER.lerp(spark, rng.randf_range(0.3, 0.7)))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)


## Tief stehende Morgensonne über der Hafenstadt (Web: additives Sprite bei
## (−8; 4,2; 52)). Sie gibt dem Dunst am Horizont seinen warmen Kern.
func _build_sun() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(18.0, 18.0)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.84, 0.59, 0.95))
	gradient.set_color(1, Color(1.0, 0.84, 0.59, 0.0))
	gradient.add_point(0.45, Color(1.0, 0.87, 0.66, 0.45))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 96
	tex.height = 96
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = tex
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_receive_shadows = true
	# Ohne das schluckt der Tiefennebel (Ende 78 m) die Scheibe komplett.
	mat.disable_fog = true
	quad.material = mat
	var sun := MeshInstance3D.new()
	sun.mesh = quad
	sun.position = Vector3(-9.0, 6.0, -95.0)
	sun.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(sun)


## Das Wasser unter dem Boot durchziehen (Meter gefahrener Strecke).
func scroll_water(metres: float) -> void:
	if _water_mat == null:
		return
	_water_mat.uv1_offset = Vector3(0.0, fmod(metres * 0.11, 1.0), 0.0)


func _build_walls() -> void:
	for side: float in [-1.0, 1.0]:
		var wall := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(WALL_W, WALL_H, WALL_LEN)
		mesh.material = Fx.flat(QUAY)
		wall.mesh = mesh
		wall.position = Vector3(side * _wall_x, 0.45, -70.0)
		add_child(wall)
		var cap := MeshInstance3D.new()
		var cap_mesh := BoxMesh.new()
		cap_mesh.size = Vector3(WALL_W + 0.2, CAP_H, WALL_LEN)
		cap_mesh.material = Fx.flat(QUAY_TOP)
		cap.mesh = cap_mesh
		cap.position = Vector3(side * _wall_x, 1.28, -70.0)
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(cap)


func _build_band() -> void:
	band = ScrollBand.new(LOOP_LEN, DESPAWN_Z)
	_build_foam_lines()
	_build_posts()
	_build_town()


## Schaumglitzer auf dem Wasser — sie machen das Tempo sichtbar.
##
## Vorher waren das 1,5 m breite Leuchtbalken; aus der Verfolgerperspektive
## sahen sie aus wie weiße Bretter, die im Kanal treiben. Das Web hat dort nur
## feine Funken in der Wassertextur — also kurze, halbtransparente Striche.
func _build_foam_lines() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.5, 0.012, 0.05)
	mesh.material = Fx.glass(Color(0.93, 1.0, 0.99, 0.5), true)
	var prop := _prop([{"mesh": mesh, "xform": Transform3D.IDENTITY}], 44)
	var items: Array = []
	for i in 36:
		var lane := fmod(float(i) * 1.37, 5.6) - 2.8
		items.append({"x": lane, "y": 0.03, "z": DESPAWN_Z - i * 2.6})
	band.call("add_group", prop, items)


## Poller auf der Kaimauer (Web: recycelte Decor-Reihen).
func _build_posts() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.09
	mesh.bottom_radius = 0.11
	mesh.height = 0.55
	mesh.radial_segments = 8
	mesh.rings = 1
	mesh.material = Fx.flat(POST)
	var prop := _prop([{"mesh": mesh, "xform": Transform3D.IDENTITY}], 32)
	var items: Array = []
	for i in 14:
		for side: float in [-1.0, 1.0]:
			(
				items
				. append(
					{
						"x": side * (_wall_x - 0.75),
						"y": 1.62,
						"z": DESPAWN_Z - i * (LOOP_LEN / 14.0),
					}
				)
			)
	band.call("add_group", prop, items)

	var flag := _prop(Models.parts(BUOY_FLAG, 0.7), 8)
	var flag_items: Array = []
	for i in 6:
		var side := -1.0 if i % 2 == 0 else 1.0
		(
			flag_items
			. append(
				{
					"x": side * (_wall_x + WALL_W * 0.5 + 0.9),
					"z": DESPAWN_Z - i * (LOOP_LEN / 6.0) - 4.0,
				}
			)
		)
	band.call("add_group", flag, flag_items)


## Hafenstädtchen hinter der Mauer — Kulisse, KEINE Häuserschlucht.
##
## Zwei Reihen weit draußen: die nähere gibt dem Kanal einen Rahmen, die
## fernere verliert sich im Morgennebel. Schattenwurf ist aus — sonst legten
## die Dächer harte Balken über das Wasser, das im Web spiegelglatt bleibt.
func _build_town() -> void:
	var rows := int(LOOP_LEN / 16.0)
	# Einheitliches Dunstmaterial ÜBER den Haustexturen: die Kenney-Modelle
	# bringen fast schwarze Ladenzeilen mit, und am Bildrand standen die als
	# Kohleklötze neben dem Kanal. Das Web malt dort eine blasse Silhouette —
	# ein heller Überzug bringt genau das, behält aber die echte 3D-Form.
	var mist := Fx.flat(MIST, 1.0)
	for i in TOWN.size():
		var prop := _prop_tinted(Models.parts(TOWN[i], 9.0), 12, mist)
		prop.call("set_shadows", false)
		var items: Array = []
		for row in rows:
			for side: int in [-1, 1]:
				if (row * 2 + (1 if side > 0 else 0)) % TOWN.size() != i:
					continue
				for rank in 2:
					(
						items
						. append(
							{
								"x": side * (_wall_x + TOWN_OFFSET + float(rank) * 11.0),
								"y": 0.4,
								"z": -row * 16.0 - 6.0 - float(rank) * 7.0,
								"yaw": -PI * 0.5 if side > 0 else PI * 0.5,
							}
						)
					)
		band.call("add_group", prop, items)
	_build_cranes()


## Zwei Hafenkräne als Silhouette (Web malt sie in die Kulissentextur).
func _build_cranes() -> void:
	var mast := BoxMesh.new()
	mast.size = Vector3(0.5, 11.0, 0.5)
	mast.material = Fx.flat(MIST.darkened(0.22))
	var jib := BoxMesh.new()
	jib.size = Vector3(9.0, 0.42, 0.42)
	jib.material = mast.material
	var parts: Array = [
		{"mesh": mast, "xform": Transform3D(Basis.IDENTITY, Vector3(0.0, 5.5, 0.0))},
		{
			"mesh": jib,
			"xform": Transform3D(Basis(Vector3.FORWARD, 0.16), Vector3(3.6, 10.4, 0.0)),
		},
	]
	var prop := _prop(parts, 6)
	prop.call("set_shadows", false)
	var items: Array = []
	for i in 4:
		var side := -1.0 if i % 2 == 0 else 1.0
		(
			items
			. append(
				{
					"x": side * (_wall_x + TOWN_OFFSET + 6.0),
					"z": -float(i) * (LOOP_LEN / 4.0) - 18.0,
					"yaw": 0.0 if side > 0.0 else PI,
				}
			)
		)
	band.call("add_group", prop, items)


func _build_props(ring_radius: float) -> void:
	crate_prop = _prop(Models.parts(CRATE, 0.86, false), 14)
	ring_prop = _prop(_ring_parts(ring_radius), 12)
	buoy_prop = _prop(Models.parts(BUOY, 0.9), 12)
	pier_prop = _prop(_pier_parts(), 4)
	wave_prop = _prop(_wave_parts(), 6)
	foam_prop = _prop(_foam_parts(), 6)


## Netzring: schwimmender Torus mit Leuchtkante.
func _ring_parts(radius: float) -> Array:
	var torus := TorusMesh.new()
	torus.inner_radius = maxf(0.08, radius - 0.16)
	torus.outer_radius = radius
	torus.rings = 20
	torus.ring_segments = 8
	torus.material = Fx.glow(Color(0.45, 0.9, 0.8), 0.9)
	var lift := Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3.ZERO)
	return [{"mesh": torus, "xform": lift}]


## Mole: Einheitskasten, per Skalierung auf Länge/Tiefe gebracht.
func _pier_parts() -> Array:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 0.7, 1.0)
	mesh.material = Fx.flat(Color(0.55, 0.4, 0.28))
	return [{"mesh": mesh, "xform": Transform3D.IDENTITY}]


func _wave_parts() -> Array:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 0.22, 0.5)
	mesh.material = Fx.glass(Color(0.42, 0.76, 0.9, 0.85))
	return [{"mesh": mesh, "xform": Transform3D.IDENTITY}]


func _foam_parts() -> Array:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 0.16, 0.7)
	mesh.material = Fx.glow(Color(1.0, 1.0, 1.0), 0.8)
	return [{"mesh": mesh, "xform": Transform3D.IDENTITY}]


func _prop(parts: Array, cap: int) -> Node3D:
	return _prop_tinted(parts, cap, null)


func _prop_tinted(parts: Array, cap: int, material: Material) -> Node3D:
	var node: Node3D = MultiProp.new()
	add_child(node)
	node.call("build", parts, cap, false, material)
	return node
