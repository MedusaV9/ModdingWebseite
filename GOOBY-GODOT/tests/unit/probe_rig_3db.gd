extends SceneTree
## 3D-B-Hilfswerkzeug (KEIN Test): misst die tatsächliche Höhe des Gooby-Rigs,
## damit `GoobyMount.RAW_HEIGHT` stimmt (davon hängt jede Figurgröße ab).
##
##   godot --headless --path GOOBY-GODOT --script res://tests/unit/probe_rig_3db.gd

const GLB := "res://assets/character/gooby.glb"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var scene := load(GLB) as PackedScene
	var node := scene.instantiate()
	root.add_child(node)
	await process_frame
	print("GLB-AABB: ", _bounds(node))
	node.queue_free()
	var rig := GoobyRig.new()
	root.add_child(rig)
	for _i in 4:
		await process_frame
	print("Rig-AABB (scale 1): ", _bounds(rig))
	quit(0)


func _bounds(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var world: AABB = mi.global_transform * mi.get_aabb()
		box = world if first else box.merge(world)
		first = false
	return box
