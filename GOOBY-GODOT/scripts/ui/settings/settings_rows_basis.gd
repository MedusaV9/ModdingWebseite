class_name SettingsRowsBasis
extends Control
## W14/UISCREENS-A: Generische Row-/Karten-Bausteine des Settings-Screens,
## als Basisklasse ausgelagert (gdlint-1000-Zeilen-Limit). Enthält NUR die
## wiederverwendbaren Builder (Karte/Pick/Switch/Slider/Hilfe) und die
## AppSettings-Lesehelfer — die Sektions-INHALTE wohnen in
## settings_screen.gd. Skalierungs-Faktoren setzt der erbende Screen.

## Aktueller UiScale-Faktor (FIX1) — setzt _rebuild, nutzen die Row-Builder.
var _f := 1.0
## Font-Faktor (= _f x Textgroesse-Regler).
var _tf := 1.0
## W14 (FB3-Regel): PHYSISCHER Touch-Floor in Canvas-px (44 pt echt) — die
## reine 48×_f-Höhe blieb auf Retina unter der Apple-HIG-Tippfläche.
var _floor_px := float(AcTokens.TOUCH_FLOOR)
var _scroll_dragging := false
## Ziel-VBox für die Sektions-Karten (weist der Screen in _ready zu).
var _sections: VBoxContainer


## Row-Kontrollhöhe: Design-Floor × Faktor, nie unter dem physischen Floor.
func _row_floor() -> float:
	return maxf(AcTokens.TOUCH_FLOOR * _f, _floor_px)


## W14: `show_title = false` für Hüllen-Karten, deren Titel bereits der
## Gruppen-Header direkt darüber trägt (Mehrspieler/Spielstand — keine
## doppelte Überschrift im Bild).
func _add_section(node_name: String, title: String, show_title := true) -> VBoxContainer:
	var card := PanelContainer.new()
	card.name = "Section" + node_name
	card.theme_type_variation = "AcCard"
	card.mouse_filter = Control.MOUSE_FILTER_PASS
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.mouse_filter = Control.MOUSE_FILTER_PASS
	rows.add_theme_constant_override("separation", int(10.0 * _f))
	if show_title:
		var title_label := Label.new()
		title_label.name = "SectionTitle"
		title_label.theme_type_variation = "TitleLabel"
		title_label.text = title
		title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		title_label.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_TITLE * _tf))
		rows.add_child(title_label)
	card.add_child(rows)
	_sections.add_child(card)
	return rows


## Zentrierter Aktions-Button innerhalb einer Sektion (Text via String-Key).
func _section_button(rows: VBoxContainer, node_name: String, text_key: String) -> SquishButton:
	var btn := SquishButton.new()
	btn.name = node_name
	btn.theme_type_variation = "BtnTeal"
	btn.text = I18nService.t(text_key)
	btn.custom_minimum_size = Vector2(0, 52.0 * _f)
	btn.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BUTTON * _tf))
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.focus_mode = Control.FOCUS_NONE
	rows.add_child(btn)
	return btn


## Kurzerklaerung unter einer Row (SoftLabel, Caption-Groesse).
func _add_help(rows: VBoxContainer, node_name: String, text: String) -> void:
	var label := Label.new()
	label.name = node_name
	label.theme_type_variation = "SoftLabel"
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_CAPTION * _tf))
	rows.add_child(label)


## OptionButton-Row (generisch): options = [[id, label], ...],
## handler(id: String) wird bei Auswahl gerufen.
func _add_pick_row(
	rows: VBoxContainer,
	key: String,
	label_text: String,
	options: Array,
	current_id: String,
	handler: Callable
) -> OptionButton:
	var row := _make_row(rows, key, label_text)
	var picker := OptionButton.new()
	picker.name = "Value"
	picker.focus_mode = Control.FOCUS_NONE
	picker.custom_minimum_size = Vector2(210.0 * _f, _row_floor())
	picker.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BODY * _tf))
	for i in options.size():
		picker.add_item(str(options[i][1]), i)
		if str(options[i][0]) == current_id:
			picker.select(i)
	picker.item_selected.connect(func(index: int) -> void: handler.call(str(options[index][0])))
	row.add_child(picker)
	return picker


## CheckButton-Row (generisch): handler(on: bool).
func _add_switch_row(
	rows: VBoxContainer, key: String, label_text: String, initial: bool, handler: Callable
) -> CheckButton:
	var row := _make_row(rows, key, label_text)
	var toggle := CheckButton.new()
	toggle.name = "Value"
	toggle.focus_mode = Control.FOCUS_NONE
	# W14 (FB3-Audit): Floor auf BEIDEN Achsen — die kurze Seite eines
	# CheckButtons ist seine BREITE (Toggle-Icon ~76 px = 23 pt).
	toggle.custom_minimum_size = Vector2(_row_floor(), _row_floor())
	toggle.button_pressed = initial
	toggle.toggled.connect(func(on: bool) -> void: handler.call(on))
	row.add_child(toggle)
	return toggle


## HSlider-Row (generisch): handler(value: float) bei jeder Aenderung;
## rebuild_on_release baut den Screen nach dem Loslassen neu (Anzeige-Regler,
## die die Skalierung dieses Screens selbst veraendern).
func _add_range_row(
	rows: VBoxContainer,
	key: String,
	label_text: String,
	min_value: float,
	max_value: float,
	step: float,
	initial: float,
	handler: Callable,
	rebuild_on_release := false
) -> HSlider:
	var row := _make_row(rows, key, label_text)
	var slider := HSlider.new()
	slider.name = "Value"
	slider.focus_mode = Control.FOCUS_NONE
	slider.min_value = min_value
	slider.max_value = max_value
	slider.step = step
	slider.value = clampf(initial, min_value, max_value)
	slider.custom_minimum_size = Vector2(240.0 * _f, _row_floor())
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(value: float) -> void: handler.call(value))
	if rebuild_on_release:
		slider.drag_ended.connect(
			func(changed: bool) -> void:
				if changed and not _scroll_dragging:
					call_deferred("_rebuild")
		)
	row.add_child(slider)
	return slider


func _make_row(rows: VBoxContainer, key: String, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Row" + key.to_pascal_case()
	row.add_theme_constant_override("separation", int(12.0 * _f))
	var label := Label.new()
	label.name = "RowLabel"
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# W14 (FB3-Audit): Autowrap — ohne treibt das LÄNGSTE Label die
	# Karten-Mindestbreite über den Canvas (Hochformat lief 11 px über).
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BODY * _tf))
	row.add_child(label)
	rows.add_child(row)
	return row


func _select_pick(picker: OptionButton, id: String, options: Array) -> void:
	if picker == null or not is_instance_valid(picker):
		return
	for i in options.size():
		if str(options[i][0]) == id:
			picker.select(i)
			return


func _app_value(key: String, fallback: Variant) -> Variant:
	var app := _app()
	if app != null and app.has_method("value_of"):
		var value: Variant = app.value_of(key)
		if value != null:
			return value
	return fallback


func _app_on(key: String, fallback: bool) -> bool:
	var app := _app()
	if app != null and app.has_method("is_on"):
		return app.is_on(key)
	return fallback


## Bool-Schalter mit EXPLIZITEM Default: für Keys, die (noch) nicht in
## AppSettings._defaults stehen — is_on() fiele dort auf false zurück.
func _app_on_default(key: String, fallback: bool) -> bool:
	var app := _app()
	if app != null and app.has_method("get_setting"):
		return bool(app.get_setting(key, fallback))
	return fallback


func _app() -> Node:
	return get_node_or_null("/root/AppSettings")
