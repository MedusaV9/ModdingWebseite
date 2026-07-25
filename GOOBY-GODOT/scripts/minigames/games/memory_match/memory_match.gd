extends MinigameBase
## Memory (memoryMatch) — Spiel-Szene. MECHANIK-Zahlen 1:1 aus
## MemoryMatchLogic (zahlengleich zum Web, Bot-zertifiziert): 4×4 mit 8 Paaren,
## ab Gooby-Level 6 ein 4×6-Brett mit 12 Paaren, Score = 20 − Fehlgriffe +
## Zeitbonus (0–8) + 20 Board-Bonus. Nach drei sauberen Treffern in Folge gibt
## es EINEN Spick-Blick, der kurz alle Karten zeigt. Endlos kettet Boards, bis
## 12 Fehlgriffe zusammenkommen. Kein Fail-State im getakteten Modus.
## Optik: Papier-Karten mit dicker Outline, Motive als gezeichnete Symbole.

var tune: Dictionary = {}
var rng: GoobyRng
var layout: Dictionary = {}
var cards: Array[Dictionary] = []
var picked: Array[int] = []
var misses := 0
var matched_pairs := 0
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


func setup(context: MinigameCtx) -> void:
	super.setup(context)
	tune = MemoryMatchLogic.apply_difficulty(MemoryMatchLogic.MEMORY, ctx.difficulty)
	rng = ctx.rng()
	layout = MemoryMatchLogic.layout_for_level(_gooby_level())
	peek = {"cleanMatches": 0, "peekReady": false, "peekUsed": false}
	_deal_board()
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
	# Etwas tiefer als mittig: darüber steht der Gooby-Cameo statt Leerraum.
	_grid_origin = Vector2((view_size.x - board.x) * 0.5, top + (avail.y - board.y) * 0.58)
	if _time_label != null:
		_time_label.position = Vector2(16.0, 10.0)
		_miss_label.position = Vector2(16.0, 48.0)
		_hint_label.position = Vector2(view_size.x * 0.5 - 170.0, view_size.y - 44.0)
		_hint_label.size = Vector2(340.0, 36.0)
		_peek_button.position = Vector2(view_size.x * 0.5 - 70.0, _grid_origin.y + board.y + 12.0)
		_peek_button.size = Vector2(140.0, 48.0)
	queue_redraw()


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
	_update_labels()


func _fit_viewport() -> void:
	apply_view(get_viewport_rect().size)


func _process(delta: float) -> void:
	if not is_active() or finished:
		return
	elapsed += delta
	if reveal_left > 0.0:
		reveal_left = maxf(0.0, reveal_left - delta)
	if peek_left > 0.0:
		peek_left = maxf(0.0, peek_left - delta)
	if resolve_left > 0.0:
		resolve_left = maxf(0.0, resolve_left - delta)
		if resolve_left <= 0.0:
			_resolve_pick()
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
		AudioDirector.try_play(self, "mg_perfect")
		if ctx.juice != null:
			ctx.juice.float_text(pos, "★", AcTokens.GOLD)
			ctx.juice.bloom_pulse(0.4)
	else:
		a["state"] = "down"
		b["state"] = "down"
		misses += 1
		AudioDirector.try_play(self, "mg_junk", 0.95)
		if ctx.juice != null:
			ctx.juice.shake(0.2)
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
	AudioDirector.try_play(self, "mg_win")
	if ctx.juice != null:
		ctx.juice.bloom_pulse(1.0)
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


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, view_size), AcTokens.BG_CREAM)
	# Tischdecke unter dem Brett — hebt die Karten vom Cream-Wash ab.
	var cols := int(layout["cols"])
	var rows := int(layout["rows"])
	var board := Rect2(
		_grid_origin - Vector2(12.0, 12.0),
		Vector2(
			_card_size.x * cols + _card_gap.x * (cols - 1) + 24.0,
			_card_size.y * rows + _card_gap.y * (rows - 1) + 24.0
		)
	)
	draw_rect(Rect2(board.position + Vector2(6.0, 8.0), board.size), AcTokens.SHADOW_COLOR)
	draw_rect(board, AcTokens.PAPER_SHADE)
	# Karo-Tischdecke, damit die Fläche unter den Karten nicht tot wirkt.
	var weave := 26.0
	var wx := board.position.x
	while wx < board.end.x:
		draw_line(
			Vector2(wx, board.position.y), Vector2(wx, board.end.y), Color(1, 1, 1, 0.35), 2.0
		)
		wx += weave
	var wy := board.position.y
	while wy < board.end.y:
		draw_line(
			Vector2(board.position.x, wy), Vector2(board.end.x, wy), Color(1, 1, 1, 0.35), 2.0
		)
		wy += weave
	draw_rect(board, AcTokens.INK, false, 3.0)
	for i in cards.size():
		_draw_card(i)
	_draw_gooby()


func _draw_card(index: int) -> void:
	var card: Dictionary = cards[index]
	var pos := _card_pos(index)
	var rect := Rect2(pos, _card_size)
	var state := str(card["state"])
	if state == "matched":
		draw_rect(rect, Color(0.83, 0.93, 0.8))
		draw_rect(rect, AcTokens.LEAF_DARK, false, 3.0)
	elif _face_visible(card):
		draw_rect(rect, AcTokens.PAPER)
		draw_rect(rect, AcTokens.INK, false, 3.0)
	else:
		_draw_card_back(rect)
		return
	if not _face_visible(card):
		return
	var key: String = MemoryMatchLogic.FACE_KEYS[
		int(card["face"]) % MemoryMatchLogic.FACE_KEYS.size()
	]
	Mg1FoodArt.draw(self, key, rect.get_center(), minf(_card_size.x, _card_size.y) * 0.32)


## Rückseite: Gooby-Kopf als Wappen auf gestreiftem Grund.
func _draw_card_back(rect: Rect2) -> void:
	draw_rect(rect, AcTokens.PINK)
	var stripe := rect.size.x * 0.24
	var sx := rect.position.x - rect.size.y
	while sx < rect.end.x:
		draw_line(
			Vector2(maxf(sx, rect.position.x), rect.position.y + maxf(0.0, rect.position.x - sx)),
			Vector2(
				minf(sx + rect.size.y, rect.end.x),
				rect.position.y + minf(rect.size.y, rect.end.x - sx)
			),
			Color(1.0, 1.0, 1.0, 0.10),
			stripe * 0.5
		)
		sx += stripe
	var inner := rect.grow(-rect.size.x * 0.09)
	draw_rect(inner, Color(1.0, 1.0, 1.0, 0.16))
	draw_rect(inner, Color(1.0, 1.0, 1.0, 0.45), false, 2.5)
	var c := rect.get_center()
	var r := rect.size.x * 0.2
	for side in [-1.0, 1.0]:
		draw_circle(c + Vector2(side * r * 0.52, -r * 1.15), r * 0.3, AcTokens.PINK_DARK)
	draw_circle(c, r, AcTokens.PINK_DARK)
	draw_circle(c + Vector2(-r * 0.34, -r * 0.12), r * 0.11, AcTokens.PINK)
	draw_circle(c + Vector2(r * 0.34, -r * 0.12), r * 0.11, AcTokens.PINK)
	draw_rect(rect, AcTokens.INK, false, 3.0)


## Gooby-Cameo über dem Kartentisch — hält die Lupe auf die Auslage.
func _draw_gooby() -> void:
	var r := clampf(_grid_origin.y * 0.2, 22.0, 46.0)
	var base := Vector2(view_size.x * 0.5, maxf(74.0, _grid_origin.y - r * 1.5))
	if landscape:
		base = Vector2(view_size.x - r * 2.0, r * 2.2)
	var fur := Color(0.99, 0.91, 0.7)
	for side in [-1.0, 1.0]:
		var ear_root := base + Vector2(side * r * 0.42, -r * 0.72)
		var ear_tip := ear_root + Vector2(side * r * 0.34, -r * 0.85)
		draw_line(ear_root, ear_tip, Color(0.98, 0.88, 0.66), r * 0.32)
		draw_circle(ear_tip, r * 0.16, Color(0.98, 0.88, 0.66))
	draw_circle(base, r, fur)
	draw_arc(base, r, 0.0, TAU, 26, AcTokens.INK, 3.0)
	draw_circle(base + Vector2(-r * 0.32, -r * 0.14), r * 0.12, AcTokens.INK)
	draw_circle(base + Vector2(r * 0.32, -r * 0.14), r * 0.12, AcTokens.INK)
	draw_circle(base + Vector2(-r * 0.62, r * 0.24), r * 0.16, Color(1.0, 0.72, 0.74, 0.5))
	draw_circle(base + Vector2(r * 0.62, r * 0.24), r * 0.16, Color(1.0, 0.72, 0.74, 0.5))
	draw_arc(base + Vector2(0.0, r * 0.2), r * 0.3, 0.3, PI - 0.3, 12, AcTokens.INK, 2.6)
	# Lupe in der Pfote.
	var lens := base + Vector2(r * 1.25, r * 0.45)
	draw_line(
		lens + Vector2(r * 0.4, r * 0.4), lens + Vector2(r * 0.85, r * 0.85), Color("8A5A34"), 5.0
	)
	draw_circle(lens, r * 0.42, Color(0.75, 0.9, 1.0, 0.55))
	draw_arc(lens, r * 0.42, 0.0, TAU, 20, AcTokens.INK, 3.0)
