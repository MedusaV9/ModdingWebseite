extends RefCounted
## Boss-Fabrik der GvZ-3D-Bühne: baut den EINEN Boss-Müllwagen samt gekröntem
## Zombie-König. Alle MENGEN-Figuren (Türme, Zombies, Mäher, Projektile,
## Drops, Häuser) laufen seit dem Draw-Call-Budget-Pass (Eval C Befund 2)
## als MultiMesh-Instanzen über gvz_stage3d_crowd.gd bzw. den Haus-Schwarm
## in gvz_stage3d.gd — die alten Ein-Knoten-pro-Figur-Fabriken sind bewusst
## GELÖSCHT, damit niemand sie versehentlich wiederbelebt. Der Boss bleibt
## Einzelknoten: es gibt höchstens einen, und seine Qualm-Bälle schalten
## per Sichtbarkeit mit der Boss-Phase.

const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")

const MINT := Color("#C7E2C0")
const STAR_GOLD := Color("#FFD34D")
const INK := Color("#241C18")


## Chibi-Gooby (Kugelkörper, Ohren, Augen), nominell ~1.0 hoch, Blick +z.
## Bewusst NIEDRIG segmentiert (Primitive-Budget) — die Figur ist klein.
static func chibi(body_color: Color, with_eyes := true) -> Node3D:
	var root := Node3D.new()
	var mat := Fx.flat(body_color)
	var body := MeshInstance3D.new()
	var body_mesh := SphereMesh.new()
	body_mesh.radius = 0.34
	body_mesh.height = 0.72
	body_mesh.radial_segments = 24
	body_mesh.rings = 12
	body_mesh.material = mat
	body.mesh = body_mesh
	body.position.y = 0.36
	body.scale = Vector3(1.0, 1.1, 0.92)
	root.add_child(body)
	var ear_mesh := CapsuleMesh.new()
	ear_mesh.radius = 0.085
	ear_mesh.height = 0.4
	ear_mesh.radial_segments = 10
	ear_mesh.rings = 4
	ear_mesh.material = mat
	for side: float in [-1.0, 1.0]:
		var ear := MeshInstance3D.new()
		ear.mesh = ear_mesh
		ear.position = Vector3(side * 0.15, 0.82, -0.02)
		ear.rotation.z = -side * 0.25
		root.add_child(ear)
	if with_eyes:
		var eye_mesh := SphereMesh.new()
		eye_mesh.radius = 0.045
		eye_mesh.height = 0.09
		eye_mesh.radial_segments = 12
		eye_mesh.rings = 6
		eye_mesh.material = Fx.flat(INK)
		for side: float in [-1.0, 1.0]:
			var eye := MeshInstance3D.new()
			eye.mesh = eye_mesh
			eye.position = Vector3(side * 0.12, 0.5, 0.29)
			eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(eye)
	return root


## Boss Knurps: Müllwagen + gekrönter Zombie-König; {node, puffs} — die
## Qualm-Bälle werden mit der Boss-Phase sichtbar.
static func boss() -> Dictionary:
	var root := Node3D.new()
	var truck := MeshInstance3D.new()
	var truck_mesh := BoxMesh.new()
	truck_mesh.size = Vector3(0.7, 0.55, 1.15)
	truck_mesh.material = Fx.flat(Color("#7B8794"))
	truck.mesh = truck_mesh
	truck.position.y = 0.45
	root.add_child(truck)
	var cab := MeshInstance3D.new()
	var cab_mesh := BoxMesh.new()
	cab_mesh.size = Vector3(0.62, 0.3, 0.34)
	cab_mesh.material = Fx.flat(Color("#5A6572"))
	cab.mesh = cab_mesh
	cab.position = Vector3(0.0, 0.55, 0.62)
	root.add_child(cab)
	var wheel_mesh := CylinderMesh.new()
	wheel_mesh.top_radius = 0.16
	wheel_mesh.bottom_radius = 0.16
	wheel_mesh.height = 0.1
	wheel_mesh.radial_segments = 14
	wheel_mesh.material = Fx.flat(Color("#3E3A45"))
	for fz: float in [-0.4, 0.4]:
		for side: float in [-1.0, 1.0]:
			var wheel := MeshInstance3D.new()
			wheel.mesh = wheel_mesh
			wheel.rotation.z = PI * 0.5
			wheel.position = Vector3(side * 0.38, 0.16, fz)
			root.add_child(wheel)
	var king := chibi(MINT)
	king.scale = Vector3.ONE * 0.7
	king.position.y = 0.72
	root.add_child(king)
	var crown := MeshInstance3D.new()
	var crown_mesh := CylinderMesh.new()
	crown_mesh.top_radius = 0.16
	crown_mesh.bottom_radius = 0.12
	crown_mesh.height = 0.12
	crown_mesh.radial_segments = 14
	crown_mesh.material = Fx.glow(STAR_GOLD, 0.7)
	crown.mesh = crown_mesh
	crown.position.y = 0.68
	king.add_child(crown)
	var puffs: Array = []
	var puff_mesh := SphereMesh.new()
	puff_mesh.radius = 0.11
	puff_mesh.height = 0.22
	puff_mesh.radial_segments = 12
	puff_mesh.rings = 6
	puff_mesh.material = Fx.glass(Color(0.4, 0.38, 0.36, 0.5), true)
	for i in 2:
		var puff := MeshInstance3D.new()
		puff.mesh = puff_mesh
		puff.position = Vector3(0.0, 1.0 + 0.14 * float(i), -0.6 - 0.16 * float(i))
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		puff.visible = false
		root.add_child(puff)
		puffs.append(puff)
	return {"node": root, "puffs": puffs}
