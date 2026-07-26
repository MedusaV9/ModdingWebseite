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
##
## ECHTER 3D-DISCO-CLUB (FB-4, DancePartyStage3D): Noten fallen als leuchtende
## 3D-Kugeln durch Glasbahnen auf Trefferringe, Spiegelkugel + Scheinwerfer
## schwenken im Takt, Gooby (echtes Rig) tanzt auf dem Kachelboden. Alle
## Bildschirm-Anker (lane_x/note_y) bleiben die 2D-Rechnung — die Bühne
## rechnet sie nur in Weltkoordinaten um. Nur die Zugabe-Einblendung bleibt
## als 2D-Overlay.

const Logic := preload("res://scripts/minigames/games/dance_party/dance_party_logic.gd")
const Stage := preload("res://scripts/minigames/games/dance_party/dance_party_stage3d.gd")

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
var _lane_flash: Array[float] = [0.0, 0.0, 0.0]
var _ball_spin := 0.0
var _ball_pop := 0.0
var _bob := 0.0
var _score_label: Label
var _combo_label: Label
var _hint_label: Label
var _stage: Node3D


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = Logic.apply_difficulty(Logic.DANCE_TUNING, ctx.difficulty)
	tally = Logic.create_tally()
	fever = Logic.create_fever_chain()
	endless_state = Logic.create_endless_state()
	song_time = -float(tune["LEAD_IN_SEC"])
	_append_segment()
	_stage = Stage.new()
	_stage.name = "Club3D"
	add_child(_stage)
	_stage.setup_stage()
	if ctx.juice != null:
		ctx.juice.world_environment = _stage.stage.world_env
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
	if _stage != null:
		_stage.frame(view_size)
		var xs: Array[float] = [lane_x(0), lane_x(1), lane_x(2)]
		_stage.layout(
			xs,
			view_size.y * (HIT_LINE_FRAC - TRAVEL_FRAC),
			view_size.y * HIT_LINE_FRAC,
			lane_span()
		)
	_layout_hud()
	queue_redraw()


## HUD IMMER aus dem Viewport-Rect stellen: unter canvas_items-Stretch sind
## Canvas-Einheiten ≠ Fensterpixel, apply_view-Größen können abweichen.
func _layout_hud() -> void:
	if _score_label == null:
		return
	var vp := get_viewport_rect().size
	_score_label.position = Vector2(16.0, 10.0)
	_combo_label.position = Vector2(16.0, 48.0)
	_hint_label.position = Vector2(vp.x * 0.5 - 160.0, vp.y - 44.0)
	_hint_label.size = Vector2(320.0, 36.0)


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
	_sync_stage(delta)
	_update_labels()
	queue_redraw()


## Sichtbare Noten als Bildschirm-Anker an die Bühne geben.
func _sync_stage(delta: float) -> void:
	var visible_notes: Array[Dictionary] = []
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
		visible_notes.append({"lane": lane, "x": lane_x(lane), "y": note_y(float(n["time"]))})
	var beat := sin(_bob * (float(Logic.DANCE["BPM"]) / 60.0) * TAU)
	var pop := 0.0
	if _ball_pop > 0.0:
		var f := _ball_pop / float(Logic.DANCE_JUICE["BALL_POP_SEC"])
		pop = (float(Logic.DANCE_JUICE["BALL_POP_SCALE"]) - 1.0) * f
	_stage.sync(
		visible_notes,
		_lane_flash,
		tier(),
		beat,
		_ball_spin,
		pop,
		Logic.encore_active(fever, song_time),
		_bob,
		delta
	)


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
		_stage.miss_fx()
		if ctx.juice != null:
			ctx.juice.shake(0.35)
			ctx.juice.sfx("game_miss")
			ctx.juice.show_combo(0)
		return
	_stage.hit_fx(at_x, kind == "perfect")
	_ball_pop = float(Logic.DANCE_JUICE["BALL_POP_SEC"])
	var combo := int(tally["combo"])
	if bool(chain["started"]):
		AudioDirector.try_play(self, "mg_golden")
		_stage.encore_fx()
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


## Nur noch HUD-Overlay: die Zugabe-Einblendung ist eine ANSAGE, keine
## Kulisse, und muss in jeder Kameralage sofort lesbar sein.
func _draw() -> void:
	if Logic.encore_active(fever, song_time):
		_draw_encore()


func _draw_encore() -> void:
	var vp := get_viewport_rect().size
	var alpha := 0.25 + 0.15 * sin(_bob * 12.0)
	draw_rect(Rect2(Vector2.ZERO, vp), Color(1.0, 0.8, 0.45, alpha * 0.35))
	draw_string(
		ThemeService.font(800),
		Vector2(0.0, vp.y * 0.2),
		I18nService.t("mg.danceParty.encore"),
		HORIZONTAL_ALIGNMENT_CENTER,
		vp.x,
		30,
		Color(1.0, 0.9, 0.6, 0.9)
	)
