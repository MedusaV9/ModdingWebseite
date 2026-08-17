extends "res://scripts/minigames/games/_3dc_stage/stage3d.gd"
## Sternenhüpfer — 3D-Bühne (Agent 3D-C). Echter Weltraumkorridor: Gooby sitzt
## als PILOT auf einem Kenney-Speeder, der Blick geht die drei Bahnen entlang
## nach vorn. Meteore sind echte Space-Kit-Felsen, Sterne/Karotten schweben als
## Leuchtobjekte im Raum, dahinter zieht ein Sternenfeld mit Parallaxe vorbei.
##
## Die Bühne rechnet NUR Optik — jede Zahl kommt aus StarHopperLogic (Bahn,
## Streckenmeter, Schild, Wurmloch). Weltmaßstab wie im Web: 0,12 wu je Meter.

const Models := preload("res://scripts/minigames/games/_3dc_stage/models3d.gd")
const Puff := preload("res://scripts/minigames/games/_3dc_stage/puff3d.gd")
const Pool := preload("res://scripts/minigames/games/_3dc_stage/pool3d.gd")
const DIR := "res://assets/minigames/star_hopper/"

## Welteinheiten je Streckenmeter (Web: WU_PER_M).
const WU_PER_M := 0.12
## Länge des sichtbaren Korridors in Welteinheiten.
const TRACK_WU := 12.0
## Abstand der Bahnstreben (Welteinheiten) — das Tempogefühl.
const RUNG_STEP := 1.6
const RUNG_COUNT := 16
const STAR_COUNT := 260
const METEOR_POOL := 14
const PICKUP_POOL := 8
## W14 Kulisse: Leucht-Pylonen-Paare neben der Bahn (Abstand in wu).
const PYLON_STEP := 6.4
const PYLON_PAIRS := 5
## W16 Tempo-Gefühl (M10): Basis-Blickwinkel + FOV-Kick Richtung Vmax.
const HFOV_BASE := 54.0
const HFOV_MIN_V := 49.0
const HFOV_KICK := 7.0
## W16 Kulisse: Asteroiden-Gürtel unter/neben der Bahn. Der Gürtel ist in z
## PERIODISCH (BELT_UNIQUE Felsen je BELT_WRAP wu, BELT_BANDS Bänder), damit
## der fposmod-Wrap in _sync_scroll nahtlos bleibt (Pylonen-Prinzip).
const BELT_UNIQUE := 12
const BELT_BANDS := 4
const BELT_WRAP := 10.5
const COMET_COUNT := 3

var lane_x: Array = [-1.15, 0.0, 1.15]
var gooby: GoobyRig

var _ship: Node3D
var _ship_tilt: Node3D
var _meteors: Node3D
var _pickups: Node3D
var _rungs: Node3D
var _pylons: Node3D
var _stars: Node3D
var _shield_bubble: MeshInstance3D
var _wormhole: Node3D
var _warn: Array[MeshInstance3D] = []
var _thrust: GPUParticles3D
var _dust: GPUParticles3D
var _spark: GPUParticles3D
var _meteor_meshes: Array[Mesh] = []
var _star_mesh: Mesh
var _gold: Node3D
var _emotion := "happy"
var _lane_mats: Array[StandardMaterial3D] = []
var _belt: Node3D
var _comets: Node3D
var _speed_band := -1.0


func setup_stage(lanes: Array) -> void:
	lane_x = lanes
	build(
		{
			"space": true,
			# BELICHTUNGS-EICHUNG (Gegenrichtung zu den Tagbühnen): 49 % der
			# Pixel lagen unter Luma 25 — der Weltraum soff in Schwarz ab.
			# Etwas helleres Blau als Grundton + Milchstraße/Nebel füllen das
			# obere Drittel, ohne den Neon-Kontrast der Bahnen zu verlieren.
			"bg": Color(0.03, 0.026, 0.094),
			"ambient_color": Color(0.5, 0.52, 0.86),
			"ambient": 1.25,
			"sun_color": Color(1.0, 0.94, 0.88),
			"sun_energy": 2.6,
			"sun_dir": Vector3(-0.3, -0.5, -0.8),
			"fill_color": Color(1.0, 0.6, 0.88),
			"fill_energy": 1.1,
			"shadows": false,
			"glow": 0.45,
			"glow_bloom": 0.02,
			"glow_threshold": 1.0,
			"far": 90.0,
		}
	)
	# 54° waagerecht hält die drei Bahnen in beiden Formaten gleich breit; die
	# 49° senkrechte Untergrenze ist das Querformat-Sicherheitsnetz: das Schiff
	# steht 16,6° unter der Blickachse und fiele sonst aus dem Bild.
	set_hfov(HFOV_BASE, HFOV_MIN_V)
	camera.position = Vector3(0.0, 2.1, 4.3)
	camera.look_at_from_position(camera.position, Vector3(0.0, 0.75, -4.0), Vector3.UP)
	_build_nebula()
	_build_starfield()
	_build_track()
	_build_pylons()
	_build_ship()
	_build_pools()
	_build_belt()
	_build_effects()


## W14 Intro-Beat: Kamera schwebt aus erhöhter Totale (k=0) in die Spielpose
## (k=1) — reine Optik, die Bahn-Projektion für Popups läuft erst im Spiel.
## W16: Totale weiter raus und leicht nach links Richtung Ringplanet — vorher
## hob sie nur 1,4 m und der schöne Planet kam im Intro nie ins Bild.
func establish(k: float) -> void:
	var e := 1.0 - ease(clampf(k, 0.0, 1.0), 0.4)
	camera.position = Vector3(-2.4 * e, 2.1 + 3.3 * e, 4.3 + 2.9 * e)
	var look := Vector3(-1.6 * e, 0.75 + 1.4 * e, -4.0)
	camera.look_at_from_position(camera.position, look, Vector3.UP)


## W16 Tempo-Gefühl: FOV-Kick Richtung Vmax (M10, set_hfov-Bonus — das
## 3dc-Kit hat kein set_fov_bonus). band01 = 0 bei Basistempo, 1 bei Vmax.
func set_speed_band(band01: float) -> void:
	var band := clampf(band01, 0.0, 1.0)
	if is_equal_approx(band, _speed_band):
		return
	_speed_band = band
	set_hfov(HFOV_BASE + HFOV_KICK * band, HFOV_MIN_V)


func _exit_tree() -> void:
	# Die Karotten-Vorlage hängt nie im Baum (nur duplicate()-Quelle) und
	# muss deshalb von Hand freigegeben werden — sonst leaken Node, Meshes
	# und Materialien beim Beenden (REST5, EVAL-2 B4).
	if _gold != null and is_instance_valid(_gold):
		_gold.free()
	_gold = null


## Ganze Bühne je Frame aus dem Spielzustand nachziehen.
func sync(s: Dictionary) -> void:
	var traveled := float(s["traveled"])
	var elapsed := float(s["elapsed"])
	_sync_scroll(traveled)
	_sync_ship(s, elapsed)
	_sync_meteors(s["meteors"], traveled, elapsed)
	_sync_pickups(s["pickups"], traveled, elapsed)
	_sync_state(s, elapsed)


## Gooby-Emotion setzen (nur bei Wechsel, sonst flackert der Blend).
func feel(emotion: String) -> void:
	if gooby == null or _emotion == emotion:
		return
	_emotion = emotion
	gooby.set_emotion(emotion)


## Kurzer Funkenausbruch am Schiff (Schildtreffer, Einsammeln).
func spark_at(pos: Vector3, color: Color) -> void:
	Puff.fire(_spark, pos, color)


## Gooby hüpft im Sitz (Bahnwechsel) bzw. jubelt (goldene Karotte).
func cheer(clip: String) -> void:
	if gooby != null:
		gooby.play_clip(clip)


func ship_position() -> Vector3:
	return _ship.position


# ── Aufbau ────────────────────────────────────────────────────────────────


func _build_nebula() -> void:
	# Zwei riesige, weiche Farbschleier weit hinten: der Nachthimmel des Webs
	# (violett/magenta/teal) ohne Textur-Backerei.
	_build_planet()
	# Kräftiger als die erste Fassung (0,34/0,26/0,3): die Schleier waren im
	# fertigen Bild kaum zu ahnen, die obere Bildhälfte blieb schwarz.
	var tints := [
		[Vector3(-8.5, 4.0, -40.0), 26.0, Color(0.4, 0.2, 0.72, 0.46)],
		[Vector3(9.5, -1.0, -34.0), 20.0, Color(0.72, 0.24, 0.58, 0.36)],
		[Vector3(2.0, 7.5, -30.0), 15.0, Color(0.14, 0.45, 0.66, 0.42)],
	]
	for entry: Array in tints:
		var quad := MeshInstance3D.new()
		var mesh := QuadMesh.new()
		mesh.size = Vector2(float(entry[1]), float(entry[1]))
		quad.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = entry[2]
		mat.albedo_texture = load(DIR + "vfx/circle_05.png")
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		quad.material_override = mat
		quad.position = entry[0]
		add_child(quad)


## Ferner Ringplanet links oben — gibt dem Weltraum Tiefe und Maßstab.
func _build_planet() -> void:
	var planet := MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 7.0
	ball.height = 14.0
	ball.radial_segments = 24
	ball.rings = 12
	var mat := StandardMaterial3D.new()
	# Satter Koralle-Ton mit mehr Eigenleuchten: die blasse erste Fassung las
	# sich vor dem dunklen Feld als grauer Ball mit Unterlegscheibe.
	mat.albedo_color = Color(1.0, 0.56, 0.42)
	mat.roughness = 1.0
	mat.emission_enabled = true
	mat.emission = Color(0.62, 0.24, 0.4)
	mat.emission_energy_multiplier = 0.8
	ball.material = mat
	planet.mesh = ball
	planet.position = Vector3(-19.0, 11.0, -62.0)
	add_child(planet)
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 9.5
	torus.outer_radius = 12.5
	torus.rings = 24
	torus.ring_segments = 8
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(1.0, 0.72, 0.38, 0.75)
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	torus.material = rmat
	ring.mesh = torus
	ring.rotation_degrees = Vector3(74.0, 0.0, 18.0)
	planet.add_child(ring)


func _build_starfield() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = load(DIR + "vfx/star_03.png")
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = STAR_COUNT
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260725
	for i in STAR_COUNT:
		var depth := rng.randf()
		# Hohler Mantel: nie IM Korridor, sonst fliegen Sterne durch das Schiff.
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var pos := Vector3(
			side * rng.randf_range(3.2, 24.0),
			rng.randf_range(-7.0, 15.0),
			rng.randf_range(-44.0, 4.0)
		)
		if rng.randf() < 0.4:
			pos.x = rng.randf_range(-24.0, 24.0)
			pos.y = rng.randf_range(4.0, 17.0)
		var size := 0.9 + depth * 2.6
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), pos))
		mm.set_instance_color(i, Color(1.0, 0.95 - depth * 0.12, 0.82 + depth * 0.18, 0.6 + depth))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.extra_cull_margin = 60.0
	_stars = Node3D.new()
	_stars.add_child(mmi)
	add_child(_stars)
	_build_milky_way(mat)


## Milchstraßen-Band: ein zweites MultiMesh aus 150 winzigen, dichten Sternen
## auf einer Diagonale quer über den oberen Himmel. Füllt das schwarze obere
## Drittel für genau EINEN Draw-Call und gibt dem Korridor eine Richtung.
func _build_milky_way(mat: StandardMaterial3D) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.12, 0.12)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = 150
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	for i in 150:
		# Band von links unten nach rechts oben, quer hinter dem Korridor.
		var t := rng.randf()
		var across := rng.randfn(0.0, 2.6)
		var pos := Vector3(
			lerpf(-26.0, 26.0, t) + across * 0.4,
			lerpf(2.0, 15.0, t) + across,
			-46.0 + rng.randf_range(-4.0, 4.0)
		)
		var size := 0.6 + rng.randf() * 1.6
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * size), pos))
		var warm := rng.randf()
		mm.set_instance_color(
			i, Color(0.85 + warm * 0.15, 0.85, 1.0 - warm * 0.2, 0.35 + rng.randf() * 0.5)
		)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.extra_cull_margin = 60.0
	_stars.add_child(mmi)


func _build_track() -> void:
	# Bahnen als schwebende Glasstreifen + leuchtende Kanten. W16: Alpha
	# 0,2 → 0,35 — vorher waren die drei Streifen vor dem dunklen Feld fast
	# unsichtbar; die Materialien wandern in _lane_mats, damit _sync_ship
	# die AKTIVE Bahn atmen lassen kann (Befund 1).
	_lane_mats.clear()
	for i in lane_x.size():
		var strip := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.02, 0.03, TRACK_WU * 2.0)
		strip.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.36, 0.78, 0.35)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.emission_enabled = true
		mat.emission = Color(0.22, 0.34, 0.8)
		mat.emission_energy_multiplier = 0.16
		strip.mesh.material = mat
		strip.position = Vector3(float(lane_x[i]), -0.42, -TRACK_WU * 0.55)
		add_child(strip)
		_lane_mats.append(mat)
	for i in lane_x.size() + 1:
		var edge := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.05, 0.05, TRACK_WU * 2.0)
		edge.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.62, 0.92, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(0.4, 0.85, 1.0)
		mat.emission_energy_multiplier = 1.5
		edge.mesh.material = mat
		var span := (float(lane_x[lane_x.size() - 1]) - float(lane_x[0])) / (lane_x.size() - 1)
		edge.position = Vector3(float(lane_x[0]) + span * (i - 0.5), -0.41, -TRACK_WU * 0.55)
		add_child(edge)
	_build_rungs()
	_build_warn_lanes()


func _build_rungs() -> void:
	var bar := BoxMesh.new()
	bar.size = Vector3(3.7, 0.04, 0.12)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.78, 1.0, 0.42)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.42, 0.72, 1.0)
	mat.emission_energy_multiplier = 0.9
	bar.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = bar
	mm.instance_count = RUNG_COUNT
	for i in RUNG_COUNT:
		mm.set_instance_transform(
			i, Transform3D(Basis.IDENTITY, Vector3(0.0, -0.4, -float(i) * RUNG_STEP))
		)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.extra_cull_margin = 40.0
	_rungs = Node3D.new()
	_rungs.add_child(mmi)
	add_child(_rungs)


## W14 Kulissen-Dichte: Leucht-Pylonen-Paare ziehen als Tor-Reihe am Korridor
## vorbei — füllt die leeren Blau-Flächen NEBEN der Bahn und verstärkt das
## Tempogefühl. Ein MultiMesh, wrappt in _sync_scroll.
func _build_pylons() -> void:
	var post := BoxMesh.new()
	post.size = Vector3(0.09, 1.1, 0.09)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.5, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.36, 0.7, 1.0)
	mat.emission_energy_multiplier = 1.1
	post.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = post
	mm.instance_count = PYLON_PAIRS * 2
	var span := absf(float(lane_x[lane_x.size() - 1])) + 1.0
	for i in PYLON_PAIRS:
		var z := -float(i) * PYLON_STEP
		var basis := Basis.IDENTITY
		mm.set_instance_transform(i * 2, Transform3D(basis, Vector3(-span, 0.12, z)))
		mm.set_instance_transform(i * 2 + 1, Transform3D(basis, Vector3(span, 0.12, z)))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.extra_cull_margin = 40.0
	_pylons = Node3D.new()
	_pylons.add_child(mmi)
	add_child(_pylons)


func _build_warn_lanes() -> void:
	for i in lane_x.size():
		var warn := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(1.05, 3.2, TRACK_WU)
		warn.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.3, 0.32, 0.16)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		warn.mesh.material = mat
		warn.position = Vector3(float(lane_x[i]), 1.2, -TRACK_WU * 0.5)
		warn.visible = false
		add_child(warn)
		_warn.append(warn)


func _build_ship() -> void:
	_ship = Node3D.new()
	add_child(_ship)
	_ship_tilt = Node3D.new()
	_ship.add_child(_ship_tilt)
	var craft := Models.node(DIR + "craft_speederA.glb", 1.75, false)
	craft.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	craft.position.y = -0.12
	_ship_tilt.add_child(craft)
	gooby = GoobyRig.new()
	gooby.name = "GoobyPilot"
	gooby.scale = Vector3.ONE * 0.95
	gooby.position = Vector3(0.0, 0.12, -0.02)
	gooby.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	_ship_tilt.add_child(gooby)
	gooby.set_emotion(_emotion)
	# Schildblase (nur sichtbar, wenn der Schild aktiv ist).
	_shield_bubble = MeshInstance3D.new()
	var bubble := SphereMesh.new()
	bubble.radius = 0.72
	bubble.height = 1.44
	_shield_bubble.mesh = bubble
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.45, 0.85, 1.0, 0.22)
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	bmat.cull_mode = BaseMaterial3D.CULL_FRONT
	_shield_bubble.mesh.material = bmat
	_shield_bubble.visible = false
	_ship.add_child(_shield_bubble)


func _build_pools() -> void:
	for name_part in ["meteor.glb", "meteor_detailed.glb", "meteor_half.glb"]:
		var mesh := Models.first_mesh(DIR + name_part)
		if mesh != null:
			_meteor_meshes.append(mesh)
	_meteors = Pool.new()
	add_child(_meteors)
	_meteors.build(_make_meteor, METEOR_POOL)
	_star_mesh = _make_star_mesh()
	# ACHTUNG: _gold ist NUR duplicate()-Vorlage und hängt nie im Baum —
	# ohne das free() in _exit_tree leakt der ganze Karotten-Teilbaum samt
	# Meshes/Materialien beim Beenden (REST5, EVAL-2 B4).
	_gold = Models.node(DIR + "carrot.glb", 0.55, false)
	Models.tint(_gold, Color(1.0, 0.72, 0.2), 0.9)
	_pickups = Pool.new()
	add_child(_pickups)
	_pickups.build(_make_pickup, PICKUP_POOL)
	_build_wormhole()


func _make_meteor() -> Node3D:
	var holder := Node3D.new()
	var mesh_node := MeshInstance3D.new()
	var index := _meteors.get_child_count() % maxi(1, _meteor_meshes.size())
	if not _meteor_meshes.is_empty():
		mesh_node.mesh = _meteor_meshes[index]
	var box := mesh_node.mesh.get_aabb() if mesh_node.mesh != null else AABB()
	var longest := maxf(0.01, maxf(box.size.x, maxf(box.size.y, box.size.z)))
	mesh_node.scale = Vector3.ONE * (0.95 / longest)
	mesh_node.position = -box.get_center() * (0.95 / longest)
	holder.add_child(mesh_node)
	# Warmer Glutsaum, damit Meteore vor dem dunklen Feld nicht verschwinden.
	var halo := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(2.1, 2.1)
	halo.mesh = quad
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	# 0,5 Deckkraft ging im dunklen Feld unter — die Felsen lasen sich als
	# braune Kartoffeln statt als glühende Brocken.
	mat.albedo_color = Color(1.0, 0.5, 0.24, 0.68)
	mat.albedo_texture = load(DIR + "vfx/circle_05.png")
	halo.material_override = mat
	holder.add_child(halo)
	return holder


func _make_star_mesh() -> Mesh:
	var prism := PrismMesh.new()
	prism.size = Vector3(0.42, 0.42, 0.42)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.42)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.86, 0.35)
	mat.emission_energy_multiplier = 2.6
	prism.material = mat
	return prism


func _make_pickup() -> Node3D:
	var holder := Node3D.new()
	var star := MeshInstance3D.new()
	star.name = "Star"
	star.mesh = _star_mesh
	holder.add_child(star)
	var gold: Node3D = _gold.duplicate()
	gold.name = "Gold"
	holder.add_child(gold)
	var shield := MeshInstance3D.new()
	shield.name = "Shield"
	var torus := TorusMesh.new()
	torus.inner_radius = 0.24
	torus.outer_radius = 0.38
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.5, 0.88, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.45, 0.85, 1.0)
	mat.emission_energy_multiplier = 2.4
	torus.material = mat
	shield.mesh = torus
	holder.add_child(shield)
	var halo := MeshInstance3D.new()
	halo.name = "Halo"
	var quad := QuadMesh.new()
	quad.size = Vector2(1.4, 1.4)
	halo.mesh = quad
	var hmat := StandardMaterial3D.new()
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	hmat.albedo_color = Color(1.0, 0.9, 0.5, 0.55)
	hmat.albedo_texture = load(DIR + "vfx/circle_05.png")
	halo.material_override = hmat
	holder.add_child(halo)
	return holder


## W16 Befund 3: Asteroiden-Gürtel unter/neben der Bahn — füllt die leere
## untere Bildhälfte/Flanken im Hochkant. EIN MultiMesh (1 Draw-Call); die
## Felsen wiederholen sich exakt alle BELT_WRAP wu, damit der Wrap in
## _sync_scroll nahtlos ist. Deterministischer Seed, spart den Korridor aus.
func _build_belt() -> void:
	var rock: Mesh = SphereMesh.new()
	if not _meteor_meshes.is_empty():
		rock = _meteor_meshes[0]
	var box := rock.get_aabb()
	var longest := maxf(0.01, maxf(box.size.x, maxf(box.size.y, box.size.z)))
	var fit := 0.8 / longest
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = rock
	mm.instance_count = BELT_UNIQUE * BELT_BANDS
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260731
	for i in BELT_UNIQUE:
		# Flanken ab |x| 3,4 und unter y −1,6: nah genug für Tiefe, aber ohne
		# die Bahn zu überlappen (sonst lesen sich Felsen als Hindernis).
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var pos := Vector3(
			side * rng.randf_range(3.4, 9.0),
			rng.randf_range(-4.8, -2.0),
			rng.randf_range(2.0 - BELT_WRAP, 2.0)
		)
		if rng.randf() < 0.35:
			pos.x = rng.randf_range(-6.0, 6.0)
			pos.y = rng.randf_range(-7.0, -3.6)
		var spin := Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		var basis := Basis.from_euler(spin).scaled(Vector3.ONE * fit * rng.randf_range(0.6, 1.8))
		for band in BELT_BANDS:
			var shifted := pos + Vector3(0.0, 0.0, -float(band) * BELT_WRAP)
			mm.set_instance_transform(band * BELT_UNIQUE + i, Transform3D(basis, shifted))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.extra_cull_margin = 60.0
	# Dunkles Einheitsmaterial: nahe Felsen fingen sonst das rosa Fülllicht
	# und überstrahlten — der Gürtel soll Silhouette bleiben, nicht Hindernis.
	var rock_mat := StandardMaterial3D.new()
	rock_mat.albedo_color = Color(0.34, 0.26, 0.22)
	rock_mat.roughness = 1.0
	mmi.material_override = rock_mat
	_belt = Node3D.new()
	_belt.add_child(mmi)
	add_child(_belt)
	_build_comets()


## W16 Befund 3 (Teil 2): drei ferne Kometen-Streifen in der Tiefe — ziehen
## mit eigener, langsamer Parallaxe vorbei (Sternenfeld-Wrap-Prinzip).
func _build_comets() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(0.18, 3.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_texture = load(DIR + "vfx/star_03.png")
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = COMET_COUNT
	var rng := RandomNumberGenerator.new()
	rng.seed = 987654
	for i in COMET_COUNT:
		var side := -1.0 if i % 2 == 0 else 1.0
		var pos := Vector3(
			side * rng.randf_range(7.0, 15.0),
			rng.randf_range(-5.0, 3.0),
			rng.randf_range(-38.0, -16.0)
		)
		var basis := Basis.from_euler(Vector3(0.0, rng.randf_range(-0.5, 0.5), side * 0.6))
		mm.set_instance_transform(i, Transform3D(basis.scaled(Vector3.ONE), pos))
		mm.set_instance_color(i, Color(0.75, 0.92, 1.0, 0.28 + rng.randf() * 0.18))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.extra_cull_margin = 60.0
	_comets = Node3D.new()
	_comets.add_child(mmi)
	add_child(_comets)


func _build_wormhole() -> void:
	_wormhole = Node3D.new()
	_wormhole.position = Vector3(0.0, 0.3, -5.5)
	_wormhole.visible = false
	add_child(_wormhole)
	for i in 5:
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 1.5 + i * 0.22
		torus.outer_radius = 1.72 + i * 0.22
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.62, 0.42, 1.0)
		mat.emission_enabled = true
		mat.emission = Color(0.7, 0.45, 1.0)
		mat.emission_energy_multiplier = 2.2 - i * 0.3
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		torus.material = mat
		ring.mesh = torus
		ring.position = Vector3(0.0, 0.0, -float(i) * 1.1)
		ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		_wormhole.add_child(ring)


func _build_effects() -> void:
	_thrust = (
		Puff
		. stream(
			DIR + "vfx/circle_05.png",
			{
				"amount": 26,
				"lifetime": 0.5,
				"size": 0.3,
				"dir": Vector3(0.0, 0.0, 1.0),
				"spread": 12.0,
				"speed": Vector2(2.2, 3.6),
				"gravity": Vector3.ZERO,
				"color": Color(1.0, 0.66, 0.3, 0.9),
				"color_end": Color(1.0, 0.3, 0.5, 0.0),
				"scale_range": Vector2(0.6, 1.1),
			}
		)
	)
	_thrust.position = Vector3(0.0, 0.02, 0.45)
	_ship.add_child(_thrust)
	_dust = (
		Puff
		. stream(
			DIR + "vfx/star_03.png",
			{
				"amount": 40,
				"lifetime": 1.5,
				"size": 0.14,
				"dir": Vector3(0.0, 0.0, 1.0),
				"spread": 4.0,
				"speed": Vector2(6.0, 11.0),
				"gravity": Vector3.ZERO,
				"color": Color(0.85, 0.92, 1.0, 0.8),
				"color_end": Color(0.7, 0.8, 1.0, 0.0),
				"box": Vector3(3.0, 2.0, 0.4),
				"local": false,
			}
		)
	)
	_dust.position = Vector3(0.0, 0.6, -9.0)
	add_child(_dust)
	_spark = (
		Puff
		. burst(
			DIR + "vfx/star_03.png",
			{
				"amount": 26,
				"lifetime": 0.6,
				"size": 0.22,
				"dir": Vector3.UP,
				"spread": 180.0,
				"speed": Vector2(1.6, 3.4),
				"gravity": Vector3.ZERO,
				"color": Color(1.0, 0.9, 0.5, 1.0),
				"color_end": Color(1.0, 0.6, 0.3, 0.0),
				"local": false,
			}
		)
	)
	add_child(_spark)


# ── Takt ──────────────────────────────────────────────────────────────────


func _sync_scroll(traveled: float) -> void:
	var wrap := fposmod(traveled * WU_PER_M, RUNG_STEP)
	_rungs.position.z = wrap
	_pylons.position.z = fposmod(traveled * WU_PER_M, PYLON_STEP)
	# Sternenfeld mit Parallaxe (viel langsamer als die Bahn).
	_stars.position.z = fposmod(traveled * WU_PER_M * 0.12, 6.0)
	# W16: Gürtel driftet mit halber Bahngeschwindigkeit (Tiefen-Parallaxe),
	# der Wrap ist dank z-periodischem Muster nahtlos; Kometen sehr langsam.
	_belt.position.z = fposmod(traveled * WU_PER_M * 0.5, BELT_WRAP)
	_comets.position.z = fposmod(traveled * WU_PER_M * 0.18, 7.0)


func _sync_ship(s: Dictionary, elapsed: float) -> void:
	var lane_f := float(s["lane_visual"])
	# W16 Befund 1: die Bahn unter dem Schiff ATMET (Emission pulsiert),
	# Nachbarbahnen bleiben auf Grundhelligkeit — die aktive Spur ist endlich
	# markiert, der Bahnwechsel blendet weich über lane_visual mit.
	for i in _lane_mats.size():
		var near := clampf(1.0 - absf(lane_f - float(i)), 0.0, 1.0)
		var breathe := 0.55 + 0.2 * sin(elapsed * 5.0)
		_lane_mats[i].emission_energy_multiplier = 0.16 + near * breathe
	_ship.position.x = lane_pos(lane_f)
	_ship.position.y = 0.02 + sin(elapsed * 2.2) * 0.03
	var tilt := (lane_f - float(s["lane"])) * 0.55
	var roll := float(s["roll"])
	if roll > 0.0:
		tilt += TAU * (1.0 - roll / maxf(0.001, float(s["roll_max"])))
	_ship_tilt.rotation.z = tilt
	var pop := float(s["pop"])
	var scale := 1.0 + 0.13 * (pop / maxf(0.001, float(s["pop_max"])))
	_ship_tilt.scale = Vector3.ONE * scale
	if gooby != null:
		gooby.set_locomotion(clampf(float(s["speed"]) / 19.0, 0.0, 1.0))
	_thrust.speed_scale = 0.8 + float(s["speed"]) / 14.0
	_shield_bubble.visible = bool(s["shielded"]) or float(s["invuln"]) > 0.0
	if _shield_bubble.visible:
		var pulse := 1.0 + 0.06 * sin(elapsed * 8.0)
		_shield_bubble.scale = Vector3.ONE * pulse


func _sync_meteors(meteors: Array, traveled: float, elapsed: float) -> void:
	_meteors.begin()
	for meteor: Dictionary in meteors:
		var z := -(float(meteor["m"]) - traveled) * WU_PER_M
		if z < -TRACK_WU or z > 2.5:
			continue
		var node: Node3D = _meteors.take()
		if node == null:
			break
		node.position = Vector3(lane_pos(float(meteor["lane"])), 0.05, z)
		var spin := float(meteor["spin"]) + elapsed * 1.3
		node.rotation = Vector3(spin * 0.7, spin, spin * 0.4)
	_meteors.flush()


func _sync_pickups(pickups: Array, traveled: float, elapsed: float) -> void:
	_pickups.begin()
	for pickup: Dictionary in pickups:
		var z := -(float(pickup["m"]) - traveled) * WU_PER_M
		if z < -TRACK_WU or z > 2.5:
			continue
		var node: Node3D = _pickups.take()
		if node == null:
			break
		var kind := str(pickup["kind"])
		node.position = Vector3(
			lane_pos(float(pickup["lane"])), 0.22 + sin(elapsed * 3.0 + z) * 0.06, z
		)
		node.rotation.y = elapsed * 2.2
		node.get_node("Star").visible = kind == "star"
		node.get_node("Gold").visible = kind == "gold"
		node.get_node("Shield").visible = kind == "shield"
		var halo := node.get_node("Halo") as MeshInstance3D
		halo.visible = true
		var tint := Color(1.0, 0.9, 0.5, 0.55)
		if kind == "gold":
			tint = Color(1.0, 0.66, 0.2, 0.7)
		elif kind == "shield":
			tint = Color(0.5, 0.88, 1.0, 0.6)
		(halo.material_override as StandardMaterial3D).albedo_color = tint
	_pickups.flush()


func _sync_state(s: Dictionary, elapsed: float) -> void:
	var warn_on := str(s["shower_state"]) == "warn"
	var danger: Array = s["shower_danger"]
	var pulse := 0.12 + 0.16 * absf(sin(elapsed * 13.0))
	for i in _warn.size():
		var on := warn_on and danger.has(i)
		_warn[i].visible = on
		if on:
			var mat := _warn[i].mesh.material as StandardMaterial3D
			mat.albedo_color = Color(1.0, 0.32, 0.34, pulse)
	var hole := float(s["wormhole_left"])
	_wormhole.visible = hole > 0.0
	if hole > 0.0:
		var f := hole / maxf(0.001, float(s["wormhole_max"]))
		_wormhole.scale = Vector3.ONE * (0.7 + (1.0 - f) * 0.55)
		_wormhole.rotation.z = elapsed * 1.4
		_wormhole.position.z = -5.5 + (1.0 - f) * 4.0


## Bahn-Index (auch als Bruch beim Wechsel) → x in Welteinheiten.
func lane_pos(lane_f: float) -> float:
	var low := int(floor(lane_f))
	var high := mini(lane_x.size() - 1, low + 1)
	low = clampi(low, 0, lane_x.size() - 1)
	return lerpf(float(lane_x[low]), float(lane_x[high]), lane_f - floor(lane_f))
