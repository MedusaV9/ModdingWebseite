class_name RanchLevelSelect
extends Control
## Level-Auswahl der Ranch-Minispiele (RANCH-2): 10 Kacheln mit Sternen
## 0–3 aus `ranch.spiele.<spiel>` (RanchSpieleProgress), gesperrte Level
## ausgegraut, unten Gesamt-Sterne + Fertig-Knopf (Muster =
## GobnomLevelSelect). Anchor-Layout, funktioniert quer UND hochkant.

signal level_chosen(level_id: int)
signal done_pressed

const COLS_LANDSCAPE := 5
const COLS_PORTRAIT := 3
const TILE_FILL_OFFEN := Color("#FFF6E3")
const TILE_FILL_GESCHAFFT := Color("#DFF2CF")
const TILE_FILL_GESPERRT := Color("#E7DFD3")
const RAND_INK := Color("#3B3630")

## Duck-Typing: /root/GameState ODER Test-Double (vom Spiel gesetzt).
var game_state: Object
## "parcours" oder "herde" (RanchSpieleProgress-Schlüssel).
var spiel := RanchSpieleProgress.SPIEL_PARCOURS
## Titel-Key (mg.ranchParcours.title / mg.ranchHerde.title).
var title_key := "mg.ranchParcours.title"
## Kachel-Präfix ("K" = Kurs, "L" = Level).
var tile_prefix := "K"

var _grid: GridContainer
var _stars_label: Label
var _buttons: Array[Button] = []


func _ready() -> void:
	_fit_viewport()
	get_viewport().size_changed.connect(_fit_viewport)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 14)
	add_child(margin)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(scroll)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)
	var title := Label.new()
	title.theme_type_variation = &"HeadlineLabel"
	title.text = I18nService.t(title_key)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", RAND_INK)
	column.add_child(title)
	var hint := Label.new()
	hint.theme_type_variation = &"SoftLabel"
	hint.text = I18nService.t("ranchplay.select.hint_%s" % spiel)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(hint)
	_grid = GridContainer.new()
	_grid.columns = COLS_LANDSCAPE
	_grid.add_theme_constant_override("h_separation", 8)
	_grid.add_theme_constant_override("v_separation", 8)
	column.add_child(_grid)
	for id in range(1, RanchSpieleProgress.LEVEL_COUNT + 1):
		var tile := Button.new()
		tile.custom_minimum_size = Vector2(96, 64)
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.add_theme_font_size_override("font_size", 18)
		for state_name in ["font", "font_hover", "font_pressed", "font_focus"]:
			tile.add_theme_color_override("%s_color" % state_name, RAND_INK)
		tile.add_theme_color_override("font_disabled_color", Color("#B3A99C"))
		tile.pressed.connect(_on_tile.bind(id))
		_grid.add_child(tile)
		_buttons.append(tile)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	column.add_child(footer)
	_stars_label = Label.new()
	_stars_label.theme_type_variation = &"CaptionLabel"
	_stars_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stars_label.add_theme_font_size_override("font_size", 18)
	_stars_label.add_theme_color_override("font_color", RAND_INK)
	footer.add_child(_stars_label)
	var done := Button.new()
	done.text = I18nService.t("ranchplay.select.done")
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


## Sterne/Sperren neu aus dem Fortschritt lesen (nach jedem Sieg).
func refresh() -> void:
	var unlocked := RanchSpieleProgress.max_unlocked(game_state, spiel)
	for id in range(1, RanchSpieleProgress.LEVEL_COUNT + 1):
		var tile := _buttons[id - 1]
		var tag := "%s%d" % [tile_prefix, id]
		if id > unlocked:
			tile.disabled = true
			tile.text = tag
			_style_tile(tile, TILE_FILL_GESPERRT, true)
		else:
			tile.disabled = false
			var stars := RanchSpieleProgress.level_stars(game_state, spiel, id)
			var cleared := RanchSpieleProgress.is_cleared(game_state, spiel, id)
			tile.text = "%s\n%s%s" % [tag, "★".repeat(stars), "☆".repeat(3 - stars)]
			_style_tile(tile, TILE_FILL_GESCHAFFT if cleared else TILE_FILL_OFFEN, false)
	_stars_label.text = I18nService.t(
		"ranchplay.select.stars",
		{"n": RanchSpieleProgress.total_stars(game_state, spiel), "max": 30}
	)


## Pastell-Kachel im Sticker-Look (Muster GobnomLevelSelect).
static func _style_tile(tile: Button, fill: Color, locked: bool) -> void:
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = fill.darkened(0.06) if state_name == "pressed" else fill
		style.set_corner_radius_all(14)
		style.set_border_width_all(2 if locked else 3)
		style.border_color = Color("#CDBFAE") if locked else RAND_INK
		tile.add_theme_stylebox_override(state_name, style)


func _on_tile(id: int) -> void:
	AudioDirector.try_play(self, "ui_confirm")
	level_chosen.emit(id)


func _fit_viewport() -> void:
	position = Vector2.ZERO
	size = get_viewport_rect().size


func _on_resized() -> void:
	if _grid != null:
		_grid.columns = COLS_LANDSCAPE if size.x >= size.y else COLS_PORTRAIT
