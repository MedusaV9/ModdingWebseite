extends SceneTree
## MPG-Screenshot-Werkzeug (KEIN TestCase — der Haupt-Runner überspringt es):
## montiert die vier MPG-Spiele (gvz, gobnom, ranchParcours, ranchHerde)
## DIREKT (fb4_screens-Muster), spielt echte Logik-Sekunden hinein und legt
## PNGs samt Draw-Call-Messung ab. Braucht einen echten Renderer (xvfb):
##   xvfb-run -a godot --path GOOBY-GODOT --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --fixed-fps 60 \
##     --script res://tests/unit/test_mpg_screens.gd -- [before|after] [ids...]
## Höhepunkte laufen über die ECHTEN Sim-APIs (GvzLogic/GobnomLogic/…):
## gvz_sieg spult Level 1 mit gesetzten Türmen bis zum Sieg, gobnom_nom
## führt den Level-1-Lösungsplan aus, parcours_sprung springt im Bogenfenster,
## herde_pferch treibt die Herde per Reiter-Ziel ins Tor.

const OUT_BASE := "/tmp/gooby-godot/artifacts/MPG"
const PORTRAIT := Vector2i(720, 1160)
const LANDSCAPE := Vector2i(1160, 720)

var _phase := "before"
var _portrait_run := false

var _shots := [
	"gvz_select",
	"gvz",
	"gvz_sieg",
	"gobnom",
	"gobnom_nom",
	"ranchParcours",
	"parcours_sprung",
	"ranchHerde",
	"herde_pferch",
]


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	root.theme = ThemeService.theme()
	var ids: Array = []
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		if text == "before" or text == "after":
			_phase = text
		elif text == "portrait":
			_portrait_run = true
		else:
			ids.append(text)
	if ids.is_empty():
		ids = _shots
	DirAccess.make_dir_recursive_absolute("%s/%s" % [OUT_BASE, _phase])
	for id: String in ids:
		await _shoot(id)
	print("MPG-Screenshots fertig → %s/%s" % [OUT_BASE, _phase])
	quit(0)


func _shoot(id: String) -> void:
	match id:
		"gvz_select":
			await _gvz_select()
		"gvz":
			await _gvz_battle()
		"gvz_sieg":
			await _gvz_sieg()
		"gobnom":
			await _gobnom_play()
		"gobnom_nom":
			await _gobnom_nom()
		"ranchParcours":
			await _parcours(4.6, false)
		"parcours_sprung":
			await _parcours(0.0, true)
		"ranchHerde":
			await _herde(false)
		"herde_pferch":
			await _herde(true)
		_:
			print("  ÜBERSPRUNGEN (unbekannt): %s" % id)


## ── gvz ───────────────────────────────────────────────────────────────────


func _gvz_select() -> void:
	var game := await _mount("gvz")
	for _i in 20:
		await process_frame
	await _snap(game, "gvz_select")


func _gvz_battle() -> void:
	var game := await _mount("gvz")
	game.call("open_level", 4)
	var state: Dictionary = game.get("state")
	state["nutella"] = 900
	GvzLogic.place_tower(state, "moehrenschuetze", 1, 1)
	GvzLogic.place_tower(state, "moehrenschuetze", 2, 1)
	GvzLogic.place_tower(state, "moehrenschuetze", 3, 2)
	GvzLogic.place_tower(state, "nutella_sammler", 2, 0)
	GvzLogic.place_tower(state, "schnarch_knolle", 1, 3)
	GvzZombies.spawn(state, "schlurfi", 2, 6800)
	GvzZombies.spawn(state, "huetchen", 1, 8200)
	GvzZombies.spawn(state, "eimer", 3, 8800)
	GvzZombies.spawn(state, "sprinter", 0, 7600)
	GvzZombies.spawn(state, "ballon", 4, 8300)
	for _i in int(7.0 * 60.0):
		await process_frame
	await _snap(game, "gvz")


## Level 1 ehrlich GEWINNEN: Türme setzen, Sim in großen Häppchen vorspulen
## (echte GvzLogic-Ticks über den normalen _process-Weg), Sieg-Overlay fotografieren.
func _gvz_sieg() -> void:
	var game := await _mount("gvz")
	game.call("open_level", 1)
	var state: Dictionary = game.get("state")
	state["nutella"] = 900
	GvzLogic.place_tower(state, "moehrenschuetze", 2, 0)
	GvzLogic.place_tower(state, "moehrenschuetze", 2, 1)
	GvzLogic.place_tower(state, "moehrenschuetze", 2, 2)
	for _i in 40:
		if str(game.get("phase")) != "battle":
			break
		game.set("_accum", 6.0)
		await process_frame
	for _i in 30:
		await process_frame
	print("  gvz_sieg: phase=%s" % str(game.get("phase")))
	await _snap(game, "gvz_sieg")


## ── gobnom ────────────────────────────────────────────────────────────────


func _gobnom_play() -> void:
	var game := await _mount("gobnom")
	game.call("open_level", "campaign", 5)
	for _i in int(2.2 * 60.0):
		await process_frame
	# Swipe-Spur sichtbar machen (Zeiger streicht unter dem Bonbon durch).
	_touch(Vector2(0.35, 0.42), true)
	for i in 10:
		_drag(Vector2(0.35 + 0.02 * float(i), 0.42 + 0.008 * float(i)))
		await process_frame
	_touch(Vector2(0.55, 0.5), false)
	await _snap(game, "gobnom")


## Level 1 über den Lösungsplan gewinnen: Seil kappen → Bonbon fällt durch
## alle drei Gläser in Goobys Maul (Konfetti + Sieg-Overlay).
func _gobnom_nom() -> void:
	var game := await _mount("gobnom")
	game.call("open_level", "campaign", 1)
	var state: Dictionary = game.get("state")
	for _i in 30:
		await process_frame
	GobnomLogic.cut_rope(state, 0)
	var caught_frame := -1
	for frame in 300:
		if int(state.get("jars_taken", 0)) >= 3 and caught_frame < 0:
			caught_frame = frame
			await _snap(game, "gobnom_glas_gefangen", false)
		if GobnomLogic.is_over(state) and str(game.get("phase")) != "play":
			break
		await process_frame
	for _i in 24:
		await process_frame
	print("  gobnom_nom: outcome=%s jars=%d" % [str(state["outcome"]), int(state["jars_taken"])])
	await _snap(game, "gobnom_nom")


## ── ranch ─────────────────────────────────────────────────────────────────


func _parcours(sec: float, sprung: bool) -> void:
	var game := await _mount("ranchParcours")
	game.call("_on_level_chosen", 1)
	game.set("galopp", true)
	if not sprung:
		for _i in int(sec * 60.0):
			await process_frame
		await _snap(game, "parcours")
		return
	# Bis kurz vor Hindernis 1 (at=26 m) laufen, im Bogenfenster abspringen,
	# im höchsten Punkt fotografieren.
	var jumped := false
	for _i in 1200:
		var x := float(game.get("x"))
		var tempo := float(game.get("tempo"))
		var weite := float(RanchRideFeel.sprung_daten(tempo)["weite_m"])
		if not jumped and x >= 26.0 - weite * 0.52:
			game.call("_sprung_input")
			jumped = true
		if jumped:
			var s: Dictionary = game.get("sprung")
			if bool(game.get("in_luft")) and float(s["vy"]) <= 0.5:
				break
		await process_frame
	await _snap(game, "parcours_sprung")


func _herde(pferch: bool) -> void:
	var game := await _mount("ranchHerde")
	game.call("_on_level_chosen", 1)
	for _i in 30:
		await process_frame
	if not pferch:
		# Reiter hinter die Herde schicken (Schafe fliehen Richtung Tor).
		game.set("ziel", Vector2(0.0, 2.0))
		for _i in int(4.0 * 60.0):
			await process_frame
		await _snap(game, "herde")
		return
	# Höhepunkt: Herde per Reiter-Ziel Richtung Tor treiben; wenn die Sim
	# zu lange braucht, die Schafe kurz vors Tor setzen (Logik zählt selbst).
	game.set("ziel", Vector2(0.0, 1.5))
	for _i in int(6.0 * 60.0):
		if not bool(game.get("level_running")):
			break
		await process_frame
	if bool(game.get("level_running")):
		var schafe: Array = game.get("schafe")
		var tor: Vector2 = RanchHerdeLogic.tor_pos(game.get("level"))
		for i in schafe.size():
			var s: Dictionary = schafe[i]
			s["x"] = tor.x - 1.0 + float(i)
			s["z"] = tor.y - 1.4
		game.set("ziel", Vector2(tor.x, tor.y + 3.0))
		for _i in int(8.0 * 60.0):
			if not bool(game.get("level_running")):
				break
			await process_frame
	for _i in 20:
		await process_frame
	print("  herde_pferch: drin=%d" % int(game.get("drin_vorher")))
	await _snap(game, "herde_pferch")


## ── Gerüst ────────────────────────────────────────────────────────────────


func _mount(game_id: String) -> Node:
	var meta := MinigameRegistry.get_game(game_id)
	var landscape := not _portrait_run
	_resize(LANDSCAPE if landscape else PORTRAIT)
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
		game.call("apply_view", root.get_visible_rect().size)
	for _i in 8:
		await process_frame
	return game


func _touch(rel: Vector2, pressed: bool) -> void:
	var touch := InputEventScreenTouch.new()
	touch.position = root.get_visible_rect().size * rel
	touch.pressed = pressed
	root.push_input(touch, true)


func _drag(rel: Vector2) -> void:
	var drag := InputEventScreenDrag.new()
	drag.position = root.get_visible_rect().size * rel
	root.push_input(drag, true)


func _resize(size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	root.size = size


func _snap(game: Node, name_base: String, free := true) -> void:
	for _i in 4:
		await process_frame
	var draws := RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
	)
	var suffix := "_portrait" if _portrait_run else ""
	var file := "%s/%s%s.png" % [_phase, name_base, suffix]
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_BASE, file])
	var luma := 0.0
	var probe := image.duplicate()
	probe.resize(32, 32, Image.INTERPOLATE_BILINEAR)
	for y in 32:
		for x in 32:
			var c: Color = probe.get_pixel(x, y)
			luma += 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
	luma = luma / (32.0 * 32.0) * 255.0
	print("  %s: Draw-Calls=%d Luma=%.0f" % [file, draws, luma])
	if free and game != null and is_instance_valid(game):
		game.queue_free()
		await process_frame
		await process_frame
