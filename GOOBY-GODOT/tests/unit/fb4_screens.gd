extends SceneTree
## FB4-Screenshot-Werkzeug (KEIN Test): montiert die Spiel-Szenen DIREKT
## (ohne MinigameHost — der ist parallel im Umbau), spielt ein paar Sekunden
## hinein und legt PNGs ab. Braucht einen echten Renderer (xvfb):
##   xvfb-run -a godot --path GOOBY-GODOT --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --fixed-fps 60 \
##     --script res://tests/unit/fb4_screens.gd -- [before|after] [ids...]
## `--fixed-fps 60` ist PFLICHT: der Software-Renderer schafft nur ~7 fps.

const OUT_BASE := "/tmp/gooby-godot/artifacts/FB4"
const PORTRAIT := Vector2i(720, 1160)
const LANDSCAPE := Vector2i(1160, 720)

## id → {sec: Spielzeit vor dem Foto, taps: [[frame, rel_x, rel_y, gedrückt]]}
const PLANS := {
	"bubblePop": {"sec": 5.0, "taps": [[120, 0.5, 0.5, true], [122, 0.5, 0.5, false]]},
	"bunnyHop": {"sec": 5.0, "taps": [[100, 0.5, 0.6, true], [102, 0.5, 0.6, false]]},
	"carrotCatch": {"sec": 5.0, "taps": []},
	"carrotGuard": {"sec": 6.0, "taps": [[140, 0.5, 0.45, true], [142, 0.5, 0.45, false]]},
	"danceParty": {"sec": 9.0, "taps": []},
	"gardenRush": {"sec": 5.0, "taps": [[60, 0.3, 0.55, true], [62, 0.3, 0.55, false]]},
	"gobnom": {"sec": 4.0, "taps": []},
	"goobySays": {"sec": 6.0, "taps": []},
	"gvz": {"sec": 7.0, "taps": []},
	"lanternFloat": {"sec": 5.0, "taps": [[80, 0.5, 0.75, true], [82, 0.5, 0.75, false]]},
	"memoryMatch": {"sec": 4.0, "taps": [[60, 0.3, 0.35, true], [62, 0.3, 0.35, false]]},
	"pancakeTower": {"sec": 5.0, "taps": [[90, 0.5, 0.6, true], [92, 0.5, 0.6, false]]},
	"pipeFlow": {"sec": 4.0, "taps": [[60, 0.5, 0.4, true], [62, 0.5, 0.4, false]]},
	"snailMail": {"sec": 1.8, "taps": []},
	"teaParty": {"sec": 5.0, "taps": [[80, 0.5, 0.6, true], [110, 0.5, 0.6, false]]},
	"trampoline": {"sec": 5.0, "taps": [[80, 0.5, 0.6, true], [82, 0.5, 0.6, false]]},
	"toyRacer": {"sec": 7.0, "taps": []},
	"runner": {"sec": 9.0, "taps": []},
	"deliveryRush": {"sec": 6.0, "taps": []},
	# Kollisions-BELEG: Spieler-Kart rammt einen Bot — Foto im Rempel-Moment
	# (Funken + Abdrängung statt Durchfahren). 0,35 s reichen: der Kontakt
	# passiert im ersten Frame, die Trennung braucht ~8 Frames.
	"toyRacerBump": {"sec": 0.35, "taps": [], "game": "toyRacer"},
	# Boden-BELEG: zwei geparkte Autos dicht vor dem Spieler — die Räder
	# müssen sichtbar auf der Fahrbahn stehen (Bugfix „Manche Autos schweben").
	"runnerCars": {"sec": 2.0, "taps": [], "game": "runner"},
}

var _phase := "before"
var _landscape_run := false


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.theme = ThemeService.theme()
	var ids: Array = []
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		if text == "before" or text == "after":
			_phase = text
		elif text == "landscape":
			_landscape_run = true
		else:
			ids.append(text)
	if ids.is_empty():
		ids = PLANS.keys()
	DirAccess.make_dir_recursive_absolute("%s/%s" % [OUT_BASE, _phase])
	for id: String in ids:
		await _shoot_game(id)
	print("Screenshots fertig → %s/%s" % [OUT_BASE, _phase])
	quit(0)


func _shoot_game(game_id: String) -> void:
	var plan: Dictionary = PLANS.get(game_id, {"sec": 5.0, "taps": []})
	# Plan-Einträge dürfen unter eigenem Foto-Namen ein anderes Spiel montieren
	# (z. B. toyRacerBump → toyRacer für den Kollisions-Beleg).
	var mount_id := str(plan.get("game", game_id))
	var meta := MinigameRegistry.get_game(mount_id)
	if meta.is_empty():
		print("  ÜBERSPRUNGEN (nicht in der Registry): %s" % game_id)
		return
	var landscape := _landscape_run or str(meta.get("orientation", "portrait")) == "landscape"
	_resize(LANDSCAPE if landscape else PORTRAIT)
	var game := await _mount_game(mount_id, meta, landscape)
	_enter_level(game, game_id)
	var taps: Array = plan["taps"]
	for frame in int(float(plan["sec"]) * 60.0):
		if not bool(game.get("running")) and frame > 40:
			break
		for entry: Array in taps:
			if int(entry[0]) == frame:
				_touch(Vector2(float(entry[1]), float(entry[2])), entry[3])
		await process_frame
	var suffix := "_landscape" if _landscape_run else ""
	var draws := await _snap("%s/%s%s.png" % [_phase, game_id, suffix])
	print("  %s: Draw-Calls=%d" % [game_id, draws])
	game.queue_free()
	await process_frame


## Spiel DIREKT montieren: Szene + Stub-Kontext, Lifecycle wie der Host.
func _mount_game(game_id: String, meta: Dictionary, landscape: bool) -> Node:
	var game: Node = (load(str(meta["scene"])) as PackedScene).instantiate()
	var ctx := MinigameCtx.new()
	ctx.game_id = game_id
	ctx.difficulty = "normal"
	ctx.orientation = "landscape" if landscape else "portrait"
	ctx.run_seed = 4242
	root.add_child(game)
	game.call("setup", ctx)
	await process_frame
	game.call("start")
	if game.has_method("apply_view"):
		# WICHTIG: Canvas-Einheiten, nicht Fensterpixel! Unter canvas_items-
		# Stretch (Basis 1280x720, expand) ist die sichtbare Canvas-Fläche
		# skaliert — die Spiele erwarten get_viewport_rect().size.
		game.call("apply_view", root.get_visible_rect().size)
	for _i in 8:
		await process_frame
	return game


## Level-Select-Spiele direkt in ein Gefecht/Puzzle schicken.
func _enter_level(game: Node, game_id: String) -> void:
	if game == null:
		return
	if game_id == "gvz":
		game.call("open_level", 1)
		# Fürs Foto ein LAUFENDES Gefecht herstellen (echte Logik-APIs):
		# Nutella auffüllen, Schützen setzen, Zombies auf drei Bahnen spawnen.
		var state: Dictionary = game.get("state")
		state["nutella"] = 600
		GvzLogic.place_tower(state, "moehrenschuetze", 2, 1)
		GvzLogic.place_tower(state, "moehrenschuetze", 1, 0)
		GvzLogic.place_tower(state, "moehrenschuetze", 3, 2)
		GvzZombies.spawn(state, "schlurfi", 2, 6800)
		GvzZombies.spawn(state, "huetchen", 1, 8200)
		GvzZombies.spawn(state, "eimer", 3, 8800)
	elif game_id == "gobnom":
		game.call("open_level", "campaign", 1)
	elif game_id == "snailMail":
		# Fürs Foto den spieleigenen Bot-Weg einsetzen: Schnecke kriecht los.
		var route: Dictionary = SnailMailLogic.auto_route(game.get("_level"), game.get("tune"))
		game.set("_path", route["smooth"])
		game.set("_phase", "follow")
	elif game_id == "toyRacerBump":
		# Kollisions-Beleg: Spieler-Kart überdeckend hinter einen Bot setzen —
		# ToyRacerContact trennt die beiden im nächsten Frame (Funken-Burst,
		# seitliche Abdrängung, Tempoverlust) statt sie durchfahren zu lassen.
		var race: Dictionary = game.get("race")
		var karts: Array = race["karts"]
		# Fotoplatz: gerades Stück ABSEITS des Loopings (dort verdeckt die
		# Röhre die Kamera) — erste s-Position mit 4 Einheiten Freiraum.
		var spot := 6.0
		while (
			ToyRacerLogic.in_loop_zone(race["track"], spot - 2.0)
			or ToyRacerLogic.in_loop_zone(race["track"], spot + 4.0)
		):
			spot += 1.0
		for values: Array in [
			[0, spot, 0.02, 3.0],
			[1, spot + 0.3, -0.06, 1.6],
			[2, spot + 14.0, 0.2, 2.0],
			[3, spot + 20.0, -0.2, 2.0],
		]:
			var kart: Dictionary = karts[int(values[0])]
			kart["s"] = float(values[1])
			kart["progress"] = float(values[1])
			kart["lateral"] = float(values[2])
			kart["speed"] = float(values[3])
		# Kamera sofort hinter das versetzte Spieler-Kart springen lassen.
		game.call("_snap_camera")
	elif game_id == "runnerCars":
		# Boden-Beleg: zwei Autos in den Seitenspuren nah vor dem Spieler
		# (Spur 1 bleibt frei — kein Crash vor dem Foto). Sie posieren wie
		# alle Hindernis-Autos auf y = 0 == Fahrbahn-OBERKANTE.
		var obstacles: Array = game.get("_obstacles")
		obstacles.append({"kind": "car", "lane": 0, "z": -16.0, "yaw": 0.08, "row": 900})
		obstacles.append({"kind": "car", "lane": 2, "z": -20.0, "yaw": PI - 0.06, "row": 901})


## `pressed` null = Ziehen, true = Auflegen, false = Abheben.
## rel wird auf die SICHTBARE Canvas-Fläche gerechnet (Stretch-Koordinaten).
func _touch(rel: Vector2, pressed: Variant) -> void:
	var pos := root.get_visible_rect().size * rel
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
	root.push_input(event, true)


func _resize(size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	root.size = size


## Foto machen und die Draw-Calls DIESES gerenderten Frames zurückgeben.
func _snap(file: String) -> int:
	for _i in 4:
		await process_frame
	var draws := RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
	)
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_BASE, file])
	print("  gespeichert: %s (%dx%d)" % [file, image.get_width(), image.get_height()])
	return draws
