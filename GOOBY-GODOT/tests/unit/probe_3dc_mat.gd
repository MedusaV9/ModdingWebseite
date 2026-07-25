extends SceneTree

func _init() -> void:
	for p in [
		"res://assets/minigames/burger_build/tomato-slice.glb",
		"res://assets/minigames/burger_build/salad.glb",
		"res://assets/minigames/veggie_chop/paprika.glb",
		"res://assets/minigames/hide_seek/pot_large.glb",
	]:
		var ps := load(p) as PackedScene
		if ps == null:
			print("MISSING ", p)
			continue
		var n := ps.instantiate()
		print("== ", p)
		_walk(n, 0)
		n.free()
	quit(0)

func _walk(n: Node, d: int) -> void:
	if n is MeshInstance3D:
		var m := (n as MeshInstance3D).mesh
		for i in m.get_surface_count():
			var mat := m.surface_get_material(i)
			var line := "  surf %d: %s" % [i, mat]
			if mat is StandardMaterial3D:
				var sm := mat as StandardMaterial3D
				line += " albedo=%s tex=%s" % [sm.albedo_color, sm.albedo_texture]
			elif mat is BaseMaterial3D:
				line += " (base)"
			print(line)
	for c in n.get_children():
		_walk(c, d + 1)
