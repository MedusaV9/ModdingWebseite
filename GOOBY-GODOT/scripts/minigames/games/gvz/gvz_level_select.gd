class_name GvzLevelSelect
extends Control
## Level-Auswahl von GvZ (W3b): 15 Kacheln (5×3), Sterne 1–3 aus dem
## GameState-Slice "gvz" (GvzProgress), gesperrte Level ausgegraut; unten
## Gesamt-Sterne + Fertig-Knopf (meldet die Session ans Framework zurück).
## Layout ist Anchor-basiert und funktioniert quer UND hochkant.

signal level_chosen(level_id: int)
signal done_pressed

const COLS_LANDSCAPE := 5
const COLS_PORTRAIT := 3

## Duck-Typing: /root/GameState ODER Test-Double (von gvz_game gesetzt).
var game_state: Object

var _grid: GridContainer
var _stars_label: Label
var _buttons: Dictionary = {}
## Level-Id → neues Element ("tower"/"zombie") für das NEU-Badge (E11 §Intro).
var _new_element: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_load_new_elements()
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 14)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)
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
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 12)
	column.add_child(footer)
	_stars_label = Label.new()
	_stars_label.theme_type_variation = &"CaptionLabel"
	_stars_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stars_label.add_theme_font_size_override("font_size", 18)
	_stars_label.add_theme_color_override("font_color", GvzArt.OUTLINE)
	footer.add_child(_stars_label)
	var done := Button.new()
	done.text = I18nService.t("gvz.select.done")
	done.custom_minimum_size = Vector2(140, 48)
	done.pressed.connect(
		func() -> void:
			AudioDirector.try_play(self, "ui_back")
			done_pressed.emit()
	)
	footer.add_child(done)
	_build_tiles()
	refresh()
	resized.connect(_on_resized)
	_on_resized()


func _build_tiles() -> void:
	for id in range(1, GvzProgress.LEVEL_COUNT + 1):
		var tile := Button.new()
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
		_grid.add_child(tile)
		_buttons[id] = tile


## Sterne/Sperren neu aus dem Fortschritt lesen (nach jedem Sieg).
func refresh() -> void:
	var unlocked := GvzProgress.max_unlocked(game_state)
	for id in range(1, GvzProgress.LEVEL_COUNT + 1):
		var tile: Button = _buttons[id]
		var stars := GvzProgress.level_stars(game_state, id)
		var badge := " · BOSS" if id == 15 else ""
		if id > unlocked:
			tile.disabled = true
			tile.text = "%d%s" % [id, badge]
			_style_tile(tile, Color("#E7DFD3"), true)
		else:
			tile.disabled = false
			var cleared := GvzProgress.is_cleared(game_state, id)
			# E11 §Intro: das Level, das ein neues Element einführt, sagt das
			# jetzt AN der Kachel (bis es abgeschlossen wurde).
			if not cleared and _new_element.has(id):
				badge += " · %s" % I18nService.t("gvz.select.new")
			var star_row := "☆☆☆"
			if stars > 0:
				star_row = "★".repeat(stars) + "☆".repeat(3 - stars)
			tile.text = "%d%s\n%s" % [id, badge, star_row]
			_style_tile(tile, Color("#DFF2CF") if cleared else Color("#FFF6E3"), false)
	_stars_label.text = I18nService.t(
		"gvz.select.stars", {"n": GvzProgress.total_stars(game_state), "max": 45}
	)


## new_towers/new_zombies aus den Level-Daten für die Badges einlesen.
func _load_new_elements() -> void:
	_new_element = {}
	for level: Dictionary in GvzData.load_levels():
		var id := int(level.get("id", 0))
		if not (level.get("new_towers", []) as Array).is_empty():
			_new_element[id] = "tower"
		elif not (level.get("new_zombies", []) as Array).is_empty():
			_new_element[id] = "zombie"


## Pastell-Kachel im Sticker-Look: Creme offen, Mint geschafft, blass gesperrt.
static func _style_tile(tile: Button, fill: Color, locked: bool) -> void:
	for state_name in ["normal", "hover", "pressed", "disabled", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = fill.darkened(0.06) if state_name == "pressed" else fill
		style.set_corner_radius_all(14)
		style.set_border_width_all(2 if locked else 3)
		style.border_color = Color("#CDBFAE") if locked else GvzArt.OUTLINE
		tile.add_theme_stylebox_override(state_name, style)


func _on_tile(id: int) -> void:
	AudioDirector.try_play(self, "ui_confirm")
	level_chosen.emit(id)


func _on_resized() -> void:
	if _grid != null:
		_grid.columns = COLS_LANDSCAPE if size.x >= size.y else COLS_PORTRAIT
