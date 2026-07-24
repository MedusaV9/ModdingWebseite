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
var _particles: GPUParticles3D
var _busy := false


## Baut die Tür-Optik + Tap-Fläche (von RoomBase gerufen).
func setup(p_door_id: String, p_target_room: String, p_to_door_id: String) -> void:
	door_id = p_door_id
	target_room = p_target_room
	to_door_id = p_to_door_id
	name = "Door_%s" % door_id
	_build_frame()
	_build_panel()
	_build_particles()
	_build_tap_area()


## Komplette Tür-Reise (Doc A §5). `gooby` braucht `walk_to(pos)` (Coroutine)
## und `play_clip(name)`; `ui_layer` nimmt das Tap-Mash-Overlay auf.
func travel(gooby: Node3D, ui_layer: Node) -> void:
	if _busy:
		return
	_busy = true
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
	_goto()


## Skip per Tap irgendwo (nicht während Tap-Mash — DoorLogic regelt das).
func skip() -> void:
	if _busy and logic != null:
		logic.skip()


func is_busy() -> bool:
	return _busy


func _build_frame() -> void:
	var post := BoxMesh.new()
	post.size = Vector3(0.08, DOOR_HEIGHT, 0.12)
	for side in [-1.0, 1.0]:
		var mesh := MeshInstance3D.new()
		mesh.mesh = post
		mesh.material_override = _flat_material(FRAME_COLOR)
		mesh.position = Vector3(side * (door_width * 0.5 + 0.04), DOOR_HEIGHT * 0.5, 0.0)
		add_child(mesh)
	var lintel := MeshInstance3D.new()
	var lintel_mesh := BoxMesh.new()
	lintel_mesh.size = Vector3(door_width + 0.24, 0.1, 0.12)
	lintel.mesh = lintel_mesh
	lintel.material_override = _flat_material(FRAME_COLOR)
	lintel.position = Vector3(0.0, DOOR_HEIGHT + 0.05, 0.0)
	add_child(lintel)


func _build_panel() -> void:
	_hinge = Node3D.new()
	_hinge.name = "Hinge"
	_hinge.position = Vector3(-door_width * 0.5, 0.0, 0.0)
	add_child(_hinge)
	var panel := MeshInstance3D.new()
	var panel_mesh := BoxMesh.new()
	panel_mesh.size = Vector3(door_width, DOOR_HEIGHT, DOOR_THICKNESS)
	panel.mesh = panel_mesh
	panel.material_override = _flat_material(PANEL_COLOR)
	panel.position = Vector3(door_width * 0.5, DOOR_HEIGHT * 0.5, 0.0)
	_hinge.add_child(panel)
	var knob := MeshInstance3D.new()
	var knob_mesh := SphereMesh.new()
	knob_mesh.radius = 0.04
	knob_mesh.height = 0.08
	knob.mesh = knob_mesh
	knob.material_override = _flat_material(Color(0.95, 0.8, 0.35))
	knob.position = Vector3(door_width * 0.85, 1.0, DOOR_THICKNESS)
	_hinge.add_child(knob)


func _build_particles() -> void:
	_particles = GPUParticles3D.new()
	_particles.emitting = false
	_particles.amount = 24
	_particles.lifetime = 0.7
	_particles.one_shot = false
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 60.0
	mat.initial_velocity_min = 0.6
	mat.initial_velocity_max = 1.4
	mat.gravity = Vector3(0, -2.0, 0)
	mat.scale_min = 0.5
	mat.scale_max = 1.0
	_particles.process_material = mat
	var mesh := SphereMesh.new()
	mesh.radius = 0.03
	mesh.height = 0.06
	_particles.draw_pass_1 = mesh
	_particles.position = Vector3(0.0, 1.0, 0.1)
	add_child(_particles)


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
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_hinge, "rotation:y", deg_to_rad(-105.0), 0.35)
	await tween.finished


func _run_stuck_gag(gooby: Node3D, ui_layer: Node) -> void:
	stuck_started.emit()
	if gooby != null and gooby.has_method("play_clip"):
		gooby.play_clip("squeeze_door")
	_particles.emitting = true
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
	_particles.emitting = false
	await _pop_through(gooby)
	overlay.queue_free()
	logic.pop_finished()


func _rattle() -> void:
	var tween := create_tween()
	tween.tween_property(_hinge, "rotation:y", deg_to_rad(-100.0), 0.05)
	tween.tween_property(_hinge, "rotation:y", deg_to_rad(-105.0), 0.05)


func _pop_through(gooby: Node3D) -> void:
	_particles.emitting = true
	if gooby == null:
		await get_tree().create_timer(0.3).timeout
		return
	if gooby.has_method("play_clip"):
		gooby.play_clip("hop")
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(gooby, "scale", Vector3(1.25, 0.75, 1.25), 0.12)
	tween.chain().tween_property(gooby, "scale", Vector3.ONE, 0.18)
	tween.parallel().tween_property(
		gooby, "global_position", global_position - global_transform.basis.z * 0.4, 0.3
	)
	await tween.finished
	_particles.emitting = false


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
