extends SceneTree
## FIX-3-Perf-Probe (KEIN Test — kein test_-Präfix): misst die Frame-Zeiten
## beim Öffnen/Schließen des Baumodus, die Kosten pro Ghost-Drag-Event und
## die Draw-Calls im offenen Baumodus (inkl. Stadt-Kulisse).
## Läuft mit echtem Renderer für realistische Zahlen (Shader-Kompilierung!):
##   xvfb-run -a godot --path . --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --script res://tests/unit/fix3_perf_probe.gd
##
## Vorher/Nachher: FIX3_PHASE=vorher simuliert die ALTEN Pfade in einem
## frischen Prozess (kein Shader-Warm-up beim Raumaufbau, Drawer-Neubau bei
## jedem Öffnen, Ghost-Neuaufbau bei jedem Drag-Event) — Default misst den
## aktuellen Stand. Beide Läufe gehören in den FIX-3-Bericht.

const ZYKLEN := 20
const DRAG_EVENTS := 60

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

var _vorher := false


func _init() -> void:
	_vorher = OS.get_environment("FIX3_PHASE") == "vorher"
	_run.call_deferred()


func _run() -> void:
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	print("== FIX3-PERF (%s) ==" % ("VORHER-Simulation" if _vorher else "NACHHER"))
	var dir := "user://fix3_probe/%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	HomeState.ensure_initialized(gs)
	# Lager füllen, damit der Drawer-Aufbau realistische Kosten hat.
	for item: String in ["chair", "table", "bookcaseOpen", "loungeSofa", "pottedPlant"]:
		HomeState.store_item(gs, item)
	HomeState.set_flag(gs, HomeState.FLAG_BED_PLACED, true)
	var scene: PackedScene = load("res://scenes/home/wohnzimmer.tscn")
	var room: RoomBase = scene.instantiate()
	room.game_state_override = gs
	room.stunde_override = 13.0
	root.add_child(room)
	if _vorher:
		# Warm-up neutralisieren: unsichtbare Nodes rendern nicht → die
		# Overlay-/Ghost-Shader kompilieren erst beim ersten open() —
		# exakt das alte Verhalten.
		room.visible = false
	for _i in 90:
		await process_frame
	if _vorher:
		room.visible = true
		for _i in 30:
			await process_frame
	var build: BuildMode = room.get_node("BuildMode")
	# Ruhe-Referenz: so teuer ist ein Frame OHNE Baumodus-Aktivität.
	var idle := await _frame_stats(30)
	print("  idle: avg=%.2fms worst=%.2fms" % [float(idle["avg"]), float(idle["worst"])])
	var open_ms: Array[float] = []
	var close_ms: Array[float] = []
	var open_frame_ms: Array[float] = []
	var close_frame_ms: Array[float] = []
	var draw_calls := 0
	for zyklus in ZYKLEN:
		if _vorher:
			build._drawer_sig = ""
		var t0 := Time.get_ticks_usec()
		room.open_build_mode()
		var call_open := (Time.get_ticks_usec() - t0) / 1000.0
		var worst_open := await _worst_frame_ms(10)
		draw_calls = maxi(
			draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		)
		t0 = Time.get_ticks_usec()
		build.close()
		var call_close := (Time.get_ticks_usec() - t0) / 1000.0
		var worst_close := await _worst_frame_ms(10)
		open_ms.append(call_open)
		close_ms.append(call_close)
		open_frame_ms.append(worst_open)
		close_frame_ms.append(worst_close)
		print(
			(
				(
					"  zyklus=%02d open_call=%.2fms open_worst_frame=%.2fms "
					+ "close_call=%.2fms close_worst_frame=%.2fms"
				)
				% [zyklus + 1, call_open, worst_open, call_close, worst_close]
			)
		)
		if build.is_active():
			print("  FEHLER: Baumodus nach close() noch aktiv (Zyklus %d)!" % (zyklus + 1))
	# Ghost-Drag-Kosten: Ghost aufnehmen und über den Raum ziehen. In der
	# VORHER-Simulation wird der Pool-Schlüssel pro Event gelöscht → der
	# Ghost-Node wird (wie früher) jedes Mal neu instanziert.
	room.open_build_mode()
	await _worst_frame_ms(10)
	build._begin_new(FurnitureCatalog.def("chair"))
	await process_frame
	var drag_t0 := Time.get_ticks_usec()
	for i in DRAG_EVENTS:
		if _vorher:
			build._ghost_sig = ""
		var pos := Vector2(300.0 + i * 8.0, 360.0 + sin(i * 0.4) * 60.0)
		build._move_ghost_to_pointer(pos)
	var drag_ms := (Time.get_ticks_usec() - drag_t0) / 1000.0
	build._cancel_ghost()
	await _worst_frame_ms(5)
	draw_calls = maxi(
		draw_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	)
	build.close()
	print("== FIX3-PERF ZUSAMMENFASSUNG (%s) ==" % ("VORHER" if _vorher else "NACHHER"))
	print(
		(
			"open_call avg=%.2f max=%.2f | open_worst_frame avg=%.2f max=%.2f"
			% [_avg(open_ms), _max(open_ms), _avg(open_frame_ms), _max(open_frame_ms)]
		)
	)
	print(
		(
			"close_call avg=%.2f max=%.2f | close_worst_frame avg=%.2f max=%.2f"
			% [_avg(close_ms), _max(close_ms), _avg(close_frame_ms), _max(close_frame_ms)]
		)
	)
	print(
		(
			"ghost_drag: %d Events in %.2fms (%.3fms/Event)"
			% [DRAG_EVENTS, drag_ms, drag_ms / DRAG_EVENTS]
		)
	)
	print("draw_calls_baumodus(max, inkl. Kulisse)=%d" % draw_calls)
	room.queue_free()
	await process_frame
	await process_frame
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()
	quit(0)


func _worst_frame_ms(frames: int) -> float:
	var worst := 0.0
	for _i in frames:
		var t0 := Time.get_ticks_usec()
		await process_frame
		worst = maxf(worst, (Time.get_ticks_usec() - t0) / 1000.0)
	return worst


func _frame_stats(frames: int) -> Dictionary:
	var worst := 0.0
	var summe := 0.0
	for _i in frames:
		var t0 := Time.get_ticks_usec()
		await process_frame
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		worst = maxf(worst, ms)
		summe += ms
	return {"avg": summe / frames, "worst": worst}


func _avg(werte: Array[float]) -> float:
	if werte.is_empty():
		return 0.0
	var summe := 0.0
	for wert in werte:
		summe += wert
	return summe / werte.size()


func _max(werte: Array[float]) -> float:
	var out := 0.0
	for wert in werte:
		out = maxf(out, wert)
	return out
