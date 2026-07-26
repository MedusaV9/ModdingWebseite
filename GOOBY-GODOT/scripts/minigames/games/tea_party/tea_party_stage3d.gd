extends Node3D
## ECHTE 3D-Teestube (FB-4): Gooby steht als Gastgeber hinter dem Tisch, die
## Kanne schwebt über der Glastasse und kippt beim Gießen, der Tee steigt als
## echter Zylinder in der Tasse, das Zielband liegt als Glasring UM die Tasse.
## Kulisse: Küchenzeile (Kenney furniture-kit, wiederverwendet aus veggie_chop)
## plus Törtchen-Regal (tinytreats). Die MECHANIK bleibt komplett in
## tea_party.gd/TeaPartyLogic — diese Bühne ist reine Darstellung.

const Stage3D := preload("res://scripts/minigames/games/_3dc_stage/stage3d.gd")
const Actor := preload("res://scripts/minigames/games/_3da_stage/gooby_actor.gd")
const Models := preload("res://scripts/minigames/games/_3db_stage/model_bank.gd")
const Fx := preload("res://scripts/minigames/games/_3db_stage/fx3d.gd")

const KIT := "res://assets/minigames/veggie_chop/"
const TREATS := "res://assets/minigames/purble_place/tinytreats/"

const TEA := Color(0.72, 0.45, 0.18)
const GLASS := Color(0.85, 0.93, 0.96, 0.34)
const BAND := Color(0.42, 0.78, 0.42, 0.4)
const PERFECT := Color(1.0, 0.72, 0.2)

## Tassenmaße (Meter) — level 1.0 entspricht der vollen Innenhöhe.
const CUP_H := 0.34
const CUP_R := 0.17
const TABLE_H := 0.76
## Tassen-Rutschweg beim Servieren (Meter, von rechts herein).
const SLIDE_M := 1.9

var stage: Node3D
var gooby: Node3D

var _cup_root: Node3D
var _tea: MeshInstance3D
var _band_shell: MeshInstance3D
var _perfect_ring: MeshInstance3D
var _kettle: Node3D
var _stream: MeshInstance3D
var _splash: GPUParticles3D
var _steam: GPUParticles3D
var _kettle_tilt := 0.0


func setup_stage() -> void:
	stage = Stage3D.new()
	add_child(stage)
	(
		stage
		. build(
			{
				# Warme Stube: Cremewand statt Himmel, sanftes Fenster-Licht.
				# NICHT überbelichten (bekannte Falle): Sonne + Ambient unter 1.
				"sky_top": Color(0.87, 0.8, 0.7),
				"sky_horizon": Color(0.93, 0.86, 0.76),
				"ground_horizon": Color(0.85, 0.76, 0.64),
				"ground_bottom": Color(0.62, 0.5, 0.4),
				"sun_dir": Vector3(-0.5, -0.8, -0.35),
				"sun_color": Color(1.0, 0.93, 0.8),
				"sun_energy": 0.78,
				"ambient": 0.78,
				"fill_energy": 0.22,
				"glow": 0.22,
				"shadow_distance": 14.0,
				"hfov": 44.0,
				"far": 60.0,
			}
		)
	)
	stage.set_hfov(44.0, 58.0)
	stage.camera.position = Vector3(0.0, 1.5, 3.1)
	stage.camera.look_at(Vector3(0.0, 0.92, 0.0), Vector3.UP)
	_build_room()
	_build_table()
	_build_cup()
	_build_kettle()
	_build_gooby()
	_build_fx()


func _build_room() -> void:
	add_child(Fx.ground(Vector2(16.0, 12.0), Color(0.85, 0.72, 0.55)))
	# Teppich unter dem Tisch.
	var rug := MeshInstance3D.new()
	var rug_mesh := CylinderMesh.new()
	rug_mesh.top_radius = 1.7
	rug_mesh.bottom_radius = 1.7
	rug_mesh.height = 0.02
	rug_mesh.radial_segments = 28
	rug_mesh.material = Fx.flat(Color(0.94, 0.82, 0.78))
	rug.mesh = rug_mesh
	rug.position.y = 0.011
	add_child(rug)
	# Küchenzeile als Rückwand-Kulisse.
	var row := Node3D.new()
	row.position = Vector3(0.0, 0.0, -2.6)
	add_child(row)
	for i in 4:
		var cab := Models.node(KIT + "kitchenCabinet.glb", 1.1)
		cab.position.x = -1.65 + float(i) * 1.1
		row.add_child(cab)
	var sink := Models.node(KIT + "kitchenSink.glb", 1.1)
	sink.position.x = 2.75
	row.add_child(sink)
	for i in 3:
		var upper := Models.node(KIT + "kitchenCabinetUpper.glb", 1.1)
		upper.position = Vector3(-1.1 + float(i) * 1.1, 1.5, 0.0)
		row.add_child(upper)
	var rack := Models.node(KIT + "tinytreats/dishrack_plates.gltf", 0.62)
	rack.position = Vector3(2.7, 0.93, -2.5)
	add_child(rack)
	# Törtchen auf der Arbeitsplatte — die Teestube hat Kundschaft verdient.
	for entry: Array in [
		[TREATS + "macaron_pink.gltf", 0.2, -1.7],
		[TREATS + "macaron_blue.gltf", 0.2, -1.35],
		["res://assets/minigames/purble_place/cake.glb", 0.42, 0.6],
		["res://assets/minigames/purble_place/cupcake.glb", 0.24, 1.4],
	]:
		var treat := Models.node(str(entry[0]), float(entry[1]))
		treat.position = Vector3(float(entry[2]), 0.93, -2.5)
		add_child(treat)


func _build_table() -> void:
	var leg := MeshInstance3D.new()
	var leg_mesh := CylinderMesh.new()
	leg_mesh.top_radius = 0.09
	leg_mesh.bottom_radius = 0.14
	leg_mesh.height = TABLE_H
	leg_mesh.material = Fx.flat(Color(0.62, 0.46, 0.3))
	leg.mesh = leg_mesh
	leg.position.y = TABLE_H * 0.5
	add_child(leg)
	var top := MeshInstance3D.new()
	var top_mesh := CylinderMesh.new()
	top_mesh.top_radius = 0.95
	top_mesh.bottom_radius = 0.95
	top_mesh.height = 0.06
	top_mesh.radial_segments = 32
	top_mesh.material = Fx.flat(Color(0.96, 0.78, 0.76))
	top.mesh = top_mesh
	top.position.y = TABLE_H
	add_child(top)


## Glastasse + Untertasse + Henkel + Tee-Säule + Zielband-Ringe, verschiebbar.
func _build_cup() -> void:
	_cup_root = Node3D.new()
	_cup_root.position = Vector3(0.0, TABLE_H + 0.032, 0.35)
	add_child(_cup_root)
	var saucer := MeshInstance3D.new()
	var saucer_mesh := CylinderMesh.new()
	saucer_mesh.top_radius = CUP_R + 0.1
	saucer_mesh.bottom_radius = CUP_R + 0.04
	saucer_mesh.height = 0.03
	saucer_mesh.material = Fx.flat(Color(0.99, 0.97, 0.94), 0.4)
	saucer.mesh = saucer_mesh
	saucer.position.y = 0.005
	_cup_root.add_child(saucer)
	# Tee-Säule: skaliert in y mit dem Füllstand (Pivot an der Unterkante).
	_tea = MeshInstance3D.new()
	var tea_mesh := CylinderMesh.new()
	tea_mesh.top_radius = CUP_R - 0.025
	tea_mesh.bottom_radius = CUP_R - 0.025
	tea_mesh.height = 1.0
	tea_mesh.material = Fx.flat(TEA, 0.25)
	_tea.mesh = tea_mesh
	_cup_root.add_child(_tea)
	var wall := MeshInstance3D.new()
	var wall_mesh := CylinderMesh.new()
	wall_mesh.top_radius = CUP_R
	wall_mesh.bottom_radius = CUP_R - 0.02
	wall_mesh.height = CUP_H
	wall_mesh.material = Fx.glass(GLASS)
	wall.mesh = wall_mesh
	wall.position.y = 0.02 + CUP_H * 0.5
	wall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cup_root.add_child(wall)
	var handle := MeshInstance3D.new()
	var handle_mesh := TorusMesh.new()
	handle_mesh.inner_radius = 0.035
	handle_mesh.outer_radius = 0.075
	handle_mesh.material = Fx.flat(Color(0.99, 0.97, 0.94), 0.4)
	handle.mesh = handle_mesh
	handle.rotation_degrees = Vector3(0.0, 0.0, 90.0)
	handle.position = Vector3(CUP_R + 0.04, 0.02 + CUP_H * 0.55, 0.0)
	_cup_root.add_child(handle)
	# Zielband (good) als Glasring um die Tasse, Perfect als Goldring.
	_band_shell = MeshInstance3D.new()
	var band_mesh := CylinderMesh.new()
	band_mesh.top_radius = CUP_R + 0.028
	band_mesh.bottom_radius = CUP_R + 0.028
	band_mesh.height = 1.0
	band_mesh.material = Fx.glass(BAND, true)
	_band_shell.mesh = band_mesh
	_band_shell.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cup_root.add_child(_band_shell)
	_perfect_ring = MeshInstance3D.new()
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = CUP_R + 0.02
	ring_mesh.outer_radius = CUP_R + 0.05
	ring_mesh.material = Fx.glow(PERFECT, 1.6)
	_perfect_ring.mesh = ring_mesh
	_perfect_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_cup_root.add_child(_perfect_ring)


func _build_kettle() -> void:
	_kettle = Node3D.new()
	_kettle.position = Vector3(0.0, TABLE_H + 0.72, 0.35)
	add_child(_kettle)
	var body := Models.node(KIT + "tinytreats/kettle.gltf", 0.42)
	# Tülle zeigt nach −x; Pivot mittig, damit das Kippen natürlich wirkt.
	body.position.y = -0.15
	_kettle.add_child(body)
	_stream = MeshInstance3D.new()
	var stream_mesh := CylinderMesh.new()
	stream_mesh.top_radius = 0.022
	stream_mesh.bottom_radius = 0.03
	stream_mesh.height = 1.0
	stream_mesh.material = Fx.glow(TEA.lightened(0.12), 0.7)
	_stream.mesh = stream_mesh
	_stream.visible = false
	_stream.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_stream)


func _build_gooby() -> void:
	# HINTER dem Tisch (außerhalb der Platte, auch im engen Hochkant-Blick
	# sichtbar), groß genug, dass Gesicht und Bauch über die Platte ragen.
	gooby = Actor.new()
	gooby.position = Vector3(-0.4, 0.0, -1.2)
	add_child(gooby)
	gooby.mount(1.6, 0.1)
	gooby.base_emotion = "happy"


func _build_fx() -> void:
	_splash = (
		Fx
		. particles(
			{
				"color": Color(0.88, 0.62, 0.3, 0.9),
				"amount": 14,
				"lifetime": 0.4,
				"speed": Vector2(0.3, 0.9),
				"spread": 70.0,
				"gravity": Vector3(0.0, -3.0, 0.0),
				"size": Vector2(0.015, 0.04),
			}
		)
	)
	_splash.emitting = false
	add_child(_splash)
	_steam = (
		Fx
		. particles(
			{
				"color": Color(1.0, 1.0, 1.0, 0.3),
				"amount": 10,
				"lifetime": 1.3,
				"speed": Vector2(0.1, 0.3),
				"spread": 12.0,
				"gravity": Vector3(0.0, 0.5, 0.0),
				"size": Vector2(0.04, 0.1),
			}
		)
	)
	_steam.emitting = false
	add_child(_steam)


## Jeden Frame aus tea_party._process: Zustand → Posen.
func sync(level: float, band: Dictionary, holding: bool, cup_slide: float, delta: float) -> void:
	stage.tick(delta)
	gooby.tick(delta)
	# Tasse rutscht beim Servieren von rechts herein.
	_cup_root.position.x = cup_slide * SLIDE_M
	# Tee-Säule (Pivot unten): Höhe = level · CUP_H, minimal 1 mm gegen Flackern.
	var fill := clampf(level, 0.0, 1.12) * CUP_H
	_tea.scale = Vector3(1.0, maxf(0.001, fill), 1.0)
	_tea.position.y = 0.02 + fill * 0.5
	_tea.visible = fill > 0.004
	# Zielband + Perfect-Ring auf Bandhöhe.
	var center := float(band.get("center", 0.7))
	var half := float(band.get("half", 0.075))
	_band_shell.scale = Vector3(1.0, maxf(0.001, 2.0 * half * CUP_H), 1.0)
	_band_shell.position.y = 0.02 + center * CUP_H
	_perfect_ring.position.y = 0.02 + center * CUP_H
	# Kanne folgt der Tasse und kippt beim Gießen.
	_kettle_tilt = lerpf(_kettle_tilt, 0.55 if holding else 0.0, minf(1.0, delta * 9.0))
	_kettle.position.x = _cup_root.position.x
	_kettle.rotation.z = -_kettle_tilt
	# Gießstrahl von der Tülle zur Tasse.
	var pouring := holding and cup_slide <= 0.01
	_stream.visible = pouring
	_splash.emitting = pouring
	_steam.emitting = level > 0.55
	if pouring:
		var spout := _kettle.global_position + Vector3(-0.24, -0.08, 0.0)
		var brim := _cup_root.global_position + Vector3(0.0, 0.02 + fill, 0.0)
		var length := maxf(0.05, spout.y - brim.y)
		_stream.scale = Vector3(1.0, length, 1.0)
		_stream.global_position = Vector3(brim.x, brim.y + length * 0.5, brim.z)
		_splash.global_position = brim
	_steam.global_position = _cup_root.global_position + Vector3(0.0, CUP_H + 0.1, 0.0)


## Bildschirmpunkt der Tasse (Anker für float_text).
func cup_screen() -> Vector2:
	return stage.to_screen(_cup_root.global_position + Vector3(0.0, CUP_H * 0.5, 0.0))


## Layout-Hook aus apply_view.
func apply_size(size: Vector2) -> void:
	stage.apply_size(size)
	var portrait := size.y > size.x
	# Hochkant: näher heran und etwas höher zielen, damit Tisch + Kanne das
	# Bild füllen statt leerem Boden.
	stage.camera.position = Vector3(0.0, 1.42, 2.6) if portrait else Vector3(0.0, 1.35, 3.1)
	stage.camera.look_at(Vector3(0.0, 1.04 if portrait else 0.92, 0.0), Vector3.UP)


func celebrate() -> void:
	gooby.play_for("celebrate", 1.2)
	gooby.emote("ecstatic", 1.2)
	stage.pulse_glow(0.7)


func cheer() -> void:
	gooby.play_for("wave", 0.9)
	gooby.emote("happy", 0.9)


func groan() -> void:
	gooby.emote("sad", 1.2)
