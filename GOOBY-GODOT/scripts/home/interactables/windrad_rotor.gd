class_name WindradRotor
extends Node3D
## W15/INTEGRATE (MARKT→HOME-Request): die Windrad-Deko dreht ihren Rotor
## im Gartenwind — gleiche gemütliche Drehgeschwindigkeit wie die
## Ranch-Windräder (ranch_hof_scene/ranch_fahrt_scene: 0.9 rad/s). Dockt
## über den InteractablesHost an (Muster Fernseher/Nougatschleuse), damit
## FurnitureNode selbst unangetastet bleibt. Ohne Rotor-Node im GLB bleibt
## die Deko still stehen (kein Prozess-Takt).

## Name der Rotor-Node im Windrad-GLB (minigames/mini_golf/windmill.glb).
const ROTOR_NODE := "blades"
## Drehgeschwindigkeit in rad/s — wie die Ranch-Windräder.
const DREH_RAD_S := 0.9

var _rotor: Node3D = null


func setup(_host: Node, furniture: Node3D) -> void:
	var node := furniture.find_child(ROTOR_NODE, true, false)
	_rotor = node if node is Node3D else null
	set_process(_rotor != null)


func _process(delta: float) -> void:
	if _rotor == null or not is_instance_valid(_rotor):
		set_process(false)
		return
	_rotor.rotation.z += delta * DREH_RAD_S
