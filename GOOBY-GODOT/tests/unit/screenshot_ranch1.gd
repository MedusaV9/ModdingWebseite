extends SceneTree
## RANCH-1-Screenshot-Tool (KEIN Test — kein test_-Präfix): rendert die
## Gooby-Ranch-Deliverables als Review-Artefakte (Stadtausfahrt mit Schild,
## Landstraße unterwegs, Ankunft am Ranch-Tor, Ranch-Übersicht, Pferd nah,
## Kauf-Angebot-Dialog) und misst die Draw-Calls der Ranch-Ansicht
## (Budget ≤ 400). Braucht einen echten Renderer (xvfb):
## xvfb-run -a godot --path . --rendering-method gl_compatibility \
##   --rendering-driver opengl3 --script res://tests/unit/screenshot_ranch1.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/RANCH1"
const SETTLE_FRAMES := 24
const DRAWCALL_BUDGET := 400

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

var _seq := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.theme = ThemeService.theme()
	DisplayServer.window_set_size(Vector2i(1280, 720))
	root.size = Vector2i(1280, 720)
	await _shot_stadtausfahrt_und_angebot()
	await _shot_fahrt()
	await _shot_hof_und_pferd()
	print("Screenshots fertig → %s" % OUT_DIR)
	quit(0)


func _make_gs(level := 20, coins := 9999) -> Node:
	_seq += 1
	var dir := "user://ranch_shots/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	CityState.register_slice()
	RanchState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	gs.set_value("progression.level", level)
	gs.set_value("economy.coins", coins)
	return gs


func _teardown(node: Node, gs: Node) -> void:
	PanelStack.clear()
	node.queue_free()
	await process_frame
	await process_frame
	gs.free()
	SaveSchema.unregister_slice(CityState.SLICE_ID)
	SaveSchema.unregister_slice(RanchState.SLICE_ID)
	CityState.reset_for_tests()
	RanchState.reset_for_tests()


## Stadtausfahrt: Stadt + RanchExit (Schild „Zur Gooby Ranch — 8 km“),
## Auto in der Zone (Prompt offen); danach das Kauf-Angebot-Sheet darüber.
func _shot_stadtausfahrt_und_angebot() -> void:
	var gs := _make_gs()
	var city: Node3D = load("res://scenes/city/city_scene.tscn").instantiate()
	city.set("game_state_override", gs)
	city.set("stunde_override", 13.0)
	root.add_child(city)
	for _i in 40:
		await process_frame
	var exit: RanchExit = RanchExit.install(city)
	exit.game_state_override = gs
	await process_frame
	var ziel := exit.ausfahrt_pos()
	# Westlich starten und aufs Schild zurollen: „Zur Gooby Ranch — 8 km“
	# steht dann lesbar VOR dem Auto (Chase-Cam blickt nach Osten).
	city.auto.teleport(ziel.x - 24.0, ziel.z + CityCarFeel.LANE_OFFSET_M, PI / 2.0)
	city.cam.snap()
	for _i in 30:
		await physics_frame
	city.auto.set_frozen(true)
	await _snap("stadtausfahrt_schild.png")
	# Direkt danach: das Angebot nach dem Rückblick (User-Wunsch-Dialog).
	var sheet := RanchOffer.zeige(root, gs)
	for _i in 30:
		await process_frame
	await _snap("kauf_angebot_dialog.png")
	if sheet != null:
		sheet.queue_free()
	await _teardown(city, gs)


## Landstraße: unterwegs zwischen Feldern + Ankunft am Ranch-Tor (Prompt).
func _shot_fahrt() -> void:
	var gs := _make_gs()
	var szene: RanchFahrtScene = load("res://scenes/ranch/ranch_fahrt.tscn").instantiate()
	szene.game_state_override = gs
	szene.stunde_override = 13.0
	root.add_child(szene)
	for _i in 50:
		await process_frame
	# Mittelteil der Strecke: Felder, Zäune, Windrad in Sicht.
	szene.auto.teleport(-CityCarFeel.LANE_OFFSET_M, -float(szene.plan["laenge"]) * 0.22, 0.0)
	szene.cam.snap()
	for _i in 70:
		await physics_frame
	await _snap("landstrasse_unterwegs.png")
	var fahrt_calls := await _mess_draw_calls(30)
	print("draw_calls_fahrt(max)=%d (Budget %d)" % [fahrt_calls, DRAWCALL_BUDGET])
	# Ankunft: kurz vors Tor rollen, bis der Kauf-Prompt aufgeht (das Auto
	# rampt sein Tempo selbst hoch — genug Frames zum Einrollen geben).
	szene.auto.teleport(-CityCarFeel.LANE_OFFSET_M, float(szene.plan["tor_z"]) - 26.0, 0.0)
	szene.cam.snap()
	for _i in 240:
		await physics_frame
		if szene.hud.prompt_sichtbar():
			break
	szene.auto.set_frozen(true)
	for _i in 10:
		await physics_frame
	await _snap("ankunft_ranch_tor.png")
	await _teardown(szene, gs)


## Riesenfeld: Übersicht (Draw-Call-Messung) + Pferd-Nahaufnahme.
func _shot_hof_und_pferd() -> void:
	var gs := _make_gs()
	var szene: RanchHofScene = load("res://scenes/ranch/ranch_hof.tscn").instantiate()
	szene.game_state_override = gs
	szene.stunde_override = 13.0
	root.add_child(szene)
	for _i in 80:
		await process_frame
	await _snap("ranch_uebersicht.png")
	var hof_calls := await _mess_draw_calls(40)
	var status := "OK" if hof_calls <= DRAWCALL_BUDGET else "ÜBER BUDGET"
	print("draw_calls_ranch(max)=%d (Budget %d) → %s" % [hof_calls, DRAWCALL_BUDGET, status])
	# Nahaufnahme: Kamera-Drift aus, ran ans erste (stehende) Pferd.
	var kamera := szene.cam
	szene.cam = null
	var pferd: RanchPferd = szene.pferde[0]
	pferd._blinzel_zeit = 0.0
	kamera.position = pferd.position + Vector3(1.7, 1.6, -2.9)
	kamera.look_at(pferd.position + Vector3(0.0, 1.25, 0.2), Vector3.UP)
	kamera.fov = 45.0
	for _i in 12:
		await process_frame
	await _snap("pferd_nah.png")
	await _teardown(szene, gs)


## Draw-Calls über mehrere Frames maximieren (Performance-Monitor).
func _mess_draw_calls(frames: int) -> int:
	var maximum := 0
	for _i in frames:
		await process_frame
		maximum = maxi(
			maximum, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		)
	return maximum


func _snap(file: String) -> void:
	for _i in SETTLE_FRAMES:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("  gespeichert: %s (%dx%d)" % [file, image.get_width(), image.get_height()])
