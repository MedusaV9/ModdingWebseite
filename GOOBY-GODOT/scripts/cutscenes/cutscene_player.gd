class_name CutscenePlayer
extends Node3D
## Datengetriebener Cutscene-Player (FIX-4) — spielt CutsceneLib-Skripte in
## einem Raum (RoomBase-artiger Host) ab: Kamerafahrten, Rig-Clips, Props,
## Captions, Blenden, Letterbox und Musik/Stinger über den MusicDirector.
## Muster DeliveryCutscene: als Kind an den Raum hängen, `spielen()` awaiten.
##
##   var player := CutscenePlayer.play_in_room(room, gs, "wake_morning")
##   await player.finished_signal_or_spielen…
##
## Überspringbar (Chip oben rechts + Tap nach kurzer Schonfrist): ab dann
## laufen alle restlichen Schritte im Schnelldurchlauf, damit der Endzustand
## IDENTISCH zum voll angesehenen Ablauf ist (Web keepOnSkip-Idee).
## Headless-/testsicher: ohne Gooby/Kamera degradieren Ops zu No-ops;
## time_scale beschleunigt Testläufe.

signal finished(skipped: bool)

const SKIP_GRACE_S := 0.8
const LETTERBOX_RATIO := 0.11
const FAST_STEP_S := 0.03
## Overlay-Ebene; Spiel-UI (HUD-CanvasLayer darunter) wird fürs Kino versteckt.
const OVERLAY_LAYER := 90

## Test-Hebel: 1.0 = Echtzeit; Tests setzen z. B. 20.0.
var time_scale := 1.0

var _room: Node
var _def: Dictionary = {}
var _skip := false
var _props: Dictionary = {}
var _overlay: CanvasLayer
var _fade_rect: ColorRect
var _bar_top: ColorRect
var _bar_bottom: ColorRect
var _caption: Label
var _skip_button: Button
var _catcher: Control
var _cam_saved := {}
var _started_at_ms := 0
var _hidden_layers: Array = []


## Cutscene an einen Raum hängen und starten (null bei unbekannter Id).
static func play_in_room(room: Node, _gs: Object, id: String) -> CutscenePlayer:
	var def := CutsceneLib.get_cutscene(id)
	if def.is_empty():
		push_warning("[cutscene] unbekannte Cutscene '%s'" % id)
		return null
	var player := CutscenePlayer.new()
	player.name = "Cutscene_%s" % id
	player._def = def
	player._room = room
	room.add_child(player)
	return player


## Komplette Cutscene abspielen (awaitbar). Räumt sich selbst auf.
func spielen() -> void:
	_started_at_ms = Time.get_ticks_msec()
	var gooby := _gooby()
	if gooby != null and gooby.has_method("set_wander_enabled"):
		gooby.set_wander_enabled(false)
	_build_overlay()
	var steps: Array = _def.get("steps", [])
	for step: Variant in steps:
		if step is Dictionary:
			await _run_step(step)
	_teardown()
	if gooby != null and gooby.has_method("set_wander_enabled"):
		gooby.set_wander_enabled(true)
	finished.emit(_skip)
	queue_free()


func ueberspringen() -> void:
	_skip = true


func is_skipped() -> bool:
	return _skip


# ── Step-Dispatch ─────────────────────────────────────────────────────────────


func _run_step(step: Dictionary) -> void:
	match str(step.get("op", "")):
		"wait":
			await _wait(float(step.get("duration", 0.5)))
		"fade":
			await _op_fade(step)
		"letterbox":
			_op_letterbox(bool(step.get("on", true)))
		"caption":
			_op_caption(I18nService.t(str(step.get("key", ""))))
		"caption_clear":
			_op_caption("")
		"camera":
			await _op_camera(step)
		"clip":
			_op_clip(str(step.get("clip", "")))
		"emotion":
			_op_emotion(str(step.get("emotion", "")))
		"walk":
			await _op_walk(step)
		"place_gooby":
			_op_place_gooby(step)
		"prop":
			await _op_prop(step)
		"sfx":
			AudioDirector.try_play(self, str(step.get("id", "")), float(step.get("pitch", 1.0)))
		"music":
			_op_music(step)
		"stinger":
			_op_stinger(str(step.get("track", "")))
		"parallel":
			await _op_parallel(step.get("steps", []))
		_:
			push_warning("[cutscene] op '%s' übersprungen." % step.get("op"))


func _op_parallel(steps: Variant) -> void:
	if not (steps is Array) or (steps as Array).is_empty():
		return
	var state := {"open": (steps as Array).size()}
	for step: Variant in steps:
		_run_branch(step, state)
	while int(state["open"]) > 0:
		await get_tree().process_frame


func _run_branch(step: Variant, state: Dictionary) -> void:
	if step is Dictionary:
		await _run_step(step)
	state["open"] = int(state["open"]) - 1


# ── Ops ───────────────────────────────────────────────────────────────────────


func _op_fade(step: Dictionary) -> void:
	if _fade_rect == null:
		return
	var target := clampf(float(step.get("to", 0.0)), 0.0, 1.0)
	var dur := _dur(float(step.get("duration", 0.5)))
	var tween := create_tween()
	tween.tween_property(_fade_rect, "modulate:a", target, dur)
	await tween.finished


func _op_letterbox(on: bool) -> void:
	if _bar_top == null:
		return
	var height := LETTERBOX_RATIO if on else 0.0
	for bar_data: Array in [[_bar_top, 0.0, height], [_bar_bottom, 1.0 - height, 1.0]]:
		var bar: ColorRect = bar_data[0]
		var tween := create_tween()
		tween.tween_property(bar, "anchor_top", float(bar_data[1]), _dur(0.4))
		tween.parallel().tween_property(bar, "anchor_bottom", float(bar_data[2]), _dur(0.4))


func _op_caption(text: String) -> void:
	if _caption != null:
		_caption.text = text
		_caption.visible = not text.is_empty()


func _op_camera(step: Dictionary) -> void:
	var rig := _camera_rig()
	if rig == null or rig.camera == null:
		await _wait(float(step.get("duration", 0.0)) * 0.5)
		return
	var cam: Camera3D = rig.camera
	var dur := _dur(float(step.get("duration", 1.2)))
	match str(step.get("move", "")):
		"fly":
			_freeze_rig(rig)
			var pos := _resolve_pos(step.get("pos", []), Vector3(0, 4, 6))
			var look := _resolve_pos(step.get("look", []), Vector3.ZERO)
			if step.has("fov"):
				cam.fov = float(step["fov"])
			await _fly_camera(cam, pos, look, dur)
		"push_in":
			_freeze_rig(rig)
			var target := _gooby_pos() + Vector3(0.0, 0.55, 0.0)
			var pos_in := cam.global_position.lerp(target, 0.35) + Vector3(0.0, 0.15, 0.0)
			await _fly_camera(cam, pos_in, target, dur)
		"restore":
			_restore_rig(rig)
			await _wait(dur * 0.5)


func _fly_camera(cam: Camera3D, pos: Vector3, look: Vector3, dur: float) -> void:
	var from := cam.global_position
	var step_fn := func(t: float) -> void:
		cam.global_position = from.lerp(pos, t)
		if cam.global_position.distance_to(look) > 0.05:
			cam.look_at(look, Vector3.UP)
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.tween_method(step_fn, 0.0, 1.0, maxf(0.05, dur))
	await tween.finished


func _freeze_rig(rig: Node) -> void:
	if _cam_saved.is_empty():
		_cam_saved = {
			"follow": rig.get("follow_target"),
			"fov": rig.camera.fov if rig.get("camera") != null else 45.0,
		}
	rig.set_process(false)
	rig.set("follow_target", null)


func _restore_rig(rig: Node) -> void:
	if not _cam_saved.is_empty():
		rig.set("follow_target", _cam_saved.get("follow"))
		if rig.get("camera") != null:
			rig.camera.fov = float(_cam_saved.get("fov", 45.0))
		_cam_saved = {}
	rig.set_process(true)


func _op_clip(clip: String) -> void:
	var gooby := _gooby()
	if gooby != null and gooby.has_method("play_clip"):
		gooby.play_clip(clip)


func _op_emotion(emotion: String) -> void:
	var gooby := _gooby()
	if gooby != null and gooby.get("rig") != null:
		gooby.rig.set_emotion(emotion)


func _op_walk(step: Dictionary) -> void:
	var gooby := _gooby()
	var ziel := _resolve_pos(step.get("to", []), _gooby_pos())
	if gooby == null or not gooby.has_method("walk_to"):
		await _wait(0.3)
		return
	if _skip:
		gooby.global_position = ziel
		return
	await gooby.walk_to(ziel, float(step.get("timeout", 5.0)) / time_scale)
	if gooby.global_position.distance_to(ziel) > 0.8:
		gooby.global_position = ziel


func _op_place_gooby(step: Dictionary) -> void:
	var gooby := _gooby()
	if gooby == null:
		return
	gooby.global_position = _resolve_pos(step.get("at", []), _gooby_pos())
	if step.has("face_deg"):
		gooby.rotation.y = deg_to_rad(float(step["face_deg"]))


func _op_prop(step: Dictionary) -> void:
	var id := str(step.get("id", ""))
	match str(step.get("action", "")):
		"spawn":
			_prop_despawn(id)
			var prop := _prop_modell(str(step.get("glb", "")))
			prop.name = "Prop_%s" % id
			prop.position = _resolve_pos(step.get("at", []), Vector3.ZERO)
			prop.rotation.y = deg_to_rad(float(step.get("rot_deg", 0.0)))
			prop.scale = Vector3.ONE * float(step.get("scale", 1.0))
			add_child(prop)
			_props[id] = prop
		"glide":
			var prop: Node3D = _props.get(id)
			if prop == null:
				return
			var ziel := _resolve_pos(step.get("to", []), prop.position)
			if _skip:
				prop.position = ziel
				return
			var tween := create_tween()
			tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tween.tween_property(prop, "position", ziel, _dur(float(step.get("duration", 1.5))))
			await tween.finished
		"despawn":
			_prop_despawn(id)


func _prop_despawn(id: String) -> void:
	var prop: Node3D = _props.get(id)
	if prop != null and is_instance_valid(prop):
		prop.queue_free()
	_props.erase(id)


func _prop_modell(glb: String) -> Node3D:
	if not glb.is_empty() and ResourceLoader.exists(glb):
		var scene: Variant = load(glb)
		if scene is PackedScene:
			var wurzel := Node3D.new()
			wurzel.add_child((scene as PackedScene).instantiate())
			return wurzel
	# Fallback: weiche Kiste, damit die Szene auch ohne GLB liest.
	var box := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.6, 0.5, 0.6)
	box.mesh = mesh
	box.position.y = 0.25
	var wrap := Node3D.new()
	wrap.add_child(box)
	return wrap


func _op_music(step: Dictionary) -> void:
	if not is_inside_tree():
		return
	var music := MusicDirector.get_or_create(self)
	if bool(step.get("stop", false)):
		music.stop_music(float(step.get("fade", MusicDirector.CROSSFADE_S)))
	elif step.has("context"):
		music.set_context(str(step["context"]))
	elif step.has("track"):
		music.play_track(str(step["track"]), float(step.get("fade", 1.0)))


func _op_stinger(track: String) -> void:
	if is_inside_tree():
		MusicDirector.get_or_create(self).play_stinger(track)


# ── Overlay (Letterbox/Caption/Skip/Fade) ─────────────────────────────────────


func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.layer = OVERLAY_LAYER
	add_child(_overlay)
	_hide_game_ui()
	_catcher = Control.new()
	_catcher.set_anchors_preset(Control.PRESET_FULL_RECT)
	_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_catcher.gui_input.connect(_on_catcher_input)
	_overlay.add_child(_catcher)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color.BLACK
	_fade_rect.modulate.a = 0.0
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_fade_rect)
	_bar_top = _letterbox_bar()
	_bar_top.anchor_bottom = 0.0
	_overlay.add_child(_bar_top)
	_bar_bottom = _letterbox_bar()
	_bar_bottom.anchor_top = 1.0
	_overlay.add_child(_bar_bottom)
	_caption = Label.new()
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_caption.offset_top = -96.0
	_caption.offset_bottom = -40.0
	_caption.add_theme_font_size_override("font_size", 26)
	_caption.add_theme_color_override("font_color", Color.WHITE)
	_caption.add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.06, 0.9))
	_caption.add_theme_constant_override("outline_size", 8)
	_caption.visible = false
	_caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(_caption)
	_skip_button = Button.new()
	_skip_button.text = I18nService.t("cutscene.ueberspringen")
	_skip_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skip_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_skip_button.offset_top = 16.0
	_skip_button.offset_right = -16.0
	_skip_button.pressed.connect(ueberspringen)
	_overlay.add_child(_skip_button)


func _letterbox_bar() -> ColorRect:
	var bar := ColorRect.new()
	bar.color = Color(0.05, 0.04, 0.05)
	bar.set_anchors_preset(Control.PRESET_FULL_RECT)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return bar


func _on_catcher_input(event: InputEvent) -> void:
	var pressed: bool = event is InputEventMouseButton and event.is_pressed()
	var touched: bool = event is InputEventScreenTouch and event.is_pressed()
	if not (pressed or touched):
		return
	if Time.get_ticks_msec() - _started_at_ms >= int(SKIP_GRACE_S * 1000.0):
		ueberspringen()


func _teardown() -> void:
	for id: String in _props.keys():
		_prop_despawn(id)
	var rig := _camera_rig()
	if rig != null and not _cam_saved.is_empty():
		_restore_rig(rig)
	_restore_game_ui()
	if _overlay != null and is_instance_valid(_overlay):
		_overlay.queue_free()
		_overlay = null


## HUD & Co. fürs Kino ausblenden — nur sichtbare CanvasLayer UNTER der
## Overlay-Ebene; _restore_game_ui stellt exakt diese wieder her.
func _hide_game_ui() -> void:
	if not is_inside_tree():
		return
	for node: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var canvas := node as CanvasLayer
		if canvas == null or canvas == _overlay or not canvas.visible:
			continue
		if canvas.layer >= OVERLAY_LAYER:
			continue
		canvas.visible = false
		_hidden_layers.append(canvas)


func _restore_game_ui() -> void:
	for canvas: Variant in _hidden_layers:
		if is_instance_valid(canvas):
			canvas.visible = true
	_hidden_layers.clear()


# ── Helfer ────────────────────────────────────────────────────────────────────


func _wait(seconds: float) -> void:
	var dauer := FAST_STEP_S if _skip else maxf(0.01, seconds / time_scale)
	if not is_inside_tree():
		return
	await get_tree().create_timer(dauer).timeout


func _dur(seconds: float) -> float:
	return FAST_STEP_S if _skip else maxf(0.05, seconds / time_scale)


func _gooby() -> Node3D:
	if _room != null and _room.has_method("gooby"):
		return _room.gooby()
	return null


func _gooby_pos() -> Vector3:
	var gooby := _gooby()
	return gooby.global_position if gooby != null else Vector3.ZERO


func _camera_rig() -> Node:
	if _room != null and _room.has_method("camera_rig"):
		return _room.camera_rig()
	return null


## [x,z] | [x,y,z] | {"anchor": ..., "offset": [dx,dy,dz]} → Weltposition.
func _resolve_pos(raw: Variant, fallback: Vector3) -> Vector3:
	if raw is Array:
		var arr: Array = raw
		if arr.size() == 2:
			return Vector3(float(arr[0]), 0.0, float(arr[1]))
		if arr.size() >= 3:
			return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
		return fallback
	if raw is Dictionary:
		var base := _anchor_pos(str((raw as Dictionary).get("anchor", "center")))
		var off: Variant = (raw as Dictionary).get("offset", [])
		if off is Array and (off as Array).size() >= 3:
			base += Vector3(float(off[0]), float(off[1]), float(off[2]))
		elif off is Array and (off as Array).size() == 2:
			base += Vector3(float(off[0]), 0.0, float(off[1]))
		return base
	return fallback


func _anchor_pos(anchor: String) -> Vector3:
	match anchor:
		"gooby":
			return _gooby_pos()
		"entry":
			var size := _room_world_size()
			return Vector3(size.x * 0.5, 0.0, 0.9)
		_:
			var mitte := _room_world_size()
			return Vector3(mitte.x * 0.5, 0.0, mitte.y * 0.5)


func _room_world_size() -> Vector2:
	if _room != null and _room.has_method("room_def"):
		var grid: Variant = _room.room_def().get("grid", Vector2i(12, 10))
		if grid is Vector2i:
			var cells: Vector2i = grid
			return Vector2(cells.x, cells.y) * GridData.CELL_SIZE
	return Vector2(6.0, 5.0)
