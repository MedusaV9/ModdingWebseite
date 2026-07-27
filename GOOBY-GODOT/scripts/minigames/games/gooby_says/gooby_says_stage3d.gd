extends Node3D
## ECHTE 3D-Spielshow-Bühne für „Gooby sagt" (FB-4): vier dicke Pastell-Pads
## als 3D-Podeste auf einem Bühnenboden, Gooby dirigiert GROSS dahinter und
## bekommt beim Vorspielen einen Leuchtring in der Pad-Farbe. Eingaben laufen
## als Raycast auf die Bodenebene (pad_at). Die MECHANIK bleibt komplett in
## gooby_says.gd/GoobySaysLogic — diese Bühne ist reine Darstellung.

const Stage3D := preload("res://scripts/minigames/games/_3dc_stage/stage3d.gd")
const Actor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")

const PAD_COLORS: Array[Color] = [
	Color("59C9B9"), Color("FF7BA9"), Color("FFD166"), Color("8FD06C")
]
const PAD_SYMBOLS: Array[String] = ["▲", "●", "◆", "★"]
## Pad-Kantenlänge/Höhe in Metern.
const PAD_W := 1.05
const PAD_H := 0.16

var stage: Node3D
var gooby: Node3D

var _pads: Array[Node3D] = []
var _pad_mats: Array[StandardMaterial3D] = []
var _halo: MeshInstance3D
var _halo_mat: StandardMaterial3D
var _confetti: GPUParticles3D
var _landscape := false
## Rest-Sekunden des roten Fehler-Blitzes auf allen Pads.
var _fail_left := 0.0


func setup_stage() -> void:
	stage = Stage3D.new()
	add_child(stage)
	(
		stage
		. build(
			{
				# Abendliche Show-Bühne: dunkler Vorhang, warme Scheinwerfer —
				# so tragen die leuchtenden Pads den Kontrast.
				"sky_top": Color(0.24, 0.2, 0.32),
				"sky_horizon": Color(0.38, 0.28, 0.38),
				"ground_horizon": Color(0.32, 0.24, 0.3),
				"ground_bottom": Color(0.2, 0.16, 0.2),
				"sun_dir": Vector3(-0.3, -0.85, -0.4),
				"sun_color": Color(1.0, 0.93, 0.8),
				"sun_energy": 0.85,
				"ambient": 0.65,
				"fill_energy": 0.3,
				"glow": 0.42,
				"glow_threshold": 0.72,
				"shadow_distance": 16.0,
				"hfov": 48.0,
				"far": 60.0,
			}
		)
	)
	_build_stage_floor()
	_build_pads()
	_build_gooby()
	_confetti = (
		Fx
		. particles(
			{
				"color": Color(1.0, 0.85, 0.5, 1.0),
				"amount": 32,
				"lifetime": 1.2,
				"one_shot": true,
				"explosiveness": 1.0,
				"speed": Vector2(2.0, 4.2),
				"spread": 70.0,
				"gravity": Vector3(0.0, -4.5, 0.0),
				"size": Vector2(0.05, 0.14),
			}
		)
	)
	add_child(_confetti)


func _build_stage_floor() -> void:
	add_child(Fx.ground(Vector2(26.0, 20.0), Color(0.26, 0.2, 0.26)))
	# Runde Show-Bühne aus zwei Holzscheiben.
	for entry: Array in [[3.6, 0.0, Color(0.55, 0.4, 0.3)], [3.1, 0.06, Color(0.65, 0.48, 0.35)]]:
		var disc := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = float(entry[0])
		mesh.bottom_radius = float(entry[0]) + 0.15
		mesh.height = 0.12
		mesh.radial_segments = 36
		mesh.material = Fx.flat(entry[2])
		disc.mesh = mesh
		disc.position.y = float(entry[1])
		add_child(disc)
	# Vorhang-Rückwand mit Wellenfalten (Zylinderreihe).
	var folds := MultiMeshInstance3D.new()
	var fold_mesh := CylinderMesh.new()
	fold_mesh.top_radius = 0.34
	fold_mesh.bottom_radius = 0.4
	fold_mesh.height = 5.2
	fold_mesh.radial_segments = 10
	fold_mesh.material = Fx.flat(Color(0.62, 0.24, 0.34), 0.7)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = fold_mesh
	mm.instance_count = 15
	for i in 15:
		var x := -4.9 + float(i) * 0.7
		mm.set_instance_transform(
			i, Transform3D(Basis.IDENTITY, Vector3(x, 2.6, -3.4 - 0.12 * float(i % 2)))
		)
	folds.multimesh = mm
	add_child(folds)
	# Zwei warme Bühnenspots (nur Optik: Glühscheiben über der Bühne) mit
	# sichtbaren Lichtkegeln auf Goobys Podium — DAS Spielshow-Signal.
	for x: float in [-2.4, 2.4]:
		var spot := MeshInstance3D.new()
		var lamp := SphereMesh.new()
		lamp.radius = 0.16
		lamp.height = 0.32
		lamp.material = Fx.glow(Color(1.0, 0.9, 0.6), 2.2)
		spot.mesh = lamp
		spot.position = Vector3(x, 3.4, -1.4)
		spot.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(spot)
		var beam := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.06
		cone.bottom_radius = 0.75
		cone.height = 3.1
		cone.radial_segments = 14
		cone.material = Fx.glass(Color(1.0, 0.92, 0.66, 0.1), true)
		beam.mesh = cone
		beam.position = (spot.position + Vector3(x * -0.4, 0.3, -2.1)) * 0.5
		beam.position.y = 1.85
		beam.look_at_from_position(beam.position, Vector3(x * 0.28, 0.4, -2.1), Vector3.UP)
		beam.rotate_object_local(Vector3.RIGHT, PI * 0.5)
		beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(beam)
	_build_footlights()
	_build_curtain_deco()


func _build_footlights() -> void:
	# Rampenlicht: Glühbirnenkranz am vorderen Bühnenrand (1 Draw-Call).
	var lights := MultiMeshInstance3D.new()
	var bulb := SphereMesh.new()
	bulb.radius = 0.07
	bulb.height = 0.14
	bulb.radial_segments = 10
	bulb.rings = 6
	bulb.material = Fx.glow(Color(1.0, 0.86, 0.5), 1.7)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = bulb
	mm.instance_count = 11
	for i in 11:
		var a := deg_to_rad(-62.0 + float(i) * 12.4)
		mm.set_instance_transform(
			i, Transform3D(Basis.IDENTITY, Vector3(sin(a) * 3.45, 0.2, cos(a) * 3.45))
		)
	lights.multimesh = mm
	lights.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lights)


func _build_curtain_deco() -> void:
	# Goldene Sterne am Vorhang + Glühbirnen-Bogen über Goobys Podium.
	for entry: Array in [
		[Vector3(-2.0, 3.6, -3.05), 0.5],
		[Vector3(2.1, 3.9, -3.05), 0.42],
		[Vector3(-3.1, 2.4, -3.0), 0.34],
		[Vector3(3.2, 2.2, -3.0), 0.34],
	]:
		var star := Label3D.new()
		star.text = "★"
		star.font_size = 200
		star.pixel_size = 0.0032 * float(entry[1])
		star.modulate = Color(1.0, 0.84, 0.42, 0.95)
		star.position = entry[0]
		add_child(star)
	var arch := MultiMeshInstance3D.new()
	var bulb := SphereMesh.new()
	bulb.radius = 0.09
	bulb.height = 0.18
	bulb.radial_segments = 10
	bulb.rings = 6
	bulb.material = Fx.glow(Color(1.0, 0.78, 0.85), 1.9)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = bulb
	mm.instance_count = 7
	for i in 7:
		var a := deg_to_rad(30.0 + float(i) * 20.0)
		mm.set_instance_transform(
			i, Transform3D(Basis.IDENTITY, Vector3(cos(a) * 1.7, 1.4 + sin(a) * 1.5, -2.6))
		)
	arch.multimesh = mm
	arch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(arch)


func _build_pads() -> void:
	for i in 4:
		var pad := Node3D.new()
		add_child(pad)
		var body := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(PAD_W, PAD_H, PAD_W)
		var mat := Fx.flat(PAD_COLORS[i], 0.6)
		mat.emission_enabled = true
		mat.emission = PAD_COLORS[i]
		mat.emission_energy_multiplier = 0.0
		mesh.material = mat
		body.mesh = mesh
		body.position.y = PAD_H * 0.5
		pad.add_child(body)
		var glyph := Label3D.new()
		glyph.text = PAD_SYMBOLS[i]
		glyph.font_size = 220
		glyph.pixel_size = 0.0026
		glyph.modulate = Color(1.0, 1.0, 1.0, 0.92)
		glyph.outline_size = 24
		glyph.outline_modulate = Color(0.16, 0.13, 0.16, 0.8)
		glyph.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		glyph.position.y = PAD_H + 0.012
		pad.add_child(glyph)
		_pads.append(pad)
		_pad_mats.append(mat)


func _build_gooby() -> void:
	# Podest + GROSSER Dirigent dahinter.
	var podium := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.85
	mesh.bottom_radius = 1.0
	mesh.height = 0.3
	mesh.radial_segments = 24
	mesh.material = Fx.flat(Color(0.93, 0.78, 0.56))
	podium.mesh = mesh
	podium.position = Vector3(0.0, 0.21, -2.1)
	add_child(podium)
	gooby = Actor.new()
	gooby.position = Vector3(0.0, 0.36, -2.1)
	add_child(gooby)
	gooby.mount(1.5)
	gooby.base_emotion = "happy"
	_halo = MeshInstance3D.new()
	var halo_mesh := TorusMesh.new()
	halo_mesh.inner_radius = 0.95
	halo_mesh.outer_radius = 1.08
	_halo_mat = Fx.glow(Color(1.0, 1.0, 1.0), 1.8)
	halo_mesh.material = _halo_mat
	_halo.mesh = halo_mesh
	_halo.position = Vector3(0.0, 0.4, -2.1)
	_halo.visible = false
	_halo.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_halo)


## Pads je Orientierung stellen: Hochkant 2×2-Block vor Gooby, quer eine Reihe.
func apply_size(size: Vector2) -> void:
	stage.apply_size(size)
	_landscape = size.x > size.y
	if _landscape:
		for i in 4:
			_pads[i].position = Vector3(-2.1 + float(i) * 1.4, 0.12, 0.9)
		stage.camera.position = Vector3(0.0, 4.1, 4.4)
		stage.camera.look_at(Vector3(0.0, 0.3, -0.5), Vector3.UP)
		stage.set_hfov(52.0, 46.0)
	else:
		for i in 4:
			_pads[i].position = Vector3(-0.75 + float(i % 2) * 1.5, 0.12, 0.25 + float(i / 2) * 1.5)
		stage.camera.position = Vector3(0.0, 4.6, 4.9)
		stage.camera.look_at(Vector3(0.0, 0.35, -0.3), Vector3.UP)
		stage.set_hfov(40.0, 62.0)


## Bildschirmpunkt → Pad-Index (Raycast auf die Pad-Deckelhöhe), −1 = daneben.
func pad_at(screen: Vector2) -> int:
	var hit: Vector3 = stage.ground_point(screen, PAD_H + 0.12)
	for i in _pads.size():
		var local := hit - _pads[i].position
		# Großzügige Treffer-Fläche (Fingerfreundlich, wie die 2D-Rects).
		if absf(local.x) <= PAD_W * 0.62 and absf(local.z) <= PAD_W * 0.62:
			return i
	return -1


## Jeden Frame: Pad-Leuchten (+Pop), Fehler-Blitz, Gooby-Halo + Puls.
func sync(lit_pad: int, lit_left: float, phase: String, pulse: float, delta: float) -> void:
	stage.tick(delta)
	gooby.tick(delta)
	_fail_left = maxf(0.0, _fail_left - delta)
	var failing := _fail_left > 0.0
	for i in _pads.size():
		var lit := i == lit_pad and lit_left > 0.0
		# Fehler: alle Pads blitzen rot — unübersehbare Fehlerrückmeldung.
		_pad_mats[i].emission = Color(0.95, 0.2, 0.16) if failing else PAD_COLORS[i]
		var target := 1.5 if failing else (0.95 if lit else 0.0)
		_pad_mats[i].emission_energy_multiplier = (lerpf(
			_pad_mats[i].emission_energy_multiplier, target, delta * 14.0
		))
		var body := _pads[i].get_child(0) as MeshInstance3D
		body.position.y = PAD_H * 0.5 + (0.06 if lit else 0.0)
		# Skalier-Pop beim Aufleuchten: sofort spürbare Trefferrückmeldung.
		var pop := 1.09 if lit else 1.0
		body.scale = body.scale.lerp(Vector3(pop, 1.0 + (pop - 1.0) * 2.0, pop), delta * 16.0)
		# Symbol reitet auf der Pad-Oberkante mit (sonst schluckt der Pop es).
		var glyph := _pads[i].get_child(1) as Node3D
		glyph.position.y = body.position.y + PAD_H * 0.5 * body.scale.y + 0.012
	var show_halo := lit_pad >= 0 and lit_left > 0.0 and phase == "watch"
	_halo.visible = show_halo
	if show_halo:
		_halo_mat.albedo_color = PAD_COLORS[lit_pad]
		_halo_mat.emission = PAD_COLORS[lit_pad]
		_halo.rotation.y = pulse * 1.6
	# Beim Vorspielen wippt der Dirigent im Takt.
	gooby.rotation.z = sin(pulse * 5.0) * (0.06 if phase == "watch" else 0.02)


## Bildschirmanker über Gooby (float_text).
func gooby_screen() -> Vector2:
	return stage.to_screen(gooby.global_position + Vector3(0.0, 1.6, 0.0))


func flash_playback(pad: int) -> void:
	gooby.play_for("wave", 0.5)
	if pad >= 0:
		gooby.face(0.25 - 0.16 * float(pad))


func celebrate() -> void:
	gooby.play_for("celebrate", 1.1)
	gooby.emote("ecstatic", 1.1)
	stage.pulse_glow(0.8)
	Fx.burst(_confetti, gooby.global_position + Vector3(0.0, 1.4, 0.0))


func fail_fx() -> void:
	gooby.emote("dizzy", 1.6)
	gooby.play_for("idle", 0.2)
	_fail_left = 0.6
