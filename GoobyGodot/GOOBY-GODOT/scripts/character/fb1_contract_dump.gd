extends SceneTree
## FB1-Kontrakt-Dump: schreibt Bone-, Clip- und Shapekey-Namen (+ Loop-Flags)
## aus res://assets/character/gooby.glb als JSON. Für den Vorher/Nachher-
## Vergleich beim Model-Rebuild — Namen sind Frozen-Contract (Cosmetics,
## Minispiele, gooby_rig.gd hängen daran).
##
## Aufruf:
##   godot --headless --path GOOBY-GODOT \
##     --script res://scripts/character/fb1_contract_dump.gd -- --out=/tmp/contract.json

const GLB_PATH := "res://assets/character/gooby.glb"


func _initialize() -> void:
	var out_path := "/tmp/fb1_contract.json"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--out="):
			out_path = arg.trim_prefix("--out=")
	var model: Node = (load(GLB_PATH) as PackedScene).instantiate()

	var bones: Array[String] = []
	for child in model.find_children("*", "Skeleton3D", true, false):
		var skeleton: Skeleton3D = child
		for i in range(skeleton.get_bone_count()):
			bones.append(skeleton.get_bone_name(i))
		break

	var clips := {}
	var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	if player != null:
		for anim_name in player.get_animation_list():
			var anim := player.get_animation(anim_name)
			clips[String(anim_name)] = {
				"loop": anim.loop_mode != Animation.LOOP_NONE,
				"length": snappedf(anim.length, 0.01),
			}

	var shapekeys: Array[String] = []
	for child in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance: MeshInstance3D = child
		for i in range(mesh_instance.get_blend_shape_count()):
			shapekeys.append(String(mesh_instance.mesh.get_blend_shape_name(i)))
		break

	var contract := {"bones": bones, "clips": clips, "shapekeys": shapekeys}
	var out_file := FileAccess.open(out_path, FileAccess.WRITE)
	out_file.store_string(JSON.stringify(contract, "  "))
	out_file.close()
	print("[fb1] Kontrakt: %s" % out_path)
	model.free()
	quit(0)
