class_name HomeCameraRig
extends Node3D
## Kamera-Rig der Raum-Szenen (W2a HOUSE): sanftes Follow/Pan hinter Gooby
## (geclampt auf den Raum) + 55°-Schräg-Draufsicht im Baumodus (Doc D §2.1).

const FOLLOW_OFFSET := Vector3(0.0, 4.6, 4.1)
const BUILD_OFFSET := Vector3(0.0, 6.8, 3.2)
const SMOOTHING := 3.5

var camera: Camera3D
var follow_target: Node3D

var _bounds := Rect2(Vector2.ZERO, Vector2(6, 5))
var _pivot := Vector3.ZERO
var _offset := FOLLOW_OFFSET
var _build_active := false


func _ready() -> void:
	camera = Camera3D.new()
	camera.fov = 45.0
	camera.current = true
	add_child(camera)
	_apply(1.0)


## Raumgrenzen in Weltmetern (XZ) — der Pivot bleibt im Raum.
func setup(room_world_size: Vector2) -> void:
	var margin := 0.8
	_bounds = Rect2(
		Vector2(margin, margin), (room_world_size - Vector2(margin, margin) * 2.0).max(Vector2.ZERO)
	)
	_pivot = Vector3(room_world_size.x * 0.5, 0.0, room_world_size.y * 0.5)
	_apply(1.0)


func set_build_mode(active: bool) -> void:
	_build_active = active
	_offset = BUILD_OFFSET if active else FOLLOW_OFFSET


func is_build_mode() -> bool:
	return _build_active


func _process(delta: float) -> void:
	var goal := _pivot
	if not _build_active and follow_target != null:
		goal = follow_target.global_position
	elif _build_active:
		goal = Vector3(
			_bounds.position.x + _bounds.size.x * 0.5,
			0.0,
			_bounds.position.y + _bounds.size.y * 0.5
		)
	goal.x = clampf(goal.x, _bounds.position.x, _bounds.position.x + _bounds.size.x)
	goal.z = clampf(goal.z, _bounds.position.y, _bounds.position.y + _bounds.size.y)
	goal.y = 0.0
	_pivot = _pivot.lerp(goal, 1.0 - exp(-SMOOTHING * delta))
	_apply(delta)


func _apply(delta: float) -> void:
	if camera == null:
		return
	var target_pos := _pivot + _offset
	camera.global_position = camera.global_position.lerp(target_pos, 1.0 - exp(-SMOOTHING * delta))
	camera.look_at(_pivot + Vector3(0, 0.5, 0))
