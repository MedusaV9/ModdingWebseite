extends RefCounted
## BOLZPLATZ (Agent MP-E, Tiefenpolitur): die Kulisse rund um das Tor. Vorher
## stand das Tor allein auf einer Wiese vor Baumkranz — jetzt ist es ein
## Vereinsgelände: Vereinsheim mit warm beleuchteten Fenstern, zwei
## Flutlichtmasten, eine rot-weiße Bande, Zuschauer-Blobs, Eckfahnen und
## Trainingshütchen.
##
## Nur Kulisse, keine Mechanik. Massenware über MultiMesh — der ganze Ausbau
## kostet rund 18 Draw-Calls. Die Zuschauer werden zurückgegeben, damit das
## Spiel sie bei Paraden hüpfen lassen kann.
##
## W17/G4 (NUR Präsentation): der Park-Kranz (Hecke + Bäume) ist aus
## goalie_gooby.gd hierher gezogen (Zeilen-Luft), dazu der Intro-Kameraflug
## Vereinsheim→Tor (M1) und das Ziel-Banner mit Telegraph-Legende (M4/M7).

const Props3D := preload("res://scripts/minigames/games/_3da_stage/props3d.gd")

const ASSETS := "res://assets/minigames/goalie_gooby/"

const HEIM_WOOD := Color(0.78, 0.6, 0.42)
const HEIM_ROOF := Color(0.62, 0.36, 0.32)
## Telegraph-Farben der Schussarten — Intro-Legende (M4) und Bahn-Leuchtfeld
## im Spiel müssen dieselbe Sprache sprechen (goalie_gooby._tick_telegraph).
const LOB_TINT := Color(0.55, 0.85, 1.0)
const ROLLER_TINT := Color(1.0, 0.6, 0.85)
## Pastellfarben der Zuschauer-Blobs (per-Instanz-Farbe, EIN Material).
const CROWD_COLORS := [
	Color(0.95, 0.62, 0.55),
	Color(0.62, 0.78, 0.94),
	Color(0.97, 0.84, 0.5),
	Color(0.72, 0.88, 0.62),
	Color(0.88, 0.68, 0.9),
]


## Baut Rasenbahnen + Park-Kranz + Vereinsgelände; gibt die Zuschauer zurück.
## `spot_z` ist der Elfmeterpunkt — hinter ihm (Kameraseite) bleibt es leer;
## `grass` ist die Wiesenfarbe des Spiels (Bahnen sind daraus abgedunkelt).
static func build(stage: Node3D, spot_z: float, grass: Color) -> Node3D:
	_stripes(stage, grass)
	_park(stage, spot_z)
	_clubhouse(stage)
	_floodlights(stage)
	_barrier(stage)
	_corner_flags(stage)
	_cones(stage)
	return _crowd(stage)


## Gemähte Rasenbahnen quer zum Schuss — sie geben der leeren Wiese Tiefe.
## Flache PLATTEN, keine Quader: die 2 cm hohen Seitenflächen eines Quaders
## lesen sich aus flachem Blickwinkel als dunkle Scanlines über die Wiese.
static func _stripes(stage: Node3D, grass: Color) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(64.0, 3.2)
	mesh.material = Props3D.flat(grass.darkened(0.13))
	var poses: Array = []
	for i in 10:
		poses.append(Props3D.pose(Vector3(0.0, 0.004, 6.4 - float(i) * 6.4)))
	stage.add_child(Props3D.swarm_mesh(mesh, poses, 40.0))


## Bolzplatz im Park: Hecke hinter dem Tor, Bäume dahinter, Büsche und
## Blumen an den Seiten (1:1 aus goalie_gooby._build_park gezogen — dieselben
## deterministischen Streu-Aufrufe, also exakt dieselbe Kulisse).
static func _park(stage: Node3D, spot_z: float) -> void:
	var behind := func(at: Vector3) -> bool: return at.z > spot_z + 1.0

	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.4, 1.0, 1.0)
	mesh.material = Props3D.flat(Color(0.29, 0.53, 0.31))
	var poses: Array = []
	for i in 26:
		var a := TAU * float(i) / 26.0
		var at := Vector3(sin(a) * 15.0, 0.45, cos(a) * 15.0)
		if at.z > spot_z + 1.0:
			continue
		poses.append(Props3D.pose(at, -a, 1.0 + 0.08 * sin(float(i) * 2.1)))
	stage.add_child(Props3D.swarm_mesh(mesh, poses, 34.0))

	stage.add_child(
		Props3D.scatter(ASSETS + "tree_oak.glb", 4.1, 10, 17.0, Vector3.ZERO, 1.6, 1.0, behind)
	)
	stage.add_child(
		Props3D.scatter(ASSETS + "tree_fat.glb", 3.5, 8, 18.4, Vector3.ZERO, 1.7, 1.9, behind)
	)
	stage.add_child(
		Props3D.scatter(
			ASSETS + "tree_pineRoundA.glb", 4.6, 7, 19.6, Vector3.ZERO, 1.8, 2.6, behind
		)
	)
	stage.add_child(
		Props3D.scatter(
			ASSETS + "plant_bushLarge.glb", 0.85, 12, 13.2, Vector3.ZERO, 1.0, 0.5, behind
		)
	)
	stage.add_child(
		Props3D.scatter(ASSETS + "grass_large.glb", 0.36, 20, 11.4, Vector3.ZERO, 1.8, 3.1, behind)
	)
	stage.add_child(
		Props3D.scatter(
			ASSETS + "flower_yellowA.glb", 0.3, 12, 12.4, Vector3.ZERO, 1.2, 2.2, behind
		)
	)
	stage.add_child(
		Props3D.scatter(ASSETS + "flower_redA.glb", 0.32, 12, 13.9, Vector3.ZERO, 1.1, 3.8, behind)
	)


## Vereinsheim links hinter dem Tor: Holzhütte mit Vordach, warm leuchtenden
## Fenstern und Wimpelkette — das soziale Zentrum des Platzes.
static func _clubhouse(stage: Node3D) -> void:
	var holder := Node3D.new()
	holder.name = "Clubhouse"
	holder.position = Vector3(-8.6, 0.0, -5.2)
	holder.rotation.y = 0.55
	var wall := Props3D.flat(HEIM_WOOD, 0.9)
	holder.add_child(Props3D.box(Vector3(4.6, 2.0, 2.6), wall, Vector3(0.0, 1.0, 0.0)))
	holder.add_child(
		Props3D.box(Vector3(5.2, 0.18, 3.4), Props3D.flat(HEIM_ROOF, 0.85), Vector3(0.0, 2.16, 0.2))
	)
	holder.add_child(
		Props3D.box(
			Vector3(5.2, 0.16, 1.4),
			Props3D.flat(HEIM_ROOF.lightened(0.15), 0.85),
			Vector3(0.0, 2.36, -0.9)
		)
	)
	var door := Props3D.box(
		Vector3(0.7, 1.4, 0.06), Props3D.flat(Color(0.5, 0.36, 0.28), 0.9), Vector3(-1.5, 0.7, 1.33)
	)
	holder.add_child(door)
	var window_mesh := BoxMesh.new()
	window_mesh.size = Vector3(0.85, 0.65, 0.06)
	window_mesh.material = Props3D.glow(Color(1.0, 0.88, 0.6), 0.9)
	var windows: Array = [
		Props3D.pose(Vector3(-0.2, 1.15, 1.33)),
		Props3D.pose(Vector3(1.15, 1.15, 1.33)),
	]
	holder.add_child(Props3D.swarm_mesh(window_mesh, windows, 10.0))
	# Wimpelkette überm Eingang: kleine bunte Dreiecke (Instanzfarben).
	holder.add_child(_pennants(Vector3(-2.2, 1.95, 1.42), Vector3(2.4, 1.95, 1.42)))
	stage.add_child(holder)


## Wimpelkette zwischen zwei Punkten (EIN MultiMesh, Instanzfarben).
static func _pennants(from: Vector3, to: Vector3) -> MultiMeshInstance3D:
	var mesh := PrismMesh.new()
	mesh.size = Vector3(0.16, 0.22, 0.02)
	var mat := Props3D.flat(Color.WHITE, 0.8)
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	var count := 7
	mm.instance_count = count
	for i in count:
		var f := float(i + 1) / float(count + 1)
		var at := from.lerp(to, f)
		at.y -= sin(f * PI) * 0.22 + 0.11
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.RIGHT, PI), at))
		mm.set_instance_color(i, CROWD_COLORS[i % CROWD_COLORS.size()])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.extra_cull_margin = 10.0
	return mmi


## Zwei Flutlichtmasten hinter den Torecken: Mast + Querbalken + vier
## Leuchtpaneele, die als heller Glow-Block über dem Platz stehen.
static func _floodlights(stage: Node3D) -> void:
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.07
	pole_mesh.bottom_radius = 0.1
	pole_mesh.height = 1.0
	pole_mesh.radial_segments = 8
	pole_mesh.rings = 1
	pole_mesh.material = Props3D.flat(Color(0.44, 0.48, 0.54), 0.6)
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3(0.34, 0.26, 0.1)
	panel_mesh.material = Props3D.glow(Color(1.0, 0.97, 0.85), 1.5)
	var poles: Array = []
	var panels: Array = []
	var bars: Array = []
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(1.7, 0.1, 0.1)
	bar_mesh.material = pole_mesh.material
	for side: float in [-1.0, 1.0]:
		var at := Vector3(side * 10.5, 0.0, -3.6)
		var height := 6.2
		poles.append(
			Transform3D(
				Basis.from_scale(Vector3(1.0, height, 1.0)), at + Vector3(0.0, height * 0.5, 0.0)
			)
		)
		bars.append(Props3D.pose(at + Vector3(0.0, height + 0.1, 0.0)))
		for k in 4:
			var x := -0.6 + 0.4 * float(k)
			panels.append(
				Transform3D(Basis(Vector3.RIGHT, -0.35), at + Vector3(x, height + 0.36, 0.06))
			)
	stage.add_child(Props3D.swarm_mesh(pole_mesh, poles, 30.0))
	stage.add_child(Props3D.swarm_mesh(bar_mesh, bars, 30.0))
	stage.add_child(Props3D.swarm_mesh(panel_mesh, panels, 30.0))


## Rot-weiße Bande um den Platz (Instanzfarben, EIN MultiMesh) — die typische
## Bolzplatz-Begrenzung, ersetzt die leere Wiesenkante.
static func _barrier(stage: Node3D) -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.9, 0.5, 0.09)
	var mat := Props3D.flat(Color.WHITE, 0.85)
	mat.vertex_color_use_as_albedo = true
	mesh.material = mat
	var slots: Array = []
	for i in 9:
		var x := -8.0 + 2.0 * float(i)
		slots.append({"at": Vector3(x, 0.25, -4.6), "yaw": 0.0})
	for side: float in [-1.0, 1.0]:
		for i in 7:
			var z := -3.5 + 2.0 * float(i)
			slots.append({"at": Vector3(side * 9.2, 0.25, z), "yaw": PI * 0.5})
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = mesh
	mm.instance_count = slots.size()
	for i in slots.size():
		var slot: Dictionary = slots[i]
		mm.set_instance_transform(
			i, Transform3D(Basis(Vector3.UP, float(slot["yaw"])), slot["at"] as Vector3)
		)
		mm.set_instance_color(i, Color(0.92, 0.4, 0.38) if i % 2 == 0 else Color(0.98, 0.97, 0.94))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.extra_cull_margin = 30.0
	mmi.name = "Barrier"
	stage.add_child(mmi)


## Eckfahnen an der Grundlinie — Maßstab und Farbtupfer.
static func _corner_flags(stage: Node3D) -> void:
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.02
	pole_mesh.bottom_radius = 0.025
	pole_mesh.height = 1.5
	pole_mesh.radial_segments = 6
	pole_mesh.rings = 1
	pole_mesh.material = Props3D.flat(Color(0.95, 0.95, 0.9), 0.6)
	var flag_mesh := PrismMesh.new()
	flag_mesh.size = Vector3(0.34, 0.22, 0.02)
	var flag_mat := Props3D.flat(Color(0.95, 0.5, 0.3), 0.7)
	flag_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	flag_mesh.material = flag_mat
	var poles: Array = []
	var flags: Array = []
	for side: float in [-1.0, 1.0]:
		var at := Vector3(side * 8.6, 0.0, -0.2)
		poles.append(Props3D.pose(at + Vector3(0.0, 0.75, 0.0)))
		flags.append(
			Transform3D(
				Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, PI * 0.5),
				at + Vector3(side * 0.02, 1.38, 0.17)
			)
		)
	stage.add_child(Props3D.swarm_mesh(pole_mesh, poles, 20.0))
	stage.add_child(Props3D.swarm_mesh(flag_mesh, flags, 20.0))


## Trainingshütchen neben dem Strafraum — hier wird sonst trainiert.
static func _cones(stage: Node3D) -> void:
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 0.14
	cone.height = 0.26
	cone.radial_segments = 8
	cone.rings = 1
	cone.material = Props3D.flat(Color(0.97, 0.6, 0.25), 0.8)
	var poses: Array = []
	for i in 4:
		poses.append(
			Props3D.pose(Vector3(6.4 + 0.5 * sin(float(i) * 2.0), 0.13, 3.2 + float(i) * 0.9))
		)
	stage.add_child(Props3D.swarm_mesh(cone, poses, 20.0))


## Zuschauer-Blobs hinter der Bande (Körper + Kopf, Instanzfarben).
static func _crowd(stage: Node3D) -> Node3D:
	var crowd := Node3D.new()
	crowd.name = "Crowd"
	var spots: Array = []
	for i in 8:
		var x := -7.2 + 14.4 * float(i) / 7.0 + 0.4 * sin(float(i) * 2.7)
		spots.append(Vector3(x, 0.6, -5.35))
	for side: float in [-1.0, 1.0]:
		for i in 3:
			spots.append(Vector3(side * 9.9, 0.6, 0.4 + 2.2 * float(i)))
	crowd.add_child(_blob_layer(spots, 0.26, Vector3(1.0, 1.15, 0.92), 0.0))
	crowd.add_child(_blob_layer(spots, 0.16, Vector3(0.95, 0.9, 0.95), 0.33))
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
			i, Transform3D(Basis.from_scale(squash * (0.9 + 0.1 * float(i % 3))), at)
		)
		mm.set_instance_color(i, CROWD_COLORS[i % CROWD_COLORS.size()])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.extra_cull_margin = 24.0
	return mmi


## Intro-Kameraflug (M1): t 0..1. Die Start-Pose blickt aufs warm beleuchtete
## Vereinsheim (mit Flutlichtmast im Anschnitt), dann schwenkt die Fahrt
## geglättet über den Platz in die fit()-Spielpose `play` — mit kleinem
## Höhenbogen, damit der Flug nach Kran statt nach Schiene aussieht.
static func intro_cam(t: float, play: Transform3D) -> Dictionary:
	var eased := smoothstep(0.0, 1.0, clampf(t, 0.0, 1.0))
	var from := Vector3(-3.4, 2.2, 3.0)
	var look := Vector3(-8.6, 1.2, -5.2)
	var play_look := play.origin - play.basis.z * 12.0
	var at := from.lerp(play.origin, eased)
	at.y += sin(eased * PI) * 0.8
	return {"from": at, "look": look.lerp(play_look, eased)}


## Ziel-Banner des Intro-Beats (M1/M7): Titel + Legende auf dunkler Plate mit
## Kontur (Stil des Trefferbands). `legend` = [[Farbe, Text], …] — je Zeile
## ein Farbpunkt in exakt der Telegraph-Farbe, die das Leuchtfeld später
## in die angesagte Bahn legt (M4). Alle Maße skalieren mit `ui` (M9).
static func draw_intro_banner(
	g: CanvasItem, view: Vector2, ui: float, alpha: float, title: String, legend: Array
) -> void:
	var font := ThemeService.font(800)
	var title_px := int(24.0 * ui)
	var line_px := int(15.0 * ui)
	var dot_r := 6.0 * ui
	var gap := 8.0 * ui
	var line_h := font.get_height(line_px) + 4.0 * ui
	var w := font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, title_px).x
	for entry: Array in legend:
		var lw := font.get_string_size(str(entry[1]), HORIZONTAL_ALIGNMENT_CENTER, -1, line_px).x
		w = maxf(w, lw + dot_r * 2.0 + gap)
	w = minf(w, view.x * 0.92)
	var h := font.get_height(title_px) + 6.0 * ui + line_h * float(legend.size())
	var pad := Vector2(18.0, 12.0) * ui
	var top := view.y * 0.18
	var plate := StyleBoxFlat.new()
	plate.bg_color = Color(0.1, 0.18, 0.12, 0.62 * alpha)
	plate.set_corner_radius_all(int(14.0 * ui))
	g.draw_style_box(
		plate, Rect2(Vector2((view.x - w) * 0.5, top) - pad, Vector2(w, h) + pad * 2.0)
	)
	var ink := Color(1.0, 0.97, 0.88, alpha)
	var rim := Color(0.08, 0.16, 0.1, 0.9 * alpha)
	var at := Vector2((view.x - w) * 0.5, top + font.get_ascent(title_px))
	g.draw_string_outline(
		font, at, title, HORIZONTAL_ALIGNMENT_CENTER, w, title_px, int(5.0 * ui), rim
	)
	g.draw_string(font, at, title, HORIZONTAL_ALIGNMENT_CENTER, w, title_px, ink)
	var y := top + font.get_height(title_px) + 6.0 * ui
	for entry: Array in legend:
		var text := str(entry[1])
		var lw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, line_px).x
		var x := (view.x - lw - dot_r * 2.0 - gap) * 0.5
		g.draw_circle(
			Vector2(x + dot_r, y + font.get_height(line_px) * 0.5),
			dot_r,
			Color(entry[0] as Color, alpha)
		)
		var base := Vector2(x + dot_r * 2.0 + gap, y + font.get_ascent(line_px))
		g.draw_string_outline(
			font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, line_px, int(4.0 * ui), rim
		)
		g.draw_string(font, base, text, HORIZONTAL_ALIGNMENT_LEFT, -1, line_px, ink)
		y += line_h
