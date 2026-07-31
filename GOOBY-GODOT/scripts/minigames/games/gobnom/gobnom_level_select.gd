class_name GobnomLevelSelect
extends Control
## Level-Auswahl von GOB NOM: Kampagne (15 Kacheln) + Coop (10 Kacheln,
## Doc G §5.4 geteilte Kontrolle) untereinander, Sterne 0–3 = NUTELLA-Gläser
## aus dem GameState-Slice "gobnom" (GobnomProgress), gesperrte Level
## ausgegraut; unten Gesamt-Gläser + Fertig-Knopf (Muster = GvzLevelSelect).
## Layout ist Anchor-basiert und funktioniert quer UND hochkant.
## W15/GAMESQA2 Level-Menü-Charme (Muster = GvzLevelSelect): AC-Sticker-
## Karten mit Schatten/Hover-Lift/Druck-Senkung, goldene Sterne-Stempel als
## eigenes Label, Locked = flach + "· · ·", Gold-Glanz bei 3 Sternen +
## Gold-Rahmen am nächsten Level (Frontier), gestaffelte Seiten-Blätter-
## Animation beim refresh(), Haptics.tap auf jeder Kachel.

signal level_chosen(track: String, level_id: int)
signal done_pressed

const COLS_LANDSCAPE := 5
const COLS_PORTRAIT := 3
const PAGE_TURN_S := 0.22
const PAGE_TURN_STAGGER_S := 0.03
const PAGE_TURN_MAX_DELAY_S := 0.36
const PAGE_TURN_DEBOUNCE_MS := 600

## Duck-Typing: /root/GameState ODER Test-Double (von gobnom_game gesetzt).
var game_state: Object
## W15 Netz-Coop: „Mit Freund spielen“-Panel (GobnomNetzPanel), von
## gobnom_game VOR add_child gesetzt; null = ohne Netz (reiner Hot-Seat).
var netz_panel: Control

var _grids: Dictionary = {}
var _stars_label: Label
var _buttons: Dictionary = {}
## Level-Key → Sterne-Stempel-Label (goldene Sterne unter der Level-Nummer).
var _stamps: Dictionary = {}
## "c<id>"/"n<id>" → Intro-Schlüssel für das NEU-Badge (neues Element).
var _new_element: Dictionary = {}
## Entprellung der Blätter-Animation (refresh() feuert bei Bau UND Sieg).
var _page_turn_ms := -PAGE_TURN_DEBOUNCE_MS


func _ready() -> void:
	# Parent ist ein Node2D (MinigameBase) — dessen anchorable-Rect ist 0×0,
	# FULL_RECT-Anker kollabieren dort. Darum direkt an den Viewport binden
	# (funktioniert im Arcade-SubViewport UND im Test-/Screenshot-Mount).
	_fit_viewport()
	get_viewport().size_changed.connect(_fit_viewport)
	_load_new_elements()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 14)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var title := Label.new()
	title.theme_type_variation = &"HeadlineLabel"
	title.text = I18nService.t("gobnom.select.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", GobnomArt.OUTLINE)
	column.add_child(title)
	for track: String in [GobnomProgress.TRACK_CAMPAIGN, GobnomProgress.TRACK_COOP]:
		var header := Label.new()
		header.theme_type_variation = &"CaptionLabel"
		header.text = I18nService.t("gobnom.select.%s" % track)
		header.add_theme_font_size_override("font_size", 18)
		header.add_theme_color_override("font_color", GobnomArt.OUTLINE)
		column.add_child(header)
		if track == GobnomProgress.TRACK_COOP and netz_panel != null:
			column.add_child(netz_panel)
		var grid := GridContainer.new()
		grid.columns = COLS_LANDSCAPE
		grid.add_theme_constant_override("h_separation", 8)
		grid.add_theme_constant_override("v_separation", 8)
		column.add_child(grid)
		_grids[track] = grid
		_build_tiles(track, grid)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	column.add_child(footer)
	_stars_label = Label.new()
	_stars_label.theme_type_variation = &"CaptionLabel"
	_stars_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stars_label.add_theme_font_size_override("font_size", 18)
	_stars_label.add_theme_color_override("font_color", GobnomArt.OUTLINE)
	footer.add_child(_stars_label)
	var done := Button.new()
	done.text = I18nService.t("gobnom.select.done")
	done.custom_minimum_size = Vector2(140, 48)
	done.pressed.connect(
		func() -> void:
			Haptics.tap(self)
			AudioDirector.try_play(self, "ui_back")
			done_pressed.emit()
	)
	footer.add_child(done)
	refresh()
	resized.connect(_on_resized)
	_on_resized()


func _build_tiles(track: String, grid: GridContainer) -> void:
	for id in range(1, GobnomProgress.level_count(track) + 1):
		var tile := Button.new()
		tile.custom_minimum_size = Vector2(96, 64)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.add_theme_font_size_override("font_size", 18)
		for state_name in ["font", "font_hover", "font_pressed", "font_focus"]:
			tile.add_theme_color_override("%s_color" % state_name, GobnomArt.OUTLINE)
		tile.add_theme_color_override("font_disabled_color", Color("#B3A99C"))
		tile.pressed.connect(_on_tile.bind(track, id))
		tile.add_child(_build_stamp(GobnomProgress.level_key(track, id)))
		grid.add_child(tile)
		_buttons[GobnomProgress.level_key(track, id)] = tile


## Sterne-Stempel: eigenes Label in der unteren Kartenhälfte, damit die
## Sterne GOLD sein können (Button-Text kann nur eine Farbe). Heller
## Outline-Rand gibt den Stempel-/Sticker-Look.
func _build_stamp(key: String) -> Label:
	var stamp := Label.new()
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stamp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stamp.anchor_top = 0.5
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stamp.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	stamp.add_theme_font_size_override("font_size", 18)
	stamp.add_theme_constant_override("outline_size", 3)
	_stamps[key] = stamp
	return stamp


## Sterne/Sperren neu aus dem Fortschritt lesen (nach jedem Sieg). Kacheln
## feiern den Fortschritt: Mint = geschafft, Gold-Glanz = 3 Sterne, goldener
## Rahmen = das NÄCHSTE Level (Frontier, Muster = GvzLevelSelect).
func refresh() -> void:
	for track: String in [GobnomProgress.TRACK_CAMPAIGN, GobnomProgress.TRACK_COOP]:
		var unlocked := GobnomProgress.max_unlocked(game_state, track)
		for id in range(1, GobnomProgress.level_count(track) + 1):
			var key := GobnomProgress.level_key(track, id)
			var tile: Button = _buttons[key]
			var stamp: Label = _stamps[key]
			var stars := GobnomProgress.level_stars(game_state, track, id)
			var tag := str(id) if track == GobnomProgress.TRACK_CAMPAIGN else "C%d" % id
			if id > unlocked:
				tile.disabled = true
				tile.text = "%s\n" % tag
				stamp.text = stamp_text(0, true)
				_tint_stamp(stamp, Color("#B3A99C"))
				_style_tile(tile, Color("#E7DFD3"), Color("#CDBFAE"), 2, true)
			else:
				tile.disabled = false
				var cleared := GobnomProgress.is_cleared(game_state, track, id)
				var badge := ""
				if not cleared and _new_element.has(key):
					badge = " · %s" % I18nService.t("gobnom.select.new")
				tile.text = "%s%s\n" % [tag, badge]
				stamp.text = stamp_text(stars, false)
				_tint_stamp(stamp, GobnomArt.STAR_GOLD if stars > 0 else Color("#C9BCA9"))
				var fill := Color("#DFF2CF") if cleared else Color("#FFF6E3")
				var border := GobnomArt.OUTLINE
				var width := 3
				if cleared and stars >= 3:
					fill = Color("#FFF1C2")
					border = Color("#D9A83C")
				elif not cleared and id == unlocked:
					border = Color("#D9A83C")
					width = 4
				_style_tile(tile, fill, border, width, false)
	var total := (
		GobnomProgress.total_stars(game_state, GobnomProgress.TRACK_CAMPAIGN)
		+ GobnomProgress.total_stars(game_state, GobnomProgress.TRACK_COOP)
	)
	_stars_label.text = I18nService.t("gobnom.select.stars", {"n": total, "max": 75})
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
## gedeckelt, damit alle 25 Kacheln flott fertig blättern.
static func page_turn_delay(index: int) -> float:
	return minf(maxi(index, 0) * PAGE_TURN_STAGGER_S, PAGE_TURN_MAX_DELAY_S)


## intro-Feld der Level-Daten für die NEU-Badges einlesen.
func _load_new_elements() -> void:
	_new_element = {}
	var tracks := {
		GobnomProgress.TRACK_CAMPAIGN: GobnomData.load_campaign(),
		GobnomProgress.TRACK_COOP: GobnomData.load_coop(),
	}
	for track: String in tracks:
		for level: Dictionary in tracks[track]:
			if str(level.get("intro", "")) != "":
				_new_element[GobnomProgress.level_key(track, int(level["id"]))] = true


## Pastell-Kachel im Sticker-Look: Creme offen, Mint geschafft, Gold-Glanz
## bei 3 Sternen, blass gesperrt; Gold-Rahmen markiert die Frontier.
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
	for key: String in _buttons:
		var tile: Button = _buttons[key]
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


func _on_tile(track: String, id: int) -> void:
	Haptics.tap(self)
	AudioDirector.try_play(self, "ui_confirm")
	level_chosen.emit(track, id)


func _fit_viewport() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size


func _on_resized() -> void:
	var cols := COLS_LANDSCAPE if size.x >= size.y else COLS_PORTRAIT
	for track: String in _grids:
		(_grids[track] as GridContainer).columns = cols
