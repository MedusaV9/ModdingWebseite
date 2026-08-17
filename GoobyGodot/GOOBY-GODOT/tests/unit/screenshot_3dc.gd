extends SceneTree
## 3D-C-Screenshot-Werkzeug (KEIN Test): montiert den MinigameHost für die
## sechs 3D-Rückbauten, spielt sie ein paar Sekunden MITTEN INS SPIEL und legt
## PNGs ab. Braucht einen echten Renderer (xvfb):
##   xvfb-run -a godot --path GOOBY-GODOT --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --fixed-fps 60 \
##     --script res://tests/unit/screenshot_3dc.gd
## `--fixed-fps 60` ist PFLICHT: der Software-Renderer schafft nur ~7 fps, ohne
## festes Delta rast die Simulation (und der Foto-Bot verliert sofort).
## Optional: `-- starHopper landscape` (Ids und/oder das Wort `landscape`).

const HopperLogic := preload("res://scripts/minigames/games/star_hopper/star_hopper_logic.gd")
const OUT_DIR := "/tmp/gooby-godot/artifacts/3DC"
const HOST_SCENE := "res://scripts/minigames/minigame_host.tscn"
const PORTRAIT := Vector2i(720, 1160)
const LANDSCAPE := Vector2i(1160, 720)

## id → {sec: Spielzeit vor dem Foto, taps: [[frame, rel_x, rel_y, gedrückt]]}
const PLANS := {
	"starHopper": {"sec": 6.0, "taps": [[90, 0.2, 0.6, true], [92, 0.2, 0.6, false]]},
	"rocketRescue": {"sec": 5.0, "taps": [[30, 0.46, 0.7, true]]},
	"burgerBuild": {"sec": 8.0, "taps": [[20, 0.5, 0.8, true]]},
	"veggieChop": {"sec": 5.0, "taps": []},
	"hideSeek": {"sec": 5.0, "taps": []},
	"purblePlace": {"sec": 9.0, "taps": []},
}

var _landscape_run := false


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	root.theme = ThemeService.theme()
	var ids: Array = []
	for arg in OS.get_cmdline_user_args():
		if str(arg) == "landscape":
			_landscape_run = true
		else:
			ids.append(str(arg))
	if ids.is_empty():
		ids = PLANS.keys()
	for id: String in ids:
		await _shoot_game(id)
	print("Screenshots fertig → %s" % OUT_DIR)
	quit(0)


func _shoot_game(game_id: String) -> void:
	var meta := MinigameRegistry.get_game(game_id)
	if meta.is_empty():
		print("  ÜBERSPRUNGEN (nicht in der Registry): %s" % game_id)
		return
	var landscape := _landscape_run or str(meta.get("orientation", "portrait")) == "landscape"
	_resize(LANDSCAPE if landscape else PORTRAIT)
	var host: MinigameHost = (load(HOST_SCENE) as PackedScene).instantiate()
	host.auto_navigate = false
	host.countdown_step_sec = 0.01
	var params := {"game_id": game_id, "difficulty": "normal", "seed": 4242}
	if _landscape_run:
		params["orientation"] = "landscape"
	host.receive_params(params)
	root.add_child(host)
	for _i in 16:
		await process_frame
	var plan: Dictionary = PLANS.get(game_id, {"sec": 5.0, "taps": []})
	var taps: Array = plan["taps"]
	for frame in int(float(plan["sec"]) * 60.0):
		var game := _game_of(host)
		if game != null and not bool(game.get("running")) and frame > 40:
			print("  (Runde vorbei bei Frame %d — Foto sofort) %s" % [frame, game.name])
			break
		for entry: Array in taps:
			if int(entry[0]) == frame:
				_touch(host, Vector2(float(entry[1]), float(entry[2])), entry[3])
		_autoplay(host, game_id)
		await process_frame
	_probe(host, game_id)
	var draws := RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
	)
	var suffix := "_landscape" if _landscape_run else ""
	await _snap("%s%s.png" % [game_id, suffix])
	print("  %s: Draw-Calls=%d" % [game_id, draws])
	host.queue_free()
	await process_frame


## Spiele, die für ein aussagekräftiges Foto Eingaben brauchen, werden pro
## Frame aus ihrem Zustand heraus bedient (Bot-Ersatz).
func _autoplay(host: MinigameHost, game_id: String) -> void:
	var game := _game_of(host)
	if game == null:
		return
	match game_id:
		"burgerBuild":
			_autoplay_burger(host, game)
		"hideSeek":
			_autoplay_seek(host, game)
		"veggieChop":
			_autoplay_chop(host, game)
		"purblePlace":
			game.set("autoplay", true)
		"rocketRescue":
			_autoplay_rocket(host, game)
		"starHopper":
			_autoplay_hopper(host, game)


## Ausweich-Bot: Kontaktzeit je Bahn schätzen und rechtzeitig ausweichen,
## damit das Foto MITTEN im Lauf entsteht (und nicht im Ergebnis-Dialog).
func _autoplay_hopper(host: MinigameHost, game: Node) -> void:
	var tune: Dictionary = game.get("tune")
	var traveled := float(game.get("traveled"))
	var lane := int(game.get("lane"))
	var speed := HopperLogic.speed_at(float(game.get("elapsed")), tune)
	var reach := (
		float(tune["HITBOX_SCALE"]) * (float(tune["PLAYER_HALF_M"]) + float(tune["METEOR_HALF_M"]))
	)
	var contact := [99.0, 99.0, 99.0]
	for meteor: Dictionary in game.get("_meteors"):
		var closing := speed + float(meteor["approach"])
		var t := (float(meteor["m"]) - traveled - reach * 2.0) / maxf(0.1, closing)
		var index := int(meteor["lane"])
		if t > -0.35 and t < float(contact[index]):
			contact[index] = t
	if float(contact[lane]) > 1.3:
		return
	var best := lane
	for i in 3:
		if absi(i - lane) == 1 and float(contact[i]) > float(contact[best]):
			best = i
	if best == lane:
		return
	var side := 0.2 if best < lane else 0.8
	_touch(host, Vector2(side, 0.6), true)
	_touch(host, Vector2(side, 0.6), false)


func _autoplay_burger(host: MinigameHost, game: Node) -> void:
	# Teller unter die nächste RICHTIGE Zutat schieben.
	var items: Array = game.get("_items")
	var ticket: Array = game.get("ticket")
	var placed: int = int(game.get("placed"))
	var needed := "" if placed >= ticket.size() else str(ticket[placed])
	var target := 0.0
	var best := 99.0
	for item: Dictionary in items:
		if str(item["id"]) != needed:
			continue
		if float(item["y"]) < best:
			best = float(item["y"])
			target = float(item["x"])
	var pos: Vector2 = game.call("project", target, 0.0)
	var size := Vector2(_sub_viewport(host).size)
	_touch(host, Vector2(pos.x / size.x, 0.8), null)


func _autoplay_seek(host: MinigameHost, game: Node) -> void:
	# Jedes zweite Sekundenviertel EIN Versteck aufdecken (nie alle).
	var hidden: Dictionary = game.get("_hidden")
	if hidden.size() <= 2:
		return
	if int(float(game.get("elapsed")) * 2.0) % 3 != 0:
		return
	var spot: int = hidden.keys()[0]
	var pos: Vector2 = game.call("spot_center", spot)
	var size := Vector2(_sub_viewport(host).size)
	_touch(host, pos / size, true)
	_touch(host, pos / size, false)


func _autoplay_chop(host: MinigameHost, game: Node) -> void:
	# Nur gelegentlich schnippeln — sonst ist die Luft im Foto immer leer.
	var items: Array = game.get("items")
	if items.size() < 2 or int(float(game.get("elapsed")) * 4.0) % 3 != 0:
		return
	var size := Vector2(_sub_viewport(host).size)
	var entry: Dictionary = items[0]
	var pos: Vector2 = game.call("_to_screen", Vector2(entry["pos"]))
	_touch(host, (pos + Vector2(-70.0, 40.0)) / size, true)
	_touch(host, (pos + Vector2(70.0, -40.0)) / size, null)
	_touch(host, (pos + Vector2(70.0, -40.0)) / size, false)


func _autoplay_rocket(host: MinigameHost, game: Node) -> void:
	# Sanft schweben: unter 3 m Höhe Schub geben, sonst fallen lassen.
	var state: Dictionary = game.get("engine").state
	var thrust := float(state["vy"]) < -0.6 or float(state["y"]) < 2.4
	_touch(host, Vector2(0.5, 0.65), thrust)


## Projektionsprobe: stimmt die 3D-Kamera mit der 2D-Formel des Spiels überein?
func _probe(host: MinigameHost, game_id: String) -> void:
	var game := _game_of(host)
	if game == null:
		return
	if game_id == "purblePlace":
		var shop: Node3D = game.get("_shop")
		var baker: Node3D = shop.get("gooby")
		var feet: Vector2 = shop.camera.unproject_position(baker.global_position)
		var crown: Vector2 = shop.camera.unproject_position(
			baker.global_position + Vector3(0, 1.75, 0)
		)
		print(
			(
				"  probe vp=%s cam=%s gooby=%s..%s (h=%.0f px) guest0=%s"
				% [
					str(_sub_viewport(host).size),
					str(shop.camera.position),
					str(feet),
					str(crown),
					feet.y - crown.y,
					str(shop.guest_anchor(0)),
				]
			)
		)
		return
	if game_id == "hideSeek":
		var garden: Node3D = game.get("_stage")
		var rig: Node3D = garden.get("gooby")
		print(
			(
				"  probe vp=%s fov=%.1f gooby=%s screen=%s"
				% [
					str(_sub_viewport(host).size),
					garden.camera.fov,
					str(rig.global_position) if rig != null else "null",
					(
						str(garden.camera.unproject_position(rig.global_position))
						if rig != null
						else "-"
					),
				]
			)
		)
		return
	if game_id != "veggieChop":
		return
	var stage: Node3D = game.get("_stage")
	print(
		(
			"  probe vp=%s ppu=%.1f fov=%.1f cam=%s 2d(-3.35)=%s 3d(-3.35)=%s"
			% [
				str(_sub_viewport(host).size),
				float(game.call("_ppu")),
				stage.camera.fov,
				str(stage.camera.position),
				str(game.call("_to_screen", Vector2(0.0, -3.35))),
				str(stage.camera.unproject_position(Vector3(0.0, -3.35, 0.0))),
			]
		)
	)


func _game_of(host: MinigameHost) -> Node:
	var viewport := _sub_viewport(host)
	if viewport == null or viewport.get_child_count() == 0:
		return null
	return viewport.get_child(viewport.get_child_count() - 1)


## `pressed` null = Ziehen, true = Auflegen, false = Abheben.
func _touch(host: MinigameHost, rel: Vector2, pressed: Variant) -> void:
	var viewport := _sub_viewport(host)
	if viewport == null:
		return
	var pos := Vector2(viewport.size) * rel
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


func _snap(file: String) -> void:
	for _i in 4:
		await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("  gespeichert: %s (%dx%d)" % [file, image.get_width(), image.get_height()])
