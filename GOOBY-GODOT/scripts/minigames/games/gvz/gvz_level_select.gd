class_name GvzLevelSelect
extends Control
## Level-Auswahl von GvZ (W3b): 15 Kacheln (5×3), Sterne 1–3 aus dem
## GameState-Slice "gvz" (GvzProgress), gesperrte Level ausgegraut; unten
## Gesamt-Sterne + Fertig-Knopf (meldet die Session ans Framework zurück).
## Layout ist Anchor-basiert und funktioniert quer UND hochkant.
## W15/GAMESQA2 Level-Menü-Charme: Kacheln als AC-Sticker-Karten (Schatten,
## Hover-Lift, Druck-Senkung), goldene Sterne-Stempel als eigenes Label,
## Locked = flach + "· · ·", gestaffelte Seiten-Blätter-Animation beim
## refresh() (Reduced Motion respektiert). W16/G4: Kacheln/Knöpfe sind
## SquishButtons (zentrale Haptik), Touch-Floor + Fonts/Margins skalieren
## über ScreenShell.metrics (Menü lebt im SubViewport!), Footer mittig.

signal level_chosen(level_id: int)
signal done_pressed

const COLS_LANDSCAPE := 5
const COLS_PORTRAIT := 3
const PAGE_TURN_S := 0.22
const PAGE_TURN_STAGGER_S := 0.03
const PAGE_TURN_MAX_DELAY_S := 0.36
const PAGE_TURN_DEBOUNCE_MS := 600

## Duck-Typing: /root/GameState ODER Test-Double (von gvz_game gesetzt).
var game_state: Object

var _margin: MarginContainer
var _done: Button
var _grid: GridContainer
var _stars_label: Label
var _buttons: Dictionary = {}
## Level-Id → Sterne-Stempel-Label (goldene Sterne unter der Level-Nummer).
var _stamps: Dictionary = {}
## Level-Id → neues Element ("tower"/"zombie") für das NEU-Badge (E11 §Intro).
var _new_element: Dictionary = {}
## Gesamt-Sterne-Fortschritt als goldener Balken (der Fortschritt FEIERT).
var _progress_fill: ColorRect
## Entprellung der Blätter-Animation (refresh() feuert bei Bau UND Sieg).
var _page_turn_ms := -PAGE_TURN_DEBOUNCE_MS


func _ready() -> void:
	# MinigameBase ist Node2D → dessen anchorable_rect ist 0×0, FULL_RECT-Anker
	# greifen ins Leere. Direkt an den Viewport binden (GOB-NOM-Muster).
	_fit_viewport()
	get_viewport().size_changed.connect(_fit_viewport)
	_load_new_elements()
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	_margin.add_child(column)
	var title := Label.new()
	title.theme_type_variation = &"HeadlineLabel"
	title.text = I18nService.t("gvz.select.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", GvzArt.OUTLINE)
	column.add_child(title)
	_grid = GridContainer.new()
	_grid.columns = COLS_LANDSCAPE
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(_grid)
	column.add_child(_build_progress_bar())
	# Footer mittig (Daumenzone statt „rechts außen“, ui-ranch §2.2).
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	column.add_child(footer)
	_stars_label = Label.new()
	_stars_label.theme_type_variation = &"CaptionLabel"
	_stars_label.add_theme_font_size_override("font_size", 18)
	_stars_label.add_theme_color_override("font_color", GvzArt.OUTLINE)
	footer.add_child(_stars_label)
	_done = SquishButton.new()
	_done.text = I18nService.t("gvz.select.done")
	_done.pressed.connect(
		func() -> void:
			AudioDirector.try_play(self, "ui_back")
			done_pressed.emit()
	)
	footer.add_child(_done)
	_build_tiles()
	refresh()
	_apply_metrics()
	resized.connect(_on_resized)
	_on_resized()


func _build_tiles() -> void:
	for id in range(1, GvzProgress.LEVEL_COUNT + 1):
		var tile := SquishButton.new()
		tile.custom_minimum_size = Vector2(96, 64)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tile.add_theme_font_size_override("font_size", 20)
		tile.add_theme_color_override("font_color", GvzArt.OUTLINE)
		tile.add_theme_color_override("font_hover_color", GvzArt.OUTLINE)
		tile.add_theme_color_override("font_pressed_color", GvzArt.OUTLINE)
		tile.add_theme_color_override("font_focus_color", GvzArt.OUTLINE)
		tile.add_theme_color_override("font_disabled_color", Color("#B3A99C"))
		tile.pressed.connect(_on_tile.bind(id))
		tile.add_child(_build_stamp(id))
		_grid.add_child(tile)
		_buttons[id] = tile


## Sterne-Stempel: eigenes Label in der unteren Kartenhälfte, damit die
## Sterne GOLD sein können (Button-Text kann nur eine Farbe). Heller
## Outline-Rand gibt den Stempel-/Sticker-Look.
func _build_stamp(id: int) -> Label:
	var stamp := Label.new()
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stamp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stamp.anchor_top = 0.5
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stamp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stamp.add_theme_font_size_override("font_size", 20)
	stamp.add_theme_constant_override("outline_size", 3)
	_stamps[id] = stamp
	return stamp


## Sterne/Sperren neu aus dem Fortschritt lesen (nach jedem Sieg). Kacheln
## feiern den Fortschritt: Mint = geschafft, Gold-Glanz = 3 Sterne, goldener
## Rahmen = das NÄCHSTE Level, Berry-Rahmen = Boss-Finale.
func refresh() -> void:
	var unlocked := GvzProgress.max_unlocked(game_state)
	for id in range(1, GvzProgress.LEVEL_COUNT + 1):
		var tile: Button = _buttons[id]
		var stamp: Label = _stamps[id]
		var stars := GvzProgress.level_stars(game_state, id)
		var badge := " · BOSS" if id == 15 else ""
		if id > unlocked:
			tile.disabled = true
			tile.text = "%d%s\n" % [id, badge]
			stamp.text = stamp_text(0, true)
			_tint_stamp(stamp, Color("#B3A99C"))
			_style_tile(tile, Color("#E7DFD3"), Color("#CDBFAE"), 2, true)
			continue
		tile.disabled = false
		var cleared := GvzProgress.is_cleared(game_state, id)
		# E11 §Intro: das Level, das ein neues Element einführt, sagt das
		# jetzt AN der Kachel (bis es abgeschlossen wurde).
		if not cleared and _new_element.has(id):
			badge += " · %s" % I18nService.t("gvz.select.new")
		tile.text = "%d%s\n" % [id, badge]
		stamp.text = stamp_text(stars, false)
		_tint_stamp(stamp, GvzArt.STAR_GOLD if stars > 0 else Color("#C9BCA9"))
		var fill := Color("#DFF2CF") if cleared else Color("#FFF6E3")
		var border := GvzArt.OUTLINE
		var width := 3
		if cleared and stars >= 3:
			fill = Color("#FFF1C2")
			border = Color("#D9A83C")
		elif not cleared and id == unlocked:
			border = Color("#D9A83C")
			width = 4
		if id == 15:
			border = GvzArt.BERRY_RED
		_style_tile(tile, fill, border, width, false)
	var total := GvzProgress.total_stars(game_state)
	_stars_label.text = I18nService.t("gvz.select.stars", {"n": total, "max": 45})
	if _progress_fill != null:
		_progress_fill.visible = total > 0
		_progress_fill.anchor_right = clampf(float(total) / 45.0, 0.05, 1.0)
	_maybe_page_turn()


## Stempel-Farbe samt dunklerem Rand — der Rand macht die goldenen Sterne
## auf Creme/Mint erst richtig "gestempelt" (satt statt ausgewaschen).
static func _tint_stamp(stamp: Label, color: Color) -> void:
	stamp.add_theme_color_override("font_color", color)
	stamp.add_theme_color_override("font_outline_color", color.darkened(0.55))


## PURE: Stempel-Zeile einer Kachel — Gold-Sterne offen, "· · ·" gesperrt
## (bewusst KEIN Schloss-Emoji: Font-Fallback ist auf Geräten unzuverlässig).
static func stamp_text(stars: int, locked: bool) -> String:
	if locked:
		return "· · ·"
	if stars <= 0:
		return "☆☆☆"
	return "★".repeat(clampi(stars, 0, 3)) + "☆".repeat(3 - clampi(stars, 0, 3))


## PURE: Staffel-Verzögerung der Blätter-Animation je Kachel-Index —
## gedeckelt, damit auch lange Listen (GOB-NOM: 25) flott fertig blättern.
static func page_turn_delay(index: int) -> float:
	return minf(maxi(index, 0) * PAGE_TURN_STAGGER_S, PAGE_TURN_MAX_DELAY_S)


## new_towers/new_zombies aus den Level-Daten für die Badges einlesen.
func _load_new_elements() -> void:
	_new_element = {}
	for level: Dictionary in GvzData.load_levels():
		var id := int(level.get("id", 0))
		if not (level.get("new_towers", []) as Array).is_empty():
			_new_element[id] = "tower"
		elif not (level.get("new_zombies", []) as Array).is_empty():
			_new_element[id] = "zombie"


## Goldener Gesamt-Sterne-Balken zwischen Gitter und Fußzeile.
func _build_progress_bar() -> Control:
	var bar := Panel.new()
	bar.custom_minimum_size = Vector2(0, 14)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color("#EADFC9")
	bg.set_corner_radius_all(7)
	bg.set_border_width_all(2)
	bg.border_color = GvzArt.OUTLINE
	bar.add_theme_stylebox_override("panel", bg)
	_progress_fill = ColorRect.new()
	_progress_fill.color = GvzArt.STAR_GOLD
	_progress_fill.set_anchors_preset(Control.PRESET_FULL_RECT)
	_progress_fill.anchor_right = 0.0
	_progress_fill.offset_left = 3.0
	_progress_fill.offset_top = 3.0
	_progress_fill.offset_bottom = -3.0
	_progress_fill.offset_right = -1.0
	_progress_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar.add_child(_progress_fill)
	return bar


## Pastell-Kachel im Sticker-Look: Creme offen, Mint geschafft, Gold-Glanz
## bei 3 Sternen, blass gesperrt; Rahmenfarbe markiert Frontier/Boss.
static func _style_tile(tile: Button, fill: Color, border: Color, width: int, locked: bool) -> void:
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		tile.add_theme_stylebox_override(
			state_name, card_style(state_name, fill, border, width, locked)
		)


## PURE: AC-Karten-StyleBox je Button-Zustand — offene Karten werfen einen
## weichen Schatten (liegen "auf" dem Album), Hover hebt die Karte an,
## Druck senkt sie (Schatten weg); gesperrte Karten liegen flach.
static func card_style(
	state_name: String, fill: Color, border: Color, width: int, locked: bool
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.set_corner_radius_all(16)
	style.set_border_width_all(width)
	style.border_color = border
	if locked:
		return style
	style.shadow_color = Color(0.35, 0.24, 0.18, 0.18)
	style.shadow_size = 4
	style.shadow_offset = Vector2(0.0, 3.0)
	match state_name:
		"hover":
			style.bg_color = fill.lightened(0.04)
			style.shadow_size = 7
			style.shadow_offset = Vector2(0.0, 5.0)
		"pressed":
			style.bg_color = fill.darkened(0.06)
			style.shadow_size = 0
			style.shadow_offset = Vector2.ZERO
	return style


## Seiten-Blätter-Effekt: Kacheln klappen gestaffelt auf wie beim Umblättern
## in einem Sticker-Album. Entprellt (refresh() feuert bei Bau UND nach jedem
## Sieg kurz hintereinander) und respektiert Reduced Motion.
func _maybe_page_turn() -> void:
	if not is_inside_tree() or ThemeService.is_reduced_motion(self):
		return
	var now := Time.get_ticks_msec()
	if now - _page_turn_ms < PAGE_TURN_DEBOUNCE_MS:
		return
	_page_turn_ms = now
	# Deferred: erst nach dem Layout-Pass kennen die Kacheln ihre Größe
	# (pivot_offset für die Mitten-Klappe braucht sie).
	_play_page_turn.call_deferred()


func _play_page_turn() -> void:
	if not is_inside_tree():
		return
	var index := 0
	for id: int in _buttons:
		var tile: Button = _buttons[id]
		tile.pivot_offset = tile.size / 2.0
		tile.scale = Vector2(0.0, 1.0)
		var tween := tile.create_tween()
		tween.tween_interval(page_turn_delay(index))
		(
			tween
			. tween_property(tile, "scale", Vector2.ONE, PAGE_TURN_S)
			. set_trans(Tween.TRANS_BACK)
			. set_ease(Tween.EASE_OUT)
		)
		index += 1


func _on_tile(id: int) -> void:
	# Haptik kommt zentral aus dem SquishButton (Audio-Grammatik).
	AudioDirector.try_play(self, "ui_confirm")
	level_chosen.emit(id)


func _on_resized() -> void:
	if _grid != null:
		_grid.columns = COLS_LANDSCAPE if size.x >= size.y else COLS_PORTRAIT


func _fit_viewport() -> void:
	# B11: dieser Node ist size-verwaltet (Viewport-Bindung) — die Anker
	# MÜSSEN gleichseitig bleiben (Anker ODER size, nie beides), sonst warnt
	# Godot „non-equal opposite anchors“ und der Layout-Pass kippt das Rect.
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2.ZERO
	size = get_viewport_rect().size
	_apply_metrics()


## Touch-Floor + ×f (ui-arcade §6): das Menü lebt im SubViewport — Kachel-/
## Knopf-Minima auf metrics.floor_px heben, Fonts/Margins mit f skalieren.
func _apply_metrics() -> void:
	if _margin == null:
		return
	var m := ScreenShell.metrics(get_viewport())
	var f: float = m["f"]
	for side in ["left", "right", "top", "bottom"]:
		_margin.add_theme_constant_override("margin_%s" % side, int(14.0 * f))
	for id: int in _buttons:
		var tile: Button = _buttons[id]
		tile.custom_minimum_size = Vector2(96.0 * f, 64.0 * f)
		ScreenShell.touch_target(tile, m)
	_done.custom_minimum_size = Vector2(140.0 * f, 48.0 * f)
	ScreenShell.touch_target(_done, m)
	ScreenShell.scale_fonts(_margin, f)
