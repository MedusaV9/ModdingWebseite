extends MinigameBase
## Minigolf (miniGolf) — Spiel-Szene. Alle MECHANIK-Zahlen kommen aus
## MiniGolfLogic/MiniGolfCourse (zahlengleich zum Web): 6 gesetzte Löcher,
## Zugkraft = Ziehlänge (gedeckelt), Reibung 0.985/Frame, Banden, Windmühlentor,
## Kuppel, Rampe, 10-Schlag-Abbruch, Wertung 30/20/12/6.
##
## ECHTES 3D (Agent 3D-A, Rückbau): die Bahn ist eine Node3D-Welt aus dem
## Kenney-Minigolf-Kit (Windmühle mit drehenden Flügeln, Tunnelbogen, Fahne)
## auf einer Gartenwiese mit Bäumen, Hecke und Blumen — und Gooby steht als
## ECHTES Rig am Abschlag, holt mit dem Putter aus, jubelt beim Einlochen und
## lässt die Ohren hängen, wenn das Loch verloren geht.
##
## Der MinigameBase-Vertrag bleibt: Wurzel ist Node2D, die 3D-Welt hängt
## darunter (Godot rendert 3D hinter den CanvasItems), HUD und Zielhilfe
## liegen als CanvasItems obenauf.
##
## Die Steuerung ist unverändert: ziehen und loslassen. Nur die Richtung
## kommt jetzt aus dem Kamerastrahl auf die Bahnebene (Screen-to-World)
## statt aus einer fest verdrahteten Bildschirmachse.

const Logic := preload("res://scripts/minigames/games/mini_golf/mini_golf_logic.gd")
const Course := preload("res://scripts/minigames/games/mini_golf/mini_golf_course.gd")
const Scenery := preload("res://scripts/minigames/games/mini_golf/mini_golf_scenery.gd")
const Stage3D := preload("res://scripts/minigames/games/_3da_stage/stage3d.gd")
const Props3D := preload("res://scripts/minigames/games/_3da_stage/props3d.gd")
const GoobyActor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Spark3D := preload("res://scripts/minigames/games/_3da_stage/spark3d.gd")

const ASSETS := "res://assets/minigames/mini_golf/"

## Ruhepause nach einem eingelochten/abgebrochenen Loch (s).
const HOLE_PAUSE_SEC := 1.1
## Sichtbares Versacken des Balls im Loch (s) — statt hartem Ausblenden.
const SINK_SEC := 0.38
## Wie stark Gooby sich beim Zielen zurücklehnt (Radiant bei voller Kraft).
const WINDUP_LEAN := 0.22
## Punkte der gepunkteten Zielvorschau.
const PREVIEW_DOTS := 14
## Kachelhöhe der Bahn (Filz liegt auf y = 0).
const TILE_H := 0.14
## Bandenmaße.
const RAIL_H := 0.16
const RAIL_W := 0.12
## Mitte des Bahnfelds (alle sechs Löcher liegen um z ≈ 2).
const COURSE_MID_Z := 2.0
## Innenradius des Deko-Kranzes — davor bleibt der Rasen frei für die Bahn.
const SCENERY_MIN_R := 4.6

## Kunstrasen der Bahn: deutlich heller und minziger als die Wiese, sonst
## verschwindet die Bahn im Rasen (der Filz ist nur 14 cm dick).
const FELT := Color(0.62, 0.92, 0.6)
const FELT_DARK := Color(0.54, 0.85, 0.54)
const RAIL_COLOR := Color(0.9, 0.77, 0.55)
## Wiese ringsum: satter und dunkler als der Filz.
const GRASS := Color(0.38, 0.62, 0.4)
const BALL_COLOR := Color(1.0, 0.99, 0.96)

var tune: Dictionary = {}
var course: Array[Dictionary] = []
var hole_index := 0
var strokes := 0
var score := 0
## Einloch-Serie ohne Aufgeben (nur Anzeige/Feel — Combo-Ton steigt mit).
var hole_streak := 0
var theta := 0.0
var ball := {"x": 0.0, "z": 0.0, "vx": 0.0, "vz": 0.0, "done": false}
var endless_state: Dictionary = {}
var phase := "aim"
var pause_left := 0.0
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

var _rng: GoobyRng
var _dragging := false
var _drag_from := Vector2.ZERO
var _drag_to := Vector2.ZERO
var _flash := 0.0
var _flash_text := ""
var _hole_label: Label
var _stroke_label: Label
var _hint_label: Label

var _stage: Stage3D
var _gooby: GoobyActor
var _sparks: Spark3D
var _dust: Spark3D
var _roll_dust: Spark3D
var _hole_root: Node3D
var _ball_node: Node3D
var _blades: Node3D
var _nougat: Node3D
var _cup_ring: MeshInstance3D
var _ring_t := 0.0
var _ring_scale := 1.0
## Versenk-Animation: Restzeit, in der der Ball sichtbar ins Loch sackt.
var _sink_t := 0.0
## Roll-Staub: Abklingzeit bis zum nächsten Puff hinter dem rollenden Ball.
var _roll_puff_t := 0.0


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = Logic.apply_difficulty(Logic.GOLF, ctx.difficulty)
	_rng = ctx.rng()
	course = Course.generate_course(func() -> float: return _rng.next(), tune)
	endless_state = Logic.create_endless_state()
	_reset_ball()
	_build_world()
	_build_hud()
	_build_hole()
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
		_stage.set_fov(46.0 if landscape else 42.0)
		_frame_hole()
	if _hole_label != null:
		_hole_label.position = Vector2(16.0, 10.0)
		_stroke_label.position = Vector2(16.0, 48.0)
		_hint_label.position = Vector2(view_size.x * 0.5 - 150.0, view_size.y - 52.0)
		_hint_label.size = Vector2(300.0, 40.0)
	queue_redraw()


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	_flash = maxf(0.0, _flash - delta)
	_stage.tick(delta)
	_gooby.tick(delta)
	_tick_cup_ring(delta)
	_tick_windup()
	_tick_roll_dust(delta)
	if phase == "pause":
		pause_left -= delta
		_sink_t = maxf(0.0, _sink_t - delta)
		_place_ball()
		if pause_left <= 0.0:
			_next_hole()
		queue_redraw()
		return
	if phase == "roll":
		_step_roll(delta)
	theta += PI * 2.0 * float(Logic.GOLF["WINDMILL_RPS"]) * delta
	_spin_windmill()
	_move_nougat()
	_place_ball()
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
		elif _dragging:
			_dragging = false
			_putt()
	elif event is InputEventScreenDrag and _dragging:
		_drag_to = event.position
		queue_redraw()


## Das gerade gespielte Loch.
func current_hole() -> Dictionary:
	return course[hole_index % course.size()]


## Par des aktuellen Lochs (Leicht spendiert bereits in der Bahn +1).
func current_par() -> int:
	return int(current_hole()["par"])


# ------------------------------------------------------------------ Aufbau


func _build_world() -> void:
	_stage = Stage3D.new()
	add_child(_stage)
	(
		_stage
		. build(
			{
				"sky_top": Color(0.32, 0.6, 0.93),
				"sky_horizon": Color(0.9, 0.95, 1.0),
				"ground_horizon": Color(0.63, 0.78, 0.5),
				"ground_bottom": Color(0.36, 0.54, 0.3),
				"fog_color": Color(0.87, 0.93, 0.86),
				"fog_from": 22.0,
				"fog_to": 74.0,
				"fog_density": 0.55,
				"sun_dir": Vector3(-0.42, -0.86, -0.3),
				"sun_color": Color(1.0, 0.95, 0.84),
				"sun_energy": 1.05,
				"ambient": 0.38,
				"ambient_color": Color(0.92, 0.9, 0.82),
				"sky_ambient": 0.4,
				# Belichtung gedrosselt (MP-E): mit 0.82 clippte der Mint-Filz
				# in ACES fast auf Weiß — die Bahn war ~40 Luma-Stufen zu hell.
				"exposure": 0.58,
				"fill_energy": 0.22,
				"glow": 0.22,
				"shadow_distance": 24.0,
				"fov": 44.0,
			}
		)
	)

	_stage.add_child(Props3D.ground(Vector2(70.0, 70.0), Props3D.flat(GRASS), -0.001))
	_build_scenery()

	_hole_root = Node3D.new()
	_stage.add_child(_hole_root)

	var ball_mat := Props3D.flat(BALL_COLOR, 0.45)
	_ball_node = Node3D.new()
	_ball_node.add_child(Props3D.sphere(float(Logic.GOLF["BALL_R"]), ball_mat))
	_ball_node.add_child(Props3D.blob_shadow(float(Logic.GOLF["BALL_R"]) * 2.2, 0.35))
	_stage.add_child(_ball_node)

	_gooby = GoobyActor.new()
	_stage.add_child(_gooby)
	_gooby.mount(1.05, PI)
	_gooby.hold(
		_build_putter(),
		"arm.R",
		Transform3D(Basis(Vector3.RIGHT, -1.15), Vector3(0.0, -0.08, 0.05))
	)

	_sparks = Spark3D.new()
	_stage.add_child(_sparks)
	_sparks.build({"color": Color(1.0, 0.92, 0.55), "amount": 22, "speed": Vector2(1.4, 3.4)})
	_dust = Spark3D.new()
	_stage.add_child(_dust)
	(
		_dust
		. build(
			{
				"color": Color(0.78, 0.92, 0.7, 0.9),
				"amount": 12,
				"speed": Vector2(0.6, 1.6),
				"size": Vector2(0.04, 0.1),
				"texture": "puff",
				"additive": false,
			}
		)
	)
	# Dauer-Emitter hinter dem rollenden Ball — macht Tempo SICHTBAR.
	_roll_dust = Spark3D.new()
	_stage.add_child(_roll_dust)
	(
		_roll_dust
		. build(
			{
				"color": Color(0.86, 0.97, 0.8, 0.7),
				"amount": 10,
				"speed": Vector2(0.2, 0.7),
				"size": Vector2(0.03, 0.07),
				"lifetime": 0.45,
				"texture": "puff",
				"additive": false,
				"explosiveness": 0.0,
			}
		)
	)


## Putter als Requisite in Goobys rechter Pfote (Maße im Rig-Raum).
func _build_putter() -> Node3D:
	var holder := Node3D.new()
	var shaft := Props3D.cylinder(0.018, 0.62, Props3D.flat(Color(0.86, 0.87, 0.9), 0.4))
	shaft.position.y = -0.31
	holder.add_child(shaft)
	var head := Props3D.box(Vector3(0.16, 0.06, 0.07), Props3D.flat(Color(0.62, 0.66, 0.72), 0.35))
	head.position = Vector3(0.05, -0.6, 0.0)
	holder.add_child(head)
	return holder


## Garten rundherum: Hecke, Bäume, Büsche, Blumen — alles als MultiMesh, damit
## die volle Kulisse nur eine Handvoll Draw-Calls kostet. Der Kranz beginnt
## erst hinter der längsten Bahn (Radius ≥ SCENERY_MIN_R), sonst wächst ein
## Busch mitten auf dem Filz.
func _build_scenery() -> void:
	_build_lawn_stripes()
	_build_hedge()
	_scatter(ASSETS + "tree_oak.glb", 3.7, 9, 10.8, 1.4, 1.0)
	_scatter(ASSETS + "tree_fat.glb", 3.2, 7, 11.9, 1.6, 1.15)
	_scatter(ASSETS + "tree_pineRoundA.glb", 4.1, 6, 12.8, 1.8, 1.3)
	_scatter(ASSETS + "plant_bushLarge.glb", 0.8, 11, 6.3, 1.4, 1.7)
	_scatter(ASSETS + "rock_smallA.glb", 0.4, 7, 7.1, 1.6, 2.3)
	_scatter(ASSETS + "grass_large.glb", 0.34, 26, 5.6, 2.6, 3.1)
	_scatter(ASSETS + "flower_redA.glb", 0.32, 13, 6.0, 2.0, 2.7)
	_scatter(ASSETS + "flower_yellowA.glb", 0.3, 13, 7.0, 1.9, 3.7)
	_scatter(ASSETS + "mushroom_red.glb", 0.24, 8, 8.0, 1.2, 4.3)
	var bench := Props3D.model(ASSETS + "bench.glb", 0.62)
	bench.position = _ring_at(-0.95, 5.8)
	bench.rotation.y = -0.95 + PI
	Props3D.repaint(bench, Props3D.NATURE)
	_stage.add_child(bench)
	# Tiefenpolitur (MP-E): aus der einsamen Bahn wird eine ANLAGE —
	# Nachbarbahnen, Zaun, Kiosk, Lichterkette, Trittsteine.
	Scenery.build(_stage)


## Gemähte Rasenbahnen: der Greenkeeper-Look kostet EINEN Draw-Call und nimmt
## der 70×70-Wiese die Leere — ohne ihn ist der Boden eine einzige Farbfläche.
func _build_lawn_stripes() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.4, 0.02, 70.0)
	mesh.material = Props3D.flat(GRASS.darkened(0.09))
	var poses: Array = []
	for i in 15:
		poses.append(Props3D.pose(Vector3(float(i - 7) * 4.8, 0.004, COURSE_MID_Z)))
	_stage.add_child(Props3D.swarm_mesh(mesh, poses, 40.0))


## Geschnittene Buchsbaumhecke als Platzgrenze — überlappende Quader, damit
## kein Spalt bleibt, und ein Draw-Call für den ganzen Ring.
func _build_hedge() -> void:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(2.3, 0.85, 0.95)
	mesh.material = Props3D.flat(Color(0.29, 0.53, 0.3))
	var poses: Array = []
	for i in 34:
		var a := TAU * float(i) / 34.0
		poses.append(Props3D.pose(_ring_at(a, 9.3, 0.38), -a, 1.0 + 0.07 * sin(float(i) * 2.3)))
	_stage.add_child(Props3D.swarm_mesh(mesh, poses, 30.0))


## Ein Modell im Kranz um die Bahnmitte verteilen. `jitter` streut den Radius,
## `phase` verdreht den Kranz gegen die anderen Sorten.
##
## Alles, was im Blickkorridor der Kamera landen würde, fällt weg — sonst
## parkt ein Findling formatfüllend vor der Bahn.
func _scatter(
	path: String, height: float, count: int, radius: float, jitter := 0.0, phase := 0.0
) -> void:
	var poses: Array = []
	for i in count:
		var a := TAU * (float(i) + phase) / float(count)
		var r := radius + jitter * sin(float(i) * 2.7 + phase)
		var at := _ring_at(a, r)
		if _in_camera_lane(at):
			continue
		var yaw := a * 1.7 + float(i)
		poses.append(Props3D.pose(at, yaw, 0.86 + 0.28 * absf(sin(float(i) * 1.9))))
	_stage.add_child(Props3D.swarm(Props3D.parts(path, height, Props3D.NATURE), poses))


## Freie Sichtschneise vor dem Abschlag (die Kamera steht bei kleinem z).
func _in_camera_lane(at: Vector3) -> bool:
	return at.z < -1.2 and absf(at.x) < 5.0


## Punkt auf dem Deko-Kranz um die Bahnmitte.
func _ring_at(angle: float, radius: float, y := 0.0) -> Vector3:
	return Vector3(sin(angle) * radius, y, COURSE_MID_Z + cos(angle) * radius)


## Bahn des aktuellen Lochs bauen (Kacheln, Banden, Hindernisse, Fahne).
func _build_hole() -> void:
	for child in _hole_root.get_children():
		child.queue_free()
	_blades = null
	_nougat = null
	_cup_ring = null
	var hole := current_hole()
	_build_tiles(hole)
	_build_rails(hole)
	_build_features(hole)
	_build_cup(hole)
	_place_gooby()
	_frame_hole()


func _build_tiles(hole: Dictionary) -> void:
	var light: Array = []
	var dark: Array = []
	var cells: Array = hole["cells"]
	for i in cells.size():
		var cell: Array = cells[i]
		var h := Course.height_at(hole, float(cell[0]), float(cell[1]))
		var at := Vector3(float(cell[0]), h - TILE_H * 0.5, float(cell[1]))
		var target: Array = light if i % 2 == 0 else dark
		target.append(Props3D.pose(at, 0.0, 1.0))
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0, TILE_H, 1.0)
	var felt_light := mesh.duplicate() as BoxMesh
	felt_light.material = Props3D.flat(FELT)
	var felt_dark := mesh.duplicate() as BoxMesh
	felt_dark.material = Props3D.flat(FELT_DARK)
	_hole_root.add_child(Props3D.swarm_mesh(felt_light, light))
	_hole_root.add_child(Props3D.swarm_mesh(felt_dark, dark))
	# Rampe: eine gekippte Platte schließt die Stufe zum Plateau.
	var ramp: Dictionary = hole.get("ramp", {})
	if not ramp.is_empty():
		var cell: Array = ramp["cell"]
		var wedge := Props3D.box(Vector3(1.0, TILE_H, 1.06), Props3D.flat(FELT.lightened(0.08)))
		wedge.position = Vector3(
			float(cell[0]), float(ramp["h"]) * 0.5 - TILE_H * 0.5, float(cell[1])
		)
		wedge.rotation.x = -atan(float(ramp["h"]))
		_hole_root.add_child(wedge)


## Banden auf allen Zellkanten ohne Nachbarzelle.
func _build_rails(hole: Dictionary) -> void:
	var cells: Dictionary = hole["cellSet"]
	var poses: Array = []
	for cell: Array in hole["cells"]:
		var cx := int(cell[0])
		var cz := int(cell[1])
		var h := Course.height_at(hole, float(cx), float(cz))
		for dir: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if cells.has("%d,%d" % [cx + dir.x, cz + dir.y]):
				continue
			var at := Vector3(
				float(cx) + dir.x * (0.5 - RAIL_W * 0.5),
				h + RAIL_H * 0.5 - TILE_H * 0.5,
				float(cz) + dir.y * (0.5 - RAIL_W * 0.5)
			)
			poses.append(Props3D.pose(at, 0.0 if dir.y != 0 else PI * 0.5, 1.0))
	var mesh := BoxMesh.new()
	mesh.size = Vector3(1.0 + RAIL_W, RAIL_H, RAIL_W)
	mesh.material = Props3D.flat(RAIL_COLOR, 0.8)
	_hole_root.add_child(Props3D.swarm_mesh(mesh, poses))


func _build_features(hole: Dictionary) -> void:
	var bump: Dictionary = hole.get("bump", {})
	if not bump.is_empty():
		var radius := float(Logic.GOLF["BUMP_R"])
		var dome := Props3D.sphere(radius, Props3D.flat(Color(0.6, 0.85, 0.58)))
		dome.scale.y = 0.55
		dome.position = Vector3(float(bump["x"]), -0.02, float(bump["z"]))
		_hole_root.add_child(dome)
	var tunnel: Dictionary = hole.get("tunnel", {})
	if not tunnel.is_empty():
		var arch := Props3D.raw(ASSETS + "tunnel-wide.glb", 1.0)
		arch.position = Vector3(float(tunnel["cell"][0]), 0.0, float(tunnel["cell"][1]))
		Props3D.tint(arch, Color(0.62, 0.5, 0.74))
		_hole_root.add_child(arch)
	var mill: Dictionary = hole.get("windmill", {})
	if not mill.is_empty():
		var tower := Props3D.raw(ASSETS + "windmill.glb", 1.0)
		tower.position = Vector3(float(mill["cellX"]), 0.0, float(mill["gateZ"]))
		_hole_root.add_child(tower)
		var found := tower.find_children("blades", "MeshInstance3D", true, false)
		if not found.is_empty():
			_blades = found[0] as Node3D
	var nougat: Dictionary = hole.get("nougat", {})
	if not nougat.is_empty():
		_nougat = Props3D.sphere(
			float(nougat["radius"]), Props3D.flat(Color(0.72, 0.45, 0.26), 0.6)
		)
		_hole_root.add_child(_nougat)


func _build_cup(hole: Dictionary) -> void:
	var cup: Dictionary = hole["hole"]
	var at := Vector3(
		float(cup["x"]), Course.height_at(hole, float(cup["x"]), float(cup["z"])), float(cup["z"])
	)
	var radius := float(tune["HOLE_R"])
	var pit := Props3D.cylinder(radius, 0.12, Props3D.flat(Color(0.09, 0.08, 0.08), 1.0))
	pit.position = at + Vector3(0.0, -0.05, 0.0)
	_hole_root.add_child(pit)
	var lip := Props3D.torus(radius * 1.12, 0.02, Props3D.flat(Color(0.94, 0.95, 0.9), 0.6))
	lip.rotation.x = -PI * 0.5
	lip.position = at + Vector3(0.0, 0.006, 0.0)
	_hole_root.add_child(lip)
	_cup_ring = Props3D.torus(radius, 0.03, Props3D.glow(Color(1.0, 0.85, 0.4), 2.4))
	_cup_ring.rotation.x = -PI * 0.5
	_cup_ring.position = at + Vector3(0.0, 0.02, 0.0)
	_cup_ring.visible = false
	_hole_root.add_child(_cup_ring)
	var flag := Props3D.raw(ASSETS + "flag-red.glb", 1.1)
	flag.position = at
	_hole_root.add_child(flag)


func _build_hud() -> void:
	_hole_label = Label.new()
	_hole_label.theme_type_variation = &"HeadlineLabel"
	_hole_label.add_theme_color_override("font_color", Color(1.0, 0.99, 0.94))
	_hole_label.add_theme_color_override("font_outline_color", Color(0.15, 0.22, 0.14, 0.8))
	_hole_label.add_theme_constant_override("outline_size", 6)
	add_child(_hole_label)
	_stroke_label = Label.new()
	_stroke_label.theme_type_variation = &"CaptionLabel"
	_stroke_label.add_theme_color_override("font_color", Color(0.98, 0.98, 0.9))
	_stroke_label.add_theme_color_override("font_outline_color", Color(0.15, 0.22, 0.14, 0.8))
	_stroke_label.add_theme_constant_override("outline_size", 5)
	add_child(_stroke_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.miniGolf.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_color_override("font_color", Color(0.96, 0.99, 0.94, 0.95))
	_hint_label.add_theme_color_override("font_outline_color", Color(0.15, 0.22, 0.14, 0.7))
	_hint_label.add_theme_constant_override("outline_size", 5)
	add_child(_hint_label)
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


# ------------------------------------------------------------------ Kamera


## Kamera auf das aktuelle Loch einstellen: die Bahnecken plus Fahnenspitze
## werden eingepasst. Hochkant blickt sie steiler von oben (die Bahn läuft
## dann senkrecht durchs Bild), quer legt sie sich flacher hin.
func _frame_hole() -> void:
	if _stage == null or course.is_empty():
		return
	var min_x := INF
	var max_x := -INF
	var min_z := INF
	var max_z := -INF
	for cell: Array in current_hole()["cells"]:
		min_x = minf(min_x, float(cell[0]) - 0.6)
		max_x = maxf(max_x, float(cell[0]) + 0.6)
		min_z = minf(min_z, float(cell[1]) - 0.9)
		max_z = maxf(max_z, float(cell[1]) + 0.7)
	var cup: Dictionary = current_hole()["hole"]
	var points: Array = [
		Vector3(min_x, 0.0, min_z),
		Vector3(max_x, 0.0, min_z),
		Vector3(min_x, 0.0, max_z),
		Vector3(max_x, 0.0, max_z),
		Vector3(float(cup["x"]), 1.15, float(cup["z"])),
	]
	# Gooby gehört mit ins Bild — er steht neben dem Abschlag und ist bei
	# schmalen Bahnen sonst der Erste, der aus dem Kader fällt.
	if _gooby != null:
		points.append(_gooby.position + Vector3(0.45, 1.25, 0.0))
		points.append(_gooby.position - Vector3(0.45, 0.0, 0.0))
	var center := Vector3((min_x + max_x) * 0.5, 0.25, (min_z + max_z) * 0.5)
	# Flacher Blick + etwas Luft: so stehen Hecke, Baumreihe und Himmel als
	# Kulisse hinter der Bahn statt außerhalb des Bildes.
	_stage.fit(points, center, 20.0 if landscape else 30.0, 180.0, 0.72)


func _reset_ball() -> void:
	var start: Dictionary = current_hole()["start"]
	ball = {"x": float(start["x"]), "z": float(start["z"]), "vx": 0.0, "vz": 0.0, "done": false}
	strokes = 0


func _place_ball() -> void:
	if _ball_node == null:
		return
	var hole := current_hole()
	if bool(ball.get("done", false)):
		_place_sinking_ball(hole)
		return
	var bx := float(ball["x"])
	var bz := float(ball["z"])
	var y := Course.height_at(hole, bx, bz) + float(Logic.GOLF["BALL_R"])
	var bump: Dictionary = hole.get("bump", {})
	if not bump.is_empty():
		var d := Vector2(bx - float(bump["x"]), bz - float(bump["z"])).length()
		var radius := float(Logic.GOLF["BUMP_R"])
		if d < radius:
			y += cos(d / radius * PI * 0.5) * radius * 0.5
	_ball_node.position = Vector3(bx, y, bz)
	_ball_node.scale = Vector3.ONE
	_ball_node.visible = true


## Der eingelochte Ball sackt SICHTBAR ins Loch (schrumpft und sinkt), statt
## im selben Frame hart zu verschwinden — der Treffer bekommt ein Nachbild.
func _place_sinking_ball(hole: Dictionary) -> void:
	if _sink_t <= 0.0:
		_ball_node.visible = false
		_ball_node.scale = Vector3.ONE
		return
	var cup: Dictionary = hole["hole"]
	var f := 1.0 - _sink_t / SINK_SEC
	var y := Course.height_at(hole, float(cup["x"]), float(cup["z"]))
	_ball_node.visible = true
	_ball_node.position = Vector3(
		float(cup["x"]), y + float(Logic.GOLF["BALL_R"]) - 0.17 * f, float(cup["z"])
	)
	_ball_node.scale = Vector3.ONE * (1.0 - 0.5 * f)


func _place_gooby() -> void:
	if _gooby == null:
		return
	var start: Dictionary = current_hole()["start"]
	_gooby.position = Vector3(float(start["x"]) + 0.88, 0.0, float(start["z"]) - 0.5)
	# Leicht zur Bahn eingedreht, aber noch zur Kamera hin — das Gesicht ist
	# die halbe Miete.
	_gooby.face(PI * 0.82)
	_gooby.play("idle")
	_gooby.set_mood("happy")


func _spin_windmill() -> void:
	if _blades == null:
		return
	var mill: Dictionary = current_hole().get("windmill", {})
	if mill.is_empty():
		return
	_blades.rotation.z = -(theta + float(mill["phase"]))


func _move_nougat() -> void:
	if _nougat == null:
		return
	var hole := current_hole()
	var nougat: Dictionary = hole["nougat"]
	_nougat.position = Vector3(
		Course.nougat_x_at(hole, theta), float(nougat["radius"]) * 0.8, float(nougat["z"])
	)


func _tick_cup_ring(delta: float) -> void:
	if _cup_ring == null:
		return
	if _ring_t <= 0.0:
		_cup_ring.visible = false
		return
	_ring_t = maxf(0.0, _ring_t - delta)
	var f := 1.0 - _ring_t / float(Logic.GOLF_JUICE["RING_LIFE_SEC"])
	_cup_ring.visible = true
	_cup_ring.scale = Vector3.ONE * (1.0 + f * _ring_scale)


## Zielspannung: Gooby lehnt sich beim Aufziehen zurück — die Schlagkraft ist
## an seiner Körperhaltung ablesbar, BEVOR der Ball losrollt.
func _tick_windup() -> void:
	if _gooby == null:
		return
	var lean := 0.0
	if _dragging and phase == "aim":
		var pull := (_drag_from - _drag_to).length()
		var power := Logic.power_from_drag(pull, view_size.x, view_size.y)
		lean = -WINDUP_LEAN * power / float(Logic.GOLF["MAX_POWER"])
	_gooby.rotation.z = lerpf(_gooby.rotation.z, lean, 0.25)


## Staubfahne hinter dem schnell rollenden Ball (Dauer-Emitter folgt dem Ball).
func _tick_roll_dust(delta: float) -> void:
	if _roll_dust == null:
		return
	_roll_puff_t = maxf(0.0, _roll_puff_t - delta)
	var speed := Vector2(float(ball["vx"]), float(ball["vz"])).length()
	var rolling := speed > 1.6 and not bool(ball.get("done", false))
	_roll_dust.position = Vector3(float(ball["x"]), 0.04, float(ball["z"]))
	_roll_dust.stream(rolling)


# ---------------------------------------------------------------- Spielzug


## Ziehrichtung auf die Bahnebene projizieren (Screen-to-World). Fällt auf die
## reine Bildschirmachse zurück, wenn der Strahl die Ebene nicht trifft.
func _pull_direction(pull: Vector2) -> Vector2:
	var from := _stage.plane_point(_drag_from, 0.0)
	var to := _stage.plane_point(_drag_to, 0.0)
	var world := Vector2(from.x - to.x, from.z - to.z)
	if world.length() < 0.001:
		return Vector2(pull.x, -pull.y).normalized()
	return world.normalized()


func _putt() -> void:
	var pull := _drag_from - _drag_to
	if pull.length() < 8.0:
		return
	var power := Logic.power_from_drag(pull.length(), view_size.x, view_size.y)
	if power <= 0.05:
		return
	var dir := _pull_direction(pull)
	ball["vx"] = dir.x * power
	ball["vz"] = dir.y * power
	strokes += 1
	phase = "roll"
	AudioDirector.try_play(self, "mg_good", 1.0 + 0.05 * (power / 6.5))
	_gooby.play_for("build_hammer", 0.7)
	# Der Durchschwung wächst mit der Schlagkraft — ein Ass-Putt sieht anders
	# aus als ein Zärtel-Putt.
	_gooby.swing(0.42, 30.0 + 28.0 * power / float(Logic.GOLF["MAX_POWER"]), Vector3.RIGHT)
	_gooby.emote("ecstatic", 0.6)
	_dust.burst(Vector3(float(ball["x"]), 0.02, float(ball["z"])))
	_stage.shake(0.02 + 0.03 * power / 6.5, 0.2)
	if ctx.juice != null:
		ctx.juice.shake(0.08 + 0.06 * power / 6.5)


func _step_roll(delta: float) -> void:
	var hole := current_hole()
	var events := Logic.step_ball(hole, ball, delta, theta, tune)
	for event in events:
		_on_event(event)
	if bool(ball.get("done", false)):
		_end_hole(true)
	elif Course.is_stopped(hole, ball):
		phase = "aim"
		if strokes >= int(tune["MAX_STROKES"]):
			_end_hole(false)


func _on_event(event: String) -> void:
	var at := Vector3(float(ball["x"]), float(Logic.GOLF["BALL_R"]), float(ball["z"]))
	match event:
		"bank":
			AudioDirector.try_play(self, "mg_junk", 1.15)
			_sparks.burst(at)
		"bump":
			AudioDirector.try_play(self, "mg_spill", 1.1)
			_dust.burst(at)
		"windmill":
			AudioDirector.try_play(self, "mg_junk", 0.8)
			_stage.shake(0.08, 0.3)
			_gooby.emote("scared", 0.9)
			if ctx.juice != null:
				ctx.juice.shake(0.2)
		"nougat":
			AudioDirector.try_play(self, "mg_spill", 0.9)
			_dust.burst(at)
		"holed":
			pass


func _end_hole(holed: bool) -> void:
	var par := current_par()
	var taken := strokes if holed else int(tune["MAX_STROKES"]) + 1
	var points := Logic.hole_score(taken, par, tune)
	score += points
	var cup: Dictionary = current_hole()["hole"]
	var world := Vector3(float(cup["x"]), 0.25, float(cup["z"]))
	var pos := _stage.to_screen(world)
	_ring_t = float(Logic.GOLF_JUICE["RING_LIFE_SEC"])
	_ring_scale = float(Logic.GOLF_JUICE["RING_SCALE_SINK"])
	if holed:
		_sink_t = SINK_SEC
	if holed and taken == 1:
		hole_streak += 1
		_ring_scale = float(Logic.GOLF_JUICE["RING_SCALE_ACE"])
		_flash_text = I18nService.t("mg.miniGolf.ace")
		_sparks.burst(world)
		_stage.pulse_glow(1.0)
		AudioDirector.try_play(self, "mg_golden", FeelSfx.combo_pitch(hole_streak))
		_gooby.play("celebrate")
		_gooby.hop(0.6, 0.4)
		_gooby.emote("ecstatic", 1.8)
		if ctx.juice != null:
			# Ass = DER Moment des Spiels: Zeitlupe + Goldblitz + Konfetti.
			ctx.juice.hit_freeze(90)
			ctx.juice.bloom_pulse(1.0)
			ctx.juice.win_moment()
			ctx.juice.overlay_ring(pos, Color(1.0, 0.85, 0.35), 100.0)
	elif holed:
		hole_streak += 1
		_flash_text = "+%d" % points
		_sparks.burst(world)
		_stage.pulse_glow(0.5)
		# Einloch-Serie unter Par klettert hörbar.
		AudioDirector.try_play(
			self,
			"mg_perfect" if taken <= par else "mg_good",
			FeelSfx.combo_pitch(hole_streak) if taken <= par else 1.0
		)
		_gooby.play("celebrate")
		_gooby.emote("ecstatic", 1.4)
		if ctx.juice != null:
			ctx.juice.bloom_pulse(0.5)
			ctx.juice.overlay_ring(pos, Color(1.0, 0.85, 0.35), 64.0)
			if hole_streak >= 2:
				ctx.juice.show_combo(hole_streak)
	else:
		hole_streak = 0
		_flash_text = I18nService.t("mg.miniGolf.gave_up")
		AudioDirector.try_play(self, "mg_spill")
		_gooby.emote("sad", 1.6)
		if ctx.juice != null:
			ctx.juice.sfx("game_miss")
			ctx.juice.show_combo(0)
	_flash = 1.2
	if ctx.juice != null:
		ctx.juice.float_text(pos, _flash_text, Color(1.0, 0.72, 0.2))
	ctx.report_score(score, points)
	if bool(tune["ENDLESS"]) and Logic.record_hole(endless_state, taken, par):
		_finish()
		return
	phase = "pause"
	pause_left = HOLE_PAUSE_SEC


func _next_hole() -> void:
	hole_index += 1
	if not bool(tune["ENDLESS"]) and hole_index >= course.size():
		_finish()
		return
	_reset_ball()
	_build_hole()
	phase = "aim"


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	ctx.report_end({"score": score, "holes": hole_index + 1})


func _update_labels() -> void:
	if bool(tune["ENDLESS"]):
		_hole_label.text = I18nService.t(
			"mg.miniGolf.over_par",
			{"n": int(endless_state["overPar"]), "max": int(endless_state["limit"])}
		)
	else:
		_hole_label.text = I18nService.t(
			"mg.miniGolf.hole", {"n": mini(hole_index + 1, course.size()), "max": course.size()}
		)
	_stroke_label.text = I18nService.t("mg.miniGolf.strokes", {"n": strokes, "par": current_par()})


# ------------------------------------------------------------- Zielhilfe 2D


## Nur noch Zielhilfe und Trefferbanner werden gezeichnet — die Welt selbst
## ist 3D und liegt dahinter.
func _draw() -> void:
	_draw_aim()
	_draw_flash()


func _draw_aim() -> void:
	if not _dragging or phase != "aim":
		return
	var pull := _drag_from - _drag_to
	if pull.length() < 4.0:
		return
	var power := Logic.power_from_drag(pull.length(), view_size.x, view_size.y)
	var dir := _pull_direction(pull)
	var reach := Logic.roll_distance(power)
	var hole := current_hole()
	var ball_world := Vector3(
		float(ball["x"]),
		Course.height_at(hole, float(ball["x"]), float(ball["z"])) + 0.02,
		float(ball["z"])
	)
	var pos := _stage.to_screen(ball_world)
	draw_line(pos, pos - (_drag_from - _drag_to) * 0.55, Color(0.95, 0.45, 0.66, 0.5), 4.0)
	for i in PREVIEW_DOTS:
		var f := float(i + 1) / PREVIEW_DOTS
		var world := ball_world + Vector3(dir.x, 0.0, dir.y) * reach * f
		world.y = Course.height_at(hole, world.x, world.z) + 0.05
		var dot := _stage.to_screen(world)
		draw_circle(dot, 4.5 - 2.0 * f, Color(1.0, 0.98, 0.9, 0.85 - 0.5 * f))
	var frac := power / float(Logic.GOLF["MAX_POWER"])
	draw_arc(
		pos,
		32.0,
		-PI * 0.5,
		-PI * 0.5 + TAU * frac,
		24,
		Color(1.0, 0.78, 0.3).lerp(Color(0.95, 0.35, 0.4), frac),
		5.0
	)


func _draw_flash() -> void:
	if _flash <= 0.0 or _flash_text.is_empty():
		return
	var alpha := clampf(_flash * 1.4, 0.0, 1.0)
	draw_string(
		ThemeService.font(800),
		Vector2(0.0, view_size.y * 0.2),
		_flash_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		view_size.x,
		32,
		Color(0.99, 0.86, 0.45, alpha)
	)
