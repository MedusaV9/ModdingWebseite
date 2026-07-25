extends MinigameBase
## Gooby sagt (goobySays) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## GoobySaysLogic (zahlengleich zum Web, Bot-zertifiziert): Sequenz startet bei
## 3 und wächst je Runde um 1, die Wiedergabe zieht 5 % pro Runde an (Boden
## 320 ms), ein Fehler beendet die Runde. Ab Runde 6 hängt ein Zwei-Pad-Akkord
## an, der binnen CHORD_WINDOW_MS beide Felder verlangt. Score = 10·Runden +
## Speed-Bonus (0–8) aus der mittleren Reaktionszeit.
## Optik: vier dicke Pastell-Pads, Gooby dirigiert in der Mitte.

const PAD_COLORS: Array[Color] = [
	Color("59C9B9"), Color("FF7BA9"), Color("FFD166"), Color("8FD06C")
]
const PAD_SYMBOLS: Array[String] = ["▲", "●", "◆", "★"]
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
var _pads: Array[Rect2] = []
## Fläche über den Pads, auf der Gooby die Folge vorgibt.
var _gooby_stage := Rect2()
var _pulse := 0.0
var _shake := 0.0


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = GoobySaysLogic.apply_difficulty(GoobySaysLogic.SAYS, ctx.difficulty)
	rng = ctx.rng()
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
	# Hochkant: 2×2-Block; Quer: eine Reihe aus vier Pads neben Gooby.
	var top := 108.0 if not landscape else 66.0
	var bottom := 64.0
	var avail := Rect2(20.0, top, view_size.x - 40.0, maxf(120.0, view_size.y - top - bottom))
	_pads = []
	if landscape:
		var pw := (avail.size.x - 3.0 * 14.0) / 4.0
		var ph := minf(avail.size.y * 0.72, pw * 1.25)
		for i in 4:
			_pads.append(Rect2(avail.position.x + i * (pw + 14.0), avail.end.y - ph, pw, ph))
		_gooby_stage = Rect2(
			avail.position, Vector2(avail.size.x, maxf(90.0, avail.size.y - ph - 12.0))
		)
	else:
		var pw := (avail.size.x - 16.0) * 0.5
		# Hochkant ist die Breite der Engpass — die Pads dürfen darum etwas
		# höher als breit werden, sonst bleibt unten ein toter Streifen.
		var ph := clampf((avail.size.y - 16.0 - 96.0) * 0.5, pw * 0.8, pw * 1.22)
		var block_w := pw * 2.0 + 16.0
		var block_h := ph * 2.0 + 16.0
		var ox := avail.position.x + (avail.size.x - block_w) * 0.5
		# Über dem 2×2 steht die Gooby-Bühne; beide zusammen werden als EIN
		# Block zentriert, sonst klafft im Hochformat oben eine leere Hälfte.
		var stage_h := clampf(avail.size.y - block_h - 16.0, 96.0, 260.0)
		var oy := avail.position.y + (avail.size.y - block_h - stage_h) * 0.5 + stage_h
		for i in 4:
			_pads.append(Rect2(ox + (i % 2) * (pw + 16.0), oy + (i / 2) * (ph + 16.0), pw, ph))
		_gooby_stage = Rect2(
			Vector2(avail.position.x, oy - stage_h), Vector2(avail.size.x, stage_h)
		)
	if _round_label != null:
		_round_label.position = Vector2(16.0, 10.0)
		_state_label.position = Vector2(16.0, 48.0)
		_hint_label.position = Vector2(view_size.x * 0.5 - 170.0, view_size.y - 42.0)
		_hint_label.size = Vector2(340.0, 34.0)
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
	add_child(_hint_label)
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
	_shake = maxf(0.0, _shake - delta * 4.0)
	if lit_left > 0.0:
		lit_left = maxf(0.0, lit_left - delta)
		if lit_left <= 0.0 and phase == "input":
			lit_pad = -1
	if phase == "watch":
		_playback_tick(delta)
	elif phase == "input":
		_input_timeout_tick(delta)
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
	if ctx.juice != null:
		ctx.juice.bloom_pulse(0.6)
		ctx.juice.float_text(
			Vector2(view_size.x * 0.5 - 60.0, view_size.y * 0.5),
			"+%d" % int(tune["ROUND_POINTS"]),
			AcTokens.LEAF_DARK
		)
	_next_round()


func _fail() -> void:
	AudioDirector.try_play(self, "mg_lose")
	_shake = 1.0
	if ctx.juice != null:
		ctx.juice.shake(0.5)
		ctx.juice.hit_freeze(110)
		ctx.juice.float_text(
			Vector2(view_size.x * 0.5 - 50.0, view_size.y * 0.5),
			I18nService.t("mg.goobySays.oops"),
			AcTokens.DANGER
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
	_round_label.text = I18nService.t("mg.goobySays.round", {"n": maxi(1, round_no)})
	if phase == "watch":
		_state_label.text = I18nService.t("mg.goobySays.watch")
	elif step_index < sequence.size() and GoobySaysLogic.is_chord_step(sequence[step_index]):
		_state_label.text = I18nService.t("mg.goobySays.chord")
	else:
		_state_label.text = I18nService.t("mg.goobySays.go")


func _pad_at(screen: Vector2) -> int:
	for i in _pads.size():
		if _pads[i].has_point(screen):
			return i
	return -1


func _draw() -> void:
	var jitter := Vector2.ZERO
	if _shake > 0.0:
		jitter = Vector2(sin(_pulse * 60.0) * _shake * 6.0, 0.0)
	draw_set_transform(jitter, 0.0, Vector2.ONE)
	draw_rect(Rect2(Vector2.ZERO, view_size), AcTokens.BG_CREAM)
	for i in _pads.size():
		_draw_pad(i)
	_draw_gooby()
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_pad(index: int) -> void:
	var rect := _pads[index]
	var lit := index == lit_pad and lit_left > 0.0
	var base: Color = PAD_COLORS[index]
	var fill := base if lit else base.darkened(0.28)
	if lit:
		# Aufleuchtender Pad bekommt einen weichen Hof (Postprocessing-Glow).
		draw_rect(rect.grow(10.0), Color(base.r, base.g, base.b, 0.35))
	draw_rect(rect, fill)
	draw_rect(rect, AcTokens.INK, false, 4.0)
	draw_rect(
		Rect2(rect.position + Vector2(8.0, 8.0), Vector2(rect.size.x - 16.0, rect.size.y * 0.22)),
		Color(1, 1, 1, 0.22)
	)
	var font := ThemeService.font(800)
	var glyph: String = PAD_SYMBOLS[index]
	var glyph_size := int(maxf(20.0, minf(rect.size.x, rect.size.y) * 0.4))
	var width := font.get_string_size(glyph, HORIZONTAL_ALIGNMENT_LEFT, -1.0, glyph_size).x
	draw_string(
		font,
		rect.get_center() + Vector2(-width * 0.5, glyph_size * 0.36),
		glyph,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		glyph_size,
		Color(1, 1, 1, 0.9 if lit else 0.6)
	)


## Gooby dirigiert zwischen den Pads und wippt zur Wiedergabe.
## Gooby als Dirigent auf der Bühne über den Pads: er leuchtet in der Farbe
## des gerade gespielten Pads, damit „wer sagt was“ sofort klar ist.
func _draw_gooby() -> void:
	var stage := _gooby_stage
	if stage.size.y <= 1.0:
		stage = Rect2(0.0, 0.0, view_size.x, view_size.y * 0.3)
	var r := clampf(minf(stage.size.y * 0.34, stage.size.x * 0.16), 26.0, 84.0)
	var bounce := sin(_pulse * 5.0) * (r * 0.12 if phase == "watch" else r * 0.05)
	var base := Vector2(stage.get_center().x, stage.end.y - r * 1.25 + bounce)
	var lit := lit_pad >= 0 and lit_left > 0.0
	if lit:
		var halo: Color = PAD_COLORS[lit_pad]
		draw_circle(base, r * 1.9, Color(halo.r, halo.g, halo.b, 0.22))
		draw_arc(base, r * 1.55, 0.0, TAU, 34, Color(halo.r, halo.g, halo.b, 0.7), 5.0)
	# Podest, damit Gooby nicht im Nichts schwebt.
	draw_set_transform(Vector2(base.x, base.y + r * 1.15), 0.0, Vector2(1.0, 0.26))
	draw_circle(Vector2.ZERO, r * 1.25, AcTokens.PAPER_SHADE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var fur := Color(0.99, 0.91, 0.7)
	for side in [-1.0, 1.0]:
		var root := base + Vector2(side * r * 0.42, -r * 0.8)
		draw_line(root, root + Vector2(side * r * 0.34, -r * 0.95), fur, r * 0.32)
		draw_circle(root + Vector2(side * r * 0.34, -r * 0.95), r * 0.16, fur)
	draw_circle(base, r, fur)
	draw_arc(base, r, 0.0, TAU, 30, AcTokens.INK, 3.5)
	draw_circle(base + Vector2(-r * 0.34, -r * 0.16), r * 0.12, AcTokens.INK)
	draw_circle(base + Vector2(r * 0.34, -r * 0.16), r * 0.12, AcTokens.INK)
	draw_circle(base + Vector2(-r * 0.55, r * 0.2), r * 0.16, Color(1.0, 0.72, 0.74, 0.5))
	draw_circle(base + Vector2(r * 0.55, r * 0.2), r * 0.16, Color(1.0, 0.72, 0.74, 0.5))
	var mouth := 0.32 if phase == "watch" else 0.24
	draw_arc(base + Vector2(0.0, r * 0.16), r * mouth, 0.3, PI - 0.3, 14, AcTokens.INK, 3.0)
