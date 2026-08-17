extends MinigameBase
## Memory (memoryMatch) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## MemoryMatchLogic (zahlengleich zum Web, Bot-zertifiziert): 4×4 mit 8 Paaren,
## ab Gooby-Level 6 ein 4×6-Brett mit 12 Paaren, Score = 20 − Fehlgriffe +
## Zeitbonus (0–8) + 20 Board-Bonus. Nach drei sauberen Treffern in Folge gibt
## es EINEN Spick-Blick, der kurz alle Karten zeigt. Endlos kettet Boards, bis
## 12 Fehlgriffe zusammenkommen. Kein Fail-State im getakteten Modus.
##
## ECHTER 3D-PICKNICKTISCH (FB-4, MemoryMatchStage3D): 3D-Karten mit echten
## Food-Modellen auf einer Picknickdecke, Gooby (echtes Rig) schaut zu. Die
## Karten liegen per ground_point-Raycast EXAKT unter den 2D-Tap-Rechtecken —
## Eingabe und Trefferflächen bleiben zahlengleich, die MECHANIK unangetastet.
##
## W17/G5-Politur (NUR Präsentation, Audit mg-audit-b §7): Intro-Beat 1,5 s
## mit Wiesen-Totale + Ziel-Banner (Sim-Uhr und Merk-Fenster warten, M1),
## sichtbarer Countdown-Balken über dem Brett für Merk-/Spick-Fenster,
## lesbarer Fehlgriff-Text, „Brett geschafft!" als Gold-Banner (M7),
## _ui-skaliertes HUD samt Spick-Knopf (M9), Hint-Fade (M6) und Reduced-
## Motion-Gates an den Stage-Bursts (Q2). MemoryMatchLogic/RNG unangetastet.

const Stage := preload("res://scripts/minigames/games/memory_match/memory_match_stage3d.gd")
const HintFeel := preload("res://scripts/minigames/hint_feel.gd")

## W17/G5 M1: Intro-Beat (s) — Wiesen-Totale + Ziel-Banner; die Sim wartet.
const INTRO_S := 1.5
## W17/G5 M6: nach so vielen Sim-Sekunden blendet der Hinweis aus (harbor_hopper-Muster).
const HINT_FADE_SEC := 6.0
## Unter diesem Rest-Anteil pulsiert der Merk-/Spick-Countdown warnend.
const COUNTDOWN_WARN_FROM := 0.4

var tune: Dictionary = {}
var rng: GoobyRng
var layout: Dictionary = {}
var cards: Array[Dictionary] = []
var picked: Array[int] = []
var misses := 0
var matched_pairs := 0
## Paar-Serie ohne Fehlgriff (nur Anzeige/Feel — Combo-Ton steigt mit).
var match_streak := 0
var boards_cleared := 0
var elapsed := 0.0
var peek: Dictionary = {}
var reveal_left := 0.0
var peek_left := 0.0
var resolve_left := 0.0
var finished := false
var view_size := Vector2(390.0, 844.0)
var landscape := false

var _time_label: Label
var _miss_label: Label
var _hint_label: Label
var _peek_button: Button
var _grid_origin := Vector2.ZERO
var _card_size := Vector2(64.0, 78.0)
var _card_gap := Vector2(8.0, 10.0)
var _stage: Node3D
var _pulse := 0.0
var _ui := 1.0
var _intro_left := 0.0
var _banner := ""
var _banner_gold := false
var _banner_t := 0.0
var _banner_plate := StyleBoxFlat.new()
var _bar_plate := MgHudKit.progress_plate()
## W21: Milchglas-Plate hinter dem Hinweis (deliveryRush/teaParty-Muster) —
## die weiße Konturschrift lag direkt auf Wiese/Korb/Obst.
var _hint_plate := StyleBoxFlat.new()
## W21/P5: Frost-Pille hinter Zeit/Paare (Kit-Chip).
var _hud_plate := StyleBoxFlat.new()


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = MemoryMatchLogic.apply_difficulty(MemoryMatchLogic.MEMORY, ctx.difficulty)
	rng = ctx.rng()
	layout = MemoryMatchLogic.layout_for_level(_gooby_level())
	peek = {"cleanMatches": 0, "peekReady": false, "peekUsed": false}
	_deal_board()
	_stage = Stage.new()
	_stage.name = "Picknick3D"
	add_child(_stage)
	_stage.setup_stage()
	if ctx.juice != null:
		ctx.juice.world_environment = _stage.stage.world_env
	_build_hud()
	_fit_viewport()
	_banner_plate.set_corner_radius_all(12)
	# W17/G5 M1: Intro-Beat — Wiesen-Totale + Ziel-Banner; Sim-Uhr, Merk-
	# Fenster und Eingabe warten, Seeds/RNG-Reihenfolge bleiben unangetastet.
	_intro_left = INTRO_S
	_set_banner(I18nService.t("mg.memoryMatch.intro"), false, INTRO_S + 0.7)
	if is_inside_tree():
		get_viewport().size_changed.connect(_fit_viewport)


func end() -> void:
	super.end()
	finished = true


## Pflicht-Layouthook: beide Orientierungen laufen über DIESE Funktion.
## W17/G5 M9: der _ui-Faktor (Kurzkante/390, 0,75–3,0) skaliert alle HUD-Maße.
func apply_view(size: Vector2) -> void:
	if size.x > 1.0 and size.y > 1.0:
		view_size = size
	landscape = view_size.x > view_size.y
	_ui = MgHudKit.ui_scale(view_size)
	position = Vector2.ZERO
	var cols := int(layout.get("cols", 4))
	var rows := int(layout.get("rows", 4))
	# Das Brett bekommt den Platz zwischen HUD-Zeile und Hinweis/Spick-Knopf —
	# die Ränder wachsen mit dem HUD mit (M9), sonst kollidieren die Zeilen.
	var top := (96.0 if not landscape else 62.0) * _ui
	var bottom := (118.0 if not landscape else 76.0) * _ui
	var avail := Vector2(view_size.x - 32.0, maxf(80.0, view_size.y - top - bottom))
	var card_w := (avail.x - _card_gap.x * (cols - 1)) / float(cols)
	var card_h := (avail.y - _card_gap.y * (rows - 1)) / float(rows)
	# Web-Kartenverhältnis 0.82 : 1.0 halten, egal welche Achse begrenzt.
	var by_w := Vector2(card_w, card_w / 0.82)
	var by_h := Vector2(card_h * 0.82, card_h)
	_card_size = by_w if by_w.y * rows + _card_gap.y * (rows - 1) <= avail.y else by_h
	var board := Vector2(
		_card_size.x * cols + _card_gap.x * (cols - 1),
		_card_size.y * rows + _card_gap.y * (rows - 1)
	)
	# Etwas tiefer als mittig: darüber steht die 3D-Kulisse statt Leerraum.
	_grid_origin = Vector2((view_size.x - board.x) * 0.5, top + (avail.y - board.y) * 0.58)
	if _stage != null:
		# Erst die Kamera stellen, dann die Karten unter die Rechtecke raycasten.
		_stage.frame(view_size)
		var rects: Array[Rect2] = []
		var faces: Array[int] = []
		for i in cards.size():
			rects.append(Rect2(_card_pos(i), _card_size))
			faces.append(int(cards[i]["face"]))
		_stage.layout(rects, faces)
	_layout_hud()
	queue_redraw()


## HUD IMMER aus dem Viewport-Rect stellen: unter canvas_items-Stretch sind
## Canvas-Einheiten ≠ Fensterpixel, apply_view-Größen können abweichen.
## W21/P5: Zeit/Paare als Kit-Chip (Frost-Pille statt 34-px-Klotz mit Saum),
## Hinweis und Spick-Knopf mit Typo-MINIMUM (MgHudKit.font_px ≥ 14 px).
func _layout_hud() -> void:
	if _time_label == null:
		return
	var vp := get_viewport_rect().size
	var rows := int(layout.get("rows", 4))
	var board_h := _card_size.y * rows + _card_gap.y * (rows - 1)
	MgHudKit.style_chip(_time_label, _miss_label, _ui)
	MgHudKit.layout_chip(_time_label, _miss_label, _ui)
	var hint_w := minf(vp.x - 32.0 * _ui, 360.0 * _ui)
	var hint_font := MgHudKit.font_px(20.0, _ui)
	_hint_label.add_theme_font_size_override("font_size", hint_font)
	_hint_label.add_theme_constant_override("outline_size", int(5.0 * _ui))
	# W21 (Befund MM-1): der Hinweis bricht auf schmalen Hochkant-Viewports
	# in 2 Zeilen um — die feste 40-px-Höhe bei y−52 schob die zweite Zeile
	# unter die Viewport-Kante. Höhe jetzt aus dem ECHTEN Umbruch gemessen,
	# Unterkante mit Luft über dem Rand verankert. clamp_size zuerst: ein
	# direktes `size =` klemmt an der GECACHTEN Mindesthöhe (DR-1-Gotcha,
	# s. HintFeel) und machte das Label im Host kilometerhoch.
	var hint_h := hint_height(
		_hint_label.get_theme_font("font"), _hint_label.text, hint_w, hint_font
	)
	HintFeel.clamp_size(_hint_label, hint_w)
	_hint_label.position = Vector2((vp.x - hint_w) * 0.5, vp.y - hint_h - 10.0 * _ui)
	_hint_label.size = Vector2(hint_w, hint_h)
	_peek_button.add_theme_font_size_override("font_size", MgHudKit.font_px(20.0, _ui))
	# Touch-Floor 48 px bleibt auch unterm 0,75er-Boden erhalten; über
	# custom_minimum_size, weil size an der Content-Minimalgröße clampt.
	_peek_button.custom_minimum_size = Vector2(140.0 * _ui, maxf(48.0, 48.0 * _ui))
	_peek_button.size = _peek_button.custom_minimum_size
	_peek_button.position = Vector2(
		vp.x * 0.5 - _peek_button.size.x * 0.5, _grid_origin.y + board_h + 12.0 * _ui
	)


func _gooby_level() -> int:
	var state := get_node_or_null(^"/root/GameState")
	if state != null and state.has_method("get_value"):
		return int(state.get_value("progression.level", 1))
	return 1


func _deal_board() -> void:
	var deck := MemoryMatchLogic.build_deck(int(layout["pairs"]), rng)
	cards = []
	for face in deck:
		cards.append({"face": face, "state": "down", "flip": 0.0})
	picked = []
	matched_pairs = 0
	reveal_left = float(tune["REVEAL_SEC"])


func _build_hud() -> void:
	_time_label = Label.new()
	_time_label.theme_type_variation = &"HeadlineLabel"
	add_child(_time_label)
	_miss_label = Label.new()
	_miss_label.theme_type_variation = &"CaptionLabel"
	add_child(_miss_label)
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"SoftLabel"
	_hint_label.text = I18nService.t("mg.memoryMatch.hint")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_hint_label)
	_peek_button = Button.new()
	_peek_button.text = I18nService.t("mg.memoryMatch.peek_button")
	_peek_button.visible = false
	_peek_button.pressed.connect(_use_peek)
	add_child(_peek_button)
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# W21/P5: Zeit/Paare sitzen als Tinte auf der Kit-Frost-Pille — der
	# helle Saum-Klotz („weiß+Saum"-Welt aus dem Befund) ist Geschichte.
	# W21: Hinweis als Tinte auf Milchglas (deliveryRush.make_hint-Muster) —
	# weiße Schrift lag direkt auf Wiese/Korb/Obst (Befund MM-1).
	_hint_label.add_theme_color_override("font_color", Color(0.42, 0.24, 0.16))
	_hint_label.add_theme_color_override("font_outline_color", Color(1.0, 1.0, 1.0, 0.75))
	_hint_plate.set_corner_radius_all(12)
	_layout_hud()
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	_pulse += delta
	# W17/G5 M1: Intro-Beat — die Kamera schwebt aus der Wiesen-Totale an
	# den Tisch; Sim-Uhr (elapsed) UND Merk-Fenster (reveal_left) warten so
	# lange, der Lauf bleibt zahlengleich (w13c-Crosscheck).
	if _intro_left > 0.0:
		_intro_left = maxf(0.0, _intro_left - delta)
		_banner_t = maxf(0.0, _banner_t - delta)
		_stage.establish(1.0 if _reduced_motion() else 1.0 - _intro_left / INTRO_S)
		_sync_stage(delta)
		_update_labels()
		queue_redraw()
		return
	elapsed += delta
	_banner_t = maxf(0.0, _banner_t - delta)
	if reveal_left > 0.0:
		reveal_left = maxf(0.0, reveal_left - delta)
	if peek_left > 0.0:
		peek_left = maxf(0.0, peek_left - delta)
	if resolve_left > 0.0:
		resolve_left = maxf(0.0, resolve_left - delta)
		if resolve_left <= 0.0:
			_resolve_pick()
	_sync_stage(delta)
	_update_labels()
	queue_redraw()


func _sync_stage(delta: float) -> void:
	var shows: Array[bool] = []
	for card in cards:
		shows.append(_face_visible(card))
	_stage.sync(cards, shows, _pulse, delta)


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished or reveal_left > 0.0 or peek_left > 0.0:
		return
	if _intro_left > 0.0:
		return
	var pressed := event is InputEventScreenTouch and (event as InputEventScreenTouch).pressed
	if not pressed:
		return
	var index := _card_at((event as InputEventScreenTouch).position)
	if index < 0:
		return
	var card: Dictionary = cards[index]
	var flip_state := {
		"phase": "play",
		"peeking": peek_left > 0.0,
		"pickedCount": picked.size(),
		"cardState": str(card["state"]),
	}
	if not MemoryMatchLogic.can_flip_card(flip_state) or resolve_left > 0.0:
		return
	card["state"] = "up"
	picked.append(index)
	AudioDirector.try_play(self, "mg_good", 1.05)
	if picked.size() == 2:
		resolve_left = float(tune["FLIP_SEC"]) + 0.22


func _resolve_pick() -> void:
	if picked.size() < 2:
		return
	var a: Dictionary = cards[picked[0]]
	var b: Dictionary = cards[picked[1]]
	var hit := MemoryMatchLogic.is_match(int(a["face"]), int(b["face"]))
	var pos := _card_center(picked[1])
	if hit:
		a["state"] = "matched"
		b["state"] = "matched"
		matched_pairs += 1
		match_streak += 1
		# Q2: Reduced-Motion-Gate an der eigenen Burst-Call-Site (Kit tabu).
		_stage.match_fx(picked[1], _reduced_motion())
		# Paar-Serie klettert hörbar (Halbton pro Treffer in Folge).
		AudioDirector.try_play(self, "mg_perfect", FeelSfx.combo_pitch(match_streak))
		# W21/P5 Feier-Beat: „Paar gefunden!" als Kit-Beat (Gold-Pille +
		# Sparkle, MotionKit/RM-gated) — der ★-float_text ging unter.
		MgHudKit.feier_beat(self, view_size, _ui, I18nService.t("mg.hudkit.beat_paar"))
		if ctx.juice != null:
			ctx.juice.ring_burst(self, pos, AcTokens.GOLD, 70.0)
			ctx.juice.burst(self, pos, AcTokens.GOLD, 12)
			ctx.juice.hit_freeze(45)
			ctx.juice.bloom_pulse(0.4)
			if match_streak >= 2:
				ctx.juice.show_combo(match_streak)
	else:
		a["state"] = "down"
		b["state"] = "down"
		misses += 1
		match_streak = 0
		_stage.miss_fx(picked[1], _reduced_motion())
		AudioDirector.try_play(self, "mg_junk", 0.95)
		if ctx.juice != null:
			ctx.juice.shake(0.2)
			ctx.juice.sfx("game_miss")
			ctx.juice.show_combo(0)
			# W17/G5: lesbarer Fehlgriff — helle Creme MIT der dunklen
			# float_text-Outline über der zweiten Karte (Oops-Klasse).
			ctx.juice.float_text(
				pos - Vector2(0.0, 26.0 * _ui),
				I18nService.t("mg.memoryMatch.oops"),
				AcTokens.BG_CREAM
			)
	picked = []
	peek = MemoryMatchLogic.advance_peek_progress(peek, hit)
	if MemoryMatchLogic.can_use_peek(peek) and not _peek_button.visible:
		_peek_button.visible = true
		AudioDirector.try_play(self, "mg_combo")
		if ctx.juice != null:
			ctx.juice.float_text(
				pos - Vector2(0.0, 40.0),
				I18nService.t("mg.memoryMatch.peek_ready"),
				AcTokens.TEAL_DARK
			)
	ctx.report_score(_live_score(), 0)
	if MemoryMatchLogic.endless_should_end(misses, tune):
		_finish()
		return
	if matched_pairs >= int(layout["pairs"]):
		_board_cleared()


func _board_cleared() -> void:
	boards_cleared += 1
	_stage.cleared_fx()
	AudioDirector.try_play(self, "mg_win")
	if ctx.juice != null:
		ctx.juice.bloom_pulse(1.0)
		ctx.juice.win_moment()
	# W17/G5 M7: „Brett geschafft!" als Gold-Banner mit Plate + Kontur —
	# der dunkelgrüne float_text ging vor der Wiese unter (Oops-Klasse).
	_set_banner(I18nService.t("mg.memoryMatch.cleared"), true, 2.2)
	queue_redraw()
	if not bool(tune["ENDLESS"]):
		_finish()
		return
	# §G5.4 Endlos: Boards ketten weiter, nur die Fehlgriffe zählen mit.
	_deal_board()


func _use_peek() -> void:
	if not MemoryMatchLogic.can_use_peek(peek) or not is_active():
		return
	peek["peekUsed"] = true
	peek_left = float(tune["PEEK_SEC"])
	_peek_button.visible = false
	_stage.peek_fx()
	AudioDirector.try_play(self, "mg_golden")
	if ctx.juice != null:
		ctx.juice.bloom_pulse(0.7)
		ctx.juice.float_text(
			Vector2(view_size.x * 0.5 - 90.0, view_size.y * 0.32),
			I18nService.t("mg.memoryMatch.peek"),
			AcTokens.TEAL_DARK
		)


func _live_score() -> int:
	return MemoryMatchLogic.memory_score(misses, elapsed, layout, tune)


func _finish() -> void:
	if finished:
		return
	finished = true
	running = false
	(
		ctx
		. report_end(
			{
				"score": _live_score(),
				"misses": misses,
				"boards": maxi(1, boards_cleared),
				"elapsed": elapsed,
			}
		)
	)


func _update_labels() -> void:
	if bool(tune["ENDLESS"]):
		_time_label.text = I18nService.t(
			"mg.memoryMatch.misses", {"n": misses, "max": int(tune["ENDLESS_MISS_FLIPS"])}
		)
	else:
		_time_label.text = I18nService.t("mg.game.time", {"sec": int(elapsed)})
	_miss_label.text = I18nService.t(
		"mg.memoryMatch.pairs", {"n": matched_pairs, "max": int(layout["pairs"])}
	)
	_hint_label.modulate.a = _hint_alpha()


## M6: der Hinweis blendet nach ein paar Sim-Sekunden aus (harbor_hopper-
## Muster) — elapsed wartet im Intro, der Fade startet also fair.
func _hint_alpha() -> float:
	return clampf((HINT_FADE_SEC - elapsed) / 1.2, 0.0, 1.0)


## PURE Hinweis-Höhe (testbar, W21): echter Umbruch bei `width` plus Luft —
## die feste 40-px-Höhe schob die zweite Zeile unters Bild (Befund MM-1).
static func hint_height(font: Font, text: String, width: float, font_size: int) -> float:
	var wrapped := font.get_multiline_string_size(
		text, HORIZONTAL_ALIGNMENT_CENTER, width, font_size
	)
	return wrapped.y + 8.0


func _set_banner(text: String, gold := false, sec := 1.4) -> void:
	_banner = text
	_banner_gold = gold
	_banner_t = sec


## Rest-Anteil [0..1] des sichtbaren Zeitfensters: Merk-Fenster nach dem
## Geben bzw. Spick-Blick; 0 = kein Fenster aktiv (PUR für Tests). Vorher
## liefen reveal_left/peek_left unsichtbar ab — der W17/G5-Countdown-Balken
## macht das Zudecken vorhersehbar.
func countdown_frac() -> float:
	if reveal_left > 0.0:
		return clampf(reveal_left / maxf(0.001, float(tune["REVEAL_SEC"])), 0.0, 1.0)
	if peek_left > 0.0:
		return clampf(peek_left / maxf(0.001, float(tune["PEEK_SEC"])), 0.0, 1.0)
	return 0.0


## 2D-Overlay überm Tisch (W21/P5 im Kit-Standard): Frost-Pille hinter
## Zeit/Paare, Milchglas hinter dem Hinweis, Kit-Progress für Merk-/Spick-
## Fenster + der Kit-Banner (Intro-Ziel, Brett-geschafft-Gold).
func _draw() -> void:
	if _time_label == null:
		return
	MgHudKit.draw_chip(self, _hud_plate, _time_label, _miss_label, _ui)
	var hint_a := _hint_alpha()
	if hint_a > 0.0:
		_hint_plate.bg_color = MgHudKit.plate_color(MgHudKit.PLATE_ALPHA * hint_a)
		draw_style_box(
			_hint_plate, Rect2(_hint_label.position - Vector2(0.0, 2.0), _hint_label.size)
		)
	_draw_countdown()
	_draw_banner()


func _draw_countdown() -> void:
	var frac := countdown_frac()
	if frac <= 0.0:
		return
	var cols := int(layout.get("cols", 4))
	var board_w := _card_size.x * cols + _card_gap.x * (cols - 1)
	var bar := Rect2(
		Vector2(_grid_origin.x, _grid_origin.y - 18.0 * _ui), Vector2(board_w, MgHudKit.bar_h(_ui))
	)
	var color := Color(AcTokens.TEAL, 0.92)
	if frac <= COUNTDOWN_WARN_FROM:
		# Letzte 40 %: Amber + Puls — „gleich decken sich die Karten!"
		# (Reduced Motion: konstant statt pulsierend).
		var beat := 0.9 if _reduced_motion() else 0.65 + 0.35 * sin(_pulse * 10.0)
		color = Color(AcTokens.YELLOW_DARK, beat)
	MgHudKit.draw_progress(self, _bar_plate, bar, frac, color)


## Banner im Kit-Standard (W21/P5): EINE Größe/Optik über alle Spiele —
## Intro-Ziel und Brett-geschafft-Gold; lange Texte brechen um.
func _draw_banner() -> void:
	MgHudKit.draw_banner(
		self, _banner_plate, get_viewport_rect().size, _ui, _banner, _banner_t, _banner_gold
	)


## Reduced-Motion-Abfrage (Duck-Typing wie im JuiceKit — ohne Autoload = aus).
func _reduced_motion() -> bool:
	if not is_inside_tree():
		return true
	var settings := get_node_or_null(^"/root/AppSettings")
	if settings != null and settings.has_method("is_reduced_motion"):
		return settings.is_reduced_motion()
	return false


## W17/G5: tote Ternary bereinigt — `return -1 if cols > 0 else -1` lieferte
## in beiden Zweigen −1, der Treffer kommt ohnehin aus der Schleife.
func _card_at(screen: Vector2) -> int:
	for i in cards.size():
		if Rect2(_card_pos(i), _card_size).has_point(screen):
			return i
	return -1


func _card_pos(index: int) -> Vector2:
	var cols := int(layout["cols"])
	var col := index % cols
	var row := index / cols
	return (
		_grid_origin
		+ Vector2(col * (_card_size.x + _card_gap.x), row * (_card_size.y + _card_gap.y))
	)


func _card_center(index: int) -> Vector2:
	return _card_pos(index) + _card_size * 0.5


func _face_visible(card: Dictionary) -> bool:
	return (
		reveal_left > 0.0
		or peek_left > 0.0
		or str(card["state"]) == "up"
		or str(card["state"]) == "matched"
	)

# Karten, Decke, Kulisse und Gooby rendert die 3D-Bühne (MemoryMatchStage3D);
# 2D bleiben HUD-Labels, Spick-Knopf sowie Countdown-Balken + Banner (_draw).
