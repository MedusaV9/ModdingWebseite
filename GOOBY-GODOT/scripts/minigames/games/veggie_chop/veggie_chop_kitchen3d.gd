extends "res://scripts/minigames/games/_3dc_stage/stage3d.gd"
## Gemüse-Schnippler — 3D-Küchenbühne (Agent 3D-C). Gooby steht als KOCH hinter
## der Arbeitsplatte (Clip `build_hammer` = Schnippelbewegung), davor fliegen
## ECHTE Food-Kit-Modelle durch die Luft und zerfallen beim Schnitt in ihre
## „-half"-Gegenstücke. Kulisse: Unterschränke, Herd, Spüle, Hängeschränke,
## Fenster mit Abendlicht (Kenney furniture-/food-kit + Tiny Treats).
##
## Projektionsvertrag: die Kamera schaut gerade auf die Flugebene z = 0 und ist
## über set_half_height() exakt so gerahmt wie die 2D-Formel `_to_screen()` des
## Spiels — die getestete Schnitt-Trefferrechnung bleibt damit unverändert.

const Models := preload("res://scripts/minigames/games/_3dc_stage/models3d.gd")
const Puff := preload("res://scripts/minigames/games/_3dc_stage/puff3d.gd")
const DIR := "res://assets/minigames/veggie_chop/"

## Kameraabstand zur Flugebene.
const CAM_DIST := 9.0
## Oberkante der Arbeitsplatte (Weltmeter).
const COUNTER_Y := -3.35
## Fußboden.
const FLOOR_Y := -5.7
## Kachelwand.
const WALL_Z := -4.8
## Durchmesser eines fliegenden Stücks (Weltmeter).
const ITEM_SIZE := 0.82

## Spiel-Schlüssel → GLB-Datei (die Logik nennt bereits die Food-Kit-Namen).
const JUNK_FILES := {"soda": "soda-can-crushed.glb", "boot": "fish-bones.glb"}

var gooby: GoobyRig

var _items: Node3D
var _halves: Node3D
var _pools: Dictionary = {}
var _busy: Array = []
var _flying: Array = []
var _splash: GPUParticles3D
var _steam: GPUParticles3D
var _emotion := "happy"
var _knife: Node3D


func setup_stage() -> void:
	build(
		{
			"sky_top": Color(0.5, 0.68, 0.9),
			"sky_horizon": Color(0.98, 0.88, 0.76),
			"ground_horizon": Color(0.86, 0.76, 0.66),
			"ground_bottom": Color(0.6, 0.52, 0.46),
			"sky_energy": 0.45,
			"ambient": 0.42,
			"sun_color": Color(1.0, 0.88, 0.7),
			"sun_energy": 2.4,
			"sun_dir": Vector3(-0.42, -0.66, -0.62),
			"fill_color": Color(0.68, 0.8, 1.0),
			"fill_energy": 0.6,
			"shadows": false,
			"glow": 0.28,
			"glow_bloom": 0.02,
			"glow_threshold": 1.05,
			"far": 60.0,
		}
	)
	set_half_height(4.142, CAM_DIST)
	camera.position = Vector3(0.0, 0.0, CAM_DIST)
	camera.rotation = Vector3.ZERO
	_build_room()
	_build_counter()
	_build_props()
	_build_gooby()
	_items = Node3D.new()
	add_child(_items)
	_halves = Node3D.new()
	add_child(_halves)
	_build_effects()


## Rahmung an die Orientierung koppeln. `_ppu()` des Spiels ist GEKLEMMT
## (70…220 px/m), die sichtbare halbe Höhe weicht deshalb von HALF_H ab und die
## Bildmitte liegt nicht bei y = 0 — beides muss die Kamera mitmachen, sonst
## laufen 3D-Bild und Schnitt-Trefferrechnung auseinander.
func frame(half_h: float, center_y: float) -> void:
	set_half_height(half_h, CAM_DIST)
	camera.position = Vector3(0.0, center_y, CAM_DIST)


## Fliegende Stücke aus der Spielliste neu setzen (Pool, keine Neuallokation).
func sync(items: Array, elapsed: float) -> void:
	for entry: Dictionary in _busy:
		var node: Node3D = entry["node"]
		node.visible = false
		(_pools[entry["key"]] as Array).append(node)
	_busy.clear()
	for entry: Dictionary in items:
		var item: Dictionary = entry["item"]
		var key := str(item["key"])
		var node := _take(key)
		if node == null:
			continue
		var pos: Vector2 = entry["pos"]
		node.visible = true
		node.position = Vector3(pos.x, pos.y, 0.0)
		var spin := float(entry["spin"]) + float(entry["t"]) * 3.0
		node.rotation = Vector3(spin * 0.6, spin, spin * 0.35)
		_busy.append({"key": key, "node": node})
	_tick_halves(elapsed)


## Zwei Hälften auseinanderfliegen lassen (echte „-half"-Modelle).
func split(world: Vector2, half_key: String, tint: Color) -> void:
	Puff.fire(_splash, Vector3(world.x, world.y, 0.0), tint)
	pulse_glow(0.35)
	for side in [-1.0, 1.0]:
		var node := _take("half:" + half_key)
		if node == null:
			continue
		node.visible = true
		node.position = Vector3(world.x, world.y, 0.0)
		(
			_flying
			. append(
				{
					"node": node,
					"key": "half:" + half_key,
					"vel": Vector3(side * 2.6, 2.4, side * 0.6),
					"spin": Vector3(side * 5.0, 3.0, side * 4.0),
					"age": 0.0,
				}
			)
		)


## Gooby-Emotion setzen (nur bei Wechsel, sonst flackert der Blend).
func feel(emotion: String) -> void:
	if gooby == null or _emotion == emotion:
		return
	_emotion = emotion
	gooby.set_emotion(emotion)


## Schnippelbewegung anstoßen.
func chop() -> void:
	if gooby != null:
		gooby.play_clip("build_hammer")


# ── Aufbau ────────────────────────────────────────────────────────────────


func _build_room() -> void:
	var wall := MeshInstance3D.new()
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(30.0, 18.0, 0.4)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.93, 0.78, 0.66)
	mat.roughness = 1.0
	wall_mesh.material = mat
	wall.mesh = wall_mesh
	wall.position = Vector3(0.0, 2.0, WALL_Z)
	add_child(wall)
	_build_tiles()
	_build_window()
	var floor_node := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 14.0)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.7, 0.58, 0.5)
	fmat.roughness = 1.0
	plane.material = fmat
	floor_node.mesh = plane
	floor_node.position = Vector3(0.0, FLOOR_Y, -1.5)
	add_child(floor_node)


## Kachelband über der Arbeitsplatte (MultiMesh = 1 Draw-Call).
func _build_tiles() -> void:
	var tile := BoxMesh.new()
	tile.size = Vector3(0.62, 0.62, 0.06)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.58, 0.82, 0.79)
	mat.roughness = 0.5
	tile.material = mat
	var poses: Array = []
	# 42 Spalten = 29 m: QUER ist der Ausschnitt gut 27 m breit, mit den
	# ursprünglichen 24 Spalten endete der Kachelspiegel mitten im Bild.
	for row in 11:
		for col in 42:
			var pos := Vector3(-14.35 + col * 0.7, COUNTER_Y + 0.5 + row * 0.7, WALL_Z + 0.22)
			poses.append(Transform3D(Basis.IDENTITY, pos))
	add_child(Models.swarm([{"mesh": tile, "xform": Transform3D.IDENTITY}], poses, 30.0))


## Fenster mit Abendhimmel — der warme Fleck hinter dem Flugbogen.
func _build_window() -> void:
	# Zwei Scheiben statt einer: oben Himmel, unten Gartenhecke. Eine einzelne
	# gleißende Fläche wurde vom Glow zu einem weißen Loch in der Wand.
	var glass := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(3.4, 1.55)
	glass.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.76, 0.89, 0.99)
	glass.material_override = mat
	glass.position = Vector3(1.35, 1.32, WALL_Z + 0.24)
	add_child(glass)
	var garden := MeshInstance3D.new()
	var gquad := QuadMesh.new()
	gquad.size = Vector2(3.4, 1.05)
	garden.mesh = gquad
	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.albedo_color = Color(0.65, 0.83, 0.56)
	garden.material_override = gmat
	garden.position = Vector3(1.35, 0.02, WALL_Z + 0.24)
	add_child(garden)
	_build_window_view()
	var centre := Vector3(1.35, 0.8, WALL_Z + 0.24)
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.99, 0.97, 0.94)
	for bar: Array in [
		[Vector3(0, 0, 0), Vector3(3.8, 0.16, 0.12)], [Vector3(0, 0, 0), Vector3(0.16, 2.9, 0.12)]
	]:
		for sign_y in [-1.0, 1.0]:
			var post := MeshInstance3D.new()
			var box := BoxMesh.new()
			box.size = bar[1]
			box.material = frame_mat
			post.mesh = box
			var off := Vector3(0.0, sign_y * 1.36, 0.0)
			if float((bar[1] as Vector3).y) > 1.0:
				off = Vector3(sign_y * 1.78, 0.0, 0.0)
			post.position = centre + off + Vector3(0.0, 0.0, 0.05)
			add_child(post)
	# Sprosse quer auf Horizonthöhe — trennt Himmel und Hecke sauber.
	var bar_node := MeshInstance3D.new()
	var bbox := BoxMesh.new()
	bbox.size = Vector3(3.5, 0.11, 0.1)
	bbox.material = frame_mat
	bar_node.mesh = bbox
	bar_node.position = Vector3(1.35, 0.55, WALL_Z + 0.29)
	add_child(bar_node)


## Blick nach draußen: Sonne, Wölkchen und drei Baumkronen hinter der Hecke.
## Alles flache, unbeleuchtete Scheiben DICHT hinter dem Glas — echte Geometrie
## im Garten wäre hier weggeworfene Rechenzeit.
func _build_window_view() -> void:
	var z := WALL_Z + 0.25
	for entry: Array in [
		[Vector3(0.4, 1.85, z), 0.32, Color(1.0, 0.95, 0.72)],
		[Vector3(1.5, 1.72, z), 0.28, Color(1.0, 1.0, 1.0)],
		[Vector3(1.85, 1.78, z), 0.22, Color(1.0, 1.0, 1.0)],
		[Vector3(2.2, 1.7, z), 0.18, Color(1.0, 1.0, 1.0)],
		[Vector3(0.3, 0.6, z), 0.55, Color(0.44, 0.68, 0.42)],
		[Vector3(1.35, 0.7, z), 0.68, Color(0.5, 0.73, 0.44)],
		[Vector3(2.4, 0.58, z), 0.5, Color(0.42, 0.65, 0.4)],
	]:
		var blob := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = float(entry[1])
		ball.height = float(entry[1]) * 1.7
		ball.radial_segments = 12
		ball.rings = 7
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = entry[2]
		ball.material = mat
		blob.mesh = ball
		blob.position = entry[0]
		add_child(blob)


func _build_counter() -> void:
	var top := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(32.0, 0.3, 2.6)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.8, 0.66)
	mat.roughness = 0.6
	box.material = mat
	top.mesh = box
	top.position = Vector3(0.0, COUNTER_Y - 0.15, -2.2)
	add_child(top)
	var body := MeshInstance3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(31.6, 2.1, 2.3)
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.79, 0.56, 0.4)
	bmat.roughness = 0.9
	body_mesh.material = bmat
	body.mesh = body_mesh
	body.position = Vector3(0.0, COUNTER_Y - 1.35, -2.25)
	add_child(body)
	# Schranktüren + Griffe: der Unterschrank ist sonst ein brauner Balken.
	var door := BoxMesh.new()
	door.size = Vector3(1.5, 1.5, 0.08)
	var dmat := StandardMaterial3D.new()
	dmat.albedo_color = Color(0.87, 0.66, 0.49)
	dmat.roughness = 0.85
	door.material = dmat
	var knob := BoxMesh.new()
	knob.size = Vector3(0.1, 0.26, 0.08)
	var kmat := StandardMaterial3D.new()
	kmat.albedo_color = Color(0.94, 0.92, 0.9)
	kmat.metallic = 0.4
	knob.material = kmat
	var doors: Array = []
	var knobs: Array = []
	for i in 18:
		var x := -13.6 + i * 1.6
		doors.append(Transform3D(Basis.IDENTITY, Vector3(x, COUNTER_Y - 1.25, -1.06)))
		knobs.append(Transform3D(Basis.IDENTITY, Vector3(x + 0.6, COUNTER_Y - 1.25, -1.02)))
	add_child(Models.swarm([{"mesh": door, "xform": Transform3D.IDENTITY}], doors, 24.0))
	add_child(Models.swarm([{"mesh": knob, "xform": Transform3D.IDENTITY}], knobs, 24.0))


func _build_props() -> void:
	# Hochkant sind nur ±2,1 m sichtbar (das Spiel klemmt px/m) — alles
	# Erzählende steht INNEN, die breiten Möbel füllen den Querformat-Rand.
	var board := Models.node(DIR + "cutting-board.glb", 2.0, true)
	board.position = Vector3(0.55, COUNTER_Y, -1.9)
	add_child(board)
	var pot := Models.node(DIR + "pot-stew.glb", 1.15, true)
	pot.position = Vector3(1.75, COUNTER_Y, -2.5)
	add_child(pot)
	var pan := Models.node(DIR + "frying-pan.glb", 1.45, true)
	pan.position = Vector3(-2.3, COUNTER_Y, -2.4)
	pan.rotation_degrees = Vector3(0.0, -25.0, 0.0)
	add_child(pan)
	var stove := Models.node_by_height(DIR + "kitchenStove.glb", 2.35, true)
	stove.position = Vector3(-4.4, FLOOR_Y + 0.05, -3.1)
	add_child(stove)
	var sink := Models.node_by_height(DIR + "kitchenSink.glb", 2.35, true)
	sink.position = Vector3(4.6, FLOOR_Y + 0.05, -3.1)
	add_child(sink)
	for x in [-1.75, 4.2]:
		var upper := Models.node_by_height(DIR + "kitchenCabinetUpper.glb", 1.8, true)
		upper.position = Vector3(x, COUNTER_Y + 2.6, WALL_Z + 0.95)
		add_child(upper)
	var rack := Models.node(DIR + "tinytreats/dishrack_plates.gltf", 1.3, true)
	rack.position = Vector3(3.0, COUNTER_Y, -2.4)
	add_child(rack)
	_build_shelf()
	_build_upper_wall()


## Die obere Bildhälfte (y ≈ 2,4 … 5,0) wäre sonst kahle Wand: Topfleiste mit
## Pfannen, Dunstabzug über dem Herd und eine Wanduhr füllen sie. Alles steht
## an der WAND (z ≈ WALL_Z), die Flugebene z = 0 bleibt frei.
func _build_upper_wall() -> void:
	var bar := MeshInstance3D.new()
	var bar_mesh := CylinderMesh.new()
	bar_mesh.top_radius = 0.06
	bar_mesh.bottom_radius = 0.06
	bar_mesh.height = 20.0
	bar_mesh.radial_segments = 8
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.82, 0.85, 0.88)
	steel.metallic = 0.55
	steel.roughness = 0.3
	bar_mesh.material = steel
	bar.mesh = bar_mesh
	bar.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	bar.position = Vector3(0.4, 4.2, WALL_Z + 0.8)
	add_child(bar)
	var hangers := [
		["frying-pan.glb", -2.9, 1.1], ["pot-stew.glb", -1.4, 0.95], ["frying-pan.glb", 2.4, 0.9]
	]
	for entry: Array in hangers:
		var pan := Models.node(DIR + str(entry[0]), float(entry[2]), false)
		pan.position = Vector3(float(entry[1]), 3.7, WALL_Z + 0.8)
		pan.rotation_degrees = Vector3(88.0, 0.0, 0.0)
		add_child(pan)
	var hood := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.5
	cone.bottom_radius = 1.9
	cone.height = 1.5
	cone.radial_segments = 4
	var hood_mat := StandardMaterial3D.new()
	hood_mat.albedo_color = Color(0.9, 0.92, 0.94)
	hood_mat.metallic = 0.45
	hood_mat.roughness = 0.35
	cone.material = hood_mat
	hood.mesh = cone
	hood.rotation_degrees = Vector3(0.0, 45.0, 0.0)
	hood.position = Vector3(-4.4, 1.6, -3.1)
	add_child(hood)
	var clock := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.52
	disc.bottom_radius = 0.52
	disc.height = 0.14
	disc.radial_segments = 20
	var face := StandardMaterial3D.new()
	face.albedo_color = Color(0.99, 0.97, 0.92)
	disc.material = face
	clock.mesh = disc
	clock.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	clock.position = Vector3(3.9, 2.75, WALL_Z + 0.3)
	add_child(clock)
	_build_ceiling()


## Decke mit zwei Balken: ohne sie läuft die Kachelwand hochkant ins Nichts und
## das obere Bilddrittel bleibt eine leere Pastellfläche.
func _build_ceiling() -> void:
	var slab := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 12.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.99, 0.94, 0.88)
	mat.roughness = 1.0
	plane.material = mat
	slab.mesh = plane
	slab.rotation_degrees = Vector3(180.0, 0.0, 0.0)
	slab.position = Vector3(0.0, 5.1, -1.5)
	add_child(slab)
	var beam_mat := StandardMaterial3D.new()
	beam_mat.albedo_color = Color(0.72, 0.5, 0.36)
	beam_mat.roughness = 0.95
	for z in [-3.4, -0.6]:
		var beam := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(30.0, 0.42, 0.5)
		box.material = beam_mat
		beam.mesh = box
		beam.position = Vector3(0.0, 4.85, float(z))
		add_child(beam)


## Wandbrett über der Platte: füllt die obere Bildhälfte, ohne den Flugbogen
## zuzustellen (die Stücke fliegen auf z = 0, das Brett steht an der Wand).
func _build_shelf() -> void:
	var board := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(6.4, 0.16, 0.7)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.76, 0.53, 0.37)
	mat.roughness = 0.9
	box.material = mat
	board.mesh = box
	board.position = Vector3(0.2, 2.05, WALL_Z + 0.55)
	add_child(board)
	var jars := [
		["tomato.glb", -1.55], ["mushroom.glb", -0.6], ["lemon.glb", 0.9], ["onion.glb", 1.85]
	]
	for entry: Array in jars:
		var prop := Models.node(DIR + str(entry[0]), 0.5, true)
		prop.position = Vector3(0.2 + float(entry[1]), 2.13, WALL_Z + 0.55)
		add_child(prop)


func _build_gooby() -> void:
	gooby = GoobyRig.new()
	gooby.name = "GoobyChef"
	# Rig-Höhe 1.13 wu → 3.4 wu Kochgröße auf einem Podest hinter der Platte:
	# nur so ragt Gooby weit genug über die Arbeitsplatte ins Bild.
	gooby.scale = Vector3.ONE * 3.4
	gooby.position = Vector3(-1.15, FLOOR_Y + 0.55, -2.9)
	gooby.rotation_degrees = Vector3(0.0, 14.0, 0.0)
	add_child(gooby)
	gooby.set_emotion(_emotion)
	gooby.play_clip("build_hammer")
	_build_hat()
	_build_knife()


## Kochmütze auf Kopfhöhe (fester Aufsatz — das Rig steht schnippelnd fest).
func _build_hat() -> void:
	var hat := Node3D.new()
	# Am Kopf-Knochen (Rig-y ≈ 0,457) statt am Rig-Ursprung: `build_hammer`
	# beugt den Oberkörper, ein fester Aufsatz bliebe stehen. +0,38 ist die
	# Schädeldecke — die 1,13 Rig-Höhe sind bis zu den OHRENSPITZEN gemessen,
	# ein Hut auf dieser Höhe schwebte über dem Kopf.
	hat.position = Vector3(0.0, 0.38, -0.03)
	hat.rotation_degrees = Vector3(-6.0, 0.0, 5.0)
	Models.bone_mount(gooby).add_child(hat)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.99, 0.97)
	mat.roughness = 0.95
	var band := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.155
	cyl.bottom_radius = 0.17
	cyl.height = 0.1
	cyl.radial_segments = 14
	cyl.material = mat
	band.mesh = cyl
	hat.add_child(band)
	var puff := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.2
	ball.height = 0.28
	ball.radial_segments = 14
	ball.rings = 8
	ball.material = mat
	puff.mesh = ball
	puff.position = Vector3(0.0, 0.15, 0.0)
	hat.add_child(puff)


func _build_knife() -> void:
	_knife = Node3D.new()
	_knife.position = Vector3(-0.55, COUNTER_Y + 0.25, -1.5)
	_knife.rotation_degrees = Vector3(0.0, 0.0, -18.0)
	add_child(_knife)
	var blade := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.12, 0.16, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.9, 0.94)
	mat.metallic = 0.6
	mat.roughness = 0.25
	box.material = mat
	blade.mesh = box
	_knife.add_child(blade)
	var grip := MeshInstance3D.new()
	var gbox := BoxMesh.new()
	gbox.size = Vector3(0.14, 0.16, 0.44)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.44, 0.29, 0.2)
	gbox.material = gmat
	grip.mesh = gbox
	grip.position = Vector3(0.0, 0.0, 0.68)
	_knife.add_child(grip)


func _build_effects() -> void:
	_splash = (
		Puff
		. burst(
			DIR + "vfx/circle_05.png",
			{
				"amount": 22,
				"lifetime": 0.65,
				"size": 0.3,
				"dir": Vector3.UP,
				"spread": 180.0,
				"speed": Vector2(1.8, 4.0),
				"gravity": Vector3(0.0, -5.0, 0.0),
				"color": Color(1.0, 0.8, 0.5, 1.0),
				"color_end": Color(1.0, 0.7, 0.4, 0.0),
				"add": false,
				"local": false,
			}
		)
	)
	add_child(_splash)
	_steam = (
		Puff
		. stream(
			DIR + "vfx/circle_05.png",
			{
				"amount": 12,
				"lifetime": 2.2,
				"size": 0.42,
				"dir": Vector3.UP,
				"spread": 12.0,
				"speed": Vector2(0.5, 0.9),
				"gravity": Vector3(0.0, 0.35, 0.0),
				"color": Color(1.0, 1.0, 1.0, 0.3),
				"color_end": Color(1.0, 1.0, 1.0, 0.0),
				"add": false,
				"scale_range": Vector2(0.6, 1.8),
			}
		)
	)
	_steam.position = Vector3(1.75, COUNTER_Y + 0.8, -2.5)
	add_child(_steam)
	# Warmes Deckenlicht direkt über dem Brett — der Lichtkegel gibt der
	# Pastellküche die Tiefe, die ein reines Sonnen+Fülllicht nicht schafft.
	var lamp := OmniLight3D.new()
	lamp.light_color = Color(1.0, 0.86, 0.66)
	lamp.light_energy = 5.5
	lamp.omni_range = 9.0
	lamp.position = Vector3(0.2, COUNTER_Y + 3.2, -1.0)
	add_child(lamp)


# ── Pool + Takt ───────────────────────────────────────────────────────────


func _take(key: String) -> Node3D:
	if not _pools.has(key):
		_pools[key] = []
	var free: Array = _pools[key]
	if not free.is_empty():
		return free.pop_back() as Node3D
	var node := _make(key)
	if node == null:
		return null
	(_items if not key.begins_with("half:") else _halves).add_child(node)
	return node


func _make(key: String) -> Node3D:
	var file := ""
	if key.begins_with("half:"):
		file = key.substr(5) + ".glb"
	elif JUNK_FILES.has(key):
		file = str(JUNK_FILES[key])
	else:
		file = key + ".glb"
	var target := ITEM_SIZE if not key.begins_with("half:") else ITEM_SIZE * 0.8
	var node := Models.node(DIR + file, target, false)
	node.visible = false
	return node


func _tick_halves(_elapsed: float) -> void:
	var delta := get_process_delta_time()
	var kept: Array = []
	for entry: Dictionary in _flying:
		entry["age"] = float(entry["age"]) + delta
		var node: Node3D = entry["node"]
		var vel: Vector3 = entry["vel"]
		vel.y -= 11.0 * delta
		entry["vel"] = vel
		node.position += vel * delta
		node.rotation += (entry["spin"] as Vector3) * delta
		if float(entry["age"]) < 1.1:
			kept.append(entry)
		else:
			node.visible = false
			(_pools[entry["key"]] as Array).append(node)
	_flying = kept
