extends Node3D
## ECHTER 3D-DISCO-CLUB für die Tanzparty (FB-4, MP-C-Politur): Noten fallen
## als leuchtende Kugeln mit Bahnfarben-Halo durch geschiente Glasbahnen auf
## KAMERAZUGEWANDTE Trefferringe über einer glühenden Trefferlinie. Dahinter
## pumpt die Bühne im Takt: Schachbrettboden wechselt die Glutfarbe auf jeden
## Beat, eine Equalizer-Wand tanzt, Boxentürme flankieren die Bahnen, die
## Spiegelkugel dreht und poppt. Gooby (echtes Rig) ist der Star: er hüpft
## und schwingt auf JEDEN Beat, mit der Serienstufe wächst die Energie.
## Alle Anker kommen als CANVAS-PIXEL aus der View und werden 1:1 in
## Weltkoordinaten umgerechnet — Timing/Punkte bleiben komplett in
## dance_party.gd/DancePartyLogic.
##
## W15/GAMESQA2-Bühnenmitte (Audit: "Bühne mittig lange leer"): ein
## PUBLIKUM aus acht Mini-Goobys hüpft phasenversetzt im Takt vor der
## Bühne, eine Wimpel-Lichterkette in den Bahnfarben spannt sich durch die
## leere Mitte und schwingt zum Beat, die Scheinwerferkegel PUMPEN im Takt
## mit. Noten-Lesbarkeit: jede Note bekommt eine dunkle Rückscheibe und
## einen dickeren Halo — sie hebt sich damit auch von hellen Kegeln ab.
## Timing/Sim unverändert (zertifiziert).

const Stage3D := preload("res://scripts/minigames/games/_3dc_stage/stage3d.gd")
const Actor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")

const CAM_DIST := 10.0
const HALF_H := 4.2
const LANE_COLORS: Array[Color] = [
	Color(1.0, 0.48, 0.66),
	Color(0.35, 0.79, 0.73),
	Color(1.0, 0.82, 0.4),
]
## Glutfarben des Bodens je Serienstufe (0…3).
const TIER_GLOW: Array[Color] = [
	Color(0.55, 0.4, 0.75),
	Color(0.4, 0.75, 0.7),
	Color(0.95, 0.5, 0.65),
	Color(1.0, 0.8, 0.4),
]

var stage: Node3D
var gooby: Node3D

var _vp := Vector2(390.0, 844.0)
var _lanes: Array[MeshInstance3D] = []
var _rails: Array[MeshInstance3D] = []
var _rings: Array[MeshInstance3D] = []
var _pads: Array[MeshInstance3D] = []
var _cones: Array[MeshInstance3D] = []
var _note_pool: Array[Array] = [[], [], []]
var _ball: Node3D
var _ball_mesh: MeshInstance3D
var _ball_mat: StandardMaterial3D
var _floor_tiles: MultiMeshInstance3D
var _hit_bar: MeshInstance3D
var _hit_bar_mat: StandardMaterial3D
var _eq: MultiMeshInstance3D
var _speakers: Array[Node3D] = []
var _woofer_mats: Array[StandardMaterial3D] = []
var _hit_burst: GPUParticles3D
var _encore_light: OmniLight3D
var _spot: OmniLight3D
var _hit_ring_r := 0.5
var _beat_idx := -1
var _swing_side := 1.0
## W15: Publikum (Körper/Köpfe/Ohren als je EIN MultiMesh) + Basisplätze.
var _crowd_bodies: MultiMeshInstance3D
var _crowd_heads: MultiMeshInstance3D
var _crowd_ears: MultiMeshInstance3D
var _crowd_spots: Array[Vector3] = []
## W15: Wimpel-Lichterkette durch die Bühnenmitte (Anker aus layout()).
var _bunting: MultiMeshInstance3D
var _bunting_y := 2.0
var _bunting_half_w := 3.0


func setup_stage() -> void:
	stage = Stage3D.new()
	add_child(stage)
	(
		stage
		. build(
			{
				# Dunkler Club: Farbhintergrund statt Himmel, kühles Restlicht,
				# der Glow trägt Noten, Ringe und Spiegelkugel.
				"space": true,
				"bg": Color(0.07, 0.05, 0.14),
				"ambient_color": Color(0.5, 0.42, 0.7),
				"ambient": 0.55,
				"sun_dir": Vector3(0.2, -0.9, -0.4),
				"sun_color": Color(0.8, 0.75, 1.0),
				"sun_energy": 0.4,
				"fill_color": Color(0.9, 0.6, 0.9),
				"fill_energy": 0.18,
				"glow": 0.5,
				"glow_threshold": 0.6,
				"shadows": false,
				"far": 80.0,
			}
		)
	)
	_build_club()
	_build_gooby()
	_build_lanes()
	_hit_burst = (
		Fx
		. particles(
			{
				"color": Color(1.0, 0.95, 0.7, 0.95),
				"amount": 18,
				"lifetime": 0.5,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(1.5, 3.2),
				"spread": 180.0,
				"gravity": Vector3(0.0, -1.5, 0.0),
				"size": Vector2(0.05, 0.13),
				"additive": true,
			}
		)
	)
	add_child(_hit_burst)
	_encore_light = OmniLight3D.new()
	_encore_light.light_color = Color(1.0, 0.8, 0.4)
	_encore_light.light_energy = 0.0
	_encore_light.omni_range = 14.0
	_encore_light.position = Vector3(0.0, 2.0, 2.0)
	add_child(_encore_light)


## Bahnen, Schienen, Trefferringe + Pads und die glühende Trefferlinie.
func _build_lanes() -> void:
	for i in 3:
		var lane := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2.ONE
		# W14 Quick-Win: 0,12-Glas soff unter den Scheinwerferkegeln ab —
		# die Bahnen waren nur Haarlinien (Audit a=3). 0,2 macht sie zu Flächen.
		quad.material = Fx.glass(Color(LANE_COLORS[i], 0.2), true)
		lane.mesh = quad
		lane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(lane)
		_lanes.append(lane)
		for _side in 2:
			var rail := MeshInstance3D.new()
			var rail_mesh := BoxMesh.new()
			rail_mesh.size = Vector3(0.09, 1.0, 0.09)  # W14 Quick-Win: 0,045 zu dünn
			rail_mesh.material = Fx.glow(LANE_COLORS[i], 0.7)
			rail.mesh = rail_mesh
			rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(rail)
			_rails.append(rail)
		# Dunkles Pad hinter dem Ring: die Trefferzone hebt sich vom Boden ab.
		var pad := MeshInstance3D.new()
		var pad_mesh := CylinderMesh.new()
		pad_mesh.top_radius = 0.5
		pad_mesh.bottom_radius = 0.5
		pad_mesh.height = 0.04
		pad_mesh.radial_segments = 22
		var pad_mat := Fx.flat(Color(0.1, 0.07, 0.18, 0.9))
		pad_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pad_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pad_mesh.material = pad_mat
		pad.mesh = pad_mesh
		pad.rotation_degrees.x = 90.0
		pad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(pad)
		_pads.append(pad)
		# Trefferring KAMERAZUGEWANDT — als flache Scheibe war er unsichtbar.
		var ring := Fx.ring(0.5, 0.07, LANE_COLORS[i])
		ring.rotation_degrees.x = 90.0
		add_child(ring)
		_rings.append(ring)
	_hit_bar = MeshInstance3D.new()
	var bar_mesh := BoxMesh.new()
	bar_mesh.size = Vector3(1.0, 0.035, 0.03)
	_hit_bar_mat = Fx.glow(Color(1.0, 0.92, 0.98), 0.5)
	_hit_bar_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_hit_bar_mat.albedo_color.a = 0.55
	bar_mesh.material = _hit_bar_mat
	_hit_bar.mesh = bar_mesh
	_hit_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_hit_bar)


## Schachbrett-Grundanstrich — Startzustand, im Lauf übermalt _pulse_stage().
func _paint_floor(tier: int) -> void:
	var glow := TIER_GLOW[clampi(tier, 0, TIER_GLOW.size() - 1)]
	var base := Color(0.42, 0.32, 0.6)
	var mm := _floor_tiles.multimesh
	for i in 60:
		var col := i % 10
		var row := i / 10
		mm.set_instance_color(i, glow * 0.7 if (col + row) % 2 == 0 else base)


func _build_club() -> void:
	# Pulsierender Kachelboden: Grundviolett + Glutfarbe im Schachbrett.
	_floor_tiles = MultiMeshInstance3D.new()
	var tile := BoxMesh.new()
	tile.size = Vector3(1.16, 0.1, 1.16)
	tile.material = Fx.flat(Color(0.22, 0.14, 0.34))
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = tile
	mm.instance_count = 60
	for i in 60:
		var col := i % 10
		var row := i / 10
		mm.set_instance_transform(
			i,
			Transform3D(
				Basis.IDENTITY, Vector3(-5.4 + float(col) * 1.2, 0.0, -0.6 - float(row) * 1.2)
			)
		)
	var tile_mat := tile.material as StandardMaterial3D
	tile_mat.vertex_color_use_as_albedo = true
	_floor_tiles.multimesh = mm
	_floor_tiles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_floor_tiles)
	_paint_floor(0)
	_build_ball()
	_build_eq_wall()
	# Drei Scheinwerferkegel, die im Takt schwenken — schlanker als vorher,
	# damit sie die Bühne färben statt sie weiß zu waschen.
	for i in 3:
		var cone := MeshInstance3D.new()
		var cone_mesh := CylinderMesh.new()
		cone_mesh.top_radius = 0.08
		cone_mesh.bottom_radius = 1.0
		cone_mesh.height = 7.5
		cone_mesh.radial_segments = 12
		var mat := Fx.glass(Color(LANE_COLORS[i], 0.05), true)
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		cone_mesh.material = mat
		cone.mesh = cone_mesh
		cone.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(cone)
		_cones.append(cone)
	# Spotlicht auf den Star: pulst im Takt, Farbe folgt der Serienstufe.
	_spot = OmniLight3D.new()
	_spot.light_color = TIER_GLOW[0]
	_spot.light_energy = 1.2
	_spot.omni_range = 6.0
	add_child(_spot)


## Spiegelkugel: metallische Kugel + Aufhängung + Glitzer-Nieten.
func _build_ball() -> void:
	_ball = Node3D.new()
	add_child(_ball)
	var rod := MeshInstance3D.new()
	var rod_mesh := CylinderMesh.new()
	rod_mesh.top_radius = 0.02
	rod_mesh.bottom_radius = 0.02
	rod_mesh.height = 2.0
	rod_mesh.material = Fx.flat(Color(0.5, 0.5, 0.6))
	rod.mesh = rod_mesh
	rod.position.y = 1.2
	_ball.add_child(rod)
	_ball_mesh = MeshInstance3D.new()
	var ball_sphere := SphereMesh.new()
	ball_sphere.radius = 0.42
	ball_sphere.height = 0.84
	_ball_mat = StandardMaterial3D.new()
	_ball_mat.albedo_color = Color(0.85, 0.88, 1.0)
	_ball_mat.metallic = 0.9
	_ball_mat.roughness = 0.16
	_ball_mat.emission_enabled = true
	_ball_mat.emission = Color(0.5, 0.55, 0.8)
	_ball_mat.emission_energy_multiplier = 0.4
	ball_sphere.material = _ball_mat
	_ball_mesh.mesh = ball_sphere
	_ball.add_child(_ball_mesh)
	var stud_mesh := SphereMesh.new()
	stud_mesh.radius = 0.05
	stud_mesh.height = 0.1
	stud_mesh.material = Fx.glow(Color(1.0, 1.0, 1.0), 1.6)
	for i in 8:
		var a := TAU * float(i) / 8.0
		var stud := MeshInstance3D.new()
		stud.mesh = stud_mesh
		stud.position = Vector3(cos(a) * 0.42, sin(a * 2.0) * 0.18, sin(a) * 0.42)
		stud.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_ball_mesh.add_child(stud)


## Equalizer-Wand hinten: eine MultiMesh aus Balken, die im Takt hüpfen.
func _build_eq_wall() -> void:
	_eq = MultiMeshInstance3D.new()
	var bar := BoxMesh.new()
	bar.size = Vector3(0.62, 1.0, 0.2)
	var mat := Fx.glow(Color(0.7, 0.5, 0.95), 0.45)
	mat.vertex_color_use_as_albedo = true
	bar.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = bar
	mm.instance_count = 14
	for i in 14:
		mm.set_instance_color(i, LANE_COLORS[i % 3])
	_eq.multimesh = mm
	_eq.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_eq)


## Boxenturm: Kabinett + glühender Woofer + Hochtöner.
func _build_speaker(side: float) -> Node3D:
	var tower := Node3D.new()
	add_child(tower)
	var cab := MeshInstance3D.new()
	var cab_mesh := BoxMesh.new()
	cab_mesh.size = Vector3(1.05, 1.7, 0.7)
	cab_mesh.material = Fx.flat(Color(0.16, 0.11, 0.26))
	cab.mesh = cab_mesh
	cab.position.y = 0.85
	tower.add_child(cab)
	var woofer := MeshInstance3D.new()
	var woofer_mesh := CylinderMesh.new()
	woofer_mesh.top_radius = 0.34
	woofer_mesh.bottom_radius = 0.34
	woofer_mesh.height = 0.08
	woofer_mesh.radial_segments = 18
	var woofer_mat := Fx.glow(Color(0.6, 0.45, 0.9), 0.5)
	woofer_mesh.material = woofer_mat
	_woofer_mats.append(woofer_mat)
	woofer.mesh = woofer_mesh
	woofer.rotation_degrees.x = 90.0
	woofer.position = Vector3(0.0, 0.62, 0.38)
	tower.add_child(woofer)
	var tweeter := MeshInstance3D.new()
	var tweeter_mesh := CylinderMesh.new()
	tweeter_mesh.top_radius = 0.13
	tweeter_mesh.bottom_radius = 0.13
	tweeter_mesh.height = 0.07
	tweeter_mesh.radial_segments = 12
	tweeter_mesh.material = Fx.glow(Color(1.0, 0.82, 0.4), 0.6)
	tweeter.mesh = tweeter_mesh
	tweeter.rotation_degrees.x = 90.0
	tweeter.position = Vector3(0.0, 1.32, 0.38)
	tower.add_child(tweeter)
	tower.rotation_degrees.y = -sign(side) * 14.0
	return tower


func _build_gooby() -> void:
	gooby = Actor.new()
	add_child(gooby)
	gooby.mount(1.5)
	gooby.base_emotion = "happy"


## W15: Mini-Gooby-Publikum als drei MultiMeshes (Körper, Köpfe, Ohren) —
## 8 Fans in zwei Grüppchen links/rechts vor der Bühne, Plätze aus layout().
func _build_crowd() -> void:
	_crowd_bodies = MultiMeshInstance3D.new()
	var body := SphereMesh.new()
	body.radius = 0.24
	body.height = 0.44
	body.radial_segments = 10
	body.rings = 5
	var body_mat := Fx.flat(Color(0.2, 0.14, 0.32))
	body_mat.vertex_color_use_as_albedo = true
	body.material = body_mat
	var bodies := MultiMesh.new()
	bodies.transform_format = MultiMesh.TRANSFORM_3D
	bodies.use_colors = true
	bodies.mesh = body
	bodies.instance_count = _crowd_spots.size()
	_crowd_bodies.multimesh = bodies
	_crowd_bodies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_crowd_bodies)
	_crowd_heads = MultiMeshInstance3D.new()
	var head := SphereMesh.new()
	head.radius = 0.15
	head.height = 0.3
	head.radial_segments = 10
	head.rings = 5
	head.material = body.material
	var heads := MultiMesh.new()
	heads.transform_format = MultiMesh.TRANSFORM_3D
	heads.use_colors = true
	heads.mesh = head
	heads.instance_count = _crowd_spots.size()
	_crowd_heads.multimesh = heads
	_crowd_heads.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_crowd_heads)
	_crowd_ears = MultiMeshInstance3D.new()
	var ear := SphereMesh.new()
	ear.radius = 0.05
	ear.height = 0.26
	ear.radial_segments = 6
	ear.rings = 3
	ear.material = body.material
	var ears := MultiMesh.new()
	ears.transform_format = MultiMesh.TRANSFORM_3D
	ears.use_colors = true
	ears.mesh = ear
	ears.instance_count = _crowd_spots.size() * 2
	_crowd_ears.multimesh = ears
	_crowd_ears.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_crowd_ears)
	for i in _crowd_spots.size():
		var tint := Color(0.24, 0.16, 0.38).lerp(LANE_COLORS[i % 3], 0.28)
		bodies.set_instance_color(i, tint)
		heads.set_instance_color(i, tint.lightened(0.1))
		ears.set_instance_color(i * 2, tint.lightened(0.1))
		ears.set_instance_color(i * 2 + 1, tint.lightened(0.1))
	_pose_crowd(0.0)


## Publikum posen: phasenversetzter Takt-Hüpfer je Fan (auch Grundstellung).
func _pose_crowd(pulse: float) -> void:
	if _crowd_bodies == null:
		return
	var bodies := _crowd_bodies.multimesh
	var heads := _crowd_heads.multimesh
	var ears := _crowd_ears.multimesh
	for i in _crowd_spots.size():
		var base := _crowd_spots[i]
		var hop := maxf(0.0, sin(pulse * 6.2 + float(i) * 1.7)) * 0.14
		var sway := sin(pulse * 3.1 + float(i)) * 0.06
		var at := base + Vector3(sway * 0.4, hop, 0.0)
		bodies.set_instance_transform(i, Transform3D(Basis.IDENTITY, at + Vector3(0.0, 0.2, 0.0)))
		heads.set_instance_transform(
			i, Transform3D(Basis(Vector3.BACK, sway), at + Vector3(0.0, 0.5, 0.0))
		)
		for side in 2:
			var ear_x := (-0.07 if side == 0 else 0.07) + sway * 0.5
			ears.set_instance_transform(
				i * 2 + side,
				Transform3D(
					Basis(Vector3.BACK, sway * 2.0), at + Vector3(ear_x, 0.68 + hop * 0.3, 0.0)
				)
			)


## W15: Wimpel-Lichterkette in den Bahnfarben durch die leere Bühnenmitte.
func _build_bunting() -> void:
	_bunting = MultiMeshInstance3D.new()
	var prisma := PrismMesh.new()
	prisma.size = Vector3(0.26, 0.3, 0.03)
	# Unbeleuchtet + Instanzfarbe: mit weißer Glow-Emission wuschen die
	# Wimpel zu hellen Dreiecken aus — so bleiben sie satt bahnfarbig.
	var mat := Fx.flat(Color(1.0, 1.0, 1.0))
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.vertex_color_use_as_albedo = true
	prisma.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = prisma
	mm.instance_count = 13
	for i in 13:
		mm.set_instance_color(i, LANE_COLORS[i % 3])
	_bunting.multimesh = mm
	_bunting.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_bunting)
	_pose_bunting(0.0)


## Wimpel posen: Kette hängt durch und schwingt sanft zum Beat.
func _pose_bunting(pulse: float) -> void:
	if _bunting == null:
		return
	var mm := _bunting.multimesh
	var flip := Basis(Vector3.RIGHT, PI)
	for i in mm.instance_count:
		var f := (float(i) + 0.5) / float(mm.instance_count)
		var x := lerpf(-_bunting_half_w, _bunting_half_w, f)
		var sag := -sin(f * PI) * 0.5
		var sway := sin(pulse * 3.1 + f * 4.0) * 0.06
		mm.set_instance_transform(
			i,
			Transform3D(
				flip.rotated(Vector3.BACK, sway * 2.0), Vector3(x + sway, _bunting_y + sag, -2.4)
			)
		)


## Kamera frontal auf die Notenebene; Anker (Canvas-Pixel) → Welt.
func frame(vp: Vector2) -> void:
	_vp = vp
	stage.apply_size(vp)
	stage.camera.position = Vector3(0.0, 0.0, CAM_DIST)
	stage.camera.rotation = Vector3.ZERO
	stage.set_half_height(HALF_H, CAM_DIST)


## Bahnen, Ringe, Kugel, Boden und Gooby an die 2D-Anker legen.
func layout(lane_xs: Array[float], top_px: float, hit_px: float, span_px: float) -> void:
	var hit_y := _wy(hit_px)
	var top_y := _wy(top_px)
	_hit_ring_r = span_px * 0.34 / _ppu()
	for i in _lanes.size():
		var x := _wx(lane_xs[i])
		var lane := _lanes[i]
		var lane_w := span_px * 0.92 / _ppu()
		(lane.mesh as QuadMesh).size = Vector2(lane_w, top_y - hit_y)
		lane.position = Vector3(x, (top_y + hit_y) * 0.5, -0.3)
		for side in 2:
			var rail := _rails[i * 2 + side]
			rail.position = Vector3(
				x + (lane_w * 0.5) * (1.0 if side == 1 else -1.0), (top_y + hit_y) * 0.5, -0.28
			)
			rail.scale = Vector3(1.0, top_y - hit_y, 1.0)
		var ring := _rings[i]
		var torus := ring.mesh as TorusMesh
		torus.inner_radius = _hit_ring_r - 0.07
		torus.outer_radius = _hit_ring_r
		ring.position = Vector3(x, hit_y, 0.0)
		var pad := _pads[i]
		(pad.mesh as CylinderMesh).top_radius = _hit_ring_r + 0.12
		(pad.mesh as CylinderMesh).bottom_radius = _hit_ring_r + 0.12
		pad.position = Vector3(x, hit_y, -0.15)
	var full_span := span_px * 3.3 / _ppu()
	(_hit_bar.mesh as BoxMesh).size = Vector3(full_span, 0.035, 0.03)
	_hit_bar.position = Vector3(_wx(lane_xs[1]), hit_y, -0.2)
	# Boden dort, wo Gooby tanzt (92 % Bildhöhe), Kugel am oberen Anker.
	var floor_y := _wy(_vp.y * 0.92)
	_floor_tiles.position = Vector3(0.0, floor_y, 0.0)
	gooby.position = Vector3(0.0, floor_y, 1.2)
	_spot.position = Vector3(0.0, floor_y + 2.6, 2.2)
	_ball.position = Vector3(0.0, _wy(_vp.y * 0.055), -1.5)
	_encore_light.position = Vector3(0.0, hit_y + 2.0, 2.0)
	var outer := absf(_wx(lane_xs[2]) - _wx(lane_xs[1]))
	for i in _cones.size():
		_cones[i].position = Vector3(_wx(lane_xs[i]), _wy(_vp.y * 0.05), -3.0)
	# Boxentürme flankieren die Bahnen, EQ-Wand füllt den Rücken.
	if _speakers.is_empty():
		_speakers.append(_build_speaker(-1.0))
		_speakers.append(_build_speaker(1.0))
	var speaker_x := _wx(lane_xs[1]) + outer + 1.55
	_speakers[0].position = Vector3(-speaker_x, floor_y, -0.9)
	_speakers[1].position = Vector3(speaker_x, floor_y, -0.9)
	_eq.position = Vector3(_wx(lane_xs[1]), floor_y + 0.2, -4.6)
	_layout_eq(0.0, 0)
	# W15: Publikums-Plätze in zwei Grüppchen neben dem Star + Wimpel-Anker
	# durch die leere Mitte (knapp unter der Spiegelkugel gespannt).
	_crowd_spots.clear()
	for i in 8:
		var group := -1.0 if i < 4 else 1.0
		var slot := float(i % 4)
		_crowd_spots.append(
			Vector3(
				group * (1.35 + slot * 0.52 + fmod(slot * 0.37, 0.3)),
				floor_y + (0.12 if int(slot) % 2 == 0 else 0.0),
				1.7 - fmod(slot, 2.0) * 0.55
			)
		)
	if _crowd_bodies == null:
		_build_crowd()
	else:
		_pose_crowd(0.0)
	_bunting_y = _wy(_vp.y * 0.16)
	_bunting_half_w = absf(_wx(lane_xs[2]) - _wx(lane_xs[1])) * 2.1
	if _bunting == null:
		_build_bunting()
	else:
		_pose_bunting(0.0)


## EQ-Balken neu posen (Grundstellung oder Takt-Tanz).
func _layout_eq(pulse: float, tier: int) -> void:
	var mm := _eq.multimesh
	for i in 14:
		var x := -4.9 + float(i) * 0.75
		var h := 0.5 + 0.28 * float((i * 5) % 4)
		h += (0.5 + 0.3 * float(tier)) * maxf(0.0, sin(pulse * 6.2 + float(i) * 1.1))
		mm.set_instance_transform(
			i, Transform3D(Basis.IDENTITY.scaled(Vector3(1.0, h, 1.0)), Vector3(x, h * 0.5, 0.0))
		)


## Jeden Frame: sichtbare Noten (lane, y_px) aus dem Pool stellen, Takt tanzen.
func sync(
	visible_notes: Array[Dictionary],
	flash: Array[float],
	tier: int,
	beat: float,
	spin: float,
	ball_pop: float,
	encore: bool,
	pulse: float,
	delta: float
) -> void:
	stage.tick(delta)
	gooby.tick(delta)
	var used := [0, 0, 0]
	for note in visible_notes:
		var lane := int(note["lane"])
		var node := _take_note(lane)
		used[lane] += 1
		node.visible = true
		node.position = Vector3(_wx(float(note["x"])), _wy(float(note["y"])), 0.0)
		# Anflug-Rasten: kurz vor der Linie schwillt die Note leicht an.
		var near := clampf(
			1.0 - absf(_wy(float(note["y"])) - _rings[lane].position.y) / 2.6, 0.0, 1.0
		)
		node.scale = Vector3.ONE * (_hit_ring_r / 0.5) * (0.82 + 0.18 * near)
		node.rotation.y = pulse * 2.0
	for lane in 3:
		var list: Array = _note_pool[lane]
		for i in range(int(used[lane]), list.size()):
			(list[i] as Node3D).visible = false
	var beat01 := maxf(0.0, beat)
	for i in _rings.size():
		var flash_f := clampf(flash[i] / 0.18, 0.0, 1.0)
		_rings[i].scale = Vector3.ONE * (1.0 + flash_f * 0.35 + beat01 * 0.05)
	_hit_bar_mat.albedo_color.a = 0.4 + 0.3 * beat01
	# Spiegelkugel: Drehung (Logic-Tempo) + Pop, Kegel schwenken im Takt.
	_ball_mesh.rotation.y = spin
	_ball_mesh.scale = Vector3.ONE * (1.0 + ball_pop * 0.4)
	_ball_mat.emission = Color(1.0, 0.8, 0.4) if encore else Color(0.5, 0.55, 0.8)
	_ball_mat.emission_energy_multiplier = (1.0 + 0.5 * beat01) if encore else 0.4
	for i in _cones.size():
		var phase := pulse * 0.7 + float(i) * TAU / 3.0
		_cones[i].rotation.z = sin(phase) * 0.42
		# W15: die Kegel PUMPEN im Takt — die Lichtshow atmet mit der Musik.
		var breathe := 1.0 + 0.22 * beat01
		_cones[i].scale = Vector3(breathe, 1.0, breathe)
	_dance(tier, beat, pulse, delta)
	_pulse_stage(tier, beat01, pulse, encore)
	_pose_crowd(pulse)
	_pose_bunting(pulse)


## Gooby tanzt WIRKLICH: Grund-Bob jeden Frame, auf jeden Beat ein Hüpfer
## mit wechselndem Armschwung — die Serienstufe macht alles größer.
func _dance(tier: int, beat: float, pulse: float, _delta: float) -> void:
	var energy := 1.0 + 0.35 * float(tier)
	gooby.position.y = _floor_tiles.position.y + absf(beat) * 0.1 * energy
	gooby.rotation.y = beat * 0.24 * energy
	gooby.rotation.z = sin(pulse * 2.2) * 0.05 * energy
	var bpm := float(DancePartyLogic.DANCE["BPM"])
	var idx := int(floor(maxf(0.0, pulse) * bpm / 60.0))
	if idx != _beat_idx:
		_beat_idx = idx
		_swing_side = -_swing_side
		gooby.hop(0.28, 0.07 + 0.035 * float(tier))
		gooby.swing(0.3, (10.0 + 5.0 * float(tier)) * _swing_side, Vector3.BACK)
	if tier >= 2:
		gooby.set_mood("ecstatic")
	else:
		gooby.set_mood("happy")


## Boden, EQ, Woofer und Spot pumpen im Takt; Encore = Goldlicht.
func _pulse_stage(tier: int, beat01: float, pulse: float, encore: bool) -> void:
	var glow := TIER_GLOW[clampi(tier, 0, TIER_GLOW.size() - 1)]
	if encore:
		glow = Color(1.0, 0.8, 0.4)
	var mm := _floor_tiles.multimesh
	var hot := Color(glow.r, glow.g, glow.b).lerp(Color(1, 1, 1), 0.15 * beat01)
	var base := Color(0.42, 0.32, 0.6)
	var checker_flip := _beat_idx % 2 == 0
	for i in 60:
		var col := i % 10
		var row := i / 10
		var is_hot := ((col + row) % 2 == 0) == checker_flip
		mm.set_instance_color(i, hot * (0.7 + 0.3 * beat01) if is_hot else base)
	_layout_eq(pulse, tier)
	for mat in _woofer_mats:
		mat.emission_energy_multiplier = 0.35 + 0.85 * beat01
	_spot.light_color = glow
	_spot.light_energy = 1.0 + 0.9 * beat01 + 0.5 * float(tier)
	_encore_light.light_energy = (1.2 + 0.5 * sin(pulse * 10.0)) if encore else 0.0


func hit_fx(lane_x_px: float, perfect: bool) -> void:
	var at := Vector3(_wx(lane_x_px), _rings[0].position.y, 0.3)
	Fx.burst(_hit_burst, at)
	if perfect:
		stage.pulse_glow(0.5)
	gooby.hop(0.3, 0.16)


func miss_fx() -> void:
	gooby.emote("scared", 0.9)


func encore_fx() -> void:
	gooby.emote("ecstatic", 2.0)
	gooby.play_for("celebrate", 1.2)
	stage.pulse_glow(1.0)


func _take_note(lane: int) -> Node3D:
	var list: Array = _note_pool[lane]
	for node: Node3D in list:
		if not node.visible:
			return node
	var fresh := _spawn_note(lane)
	add_child(fresh)
	list.append(fresh)
	return fresh


func _spawn_note(lane: int) -> Node3D:
	var root := Node3D.new()
	var glow_ball := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.material = Fx.glow(LANE_COLORS[lane], 1.1)
	glow_ball.mesh = mesh
	glow_ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(glow_ball)
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.26
	core_mesh.height = 0.52
	core_mesh.material = Fx.glow(Color(1.0, 1.0, 1.0), 1.5)
	core.mesh = core_mesh
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(core)
	# W15 Lesbarkeit: dunkle Rückscheibe hinter der Note — sie hebt sich
	# damit auch von hellen Scheinwerferkegeln und der Wimpelkette ab.
	var backing := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.58
	disc.bottom_radius = 0.58
	disc.height = 0.02
	disc.radial_segments = 20
	var back_mat := Fx.flat(Color(0.05, 0.04, 0.12, 0.42))
	back_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	back_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	disc.material = back_mat
	backing.mesh = disc
	backing.rotation_degrees.x = 90.0
	backing.position.z = -0.12
	backing.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(backing)
	# Bahnfarben-Halo, kamerazugewandt: Noten rasten sichtbar auf die Ringe
	# (W15: dicker — 0,045 war auf dem Handy fast unsichtbar).
	var halo := Fx.ring(0.62, 0.07, LANE_COLORS[lane])
	halo.rotation_degrees.x = 90.0
	root.add_child(halo)
	return root


func _ppu() -> float:
	return _vp.y / (HALF_H * 2.0)


func _wx(px: float) -> float:
	return (px - _vp.x * 0.5) / _ppu()


func _wy(py: float) -> float:
	return (_vp.y * 0.5 - py) / _ppu()
