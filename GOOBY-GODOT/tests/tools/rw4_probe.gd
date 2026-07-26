extends SceneTree
## RW-4-Diagnose (KEIN Test): misst Gebaeude-AABBs und DorfLaden-Rects.

const GameStateScript := preload("res://scripts/state/game_state.gd")


func _initialize() -> void:
	_lauf.call_deferred()


func _lauf() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	await process_frame
	for datei: String in [
		"scheune_klein.glb", "silo_haus.glb", "scheune_gross.glb", "scheune.glb",
		"scheune_offen.glb", "brunnen.glb", "windmuehle.glb"
	]:
		var szene: PackedScene = load("res://assets/ranch/gebaeude/%s" % datei)
		var node: Node3D = szene.instantiate()
		node.scale = Vector3.ONE * 2.6
		root.add_child(node)
		await process_frame
		var aabb := AABB()
		var erster := true
		for mi: Node in node.find_children("*", "MeshInstance3D", true, false):
			var t := (mi as MeshInstance3D).global_transform
			var box := t * (mi as MeshInstance3D).mesh.get_aabb()
			aabb = box if erster else aabb.merge(box)
			erster = false
		print("%s @2.6: size=%s" % [datei, aabb.size])
		node.queue_free()
		await process_frame
	# DorfLaden-Rects pruefen.
	RanchState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize("user://rw4_probe/save_v5.json")
	gs.set_value("economy.coins", 1000)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	var laden := DorfLaden.neu("futterhof", gs)
	layer.add_child(laden)
	await process_frame
	await process_frame
	print("laden rect=%s size=%s" % [laden.position, laden.size])
	for kind: Node in laden.get_children():
		if kind is Control:
			var c := kind as Control
			print("  kind=%s pos=%s size=%s" % [c.get_class(), c.position, c.size])
	quit(0)
