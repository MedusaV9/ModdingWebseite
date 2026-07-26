extends Node3D
## 3D-Welt des Gooby-Runners (Agent 3D-B): Stadtkorridor aus echten
## Kenney-City-Kit-GLBs — genau die Modelle, die auch die Web-Fassung
## (GOOBY/src/minigames/games/runner.js) benutzt hat, nur als MultiMesh statt
## als N einzelne Szenenknoten.
##
## Aufbau (Weltachsen: x = Spur, y = hoch, z = Tiefe, −z ist vorne):
##   Straßenkacheln + Gehwegstreifen als Laufband (ScrollBand)
##   Häuserzeile links/rechts als Korridorwände, Bäume dazwischen
##   Hindernisse/Münzen/Kisten als recycelte MultiMesh-Pools
##
## Die Zahlen (Spawn/Despawn-z, Korridorlänge, Modellbreiten) sind 1:1 aus der
## Web-Fassung übernommen, damit sich der Lauf gleich anfühlt.

const Models := preload("res://scripts/minigames/games/_3db_stage/model_bank.gd")
const MultiProp := preload("res://scripts/minigames/games/_3db_stage/multi_prop.gd")
const ScrollBand := preload("res://scripts/minigames/games/_3db_stage/scroll_band.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")

const CORRIDOR_LEN := 104.0
const DESPAWN_Z := 9.0
const TILE_STEP := 8.0
const ROAD_W := 4.6
const WALK_W := 1.6
const WALK_X := 3.15
const BUILDING_X := 8.6
const BUILDING_W := 10.0
const BUILDING_STEP := 13.0
const DASH_STEP := 3.2
## Spurgrenzen: die Spuren liegen bei x = −1,1 / 0 / +1,1.
const DASH_X := 0.55

const ROAD := "res://assets/city/strassen/road-straight.glb"
const WALK := "res://assets/city/strassen/tile-low.glb"
const CONE := "res://assets/minigames/runner/city-kit-roads/construction-cone.glb"
const BARRIER := "res://assets/minigames/runner/city-kit-roads/construction-barrier.glb"
const BOX := "res://assets/minigames/runner/car-kit/box.glb"
const BUILDINGS: Array[String] = [
	"res://assets/city/gebaeude/building-a.glb",
	"res://assets/city/gebaeude/building-b.glb",
	"res://assets/city/gebaeude/building-c.glb",
	"res://assets/city/gebaeude/building-d.glb",
	"res://assets/city/gebaeude/building-e.glb",
	"res://assets/city/gebaeude/building-f.glb",
]
const TREES: Array[String] = [
	"res://assets/city/natur/tree_default.glb",
	"res://assets/minigames/runner/nature-kit/tree_oak.glb",
]
const CARS: Array[String] = [
	"res://assets/city/autos/taxi.glb",
	"res://assets/city/autos/sedan.glb",
	"res://assets/city/autos/van.glb",
]

## Hindernis-Pools nach Art (die Autos teilen sich einen Pool je Modell).
var cone_prop: Node3D
var barrier_prop: Node3D
var box_prop: Node3D
var over_bar_prop: Node3D
var over_post_prop: Node3D
var car_props: Array[Node3D] = []
var coin_prop: Node3D
var mystery_prop: Node3D
var mystery_mark_prop: Node3D

var band: RefCounted


## Kulisse und Hindernis-Pools bauen. `gap_y` = Durchfahrtshöhe des Gerüsts.
func build(gap_y: float) -> void:
	_build_ground()
	_build_band()
	_build_obstacle_pools(gap_y)


## Anzahl Draw-Calls der gesamten Welt (ohne Gooby/Partikel).
func layer_count() -> int:
	var total: int = band.call("layer_count") + 2
	for prop in _all_props():
		total += prop.call("layer_count")
	return total


## Alle Hindernis-Pools auf „nichts sichtbar" zurücksetzen (Frame-Anfang).
func begin_props() -> void:
	for prop in _all_props():
		prop.call("begin")


func flush_props() -> void:
	for prop in _all_props():
		prop.call("flush")


## Ein Hindernis an (x, z) einreihen.
func push_obstacle(kind: String, x: float, z: float, yaw: float, gap_y: float) -> void:
	match kind:
		"cone":
			cone_prop.call("push", _pose(x, 0.0, z, yaw))
		"box":
			box_prop.call("push", _pose(x, 0.0, z, yaw))
		"barrier":
			barrier_prop.call("push", _pose(x, 0.0, z, yaw))
		"overhead":
			over_bar_prop.call("push", _pose(x, gap_y, z, 0.0))
			for side: float in [-0.55, 0.55]:
				over_post_prop.call("push", _pose(x + side, 0.0, z, 0.0))
		_:
			var idx := absi(int(x * 7.0) + int(z)) % car_props.size()
			car_props[idx].call("push", _pose(x, 0.0, z, yaw))


func push_coin(x: float, y: float, z: float, spin: float) -> void:
	var basis := Basis(Vector3.UP, spin) * Basis(Vector3.FORWARD, PI * 0.5)
	coin_prop.call("push", Transform3D(basis, Vector3(x, y, z)))


func push_mystery(x: float, z: float, spin: float, bob: float) -> void:
	mystery_prop.call("push", _pose(x, 0.0, z, spin))
	mystery_mark_prop.call("push", _pose(x, 0.72 + bob, z, spin * 1.7))


func _all_props() -> Array[Node3D]:
	var list: Array[Node3D] = [
		cone_prop,
		barrier_prop,
		box_prop,
		over_bar_prop,
		over_post_prop,
		coin_prop,
		mystery_prop,
		mystery_mark_prop,
	]
	list.append_array(car_props)
	return list


func _pose(x: float, y: float, z: float, yaw: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw), Vector3(x, y, z))


func _build_ground() -> void:
	# Web: PlaneGeometry(60, 220) in 0xa8d8a0 bei y = −0,06.
	var grass := Fx.ground(Vector2(150.0, 260.0), Color(0.659, 0.847, 0.627), -0.06)
	grass.position.z = -70.0
	add_child(grass)


func _build_band() -> void:
	band = ScrollBand.new(CORRIDOR_LEN, DESPAWN_Z)

	# Die Fahrbahn muss GEDREHT eingepasst werden (Web: rotation.y = PI/2),
	# sonst läuft der Straßenquerschnitt quer zum Korridor und wiederholt sich
	# alle acht Meter als Streifenmuster.
	var road := _prop(Models.parts_yawed(ROAD, PI * 0.5, ROAD_W), 16)
	var walk := _prop(Models.parts(WALK, WALK_W), 32)
	road.call("set_shadows", false)
	walk.call("set_shadows", false)
	# FAHRBAHN-OBERKANTE exakt auf y = 0: Gooby, Autos, Hütchen und Absperrungen
	# posieren alle auf y = 0 — die eingepasste Kachel ist aber ~9 cm dick, mit
	# Unterkante auf 0 steckten alle Fahrzeuge 9 cm im Asphalt (FB-4-Bugfix
	# „Autos schweben/versinken"). Also die Platte um ihre Dicke absenken.
	var road_drop := -Models.fitted_size(ROAD, ROAD_W).y
	var road_items: Array = []
	var walk_items: Array = []
	var z := DESPAWN_Z
	while z > DESPAWN_Z - CORRIDOR_LEN:
		(
			road_items
			. append(
				{
					"x": 0.0,
					"y": road_drop,
					"z": z - 4.0,
					"scale": Vector3(1.0, 1.0, TILE_STEP / ROAD_W),
				}
			)
		)
		for sx: float in [-WALK_X, WALK_X]:
			walk_items.append(
				{"x": sx, "z": z - 4.0, "scale": Vector3(1.0, 1.0, TILE_STEP / WALK_W)}
			)
		z -= TILE_STEP
	band.call("add_group", road, road_items)
	band.call("add_group", walk, walk_items)

	var rows := int(CORRIDOR_LEN / BUILDING_STEP)
	for i in BUILDINGS.size():
		var prop := _prop(Models.parts(BUILDINGS[i], BUILDING_W), 8)
		# Häuserzeile ohne Schattenwurf: der Korridor ist eng, ihre Schatten
		# deckten die halbe Fahrbahn als schwarze Balken zu.
		prop.call("set_shadows", false)
		var items: Array = []
		for row in rows:
			for side: int in [-1, 1]:
				if (row * 2 + (1 if side > 0 else 0)) % BUILDINGS.size() != i:
					continue
				(
					items
					. append(
						{
							"x": side * BUILDING_X,
							# Häuser stehen auf der Wiese (y = −0,06) — sonst
							# schwebten die Sockel 6 cm über dem Gras.
							"y": -0.06,
							"z": -row * BUILDING_STEP - 2.0,
							"yaw": -PI * 0.5 if side > 0 else PI * 0.5,
						}
					)
				)
		band.call("add_group", prop, items)

	# Spurstriche auf den beiden Spurgrenzen (±0,55 m). Die Kachel bringt nur
	# den durchgezogenen Mittelstrich mit; hochkant füllt die nackte Fahrbahn
	# sonst ein Drittel des Bildes, und der Spielraum der drei Spuren ist
	# nirgends abzulesen.
	var dash := BoxMesh.new()
	dash.size = Vector3(0.09, 0.02, 1.1)
	dash.material = Fx.flat(Color(0.9, 0.89, 0.85))
	var dash_prop := _prop([{"mesh": dash, "xform": Transform3D.IDENTITY}], 64)
	dash_prop.call("set_shadows", false)
	var dash_items: Array = []
	var dz := DESPAWN_Z
	while dz > DESPAWN_Z - CORRIDOR_LEN:
		for lx: float in [-DASH_X, DASH_X]:
			dash_items.append({"x": lx, "y": 0.02, "z": dz})
		dz -= DASH_STEP
	band.call("add_group", dash_prop, dash_items)

	# Bäume stehen AUF der Gehwegkachel — deren Deckelhöhe, nicht y = 0.
	var walk_top := Models.fitted_size(WALK, WALK_W).y
	for i in TREES.size():
		var prop := _prop(Models.parts(TREES[i], 1.9), 8)
		var items: Array = []
		for k in 8:
			if k % 2 != i:
				continue
			items.append({"x": -3.2 if k % 4 == 0 else 3.2, "y": walk_top, "z": -k * 13.0 - 8.5})
		band.call("add_group", prop, items)


func _build_obstacle_pools(gap_y: float) -> void:
	cone_prop = _prop(Models.parts(CONE, 0.55), 12)
	barrier_prop = _prop(Models.parts(BARRIER, 1.05), 12)
	box_prop = _prop(Models.parts(BOX, 0.72), 12)
	over_bar_prop = _prop(Models.parts(BARRIER, 1.3), 8)
	over_post_prop = _prop(_post_parts(gap_y), 16)
	for path in CARS:
		car_props.append(_prop(Models.parts(path, 1.15), 6))
	coin_prop = _prop(_coin_parts(), 48)
	mystery_prop = _prop(Models.parts(BOX, 0.8), 4)
	mystery_mark_prop = _prop(_mark_parts(), 4)


## Gerüstpfosten (im Web prozedurale Boxen — hier genauso).
func _post_parts(gap_y: float) -> Array:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.09, gap_y + 0.3, 0.09)
	mesh.material = Fx.flat(Color(0.69, 0.33, 0.18))
	var lift := Transform3D(Basis.IDENTITY, Vector3(0.0, (gap_y + 0.3) * 0.5, 0.0))
	return [{"mesh": mesh, "xform": lift}]


## Münze: goldener Zylinder wie im Web (0,22 m Radius, 0,07 m dick).
func _coin_parts() -> Array:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.22
	mesh.bottom_radius = 0.22
	mesh.height = 0.07
	mesh.radial_segments = 16
	mesh.rings = 1
	mesh.material = Fx.glow(Color(1.0, 0.82, 0.4), 1.1)
	return [{"mesh": mesh, "xform": Transform3D.IDENTITY}]


## Leuchtzeichen über der Überraschungskiste.
func _mark_parts() -> Array:
	var mesh := SphereMesh.new()
	mesh.radius = 0.16
	mesh.height = 0.32
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh.material = Fx.glow(Color(1.0, 0.86, 0.35), 2.4)
	return [{"mesh": mesh, "xform": Transform3D.IDENTITY}]


func _prop(parts: Array, cap: int) -> Node3D:
	var node: Node3D = MultiProp.new()
	add_child(node)
	node.call("build", parts, cap)
	return node
