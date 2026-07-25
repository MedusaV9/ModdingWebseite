class_name MinigameHost
extends Control
## Minigame-Host (Doc G): lädt das Spiel in einen SubViewport (Pillar-/
## Letterbox auf die Ziel-Orientierung), fährt den 3-2-1-Countdown, besitzt
## Pause-Overlay + Results-Screen und bucht den Award über GameState
## (MinigameAward — Reason 'minigame'/'endless'). OrientationService wird
## beim Start gelockt (Hochkant/Quer) und beim Verlassen entsperrt.
##
## Router-Params (SceneRouter receive_params-Contract):
##   {game_id: String, difficulty: "easy|normal|hard|endless",
##    orientation: "auto|portrait|landscape", seed: int (optional, Tests)}

signal exit_requested(target: StringName, params: Dictionary)
signal round_finished(breakdown: Dictionary)

const RESULTS_SCENE := preload("res://scripts/minigames/results.tscn")
## Design-Basis wie im Web (CSS-Baseline 390×844).
const DESIGN_PORTRAIT := Vector2(390, 844)
## OrientationService.LockMode (W1a-Contract FROZEN: AUTO/LANDSCAPE/PORTRAIT).
const LOCK_LANDSCAPE := 1
const LOCK_PORTRAIT := 2

## Sekunden pro Countdown-Schritt (Tests drehen auf ~0).
var countdown_step_sec := 0.8
## Duck-Typing-Overrides für Tests (null → /root/GameState bzw. /root/…).
var state_node: Node = null
var auto_navigate := true

var game_id := ""
var difficulty := "normal"
var orientation_choice := "auto"
var run_seed := 0
var score := 0
var juice: JuiceKit

var _meta: Dictionary = {}
var _game: MinigameBase
var _ctx: MinigameCtx
var _stage: Control
var _viewport_container: SubViewportContainer
var _viewport: SubViewport
var _overlay: Control
var _score_label: Label
var _countdown_label: Label
var _pause_overlay: Control
var _pause_button: Button
var _results: MinigameResults
var _round_over := false
var _countdown_token := 0


func receive_params(params: Dictionary) -> void:
	game_id = str(params.get("game_id", ""))
	difficulty = str(params.get("difficulty", "normal"))
	orientation_choice = str(params.get("orientation", "auto"))
	run_seed = int(params.get("seed", 0))


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_meta = MinigameRegistry.get_game(game_id)
	if _meta.is_empty() or not _meta.has("scene"):
		push_warning("[mg_host] unbekanntes Spiel '%s' — zurück zur Arcade" % game_id)
		_exit_to(&"arcade", {})
		return
	difficulty = MinigameFrameworkLogic.effective_difficulty(
		game_id, {"difficulty": difficulty}, _meta
	)
	if run_seed == 0:
		run_seed = maxi(1, randi() & 0x7FFFFFFF)
	_build_ui()
	_lock_orientation()
	_mount_game()
	resized.connect(_layout_stage)
	_layout_stage()
	_run_countdown()


func _exit_tree() -> void:
	_countdown_token += 1
	Engine.time_scale = 1.0
	_unlock_orientation()


## Effektive Lauf-Orientierung: Pregame-Wahl > globale AppSettings-Präferenz
## (orientation_mode) > Spiel-Default aus der Registry.
func effective_orientation() -> String:
	if orientation_choice == "portrait" or orientation_choice == "landscape":
		return orientation_choice
	var settings := get_node_or_null("/root/AppSettings")
	if settings != null and settings.has_method("orientation_mode"):
		var global_mode: String = settings.orientation_mode()
		if global_mode == "portrait" or global_mode == "landscape":
			return global_mode
	return MinigameFrameworkLogic.normalize_orientation(_meta.get("orientation"))


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.98, 0.94, 0.87)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_stage = Control.new()
	_stage.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stage.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stage)
	_viewport_container = SubViewportContainer.new()
	_viewport_container.stretch = true
	_stage.add_child(_viewport_container)
	_viewport = SubViewport.new()
	_viewport.handle_input_locally = true
	_viewport_container.add_child(_viewport)

	juice = JuiceKit.new()
	juice.shake_target = _viewport_container
	add_child(juice)

	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_overlay)
	juice.float_text_parent = _overlay

	var top_bar := HBoxContainer.new()
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_left = 16.0
	top_bar.offset_right = -16.0
	top_bar.offset_top = 10.0
	top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.add_child(top_bar)
	_score_label = Label.new()
	_score_label.theme_type_variation = &"HeadlineLabel"
	_score_label.text = I18nService.t("mg.host.score", {"score": 0})
	top_bar.add_child(_score_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(spacer)
	_pause_button = Button.new()
	_pause_button.theme_type_variation = &"GhostButton"
	_pause_button.text = I18nService.t("mg.host.pause")
	_pause_button.pressed.connect(_on_pause_pressed)
	_pause_button.disabled = true
	top_bar.add_child(_pause_button)

	_countdown_label = Label.new()
	_countdown_label.theme_type_variation = &"TitleLabel"
	_countdown_label.add_theme_font_size_override("font_size", 96)
	_countdown_label.set_anchors_preset(Control.PRESET_CENTER)
	_countdown_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_countdown_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_overlay.add_child(_countdown_label)

	_pause_overlay = _build_pause_overlay()
	add_child(_pause_overlay)

	_results = RESULTS_SCENE.instantiate()
	_results.hide()
	_results.again_pressed.connect(_on_again_pressed)
	_results.back_pressed.connect(func() -> void: _exit_to(&"arcade", {}))
	add_child(_results)


func _build_pause_overlay() -> Control:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.hide()
	var dim := ColorRect.new()
	dim.color = Color(0.24, 0.16, 0.12, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var card := PanelContainer.new()
	card.theme_type_variation = &"AcCardLg"
	card.custom_minimum_size = Vector2(340, 0)
	center.add_child(card)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	card.add_child(rows)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = I18nService.t("mg.host.paused")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(title)
	var resume := Button.new()
	resume.theme_type_variation = &"PrimaryButton"
	resume.text = I18nService.t("mg.host.resume")
	resume.pressed.connect(_on_resume_pressed)
	rows.add_child(resume)
	var quit := Button.new()
	quit.theme_type_variation = &"GhostButton"
	quit.text = I18nService.t("mg.host.quit")
	quit.pressed.connect(_on_quit_pressed)
	rows.add_child(quit)
	return overlay


func _mount_game() -> void:
	var packed: PackedScene = load(str(_meta["scene"]))
	var node := packed.instantiate()
	if not (node is MinigameBase):
		push_warning("[mg_host] Szene %s ist kein MinigameBase" % _meta["scene"])
		node.queue_free()
		_exit_to(&"arcade", {})
		return
	_game = node
	_ctx = MinigameCtx.new()
	_ctx.game_id = game_id
	_ctx.difficulty = difficulty
	_ctx.orientation = effective_orientation()
	_ctx.run_seed = run_seed
	_ctx.juice = juice
	_ctx.on_score = _on_game_score
	_ctx.on_end = _on_game_end
	_viewport.add_child(_game)
	_game.setup(_ctx)


## Pillar-/Letterbox: Stage auf die Ziel-Orientierung einpassen.
func _layout_stage() -> void:
	if _viewport_container == null:
		return
	var avail := size - Vector2(0, 56)
	if avail.x <= 0 or avail.y <= 0:
		return
	var design := DESIGN_PORTRAIT
	if effective_orientation() == "landscape":
		design = Vector2(DESIGN_PORTRAIT.y, DESIGN_PORTRAIT.x)
	var scale_factor := minf(avail.x / design.x, avail.y / design.y)
	var fitted := design * scale_factor
	_viewport_container.position = Vector2(
		(size.x - fitted.x) * 0.5, 56.0 + (avail.y - fitted.y) * 0.5
	)
	_viewport_container.size = fitted


func _run_countdown() -> void:
	_countdown_token += 1
	var token := _countdown_token
	_countdown_label.show()
	for step in [3, 2, 1]:
		_countdown_label.text = str(step)
		AudioDirector.try_play(self, "ui_tick")
		await get_tree().create_timer(countdown_step_sec).timeout
		if token != _countdown_token or not is_inside_tree():
			return
	_countdown_label.text = I18nService.t("mg.host.go")
	AudioDirector.try_play(self, "mg_go")
	_countdown_label.show()
	get_tree().create_timer(0.6).timeout.connect(
		func() -> void:
			if is_instance_valid(_countdown_label):
				_countdown_label.hide()
	)
	_pause_button.disabled = false
	if _game != null:
		_game.start()


func _on_game_score(total: int, _delta: int) -> void:
	score = total
	_score_label.text = I18nService.t("mg.host.score", {"score": total})


func _on_game_end(result: Dictionary) -> void:
	if _round_over:
		return
	_round_over = true
	score = int(result.get("score", score))
	_pause_button.disabled = true
	var breakdown := _award(score)
	_unlock_orientation()
	_results.show_results(breakdown, _meta)
	round_finished.emit(breakdown)


## Award über GameState.update (Signale + Autosave); ohne GameState (Tests
## ohne State) gibt es ein reines Anzeige-Breakdown ohne Buchung.
func _award(final_score: int) -> Dictionary:
	var gs := _resolve_state()
	if gs == null:
		return {
			"gameId": game_id,
			"score": final_score,
			"coins": 0,
			"difficulty": difficulty,
			"firstToday": false,
			"newBest": false,
			"best": final_score,
			"xp": 0,
			"levelsGained": 0,
			"coinsFromLevels": 0,
			"dayCapReached": false,
			"beatTarget": false,
		}
	var today: String = gs.clock.local_day()
	var holder: Array[Dictionary] = []
	var meta := _meta
	var mode := difficulty
	gs.update(
		func(state: Dictionary) -> void:
			holder.append(MinigameAward.award(state, meta, final_score, mode, today))
	)
	return holder[0] if holder.size() > 0 else {}


func _on_pause_pressed() -> void:
	if _game == null or _round_over:
		return
	AudioDirector.try_play(self, "ui_open")
	_game.pause()
	_pause_overlay.show()


func _on_resume_pressed() -> void:
	AudioDirector.try_play(self, "ui_close")
	_pause_overlay.hide()
	if _game != null:
		_game.resume()


func _on_quit_pressed() -> void:
	AudioDirector.try_play(self, "ui_back")
	if _game != null:
		_game.end()
	_exit_to(&"arcade", {})


func _on_again_pressed() -> void:
	# Interner Neustart (gleiche Difficulty/Orientierung, frischer Seed).
	_results.hide()
	_round_over = false
	score = 0
	run_seed = maxi(1, randi() & 0x7FFFFFFF)
	_score_label.text = I18nService.t("mg.host.score", {"score": 0})
	if _game != null:
		_game.queue_free()
		_game = null
	_lock_orientation()
	_mount_game()
	_run_countdown()


func _exit_to(target: StringName, params: Dictionary) -> void:
	_unlock_orientation()
	exit_requested.emit(target, params)
	if not auto_navigate:
		return
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("goto"):
		router.goto(target, params)


func _lock_orientation() -> void:
	var svc := get_node_or_null("/root/OrientationService")
	if svc == null or not svc.has_method("lock"):
		return
	var mode := LOCK_LANDSCAPE if effective_orientation() == "landscape" else LOCK_PORTRAIT
	svc.lock(mode)


func _unlock_orientation() -> void:
	var svc := get_node_or_null("/root/OrientationService")
	if svc != null and svc.has_method("unlock"):
		svc.unlock()


func _resolve_state() -> Node:
	if state_node != null:
		return state_node
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("update") and gs.get("clock") != null:
		return gs
	return null
