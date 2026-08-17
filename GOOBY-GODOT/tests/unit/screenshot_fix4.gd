extends SceneTree
## FIX4-Beleg-Treiber (KEIN Test — kein test_-Präfix): bootet das echte Spiel
## im Querformat, spielt drei Cutscenes in ihren echten Räumen an und öffnet
## das Rückblick-Kino — und schießt dabei Screenshots. Braucht einen echten
## Renderer (xvfb):
##   FIX4_OUT=/tmp/gooby-godot/artifacts/FIX4 xvfb-run -a godot \
##     --path GOOBY-GODOT --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --script res://tests/unit/screenshot_fix4.gd

const OUT_ENV := "FIX4_OUT"
const DEFAULT_OUT := "/tmp/gooby-godot/artifacts/FIX4"
const WIN := Vector2i(1792, 828)
const SETTLE_FRAMES := 24
const TRAVEL_TIMEOUT_MS := 15_000

## Cutscene-Id → [Raum-Route, Sekunden bis zum Screenshot-Moment].
const SHOTS := [
	["wake_morning", "home/bedroom", 3.2],
	["travel_departure", "home/garden", 4.0],
	["shop_trip", "home/living", 3.4],
]

var _out_dir := DEFAULT_OUT
var _router: Node


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var env := OS.get_environment(OUT_ENV)
	if env != "":
		_out_dir = env
	DirAccess.make_dir_recursive_absolute(_out_dir)
	DisplayServer.window_set_size(WIN)
	root.size = WIN
	var gs := root.get_node("/root/GameState")
	gs.set_value("onboarding.done", true)
	_router = root.get_node("/root/SceneRouter")
	var entry := (load("res://scenes/home/home_entry.tscn") as PackedScene).instantiate()
	root.add_child(entry)
	await _wait_travel_done()

	for shot: Array in SHOTS:
		await _capture_cutscene(String(shot[0]), StringName(shot[1]), float(shot[2]))

	await _capture_recap(gs)
	print("FIX4-Screenshots fertig -> %s" % _out_dir)
	quit(0)


func _capture_cutscene(id: String, route: StringName, at_sec: float) -> void:
	_router.goto(route)
	await _wait_travel_done()
	var room: Node = _router.get_current_scene()
	var player: CutscenePlayer = CutscenePlayer.play_in_room(room, null, id)
	if player == null:
		print("FIX4: Cutscene %s startete nicht." % id)
		return
	var done := {"done": false}
	player.finished.connect(func(_s: bool) -> void: done["done"] = true)
	player.spielen()
	await _wait_seconds(at_sec)
	await _snap("cutscene_%s.png" % id)
	# Rest im Schnelldurchlauf zu Ende laufen lassen (Skip-Pfad = echter Pfad).
	player.time_scale = 40.0
	player.ueberspringen()
	var deadline := Time.get_ticks_msec() + TRAVEL_TIMEOUT_MS
	while not done["done"] and Time.get_ticks_msec() < deadline:
		await process_frame
	await _settle()


func _capture_recap(gs: Node) -> void:
	# Hübsche Statzeilen für den Beleg: ein paar Zähler in den State legen.
	gs.set_value("achievements.counters.feeds", 12)
	gs.set_value("achievements.counters.tickles", 23)
	gs.set_value("achievements.counters.trips", 4)
	gs.set_value("achievements.counters.harvests", 7)
	gs.set_value("achievements.counters.sleeps", 6)
	gs.set_value("economy.coinsEarned", 340)
	gs.set_value("minigames.plays", {"teaParty": 5, "carrotCatch": 3})
	var layer := CanvasLayer.new()
	layer.layer = 95
	root.add_child(layer)
	var scene: Control = RecapScene.build(gs, 10)
	scene.replay = true  # Beleg-Lauf: nichts in den Save schreiben.
	layer.add_child(scene)
	# Intro → erste Station mit Statzeile.
	await _wait_seconds(6.5)
	await _snap("recap_station_querformat.png")
	await _wait_seconds(9.0)
	await _snap("recap_station2_querformat.png")
	# Zur Endkarte springen (Skip ist ab 10 s scharf) und dort einfrieren.
	scene.time_scale = 20.0
	var done := {"done": false}
	scene.finished.connect(func(_s: bool) -> void: done["done"] = true)
	var deadline := Time.get_ticks_msec() + TRAVEL_TIMEOUT_MS
	while not bool(scene.get("_ending")) and Time.get_ticks_msec() < deadline:
		scene.skip()
		await process_frame
	scene.time_scale = 0.001
	await _settle()
	await _snap("recap_endkarte_querformat.png")
	scene.time_scale = 30.0
	while not done["done"] and Time.get_ticks_msec() < deadline:
		await process_frame
	layer.queue_free()
	await _settle()


func _wait_travel_done() -> void:
	var deadline := Time.get_ticks_msec() + TRAVEL_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if _router != null and not _router.is_busy() and _router.get_current_scene() != null:
			break
	await _settle()


func _wait_seconds(seconds: float) -> void:
	await create_timer(seconds).timeout


func _settle() -> void:
	for i in SETTLE_FRAMES:
		await process_frame


func _snap(file: String) -> void:
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [_out_dir, file])
	print("  gespeichert: %s (%dx%d)" % [file, image.get_width(), image.get_height()])
