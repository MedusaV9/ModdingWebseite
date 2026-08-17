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
##
## W17/G5-Politur (NUR Präsentation, Audit mg-audit-b §3): Intro-Beat 1,5 s
## mit Spot-an-Totale + Ziel-Banner (Sim-Uhr und Eingabe warten, M1), heller
## Fehler-Text ÜBER den Pads statt dunkelrot vor dem Vorhang, pulsierender
## Pad-Rand als sichtbare Timeout-Warnung, _ui-skaliertes HUD (M9) und
## Hint-Fade (M6). GoobySaysLogic/RNG bleiben unangetastet (w13c-Crosscheck).

const Stage := preload("res://scripts/minigames/games/gooby_says/gooby_says_stage3d.gd")

## Pause zwischen zwei Wiedergabeschritten (Anteil der Schrittdauer).
const PLAYBACK_GAP := 0.34
## W17/G5 M9: Entwurfs-Kurzkante — alle HUD-Pixelmaße skalieren mit Kurzkante/390.
const DESIGN_SHORT := 390.0
## W17/G5 M1: Intro-Beat (s) — Spot an + Bühnen-Totale; die Sim wartet (W14-Kanon).
const INTRO_S := 1.5
## W17/G5 M6: nach so vielen Sim-Sekunden blendet der Hinweis aus (harbor_hopper-Muster).
const HINT_FADE_SEC := 6.0
## Ab diesem Anteil des Eingabe-Fensters pulsiert der Pad-Rand (letzte 40 %).
const TIMEOUT_WARN_FROM := 0.6

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
var _ui := 1.0
var _intro_left := 0.0
var _banner := ""
var _banner_t := 0.0
var _banner_plate := StyleBoxFlat.new()


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
	_banner_plate.set_corner_radius_all(12)
	# W17/G5 M1: Intro-Beat — Spot an + Vorhang-Ruckler aus der Bühnen-Totale;
	# Sim-Uhr und Eingabe warten, Seeds/RNG-Reihenfolge bleiben unangetastet.
	_intro_left = INTRO_S
	_set_banner(I18nService.t("mg.goobySays.intro"), INTRO_S + 0.7)
	if is_inside_tree():
		get_viewport().size_changed.connect(_fit_viewport)


func start() -> void:
	super.start()
	_next_round()


func end() -> void:
	super.end()
	finished = true


## Pflicht-Layouthook: beide Orientierungen laufen über DIESE Funktion.
## W17/G5 M9: der _ui-Faktor (Kurzkante/390, 0,75–3,0) skaliert alle HUD-Maße.
func apply_view(size: Vector2) -> void:
	if size.x > 1.0 and size.y > 1.0:
		view_size = size
	landscape = view_size.x > view_size.y
	_ui = clampf(minf(view_size.x, view_size.y) / DESIGN_SHORT, 0.75, 3.0)
	position = Vector2.ZERO
	if _stage != null:
		_stage.apply_size(view_size)
	_layout_hud()
	_update_labels()
	queue_redraw()


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
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_hint_label)
	# Heller Text + dunkler Saum: lesbar auf Vorhang UND Bühnenholz.
	for label: Label in [_round_label, _state_label, _hint_label]:
		label.add_theme_color_override("font_color", Color(1.0, 0.97, 0.92))
		label.add_theme_color_override("font_outline_color", Color(0.24, 0.12, 0.2, 0.9))
	_layout_hud()
	_update_labels()


## Bedienleiste in Entwurfspixeln, mit _ui skaliert (M9, tea_party-Muster) —
## vorher klebten Runde/Status auf festen 16/10/48-px-Offsets und der Hinweis
## war auf 340×34 px festgenagelt (Krümel-HUD auf Tablets).
func _layout_hud() -> void:
	if _round_label == null:
		return
	var vp := get_viewport_rect().size
	_round_label.position = Vector2(16.0, 10.0) * _ui
	_round_label.add_theme_font_size_override("font_size", int(34.0 * _ui))
	_round_label.add_theme_constant_override("outline_size", int(7.0 * _ui))
	_state_label.position = Vector2(16.0, 48.0) * _ui
	_state_label.add_theme_font_size_override("font_size", int(15.0 * _ui))
	_state_label.add_theme_constant_override("outline_size", int(5.0 * _ui))
	var hint_w := minf(vp.x - 32.0 * _ui, 360.0 * _ui)
	_hint_label.add_theme_font_size_override("font_size", int(20.0 * _ui))
	_hint_label.add_theme_constant_override("outline_size", int(5.0 * _ui))
	_hint_label.position = Vector2((vp.x - hint_w) * 0.5, vp.y - 52.0 * _ui)
	_hint_label.size = Vector2(hint_w, 40.0 * _ui)


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
	_pulse += delta
	# W17/G5 M1: Intro-Beat — die Kamera schwebt aus der Bühnen-Totale in
	# die Spielpose, die Spots glimmen hoch; Sim-Uhr (elapsed) und Eingabe
	# warten so lange, der Lauf bleibt zahlengleich (w13c-Crosscheck).
	if _intro_left > 0.0:
		_intro_left = maxf(0.0, _intro_left - delta)
		_banner_t = maxf(0.0, _banner_t - delta)
		_stage.establish(1.0 if _reduced_motion() else 1.0 - _intro_left / INTRO_S)
		_stage.sync(lit_pad, lit_left, phase, _pulse, delta)
		_update_labels()
		queue_redraw()
		return
	elapsed += delta
	_banner_t = maxf(0.0, _banner_t - delta)
	if lit_left > 0.0:
		lit_left = maxf(0.0, lit_left - delta)
		if lit_left <= 0.0 and phase == "input":
			lit_pad = -1
	if phase == "watch":
		_playback_tick(delta)
	elif phase == "input":
		_input_timeout_tick(delta)
	_stage.sync(lit_pad, lit_left, phase, _pulse, delta, _timeout_urgency(), _reduced_motion())
	_update_labels()
	queue_redraw()


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


## W17/G5: Warnanteil [0..1] des Eingabe-Fensters — bis 60 % still, danach
## steigt der Wert bis 1 kurz vor dem Timeout (Pad-Rand pulsiert sichtbar;
## vorher failte _input_timeout_tick ohne jede Anzeige).
func _timeout_urgency() -> float:
	if phase != "input" or step_started_at < 0.0:
		return 0.0
	var frac := (elapsed - step_started_at) * 1000.0 / float(tune["INPUT_TIMEOUT_MS"])
	return clampf((frac - TIMEOUT_WARN_FROM) / (1.0 - TIMEOUT_WARN_FROM), 0.0, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished or phase != "input" or _intro_left > 0.0:
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
	# Q2: Reduced-Motion-Gate an der eigenen Konfetti-Call-Site (Kit tabu).
	_stage.celebrate(_reduced_motion())
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
		# W17/G5: helle Creme MIT der dunklen float_text-Outline ÜBER den
		# Pads — Dunkelrot vor rotem Vorhang war unlesbar (Audit-Beleg).
		ctx.juice.float_text(
			_stage.pads_screen(), I18nService.t("mg.goobySays.oops"), AcTokens.BG_CREAM
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
	_round_label.text = I18nService.t("mg.goobySays.round", {"n": maxi(1, round_no)})
	# Schrittzähler „3/5" macht den Fortschritt der Runde jederzeit ablesbar.
	var steps := "  %d/%d" % [mini(step_index, sequence.size()), sequence.size()]
	if phase == "watch":
		_state_label.text = I18nService.t("mg.goobySays.watch")
	elif step_index < sequence.size() and GoobySaysLogic.is_chord_step(sequence[step_index]):
		_state_label.text = I18nService.t("mg.goobySays.chord") + steps
	else:
		_state_label.text = I18nService.t("mg.goobySays.go") + steps
	_hint_label.modulate.a = _hint_alpha()


## M6: der Hinweis blendet nach ein paar Sim-Sekunden aus (harbor_hopper-
## Muster) — elapsed wartet im Intro, der Fade startet also fair.
func _hint_alpha() -> float:
	return clampf((HINT_FADE_SEC - elapsed) / 1.2, 0.0, 1.0)


func _set_banner(text: String, sec := 1.4) -> void:
	_banner = text
	_banner_t = sec


## 2D-Overlay über der Bühne: nur die Banner-Ebene (Intro-Ziel) — die Labels
## bringen ihre Lesbarkeit über die Konturen aus _layout_hud mit.
func _draw() -> void:
	_draw_banner()


## Ziel-Banner mittig mit Milchglas-Plate und Kontur (M7, carrot_catch-
## Muster); lange Übersetzungen brechen um.
func _draw_banner() -> void:
	if _banner_t <= 0.0 or _banner.is_empty():
		return
	var vp := get_viewport_rect().size
	var font := ThemeService.font(800)
	var alpha := clampf(_banner_t * 1.4, 0.0, 1.0)
	var font_size := int(26.0 * _ui)
	var w := minf(vp.x * 0.92, 460.0 * _ui)
	var text_size := font.get_multiline_string_size(
		_banner, HORIZONTAL_ALIGNMENT_CENTER, w, font_size
	)
	var top := vp.y * 0.26
	var pad := Vector2(18.0 * _ui, 10.0 * _ui)
	_banner_plate.set_corner_radius_all(int(12.0 * _ui))
	_banner_plate.bg_color = Color(1.0, 0.99, 0.94, 0.74 * alpha)
	var plate_pos := Vector2((vp.x - text_size.x) * 0.5, top) - pad
	draw_style_box(_banner_plate, Rect2(plate_pos, text_size + pad * 2.0))
	var ink := Color(0.32, 0.24, 0.28, alpha)
	var rim := Color(1.0, 1.0, 1.0, 0.75 * alpha)
	var at := Vector2((vp.x - w) * 0.5, top + font.get_ascent(font_size))
	draw_multiline_string_outline(
		font, at, _banner, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, -1, int(5.0 * _ui), rim
	)
	draw_multiline_string(font, at, _banner, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, -1, ink)


## Reduced-Motion-Abfrage (Duck-Typing wie im JuiceKit — ohne Autoload = aus).
func _reduced_motion() -> bool:
	if not is_inside_tree():
		return true
	var settings := get_node_or_null(^"/root/AppSettings")
	if settings != null and settings.has_method("is_reduced_motion"):
		return settings.is_reduced_motion()
	return false


func _pad_at(screen: Vector2) -> int:
	return _stage.pad_at(screen)
