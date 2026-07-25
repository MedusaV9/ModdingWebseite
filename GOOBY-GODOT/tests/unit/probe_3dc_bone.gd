extends SceneTree
## 3D-C-Hilfsskript (KEIN Test): misst, wo der Kopf-Knochen des Gooby-Rigs im
## Rig-Koordinatensystem sitzt. Daraus kommt der Offset der Kochmützen in
## burger_build/veggie_chop (BoneAttachment3D statt fester Aufsatz).
##   godot --headless --path GOOBY-GODOT --script res://tests/unit/probe_3dc_bone.gd


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var rig := GoobyRig.new()
	root.add_child(rig)
	for _i in 8:
		await process_frame
	var found := rig.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		print("kein Skeleton3D gefunden")
		quit(1)
		return
	var skeleton: Skeleton3D = found[0]
	print("skeleton pfad=%s xform=%s" % [str(skeleton.get_path()), str(skeleton.global_transform)])
	for bone in ["head", "spine", "root"]:
		var idx := skeleton.find_bone(bone)
		if idx < 0:
			print("  %s: fehlt" % bone)
			continue
		var world: Transform3D = skeleton.global_transform * skeleton.get_bone_global_pose(idx)
		print(
			(
				"  %s: idx=%d rig-lokal=%s"
				% [bone, idx, str(rig.global_transform.affine_inverse() * world)]
			)
		)
	var aabb := _aabb(rig)
	print("rig aabb=%s" % str(aabb))
	quit(0)


func _aabb(node: Node) -> AABB:
	var box := AABB()
	var first := true
	for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
		var here := mesh.global_transform * mesh.get_aabb()
		box = here if first else box.merge(here)
		first = false
	return box
