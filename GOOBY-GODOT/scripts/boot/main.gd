extends Node
## Boot-Szene (W1a). Die Autoloads sind hier bereits geladen; main instanziert
## den Zuhause-Einstieg (W2a: HomeEntry setzt Router-Mount-Point, HUD,
## Onboarding und lädt danach das Wohnzimmer — siehe W2a-boot-request).

@onready var world: Node3D = $World


func _ready() -> void:
	var entry_scene := load("res://scenes/home/home_entry.tscn") as PackedScene
	if entry_scene != null:
		add_child(entry_scene.instantiate())
		return
	# Fallback (Einstieg fehlt): Mount-Point wie in W1 setzen.
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("set_mount_point"):
		router.set_mount_point(world)
