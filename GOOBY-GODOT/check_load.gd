extends SceneTree

const PFADE := [
	"res://scripts/home/craft/craft_panel.gd",
	"res://scripts/home/goobay/goobay_panel.gd",
	"res://scripts/home/garden/garden_view.gd",
	"res://scripts/home/garden/garden_host.gd",
	"res://scripts/home/delivery_cutscene.gd",
	"res://scripts/home/room_base.gd",
	"res://scripts/home/build_mode/build_mode.gd",
	"res://scripts/home/home_state.gd",
	"res://scripts/home/garden/garden_state.gd",
]


func _initialize() -> void:
	for p in PFADE:
		var s: Variant = load(p)
		print("%s -> %s" % [p, "OK" if s != null else "FEHLER"])
	quit(0)
