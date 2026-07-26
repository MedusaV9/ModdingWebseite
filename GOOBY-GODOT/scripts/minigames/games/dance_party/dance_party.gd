extends MinigameBase
## Tanzparty (danceParty) — Spiel-Szene. Alle MECHANIK-Zahlen aus
## DancePartyLogic (zahlengleich zum Web): 100 BPM, gesetztes Notenbild aus
## PATTERN_SEED, 3 Bahnen, ≤ 70 ms perfekt (+4) / ≤ 140 ms gut (+2), Fehler
## bricht die Serie und kostet 2 Punkte, Serienstufen 4/8/16, fünf perfekte
## Fiebertreffer starten die 5-s-Zugabe (doppelte Notenpunkte).
##
## Der Song läuft ab −LEAD_IN_SEC; Noten fallen NOTE_TRAVEL_SEC lang auf die
## Trefferlinie. Im Endlos-Modus werden Chart-Segmente angehängt und je
## 12-Sekunden-Abschnitt ein Serienbruch gezählt (3 beenden den Lauf).

const Logic := preload("res://scripts/minigames/games/dance_party/dance_party_logic.gd")

## Bildschirmhöhe der Trefferlinie (Anteil von oben).
const HIT_LINE_FRAC := 0.74
## Höhe der Anflugstrecke als Anteil der Viewport-Höhe.
const TRAVEL_FRAC := 0.66

const FLOOR_DARK := Color(0.1, 0.07, 0.2)
const FLOOR_LIGHT := Color(0.24, 0.14, 0.36)
const LANE_COLORS: Array[Color] = [
	Color(1.0, 0.48, 0.66),
	Color(0.35, 0.79, 0.73),
	Color(1.0, 0.82, 0.4),
]

var tune: Dictionary = {}
var notes: Array[Dictionary] = []
var tally: Dictionary = {}
var fever: Dictionary = {}
var endless_state: Dictionary = {}
var song_time := 0.0
var score := 0
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

var _chart_segment := 0
var _head := 0
var _section_idx := 0
var _section_missed := false
var _bursts: Array[Dictionary] = []
var _lane_flash: Array[float] = [0.0, 0.0, 0.0]
var _ball_spin := 0.0
var _ball_pop := 0.0
var _bob := 0.0
var _score_label: Label
var _combo_label: Label
var _hint_label: Label


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = Logic.apply_difficulty(Logic.DANCE_TUNING, ctx.difficulty)
	tally = Logic.create_tally()
	fever = Logic.create_fever_chain()
	endless_state = Logic.create_endless_state()
	song_time = -float(tune["LEAD_IN_SEC"])
	_append_segment()
	_build_hud()
	_fit_viewport()
	if is_inside_tree():
		get_viewport().size_changed.connect(_fit_viewport)


func end() -> void:
	super.end()
	finished = true


## Pflicht-Layouthook: beide Orientierungen laufen über DIESE Funktion.
func apply_view(size: Vector2) -> void:
	if size.x > 1.0 and size.y > 1.0:
		view_size = size
	landscape = view_size.x > view_size.y
	position = Vector2.ZERO
	if _score_label != null:
		_score_label.position = Vector2(16.0, 10.0)
		_combo_label.position = Vector2(16.0, 48.0)
		_hint_label.position = Vector2(view_size.x * 0.5 - 160.0, view_size.y - 44.0)
		_hint_label.size = Vector2(320.0, 36.0)
	queue_redraw()


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	song_time += delta
	_bob += delta
	_ball_spin += (
		delta
		* (
			float(Logic.DANCE_JUICE["BALL_SPIN_BASE"])
			+ float(Logic.DANCE_JUICE["BALL_SPIN_PER_TIER"]) * tier()
		)
	)
	_ball_pop = maxf(0.0, _ball_pop - delta)
	_age_bursts(delta)
	if bool(tune["ENDLESS"]):
		_tick_endless()
		if finished:
			return
	_expire_notes()
	if not bool(tune["ENDLESS"]) and song_time >= float(tune["DURATION_SEC"]):
		_finish()
		return
	score = Logic.dance_score(tally)
	ctx.report_score(score, 0)
	_update_labels()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished:
		return
	if event is InputEventScreenTouch and event.pressed:
		_tap_lane(lane_at(event.position.x))


## Aktuelle Tanzenergie-Stufe (0 … 3) aus der laufenden Serie.
func tier() -> int:
	return Logic.combo_tier(int(tally["combo"]))


## Bahn unter einer Bildschirm-x-Position.
func lane_at(px: float) -> int:
	var span := lane_span()
	var left := view_size.x * 0.5 - span * 1.5
	return clampi(int(floor((px - left) / span)), 0, int(Logic.DANCE["LANES"]) - 1)


## Breite einer Bahn in Pixeln.
func lane_span() -> float:
	return minf(view_size.x / 3.4, 150.0)


## Bildschirm-x der Bahnmitte.
func lane_x(lane: int) -> float:
	return view_size.x * 0.5 + (lane - 1.0) * lane_span()


## Bildschirm-y einer Note zur aktuellen Songzeit.
func note_y(note_time: float) -> float:
	var travel := float(tune["NOTE_TRAVEL_SEC"])
	var t := clampf((note_time - song_time) / travel, -0.4, 1.4)
	return view_size.y * HIT_LINE_FRAC - t * view_size.y * TRAVEL_FRAC


func _build_hud() -> void:
	_score_label = Label.new()
	_score_label.theme_type_variation = &"HeadlineLabel"
	add_child(_score_label)
	_combo_label = Label.new()
	_combo_label.theme_type_variation = &"CaptionLabel"
	add_child(_combo_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.danceParty.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint_label)
	# Der Discoboden ist dunkel — die Theme-Schriftfarben sind es auch.
	_score_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.9))
	_combo_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.5))
	_hint_label.add_theme_color_override("font_color", Color(0.88, 0.84, 0.96))
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


## Endlos: das nächste Chartsegment anhängen (eigener Seed je Segment).
func _append_segment() -> void:
	var offset := _chart_segment * float(tune["DURATION_SEC"])
	for note in Logic.generate_pattern(Logic.segment_seed(_chart_segment), tune):
		(
			notes
			. append(
				{
					"time": float(note["time"]) + offset,
					"lane": int(note["lane"]),
					"hit": false,
					"missed": false,
				}
			)
		)
	_chart_segment += 1


func _tick_endless() -> void:
	if song_time >= 0.0:
		var section := Logic.section_index(song_time)
		if section > _section_idx:
			var ended := Logic.record_section(endless_state, _section_missed)
			_section_idx = section
			_section_missed = false
			if ended:
				_finish()
				return
	while (
		song_time + float(tune["NOTE_TRAVEL_SEC"]) >= _chart_segment * float(tune["DURATION_SEC"])
	):
		_append_segment()


## Noten, die die Linie ungespielt passiert haben, zählen als Fehler.
func _expire_notes() -> void:
	while _head < notes.size():
		var n: Dictionary = notes[_head]
		if bool(n["hit"]) or bool(n["missed"]):
			_head += 1
			continue
		if Logic.note_lifecycle(float(n["time"]), song_time, tune) != "expired":
			break
		n["missed"] = true
		_head += 1
		_judge("miss", lane_x(int(n["lane"])))


func _tap_lane(lane: int) -> void:
	_lane_flash[lane] = 0.18
	var window: Array[Dictionary] = notes.slice(_head, mini(notes.size(), _head + 48))
	var idx := Logic.judge_tap(window, lane, song_time, tune)
	if idx == -1:
		return
	var note: Dictionary = window[idx]
	note["hit"] = true
	var kind := Logic.classify_hit(float(note["time"]) - song_time, tune)
	_judge(kind if not kind.is_empty() else "miss", lane_x(lane))


func _judge(kind: String, at_x: float) -> void:
	Logic.apply_judgment(tally, kind)
	var chain: Dictionary = Logic.advance_fever_chain(fever, kind, int(tally["combo"]), song_time)
	tally["bonus"] = int(tally["bonus"]) + Logic.encore_bonus(kind, bool(chain["active"]))
	if kind == "miss":
		_section_missed = true
		AudioDirector.try_play(self, "mg_junk")
		if ctx.juice != null:
			ctx.juice.shake(0.35)
			ctx.juice.sfx("game_miss")
			ctx.juice.show_combo(0)
		return
	_bursts.append({"x": at_x, "t": float(Logic.DANCE_JUICE["BURST_LIFE_SEC"]), "kind": kind})
	_ball_pop = float(Logic.DANCE_JUICE["BALL_POP_SEC"])
	var combo := int(tally["combo"])
	if bool(chain["started"]):
		AudioDirector.try_play(self, "mg_golden")
		if ctx.juice != null:
			ctx.juice.bloom_pulse(1.0)
			ctx.juice.edge_glow(0.8, Color(1.0, 0.75, 0.3))
			ctx.juice.confetti(40)
			ctx.juice.float_text(
				Vector2(view_size.x * 0.5, view_size.y * 0.3),
				I18nService.t("mg.danceParty.encore"),
				Color(1.0, 0.85, 0.5)
			)
		return
	# Rhythmusspiel = Combo-Kern: jeder Treffer der Serie klingt einen
	# Halbton höher (der stärkste Dopamin-Hebel).
	AudioDirector.try_play(
		self, "mg_perfect" if kind == "perfect" else "mg_good", FeelSfx.combo_pitch(combo)
	)
	if ctx.juice != null:
		ctx.juice.ring_burst(
			self,
			Vector2(at_x, view_size.y * HIT_LINE_FRAC),
			Color(1.0, 0.85, 0.4) if kind == "perfect" else Color(0.6, 0.85, 1.0),
			54.0
		)
		if combo >= 4:
			ctx.juice.show_combo(combo)
	if kind == "perfect" and ctx.juice != null and tier() >= 2:
		ctx.juice.bloom_pulse(0.45)


func _age_bursts(delta: float) -> void:
	var kept: Array[Dictionary] = []
	for b in _bursts:
		b["t"] = float(b["t"]) - delta
		if float(b["t"]) > 0.0:
			kept.append(b)
	_bursts = kept
	for i in _lane_flash.size():
		_lane_flash[i] = maxf(0.0, _lane_flash[i] - delta)


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	AudioDirector.try_play(self, "mg_win")
	(
		ctx
		. report_end(
			{
				"score": Logic.dance_score(tally),
				"maxCombo": int(tally["maxCombo"]),
				"perfect": int(tally["perfect"]),
			}
		)
	)


func _update_labels() -> void:
	if bool(tune["ENDLESS"]):
		_score_label.text = I18nService.t(
			"mg.danceParty.breaks",
			{"n": int(endless_state["breaks"]), "max": int(endless_state["limit"])}
		)
	else:
		var left := maxi(0, int(ceil(float(tune["DURATION_SEC"]) - song_time)))
		_score_label.text = I18nService.t("mg.game.time", {"sec": left})
	if int(tally["combo"]) > 1:
		_combo_label.text = I18nService.t("mg.game.streak", {"n": int(tally["combo"])})
	else:
		_combo_label.text = ""


func _draw() -> void:
	_draw_floor()
	_draw_lanes()
	_draw_hit_line()
	_draw_notes()
	_draw_bursts()
	_draw_gooby()
	_draw_mirror_ball()
	if Logic.encore_active(fever, song_time):
		_draw_encore()


func _draw_floor() -> void:
	for i in 12:
		var f := float(i) / 11.0
		draw_rect(
			Rect2(0.0, view_size.y * f, view_size.x, view_size.y / 11.0 + 1.0),
			FLOOR_DARK.lerp(FLOOR_LIGHT, f)
		)
	# Discolicht-Kegel von oben.
	for i in 3:
		var phase := _bob * 0.7 + i * TAU / 3.0
		var top := Vector2(view_size.x * 0.5, view_size.y * 0.02)
		var aim := view_size.x * (0.5 + 0.45 * sin(phase))
		draw_colored_polygon(
			PackedVector2Array(
				[
					top + Vector2(-14.0, 0.0),
					top + Vector2(14.0, 0.0),
					Vector2(aim + 90.0, view_size.y * HIT_LINE_FRAC),
					Vector2(aim - 90.0, view_size.y * HIT_LINE_FRAC),
				]
			),
			Color(LANE_COLORS[i], 0.09)
		)


func _draw_lanes() -> void:
	var span := lane_span()
	var top := view_size.y * (HIT_LINE_FRAC - TRAVEL_FRAC)
	var height := view_size.y * HIT_LINE_FRAC - top
	for i in int(Logic.DANCE["LANES"]):
		var x := lane_x(i)
		var alpha := 0.07 + _lane_flash[i] * 1.6
		draw_rect(Rect2(x - span * 0.46, top, span * 0.92, height), Color(LANE_COLORS[i], alpha))
		draw_rect(
			Rect2(x - span * 0.46, top, span * 0.92, height),
			Color(LANE_COLORS[i], 0.22),
			false,
			2.0
		)


func _draw_hit_line() -> void:
	var y := view_size.y * HIT_LINE_FRAC
	var span := lane_span()
	draw_line(
		Vector2(view_size.x * 0.5 - span * 1.5, y),
		Vector2(view_size.x * 0.5 + span * 1.5, y),
		Color(1.0, 1.0, 1.0, 0.55),
		3.0
	)
	for i in int(Logic.DANCE["LANES"]):
		var pulse := 1.0 + _lane_flash[i] * 2.2
		draw_arc(
			Vector2(lane_x(i), y),
			span * 0.34 * pulse,
			0.0,
			TAU,
			28,
			Color(LANE_COLORS[i], 0.85),
			3.0
		)


func _draw_notes() -> void:
	var span := lane_span()
	for i in range(_head, notes.size()):
		var n: Dictionary = notes[i]
		if bool(n["hit"]) or bool(n["missed"]):
			continue
		var life := Logic.note_lifecycle(float(n["time"]), song_time, tune)
		if life == "future":
			break
		if life != "visible":
			continue
		var lane := int(n["lane"])
		var pos := Vector2(lane_x(lane), note_y(float(n["time"])))
		var r := span * 0.3
		draw_circle(pos, r * 1.5, Color(LANE_COLORS[lane], 0.18))
		draw_circle(pos, r, LANE_COLORS[lane])
		draw_circle(pos, r * 0.55, Color(1.0, 1.0, 1.0, 0.75))


func _draw_bursts() -> void:
	var life := float(Logic.DANCE_JUICE["BURST_LIFE_SEC"])
	var y := view_size.y * HIT_LINE_FRAC
	for b in _bursts:
		var f := 1.0 - float(b["t"]) / life
		var end_scale := float(
			Logic.DANCE_JUICE[
				"BURST_SCALE_PERFECT" if str(b["kind"]) == "perfect" else "BURST_SCALE_GOOD"
			]
		)
		draw_arc(
			Vector2(float(b["x"]), y),
			lane_span() * 0.3 * (1.0 + (end_scale - 1.0) * f),
			0.0,
			TAU,
			30,
			Color(1.0, 0.98, 0.85, 1.0 - f),
			3.0
		)


func _draw_gooby() -> void:
	var t := tier()
	var pos := Vector2(view_size.x * 0.5, view_size.y * 0.85)
	var beat := sin(_bob * (float(Logic.DANCE["BPM"]) / 60.0) * TAU)
	var s := (view_size.y * 0.048) * (1.0 + 0.06 * t) * (1.0 + 0.05 * beat)
	var sway := beat * (4.0 + 5.0 * t)
	pos.x += sway
	draw_circle(pos + Vector2(0.0, s * 0.85), s * 0.95, Color(0.99, 0.9, 0.66))
	draw_circle(pos, s * 0.72, Color(0.99, 0.93, 0.74))
	for side in [-1.0, 1.0]:
		draw_circle(pos + Vector2(side * s * 0.34, -s * 0.85), s * 0.24, Color(0.99, 0.93, 0.74))
		draw_circle(pos + Vector2(side * s * 0.26, -s * 0.05), s * 0.1, Color(0.22, 0.18, 0.16))
	draw_circle(pos + Vector2(0.0, s * 0.2), s * 0.1, Color(0.96, 0.62, 0.68))
	# Arme heben sich mit der Serienstufe.
	for side in [-1.0, 1.0]:
		draw_line(
			pos + Vector2(side * s * 0.7, s * 0.7),
			pos + Vector2(side * s * (1.2 + 0.2 * t), s * (0.7 - 0.45 * t - 0.2 * beat)),
			Color(0.99, 0.9, 0.66),
			s * 0.22
		)


func _draw_mirror_ball() -> void:
	var pop := 1.0
	if _ball_pop > 0.0:
		var f := _ball_pop / float(Logic.DANCE_JUICE["BALL_POP_SEC"])
		pop = 1.0 + (float(Logic.DANCE_JUICE["BALL_POP_SCALE"]) - 1.0) * f
	var center := Vector2(view_size.x * 0.5, view_size.y * 0.055)
	var r := view_size.y * 0.028 * pop
	draw_line(Vector2(center.x, 0.0), center, Color(0.6, 0.6, 0.7), 2.0)
	draw_circle(center, r * 1.6, Color(0.8, 0.85, 1.0, 0.14))
	draw_circle(center, r, Color(0.72, 0.78, 0.95))
	for i in 8:
		var a := _ball_spin + i * TAU / 8.0
		draw_line(
			center + Vector2(cos(a), sin(a)) * r * 0.25,
			center + Vector2(cos(a), sin(a)) * r,
			Color(0.95, 0.97, 1.0, 0.75),
			2.0
		)


func _draw_encore() -> void:
	var alpha := 0.25 + 0.15 * sin(_bob * 12.0)
	draw_rect(Rect2(Vector2.ZERO, view_size), Color(1.0, 0.8, 0.45, alpha * 0.35))
	draw_string(
		ThemeService.font(800),
		Vector2(0.0, view_size.y * 0.2),
		I18nService.t("mg.danceParty.encore"),
		HORIZONTAL_ALIGNMENT_CENTER,
		view_size.x,
		30,
		Color(1.0, 0.9, 0.6, 0.9)
	)
