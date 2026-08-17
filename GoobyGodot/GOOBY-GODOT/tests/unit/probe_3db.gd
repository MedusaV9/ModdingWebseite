extends SceneTree
## 3D-B-Sonde (KEIN Test): montiert ein Spiel, läuft ein paar Sekunden und
## meldet, WO Gooby, Kamera und Kulisse tatsächlich stehen. Nur zur Diagnose
## während des 3D-Umbaus.
##
##   xvfb-run -a godot --path GOOBY-GODOT --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --script res://tests/unit/probe_3db.gd -- runner

const HOST_SCENE := "res://scripts/minigames/minigame_host.tscn"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var game_id := str(args[0]) if args.size() > 0 else "runner"
	var size := Vector2i(1200, 760)
	DisplayServer.window_set_size(size)
	root.size = size
	root.set_content_scale_size(size)
	root.theme = ThemeService.theme()
	var gs := root.get_node_or_null(^"/root/GameState")
	if gs != null and gs.has_method("set_value"):
		gs.call("set_value", "gooby.stats.energy", 100.0)
	var host: MinigameHost = (load(HOST_SCENE) as PackedScene).instantiate()
	host.auto_navigate = false
	host.countdown_step_sec = 0.01
	(
		host
		. receive_params(
			{
				"game_id": game_id,
				"difficulty": "normal",
				"seed": 4242,
				"orientation": "landscape",
			}
		)
	)
	root.add_child(host)
	for _i in 20:
		await process_frame
	var found := host.find_children("*", "SubViewport", true, false)
	var viewport: SubViewport = found[0] as SubViewport
	print("SubViewport size: ", viewport.size)
	var game := viewport.get_child(viewport.get_child_count() - 1)
	if "autoplay" in game:
		game.set("autoplay", true)
	var frames := int(str(args[1])) if args.size() > 1 else 420
	for _i in frames:
		await process_frame
	print("game: ", game.get_class(), " ", game.get_script().resource_path)
	_dump(game, 0)
	_report_gooby(game)
	await process_frame
	root.get_texture().get_image().save_png("/tmp/gooby-godot/artifacts/3DB/probe.png")
	quit(0)


func _report_gooby(game: Node) -> void:
	var mount: Node3D = game.get("_gooby") as Node3D
	var stage: Node3D = game.get("_stage") as Node3D
	var cam: Camera3D = stage.get("camera") as Camera3D
	if mount == null or cam == null:
		print("KEIN Gooby/Kamera")
		return
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in mount.find_children("*", "MeshInstance3D", true, false):
		var world: AABB = mi.global_transform * mi.get_aabb()
		box = world if first else box.merge(world)
		first = false
		print("  mesh %s vis=%s aabb=%s" % [mi.name, mi.visible, world])
	print("Gooby-Welt-AABB: ", box)
	print(
		(
			"Gooby-Schirm: oben=%s unten=%s"
			% [
				cam.unproject_position(box.position + Vector3(0.0, box.size.y, 0.0)),
				cam.unproject_position(box.position)
			]
		)
	)


func _dump(node: Node, depth: int) -> void:
	var pad := "  ".repeat(depth)
	var extra := ""
	if node is Node3D:
		var n3 := node as Node3D
		extra = " pos=%s scale=%s vis=%s" % [n3.global_position, n3.scale, n3.visible]
	if node is VisualInstance3D:
		extra += " aabb=%s" % (node as VisualInstance3D).get_aabb()
	if node is Camera3D:
		var cam := node as Camera3D
		extra += " fov=%.1f current=%s" % [cam.fov, cam.current]
	print(pad, node.name, " [", node.get_class(), "]", extra)
	if depth >= 5:
		return
	for child in node.get_children():
		_dump(child, depth + 1)
