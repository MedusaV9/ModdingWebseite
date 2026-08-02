extends SceneTree
## PT-1-Diagnose (KEIN Playtest-Flow): headless prüfen, warum die Garten-
## Defaults (treeDefault/treeFat/gardenBench/potLarge) im Lauf v4 zwar im
## Grid liegen, aber NICHT als FurnitureNode spawnen (ASSET-ROT-Verdacht).
## Aufruf: godot --headless --path GOOBY-GODOT
##         --script res://tests/tools/playtest_flows/flow_pt1_diag_assets.gd

const IDS := ["treeDefault", "treeFat", "gardenBench", "potLarge", "flowerRed", "loungeSofa"]


func _initialize() -> void:
	for id: String in IDS:
		_pruefe(id)
	quit(0)


func _pruefe(id: String) -> void:
	var def := FurnitureCatalog.def(id)
	if def.is_empty():
		print("[DIAG] %s: DEF LEER (Katalog kennt das Item nicht!)" % id)
		return
	var path := FurnitureCatalog.glb_path(def)
	var existiert := ResourceLoader.exists(path)
	print(
		(
			"[DIAG] %s: glb=%s exists=%s blocks=%s layer=%s"
			% [id, path, existiert, def.get("blocks_movement"), def.get("layer")]
		)
	)
	if not existiert:
		return
	var scene: PackedScene = load(path)
	print("[DIAG]   load -> %s" % str(scene))
	if scene != null:
		var inst := scene.instantiate()
		print("[DIAG]   instantiate -> %s" % str(inst))
		if inst != null:
			inst.free()
	var node := FurnitureNode.create(def, Vector2i(0, 0), 0, "diag")
	print("[DIAG]   FurnitureNode.create -> %s" % str(node))
	if node != null:
		node.free()
