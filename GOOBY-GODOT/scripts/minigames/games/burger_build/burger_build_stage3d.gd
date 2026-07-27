extends "res://scripts/minigames/games/_3dc_stage/stage3d.gd"
## Burger-Bau — 3D-Dinerbühne (Agent 3D-C). Gooby steht als KOCH hinter der
## Theke, aus drei Schächten regnen ECHTE Food-Kit-Zutaten auf einen Teller,
## der auf der Theke mitfährt; dahinter Menütafel, Regal mit Pommes/Soda,
## Kachelwand und Hängelampen.
##
## Projektionsvertrag: die Kamera schaut gerade auf die Spielebene z = 0 und
## ist so gerahmt, dass sie mit `project(wx, wy)` des Spiels deckungsgleich ist
## (Bildmitte = Weltnullpunkt, halbe Bildhöhe = view.y/2 / world_scale).

const Models := preload("res://scripts/minigames/games/_3dc_stage/models3d.gd")
const Puff := preload("res://scripts/minigames/games/_3dc_stage/puff3d.gd")
const DIR := "res://assets/minigames/burger_build/"

## Kameraabstand zur Spielebene.
const CAM_DIST := 16.0
## Tellerhöhe (muss zu PLATE_Y des Spiels passen).
const PLATE_Y := -3.4
## Oberkante der Theke.
const COUNTER_Y := -3.62
const FLOOR_Y := -6.8
const WALL_Z := -5.4
## Breite einer Zutatenlage in Weltmetern.
const LAYER_W := 1.15
## Maximale Höhe einer Zutatenlage.
const LAYER_H := 0.34
## Sichtbare Stapelhöhe je Lage (muss zu _stack_top() des Spiels passen).
const LAYER_STEP := 0.22

## Zutaten-Id → GLB.
const LAYER_FILES := {
	"bun": "bread.glb",
	"patty": "meat-patty.glb",
	"cheese": "cheese-cut.glb",
	"tomato": "tomato-slice.glb",
	"salad": "salad.glb",
	"onion": "onion-half.glb",
}

var gooby: GoobyRig

var _plate: Node3D
var _stack: Node3D
var _rain: Node3D
var _pools: Dictionary = {}
var _busy: Array = []
var _stack_nodes: Array[Node3D] = []
var _marker: MeshInstance3D
var _steam: GPUParticles3D
var _pop: GPUParticles3D
var _lamps: Array[MeshInstance3D] = []
var _emotion := "happy"


func setup_stage(columns: Array) -> void:
	build(
		{
			"sky_top": Color(0.55, 0.72, 0.9),
			"sky_horizon": Color(0.99, 0.9, 0.8),
			"ground_horizon": Color(0.9, 0.78, 0.7),
			"ground_bottom": Color(0.6, 0.4, 0.36),
			"sky_energy": 0.4,
			"ambient": 0.46,
			"sun_color": Color(1.0, 0.87, 0.7),
			"sun_energy": 1.9,
			"sun_dir": Vector3(-0.32, -0.72, -0.6),
			"fill_color": Color(0.78, 0.86, 1.0),
			"fill_energy": 0.55,
			"shadows": false,
			"glow": 0.34,
			"glow_bloom": 0.02,
			"glow_threshold": 1.0,
			"far": 70.0,
		}
	)
	# BELICHTUNGS-EICHUNG: mit der Basis-Belichtung lag das Bild im Mittel bei
	# Luma 200 und 63 % der Pixel über 230 — die Creme-Wand brannte aus und die
	# Bühne las sich flach. Dunkler belichtet kommen Verläufe und Neonlicht
	# zurück; Kontrast/Sättigung geben dem Diner seine warmen, satten Flächen.
	# (Runde 2: 0,74 drückte nur auf Luma 181 — die Filmic-Kurve staucht oben.
	# 0,66 landet bei ~165 und die Creme-Wand behält endlich Zeichnung.)
	environment.tonemap_exposure = 0.66
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.06
	environment.adjustment_saturation = 1.12
	frame(7.36)
	_build_room()
	_build_counter()
	_build_chutes(columns)
	_build_shelf()
	_build_lamps(columns)
	_build_gooby()
	_build_plate()
	_rain = Node3D.new()
	add_child(_rain)
	_build_effects()


## Rahmung an die Orientierung koppeln (Bildmitte bleibt der Weltnullpunkt).
func frame(half_h: float) -> void:
	set_half_height(half_h, CAM_DIST)
	camera.position = Vector3(0.0, 0.0, CAM_DIST)
	camera.rotation = Vector3.ZERO


## Regen + Teller + Stapel je Frame aus dem Spielzustand nachziehen.
func sync(items: Array, plate_x: float, ticket: Array, placed: int, needed: String) -> void:
	for entry: Dictionary in _busy:
		var node: Node3D = entry["node"]
		node.visible = false
		(_pools[entry["key"]] as Array).append(node)
	_busy.clear()
	for item: Dictionary in items:
		var id := str(item["id"])
		var node := _take(id)
		if node == null:
			continue
		node.visible = true
		node.position = Vector3(float(item["x"]), float(item["y"]), 0.0)
		node.rotation.y = float(item["y"]) * 0.6
		_busy.append({"key": id, "node": node})
	_plate.position.x = plate_x
	_marker.visible = not needed.is_empty()
	if _marker.visible:
		_marker.position = Vector3(plate_x, PLATE_Y + 0.02, 0.55)
	_sync_stack(ticket, placed)


## Gooby-Emotion setzen (nur bei Wechsel, sonst flackert der Blend).
func feel(emotion: String) -> void:
	if gooby == null or _emotion == emotion:
		return
	_emotion = emotion
	gooby.set_emotion(emotion)


## Jubel/Ärger-Clip des Kochs.
func cheer(clip: String) -> void:
	if gooby != null:
		gooby.play_clip(clip)


## Mehl-/Funkenwolke über dem Teller.
func poof(color: Color) -> void:
	Puff.fire(_pop, Vector3(_plate.position.x, PLATE_Y + 0.5, 0.2), color)


# ── Aufbau ────────────────────────────────────────────────────────────────


func _build_room() -> void:
	var wall := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(40.0, 26.0, 0.4)
	var mat := StandardMaterial3D.new()
	# Etwas tiefere Creme als vorher (0,98/0,9/0,8): die Wand füllt zwei
	# Bilddrittel — zu hell gerät die ganze Bühne in den Anschlag.
	mat.albedo_color = Color(0.93, 0.84, 0.72)
	mat.roughness = 1.0
	box.material = mat
	wall.mesh = box
	wall.position = Vector3(0.0, 4.0, WALL_Z)
	add_child(wall)
	# Roter Diner-Streifen auf Kopfhöhe.
	var stripe := MeshInstance3D.new()
	var sbox := BoxMesh.new()
	sbox.size = Vector3(40.0, 0.9, 0.1)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.84, 0.27, 0.27)
	sbox.material = smat
	stripe.mesh = sbox
	stripe.position = Vector3(0.0, -1.4, WALL_Z + 0.25)
	add_child(stripe)
	_build_floor()
	_build_windows()
	_build_menu_board()
	_build_wall_dressing()


## Zwei Fenster mit warmem Abendlicht: sie brechen die große Creme-Fläche und
## geben der Küche Tiefe (draußen ist Sonnenuntergang, drinnen brennt Neon).
func _build_windows() -> void:
	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.99, 0.97, 0.94)
	frame_mat.roughness = 0.7
	var glass_mat := StandardMaterial3D.new()
	glass_mat.albedo_color = Color(1.0, 0.78, 0.55)
	glass_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass_mat.emission_enabled = true
	glass_mat.emission = Color(1.0, 0.72, 0.45)
	glass_mat.emission_energy_multiplier = 0.55
	for wx in [-4.35, 4.35]:
		var glass := MeshInstance3D.new()
		var pane := BoxMesh.new()
		pane.size = Vector3(1.9, 2.2, 0.06)
		pane.material = glass_mat
		glass.mesh = pane
		glass.position = Vector3(wx, 2.5, WALL_Z + 0.28)
		add_child(glass)
		var frame := MeshInstance3D.new()
		var fbox := BoxMesh.new()
		fbox.size = Vector3(2.2, 2.5, 0.1)
		fbox.material = frame_mat
		frame.mesh = fbox
		frame.position = Vector3(wx, 2.5, WALL_Z + 0.24)
		add_child(frame)
		var cross := MeshInstance3D.new()
		var cbox := BoxMesh.new()
		cbox.size = Vector3(0.1, 2.2, 0.05)
		cbox.material = frame_mat
		cross.mesh = cbox
		cross.position = Vector3(wx, 2.5, WALL_Z + 0.33)
		add_child(cross)
		var sill := MeshInstance3D.new()
		var sbox2 := BoxMesh.new()
		sbox2.size = Vector3(0.1, 0.05, 2.0)
		sbox2.material = frame_mat
		sill.mesh = sbox2
		sill.rotation_degrees = Vector3(0.0, 0.0, 90.0)
		sill.position = Vector3(wx, 2.5, WALL_Z + 0.33)
		add_child(sill)


## Die obere Wandhälfte wäre sonst leer: Wimpelkette, Wanduhr und zwei
## Leuchtreklame-Ringe füllen den Streifen zwischen Schacht und Menütafel.
func _build_wall_dressing() -> void:
	const FLAGS: Array[Color] = [
		Color(0.95, 0.42, 0.38),
		Color(1.0, 0.82, 0.4),
		Color(0.52, 0.79, 0.72),
		Color(0.78, 0.66, 0.92),
	]
	for i in 18:
		var flag := MeshInstance3D.new()
		var tri := CylinderMesh.new()
		tri.top_radius = 0.0
		tri.bottom_radius = 0.34
		tri.height = 0.62
		tri.radial_segments = 3
		var mat := StandardMaterial3D.new()
		mat.albedo_color = FLAGS[i % FLAGS.size()]
		mat.roughness = 0.9
		tri.material = mat
		flag.mesh = tri
		var t := float(i) / 17.0
		flag.position = Vector3(-11.0 + t * 22.0, 4.9 - sin(t * PI) * 0.9, WALL_Z + 0.5)
		flag.rotation_degrees = Vector3(180.0, 0.0, 0.0)
		add_child(flag)
	var cord := MeshInstance3D.new()
	var cbox := BoxMesh.new()
	cbox.size = Vector3(22.4, 0.07, 0.07)
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.44, 0.36, 0.32)
	cbox.material = cmat
	cord.mesh = cbox
	cord.position = Vector3(0.0, 5.0, WALL_Z + 0.5)
	add_child(cord)
	for entry: Array in [[-7.4, 3.5, 1.05], [7.4, 3.5, 1.05]]:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = float(entry[2]) - 0.16
		torus.outer_radius = float(entry[2])
		torus.rings = 22
		torus.ring_segments = 6
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.62, 0.5)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.5, 0.42)
		mat.emission_energy_multiplier = 2.4
		torus.material = mat
		ring.mesh = torus
		# Aufrichten: der Torus liegt sonst flach und wird von vorn zum Strich.
		ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		ring.position = Vector3(float(entry[0]), float(entry[1]), WALL_Z + 0.4)
		add_child(ring)


## Rot-weißer Schachbrettboden (MultiMesh = 1 Draw-Call je Farbe).
func _build_floor() -> void:
	var slab := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 26.0)
	var base := StandardMaterial3D.new()
	base.albedo_color = Color(0.98, 0.95, 0.92)
	base.roughness = 0.9
	plane.material = base
	slab.mesh = plane
	slab.position = Vector3(0.0, FLOOR_Y, 0.0)
	add_child(slab)
	var tile := BoxMesh.new()
	tile.size = Vector3(1.5, 0.04, 1.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.35, 0.33)
	mat.roughness = 0.9
	tile.material = mat
	var poses: Array = []
	for row in 8:
		for col in 16:
			if (row + col) % 2 != 0:
				continue
			var pos := Vector3(-11.25 + col * 1.5, FLOOR_Y + 0.03, 6.0 - row * 1.5)
			poses.append(Transform3D(Basis.IDENTITY, pos))
	add_child(Models.swarm([{"mesh": tile, "xform": Transform3D.IDENTITY}], poses, 40.0))


func _build_menu_board() -> void:
	var board := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(5.6, 2.4, 0.18)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.24, 0.2, 0.24)
	mat.roughness = 0.95
	box.material = mat
	board.mesh = box
	board.position = Vector3(0.0, 1.6, WALL_Z + 0.3)
	add_child(board)
	# Holzrahmen: ohne ihn liest sich die Tafel als schwebender dunkler Fleck.
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color(0.62, 0.44, 0.3)
	trim.roughness = 0.85
	for edge: Array in [[0.0, 2.86, 5.9, 0.14], [0.0, 0.34, 5.9, 0.14]]:
		var bar := MeshInstance3D.new()
		var bbox := BoxMesh.new()
		bbox.size = Vector3(float(edge[2]), float(edge[3]), 0.2)
		bbox.material = trim
		bar.mesh = bbox
		bar.position = Vector3(float(edge[0]), float(edge[1]), WALL_Z + 0.32)
		add_child(bar)
	for side: float in [-2.87, 2.87]:
		var bar := MeshInstance3D.new()
		var bbox := BoxMesh.new()
		bbox.size = Vector3(0.14, 2.66, 0.2)
		bbox.material = trim
		bar.mesh = bbox
		bar.position = Vector3(side, 1.6, WALL_Z + 0.32)
		add_child(bar)
	var chalk := StandardMaterial3D.new()
	chalk.albedo_color = Color(1.0, 0.96, 0.88)
	chalk.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Gerichte-Chips vor den Kreidezeilen: die Tafel liest sich als Speisekarte
	# statt als vier graue Balken.
	const CHIP_TINTS: Array[Color] = [
		Color(0.91, 0.68, 0.36),
		Color(0.9, 0.31, 0.28),
		Color(1.0, 0.79, 0.28),
		Color(0.5, 0.79, 0.38),
	]
	for i in 4:
		var line := MeshInstance3D.new()
		var lbox := BoxMesh.new()
		lbox.size = Vector3(2.7 - i * 0.4, 0.13, 0.05)
		lbox.material = chalk
		line.mesh = lbox
		line.position = Vector3(-0.35 + i * 0.15, 2.3 - i * 0.48, WALL_Z + 0.42)
		add_child(line)
		var chip := MeshInstance3D.new()
		var cbox := BoxMesh.new()
		cbox.size = Vector3(0.34, 0.26, 0.08)
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = CHIP_TINTS[i]
		cmat.roughness = 0.8
		cbox.material = cmat
		chip.mesh = cbox
		chip.position = Vector3(-2.25, 2.3 - i * 0.48, WALL_Z + 0.42)
		add_child(chip)
	_build_neon_sign()


## Neon-Burger, der VOR dem linken Fenster hängt (wie ein „OPEN"-Schild im
## Diner). Bewusst nicht mittig: dort hängen Lampe und Flash-Text, und die
## Tafel braucht Luft. Links balanciert er den 2D-Bestellzettel rechts aus.
func _build_neon_sign() -> void:
	var holder := Node3D.new()
	# Runde 2: bei x = −3,55 in Originalgröße schnitt das Hochformat den Ring
	# an der Bildkante durch. Etwas kleiner und höher hängt er frei zwischen
	# Wimpelkette und Tafelecke — in BEIDEN Formaten voll im Bild.
	holder.position = Vector3(-3.3, 3.1, WALL_Z + 0.4)
	holder.scale = Vector3.ONE * 0.8
	add_child(holder)
	var back := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.92
	disc.bottom_radius = 0.92
	disc.height = 0.08
	disc.radial_segments = 20
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.3, 0.24, 0.28)
	bmat.roughness = 0.9
	disc.material = bmat
	back.mesh = disc
	back.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	holder.add_child(back)
	# Leuchtender Mini-Burger: Deckel, Patty, Salat, Unterseite als Neonlagen.
	var layers: Array = [
		[Vector3(0.0, 0.3, 0.1), Vector3(0.92, 0.28, 0.3), Color(1.0, 0.74, 0.28), 2.8],
		[Vector3(0.0, 0.08, 0.1), Vector3(1.02, 0.13, 0.32), Color(1.0, 0.4, 0.26), 2.6],
		[Vector3(0.0, -0.08, 0.1), Vector3(1.08, 0.09, 0.34), Color(0.6, 0.96, 0.36), 2.5],
		[Vector3(0.0, -0.24, 0.1), Vector3(0.92, 0.18, 0.3), Color(1.0, 0.74, 0.28), 2.8],
	]
	for entry: Array in layers:
		var slab := MeshInstance3D.new()
		var sbox := BoxMesh.new()
		sbox.size = entry[1]
		var smat := StandardMaterial3D.new()
		smat.albedo_color = entry[2]
		smat.emission_enabled = true
		smat.emission = entry[2]
		smat.emission_energy_multiplier = float(entry[3])
		sbox.material = smat
		slab.mesh = sbox
		slab.position = entry[0]
		holder.add_child(slab)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.86
	torus.outer_radius = 0.98
	torus.rings = 24
	torus.ring_segments = 6
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(1.0, 0.62, 0.5)
	rmat.emission_enabled = true
	rmat.emission = Color(1.0, 0.5, 0.42)
	rmat.emission_energy_multiplier = 3.0
	torus.material = rmat
	ring.mesh = torus
	# Aufrichten — flach läge der Ring als Strich im Bild.
	ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	ring.position = Vector3(0.0, 0.0, 0.12)
	holder.add_child(ring)


func _build_counter() -> void:
	var top := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(26.0, 0.34, 4.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.96, 0.93, 0.89)
	mat.roughness = 0.45
	box.material = mat
	top.mesh = box
	top.position = Vector3(0.0, COUNTER_Y - 0.17, -0.6)
	add_child(top)
	var front := MeshInstance3D.new()
	var fbox := BoxMesh.new()
	fbox.size = Vector3(25.6, 1.9, 3.8)
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.8, 0.36, 0.32)
	fmat.roughness = 0.85
	fbox.material = fmat
	front.mesh = fbox
	front.position = Vector3(0.0, COUNTER_Y - 1.29, -0.65)
	add_child(front)
	var trim := MeshInstance3D.new()
	var tbox := BoxMesh.new()
	tbox.size = Vector3(25.8, 0.3, 3.9)
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.94, 0.94, 0.96)
	tmat.metallic = 0.4
	tmat.roughness = 0.35
	tbox.material = tmat
	trim.mesh = tbox
	trim.position = Vector3(0.0, COUNTER_Y - 2.38, -0.65)
	add_child(trim)
	# Senkrechte Chromleisten + Creme-Paneele: ohne sie ist das untere Bild-
	# fünftel im Hochformat eine einzige korallenrote Fläche.
	var panel := BoxMesh.new()
	panel.size = Vector3(1.5, 1.2, 0.1)
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.97, 0.93, 0.88)
	pmat.roughness = 0.7
	panel.material = pmat
	var strip := BoxMesh.new()
	strip.size = Vector3(0.16, 1.7, 0.12)
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.94, 0.94, 0.96)
	chrome.metallic = 0.5
	chrome.roughness = 0.3
	strip.material = chrome
	var panels: Array = []
	var strips: Array = []
	for i in 12:
		var x := -11.0 + i * 2.0
		panels.append(Transform3D(Basis.IDENTITY, Vector3(x, COUNTER_Y - 1.29, 1.3)))
		strips.append(Transform3D(Basis.IDENTITY, Vector3(x + 1.0, COUNTER_Y - 1.29, 1.31)))
	add_child(Models.swarm([{"mesh": panel, "xform": Transform3D.IDENTITY}], panels, 30.0))
	add_child(Models.swarm([{"mesh": strip, "xform": Transform3D.IDENTITY}], strips, 30.0))
	for x in [-4.6, 4.6]:
		var stool := Models.node_by_height(DIR + "stoolBar.glb", 2.6, true)
		stool.position = Vector3(x, FLOOR_Y + 0.05, 2.6)
		add_child(stool)
	_build_condiments()


## Ketchup- und Senfflasche auf der Theke: Diner-Charakter im Nahbereich,
## bewusst außerhalb der Teller-Fahrspur (±3,0).
func _build_condiments() -> void:
	for entry: Array in [[-5.3, Color(0.82, 0.24, 0.2)], [5.3, Color(0.95, 0.75, 0.25)]]:
		var bottle := Node3D.new()
		bottle.position = Vector3(float(entry[0]), COUNTER_Y, -0.4)
		add_child(bottle)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = entry[1]
		mat.roughness = 0.55
		var body := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.17
		cyl.bottom_radius = 0.21
		cyl.height = 0.62
		cyl.radial_segments = 10
		cyl.material = mat
		body.mesh = cyl
		body.position = Vector3(0.0, 0.31, 0.0)
		bottle.add_child(body)
		var tip := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.03
		cone.bottom_radius = 0.14
		cone.height = 0.26
		cone.radial_segments = 10
		cone.material = mat
		tip.mesh = cone
		tip.position = Vector3(0.0, 0.75, 0.0)
		bottle.add_child(tip)


## Zutatenschächte über den drei Spalten: durchgehende Rohre bis über den
## Bildrand, Mündung mit rotem Bund und warmem Lichtsaum — so sieht man,
## WOHER die Zutaten fallen (vorher schnitt der Bildrand die Kästen ab und
## übrig blieben schwebende rote Deckel).
func _build_chutes(columns: Array) -> void:
	for cx: float in columns:
		var chute := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(1.5, 3.4, 1.4)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.84, 0.86, 0.9)
		mat.metallic = 0.35
		mat.roughness = 0.4
		box.material = mat
		chute.mesh = box
		chute.position = Vector3(cx, 6.8, -0.4)
		add_child(chute)
		var lip := MeshInstance3D.new()
		var lbox := BoxMesh.new()
		lbox.size = Vector3(1.8, 0.3, 1.7)
		var lmat := StandardMaterial3D.new()
		lmat.albedo_color = Color(0.84, 0.32, 0.3)
		lbox.material = lmat
		lip.mesh = lbox
		lip.position = Vector3(cx, 5.0, -0.4)
		add_child(lip)
		var rim := MeshInstance3D.new()
		var rbox := BoxMesh.new()
		rbox.size = Vector3(1.66, 0.1, 1.56)
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color(1.0, 0.86, 0.55)
		rmat.emission_enabled = true
		rmat.emission = Color(1.0, 0.82, 0.5)
		rmat.emission_energy_multiplier = 1.7
		rbox.material = rmat
		rim.mesh = rbox
		rim.position = Vector3(cx, 4.83, -0.4)
		add_child(rim)


func _build_shelf() -> void:
	var board := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(9.0, 0.2, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.78, 0.56, 0.4)
	box.material = mat
	board.mesh = box
	board.position = Vector3(0.0, -0.4, WALL_Z + 0.7)
	add_child(board)
	var props := [
		["soda.glb", -3.3, 0.75],
		["fries.glb", -1.5, 0.8],
		["burger.glb", 1.6, 0.9],
		["soda.glb", 3.2, 0.75]
	]
	for entry: Array in props:
		var prop := Models.node_by_height(DIR + str(entry[0]), float(entry[2]), true)
		prop.position = Vector3(float(entry[1]), -0.3, WALL_Z + 0.7)
		add_child(prop)
	var fridge := Models.node_by_height(DIR + "kitchenFridgeLarge.glb", 4.6, true)
	fridge.position = Vector3(-8.4, FLOOR_Y + 0.05, WALL_Z + 1.4)
	add_child(fridge)
	var micro := Models.node_by_height(DIR + "kitchenMicrowave.glb", 1.1, true)
	micro.position = Vector3(6.6, COUNTER_Y, -1.9)
	add_child(micro)
	var coffee := Models.node_by_height(DIR + "kitchenCoffeeMachine.glb", 1.4, true)
	coffee.position = Vector3(-6.4, COUNTER_Y, -1.9)
	add_child(coffee)


## Hängelampen über den Spalten — der Diner-Blickfang.
func _build_lamps(columns: Array) -> void:
	for cx: float in columns:
		var cord := MeshInstance3D.new()
		var cbox := BoxMesh.new()
		cbox.size = Vector3(0.06, 1.6, 0.06)
		var cmat := StandardMaterial3D.new()
		cmat.albedo_color = Color(0.3, 0.26, 0.24)
		cbox.material = cmat
		cord.mesh = cbox
		cord.position = Vector3(cx, 4.2, 1.4)
		add_child(cord)
		var shade := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.14
		cone.bottom_radius = 0.62
		cone.height = 0.6
		cone.radial_segments = 14
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.9, 0.34, 0.32)
		mat.roughness = 0.6
		cone.material = mat
		shade.mesh = cone
		shade.position = Vector3(cx, 3.2, 1.4)
		add_child(shade)
		var bulb := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.22
		ball.height = 0.44
		ball.radial_segments = 10
		ball.rings = 6
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = Color(1.0, 0.93, 0.7)
		bmat.emission_enabled = true
		bmat.emission = Color(1.0, 0.88, 0.6)
		bmat.emission_energy_multiplier = 2.6
		ball.material = bmat
		bulb.mesh = ball
		bulb.position = Vector3(cx, 2.9, 1.4)
		add_child(bulb)
		_lamps.append(bulb)
		# Warmer Lichthof um die Birne — die Lampen LEUCHTEN statt nur zu glimmen.
		var halo := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(1.7, 1.7)
		halo.mesh = quad
		var hmat := StandardMaterial3D.new()
		hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		hmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		hmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		hmat.albedo_color = Color(1.0, 0.82, 0.5, 0.34)
		hmat.albedo_texture = load(DIR + "vfx/circle_05.png")
		halo.material_override = hmat
		halo.position = Vector3(cx, 2.9, 1.4)
		add_child(halo)


func _build_gooby() -> void:
	gooby = GoobyRig.new()
	gooby.name = "GoobyChef"
	# Rig-Höhe 1.13 wu → 4,7 wu Kochgröße hinter der Theke. Hochkant sind nur
	# ±4,6 wu sichtbar: weiter außen als −3,6 wird Gooby vom Bildrand
	# abgeschnitten, weiter innen verdeckt er den linken Zutatenschacht.
	gooby.scale = Vector3.ONE * 3.9
	gooby.position = Vector3(-2.8, COUNTER_Y - 1.5, -1.9)
	gooby.rotation_degrees = Vector3(0.0, 16.0, 0.0)
	add_child(gooby)
	# Tritt hinter der Theke: sonst schaut nur die Mütze über die Platte.
	var step := MeshInstance3D.new()
	var sbox := BoxMesh.new()
	sbox.size = Vector3(4.4, 1.6, 1.8)
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(0.72, 0.5, 0.36)
	smat.roughness = 0.9
	sbox.material = smat
	step.mesh = sbox
	step.position = Vector3(-2.8, COUNTER_Y - 2.3, -1.9)
	add_child(step)
	gooby.set_emotion(_emotion)
	_build_hat()


func _build_hat() -> void:
	var hat := Node3D.new()
	# Am Kopf-Knochen (Rig-y ≈ 0,457) statt am Rig-Ursprung — sonst bleibt die
	# Mütze stehen, wenn ein Clip oder die Emotions-Pose den Kopf bewegt.
	# +0,38 ist die Schädeldecke (die Rig-Höhe 1,13 geht bis zur Ohrenspitze).
	hat.position = Vector3(0.0, 0.38, -0.03)
	hat.rotation_degrees = Vector3(-6.0, 0.0, 6.0)
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


func _build_plate() -> void:
	_plate = Node3D.new()
	_plate.position = Vector3(0.0, PLATE_Y, 0.0)
	add_child(_plate)
	var dish := Models.node(DIR + "plate-dinner.glb", 2.0, true)
	dish.position.y = -0.16
	_plate.add_child(dish)
	_stack = Node3D.new()
	_plate.add_child(_stack)
	# Leuchtring auf der Theke: zeigt, wo der Teller gerade steht.
	_marker = MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.9
	torus.outer_radius = 1.05
	torus.rings = 20
	torus.ring_segments = 6
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.4, 0.6)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	torus.material = mat
	_marker.mesh = torus
	_marker.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	add_child(_marker)


func _build_effects() -> void:
	_pop = (
		Puff
		. burst(
			DIR + "vfx/star_03.png",
			{
				"amount": 20,
				"lifetime": 0.6,
				"size": 0.34,
				"dir": Vector3.UP,
				"spread": 150.0,
				"speed": Vector2(1.6, 3.4),
				"gravity": Vector3(0.0, -4.0, 0.0),
				"color": Color(1.0, 0.9, 0.55, 1.0),
				"color_end": Color(1.0, 0.7, 0.4, 0.0),
				"local": false,
			}
		)
	)
	add_child(_pop)
	# ADDITIV: die Kenney-Sprites haben SCHWARZEN Grund (kein Alpha) — mit
	# Alpha-Blending rendert jeder Partikel als dunkles Quadrat.
	_steam = (
		Puff
		. stream(
			DIR + "vfx/circle_05.png",
			{
				"amount": 10,
				"lifetime": 2.4,
				"size": 0.5,
				"dir": Vector3.UP,
				"spread": 14.0,
				"speed": Vector2(0.5, 1.0),
				"gravity": Vector3(0.0, 0.4, 0.0),
				"color": Color(1.0, 0.95, 0.88, 0.2),
				"color_end": Color(1.0, 1.0, 1.0, 0.0),
				"scale_range": Vector2(0.6, 1.9),
			}
		)
	)
	# Über dem Show-Burger im Regal — dort ist der Dampf auch hochkant im Bild
	# (die Kaffeemaschine bei x = −6,4 sieht nur das Querformat).
	_steam.position = Vector3(1.6, 0.6, WALL_Z + 0.7)
	add_child(_steam)


# ── Pool + Stapel ─────────────────────────────────────────────────────────


func _take(id: String) -> Node3D:
	if not _pools.has(id):
		_pools[id] = []
	var free: Array = _pools[id]
	if not free.is_empty():
		return free.pop_back() as Node3D
	var node := _layer_node(id)
	_rain.add_child(node)
	return node


## Eine Zutatenlage: auf LAYER_W Breite gebracht und auf LAYER_H flachgedrückt.
func _layer_node(id: String) -> Node3D:
	var file := str(LAYER_FILES.get(id, "cheese-cut.glb"))
	var box := Models.aabb(DIR + file)
	var wide := maxf(0.01, maxf(box.size.x, box.size.z))
	var factor := LAYER_W / wide
	var node := Models.node(DIR + file, 0.0, false)
	node.scale = Vector3(factor, minf(factor, LAYER_H / maxf(0.01, box.size.y)), factor)
	var holder := Node3D.new()
	holder.add_child(node)
	holder.visible = false
	return holder


func _sync_stack(ticket: Array, placed: int) -> void:
	while _stack_nodes.size() > placed:
		var node: Node3D = _stack_nodes.pop_back()
		node.queue_free()
	while _stack_nodes.size() < placed and _stack_nodes.size() < ticket.size():
		var index := _stack_nodes.size()
		var layer := _layer_node(str(ticket[index]))
		layer.visible = true
		layer.position = Vector3(0.0, 0.18 + index * LAYER_STEP, 0.0)
		_stack.add_child(layer)
		_stack_nodes.append(layer)
