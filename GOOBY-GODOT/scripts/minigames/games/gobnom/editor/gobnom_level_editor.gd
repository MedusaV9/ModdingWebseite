@tool
class_name GobnomLevelEditor
extends Control
## W15/TECHKIT (Doc G §5) — GOB-NOM-@tool-Level-Editor: neue Level bauen ohne
## Hand-JSON. Bedienung: siehe README.md in diesem Ordner. Kurzform:
## Szene im Godot-Editor öffnen und mit F6 (Aktuelle Szene abspielen)
## starten — links die Welt (Ziehen mit Snap-Raster, Klick = auswählen),
## rechts Datei/Level/Elemente/Eigenschaften und der Validierungs-Knopf
## (BESTEHENDER Auto-Solver → grüne/rote Candy-Flugbahn).
##
## NUR im Editor nutzbar: im Godot-Editor selbst zeigt die Szene nur einen
## Hinweis (die Sim-Klassen sind kein @tool), in EXPORTIERTEN Builds
## entsorgt sich der Editor sofort selbst (plus Export-Filter-Request an
## W2b, s. README). Die eingecheckten Level-Daten bleiben unangetastet —
## gespeichert wird NUR auf den Pfad im Datei-Feld.

const PANEL_WIDTH := 340.0
const OK_COLOR := Color(0.35, 0.9, 0.45)
const BAD_COLOR := Color(0.95, 0.4, 0.35)

var _doc: Dictionary = {}
var _balance: Dictionary = {}
var _level: Dictionary = {}

var _canvas: GobnomEditorCanvas
var _path_edit: LineEdit
var _track_opt: OptionButton
var _level_opt: OptionButton
var _kind_opt: OptionButton
var _grid_spin: SpinBox
var _props_box: VBoxContainer
var _result_label: Label
var _report_label: Label
var _status: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if Engine.is_editor_hint():
		_build_editor_hint()
		return
	if not OS.has_feature("editor"):
		# Export-Guard: der Editor ist reines Dev-Werkzeug — nie im Spiel.
		queue_free()
		return
	_build_ui()
	_load_doc()


## ------------------------------------------------------------------ Daten


func _load_doc() -> void:
	_doc = GobnomEditorLogic.load_doc(_path_edit.text)
	_balance = GobnomData.load_balance()
	var world: Dictionary = _balance.get("world", {})
	_canvas.world = Vector2(_numf(world.get("w"), 960.0), _numf(world.get("h"), 540.0))
	if _doc.is_empty():
		_set_status("Datei leer/kaputt: %s" % _path_edit.text)
		return
	_refresh_levels()
	_set_status("Geladen: %s" % _path_edit.text)


func _save_doc() -> void:
	if GobnomEditorLogic.save_doc(_path_edit.text, _doc):
		_set_status("Gespeichert: %s" % _path_edit.text)
	else:
		_set_status("Speichern fehlgeschlagen: %s" % _path_edit.text)


func _track() -> String:
	return "coop" if _track_opt.selected == 1 else "campaign"


func _refresh_levels(keep_id := -1) -> void:
	_level_opt.clear()
	var ids := GobnomEditorLogic.level_ids(_doc, _track())
	for id in ids:
		_level_opt.add_item("Level %d" % id, id)
	if ids.is_empty():
		_level = {}
		_canvas.level = {}
		_canvas.queue_redraw()
		return
	var target := keep_id if ids.has(keep_id) else ids[0]
	_level_opt.select(ids.find(target))
	_select_level(target)


func _select_level(id: int) -> void:
	_level = GobnomEditorLogic.level_ref(_doc, _track(), id)
	_canvas.level = _level
	_canvas.select_handle("", -2)
	_canvas.clear_solver()
	_rebuild_props()
	_clear_result()


func _new_level() -> void:
	var ids := GobnomEditorLogic.level_ids(_doc, _track())
	var next_id := 1
	for id in ids:
		next_id = maxi(next_id, id + 1)
	var level := {
		"id": next_id,
		"candy": {"x": 480.0, "y": 150.0},
		"mouth": {"x": 480.0, "y": 470.0},
		"ropes": [{"x": 480.0, "y": 90.0, "rest": 60.0}],
		"jars": [{"x": 400.0, "y": 300.0}, {"x": 480.0, "y": 340.0}, {"x": 560.0, "y": 300.0}],
		"solution": {"full_clear": true, "actions": []},
	}
	if _track() == "coop":
		level["split"] = {"axis": "x"}
	if not (_doc.get(_track()) is Array):
		_doc[_track()] = []
	(_doc[_track()] as Array).append(level)
	_refresh_levels(next_id)
	_set_status("Neues Level %d angelegt (Lösungs-Plan fehlt noch!)" % next_id)


## ------------------------------------------------------------ Validierung


func _validate() -> void:
	if _level.is_empty():
		return
	var result := GobnomEditorLogic.validate(_level, _balance)
	var ok := bool(result["ok"])
	# QW #21: UI-Strings über i18n (I18nService.t ist static — @tool-tauglich).
	_result_label.text = I18nService.t(
		"gobnom.editor.loesbar" if ok else "gobnom.editor.nicht_loesbar"
	)
	_result_label.add_theme_color_override("font_color", OK_COLOR if ok else BAD_COLOR)
	var lines: Array[String] = []
	for error: String in result["errors"] as PackedStringArray:
		lines.append("• %s" % error)
	var report: Dictionary = result["solver"]
	if not report.is_empty():
		(
			lines
			. append(
				(
					"Solver: %s · Gläser %d/3 · Sterne %d · Ticks %d · verweigert %d"
					% [
						str(report.get("outcome", "?")),
						int(report.get("jars", 0)),
						int(report.get("stars", 0)),
						int(report.get("ticks", 0)),
						int(report.get("denied", 0)),
					]
				)
			)
		)
	_report_label.text = "\n".join(lines)
	_canvas.show_solver(result["path"] as Array[Vector2], ok)


func _clear_result() -> void:
	_result_label.text = "—"
	_result_label.remove_theme_color_override("font_color")
	_report_label.text = ""


## ---------------------------------------------------------- Eigenschaften


func _rebuild_props() -> void:
	for child in _props_box.get_children():
		child.queue_free()
	if _level.is_empty() or _canvas.selected_kind.is_empty():
		var hint := Label.new()
		hint.text = I18nService.t("gobnom.editor.nichts_gewaehlt")
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_props_box.add_child(hint)
		return
	var kind := _canvas.selected_kind
	var index := _canvas.selected_index
	var title := Label.new()
	title.text = "%s [%d]" % [kind, index] if index >= 0 else kind
	_props_box.add_child(title)
	var props := GobnomEditorLogic.properties_of(_level, kind, index)
	var keys: Array = props.keys()
	keys.sort()
	for key: String in keys:
		_props_box.add_child(_prop_row(kind, index, key, props[key]))


func _prop_row(kind: String, index: int, key: String, value: Variant) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = key
	label.custom_minimum_size = Vector2(90, 0)
	row.add_child(label)
	if value is bool:
		var check := CheckBox.new()
		check.button_pressed = value
		check.toggled.connect(_on_prop_bool.bind(kind, index, key))
		row.add_child(check)
		return row
	var spin := SpinBox.new()
	spin.min_value = -10000.0
	spin.max_value = 10000.0
	spin.step = 0.5
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.value = float(value)
	spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spin.value_changed.connect(_on_prop_num.bind(kind, index, key))
	row.add_child(spin)
	return row


func _on_prop_num(value: float, kind: String, index: int, key: String) -> void:
	if key == "x" or key == "y":
		# Getippte Koordinaten gelten exakt (Snap nur beim Ziehen).
		var props := GobnomEditorLogic.properties_of(_level, kind, index)
		var pos := Vector2(_numf(props.get("x")), _numf(props.get("y")))
		pos.x = value if key == "x" else pos.x
		pos.y = value if key == "y" else pos.y
		GobnomEditorLogic.move_element(_level, kind, index, pos, 0.0)
	else:
		GobnomEditorLogic.set_property(_level, kind, index, key, value)
	_canvas.clear_solver()
	_canvas.queue_redraw()


func _on_prop_bool(pressed: bool, kind: String, index: int, key: String) -> void:
	GobnomEditorLogic.set_property(_level, kind, index, key, pressed)
	_canvas.clear_solver()
	_canvas.queue_redraw()


## ---------------------------------------------------------------- Aktionen


func _on_place_pressed() -> void:
	if _level.is_empty():
		return
	var kind := str(GobnomEditorLogic.ELEMENT_KEYS[_kind_opt.selected])
	_canvas.placement_kind = kind
	_set_status("Platzieren: klick ins Feld für ein neues %s-Element." % kind)


func _on_delete_pressed() -> void:
	if _canvas.selected_index < 0:
		_set_status("Löschen: erst ein Listen-Element wählen (candy/mouth bleiben).")
		return
	if GobnomEditorLogic.remove_element(_level, _canvas.selected_kind, _canvas.selected_index):
		_canvas.select_handle("", -2)
		_canvas.clear_solver()
		_rebuild_props()
		_set_status("Element gelöscht.")


func _on_couple_pressed() -> void:
	# „Verbinden“: Seil-Ruhelänge = aktueller Abstand Anker → Bonbon.
	if _canvas.selected_kind != "ropes" or not (_level.get("candy") is Dictionary):
		_set_status("Koppeln: erst ein Seil (ropes) auswählen.")
		return
	var props := GobnomEditorLogic.properties_of(_level, "ropes", _canvas.selected_index)
	var anchor := Vector2(_numf(props.get("x")), _numf(props.get("y")))
	var candy: Dictionary = _level["candy"]
	var rest := anchor.distance_to(Vector2(_numf(candy.get("x")), _numf(candy.get("y"))))
	GobnomEditorLogic.set_property(
		_level, "ropes", _canvas.selected_index, "rest", snappedf(rest, 1.0)
	)
	_canvas.clear_solver()
	_canvas.queue_redraw()
	_rebuild_props()
	_set_status("Seil gekoppelt: rest = %d px." % int(snappedf(rest, 1.0)))


func _on_selection_changed(_kind: String, _index: int) -> void:
	_rebuild_props()


func _on_level_edited() -> void:
	_rebuild_props()


func _on_track_selected(_idx: int) -> void:
	_refresh_levels()


func _on_level_selected(idx: int) -> void:
	_select_level(_level_opt.get_item_id(idx))


func _on_grid_changed(value: float) -> void:
	_canvas.grid = value
	_canvas.queue_redraw()


func _set_status(text: String) -> void:
	_status.text = text


## ---------------------------------------------------------------------- UI


func _build_editor_hint() -> void:
	var hint := Label.new()
	hint.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hint.text = I18nService.t("gobnom.editor.hint_f6")
	add_child(hint)


func _build_ui() -> void:
	var split := HSplitContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(split)
	_canvas = GobnomEditorCanvas.new()
	_canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_canvas.selection_changed.connect(_on_selection_changed)
	_canvas.level_edited.connect(_on_level_edited)
	split.add_child(_canvas)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	split.add_child(scroll)
	var panel := VBoxContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_constant_override("separation", 8)
	scroll.add_child(panel)
	_build_file_section(panel)
	_build_level_section(panel)
	_build_element_section(panel)
	_build_props_section(panel)
	_build_validate_section(panel)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_status)


func _build_file_section(panel: VBoxContainer) -> void:
	panel.add_child(_headline("Datei"))
	_path_edit = LineEdit.new()
	_path_edit.text = GobnomData.LEVELS_PATH
	panel.add_child(_path_edit)
	var row := HBoxContainer.new()
	row.add_child(_button("Laden", _load_doc))
	row.add_child(_button("Speichern", _save_doc))
	panel.add_child(row)


func _build_level_section(panel: VBoxContainer) -> void:
	panel.add_child(_headline("Level"))
	_track_opt = OptionButton.new()
	_track_opt.add_item("campaign", 0)
	_track_opt.add_item("coop", 1)
	_track_opt.item_selected.connect(_on_track_selected)
	panel.add_child(_track_opt)
	_level_opt = OptionButton.new()
	_level_opt.item_selected.connect(_on_level_selected)
	panel.add_child(_level_opt)
	panel.add_child(_button("Neues Level", _new_level))
	var grid_row := HBoxContainer.new()
	var grid_label := Label.new()
	grid_label.text = I18nService.t("gobnom.editor.snap_raster")
	grid_row.add_child(grid_label)
	_grid_spin = SpinBox.new()
	_grid_spin.min_value = 0.0
	_grid_spin.max_value = 80.0
	_grid_spin.step = 5.0
	_grid_spin.value = GobnomEditorLogic.DEFAULT_GRID
	_grid_spin.value_changed.connect(_on_grid_changed)
	grid_row.add_child(_grid_spin)
	panel.add_child(grid_row)


func _build_element_section(panel: VBoxContainer) -> void:
	panel.add_child(_headline("Elemente"))
	_kind_opt = OptionButton.new()
	for kind in GobnomEditorLogic.ELEMENT_KEYS:
		_kind_opt.add_item(kind)
	panel.add_child(_kind_opt)
	panel.add_child(_button("Platzieren (dann Klick ins Feld)", _on_place_pressed))
	panel.add_child(_button("Auswahl löschen", _on_delete_pressed))
	panel.add_child(_button("Seil ans Bonbon koppeln", _on_couple_pressed))


func _build_props_section(panel: VBoxContainer) -> void:
	panel.add_child(_headline("Eigenschaften"))
	_props_box = VBoxContainer.new()
	panel.add_child(_props_box)


func _build_validate_section(panel: VBoxContainer) -> void:
	panel.add_child(_headline("Validierung"))
	panel.add_child(_button("Level prüfen (Auto-Solver)", _validate))
	_result_label = Label.new()
	_result_label.text = "—"
	panel.add_child(_result_label)
	_report_label = Label.new()
	_report_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_report_label)


func _headline(text: String) -> Label:
	var label := Label.new()
	label.text = text.to_upper()
	label.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	return label


func _button(text: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(on_pressed)
	return button


static func _numf(value: Variant, fallback := 0.0) -> float:
	if value is float or value is int:
		return float(value)
	return fallback
