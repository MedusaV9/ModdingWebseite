extends MinigameBase
## Angelteich (fishingPond) — Spiel-Szene. Alle MECHANIK-Zahlen aus
## FishingPondLogic (zahlengleich zum Web): 90 s, HALTEN senkt den Haken,
## LOSLASSEN angelt den nächsten Schwimmer im Fangradius, S/M/L = 2/3/5,
## Stiefel −3, große Fische brauchen 5 Wackel-Taps in 2 s.
##
## ECHTES 3D (Agent 3D-A, Rückbau): der Teich ist ein aufgeschnittenes
## Dioramen-Ufer — vorn ist die Erde abgetragen, sodass man wie durch eine
## Aquarienscheibe ins Wasser sieht, während Grasnarbe, Steg, Schilf und
## Baumreihe in echter Perspektive nach hinten weglaufen. Gooby sitzt als
## ECHTES Rig auf dem Steg, hält die Rute (BoneAttachment an `arm.R`), reißt
## beim Anhieb hoch und jubelt beim Fang.
##
## Warum der Querschnitt-Blick bleibt: die Logik rechnet in (x, Tiefe) und
## kennt kein z. Eine Kamera von oben würde die Tiefe wegstauchen und den
## Fangradius unlesbar machen. Die flache Kamera zeigt die Tiefe 1:1 — und
## Steg, Boot, Ufer und Bäume machen daraus trotzdem eine räumliche Szene.
##
## Der MinigameBase-Vertrag bleibt: Wurzel ist Node2D, die 3D-Welt hängt
## darunter, HUD/Einholbalken/Fangtext sind CanvasItems obenauf.

const Logic := preload("res://scripts/minigames/games/fishing_pond/fishing_pond_logic.gd")
const Stage3D := preload("res://scripts/minigames/games/_3da_stage/stage3d.gd")
const Props3D := preload("res://scripts/minigames/games/_3da_stage/props3d.gd")
const GoobyActor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Spark3D := preload("res://scripts/minigames/games/_3da_stage/spark3d.gd")

const ASSETS := "res://assets/minigames/fishing_pond/"

## Wie lange ein Fang-Text stehen bleibt (s).
const FLASH_SEC := 1.0
## Tiefenebene der Schwimmer und des Hakens (hinter der Wasserscheibe).
const SWIM_Z := -0.35
## Innenmaße des Beckens (Logik: POND_HALF_W 1.8, MAX_DEPTH 3.9).
const POOL_HALF_W := 2.15
const POOL_FRONT_Z := 1.15
const POOL_BACK_Z := -1.8
const POOL_FLOOR_Y := -4.4
## Oberkante der Grasnarbe (die Wasserlinie ist y = 0).
const BANK_Y := 0.26
## Steghöhe über dem Wasser.
const DECK_Y := 0.44
## Rutenspitze (Weltpunkt), von dort hängt die Schnur senkrecht zum Haken.
const ROD_TIP := Vector3(0.46, 1.52, 0.04)
## Goobys Pfote am Rutengriff (Weltpunkt).
const ROD_GRIP := Vector3(1.6, 0.82, 0.1)
## Rohlänge von `fish.glb` entlang seiner z-Achse (Kenney Food Kit).
const FISH_RAW_LEN := 0.62
const FISH_RAW_HEIGHT := 0.32

const WATER := Color(0.16, 0.42, 0.52)
const GRASS := Color(0.36, 0.53, 0.36)
const SOIL := Color(0.42, 0.31, 0.26)
const WOOD := Color(0.66, 0.47, 0.31)

var tune: Dictionary = {}
var rng: GoobyRng
var score := 0
var elapsed := 0.0
var hook_depth := 0.0
var phase := "idle"
var fish: Array[Dictionary] = []
var hooked: Dictionary = {}
var reel_taps := 0
var reel_elapsed := 0.0
var since_boot := 0.0
var endless_state: Dictionary = {}
var caught_species: Array[String] = []
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

var _stream: Callable
var _respawn: Array[float] = []
var _flash := 0.0
var _flash_text := ""
var _flash_color := Color.WHITE
var _time_label: Label
var _score_label: Label
var _hint_label: Label

var _stage: Stage3D
var _gooby: GoobyActor
var _splash: Spark3D
var _sparks: Spark3D
var _swimmers: Node3D
var _bobber: Node3D
var _hook: Node3D
var _catch_ring: MeshInstance3D
var _line_rod: MeshInstance3D
var _line_deep: MeshInstance3D
var _hooked_node: Node3D
var _surface: MeshInstance3D


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = Logic.apply_difficulty(Logic.FISHING, ctx.difficulty)
	rng = ctx.rng()
	_stream = func() -> float: return rng.next()
	endless_state = Logic.create_endless_state()
	_build_world()
	for i in int(tune["FISH_COUNT"]):
		fish.append(_spawn_fish())
	_build_hud()
	_fit_viewport()
	if is_inside_tree():
		get_viewport().size_changed.connect(_fit_viewport)


func end() -> void:
	super.end()
	finished = true


## Pflicht-Layouthook: beide Orientierungen laufen über DIESE Funktion.
## Hochkant rückt die Kamera näher heran und blickt etwas flacher, damit das
## schmale Bild vom Becken statt vom Ufer gefüllt wird.
func apply_view(size: Vector2) -> void:
	if size.x > 1.0 and size.y > 1.0:
		view_size = size
	landscape = view_size.x > view_size.y
	position = Vector2.ZERO
	if _stage != null:
		_stage.apply_size(view_size)
		_stage.set_fov(40.0 if landscape else 36.0)
		_frame_pond()
	if _time_label != null:
		_time_label.position = Vector2(16.0, 10.0)
		_score_label.position = Vector2(16.0, 48.0)
		_hint_label.position = Vector2(view_size.x * 0.5 - 150.0, view_size.y - 52.0)
		_hint_label.size = Vector2(300.0, 40.0)
	queue_redraw()


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	elapsed += delta
	since_boot += delta
	_flash = maxf(0.0, _flash - delta)
	_stage.tick(delta)
	_gooby.tick(delta)
	_swim(delta)
	_step_respawns(delta)
	_step_hook(delta)
	if not bool(tune["ENDLESS"]) and elapsed >= float(tune["DURATION_SEC"]):
		_finish()
		return
	_place_swimmers()
	_place_tackle()
	_update_labels()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished:
		return
	if not (event is InputEventScreenTouch):
		return
	if phase == "reel":
		if event.pressed:
			reel_taps += 1
			_gooby.swing(0.16, 20.0, Vector3.RIGHT)
			AudioDirector.try_play(self, "mg_combo", 1.0 + 0.05 * reel_taps)
		return
	if event.pressed and phase == "idle":
		phase = "lower"
		_gooby.play_for("build_hammer", 0.5, "sit")
	elif not event.pressed and phase == "lower":
		_release()


## Sichtbare Wassertiefe in Weltmetern (Rand oben/unten eingerechnet).
func pond_depth_span() -> float:
	return float(tune["MAX_DEPTH"]) + 0.35


## Hängt gerade etwas an der Angel? (Screenshot-Treiber, Autoplay-Sonden.)
func has_catch() -> bool:
	return not hooked.is_empty()


# ------------------------------------------------------------------ Aufbau


func _build_world() -> void:
	_stage = Stage3D.new()
	add_child(_stage)
	# Abenddämmerung wie in der Web-Fassung: violetter Zenit, oranger Horizont,
	# tief stehende warme Sonne. Der Glow trägt Sonnenscheibe und Glühwürmchen.
	(
		_stage
		. build(
			{
				"sky_top": Color(0.19, 0.16, 0.36),
				"sky_horizon": Color(0.97, 0.6, 0.4),
				"ground_horizon": Color(0.72, 0.47, 0.47),
				"ground_bottom": Color(0.5, 0.33, 0.38),
				"sky_energy": 0.85,
				"fog_color": Color(0.72, 0.47, 0.47),
				"fog_from": 12.0,
				"fog_to": 46.0,
				"fog_density": 0.85,
				"sun_dir": Vector3(0.5, -0.24, -0.83),
				"sun_color": Color(1.0, 0.72, 0.45),
				"sun_energy": 1.5,
				"ambient": 0.5,
				"ambient_color": Color(0.72, 0.62, 0.72),
				"sky_ambient": 0.5,
				"exposure": 0.9,
				"white": 2.6,
				"fill_color": Color(0.52, 0.55, 0.88),
				"fill_energy": 0.3,
				"glow": 0.42,
				"glow_threshold": 0.78,
				"shadows": false,
				"fov": 40.0,
			}
		)
	)
	_build_banks()
	_build_water()
	_build_shore()
	_build_deck()
	_build_tackle()
	_swimmers = Node3D.new()
	_stage.add_child(_swimmers)
	_build_gooby()
	_build_sparks()


## Ufermasse: drei große Erdblöcke mit Grasnarbe, vorn aufgeschnitten. Das
## Becken ist die Kerbe dazwischen — seine Innenflächen sind zugleich die
## Beckenwände, die man durch das Wasser sieht.
func _build_banks() -> void:
	var soil := Props3D.flat(SOIL)
	var grass := Props3D.flat(GRASS)
	# Tief genug, dass die Schnittkante den unteren Bildrand IMMER füllt —
	# hochkant bleibt sonst ein schwarzer Streifen unter dem Becken stehen.
	var depth := BANK_Y + 14.0
	var mid := BANK_Y - depth * 0.5
	# Vor der Schnittkante darf NICHTS stehen: die Kamera liegt fast auf
	# Grasnarbenhöhe, jedes Stück Land davor würde das Becken verdecken.
	var side_len := POOL_FRONT_Z + 26.0
	var side_mid := POOL_FRONT_Z - side_len * 0.5
	for sign_x: float in [-1.0, 1.0]:
		var at := Vector3(sign_x * (POOL_HALF_W + 14.0), mid, side_mid)
		_stage.add_child(Props3D.box(Vector3(28.0, depth, side_len), soil, at))
		_stage.add_child(
			Props3D.box(
				Vector3(28.0, 0.16, side_len), grass, Vector3(at.x, BANK_Y - 0.07, side_mid)
			)
		)
	_build_strata()
	var back_len := 88.0
	var back_mid := POOL_BACK_Z - back_len * 0.5
	_stage.add_child(Props3D.box(Vector3(90.0, depth, back_len), soil, Vector3(0.0, mid, back_mid)))
	_stage.add_child(
		Props3D.box(Vector3(90.0, 0.16, back_len), grass, Vector3(0.0, BANK_Y - 0.07, back_mid))
	)
	# Beckensohle aus hellem Sand — sie gibt der Tiefe einen Boden.
	var floor_z := (POOL_FRONT_Z + POOL_BACK_Z) * 0.5
	_stage.add_child(
		Props3D.box(
			Vector3(POOL_HALF_W * 2.0, 0.4, POOL_FRONT_Z - POOL_BACK_Z),
			Props3D.flat(Color(0.55, 0.47, 0.36)),
			Vector3(0.0, POOL_FLOOR_Y - 0.2, floor_z)
		)
	)


## Erdschichten auf der Schnittfläche. Eine nackte Wand ist im Querformat die
## halbe Bildfläche; die Bänder machen daraus einen Bodenaufschluss mit
## Humus, Lehm, Sand und Kiesel — und geben dem Ausschnitt Maßstab.
func _build_strata() -> void:
	var bands := [
		{"y": 0.02, "h": 0.36, "c": Color(0.34, 0.24, 0.2)},
		{"y": -0.7, "h": 1.1, "c": Color(0.5, 0.35, 0.28)},
		{"y": -2.1, "h": 1.7, "c": Color(0.44, 0.32, 0.3)},
		{"y": -3.9, "h": 1.9, "c": Color(0.56, 0.44, 0.35)},
		{"y": -7.0, "h": 4.4, "c": Color(0.35, 0.29, 0.32)},
	]
	for band: Dictionary in bands:
		var mesh := BoxMesh.new()
		mesh.size = Vector3(26.0, float(band["h"]), 0.06)
		mesh.material = Props3D.flat(band["c"])
		var poses: Array = []
		for sign_x: float in [-1.0, 1.0]:
			poses.append(
				Props3D.pose(
					Vector3(sign_x * (POOL_HALF_W + 13.0), float(band["y"]), POOL_FRONT_Z + 0.02)
				)
			)
		_stage.add_child(Props3D.swarm_mesh(mesh, poses, 8.0))


## Wasser: Spiegelfläche oben + Schnittscheibe vorn. Beide sind durchsichtig,
## die Scheibe färbt alles dahinter teichgrün ein — genau der Trick, mit dem
## die Web-Fassung ihren Querschnitt baut, hier aber vor echter Geometrie.
func _build_water() -> void:
	var floor_z := (POOL_FRONT_Z + POOL_BACK_Z) * 0.5
	var span := POOL_FRONT_Z - POOL_BACK_Z
	var top := Props3D.glass(Color(0.44, 0.76, 0.82, 0.42))
	top.emission_enabled = true
	top.emission = Color(0.95, 0.62, 0.42)
	top.emission_energy_multiplier = 0.35
	_surface = Props3D.ground(Vector2(POOL_HALF_W * 2.0, span), top, 0.0)
	_surface.position.z = floor_z
	_stage.add_child(_surface)
	var pane := Props3D.box(
		Vector3(POOL_HALF_W * 2.0, -POOL_FLOOR_Y, 0.02),
		Props3D.glass(Color(0.2, 0.5, 0.58, 0.44)),
		Vector3(0.0, POOL_FLOOR_Y * 0.5, POOL_FRONT_Z)
	)
	pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage.add_child(pane)
	# Zweite Scheibe HINTER den Fischen: sie färbt nur die Beckenrückwand ein
	# und erzeugt so das Tiefengefälle, das eine einzelne Scheibe nicht kann.
	var murk := Props3D.box(
		Vector3(POOL_HALF_W * 2.0, -POOL_FLOOR_Y, 0.02),
		Props3D.glass(Color(0.1, 0.3, 0.4, 0.5)),
		Vector3(0.0, POOL_FLOOR_Y * 0.5, POOL_BACK_Z + 0.5)
	)
	murk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage.add_child(murk)
	# Heller Saum auf der Wasserlinie — er trennt Luft und Wasser sichtbar.
	_stage.add_child(
		Props3D.box(
			Vector3(POOL_HALF_W * 2.0, 0.028, 0.05),
			Props3D.glow(Color(1.0, 0.78, 0.55), 0.9),
			Vector3(0.0, 0.0, POOL_FRONT_Z)
		)
	)
	_build_underwater()


## Beckengrund: Steine und Wasserpflanzen als Massenware (ein Draw-Call je
## Sorte) — sie geben der Tiefe Maßstab und verstecken die nackte Sohle.
func _build_underwater() -> void:
	var rocks: Array = []
	var weeds: Array = []
	for i in 9:
		var x := -POOL_HALF_W + 0.35 + 3.6 * float(i) / 8.0
		var z := POOL_BACK_Z + 0.4 + 1.9 * absf(sin(float(i) * 2.3))
		rocks.append(Props3D.pose(Vector3(x, POOL_FLOOR_Y, z), float(i) * 1.7, 0.9))
		if i % 2 == 0:
			weeds.append(Props3D.pose(Vector3(x + 0.2, POOL_FLOOR_Y, z - 0.3), float(i), 1.4))
	_stage.add_child(Props3D.swarm(Props3D.parts(ASSETS + "rock_smallA.glb", 0.3), rocks))
	_stage.add_child(
		Props3D.swarm(
			Props3D.parts(ASSETS + "grass_large.glb", 0.55, {"grass": Color(0.24, 0.5, 0.4)}), weeds
		)
	)


## Uferbewuchs: Schilfgürtel, Baumreihe, Büsche, Steine, Pilze — und das
## Ruderboot am linken Ufer. Alles hinter der Beckenkante.
func _build_shore() -> void:
	# Zwei Sperrzonen: das Becken selbst (nichts wächst im Wasser) und ALLES
	# vor der Beckenkante — dort steht die Kamera. Ohne die zweite Regel
	# pflanzt der Kranz der großen Radien Bäume direkt vors Objektiv.
	var bank := func(at: Vector3) -> bool:
		if at.z > POOL_FRONT_Z + 1.4:
			return true
		return absf(at.x) < POOL_HALF_W + 0.5 and at.z > POOL_BACK_Z - 0.5
	var behind := func(at: Vector3) -> bool: return at.z > POOL_BACK_Z - 0.6
	var center := Vector3(0.0, BANK_Y, POOL_BACK_Z - 0.4)
	_stage.add_child(
		Props3D.scatter(ASSETS + "grass_large.glb", 0.55, 26, 3.3, center, 0.7, 0.3, bank)
	)
	_stage.add_child(
		Props3D.scatter(ASSETS + "plant_bushLarge.glb", 0.8, 12, 5.2, center, 0.9, 1.4, bank)
	)
	_stage.add_child(
		Props3D.scatter(ASSETS + "tree_default.glb", 3.6, 9, 8.6, center, 1.4, 0.6, behind)
	)
	_stage.add_child(
		Props3D.scatter(ASSETS + "tree_pineRoundA.glb", 4.4, 8, 11.0, center, 1.8, 2.2, behind)
	)
	_stage.add_child(
		Props3D.scatter(ASSETS + "tree_fat.glb", 3.2, 7, 14.5, center, 2.1, 1.1, behind)
	)
	_stage.add_child(
		Props3D.scatter(ASSETS + "rock_largeA.glb", 0.62, 7, 4.4, center, 0.8, 2.8, bank)
	)
	_stage.add_child(
		Props3D.scatter(ASSETS + "mushroom_red.glb", 0.26, 8, 4.0, center, 0.7, 3.5, bank)
	)
	var boat := Props3D.model(ASSETS + "boat-row-small.glb", 0.46)
	boat.position = Vector3(-4.1, BANK_Y - 0.05, POOL_FRONT_Z - 0.4)
	boat.rotation.y = -0.5
	Props3D.tint(boat, Color(0.78, 0.55, 0.36))
	_stage.add_child(boat)
	_build_lilies()
	# Tief stehende Abendsonne hinter der Baumreihe (Web: sun disc + glow).
	var sun := Props3D.halo(3.4, Color(1.0, 0.66, 0.36, 0.85))
	sun.position = Vector3(-9.0, 3.4, POOL_BACK_Z - 24.0)
	_stage.add_child(sun)
	var bridge := Props3D.model(ASSETS + "bridge_wood.glb", 0.5)
	bridge.position = Vector3(-3.4, BANK_Y, POOL_BACK_Z - 1.2)
	bridge.scale = Vector3(1.6, 1.0, 1.6)
	Props3D.repaint(bridge, Props3D.NATURE)
	_stage.add_child(bridge)


## Seerosen auf dem Wasser — sie geben der Spiegelfläche eine Oberfläche, an
## der man sie überhaupt als Wasser erkennt (eine leere Glasplatte tut das
## nicht). Sie liegen bewusst LINKS des Hakens und stören das Auswerfen nicht.
func _build_lilies() -> void:
	var pad := CylinderMesh.new()
	pad.top_radius = 0.19
	pad.bottom_radius = 0.19
	pad.height = 0.025
	pad.radial_segments = 10
	pad.rings = 1
	pad.material = Props3D.flat(Color(0.33, 0.56, 0.35), 0.85)
	var pads: Array = []
	var spots := [
		Vector3(-1.62, 0.012, 0.45),
		Vector3(-1.15, 0.012, -0.35),
		Vector3(-1.85, 0.012, -0.95),
		Vector3(1.42, 0.012, -1.15),
	]
	for i in spots.size():
		pads.append(Props3D.pose(spots[i], float(i) * 1.3, 0.8 + 0.35 * float(i % 2)))
	_stage.add_child(Props3D.swarm_mesh(pad, pads, 3.0))
	var bloom := Props3D.sphere(0.075, Props3D.glow(Color(0.98, 0.7, 0.82), 0.5))
	bloom.position = spots[0] + Vector3(0.05, 0.05, 0.0)
	_stage.add_child(bloom)


## Anglersteg: Bohlen über der Wasserkante, zwei Pfähle ins Wasser.
func _build_deck() -> void:
	var wood := Props3D.flat(WOOD, 0.85)
	var plank := BoxMesh.new()
	plank.size = Vector3(1.5, 0.07, 0.22)
	plank.material = wood
	var poses: Array = []
	for i in 6:
		poses.append(Props3D.pose(Vector3(1.72, DECK_Y, 0.62 - float(i) * 0.28)))
	_stage.add_child(Props3D.swarm_mesh(plank, poses, 4.0))
	_stage.add_child(
		Props3D.box(
			Vector3(1.58, 0.09, 1.78),
			Props3D.flat(WOOD.darkened(0.28), 0.9),
			Vector3(1.72, DECK_Y - 0.09, -0.09)
		)
	)
	for z: float in [0.5, -0.66]:
		_stage.add_child(
			Props3D.cylinder(
				0.08, 1.5, Props3D.flat(WOOD.darkened(0.4), 0.95), Vector3(1.12, DECK_Y - 0.82, z)
			)
		)


## Schwimmer, Haken, Fangkreis und die zwei Schnurstücke (Rute → Schwimmer,
## Schwimmer → Haken). Die Schnur ist echte Geometrie, damit sie im Wasser
## gebrochen wirkt statt als 2D-Strich über der Szene zu liegen.
func _build_tackle() -> void:
	_bobber = Node3D.new()
	var top := Props3D.sphere(0.075, Props3D.flat(Color(0.91, 0.33, 0.18), 0.5))
	top.position.y = 0.03
	_bobber.add_child(top)
	_bobber.add_child(Props3D.sphere(0.06, Props3D.flat(Color(1.0, 0.96, 0.92), 0.5)))
	_stage.add_child(_bobber)

	_hook = Node3D.new()
	var shank := Props3D.cylinder(0.012, 0.13, Props3D.flat(Color(0.82, 0.85, 0.92), 0.3))
	_hook.add_child(shank)
	var barb := Props3D.torus(0.045, 0.011, Props3D.flat(Color(0.82, 0.85, 0.92), 0.3))
	barb.rotation.x = PI * 0.5
	barb.position.y = -0.1
	_hook.add_child(barb)
	_stage.add_child(_hook)

	_catch_ring = Props3D.torus(
		float(tune["CATCH_RADIUS"]), 0.018, Props3D.glow(Color(0.72, 0.95, 1.0), 1.6)
	)
	_catch_ring.rotation.x = PI * 0.5
	_stage.add_child(_catch_ring)

	var line_mat := Props3D.flat(Color(0.94, 0.92, 0.84), 0.4)
	_line_rod = Props3D.cylinder(0.008, 1.0, line_mat)
	_line_rod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage.add_child(_line_rod)
	_line_deep = Props3D.cylinder(0.008, 1.0, line_mat)
	_line_deep.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_stage.add_child(_line_deep)


func _build_gooby() -> void:
	_gooby = GoobyActor.new()
	_stage.add_child(_gooby)
	_gooby.position = Vector3(1.78, DECK_Y, -0.05)
	# Dreiviertelprofil: er schaut zur Schnur (−x) und bleibt der Kamera
	# trotzdem zugewandt — reines Profil würde das Gesicht verstecken.
	_gooby.mount(1.05, -0.95, "sit")
	_gooby.set_mood("happy")
	# Die Rute wird als STARRE Requisite zwischen Pfote und Spitze gespannt
	# (siehe GoobyActor.attach): so trifft die Spitze garantiert den Punkt, an
	# dem die Schnur hängt — eine Knochenmontage verdreht sie je nach Clip.
	var rod := Props3D.cylinder(0.024, 1.0, Props3D.flat(Color(0.45, 0.29, 0.18), 0.7))
	_gooby.attach(rod)
	_stretch(rod, ROD_GRIP - _gooby.position, ROD_TIP - _gooby.position)
	var reel := Props3D.cylinder(0.055, 0.06, Props3D.flat(Color(0.85, 0.84, 0.88), 0.4))
	reel.rotation.z = PI * 0.5
	reel.position = ROD_GRIP - _gooby.position + Vector3(-0.1, 0.09, 0.0)
	_gooby.attach(reel)


func _build_sparks() -> void:
	_splash = Spark3D.new()
	_stage.add_child(_splash)
	(
		_splash
		. build(
			{
				"color": Color(0.78, 0.94, 1.0),
				"amount": 22,
				"speed": Vector2(1.0, 2.4),
				"gravity": Vector3(0.0, -5.0, 0.0),
				"size": Vector2(0.05, 0.13),
				"texture": "puff",
				"additive": false,
				"lifetime": 0.7,
			}
		)
	)
	_sparks = Spark3D.new()
	_stage.add_child(_sparks)
	(
		_sparks
		. build(
			{
				"color": Color(1.0, 0.88, 0.5),
				"amount": 26,
				"speed": Vector2(1.4, 3.2),
				"lifetime": 0.9,
			}
		)
	)


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	add_child(_time_label)
	_score_label = Label.new()
	_score_label.theme_type_variation = &"CaptionLabel"
	add_child(_score_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.fishingPond.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint_label)
	# Die Dämmerungskulisse ist dunkel — Theme-Schriftfarben wären es auch.
	for label: Label in [_time_label, _score_label, _hint_label]:
		label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.9))
		label.add_theme_color_override("font_outline_color", Color(0.14, 0.1, 0.2, 0.85))
		label.add_theme_constant_override("outline_size", 6)
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


## Kamera fast waagerecht vor die Schnittkante — Becken, Wasserlinie, Steg
## und Gooby sollen zugleich im Bild stehen. Der Rest rechnet `fit()` aus.
func _frame_pond() -> void:
	if _stage == null or _gooby == null:
		return
	var half := float(tune["POND_HALF_W"]) + 0.45
	# Der Punkt ÜBER der Baumreihe hält den Kader oben offen. Ohne ihn wandert
	# der freie Platz des Hochformats unter die Beckensohle und man fotografiert
	# vor allem Erdreich.
	var points: Array = [
		Vector3(-half, 0.1, SWIM_Z),
		Vector3(half, 0.1, SWIM_Z),
		Vector3(0.0, -float(tune["MAX_DEPTH"]) - 0.35, SWIM_Z),
		Vector3(_gooby.position.x + 0.5, DECK_Y + 1.15, 0.0),
		Vector3(0.0, 2.5 if landscape else 4.4, POOL_BACK_Z - 7.0),
	]
	var center := Vector3(0.3, -0.9 if landscape else -0.5, SWIM_Z)
	_stage.fit(points, center, 9.0 if landscape else 6.5, 0.0, 0.9)


# ---------------------------------------------------------------- Schwimmer


## Neuen Schwimmer würfeln (Art, Tiefe, Richtung, Tempo).
func _spawn_fish() -> Dictionary:
	var half := float(tune["POND_HALF_W"])
	if Logic.should_spawn_boot(_stream, since_boot, tune):
		since_boot = 0.0
		var boot := {
			"kind": "boot",
			"species": "boot",
			"x": -half if rng.next() < 0.5 else half,
			"depth": 0.7 + rng.next() * 0.5,
			"dir": 1.0,
			"speed": float(tune["BOOT_SPEED"]),
			"scale": 0.42,
			"wiggle": rng.next() * TAU,
		}
		boot["node"] = _make_swimmer(boot)
		return boot
	var kind := Logic.roll_fish_kind(_stream)
	var detail := Logic.roll_species_detail(kind, _stream)
	var lo := float(tune["FISH_DEPTH_MIN"])
	var hi := float(tune["FISH_DEPTH_MAX"])
	var item := {
		"kind": kind,
		"species": str(detail["species"]),
		"rare": bool(detail["rare"]),
		"collectionId": str(detail["collectionId"]),
		"x": -half + rng.next() * half * 2.0,
		"depth": lo + rng.next() * (hi - lo),
		"dir": 1.0 if rng.next() < 0.5 else -1.0,
		"speed": Logic.fish_speed_for(kind, _stream),
		"scale": float((tune["SIZES"] as Dictionary)[kind]["scale"]),
		"wiggle": rng.next() * TAU,
	}
	item["node"] = _make_swimmer(item)
	return item


## 3D-Körper eines Schwimmers bauen (Kenney-Fisch bzw. Prozedur-Stiefel).
func _make_swimmer(item: Dictionary) -> Node3D:
	var holder := Node3D.new()
	if str(item["kind"]) == "boot":
		holder.add_child(_make_boot())
	else:
		var length: float = float(item["scale"]) + 0.25
		# `model()` passt auf HÖHE ein — der Fisch soll aber auf LÄNGE sitzen.
		var body := Props3D.model(ASSETS + "fish.glb", length * FISH_RAW_HEIGHT / FISH_RAW_LEN)
		body.position.y = -length * 0.22
		var mat := Props3D.flat(Logic.species_color(str(item["species"])), 0.55)
		_paint(body, mat)
		item["mat"] = mat
		holder.add_child(body)
		if bool(item.get("rare", false)):
			var aura := Props3D.halo(length * 0.85, Color(1.0, 0.85, 0.4, 0.5))
			holder.add_child(aura)
	_swimmers.add_child(holder)
	return holder


## Alter Gummistiefel — prozedural, wie im Web (kein Modell im Kit).
func _make_boot() -> Node3D:
	var holder := Node3D.new()
	var leather := Props3D.flat(Color(0.31, 0.25, 0.22), 0.95)
	var shaft := Props3D.box(Vector3(0.19, 0.3, 0.19), leather, Vector3(0.05, 0.06, 0.0))
	holder.add_child(shaft)
	holder.add_child(Props3D.box(Vector3(0.34, 0.13, 0.19), leather, Vector3(-0.02, -0.15, 0.0)))
	holder.add_child(
		Props3D.box(
			Vector3(0.2, 0.05, 0.2),
			Props3D.flat(Color(0.2, 0.17, 0.16), 0.95),
			Vector3(0.05, 0.22, 0.0)
		)
	)
	return holder


## Material auf alle Flächen einer Instanz legen (Artenfarbe der Fische).
func _paint(node: Node, mat: Material) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).material_override = mat
	for child in node.get_children():
		_paint(child, mat)


func _swim(delta: float) -> void:
	var half := float(tune["POND_HALF_W"])
	for f in fish:
		f["x"] = float(f["x"]) + float(f["dir"]) * float(f["speed"]) * delta
		f["wiggle"] = float(f["wiggle"]) + delta * 6.0
		if float(f["x"]) > half:
			f["x"] = half
			f["dir"] = -1.0
		elif float(f["x"]) < -half:
			f["x"] = -half
			f["dir"] = 1.0


## Alle Schwimmer an ihre (x, Tiefe) setzen. Die Tiefe färbt sie zusätzlich
## ins Trübe ein — so liest man auch ohne Zahlen, wie weit unten ein Fisch ist.
func _place_swimmers() -> void:
	for f in fish:
		var node: Node3D = f["node"]
		var wob := sin(float(f["wiggle"]))
		node.position = Vector3(float(f["x"]), -float(f["depth"]) + wob * 0.03, SWIM_Z)
		node.rotation.y = (PI * 0.5 if float(f["dir"]) > 0.0 else -PI * 0.5) + wob * 0.12
		if f.has("mat"):
			var deep := clampf(float(f["depth"]) / float(tune["MAX_DEPTH"]), 0.0, 1.0)
			var base := Logic.species_color(str(f["species"]))
			(f["mat"] as StandardMaterial3D).albedo_color = base.lerp(WATER, deep * 0.55)


func _step_respawns(delta: float) -> void:
	var kept: Array[float] = []
	for t in _respawn:
		var left := t - delta
		if left <= 0.0:
			fish.append(_spawn_fish())
		else:
			kept.append(left)
	_respawn = kept


# ----------------------------------------------------------------- Angeln


func _step_hook(delta: float) -> void:
	match phase:
		"lower":
			hook_depth = Logic.lower_depth(hook_depth, delta, tune)
		"raise":
			hook_depth = maxf(0.0, hook_depth - float(tune["RAISE_SPEED"]) * delta)
			if hook_depth <= 0.0:
				phase = "idle"
				_drop_hooked()
		"reel":
			reel_elapsed = Logic.advance_reel_elapsed(reel_elapsed, delta, tune)
			var verdict := Logic.reel_resolve(reel_taps, reel_elapsed, tune)
			if verdict != "reeling":
				_resolve_reel(verdict)


## Haken, Schwimmer, Schnur und Fangkreis nachziehen.
func _place_tackle() -> void:
	var hook_at := _hook_world()
	var bob_at := Vector3(float(tune["HOOK_X"]), sin(elapsed * 2.4) * 0.03, SWIM_Z)
	_bobber.position = bob_at
	_hook.position = hook_at
	_catch_ring.position = hook_at
	_catch_ring.visible = phase == "idle" or phase == "lower"
	_stretch(_line_rod, ROD_TIP, bob_at)
	_stretch(_line_deep, bob_at, hook_at + Vector3(0.0, 0.06, 0.0))
	if _hooked_node != null:
		_hooked_node.position = hook_at + Vector3(0.0, -0.16, 0.0)
		_hooked_node.rotation = Vector3(0.0, 0.0, sin(elapsed * 18.0) * 0.35)
	if _surface != null:
		# Der Steg-Gooby wippt mit der Dünung, das Wasser atmet leicht mit.
		_surface.position.y = sin(elapsed * 1.7) * 0.012


## Weltposition des Hakens (Logik-Tiefe → y).
func _hook_world() -> Vector3:
	return Vector3(float(tune["HOOK_X"]), -hook_depth, SWIM_Z)


## Einen Zylinder zwischen zwei Weltpunkte spannen (Schnurstücke).
func _stretch(node: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var delta := to - from
	var length := delta.length()
	if length < 0.001:
		node.visible = false
		return
	node.visible = true
	node.position = (from + to) * 0.5
	var up := delta / length
	var side := up.cross(Vector3.FORWARD)
	if side.length_squared() < 0.0001:
		side = up.cross(Vector3.RIGHT)
	side = side.normalized()
	# Die Streckung muss RECHTS der Drehung stehen — `Basis.scaled()` zieht
	# entlang der WELT-Achsen und würde die Schnur scheren statt verlängern.
	node.basis = Basis(side, up, side.cross(up)) * Basis.from_scale(Vector3(1.0, length, 1.0))


func _release() -> void:
	phase = "raise"
	_splash.burst(Vector3(float(tune["HOOK_X"]), 0.0, SWIM_Z))
	_gooby.swing(0.35, 30.0, Vector3.RIGHT)
	var index := Logic.nearest_catch(
		fish, float(tune["HOOK_X"]), hook_depth, float(tune["CATCH_RADIUS"])
	)
	if index < 0:
		AudioDirector.try_play(self, "mg_junk", 0.85)
		_gooby.emote("sad", 0.6)
		return
	hooked = fish[index]
	fish.remove_at(index)
	_hooked_node = hooked["node"]
	_respawn.append(float(tune["RESPAWN_SEC"]))
	_gooby.emote("ecstatic", 0.9)
	if Logic.needs_reel(str(hooked["kind"])):
		phase = "reel"
		reel_taps = 0
		reel_elapsed = 0.0
		AudioDirector.try_play(self, "mg_golden", 0.8)
		_stage.shake(0.05, 0.3)
		if ctx.juice != null:
			ctx.juice.shake(0.3)
		return
	_land_catch()


func _resolve_reel(verdict: String) -> void:
	phase = "raise"
	if verdict == "caught":
		_land_catch()
		return
	_flash_text = I18nService.t("mg.fishingPond.line_break")
	_flash_color = Color(0.85, 0.35, 0.35)
	_flash = FLASH_SEC
	AudioDirector.try_play(self, "mg_spill")
	_splash.burst(_hook_world())
	_gooby.emote("dizzy", 1.2)
	_stage.shake(0.09, 0.34)
	if ctx.juice != null:
		ctx.juice.shake(0.45)
		ctx.juice.float_text(_stage.to_screen(_hook_world()), _flash_text, _flash_color)
	_drop_hooked()
	if bool(tune["ENDLESS"]) and Logic.record_failure(endless_state, "lineBreak"):
		_finish()


## Den Fang am Haken entfernen (gelandet oder entkommen).
func _drop_hooked() -> void:
	if _hooked_node != null:
		_hooked_node.queue_free()
		_hooked_node = null
	hooked = {}


func _land_catch() -> void:
	var kind := str(hooked["kind"])
	var value := Logic.catch_value(kind)
	score = Logic.apply_catch(score, value)
	_flash_text = "%+d" % value
	_flash_color = Color(0.85, 0.35, 0.35) if value < 0 else Color(1.0, 0.78, 0.3)
	_flash = FLASH_SEC
	var world := _hook_world()
	if kind == "boot":
		AudioDirector.try_play(self, "mg_junk")
		_gooby.emote("angry", 1.2)
		_stage.shake(0.06, 0.28)
		if ctx.juice != null:
			ctx.juice.shake(0.3)
	else:
		_celebrate_fish(kind, world)
	if ctx.juice != null:
		ctx.juice.hit_freeze(40)
		ctx.juice.float_text(_stage.to_screen(world), _flash_text, _flash_color)
	ctx.report_score(score, value)
	var was_boot := kind == "boot"
	_drop_hooked()
	if was_boot and bool(tune["ENDLESS"]) and Logic.record_failure(endless_state, "boot"):
		_finish()


## Fangjubel: Funken, Glow-Puls, Gooby-Reaktion, Set-Bonus.
func _celebrate_fish(kind: String, world: Vector3) -> void:
	caught_species.append(str(hooked["species"]))
	_sparks.burst(world)
	_gooby.play_for("celebrate", 1.0, "sit")
	_gooby.emote("ecstatic", 1.3)
	_gooby.hop(0.4, 0.12)
	var bonus := Logic.rare_set_bonus(caught_species)
	if bonus > 0 and not caught_species.has("__bonus"):
		caught_species.append("__bonus")
		score += bonus
		_flash_text = I18nService.t("mg.fishingPond.rare_set", {"n": bonus})
		AudioDirector.try_play(self, "mg_golden")
		_stage.pulse_glow(1.2)
		if ctx.juice != null:
			ctx.juice.bloom_pulse(1.0)
	elif bool(hooked.get("rare", false)):
		AudioDirector.try_play(self, "mg_golden")
		_stage.pulse_glow(0.9)
		if ctx.juice != null:
			ctx.juice.bloom_pulse(0.8)
	else:
		AudioDirector.try_play(self, "mg_perfect" if kind == "L" else "mg_good")
		_stage.pulse_glow(0.5 if kind == "L" else 0.25)
		if ctx.juice != null:
			ctx.juice.bloom_pulse(0.4 if kind == "L" else 0.2)


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	ctx.report_end({"score": score, "species": caught_species.size()})


func _update_labels() -> void:
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.fishingPond.failures",
			{"n": int(endless_state["failures"]), "max": int(endless_state["limit"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - elapsed)))
		_time_label.text = I18nService.t("mg.game.time", {"sec": left})
	_score_label.text = I18nService.t("mg.fishingPond.depth", {"m": "%.1f" % hook_depth})


# ---------------------------------------------------------------- HUD 2D


## Einholbalken und Fangtext — die Szene selbst ist 3D.
func _draw() -> void:
	if phase == "reel":
		_draw_reel_meter()
	_draw_flash()


func _draw_reel_meter() -> void:
	var w := view_size.x * 0.62
	var x := view_size.x * 0.19
	var y := view_size.y * 0.16
	var need := float(tune["REEL_TAPS"])
	draw_rect(Rect2(x, y, w, 22.0), Color(0.1, 0.15, 0.2, 0.55))
	draw_rect(Rect2(x, y, w * clampf(reel_taps / need, 0.0, 1.0), 22.0), Color(0.4, 0.85, 0.5))
	var left := 1.0 - clampf(reel_elapsed / float(tune["REEL_WINDOW_SEC"]), 0.0, 1.0)
	draw_rect(Rect2(x, y + 24.0, w * left, 6.0), Color(0.95, 0.6, 0.3))
	draw_string(
		ThemeService.font(800),
		Vector2(x, y - 10.0),
		I18nService.t("mg.fishingPond.reel"),
		HORIZONTAL_ALIGNMENT_CENTER,
		w,
		24,
		Color(1.0, 0.98, 0.9)
	)


func _draw_flash() -> void:
	if _flash <= 0.0 or _flash_text.is_empty():
		return
	var alpha := clampf(_flash * 1.5, 0.0, 1.0)
	var y := view_size.y * 0.26
	draw_rect(Rect2(0.0, y - 32.0, view_size.x, 46.0), Color(0.12, 0.09, 0.18, 0.45 * alpha))
	draw_string(
		ThemeService.font(800),
		Vector2(0.0, y),
		_flash_text,
		HORIZONTAL_ALIGNMENT_CENTER,
		view_size.x,
		32,
		Color(_flash_color, alpha)
	)
