extends SceneTree
## FIX5-Probe (KEIN Test): druckt die AABBs der Stadt-Kulissen-GLBs, damit
## die Skalierungen im CityKulisse-Planer auf echten Maßen beruhen.


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var pfade: Array[String] = [
		"res://assets/city/vorstadt/driveway-short.glb",
		"res://assets/city/vorstadt/fence-1x4.glb",
		"res://assets/city/vorstadt/fence-low.glb",
		"res://assets/city/vorstadt/planter.glb",
		"res://assets/city/vorstadt/path-stones-long.glb",
		"res://assets/city/vorstadt/tree-large.glb",
		"res://assets/city/vorstadt/tree-small.glb",
		"res://assets/city/strassen/light-curved.glb",
		"res://assets/city/strassen/light-square-double.glb",
		"res://assets/city/strassen/sign-highway.glb",
		"res://assets/city/strassen/construction-cone.glb",
		"res://assets/city/strassen/construction-barrier.glb",
		"res://assets/city/natur/tree_detailed.glb",
		"res://assets/city/natur/tree_oak.glb",
		"res://assets/city/natur/tree_fat.glb",
		"res://assets/city/natur/tree_pineTallA.glb",
		"res://assets/city/natur/flower_redA.glb",
		"res://assets/city/natur/grass_large.glb",
		"res://assets/city/natur/plant_bushLarge.glb",
		"res://assets/city/natur/rock_smallA.glb",
		"res://assets/city/natur/pot_large.glb",
		"res://assets/city/natur/tree_default.glb",
		"res://assets/city/gebaeude/building-a.glb",
		"res://assets/city/gebaeude/low-detail-building-b.glb",
		"res://assets/city/deko/streetlight.gltf",
		"res://assets/city/deko/bench.gltf",
		"res://assets/city/deko/firehydrant.gltf",
		"res://assets/city/autos/sedan.glb",
		"res://assets/city/autos/police.glb",
		"res://assets/city/strassen/road-straight.glb",
	]
	for pfad in pfade:
		var szene: PackedScene = load(pfad)
		if szene == null:
			print("%s -> LAEDT NICHT" % pfad)
			continue
		var node: Node3D = szene.instantiate()
		var gesamt := AABB()
		var erste := true
		var mesh_anzahl := 0
		for mesh in node.find_children("*", "MeshInstance3D", true, false):
			var mi: MeshInstance3D = mesh
			mesh_anzahl += 1
			var aabb := mi.transform * mi.get_aabb()
			if erste:
				gesamt = aabb
				erste = false
			else:
				gesamt = gesamt.merge(aabb)
		print(
			(
				"%s -> meshes=%d pos=%s size=%s"
				% [pfad.get_file(), mesh_anzahl, gesamt.position, gesamt.size]
			)
		)
		node.free()
	quit(0)
