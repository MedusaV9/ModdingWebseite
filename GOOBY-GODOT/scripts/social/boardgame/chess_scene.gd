class_name ChessScene
extends Control
## Schach am Brettspieltisch (BACKLOG-REST, Doc C §3.5): hübsches 2D-Brett im
## GOOBY-Look (warme Holztöne, runde Figuren-Chips mit deutschen Buchstaben,
## K/D/T/L/S/B). Zwei Modi über dieselbe Szene:
##   - SOLO gegen den Gooby-Bot (ChessAi, 3 Stärken, Farbe wählbar) — auch
##     offline erreichbar („Schach üben" im Social-Screen).
##   - MEHRSPIELER über ChessSession (Server-Turn-Relay wie Schiffe
##     versenken, inkl. Aufgeben/Revanche/Peer-Down/Resume + Emote-Rad).
## Zugeingabe: eigene Figur antippen → legale Ziele leuchten → Ziel antippen;
## Umwandlung fragt per Picker (Dame/Turm/Läufer/Springer). Das Brett dreht
## sich für Schwarz. Ergebnis-Overlay mit JuiceKit-Konfetti beim Sieg;
## ein Sieg feuert den Sticker-Hook "chess_win" (Album-Set Mehrspieler).

const ROUTE := &"social/chess"
const ROUTES := {ROUTE: "res://scripts/social/boardgame/chess_scene.tscn"}

const COLOR_BG := Color(0.98, 0.94, 0.87)
const COLOR_LIGHT := Color("#F2DDB8")
const COLOR_DARK := Color("#BA8A5B")
const COLOR_SELECTED := Color("#3FBFB0")
const COLOR_LAST_MOVE := Color("#E8C25A")
const COLOR_CHECK := Color("#E4634F")
const COLOR_CHIP_WHITE := Color("#FFF8EC")
const COLOR_CHIP_BLACK := Color("#54382A")
const COLOR_TEXT_WHITE := Color("#6B4A2B")
const COLOR_TEXT_BLACK := Color("#FFF3DC")
const SQUARE_PX := 64.0
const PIECE_KEYS: Array[String] = ["", "pawn", "knight", "bishop", "rook", "queen", "king"]

## Tests/Screenshots: SocialServices-Instanz injizieren statt /root-Lookup.
var services_override: Node = null

var toast: ToastLayer

var _services: Node = null
var _session: ChessSession = null
var _mode := "solo"
var _phase := "pick"  # pick -> play -> over
var _solo_logic: ChessLogic = null
var _ai: ChessAi = null
var _ai_strength := 2
var _my_color := ChessLogic.WHITE
var _selected := -1
var _targets: Dictionary = {}
var _last_from := -1
var _last_to := -1
var _thinking := false
var _pending_promo: Array[int] = []
var _squares: Dictionary = {}
var _turn_label: Label
var _opp_label: Label
var _moves_label: RichTextLabel
var _move_count := 0
var _leave_button: Button
var _surrender_dialog: ConfirmationDialog
var _action_box: VBoxContainer
var _rematch_button: Button
var _new_game_button: Button
var _emote_button: Button
var _wheel: Control
var _pick_panel: PanelContainer
var _promo_panel: PanelContainer
var _result_panel: PanelContainer
var _result_label: Label
var _result_reason: Label
var _juice: JuiceKit


static func register_routes() -> void:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return
	var router := (loop as SceneTree).root.get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("register_routes"):
		router.register_routes(ROUTES)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_services = services_override
	if _services == null:
		_services = SocialServices.get_or_create(self)
	_session = _services.chess if _services != null else null
	_build_ui()
	_wire_session()
	if _session != null and _session.is_active():
		_enter_multiplayer()
	else:
		_show_pick()


func receive_params(params: Dictionary) -> void:
	if params.get("mode", "") == "solo":
		_mode = "solo"


## Aktive Regelinstanz: Session-Brett (MP) oder das Solo-Brett.
func game_logic() -> ChessLogic:
	if _mode == "mp" and _session != null:
		return _session.logic
	return _solo_logic


func session() -> ChessSession:
	return _session


# ── Aufbau ───────────────────────────────────────────────────────────────────


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = COLOR_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var header := HBoxContainer.new()
	header.set_anchors_preset(Control.PRESET_TOP_WIDE)
	header.offset_left = 16.0
	header.offset_top = 12.0
	header.offset_right = -16.0
	add_child(header)
	_leave_button = Button.new()
	_leave_button.theme_type_variation = &"GhostButton"
	_leave_button.text = I18nService.t("chess.leave")
	_leave_button.pressed.connect(_on_leave_pressed)
	header.add_child(_leave_button)

	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 28)
	main.set_anchors_preset(Control.PRESET_CENTER)
	main.grow_horizontal = Control.GROW_DIRECTION_BOTH
	main.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(main)

	main.add_child(_build_board())
	main.add_child(_build_side_panel())

	_pick_panel = _build_pick_panel()
	add_child(_pick_panel)
	_promo_panel = _build_promo_panel()
	add_child(_promo_panel)
	_result_panel = _build_result_panel()
	add_child(_result_panel)

	_surrender_dialog = ConfirmationDialog.new()
	_surrender_dialog.ok_button_text = I18nService.t("chess.surrender")
	_surrender_dialog.confirmed.connect(_on_surrender_confirmed)
	add_child(_surrender_dialog)

	_wheel = EmoteWheel.new()
	_wheel.set_anchors_preset(Control.PRESET_CENTER)
	_wheel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_wheel.grow_vertical = Control.GROW_DIRECTION_BOTH
	_wheel.emote_picked.connect(_on_emote_picked)
	add_child(_wheel)

	toast = ToastLayer.new()
	add_child(toast)
	toast.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_juice = JuiceKit.new()
	add_child(_juice)
	_juice.float_text_parent = self


## Brett mit Koordinaten: 9×9-Gitter (Spalte 0 = Reihen-Zahlen, letzte
## Zeile = Linien-Buchstaben). Anzeige-Zeile 0 = OBEN.
func _build_board() -> Control:
	var frame := PanelContainer.new()
	frame.theme_type_variation = &"AcCard"
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	frame.add_child(margin)
	var grid := GridContainer.new()
	grid.columns = 9
	grid.add_theme_constant_override("h_separation", 0)
	grid.add_theme_constant_override("v_separation", 0)
	margin.add_child(grid)
	for row in 8:
		grid.add_child(_coord_label(""))
		for col in 8:
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(SQUARE_PX, SQUARE_PX)
			btn.focus_mode = Control.FOCUS_NONE
			btn.clip_contents = false
			btn.pressed.connect(_on_display_square_pressed.bind(row, col))
			grid.add_child(btn)
			_squares[Vector2i(col, row)] = btn
	grid.add_child(_coord_label(""))
	for col in 8:
		grid.add_child(_coord_label(""))
	return frame


func _coord_label(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"CaptionLabel"
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(22.0, 22.0)
	return label


func _build_side_panel() -> Control:
	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 10)
	panel.custom_minimum_size = Vector2(240.0, 0.0)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = I18nService.t("chess.title")
	panel.add_child(title)
	_opp_label = Label.new()
	_opp_label.theme_type_variation = &"HeadlineLabel"
	panel.add_child(_opp_label)
	_turn_label = Label.new()
	_turn_label.theme_type_variation = &"HeadlineLabel"
	panel.add_child(_turn_label)
	var moves_title := Label.new()
	moves_title.theme_type_variation = &"CaptionLabel"
	moves_title.text = I18nService.t("chess.moves")
	panel.add_child(moves_title)
	_moves_label = RichTextLabel.new()
	_moves_label.scroll_following = true
	_moves_label.custom_minimum_size = Vector2(220.0, 220.0)
	_moves_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(_moves_label)

	_action_box = VBoxContainer.new()
	_action_box.add_theme_constant_override("separation", 8)
	panel.add_child(_action_box)
	_emote_button = Button.new()
	_emote_button.theme_type_variation = &"BtnTeal"
	_emote_button.text = I18nService.t("chess.emote_button")
	_emote_button.pressed.connect(func() -> void: _wheel.toggle())
	_action_box.add_child(_emote_button)
	_rematch_button = Button.new()
	_rematch_button.theme_type_variation = &"PrimaryButton"
	_rematch_button.text = I18nService.t("chess.rematch.button")
	_rematch_button.visible = false
	_rematch_button.pressed.connect(_on_rematch_pressed)
	_action_box.add_child(_rematch_button)
	_new_game_button = Button.new()
	_new_game_button.theme_type_variation = &"PrimaryButton"
	_new_game_button.text = I18nService.t("chess.new_game")
	_new_game_button.visible = false
	_new_game_button.pressed.connect(_show_pick)
	_action_box.add_child(_new_game_button)
	return panel


func _build_pick_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"AcCard"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.theme_type_variation = &"HeadlineLabel"
	title.text = I18nService.t("chess.solo.title")
	box.add_child(title)
	var subtitle := Label.new()
	subtitle.theme_type_variation = &"CaptionLabel"
	subtitle.text = I18nService.t("chess.solo.subtitle")
	box.add_child(subtitle)
	var strengths := HBoxContainer.new()
	strengths.add_theme_constant_override("separation", 8)
	box.add_child(strengths)
	for strength in 3:
		var btn := Button.new()
		btn.theme_type_variation = &"BtnTeal"
		btn.text = I18nService.t("chess.solo.strength%d" % (strength + 1))
		btn.pressed.connect(_on_strength_picked.bind(strength + 1, strengths))
		strengths.add_child(btn)
	var colors := HBoxContainer.new()
	colors.add_theme_constant_override("separation", 8)
	box.add_child(colors)
	var white_btn := Button.new()
	white_btn.theme_type_variation = &"PrimaryButton"
	white_btn.text = I18nService.t("chess.solo.white")
	white_btn.pressed.connect(_on_solo_start.bind(ChessLogic.WHITE))
	colors.add_child(white_btn)
	var black_btn := Button.new()
	black_btn.theme_type_variation = &"GhostButton"
	black_btn.text = I18nService.t("chess.solo.black")
	black_btn.pressed.connect(_on_solo_start.bind(ChessLogic.BLACK))
	colors.add_child(black_btn)
	return panel


func _build_promo_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"AcCard"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var title := Label.new()
	title.theme_type_variation = &"HeadlineLabel"
	title.text = I18nService.t("chess.promo.title")
	box.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var options: Array[Array] = [
		["queen", ChessLogic.QUEEN],
		["rook", ChessLogic.ROOK],
		["bishop", ChessLogic.BISHOP],
		["knight", ChessLogic.KNIGHT],
	]
	for option in options:
		var btn := Button.new()
		btn.theme_type_variation = &"BtnTeal"
		btn.text = I18nService.t("chess.promo." + str(option[0]))
		btn.pressed.connect(_on_promo_picked.bind(int(option[1])))
		row.add_child(btn)
	return panel


func _build_result_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"AcCard"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.offset_top = -180.0
	panel.offset_bottom = -120.0
	panel.visible = false
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	_result_label = Label.new()
	_result_label.theme_type_variation = &"TitleLabel"
	_result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_label)
	_result_reason = Label.new()
	_result_reason.theme_type_variation = &"CaptionLabel"
	_result_reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_result_reason)
	return panel


func _wire_session() -> void:
	if _session == null:
		return
	_session.opponent_moved.connect(_on_opponent_moved)
	_session.opponent_emote.connect(_on_opponent_emote)
	_session.game_over.connect(_on_session_game_over)
	_session.opponent_forfeit.connect(_on_opponent_forfeit)
	_session.game_started.connect(_on_rematch_started)
	_session.game_resumed.connect(_on_game_resumed)
	_session.rematch_requested_by_opponent.connect(_on_rematch_incoming)
	_session.rematch_declined.connect(_on_rematch_declined)
	_session.peer_connection_changed.connect(_on_peer_connection_changed)
	_session.send_rejected.connect(func(_kind: String, _code: String) -> void: _render())


# ── Modi ─────────────────────────────────────────────────────────────────────


func _show_pick() -> void:
	_mode = "solo"
	_phase = "pick"
	_pick_panel.visible = true
	_result_panel.visible = false
	_new_game_button.visible = false
	_emote_button.visible = false
	_solo_logic = ChessLogic.new()
	_reset_view()
	_render()


func _on_strength_picked(strength: int, row: HBoxContainer) -> void:
	_ai_strength = strength
	for i in row.get_child_count():
		var btn: Button = row.get_child(i)
		btn.theme_type_variation = &"PrimaryButton" if i == strength - 1 else &"BtnTeal"


func _on_solo_start(color: int) -> void:
	_mode = "solo"
	_phase = "play"
	_my_color = color
	_solo_logic = ChessLogic.new()
	_ai = ChessAi.new(int(Time.get_unix_time_from_system()) | 1)
	_pick_panel.visible = false
	_result_panel.visible = false
	_new_game_button.visible = false
	_opp_label.text = (
		"%s (%s)"
		% [
			I18nService.t("chess.solo.bot_name"),
			I18nService.t("chess.solo.strength%d" % _ai_strength),
		]
	)
	_reset_view()
	_render()
	if _my_color == ChessLogic.BLACK:
		_ai_turn()


func _enter_multiplayer() -> void:
	_mode = "mp"
	_phase = "play"
	_my_color = _session.my_color
	_pick_panel.visible = false
	_result_panel.visible = false
	_rematch_button.visible = false
	_new_game_button.visible = false
	_emote_button.visible = true
	_opp_label.text = _session.opponent_gooby_name
	_fire_hook("chess_online")
	_reset_view()
	_render()


func _reset_view() -> void:
	_selected = -1
	_targets = {}
	_last_from = -1
	_last_to = -1
	_thinking = false
	_pending_promo = []
	_move_count = 0
	_moves_label.clear()
	_promo_panel.visible = false


# ── Brett-Anzeige ────────────────────────────────────────────────────────────


## Anzeige-Koordinate → 0x88-Feld (Brett dreht sich für Schwarz).
func _display_to_square(row: int, col: int) -> int:
	var file := col if _my_color == ChessLogic.WHITE else 7 - col
	var rank := 7 - row if _my_color == ChessLogic.WHITE else row
	return rank * 16 + file


func _render() -> void:
	var logic := game_logic()
	if logic == null:
		return
	var check_sq := -1
	if _phase != "pick" and logic.in_check():
		check_sq = logic.board.find(ChessLogic.KING * logic.to_move)
	for pos: Vector2i in _squares:
		var btn: Button = _squares[pos]
		var sq := _display_to_square(pos.y, pos.x)
		var base := COLOR_LIGHT if ((sq >> 4) + (sq & 7)) % 2 == 1 else COLOR_DARK
		if sq == _last_from or sq == _last_to:
			base = base.lerp(COLOR_LAST_MOVE, 0.45)
		if sq == _selected:
			base = base.lerp(COLOR_SELECTED, 0.55)
		if sq == check_sq:
			base = base.lerp(COLOR_CHECK, 0.6)
		_style_square(btn, base)
		for child in btn.get_children():
			child.queue_free()
		var piece: int = logic.board[sq]
		if piece != 0:
			btn.add_child(_piece_chip(piece))
		if _targets.has(sq):
			btn.add_child(_target_dot(piece != 0))
	_render_coords()
	_update_turn_label()


func _style_square(btn: Button, color: Color) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(4)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		btn.add_theme_stylebox_override(state, style)


## Runder Figuren-Chip mit deutschem Buchstaben (K/D/T/L/S/B).
func _piece_chip(piece: int) -> Control:
	var chip := PanelContainer.new()
	chip.set_anchors_preset(Control.PRESET_CENTER)
	chip.grow_horizontal = Control.GROW_DIRECTION_BOTH
	chip.grow_vertical = Control.GROW_DIRECTION_BOTH
	chip.custom_minimum_size = Vector2(46.0, 46.0)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_CHIP_WHITE if piece > 0 else COLOR_CHIP_BLACK
	style.set_corner_radius_all(23)
	style.border_color = COLOR_TEXT_WHITE if piece > 0 else Color(0.15, 0.08, 0.04)
	style.set_border_width_all(2)
	chip.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.text = I18nService.t("chess.pieces." + PIECE_KEYS[absi(piece)])
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override(
		"font_color", COLOR_TEXT_WHITE if piece > 0 else COLOR_TEXT_BLACK
	)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(label)
	return chip


## Zielmarker: Punkt auf leeren Feldern, Ring um schlagbare Figuren.
func _target_dot(is_capture: bool) -> Control:
	var dot := PanelContainer.new()
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.grow_horizontal = Control.GROW_DIRECTION_BOTH
	dot.grow_vertical = Control.GROW_DIRECTION_BOTH
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	if is_capture:
		dot.custom_minimum_size = Vector2(56.0, 56.0)
		style.bg_color = Color(0, 0, 0, 0)
		style.border_color = COLOR_SELECTED
		style.set_border_width_all(4)
		style.set_corner_radius_all(28)
	else:
		dot.custom_minimum_size = Vector2(18.0, 18.0)
		style.bg_color = COLOR_SELECTED
		style.set_corner_radius_all(9)
	dot.add_theme_stylebox_override("panel", style)
	return dot


func _render_coords() -> void:
	var grid: GridContainer = _squares[Vector2i(0, 0)].get_parent()
	for row in 8:
		var label: Label = grid.get_child(row * 9)
		var rank := (7 - row) if _my_color == ChessLogic.WHITE else row
		label.text = str(rank + 1)
	for col in 8:
		var label: Label = grid.get_child(72 + 1 + col)
		var file := col if _my_color == ChessLogic.WHITE else 7 - col
		label.text = char(97 + file)


func _update_turn_label() -> void:
	var logic := game_logic()
	if _phase != "play" or logic == null:
		_turn_label.text = ""
		return
	var opp := _opponent_name()
	if _thinking:
		_turn_label.text = I18nService.t("chess.thinking", {"name": opp})
	elif _is_my_turn():
		var text := I18nService.t("chess.your_turn")
		if logic.in_check():
			text += " — " + I18nService.t("chess.check")
		_turn_label.text = text
	else:
		_turn_label.text = I18nService.t("chess.their_turn", {"name": opp})


func _opponent_name() -> String:
	if _mode == "mp" and _session != null:
		return _session.opponent_gooby_name
	return I18nService.t("chess.solo.bot_name")


# ── Zugeingabe ───────────────────────────────────────────────────────────────


func _is_my_turn() -> bool:
	if _phase != "play" or _thinking:
		return false
	if _mode == "mp":
		return _session != null and _session.my_turn()
	var logic := game_logic()
	return logic != null and logic.to_move == _my_color


func _on_display_square_pressed(row: int, col: int) -> void:
	_on_square_pressed(_display_to_square(row, col))


func _on_square_pressed(sq: int) -> void:
	var logic := game_logic()
	if logic == null or _promo_panel.visible or not _is_my_turn():
		return
	if _targets.has(sq):
		_commit_target(sq)
		return
	var piece: int = logic.board[sq]
	if piece != 0 and signi(piece) == _my_color:
		_selected = sq
		_targets = {}
		for m in logic.legal_moves_from(sq):
			var to := ChessLogic.mv_to(m)
			if not _targets.has(to):
				_targets[to] = []
			(_targets[to] as Array).append(m)
		_sfx("ui_click")
	else:
		_selected = -1
		_targets = {}
	_render()


## Ziel angeklickt: 1 Zug = direkt spielen; mehrere = Umwandlungs-Picker.
func _commit_target(sq: int) -> void:
	var moves: Array = _targets[sq]
	if moves.size() == 1:
		_play_my_move(int(moves[0]))
		return
	_pending_promo.assign(moves)
	_promo_panel.visible = true


func _on_promo_picked(piece: int) -> void:
	_promo_panel.visible = false
	for m in _pending_promo:
		if ChessLogic.mv_promo(m) == piece:
			_play_my_move(m)
			return
	_pending_promo = []


func _play_my_move(m: int) -> void:
	var logic := game_logic()
	if logic == null:
		return
	var uci := ChessLogic.move_to_uci(m)
	if _mode == "mp":
		if not _session.send_move(uci):
			return
	elif not logic.play_move(m):
		return
	_after_move_applied(m, true)
	if _mode == "solo" and _phase == "play":
		_ai_turn()


func _after_move_applied(m: int, mine: bool) -> void:
	_selected = -1
	_targets = {}
	_pending_promo = []
	_last_from = ChessLogic.mv_from(m)
	_last_to = ChessLogic.mv_to(m)
	_move_count += 1
	_moves_label.append_text(
		"%s%s " % ["" if _move_count % 2 == 1 else " · ", ChessLogic.move_to_uci(m)]
	)
	_sfx("ui_confirm" if mine else "ui_click")
	var logic := game_logic()
	if logic != null and _phase == "play" and logic.in_check():
		if logic.result() == ChessLogic.RESULT_RUNNING:
			toast.show_toast(I18nService.t("chess.check"))
	if _mode == "solo":
		_check_solo_end()
	_render()


# ── Solo-Gegner ──────────────────────────────────────────────────────────────


func _ai_turn() -> void:
	var logic := game_logic()
	if logic == null or _phase != "play" or logic.to_move == _my_color:
		return
	_thinking = true
	_update_turn_label()
	await get_tree().process_frame
	await get_tree().process_frame
	if _phase != "play" or game_logic() != logic:
		return
	var m := _ai.pick_move(logic, _ai_strength)
	_thinking = false
	if m == 0 or not logic.play_move(m):
		_check_solo_end()
		return
	_after_move_applied(m, false)


func _check_solo_end() -> void:
	var logic := game_logic()
	if logic == null:
		return
	var res := logic.result()
	if res == ChessLogic.RESULT_RUNNING:
		return
	var i_won := res == ChessLogic.RESULT_CHECKMATE and logic.to_move != _my_color
	var i_lost := res == ChessLogic.RESULT_CHECKMATE and not i_won
	_finish(i_won, i_lost, res)


## Gemeinsames Partie-Ende (Solo + MP): Overlay, Konfetti, Sticker-Hook.
func _finish(i_won: bool, i_lost: bool, reason: String) -> void:
	if _phase == "over":
		return
	_phase = "over"
	_thinking = false
	_promo_panel.visible = false
	var key := "chess.draw"
	if i_won:
		key = "chess.win"
	elif i_lost:
		key = "chess.lose"
	_result_label.text = I18nService.t(key)
	var reason_key := "chess.reason." + reason
	_result_reason.text = I18nService.t(reason_key)
	_result_panel.visible = true
	if _mode == "solo":
		_new_game_button.visible = true
	else:
		_rematch_button.visible = true
		_rematch_button.disabled = false
	_leave_button.text = I18nService.t("chess.exit")
	if i_won:
		_juice.confetti(70)
		_sfx("mg_win")
	_award_stickers(i_won, reason)
	_render()


## Sticker-Hooks + Zähler am Partie-Ende (Album-Set Multiplayer):
## chess_win/chess_matt-Hooks, chessWins- und chessSoloGames-Zähler.
func _award_stickers(i_won: bool, reason: String) -> void:
	var gs := _sticker_gs()
	if gs == null or not gs.has_method("update"):
		return
	if _mode == "solo":
		_bump_counter(gs, "chessSoloGames")
	if not i_won:
		return
	StickerUnlocks.fire_event_hook(gs, "chess_win")
	_bump_counter(gs, "chessWins")
	if reason == ChessLogic.RESULT_CHECKMATE:
		StickerUnlocks.fire_event_hook(gs, "chess_matt")


## Einmalige Hooks für Partie-Start (Online-Partie / Revanche).
func _fire_hook(hook: String) -> void:
	var gs := _sticker_gs()
	if gs != null and gs.has_method("update"):
		StickerUnlocks.fire_event_hook(gs, hook)


func _sticker_gs() -> Object:
	if _services != null and _services.get("game_state_override") != null:
		return _services.get("game_state_override")
	return get_node_or_null("/root/GameState")


func _bump_counter(gs: Object, key: String) -> void:
	gs.update(
		func(state: Dictionary) -> void:
			if not (state.get("achievements") is Dictionary):
				state["achievements"] = {"unlocked": {}, "counters": {}}
			var achievements: Dictionary = state["achievements"]
			if not (achievements.get("counters") is Dictionary):
				achievements["counters"] = {}
			var counters: Dictionary = achievements["counters"]
			counters[key] = int(counters.get(key, 0)) + 1
	)
	if gs.has_method("notify_slice_changed"):
		gs.notify_slice_changed("achievements")


func _sfx(id: String) -> void:
	AudioDirector.try_play(self, id)


# ── Session-Ereignisse (Mehrspieler) ─────────────────────────────────────────


func _on_opponent_moved(uci: String) -> void:
	if _mode != "mp":
		return
	var logic := game_logic()
	if logic == null:
		return
	var m := 0
	# Der Zug ist schon gespielt — from/to fürs Highlight aus der UCI holen.
	var from := (uci.unicode_at(1) - 49) * 16 + (uci.unicode_at(0) - 97)
	var to := (uci.unicode_at(3) - 49) * 16 + (uci.unicode_at(2) - 97)
	m = from | to << 7
	_after_move_applied(m, false)


func _on_session_game_over(_winner_code: String, i_won: bool, reason: String) -> void:
	if _mode != "mp":
		return
	_finish(i_won, not i_won and not _is_draw_reason(reason), reason)


func _is_draw_reason(reason: String) -> bool:
	return reason.begins_with("draw") or reason == ChessLogic.RESULT_STALEMATE


func _on_opponent_forfeit(_data: Dictionary) -> void:
	toast.show_toast(I18nService.t("chess.reason.forfeit") + " — " + _opponent_name())
	_rematch_button.visible = false


func _on_rematch_pressed() -> void:
	if _session == null:
		return
	_rematch_button.disabled = true
	var res: Dictionary = await _session.request_rematch()
	if not res["ok"]:
		_rematch_button.disabled = false
		toast.show_toast(I18nService.t("chess.rematch.failed", {"code": str(res["code"])}))
		return
	if bool(res["waiting"]):
		toast.show_toast(I18nService.t("chess.rematch.waiting", {"name": _opponent_name()}))


func _on_rematch_started(_data: Dictionary) -> void:
	_result_panel.visible = false
	_rematch_button.visible = false
	_leave_button.text = I18nService.t("chess.leave")
	_fire_hook("chess_rematch")
	_enter_multiplayer()


func _on_game_resumed(_data: Dictionary) -> void:
	toast.show_toast(I18nService.t("chess.resumed"))
	if _mode != "mp":
		_enter_multiplayer()
	if _session.finished:
		_on_session_game_over(
			_session.winner, _session.winner == _session.my_code(), _session.reason
		)
	_render()


func _on_rematch_incoming() -> void:
	toast.show_toast(I18nService.t("chess.rematch.incoming", {"name": _opponent_name()}))


func _on_rematch_declined() -> void:
	toast.show_toast(I18nService.t("chess.rematch.declined", {"name": _opponent_name()}))
	_rematch_button.visible = false


func _on_peer_connection_changed(down: bool, _wait_ms: int) -> void:
	var key := "chess.peer.down" if down else "chess.peer.up"
	toast.show_toast(I18nService.t(key, {"name": _opponent_name()}))
	_update_turn_label()


func _on_emote_picked(emote_id: String) -> void:
	if _session != null:
		_session.send_emote(emote_id)


func _on_opponent_emote(emote_id: String) -> void:
	var label_key := str(BoardEmotes.def(emote_id).get("label_key", ""))
	if not label_key.is_empty():
		toast.show_toast("%s: %s" % [_opponent_name(), I18nService.t(label_key)])


# ── Verlassen / Aufgeben ─────────────────────────────────────────────────────


func _on_leave_pressed() -> void:
	if _phase == "play" and _mode == "mp" and _session != null and _session.is_active():
		_surrender_dialog.dialog_text = I18nService.t(
			"chess.surrender_confirm", {"name": _opponent_name()}
		)
		_surrender_dialog.popup_centered()
		return
	await _leave_and_go_back()


func _on_surrender_confirmed() -> void:
	if _session != null:
		_session.surrender()


func _leave_and_go_back() -> void:
	if _mode == "mp" and _session != null:
		await _session.leave()
	var router := get_node_or_null("/root/SceneRouter")
	if router == null or not router.has_method("goto"):
		return
	var routes: Variant = router.get("_routes")
	if routes is Dictionary and (routes as Dictionary).has(&"social"):
		router.goto(&"social", {})
	elif routes is Dictionary and (routes as Dictionary).has(&"home"):
		router.goto(&"home", {})
