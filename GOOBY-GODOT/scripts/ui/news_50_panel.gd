class_name News50Panel
extends PanelSheet
## 5.0-Neuigkeiten-Panel: Liste der Godot-Rewrite-Highlights (DEUTSCH,
## Inhalte aus strings `news.items`). Baut auf dem Bottom-Sheet auf;
## `news_seen` feuert beim Bestätigen (W1d persistiert `whats_new_5_seen`).
##
## FIX1 („Patchnotes komplett broken“): Das Sheet selbst ist jetzt
## zentriert, breiten-gedeckelt und SCROLLT (PanelSheet-Umbau) — vorher
## wuchs die Liste ungebremst aus dem Bildschirm und das Panel war leer.
## Neu außerdem: Versions-Zeile (aus project.godot `config/version`).

signal news_seen

const ICON_DIR := "res://assets/ui/icons/"


func _ready() -> void:
	super()
	set_title(I18nService.t("news.titel"))
	add_content(_build_content())


## FIX1: bei jedem Öffnen frisch bauen — so stimmt die Schrift-Skalierung
## auch nach Rotation/Resize (Faktor wird in _build_content gelesen).
func open() -> void:
	if not is_open():
		add_content(_build_content())
	super()


func _build_content() -> Control:
	var f := UiScale.for_viewport(get_viewport())
	var vbox := VBoxContainer.new()
	vbox.name = "NewsList"
	vbox.add_theme_constant_override("separation", int(12.0 * f))
	var subtitle := Label.new()
	subtitle.name = "Subtitle"
	subtitle.theme_type_variation = "SoftLabel"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BODY * f))
	subtitle.text = I18nService.t("news.untertitel")
	vbox.add_child(subtitle)
	var version := Label.new()
	version.name = "VersionLabel"
	version.theme_type_variation = "CaptionLabel"
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	version.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_CAPTION * f))
	version.text = I18nService.t(
		"news.version",
		{"version": str(ProjectSettings.get_setting("application/config/version", "5.0.0"))}
	)
	vbox.add_child(version)
	var entries := I18nService.items("news.items")
	for i in entries.size():
		vbox.add_child(_build_item_row(i, entries[i], f))
	var ok := SquishButton.new()
	ok.name = "NewsOkButton"
	ok.theme_type_variation = "BtnLeaf"
	ok.text = I18nService.t("news.button")
	ok.custom_minimum_size = Vector2(220.0 * f, 52.0 * f)
	ok.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BUTTON * f))
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.focus_mode = Control.FOCUS_NONE
	ok.pressed.connect(_on_ok_pressed)
	vbox.add_child(ok)
	return vbox


func _build_item_row(index: int, entry: Dictionary, f: float) -> Control:
	var row := PanelContainer.new()
	row.name = "Item%d" % index
	row.theme_type_variation = "AcWell"
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", int(12.0 * f))
	var icon := TextureRect.new()
	icon.texture = load(ICON_DIR + "sparkle.svg")
	icon.custom_minimum_size = Vector2.ONE * roundf(28.0 * f)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.self_modulate = AcTokens.YELLOW_DARK
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	box.add_child(icon)
	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var title := Label.new()
	title.name = "ItemTitle"
	title.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BODY * f))
	title.text = str(entry.get("titel", ""))
	text_box.add_child(title)
	var body := Label.new()
	body.name = "ItemText"
	body.theme_type_variation = "CaptionLabel"
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_CAPTION * f))
	body.text = str(entry.get("text", ""))
	text_box.add_child(body)
	box.add_child(text_box)
	row.add_child(box)
	return row


func _on_ok_pressed() -> void:
	news_seen.emit()
	close()
