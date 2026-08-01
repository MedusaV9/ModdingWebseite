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
##
## W17/G4-Politur (NUR Präsentation, Sim/Timing zertifiziert unangetastet):
## Hit-Quality-Popup „Perfekt!/Gut!“ am getroffenen Ring (M3/M7, farblich
## gestuft), _ui-Skalierung des HUD samt Konturen, dunklen Plates und
## Hint-Fade (M9/M7/M6), Zugabe-Banner auf Plate mit Kontur (M7) und ein
## Intro, das am BESTEHENDEN musikalischen Vorlauf (song_time −2,4…0)
## andockt: Ziel-Banner + „Spot an“ — KEIN zusätzliches Sim-Gate, der Lauf
## bleibt zahlengleich. Eigene FX sind an der Call-Site Reduced-Motion-
## gegatet. Die Club-Seitenwände (Quer-Füllung, M2/M5) leben in der Bühne.

const Logic := preload("res://scripts/minigames/games/dance_party/dance_party_logic.gd")
const Stage := preload("res://scripts/minigames/games/dance_party/dance_party_stage3d.gd")
const Timing := preload("res://scripts/minigames/games/dance_party/dance_timing.gd")

## Bildschirmhöhe der Trefferlinie (Anteil von oben).
const HIT_LINE_FRAC := 0.74
## Höhe der Anflugstrecke als Anteil der Viewport-Höhe.
const TRAVEL_FRAC := 0.66
## W17 M9: Entwurfs-Kurzkante — alle HUD-Pixelmaße skalieren damit.
const DESIGN_SHORT := 390.0
## Dunkle Tinten-Kontur (M7): hebt die helle Club-Schrift von Kegeln/Glow ab.
const OUTLINE_INK := Color(0.12, 0.07, 0.2, 0.92)
## Lebensdauer eines Hit-Quality-Popups (s) — kurz, die nächste Note kommt.
const HIT_POP_SEC := 0.75
## Farbstufen der Trefferwertung (M3/M7): Gold = perfekt, Eisblau = gut
## (dieselben Töne wie die Ring-Bursts — eine Farbsprache).
const POP_PERFECT := Color(1.0, 0.85, 0.4)
const POP_GOOD := Color(0.6, 0.85, 1.0)

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
## W15/TECHKIT (Doc G §9 R5): kompensierte Timing-Quelle — Note-Position und
## Treffer-Fenster laufen über timing.play_time(song_time); Score-Formel,
## Rundendauer und Fieber/Zugabe bleiben auf der rohen Uhr (zahlengleich).
var timing := Timing.new()

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
## W17 M9: HUD-Skalenfaktor (Kurzkante/390, geklemmt 0,75…3,0).
var _ui := 1.0
## W17 M3/M7: lebende Hit-Quality-Popups ({text, color, perfect, x, t, rise}).
var _hit_pops: Array[Dictionary] = []
var _hud_plate := StyleBoxFlat.new()
var _hint_plate := StyleBoxFlat.new()
var _banner_plate := StyleBoxFlat.new()
var _encore_plate := StyleBoxFlat.new()


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = Logic.apply_difficulty(Logic.DANCE_TUNING, ctx.difficulty)
	tally = Logic.create_tally()
	fever = Logic.create_fever_chain()
	endless_state = Logic.create_endless_state()
	song_time = -float(tune["LEAD_IN_SEC"])
	timing = Timing.from_audio_server(Timing.manual_offset_from_state(_save_state()))
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
## W17 M9: der _ui-Faktor skaliert alle HUD-Maße mit der Kurzkante.
func apply_view(size: Vector2) -> void:
	if size.x > 1.0 and size.y > 1.0:
		view_size = size
	landscape = view_size.x > view_size.y
	_ui = ui_scale_for(view_size)
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


## W17 M9: HUD-Skalenfaktor aus der Kurzkante (Referenz 390 px, 0,75…3,0).
static func ui_scale_for(size: Vector2) -> float:
	return clampf(minf(size.x, size.y) / DESIGN_SHORT, 0.75, 3.0)


## Farbstufe der Trefferwertung (M3): Gold für perfekt, Eisblau für gut.
static func hit_pop_color(kind: String) -> Color:
	return POP_PERFECT if kind == "perfect" else POP_GOOD


## Hinweis-Fade (M6): voll bis Songsekunde 4, weich aus bis 5,5 — die erste
## Note fällt erst bei 7,2 s, das Feld gehört dann ganz dem Geschehen.
static func hint_alpha_for(song_t: float) -> float:
	return clampf(1.0 - (song_t - 4.0) / 1.5, 0.0, 1.0)


## Intro-Fortschritt 0…1 über den BESTEHENDEN musikalischen Vorlauf
## (song_time −LEAD_IN…0) — kein eigenes Gate, nur eine Leselinse darauf.
static func intro_progress(song_t: float, lead_in: float) -> float:
	return clampf(1.0 + song_t / maxf(lead_in, 0.001), 0.0, 1.0)


## Alpha des Ziel-Banners (M1): blendet mit dem Vorlauf ein und bis 0,9 s
## nach Songstart weich aus (die erste Note ist erst bei 7,2 s unterwegs).
static func intro_banner_alpha(song_t: float, lead_in: float) -> float:
	var fade_in := (song_t + lead_in) / 0.3
	var fade_out := (0.9 - song_t) / 0.5
	return clampf(minf(fade_in, fade_out), 0.0, 1.0)


## HUD IMMER aus dem Viewport-Rect stellen: unter canvas_items-Stretch sind
## Canvas-Einheiten ≠ Fensterpixel, apply_view-Größen können abweichen.
## W17 M9: skalierte Maße statt Fix-Pixeln (Krümel-HUD auf Tablets), dazu
## Konturen (M7) — die Basisgrößen 34/15/20 sind der Theme-Look bei Faktor 1.
func _layout_hud() -> void:
	if _score_label == null:
		return
	var vp := get_viewport_rect().size
	_score_label.position = Vector2(16.0, 10.0) * _ui
	_score_label.add_theme_font_size_override("font_size", int(34.0 * _ui))
	_score_label.add_theme_constant_override("outline_size", int(6.0 * _ui))
	_combo_label.position = Vector2(16.0, 48.0) * _ui
	_combo_label.add_theme_font_size_override("font_size", int(15.0 * _ui))
	_combo_label.add_theme_constant_override("outline_size", int(5.0 * _ui))
	var hint_w := minf(vp.x - 32.0 * _ui, 380.0 * _ui)
	_hint_label.add_theme_font_size_override("font_size", int(20.0 * _ui))
	_hint_label.add_theme_constant_override("outline_size", int(5.0 * _ui))
	# ERST die Breite setzen: Autowrap rechnet die Mindesthöhe an der AKTUELLEN
	# Breite — frisch instanziiert ist die ~1 px, jede Silbe bricht um und die
	# Höhen-Klemme bleibt riesig hängen (Hinweis ragte unter die Sichtkante).
	_hint_label.size = Vector2(hint_w, 0.0)
	var hint_h := maxf(40.0 * _ui, _hint_label.get_minimum_size().y + 12.0 * _ui)
	_hint_label.position = Vector2((vp.x - hint_w) * 0.5, vp.y - hint_h - 12.0 * _ui)
	_hint_label.size = Vector2(hint_w, hint_h)
	_hud_plate.set_corner_radius_all(int(10.0 * _ui))
	_hint_plate.set_corner_radius_all(int(10.0 * _ui))


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
	_age_pops(delta)
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
	# W17 M1: „Spot an“ im musikalischen Vorlauf (NACH sync, damit der Ramp
	# die Takt-Werte des Frames übersteuert). Reduced Motion: Licht steht
	# sofort — die Lichtfahrt ist eigener FX (Call-Site-Gate).
	var intro_f := intro_progress(song_time, float(tune["LEAD_IN_SEC"]))
	if intro_f < 1.0 and not _reduced_motion():
		_stage.intro_spot(intro_f)
	_update_labels()
	queue_redraw()


## Sichtbare Noten als Bildschirm-Anker an die Bühne geben.
func _sync_stage(delta: float) -> void:
	var visible_notes: Array[Dictionary] = []
	for i in range(_head, notes.size()):
		var n: Dictionary = notes[i]
		if bool(n["hit"]) or bool(n["missed"]):
			continue
		var life := Logic.note_lifecycle(float(n["time"]), play_time(), tune)
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
		delta,
		_reduced_motion()
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


## W15/TECHKIT: die latenz-kompensierte Songzeit (Basis + manueller Offset)
## — DIE Zeitachse für Note-Position, Sichtbarkeit und Treffer-Fenster.
func play_time() -> float:
	return timing.play_time(song_time)


## Save-Zustand für den Kalibrier-Offset (ohne GameState = {} → Offset 0).
func _save_state() -> Dictionary:
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("state"):
		return gs.state()
	return {}


## Bildschirm-y einer Note zur aktuellen (kompensierten) Songzeit.
func note_y(note_time: float) -> float:
	var travel := float(tune["NOTE_TRAVEL_SEC"])
	var t := clampf((note_time - play_time()) / travel, -0.4, 1.4)
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
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_hint_label)
	# Der Discoboden ist dunkel — die Theme-Schriftfarben sind es auch.
	_score_label.add_theme_color_override("font_color", Color(1.0, 0.96, 0.9))
	_combo_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.5))
	_hint_label.add_theme_color_override("font_color", Color(0.88, 0.84, 0.96))
	# W17 M7: dunkle Tinten-Konturen — lesbar auch ÜBER hellen Lichtkegeln.
	_score_label.add_theme_color_override("font_outline_color", OUTLINE_INK)
	_combo_label.add_theme_color_override("font_outline_color", OUTLINE_INK)
	_hint_label.add_theme_color_override("font_outline_color", Color(OUTLINE_INK, 0.7))
	_hud_plate.bg_color = Color(0.09, 0.05, 0.16, 0.62)
	_banner_plate.set_border_width_all(2)
	_encore_plate.set_border_width_all(2)
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
		if Logic.note_lifecycle(float(n["time"]), play_time(), tune) != "expired":
			break
		n["missed"] = true
		_head += 1
		_judge("miss", lane_x(int(n["lane"])))


func _tap_lane(lane: int) -> void:
	_lane_flash[lane] = 0.18
	var window: Array[Dictionary] = notes.slice(_head, mini(notes.size(), _head + 48))
	var idx := Logic.judge_tap(window, lane, play_time(), tune)
	if idx == -1:
		return
	var note: Dictionary = window[idx]
	note["hit"] = true
	var kind := Logic.classify_hit(float(note["time"]) - play_time(), tune)
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
	_spawn_hit_pop(kind, at_x)
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


## W17 M3/M7: Hit-Quality-Popup am getroffenen Ring — NUR Anzeige der schon
## gebuchten Bewertung. Unter Reduced Motion steht das Popup (kein Aufstieg);
## der Text bleibt als Information sichtbar (Call-Site-Gate).
func _spawn_hit_pop(kind: String, at_x: float) -> void:
	var key := "mg.danceParty.perfect" if kind == "perfect" else "mg.danceParty.good"
	(
		_hit_pops
		. append(
			{
				"text": I18nService.t(key),
				"color": hit_pop_color(kind),
				"perfect": kind == "perfect",
				"x": at_x,
				"t": HIT_POP_SEC,
				"rise": not _reduced_motion(),
			}
		)
	)


func _age_pops(delta: float) -> void:
	for pop in _hit_pops:
		pop["t"] = float(pop["t"]) - delta
	while not _hit_pops.is_empty() and float(_hit_pops[0]["t"]) <= 0.0:
		_hit_pops.pop_front()


## Reduced-Motion-Abfrage (Duck-Typing wie im JuiceKit — ohne Autoload = aus).
func _reduced_motion() -> bool:
	if not is_inside_tree():
		return true
	var settings := get_node_or_null(^"/root/AppSettings")
	if settings != null and settings.has_method("is_reduced_motion"):
		return settings.is_reduced_motion()
	return false


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
	# W17 M6: der Hinweis blendet aus, bevor die erste Note fällt.
	_hint_label.modulate.a = hint_alpha_for(song_time)


## HUD-Overlay: dunkle Plates (M6), Hit-Quality-Popups (M3/M7), die
## Zugabe-ANSAGE auf Plate mit Kontur (M7) und das Ziel-Banner im
## musikalischen Vorlauf (M1) — in jeder Kameralage sofort lesbar.
func _draw() -> void:
	if tune.is_empty():
		return
	_draw_hud_plates()
	_draw_hit_pops()
	if Logic.encore_active(fever, song_time):
		_draw_encore()
	_draw_intro_banner()


## Dunkles Milchglas hinter Zeit/Serie und dem Hinweis (M6): helle Kegel
## und Noten zogen sonst direkt durch die Ziffern.
func _draw_hud_plates() -> void:
	if _score_label == null:
		return
	var pad := Vector2(12.0, 6.0) * _ui
	var wide := maxf(_score_label.size.x, _combo_label.size.x)
	var top_left := _score_label.position - pad
	var bottom_right := _combo_label.position + Vector2(wide, _combo_label.size.y) + pad
	draw_style_box(_hud_plate, Rect2(top_left, bottom_right - top_left))
	var hint_a := hint_alpha_for(song_time)
	if hint_a > 0.0:
		_hint_plate.bg_color = Color(0.09, 0.05, 0.16, 0.6 * hint_a)
		draw_style_box(
			_hint_plate, Rect2(_hint_label.position - Vector2(0.0, 2.0), _hint_label.size)
		)


## Trefferwertung am Ring (M3/M7): farblich gestuft (Gold/Eisblau), mit
## Tinten-Kontur, steigt auf und blendet aus (Reduced Motion: steht).
func _draw_hit_pops() -> void:
	if _hit_pops.is_empty():
		return
	var font := ThemeService.font(800)
	var hit_y := view_size.y * HIT_LINE_FRAC
	for pop in _hit_pops:
		var left := float(pop["t"]) / HIT_POP_SEC
		var alpha := clampf(left / 0.45, 0.0, 1.0)
		var rise := 46.0 * _ui * (1.0 - left) if bool(pop["rise"]) else 0.0
		var font_size := int((22.0 if bool(pop["perfect"]) else 19.0) * _ui)
		var w := 240.0 * _ui
		var at := Vector2(float(pop["x"]) - w * 0.5, hit_y - 64.0 * _ui - rise)
		var tint: Color = pop["color"]
		draw_string_outline(
			font,
			at,
			str(pop["text"]),
			HORIZONTAL_ALIGNMENT_CENTER,
			w,
			font_size,
			int(5.0 * _ui),
			Color(OUTLINE_INK, OUTLINE_INK.a * alpha)
		)
		draw_string(
			font,
			at,
			str(pop["text"]),
			HORIZONTAL_ALIGNMENT_CENTER,
			w,
			font_size,
			Color(tint, alpha)
		)


## Zugabe-Einblendung (M7): Goldpuls wie gehabt, die Ansage aber auf einer
## dunklen Plate mit Goldrand, Kontur und Umbruch.
func _draw_encore() -> void:
	var vp := get_viewport_rect().size
	var alpha := 0.25 + 0.15 * sin(_bob * 12.0)
	draw_rect(Rect2(Vector2.ZERO, vp), Color(1.0, 0.8, 0.45, alpha * 0.35))
	var font := ThemeService.font(800)
	var font_size := int(30.0 * _ui)
	var w := minf(vp.x * 0.9, 420.0 * _ui)
	var text := I18nService.t("mg.danceParty.encore")
	var text_size := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size)
	var top := vp.y * 0.16
	var pad := Vector2(20.0, 10.0) * _ui
	_encore_plate.set_corner_radius_all(int(14.0 * _ui))
	_encore_plate.bg_color = Color(0.16, 0.09, 0.24, 0.72)
	_encore_plate.border_color = Color(1.0, 0.85, 0.5, 0.9)
	var plate_pos := Vector2((vp.x - text_size.x) * 0.5, top) - pad
	draw_style_box(_encore_plate, Rect2(plate_pos, text_size + pad * 2.0))
	var at := Vector2((vp.x - w) * 0.5, top + font.get_ascent(font_size))
	draw_multiline_string_outline(
		font,
		at,
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		w,
		font_size,
		-1,
		int(6.0 * _ui),
		Color(0.25, 0.12, 0.05, 0.9)
	)
	draw_multiline_string(
		font, at, text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, -1, Color(1.0, 0.9, 0.6)
	)


## Ziel-Banner (M1/M7): dockt am musikalischen Vorlauf an (song_time < 0),
## Milchglas-Plate mit Kontur und Umbruch — KEIN zusätzliches Sim-Gate.
func _draw_intro_banner() -> void:
	var alpha := intro_banner_alpha(song_time, float(tune["LEAD_IN_SEC"]))
	if alpha <= 0.0:
		return
	var vp := get_viewport_rect().size
	var font := ThemeService.font(800)
	var font_size := int(26.0 * _ui)
	var w := minf(vp.x * 0.92, 460.0 * _ui)
	var text := I18nService.t("mg.danceParty.intro")
	var text_size := font.get_multiline_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size)
	var top := vp.y * 0.24
	var pad := Vector2(18.0, 10.0) * _ui
	_banner_plate.set_corner_radius_all(int(12.0 * _ui))
	_banner_plate.bg_color = Color(0.12, 0.07, 0.2, 0.78 * alpha)
	_banner_plate.border_color = Color(0.35, 0.79, 0.73, 0.8 * alpha)
	var plate_pos := Vector2((vp.x - text_size.x) * 0.5, top) - pad
	draw_style_box(_banner_plate, Rect2(plate_pos, text_size + pad * 2.0))
	var ink := Color(1.0, 0.96, 0.9, alpha)
	var rim := Color(OUTLINE_INK, 0.9 * alpha)
	var at := Vector2((vp.x - w) * 0.5, top + font.get_ascent(font_size))
	draw_multiline_string_outline(
		font, at, text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, -1, int(5.0 * _ui), rim
	)
	draw_multiline_string(font, at, text, HORIZONTAL_ALIGNMENT_CENTER, w, font_size, -1, ink)
