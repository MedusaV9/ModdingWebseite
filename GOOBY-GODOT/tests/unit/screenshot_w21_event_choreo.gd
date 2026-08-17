extends SceneTree
## W21-Screenshot-Werkzeug (KEIN Test — kein test_-Präfix): rendert die
## Nachher-Deliverables des Event-Kaperungs-Fixes (Blocker #2) als Review-
## Artefakte — (1) Nutella-Wahlkarte in der Bubble-Lane NEBEN der
## spielbaren Welt (Gooby sichtbar, kein full-rect STOP), (2) nach dem
## Vertagen (injizierte Uhr) nur noch der kleine Rand-Chip
## „{gooby} wartet…“ an der Lane-Kante. Braucht einen echten Renderer:
## xvfb-run -a godot --path GOOBY-GODOT --rendering-method gl_compatibility \
##   --rendering-driver opengl3 \
##   --script res://tests/unit/screenshot_w21_event_choreo.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/W21EVENT"
## Leitformat-Seitenverhältnis (iPhone quer, 2868×1320 → halbe Auflösung).
const LANDSCAPE := Vector2i(1434, 660)
const NOW_MS := 1785448800000  # 2026-07-30 UTC


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.theme = ThemeService.theme()
	_resize(LANDSCAPE)
	await _shot_event_choreo()
	print("Screenshots fertig -> %s" % OUT_DIR)
	quit(0)


## Wohnzimmer + HUD, Nutella-Event staged → Karte in der Lane; dann per
## injizierter Uhr vertagen → Rand-Chip. Beide Zustände fotografieren.
func _shot_event_choreo() -> void:
	var gs := root.get_node("/root/GameState")
	RandomEventEngine.register_slice()
	var room: RoomBase = (load("res://scenes/home/wohnzimmer.tscn") as PackedScene).instantiate()
	room.stunde_override = 13.0
	root.add_child(room)
	for _i in 24:
		await process_frame
	var hud: Hud = (load("res://scripts/ui/hud.tscn") as PackedScene).instantiate()
	root.add_child(hud)
	hud.set_stats({"hunger": 62.0, "energie": 71.0, "hygiene": 80.0, "spass": 55.0})
	for _i in 8:
		await process_frame
	var defs := RandomEventEngine.defs_from_registry()
	var def := RandomEventEngine.def_by_id(defs, "nutella_nacht")
	RandomEventEngine.activate(gs, def, NOW_MS)
	var runner := EventRunner.attach_to(room, defs)
	for _i in 12:
		await process_frame
	await _snap("w21_event_nachher_karte_in_lane.png")
	# Vertagen mit injizierter Uhr: Karte gleitet als Chip an den Rand.
	var choreo: EventChoreo = runner.get_node("EventChoreo")
	choreo.set_process(false)
	choreo.tick(EventChoreo.VERTAGEN_S + 0.1)
	for _i in 12:
		await process_frame
	await _snap("w21_event_nachher_rand_chip.png")
	room.queue_free()
	hud.queue_free()
	await process_frame


func _resize(size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	root.size = size
	root.set_content_scale_size(size)


func _snap(file_name: String) -> void:
	for _i in 4:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file_name])
	print("  %s (%dx%d)" % [file_name, image.get_width(), image.get_height()])
