extends "res://scripts/minigames/games/_3dc_stage/stage3d.gd"
## Tortenwerkstatt — 3D-Backstube (Agent 3D-C). Das Web zeigte eine flache
## Seitenansicht auf ein gerades Band; hier steht dieselbe Strecke als ECHTE
## Werkstatt: Laufband mit mitlaufenden Querstreben, Ofentunnel mit Glutfenster,
## zehn Düsen an der Versorgungsschiene, Versandkiste, Gästetheke — und Gooby
## als BÄCKER am Ofenausgang (echtes Rig, Mütze, Emotionen).
##
## Projektionsvertrag: die Kamera blickt mit `PITCH_DEG` Neigung auf die
## Bandebene z = 0; die Bandkoordinate s IST die Welt-x-Achse, y zählt Meter
## über der Bandoberkante. `purble_place.project()` fragt genau diese Kamera,
## damit die 2D-Overlays (Backuhr, Fangfenster, Auftragskarten) pixelgenau auf
## den 3D-Requisiten sitzen.
##
## Warum überhaupt geneigt? Aus reiner Seitensicht sind runde, eckige und
## Herz-Torten dieselbe Silhouette — erst der Blick schräg von oben macht das
## §C9.2-Merkmal „Form" lesbar.

const Models := preload("res://scripts/minigames/games/_3dc_stage/models3d.gd")
const Puff := preload("res://scripts/minigames/games/_3dc_stage/puff3d.gd")
const Cake := preload("res://scripts/minigames/games/purble_place/purble_place_cake.gd")
const Cake3D := preload("res://scripts/minigames/games/purble_place/purble_place_cake3d.gd")
const Shop3D := preload("res://scripts/minigames/games/purble_place/purble_place_shop3d.gd")
const DIR := "res://assets/minigames/purble_place/"

## Kameraneigung nach unten (Grad) und fester senkrechter Blickwinkel.
const PITCH_DEG := 12.0
const VFOV := 44.0
## Boden der Backstube (Meter unter der Bandoberkante).
const FLOOR_Y := -0.55
## Rückwand.
const WALL_Z := -4.2
## Gästetheke.
const COUNTER_Z := -2.05
## Halbe Bandtiefe.
const BELT_HALF_Z := 0.42
## Höhe der Versorgungsschiene und der Düsenköpfe (= Fallhöhe FALL_M).
const RAIL_Y := 1.15
const NOZZLE_Y := 0.55
## Querstreben des Bandes: Abstand in Metern und Anzahl im Umlauf.
const SLAT_PITCH := 0.25
const SLAT_COUNT := 34
## Volle Breite einer Torte in Metern (2D: ppm · 0,6).
const CAKE_W := 0.58
## Rig-Höhe bei scale 1 (gooby.glb) und Wunschgröße des Bäckers.
const RIG_HEIGHT := 1.13
const GOOBY_HEIGHT := 1.78
## Bäckerplatz: liegt im Fenster, das in JEDER Kamerastellung sichtbar bleibt
## (Kamera klemmt auf Bandmitte ±1,4 m, Hochkant zeigt ±1,8 m).
const GOOBY_S := 3.38

var gooby: GoobyRig

var _stations: Array = []
var _tune: Dictionary = {}
var _slats: MultiMeshInstance3D
var _pans: Node3D
var _drops: Node3D
var _splats: Node3D
var _guests: Node3D
var _guest_list: Array[Node3D] = []
var _heads: Dictionary = {}
var _pan_free: Array[Node3D] = []
var _pan_busy: Array[Node3D] = []
var _drop_free: Array[MeshInstance3D] = []
var _drop_busy: Array[MeshInstance3D] = []
var _splat_free: Array[MeshInstance3D] = []
var _splat_busy: Array[MeshInstance3D] = []
var _oven_glow: MeshInstance3D
var _oven_mat: StandardMaterial3D
var _ship_zone: MeshInstance3D
var _ship_mat: StandardMaterial3D
var _smoke: GPUParticles3D
var _flour: GPUParticles3D
var _sparkle: GPUParticles3D
var _emotion := "happy"
var _cam_s := 3.0
var _window := 3.6


## `stations` = Logic.STATIONS, `tune` = die Runden-Zahlen (Ofen-/Versandmarken).
func setup_stage(stations: Array, tune: Dictionary) -> void:
	_stations = stations
	_tune = tune
	build(
		{
			"sky_top": Color(0.55, 0.72, 0.93),
			"sky_horizon": Color(1.0, 0.91, 0.8),
			"ground_horizon": Color(0.9, 0.8, 0.7),
			"ground_bottom": Color(0.66, 0.56, 0.48),
			"sky_energy": 0.5,
			"ambient": 0.5,
			"sun_color": Color(1.0, 0.9, 0.74),
			"sun_energy": 2.1,
			"sun_dir": Vector3(-0.35, -0.78, -0.52),
			"fill_color": Color(0.74, 0.84, 1.0),
			"fill_energy": 0.55,
			"shadows": false,
			"glow": 0.3,
			"glow_bloom": 0.05,
			"glow_threshold": 0.95,
			"far": 70.0,
		}
	)
	Shop3D.build(self)
	_build_belt()
	_build_oven()
	_build_nozzles()
	_build_spawn()
	_build_ship()
	_build_guests()
	_build_gooby()
	_pans = Node3D.new()
	add_child(_pans)
	_drops = Node3D.new()
	add_child(_drops)
	_splats = Node3D.new()
	add_child(_splats)
	_build_effects()


## Rahmung je Frame. `ppm` und `belt_px` sind die Layoutwerte des Spiels: die
## Kamera wird so gestellt, dass die Bandoberkante bei `cam_s` genau auf
## `belt_px` liegt und ein Meter dort ~`ppm` Pixel misst.
func frame(cam_s: float, ppm: float, belt_px: float, size: Vector2) -> void:
	if size.x <= 1.0 or size.y <= 1.0 or ppm <= 0.0:
		return
	_cam_s = cam_s
	_window = size.x / ppm
	apply_size(size)
	var half_h := size.y * 0.5 / ppm
	var dist := half_h / tan(deg_to_rad(VFOV) * 0.5)
	# Zielhöhe aus der Vorgabe „Band liegt auf belt_px" (Herleitung siehe Kopf:
	# ty = k·R / (cos θ − k·sin θ) mit k = (belt_px − Bildmitte) / (ppm·R)).
	var pitch := deg_to_rad(PITCH_DEG)
	var k := (belt_px - size.y * 0.5) / (ppm * dist)
	var ty := k * dist / maxf(0.05, cos(pitch) - k * sin(pitch))
	set_half_height(half_h, dist)
	camera.position = Vector3(cam_s, ty + dist * sin(pitch), dist * cos(pitch))
	camera.rotation_degrees = Vector3(-PITCH_DEG, 0.0, 0.0)
	_place_guests()


## Bandmeter → Bildschirmpixel. DAS ist die Projektion, die das Spiel benutzt.
func project(s: float, y: float) -> Vector2:
	if camera == null:
		return Vector2.ZERO
	return camera.unproject_position(Vector3(s, y, 0.0))


## Alles Bewegliche aus dem Logikzustand neu setzen.
func sync(line: Dictionary, scroll: float, oven_heat: float) -> void:
	_sync_slats(scroll)
	_sync_pans(line["pans"])
	_sync_drops(line["drops"], float(line["t"]))
	_sync_splats(line["splats"])
	_sync_locks(line["lockouts"])
	_oven_mat.emission_energy_multiplier = 0.8 + 3.4 * oven_heat
	_smoke.emitting = oven_heat > 0.05
	_ship_mat.emission_energy_multiplier = 2.6 if _ship_armed(line) else 0.35


## Bildschirmanker über dem Kopf von Gast `index` (dort hängt die Wunschblase).
func guest_anchor(index: int) -> Vector2:
	if index < 0 or index >= _guest_list.size() or camera == null:
		return Vector2.ZERO
	var guest := _guest_list[index]
	return camera.unproject_position(guest.global_position + Vector3(0.0, 1.62, 0.0))


## Gooby-Emotion (nur bei Wechsel, sonst flackert der Blend).
func feel(emotion: String) -> void:
	if gooby == null or _emotion == emotion:
		return
	_emotion = emotion
	gooby.set_emotion(emotion)


## Mehlwolke an der Bandstelle `s` (Tropfen eingefangen / Klecks).
func flour(s: float, tint: Color) -> void:
	Puff.fire(_flour, Vector3(s, 0.12, 0.0), tint)


## Versand geglückt: Funken an der Kiste + Glow-Puls + Gooby jubelt.
func celebrate(s: float) -> void:
	Puff.fire(_sparkle, Vector3(s, 0.45, 0.1), Color(1.0, 0.88, 0.5))
	pulse_glow(0.7)
	if gooby != null:
		gooby.play_clip("celebrate")


## Frisch gebacken: Dampfstoß am Ofenausgang.
func bake_puff() -> void:
	Puff.fire(_flour, Vector3(float(_tune["OVEN_END_S"]), 0.7, 0.0), Color(1.0, 0.97, 0.9))
	pulse_glow(0.35)


# ── Aufbau ────────────────────────────────────────────────────────────────


func _build_belt() -> void:
	var band := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(7.6, 0.16, BELT_HALF_Z * 2.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.38, 0.35, 0.4)
	mat.roughness = 0.95
	mat.metallic_specular = 0.1
	box.material = mat
	band.mesh = box
	band.position = Vector3(3.0, -0.08, 0.0)
	add_child(band)

	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color(0.74, 0.57, 0.44)
	frame_mat.roughness = 0.85
	for side in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		var rbox := BoxMesh.new()
		rbox.size = Vector3(7.6, 0.1, 0.08)
		rbox.material = frame_mat
		rail.mesh = rbox
		rail.position = Vector3(3.0, -0.19, side * (BELT_HALF_Z + 0.05))
		add_child(rail)

	# Rollen + Beine: je 1 MultiMesh.
	var roller := CylinderMesh.new()
	roller.top_radius = 0.09
	roller.bottom_radius = 0.09
	roller.height = BELT_HALF_Z * 2.1
	roller.radial_segments = 10
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.64, 0.49, 0.38)
	roller.material = rmat
	var roll_poses: Array = []
	for i in 16:
		roll_poses.append(
			Transform3D(Basis(Vector3.RIGHT, PI * 0.5), Vector3(-0.5 + i * 0.5, -0.24, 0.0))
		)
	add_child(Models.swarm([{"mesh": roller, "xform": Transform3D.IDENTITY}], roll_poses, 20.0))

	var leg := BoxMesh.new()
	leg.size = Vector3(0.1, 0.32, 0.1)
	leg.material = frame_mat
	var leg_poses: Array = []
	for i in 5:
		for z in [-0.3, 0.3]:
			leg_poses.append(
				Transform3D(Basis.IDENTITY, Vector3(0.3 + i * 1.4, FLOOR_Y + 0.16, float(z)))
			)
	add_child(Models.swarm([{"mesh": leg, "xform": Transform3D.IDENTITY}], leg_poses, 20.0))

	# Querstreben laufen mit — 1 MultiMesh, Transforms je Frame.
	var slat := BoxMesh.new()
	slat.size = Vector3(0.035, 0.022, BELT_HALF_Z * 1.86)
	var slat_mat := StandardMaterial3D.new()
	slat_mat.albedo_color = Color(0.15, 0.14, 0.17)
	slat_mat.roughness = 1.0
	slat_mat.metallic_specular = 0.0
	slat.material = slat_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = slat
	mm.instance_count = SLAT_COUNT
	_slats = MultiMeshInstance3D.new()
	_slats.multimesh = mm
	_slats.extra_cull_margin = 20.0
	add_child(_slats)
	_sync_slats(0.0)


func _build_oven() -> void:
	var s0 := float(_tune["OVEN_START_S"])
	var s1 := float(_tune["OVEN_END_S"])
	var mid := (s0 + s1) * 0.5
	var width := s1 - s0
	var body := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, 0.92, 1.14)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.93, 0.62, 0.44)
	mat.roughness = 0.7
	box.material = mat
	body.mesh = box
	body.position = Vector3(mid, 0.46, 0.0)
	add_child(body)

	var top := MeshInstance3D.new()
	var tbox := BoxMesh.new()
	tbox.size = Vector3(width + 0.12, 0.14, 1.24)
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(0.84, 0.5, 0.34)
	tbox.material = tmat
	top.mesh = tbox
	top.position = Vector3(mid, 0.95, 0.0)
	add_child(top)

	# Glutfenster in der Vorderwand.
	_oven_mat = StandardMaterial3D.new()
	_oven_mat.albedo_color = Color(0.35, 0.16, 0.1)
	_oven_mat.emission_enabled = true
	_oven_mat.emission = Color(1.0, 0.55, 0.24)
	_oven_mat.emission_energy_multiplier = 1.0
	_oven_glow = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(width * 0.74, 0.4)
	_oven_glow.mesh = quad
	_oven_glow.material_override = _oven_mat
	_oven_glow.position = Vector3(mid, 0.5, 0.58)
	add_child(_oven_glow)

	var chimney := MeshInstance3D.new()
	var cbox := CylinderMesh.new()
	cbox.top_radius = 0.11
	cbox.bottom_radius = 0.13
	cbox.height = 0.5
	cbox.radial_segments = 12
	cbox.material = tmat
	chimney.mesh = cbox
	chimney.position = Vector3(s1 - 0.18, 1.25, -0.2)
	add_child(chimney)

	# Ein-/Ausfahrt: dunkle Tunnelmäuler, damit die Form wirklich verschwindet.
	var mouth_mat := StandardMaterial3D.new()
	mouth_mat.albedo_color = Color(0.16, 0.09, 0.08)
	mouth_mat.roughness = 1.0
	for x in [s0, s1]:
		var mouth := MeshInstance3D.new()
		var mquad := QuadMesh.new()
		mquad.size = Vector2(0.62, 0.5)
		mouth.mesh = mquad
		mouth.material_override = mouth_mat
		mouth.rotation_degrees = Vector3(0.0, 90.0 if float(x) == s0 else -90.0, 0.0)
		mouth.position = Vector3(float(x) + (0.01 if float(x) == s0 else -0.01), 0.24, 0.0)
		add_child(mouth)


func _build_nozzles() -> void:
	var pipe := CylinderMesh.new()
	pipe.top_radius = 0.035
	pipe.bottom_radius = 0.035
	pipe.height = RAIL_Y - NOZZLE_Y
	pipe.radial_segments = 8
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.76, 0.72, 0.7)
	steel.metallic = 0.35
	steel.roughness = 0.4
	pipe.material = steel
	var poses: Array = []
	for st: Dictionary in _stations:
		if not bool(st["drop"]):
			continue
		poses.append(
			Transform3D(Basis.IDENTITY, Vector3(float(st["s"]), (RAIL_Y + NOZZLE_Y) * 0.5, -0.1))
		)
	add_child(Models.swarm([{"mesh": pipe, "xform": Transform3D.IDENTITY}], poses, 20.0))

	var rail := MeshInstance3D.new()
	var rbox := BoxMesh.new()
	rbox.size = Vector3(7.6, 0.11, 0.16)
	var rail_mat := StandardMaterial3D.new()
	rail_mat.albedo_color = Color(0.72, 0.66, 0.63)
	rail_mat.metallic = 0.25
	rbox.material = rail_mat
	rail.mesh = rbox
	rail.position = Vector3(3.0, RAIL_Y + 0.05, -0.1)
	add_child(rail)

	for st: Dictionary in _stations:
		if not bool(st["drop"]):
			continue
		var tint := _station_color(st)
		var head := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.15
		cone.bottom_radius = 0.05
		cone.height = 0.18
		cone.radial_segments = 12
		head.mesh = cone
		var mat := StandardMaterial3D.new()
		mat.albedo_color = tint
		mat.roughness = 0.5
		head.material_override = mat
		head.position = Vector3(float(st["s"]), NOZZLE_Y + 0.09, -0.1)
		add_child(head)
		_heads[str(st["id"])] = {"node": head, "mat": mat, "tint": tint}
		var tank := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.14
		ball.height = 0.24
		ball.radial_segments = 12
		ball.rings = 7
		tank.mesh = ball
		var tmat := StandardMaterial3D.new()
		tmat.albedo_color = tint.lightened(0.12)
		tmat.roughness = 0.35
		tank.material_override = tmat
		tank.position = Vector3(float(st["s"]), RAIL_Y + 0.2, -0.1)
		add_child(tank)


func _build_spawn() -> void:
	var s := float(_tune["SPAWN_S"])
	var hopper := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.42
	cone.bottom_radius = 0.14
	cone.height = 0.44
	cone.radial_segments = 14
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.58, 0.77, 0.9)
	mat.roughness = 0.55
	cone.material = mat
	hopper.mesh = cone
	hopper.position = Vector3(s, 0.85, 0.0)
	add_child(hopper)
	var tube := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.14
	cyl.bottom_radius = 0.14
	cyl.height = 0.22
	cyl.radial_segments = 12
	cyl.material = mat
	tube.mesh = cyl
	tube.position = Vector3(s, 0.52, 0.0)
	add_child(tube)


func _build_ship() -> void:
	var s := float(_tune["SHIP_S"])
	var half := float(_tune["SHIP_HALF_M"])
	var crate := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.62, 0.5, 0.6)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.86, 0.67, 0.46)
	mat.roughness = 0.9
	box.material = mat
	crate.mesh = box
	crate.position = Vector3(s + 0.62, 0.25, -0.05)
	add_child(crate)
	var ribbon_mat := StandardMaterial3D.new()
	ribbon_mat.albedo_color = Color(0.95, 0.6, 0.72)
	for entry: Array in [[Vector3(0.64, 0.08, 0.62)], [Vector3(0.08, 0.52, 0.62)]]:
		var band := MeshInstance3D.new()
		var bbox := BoxMesh.new()
		bbox.size = entry[0]
		bbox.material = ribbon_mat
		band.mesh = bbox
		band.position = Vector3(s + 0.62, 0.3, -0.04)
		add_child(band)

	# Leuchtstreifen auf dem Band = Versandzone (grün, wenn scharf).
	_ship_mat = StandardMaterial3D.new()
	_ship_mat.albedo_color = Color(0.42, 0.78, 0.5)
	_ship_mat.emission_enabled = true
	_ship_mat.emission = Color(0.4, 0.9, 0.5)
	_ship_mat.emission_energy_multiplier = 0.4
	_ship_zone = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(half * 2.0, BELT_HALF_Z * 1.8)
	_ship_zone.mesh = quad
	_ship_zone.material_override = _ship_mat
	_ship_zone.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_ship_zone.position = Vector3(s, 0.011, 0.0)
	add_child(_ship_zone)


## Drei Gäste an der Ladentheke hinter dem Band. Die Gruppe folgt der Kamera
## (wie im Web, wo die Gäste feste Bildschirmplätze hatten) — die durchgehende
## Theke verdeckt, dass sie mitwandern.
func _build_guests() -> void:
	var counter := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(16.0, 1.32, 0.55)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.88, 0.72, 0.55)
	mat.roughness = 0.85
	box.material = mat
	counter.mesh = box
	counter.position = Vector3(3.0, FLOOR_Y + 0.66, COUNTER_Z)
	add_child(counter)
	var ledge := MeshInstance3D.new()
	var lbox := BoxMesh.new()
	lbox.size = Vector3(16.0, 0.09, 0.72)
	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color(0.95, 0.84, 0.7)
	lbox.material = lmat
	ledge.mesh = lbox
	ledge.position = Vector3(3.0, FLOOR_Y + 1.36, COUNTER_Z)
	add_child(ledge)

	const TINTS: Array[Color] = [
		Color(0.55, 0.75, 0.9), Color(0.95, 0.66, 0.55), Color(0.62, 0.82, 0.6)
	]
	_guests = Node3D.new()
	add_child(_guests)
	for i in TINTS.size():
		var guest := Node3D.new()
		# y = 0 (nicht FLOOR_Y): die Gäste stehen auf einem Podest hinter der
		# Theke, sonst schluckt die Thekenkante Kopf UND Wunschblase.
		guest.position = Vector3(float(i - 1) * 1.45, 0.28, COUNTER_Z - 0.62)
		_guests.add_child(guest)
		_guest_list.append(guest)
		var body := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.24
		cone.bottom_radius = 0.4
		cone.height = 1.02
		cone.radial_segments = 12
		var bmat := StandardMaterial3D.new()
		bmat.albedo_color = TINTS[i]
		bmat.roughness = 0.9
		cone.material = bmat
		body.mesh = cone
		body.position = Vector3(0.0, 0.51, 0.0)
		guest.add_child(body)
		var head := MeshInstance3D.new()
		var ball := SphereMesh.new()
		ball.radius = 0.26
		ball.height = 0.5
		ball.radial_segments = 14
		ball.rings = 8
		var hmat := StandardMaterial3D.new()
		hmat.albedo_color = Color(0.996, 0.906, 0.671)
		hmat.roughness = 0.85
		ball.material = hmat
		head.mesh = ball
		head.position = Vector3(0.0, 1.24, 0.0)
		guest.add_child(head)
		var eye := SphereMesh.new()
		eye.radius = 0.036
		eye.height = 0.072
		eye.radial_segments = 8
		eye.rings = 5
		var emat := StandardMaterial3D.new()
		emat.albedo_color = Color(0.2, 0.16, 0.14)
		eye.material = emat
		for side in [-1.0, 1.0]:
			var dot := MeshInstance3D.new()
			dot.mesh = eye
			dot.position = Vector3(side * 0.09, 1.27, 0.235)
			guest.add_child(dot)


func _build_gooby() -> void:
	gooby = GoobyRig.new()
	gooby.name = "GoobyBaker"
	gooby.scale = Vector3.ONE * (GOOBY_HEIGHT / RIG_HEIGHT)
	gooby.position = Vector3(GOOBY_S, FLOOR_Y, -0.98)
	gooby.rotation_degrees = Vector3(0.0, -18.0, 0.0)
	add_child(gooby)
	gooby.set_emotion(_emotion)
	gooby.play_clip("build_hammer")
	_build_hat()


## Bäckermütze (fester Aufsatz auf Kopfhöhe des Rigs).
func _build_hat() -> void:
	var hat := Node3D.new()
	hat.position = Vector3(0.0, 0.82, -0.03)
	hat.rotation_degrees = Vector3(-6.0, 0.0, 5.0)
	gooby.add_child(hat)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.99, 0.97)
	mat.roughness = 0.95
	var band := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.155
	cyl.bottom_radius = 0.17
	cyl.height = 0.1
	cyl.radial_segments = 14
	cyl.material = mat
	band.mesh = cyl
	hat.add_child(band)
	var puff := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.17
	ball.height = 0.26
	ball.radial_segments = 14
	ball.rings = 8
	ball.material = mat
	puff.mesh = ball
	puff.position = Vector3(0.0, 0.14, 0.0)
	hat.add_child(puff)


func _build_effects() -> void:
	_smoke = (
		Puff
		. stream(
			DIR + "vfx/circle_05.png",
			{
				"amount": 10,
				"lifetime": 1.9,
				"size": 0.3,
				"dir": Vector3.UP,
				"spread": 14.0,
				"speed": Vector2(0.45, 0.85),
				"gravity": Vector3(0.0, 0.3, 0.0),
				"color": Color(1.0, 1.0, 1.0, 0.28),
				"color_end": Color(1.0, 1.0, 1.0, 0.0),
				"add": false,
				"scale_range": Vector2(0.6, 1.7),
			}
		)
	)
	_smoke.position = Vector3(float(_tune["OVEN_END_S"]) - 0.18, 1.55, -0.2)
	_smoke.emitting = false
	add_child(_smoke)

	_flour = (
		Puff
		. burst(
			DIR + "vfx/circle_05.png",
			{
				"amount": 16,
				"lifetime": 0.6,
				"size": 0.16,
				"dir": Vector3.UP,
				"spread": 180.0,
				"speed": Vector2(0.8, 2.0),
				"gravity": Vector3(0.0, -3.4, 0.0),
				"color": Color(1.0, 0.95, 0.88, 1.0),
				"color_end": Color(1.0, 0.92, 0.84, 0.0),
				"add": false,
				"local": false,
			}
		)
	)
	add_child(_flour)

	_sparkle = (
		Puff
		. burst(
			DIR + "vfx/star_03.png",
			{
				"amount": 20,
				"lifetime": 0.9,
				"size": 0.2,
				"dir": Vector3.UP,
				"spread": 65.0,
				"speed": Vector2(1.6, 3.2),
				"gravity": Vector3(0.0, -3.0, 0.0),
				"color": Color(1.0, 0.9, 0.55, 1.0),
				"color_end": Color(1.0, 0.72, 0.4, 0.0),
				"add": true,
				"local": false,
			}
		)
	)
	add_child(_sparkle)


# ── Takt ──────────────────────────────────────────────────────────────────


func _place_guests() -> void:
	if _guests == null:
		return
	_guests.position.x = _cam_s
	var spread := clampf(_window * 0.27, 0.85, 1.6)
	for i in _guest_list.size():
		var guest := _guest_list[i]
		guest.position.x = float(i - 1) * spread


func _sync_slats(scroll: float) -> void:
	var mm := _slats.multimesh
	var phase := fposmod(scroll, SLAT_PITCH)
	for i in SLAT_COUNT:
		var x := -0.6 + i * SLAT_PITCH + phase
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(x, 0.017, 0.0)))


func _sync_pans(pans: Array) -> void:
	for node in _pan_busy:
		node.visible = false
		_pan_free.append(node)
	_pan_busy.clear()
	for pan: Dictionary in pans:
		var node := _take_pan()
		node.visible = true
		node.position = Vector3(float(pan["s"]), 0.02, 0.0)
		Cake3D.dress(node, pan)
		_pan_busy.append(node)


func _sync_drops(drops: Array, now: float) -> void:
	for node in _drop_busy:
		node.visible = false
		_drop_free.append(node)
	_drop_busy.clear()
	var fall := float(_tune["FALL_SEC"])
	for drop: Dictionary in drops:
		var id := str(drop["station"])
		if not _heads.has(id):
			continue
		var entry: Dictionary = _heads[id]
		var frac := clampf((now - float(drop["firedAt"])) / maxf(0.001, fall), 0.0, 1.0)
		var node := _take_drop()
		node.visible = true
		node.position = Vector3(
			(_heads[id]["node"] as MeshInstance3D).position.x,
			NOZZLE_Y * (1.0 - frac) + 0.07,
			-0.1 + 0.1 * frac
		)
		var mat := node.material_override as StandardMaterial3D
		mat.albedo_color = entry["tint"]
		_drop_busy.append(node)


func _sync_splats(splats: Array) -> void:
	for node in _splat_busy:
		node.visible = false
		_splat_free.append(node)
	_splat_busy.clear()
	var ttl_max := float(_tune["SPLAT_TTL_SEC"])
	for splat: Dictionary in splats:
		var node := _take_splat()
		node.visible = true
		node.position = Vector3(float(splat["s"]), 0.024, 0.0)
		var fade := clampf(float(splat["ttl"]) / maxf(0.001, ttl_max), 0.0, 1.0)
		var mat := node.material_override as StandardMaterial3D
		mat.albedo_color = Color(0.6, 0.42, 0.34, 0.4 + 0.45 * fade)
		_splat_busy.append(node)


func _sync_locks(lockouts: Dictionary) -> void:
	for id: String in _heads:
		var entry: Dictionary = _heads[id]
		var tint: Color = entry["tint"]
		var locked := float(lockouts.get(id, 0.0)) > 0.0
		(entry["mat"] as StandardMaterial3D).albedo_color = tint.darkened(0.3) if locked else tint


func _ship_armed(line: Dictionary) -> bool:
	var ship_s := float(_tune["SHIP_S"])
	for pan: Dictionary in line["pans"]:
		if absf(float(pan["s"]) - ship_s) <= float(_tune["SHIP_HALF_M"]) + 0.0001:
			if pan["bake"] != null:
				return true
	return false


# ── Torten ────────────────────────────────────────────────────────────────


func _take_pan() -> Node3D:
	if not _pan_free.is_empty():
		return _pan_free.pop_back()
	var node := Cake3D.make(CAKE_W)
	_pans.add_child(node)
	return node


func _take_drop() -> MeshInstance3D:
	if not _drop_free.is_empty():
		return _drop_free.pop_back()
	var node := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.075
	mesh.height = 0.19
	mesh.radial_segments = 10
	mesh.rings = 6
	node.mesh = mesh
	node.material_override = StandardMaterial3D.new()
	_drops.add_child(node)
	return node


func _take_splat() -> MeshInstance3D:
	if not _splat_free.is_empty():
		return _splat_free.pop_back()
	var node := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.16
	mesh.bottom_radius = 0.16
	mesh.height = 0.02
	mesh.radial_segments = 12
	node.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	node.material_override = mat
	_splats.add_child(node)
	return node


func _station_color(st: Dictionary) -> Color:
	var kind := str(st["kind"])
	if kind == "teig":
		return Cake.SPONGE[str(st["value"])]
	if kind == "guss":
		return Cake.ICING[str(st["value"])]
	if kind == "deko":
		return Cake.DEKO[str(st["value"])]
	return Color(0.969, 0.906, 0.784)
