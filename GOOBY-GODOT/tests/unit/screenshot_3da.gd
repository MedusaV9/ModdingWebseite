extends SceneTree
## 3D-A-Screenshot-Werkzeug (KEIN Test): montiert den MinigameHost für die fünf
## zurückgebauten 3D-Spiele, spielt sie mit simulierten Berührungen bis in eine
## aussagekräftige Spielsituation und legt PNGs ab. Zusätzlich wird der
## Draw-Call-Zähler des Frames protokolliert (Perf-Budget ≤ 250).
##
##   xvfb-run -a godot --path GOOBY-GODOT --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --script res://tests/unit/screenshot_3da.gd
##
## Optional: `-- <id>[:quer|:hoch] …` — ohne Argumente alle fünf in ihrer
## Standard-Orientierung PLUS je einer im anderen Format.
##
## Die Regie ist ZUSTANDSgetrieben, nicht bildzählend: unter xvfb braucht ein
## Bild gern 0,2 s, ein festes „warte 80 Frames" wäre also mal eine halbe und
## mal zehn Spielsekunden. Stattdessen wartet der Treiber auf das, worauf es
## ankommt (Ball fliegt, Schuss ist unterwegs, Fisch beißt) und fotografiert
## genau dann.

const OUT_DIR := "/tmp/gooby-godot/artifacts/3DA"
const HOST_SCENE := "res://scripts/minigames/minigame_host.tscn"
const PORTRAIT := Vector2i(760, 1200)
const LANDSCAPE := Vector2i(1200, 760)
const IDS: Array[String] = ["miniGolf", "basketBounce", "goalieGooby", "fishingPond", "ghostHunt"]
## Notbremse für jede Wartebedingung (Bilder, nicht Sekunden).
const WAIT_LIMIT := 300

var _report: Array[String] = []


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.theme = ThemeService.theme()
	var ids: Array = []
	for arg in OS.get_cmdline_user_args():
		ids.append(str(arg))
	if ids.is_empty():
		for id in IDS:
			ids.append(id)
			var meta := MinigameRegistry.get_game(id)
			var flip := (
				"hoch" if str(meta.get("orientation", "portrait")) == "landscape" else "quer"
			)
			ids.append("%s:%s" % [id, flip])
	for spec: String in ids:
		await _shoot(spec)
	print("\n== Draw-Calls ==")
	for line in _report:
		print("  ", line)
	print("Screenshots fertig → %s" % OUT_DIR)
	quit(0)


func _shoot(spec: String) -> void:
	var parts := spec.split(":")
	var game_id := parts[0]
	var meta := MinigameRegistry.get_game(game_id)
	if meta.is_empty():
		print("  ÜBERSPRUNGEN (nicht in der Registry): %s" % game_id)
		return
	_refill_energy()
	var landscape := str(meta.get("orientation", "portrait")) == "landscape"
	var suffix := ""
	if parts.size() > 1:
		landscape = parts[1] == "quer"
		suffix = "_%s" % parts[1]
	_resize(LANDSCAPE if landscape else PORTRAIT)
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
				"orientation": "landscape" if landscape else "portrait",
			}
		)
	)
	root.add_child(host)
	for _i in 24:
		await process_frame
	match game_id:
		"miniGolf":
			await _play_golf(host)
		"basketBounce":
			await _play_basket(host)
		"goalieGooby":
			await _play_goalie(host)
		"fishingPond":
			await _play_fishing(host)
		"ghostHunt":
			await _play_ghost(host)
		_:
			for _i in 60:
				await process_frame
	var calls := RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
	)
	_report.append("%s%s: %d Draw-Calls" % [game_id, suffix, calls])
	await _snap("%s%s.png" % [game_id, suffix])
	host.queue_free()
	await process_frame


# ------------------------------------------------------------------ Regie


## Minigolf ist zugbasiert: ziehen, kurz vor dem Loslassen fotografieren —
## dann sind Zielhilfe, Ball und ausholender Gooby gleichzeitig im Bild.
func _play_golf(host: MinigameHost) -> void:
	_touch(host, Vector2(0.5, 0.62), true)
	for step in 6:
		await process_frame
		_touch(host, Vector2(0.5, 0.62 + 0.035 * (step + 1)), null)
	for _i in 4:
		await process_frame


## Korbjagd: flicken und warten, bis der Ball wirklich fliegt und ungefähr
## seinen Scheitel erreicht hat.
func _play_basket(host: MinigameHost) -> void:
	var game := _game(host)
	_touch(host, Vector2(0.5, 0.86), true)
	for step in 5:
		await process_frame
		_touch(host, Vector2(0.5, 0.86 - 0.075 * (step + 1)), null)
	_touch(host, Vector2(0.5, 0.48), false)
	await _until(func() -> bool: return str(game.phase) == "fly")
	for _i in 2:
		await process_frame


## Torwart: auf einen Schuss warten, ihn ANFLIEGEN lassen und erst dann in seine
## Bahn hechten — `dive_covers()` rechnet eine Parade nur an, wenn die Hechte
## höchstens DIVE_HOLD_SEC vor der Linie kommt. Zu früh gehechtet = Gegentor,
## und nach drei Gegentoren ist die Runde vorbei, bevor das Foto steht.
func _play_goalie(host: MinigameHost) -> void:
	var game := _game(host)
	for _try in 6:
		await _until(func() -> bool: return not (game.kick as Dictionary).is_empty())
		var shot: Dictionary = game.kick
		if shot.is_empty():
			return
		var lane := int(shot["lane"])
		var kind := str(shot["kind"])
		await _until(
			func() -> bool:
				return (game.kick as Dictionary).is_empty() or float(game.kick_progress()) >= 0.2
		)
		if (game.kick as Dictionary).is_empty():
			continue
		# Der Wisch wird über den WINKEL ausgewertet (`lane_from_swipe` rechnet
		# atan2(dx, |dy|)) — ein rein waagerechter Wisch landet deshalb IMMER in
		# der Außenbahn. Also erst die Höhe setzen, dann dx daraus ableiten.
		var size := Vector2(_sub_viewport(host).size)
		var dy := 16.0
		if kind == "lob":
			dy = -60.0
		elif kind == "roller":
			dy = 60.0
		var lane_deg: Array[float] = [-70.0, -36.0, 0.0, 36.0, 70.0]
		var delta := Vector2(tan(deg_to_rad(lane_deg[lane])) * absf(dy), dy)
		var from := Vector2(0.5, 0.6) * size
		_touch_px(host, from, true)
		await process_frame
		_touch_px(host, from + delta, false)
		await process_frame
		return


## Angelteich: halten bis der Haken auf Fischtiefe ist, loslassen und warten,
## bis wirklich etwas an der Schnur hängt — dann erst auslösen.
func _play_fishing(host: MinigameHost) -> void:
	var game := _game(host)
	for _try in 8:
		_touch(host, Vector2(0.5, 0.55), true)
		await _until(func() -> bool: return _fish_at_hook(game) or float(game.hook_depth) >= 3.6)
		_touch(host, Vector2(0.5, 0.55), false)
		await process_frame
		if bool(game.has_catch()):
			break
		await _until(func() -> bool: return str(game.phase) == "idle")
	for _i in 3:
		await process_frame


## Steht gerade ein Schwimmer im Fangradius des Hakens? (Angel-Regie.)
func _fish_at_hook(game: MinigameBase) -> bool:
	for f: Dictionary in game.fish as Array:
		var dx := float(f["x"])
		var dd := float(f["depth"]) - float(game.hook_depth)
		if sqrt(dx * dx + dd * dd) <= 0.4:
			return true
	return false


## Geisterjagd: warten, bis ein Geist sichtbar ist, ihn fangen und im
## Fang-Moment fotografieren.
func _play_ghost(host: MinigameHost) -> void:
	var game := _game(host)
	await _until(func() -> bool: return game.has_visible_ghost())
	var aim: Vector2 = game.first_ghost_screen()
	var size := Vector2(_sub_viewport(host).size)
	_touch(host, aim / size, true)
	await process_frame
	_touch(host, aim / size, false)
	for _i in 6:
		await process_frame


# ----------------------------------------------------------------- Technik


func _game(host: MinigameHost) -> MinigameBase:
	var found := host.find_children("*", "MinigameBase", true, false)
	return null if found.is_empty() else found[0] as MinigameBase


## Auf eine Spielbedingung warten (mit Notbremse, damit ein hängendes Spiel
## den Lauf nicht blockiert).
func _until(cond: Callable) -> void:
	for _i in WAIT_LIMIT:
		if bool(cond.call()):
			return
		await process_frame
	push_warning("[3DA] Wartebedingung nie erfüllt — fotografiere trotzdem")


## Jede Runde kostet Energie — nach ein paar Fotos verweigert der Host sonst.
func _refill_energy() -> void:
	var gs := root.get_node_or_null(^"/root/GameState")
	if gs != null and gs.has_method("set_value"):
		gs.call("set_value", "gooby.stats.energy", 100.0)


## `pressed` null = Ziehen, true = Auflegen, false = Abheben.
func _touch(host: MinigameHost, rel: Vector2, pressed: Variant) -> void:
	var viewport := _sub_viewport(host)
	if viewport == null:
		return
	_touch_px(host, Vector2(viewport.size) * rel, pressed)


## Wie `_touch()`, aber in Bildpunkten — nötig, wo die Logik Wischstrecken in
## Pixeln auswertet.
func _touch_px(host: MinigameHost, pos: Vector2, pressed: Variant) -> void:
	var viewport := _sub_viewport(host)
	if viewport == null:
		return
	var event: InputEvent
	if pressed == null:
		var drag := InputEventScreenDrag.new()
		drag.position = pos
		event = drag
	else:
		var touch := InputEventScreenTouch.new()
		touch.position = pos
		touch.pressed = bool(pressed)
		event = touch
	viewport.push_input(event, true)


func _sub_viewport(host: MinigameHost) -> SubViewport:
	var found := host.find_children("*", "SubViewport", true, false)
	return null if found.is_empty() else found[0] as SubViewport


func _resize(size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	root.size = size
	root.set_content_scale_size(size)


func _snap(file_name: String) -> void:
	for _i in 2:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file_name])
	print("  %s (%dx%d)" % [file_name, image.get_width(), image.get_height()])
