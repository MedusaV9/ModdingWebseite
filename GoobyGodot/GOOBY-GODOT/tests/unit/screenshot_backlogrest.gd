extends SceneTree
## BACKLOG-REST-Screenshot-Tool (KEIN Test — kein test_-Präfix): rendert die
## Deliverables als Review-Artefakte: drei neue Zufalls-Ereignisse in Aktion
## (Robo-Jagd, Mehl-Unfall, Gewitter-Angst), Schach (laufende Partie + Matt-
## Overlay) und das Album mit den neuen Sets (gesperrt = Fragezeichen-Karte
## vs. frei, NEU-Marker, Set-komplett-Belohnung). Braucht einen echten
## Renderer (xvfb):
## xvfb-run -a godot --path . --rendering-method gl_compatibility \
##   --rendering-driver opengl3 --script res://tests/unit/screenshot_backlogrest.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/BACKLOGREST"
const SETTLE_FRAMES := 24
const CAMERA_FRAMES := 150

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

var _seq := 0


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.theme = ThemeService.theme()
	_resize(Vector2i(1280, 720))
	await _shot_event("robo_jagd", "living", "event_robo_jagd.png", 45, Vector2(0.45, 0.5))
	await _shot_event("mehl_unfall", "kitchen", "event_mehl_unfall.png", 40, Vector2(0.35, 0.58))
	await _shot_event(
		"gewitter_angst", "living", "event_gewitter_angst.png", 50, Vector2(0.7, 0.62)
	)
	await _shot_chess_running()
	await _shot_chess_mate()
	await _shot_album_sets()
	print("Screenshots fertig → %s" % OUT_DIR)
	quit(0)


func _resize(win_size: Vector2i) -> void:
	DisplayServer.window_set_size(win_size)
	root.size = win_size


# ── Ereignisse im Raum ───────────────────────────────────────────────────────


func _shot_event(
	event_id: String, room_id: String, file: String, extra_frames: int, pose := Vector2(0.5, 0.66)
) -> void:
	var ctx := await _make_room(room_id, pose)
	var runner := EventRunner.attach_to(ctx["room"], _event_defs())
	var def := RandomEventEngine.def_by_id(_event_defs(), event_id)
	runner.start(def)
	if event_id == "robo_jagd":
		_freeze_robo(runner)
	for _i in extra_frames:
		await process_frame
	await _snap(file)
	await _teardown(ctx)


## Nur fürs Foto: Kreisfahrt anhalten und den Sauger gut sichtbar vor den
## Fluchttisch stellen (im Spiel fährt er natürlich weiter Runden).
func _freeze_robo(runner: EventRunner) -> void:
	if runner._robo_tween != null:
		runner._robo_tween.kill()
		runner._robo_tween = null
	if runner._robo != null:
		runner._robo.position = runner._gooby_pos() + Vector3(-1.3, 0.07, 0.35)


func _event_defs() -> Array:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/events/data/events.json")
	)
	return parsed.get("items", []) if parsed is Dictionary else []


# ── Schach: laufende Partie + Matt ───────────────────────────────────────────


func _shot_chess_running() -> void:
	var scene := await _open_chess()
	# Kurze echte Eröffnung gegen den Bot (Stufe 1): 1. e4 …, 2. Sf3 …
	scene._on_square_pressed(0x14)
	scene._on_square_pressed(0x34)
	await _wait_white(scene)
	scene._on_square_pressed(0x06)
	scene._on_square_pressed(0x25)
	await _wait_white(scene)
	# Läufer f1 anwählen → Ziel-Highlights sichtbar im Screenshot.
	scene._on_square_pressed(0x05)
	await _snap("schach_partie_laeuft.png")
	scene.queue_free()
	await process_frame


func _shot_chess_mate() -> void:
	var scene := await _open_chess()
	# Zwei-Türme-Matt in 1: Tb2–b8# → Sieg-Overlay + Konfetti.
	scene._solo_logic.from_fen("7k/R7/8/8/8/8/1R6/K7 w - - 0 1")
	scene._render()
	scene._on_square_pressed(0x11)
	scene._on_square_pressed(0x71)
	for _i in 30:
		await process_frame
	await _snap("schach_matt_overlay.png")
	scene.queue_free()
	await process_frame


func _open_chess() -> ChessScene:
	var scene := ChessScene.new()
	root.add_child(scene)
	await process_frame
	scene._ai_strength = 1
	scene._on_solo_start(ChessLogic.WHITE)
	await process_frame
	return scene


func _wait_white(scene: ChessScene) -> void:
	for _i in 240:
		if scene.game_logic().to_move == ChessLogic.WHITE and not scene._thinking:
			return
		await process_frame


# ── Album: neue Sets (gesperrt vs. frei, NEU-Marker, Set-Belohnung) ──────────


func _shot_album_sets() -> void:
	# `--script` mit `--path .` lädt die Projekt-Autoloads: das Album bindet
	# an /root/GameState — Autoload auf einen frischen Temp-Save umbiegen.
	var gs: Node = root.get_node("/root/GameState")
	RandomEventEngine.register_slice()
	GoobyBuffs.register_slice()
	BadState.register_slice()
	_seq += 1
	var dir := "user://backlogrest_shots/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	gs.initialize(dir + "/save_v5.json")
	gs.update(
		func(state: Dictionary) -> void:
			var now := int(Time.get_unix_time_from_system() * 1000.0)
			# Ranch-Seite: 2 frei (mit NEU-Marker) vs. 5 Fragezeichen-Karten.
			# Jahreszeiten: 5 von 6 vorab — jz_jahresring feuert dann LIVE
			# (seasonsCollected=4) → Unlock-Toast + Set-komplett-Belohnung.
			state["stickers"]["unlocked"] = {
				"sticker_erster_boot": now,
				"ranch_neuer_hof": now,
				"ranch_erstes_pferd": now,
				"jz_fruehling": now,
				"jz_sommer": now,
				"jz_herbst": now,
				"jz_winter": now,
				"jz_regenbogen": now,
			}
			state["stickers"]["seen"] = {"sticker_erster_boot": true}
	)
	var album: AlbumScreen = (
		(load("res://scripts/ui/album/album_screen.tscn") as PackedScene).instantiate()
	)
	album.auto_navigate = false
	root.add_child(album)
	await process_frame
	album.show_page("ranch")
	await _snap("album_ranch_frei_vs_gesperrt.png")
	album.show_page("stadtnacht")
	await _snap("album_stadtnacht_gesperrt.png")
	album.show_page("jahreszeiten")
	for _i in 20:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/album_set_komplett_belohnung.png" % OUT_DIR)
	print("  gespeichert: album_set_komplett_belohnung.png")
	album.queue_free()
	await process_frame


# ── Raum-Gerüst (W2a-Muster, wie screenshot_w3d.gd) ──────────────────────────


func _fresh_gs() -> Node:
	RandomEventEngine.register_slice()
	GoobyBuffs.register_slice()
	BadState.register_slice()
	_seq += 1
	var dir := "user://backlogrest_shots/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	return gs


func _make_room(room_id: String, pose := Vector2(0.5, 0.66)) -> Dictionary:
	HomeState.register_slice()
	var gs := _fresh_gs()
	var scene: PackedScene = load(str(RoomDefs.room(room_id)["scene"]))
	var room: RoomBase = scene.instantiate()
	room.game_state_override = gs
	root.add_child(room)
	await process_frame
	_pose_gooby(room, pose)
	for _i in CAMERA_FRAMES:
		await process_frame
	return {"room": room, "gs": gs}


func _pose_gooby(room: RoomBase, pose := Vector2(0.5, 0.66)) -> void:
	var gooby := room.gooby()
	gooby.set_wander_enabled(false)
	var free := room.grid.free_cells()
	if free.is_empty():
		return
	var target := Vector2i(int(room.grid.size.x * pose.x), int(room.grid.size.y * pose.y))
	free.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			return (a - target).length_squared() < (b - target).length_squared()
	)
	gooby.global_position = GridData.world_center(free[0], Vector2i.ONE, 0)


func _teardown(ctx: Dictionary) -> void:
	# Offene Sheets werden hier mit-gefreet, ohne close() → Stack aufräumen,
	# sonst stolpert PanelStack._prune über die toten Referenzen.
	PanelStack.clear()
	(ctx["room"] as Node).queue_free()
	await process_frame
	await process_frame
	(ctx["gs"] as Node).free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()


func _snap(file: String) -> void:
	for _i in SETTLE_FRAMES:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("  gespeichert: %s (%dx%d)" % [file, image.get_width(), image.get_height()])
