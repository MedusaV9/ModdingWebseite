## Tischplatte (Fluchttisch im Ereignis „Robo-Jagd").
static func table_top() -> MeshInstance3D:
	var table := MeshInstance3D.new()
	var top := BoxMesh.new()
	top.size = Vector3(0.9, 0.08, 0.9)
	table.mesh = top
	table.material_override = flat_mat(Color(0.52, 0.36, 0.22))
	return table
