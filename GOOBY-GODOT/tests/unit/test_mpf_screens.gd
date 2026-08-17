extends SceneTree
## MP-F Screenshot-/Bot-Werkzeug (KEIN Test — der Haupt-Runner überspringt
## Nicht-TestCase-Dateien mit SKIP). Montiert die vier MP-F-Spiele (runner,
## toyRacer, harborHopper, shoppingSurf) DIREKT, lässt den eingebauten
## Autoplay-Piloten fahren und fotografiert Bühne, Tempo- und Belohnungs-
## Momente. Braucht einen echten Renderer (xvfb):
##   xvfb-run -a godot --path GOOBY-GODOT --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --fixed-fps 60 \
##     --script res://tests/unit/test_mpf_screens.gd -- [before|after] [ids...]
## `--fixed-fps 60` ist PFLICHT: der Software-Renderer schafft nur ~7 fps.
## ZEITRAFFER: pro gerendertem Frame wird `_process` zusätzlich von Hand
## getickt — sonst dauert eine Fahrt zum Tempomoment Minuten an Wandzeit.

const OUT_BASE := "/tmp/gooby-godot/artifacts/MPF"
const PORTRAIT := Vector2i(720, 1160)
const LANDSCAPE := Vector2i(1160, 720)
const GAMES: Array[String] = ["runner", "toyRacer", "harborHopper", "shoppingSurf"]
## Zusätzliche Handticks pro gerendertem Frame (je 0,05 s Spielzeit).
const WARP_TICKS := 4
const WARP_DT := 0.05

var _phase := "before"
var _juice: JuiceKit
var _overlay: Control
var _game: Node


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	root.theme = ThemeService.theme()
	var ids: Array[String] = []
	for arg in OS.get_cmdline_user_args():
		var text := str(arg)
		if text == "before" or text == "after":
			_phase = text
		else:
			ids.append(text)
	if ids.is_empty():
		ids = GAMES
	DirAccess.make_dir_recursive_absolute("%s/%s" % [OUT_BASE, _phase])
	for id in ids:
		await _shoot(id)
	print("MPF-Screenshots fertig → %s/%s" % [OUT_BASE, _phase])
	quit(0)


func _shoot(game_id: String) -> void:
	var meta := MinigameRegistry.get_game(game_id)
	var landscape := str(meta.get("orientation", "portrait")) == "landscape"
	_resize(LANDSCAPE if landscape else PORTRAIT)
	await _mount(game_id, meta, landscape)
	match game_id:
		"runner":
			await _play_runner()
		"toyRacer":
			await _play_toy_racer()
		"harborHopper":
			await _play_harbor()
		"shoppingSurf":
			await _play_surf()
	_teardown()
	await process_frame


func _mount(game_id: String, meta: Dictionary, landscape: bool) -> void:
	var ctx := MinigameCtx.new()
	ctx.game_id = game_id
	ctx.difficulty = "normal"
	ctx.orientation = "landscape" if landscape else "portrait"
	ctx.run_seed = 4242
	_overlay = Control.new()
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_overlay)
	_juice = JuiceKit.new()
	_juice.float_text_parent = _overlay
	root.add_child(_juice)
	ctx.juice = _juice
	_game = (load(str(meta["scene"])) as PackedScene).instantiate()
	root.add_child(_game)
	root.move_child(_overlay, root.get_child_count() - 1)
	_game.call("setup", ctx)
	_game.set("autoplay", true)
	await process_frame
	_game.call("start")
	if _game.has_method("apply_view"):
		_game.call("apply_view", root.get_visible_rect().size)
	for _i in 6:
		await process_frame


func _teardown() -> void:
	_game.queue_free()
	_juice.queue_free()
	_overlay.queue_free()


## Ein gerenderter Frame + WARP_TICKS Handticks Spielzeit.
func _step() -> void:
	for _i in WARP_TICKS:
		if bool(_game.get("finished")):
			break
		_game.call("_process", WARP_DT)
	await process_frame


# ── Spielpläne ────────────────────────────────────────────────────────────


## Runner: Bühne bei ~8 s, Belohnung (Combo/Kiste), Tempo (Vollgas 13 m/s).
func _play_runner() -> void:
	var reward_shot := false
	for _frame in 600:
		if bool(_game.get("finished")):
			break
		await _step()
		var elapsed := float(_game.get("elapsed"))
		if elapsed >= 8.0 and not reward_shot and _frame_has_runner_reward():
			reward_shot = true
			await _snap("runner_reward")
		if elapsed >= 8.0 and _game.get_meta("mid_done", false) == false:
			_game.set_meta("mid_done", true)
			await _snap("runner_mid")
		if reward_shot and elapsed >= 12.0:
			break
		if elapsed >= 40.0:
			break
	# Tempomoment: Spielzeit vorspulen — die Logik rechnet Tempo aus `elapsed`.
	if not bool(_game.get("finished")):
		_game.set("elapsed", 160.0)
		for _i in 10:
			await _step()
		await _snap("runner_tempo")


func _frame_has_runner_reward() -> bool:
	return int(_game.get("coin_streak")) >= 5 or int(_game.get("powerups")) >= 1


## ToyRacer: Bühne bei ~7 s, Tempo (Drift-Boost), Belohnung (Überholen —
## Rückfall: Zieleinlauf mit Konfetti/Banner, der kommt IMMER).
func _play_toy_racer() -> void:
	var mid_shot := false
	var tempo_shot := false
	var reward_shot := false
	var overtakes0 := int((_game.get("race") as Dictionary)["overtakes"])
	for _frame in 900:
		if bool(_game.get("finished")):
			break
		await _step()
		var race: Dictionary = _game.get("race")
		var kart0: Dictionary = (race["karts"] as Array)[0]
		var elapsed := float(_game.get("_elapsed"))
		if not mid_shot and elapsed >= 7.0:
			mid_shot = true
			await _snap("toyRacer_mid")
		if not tempo_shot and float(kart0["boostT"]) > 0.6:
			tempo_shot = true
			await _snap("toyRacer_tempo")
		# Belohnung: Überholmanöver — oder der Zieleinlauf (Konfetti-Burst und
		# Banner laufen im 1,2-s-`_ending`-Fenster, bevor `finished` kippt).
		var rewarded := int(race["overtakes"]) > overtakes0 or bool(race["ended"])
		if not reward_shot and rewarded:
			reward_shot = true
			await _snap("toyRacer_reward")
		if mid_shot and tempo_shot and reward_shot:
			break


## HarborHopper: Bühne bei ~7 s, Tempo (Wellen-Boost), Belohnung (Sammelserie).
func _play_harbor() -> void:
	var mid_shot := false
	var tempo_shot := false
	var reward_shot := false
	for _frame in 900:
		if bool(_game.get("finished")):
			break
		await _step()
		var state: Dictionary = _game.get("engine").get("state")
		var elapsed := float(state["elapsed"])
		if not mid_shot and elapsed >= 7.0:
			mid_shot = true
			await _snap("harborHopper_mid")
		if not tempo_shot and float(state["boostT"]) > 1.0:
			tempo_shot = true
			await _snap("harborHopper_tempo")
		if not reward_shot and int(_game.get("collect_streak")) >= 3:
			reward_shot = true
			await _snap("harborHopper_reward")
		if mid_shot and tempo_shot and reward_shot:
			break


## ShoppingSurf: Bühne bei ~7 s, Belohnung (Beinahe-Treffer/Münzserie),
## Tempo (Speed-Rampe wird am Ende vorgespult — wie beim Runner).
func _play_surf() -> void:
	var mid_shot := false
	var reward_shot := false
	for _frame in 600:
		if bool(_game.get("finished")):
			break
		await _step()
		var run: Dictionary = _game.get("run")
		var elapsed := float(run["elapsed"])
		if not mid_shot and elapsed >= 7.0:
			mid_shot = true
			await _snap("shoppingSurf_mid")
		if not reward_shot and (int(run["nearMisses"]) >= 1 or int(_game.get("coin_run")) >= 5):
			reward_shot = true
			await _snap("shoppingSurf_reward")
		if mid_shot and reward_shot and elapsed >= 12.0:
			break
		if elapsed > 60.0:
			break
	# Tempomoment: Rampen-Uhr vorspulen — die Logik rechnet das Tempo daraus.
	if not bool(_game.get("finished")):
		(_game.get("run") as Dictionary)["rampSec"] = 300.0
		for _i in 10:
			await _step()
		await _snap("shoppingSurf_tempo")


# ── Foto ──────────────────────────────────────────────────────────────────


func _snap(name: String) -> void:
	for _i in 3:
		await process_frame
	var draws := RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
	)
	var file := "%s/%s/%s.png" % [OUT_BASE, _phase, name]
	var image := root.get_texture().get_image()
	image.save_png(file)
	print("  Foto %s (%dx%d) Draw-Calls=%d" % [file, image.get_width(), image.get_height(), draws])


func _resize(size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	root.size = size
