extends SceneTree
## FEEL-AC Artefakt-Tool (KEIN Test — kein test_-Präfix): rendert die
## Review-Artefakte der inszenierten Gefühle + des Post-FX-Stapels.
##  Teil "screens" (Default):
##   1. Alle 12 Emotionen als Nahaufnahme (Gesicht groß, Symbol sichtbar).
##   2. Post-FX an/aus im ECHTEN Wohnzimmer (gleiche Szene, eigene Kamera)
##      + Kosten-Messung (Draw-Calls/Frame-Zeit je Stufe aus/dezent/hoch).
##  Teil "clip" (FEELAC_TEIL=clip, MIT --fixed-fps 30 starten!):
##   3. Schreck-Moment als Frame-Folge für einen kurzen Clip (ffmpeg, 30 fps).
## Aufruf:
##   xvfb-run -a godot --path GOOBY-GODOT --rendering-method gl_compatibility \
##     --rendering-driver opengl3 --audio-driver Dummy \
##     --script res://tests/unit/feelac_screens.gd
##   FEELAC_TEIL=clip xvfb-run -a godot --path GOOBY-GODOT ... --fixed-fps 30 \
##     --script res://tests/unit/feelac_screens.gd

const OUT_DIR := "/tmp/gooby-godot/artifacts/FEELAC"
const FRAMES_DIR := OUT_DIR + "/frames_schreck"
const PORTRAIT := Vector2i(720, 1160)
const QUER := Vector2i(1280, 720)

const GameStateScript := preload("res://scripts/state/game_state.gd")
const WOHNZIMMER_SZENE := "res://scenes/home/wohnzimmer.tscn"

var _rig: GoobyRig = null
var _layer: GoobyFeelings = null
var _stage: Array[Node] = []
var _fx: PostFx = null
var _stub := SettingsStub.new()


class SettingsStub:
	extends RefCounted
	var post_fx := "dezent"

	func value_of(key: String) -> Variant:
		if key == "graphics.post_fx":
			return post_fx
		return ""

	func is_reduced_motion() -> bool:
		return false


func _initialize() -> void:
	_run()


func _run() -> void:
	await process_frame
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_fx = PostFx.get_or_create(root)
	await process_frame
	_fx.settings_override = _stub
	_fx.reduced_motion_override = 0
	_fx.refresh()
	_fx.set_tageszeit(13.0)
	var teil := OS.get_environment("FEELAC_TEIL")
	if teil == "clip":
		await _schreck_clip_frames()
	elif teil == "vergleich":
		await _postfx_vergleich_im_wohnzimmer()
	else:
		await _emotions_nahaufnahmen()
		await _postfx_vergleich_im_wohnzimmer()
	print("FEELAC-Artefakte fertig -> %s" % OUT_DIR)
	quit(0)


# ── 1) 12 Emotionen als Nahaufnahme ──────────────────────────────────────────


func _emotions_nahaufnahmen() -> void:
	DisplayServer.window_set_size(PORTRAIT)
	root.size = PORTRAIT
	# Rahmen: Gesicht (~0,45–0,95 m) UND Symbol (~1,1–1,65 m) gemeinsam groß;
	# Abstand 1,72 m lässt auch geduckten (schreck) und gestreckten (stolz)
	# Posen den Mund im Bild.
	await _build_stage(Vector3(0.0, 1.0, 1.72), Vector3(0.0, 1.0, 0.0), 46.0)
	var index := 0
	for id in FeelEmotions.alle():
		index += 1
		_layer.zeige(id)
		# Unter llvmpipe laufen Frames langsamer als Echtzeit — Restdauer
		# einfrieren, damit der Shot die VOLLE Inszenierung erwischt.
		_layer._rest_s = 999.0
		await _settle(45)
		await _shot("emotion_%02d_%s.png" % [index, id])
		_layer.beende()
		await _settle(30)
	_clear_stage()


# ── 2) Schreck-Moment als Frame-Folge (Video via ffmpeg, --fixed-fps 30) ────


func _schreck_clip_frames() -> void:
	DirAccess.make_dir_recursive_absolute(FRAMES_DIR)
	DisplayServer.window_set_size(QUER)
	root.size = QUER
	# Im ECHTEN Wohnzimmer filmen — kontrolliertes Innenlicht, kein
	# ausgewaschener Studio-Hintergrund unter Stufe "hoch".
	var dir := "user://feelac_clip/%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	var scene: PackedScene = load(WOHNZIMMER_SZENE)
	var room: Node = scene.instantiate()
	room.set("game_state_override", gs)
	room.set("stunde_override", 19.0)
	root.add_child(room)
	await _settle(80)
	var gooby: Node3D = room.gooby()
	gooby.set_wander_enabled(false)
	var buehne := _offene_buehne(room.grid)
	gooby.position = buehne["pos"]
	await _settle(5)
	var ziel: Vector3 = gooby.global_position
	var camera := Camera3D.new()
	root.add_child(camera)
	# Kamera entlang der FREIEN Diagonale (nichts verdeckt Gooby); er dreht
	# sich zur Kamera (Rig-Vorwärts = +Z, s. gooby_home walk). Blick auf
	# 0,8 m Höhe: Gesicht UND Emote-Symbol (~1,4 m) bleiben im Bild.
	var cam_dir: Vector3 = buehne["dir"]
	var cam_pos: Vector3 = ziel + cam_dir * 1.9 + Vector3(0.0, 0.95, 0.0)
	camera.look_at_from_position(cam_pos, ziel + Vector3(0.0, 0.85, 0.0))
	camera.fov = 50.0
	camera.current = true
	gooby.rig.rotation.y = atan2(cam_dir.x, cam_dir.z)
	_stub.post_fx = "hoch"
	_fx.refresh()
	_fx.set_tageszeit(19.0)
	var layer := GoobyFeelings.attach_to(gooby.rig)
	layer.reduced_motion_override = 0
	layer.regie().reduced_motion_override = 0
	layer.regie().reset_cooldown()
	await _settle(5)
	var frame := 0
	for i in 160:
		await process_frame
		if i == 30:
			layer.zeige("schreck")
		var image := root.get_texture().get_image()
		image.save_png("%s/f%08d.png" % [FRAMES_DIR, frame])
		frame += 1
	Engine.time_scale = 1.0
	camera.queue_free()
	room.queue_free()
	await _settle(2)
	gs.free()
	print("clip frames: %d -> %s" % [frame, FRAMES_DIR])


# ── 3) Post-FX an/aus im echten Wohnzimmer + Kosten ──────────────────────────


func _postfx_vergleich_im_wohnzimmer() -> void:
	DisplayServer.window_set_size(QUER)
	root.size = QUER
	var dir := "user://feelac_shots/%d" % Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	var scene: PackedScene = load(WOHNZIMMER_SZENE)
	var room: Node = scene.instantiate()
	room.set("game_state_override", gs)
	room.set("stunde_override", 19.0)
	root.add_child(room)
	await _settle(80)
	var gooby: Node3D = room.gooby()
	if gooby != null and gooby.has_method("set_wander_enabled"):
		gooby.set_wander_enabled(false)
		# Zurück auf die freie Zelle nahe der Raummitte (Spawn-Logik) — beim
		# Herumstreunen landet die Vergleichs-Kamera sonst in einem Möbel.
		gooby.position = _freie_mitte(room.grid)
	# Eigene Kamera auf Augenhöhe — die Raum-Kamera schaut durch die
	# Deckenbalken von oben, das taugt nicht für den Vergleich.
	var ziel := gooby.global_position if gooby != null else Vector3.ZERO
	var camera := Camera3D.new()
	root.add_child(camera)
	var cam_pos := ziel + Vector3(1.6, 1.0, 2.1)
	camera.look_at_from_position(cam_pos, ziel + Vector3(0.0, 0.55, 0.0))
	camera.fov = 55.0
	camera.current = true
	await _settle(5)
	_stub.post_fx = "aus"
	_fx.refresh()
	await _settle(20)
	await _shot("postfx_aus_wohnzimmer_19h.png")
	await _messe("aus")
	_stub.post_fx = "dezent"
	_fx.refresh()
	_fx.set_tageszeit(19.0)
	await _settle(20)
	await _messe("dezent")
	_stub.post_fx = "hoch"
	_fx.refresh()
	_fx.set_tageszeit(19.0)
	_fx.set_stimmung(85.0)
	await _settle(20)
	await _shot("postfx_an_hoch_wohnzimmer_19h.png")
	await _messe("hoch")
	# Puls SOFORT schießen — unter llvmpipe ist ein Frame ~0,3 s, der Puls
	# wäre nach 3 Frames schon abgeklungen.
	_fx.emotions_puls(FeelEmotions.farbe("schreck"), 1.0)
	await _shot("postfx_emotions_puls.png")
	await _settle(30)
	camera.queue_free()
	room.queue_free()
	await _settle(2)
	gs.free()


## Kosten je Stufe: Draw-Calls + Frame-Zeit über 60 Frames gemittelt.
func _messe(level: String) -> void:
	var draw_sum := 0.0
	var ms_sum := 0.0
	var draw_max := 0
	for _i in 60:
		await process_frame
		var messung := _fx.messung()
		draw_sum += float(messung["draw_calls"])
		draw_max = maxi(draw_max, int(messung["draw_calls"]))
		ms_sum += float(messung["frame_ms"])
	print(
		(
			"PERF post_fx=%s: draw_calls_avg=%.1f draw_calls_max=%d frame_ms_avg=%.2f"
			% [level, draw_sum / 60.0, draw_max, ms_sum / 60.0]
		)
	)


## Offenste freie Zelle (max. Abstand zum nächsten Möbel, Tie-Break nah an
## der Mitte) + freie Kamera-Diagonale: Gooby steht sichtbar, nichts verdeckt
## den Schreck-Moment hinter einer Sofalehne.
func _offene_buehne(grid: Variant) -> Dictionary:
	var free: Array = grid.free_cells()
	var belegt: Array[Vector2i] = []
	for x: int in grid.size.x:
		for y: int in grid.size.y:
			var cell := Vector2i(x, y)
			if not free.has(cell):
				belegt.append(cell)
	var center := Vector2(grid.size.x, grid.size.y) * 0.5
	var best: Vector2i = free[0] if not free.is_empty() else Vector2i(6, 5)
	var best_score := -1e9
	for cell: Vector2i in free:
		var min_d := 1e9
		for b: Vector2i in belegt:
			min_d = minf(min_d, Vector2(cell - b).length())
		var score: float = min_d - (Vector2(cell) - center).length() * 0.15
		if score > best_score:
			best_score = score
			best = cell
	var best_dir := Vector2i(1, 1)
	var best_frei := -1
	for dir: Vector2i in [Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var frei := 0
		for schritt in range(1, 5):
			if free.has(best + dir * schritt):
				frei += 1
			else:
				break
		if frei > best_frei:
			best_frei = frei
			best_dir = dir
	var dir3 := Vector3(float(best_dir.x), 0.0, float(best_dir.y)).normalized()
	return {"pos": GridData.world_center(best, Vector2i.ONE, 0), "dir": dir3}


## Freie Grid-Zelle möglichst nah an der Raummitte (wie room_base._spawn_gooby).
func _freie_mitte(grid: Variant) -> Vector3:
	var center := Vector2i(grid.size.x / 2, grid.size.y / 2)
	var free: Array = grid.free_cells()
	var best: Vector2i = center
	if not free.is_empty():
		free.sort_custom(
			func(a: Vector2i, b: Vector2i) -> bool:
				return (a - center).length_squared() < (b - center).length_squared()
		)
		best = free[0]
	return GridData.world_center(best, Vector2i.ONE, 0)


# ── Bühne / Helfer ───────────────────────────────────────────────────────────


func _build_stage(cam_pos: Vector3, cam_ziel: Vector3, fov: float) -> void:
	var camera := Camera3D.new()
	camera.position = cam_pos
	camera.look_at_from_position(cam_pos, cam_ziel)
	camera.fov = fov
	root.add_child(camera)
	camera.current = true
	_stage.append(camera)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-38.0, 28.0, 0.0)
	sun.light_energy = 1.15
	root.add_child(sun)
	_stage.append(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-12.0, -140.0, 0.0)
	fill.light_energy = 0.45
	root.add_child(fill)
	_stage.append(fill)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#cfe8f7")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#f2ead9")
	env.ambient_light_energy = 0.85
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	root.add_child(world_env)
	_stage.append(world_env)
	_rig = GoobyRig.new()
	root.add_child(_rig)
	_stage.append(_rig)
	_fx.refresh()
	await _settle(6)
	_rig.play_clip("idle")
	_layer = GoobyFeelings.attach_to(_rig)
	_layer.reduced_motion_override = 0
	_layer.regie().reduced_motion_override = 1
	await _settle(4)


func _clear_stage() -> void:
	for node in _stage:
		node.queue_free()
	_stage = []
	_rig = null
	_layer = null


func _settle(frames: int) -> void:
	for _i in frames:
		await process_frame


func _shot(file: String) -> void:
	await process_frame
	var image := root.get_texture().get_image()
	image.save_png("%s/%s" % [OUT_DIR, file])
	print("shot: %s" % file)
