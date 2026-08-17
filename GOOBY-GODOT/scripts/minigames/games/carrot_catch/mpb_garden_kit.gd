extends RefCounted
## Kulissen-Baukasten der MP-B-Spiele (bubblePop, carrotCatch, carrotGuard,
## gardenRush): Hügelketten am Horizont, Schmetterlings- und Fischschwärme,
## Gewächshaus, Ring-Puls-Effekte und die HUD-Milchglasplatte. Alles sind
## Massen-Requisiten (MultiMesh, 1 Draw-Call je Schwarm) oder wenige Meshes,
## damit das Draw-Call-Budget (≤250) hält. Reine Fabrik ohne eigenen Zustand —
## Animationen laufen über animate_*/tick_* mit dem Puls der Bühne und
## pausieren so mit dem Spiel.

const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")
const Models := preload("res://scripts/minigames/games/_3dc_stage/models3d.gd")

const MPB_DIR := "res://assets/minigames/carrot_catch/mpb/"
## Ring-Puls: Lebensdauer und Ausdehnung (Welteinheiten pro Sekunde).
const PULSE_LIFE := 0.45


## Sanfte Hügelkette am Horizont: flachgedrückte Kugeln in EINEM MultiMesh.
## `entries` = [[x, z, breite, höhe], …]; Fog macht die Staffelung weich.
static func hills(entries: Array, color: Color) -> MultiMeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 1.0
	mesh.height = 2.0
	mesh.radial_segments = 24
	mesh.rings = 12
	mesh.material = Fx.flat(color)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = entries.size()
	for i in entries.size():
		var e: Array = entries[i]
		var basis := Basis.IDENTITY.scaled(Vector3(float(e[2]), float(e[3]), float(e[2]) * 0.7))
		mm.set_instance_transform(i, Transform3D(basis, Vector3(float(e[0]), 0.0, float(e[1]))))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.extra_cull_margin = 60.0
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mmi


## Schmetterlingsschwarm: je Falter zwei Flügel-Quads im selben MultiMesh
## (1 Draw-Call). `centers` sind die Blüten, um die die Falter kreisen.
## Bewegung + Flattern macht animate_butterflies mit dem Bühnen-Puls.
static func butterflies(centers: Array, color: Color, wing := 0.2) -> MultiMeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = Vector2(wing, wing * 0.72)
	var mat := Fx.flat(color)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = quad
	mm.instance_count = centers.size() * 2
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.extra_cull_margin = 30.0
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.set_meta("centers", centers)
	animate_butterflies(mmi, 0.0)
	return mmi


## Flattern + Kreisen um die Blüte (deterministisch aus dem Index, kein RNG).
static func animate_butterflies(mmi: MultiMeshInstance3D, pulse: float) -> void:
	var centers: Array = mmi.get_meta("centers")
	var mm := mmi.multimesh
	for i in centers.size():
		var seed_f := float(i) * 2.39996
		var around := pulse * (0.5 + 0.13 * float(i % 3)) + seed_f
		var center: Vector3 = centers[i]
		var pos := (
			center
			+ Vector3(
				cos(around) * 0.55, 0.85 + sin(pulse * 1.7 + seed_f) * 0.22, sin(around) * 0.4
			)
		)
		var heading := Basis(Vector3.UP, around + PI * 0.5)
		var flap := sin(pulse * 16.0 + seed_f) * 1.0
		for side in 2:
			var sign_f := 1.0 if side == 0 else -1.0
			var wing_rot := heading * Basis(Vector3(1, 0, 0).normalized(), flap * sign_f)
			var basis := wing_rot * Basis.from_euler(Vector3(-PI * 0.5, 0.0, 0.0))
			var offset := wing_rot * Vector3(0.0, 0.0, sign_f * -0.075)
			mm.set_instance_transform(i * 2 + side, Transform3D(basis, pos + offset))


## Fischschwarm fürs Aquarium: gestreckte Kugeln in EINEM MultiMesh, die in
## Bahnen hin- und herschwimmen (animate_fish dreht sie in Schwimmrichtung).
static func fish(count: int, center: Vector3, spread: Vector3, color: Color) -> MultiMeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 12
	mesh.rings = 6
	mesh.material = Fx.flat(color)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.extra_cull_margin = 30.0
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.set_meta("center", center)
	mmi.set_meta("spread", spread)
	animate_fish(mmi, 0.0)
	return mmi


static func animate_fish(mmi: MultiMeshInstance3D, pulse: float) -> void:
	var center: Vector3 = mmi.get_meta("center")
	var spread: Vector3 = mmi.get_meta("spread")
	var mm := mmi.multimesh
	for i in mm.instance_count:
		var seed_f := float(i) * 1.7
		var speed := 0.35 + 0.08 * float(i % 4)
		var t := pulse * speed + seed_f
		var x := sin(t) * spread.x
		var y := sin(t * 1.6 + seed_f) * spread.y
		var z := cos(t * 0.8 + seed_f) * spread.z
		var dx := cos(t) * speed * spread.x
		var yaw := PI * 0.5 if dx >= 0.0 else -PI * 0.5
		var basis := Basis(Vector3.UP, yaw).scaled(Vector3(0.34, 0.13, 0.11))
		mm.set_instance_transform(
			i, Transform3D(basis, center + Vector3(x, y, z) + Vector3(0.0, float(i % 3) * 0.3, 0.0))
		)


## Kleines Pastell-Gewächshaus (weißer Rahmen, Glasdach) — 5 Meshes.
static func greenhouse(width := 3.2, depth := 2.2, height := 2.1) -> Node3D:
	var root := Node3D.new()
	var frame_mat := Fx.flat(Color(0.94, 0.95, 0.92))
	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(width, height * 0.55, depth)
	base_mesh.material = frame_mat
	base.mesh = base_mesh
	base.position.y = height * 0.275
	root.add_child(base)
	var glass := Fx.glass(Color(0.75, 0.92, 0.95, 0.5))
	var wall := MeshInstance3D.new()
	var wall_mesh := BoxMesh.new()
	wall_mesh.size = Vector3(width * 0.92, height * 0.42, depth * 0.92)
	wall_mesh.material = glass
	wall.mesh = wall_mesh
	wall.position.y = height * 0.72
	root.add_child(wall)
	for side: float in [-1.0, 1.0]:
		var roof := MeshInstance3D.new()
		var roof_mesh := BoxMesh.new()
		roof_mesh.size = Vector3(width * 0.58, 0.06, depth * 1.04)
		roof_mesh.material = glass
		roof.mesh = roof_mesh
		roof.position = Vector3(side * width * 0.24, height * 0.98, 0.0)
		roof.rotation.z = -side * 0.5
		root.add_child(roof)
	var door := MeshInstance3D.new()
	var door_mesh := BoxMesh.new()
	door_mesh.size = Vector3(width * 0.26, height * 0.48, 0.05)
	door_mesh.material = Fx.flat(Color(0.68, 0.5, 0.36))
	door.mesh = door_mesh
	door.position = Vector3(0.0, height * 0.24, depth * 0.51)
	root.add_child(door)
	return root


## Ring-Puls an einer Weltposition starten (Treffer-Echo). Der Aufrufer hält
## die Liste und tickt sie jeden Frame über tick_pulses.
static func spawn_pulse(
	parent: Node3D, pulses: Array, at: Vector3, color: Color, max_r := 0.9
) -> void:
	var ring := Fx.ring(0.2, 0.05, color)
	ring.position = at
	ring.rotation.x = PI * 0.5
	parent.add_child(ring)
	pulses.append({"node": ring, "t": 0.0, "max_r": max_r})


## Pulse ausdehnen und ausblenden; abgelaufene Knoten räumen sich selbst weg.
static func tick_pulses(pulses: Array, delta: float) -> void:
	var kept: Array = []
	for entry: Dictionary in pulses:
		var t := float(entry["t"]) + delta
		var ring := entry["node"] as MeshInstance3D
		if t >= PULSE_LIFE or not is_instance_valid(ring):
			if is_instance_valid(ring):
				ring.queue_free()
			continue
		var f := t / PULSE_LIFE
		var scale := 1.0 + f * float(entry["max_r"]) * 6.0
		ring.scale = Vector3.ONE * scale
		ring.transparency = f
		entry["t"] = t
		kept.append(entry)
	pulses.assign(kept)


## Milchglas-Platte hinter HUD-Labels (Lesbarkeit auf Wiese/Wasser/Himmel).
static func hud_plate() -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = Color(1.0, 0.99, 0.94, 0.72)
	box.set_corner_radius_all(16)
	return box


## Requisiten-Knoten aus dem MP-B-Ordner (Kurzform für die Bühnen).
static func prop(file: String, size: float) -> Node3D:
	return Models.node(MPB_DIR + file, size)


## Teile-Liste für Schwärme aus dem MP-B-Ordner.
static func prop_parts(file: String, size: float) -> Array:
	return Models.parts(MPB_DIR + file, size)
