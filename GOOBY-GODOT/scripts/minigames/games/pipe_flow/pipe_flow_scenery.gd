extends RefCounted
## Statische Gärtnerei-Kulisse des Rohr-Wirrwarrs (MP-D-Tiefenpolitur):
## Tiefenstaffelung hinter dem Blaupausen-Panel — Wiese, Beethecke, Zaun- und
## Baumreihe, ferne Hügelkette, treibende Wolken und ein warmer Sonnenfleck.
## Alles Massenware läuft über Models.swarm (1 Draw-Call je Teilmesh), damit
## die Kulisse das Budget SENKT statt hebt. Wird einmal von
## PipeFlowStage3D gebaut und danach nur noch über `drift()` leicht bewegt.

const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")
const Models := preload("res://scripts/minigames/games/_3dc_stage/models3d.gd")
const NATURE := "res://assets/minigames/carrot_catch/"
const POND := "res://assets/minigames/fishing_pond/"
const OWN := "res://assets/minigames/pipe_flow/"

## Wolkenband (MultiMesh) — drift() schiebt es langsam seitwärts.
static var _clouds: MultiMeshInstance3D


## Gesamte Kulisse unter `stage` hängen. `bed_wy` interessiert hier nicht —
## die Kulisse liegt komplett hinter der Panel-Ebene (z < 0).
static func build(stage: Node3D) -> void:
	_lawn(stage)
	_hills(stage)
	_sun(stage)
	_clouds_band(stage)
	_green_rows(stage)


## Wiese in zwei Tönen: sattes Vordergrund-Grün + hellerer Saum nach hinten.
static func _lawn(stage: Node3D) -> void:
	var lawn := Fx.ground(Vector2(90.0, 60.0), Color(0.52, 0.72, 0.4))
	lawn.position = Vector3(0.0, -4.7, -12.0)
	stage.add_child(lawn)
	var seam := Fx.ground(Vector2(90.0, 14.0), Color(0.62, 0.79, 0.47))
	seam.position = Vector3(0.0, -4.66, -26.0)
	stage.add_child(seam)


## Ferne Hügelkette: flachgedrückte Kugeln, die im Hochformat über die
## Panel-Oberkante lugen — der Horizont bekommt eine Silhouette.
static func _hills(stage: Node3D) -> void:
	var hill := SphereMesh.new()
	hill.radius = 16.0
	hill.height = 32.0
	hill.radial_segments = 24
	hill.rings = 12
	hill.material = Fx.flat(Color(0.56, 0.74, 0.55))
	var poses: Array = [
		Transform3D(Basis.IDENTITY.scaled(Vector3(1.5, 1.0, 0.6)), Vector3(-16.0, -6.0, -34.0)),
		Transform3D(Basis.IDENTITY.scaled(Vector3(1.2, 0.82, 0.6)), Vector3(10.0, -5.0, -35.0)),
		Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, 1.16, 0.6)), Vector3(-1.0, -7.5, -36.0)),
	]
	var swarm := Models.swarm([{"mesh": hill, "xform": Transform3D.IDENTITY}], poses, 60.0)
	_no_shadow(swarm)
	stage.add_child(swarm)


## Warmer Sonnenfleck hoch am Himmel (weiches Glühen, kein hartes Licht).
static func _sun(stage: Node3D) -> void:
	var disc := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 2.2
	mesh.height = 4.4
	mesh.radial_segments = 16
	mesh.rings = 8
	mesh.material = Fx.glow(Color(1.0, 0.92, 0.7), 1.6)
	disc.mesh = mesh
	disc.position = Vector3(9.0, 15.0, -38.0)
	disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(disc)


## Treibende Schäfchenwolken als EIN MultiMesh (drift() bewegt den Knoten).
static func _clouds_band(stage: Node3D) -> void:
	var puff := SphereMesh.new()
	puff.radius = 1.0
	puff.height = 2.0
	puff.radial_segments = 12
	puff.rings = 6
	puff.material = Fx.flat(Color(0.99, 0.99, 1.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4711
	var poses: Array = []
	for i in 7:
		var cx := -20.0 + float(i) * 6.5
		var cy := rng.randf_range(9.0, 16.0)
		for p in 3:
			var b := Basis.IDENTITY.scaled(
				Vector3(rng.randf_range(1.6, 2.6), rng.randf_range(0.7, 1.0), 1.0)
			)
			poses.append(Transform3D(b, Vector3(cx + float(p - 1) * 1.7, cy, -32.0)))
	_clouds = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = puff
	mm.instance_count = poses.size()
	for i in poses.size():
		mm.set_instance_transform(i, poses[i])
	_clouds.multimesh = mm
	_clouds.extra_cull_margin = 60.0
	_clouds.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(_clouds)


## Grünstaffel hinter dem Panel: Hecke, Zaun, zwei Baumreihen — im Querformat
## füllen sie die Seiten, im Hochformat tragen sie den Horizontstreifen.
static func _green_rows(stage: Node3D) -> void:
	var fence_poses: Array = []
	for i in 16:
		fence_poses.append(
			Transform3D(Basis.IDENTITY, Vector3(-13.5 + float(i) * 1.8, -4.65, -9.0))
		)
	stage.add_child(Models.swarm(Models.parts(NATURE + "fence_simple.glb", 1.8), fence_poses))
	var hedge_poses: Array = []
	for i in 9:
		hedge_poses.append(
			Transform3D(
				Basis(Vector3.UP, float(i) * 0.9), Vector3(-12.0 + float(i) * 3.0, -4.65, -10.5)
			)
		)
	stage.add_child(Models.swarm(Models.parts(POND + "plant_bushLarge.glb", 1.7), hedge_poses))
	var near_trees: Array = []
	for i in 5:
		near_trees.append(
			Transform3D(
				Basis(Vector3.UP, float(i) * 1.4),
				Vector3(-12.0 + float(i) * 6.0, -4.65, -13.0 - 2.0 * float(i % 2))
			)
		)
	stage.add_child(Models.swarm(Models.parts(NATURE + "tree_default.glb", 4.4), near_trees))
	var far_trees: Array = []
	for i in 6:
		far_trees.append(
			Transform3D(
				Basis(Vector3.UP, float(i) * 0.8),
				Vector3(-15.0 + float(i) * 6.0, -4.65, -20.0 - 3.0 * float(i % 3))
			)
		)
	stage.add_child(Models.swarm(Models.parts(POND + "tree_fat.glb", 5.2), far_trees))


## Requisiten der unteren Beet-Zeile: Grasbüschel, Steine, ein Pilz — kommt
## als fertiger Knoten zurück, das Spiel legt ihn auf die Beethöhe.
static func bed_props() -> Node3D:
	var holder := Node3D.new()
	var grass_poses: Array = []
	for i in 6:
		grass_poses.append(
			Transform3D(
				Basis(Vector3.UP, float(i) * 1.1),
				Vector3(-2.4 + float(i) * 0.96, 0.0, 0.55 + 0.25 * float(i % 2))
			)
		)
	holder.add_child(Models.swarm(Models.parts(POND + "grass_large.glb", 0.5), grass_poses))
	var rock_poses: Array = [
		Transform3D(Basis(Vector3.UP, 0.6), Vector3(-2.6, 0.0, 0.9)),
		Transform3D(Basis(Vector3.UP, 2.1), Vector3(2.5, 0.0, 0.8)),
	]
	holder.add_child(Models.swarm(Models.parts(POND + "rock_smallA.glb", 0.34), rock_poses))
	var shroom := Models.node(POND + "mushroom_red.glb", 0.3)
	shroom.position = Vector3(-1.7, 0.0, 1.0)
	holder.add_child(shroom)
	return holder


## Blumentöpfe fürs Werkbank-Bord über dem Panel (lugen in den Himmel).
static func shelf_props() -> Node3D:
	var holder := Node3D.new()
	var pot_a := Models.node(OWN + "pot_large.glb", 0.42)
	pot_a.position = Vector3(-0.62, 0.0, 0.0)
	holder.add_child(pot_a)
	var bloom_a := Models.node(NATURE + "flower_redA.glb", 0.4)
	bloom_a.position = Vector3(-0.62, 0.26, 0.0)
	holder.add_child(bloom_a)
	var pot_b := Models.node(OWN + "pot_small.glb", 0.3)
	pot_b.position = Vector3(0.55, 0.0, 0.05)
	holder.add_child(pot_b)
	var bloom_b := Models.node(NATURE + "flower_yellowA.glb", 0.36)
	bloom_b.position = Vector3(0.55, 0.18, 0.05)
	holder.add_child(bloom_b)
	return holder


## Goobys Werkzeug: kleiner Schraubenschlüssel für die rechte Pfote.
static func wrench() -> Node3D:
	var holder := Node3D.new()
	var steel := Fx.flat(Color(0.78, 0.8, 0.86), 0.4)
	var grip := MeshInstance3D.new()
	var grip_mesh := CylinderMesh.new()
	grip_mesh.top_radius = 0.035
	grip_mesh.bottom_radius = 0.035
	grip_mesh.height = 0.34
	grip_mesh.radial_segments = 8
	grip_mesh.material = steel
	grip.mesh = grip_mesh
	holder.add_child(grip)
	var jaw := MeshInstance3D.new()
	var jaw_mesh := TorusMesh.new()
	jaw_mesh.inner_radius = 0.045
	jaw_mesh.outer_radius = 0.085
	jaw_mesh.rings = 12
	jaw_mesh.ring_segments = 6
	jaw_mesh.material = steel
	jaw.mesh = jaw_mesh
	jaw.position.y = 0.2
	holder.add_child(jaw)
	return holder


## Hocker, auf dem Gooby neben dem Beet sitzt.
static func stool() -> Node3D:
	var holder := Node3D.new()
	var wood := Fx.flat(Color(0.72, 0.53, 0.36))
	var seat := MeshInstance3D.new()
	var seat_mesh := CylinderMesh.new()
	seat_mesh.top_radius = 0.3
	seat_mesh.bottom_radius = 0.3
	seat_mesh.height = 0.08
	seat_mesh.radial_segments = 12
	seat_mesh.material = wood
	seat.mesh = seat_mesh
	seat.position.y = 0.36
	holder.add_child(seat)
	var leg_mesh := CylinderMesh.new()
	leg_mesh.top_radius = 0.035
	leg_mesh.bottom_radius = 0.045
	leg_mesh.height = 0.36
	leg_mesh.radial_segments = 6
	leg_mesh.material = wood
	for i in 3:
		var leg := MeshInstance3D.new()
		leg.mesh = leg_mesh
		var ang := TAU * float(i) / 3.0
		leg.position = Vector3(cos(ang) * 0.2, 0.18, sin(ang) * 0.2)
		holder.add_child(leg)
	return holder


## Wolken treiben lassen (vom Spiel je Frame getickt).
static func drift(delta: float) -> void:
	if _clouds == null or not is_instance_valid(_clouds):
		return
	_clouds.position.x += delta * 0.25
	if _clouds.position.x > 24.0:
		_clouds.position.x = -24.0


static func _no_shadow(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for child in node.get_children():
		_no_shadow(child)
