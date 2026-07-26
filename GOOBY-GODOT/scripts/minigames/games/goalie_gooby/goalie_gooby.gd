extends MinigameBase
## Torwart-Gooby (goalieGooby) — Spiel-Szene. Alle MECHANIK-Zahlen aus
## GoalieGoobyLogic (zahlengleich zum Web): 5 Bahnen, Ankündigung 0.9 s → 0.45 s,
## Heber/Roller, Parade +4 (+2 Superparade), 3 Gegentore beenden früh,
## alle 10 Paraden Jubel + 10 % Tempo, Elfmeterfinale ab Sekunde 50.
##
## ECHTES 3D (Agent 3D-A, Rückbau): die Kamera steht dort, wo der Schütze
## anläuft (GOALIE_JUICE.CAM_Z_*), und blickt auf ein echtes Tor mit Pfosten,
## Latte und Netz auf einem Bolzplatz im Park. Gooby ist als ECHTES Rig der
## Torwart — er steht dem Spieler ZUGEWANDT auf der Linie, hechtet in die
## gewischte Bahn, springt beim Heber, geht beim Roller runter und jubelt
## nach der Parade.
##
## Der MinigameBase-Vertrag bleibt: Wurzel ist Node2D, die 3D-Welt hängt
## darunter, HUD/Banner/Gegentor-Punkte sind CanvasItems obenauf.
##
## Die Steuerung ist unverändert: wischen = hechten, tippen = Mitte. Die Bahn
## 0…4 liegt weiterhin links → rechts im Bild, weil die Kamera achsparallel
## auf −z blickt.

const Logic := preload("res://scripts/minigames/games/goalie_gooby/goalie_gooby_logic.gd")
const Stage3D := preload("res://scripts/minigames/games/_3da_stage/stage3d.gd")
const Props3D := preload("res://scripts/minigames/games/_3da_stage/props3d.gd")
const GoobyActor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Spark3D := preload("res://scripts/minigames/games/_3da_stage/spark3d.gd")

const ASSETS := "res://assets/minigames/goalie_gooby/"

## Mindest-Wischweg (px), bevor eine Geste als Hechte gilt.
const SWIPE_MIN_PX := 10.0
## Torhöhe im Verhältnis zur halben Torbreite (Kinderfeld-Proportion).
const GOAL_H_RATIO := 0.8
## Elfmeterpunkt (Meter vor der Linie) — von dort kommt jeder Schuss.
const SPOT_Z := 7.4
## Ballradius in Metern.
const BALL_R := 0.16

const GRASS := Color(0.35, 0.61, 0.33)
const POST := Color(0.99, 0.99, 0.97)
const BALL_COLOR := Color(0.99, 0.99, 0.96)

var tune: Dictionary = {}
var rng: GoobyRng
var score := 0
var saves := 0
var goals := 0
## Parade-Serie ohne Gegentor (nur Anzeige/Feel — Combo-Ton steigt mit).
var save_streak := 0
var elapsed := 0.0
var kick: Dictionary = {}
var kick_start := 0.0
var arrive_t := 0.0
var next_kick_at := 0.6
var dive: Dictionary = {}
var finished := false
var view_size := Vector2(844.0, 390.0)
var landscape := true

var _stream: Callable
var _drag_from := Vector2.ZERO
var _ring := 0.0
var _ring_scale := 1.0
var _pip_pop := 0.0
var _cheer := 0.0
var _flash := 0.0
var _flash_text := ""
var _time_label: Label
var _saves_label: Label
var _hint_label: Label

var _stage: Stage3D
var _gooby: GoobyActor
var _sparks: Spark3D
var _goal: Node3D
var _lane_glow: MeshInstance3D
var _ball_node: Node3D
var _ball_shadow: MeshInstance3D
var _save_ring: MeshInstance3D
var _keeper_x := 0.0
var _keeper_y := 0.0
var _built_half := 0.0


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = Logic.apply_difficulty(Logic.GOALIE, ctx.difficulty)
	rng = ctx.rng()
	_stream = func() -> float: return rng.next()
	_build_world()
	_build_hud()
	_fit_viewport()
	if is_inside_tree():
		get_viewport().size_changed.connect(_fit_viewport)


func end() -> void:
	super.end()
	finished = true


## Pflicht-Layouthook: beide Orientierungen laufen über DIESE Funktion.
## Das Tor ist hochkant SCHMALER (GOAL_HALF_W_PORTRAIT) — es wird also neu
## gebaut, nicht nur die Kamera verschoben.
func apply_view(size: Vector2) -> void:
	if size.x > 1.0 and size.y > 1.0:
		view_size = size
	landscape = view_size.x > view_size.y
	position = Vector2.ZERO
	if _stage != null:
		_stage.apply_size(view_size)
		_stage.set_fov(40.0 if landscape else 36.0)
		_build_goal()
		_frame_goal()
	if _time_label != null:
		_time_label.position = Vector2(16.0, 10.0)
		_saves_label.position = Vector2(16.0, 48.0)
		_hint_label.position = Vector2(view_size.x * 0.5 - 150.0, view_size.y - 48.0)
		_hint_label.size = Vector2(300.0, 40.0)
	queue_redraw()


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	elapsed += delta
	_ring = maxf(0.0, _ring - delta)
	_pip_pop = maxf(0.0, _pip_pop - delta)
	_cheer = maxf(0.0, _cheer - delta)
	_flash = maxf(0.0, _flash - delta)
	_stage.tick(delta)
	_gooby.tick(delta)
	if not bool(tune["ENDLESS"]) and elapsed >= float(tune["DURATION_SEC"]):
		_finish()
		return
	if kick.is_empty():
		if elapsed >= next_kick_at:
			_spawn_kick()
	elif elapsed >= arrive_t:
		_resolve_kick()
	_tick_keeper(delta)
	_tick_ball()
	_tick_telegraph()
	_tick_ring(delta)
	_update_labels()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			_drag_from = event.position
		else:
			_dive(event.position - _drag_from)


## Aktuelle Torbreite in Weltmetern (quer breiter als hochkant).
func goal_half_width() -> float:
	var juice: Dictionary = Logic.GOALIE_JUICE
	return float(juice["GOAL_HALF_W_LANDSCAPE" if landscape else "GOAL_HALF_W_PORTRAIT"])


## Wie weit der aktuelle Schuss geflogen ist (0 Ankündigung … 1 Linie).
func kick_progress() -> float:
	if kick.is_empty():
		return 0.0
	var telegraph := float(kick["telegraph"])
	var flight := float(kick["flight"])
	var t := elapsed - kick_start
	if t < telegraph:
		return 0.0
	return clampf((t - telegraph) / maxf(0.001, flight), 0.0, 1.0)


# ------------------------------------------------------------------ Aufbau


func _build_world() -> void:
	_stage = Stage3D.new()
	add_child(_stage)
	(
		_stage
		. build(
			{
				"sky_top": Color(0.36, 0.63, 0.95),
				"sky_horizon": Color(0.92, 0.96, 1.0),
				# Boden-Hemisphäre = Nebelfarbe: die Wiese endet irgendwo, und
				# ohne diesen Abgleich klebt dort ein dunkelgrüner Balken.
				"ground_horizon": Color(0.86, 0.93, 0.92),
				"ground_bottom": Color(0.86, 0.93, 0.92),
				"fog_color": Color(0.86, 0.93, 0.92),
				# Nebel erst SPÄT: hochkant steht die Kamera fast 20 m zurück,
				# ein früher Nebel bleicht dann den halben Platz aus.
				"fog_from": 38.0,
				"fog_to": 100.0,
				"fog_density": 1.0,
				"sun_dir": Vector3(-0.36, -0.84, 0.4),
				"sun_color": Color(1.0, 0.95, 0.85),
				"sun_energy": 1.25,
				"ambient": 0.32,
				"ambient_color": Color(0.92, 0.9, 0.84),
				"sky_ambient": 0.34,
				"exposure": 0.54,
				"fill_energy": 0.24,
				"glow": 0.3,
				"shadow_distance": 26.0,
				"fov": 40.0,
			}
		)
	)
	_stage.add_child(Props3D.ground(Vector2(220.0, 220.0), Props3D.flat(GRASS), -0.01))
	_build_stripes()
	_build_park()

	_goal = Node3D.new()
	_stage.add_child(_goal)

	_ball_node = Node3D.new()
	_ball_node.add_child(Props3D.sphere(BALL_R, Props3D.flat(BALL_COLOR, 0.55)))
	for i in 6:
		var a := TAU * float(i) / 6.0
		var patch := Props3D.sphere(BALL_R * 0.34, Props3D.flat(Color(0.22, 0.24, 0.3), 0.6))
		patch.position = (
			Vector3(sin(a), 0.35 * (1 if i % 2 == 0 else -1), cos(a)).normalized() * BALL_R * 0.92
		)
		_ball_node.add_child(patch)
	_stage.add_child(_ball_node)
	_ball_shadow = Props3D.blob_shadow(BALL_R * 2.2, 0.3)
	_stage.add_child(_ball_shadow)

	_save_ring = Props3D.torus(0.4, 0.05, Props3D.glow(Color(1.0, 0.88, 0.42), 2.6))
	_save_ring.visible = false
	_stage.add_child(_save_ring)

	_gooby = GoobyActor.new()
	_stage.add_child(_gooby)
	# yaw 0 = zur Kamera: der Torwart schaut dem Schützen (und dem Spieler)
	# ins Gesicht — genau darum geht es in diesem Spiel.
	_gooby.mount(1.2, 0.0)
	_gooby.hold(
		_build_glove(Color(0.98, 0.55, 0.35)),
		"arm.R",
		Transform3D(Basis.IDENTITY, Vector3(0.0, -0.16, 0.0))
	)
	_gooby.hold(
		_build_glove(Color(0.98, 0.55, 0.35)),
		"arm.L",
		Transform3D(Basis.IDENTITY, Vector3(0.0, -0.16, 0.0))
	)

	_sparks = Spark3D.new()
	_stage.add_child(_sparks)
	_sparks.build({"color": Color(1.0, 0.9, 0.5), "amount": 24, "speed": Vector2(1.5, 3.6)})


func _build_glove(color: Color) -> Node3D:
	var holder := Node3D.new()
	var pad := Props3D.sphere(0.11, Props3D.flat(color, 0.7))
	pad.scale = Vector3(1.0, 1.25, 0.75)
	holder.add_child(pad)
	return holder


## Gemähte Rasenbahnen quer zum Schuss — sie geben der leeren Wiese Tiefe.
func _build_stripes() -> void:
	# Flache PLATTEN, keine Quader: die 2 cm hohen Seitenflächen eines Quaders
	# lesen sich aus flachem Blickwinkel als dunkle Scanlines über die Wiese.
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(64.0, 3.2)
	mesh.material = Props3D.flat(GRASS.darkened(0.13))
	var poses: Array = []
	for i in 10:
		poses.append(Props3D.pose(Vector3(0.0, 0.004, 6.4 - float(i) * 6.4)))
	_stage.add_child(Props3D.swarm_mesh(mesh, poses, 40.0))


## Bolzplatz im Park: Hecke hinter dem Tor, Bäume dahinter, Büsche und
## Blumen an den Seiten. Hinter der Kamera bleibt alles leer.
func _build_park() -> void:
	var behind := func(at: Vector3) -> bool: return at.z > SPOT_Z + 1.0

	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.4, 1.0, 1.0)
	mesh.material = Props3D.flat(Color(0.29, 0.53, 0.31))
	var poses: Array = []
	for i in 26:
		var a := TAU * float(i) / 26.0
		var at := Vector3(sin(a) * 15.0, 0.45, cos(a) * 15.0)
		if at.z > SPOT_Z + 1.0:
			continue
		poses.append(Props3D.pose(at, -a, 1.0 + 0.08 * sin(float(i) * 2.1)))
	_stage.add_child(Props3D.swarm_mesh(mesh, poses, 34.0))

	_stage.add_child(
		Props3D.scatter(ASSETS + "tree_oak.glb", 4.1, 10, 17.0, Vector3.ZERO, 1.6, 1.0, behind)
	)
	_stage.add_child(
		Props3D.scatter(ASSETS + "tree_fat.glb", 3.5, 8, 18.4, Vector3.ZERO, 1.7, 1.9, behind)
	)
	_stage.add_child(
		Props3D.scatter(
			ASSETS + "tree_pineRoundA.glb", 4.6, 7, 19.6, Vector3.ZERO, 1.8, 2.6, behind
		)
	)
	_stage.add_child(
		Props3D.scatter(
			ASSETS + "plant_bushLarge.glb", 0.85, 12, 13.2, Vector3.ZERO, 1.0, 0.5, behind
		)
	)
	_stage.add_child(
		Props3D.scatter(ASSETS + "grass_large.glb", 0.36, 20, 11.4, Vector3.ZERO, 1.8, 3.1, behind)
	)
	_stage.add_child(
		Props3D.scatter(
			ASSETS + "flower_yellowA.glb", 0.3, 12, 12.4, Vector3.ZERO, 1.2, 2.2, behind
		)
	)
	_stage.add_child(
		Props3D.scatter(ASSETS + "flower_redA.glb", 0.32, 12, 13.9, Vector3.ZERO, 1.1, 3.8, behind)
	)
	var bench := Props3D.model(ASSETS + "bench.glb", 0.66)
	bench.position = Vector3(-9.2, 0.0, 1.4)
	bench.rotation.y = PI * 0.5
	Props3D.repaint(bench, Props3D.NATURE)
	_stage.add_child(bench)


## Tor mit Pfosten, Latte, Netz und Strafraumlinien. Wird bei jedem
## Orientierungswechsel neu gebaut — hochkant ist es 2×2,4 m statt 2×3,1 m.
func _build_goal() -> void:
	var half := goal_half_width()
	if absf(half - _built_half) < 0.001:
		return
	_built_half = half
	for child in _goal.get_children():
		child.queue_free()
	_lane_glow = null
	var height := half * GOAL_H_RATIO * 2.0 * 0.5 + 0.4
	var post_mat := Props3D.flat(POST, 0.4)
	for side: float in [-1.0, 1.0]:
		var post := Props3D.cylinder(0.075, height, post_mat)
		post.position = Vector3(side * half, height * 0.5, 0.0)
		_goal.add_child(post)
	var bar := Props3D.cylinder(0.075, half * 2.0, post_mat)
	bar.rotation.z = PI * 0.5
	bar.position = Vector3(0.0, height, 0.0)
	_goal.add_child(bar)
	# Netz: Rückwand + zwei Seiten + Dach, jeweils als Gitter aus dünnen
	# Stäben in EINEM MultiMesh (vier Draw-Calls wären Verschwendung).
	_build_net(half, height)
	_build_pitch_lines(half)
	_build_lane_strips(half)
	# Leuchtfeld für die angekündigte Bahn.
	_lane_glow = Props3D.box(
		Vector3(half * 2.0 / float(tune["LANES"]), height, 0.05),
		Props3D.glass(Color(1.0, 0.85, 0.35, 0.3), true)
	)
	_lane_glow.visible = false
	_goal.add_child(_lane_glow)


func _build_net(half: float, height: float) -> void:
	var depth := 1.5
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.02, 1.0, 0.02)
	mesh.material = Props3D.glass(Color(1.0, 1.0, 1.0, 0.55), true)
	var poses: Array = []
	var steps := 15
	for i in steps + 1:
		var x := -half + 2.0 * half * float(i) / float(steps)
		poses.append(_bar(Vector3(x, height * 0.5, -depth), Vector3(0.0, height, 0.0)))
	for i in 7:
		var y := height * float(i) / 6.0
		poses.append(_bar(Vector3(0.0, y, -depth), Vector3(half * 2.0, 0.0, 0.0)))
	for side: float in [-1.0, 1.0]:
		for i in 5:
			var y := height * float(i) / 4.0
			poses.append(_bar(Vector3(side * half, y, -depth * 0.5), Vector3(0.0, 0.0, depth)))
		for i in 5:
			var z := -depth * float(i) / 4.0
			poses.append(_bar(Vector3(side * half, height * 0.5, z), Vector3(0.0, height, 0.0)))
	for i in 5:
		var z := -depth * float(i) / 4.0
		poses.append(_bar(Vector3(0.0, height, z), Vector3(half * 2.0, 0.0, 0.0)))
	_goal.add_child(Props3D.swarm_mesh(mesh, poses, 6.0))


## Ein Netzstab: Mitte + Richtungsvektor (Länge = Betrag).
func _bar(at: Vector3, along: Vector3) -> Transform3D:
	var length := along.length()
	var basis := Basis.IDENTITY
	if absf(along.x) > 0.001:
		basis = Basis(Vector3.FORWARD, PI * 0.5)
	elif absf(along.z) > 0.001:
		basis = Basis(Vector3.RIGHT, PI * 0.5)
	return Transform3D(basis * Basis.from_scale(Vector3(1.0, length, 1.0)), at)


## Torlinie, Strafraum und Elfmeterpunkt als flache Streifen.
func _build_pitch_lines(half: float) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(1.0, 1.0)
	mesh.material = Props3D.flat(Color(1.0, 0.99, 0.96), 0.85)
	var box_half := half + 3.4
	var box_depth := SPOT_Z + 2.2
	var poses: Array = [
		Transform3D(Basis.from_scale(Vector3(box_half * 2.0, 1.0, 0.1)), Vector3(0.0, 0.012, 0.0)),
		Transform3D(
			Basis.from_scale(Vector3(box_half * 2.0, 1.0, 0.1)), Vector3(0.0, 0.012, box_depth)
		),
		Transform3D(
			Basis.from_scale(Vector3(0.1, 1.0, box_depth)),
			Vector3(-box_half, 0.012, box_depth * 0.5)
		),
		Transform3D(
			Basis.from_scale(Vector3(0.1, 1.0, box_depth)),
			Vector3(box_half, 0.012, box_depth * 0.5)
		),
		Transform3D(Basis.from_scale(Vector3(0.24, 1.0, 0.24)), Vector3(0.0, 0.014, SPOT_Z)),
	]
	_goal.add_child(Props3D.swarm_mesh(mesh, poses, 12.0))


## Fünf helle Kreidebahnen vom Elfmeterpunkt zur Linie — wie im Web. Sie
## erzählen dem Spieler, wohin gehechtet werden kann, und füllen hochkant den
## sonst leeren Vordergrund mit Fluchtlinien.
func _build_lane_strips(half: float) -> void:
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(1.0, 1.0)
	mesh.material = Props3D.flat(Color(1.0, 1.0, 0.98, 0.2))
	mesh.material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var lanes := int(tune["LANES"])
	var length := SPOT_Z + 0.6
	var poses: Array = []
	for i in lanes:
		var x := lane_world(i, 0.0).x
		poses.append(
			Transform3D(
				Basis.from_scale(Vector3(half * 2.0 / float(lanes) * 0.52, 1.0, length)),
				Vector3(x * 0.86, 0.011, length * 0.5)
			)
		)
	_goal.add_child(Props3D.swarm_mesh(mesh, poses, 24.0))


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	_time_label.add_theme_color_override("font_color", Color(1.0, 0.99, 0.95))
	_time_label.add_theme_color_override("font_outline_color", Color(0.16, 0.24, 0.15, 0.85))
	_time_label.add_theme_constant_override("outline_size", 6)
	add_child(_time_label)
	_saves_label = Label.new()
	_saves_label.theme_type_variation = &"CaptionLabel"
	_saves_label.add_theme_color_override("font_color", Color(1.0, 0.94, 0.8))
	_saves_label.add_theme_color_override("font_outline_color", Color(0.16, 0.24, 0.15, 0.85))
	_saves_label.add_theme_constant_override("outline_size", 5)
	add_child(_saves_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.goalieGooby.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_color_override("font_color", Color(1.0, 0.99, 0.95, 0.95))
	_hint_label.add_theme_color_override("font_outline_color", Color(0.16, 0.24, 0.15, 0.75))
	_hint_label.add_theme_constant_override("outline_size", 5)
	add_child(_hint_label)
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


# ------------------------------------------------------------------ Kamera


## Kamera dorthin, wo der Schütze anläuft — leicht erhöht, achsparallel auf
## −z, damit Bahn 0…4 weiterhin links → rechts im Bild liegt.
func _frame_goal() -> void:
	if _stage == null:
		return
	var half := goal_half_width()
	var height := half * GOAL_H_RATIO + 0.4
	# Hochkant zählt NICHT der ganze Anlauf zum Bildausschnitt: nähme man den
	# Elfmeterpunkt mit, bände die Höhe den Ausschnitt und das Tor bliebe ein
	# schmaler Streifen in der Bildmitte. Der Ball fliegt die erste Zehntel-
	# sekunde dann knapp außerhalb — genau wie in der Web-Fassung.
	var near_z := SPOT_Z + 0.6 if landscape else SPOT_Z * 0.55
	var points: Array = [
		Vector3(-half - 0.9, 0.0, 0.0),
		Vector3(half + 0.9, 0.0, 0.0),
		Vector3(-half - 0.9, height + 0.7, 0.0),
		Vector3(half + 0.9, height + 0.7, 0.0),
		Vector3(0.0, 0.0, near_z),
	]
	var center := Vector3(0.0, height * 0.55, near_z * 0.42)
	# Hochkant steiler und enger: sonst steht das Tor als schmaler Streifen in
	# der Bildmitte, oben nur Himmel, unten nur Rasen.
	_stage.fit(points, center, 8.0 if landscape else 16.0, 0.0, 0.94 if landscape else 0.96)


# ------------------------------------------------------------------- Szene


## Weltmitte einer Torbahn auf der Linie.
func lane_world(lane: int, y := 0.9) -> Vector3:
	var lanes := int(tune["LANES"])
	var span := goal_half_width() - 0.42
	var t := (float(lane) - (lanes - 1) * 0.5) / maxf(1.0, (lanes - 1) * 0.5)
	return Vector3(t * span, y, 0.0)


## Zielhöhe eines Schusses nach Art (Heber hoch, Roller flach).
func _kick_height(kind: String) -> float:
	var height := goal_half_width() * GOAL_H_RATIO + 0.4
	match kind:
		"lob":
			return height * 0.82
		"roller":
			return BALL_R + 0.04
		_:
			return height * 0.42


func _tick_keeper(_delta: float) -> void:
	if _gooby == null:
		return
	var lane := int(dive.get("lane", 2))
	var v := str(dive.get("v", "mid"))
	var target := lane_world(lane)
	var lift := 0.0
	if v == "up":
		lift = 0.34
	elif v == "down":
		lift = -0.12
	# Sanft nachziehen: der harte Sprung der 2D-Fassung wirkt in 3D wie ein
	# Teleport. Die LOGIK entscheidet weiterhin allein über die Parade.
	_keeper_x = lerpf(_keeper_x, target.x, 0.35)
	_keeper_y = lerpf(_keeper_y, lift, 0.3)
	_gooby.position = Vector3(_keeper_x, maxf(0.0, _keeper_y), 0.22)
	_gooby.rotation.z = -clampf((target.x - _keeper_x) * 0.6 + _keeper_x * 0.12, -0.5, 0.5)


func _tick_ball() -> void:
	if _ball_node == null:
		return
	if kick.is_empty():
		_ball_node.visible = false
		_ball_shadow.visible = false
		return
	_ball_node.visible = true
	_ball_shadow.visible = true
	var p := kick_progress()
	var kind := str(kick["kind"])
	var target := lane_world(int(kick["lane"]), _kick_height(kind))
	var from := Vector3(0.0, BALL_R + 0.06, SPOT_Z)
	var at := from.lerp(target, p)
	if kind == "lob":
		at.y += sin(p * PI) * 0.85
	elif kind == "roller":
		at.y = BALL_R + 0.02
	else:
		at.y += sin(p * PI) * 0.22
	_ball_node.position = at
	_ball_node.rotation.x -= 0.35 * p
	_ball_shadow.position = Vector3(at.x, 0.02, at.z)
	_ball_shadow.scale = Vector3.ONE * clampf(1.3 - at.y * 0.2, 0.6, 1.3)


func _tick_telegraph() -> void:
	if _lane_glow == null:
		return
	if kick.is_empty() or elapsed - kick_start > float(kick["telegraph"]):
		_lane_glow.visible = false
		return
	var height := goal_half_width() * GOAL_H_RATIO + 0.4
	_lane_glow.visible = true
	_lane_glow.position = Vector3(lane_world(int(kick["lane"])).x, height * 0.5, -0.1)
	var mat := _lane_glow.get_active_material(0)
	if mat is StandardMaterial3D:
		var pulse := 0.18 + 0.24 * absf(sin((elapsed - kick_start) * 16.0))
		var tint := Color(1.0, 0.85, 0.35, pulse)
		if str(kick["kind"]) == "lob":
			tint = Color(0.55, 0.85, 1.0, pulse)
		elif str(kick["kind"]) == "roller":
			tint = Color(1.0, 0.6, 0.85, pulse)
		(mat as StandardMaterial3D).albedo_color = tint


func _tick_ring(delta: float) -> void:
	if _save_ring == null:
		return
	if _ring <= 0.0:
		_save_ring.visible = false
		return
	_ring = maxf(0.0, _ring)
	var f := 1.0 - _ring / float(Logic.GOALIE_JUICE["RING_LIFE_SEC"])
	_save_ring.visible = true
	_save_ring.scale = Vector3.ONE * (0.5 + f * _ring_scale * 0.5)
	_save_ring.rotation.y += delta * 3.0


# ---------------------------------------------------------------- Spielzug


func _spawn_kick() -> void:
	var shootout := Logic.is_shootout_at(elapsed, tune)
	var rolled := Logic.roll_kick(_stream, elapsed)
	var telegraph: float = (
		tune["SHOOTOUT_TELEGRAPH_SEC"] if shootout else Logic.telegraph_sec_at(elapsed, tune)
	)
	var flight: float = (
		tune["SHOOTOUT_FLIGHT_SEC"]
		if shootout
		else Logic.flight_sec_at(Logic.cheers_at(saves), tune)
	)
	kick = {
		"lane": int(rolled["lane"]),
		"kind": str(rolled["kind"]),
		"telegraph": telegraph,
		"flight": flight,
		"shootout": shootout,
	}
	kick_start = elapsed
	arrive_t = elapsed + telegraph + flight
	dive = {}
	AudioDirector.try_play(self, "mg_junk", 0.7)
	_gooby.emote("scared", telegraph)


## Hechte in die gewischte Bahn (Tippen = Mitte).
func _dive(delta_px: Vector2) -> void:
	var lane := Logic.lane_from_swipe(delta_px.x, delta_px.y)
	var v := Logic.v_kind_from_swipe(delta_px.y)
	if delta_px.length() < SWIPE_MIN_PX:
		lane = 2
		v = "mid"
	dive = {"lane": lane, "v": v, "t": elapsed}
	AudioDirector.try_play(self, "mg_good", 1.1)
	if v == "up":
		_gooby.hop(0.4, 0.3)
	_gooby.play_for("wave", 0.45)
	_gooby.swing(0.35, 26.0, Vector3.FORWARD)
	if ctx.juice != null:
		ctx.juice.shake(0.1)


func _resolve_kick() -> void:
	var saved := (
		not dive.is_empty()
		and Logic.save_matches(kick, dive)
		and Logic.dive_covers(float(dive["t"]), arrive_t, tune)
	)
	var shootout := bool(kick["shootout"])
	if saved:
		_on_save()
	else:
		_on_goal()
	kick = {}
	next_kick_at = elapsed + float(tune["SHOOTOUT_GAP_SEC" if shootout else "GAP_SEC"])


func _on_save() -> void:
	var super_save := Logic.is_super_save(float(dive["t"]), arrive_t, tune)
	var shootout := bool(kick["shootout"])
	var points := Logic.save_points(super_save, shootout, tune)
	var before := Logic.cheers_at(saves)
	saves += 1
	save_streak += 1
	score += points
	var world := lane_world(int(kick["lane"]), _kick_height(str(kick["kind"])))
	_ring = float(Logic.GOALIE_JUICE["RING_LIFE_SEC"])
	_ring_scale = float(Logic.GOALIE_JUICE["RING_SCALE_SUPER" if super_save else "RING_SCALE_SAVE"])
	_save_ring.position = world
	_flash_text = I18nService.t("mg.goalieGooby.super") if super_save else "+%d" % points
	_flash = 0.8
	# Parade-Serie klingt pro Halten einen Halbton höher.
	AudioDirector.try_play(
		self, "mg_perfect" if super_save else "mg_good", FeelSfx.combo_pitch(save_streak)
	)
	_sparks.burst(world)
	_stage.pulse_glow(1.0 if super_save else 0.5)
	_stage.shake(0.06 if super_save else 0.03, 0.22)
	_gooby.play("celebrate")
	_gooby.emote("ecstatic", 1.2)
	if ctx.juice != null:
		# Nur die Punktzahl schwebt — der Klartext steht schon als Banner da.
		ctx.juice.float_text(_stage.to_screen(world), "+%d" % points, Color(1.0, 0.78, 0.3))
		ctx.juice.overlay_ring(
			_stage.to_screen(world), Color(1.0, 0.85, 0.4), 84.0 if super_save else 56.0
		)
		ctx.juice.hit_freeze(70 if super_save else 35)
		ctx.juice.bloom_pulse(0.9 if super_save else 0.4)
		if save_streak >= 2:
			ctx.juice.show_combo(save_streak)
		if super_save:
			ctx.juice.slowmo(0.35, 260)
	if Logic.cheers_at(saves) > before:
		_cheer = 1.4
		_gooby.hop(0.6, 0.4)
		AudioDirector.try_play(self, "mg_golden")
		if ctx.juice != null:
			ctx.juice.bloom_pulse(1.0)
	ctx.report_score(score, points)


func _on_goal() -> void:
	goals += 1
	save_streak = 0
	_pip_pop = 0.4
	_flash_text = I18nService.t("mg.goalieGooby.goal")
	_flash = 1.0
	AudioDirector.try_play(self, "mg_spill")
	_gooby.play("idle")
	_gooby.emote("sad", 1.3)
	_stage.shake(0.1, 0.35)
	if ctx.juice != null:
		ctx.juice.shake(0.5)
		ctx.juice.hit_flash(Color(0.9, 0.32, 0.22, 0.16), 180)
		ctx.juice.sfx("game_miss")
		ctx.juice.show_combo(0)
	ctx.report_score(score, 0)
	if goals >= int(tune["MAX_GOALS"]):
		_finish()


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	ctx.report_end({"score": score, "saves": saves, "goals": goals})


func _update_labels() -> void:
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.goalieGooby.conceded", {"n": goals, "max": int(tune["ENDLESS_GOALS"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - elapsed)))
		_time_label.text = I18nService.t("mg.game.time", {"sec": left})
	_saves_label.text = I18nService.t("mg.goalieGooby.saves", {"n": saves})


# ---------------------------------------------------------------- HUD 2D


## Gegentor-Punkte, Jubelband und Trefferbanner — die Szene selbst ist 3D.
func _draw() -> void:
	_draw_pips()
	if _cheer > 0.0:
		_draw_cheer()
	_draw_flash()


func _draw_pips() -> void:
	var maxg := int(tune["ENDLESS_GOALS"] if bool(tune["ENDLESS"]) else tune["MAX_GOALS"])
	for i in maxg:
		var pos := Vector2(view_size.x - 34.0 - i * 30.0, 26.0)
		var rad := 10.0
		if i == goals - 1 and _pip_pop > 0.0:
			rad *= 1.0 + (float(Logic.GOALIE_JUICE["PIP_POP_SCALE"]) - 1.0) * (_pip_pop / 0.4)
		draw_circle(pos, rad, Color(0.9, 0.35, 0.35) if i < goals else Color(1, 1, 1, 0.35))


func _draw_cheer() -> void:
	draw_string(
		ThemeService.font(800),
		Vector2(0.0, view_size.y * 0.1),
		I18nService.t("mg.goalieGooby.cheer"),
		HORIZONTAL_ALIGNMENT_CENTER,
		view_size.x,
		26,
		Color(1.0, 0.85, 0.4, clampf(_cheer, 0.0, 1.0))
	)


func _draw_flash() -> void:
	if _flash <= 0.0 or _flash_text.is_empty():
		return
	var alpha := clampf(_flash * 1.5, 0.0, 1.0)
	# Ohne dunkles Band verschwindet Pink auf dem Rasen.
	var y := view_size.y * 0.78
	draw_rect(Rect2(0.0, y - 34.0, view_size.x, 48.0), Color(0.12, 0.2, 0.13, 0.5 * alpha))
	draw_string(
		ThemeService.font(800),
		Vector2(0.0, y),
		_flash_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		view_size.x,
		32,
		Color(1.0, 0.86, 0.5, alpha)
	)
