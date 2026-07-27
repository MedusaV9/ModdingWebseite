class_name RecapScene
extends Control
## Recap-Kino (FIX-4) — der Rückblick im QUERFORMAT (alter User-Wunsch):
## Gooby steht im 3D-Viewport, die Kamera fährt sanft durch die Stationen
## des Tages/der Woche (die erreichten Orte aus dem GameState), Statzeilen
## poppen auf Takt-Downbeats (Roll-up-Zähler), am Ende Level-Karte mit
## Konfetti. Musik: ein Recap-FM-Track (deterministisch pro Meilenstein),
## Beat-Raster aus der MusicRegistry.
##
## Aufbau komplett in Code (kein .tscn) — headless-/testsicher: ohne
## Renderer degradiert alles zu Labels + Zeitplan; time_scale beschleunigt
## Testläufe. Überspringbar ab skip_after_sec (Web §C-SYS2.2): Tap → Schnitt
## zur Endkarte, die mindestens min_show_sec steht.
##
##   var scene := RecapScene.build(gs)         # oder .build(gs, 0, history_row)
##   parent.add_child(scene)
##   await scene.finished                       # (skipped: bool)

signal finished(skipped: bool)

const SKIP_CUT_S := 0.3
const CAM_RADIUS := 2.6
const CAM_HEIGHT := 1.15
const CAM_LOOK := Vector3(0.0, 0.55, 0.0)
## Fallback, falls recap-fm leer wäre (Web „Recap - Abenteuer“).
const FALLBACK_TRACK := "recap-abenteuer"
## Spiel-UI (HUD-CanvasLayer < dieser Schwelle) wird fürs Kino versteckt.
const UI_HIDE_BELOW := 90

## Test-Hebel: 1.0 = Echtzeit.
var time_scale := 1.0
## true = §C-SYS2.8-Replay aus der History (KEIN complete_recap-Write).
var replay := false

var _gs: Object
var _timeline: Dictionary = {}
var _lines: Array = []
var _cue_index := 0
var _t := 0.0
var _running := false
var _skipped := false
var _ending := false
var _end_since := -1.0
var _advance := false
var _done := false

var _wallpaper: Control
var _viewport: SubViewport
var _rig: Node3D
var _camera: Camera3D
var _cam_from := Vector3.ZERO
var _cam_to := Vector3.ZERO
var _cam_seg_start := 0.0
var _cam_seg_dur := 1.0
var _title: Label
var _station_label: Label
var _stat_labels: Array[Label] = []
var _pops: Array = []
var _end_card: Control
var _confetti: CPUParticles2D
var _skip_button: Button
var _hidden_layers: Array = []


## Recap aus dem Live-State bauen (level 0 = pending/Meilenstein selbst
## bestimmen) oder eine History-Zeile abspielen (§C-SYS2.8 Replay).
static func build(gs: Object, level := 0, history_row: Dictionary = {}) -> RecapScene:
	var scene := RecapScene.new()
	scene.name = "RecapScene"
	scene._gs = gs
	var state := _state_of(gs)
	var slice := RecapEngine.slice_of(state)
	var lines: Array = []
	var recap_level := level
	if not history_row.is_empty():
		scene.replay = true
		lines = history_row.get("stats", []) if history_row.get("stats") is Array else []
		recap_level = int(history_row.get("level", level))
	else:
		var now_ms := float(Time.get_unix_time_from_system() * 1000.0)
		lines = RecapEngine.select_lines(RecapEngine.diff(slice["baseline"], state, now_ms))
		if recap_level <= 0:
			recap_level = int(slice["pendingLevel"])
		if recap_level <= 0:
			var prog: Variant = state.get("progression")
			var lvl := int((prog as Dictionary).get("level", 1)) if prog is Dictionary else 1
			recap_level = RecapEngine.highest_milestone(maxi(1, lvl))
	scene._lines = lines
	var seed_value := recap_level * 31 + int(slice["baselineAt"]) % 100000
	var track := RecapDirector.pick_track(MusicRegistry.station_track_ids("recap-fm"), seed_value)
	if track.is_empty():
		track = FALLBACK_TRACK
	var entry := MusicRegistry.entry(track)
	scene._timeline = (
		RecapDirector
		. build_timeline(
			{
				"beats": MusicRegistry.beat_grid(track),
				"duration_sec": float(entry.get("duration_sec", 100.0)),
				"lines": lines,
				"stations": RecapDirector.stations_for(state),
				"level": recap_level,
				"track_id": track,
			}
		)
	)
	return scene


func timeline() -> Dictionary:
	return _timeline


func is_done() -> bool:
	return _done


func _ready() -> void:
	# WICHTIG: anchors+offsets — set_anchors_preset() allein löst nach
	# add_child (z. B. unter einem CanvasLayer) KEIN Relayout aus → 0×0.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_lock_landscape(true)
	_hide_game_ui()
	_build_background()
	_build_stage()
	_build_ui()
	_start_music()
	gui_input.connect(_on_gui_input)
	_running = true


func _exit_tree() -> void:
	_restore_game_ui()
	_lock_landscape(false)


func _process(delta: float) -> void:
	if not _running:
		return
	_t += delta * time_scale
	_fire_due_cues()
	_animate_camera()
	_animate_pops()
	if _ending and _end_since >= 0.0:
		var shown := _t - _end_since
		var min_show := float(_timeline.get("end_card", {}).get("min_show_sec", 3.0))
		if (_skipped or _advance) and shown >= min_show:
			_finish()
		elif not _skipped and _t >= float(_timeline.get("total_sec", 90.0)):
			_finish()


# ── Cue-Abarbeitung ───────────────────────────────────────────────────────────


func _fire_due_cues() -> void:
	var cues: Array = _timeline.get("cues", [])
	while _cue_index < cues.size():
		var cue: Dictionary = cues[_cue_index]
		if float(cue["t"]) > _t:
			break
		_cue_index += 1
		match str(cue["kind"]):
			"intro":
				_show_intro()
			"cut":
				_show_station(cue)
			"text":
				_show_text(cue)
			"end":
				_show_end_card()


func _show_intro() -> void:
	_title.text = I18nService.t("recap.title", {"level": int(_timeline.get("level", 5))})
	_title.visible = true
	_station_label.visible = false


func _show_station(cue: Dictionary) -> void:
	_title.visible = false
	var station: Dictionary = cue.get("station", {})
	_station_label.text = I18nService.t(str(station.get("label_key", "recap.station.home")))
	_station_label.visible = true
	if _wallpaper != null and _wallpaper.has_method("set_pattern_by_name"):
		_wallpaper.set_pattern_by_name(str(station.get("pattern", "leaves")))
	if _rig != null:
		if _rig.has_method("play_clip"):
			_rig.play_clip(str(station.get("clip", "wave")))
		if _rig.has_method("set_emotion"):
			_rig.set_emotion(str(station.get("emotion", "happy")))
	_begin_camera_move(int(cue.get("vignette", 0)))


func _show_text(cue: Dictionary) -> void:
	var label := _next_stat_label()
	label.text = str(cue.get("text", ""))
	label.visible = true
	var beat := float(_timeline.get("beat_sec", 0.6))
	(
		_pops
		. append(
			{
				"label": label,
				"start": _t,
				"pop_s": float(cue.get("pop_beats", 2)) * beat,
				"rollup_s": float(cue.get("rollup_beats", 2)) * beat,
				"value": int(cue.get("value", 0)),
				"line_id": str(cue.get("line_id", "")),
			}
		)
	)


func _show_end_card() -> void:
	_ending = true
	_end_since = _t
	_station_label.visible = false
	for label in _stat_labels:
		label.visible = false
	_end_card.visible = true
	if _confetti != null:
		_confetti.emitting = true
	if is_inside_tree():
		MusicDirector.get_or_create(self).play_stinger("stinger-levelup")


# ── Skip / Abschluss ──────────────────────────────────────────────────────────


func skip() -> void:
	if _ending or _done:
		return
	if _t < float(_timeline.get("skip_after_sec", 10.0)):
		return
	_skipped = true
	# 300-ms-Schnitt zur Endkarte: alle restlichen Cues verwerfen.
	var cues: Array = _timeline.get("cues", [])
	_cue_index = cues.size()
	_t += SKIP_CUT_S
	_show_end_card()


func _on_gui_input(event: InputEvent) -> void:
	var pressed: bool = event is InputEventMouseButton and event.is_pressed()
	var touched: bool = event is InputEventScreenTouch and event.is_pressed()
	if pressed or touched:
		skip()


func _on_weiter() -> void:
	_advance = true


func _finish() -> void:
	if _done:
		return
	_done = true
	_running = false
	if not replay and _gs != null and _gs.has_method("update"):
		var now_ms := float(Time.get_unix_time_from_system() * 1000.0)
		var played := _lines
		_gs.update(
			func(s: Dictionary) -> void:
				s["recap"] = RecapEngine.complete_recap(s, now_ms, played)["recap"]
				var counters: Variant = s.get("achievements", {}).get("counters")
				if counters is Dictionary:
					counters["recapsSeen"] = int(counters.get("recapsSeen", 0)) + 1
		)
	if is_inside_tree():
		MusicDirector.get_or_create(self).set_context("home")
	finished.emit(_skipped)
	queue_free()


# ── Aufbau ────────────────────────────────────────────────────────────────────


func _build_background() -> void:
	# Animierter Hintergrund (User-Meldung 2): AcWallpaper-Drift-Shader.
	var wallpaper_script: Variant = load("res://scripts/ui/wallpaper.gd")
	if wallpaper_script is GDScript:
		_wallpaper = (wallpaper_script as GDScript).new()
		_wallpaper.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_wallpaper)
	else:
		var rect := ColorRect.new()
		rect.color = Color(0.98, 0.95, 0.87)
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(rect)
		_wallpaper = rect


func _build_stage() -> void:
	var container := SubViewportContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	_viewport = SubViewport.new()
	_viewport.transparent_bg = true
	# Eigene 3D-Welt — sonst teilt der SubViewport die World3D des Root-
	# Viewports und rendert den Home-Raum statt der Recap-Bühne.
	_viewport.own_world_3d = true
	# KEINE manuelle size: der Stretch-Container übernimmt die Größe (REST5).
	container.add_child(_viewport)
	var world := Node3D.new()
	_viewport.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	world.add_child(light)
	var floor_mesh := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 1.6
	disc.bottom_radius = 1.6
	disc.height = 0.05
	floor_mesh.mesh = disc
	floor_mesh.position.y = -0.03
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.85, 0.62)
	floor_mesh.material_override = mat
	world.add_child(floor_mesh)
	var rig_script: Variant = load("res://scripts/character/gooby_rig.gd")
	if rig_script is GDScript:
		_rig = (rig_script as GDScript).new()
		_rig.name = "Gooby"
		world.add_child(_rig)
		if _gs != null and _rig.has_method("apply_saved_morphs"):
			_rig.apply_saved_morphs(_gs)
	_camera = Camera3D.new()
	_camera.position = Vector3(0.0, CAM_HEIGHT, CAM_RADIUS)
	_camera.look_at_from_position(_camera.position, CAM_LOOK, Vector3.UP)
	world.add_child(_camera)
	_camera.current = true
	_cam_from = _camera.position
	_cam_to = _camera.position


func _build_ui() -> void:
	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.set_anchors_preset(Control.PRESET_FULL_RECT)
	_title.add_theme_font_size_override("font_size", 44)
	_title.add_theme_color_override("font_color", Color(0.32, 0.24, 0.16))
	_title.visible = false
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_title)
	_station_label = Label.new()
	_station_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_station_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_station_label.offset_top = 24.0
	_station_label.offset_bottom = 72.0
	_station_label.add_theme_font_size_override("font_size", 30)
	_station_label.add_theme_color_override("font_color", Color(0.32, 0.24, 0.16))
	_station_label.visible = false
	_station_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_station_label)
	for i in 2:
		var stat := Label.new()
		stat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stat.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		stat.offset_top = -170.0 + float(i) * 58.0
		stat.offset_bottom = -120.0 + float(i) * 58.0
		stat.add_theme_font_size_override("font_size", 26)
		stat.add_theme_color_override("font_color", Color(0.25, 0.18, 0.1))
		stat.visible = false
		stat.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(stat)
		_stat_labels.append(stat)
	_build_end_card()
	_skip_button = Button.new()
	_skip_button.text = I18nService.t("recap.ueberspringen")
	_skip_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_skip_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_skip_button.offset_top = 16.0
	_skip_button.offset_right = -16.0
	_skip_button.visible = false
	_skip_button.pressed.connect(skip)
	add_child(_skip_button)


func _build_end_card() -> void:
	_end_card = Control.new()
	_end_card.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_card.visible = false
	_end_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_end_card)
	var headline := Label.new()
	headline.text = I18nService.t("recap.level_headline", {"level": int(_timeline.get("level", 5))})
	headline.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	headline.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	headline.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Oberes Drittel — mittig würde die Headline Gooby verdecken.
	headline.offset_bottom = -440.0
	headline.add_theme_font_size_override("font_size", 52)
	headline.add_theme_color_override("font_color", Color(0.85, 0.5, 0.15))
	_end_card.add_child(headline)
	var weiter := Button.new()
	weiter.text = I18nService.t("recap.weiter")
	weiter.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	weiter.offset_top = -110.0
	weiter.offset_bottom = -60.0
	weiter.offset_left = -90.0
	weiter.offset_right = 90.0
	weiter.pressed.connect(_on_weiter)
	_end_card.add_child(weiter)
	_confetti = CPUParticles2D.new()
	_confetti.emitting = false
	_confetti.one_shot = true
	_confetti.amount = 90
	_confetti.lifetime = 2.2
	_confetti.explosiveness = 0.9
	_confetti.position = Vector2(640.0, 120.0)
	_confetti.direction = Vector2(0.0, 1.0)
	_confetti.spread = 70.0
	_confetti.initial_velocity_min = 180.0
	_confetti.initial_velocity_max = 420.0
	_confetti.gravity = Vector2(0.0, 500.0)
	_confetti.scale_amount_min = 3.0
	_confetti.scale_amount_max = 7.0
	_confetti.color_ramp = _confetti_ramp()
	_end_card.add_child(_confetti)


func _confetti_ramp() -> Gradient:
	var gradient := Gradient.new()
	gradient.set_color(0, Color(1.0, 0.75, 0.25))
	gradient.set_color(1, Color(0.45, 0.75, 1.0))
	gradient.add_point(0.5, Color(0.95, 0.45, 0.6))
	return gradient


# ── Animation ─────────────────────────────────────────────────────────────────


func _begin_camera_move(vignette: int) -> void:
	if _camera == null:
		return
	var angle_a := TAU * float(vignette) / float(RecapEngine.VIGNETTES)
	var angle_b := angle_a + TAU / float(RecapEngine.VIGNETTES) * 0.6
	var radius := CAM_RADIUS + 0.35 * sin(float(vignette) * 1.7)
	var height := CAM_HEIGHT + 0.25 * cos(float(vignette) * 2.3)
	_cam_from = Vector3(sin(angle_a) * radius, height, cos(angle_a) * radius)
	_cam_to = Vector3(sin(angle_b) * radius, height + 0.1, cos(angle_b) * radius)
	_cam_seg_start = _t
	_cam_seg_dur = maxf(1.0, float(_timeline.get("bar_sec", 2.4)) * 2.0)
	_camera.position = _cam_from
	_camera.look_at_from_position(_cam_from, CAM_LOOK, Vector3.UP)


func _animate_camera() -> void:
	if _camera == null or _ending:
		return
	var raw := (_t - _cam_seg_start) / _cam_seg_dur
	var k := clampf(raw, 0.0, 1.0)
	var eased := 0.5 - 0.5 * cos(k * PI)
	_camera.position = _cam_from.lerp(_cam_to, eased)
	_camera.look_at_from_position(_camera.position, CAM_LOOK, Vector3.UP)


func _animate_pops() -> void:
	if _skip_button != null and not _skip_button.visible:
		if _t >= float(_timeline.get("skip_after_sec", 10.0)):
			_skip_button.visible = true
	var keep: Array = []
	for pop: Dictionary in _pops:
		var label: Label = pop["label"]
		var since: float = _t - float(pop["start"])
		var pop_s := maxf(0.05, float(pop["pop_s"]))
		if since < pop_s:
			# Text-Pop 0.8→1.05→1.0 (§C-SYS2.6).
			var k: float = since / pop_s
			var s := lerpf(0.8, 1.05, k / 0.7) if k < 0.7 else lerpf(1.05, 1.0, (k - 0.7) / 0.3)
			label.scale = Vector2(s, s)
			label.pivot_offset = label.size * 0.5
			keep.append(pop)
		elif since < pop_s + maxf(0.05, float(pop["rollup_s"])):
			# Zähler-Roll-up 0→value über rollup_beats.
			label.scale = Vector2.ONE
			var k2: float = (since - pop_s) / maxf(0.05, float(pop["rollup_s"]))
			var shown := int(round(float(pop["value"]) * clampf(k2, 0.0, 1.0)))
			label.text = RecapEngine.format_line(str(pop["line_id"]), shown)
			keep.append(pop)
		else:
			label.scale = Vector2.ONE
			label.text = RecapEngine.format_line(str(pop["line_id"]), int(pop["value"]))
	_pops = keep


func _next_stat_label() -> Label:
	for label in _stat_labels:
		if not label.visible:
			return label
	# Beide belegt → ältesten recyceln.
	var oldest := _stat_labels[0]
	_stat_labels.remove_at(0)
	_stat_labels.append(oldest)
	return oldest


# ── Umgebung ──────────────────────────────────────────────────────────────────


func _start_music() -> void:
	if not is_inside_tree():
		return
	var track := str(_timeline.get("track_id", ""))
	if track.is_empty():
		return
	MusicDirector.get_or_create(self).play_track(track, 0.6, false)


## HUD & Co. fürs Kino ausblenden (CanvasLayer unterhalb der Kino-Ebene);
## _restore_game_ui stellt exakt die versteckten wieder her.
func _hide_game_ui() -> void:
	if not is_inside_tree():
		return
	for node: Node in get_tree().root.find_children("*", "CanvasLayer", true, false):
		var canvas := node as CanvasLayer
		if canvas == null or not canvas.visible:
			continue
		if canvas.layer >= UI_HIDE_BELOW or canvas.is_ancestor_of(self):
			continue
		canvas.visible = false
		_hidden_layers.append(canvas)


func _restore_game_ui() -> void:
	for canvas: Variant in _hidden_layers:
		if is_instance_valid(canvas):
			canvas.visible = true
	_hidden_layers.clear()


func _lock_landscape(on: bool) -> void:
	var service := get_node_or_null("/root/OrientationService")
	if service == null:
		return
	if on and service.has_method("lock"):
		service.lock(1)  # OrientationService.LockMode.LANDSCAPE
	elif not on and service.has_method("unlock"):
		service.unlock()


static func _state_of(gs: Object) -> Dictionary:
	if gs != null and gs.has_method("state"):
		var state: Variant = gs.state()
		if state is Dictionary:
			return state
	return {}
