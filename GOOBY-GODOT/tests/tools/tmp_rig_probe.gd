extends SceneTree


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = load("res://assets/character/gooby.glb")
	var model: Node3D = packed.instantiate()
	root.add_child(model)
	var mesh: MeshInstance3D = _find(model, "MeshInstance3D")
	var skel: Skeleton3D = _find(model, "Skeleton3D")
	if mesh != null:
		print("== blendshapes ==")
		for i in mesh.get_blend_shape_count():
			print("  ", mesh.mesh.get_blend_shape_name(i))
		print("== surfaces ==")
		for i in mesh.mesh.get_surface_count():
			var mat: Material = mesh.mesh.surface_get_material(i)
			if mat is StandardMaterial3D:
				print("  surf %d albedo=%s" % [i, (mat as StandardMaterial3D).albedo_color])
			else:
				print("  surf %d %s" % [i, mat])
		print("aabb=", mesh.get_aabb())
	if skel != null:
		print("== bones ==")
		for i in skel.get_bone_count():
			print("  %s pos=%s" % [skel.get_bone_name(i), skel.get_bone_global_rest(i).origin])
	quit(0)


func _find(node: Node, klass: String) -> Variant:
	if node.is_class(klass):
		return node
	for child in node.get_children():
		var found: Variant = _find(child, klass)
		if found != null:
			return found
	return null
