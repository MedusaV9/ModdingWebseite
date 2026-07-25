extends SceneTree
## 3D-B-Screenshot-Werkzeug (KEIN Test): montiert den MinigameHost für die fünf
## 3D-Spiele des Auftrags, spielt ein paar Sekunden und legt PNGs ab —
## zusätzlich wird der Draw-Call-Zähler des Frames protokolliert (Perf-Budget).
##
##   xvfb-run -a godot --path GOOBY-GODOT --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --script res://tests/unit/screenshot_3db.gd
##
## Optional: `-- <id>[:quer|:hoch][@sekunden] …` — ohne Argumente alle fünf in
## ihrer Standard-Orientierung PLUS je einer in der anderen. Das `@`-Suffix
## kürzt die Spielzeit vor dem Foto (schnelle Iteration beim Bildaufbau).

const OUT_DIR := "/tmp/gooby-godot/artifacts/3DB"
const HOST_SCENE := "res://scripts/minigames/minigame_host.tscn"
const PORTRAIT := Vector2i(760, 1200)
const LANDSCAPE := Vector2i(1200, 760)

## id → {sec: Spielzeit vor dem Foto, keys: [[frame, keycode, halten?]]}.
const PLANS := {
	"runner": {"sec": 9.0, "keys": [], "autoplay": true},
	"shoppingSurf": {"sec": 8.0, "keys": [], "autoplay": true},
	"harborHopper": {"sec": 7.0, "keys": [], "autoplay": true},
	# Nach ~12 s ist das Feld aus dem ersten Looping heraus; den Rest sucht
	# `screenshot_ready()` selbst — es wartet auf eine Lücke im Gummiband-Pulk,
	# in der Gooby nicht hinter einem KI-Kart steckt.
	"toyRacer": {"sec": 12.0, "keys": [], "autoplay": true},
	"deliveryRush": {"sec": 7.0, "keys": [], "autoplay": true},
}
const BOTH: Array[String] = ["runner", "shoppingSurf", "harborHopper", "toyRacer", "deliveryRush"]

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
		for id in BOTH:
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
	var seconds := -1.0
	if spec.contains("@"):
		var split := spec.split("@")
		spec = split[0]
		seconds = float(split[1])
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
	var orientation := "landscape" if landscape else "portrait"
	(
		host
		. receive_params(
			{
				"game_id": game_id,
				"difficulty": "normal",
				"seed": 4242,
				"orientation": orientation,
			}
		)
	)
	root.add_child(host)
	for _i in 20:
		await process_frame
	var plan: Dictionary = PLANS.get(game_id, {"sec": 5.0, "keys": []})
	if bool(plan.get("autoplay", false)):
		_enable_autoplay(host)
	var target := seconds if seconds > 0.0 else float(plan["sec"])
	var keys: Array = plan["keys"]
	var frame := 0
	var played := 0.0
	# ACHTUNG: unter llvmpipe läuft der Bildaufbau bei ~5 fps, und die Spiele
	# rechnen mit `min(delta, 0.1)`. Wer hier Frames zählt (× 60), spielt in
	# Wahrheit das Zehnfache — deshalb wird SPIELZEIT nachgehalten.
	while played < target:
		for entry: Array in keys:
			if int(entry[0]) == frame:
				_press(host, int(entry[1]), str(entry[2]) if entry.size() > 2 else "")
		var before := Time.get_ticks_usec()
		await process_frame
		played += minf(float(Time.get_ticks_usec() - before) / 1e6, 0.1)
		frame += 1
	await _wait_for_gooby(host)
	var calls := RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
	)
	_report.append("%s%s: %d Draw-Calls" % [game_id, suffix, calls])
	await _snap("%s%s.png" % [game_id, suffix])
	host.queue_free()
	await process_frame


## Nach einem Treffer blinkt Gooby unverwundbar, beim Rutschen ist er auf halbe
## Höhe gestaucht — in beiden Fällen ist das Beweisfoto wertlos. Also so lange
## weiterspielen (max. 3 s), bis er aufrecht und sichtbar ist.
func _wait_for_gooby(host: MinigameHost) -> void:
	var game := _game_node(host)
	if game == null:
		return
	var gooby := game.get("_gooby") as Node3D
	if gooby == null:
		return
	var camera := (game.get("_stage") as Node3D).get("camera") as Camera3D
	var share := 0.0
	for _i in 200:
		share = _gooby_screen_share(gooby, camera)
		var staged: bool = (
			not game.has_method("screenshot_ready") or bool(game.call("screenshot_ready"))
		)
		if staged and gooby.visible and gooby.scale.y > 0.9 and share > 0.03:
			return
		await process_frame
	print("    (Gooby blieb klein/verdeckt — Bildanteil %.3f)" % share)


## Anteil der Bildhöhe, den Gooby einnimmt. Fährt die Stuntkamera im Looping
## weit weg, sinkt der Wert — dann lohnt sich das Foto noch nicht.
func _gooby_screen_share(gooby: Node3D, camera: Camera3D) -> float:
	if camera == null:
		return 1.0
	var box := AABB()
	var first := true
	for mi: MeshInstance3D in gooby.find_children("*", "MeshInstance3D", true, false):
		var world: AABB = mi.global_transform * mi.get_aabb()
		box = world if first else box.merge(world)
		first = false
	if first:
		return 1.0
	var top := box.position + Vector3(0.0, box.size.y, 0.0)
	if camera.is_position_behind(top) or camera.is_position_behind(box.position):
		return 0.0
	var span := absf(camera.unproject_position(top).y - camera.unproject_position(box.position).y)
	return span / maxf(1.0, float(camera.get_viewport().get_visible_rect().size.y))


func _game_node(host: MinigameHost) -> Node:
	var viewport := _sub_viewport(host)
	if viewport == null or viewport.get_child_count() == 0:
		return null
	return viewport.get_child(viewport.get_child_count() - 1)


func _enable_autoplay(host: MinigameHost) -> void:
	var game := _game_node(host)
	if game != null and "autoplay" in game:
		game.set("autoplay", true)


## Jede Runde kostet Energie — nach ein paar Fotos verweigert der Host sonst.
func _refill_energy() -> void:
	var gs := root.get_node_or_null(^"/root/GameState")
	if gs != null and gs.has_method("set_value"):
		gs.call("set_value", "gooby.stats.energy", 100.0)


func _sub_viewport(host: MinigameHost) -> SubViewport:
	var found := host.find_children("*", "SubViewport", true, false)
	return null if found.is_empty() else found[0] as SubViewport


func _press(host: MinigameHost, keycode: int, mode := "") -> void:
	var viewport := _sub_viewport(host)
	if viewport == null:
		return
	if mode != "up":
		viewport.push_input(_key_event(keycode, true), true)
	if mode == "" or mode == "up":
		viewport.push_input(_key_event(keycode, false), true)


func _key_event(keycode: int, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = keycode as Key
	event.physical_keycode = keycode as Key
	event.pressed = pressed
	return event


func _resize(size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	root.size = size
	root.set_content_scale_size(size)


func _snap(file_name: String) -> void:
	await process_frame
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file_name])
	print("  %s (%dx%d)" % [file_name, image.get_width(), image.get_height()])
