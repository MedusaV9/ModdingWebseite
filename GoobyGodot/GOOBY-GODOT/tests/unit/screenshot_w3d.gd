extends SceneTree
## W3d-Screenshot-Tool (KEIN Test — kein test_-Präfix): rendert die
## CONTENT-Deliverables als Review-Artefakte: Album (Garten-Seite,
## unlocked+locked-Mix + Unlock-Toast/Konfetti), Nutella-Nacht,
## Marienkäfer-Event, Lampen-Schalter-Sheet und das Geschichten-Buch.
## Braucht einen echten Renderer (xvfb):
## xvfb-run -a godot --path . --rendering-method gl_compatibility \
##   --rendering-driver opengl3 --script res://tests/unit/screenshot_w3d.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/W3d"
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
	await _shot_album()
	await _shot_event("nutella_nacht", "kitchen", "nutella_nacht_choice.png", 40)
	# Marienkäfer: Gooby rechts der Raummitte auf freiem Boden posen, sonst
	# verdeckt ihn die Sprechblase am unteren Rand bzw. der Sessel.
	await _shot_event("hingefallen", "living", "marienkaefer_event.png", 30, Vector2(0.8, 0.62))
	await _shot_lampen_schalter()
	await _shot_story_buch()
	print("Screenshots fertig → %s" % OUT_DIR)
	quit(0)


func _resize(win_size: Vector2i) -> void:
	DisplayServer.window_set_size(win_size)
	root.size = win_size


func _fresh_gs() -> Node:
	RandomEventEngine.register_slice()
	GoobyBuffs.register_slice()
	BadState.register_slice()
	_seq += 1
	var dir := "user://w3d_shots/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	return gs


# ── Album: Garten-Seite (Mix) + Live-Unlock mit Toast/Konfetti ───────────────


func _shot_album() -> void:
	# `--script` mit `--path .` lädt die Projekt-Autoloads: das Album bindet
	# IMMER an /root/GameState — also das Autoload auf einen frischen
	# Temp-Save umbiegen statt einen zweiten Store zu injizieren.
	var gs: Node = root.get_node("/root/GameState")
	RandomEventEngine.register_slice()
	GoobyBuffs.register_slice()
	BadState.register_slice()
	_seq += 1
	var dir := "user://w3d_shots/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	gs.initialize(dir + "/save_v5.json")
	# Vorab-Unlocks: Mix aus offen/gesperrt auf der Garten-Seite; erster_boot
	# gleich mit, damit beim Öffnen kein Alt-Toast über dem Screen hängt.
	gs.update(
		func(state: Dictionary) -> void:
			var now := int(Time.get_unix_time_from_system() * 1000.0)
			state["stickers"]["unlocked"] = {
				"garten_giesser": now,
				"garten_pause": now,
				"garten_riesenkuerbis": now,
				"sticker_erster_boot": now,
				"firstNom": now,
				"cleanMachine": now,
				# seedStarter teilt den plantings-Counter — vorab öffnen,
				# damit der Live-Unlock-Toast den Garten-Sticker zeigt.
				"seedStarter": now,
			}
	)
	var album: AlbumScreen = (
		(load("res://scripts/ui/album/album_screen.tscn") as PackedScene).instantiate()
	)
	album.auto_navigate = false
	root.add_child(album)
	await process_frame
	album.show_page("garten")
	await _snap("album_garten_seite.png")
	# Live-Unlock: plantings-Counter erfüllt „Gewächshaus-Gärtner“ →
	# Karte deckt auf + Toast + Konfetti.
	gs.update(func(state: Dictionary) -> void: state["achievements"]["counters"]["plantings"] = 25)
	gs.notify_slice_changed("achievements")
	for _i in 10:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/album_unlock_toast_konfetti.png" % OUT_DIR)
	print("  gespeichert: album_unlock_toast_konfetti.png")
	album.queue_free()
	await process_frame


# ── Events im Raum (Nutella-Nacht / Marienkäfer) ─────────────────────────────


func _shot_event(
	event_id: String, room_id: String, file: String, extra_frames: int, pose := Vector2(0.5, 0.66)
) -> void:
	var ctx := await _make_room(room_id, pose)
	var runner := EventRunner.attach_to(ctx["room"], _event_defs())
	var def := RandomEventEngine.def_by_id(_event_defs(), event_id)
	runner.start(def)
	for _i in extra_frames:
		await process_frame
	await _snap(file)
	await _teardown(ctx)


func _event_defs() -> Array:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/events/data/events.json")
	)
	return parsed.get("items", []) if parsed is Dictionary else []


# ── Lampen-Schalter-Sheet ────────────────────────────────────────────────────


func _shot_lampen_schalter() -> void:
	var ctx := await _make_room("living")
	var host := InteractablesHost.attach_to(ctx["room"])
	await process_frame
	var lamp: LampenSchalter = null
	for child in host.get_children():
		if child is LampenSchalter:
			lamp = child
			break
	if lamp == null:
		print("  WARNUNG: keine Lampe im Wohnzimmer gefunden!")
	else:
		lamp._open_sheet()
		for _i in 40:
			await process_frame
	await _snap("lampen_schalter_sheet.png")
	await _teardown(ctx)


# ── Geschichten-Buch ─────────────────────────────────────────────────────────


func _shot_story_buch() -> void:
	var story_node := StoryTime.new()
	root.add_child(story_node)
	var stories := StoryTime.stories_from_registry()
	var story: Dictionary = stories[0] if not stories.is_empty() else {}
	story_node.open_book(story)
	for _i in 40:
		await process_frame
	# Ein Wort einsetzen (erste Lücke gefüllt, Chip deaktiviert = Spielstand).
	var chip := root.find_child("Wort_giesskanne", true, false)
	if chip is Button:
		story_node._on_word_tapped("giesskanne", chip)
	for _i in 10:
		await process_frame
	await _snap("geschichten_buch_ui.png")
	PanelStack.clear()
	story_node.queue_free()
	await process_frame


# ── Raum-Gerüst (W2a-Muster) ─────────────────────────────────────────────────


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


## Gooby auf einen freien, gut sichtbaren Platz stellen (`pose` = Zielzelle
## als Anteil der Grid-Größe; Default = untere Raummitte).
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
