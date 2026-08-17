class_name GhostHuntScenery
extends RefCounted
## Weltbau der Geisterjagd (G5/P31-Split, Muster gvz_hud.gd): ghost_hunt.gd
## stand mit 999 Zeilen exakt am 1000-Zeilen-Limit — der komplette
## Friedhofsgarten (Bühne, Mond, Zaun, Verstecke, Attrappen, Geister-Pool,
## Aufsammler, Gooby, Funken) wohnt jetzt hier. Reiner AUFBAU: dieser Helfer
## baut EINMAL in `view` (die Spielszene) hinein und schreibt die
## Sync-Anker (_stage, _gooby, _ghosts, _decoys, _tokens, _mist, _sky,
## _lantern_light, _sparks) direkt auf die Szene; der laufende Abgleich
## (Sync/Tap/Events) bleibt in ghost_hunt.gd. Die Farb-Konstanten der
## Sync-Schicht (GHOST_TINT & Co.) liest der Bauer über `view.<KONST>` —
## eine Quelle, kein Drift.

const Logic := preload("res://scripts/minigames/games/ghost_hunt/ghost_hunt_logic.gd")
const Stage3D := preload("res://scripts/minigames/games/_3da_stage/stage3d.gd")
const Props3D := preload("res://scripts/minigames/games/_3da_stage/props3d.gd")
const GoobyActor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Spark3D := preload("res://scripts/minigames/games/_3da_stage/spark3d.gd")

const ASSETS := "res://assets/minigames/ghost_hunt/"

## So viele Geister können gleichzeitig stehen (Buh-Welle: BOO_COUNT = 5).
const GHOST_RIGS := 6
const STONE := Color(0.68, 0.67, 0.76)
const TURF := Color(0.24, 0.33, 0.29)
## Umfärbung des Kenney-Kürbisses (`leafsFall` = Körper, `grass` = Stiel).
const PUMPKIN_SKIN := {
	"leafsFall": Color(0.93, 0.47, 0.16),
	"grass": Color(0.36, 0.5, 0.28),
}

## Die Spielszene (ghost_hunt.gd) — bewusst untypisiert (kein class_name
## dort; ein Preload wäre zirkulär). Liefert die Farb-Konstanten und nimmt
## die gebauten Sync-Anker entgegen.
var view

## Mesh-Caches: Gesichts-Plättchen und Laken-Drehkörper (einmal je Aufbau).
var _sheet: ArrayMesh
var _face: Mesh


func _init(game_view: Node2D) -> void:
	view = game_view


## Kompletten Friedhofsgarten in die Szene bauen (einziger Einstiegspunkt).
func build_world() -> void:
	var stage: Stage3D = Stage3D.new()
	view._stage = stage
	view.add_child(stage)
	# Dämmerungsviolett wie im Web (§C10.1 „distinct look"): kaltes Mondlicht,
	# warmer Kürbisschein, kräftiger Glow, damit die Laternen wirklich glühen.
	(
		stage
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
	stage.add_child(Props3D.ground(Vector2(70.0, 70.0), Props3D.flat(TURF), 0.0))
	_build_moon()
	_build_yard()
	_build_mist()
	_build_spots()
	_build_decoys()
	_build_ghosts()
	_build_tokens()
	_build_gooby()
	var sparks: Spark3D = Spark3D.new()
	view._sparks = sparks
	stage.add_child(sparks)
	(
		sparks
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
	var sky := Node3D.new()
	view._sky = sky
	view._stage.add_child(sky)
	# Nicht zu weit weg: die Kamera blickt steil nach unten, ein Mond in 34 m
	# läge unter der Bodenebene und wäre schlicht verdeckt.
	var moon := Props3D.halo(0.6, Color(1.0, 0.96, 0.82, 0.95))
	moon.position = Vector3(-3.2, 6.0, -20.0)
	sky.add_child(moon)
	var haze := Props3D.halo(1.7, Color(0.72, 0.68, 1.0, 0.16))
	haze.position = Vector3(-3.2, 6.0, -20.2)
	sky.add_child(haze)


## Friedhofsgarten: Zaun ums Feld, tote Bäume, Stümpfe, Büsche, Pilze und ein
## Trampelpfad. Alles Massenware — ein Draw-Call je Sorte.
func _build_yard() -> void:
	var stage: Stage3D = view._stage
	var yard := Vector3(0.0, 0.0, -3.6)
	var gate := func(at: Vector3) -> bool: return at.z > 0.9
	_build_fence()
	# Bewusst kleiner und weiter draußen als im ersten Versuch: hochkant blickt
	# die Kamera steil, große Bäume am inneren Kranz füllen sonst den halben
	# Himmel und werden oben abgeschnitten.
	stage.add_child(
		Props3D.scatter(ASSETS + "tree_pineTallA.glb", 3.8, 10, 10.4, yard, 1.5, 0.4, gate)
	)
	stage.add_child(Props3D.scatter(ASSETS + "tree_oak.glb", 3.1, 8, 13.0, yard, 1.8, 1.7, gate))
	stage.add_child(Props3D.scatter(ASSETS + "stump_round.glb", 0.36, 6, 6.2, yard, 0.9, 2.4, gate))
	stage.add_child(Props3D.scatter(ASSETS + "log.glb", 0.3, 5, 5.6, yard, 1.1, 3.1, gate))
	stage.add_child(
		Props3D.scatter(ASSETS + "plant_bushLarge.glb", 0.62, 12, 6.8, yard, 1.2, 0.9, gate)
	)
	stage.add_child(
		Props3D.scatter(ASSETS + "grass_large.glb", 0.34, 22, 5.4, yard, 1.4, 2.0, gate)
	)
	stage.add_child(
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
	stage.add_child(Props3D.swarm_mesh(slab, path, 10.0))
	_build_gate()
	_build_stars()


## Friedhofstor im Vordergrund: zwei Pfeiler mit Kürbislaternen. Sie rahmen
## das Bild unten ein — ohne sie ist der Nahbereich eine leere Rasenfläche.
func _build_gate() -> void:
	var stage: Stage3D = view._stage
	var lantern: Color = view.LANTERN_TINT
	var stone := Props3D.flat(Color(0.46, 0.43, 0.52), 0.95)
	for sign_x: float in [-1.0, 1.0]:
		var at := Vector3(sign_x * 2.35, 0.0, 1.05)
		stage.add_child(Props3D.box(Vector3(0.42, 1.5, 0.42), stone, at + Vector3.UP * 0.75))
		stage.add_child(
			Props3D.box(
				Vector3(0.58, 0.12, 0.58),
				Props3D.flat(Color(0.38, 0.35, 0.44), 0.95),
				at + Vector3.UP * 1.56
			)
		)
		var lamp := Props3D.box(
			Vector3(0.26, 0.3, 0.26), Props3D.glow(lantern, 1.8), at + Vector3.UP * 1.77
		)
		stage.add_child(lamp)
		var halo := Props3D.halo(0.68, Color(lantern, 0.28))
		halo.position = at + Vector3.UP * 1.77
		stage.add_child(halo)


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
		view._stage.add_child(wisp)
		view._mist.append({"node": wisp, "home": entry[0] as Vector3})


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
	view._sky.add_child(Props3D.swarm_mesh(star, poses, 60.0))


func _build_fence() -> void:
	var poses: Array = []
	for i in 30:
		var a := TAU * float(i) / 30.0
		var at := Vector3(sin(a) * 6.6, 0.0, -3.6 + cos(a) * 5.4)
		if at.z > 1.0:
			continue
		poses.append(Props3D.pose(at, -a, 1.0))
	view._stage.add_child(
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
				view._stage.add_child(_build_crypt(at))
			_:
				graves.append(Props3D.pose(at, float(spot["id"]) * 0.4 - 0.6, 1.0))
	view._stage.add_child(Props3D.swarm_mesh(_grave_mesh(), graves, 8.0))
	# Materialnamen aus dem GLB: `leafsFall` ist der Kürbiskörper, `grass` der
	# Stiel — ohne die Umfärbung bleiben die Kürbisse kit-lachsrosa.
	view._stage.add_child(
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
	var lantern: Color = view.LANTERN_TINT
	for spot: Dictionary in Logic.DECOY_SPOTS:
		var holder := Node3D.new()
		holder.position = Vector3(float(spot["x"]), 0.0, float(spot["z"]))
		var body := Props3D.model(ASSETS + "crop_pumpkin.glb", 0.5)
		Props3D.repaint(body, PUMPKIN_SKIN)
		holder.add_child(body)
		var face_mat := Props3D.glow(lantern, 0.0)
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
		var halo := Props3D.halo(0.85, Color(lantern, 0.0))
		halo.position = Vector3(0.0, 0.26, 0.0)
		holder.add_child(halo)
		view._stage.add_child(holder)
		view._decoys.append({"root": holder, "face": face_mat, "halo": halo})


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
	var tint: Color = view.GHOST_TINT
	for i in GHOST_RIGS:
		var root := Node3D.new()
		root.visible = false
		var mat := Props3D.glass(tint)
		mat.emission_enabled = true
		mat.emission = tint
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
		var halo := Props3D.halo(1.0, Color(tint, 0.16))
		halo.position = Vector3(0.0, 0.4, 0.0)
		root.add_child(halo)
		view._stage.add_child(root)
		view._ghosts.append({"root": root, "mat": mat, "halo": halo, "sheet": sheet})


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
		var tint: Color = view.LANTERN_TINT if kind == "lantern" else view.NET_TINT
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
		view._stage.add_child(holder)
		view._tokens.append({"root": holder, "kind": kind, "halo": halo})


## Gooby steht mit der Laterne am Tor und blickt in den Hof (Dreiviertelrücken
## wie im Web) — er dreht sich zu jedem Geist, den er fängt.
func _build_gooby() -> void:
	var lantern: Color = view.LANTERN_TINT
	var gooby: GoobyActor = GoobyActor.new()
	view._gooby = gooby
	view._stage.add_child(gooby)
	gooby.position = Vector3(-1.55, 0.0, 0.95)
	gooby.mount(1.0, 2.5)
	gooby.set_mood("happy")
	var lamp := Node3D.new()
	lamp.add_child(Props3D.box(Vector3(0.15, 0.19, 0.15), Props3D.glow(lantern, 1.6)))
	lamp.add_child(
		Props3D.box(
			Vector3(0.19, 0.04, 0.19),
			Props3D.flat(Color(0.45, 0.33, 0.24), 0.8),
			Vector3(0.0, 0.11, 0.0)
		)
	)
	lamp.add_child(Props3D.halo(0.34, Color(lantern, 0.35)))
	lamp.position = Vector3(0.4, 0.58, 0.2)
	gooby.attach(lamp)
	var light := OmniLight3D.new()
	light.light_color = lantern
	light.light_energy = 1.5
	light.omni_range = 4.6
	light.omni_attenuation = 1.6
	light.position = gooby.position + Vector3(0.4, 0.72, 0.2)
	view._lantern_light = light
	view._stage.add_child(light)


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
