extends MinigameBase
## Korbjagd (basketBounce) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## BasketBounceLogic (zahlengleich zum Web): Flick wirft, Ring/Brett prallen
## ab, Korb +3 / Brett +2 / Swish-Serie +2, ab Korb 10 wandert der Ring und
## Swishes zählen doppelt. 60 s (Endlos: bis 3 Fehlwürfe in Folge).
##
## ECHTES 3D (Agent 3D-A, Rückbau): die Logik rechnet ohnehin in Weltmetern
## (Abwurf bei z = 4,6, Ring bei y = 2,6) — die Szene stellt genau diese Meter
## als Streetball-Platz im Park auf: Asphalt mit gemalten Linien, Korbanlage
## mit Mast, Brett, Ring und schwingendem Netz, Hecke und Baumkranz drumherum.
## Gooby steht als ECHTES Rig am Abwurfpunkt, holt beim Flick aus, dreht sich
## beim Treffer zur Kamera und jubelt.
##
## Der MinigameBase-Vertrag bleibt: Wurzel ist Node2D, die 3D-Welt hängt
## darunter (Godot rendert 3D hinter den CanvasItems), Zielhilfe und HUD sind
## CanvasItems obenauf.
##
## Die Steuerung ist unverändert: derselbe Flick, dieselben px/s. Die Kamera
## blickt bewusst achsparallel nach −z, damit „Wisch nach rechts" weiter
## „Ball nach +x" heißt.

const Stage3D := preload("res://scripts/minigames/games/_3da_stage/stage3d.gd")
const Props3D := preload("res://scripts/minigames/games/_3da_stage/props3d.gd")
const GoobyActor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Spark3D := preload("res://scripts/minigames/games/_3da_stage/spark3d.gd")

const ASSETS := "res://assets/minigames/basket_bounce/"

## Flick-Abtastfenster (s) — nur die letzte Bewegung zählt als Wurfimpuls.
const FLICK_SAMPLE_SEC := 0.13
## Punkte der 3D-Flugspur (Weltpunkte, im HUD als Linie gezeichnet).
const TRAIL_MAX := 26

const BALL_COLOR := Color(0.94, 0.52, 0.19)
const SEAM_COLOR := Color(0.45, 0.22, 0.09)
const RIM_COLOR := Color(0.94, 0.35, 0.22)
const COURT := Color(0.8, 0.58, 0.4)
const LINE := Color(0.99, 0.97, 0.93)
const POLE := Color(0.58, 0.6, 0.64)
## Halbe Platzbreite/‑länge in Metern (der Asphalt, nicht die Wiese).
const COURT_HALF_X := 4.2
const COURT_FAR_Z := -6.4
const COURT_NEAR_Z := 10.5

var tune: Dictionary = {}
var rng: GoobyRng
var score := 0
var baskets := 0
var shots := 0
var miss_streak := 0
var swish_streak := 0
var elapsed := 0.0
var slide_elapsed := 0.0
var phase := "aim"
var reset_left := 0.0
var ball: Dictionary = {}
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

var _trail: Array[Vector3] = []
var _samples: Array = []
var _dragging := false
var _drag_from := Vector2.ZERO
var _drag_to := Vector2.ZERO
var _flash := 0.0
var _flash_text := ""
var _time_label: Label
var _streak_label: Label
var _hint_label: Label

var _stage: Stage3D
var _gooby: GoobyActor
var _sparks: Spark3D
var _hoop: Node3D
var _rim: MeshInstance3D
var _net: Node3D
var _ball_node: Node3D
var _ball_shadow: MeshInstance3D
var _net_pulse := 0.0
var _framed_dist := -1.0


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = BasketBounceLogic.apply_difficulty(BasketBounceLogic.BASKET, ctx.difficulty)
	rng = ctx.rng()
	_build_world()
	_build_hud()
	_fit_viewport()
	if is_inside_tree():
		get_viewport().size_changed.connect(_fit_viewport)


func end() -> void:
	super.end()
	finished = true


## Pflicht-Layouthook: beide Orientierungen laufen über DIESE Funktion.
func apply_view(size: Vector2) -> void:
	if size.x > 1.0 and size.y > 1.0:
		view_size = size
	landscape = view_size.x > view_size.y
	position = Vector2.ZERO
	if _stage != null:
		_stage.apply_size(view_size)
		_stage.set_fov(48.0 if landscape else 44.0)
		_framed_dist = -1.0
		_frame_court()
	if _time_label != null:
		_time_label.position = Vector2(16.0, 10.0)
		_streak_label.position = Vector2(16.0, 48.0)
		_hint_label.position = Vector2(view_size.x * 0.5 - 150.0, view_size.y - 56.0)
		_hint_label.size = Vector2(300.0, 40.0)
	queue_redraw()


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	elapsed += delta
	_flash = maxf(0.0, _flash - delta)
	_stage.tick(delta)
	_gooby.tick(delta)
	if BasketBounceLogic.is_moving_hoop(baskets, tune):
		slide_elapsed += delta
	if BasketBounceLogic.is_round_over(elapsed, miss_streak, tune):
		_finish()
		return
	if phase == "fly":
		_step_flight(delta)
	elif phase == "reset":
		reset_left -= delta
		if reset_left <= 0.0:
			phase = "aim"
	_place_hoop()
	_place_ball()
	_tick_net(delta)
	_frame_court()
	_update_labels()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished or phase != "aim":
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_dragging = true
			_drag_from = event.position
			_drag_to = event.position
			_samples = [{"p": event.position, "t": elapsed}]
		elif _dragging:
			_dragging = false
			_launch()
	elif event is InputEventScreenDrag and _dragging:
		_drag_to = event.position
		_samples.append({"p": event.position, "t": elapsed})
		if _samples.size() > 24:
			_samples.pop_front()
		queue_redraw()


## Aktueller Ringmittelpunkt in Weltmetern.
func hoop_now() -> Dictionary:
	var spawn: Dictionary = tune["SPAWN"]
	return {
		"x": BasketBounceLogic.hoop_slide_x(slide_elapsed, baskets, tune),
		"z": float(spawn["z"]) - BasketBounceLogic.hoop_distance(baskets, tune),
	}


# ------------------------------------------------------------------ Aufbau


func _build_world() -> void:
	_stage = Stage3D.new()
	add_child(_stage)
	(
		_stage
		. build(
			{
				"sky_top": Color(0.4, 0.66, 0.96),
				"sky_horizon": Color(0.91, 0.95, 1.0),
				# Boden-Hemisphäre = Nebelfarbe, sonst klebt ein dunkelgrüner
				# Balken dort, wo die Wiese endet.
				"ground_horizon": Color(0.87, 0.92, 0.87),
				"ground_bottom": Color(0.87, 0.92, 0.87),
				"fog_color": Color(0.87, 0.92, 0.87),
				"fog_from": 30.0,
				"fog_to": 84.0,
				"fog_density": 1.0,
				"sun_dir": Vector3(-0.45, -0.82, 0.35),
				"sun_color": Color(1.0, 0.94, 0.82),
				"sun_energy": 1.15,
				"ambient": 0.34,
				"ambient_color": Color(0.93, 0.9, 0.83),
				"sky_ambient": 0.34,
				# Belichtung bewusst niedrig: Sonne + Ambient summieren sich in
				# ACES sonst über den Weißpunkt und der helle Asphalt clippt
				# auf Cremeweiß (der Platz sah aus wie ein leeres Blatt).
				"exposure": 0.56,
				"fill_energy": 0.22,
				"glow": 0.26,
				"shadow_distance": 26.0,
				"fov": 44.0,
			}
		)
	)
	_stage.add_child(
		Props3D.ground(Vector2(220.0, 220.0), Props3D.flat(Color(0.36, 0.6, 0.36)), -0.02)
	)
	_build_court()
	_build_park()
	_build_hoop()

	_ball_node = Node3D.new()
	var radius := float(tune["BALL_R"])
	_ball_node.add_child(Props3D.sphere(radius, Props3D.flat(BALL_COLOR, 0.62)))
	var seam := Props3D.torus(radius * 0.99, 0.012, Props3D.flat(SEAM_COLOR, 0.7))
	_ball_node.add_child(seam)
	var seam2 := Props3D.torus(radius * 0.99, 0.012, Props3D.flat(SEAM_COLOR, 0.7))
	seam2.rotation.x = PI * 0.5
	_ball_node.add_child(seam2)
	_stage.add_child(_ball_node)
	_ball_shadow = Props3D.blob_shadow(radius * 2.0, 0.34)
	_stage.add_child(_ball_shadow)

	_gooby = GoobyActor.new()
	_stage.add_child(_gooby)
	# Seitenansicht statt Rückenansicht: die Kamera steht hinter dem Abwurf,
	# ein zum Korb gedrehter Gooby wäre nur ein cremefarbener Rücken.
	_gooby.mount(1.4, PI * 0.58)
	var spawn: Dictionary = tune["SPAWN"]
	_gooby.position = Vector3(float(spawn["x"]) - 0.78, 0.0, float(spawn["z"]) + 0.34)

	_sparks = Spark3D.new()
	_stage.add_child(_sparks)
	_sparks.build({"color": Color(1.0, 0.86, 0.42), "amount": 26, "speed": Vector2(1.6, 4.0)})


## Asphaltplatz mit gemalten Linien: Grundfläche, Seiten-/Grundlinie,
## Zone, Freiwurfkreis und Drei-Punkte-Bogen. Alle Linien sind flache Quader
## in EINEM MultiMesh — ein Draw-Call für die komplette Bemalung.
func _build_court() -> void:
	var court := Props3D.box(
		Vector3(COURT_HALF_X * 2.0, 0.06, COURT_NEAR_Z - COURT_FAR_Z), Props3D.flat(COURT, 0.95)
	)
	court.position = Vector3(0.0, -0.03, (COURT_NEAR_Z + COURT_FAR_Z) * 0.5)
	_stage.add_child(court)

	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, 0.02, 1.0)
	mesh.material = Props3D.flat(LINE, 0.85)
	var poses: Array = []
	var y := 0.012
	# Seitenlinien + Grundlinie.
	var length := COURT_NEAR_Z - COURT_FAR_Z - 0.6
	var mid_z := (COURT_NEAR_Z + COURT_FAR_Z) * 0.5
	poses.append(_line_pose(Vector3(-COURT_HALF_X + 0.3, y, mid_z), Vector3(0.1, 1.0, length)))
	poses.append(_line_pose(Vector3(COURT_HALF_X - 0.3, y, mid_z), Vector3(0.1, 1.0, length)))
	poses.append(
		_line_pose(Vector3(0.0, y, COURT_FAR_Z + 0.3), Vector3(COURT_HALF_X * 2.0 - 0.6, 1.0, 0.1))
	)
	# Zone unter dem Korb.
	var key_z := COURT_FAR_Z + 0.3
	poses.append(_line_pose(Vector3(-0.92, y, key_z + 2.4), Vector3(0.09, 1.0, 4.8)))
	poses.append(_line_pose(Vector3(0.92, y, key_z + 2.4), Vector3(0.09, 1.0, 4.8)))
	poses.append(_line_pose(Vector3(0.0, y, key_z + 4.8), Vector3(1.84, 1.0, 0.09)))
	# Freiwurfkreis + Drei-Punkte-Bogen als Kreissegmente.
	_arc_poses(poses, Vector3(0.0, y, key_z + 4.8), 1.2, 0.0, TAU, 22)
	_arc_poses(poses, Vector3(0.0, y, key_z + 0.5), 5.0, -0.92, 0.92, 26)
	_stage.add_child(Props3D.swarm_mesh(mesh, poses, 12.0))


## Pose eines Linienquaders (Skalierung steckt in der Basis, damit ein
## einziges Einheits-Mesh alle Linien trägt).
func _line_pose(at: Vector3, size: Vector3) -> Transform3D:
	return Transform3D(Basis.from_scale(size), at)


## Kreisbogen aus kurzen Strichen (Freiwurfkreis, Drei-Punkte-Linie).
func _arc_poses(
	out: Array, center: Vector3, radius: float, from: float, to: float, steps: int
) -> void:
	var span := (to - from) / float(steps)
	var seg := radius * absf(span) * 1.15
	for i in steps:
		var a := from + span * (float(i) + 0.5)
		var at := center + Vector3(sin(a) * radius, 0.0, cos(a) * radius)
		# +PI/2 dreht den Strich auf die TANGENTE — ohne die Vierteldrehung
		# zeigen die Segmente radial nach außen und der Kreis wird zum Stern.
		# Die Skalierung muss RECHTS der Drehung stehen: `Basis.scaled()`
		# streckt entlang der WELT-Achsen und würde die Striche scheren.
		out.append(
			Transform3D(
				Basis(Vector3.UP, a + PI * 0.5) * Basis.from_scale(Vector3(0.09, 1.0, seg)), at
			)
		)


## Parkkulisse: Hecke als Platzbegrenzung, dahinter Bäume, davor Büsche,
## Grasbüschel und Blumen. Die Schneise zur Kamera bleibt frei.
func _build_park() -> void:
	# Was hinter der Kamera stünde, würde im Hochformat als grüne Wand die
	# untere Bildhälfte zumauern — die Schneise bleibt frei.
	var lane := func(at: Vector3) -> bool: return at.z > COURT_NEAR_Z - 1.0

	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.2, 0.95, 0.9)
	mesh.material = Props3D.flat(Color(0.3, 0.54, 0.31))
	var poses: Array = []
	for i in 30:
		var a := TAU * float(i) / 30.0
		var at := Vector3(sin(a) * 12.0, 0.42, cos(a) * 12.0)
		if at.z > COURT_NEAR_Z - 1.0:
			continue
		poses.append(Props3D.pose(at, -a, 1.0 + 0.08 * sin(float(i) * 2.1)))
	_stage.add_child(Props3D.swarm_mesh(mesh, poses, 30.0))
	_stage.add_child(
		Props3D.scatter(ASSETS + "tree_oak.glb", 3.9, 9, 13.6, Vector3.ZERO, 1.4, 1.0, lane)
	)
	_stage.add_child(
		Props3D.scatter(ASSETS + "tree_fat.glb", 3.4, 7, 14.6, Vector3.ZERO, 1.5, 1.7, lane)
	)
	_stage.add_child(
		Props3D.scatter(ASSETS + "tree_pineRoundA.glb", 4.3, 6, 15.4, Vector3.ZERO, 1.6, 2.4, lane)
	)
	_stage.add_child(
		Props3D.scatter(
			ASSETS + "plant_bushLarge.glb", 0.82, 12, 10.4, Vector3.ZERO, 0.9, 0.4, lane
		)
	)
	_stage.add_child(
		Props3D.scatter(ASSETS + "grass_large.glb", 0.34, 22, 8.6, Vector3.ZERO, 1.6, 2.9, lane)
	)
	_stage.add_child(
		Props3D.scatter(ASSETS + "flower_yellowA.glb", 0.3, 12, 9.4, Vector3.ZERO, 1.2, 3.4, lane)
	)
	_stage.add_child(
		Props3D.scatter(ASSETS + "flower_redA.glb", 0.32, 12, 10.9, Vector3.ZERO, 1.1, 1.9, lane)
	)
	var bench := Props3D.model(ASSETS + "bench.glb", 0.66)
	bench.position = Vector3(-6.4, 0.0, 2.6)
	bench.rotation.y = PI * 0.5
	Props3D.repaint(bench, Props3D.NATURE)
	_stage.add_child(bench)


## Korbanlage: Mast, Ausleger, Brett mit Zielrechteck, Ring und Netz.
## Der ganze Block hängt an einem Knoten und wird pro Frame verschoben —
## der Ring wandert ab Korb 10 seitlich.
func _build_hoop() -> void:
	_hoop = Node3D.new()
	_stage.add_child(_hoop)
	var rim_y := float(tune["RIM_Y"])
	var gap := float(tune["BOARD_GAP"])
	var board_bottom := float(tune["BOARD_BOTTOM_Y"])
	var board_w := float(tune["BOARD_W"])
	var board_h := float(tune["BOARD_H"])
	var pole_z := -gap - 0.55

	var pole_mat := Props3D.flat(POLE, 0.5)
	var pole := Props3D.cylinder(0.09, board_bottom + board_h * 0.6, pole_mat)
	pole.position = Vector3(0.0, (board_bottom + board_h * 0.6) * 0.5, pole_z)
	_hoop.add_child(pole)
	var foot := Props3D.cylinder(0.42, 0.14, Props3D.flat(Color(0.5, 0.52, 0.56), 0.7))
	foot.position = Vector3(0.0, 0.07, pole_z)
	_hoop.add_child(foot)
	var arm := Props3D.box(Vector3(0.12, 0.1, 0.62), pole_mat)
	arm.position = Vector3(0.0, board_bottom + 0.42, pole_z * 0.5 - gap * 0.5)
	_hoop.add_child(arm)

	var board := Props3D.box(
		Vector3(board_w, board_h, 0.07), Props3D.flat(Color(0.99, 0.98, 0.95), 0.45)
	)
	board.position = Vector3(0.0, board_bottom + board_h * 0.5, -gap)
	_hoop.add_child(board)
	var frame := Props3D.box(
		Vector3(board_w + 0.1, board_h + 0.1, 0.04), Props3D.flat(Color(0.95, 0.45, 0.66), 0.55)
	)
	frame.position = Vector3(0.0, board_bottom + board_h * 0.5, -gap - 0.045)
	_hoop.add_child(frame)
	for edge: Vector3 in [
		Vector3(0.0, 0.24, 0.0),
		Vector3(0.0, 0.92, 0.0),
		Vector3(-0.3, 0.58, 0.0),
		Vector3(0.3, 0.58, 0.0)
	]:
		var thick := Vector3(0.62, 0.05, 0.02) if edge.x == 0.0 else Vector3(0.05, 0.72, 0.02)
		var bar := Props3D.box(thick, Props3D.flat(Color(0.95, 0.42, 0.6), 0.6))
		bar.position = Vector3(edge.x, board_bottom + edge.y, -gap + 0.05)
		_hoop.add_child(bar)

	_rim = Props3D.torus(
		float(tune["RIM_R"]), float(tune["RIM_TUBE"]), Props3D.glow(RIM_COLOR, 0.6)
	)
	_rim.rotation.x = -PI * 0.5
	_rim.position = Vector3(0.0, rim_y, 0.0)
	_hoop.add_child(_rim)
	var neck := Props3D.box(Vector3(0.12, 0.06, gap), Props3D.flat(RIM_COLOR.darkened(0.2), 0.5))
	neck.position = Vector3(0.0, rim_y, -gap * 0.5)
	_hoop.add_child(neck)
	_build_net(rim_y)


## Netz aus 14 Schnüren in EINEM MultiMesh — beim Treffer schwingt es kurz
## (Skalierung des Knotens), das ist der 3D-Ersatz für den 2D-Netzpuls.
func _build_net(rim_y: float) -> void:
	_net = Node3D.new()
	_net.position = Vector3(0.0, rim_y, 0.0)
	_hoop.add_child(_net)
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.014, 0.46, 0.014)
	mesh.material = Props3D.glass(Color(1.0, 1.0, 1.0, 0.7), true)
	var radius := float(tune["RIM_R"])
	var poses: Array = []
	for i in 14:
		var a := TAU * float(i) / 14.0
		var top := Vector3(sin(a) * radius, 0.0, cos(a) * radius)
		var bottom := Vector3(sin(a) * radius * 0.55, -0.44, cos(a) * radius * 0.55)
		var mid := (top + bottom) * 0.5
		var basis := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, -atan2(radius * 0.45, 0.44))
		poses.append(Transform3D(basis, mid))
	_net.add_child(Props3D.swarm_mesh(mesh, poses, 4.0))


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	_time_label.add_theme_color_override("font_color", Color(1.0, 0.99, 0.95))
	_time_label.add_theme_color_override("font_outline_color", Color(0.24, 0.18, 0.12, 0.8))
	_time_label.add_theme_constant_override("outline_size", 6)
	add_child(_time_label)
	_streak_label = Label.new()
	_streak_label.theme_type_variation = &"CaptionLabel"
	_streak_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.5))
	_streak_label.add_theme_color_override("font_outline_color", Color(0.24, 0.18, 0.12, 0.8))
	_streak_label.add_theme_constant_override("outline_size", 5)
	add_child(_streak_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.basketBounce.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_color_override("font_color", Color(1.0, 0.99, 0.95, 0.95))
	_hint_label.add_theme_color_override("font_outline_color", Color(0.24, 0.18, 0.12, 0.7))
	_hint_label.add_theme_constant_override("outline_size", 5)
	add_child(_hint_label)
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


# ------------------------------------------------------------------ Kamera


## Kamera achsparallel hinter den Abwurfpunkt setzen. Sie zieht nur zurück,
## wenn der Ring weiter weg rückt (jeder Korb schiebt ihn 0,35 m) — sonst
## wackelt das Bild bei jedem Ringschwenk.
func _frame_court() -> void:
	if _stage == null:
		return
	var distance := BasketBounceLogic.hoop_distance(baskets, tune)
	if absf(distance - _framed_dist) < 0.01:
		return
	_framed_dist = distance
	var spawn: Dictionary = tune["SPAWN"]
	var hoop_z := float(spawn["z"]) - distance
	var board_top := float(tune["BOARD_BOTTOM_Y"]) + float(tune["BOARD_H"])
	var points: Array = [
		Vector3(-2.3, 0.0, float(spawn["z"]) + 1.0),
		Vector3(2.3, 0.0, float(spawn["z"]) + 1.0),
		Vector3(-2.2, 0.0, hoop_z - 1.2),
		Vector3(2.2, 0.0, hoop_z - 1.2),
		Vector3(0.0, board_top + 0.5, hoop_z - float(tune["BOARD_GAP"])),
		Vector3(0.0, 3.9, (float(spawn["z"]) + hoop_z) * 0.5),
	]
	var center := Vector3(0.0, 1.7, (float(spawn["z"]) + hoop_z) * 0.5)
	# yaw = 0 stellt die Kamera auf die +z-Seite (hinter den Abwurfpunkt).
	# Damit zeigt Bildschirm-rechts weiter auf Welt-+x — Bedingung dafür, dass
	# der Flick sich exakt wie in der 2D-Fassung anfühlt.
	_stage.fit(points, center, 10.0 if landscape else 14.0, 0.0, 0.88 if landscape else 0.95)


# ------------------------------------------------------------------- Szene


func _place_hoop() -> void:
	if _hoop == null:
		return
	var hoop := hoop_now()
	_hoop.position = Vector3(float(hoop["x"]), 0.0, float(hoop["z"]))


func _place_ball() -> void:
	if _ball_node == null:
		return
	var world := _ball_world()
	_ball_node.position = world
	_ball_node.rotation.x += 0.16 if phase == "fly" else 0.0
	_ball_shadow.position = Vector3(world.x, 0.02, world.z)
	var fade := clampf(1.0 - world.y / 5.0, 0.12, 0.4)
	_ball_shadow.scale = Vector3.ONE * clampf(1.4 - world.y * 0.12, 0.5, 1.4)
	var mat := _ball_shadow.get_active_material(0)
	if mat is StandardMaterial3D:
		(mat as StandardMaterial3D).albedo_color.a = fade


func _ball_world() -> Vector3:
	if phase == "fly" and not ball.is_empty():
		return Vector3(float(ball["px"]), float(ball["py"]), float(ball["pz"]))
	var spawn: Dictionary = tune["SPAWN"]
	return Vector3(float(spawn["x"]), float(spawn["y"]), float(spawn["z"]))


func _tick_net(delta: float) -> void:
	if _net == null:
		return
	if _net_pulse <= 0.0:
		_net.scale = Vector3.ONE
		return
	_net_pulse = maxf(0.0, _net_pulse - delta)
	var f := _net_pulse / float(BasketBounceLogic.BASKET_JUICE["NET_PULSE_SEC"])
	_net.scale = Vector3(1.0 + 0.12 * f, 1.0 + 0.45 * f, 1.0 + 0.12 * f)


# ---------------------------------------------------------------- Spielzug


## Wischimpuls aus den letzten Abtastpunkten (px/s, Bildschirmkoordinaten).
func _flick_velocity() -> Vector2:
	if _samples.size() < 2:
		return Vector2.ZERO
	var last: Dictionary = _samples[_samples.size() - 1]
	var first: Dictionary = _samples[0]
	for sample: Dictionary in _samples:
		if float(last["t"]) - float(sample["t"]) <= FLICK_SAMPLE_SEC:
			first = sample
			break
	var dt := float(last["t"]) - float(first["t"])
	if dt <= 0.0001:
		return Vector2.ZERO
	return (Vector2(last["p"]) - Vector2(first["p"])) / dt


func _launch() -> void:
	var flick := _flick_velocity()
	var vel := BasketBounceLogic.flick_to_velocity(flick.x, flick.y, tune)
	_samples = []
	if vel.is_empty():
		return
	ball = BasketBounceLogic.make_ball(vel, tune)
	_trail = []
	phase = "fly"
	AudioDirector.try_play(self, "mg_good", 0.82)
	_gooby.face(PI * 0.58)
	_gooby.play_for("wave", 0.6)
	_gooby.swing(0.4, 34.0, Vector3.RIGHT)
	_gooby.emote("ecstatic", 0.7)


func _step_flight(delta: float) -> void:
	var hoop := hoop_now()
	var ev := BasketBounceLogic.step_ball_swept(ball, delta, hoop, tune)
	_trail.append(Vector3(float(ball["px"]), float(ball["py"]), float(ball["pz"])))
	if _trail.size() > TRAIL_MAX:
		_trail.pop_front()
	if bool(ev["rim"]):
		AudioDirector.try_play(self, "mg_junk", 1.1)
		_stage.shake(0.05, 0.2)
	if bool(ev["board"]):
		AudioDirector.try_play(self, "mg_spill", 1.15)
		_stage.shake(0.04, 0.18)
	if bool(ev["basket"]):
		_resolve_shot(true, not bool(ball["rim"]) and not bool(ball["board"]), bool(ball["board"]))
	elif bool(ev["dead"]):
		_resolve_shot(false, false, false)


func _resolve_shot(made: bool, swish: bool, bank: bool) -> void:
	shots += 1
	var moving := BasketBounceLogic.is_moving_hoop(baskets, tune)
	var shot := BasketBounceLogic.score_shot(
		{"basket": made, "swish": swish, "bank": bank}, swish_streak, moving, tune
	)
	swish_streak = int(shot["swishStreak"])
	var points := int(shot["points"])
	score += points
	var hoop := hoop_now()
	var world := Vector3(float(hoop["x"]), float(tune["RIM_Y"]), float(hoop["z"]))
	var pos := _stage.to_screen(world)
	if made:
		baskets += 1
		miss_streak = 0
		_flash_text = "+%d" % points
		_flash = 0.9
		_net_pulse = float(BasketBounceLogic.BASKET_JUICE["NET_PULSE_SEC"])
		_sparks.burst(world - Vector3(0.0, 0.35, 0.0))
		_stage.pulse_glow(0.9 if swish else 0.55)
		# Beim Korb dreht Gooby sich zur Kamera — sonst sähe man nur den Rücken.
		_gooby.face(0.3)
		_gooby.play("celebrate")
		_gooby.hop(0.5, 0.34)
		_gooby.emote("ecstatic", 1.5)
		_celebrate(swish, bank, pos, points)
	else:
		miss_streak += 1
		_flash_text = I18nService.t("mg.basketBounce.miss")
		_flash = 0.8
		AudioDirector.try_play(self, "mg_spill")
		_gooby.face(PI * 0.58)
		_gooby.play("idle")
		_gooby.emote("sad", 1.1)
		if ctx.juice != null:
			ctx.juice.shake(0.25)
			ctx.juice.sfx("game_miss")
			ctx.juice.show_combo(0)
			ctx.juice.float_text(pos, _flash_text, Color(0.8, 0.35, 0.3))
	ctx.report_score(score, points)
	phase = "reset"
	reset_left = float(tune["SHOT_RESET_SEC"])
	if BasketBounceLogic.is_round_over(elapsed, miss_streak, tune):
		_finish()


func _celebrate(swish: bool, bank: bool, pos: Vector2, points: int) -> void:
	if swish:
		# Swish-Serie klettert die volle Halbton-Treppe (Deckel +12).
		AudioDirector.try_play(self, "mg_perfect", FeelSfx.combo_pitch(swish_streak))
	elif bank:
		AudioDirector.try_play(self, "mg_combo")
	else:
		AudioDirector.try_play(self, "mg_good")
	if ctx.juice == null:
		return
	ctx.juice.float_text(pos, "+%d" % points, Color(1.0, 0.72, 0.2))
	ctx.juice.overlay_ring(pos, Color(1.0, 0.72, 0.2), 70.0 if swish else 52.0)
	ctx.juice.hit_freeze(45)
	ctx.juice.bloom_pulse(0.7 if swish else 0.4)
	if swish_streak >= 2:
		ctx.juice.show_combo(swish_streak)
	if BasketBounceLogic.is_on_fire(swish_streak):
		AudioDirector.try_play(self, "mg_golden")
		ctx.juice.bloom_pulse(1.0)
		ctx.juice.edge_glow(0.75, Color(1.0, 0.55, 0.25))
		_stage.pulse_glow(1.2)
		ctx.juice.float_text(
			pos - Vector2(0.0, 44.0),
			I18nService.t("mg.basketBounce.on_fire"),
			Color(0.95, 0.45, 0.66)
		)


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	ctx.report_end({"score": score, "baskets": baskets, "shots": shots})


func _update_labels() -> void:
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.basketBounce.misses",
			{"n": miss_streak, "max": int(tune["ENDLESS_CONSECUTIVE_MISSES"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - elapsed)))
		_time_label.text = I18nService.t("mg.game.time", {"sec": left})
	if swish_streak > 1:
		_streak_label.text = I18nService.t("mg.game.streak", {"n": swish_streak})
	else:
		_streak_label.text = ""


# ------------------------------------------------------------- Zielhilfe 2D


## Nur Flugspur, Zielhilfe und Trefferbanner werden gezeichnet — die Halle
## selbst ist 3D und liegt dahinter.
func _draw() -> void:
	_draw_trail()
	_draw_aim()
	_draw_flash()


func _draw_trail() -> void:
	if _trail.size() < 2 or _stage == null:
		return
	for i in range(1, _trail.size()):
		var a := float(i) / _trail.size()
		draw_line(
			_stage.to_screen(_trail[i - 1]),
			_stage.to_screen(_trail[i]),
			Color(1.0, 0.82, 0.4, a * 0.7),
			3.0 * a + 1.0
		)


func _draw_aim() -> void:
	if not _dragging:
		return
	var pull := _drag_to - _drag_from
	draw_line(_drag_from, _drag_to, Color(0.95, 0.45, 0.66, 0.55), 4.0)
	var flick := _flick_velocity()
	var preview := BasketBounceLogic.flick_to_velocity(flick.x, flick.y, tune)
	var strength := clampf(pull.length() / 220.0, 0.0, 1.0)
	var tint := Color(0.35, 0.78, 0.5, 0.9) if not preview.is_empty() else Color(0.8, 0.5, 0.5, 0.7)
	draw_arc(_drag_from, 26.0, -PI * 0.5, -PI * 0.5 + TAU * strength, 22, tint, 5.0)


func _draw_flash() -> void:
	if _flash <= 0.0 or _flash_text.is_empty():
		return
	var font := ThemeService.font(800)
	var alpha := clampf(_flash * 1.6, 0.0, 1.0)
	var pos := Vector2(0.0, view_size.y * 0.3)
	draw_string(
		font,
		pos,
		_flash_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		view_size.x,
		34,
		Color(0.95, 0.45, 0.66, alpha)
	)
