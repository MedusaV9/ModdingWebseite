class_name SettingsScreen
extends Control
## Settings-Screen (H §5.2-Auszug für W1): Allgemein / Audio / Updates / Über.
## Werte werden lose gespiegelt: existiert `/root/Settings` (W1a) mit
## `get_value`/`set_value`, wird dort gelesen/geschrieben — sonst hält der
## Screen lokale Werte. IMMER wird `setting_changed(key, value)` emittiert.
##
## „Suche nach Updates“ ruft ein UpdateService-INTERFACE auf (W2 liefert):
## existiert `/root/UpdateManager.check_for_updates()`, wird es gerufen —
## sonst kommt der „bald“-Toast. Signal `update_check_requested` feuert immer.
##
## FIX1 (P0 „UI meist falsch skaliert“): der ganze Screen skaliert mit der
## zentralen Regel `UiScale.for_viewport()` — Schriften, Zeilenhöhen und
## die Sektions-Breite wachsen mit, Ränder respektieren die Safe-Area.
## Bei Resize/Rotation wird neu aufgebaut (Werte bleiben in `_values`).

signal setting_changed(key: StringName, value: Variant)
signal update_check_requested
signal open_news_requested
signal back_pressed

const ICON_DIR := "res://assets/ui/icons/"
const NEWS_PANEL_SCENE := "res://scripts/ui/news_50_panel.tscn"
const VERSION_FALLBACK := "5.0.0-dev"
## Slider-Key → AppSettings-Key (W1a-FROZEN `audio.*`; W4P1-Hinweis:
## AudioDirector liest audio_level() — ohne Brücke wären die Slider stumm).
const AUDIO_KEYS := {
	"volume_master": "master",
	"volume_music": "music",
	"volume_sfx": "sfx",
}

var _values: Dictionary = {
	"language": "de",
	"orientation": "auto",
	"reduced_motion": false,
	"door_animation": true,
	"volume_master": 0.8,
	"volume_music": 0.8,
	"volume_sfx": 0.8,
}
var _news_panel: PanelSheet
## Aktueller UiScale-Faktor (FIX1) — setzt _rebuild, nutzen die Row-Builder.
var _f := 1.0

@onready var _sections: VBoxContainer = %SectionsVBox
@onready var _title: Label = %HeaderTitle
@onready var _toast: ToastLayer = %Toast
@onready var _back: Button = %BackButton
@onready var _margin: MarginContainer = $Margin


func _ready() -> void:
	_back.icon = load(ICON_DIR + "arrow_left.svg")
	_back.pressed.connect(func() -> void: back_pressed.emit())
	_load_from_settings_autoload()
	get_viewport().size_changed.connect(_on_viewport_resized)
	_rebuild()


## FIX1: bei Resize/Rotation neu skalieren (nur wenn sich der Faktor
## wirklich ändert — _rebuild wirft die Rows weg und baut sie frisch).
func _on_viewport_resized() -> void:
	if absf(UiScale.for_viewport(get_viewport()) - _f) > 0.01:
		_rebuild()


## Aktueller Wert (fürs HUD/Tests; Quelle: Autoload-Spiegel oder lokal).
func get_value(key: String) -> Variant:
	return _values.get(key)


func _load_from_settings_autoload() -> void:
	var app := get_node_or_null("/root/AppSettings")
	if app != null and app.has_method("audio_level"):
		for key: String in AUDIO_KEYS:
			_values[key] = app.audio_level(str(AUDIO_KEYS[key]))
	var svc := get_node_or_null("/root/Settings")
	if svc == null or not svc.has_method("get_value"):
		return
	for key: String in _values:
		var value: Variant = svc.get_value(key)
		if value != null:
			_values[key] = value


func _set_value(key: String, value: Variant) -> void:
	_values[key] = value
	if AUDIO_KEYS.has(key):
		var app := get_node_or_null("/root/AppSettings")
		if app != null and app.has_method("set_setting"):
			app.set_setting("audio." + str(AUDIO_KEYS[key]), value)
	var svc := get_node_or_null("/root/Settings")
	if svc != null and svc.has_method("set_value"):
		svc.set_value(key, value)
	if key == "reduced_motion":
		var theme_svc := get_node_or_null("/root/UiTheme")
		if theme_svc != null and "reduced_motion" in theme_svc:
			theme_svc.reduced_motion = value
	setting_changed.emit(StringName(key), value)


func _rebuild() -> void:
	_f = UiScale.for_viewport(get_viewport())
	_apply_scale()
	_title.text = I18nService.t("settings.titel")
	for child in _sections.get_children():
		child.queue_free()
	_build_general_section()
	_build_audio_section()
	_build_updates_section()
	_build_transfer_section()
	_build_about_section()


## FIX1: Chrome (Ränder/Header/Sektions-Breite) an Faktor + Safe-Area ziehen.
func _apply_scale() -> void:
	var canvas := Vector2(get_viewport().get_visible_rect().size)
	var insets := UiScale.safe_insets_canvas(get_viewport())
	_margin.add_theme_constant_override("margin_left", int(24.0 + float(insets["left"])))
	_margin.add_theme_constant_override("margin_top", int(16.0 + float(insets["top"])))
	_margin.add_theme_constant_override("margin_right", int(24.0 + float(insets["right"])))
	_margin.add_theme_constant_override("margin_bottom", int(16.0 + float(insets["bottom"])))
	var floor_px := HudLayoutLogic.touch_floor_canvas(canvas)
	_back.custom_minimum_size = Vector2.ONE * maxf(56.0 * _f, floor_px)
	_title.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_HEADLINE * _f))
	var avail := canvas.x - float(insets["left"]) - float(insets["right"]) - 48.0
	_sections.custom_minimum_size = Vector2(minf(660.0 * _f, avail), 0.0)


func _build_general_section() -> void:
	var rows := _add_section("Allgemein", I18nService.t("settings.allgemein"))
	_add_option_row(
		rows,
		"language",
		I18nService.t("settings.sprache"),
		[
			["de", I18nService.t("settings.sprache_de")],
			["en", I18nService.t("settings.sprache_en")],
		]
	)
	_add_option_row(
		rows,
		"orientation",
		I18nService.t("settings.orientierung"),
		[
			["auto", I18nService.t("settings.orientierung_auto")],
			["portrait", I18nService.t("settings.orientierung_hochkant")],
			["landscape", I18nService.t("settings.orientierung_quer")],
		]
	)
	_add_toggle_row(rows, "reduced_motion", I18nService.t("settings.reduced_motion"))
	_add_toggle_row(rows, "door_animation", I18nService.t("settings.tuer_animation"))
	# W6/FIX-3: Nachfrage vor dem Raumwechsel — abschaltbar (Standard: an).
	_add_toggle_row(rows, "door_confirmation", I18nService.t("settings.tuer_bestaetigung"))


func _build_audio_section() -> void:
	var rows := _add_section("Audio", I18nService.t("settings.audio"))
	_add_slider_row(rows, "volume_master", I18nService.t("settings.laut_master"))
	_add_slider_row(rows, "volume_music", I18nService.t("settings.laut_musik"))
	_add_slider_row(rows, "volume_sfx", I18nService.t("settings.laut_effekte"))


func _build_updates_section() -> void:
	var rows := _add_section("Updates", I18nService.t("settings.updates"))
	var btn := SquishButton.new()
	btn.name = "UpdateCheckButton"
	btn.theme_type_variation = "BtnTeal"
	btn.text = I18nService.t("settings.update_suchen")
	btn.custom_minimum_size = Vector2(0, 52.0 * _f)
	btn.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BUTTON * _f))
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(_on_update_check)
	rows.add_child(btn)


## W6/FIX-6: Weg zum Uebernahme-Screen fuer den Spielstand der alten App —
## der User fand ihn sonst nicht („Wo genau uebertraegt man seinen Save?").
func _build_transfer_section() -> void:
	var rows := _add_section("Spielstand", I18nService.t("settings.spielstand"))
	var btn := SquishButton.new()
	btn.name = "TransferButton"
	btn.theme_type_variation = "BtnTeal"
	btn.text = I18nService.t("settings.spielstand_uebertragen")
	btn.custom_minimum_size = Vector2(0, 52.0 * _f)
	btn.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BUTTON * _f))
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(_on_transfer_pressed)
	rows.add_child(btn)


func _on_transfer_pressed() -> void:
	TransferScreen.register_routes()
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("goto"):
		router.goto(TransferScreen.ROUTE)


func _build_about_section() -> void:
	var rows := _add_section("Ueber", I18nService.t("settings.ueber"))
	var version := str(ProjectSettings.get_setting("application/config/version", VERSION_FALLBACK))
	if version.is_empty():
		version = VERSION_FALLBACK
	var version_label := Label.new()
	version_label.name = "VersionLabel"
	version_label.theme_type_variation = "SoftLabel"
	version_label.text = I18nService.t("settings.version", {"version": version})
	version_label.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BODY * _f))
	rows.add_child(version_label)
	var news_btn := SquishButton.new()
	news_btn.name = "NewsButton"
	news_btn.theme_type_variation = "BtnYellow"
	news_btn.text = I18nService.t("settings.news_button")
	news_btn.custom_minimum_size = Vector2(0, 52.0 * _f)
	news_btn.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BUTTON * _f))
	news_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	news_btn.focus_mode = Control.FOCUS_NONE
	news_btn.pressed.connect(_on_open_news)
	rows.add_child(news_btn)


func _add_section(node_name: String, title: String) -> VBoxContainer:
	var card := PanelContainer.new()
	card.name = "Section" + node_name
	card.theme_type_variation = "AcCard"
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override("separation", int(10.0 * _f))
	var title_label := Label.new()
	title_label.name = "SectionTitle"
	title_label.theme_type_variation = "TitleLabel"
	title_label.text = title
	title_label.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_TITLE * _f))
	rows.add_child(title_label)
	card.add_child(rows)
	_sections.add_child(card)
	return rows


func _add_option_row(rows: VBoxContainer, key: String, label_text: String, options: Array) -> void:
	var row := _make_row(rows, key, label_text)
	var picker := OptionButton.new()
	picker.name = "Value"
	picker.focus_mode = Control.FOCUS_NONE
	picker.custom_minimum_size = Vector2(210.0 * _f, AcTokens.TOUCH_FLOOR * _f)
	picker.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BODY * _f))
	for i in options.size():
		picker.add_item(options[i][1], i)
		if options[i][0] == str(_values.get(key)):
			picker.select(i)
	picker.item_selected.connect(
		func(index: int) -> void: _on_option_selected(key, options[index][0])
	)
	row.add_child(picker)


func _add_toggle_row(rows: VBoxContainer, key: String, label_text: String) -> void:
	var row := _make_row(rows, key, label_text)
	var toggle := CheckButton.new()
	toggle.name = "Value"
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.custom_minimum_size = Vector2(0, AcTokens.TOUCH_FLOOR * _f)
	toggle.button_pressed = bool(_values.get(key, false))
	toggle.toggled.connect(func(on: bool) -> void: _set_value(key, on))
	row.add_child(toggle)


func _add_slider_row(rows: VBoxContainer, key: String, label_text: String) -> void:
	var row := _make_row(rows, key, label_text)
	var slider := HSlider.new()
	slider.name = "Value"
	slider.focus_mode = Control.FOCUS_NONE
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = float(_values.get(key, 0.8))
	slider.custom_minimum_size = Vector2(240.0 * _f, AcTokens.TOUCH_FLOOR * _f)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(value: float) -> void: _set_value(key, value))
	row.add_child(slider)


func _make_row(rows: VBoxContainer, key: String, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Row" + key.to_pascal_case()
	row.add_theme_constant_override("separation", int(12.0 * _f))
	var label := Label.new()
	label.name = "RowLabel"
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BODY * _f))
	row.add_child(label)
	rows.add_child(row)
	return row


func _on_option_selected(key: String, option_id: String) -> void:
	_set_value(key, option_id)
	if key == "language":
		I18nService.set_locale(option_id)
		_rebuild()


func _on_update_check() -> void:
	update_check_requested.emit()
	var svc := get_node_or_null("/root/UpdateManager")
	if svc != null and svc.has_method("check_for_updates"):
		svc.check_for_updates()
		return
	_toast.show_toast(I18nService.t("settings.update_bald"))


func _on_open_news() -> void:
	open_news_requested.emit()
	if _news_panel == null:
		_news_panel = (load(NEWS_PANEL_SCENE) as PackedScene).instantiate()
		add_child(_news_panel)
	_news_panel.open()
