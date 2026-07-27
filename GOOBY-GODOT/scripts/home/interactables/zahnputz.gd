class_name Zahnputz
extends Node3D
## Zahnputz-Interactable (W3d CONTENT, Doc F §3.2 „Zähneputzen-Pflicht“):
## nach dem Aufwachen setzt BadState.mark_woke_up() die Pflicht — Gooby
## wartet dann am Waschbecken (Warte-Pose). Tap aufs Becken startet die
## Rubbel-Mini-Interaktion (5 s Coverage-Geste), Abschluss: brush_teeth-Clip,
## Schaum-Sparkle, Buff „frische_zaehne“ + teeth_brushed-Counter (Sticker!).
## Zahnbürsten-Bruch-Chance kommt aus der W2b-Balance
## (`zahnbuersten_bruch_chance`).

var _host: InteractablesHost
var _rng := RandomNumberGenerator.new()
var _overlay: RubOverlay
var _busy := false
var _waiting_pose_done := false


func setup(host: InteractablesHost, furniture: Node3D) -> void:
	_host = host
	_rng.randomize()
	add_child(InteractablesHost.make_tap_area(furniture, _on_tapped))


func _process(_delta: float) -> void:
	if _busy or _waiting_pose_done:
		return
	var gs := _host.game_state()
	if gs == null or not BadState.needs_brushing(gs):
		return
	_waiting_pose_done = true
	_take_waiting_pose()


## Gooby stellt sich ans Waschbecken und tippelt wartend (Warte-Pose M1).
func _take_waiting_pose() -> void:
	var gooby := _gooby()
	if gooby == null:
		return
	gooby.set_wander_enabled(false)
	await gooby.walk_to(global_position + Vector3(0.0, 0.0, 0.7), 5.0)
	gooby.play_clip("idle_lookaround")
	_say("bad.zahnputz.warte")


func _on_tapped() -> void:
	if _busy or _room_busy():
		return
	_busy = true
	_start_rub_game()


func _start_rub_game() -> void:
	var gooby := _gooby()
	if gooby != null:
		gooby.set_wander_enabled(false)
		await gooby.walk_to(global_position + Vector3(0.0, 0.0, 0.7), 5.0)
		if "rig" in gooby and gooby.rig != null:
			gooby.rig.play_clip("brush_teeth")
	_overlay = RubOverlay.new()
	_overlay.target_seconds = BadState.BRUSH_RUB_S
	_overlay.finished.connect(_on_rub_finished)
	# Theme explizit setzen: Window-Theme propagiert NICHT durch CanvasLayer.
	_overlay.theme = ThemeService.theme()
	_ui_layer().add_child(_overlay)


func _on_rub_finished() -> void:
	_overlay.queue_free()
	_overlay = null
	var broke := BadState.brush_breaks(_rng.randf(), BadState.brush_break_chance())
	var gs := _host.game_state()
	if gs != null:
		BadState.mark_brushed(gs, broke)
		GoobyBuffs.grant(gs, "frische_zaehne", "hygiene", 10.0, 3.0, _now_ms())
	var gooby := _gooby()
	if gooby != null:
		gooby.play_clip("hop")
		gooby.set_wander_enabled(true)
	# EF-1/EVAL-1 D6: Pflege meldet sichtbar+hörbar zurück („+10“-Float für
	# den frische_zaehne-Buff, Glitzer, Pluck) — vorher nur eine Textzeile.
	AudioDirector.try_play(self, "ui_sticker")
	_show_care_reward(gooby, 10)
	_say("bad.zahnputz.bruch" if broke else "bad.zahnputz.fertig")
	_waiting_pose_done = false
	_busy = false


func is_busy() -> bool:
	return _busy


## Pflege-Belohnung (EF-1, EVAL-1 D6): „+{n}“-Float + Glitzer über Gooby.
func _show_care_reward(gooby: Node, betrag: int) -> void:
	var room := _host.room()
	if room == null:
		return
	var pos: Vector3 = global_position + Vector3(0.0, 1.0, 0.4)
	if gooby is Node3D:
		pos = (gooby as Node3D).global_position + Vector3(0.0, 0.9, 0.0)
	RewardFx.pflege_reward(room, pos, betrag)


func _gooby() -> Node:
	var room := _host.room()
	if room != null and room.has_method("gooby"):
		return room.gooby()
	return null


func _say(key: String) -> void:
	var room := _host.room()
	if room != null and room.has_method("say"):
		room.say(I18nService.t(key))


func _room_busy() -> bool:
	var room := _host.room()
	return room != null and room.has_method("is_build_mode_active") and room.is_build_mode_active()


func _now_ms() -> int:
	var gs := _host.game_state()
	if gs != null and "clock" in gs:
		return int(gs.clock.now_ms())
	return int(Time.get_unix_time_from_system() * 1000.0)


func _ui_layer() -> CanvasLayer:
	var existing := _host.get_node_or_null("W3dUiLayer")
	if existing is CanvasLayer:
		return existing
	var layer := CanvasLayer.new()
	layer.name = "W3dUiLayer"
	layer.layer = 6
	_host.add_child(layer)
	return layer


class RubOverlay:
	extends Control
	## Rubbel-Geste (Coverage-Logik light): solange der Finger/die Maus
	## GEDRÜCKT über den Screen rubbelt, füllt sich der Fortschritt —
	## `target_seconds` Rubbelzeit lösen `finished` aus.

	signal finished

	var target_seconds := 5.0
	var progress := 0.0

	var _rubbing := false
	var _bar: ProgressBar

	func _ready() -> void:
		# _ready läuft NACH dem Einhängen → set_anchors_preset würde den
		# 0-Rect konservieren; Offsets explizit mitsetzen.
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		var hint := Label.new()
		hint.theme_type_variation = &"HeadlineLabel"
		hint.text = I18nService.t("bad.zahnputz.rubbel")
		hint.set_anchors_preset(Control.PRESET_CENTER_TOP)
		hint.grow_horizontal = Control.GROW_DIRECTION_BOTH
		hint.position.y = 40.0
		add_child(hint)
		_bar = ProgressBar.new()
		_bar.max_value = 1.0
		_bar.show_percentage = false
		_bar.custom_minimum_size = Vector2(320, 18)
		_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
		_bar.position.y = -60.0
		add_child(_bar)

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			_rubbing = event.pressed
		elif event is InputEventScreenTouch:
			_rubbing = event.pressed
		elif event is InputEventMouseMotion and _rubbing:
			_advance(0.016)
		elif event is InputEventScreenDrag:
			_advance(0.016)

	func _advance(dt: float) -> void:
		progress = minf(1.0, progress + dt / target_seconds)
		if _bar != null:
			_bar.value = progress
		if progress >= 1.0:
			finished.emit()
