extends RefCounted
## Angelteich-KULISSE (Agent MP-E, Tiefenpolitur): alles, was den Teich zu
## einem Ort macht — Anglerhütte mit warm leuchtendem Fenster, Schilfgürtel,
## Enten auf dem Wasser, eine Laterne am Steg und der Fang-Eimer neben Gooby.
##
## Nur Kulisse, keine Mechanik. Enten und Eimer gehen als Nodes zurück an die
## Spielszene: die Enten paddeln in `_process`, der Eimer sammelt die Fänge.

const Props3D := preload("res://scripts/minigames/games/_3da_stage/props3d.gd")

const HUT_WOOD := Color(0.42, 0.29, 0.22)
const HUT_ROOF := Color(0.3, 0.22, 0.24)
const REED_GREEN := Color(0.3, 0.45, 0.28)
const REED_TIP := Color(0.45, 0.3, 0.18)
const DUCK_BODY := Color(0.93, 0.88, 0.78)
const DUCK_HEAD := Color(0.35, 0.5, 0.32)
const BUCKET_TIN := Color(0.55, 0.58, 0.64)

## Standplätze der Schilfbüschel: hinterm Becken und am linken Ufer — nie vor
## der Schnittkante (dort steht die Kamera) und nie überm Schwimmbereich.
const REED_SPOTS := [
	Vector3(-2.6, 0.26, -1.9),
	Vector3(-2.9, 0.26, -1.1),
	Vector3(-2.45, 0.26, -0.2),
	Vector3(2.5, 0.26, -1.95),
	Vector3(2.85, 0.26, -1.15),
	Vector3(-1.5, 0.26, -2.15),
	Vector3(0.6, 0.26, -2.2),
	Vector3(1.7, 0.26, -2.1),
]

## Ruheplätze der Enten auf dem Wasser (links, weg von Schnur und Schwimmern).
const DUCK_SPOTS := [
	Vector3(-1.35, 0.02, -1.25),
	Vector3(-0.65, 0.02, -1.55),
	Vector3(1.15, 0.02, -1.45),
]


## Baut die komplette Kulisse; gibt {"ducks": Node3D, "bucket": Node3D} zurück.
static func build(stage: Node3D) -> Dictionary:
	_hut(stage)
	_reeds(stage)
	_lantern(stage)
	return {"ducks": _ducks(stage), "bucket": _bucket(stage)}


## Enten paddeln: gemächliches Hin und Her um den Ruheplatz, Wippen mit der
## Dünung, Blick in Fahrtrichtung. Läuft jeden Frame aus der Spielszene.
static func tick_ducks(flock: Node3D, elapsed: float) -> void:
	if flock == null:
		return
	for duck: Node3D in flock.get_children():
		var home: Vector3 = duck.get_meta("home")
		var phase: float = duck.get_meta("phase")
		var t := elapsed * 0.32 + phase
		duck.position = Vector3(
			home.x + sin(t) * 0.42, home.y + sin(elapsed * 2.0 + phase) * 0.015, home.z
		)
		# Kopf (−z) in Fahrtrichtung: dx > 0 → yaw −π/2.
		var target_yaw := -signf(cos(t)) * PI * 0.5 + 0.2 * sin(elapsed * 1.3 + phase)
		duck.rotation.y = lerp_angle(duck.rotation.y, target_yaw, 0.04)


## Fang-Flüge: der gefangene Fisch segelt in einem Bogen vom Haken in den
## Eimer. Bei der Landung wächst eine Schwanzflosse aus dem Eimerwasser.
static func tick_flights(flights: Array, bucket: Node3D, delta: float) -> void:
	for i in range(flights.size() - 1, -1, -1):
		var f: Dictionary = flights[i]
		f["t"] = float(f["t"]) + delta / 0.55
		var t: float = minf(1.0, float(f["t"]))
		var node: Node3D = f["node"]
		var from: Vector3 = f["from"]
		var to: Vector3 = bucket.position + Vector3(0.0, 0.22, 0.0)
		node.position = from.lerp(to, t) + Vector3(0.0, sin(t * PI) * 0.9, 0.0)
		node.rotation.z = t * TAU * 1.5
		if t >= 1.0:
			_add_trophy(bucket, f.get("color", DUCK_HEAD))
			node.queue_free()
			flights.remove_at(i)


## Schwanzflosse im Eimer (max. 6): flachgedrückte Kugel in Artenfarbe, leicht
## gekippt — als ragte der Fisch kopfüber im Wasser.
static func _add_trophy(bucket: Node3D, color: Color) -> void:
	var count := int(bucket.get_meta("fins", 0))
	if count >= 6:
		return
	bucket.set_meta("fins", count + 1)
	var a := float(count) * 2.4
	var fin := Props3D.sphere(0.055, Props3D.flat(color, 0.6))
	fin.scale = Vector3(0.35, 1.25, 0.8)
	fin.position = Vector3(cos(a) * 0.06, 0.24, sin(a) * 0.06)
	fin.rotation.z = 0.35 * sin(a)
	bucket.add_child(fin)


## Anglerhütte am rechten Ufer hinter dem Steg: Bretterwände, Satteldach,
## warm leuchtendes Fenster — das Licht macht die Dämmerung erst gemütlich.
static func _hut(stage: Node3D) -> void:
	var hut := Node3D.new()
	hut.name = "Hut"
	var wood := Props3D.flat(HUT_WOOD, 0.9)
	hut.add_child(Props3D.box(Vector3(2.3, 1.5, 1.7), wood, Vector3(0.0, 0.75, 0.0)))
	# Bretterfugen als dunkle Streifen — sonst liest sich die Wand als Plastik.
	var seam := BoxMesh.new()
	seam.size = Vector3(2.32, 0.035, 1.72)
	seam.material = Props3D.flat(HUT_WOOD.darkened(0.35), 0.95)
	var seams: Array = []
	for i in 4:
		seams.append(Props3D.pose(Vector3(0.0, 0.3 + 0.34 * float(i), 0.0)))
	hut.add_child(Props3D.swarm_mesh(seam, seams, 4.0))
	var roof := PrismMesh.new()
	roof.size = Vector3(2.7, 0.85, 2.1)
	roof.material = Props3D.flat(HUT_ROOF, 0.85)
	hut.add_child(Props3D.mesh_node(roof, Vector3(0.0, 1.92, 0.0)))
	# Fenster zur Kamera: warmes Licht, der Blickfang der ganzen Uferzeile.
	hut.add_child(
		Props3D.box(
			Vector3(0.5, 0.44, 0.05),
			Props3D.glow(Color(1.0, 0.78, 0.42), 1.7),
			Vector3(-0.5, 0.95, 0.87)
		)
	)
	hut.add_child(
		Props3D.box(
			Vector3(0.42, 0.9, 0.05),
			Props3D.flat(HUT_WOOD.darkened(0.5)),
			Vector3(0.55, 0.45, 0.87)
		)
	)
	# Weit genug hinten, dass sie AUCH im schmalen Hochformat im Bild steht —
	# bei x 4,6 sah man dort nur noch die Laterne und eine Dachkante.
	hut.position = Vector3(3.3, 0.26, -5.2)
	hut.rotation.y = -0.35
	stage.add_child(hut)


## Schilfgürtel: Halme als eine MultiMesh, Kolben als zweite — zwei Draw-Calls
## für den ganzen Bewuchs. Jeder Standplatz bekommt 4–5 Halme mit Streuung.
static func _reeds(stage: Node3D) -> void:
	var stalk := CylinderMesh.new()
	stalk.top_radius = 0.016
	stalk.bottom_radius = 0.024
	stalk.height = 1.0
	stalk.radial_segments = 5
	stalk.rings = 1
	stalk.material = Props3D.flat(REED_GREEN, 0.9)
	var tip := CapsuleMesh.new()
	tip.radius = 0.04
	tip.height = 0.24
	tip.radial_segments = 6
	tip.rings = 2
	tip.material = Props3D.flat(REED_TIP, 0.9)
	var stalks: Array = []
	var tips: Array = []
	for s in REED_SPOTS.size():
		var spot: Vector3 = REED_SPOTS[s]
		for i in 5:
			var a := float(s * 5 + i) * 2.39996
			var off := Vector3(cos(a) * 0.22, 0.0, sin(a) * 0.14)
			var h := 0.75 + 0.3 * absf(sin(a * 1.7))
			var at := spot + off
			var lean := 0.09 * sin(a * 3.1)
			var xf := Transform3D(
				Basis.from_euler(Vector3(lean, a, lean * 0.6)).scaled(Vector3(1.0, h, 1.0)),
				at + Vector3(0.0, h * 0.5, 0.0)
			)
			stalks.append(xf)
			if i % 2 == 0:
				tips.append(
					Transform3D(
						Basis.from_euler(Vector3(lean, a, lean * 0.6)),
						at + Vector3(0.0, h + 0.08, 0.0)
					)
				)
	stage.add_child(Props3D.swarm_mesh(stalk, stalks, 8.0))
	stage.add_child(Props3D.swarm_mesh(tip, tips, 8.0))


## Enten: Rumpf, Kopf, Schnabel — drei Blobs, die in `_tick_ducks` der
## Spielszene gemächlich paddeln und mit der Dünung wippen.
static func _ducks(stage: Node3D) -> Node3D:
	var flock := Node3D.new()
	flock.name = "Ducks"
	for i in DUCK_SPOTS.size():
		var duck := Node3D.new()
		var body := Props3D.sphere(0.11, Props3D.flat(DUCK_BODY, 0.8))
		body.position.y = 0.05
		body.scale = Vector3(1.0, 0.8, 1.45)
		duck.add_child(body)
		var tail := Props3D.sphere(0.05, Props3D.flat(DUCK_BODY.darkened(0.12), 0.8))
		tail.position = Vector3(0.0, 0.1, 0.15)
		tail.scale = Vector3(1.0, 0.7, 1.3)
		duck.add_child(tail)
		var head := Props3D.sphere(
			0.06, Props3D.flat(DUCK_HEAD if i % 2 == 0 else DUCK_BODY.darkened(0.06), 0.8)
		)
		head.position = Vector3(0.0, 0.17, -0.13)
		duck.add_child(head)
		var beak := Props3D.box(
			Vector3(0.045, 0.025, 0.07), Props3D.flat(Color(0.95, 0.62, 0.25), 0.7)
		)
		beak.position = Vector3(0.0, 0.16, -0.2)
		duck.add_child(beak)
		duck.position = DUCK_SPOTS[i]
		duck.set_meta("home", DUCK_SPOTS[i])
		duck.set_meta("phase", float(i) * 2.1)
		flock.add_child(duck)
	stage.add_child(flock)
	return flock


## Laterne am Stegpfahl: dunkler Mast, warm glühender Kopf plus Halo — sie
## beleuchtet Goobys Arbeitsplatz und spiegelt die Abendstimmung.
static func _lantern(stage: Node3D) -> void:
	var post := Node3D.new()
	post.name = "Lantern"
	post.add_child(
		Props3D.cylinder(
			0.035, 1.5, Props3D.flat(Color(0.3, 0.26, 0.24), 0.9), Vector3(0.0, 0.75, 0.0)
		)
	)
	post.add_child(
		Props3D.box(
			Vector3(0.14, 0.18, 0.14),
			Props3D.glow(Color(1.0, 0.8, 0.45), 2.0),
			Vector3(0.0, 1.5, 0.0)
		)
	)
	post.add_child(
		Props3D.box(
			Vector3(0.18, 0.04, 0.18),
			Props3D.flat(Color(0.24, 0.2, 0.2), 0.9),
			Vector3(0.0, 1.62, 0.0)
		)
	)
	var halo := Props3D.halo(0.5, Color(1.0, 0.75, 0.4, 0.4))
	halo.position = Vector3(0.0, 1.5, 0.0)
	post.add_child(halo)
	post.position = Vector3(2.6, 0.44, -0.85)
	stage.add_child(post)


## Fang-Eimer auf dem Steg: Blechzylinder mit dunklem Wasser drin. Die
## Spielszene lässt gefangene Fische hineinfliegen und steckt pro Fang eine
## Schwanzflosse hinein — der Punktestand wird als Ding in der Welt sichtbar.
static func _bucket(stage: Node3D) -> Node3D:
	var bucket := Node3D.new()
	bucket.name = "Bucket"
	var tin := CylinderMesh.new()
	tin.top_radius = 0.16
	tin.bottom_radius = 0.12
	tin.height = 0.24
	tin.radial_segments = 12
	tin.rings = 1
	tin.material = Props3D.flat(BUCKET_TIN, 0.45)
	bucket.add_child(Props3D.mesh_node(tin, Vector3(0.0, 0.12, 0.0)))
	var water := CylinderMesh.new()
	water.top_radius = 0.135
	water.bottom_radius = 0.135
	water.height = 0.02
	water.radial_segments = 12
	water.rings = 1
	water.material = Props3D.flat(Color(0.14, 0.3, 0.36), 0.3)
	bucket.add_child(Props3D.mesh_node(water, Vector3(0.0, 0.2, 0.0)))
	var handle := Props3D.torus(0.15, 0.012, Props3D.flat(BUCKET_TIN.darkened(0.25), 0.4))
	handle.rotation.x = PI * 0.45
	handle.position.y = 0.2
	bucket.add_child(handle)
	bucket.position = Vector3(2.28, 0.44, 0.42)
	stage.add_child(bucket)
	return bucket
