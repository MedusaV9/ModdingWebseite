extends SceneTree
## W4-P5 (INFRA, Plan §2.4-14) — Draw-Call-/Tris-Messfahrt Stadt + Räume
## (KEIN Test — kein test_-Präfix; Dev-Werkzeug wie die screenshot_w*-Skripte).
##
## Lädt city_scene + alle 5 Raum-Szenen nacheinander, wartet auf
## ready_for_reveal + Settle-Frames und misst dann über MESS_FRAMES Frames:
## FPS, Frame-Zeit, Draw Calls, Primitive (Tris), Nodes, VRAM — via
## scripts/dev/perf_overlay.gd::snapshot() (dasselbe Orakel wie im Spiel).
## Ergebnis: Markdown-Tabelle auf stdout + Overlay-Screenshot der Stadt.
##
## Braucht einen ECHTEN Renderer (headless = Dummy = 0en):
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --script res://scripts/dev/perf_probe.gd
## Hinweis: gl_compatibility auf Software-GL (llvmpipe) — Draw-Calls/Tris sind
## renderer-unabhängig aussagekräftig, absolute FPS NICHT (CPU-Rasterizer).

const OUT_DIR := "/tmp/gooby-godot/artifacts/W4-P5"
const SETTLE_FRAMES := 40
const MESS_FRAMES := 60

const PerfOverlayScript := preload("res://scripts/dev/perf_overlay.gd")
const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

var _seq := 0
var _rows: Array[Dictionary] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.theme = ThemeService.theme()
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	var overlay: CanvasLayer = PerfOverlayScript.new()
	root.add_child(overlay)
	overlay.set_shown(true)
	await _probe_city(overlay)
	for room_id: String in RoomDefs.ids():
		await _probe_room(room_id, overlay)
	_print_table()
	quit(0)


func _probe_city(overlay: CanvasLayer) -> void:
	var gs := _make_gs(true)
	var city: CityScene = load("res://scenes/city/city_scene.tscn").instantiate()
	city.game_state_override = gs
	root.add_child(city)
	await _wait_ready(city)
	_rows.append(await _measure("Stadt (city_scene, freie Fahrt)", overlay))
	await _snap("perf_overlay_stadt.png")
	PanelStack.clear()
	city.queue_free()
	await process_frame
	await process_frame
	gs.free()
	SaveSchema.unregister_slice(CityState.SLICE_ID)
	CityState.reset_for_tests()


func _probe_room(room_id: String, overlay: CanvasLayer) -> void:
	var gs := _make_gs(false)
	var room: RoomBase = load(str(RoomDefs.room(room_id)["scene"])).instantiate()
	room.game_state_override = gs
	root.add_child(room)
	await _wait_ready(room)
	_rows.append(await _measure("Raum %s" % room_id, overlay))
	if room_id == "living":
		await _snap("perf_overlay_wohnzimmer.png")
	room.queue_free()
	await process_frame
	await process_frame
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()


func _make_gs(for_city: bool) -> Node:
	_seq += 1
	var dir := "user://w4p5_perf/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	if for_city:
		CityState.register_slice()
	else:
		HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	return gs


func _wait_ready(scene: Node) -> void:
	var ready_flag := [false]
	if scene.has_signal("ready_for_reveal"):
		scene.ready_for_reveal.connect(func() -> void: ready_flag[0] = true)
	var deadline := Time.get_ticks_msec() + 15000
	while not ready_flag[0] and Time.get_ticks_msec() < deadline:
		await process_frame
	for _i in SETTLE_FRAMES:
		await process_frame


## Misst über MESS_FRAMES Frames; Draw Calls/Primitive/Nodes als Maximum
## (stabiler Volllast-Wert), FPS/Frame-Zeit als Durchschnitt.
func _measure(label: String, overlay: CanvasLayer) -> Dictionary:
	var fps_sum := 0.0
	var frame_ms_sum := 0.0
	var draw_max := 0
	var prim_max := 0
	var nodes_max := 0
	var vram := 0.0
	for _i in MESS_FRAMES:
		await process_frame
		var m: Dictionary = overlay.snapshot()
		fps_sum += float(m["fps"])
		frame_ms_sum += float(m["frame_ms"])
		draw_max = maxi(draw_max, int(m["draw_calls"]))
		prim_max = maxi(prim_max, int(m["primitives"]))
		nodes_max = maxi(nodes_max, int(m["nodes"]))
		vram = maxf(vram, float(m["vram_mb"]))
	return {
		"label": label,
		"fps": fps_sum / MESS_FRAMES,
		"frame_ms": frame_ms_sum / MESS_FRAMES,
		"draw": draw_max,
		"prim": prim_max,
		"nodes": nodes_max,
		"vram": vram,
	}


func _print_table() -> void:
	print("")
	print("| Szene | Draw Calls | Primitive (Tris) | Nodes | VRAM MB | FPS* | Frame ms* |")
	print("|---|---|---|---|---|---|---|")
	for row: Dictionary in _rows:
		print(
			(
				"| %s | %d | %d | %d | %.1f | %.0f | %.1f |"
				% [
					row["label"],
					row["draw"],
					row["prim"],
					row["nodes"],
					row["vram"],
					row["fps"],
					row["frame_ms"],
				]
			)
		)
	print("(*FPS/Frame-Zeit unter xvfb/llvmpipe — nur Relation aussagekräftig)")


func _snap(file: String) -> void:
	for _i in 8:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("  Screenshot: %s (%dx%d)" % [file, image.get_width(), image.get_height()])
