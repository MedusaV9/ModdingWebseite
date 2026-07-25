class_name GobnomLevelSelect
extends Control
## Level-Auswahl von GOB NOM: Kampagne (15 Kacheln) + Coop (10 Kacheln,
## Doc G §5.4 geteilte Kontrolle) untereinander, Sterne 0–3 = NUTELLA-Gläser
## aus dem GameState-Slice "gobnom" (GobnomProgress), gesperrte Level
## ausgegraut; unten Gesamt-Gläser + Fertig-Knopf (Muster = GvzLevelSelect).
## Layout ist Anchor-basiert und funktioniert quer UND hochkant.

signal level_chosen(track: String, level_id: int)
signal done_pressed

const COLS_LANDSCAPE := 5
const COLS_PORTRAIT := 3

## Duck-Typing: /root/GameState ODER Test-Double (von gobnom_game gesetzt).
var game_state: Object

var _grids: Dictionary = {}
var _stars_label: Label
var _buttons: Dictionary = {}
## "c<id>"/"n<id>" → Intro-Schlüssel für das NEU-Badge (neues Element).
var _new_element: Dictionary = {}


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
		grid.add_child(tile)
		_buttons[GobnomProgress.level_key(track, id)] = tile


## Sterne/Sperren neu aus dem Fortschritt lesen (nach jedem Sieg).
func refresh() -> void:
	for track: String in [GobnomProgress.TRACK_CAMPAIGN, GobnomProgress.TRACK_COOP]:
		var unlocked := GobnomProgress.max_unlocked(game_state, track)
		for id in range(1, GobnomProgress.level_count(track) + 1):
			var key := GobnomProgress.level_key(track, id)
			var tile: Button = _buttons[key]
			var stars := GobnomProgress.level_stars(game_state, track, id)
			var tag := str(id) if track == GobnomProgress.TRACK_CAMPAIGN else "C%d" % id
			if id > unlocked:
				tile.disabled = true
				tile.text = tag
				_style_tile(tile, Color("#E7DFD3"), true)
			else:
				tile.disabled = false
				var cleared := GobnomProgress.is_cleared(game_state, track, id)
				var badge := ""
				if not cleared and _new_element.has(key):
					badge = " · %s" % I18nService.t("gobnom.select.new")
				var star_row := "★".repeat(stars) + "☆".repeat(3 - stars)
				tile.text = "%s%s\n%s" % [tag, badge, star_row]
				_style_tile(tile, Color("#DFF2CF") if cleared else Color("#FFF6E3"), false)
	var total := (
		GobnomProgress.total_stars(game_state, GobnomProgress.TRACK_CAMPAIGN)
		+ GobnomProgress.total_stars(game_state, GobnomProgress.TRACK_COOP)
	)
	_stars_label.text = I18nService.t("gobnom.select.stars", {"n": total, "max": 75})


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


## Pastell-Kachel im Sticker-Look: Creme offen, Mint geschafft, blass gesperrt.
static func _style_tile(tile: Button, fill: Color, locked: bool) -> void:
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = fill.darkened(0.06) if state_name == "pressed" else fill
		style.set_corner_radius_all(14)
		style.set_border_width_all(2 if locked else 3)
		style.border_color = Color("#CDBFAE") if locked else GobnomArt.OUTLINE
		tile.add_theme_stylebox_override(state_name, style)


func _on_tile(track: String, id: int) -> void:
	AudioDirector.try_play(self, "ui_confirm")
	level_chosen.emit(track, id)


func _fit_viewport() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size


func _on_resized() -> void:
	var cols := COLS_LANDSCAPE if size.x >= size.y else COLS_PORTRAIT
	for track: String in _grids:
		(_grids[track] as GridContainer).columns = cols
