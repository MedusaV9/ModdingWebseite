extends SceneTree
## 3D-B-Hilfssonde (KEIN Test): listet die Clip-Namen des Gooby-Rigs.


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var rig := GoobyRig.new()
	root.add_child(rig)
	for _i in 5:
		await process_frame
	print("CLIPS: ", rig.clip_names())
	quit(0)
