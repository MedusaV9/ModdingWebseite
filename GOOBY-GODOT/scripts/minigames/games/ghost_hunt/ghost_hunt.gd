extends MinigameBase
## Geisterjagd (ghostHunt) — Spiel-Szene. Alle MECHANIK-Zahlen kommen aus
## GhostHuntLogic (zahlengleich zum Web): 90-s-Runde, Sichtfenster 2.2 s → 0.9 s,
## Fang +3 mit Kettenbonus (max. +5), Kürbis-Attrappe −2, alle 25 s eine
## Buh-Welle mit 5 Geistern (≥ 4 Fänge = +10) sowie Laterne/Netz als Aufsammler.
##
## ECHTES 3D (Agent 3D-A, Rückbau): ein Friedhofsgarten in der Abenddämmerung.
## Die zwölf Verstecke aus `GhostHuntLogic.SPOTS` sind echte Grabsteine, Kürbisse
## und eine Gruft auf ihren Weltkoordinaten (x, z) — die frühere 2D-Fassung hat
## dieselben Zahlen nur mit einer Handrechnung `project()` perspektivisch
## GEFAKED. Jetzt macht das die Kamera. Getippt wird weiterhin auf Bildschirm-
## punkte: `Stage3D.to_screen()` liefert sie, der Daumenradius bleibt.
##
## Gooby ist ECHTES Rig und spielt MIT: er steht mit Laterne am Tor, dreht sich
## zum gefangenen Geist, jubelt beim Fang und erschrickt bei der Attrappe.
##
## Der MinigameBase-Vertrag bleibt: Wurzel ist Node2D, die 3D-Welt hängt
## darunter, HUD/Banner sind CanvasItems obenauf.

const Logic := preload("res://scripts/minigames/games/ghost_hunt/ghost_hunt_logic.gd")
const Stage3D := preload("res://scripts/minigames/games/_3da_stage/stage3d.gd")
const Props3D := preload("res://scripts/minigames/games/_3da_stage/props3d.gd")
const GoobyActor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Spark3D := preload("res://scripts/minigames/games/_3da_stage/spark3d.gd")

const ASSETS := "res://assets/minigames/ghost_hunt/"

## So viele Geister können gleichzeitig stehen (Buh-Welle: BOO_COUNT = 5).
const GHOST_RIGS := 6
## Höhe eines Laken-Geistes in Metern.
const GHOST_H := 1.05
## Mindest-Tippfläche in Pixeln (Daumenregel — wie in der 2D-Fassung).
const TAP_MIN_PX := 34.0
## Tippradius eines Ziels in Weltmetern (wird auf den Schirm projiziert).
const TAP_WORLD_R := 0.46

const GHOST_TINT := Color(0.93, 0.94, 1.0)
const WAVE_TINT := Color(0.85, 0.78, 1.0)
const LANTERN_TINT := Color(1.0, 0.694, 0.302)
const NET_TINT := Color(0.608, 0.878, 0.784)
const STONE := Color(0.68, 0.67, 0.76)
const TURF := Color(0.24, 0.33, 0.29)
## Umfärbung des Kenney-Kürbisses (`leafsFall` = Körper, `grass` = Stiel).
const PUMPKIN_SKIN := {
	"leafsFall": Color(0.93, 0.47, 0.16),
	"grass": Color(0.36, 0.5, 0.28),
}

var state: Dictionary = {}
var view_size := Vector2(390.0, 844.0)
var landscape := false
var finished := false

var _banner := ""
var _banner_t := 0.0
var _bob := 0.0
var _score_label: Label
var _chain_label: Label
var _hint_label: Label

var _stage: Stage3D
var _gooby: GoobyActor
var _sparks: Spark3D
var _ghosts: Array[Dictionary] = []
var _decoys: Array[Dictionary] = []
var _tokens: Array[Dictionary] = []
var _lantern_light: OmniLight3D
var _sheet: ArrayMesh
var _face: Mesh
var _sky: Node3D
var _mist: Array[Dictionary] = []


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	var tune := Logic.apply_difficulty(Logic.HUNT, ctx.difficulty)
	state = Logic.create_hunt(ctx.run_seed, tune)
	_build_world()
	_build_hud()
	_fit_viewport()
	if is_inside_tree():
		get_viewport().size_changed.connect(_fit_viewport)


func end() -> void:
	super.end()
	finished = true


## Pflicht-Layouthook: beide Orientierungen laufen über DIESE Funktion.
## Hochkant blickt die Kamera STEILER auf den Friedhof — sonst schiebt sich das
## schmale Bild voll Himmel und die hinteren Gräber liegen übereinander.
func apply_view(size: Vector2) -> void:
	if size.x > 1.0 and size.y > 1.0:
		view_size = size
	landscape = view_size.x > view_size.y
	position = Vector2.ZERO
	if _stage != null:
		_stage.apply_size(view_size)
		_stage.set_fov(44.0 if landscape else 40.0)
		_frame_yard()
	if _score_label != null:
		_score_label.position = Vector2(16.0, 10.0)
		_chain_label.position = Vector2(16.0, 48.0)
		_hint_label.position = Vector2(view_size.x * 0.5 - 170.0, view_size.y - 42.0)
		_hint_label.size = Vector2(340.0, 34.0)
	queue_redraw()


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	_bob += delta
	_banner_t = maxf(0.0, _banner_t - delta)
	_stage.tick(delta)
	_gooby.tick(delta)
	_drift_mist()
	Logic.step_hunt(state, delta)
	_drain_events()
	_sync_ghosts()
	_sync_decoys()
	_sync_tokens()
	_sync_lantern()
	ctx.report_score(Logic.hunt_score(state), 0)
	_update_labels()
	queue_redraw()
	if bool(state["ended"]):
		_finish()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished:
		return
	if event is InputEventScreenTouch and event.pressed:
		_tap_at(event.position)


## Steht gerade ein sichtbarer Geist im Bild? (Screenshot-Treiber.)
func has_visible_ghost() -> bool:
	for rig: Dictionary in _ghosts:
		if (rig["root"] as Node3D).visible:
			return true
	return false


## Bildschirmpunkt des ersten sichtbaren Geistes (Screenshot-Treiber).
func first_ghost_screen() -> Vector2:
	for rig: Dictionary in _ghosts:
		var root: Node3D = rig["root"]
		if root.visible:
			return _stage.to_screen(root.position + Vector3(0.0, GHOST_H * 0.6, 0.0))
	return view_size * 0.5


# ------------------------------------------------------------------ Aufbau


func _build_world() -> void:
	_stage = Stage3D.new()
	add_child(_stage)
	# Dämmerungsviolett wie im Web (§C10.1 „distinct look"): kaltes Mondlicht,
	# warmer Kürbisschein, kräftiger Glow, damit die Laternen wirklich glühen.
	(
		_stage
		. build(
			{
				# NACHT-EICHUNG: Belichtung 1,05 hielt den Friedhof bei Luma
				# 107 (Dämmerung statt Mitternacht). Dunklerer Himmel + 0,85
				# drücken auf ~92; die kalte Mond-Sonne (1,7) hält Konturen.
				"sky_top": Color(0.12, 0.1, 0.26),
				"sky_horizon": Color(0.48, 0.26, 0.38),
				# Boden-Hemisphäre des Prozedurhimmels = NEBELFARBE. Sie kippt
				# sonst direkt unter der Horizontlinie fast auf Schwarz und
				# malt einen dunklen Balken über die abgenebelte Wiese.
				"ground_horizon": Color(0.29, 0.2, 0.36),
				"ground_bottom": Color(0.27, 0.19, 0.34),
				"sky_energy": 0.62,
				"fog_color": Color(0.29, 0.2, 0.36),
				"fog_from": 13.0,
				"fog_to": 40.0,
				"fog_density": 0.7,
				"sun_dir": Vector3(0.42, -0.6, 0.68),
				"sun_color": Color(0.74, 0.83, 1.0),
				"sun_energy": 1.7,
				"ambient": 0.34,
				"ambient_color": Color(0.42, 0.38, 0.62),
				"sky_ambient": 0.35,
				"exposure": 0.85,
				"white": 2.2,
				"fill_color": Color(1.0, 0.66, 0.42),
				"fill_energy": 0.3,
				"glow": 0.45,
				"glow_threshold": 0.82,
				"glow_bloom": 0.14,
				"shadows": true,
				"shadow_distance": 22.0,
				"fov": 44.0,
				"far": 90.0,
			}
		)
	)
	_stage.add_child(Props3D.ground(Vector2(70.0, 70.0), Props3D.flat(TURF), 0.0))
	_build_moon()
	_build_yard()
	_build_mist()
	_build_spots()
	_build_decoys()
	_build_ghosts()
	_build_tokens()
	_build_gooby()
	_sparks = Spark3D.new()
	_stage.add_child(_sparks)
	(
		_sparks
		. build(
			{
				"color": Color(0.92, 0.95, 1.0),
				"amount": 26,
				"speed": Vector2(1.2, 2.8),
				"gravity": Vector3(0.0, -1.6, 0.0),
				"lifetime": 0.9,
			}
		)
	)


## Mond und Sterne hängen in einer KAMERAFESTEN Kuppel (`_sky`), nicht im Hof.
## Grund: die Kamera blickt hier steil von oben (30°…38°) — ein Mond mit fester
## Weltposition steht dann garantiert über dem Bildrand, und hochkant/quer
## verschiebt er sich auch noch unterschiedlich. In Kamerakoordinaten sitzt er
## immer oben links, egal welches Format.
func _build_moon() -> void:
	_sky = Node3D.new()
	_stage.add_child(_sky)
	# Nicht zu weit weg: die Kamera blickt steil nach unten, ein Mond in 34 m
	# läge unter der Bodenebene und wäre schlicht verdeckt.
	var moon := Props3D.halo(0.6, Color(1.0, 0.96, 0.82, 0.95))
	moon.position = Vector3(-3.2, 6.0, -20.0)
	_sky.add_child(moon)
	var haze := Props3D.halo(1.7, Color(0.72, 0.68, 1.0, 0.16))
	haze.position = Vector3(-3.2, 6.0, -20.2)
	_sky.add_child(haze)


## Friedhofsgarten: Zaun ums Feld, tote Bäume, Stümpfe, Büsche, Pilze und ein
## Trampelpfad. Alles Massenware — ein Draw-Call je Sorte.
func _build_yard() -> void:
	var yard := Vector3(0.0, 0.0, -3.6)
	var gate := func(at: Vector3) -> bool: return at.z > 0.9
	_build_fence()
	# Bewusst kleiner und weiter draußen als im ersten Versuch: hochkant blickt
	# die Kamera steil, große Bäume am inneren Kranz füllen sonst den halben
	# Himmel und werden oben abgeschnitten.
	_stage.add_child(
		Props3D.scatter(ASSETS + "tree_pineTallA.glb", 3.8, 10, 10.4, yard, 1.5, 0.4, gate)
	)
	_stage.add_child(Props3D.scatter(ASSETS + "tree_oak.glb", 3.1, 8, 13.0, yard, 1.8, 1.7, gate))
	_stage.add_child(
		Props3D.scatter(ASSETS + "stump_round.glb", 0.36, 6, 6.2, yard, 0.9, 2.4, gate)
	)
	_stage.add_child(Props3D.scatter(ASSETS + "log.glb", 0.3, 5, 5.6, yard, 1.1, 3.1, gate))
	_stage.add_child(
		Props3D.scatter(ASSETS + "plant_bushLarge.glb", 0.62, 12, 6.8, yard, 1.2, 0.9, gate)
	)
	_stage.add_child(
		Props3D.scatter(ASSETS + "grass_large.glb", 0.34, 22, 5.4, yard, 1.4, 2.0, gate)
	)
	_stage.add_child(
		Props3D.scatter(ASSETS + "mushroom_red.glb", 0.22, 10, 4.6, yard, 1.0, 3.6, gate)
	)
	# Trampelpfad vom Tor zur Gruft — er führt das Auge in die Tiefe. Die
	# Platten liegen bewusst schmal und fast achsparallel: gedrehte, große
	# Platten lesen sich von oben wie ein Stapel Spielkarten.
	var slab := BoxMesh.new()
	slab.size = Vector3(0.62, 0.03, 0.44)
	slab.material = Props3D.flat(Color(0.33, 0.31, 0.34))
	var path: Array = []
	for i in 11:
		var z := 0.7 - float(i) * 0.66
		var x := sin(float(i) * 0.7) * 0.24
		path.append(Props3D.pose(Vector3(x, 0.012, z), sin(float(i) * 1.9) * 0.12))
	_stage.add_child(Props3D.swarm_mesh(slab, path, 10.0))
	_build_gate()
	_build_stars()


## Friedhofstor im Vordergrund: zwei Pfeiler mit Kürbislaternen. Sie rahmen
## das Bild unten ein — ohne sie ist der Nahbereich eine leere Rasenfläche.
func _build_gate() -> void:
	var stone := Props3D.flat(Color(0.46, 0.43, 0.52), 0.95)
	for sign_x: float in [-1.0, 1.0]:
		var at := Vector3(sign_x * 2.35, 0.0, 1.05)
		_stage.add_child(Props3D.box(Vector3(0.42, 1.5, 0.42), stone, at + Vector3.UP * 0.75))
		_stage.add_child(
			Props3D.box(
				Vector3(0.58, 0.12, 0.58),
				Props3D.flat(Color(0.38, 0.35, 0.44), 0.95),
				at + Vector3.UP * 1.56
			)
		)
		var lamp := Props3D.box(
			Vector3(0.26, 0.3, 0.26), Props3D.glow(LANTERN_TINT, 1.8), at + Vector3.UP * 1.77
		)
		_stage.add_child(lamp)
		var halo := Props3D.halo(0.68, Color(LANTERN_TINT, 0.28))
		halo.position = at + Vector3.UP * 1.77
		_stage.add_child(halo)


## Bodennebel: fünf große, blasse Mondlicht-Schwaden, die träge zwischen den
## Gräbern treiben (`_drift_mist`). Additive Halos, Deckkraft 0,1 — Runde 2:
## 0,055 war unsichtbar, mehr überstrahlt die Grabsteine.
func _build_mist() -> void:
	for entry: Array in [
		[Vector3(-2.6, 0.55, -2.2), 3.2],
		[Vector3(2.4, 0.5, -4.0), 3.6],
		[Vector3(-0.8, 0.6, -5.6), 2.8],
		[Vector3(1.6, 0.5, -1.2), 2.6],
		[Vector3(-3.4, 0.5, -4.8), 3.0],
	]:
		var wisp := Props3D.halo(float(entry[1]), Color(0.74, 0.72, 0.95, 0.1))
		wisp.position = entry[0]
		_stage.add_child(wisp)
		_mist.append({"node": wisp, "home": entry[0] as Vector3})


## Sternenhimmel: ein MultiMesh winziger Leuchtplättchen weit hinten.
func _build_stars() -> void:
	var star := QuadMesh.new()
	star.size = Vector2(0.055, 0.055)
	var mat := Props3D.glow(Color(1.0, 0.98, 0.9), 3.0)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.disable_fog = true
	mat.albedo_texture = Props3D.disc()
	star.material = mat
	var poses: Array = []
	for i in 48:
		var a := float(i) * 2.399
		poses.append(
			Props3D.pose(
				Vector3(sin(a) * 9.0, 3.2 + 5.0 * absf(sin(float(i) * 1.31)), -20.0),
				0.0,
				0.5 + 0.7 * absf(cos(float(i) * 2.1))
			)
		)
	_sky.add_child(Props3D.swarm_mesh(star, poses, 60.0))


func _build_fence() -> void:
	var poses: Array = []
	for i in 30:
		var a := TAU * float(i) / 30.0
		var at := Vector3(sin(a) * 6.6, 0.0, -3.6 + cos(a) * 5.4)
		if at.z > 1.0:
			continue
		poses.append(Props3D.pose(at, -a, 1.0))
	_stage.add_child(
		Props3D.swarm(
			Props3D.parts(ASSETS + "fence_simple.glb", 0.72, {"wood": Color(0.42, 0.34, 0.4)}),
			poses
		)
	)


## Die zwölf Verstecke aus der Logik als echte Requisiten auf ihren (x, z).
func _build_spots() -> void:
	var graves: Array = []
	var pumpkins: Array = []
	for spot: Dictionary in Logic.SPOTS:
		var at := Vector3(float(spot["x"]), 0.0, float(spot["z"]))
		match str(spot["kind"]):
			"pumpkin":
				pumpkins.append(Props3D.pose(at, float(spot["id"]) * 1.3, 1.1))
			"crypt":
				_stage.add_child(_build_crypt(at))
			_:
				graves.append(Props3D.pose(at, float(spot["id"]) * 0.4 - 0.6, 1.0))
	_stage.add_child(Props3D.swarm_mesh(_grave_mesh(), graves, 8.0))
	# Materialnamen aus dem GLB: `leafsFall` ist der Kürbiskörper, `grass` der
	# Stiel — ohne die Umfärbung bleiben die Kürbisse kit-lachsrosa.
	_stage.add_child(
		Props3D.swarm(Props3D.parts(ASSETS + "crop_pumpkin.glb", 0.42, PUMPKIN_SKIN), pumpkins)
	)


## Grabstein als EIN Mesh (Stele + Rundbogen + Kreuz) — so kostet die ganze
## Reihe einen Draw-Call statt drei je Stein.
func _grave_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_box(st, Vector3(0.0, 0.42, 0.0), Vector3(0.52, 0.84, 0.16))
	_add_box(st, Vector3(0.0, 0.86, 0.0), Vector3(0.4, 0.2, 0.16))
	_add_box(st, Vector3(0.0, 0.06, 0.0), Vector3(0.66, 0.12, 0.28))
	st.generate_normals()
	var mesh: ArrayMesh = st.commit()
	mesh.surface_set_material(0, Props3D.flat(STONE, 0.95))
	return mesh


func _build_crypt(at: Vector3) -> Node3D:
	var holder := Node3D.new()
	holder.position = at
	var wall := Props3D.flat(Color(0.5, 0.48, 0.58), 0.95)
	holder.add_child(Props3D.box(Vector3(1.5, 1.3, 1.3), wall, Vector3(0.0, 0.65, 0.0)))
	# Echtes Satteldach statt eines um 45° gekippten Würfels — der sieht von
	# vorn wie eine Raute aus und nicht wie ein Dach.
	var gable := PrismMesh.new()
	gable.size = Vector3(1.72, 0.62, 1.5)
	gable.left_to_right = 0.5
	gable.material = Props3D.flat(Color(0.43, 0.4, 0.53), 0.95)
	holder.add_child(Props3D.mesh_node(gable, Vector3(0.0, 1.61, 0.0)))
	holder.add_child(
		Props3D.box(
			Vector3(0.5, 0.86, 0.1),
			Props3D.flat(Color(0.11, 0.08, 0.15), 1.0),
			Vector3(0.0, 0.43, 0.66)
		)
	)
	return holder


## Attrappen: geschnitzte Kürbislaternen, die im Flackerfenster hell glühen.
func _build_decoys() -> void:
	for spot: Dictionary in Logic.DECOY_SPOTS:
		var holder := Node3D.new()
		holder.position = Vector3(float(spot["x"]), 0.0, float(spot["z"]))
		var body := Props3D.model(ASSETS + "crop_pumpkin.glb", 0.5)
		Props3D.repaint(body, PUMPKIN_SKIN)
		holder.add_child(body)
		var face_mat := Props3D.glow(LANTERN_TINT, 0.0)
		var eyes := (
			Props3D
			. swarm_mesh(
				_face_mesh(),
				[
					Props3D.pose(Vector3(-0.09, 0.3, 0.19), 0.0, 0.7),
					Props3D.pose(Vector3(0.09, 0.3, 0.19), 0.0, 0.7),
					Props3D.pose(Vector3(0.0, 0.17, 0.2), 0.0, 1.1),
				]
			)
		)
		for child in eyes.get_children():
			(child as GeometryInstance3D).material_override = face_mat
		holder.add_child(eyes)
		var halo := Props3D.halo(0.85, Color(LANTERN_TINT, 0.0))
		halo.position = Vector3(0.0, 0.26, 0.0)
		holder.add_child(halo)
		_stage.add_child(holder)
		_decoys.append({"root": holder, "face": face_mat, "halo": halo})


## Kleines Gesichtsplättchen (Augen/Mund von Geist und Kürbis) — als MultiMesh
## verbaut, damit ein ganzes Gesicht einen Draw-Call kostet.
func _face_mesh() -> Mesh:
	if _face == null:
		var sphere := SphereMesh.new()
		sphere.radius = 0.055
		sphere.height = 0.13
		sphere.radial_segments = 8
		sphere.rings = 4
		_face = sphere
	return _face


## Geister-Pool: fertige Laken, die je Frame den aktiven Logik-Geistern
## zugewiesen werden. Neu-Instanziieren mitten in der Buh-Welle würde ruckeln.
func _build_ghosts() -> void:
	for i in GHOST_RIGS:
		var root := Node3D.new()
		root.visible = false
		var mat := Props3D.glass(GHOST_TINT)
		mat.emission_enabled = true
		mat.emission = GHOST_TINT
		mat.emission_energy_multiplier = 0.55
		var sheet := Props3D.mesh_node(_sheet_mesh(), Vector3.ZERO, false)
		sheet.material_override = mat
		root.add_child(sheet)
		var face_mat := Props3D.flat(Color(0.15, 0.13, 0.22), 0.6)
		var face := (
			Props3D
			. swarm_mesh(
				_face_mesh(),
				[
					Props3D.pose(Vector3(-0.16, 0.5, 0.22), 0.0, 1.0),
					Props3D.pose(Vector3(0.16, 0.5, 0.22), 0.0, 1.0),
					Props3D.pose(Vector3(0.0, 0.33, 0.25), 0.0, 0.7),
				]
			)
		)
		for child in face.get_children():
			(child as GeometryInstance3D).material_override = face_mat
		root.add_child(face)
		var halo := Props3D.halo(1.0, Color(GHOST_TINT, 0.16))
		halo.position = Vector3(0.0, 0.4, 0.0)
		root.add_child(halo)
		_stage.add_child(root)
		_ghosts.append({"root": root, "mat": mat, "halo": halo, "sheet": sheet})


## Laken-Geist als Drehkörper mit gewelltem Saum (Web: LatheGeometry + Scallop).
func _sheet_mesh() -> ArrayMesh:
	if _sheet != null:
		return _sheet
	var profile := [
		Vector2(0.0, 0.62),
		Vector2(0.12, 0.6),
		Vector2(0.21, 0.52),
		Vector2(0.26, 0.41),
		Vector2(0.27, 0.28),
		Vector2(0.25, 0.16),
		Vector2(0.31, 0.06),
		Vector2(0.31, 0.0),
	]
	var segments := 18
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for ring in profile.size() - 1:
		for seg in segments:
			var a0 := TAU * float(seg) / float(segments)
			var a1 := TAU * float(seg + 1) / float(segments)
			var p00 := _lathe(profile[ring], a0)
			var p01 := _lathe(profile[ring], a1)
			var p10 := _lathe(profile[ring + 1], a0)
			var p11 := _lathe(profile[ring + 1], a1)
			for point: Vector3 in [p00, p10, p11, p00, p11, p01]:
				st.add_vertex(point)
	st.generate_normals()
	_sheet = st.commit()
	return _sheet


## Profilpunkt um die y-Achse drehen; der Saum bekommt seine Wellen.
func _lathe(point: Vector2, angle: float) -> Vector3:
	var y := point.y
	if y < 0.08:
		y -= (sin(angle * 6.0) + 1.0) * 0.03
	return Vector3(cos(angle) * point.x, y, sin(angle) * point.x)


## Aufsammler: Laterne und Kescher schweben über ihren Ankern.
func _build_tokens() -> void:
	for kind: String in ["lantern", "net"]:
		var holder := Node3D.new()
		holder.visible = false
		var tint := LANTERN_TINT if kind == "lantern" else NET_TINT
		if kind == "lantern":
			holder.add_child(Props3D.box(Vector3(0.26, 0.32, 0.26), Props3D.glow(tint, 2.2)))
			var bail := Props3D.torus(0.13, 0.018, Props3D.flat(Color(0.7, 0.62, 0.5), 0.5))
			bail.rotation.x = PI * 0.5
			bail.position.y = 0.24
			holder.add_child(bail)
		else:
			var hoop := Props3D.torus(0.26, 0.03, Props3D.glow(tint, 1.8))
			hoop.rotation.x = PI * 0.5
			holder.add_child(hoop)
			holder.add_child(
				Props3D.cylinder(
					0.025, 0.42, Props3D.flat(Color(0.68, 0.55, 0.4), 0.7), Vector3(0.0, -0.28, 0.0)
				)
			)
		var halo := Props3D.halo(0.8, Color(tint, 0.3))
		holder.add_child(halo)
		_stage.add_child(holder)
		_tokens.append({"root": holder, "kind": kind, "halo": halo})


## Gooby steht mit der Laterne am Tor und blickt in den Hof (Dreiviertelrücken
## wie im Web) — er dreht sich zu jedem Geist, den er fängt.
func _build_gooby() -> void:
	_gooby = GoobyActor.new()
	_stage.add_child(_gooby)
	_gooby.position = Vector3(-1.55, 0.0, 0.95)
	_gooby.mount(1.0, 2.5)
	_gooby.set_mood("happy")
	var lamp := Node3D.new()
	lamp.add_child(Props3D.box(Vector3(0.15, 0.19, 0.15), Props3D.glow(LANTERN_TINT, 1.6)))
	lamp.add_child(
		Props3D.box(
			Vector3(0.19, 0.04, 0.19),
			Props3D.flat(Color(0.45, 0.33, 0.24), 0.8),
			Vector3(0.0, 0.11, 0.0)
		)
	)
	lamp.add_child(Props3D.halo(0.34, Color(LANTERN_TINT, 0.35)))
	lamp.position = Vector3(0.4, 0.58, 0.2)
	_gooby.attach(lamp)
	_lantern_light = OmniLight3D.new()
	_lantern_light.light_color = LANTERN_TINT
	_lantern_light.light_energy = 1.5
	_lantern_light.omni_range = 4.6
	_lantern_light.omni_attenuation = 1.6
	_lantern_light.position = _gooby.position + Vector3(0.4, 0.72, 0.2)
	_stage.add_child(_lantern_light)


func _build_hud() -> void:
	_score_label = Label.new()
	_score_label.theme_type_variation = &"HeadlineLabel"
	add_child(_score_label)
	_chain_label = Label.new()
	_chain_label.theme_type_variation = &"CaptionLabel"
	add_child(_chain_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.ghostHunt.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint_label)
	# Die Dämmerungskulisse ist dunkel — die Theme-Schriftfarben sind es auch.
	_score_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.88))
	_chain_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.55))
	_hint_label.add_theme_color_override("font_color", Color(0.86, 0.82, 0.95))
	for label: Label in [_score_label, _chain_label, _hint_label]:
		label.add_theme_color_override("font_outline_color", Color(0.09, 0.06, 0.14, 0.9))
		label.add_theme_constant_override("outline_size", 6)
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


## Kamera vor dem Tor, erhöht über dem Hof — alle zwölf Verstecke und Gooby
## müssen ins Bild, sonst kann man nicht auf sie tippen.
func _frame_yard() -> void:
	if _stage == null or _gooby == null:
		return
	var points: Array = [
		Vector3(-2.9, 0.0, -1.3),
		Vector3(2.9, 0.0, -1.3),
		Vector3(-2.9, 1.4, -6.9),
		Vector3(2.9, 1.4, -6.9),
		Vector3(0.0, 2.4, -6.4),
		_gooby.position + Vector3(0.0, 1.15, 0.3),
		# Goobys FÜSSE gehören mit in den Kader — sonst schneidet ihn das
		# Querformat unten ab und der Spieler steht nur halb im Bild.
		_gooby.position + Vector3(0.0, 0.0, 0.75),
	]
	var center := Vector3(0.0, 0.5, -3.1)
	_stage.fit(points, center, 30.0 if landscape else 38.0, 0.0, 0.9)
	if _sky != null and _stage.camera != null:
		_sky.transform = _stage.camera.transform


# ------------------------------------------------------------------ Abgleich


## Geister-Pool an die Logik hängen: Position, Hebekurve, Deckkraft, Aura.
func _sync_ghosts() -> void:
	var live: Array = state["ghosts"]
	var dt := get_process_delta_time()
	for i in _ghosts.size():
		var rig: Dictionary = _ghosts[i]
		var root: Node3D = rig["root"]
		if i >= live.size():
			root.visible = false
			continue
		var ghost: Dictionary = live[i]
		var lift := _ghost_lift(ghost)
		if lift <= 0.01:
			root.visible = false
			continue
		var spot: Dictionary = Logic.SPOTS[int(ghost["spot"])]
		# ENTDECKUNGSMOMENT: taucht ein Geist NEU auf, blitzt seine Aura kurz
		# auf und ein leiser Tick lockt das Ohr — das Auge findet ihn, bevor
		# das Sichtfenster wieder zugeht.
		if not root.visible:
			rig["flash"] = 0.45
			AudioDirector.try_play(self, "ui_tick", 0.8)
		var flash := maxf(0.0, float(rig.get("flash", 0.0)) - dt)
		rig["flash"] = flash
		root.visible = true
		root.position = _ghost_world(ghost, spot)
		root.scale = Vector3.ONE * (GHOST_H * (0.72 + 0.28 * lift))
		root.rotation.y = sin(_bob * 1.6 + float(ghost["id"])) * 0.28
		var tint: Color = WAVE_TINT if ghost["wave"] != null else GHOST_TINT
		var mat: StandardMaterial3D = rig["mat"]
		mat.albedo_color = Color(tint, 0.62 + 0.34 * lift)
		mat.emission = tint
		mat.emission_energy_multiplier = (
			0.4 + (0.9 if bool(ghost["revealed"]) else 0.0) + flash * 2.2
		)
		var halo: MeshInstance3D = rig["halo"]
		var glow := 0.16 * lift + (0.2 if bool(ghost["revealed"]) else 0.0) + flash * 0.5
		_set_halo(halo, Color(LANTERN_TINT if bool(ghost["revealed"]) else tint, glow))


## Attrappen: nur im Flackerfenster glühen Gesicht und Aura auf.
func _sync_decoys() -> void:
	var active := {}
	for flick: Dictionary in state["flickers"]:
		active[int(flick["decoy"])] = float(state["t"]) - float(flick["startT"])
	for i in _decoys.size():
		var rig: Dictionary = _decoys[i]
		var mat: StandardMaterial3D = rig["face"]
		var halo: MeshInstance3D = rig["halo"]
		if not active.has(i):
			mat.emission_energy_multiplier = 0.0
			mat.albedo_color = Color(0.28, 0.18, 0.12)
			_set_halo(halo, Color(LANTERN_TINT, 0.0))
			continue
		var f := 0.55 + 0.45 * sin(float(active[i]) * 22.0)
		mat.emission_energy_multiplier = 2.2 * f
		mat.albedo_color = LANTERN_TINT
		_set_halo(halo, Color(LANTERN_TINT, 0.3 * f))


func _sync_tokens() -> void:
	var live := {}
	for token: Dictionary in state["tokens"]:
		live[str(token["kind"])] = int(token["window"])
	for rig: Dictionary in _tokens:
		var root: Node3D = rig["root"]
		var kind := str(rig["kind"])
		if not live.has(kind):
			root.visible = false
			continue
		var anchor: Dictionary = Logic.TOKEN_ANCHORS[int(live[kind])]
		root.visible = true
		root.position = Vector3(
			float(anchor["x"]), 1.05 + sin(_bob * 2.4) * 0.09, float(anchor["z"])
		)
		root.rotation.y = _bob * 1.1


## Nebelschwaden träge treiben lassen (jede in eigener Phase um ihren Anker).
func _drift_mist() -> void:
	for i in _mist.size():
		var wisp: Dictionary = _mist[i]
		var node: Node3D = wisp["node"]
		var home: Vector3 = wisp["home"]
		var t := _bob * 0.16 + float(i) * 1.7
		node.position = home + Vector3(sin(t) * 0.8, sin(t * 1.7) * 0.06, cos(t * 0.8) * 0.5)


## Der Laternen-Aufsammler taucht den ganzen Hof kurz in warmes Licht.
func _sync_lantern() -> void:
	if _lantern_light == null:
		return
	var left := float(state["lanternT"])
	var boost := clampf(left / float(Logic.HUNT["LANTERN_SEC"]), 0.0, 1.0)
	_lantern_light.light_energy = 1.5 + 5.0 * boost
	_lantern_light.omni_range = 4.6 + 14.0 * boost


func _set_halo(node: MeshInstance3D, color: Color) -> void:
	var mat := node.get_active_material(0)
	if mat is StandardMaterial3D:
		(mat as StandardMaterial3D).albedo_color = color


## Weltposition eines Geistes: er steigt aus seinem Versteck auf.
func _ghost_world(ghost: Dictionary, spot: Dictionary) -> Vector3:
	var base := 0.34 if str(spot["kind"]) == "pumpkin" else 0.62
	if str(spot["kind"]) == "crypt":
		base = 1.5
	return Vector3(float(spot["x"]), base + _ghost_lift(ghost) * 0.72, float(spot["z"]) + 0.18)


## Aufsteig-/Absink-Kurve eines Geistes (RISE_FRAC/SINK_FRAC aus der Logik).
func _ghost_lift(ghost: Dictionary) -> float:
	var age := float(state["t"]) - float(ghost["spawnT"])
	var dur := maxf(0.001, float(ghost["dur"]))
	var f := clampf(age / dur, 0.0, 1.0)
	var rise := float(Logic.HUNT["RISE_FRAC"])
	var sink := float(Logic.HUNT["SINK_FRAC"])
	if f < rise:
		return _ease_out_back(f / rise)
	if f > 1.0 - sink:
		return maxf(0.0, (1.0 - f) / sink)
	return 1.0


func _ease_out_back(x: float) -> float:
	var c1 := 1.70158
	return 1.0 + (c1 + 1.0) * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0)


# ------------------------------------------------------------------ Tippen


## Tippradius eines Weltziels in Pixeln. Perspektive statt Handrechnung: der
## Radius wird als echte Strecke projiziert und bleibt mindestens daumengroß.
func _tap_radius(world: Vector3) -> float:
	var right := _stage.camera.global_transform.basis.x * TAP_WORLD_R
	var span := _stage.to_screen(world + right).distance_to(_stage.to_screen(world))
	return maxf(TAP_MIN_PX, span)


## Nächstliegendes Ziel unter dem Finger; Aufsammler haben Vorrang.
func _tap_at(pos: Vector2) -> void:
	var best := {}
	var best_d := INF
	for token: Dictionary in state["tokens"]:
		var anchor: Dictionary = Logic.TOKEN_ANCHORS[int(token["window"])]
		var at := Vector3(float(anchor["x"]), 1.05, float(anchor["z"]))
		var d := pos.distance_to(_stage.to_screen(at))
		if d < _tap_radius(at) * 1.2 and d < best_d:
			best_d = d
			best = {"kind": "token", "window": int(token["window"])}
	if best.is_empty():
		best = _pick_target(pos)
	Logic.tap_hunt(state, best)
	_drain_events()


## Geister und Attrappen unter dem Finger prüfen (getrennt, damit `_tap_at`
## kurz bleibt und die Vorrangregel oben lesbar steht).
func _pick_target(pos: Vector2) -> Dictionary:
	var best := {}
	var best_d := INF
	for ghost: Dictionary in state["ghosts"]:
		if _ghost_lift(ghost) <= 0.01:
			continue
		var spot: Dictionary = Logic.SPOTS[int(ghost["spot"])]
		var at := _ghost_world(ghost, spot) + Vector3(0.0, GHOST_H * 0.4, 0.0)
		var d := pos.distance_to(_stage.to_screen(at))
		if d < _tap_radius(at) and d < best_d:
			best_d = d
			best = {"kind": "ghost", "id": int(ghost["id"])}
	for flick: Dictionary in state["flickers"]:
		var spot: Dictionary = Logic.DECOY_SPOTS[int(flick["decoy"])]
		var at := Vector3(float(spot["x"]), 0.3, float(spot["z"]))
		var d := pos.distance_to(_stage.to_screen(at))
		if d < _tap_radius(at) and d < best_d:
			best_d = d
			best = {"kind": "decoy", "decoy": int(flick["decoy"])}
	return best


# ---------------------------------------------------------------- Ereignisse


## Logik-Ereignisse in SFX, Juice und Banner übersetzen.
func _drain_events() -> void:
	var events: Array = state["events"]
	for e: Dictionary in events:
		_handle_event(e)
	events.clear()


func _handle_event(e: Dictionary) -> void:
	match str(e["type"]):
		"catch":
			_on_catch(e)
		"decoy":
			_on_decoy()
		"booWave":
			_show_banner(I18nService.t("mg.ghostHunt.boo"))
			AudioDirector.try_play(self, "mg_combo")
			_stage.pulse_glow(0.9)
			_gooby.emote("scared", 1.2)
			if ctx.juice != null:
				ctx.juice.bloom_pulse(0.7)
		"booBonus":
			_show_banner(I18nService.t("mg.ghostHunt.booBonus", {"n": int(e["bonus"])}))
			AudioDirector.try_play(self, "mg_golden")
			_stage.pulse_glow(1.4)
			_gooby.play_for("celebrate", 1.2)
			_gooby.emote("ecstatic", 1.6)
			if ctx.juice != null:
				# Alle Buh-Geister erwischt: kleiner Feier-Moment.
				ctx.juice.hit_freeze(90)
				ctx.juice.confetti(46)
				ctx.juice.edge_glow(0.7, Color(0.75, 0.95, 1.0))
		"booEnd":
			_show_banner(I18nService.t("mg.ghostHunt.booMiss", {"n": int(e["caught"])}))
			AudioDirector.try_play(self, "mg_lose")
			_gooby.emote("sad", 1.4)
		"powerup":
			_show_banner(I18nService.t("mg.ghostHunt.%s" % str(e["kind"])))
			AudioDirector.try_play(self, "mg_golden")
			_stage.pulse_glow(1.1)
			_gooby.play_for("wave", 0.7)
			if ctx.juice != null:
				ctx.juice.bloom_pulse(0.9)
		"ghostGone":
			AudioDirector.try_play(self, "mg_spill")


func _on_catch(e: Dictionary) -> void:
	var spot: Dictionary = Logic.SPOTS[int(e["spot"])]
	var world := Vector3(float(spot["x"]), 1.05, float(spot["z"]))
	_sparks.burst(world)
	_stage.pulse_glow(0.5 + 0.2 * float(e["chain"]))
	_stage.shake(0.03, 0.18)
	# Gooby dreht sich zum Fang und jubelt — er JAGT mit, er schaut nicht zu.
	_gooby.face(atan2(world.x - _gooby.position.x, world.z - _gooby.position.z))
	_gooby.play_for("wave", 0.5)
	_gooby.swing(0.32, 24.0, Vector3.FORWARD)
	_gooby.emote("ecstatic", 0.9)
	var chain := int(e["chain"])
	# Fang-Kette klettert hörbar (Halbton pro Kettenglied).
	AudioDirector.try_play(
		self, "mg_perfect" if chain > 1 else "mg_good", FeelSfx.combo_pitch(chain)
	)
	if ctx.juice == null:
		return
	ctx.juice.float_text(_stage.to_screen(world), "+%d" % int(e["points"]), Color(1, 0.93, 0.72))
	ctx.juice.overlay_ring(_stage.to_screen(world), Color(0.75, 0.95, 1.0), 60.0)
	if chain >= 2:
		ctx.juice.show_combo(chain)
	if chain >= 3:
		ctx.juice.bloom_pulse(0.4)


func _on_decoy() -> void:
	AudioDirector.try_play(self, "mg_junk")
	_show_banner(I18nService.t("mg.ghostHunt.decoy"))
	_gooby.emote("dizzy", 1.2)
	_stage.shake(0.1, 0.32)
	if ctx.juice != null:
		ctx.juice.shake(0.4)
		ctx.juice.hit_flash(Color(0.75, 0.5, 0.95, 0.16), 180)
		ctx.juice.sfx("game_miss")
		ctx.juice.show_combo(0)


func _show_banner(text: String) -> void:
	_banner = text
	_banner_t = 1.4


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	AudioDirector.try_play(self, "mg_win")
	var result := Logic.run_meta(state)
	result["score"] = Logic.hunt_score(state)
	ctx.report_end(result)


func _update_labels() -> void:
	var tune: Dictionary = state["tune"]
	if bool(tune["ENDLESS"]):
		_score_label.text = I18nService.t(
			"mg.ghostHunt.escapes",
			{"n": int(state["escapedWaves"]), "max": int(tune["ENDLESS_ESCAPE_LIMIT"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - float(state["t"]))))
		_score_label.text = I18nService.t("mg.game.time", {"sec": left})
	var parts: Array[String] = []
	if int(state["chain"]) > 1:
		parts.append(I18nService.t("mg.ghostHunt.chainPill", {"n": int(state["chain"])}))
	if int(state["netLeft"]) > 0:
		parts.append(I18nService.t("mg.ghostHunt.netPill", {"n": int(state["netLeft"])}))
	if float(state["lanternT"]) > 0.0:
		parts.append(
			I18nService.t("mg.ghostHunt.lanternPill", {"n": int(ceil(float(state["lanternT"])))})
		)
	_chain_label.text = "  ".join(parts)


## Quader in einen SurfaceTool schreiben (Grabstein aus einem Guss).
func _add_box(st: SurfaceTool, at: Vector3, size: Vector3) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3(-1, -1, 1), Vector3(1, -1, 1), Vector3(1, 1, 1), Vector3(-1, 1, 1)],
		[Vector3(1, -1, -1), Vector3(-1, -1, -1), Vector3(-1, 1, -1), Vector3(1, 1, -1)],
		[Vector3(1, -1, 1), Vector3(1, -1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1)],
		[Vector3(-1, -1, -1), Vector3(-1, -1, 1), Vector3(-1, 1, 1), Vector3(-1, 1, -1)],
		[Vector3(-1, 1, 1), Vector3(1, 1, 1), Vector3(1, 1, -1), Vector3(-1, 1, -1)],
		[Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(-1, -1, 1)],
	]
	for face: Array in faces:
		for i: int in [0, 1, 2, 0, 2, 3]:
			st.add_vertex(at + (face[i] as Vector3) * h)


# ---------------------------------------------------------------- HUD 2D


## Nur noch das Ereignisband — die Szene selbst ist 3D.
func _draw() -> void:
	if _banner_t > 0.0:
		_draw_banner()


func _draw_banner() -> void:
	var fade := clampf(_banner_t / 0.4, 0.0, 1.0)
	var y := view_size.y * (0.2 if landscape else 0.24)
	var size := int(maxf(22.0, view_size.y * 0.032))
	draw_rect(
		Rect2(0.0, y - size * 1.2, view_size.x, size * 2.2), Color(0.1, 0.07, 0.16, 0.5 * fade)
	)
	draw_string(
		ThemeService.font(800),
		Vector2(0.0, y + size * 0.4),
		_banner,
		HORIZONTAL_ALIGNMENT_CENTER,
		view_size.x,
		size,
		Color(1.0, 0.9, 0.65, fade)
	)
