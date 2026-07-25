extends RefCounted
## Modell-Bank der 3D-Bühnen (Agent 3D-C) — gemeinsam genutzt von star_hopper,
## rocket_rescue, burger_build, purble_place, hide_seek und veggie_chop.
##
## Aufgabe: ein Kenney-/TinyTreats-Modell laden, EINMAL vermessen und danach
## billig ausgeben — entweder als fertig platzierten Knoten (Einzelstücke) oder
## als {mesh, xform}-Liste für MultiMeshInstance3D (Massenware, 1 Draw-Call je
## Teilmesh). Der Ordner `_3dc_stage` enthält KEIN Spiel (kein game.json), die
## Minigame-Registry sieht ihn also nicht.
##
## Alles ist statisch gecacht: ein GLB wird pro Sitzung genau einmal geladen
## und vermessen, egal wie viele Runden/Spiele es anfassen.

## path → PackedScene
static var _scenes: Dictionary = {}
## path → {"aabb": AABB, "parts": Array[{mesh, xform}]}
static var _baked: Dictionary = {}


## Roh-AABB in Modellkoordinaten (unskaliert).
static func aabb(path: String) -> AABB:
	return _bake(path)["aabb"] as AABB


## Aufhängepunkt an einem Rig-Knochen (Kochmütze auf Goobys Kopf). Ein starr in
## den Rig-Ursprung gehängter Aufsatz DRIFTET, sobald ein Clip den Oberkörper
## bewegt oder die Emotions-Pose den Kopf neigt — dann schwebt die Mütze über
## dem Ohr. Der Rückgabewert ist der Elternknoten für die Requisite; findet sich
## kein Skelett, kommt das Rig selbst zurück (Aufsatz bleibt sichtbar).
## Der Kopf-Knochen sitzt bei Rig-y ≈ 0,457, das Rig ist 1,13 hoch.
static func bone_mount(rig: Node3D, bone := "head") -> Node3D:
	var found := rig.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		return rig
	var skeleton: Skeleton3D = found[0]
	var idx := skeleton.find_bone(bone)
	if idx < 0:
		return rig
	var mount := BoneAttachment3D.new()
	mount.bone_name = bone
	mount.bone_idx = idx
	skeleton.add_child(mount)
	return mount


## Instanz des Modells, eingepasst auf `target` Meter der größten Kante
## (0 = Originalgröße). `ground` zieht die Unterkante auf y = 0.
static func node(path: String, target := 0.0, ground := true) -> Node3D:
	var holder := Node3D.new()
	var packed := _scene(path)
	if packed == null:
		return holder
	var model := packed.instantiate()
	holder.add_child(model)
	var box := aabb(path)
	var factor := 1.0
	if target > 0.0:
		factor = target / maxf(0.001, maxf(box.size.x, maxf(box.size.y, box.size.z)))
	model.scale = Vector3.ONE * factor
	var center := box.get_center() * factor
	model.position = Vector3(
		-center.x, -box.position.y * factor if ground else -center.y, -center.z
	)
	return holder


## Instanz, eingepasst auf `target` Meter HÖHE (Kisten, Regale, Bäume).
static func node_by_height(path: String, target: float, ground := true) -> Node3D:
	var box := aabb(path)
	var longest := maxf(box.size.x, maxf(box.size.y, box.size.z))
	return node(path, target * longest / maxf(0.001, box.size.y), ground)


## {mesh, xform}-Liste für MultiMeshInstance3D, auf `target` Meter größte Kante
## skaliert; `ground` setzt die Unterkante auf y = 0, sonst zentriert.
static func parts(path: String, target := 0.0, ground := true) -> Array:
	var baked := _bake(path)
	var box: AABB = baked["aabb"]
	var factor := 1.0
	if target > 0.0:
		factor = target / maxf(0.001, maxf(box.size.x, maxf(box.size.y, box.size.z)))
	var center := box.get_center() * factor
	var shift := Vector3(-center.x, -box.position.y * factor if ground else -center.y, -center.z)
	var base := Transform3D(Basis.IDENTITY.scaled(Vector3.ONE * factor), shift)
	var out: Array = []
	for entry: Dictionary in baked["parts"]:
		out.append({"mesh": entry["mesh"], "xform": base * (entry["xform"] as Transform3D)})
	return out


## Erstes Mesh des Modells (für Fälle, in denen ein Teil reicht).
static func first_mesh(path: String) -> Mesh:
	var baked := _bake(path)
	var list: Array = baked["parts"]
	return null if list.is_empty() else (list[0] as Dictionary)["mesh"] as Mesh


## Massen-Requisite: EIN Modell, viele feste Posen, 1 Draw-Call je Teilmesh.
## `poses` sind Welt-Transforms; der eingebackene Teil-Offset kommt dazu.
static func swarm(parts_list: Array, poses: Array, cull_margin := 40.0) -> Node3D:
	var holder := Node3D.new()
	for entry: Dictionary in parts_list:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = entry["mesh"]
		mm.instance_count = maxi(1, poses.size())
		for i in poses.size():
			mm.set_instance_transform(
				i, (poses[i] as Transform3D) * (entry["xform"] as Transform3D)
			)
		mm.visible_instance_count = poses.size()
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.extra_cull_margin = cull_margin
		holder.add_child(mmi)
	return holder


## Färbt alle Materialien einer Instanz um (Gold-Karotte, Pastell-Requisiten).
static func tint(node3d: Node, color: Color, emission := 0.0) -> void:
	if node3d is MeshInstance3D:
		var mesh_node := node3d as MeshInstance3D
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		if emission > 0.0:
			mat.emission_enabled = true
			mat.emission = color
			mat.emission_energy_multiplier = emission
		mesh_node.material_override = mat
	for child in node3d.get_children():
		tint(child, color, emission)


static func _scene(path: String) -> PackedScene:
	if _scenes.has(path):
		return _scenes[path]
	var packed: PackedScene = null
	if ResourceLoader.exists(path):
		packed = load(path)
	if packed == null:
		push_warning("Models3D: Modell fehlt: %s" % path)
	_scenes[path] = packed
	return packed


static func _bake(path: String) -> Dictionary:
	if _baked.has(path):
		return _baked[path]
	var result := {"aabb": AABB(Vector3.ZERO, Vector3.ONE), "parts": []}
	var packed := _scene(path)
	if packed != null:
		var root := packed.instantiate()
		var parts_out: Array = []
		var box := AABB()
		var first := true
		_collect(root, Transform3D.IDENTITY, parts_out)
		for entry: Dictionary in parts_out:
			var mesh: Mesh = entry["mesh"]
			var xform: Transform3D = entry["xform"]
			var part_box := xform * mesh.get_aabb()
			box = part_box if first else box.merge(part_box)
			first = false
		if not first:
			result = {"aabb": box, "parts": parts_out}
		root.free()
	_baked[path] = result
	return result


static func _collect(node3d: Node, xform: Transform3D, out: Array) -> void:
	var here := xform
	if node3d is Node3D:
		here = xform * (node3d as Node3D).transform
	if node3d is MeshInstance3D and (node3d as MeshInstance3D).mesh != null:
		out.append({"mesh": (node3d as MeshInstance3D).mesh, "xform": here})
	for child in node3d.get_children():
		_collect(child, here, out)
