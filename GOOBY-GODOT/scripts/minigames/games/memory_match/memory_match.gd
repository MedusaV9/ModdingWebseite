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

const Stage := preload("res://scripts/minigames/games/memory_match/memory_match_stage3d.gd")

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
	var cols := int(layout.get("cols", 4))
	var rows := int(layout.get("rows", 4))
	# Das Brett bekommt den Platz zwischen HUD-Zeile und Hinweis/Spick-Knopf.
	var top := 96.0 if not landscape else 62.0
	var bottom := 118.0 if not landscape else 76.0
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
func _layout_hud() -> void:
	if _time_label == null:
		return
	var vp := get_viewport_rect().size
	var rows := int(layout.get("rows", 4))
	var board_h := _card_size.y * rows + _card_gap.y * (rows - 1)
	_time_label.position = Vector2(16.0, 10.0)
	_miss_label.position = Vector2(16.0, 48.0)
	_hint_label.position = Vector2(vp.x * 0.5 - 170.0, vp.y - 44.0)
	_hint_label.size = Vector2(340.0, 36.0)
	_peek_button.position = Vector2(vp.x * 0.5 - 70.0, _grid_origin.y + board_h + 12.0)
	_peek_button.size = Vector2(140.0, 48.0)


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
	# Heller Text + dunkler Saum: lesbar auf Wiese, Bäumen UND Decke.
	for label: Label in [_time_label, _miss_label, _hint_label]:
		label.add_theme_color_override("font_color", Color(1.0, 0.98, 0.94))
		label.add_theme_color_override("font_outline_color", Color(0.2, 0.3, 0.16, 0.9))
		label.add_theme_constant_override("outline_size", 7)
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	elapsed += delta
	_pulse += delta
	if reveal_left > 0.0:
		reveal_left = maxf(0.0, reveal_left - delta)
	if peek_left > 0.0:
		peek_left = maxf(0.0, peek_left - delta)
	if resolve_left > 0.0:
		resolve_left = maxf(0.0, resolve_left - delta)
		if resolve_left <= 0.0:
			_resolve_pick()
	var shows: Array[bool] = []
	for card in cards:
		shows.append(_face_visible(card))
	_stage.sync(cards, shows, _pulse, delta)
	_update_labels()
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if not is_active() or finished or reveal_left > 0.0 or peek_left > 0.0:
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
		_stage.match_fx(picked[1])
		# Paar-Serie klettert hörbar (Halbton pro Treffer in Folge).
		AudioDirector.try_play(self, "mg_perfect", FeelSfx.combo_pitch(match_streak))
		if ctx.juice != null:
			ctx.juice.float_text(pos, "★", AcTokens.GOLD)
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
		_stage.miss_fx(picked[1])
		AudioDirector.try_play(self, "mg_junk", 0.95)
		if ctx.juice != null:
			ctx.juice.shake(0.2)
			ctx.juice.sfx("game_miss")
			ctx.juice.show_combo(0)
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
		ctx.juice.float_text(
			Vector2(view_size.x * 0.5 - 90.0, view_size.y * 0.42),
			I18nService.t("mg.memoryMatch.cleared"),
			AcTokens.LEAF_DARK
		)
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


func _card_at(screen: Vector2) -> int:
	var cols := int(layout["cols"])
	for i in cards.size():
		if Rect2(_card_pos(i), _card_size).has_point(screen):
			return i
	return -1 if cols > 0 else -1


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

# Kein _draw mehr: Karten, Decke, Kulisse und Gooby rendert die 3D-Bühne
# (MemoryMatchStage3D); nur HUD-Labels und der Spick-Knopf bleiben 2D.
