extends SceneTree
## 3D-B-Hilfswerkzeug (KEIN Test): listet die Materialien der Kulissen-Modelle,
## um schwarz gerenderte Fassaden aufzuspüren.
##
##   godot --headless --path GOOBY-GODOT --script res://tests/unit/probe_mats_3db.gd

const PATHS: Array[String] = [
	"res://assets/city/gebaeude/building-a.glb",
	"res://assets/city/gebaeude/building-b.glb",
	"res://assets/city/gebaeude/building-c.glb",
	"res://assets/city/gebaeude/building-d.glb",
	"res://assets/city/gebaeude/building-e.glb",
	"res://assets/city/gebaeude/building-f.glb",
]


func _init() -> void:
	for path in PATHS:
		print("== ", path)
		var packed := load(path) as PackedScene
		if packed == null:
			print("   (nicht ladbar)")
			continue
		var root_node := packed.instantiate()
		_walk(root_node, 0)
		root_node.free()
	quit(0)


func _walk(node: Node, depth: int) -> void:
	var mesh_node := node as MeshInstance3D
	if mesh_node != null and mesh_node.mesh != null:
		for i in mesh_node.mesh.get_surface_count():
			var mat := mesh_node.mesh.surface_get_material(i)
			var std := mat as StandardMaterial3D
			if std == null:
				print("   %s[%d]: %s" % [mesh_node.name, i, mat])
				continue
			print(
				(
					"   %s[%d] albedo=%s tex=%s unshaded=%s cull=%d"
					% [
						mesh_node.name,
						i,
						std.albedo_color,
						"ja" if std.albedo_texture != null else "nein",
						std.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED,
						std.cull_mode,
					]
				)
			)
	for child in node.get_children():
		_walk(child, depth + 1)
