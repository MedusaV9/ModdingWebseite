extends SceneTree
## Wegwerf-Sonde (Agent 3D-A): druckt Knotenbaum + AABB der kopierten GLBs,
## damit die Bühnen mit echten Maßen statt geratener Skalen bauen.

const PATHS := [
	"res://assets/minigames/mini_golf/tree_oak.glb",
	"res://assets/minigames/mini_golf/tree_fat.glb",
	"res://assets/minigames/mini_golf/tree_pineRoundA.glb",
	"res://assets/minigames/mini_golf/grass_large.glb",
	"res://assets/minigames/mini_golf/rock_smallA.glb",
	"res://assets/minigames/mini_golf/plant_bushLarge.glb",
	"res://assets/minigames/mini_golf/bench.glb",
	"res://assets/minigames/mini_golf/windmill.glb",
	"res://assets/minigames/mini_golf/tunnel-wide.glb",
	"res://assets/minigames/mini_golf/tree_default.glb",
	"res://assets/minigames/mini_golf/plant_bush.glb",
	"res://assets/minigames/mini_golf/flower_redA.glb",
	"res://assets/minigames/fishing_pond/boat-row-small.glb",
	"res://assets/minigames/fishing_pond/fish.glb",
	"res://assets/minigames/fishing_pond/bridge_wood.glb",
	"res://assets/minigames/fishing_pond/rock_largeA.glb",
	"res://assets/minigames/fishing_pond/grass_large.glb",
	"res://assets/minigames/fishing_pond/tree_pineRoundA.glb",
	"res://assets/minigames/ghost_hunt/crop_pumpkin.glb",
	"res://assets/minigames/ghost_hunt/fence_simple.glb",
	"res://assets/minigames/ghost_hunt/log.glb",
	"res://assets/minigames/ghost_hunt/stump_round.glb",
	"res://assets/minigames/ghost_hunt/tree_pineTallA.glb",
	"res://assets/minigames/goalie_gooby/flower_yellowA.glb",
	"res://assets/character/gooby.glb",
]


func _init() -> void:
	for path: String in PATHS:
		print("\n== %s" % path)
		if not ResourceLoader.exists(path):
			print("  FEHLT")
			continue
		var packed: PackedScene = load(path)
		var root := packed.instantiate()
		_dump(root, 1)
		root.free()
	quit(0)


func _dump(node: Node, depth: int) -> void:
	var line := "%s%s [%s]" % ["  ".repeat(depth), node.name, node.get_class()]
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		var box := (node as MeshInstance3D).mesh.get_aabb()
		line += (
			" aabb=%.2v..%.2v surfaces=%d"
			% [box.position, box.size, (node as MeshInstance3D).mesh.get_surface_count()]
		)
	print(line)
	for child in node.get_children():
		_dump(child, depth + 1)
