extends Node
## Test-Fixture (W1a): erfüllt den ready_for_reveal-Contract des SceneRouters
## nach ready_delay_frames Frames; merkt sich receive_params()-Payload.

signal ready_for_reveal

@export var ready_delay_frames := 1

var ready_emitted := false
var received_params: Dictionary = {}


func receive_params(params: Dictionary) -> void:
	received_params = params


func _ready() -> void:
	_emit_after_delay()


func _emit_after_delay() -> void:
	for _i in ready_delay_frames:
		await get_tree().process_frame
	ready_emitted = true
	ready_for_reveal.emit()
