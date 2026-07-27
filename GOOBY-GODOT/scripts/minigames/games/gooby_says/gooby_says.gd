extends MinigameBase
## Gooby sagt (goobySays) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## GoobySaysLogic (zahlengleich zum Web, Bot-zertifiziert): Sequenz startet bei
## 3 und wächst je Runde um 1, die Wiedergabe zieht 5 % pro Runde an (Boden
## 320 ms), ein Fehler beendet die Runde. Ab Runde 6 hängt ein Zwei-Pad-Akkord
## an, der binnen CHORD_WINDOW_MS beide Felder verlangt. Score = 10·Runden +
## Speed-Bonus (0–8) aus der mittleren Reaktionszeit.
##
## ECHTE 3D-SPIELSHOW (FB-4, GoobySaysStage3D): vier leuchtende 3D-Podeste auf
## einer Bühne mit Vorhang, Gooby dirigiert GROSS auf seinem Podium und trägt
## beim Vorspielen einen Leuchtring in der Pad-Farbe. Eingaben laufen als
## Raycast auf die Pads; die 3D-Welt hängt unter der Node2D-Wurzel (Godot
## rendert 3D hinter den CanvasItems), der MinigameBase-Vertrag bleibt gleich.

const Stage := preload("res://scripts/minigames/games/gooby_says/gooby_says_stage3d.gd")

## Pause zwischen zwei Wiedergabeschritten (Anteil der Schrittdauer).
const PLAYBACK_GAP := 0.34

var tune: Dictionary = {}
var rng: GoobyRng
var sequence: Array = []
var round_no := 0
var rounds_completed := 0
var step_index := 0
var play_timer := 0.0
var lit_pad := -1
var lit_left := 0.0
var chord_first := -1
var chord_at := -1.0
var reaction_total_ms := 0.0
var reaction_steps := 0
var step_started_at := -1.0
var phase := "watch"
var elapsed := 0.0
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

var _round_label: Label
var _state_label: Label
var _hint_label: Label
var _stage: Node3D
var _pulse := 0.0


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = GoobySaysLogic.apply_difficulty(GoobySaysLogic.SAYS, ctx.difficulty)
	rng = ctx.rng()
	_stage = Stage.new()
	_stage.name = "Show3D"
	add_child(_stage)
	_stage.setup_stage()
	if ctx.juice != null:
		ctx.juice.world_environment = _stage.stage.world_env
	_build_hud()
	_fit_viewport()
	if is_inside_tree():
		get_viewport().size_changed.connect(_fit_viewport)


func start() -> void:
	super.start()
	_next_round()


func end() -> void:
	super.end()
	finished = true


## Pflicht-Layouthook: beide Orientierungen laufen über DIESE Funktion.
func apply_view(size: Vector2) -> void:
	if size.x > 1.0 and size.y > 1.0:
		view_size = size
	landscape = view_size.x > view_size.y
	position = Vector2.ZERO
	if _stage != null:
		_stage.apply_size(view_size)
	_update_labels()


func _build_hud() -> void:
	_round_label = Label.new()
	_round_label.theme_type_variation = &"HeadlineLabel"
	add_child(_round_label)
	_state_label = Label.new()
	_state_label.theme_type_variation = &"CaptionLabel"
	add_child(_state_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.goobySays.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint_label)
	# Heller Text + dunkler Saum: lesbar auf Vorhang UND Bühnenholz.
	for label: Label in [_round_label, _state_label, _hint_label]:
		label.add_theme_color_override("font_color", Color(1.0, 0.97, 0.92))
		label.add_theme_color_override("font_outline_color", Color(0.24, 0.12, 0.2, 0.9))
		label.add_theme_constant_override("outline_size", 7)
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _next_round() -> void:
	round_no += 1
	sequence = GoobySaysLogic.extend_sequence(sequence, rng, round_no)
	step_index = 0
	play_timer = 0.45
	phase = "watch"
	chord_first = -1
	AudioDirector.try_play(self, "mg_combo", 0.9)
	if GoobySaysLogic.giggle_round(round_no) and ctx.juice != null:
		ctx.juice.bloom_pulse(0.6)
	_update_labels()


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	elapsed += delta
	_pulse += delta
	if lit_left > 0.0:
		lit_left = maxf(0.0, lit_left - delta)
		if lit_left <= 0.0 and phase == "input":
			lit_pad = -1
	if phase == "watch":
		_playback_tick(delta)
	elif phase == "input":
		_input_timeout_tick(delta)
	_stage.sync(lit_pad, lit_left, phase, _pulse, delta)
	_update_labels()


func _playback_tick(delta: float) -> void:
	play_timer -= delta
	if play_timer > 0.0:
		return
	var step_sec := GoobySaysLogic.step_ms_at(round_no, tune) / 1000.0
	if step_index >= sequence.size():
		phase = "input"
		step_index = 0
		lit_pad = -1
		step_started_at = elapsed
		AudioDirector.try_play(self, "mg_go")
		return
	var step: Variant = sequence[step_index]
	lit_pad = int(step[0]) if GoobySaysLogic.is_chord_step(step) else int(step)
	lit_left = step_sec * (1.0 - PLAYBACK_GAP)
	AudioDirector.try_play(self, "mg_good", 0.85 + 0.12 * float(lit_pad))
	if GoobySaysLogic.is_chord_step(step):
		AudioDirector.try_play(self, "mg_perfect", 0.85 + 0.12 * float(step[1]))
	_stage.flash_playback(lit_pad)
	step_index += 1
	play_timer = step_sec


## Zu lange gezögert = Fehler (INPUT_TIMEOUT_MS, difficulty-abhängig).
func _input_timeout_tick(_delta: float) -> void:
	if step_started_at < 0.0:
		return
	if (elapsed - step_started_at) * 1000.0 >= float(tune["INPUT_TIMEOUT_MS"]):
		_fail()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished or phase != "input":
		return
	var pressed := event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed
	if not pressed:
		return
	var pad := _pad_at((event as InputEventScreenTouch).position)
	if pad < 0:
		return
	lit_pad = pad
	lit_left = 0.16
	AudioDirector.try_play(self, "mg_good", 0.85 + 0.12 * float(pad))
	var step: Variant = sequence[step_index]
	if GoobySaysLogic.is_chord_step(step):
		_handle_chord_tap(step, pad)
	elif int(step) == pad:
		_advance_step()
	else:
		_fail()


func _handle_chord_tap(step: Variant, pad: int) -> void:
	if chord_first < 0:
		var opened := GoobySaysLogic.chord_tap_result(step, pad, -1, 0.0, tune)
		if opened == "wrong":
			_fail()
			return
		chord_first = pad
		chord_at = elapsed
		return
	var gap_ms := (elapsed - chord_at) * 1000.0
	var result := GoobySaysLogic.chord_tap_result(step, chord_first, pad, gap_ms, tune)
	chord_first = -1
	if result == "complete":
		_advance_step()
	else:
		_fail()


func _advance_step() -> void:
	if step_started_at >= 0.0:
		reaction_total_ms += (elapsed - step_started_at) * 1000.0
		reaction_steps += 1
	step_index += 1
	step_started_at = elapsed
	if step_index < sequence.size():
		return
	rounds_completed = round_no
	ctx.report_score(_live_score(), int(tune["ROUND_POINTS"]))
	AudioDirector.try_play(self, "mg_win", 1.0 + 0.02 * minf(round_no, 10.0))
	_stage.celebrate()
	if ctx.juice != null:
		ctx.juice.bloom_pulse(0.6)
		ctx.juice.float_text(
			_stage.gooby_screen(), "+%d" % int(tune["ROUND_POINTS"]), AcTokens.LEAF_DARK
		)
	_next_round()


func _fail() -> void:
	AudioDirector.try_play(self, "mg_lose")
	_stage.fail_fx()
	if ctx.juice != null:
		ctx.juice.shake(0.5)
		ctx.juice.hit_freeze(110)
		ctx.juice.float_text(
			_stage.gooby_screen(), I18nService.t("mg.goobySays.oops"), AcTokens.DANGER
		)
	_finish()


func _live_score() -> int:
	return GoobySaysLogic.round_score(rounds_completed, _avg_reaction_ms(), tune)


func _avg_reaction_ms() -> float:
	if reaction_steps <= 0:
		return INF
	return reaction_total_ms / float(reaction_steps)


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	ctx.report_end({"score": _live_score(), "rounds": rounds_completed, "elapsed": elapsed})


func _update_labels() -> void:
	if _round_label == null:
		return
	var vp := get_viewport_rect().size
	_round_label.position = Vector2(16.0, 10.0)
	_state_label.position = Vector2(16.0, 48.0)
	_hint_label.position = Vector2(vp.x * 0.5 - 170.0, vp.y - 42.0)
	_hint_label.size = Vector2(340.0, 34.0)
	_round_label.text = I18nService.t("mg.goobySays.round", {"n": maxi(1, round_no)})
	# Schrittzähler „3/5" macht den Fortschritt der Runde jederzeit ablesbar.
	var steps := "  %d/%d" % [mini(step_index, sequence.size()), sequence.size()]
	if phase == "watch":
		_state_label.text = I18nService.t("mg.goobySays.watch")
	elif step_index < sequence.size() and GoobySaysLogic.is_chord_step(sequence[step_index]):
		_state_label.text = I18nService.t("mg.goobySays.chord") + steps
	else:
		_state_label.text = I18nService.t("mg.goobySays.go") + steps


func _pad_at(screen: Vector2) -> int:
	return _stage.pad_at(screen)
