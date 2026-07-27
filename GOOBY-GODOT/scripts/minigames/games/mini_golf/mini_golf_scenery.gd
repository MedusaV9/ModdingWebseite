extends RefCounted
## Minigolf-ANLAGE (Agent MP-E, Tiefenpolitur): die Kulisse rund um die aktive
## Bahn. Vorher stand die Bahn allein auf einer leeren Wiese — jetzt ist sie
## Teil eines Platzes: Nachbarbahnen mit Fahnen im Hintergrund, ein Kiosk mit
## Sonnenschirm, eine Lichterkette überm Platz, ein Lattenzaun als Platzgrenze
## und ein Trampelpfad zum Abschlag.
##
## Nur Kulisse, keine Mechanik. Alles Massenware über Props3D.swarm/-_mesh —
## die ganze Anlage kostet rund 20 Draw-Calls.

const Props3D := preload("res://scripts/minigames/games/_3da_stage/props3d.gd")

const ASSETS := "res://assets/minigames/mini_golf/"

## Filz der Deko-Bahnen: gleiche Familie wie die aktive Bahn, hell genug, um
## sich von der Wiese abzuheben, aber gedeckter als die echte Bahn.
const DECO_FELT := Color(0.58, 0.86, 0.58)
const DECO_RAIL := Color(0.82, 0.68, 0.48)
const KIOSK_WOOD := Color(0.85, 0.64, 0.42)
const KIOSK_ROOF := Color(0.93, 0.42, 0.45)
const POLE_WOOD := Color(0.62, 0.45, 0.32)

## Deko-Bahnen: Position, Drehung, Länge — von Hand gestellt, damit sie die
## Kamera-Schneise (kleine z, |x| < 5) und die aktive Bahn nie berühren.
const LANES := [
	{"at": Vector3(-5.9, 0.0, 3.4), "yaw": 0.5, "len": 3.4},
	{"at": Vector3(5.7, 0.0, 2.4), "yaw": -0.45, "len": 3.0},
	{"at": Vector3(2.6, 0.0, 7.6), "yaw": 1.25, "len": 3.6},
	{"at": Vector3(-3.1, 0.0, 7.9), "yaw": -1.05, "len": 2.8},
]


## Baut die komplette Anlage in die Bühne.
static func build(stage: Node3D) -> void:
	_deco_lanes(stage)
	_fence_ring(stage)
	_kiosk(stage)
	_festoon(stage)
	_tee_path(stage)


## Nachbarbahnen: Filzstreifen mit Banden, Loch-Punkt und roter Fahne. Sie
## erzählen „Anlage mit vielen Bahnen" — und geben dem Mittelgrund Tiefe.
static func _deco_lanes(stage: Node3D) -> void:
	var felt_mesh := BoxMesh.new()
	felt_mesh.size = Vector3(1.0, 0.12, 1.0)
	felt_mesh.material = Props3D.flat(DECO_FELT)
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(0.1, 0.16, 1.0)
	rail_mesh.material = Props3D.flat(DECO_RAIL, 0.8)
	var cup_mesh := CylinderMesh.new()
	cup_mesh.top_radius = 0.11
	cup_mesh.bottom_radius = 0.11
	cup_mesh.height = 0.02
	cup_mesh.radial_segments = 10
	cup_mesh.rings = 1
	cup_mesh.material = Props3D.flat(Color(0.12, 0.11, 0.11))
	var felts: Array = []
	var rails: Array = []
	var cups: Array = []
	var flags: Array = []
	for lane: Dictionary in LANES:
		var at: Vector3 = lane["at"] as Vector3 + Vector3(0.0, 0.055, 0.0)
		var yaw := float(lane["yaw"])
		var basis := Basis(Vector3.UP, yaw)
		var length := float(lane["len"])
		felts.append(Transform3D(basis * Basis.from_scale(Vector3(1.05, 1.0, length)), at))
		for side: float in [-1.0, 1.0]:
			rails.append(
				Transform3D(
					basis * Basis.from_scale(Vector3(1.0, 1.0, length + 0.1)),
					at + basis * Vector3(side * 0.56, 0.06, 0.0)
				)
			)
		var cup_at := at + basis * Vector3(0.0, 0.062, length * 0.32)
		cups.append(Transform3D(basis, cup_at))
		flags.append(Props3D.pose(cup_at, yaw + 2.2, 1.15))
	stage.add_child(Props3D.swarm_mesh(felt_mesh, felts, 30.0))
	stage.add_child(Props3D.swarm_mesh(rail_mesh, rails, 30.0))
	stage.add_child(Props3D.swarm_mesh(cup_mesh, cups, 30.0))
	stage.add_child(Props3D.swarm(Props3D.parts(ASSETS + "flag-red.glb", 1.0), flags, 30.0))


## Lattenzaun als Platzgrenze — nur der hintere Halbkreis, die Kamera steht
## vorn. Tangential gedreht, damit die Felder eine geschlossene Linie bilden.
static func _fence_ring(stage: Node3D) -> void:
	var poses: Array = []
	var segments := 20
	for i in segments:
		var a := lerpf(-1.72, 1.72, float(i) / float(segments - 1))
		var at := Vector3(sin(a) * 8.5, 0.0, 2.0 + cos(a) * 8.5)
		poses.append(Props3D.pose(at, -a + PI * 0.5, 1.0))
	stage.add_child(
		Props3D.swarm(Props3D.parts(ASSETS + "fence_simple.glb", 0.62, Props3D.NATURE), poses)
	)


## Kiosk mit Sonnenschirm: der soziale Anker der Anlage (hier gibt es Eis).
## Steht rechts hinten, wo der Baumkranz eine Lücke lässt.
static func _kiosk(stage: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "Kiosk"
	holder.position = Vector3(-5.8, 0.0, 4.4)
	holder.rotation.y = 2.27
	holder.add_child(
		Props3D.box(Vector3(1.7, 1.1, 1.2), Props3D.flat(KIOSK_WOOD, 0.85), Vector3(0.0, 0.55, 0.0))
	)
	holder.add_child(
		Props3D.box(
			Vector3(1.6, 0.28, 0.08),
			Props3D.flat(Color(0.99, 0.97, 0.9), 0.7),
			Vector3(0.0, 0.94, 0.63)
		)
	)
	holder.add_child(
		Props3D.box(
			Vector3(1.9, 0.1, 1.5), Props3D.flat(KIOSK_ROOF, 0.75), Vector3(0.0, 1.22, 0.05)
		)
	)
	holder.add_child(
		Props3D.box(
			Vector3(1.9, 0.1, 0.5),
			Props3D.flat(KIOSK_ROOF.lightened(0.18), 0.75),
			Vector3(0.0, 1.34, -0.4)
		)
	)
	var pole := Props3D.cylinder(0.035, 1.9, Props3D.flat(POLE_WOOD, 0.8))
	pole.position = Vector3(1.35, 0.95, 0.75)
	holder.add_child(pole)
	var shade := CylinderMesh.new()
	shade.top_radius = 0.05
	shade.bottom_radius = 1.05
	shade.height = 0.42
	shade.radial_segments = 10
	shade.rings = 1
	shade.material = Props3D.flat(Color(0.98, 0.8, 0.4), 0.8)
	var parasol := Props3D.mesh_node(shade, Vector3(1.35, 1.95, 0.75))
	holder.add_child(parasol)
	stage.add_child(holder)


## Lichterkette überm hinteren Platz: zwei Pfosten, dazwischen ein
## durchhängendes Band aus warmen Glühbirnen (EIN MultiMesh).
static func _festoon(stage: Node3D) -> void:
	var from := Vector3(-4.4, 2.15, 7.4)
	var to := Vector3(4.8, 2.25, 6.6)
	for at: Vector3 in [from, to]:
		var post := Props3D.cylinder(0.05, at.y, Props3D.flat(POLE_WOOD, 0.85))
		post.position = Vector3(at.x, at.y * 0.5, at.z)
		stage.add_child(post)
	var bulb := SphereMesh.new()
	bulb.radius = 0.055
	bulb.height = 0.11
	bulb.radial_segments = 8
	bulb.rings = 4
	bulb.material = Props3D.glow(Color(1.0, 0.85, 0.5), 1.6)
	var poses: Array = []
	var count := 14
	for i in count:
		var f := float(i + 1) / float(count + 1)
		var at := from.lerp(to, f)
		at.y -= sin(f * PI) * 0.5
		poses.append(Props3D.pose(at))
	stage.add_child(Props3D.swarm_mesh(bulb, poses, 30.0))


## Trittsteine vom Platzrand zum Abschlag — führen das Auge zur Bahn.
static func _tee_path(stage: Node3D) -> void:
	var stone := CylinderMesh.new()
	stone.top_radius = 0.14
	stone.bottom_radius = 0.16
	stone.height = 0.035
	stone.radial_segments = 8
	stone.rings = 1
	stone.material = Props3D.flat(Color(0.72, 0.68, 0.6), 0.95)
	var poses: Array = []
	for i in 8:
		var at := Vector3(1.55 + 0.42 * sin(float(i) * 1.6), 0.015, -1.1 - float(i) * 0.55)
		poses.append(Props3D.pose(at, float(i) * 0.8, 0.85 + 0.2 * float(i % 2)))
	stage.add_child(Props3D.swarm_mesh(stone, poses, 20.0))
	_golf_bag(stage)
	_planter(stage)


## Golftasche neben dem Abschlag — Goobys Ausrüstung füllt den Vordergrund
## und erzählt, dass HIER gespielt wird.
static func _golf_bag(stage: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "GolfBag"
	holder.position = Vector3(1.72, 0.0, -1.05)
	holder.rotation = Vector3(0.0, 0.6, 0.24)
	var body := Props3D.cylinder(0.17, 0.62, Props3D.flat(Color(0.88, 0.42, 0.44), 0.85))
	body.position.y = 0.31
	holder.add_child(body)
	var rim := Props3D.cylinder(0.175, 0.05, Props3D.flat(Color(0.62, 0.28, 0.3), 0.85))
	rim.position.y = 0.62
	holder.add_child(rim)
	var shaft_mesh := CylinderMesh.new()
	shaft_mesh.top_radius = 0.014
	shaft_mesh.bottom_radius = 0.014
	shaft_mesh.height = 0.5
	shaft_mesh.radial_segments = 6
	shaft_mesh.rings = 1
	shaft_mesh.material = Props3D.flat(Color(0.85, 0.87, 0.9), 0.4)
	var shafts: Array = []
	for i in 3:
		var a := float(i) * 2.1
		shafts.append(
			Transform3D(
				Basis(Vector3.FORWARD, 0.12 * sin(a)), Vector3(0.07 * sin(a), 0.86, 0.07 * cos(a))
			)
		)
	holder.add_child(Props3D.swarm_mesh(shaft_mesh, shafts, 10.0))
	stage.add_child(holder)


## Blumenkasten am unteren Platzrand (Bildvordergrund, verdeckt nichts).
static func _planter(stage: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "Planter"
	holder.position = Vector3(-2.55, 0.0, -2.35)
	holder.rotation.y = -0.5
	holder.add_child(
		Props3D.box(
			Vector3(1.5, 0.3, 0.5),
			Props3D.flat(Color(0.6, 0.44, 0.32), 0.9),
			Vector3(0.0, 0.15, 0.0)
		)
	)
	var flowers: Array = []
	for i in 4:
		flowers.append(
			Props3D.pose(Vector3(-0.55 + 0.36 * float(i), 0.28, 0.0), float(i) * 1.9, 1.0)
		)
	holder.add_child(
		Props3D.swarm(Props3D.parts(ASSETS + "flower_purpleA.glb", 0.3, Props3D.NATURE), flowers)
	)
	stage.add_child(holder)
