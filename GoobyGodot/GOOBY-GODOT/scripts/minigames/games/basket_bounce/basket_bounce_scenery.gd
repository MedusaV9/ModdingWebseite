extends RefCounted
## Streetball-PLATZ (Agent MP-E, Tiefenpolitur): die Kulisse rund um den
## Asphalt. Vorher endete der Platz in Hecke und Bäumen — jetzt ist er ein
## echter Käfig-Court im Park: Maschendrahtzaun um drei Seiten, Bänke mit
## Zuschauer-Blobs, Parklampen an den Ecken, Ballständer am Abwurf und ein
## paar Schönwetterwolken am Himmel.
##
## Nur Kulisse, keine Mechanik. Massenware über MultiMesh — der ganze Ausbau
## kostet rund 15 Draw-Calls. Die Zuschauer stehen als Rückgabe zur Verfügung,
## damit das Spiel sie beim Korb hüpfen lassen kann.

const Props3D := preload("res://scripts/minigames/games/_3da_stage/props3d.gd")

const ASSETS := "res://assets/minigames/basket_bounce/"

const FENCE_H := 2.5
const FENCE_X := 4.95
const FENCE_FAR_Z := -7.3
const FENCE_NEAR_Z := 6.8
const POST_COLOR := Color(0.5, 0.55, 0.6)
## Pastellfarben der Zuschauer-Blobs (per-Instanz-Farbe, EIN Material).
const CROWD_COLORS := [
	Color(0.95, 0.62, 0.55),
	Color(0.62, 0.78, 0.94),
	Color(0.97, 0.84, 0.5),
	Color(0.72, 0.88, 0.62),
	Color(0.88, 0.68, 0.9),
]


## Baut den Platzausbau; gibt den Zuschauer-Knoten zurück (fürs Mitfiebern).
static func build(stage: Node3D) -> Node3D:
	_fence(stage)
	_lamps(stage)
	_clouds(stage)
	_ball_rack(stage)
	return _benches_and_crowd(stage)


## Maschendrahtzaun um drei Seiten: Pfosten + Handlauf als EIN MultiMesh,
## das „Geflecht" als durchscheinende Scheiben — Käfig-Court-Look für
## drei Draw-Calls.
static func _fence(stage: Node3D) -> void:
	var post_mesh := CylinderMesh.new()
	post_mesh.top_radius = 0.045
	post_mesh.bottom_radius = 0.05
	post_mesh.height = 1.0
	post_mesh.radial_segments = 8
	post_mesh.rings = 1
	post_mesh.material = Props3D.flat(POST_COLOR, 0.55)
	var posts: Array = []
	var rails: Array = []
	var panes: Array = []
	var span_z := FENCE_NEAR_Z - FENCE_FAR_Z
	# Rückseite (hinter dem Korb) + zwei Seiten.
	for i in 6:
		var x := -FENCE_X + 2.0 * FENCE_X * float(i) / 5.0
		posts.append(_upright(Vector3(x, 0.0, FENCE_FAR_Z), FENCE_H))
	for side: float in [-1.0, 1.0]:
		for i in 8:
			var z := FENCE_FAR_Z + span_z * float(i) / 7.0
			posts.append(_upright(Vector3(side * FENCE_X, 0.0, z), FENCE_H))
	# Handläufe oben (liegende „Pfosten" über die volle Länge).
	rails.append(
		Transform3D(
			Basis(Vector3.FORWARD, PI * 0.5) * Basis.from_scale(Vector3(1.0, FENCE_X * 2.0, 1.0)),
			Vector3(0.0, FENCE_H, FENCE_FAR_Z)
		)
	)
	for side: float in [-1.0, 1.0]:
		rails.append(
			Transform3D(
				Basis(Vector3.RIGHT, PI * 0.5) * Basis.from_scale(Vector3(1.0, span_z, 1.0)),
				Vector3(side * FENCE_X, FENCE_H, (FENCE_FAR_Z + FENCE_NEAR_Z) * 0.5)
			)
		)
	var pane_mesh := BoxMesh.new()
	pane_mesh.size = Vector3(1.0, FENCE_H - 0.1, 0.015)
	pane_mesh.material = Props3D.glass(Color(0.78, 0.86, 0.92, 0.2), true)
	panes.append(
		Transform3D(
			Basis.from_scale(Vector3(FENCE_X * 2.0, 1.0, 1.0)),
			Vector3(0.0, FENCE_H * 0.5, FENCE_FAR_Z)
		)
	)
	for side: float in [-1.0, 1.0]:
		panes.append(
			Transform3D(
				Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(Vector3(span_z, 1.0, 1.0)),
				Vector3(side * FENCE_X, FENCE_H * 0.5, (FENCE_FAR_Z + FENCE_NEAR_Z) * 0.5)
			)
		)
	stage.add_child(Props3D.swarm_mesh(post_mesh, posts, 20.0))
	stage.add_child(Props3D.swarm_mesh(post_mesh, rails, 20.0))
	stage.add_child(Props3D.swarm_mesh(pane_mesh, panes, 20.0))


## Pfostenpose: Fuß auf dem Boden, Höhe über die Skalierung.
static func _upright(at: Vector3, height: float) -> Transform3D:
	return Transform3D(
		Basis.from_scale(Vector3(1.0, height, 1.0)), at + Vector3(0.0, height * 0.5, 0.0)
	)


## Parklampen an den hinteren Zaunecken — sie rahmen die Korbanlage ein.
static func _lamps(stage: Node3D) -> void:
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.05
	pole_mesh.bottom_radius = 0.07
	pole_mesh.height = 1.0
	pole_mesh.radial_segments = 8
	pole_mesh.rings = 1
	pole_mesh.material = Props3D.flat(Color(0.38, 0.42, 0.48), 0.6)
	var lamp_mesh := SphereMesh.new()
	lamp_mesh.radius = 0.16
	lamp_mesh.height = 0.32
	lamp_mesh.radial_segments = 10
	lamp_mesh.rings = 5
	lamp_mesh.material = Props3D.glow(Color(1.0, 0.93, 0.75), 1.2)
	var poles: Array = []
	var lamps: Array = []
	for side: float in [-1.0, 1.0]:
		var at := Vector3(side * (FENCE_X + 0.55), 0.0, FENCE_FAR_Z - 0.4)
		poles.append(_upright(at, 3.6))
		lamps.append(Props3D.pose(at + Vector3(0.0, 3.72, 0.0)))
	stage.add_child(Props3D.swarm_mesh(pole_mesh, poles, 20.0))
	stage.add_child(Props3D.swarm_mesh(lamp_mesh, lamps, 20.0))


## Schönwetterwolken: drei Puffball-Wolken aus Kugeln in EINEM MultiMesh —
## der Himmel über dem Korb ist sonst ein leeres Viertel des Hochformats.
static func _clouds(stage: Node3D) -> void:
	var puff := SphereMesh.new()
	puff.radius = 1.0
	puff.height = 1.6
	puff.radial_segments = 10
	puff.rings = 5
	var mat := Props3D.flat(Color(0.99, 0.99, 1.0), 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff.material = mat
	var poses: Array = []
	var clusters := [
		{"at": Vector3(-9.0, 11.5, -30.0), "s": 2.2},
		{"at": Vector3(7.0, 13.5, -36.0), "s": 2.9},
		{"at": Vector3(16.0, 10.5, -26.0), "s": 1.8},
	]
	for cluster: Dictionary in clusters:
		var at: Vector3 = cluster["at"]
		var s := float(cluster["s"])
		poses.append(Props3D.pose(at, 0.0, s))
		poses.append(Props3D.pose(at + Vector3(s * 1.15, -0.2 * s, 0.4), 0.0, s * 0.72))
		poses.append(Props3D.pose(at + Vector3(-s * 1.05, -0.25 * s, -0.3), 0.0, s * 0.6))
	stage.add_child(Props3D.swarm_mesh(puff, poses, 60.0))


## Ballständer am Abwurfpunkt: zwei Ersatzbälle warten schon — erzählt
## „hier wird geworfen" und füllt den unteren Bildrand.
static func _ball_rack(stage: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "BallRack"
	holder.position = Vector3(2.35, 0.0, 6.1)
	holder.rotation.y = -0.35
	holder.add_child(
		Props3D.box(
			Vector3(1.1, 0.3, 0.5),
			Props3D.flat(Color(0.58, 0.42, 0.3), 0.9),
			Vector3(0.0, 0.15, 0.0)
		)
	)
	var ball_mesh := SphereMesh.new()
	ball_mesh.radius = 0.22
	ball_mesh.height = 0.44
	ball_mesh.radial_segments = 12
	ball_mesh.rings = 6
	ball_mesh.material = Props3D.flat(Color(0.94, 0.52, 0.19), 0.62)
	var balls: Array = [
		Props3D.pose(Vector3(-0.26, 0.48, 0.0)),
		Props3D.pose(Vector3(0.3, 0.48, 0.02), 0.8, 0.96),
	]
	holder.add_child(Props3D.swarm_mesh(ball_mesh, balls, 10.0))
	stage.add_child(holder)


## Bänke an den Seitenlinien plus Zuschauer-Blobs (Körper + Kopf, je EIN
## MultiMesh mit Instanzfarben). Gibt den Zuschauer-Knoten zurück — das Spiel
## lässt ihn beim Korb mitwippen.
static func _benches_and_crowd(stage: Node3D) -> Node3D:
	var bench_poses: Array = []
	var seats: Array = []
	for side: float in [-1.0, 1.0]:
		for i in 2:
			var z := -3.4 + 4.4 * float(i)
			bench_poses.append(
				Props3D.pose(Vector3(side * 6.3, 0.0, z), PI * 0.5 * side + PI * 0.5, 1.0)
			)
			for k in 3:
				seats.append(Vector3(side * 6.3, 0.52, z - 0.62 + 0.62 * float(k)))
	stage.add_child(
		Props3D.swarm(Props3D.parts(ASSETS + "bench.glb", 0.62, Props3D.NATURE), bench_poses)
	)
	# Stehplätze hinter dem Zaun (Rückseite) — die Kopfreihe hinterm Korb.
	var standing: Array = []
	for i in 7:
		var x := -4.2 + 8.4 * float(i) / 6.0 + 0.3 * sin(float(i) * 2.2)
		standing.append(Vector3(x, 0.62, FENCE_FAR_Z - 0.75))
	var crowd := Node3D.new()
	crowd.name = "Crowd"
	var spots: Array = []
	spots.append_array(seats)
	spots.append_array(standing)
	crowd.add_child(_blob_layer(spots, 0.24, Vector3(1.0, 1.15, 0.92), 0.0))
	crowd.add_child(_blob_layer(spots, 0.15, Vector3(0.95, 0.9, 0.95), 0.3))
	stage.add_child(crowd)
	return crowd


## Eine Blob-Schicht (Körper ODER Kopf) als MultiMesh mit Instanzfarben.
static func _blob_layer(
	spots: Array, radius: float, squash: Vector3, lift: float
) -> MultiMeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 10
	mesh.rings = 5
	var mat := Props3D.flat(Color.WHITE, 0.9)
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = spots.size()
	for i in spots.size():
		var at: Vector3 = spots[i] as Vector3 + Vector3(0.0, lift, 0.0)
		mm.set_instance_transform(
			i, Transform3D(Basis.from_scale(squash * (0.9 + 0.2 * float(i % 3) * 0.5)), at)
		)
		mm.set_instance_color(i, CROWD_COLORS[i % CROWD_COLORS.size()])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.extra_cull_margin = 20.0
	return mmi
