class_name TransferScreen
extends Control
## „Spielstand übertragen“-Screen (FIX-6; Doc H §5.3 sichtbar gemacht).
##
## Drei Wege in EINEM Screen:
## 1. AUTO: auf iOS wird der Alt-App-Spielstand (NSUserDefaults-Spiegelung,
##    legacy_capacitor.gd — ohne Plugin) beim Öffnen gesucht und als
##    „Gefunden!“-Karte mit Vorschau angeboten.
## 2. EINFÜGEN: Spielstand-JSON aus der Alt-App (Einstellungen → „Spielstand
##    exportieren“) oder ein GOOBY5-Code ins Textfeld → Prüfen → Vorschau
##    (Level/Münzen/Sticker/Outfits/Möbel + Umzugs-Hinweise) → Übernehmen.
## 3. DATEI: auf Desktops zusätzlich per FileDialog.
## Übernehmen sichert den alten Stand (transfer_service.apply → Vorsicherung)
## und ersetzt erst dann. Erreichbar über die Route `state/transfer`
## (Settings-Zeile: Handoff FIX6-settings-request.md an FIX-1).

signal back_requested

const TransferService := preload("res://scripts/state/import/transfer_service.gd")
const MovingBoxImport := preload("res://scripts/state/moving_box_import.gd")

const ROUTE := &"state/transfer"
const ROUTES := {ROUTE: "res://scripts/state/import/transfer_screen.tscn"}

## Tests/Screenshots: GameState-artiges Objekt statt /root/GameState.
var gs_override: Object = null
## Tests: fixe Uhr (0 = Systemzeit).
var now_override := 0
## Tests: Plist-Pfad für den Auto-Import (statt iOS-Container).
var plist_override := ""
## Tests: Auto-Suche abschaltbar.
var auto_probe := true

## Aktuelle Phase: input → preview → done (für Tests/Screenshots lesbar).
var phase := "input"

var _preview_result: Dictionary = {}
var _scroll: ScrollContainer
var _input: TextEdit
var _auto_card: PanelContainer
var _auto_label: Label
var _paste_card: PanelContainer
var _preview_card: PanelContainer
var _preview_line: Label
var _preview_furniture: Label
var _notes_box: VBoxContainer
var _error_card: PanelContainer
var _error_body: Label
var _done_card: PanelContainer
var _export_feedback: Label
var _file_dialog: FileDialog


static func register_routes() -> void:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return
	var router := (loop as SceneTree).root.get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("register_routes"):
		router.register_routes(ROUTES)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	register_routes()
	_build_ui()
	if auto_probe:
		_probe_auto()


## ── Test-/Automations-API ────────────────────────────────────────────────────


func set_input_text(text: String) -> void:
	_input.text = text


func check_now() -> Dictionary:
	_on_check_pressed()
	return _preview_result


func apply_now() -> void:
	_on_apply_pressed()


## ── Aufbau ───────────────────────────────────────────────────────────────────


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.98, 0.94, 0.87)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", 12)
	_scroll.add_child(rows)
	var pad := MarginContainer.new()
	for side in ["left", "right"]:
		pad.add_theme_constant_override("margin_%s" % side, 24)
	pad.add_theme_constant_override("margin_top", 16)
	pad.add_theme_constant_override("margin_bottom", 24)
	rows.add_child(pad)
	var inner := VBoxContainer.new()
	inner.add_theme_constant_override("separation", 12)
	pad.add_child(inner)

	_build_header(inner)
	var intro := _caption(I18nService.t("save.transfer.intro"))
	inner.add_child(intro)
	_auto_card = _build_auto_card(inner)
	_paste_card = _build_paste_card(inner)
	_preview_card = _build_preview_card(inner)
	_error_card = _build_error_card(inner)
	_done_card = _build_done_card(inner)
	_build_export_card(inner)
	_show_phase_input()


func _build_header(parent: Container) -> void:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	parent.add_child(header)
	var back := Button.new()
	back.theme_type_variation = &"GhostButton"
	back.text = I18nService.t("save.transfer.back")
	back.pressed.connect(_on_back_pressed)
	header.add_child(back)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = I18nService.t("save.transfer.title")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)


func _build_auto_card(parent: Container) -> PanelContainer:
	var card := _card(parent)
	card.visible = false
	var box := _card_box(card)
	_auto_label = Label.new()
	_auto_label.theme_type_variation = &"HeadlineLabel"
	_auto_label.text = I18nService.t("save.transfer.auto.found")
	_auto_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_auto_label)
	box.add_child(_caption(I18nService.t("save.transfer.auto.source_ios")))
	var button := Button.new()
	button.theme_type_variation = &"PrimaryButton"
	button.text = I18nService.t("save.transfer.auto.preview")
	button.pressed.connect(_on_auto_preview_pressed)
	box.add_child(button)
	return card


func _build_paste_card(parent: Container) -> PanelContainer:
	var card := _card(parent)
	var box := _card_box(card)
	var title := Label.new()
	title.theme_type_variation = &"HeadlineLabel"
	title.text = I18nService.t("save.transfer.paste.title")
	box.add_child(title)
	box.add_child(_caption(I18nService.t("save.transfer.paste.hint")))
	_input = TextEdit.new()
	_input.placeholder_text = I18nService.t("save.transfer.paste.placeholder")
	_input.custom_minimum_size = Vector2(0.0, 132.0)
	_input.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_child(_input)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	var check := Button.new()
	check.theme_type_variation = &"PrimaryButton"
	check.text = I18nService.t("save.transfer.paste.check")
	check.pressed.connect(_on_check_pressed)
	buttons.add_child(check)
	var from_file := Button.new()
	from_file.theme_type_variation = &"GhostButton"
	from_file.text = I18nService.t("save.transfer.file.button")
	from_file.pressed.connect(_on_file_pressed)
	buttons.add_child(from_file)
	return card


func _build_preview_card(parent: Container) -> PanelContainer:
	var card := _card(parent)
	card.visible = false
	var box := _card_box(card)
	var title := Label.new()
	title.theme_type_variation = &"HeadlineLabel"
	title.text = I18nService.t("save.transfer.preview.title")
	box.add_child(title)
	_preview_line = Label.new()
	_preview_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_preview_line)
	_preview_furniture = _caption("")
	box.add_child(_preview_furniture)
	box.add_child(_caption(I18nService.t("save.transfer.preview.notes")))
	_notes_box = VBoxContainer.new()
	_notes_box.add_theme_constant_override("separation", 2)
	box.add_child(_notes_box)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	box.add_child(buttons)
	var apply := Button.new()
	apply.theme_type_variation = &"PrimaryButton"
	apply.text = I18nService.t("save.transfer.preview.apply")
	apply.pressed.connect(_on_apply_pressed)
	buttons.add_child(apply)
	var cancel := Button.new()
	cancel.theme_type_variation = &"GhostButton"
	cancel.text = I18nService.t("save.transfer.preview.cancel")
	cancel.pressed.connect(_on_cancel_pressed)
	buttons.add_child(cancel)
	return card


func _build_error_card(parent: Container) -> PanelContainer:
	var card := _card(parent)
	card.visible = false
	var box := _card_box(card)
	var title := Label.new()
	title.theme_type_variation = &"HeadlineLabel"
	title.text = I18nService.t("save.transfer.error.title")
	box.add_child(title)
	_error_body = _caption("")
	box.add_child(_error_body)
	return card


func _build_done_card(parent: Container) -> PanelContainer:
	var card := _card(parent)
	card.visible = false
	var box := _card_box(card)
	var title := Label.new()
	title.theme_type_variation = &"HeadlineLabel"
	title.text = I18nService.t("save.transfer.done.title")
	box.add_child(title)
	box.add_child(_caption(I18nService.t("save.transfer.done.body")))
	box.add_child(_caption(I18nService.t("save.transfer.done.moving")))
	var cont := Button.new()
	cont.theme_type_variation = &"PrimaryButton"
	cont.text = I18nService.t("save.transfer.done.continue")
	cont.pressed.connect(_on_back_pressed)
	box.add_child(cont)
	return card


func _build_export_card(parent: Container) -> void:
	var card := _card(parent)
	var box := _card_box(card)
	var title := Label.new()
	title.theme_type_variation = &"HeadlineLabel"
	title.text = I18nService.t("save.transfer.export.title")
	box.add_child(title)
	var button := Button.new()
	button.theme_type_variation = &"GhostButton"
	button.text = I18nService.t("save.transfer.export.button")
	button.pressed.connect(_on_export_pressed)
	box.add_child(button)
	_export_feedback = _caption("")
	_export_feedback.visible = false
	box.add_child(_export_feedback)


func _card(parent: Container) -> PanelContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = &"AcCard"
	parent.add_child(card)
	return card


func _card_box(card: PanelContainer) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)
	return box


func _caption(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"CaptionLabel"
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label


## ── Ablauf ───────────────────────────────────────────────────────────────────


func _probe_auto() -> void:
	var probe := TransferService.probe_legacy(_now_ms(), plist_override)
	if not probe["found"]:
		return
	_auto_card.visible = true
	set_meta("auto_probe", probe)


func _on_auto_preview_pressed() -> void:
	var probe: Variant = get_meta("auto_probe", {})
	if probe is Dictionary and not (probe as Dictionary).is_empty():
		_show_preview((probe as Dictionary)["preview"])


func _on_check_pressed() -> void:
	_preview_result = TransferService.preview_text(_input.text, _now_ms())
	_show_preview(_preview_result)


func _on_file_pressed() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_SUBWINDOWS):
		_show_error(I18nService.t("save.transfer.file.unsupported"))
		return
	if _file_dialog == null:
		_file_dialog = FileDialog.new()
		_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
		_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_file_dialog.filters = PackedStringArray(["*.json,*.txt ; Gooby-Spielstand"])
		_file_dialog.file_selected.connect(_on_file_selected)
		add_child(_file_dialog)
	_file_dialog.popup_centered_ratio(0.8)


func _on_file_selected(path: String) -> void:
	_preview_result = TransferService.preview_file(path, _now_ms())
	_show_preview(_preview_result)


func _show_preview(result: Dictionary) -> void:
	if not result.get("ok", false):
		_show_error(
			I18nService.t("save.transfer.error.body", {"error": str(result.get("error", "?"))})
		)
		return
	_preview_result = result
	phase = "preview"
	_error_card.visible = false
	_preview_card.visible = true
	var info := TransferService.report_summary(result["report"])
	_preview_line.text = I18nService.t("save.transfer.preview.line", info)
	_preview_furniture.text = I18nService.t("save.transfer.preview.furniture", info)
	_preview_furniture.visible = int(info["furniture"]) > 0
	for child in _notes_box.get_children():
		child.queue_free()
	var state: Dictionary = result["state"]
	var migration: Dictionary = state.get("migration", {})
	for note: Variant in _note_lines(migration):
		_notes_box.add_child(_caption("• %s" % str(note)))
	_scroll_to(_preview_card)


func _note_lines(migration: Dictionary) -> Array:
	var lines: Array = []
	var notes: Variant = migration.get("notes", [])
	if notes is Array:
		lines.append_array(notes)
	var lost: Variant = migration.get("lost", [])
	if lost is Array:
		lines.append_array(lost)
	return lines


func _show_error(body: String) -> void:
	phase = "input"
	_preview_card.visible = false
	_error_card.visible = true
	_error_body.text = body
	_scroll_to(_error_card)


## Karte in den Blick scrollen — auf dem iPhone liegt die Vorschau sonst
## unterhalb des Sichtbereichs (die Einfuege-Karte ist hoch). Layout ist erst
## nach dem Container-Sort des naechsten Frames gueltig, daher Koroutine.
func _scroll_to(card: Control) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	if is_instance_valid(_scroll) and is_instance_valid(card) and card.is_visible_in_tree():
		_scroll.ensure_control_visible(card)


func _on_apply_pressed() -> void:
	if phase != "preview" or not _preview_result.get("ok", false):
		return
	if not TransferService.apply(_preview_result["state"], _game_state()):
		_show_error(I18nService.t("save.transfer.error.body", {"error": "GameState fehlt"}))
		return
	phase = "done"
	_auto_card.visible = false
	_paste_card.visible = false
	_preview_card.visible = false
	_error_card.visible = false
	_done_card.visible = true
	_scroll.scroll_vertical = 0


func _on_cancel_pressed() -> void:
	_preview_result = {}
	_show_phase_input()


func _show_phase_input() -> void:
	phase = "input"
	_paste_card.visible = true
	_preview_card.visible = false
	_error_card.visible = false
	_done_card.visible = false


func _on_export_pressed() -> void:
	var gs := _game_state()
	if gs == null or not gs.has_method("state"):
		return
	DisplayServer.clipboard_set(MovingBoxImport.export_code(gs.state()))
	_export_feedback.text = I18nService.t("save.transfer.export.copied")
	_export_feedback.visible = true


func _on_back_pressed() -> void:
	back_requested.emit()
	var router := get_node_or_null("/root/SceneRouter")
	if router == null or not router.has_method("goto"):
		return
	var routes: Variant = router.get("_routes")
	if routes is Dictionary and (routes as Dictionary).has(&"home"):
		router.goto(&"home", {})


func _game_state() -> Object:
	if gs_override != null:
		return gs_override
	return get_node_or_null("/root/GameState")


func _now_ms() -> int:
	if now_override > 0:
		return now_override
	return int(Time.get_unix_time_from_system() * 1000.0)
