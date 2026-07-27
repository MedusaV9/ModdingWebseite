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
const LAMP := "res://assets/city/strassen/light-curved.glb"
const BUILDINGS: Array[String] = [
	"res://assets/city/gebaeude/building-a.glb",
	"res://assets/city/gebaeude/building-b.glb",
	"res://assets/city/gebaeude/building-c.glb",
	"res://assets/city/gebaeude/building-d.glb",
	"res://assets/city/gebaeude/building-e.glb",
	"res://assets/city/gebaeude/building-f.glb",
]
## Zweite Reihe hinter der Häuserflucht — Tiefe statt Pappwand.
const BACK_ROW: Array[String] = [
	"res://assets/city/gebaeude/low-detail-building-a.glb",
	"res://assets/city/gebaeude/low-detail-building-c.glb",
	"res://assets/city/gebaeude/building-skyscraper-a.glb",
	"res://assets/city/gebaeude/low-detail-building-e.glb",
	"res://assets/city/gebaeude/building-skyscraper-b.glb",
	"res://assets/city/gebaeude/low-detail-building-f.glb",
]
const TREES: Array[String] = [
	"res://assets/city/natur/tree_default.glb",
	"res://assets/minigames/runner/nature-kit/tree_oak.glb",
]
## Park-Distrikt: Büsche, Blumen, Findlinge (Kenney nature-kit).
const PARK: Array[String] = [
	"res://assets/city/natur/plant_bushLarge.glb",
	"res://assets/city/natur/flower_yellowA.glb",
	"res://assets/city/natur/flower_redA.glb",
	"res://assets/city/natur/rock_smallA.glb",
]
const CARS: Array[String] = [
	"res://assets/city/autos/taxi.glb",
	"res://assets/city/autos/sedan.glb",
	"res://assets/city/autos/van.glb",
]
## Distrikt je Häuserzeilen-Reihe (Bandlänge 104 m, Schritt 13 m → 8 Reihen):
## Innenstadt → Park → Innenstadt → Baustelle. So wiederholt sich nicht EIN
## Muster, sondern ein ganzer Streckenzug mit Szenenwechseln.
const DISTRICTS: Array[String] = ["city", "city", "park", "park", "city", "city", "site", "city"]
## Warnmarkierungen auf der Fahrbahn: Gelb = springen, Türkis = rutschen,
## Koralle = Spur wechseln (Auto). Liegen VOR dem Hindernis auf dem Asphalt.
const WARN_JUMP := Color(1.0, 0.78, 0.25, 0.85)
const WARN_SLIDE := Color(0.45, 0.9, 1.0, 0.85)
const WARN_DODGE := Color(1.0, 0.48, 0.42, 0.85)

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
var warn_prop: Node3D

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


## Ein Hindernis an (x, z) einreihen — plus Warnmarkierung auf dem Asphalt
## davor (Lesbarkeit: Farbe sagt springen/rutschen/ausweichen, lange bevor
## die Silhouette groß genug ist).
func push_obstacle(kind: String, x: float, z: float, yaw: float, gap_y: float) -> void:
	match kind:
		"cone":
			cone_prop.call("push", _pose(x, 0.0, z, yaw))
			_push_warn(x, z, WARN_JUMP)
		"box":
			box_prop.call("push", _pose(x, 0.0, z, yaw))
			_push_warn(x, z, WARN_JUMP)
		"barrier":
			barrier_prop.call("push", _pose(x, 0.0, z, yaw))
			_push_warn(x, z, WARN_JUMP)
		"overhead":
			over_bar_prop.call("push", _pose(x, gap_y, z, 0.0))
			for side: float in [-0.55, 0.55]:
				over_post_prop.call("push", _pose(x + side, 0.0, z, 0.0))
			_push_warn(x, z, WARN_SLIDE)
		_:
			var idx := absi(int(x * 7.0) + int(z)) % car_props.size()
			car_props[idx].call("push", _pose(x, 0.0, z, yaw))
			_push_warn(x, z, WARN_DODGE)


func _push_warn(x: float, z: float, tint: Color) -> void:
	warn_prop.call("push", _pose(x, 0.0, z + 1.7, 0.0), tint)


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
		warn_prop,
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

	_build_districts()

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

	# Straßenbäume + Laternen auf der Gehwegkachel — deren Deckelhöhe.
	var walk_top := Models.fitted_size(WALK, WALK_W).y
	for i in TREES.size():
		var prop := _prop(Models.parts(TREES[i], 1.9), 8)
		var items: Array = []
		for k in 8:
			if k % 2 != i:
				continue
			items.append({"x": -3.2 if k % 4 == 0 else 3.2, "y": walk_top, "z": -k * 13.0 - 8.5})
		band.call("add_group", prop, items)
	_build_lamps(walk_top)
	_build_clouds()


## Distrikte statt Endlos-Muster: Innenstadt (mit zweiter Skyline-Reihe),
## Park (Bäume, Büsche, Blumen) und Baustelle (Absperrungen, Kistenstapel).
func _build_districts() -> void:
	var rows := int(CORRIDOR_LEN / BUILDING_STEP)
	var plan: Dictionary = {}
	for row in rows:
		var z := -row * BUILDING_STEP - 2.0
		match DISTRICTS[row % DISTRICTS.size()]:
			"city":
				_plan_city(plan, row, z)
			"park":
				_plan_park(plan, row, z)
			_:
				_plan_site(plan, row, z)
	for path: String in plan:
		var spec: Dictionary = plan[path]
		var prop := _prop(Models.parts(path, float(spec["w"])), (spec["items"] as Array).size())
		# Kulissen ohne Schattenwurf: der Korridor ist eng, ihre Schatten
		# deckten die halbe Fahrbahn als schwarze Balken zu.
		prop.call("set_shadows", false)
		band.call("add_group", prop, spec["items"])


func _plan_city(plan: Dictionary, row: int, z: float) -> void:
	for side: int in [-1, 1]:
		var pick := row * 2 + (1 if side > 0 else 0)
		var yaw := -PI * 0.5 if side > 0 else PI * 0.5
		# Häuser stehen auf der Wiese (y = −0,06) — sonst schwebten die Sockel.
		var front := {"x": side * BUILDING_X, "y": -0.06, "z": z, "yaw": yaw}
		_plan_put(plan, BUILDINGS[pick % BUILDINGS.size()], BUILDING_W, front)
		var back := {"x": side * (BUILDING_X + 9.0), "y": -0.06, "z": z - 6.0, "yaw": yaw}
		_plan_put(plan, BACK_ROW[(pick + row) % BACK_ROW.size()], 9.0, back)


func _plan_park(plan: Dictionary, row: int, z: float) -> void:
	for side: int in [-1, 1]:
		var sx := float(side)
		_plan_put(
			plan,
			TREES[(row + (1 if side > 0 else 0)) % TREES.size()],
			3.4,
			{"x": sx * (BUILDING_X - 1.2), "y": -0.06, "z": z - 1.0}
		)
		_plan_put(plan, PARK[0], 1.6, {"x": sx * 6.2, "y": -0.06, "z": z - 5.0})
		_plan_put(plan, PARK[1 + (row + side) % 2], 0.55, {"x": sx * 5.6, "y": -0.06, "z": z + 2.4})
		_plan_put(plan, PARK[3], 0.9, {"x": sx * 7.4, "y": -0.06, "z": z + 4.2})
		# Hintere Baumreihe: der Park hat Tiefe statt Lücke in der Skyline.
		_plan_put(
			plan,
			TREES[(row + side) % TREES.size()],
			4.4,
			{"x": sx * 14.0, "y": -0.06, "z": z - 4.0}
		)


func _plan_site(plan: Dictionary, row: int, z: float) -> void:
	for side: int in [-1, 1]:
		var sx := float(side)
		var yaw := -PI * 0.5 if side > 0 else PI * 0.5
		for k in 3:
			_plan_put(
				plan,
				BARRIER,
				1.5,
				{
					"x": sx * (BUILDING_X - 2.4),
					"y": -0.06,
					"z": z + 3.0 - float(k) * 3.2,
					"yaw": yaw
				}
			)
		_plan_put(plan, BOX, 1.1, {"x": sx * (BUILDING_X - 0.6), "y": -0.06, "z": z - 1.0})
		_plan_put(
			plan, BOX, 0.8, {"x": sx * (BUILDING_X - 0.9), "y": 1.04, "z": z - 1.1, "yaw": 0.5}
		)
		_plan_put(plan, CONE, 0.55, {"x": sx * 5.4, "y": -0.06, "z": z + 4.0})
		_plan_put(plan, CONE, 0.55, {"x": sx * 6.4, "y": -0.06, "z": z - 3.6})
		var back := {"x": sx * (BUILDING_X + 8.0), "y": -0.06, "z": z - 5.0, "yaw": yaw}
		_plan_put(plan, BACK_ROW[(row * 2 + side) % BACK_ROW.size()], 9.0, back)


func _plan_put(plan: Dictionary, path: String, width: float, item: Dictionary) -> void:
	if not plan.has(path):
		plan[path] = {"w": width, "items": []}
	(plan[path]["items"] as Array).append(item)


## Laternen entlang der Gehwege — Innenstadt-Rhythmus, ein Draw-Call.
func _build_lamps(walk_top: float) -> void:
	var prop := _prop(Models.parts_by_height(LAMP, 3.2), 10)
	prop.call("set_shadows", false)
	var items: Array = []
	for k in 8:
		var side := -1.0 if k % 2 == 0 else 1.0
		(
			items
			. append(
				{
					"x": side * 3.3,
					"y": walk_top,
					"z": -k * 13.0 - 3.0,
					"yaw": PI if side > 0.0 else 0.0,
				}
			)
		)
	band.call("add_group", prop, items)


## Weiche Wolkenquads hoch über dem Korridor — sie ziehen mit dem Band mit
## (Parallaxe) und geben dem leeren Himmel Volumen. Ohne Nebel, sonst frisst
## der Tiefen-Nebel sie auf halber Strecke.
func _build_clouds() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(11.0, 3.6)
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 1.0, 1.0, 0.88))
	gradient.set_color(1, Color(1.0, 1.0, 1.0, 0.0))
	gradient.add_point(0.55, Color(1.0, 1.0, 1.0, 0.62))
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 64
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_texture = tex
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.disable_fog = true
	mat.disable_receive_shadows = true
	quad.material = mat
	var prop := _prop([{"mesh": quad, "xform": Transform3D.IDENTITY}], 8)
	prop.call("set_shadows", false)
	var items: Array = []
	for k in 6:
		var side := -1.0 if k % 2 == 0 else 1.0
		(
			items
			. append(
				{
					"x": side * (7.0 + fmod(float(k) * 5.3, 14.0)),
					"y": 13.5 + fmod(float(k) * 2.9, 6.0),
					"z": -k * (CORRIDOR_LEN / 6.0) - 9.0,
					"scale": Vector3(0.8 + fmod(float(k) * 0.37, 0.6), 1.0, 1.0),
				}
			)
		)
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
	warn_prop = _prop_colored(_warn_parts(), 28)


## Flacher Warnstrich auf dem Asphalt (Farbe pro Exemplar = Hindernisart).
func _warn_parts() -> Array:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.85, 0.42)
	var mat := Fx.glass(Color.WHITE, true)
	mat.vertex_color_use_as_albedo = true
	quad.material = mat
	var flat_pose := Transform3D(Basis(Vector3.RIGHT, -PI * 0.5), Vector3(0.0, 0.035, 0.0))
	return [{"mesh": quad, "xform": flat_pose}]


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


func _prop_colored(parts: Array, cap: int) -> Node3D:
	var node: Node3D = MultiProp.new()
	add_child(node)
	node.call("build", parts, cap, true)
	return node
