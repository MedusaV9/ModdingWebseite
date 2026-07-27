class_name DoorTransition
extends Node3D
## Tür-Komponente (W2a HOUSE, Doc A §5): Rahmen + Türblatt (prozedural),
## Tap-Fläche, Öffnen-Animation, Gooby-Durchlauf und der Steckenbleib-Gag
## (~12 %, nie 2× hintereinander, Tap-Mash 5–8 Taps). Reist am Ende über
## W1a-SceneRouter im DOOR_TRAVEL-Modus. Statemaschine: door_logic.gd (pure).
##
## Lokales Koordinatensystem: +Z zeigt IN den Raum (RoomBase rotiert uns).

signal tapped(door_id: String)
signal travel_started(door_id: String)
signal stuck_started
signal stuck_resolved
signal travel_finished(door_id: String)

const DOOR_HEIGHT := 2.0
const DOOR_THICKNESS := 0.07
const PANEL_COLOR := Color(0.62, 0.42, 0.26)
const FRAME_COLOR := Color(0.5, 0.33, 0.2)

## Doc F §6/§7-Anbindung: nie 2× hintereinander stecken (prozessweit).
static var last_was_stuck := false

var door_id := ""
var target_room := ""
var to_door_id := ""
var door_width := RoomDefs.DOOR_WIDTH * GridData.CELL_SIZE
var logic: DoorLogic

var _hinge: Node3D
var _staub: GPUParticles3D
var _sterne: GPUParticles3D
var _busy := false
var _open_tween: Tween
var _travel_gooby: Node3D


## Baut die Tür-Optik + Tap-Fläche (von RoomBase gerufen).
func setup(p_door_id: String, p_target_room: String, p_to_door_id: String) -> void:
	door_id = p_door_id
	target_room = p_target_room
	to_door_id = p_to_door_id
	name = "Door_%s" % door_id
	_build_frame()
	_build_panel()
	_build_doormat()
	_build_particles()
	_build_tap_area()


## Komplette Tür-Reise (Doc A §5). `gooby` braucht `walk_to(pos)` (Coroutine)
## und `play_clip(name)`; `ui_layer` nimmt das Tap-Mash-Overlay auf.
func travel(gooby: Node3D, ui_layer: Node) -> void:
	if _busy:
		return
	_busy = true
	_travel_gooby = gooby
	travel_started.emit(door_id)
	logic = DoorLogic.new(_doors_animated(), last_was_stuck, randf(), randf())
	last_was_stuck = false
	if logic.begin() == DoorLogic.State.OPENING:
		await _open_panel()
		logic.door_opened()
		if gooby != null and not logic.is_traveling():
			await gooby.walk_to(global_position + global_transform.basis.z * 0.4)
		if logic.reached_door() == DoorLogic.State.STUCK:
			last_was_stuck = true
			await _run_stuck_gag(gooby, ui_layer)
	_travel_gooby = null
	_goto()


## Skip per Tap irgendwo (nicht während Tap-Mash — DoorLogic regelt das).
## W4-P3 POLISH-7: responsiv — laufende Öffnen-Animation wird sofort zu
## Ende gespult und ein laufender Gooby-Lauf abgebrochen (das awaitende
## travel() kehrt im nächsten Frame zurück statt fertig zu animieren).
func skip() -> void:
	if not _busy or logic == null:
		return
	logic.skip()
	if not logic.is_traveling():
		return
	if _open_tween != null and _open_tween.is_running():
		_open_tween.custom_step(60.0)
	if _travel_gooby != null and _travel_gooby.has_method("cancel_walk"):
		_travel_gooby.cancel_walk()


func is_busy() -> bool:
	return _busy


## Zarge mit Bekleidung: Blender-GLB (weiche Kapsel-Bekleidung, Knauf im
## Sturz) — die Tür ist das erste, was der Spieler anfasst (WELT2).
## Primitive-Fallback, falls das Asset fehlt.
func _build_frame() -> void:
	var glb := HomeProps.prop_glb("tuer_zarge")
	if glb != null:
		# GLB ist für 1,0 m Öffnungsbreite gebaut — bei abweichender
		# Türbreite nur die X-Achse mitziehen.
		if not is_equal_approx(door_width, 1.0):
			glb.scale = Vector3(door_width, 1.0, 1.0)
		add_child(glb)
		return
	var post := BoxMesh.new()
	post.size = Vector3(0.1, DOOR_HEIGHT, 0.16)
	var trim := BoxMesh.new()
	trim.size = Vector3(0.05, DOOR_HEIGHT + 0.06, 0.22)
	for side in [-1.0, 1.0]:
		var mesh := MeshInstance3D.new()
		mesh.mesh = post
		mesh.material_override = _flat_material(FRAME_COLOR)
		mesh.position = Vector3(side * (door_width * 0.5 + 0.05), DOOR_HEIGHT * 0.5, 0.0)
		add_child(mesh)
		var bekleidung := MeshInstance3D.new()
		bekleidung.mesh = trim
		bekleidung.material_override = _flat_material(FRAME_COLOR.lightened(0.18))
		bekleidung.position = Vector3(
			side * (door_width * 0.5 + 0.12), DOOR_HEIGHT * 0.5 + 0.03, 0.0
		)
		add_child(bekleidung)
	var lintel := MeshInstance3D.new()
	var lintel_mesh := BoxMesh.new()
	lintel_mesh.size = Vector3(door_width + 0.34, 0.12, 0.16)
	lintel.mesh = lintel_mesh
	lintel.material_override = _flat_material(FRAME_COLOR)
	lintel.position = Vector3(0.0, DOOR_HEIGHT + 0.06, 0.0)
	add_child(lintel)
	var architrav := MeshInstance3D.new()
	var architrav_mesh := BoxMesh.new()
	architrav_mesh.size = Vector3(door_width + 0.46, 0.07, 0.22)
	architrav.mesh = architrav_mesh
	architrav.material_override = _flat_material(FRAME_COLOR.lightened(0.18))
	architrav.position = Vector3(0.0, DOOR_HEIGHT + 0.155, 0.0)
	add_child(architrav)


## Türblatt: Blender-GLB mit Kassetten + echter Klinke (WELT2, User-Wunsch
## „Türen mit Klinke"). Ursprung des GLB = Scharnierkante, das Blatt reicht
## bis x=1,0 — hängt also direkt am Hinge-Node (Öffnen-Tween unverändert).
## Primitive-Fallback, falls das Asset fehlt.
func _build_panel() -> void:
	_hinge = Node3D.new()
	_hinge.name = "Hinge"
	_hinge.position = Vector3(-door_width * 0.5, 0.0, 0.0)
	add_child(_hinge)
	var glb := HomeProps.prop_glb("tuer_blatt")
	if glb != null:
		if not is_equal_approx(door_width, 1.0):
			glb.scale = Vector3(door_width, 1.0, 1.0)
		_hinge.add_child(glb)
		return
	var panel := MeshInstance3D.new()
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3(door_width, DOOR_HEIGHT, DOOR_THICKNESS)
	panel.mesh = panel_mesh
	panel.material_override = _flat_material(PANEL_COLOR)
	panel.position = Vector3(door_width * 0.5, DOOR_HEIGHT * 0.5, 0.0)
	_hinge.add_child(panel)
	var kassette := BoxMesh.new()
	kassette.size = Vector3(door_width * 0.62, DOOR_HEIGHT * 0.34, 0.02)
	for seite in [-1.0, 1.0]:
		for hoehe: float in [DOOR_HEIGHT * 0.31, DOOR_HEIGHT * 0.72]:
			var fuellung := MeshInstance3D.new()
			fuellung.mesh = kassette
			fuellung.material_override = _flat_material(PANEL_COLOR.darkened(0.16))
			fuellung.position = Vector3(
				door_width * 0.5, hoehe, seite * (DOOR_THICKNESS * 0.5 + 0.005)
			)
			_hinge.add_child(fuellung)
	var schild := MeshInstance3D.new()
	var schild_mesh := BoxMesh.new()
	schild_mesh.size = Vector3(0.05, 0.14, 0.02)
	schild.mesh = schild_mesh
	schild.material_override = _flat_material(Color(0.85, 0.72, 0.32))
	schild.position = Vector3(door_width * 0.85, 1.0, DOOR_THICKNESS * 0.5 + 0.008)
	_hinge.add_child(schild)
	var knob := MeshInstance3D.new()
	var knob_mesh := SphereMesh.new()
	knob_mesh.radius = 0.04
	knob_mesh.height = 0.08
	knob.mesh = knob_mesh
	knob.material_override = _flat_material(Color(0.95, 0.8, 0.35))
	knob.position = Vector3(door_width * 0.85, 1.0, DOOR_THICKNESS)
	_hinge.add_child(knob)


## Fußmatte (Kenney-GLB) vor der Tür — echtes Asset statt Farbfläche.
func _build_doormat() -> void:
	var pfad := "res://assets/furniture/rugDoormat.glb"
	if not ResourceLoader.exists(pfad):
		return
	var szene: PackedScene = load(pfad)
	if szene == null:
		return
	var matte := Node3D.new()
	matte.name = "Fussmatte"
	var modell: Node3D = szene.instantiate()
	matte.add_child(modell)
	var aabb := HomeProps.merged_aabb(modell, Transform3D.IDENTITY)
	if aabb.size.x > 0.0001:
		var s := (door_width * 0.85) / aabb.size.x
		modell.scale = Vector3.ONE * s
		var center := aabb.get_center()
		modell.position = Vector3(-center.x * s, -aabb.position.y * s + 0.006, -center.z * s)
	matte.position = Vector3(0.0, 0.0, 0.42)
	add_child(matte)


## Partikel-Setup (W4-P3 POLISH-7): warme Staub-Wölbchen beim Rütteln +
## gelber Sternchen-Burst beim Durchploppen (statt der alten weißen Kugeln).
func _build_particles() -> void:
	_staub = _make_staub()
	add_child(_staub)
	_sterne = _make_sterne()
	add_child(_sterne)


func _make_staub() -> GPUParticles3D:
	var staub := GPUParticles3D.new()
	staub.name = "Staub"
	staub.emitting = false
	staub.amount = 18
	staub.lifetime = 0.9
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(door_width * 0.45, 0.35, 0.06)
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 35.0
	mat.initial_velocity_min = 0.25
	mat.initial_velocity_max = 0.7
	# Staub schwebt leicht nach oben und verweht — keine harte Gravitation.
	mat.gravity = Vector3(0, 0.35, 0)
	mat.scale_min = 0.7
	mat.scale_max = 1.6
	mat.color_ramp = _verlauf(Color(0.72, 0.6, 0.46, 0.5), Color(0.78, 0.68, 0.55, 0.0))
	staub.process_material = mat
	var mesh := SphereMesh.new()
	mesh.radius = 0.05
	mesh.height = 0.1
	mesh.radial_segments = 8
	mesh.rings = 4
	mesh.material = _partikel_material()
	staub.draw_pass_1 = mesh
	staub.position = Vector3(0.0, 0.7, 0.12)
	return staub


func _make_sterne() -> GPUParticles3D:
	var sterne := GPUParticles3D.new()
	sterne.name = "Sterne"
	sterne.emitting = false
	sterne.one_shot = true
	sterne.explosiveness = 1.0
	sterne.amount = 18
	sterne.lifetime = 0.8
	var mat := ParticleProcessMaterial.new()
	# Über die Türbreite verteilt und seitlich/hoch raus — Richtung Kamera
	# allein verschwinden die Sterne hinter Gooby.
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(door_width * 0.4, 0.5, 0.05)
	mat.direction = Vector3(0, 1.0, 0.55)
	mat.spread = 80.0
	mat.initial_velocity_min = 1.6
	mat.initial_velocity_max = 3.0
	mat.gravity = Vector3(0, -3.2, 0)
	mat.scale_min = 1.2
	mat.scale_max = 2.2
	# Ramp steuert primär das Ausfaden; die satte Farbe kommt zusätzlich als
	# albedo_color (Gürtel+Hosenträger — color_ramp allein verwusch im
	# Compatibility-Renderer gegen die helle Wand).
	mat.color_ramp = _verlauf(Color(1.0, 0.9, 0.55, 1.0), Color(1.0, 0.75, 0.5, 0.0))
	sterne.process_material = mat
	var quad := QuadMesh.new()
	quad.size = Vector2(0.3, 0.3)
	var stern_mat := _partikel_material("res://assets/ui/icons/sparkle.svg")
	stern_mat.albedo_color = Color(1.0, 0.72, 0.1)
	quad.material = stern_mat
	sterne.draw_pass_1 = quad
	sterne.position = Vector3(0.0, 1.0, 0.4)
	return sterne


## Unshaded Billboard-Material, das die Partikelfarbe (color_ramp) nutzt.
func _partikel_material(textur_pfad := "") -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	if textur_pfad != "" and ResourceLoader.exists(textur_pfad):
		mat.albedo_texture = load(textur_pfad)
	return mat


static func _verlauf(von: Color, nach: Color) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.set_color(0, von)
	gradient.set_color(1, nach)
	var tex := GradientTexture1D.new()
	tex.gradient = gradient
	return tex


func _build_tap_area() -> void:
	var area := Area3D.new()
	area.name = "TapArea"
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(door_width + 0.3, DOOR_HEIGHT + 0.2, 0.6)
	shape.shape = box
	shape.position = Vector3(0.0, DOOR_HEIGHT * 0.5, 0.15)
	area.add_child(shape)
	area.input_event.connect(_on_area_input)
	add_child(area)


func _on_area_input(
	_cam: Node, event: InputEvent, _pos: Vector3, _normal: Vector3, _idx: int
) -> void:
	var pressed: bool = (
		(event is InputEventMouseButton and event.pressed)
		or (event is InputEventScreenTouch and event.pressed)
	)
	if pressed:
		tapped.emit(door_id)


func _doors_animated() -> bool:
	var settings := get_node_or_null("/root/AppSettings")
	if settings == null:
		return true
	return settings.are_doors_animated() and not settings.is_reduced_motion()


func _open_panel() -> void:
	AudioDirector.try_play(self, "ui_open")
	_open_tween = create_tween()
	_open_tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_open_tween.tween_property(_hinge, "rotation:y", deg_to_rad(-105.0), 0.35)
	await _open_tween.finished
	_open_tween = null


func _run_stuck_gag(gooby: Node3D, ui_layer: Node) -> void:
	stuck_started.emit()
	if gooby != null and gooby.has_method("play_clip"):
		gooby.play_clip("squeeze_door")
	_staub.emitting = true
	_rattle()
	var overlay := TapMashOverlay.new()
	overlay.logic = logic
	overlay.mashed.connect(_rattle)
	if ui_layer != null:
		ui_layer.add_child(overlay)
	else:
		add_child(overlay)
	await overlay.completed
	stuck_resolved.emit()
	_staub.emitting = false
	await _pop_through(gooby)
	overlay.queue_free()
	logic.pop_finished()


func _rattle() -> void:
	var tween := create_tween()
	tween.tween_property(_hinge, "rotation:y", deg_to_rad(-100.0), 0.05)
	tween.tween_property(_hinge, "rotation:y", deg_to_rad(-105.0), 0.05)


## Durchploppen (POLISH-7): Sternchen-Burst + Squash auf Gooby UND Türblatt
## — der letzte Tap soll spürbar „ploppen“.
func _pop_through(gooby: Node3D) -> void:
	_sterne.restart()
	_sterne.emitting = true
	var tuer_squash := create_tween()
	tuer_squash.tween_property(_hinge, "scale", Vector3(1.12, 0.86, 1.0), 0.1)
	tuer_squash.tween_property(_hinge, "scale", Vector3.ONE, 0.22)
	if gooby == null:
		await get_tree().create_timer(0.3).timeout
		return
	if gooby.has_method("play_clip"):
		gooby.play_clip("hop")
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(gooby, "scale", Vector3(1.32, 0.68, 1.32), 0.1)
	(
		tween
		. chain()
		. tween_property(gooby, "scale", Vector3.ONE, 0.22)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	tween.parallel().tween_property(
		gooby, "global_position", global_position - global_transform.basis.z * 0.4, 0.3
	)
	await tween.finished


func _goto() -> void:
	travel_finished.emit(door_id)
	_busy = false
	var router := get_node_or_null("/root/SceneRouter")
	if router == null:
		push_warning("SceneRouter fehlt — Tür %s kann nicht reisen" % door_id)
		return
	router.goto(
		RoomDefs.route_target(target_room), {"door_id": to_door_id}, router.TravelType.DOOR_TRAVEL
	)


func _flat_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	return mat
