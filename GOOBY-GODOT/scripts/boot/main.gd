extends Node
## Boot-Szene (W1a). Die Autoloads (AppSettings, OrientationService,
## SceneRouter) sind hier bereits geladen; main verdrahtet nur den
## Router-Mount-Point und zeigt ein Platzhalter-Home (W1c ersetzt es).

@onready var world: Node3D = $World


func _ready() -> void:
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("set_mount_point"):
		router.set_mount_point(world)
