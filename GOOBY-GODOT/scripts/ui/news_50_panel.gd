class_name News50Panel
extends PanelSheet
## 5.0-Neuigkeiten-Panel: Liste der Godot-Rewrite-Highlights (DEUTSCH,
## Inhalte aus strings `news.items`). Baut auf dem Bottom-Sheet auf;
## `news_seen` feuert beim Bestätigen (W1d persistiert `whats_new_5_seen`).

signal news_seen

const ICON_DIR := "res://assets/ui/icons/"


func _ready() -> void:
	super()
	set_title(I18nService.t("news.titel"))
	add_content(_build_content())


func _build_content() -> Control:
	var vbox := VBoxContainer.new()
	vbox.name = "NewsList"
	vbox.add_theme_constant_override("separation", 12)
	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.theme_type_variation = "SoftLabel"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.text = I18nService.t("news.untertitel")
	vbox.add_child(subtitle)
	var entries := I18nService.items("news.items")
	for i in entries.size():
		vbox.add_child(_build_item_row(i, entries[i]))
	var ok := SquishButton.new()
	ok.name = "NewsOkButton"
	ok.theme_type_variation = "BtnLeaf"
	ok.text = I18nService.t("news.button")
	ok.custom_minimum_size = Vector2(220, 52)
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.focus_mode = Control.FOCUS_NONE
	ok.pressed.connect(_on_ok_pressed)
	vbox.add_child(ok)
	return vbox


func _build_item_row(index: int, entry: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.name = "Item%d" % index
	row.theme_type_variation = "AcWell"
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	var icon := TextureRect.new()
	icon.texture = load(ICON_DIR + "sparkle.svg")
	icon.custom_minimum_size = Vector2(28, 28)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.self_modulate = AcTokens.YELLOW_DARK
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.name = "ItemTitle"
	title.text = str(entry.get("titel", ""))
	text_box.add_child(title)
	var body := Label.new()
	body.name = "ItemText"
	body.theme_type_variation = "CaptionLabel"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = str(entry.get("text", ""))
	text_box.add_child(body)
	box.add_child(text_box)
	row.add_child(box)
	return row


func _on_ok_pressed() -> void:
	news_seen.emit()
	close()
