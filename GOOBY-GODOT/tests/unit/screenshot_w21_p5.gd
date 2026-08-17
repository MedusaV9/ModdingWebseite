extends SceneTree
## W21/P5-Screenshot-Werkzeug (KEIN Test — kein test_-Präfix): rendert die
## Nachher-Deliverables des MG-HUD-Kits als Review-Artefakte — gvz-Gefecht
## (Skala×f statt Fix-Pixel: Zähler-Chip, Karten, Banner-Standard), teaParty
## (Kit-Chip + Hinweis im Typo-Minimum), ranchHerde (Kit-Chip überm 3D-Feld,
## Feier-Beat „Schaf im Pferch!") und memoryMatch im Feier-Beat-Moment
## („Paar gefunden!"). Braucht einen echten Renderer (xvfb):
## xvfb-run -a godot --path GOOBY-GODOT --rendering-method gl_compatibility \
##   --rendering-driver opengl3 --script res://tests/unit/screenshot_w21_p5.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/W21P5"
## Leitformat-Seitenverhältnis (iPhone quer, 2868×1320 → halbe Auflösung).
const LANDSCAPE := Vector2i(1434, 660)
const HOST_SCENE := "res://scripts/minigames/minigame_host.tscn"
const WAIT_LIMIT := 500

const HerdeLogic := preload("res://scripts/minigames/games/ranch_herde/herde_logic.gd")


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.theme = ThemeService.theme()
	_resize(LANDSCAPE)
	await _shot_gvz()
	await _shot_tea_party()
	await _shot_herde()
	await _shot_memory_beat()
	print("Screenshots fertig -> %s" % OUT_DIR)
	quit(0)


## gvz-Gefecht: Zähler-Chip, Kartenleiste und Banner-Standard auf Skala×f.
func _shot_gvz() -> void:
	var host := await _mount_host("gvz")
	var game := _game(host)
	await _until(func() -> bool: return bool(game.running))
	game.call("open_level", 1)
	# Früh fotografieren: das Intro-Banner (Banner-Standard) steht noch.
	for _i in 6:
		await process_frame
	await _snap("w21_p5_nachher_gvz.png")
	host.queue_free()
	await process_frame


## teaParty: Kit-Chip (Zeit + Serie) und Bodenhinweis im Typo-Minimum.
func _shot_tea_party() -> void:
	var host := await _mount_host("teaParty")
	var game := _game(host)
	await _until(func() -> bool: return bool(game.running))
	for _i in 45:
		await process_frame
	await _snap("w21_p5_nachher_teaparty.png")
	host.queue_free()
	await process_frame


## ranchHerde: Kit-Chip überm 3D-Feld; der Bot treibt, bis das erste Schaf
## im Pferch ist — der Feier-Beat „Schaf im Pferch!" steht mit im Bild.
func _shot_herde() -> void:
	var host := await _mount_host("ranchHerde")
	var game := _game(host)
	await _until(func() -> bool: return bool(game.running))
	game.call("_on_level_chosen", 2)
	await _until(func() -> bool: return bool(game.level_running))
	for _i in WAIT_LIMIT:
		await process_frame
		if not bool(game.level_running):
			break
		var schafe: Array = game.get("schafe")
		game.set("ziel", HerdeLogic.bot_ziel(schafe, game.get("level")))
		if HerdeLogic.drin_anzahl(schafe) >= 1:
			break
	await _snap("w21_p5_nachher_ranch_herde.png")
	host.queue_free()
	await process_frame


## memoryMatch im Feier-Beat-Moment: erstes Paar per Regie aufdecken —
## „Paar gefunden!" (Gold-Pille + Sparkle) poppt über dem Tisch.
func _shot_memory_beat() -> void:
	var host := await _mount_host("memoryMatch")
	var game := _game(host)
	await _until(func() -> bool: return bool(game.running))
	await _until(
		func() -> bool:
			return float(game.get("_intro_left")) <= 0.0 and float(game.get("reveal_left")) <= 0.0
	)
	# xvfb-Deltas sind riesig — Uhr fürs Foto zurückstellen, sonst zeigt
	# der Chip „1 s" statt einer frischen Runde.
	game.set("elapsed", 0.0)
	var cards: Array = game.get("cards")
	var paar := _erstes_paar(cards)
	(cards[paar.x] as Dictionary)["state"] = "up"
	(cards[paar.y] as Dictionary)["state"] = "up"
	var picked: Array = game.get("picked")
	picked.append(paar.x)
	picked.append(paar.y)
	game.call("_resolve_pick")
	for _i in 6:
		await process_frame
	await _snap("w21_p5_nachher_feier_beat_memory.png")
	host.queue_free()
	await process_frame


func _erstes_paar(cards: Array) -> Vector2i:
	for i in cards.size():
		for j in range(i + 1, cards.size()):
			var a: Dictionary = cards[i]
			var b: Dictionary = cards[j]
			if int(a["face"]) == int(b["face"]):
				return Vector2i(i, j)
	return Vector2i(0, 1)


## --------------------------------------------------------------- Technik


func _mount_host(game_id: String) -> Node:
	_refill_energy()
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
	for _i in 24:
		await process_frame
	return host


func _game(host: Node) -> MinigameBase:
	var found := host.find_children("*", "MinigameBase", true, false)
	return null if found.is_empty() else found[0] as MinigameBase


func _refill_energy() -> void:
	var gs := root.get_node_or_null(^"/root/GameState")
	if gs != null and gs.has_method("set_value"):
		gs.call("set_value", "gooby.stats.energy", 100.0)


func _until(cond: Callable) -> void:
	for _i in WAIT_LIMIT:
		if bool(cond.call()):
			return
		await process_frame
	push_warning("[W21P5] Wartebedingung nie erfüllt — fotografiere trotzdem")


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
