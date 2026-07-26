class_name SettingsScreen
extends Control
## Settings-Screen (H §5.2 + RW-7 Vollausbau nach Doc RANCH-DLC-IDEAS-4 §4).
## Abschnitte: Allgemein / Grafik / Anzeige / Steuerung / Barrierefreiheit /
## Audio / Benachrichtigungen / Spiel / Spielstand / Updates / Ueber.
##
## Wirkprinzip: JEDE Einstellung schreibt sofort in /root/AppSettings
## (persistiert atomar); die ANWENDUNG passiert zentral im QualityService
## (graphics./display./controls./accessibility./game.autosave), im
## AudioDirector (audio.*) und im NotificationService (notifications.*) —
## alle lauschen auf AppSettings.setting_changed. Der Screen selbst haelt
## nur den lokalen Spiegel `_values` fuer die Legacy-Keys (language,
## orientation, reduced_motion, door_*, volume_*) und emittiert wie bisher
## `setting_changed(key, value)`.
##
## Versteckter Entwicklermodus (Doc §5.1): die Sprachwahl ist eine
## Segmented-Row; 3 Tipps innerhalb 1,5 s auf das BEREITS aktive "Deutsch"
## (DevTrigger, mit Cooldown) oeffnen den Warn-Dialog mit
## Halte-Bestaetigung (DevUnlockDialog) — erst der aktiviert /root/Dev.
##
## FIX1: der ganze Screen skaliert mit `UiScale.for_viewport()`; Schriften
## nutzen zusaetzlich `UiScale.font_scale()` (Textgroesse-Regler wirkt also
## messbar auf diesen Screen selbst). Bei Resize/Rotation wird neu gebaut.

signal setting_changed(key: StringName, value: Variant)
signal update_check_requested
signal open_news_requested
signal back_pressed

const ICON_DIR := "res://assets/ui/icons/"
const NEWS_PANEL_SCENE := "res://scripts/ui/news_50_panel.tscn"
const VERSION_FALLBACK := "5.0.0-dev"
## Slider-Key → AppSettings-Key (W1a-FROZEN `audio.*`; RW-7 ergaenzt voice).
const AUDIO_KEYS := {
	"volume_master": "master",
	"volume_music": "music",
	"volume_sfx": "sfx",
	"volume_voice": "voice",
}
## Legacy-Spiegel-Key → AppSettings-Punktpfad (Root-Keys aus W1a).
const APP_KEYS := {
	"language": "language",
	"orientation": "orientation_mode",
	"reduced_motion": "reduced_motion",
	"door_animation": "doors_animated",
	"door_confirmation": "door_confirmation",
}
## Einzelregler des Grafik-Buendels (Doc §4.3 — Aenderung markiert das
## Profil als "benutzerdefiniert").
const GRAPHICS_KEYS: Array[String] = [
	"scale_3d", "fps", "msaa", "shadows", "draw_distance", "particles", "post_fx"
]

var _values: Dictionary = {
	"language": "de",
	"orientation": "auto",
	"reduced_motion": false,
	"door_animation": true,
	"door_confirmation": true,
	"volume_master": 0.8,
	"volume_music": 0.8,
	"volume_sfx": 0.8,
	"volume_voice": 0.8,
}
var _news_panel: PanelSheet
## Aktueller UiScale-Faktor (FIX1) — setzt _rebuild, nutzen die Row-Builder.
var _f := 1.0
## Font-Faktor (= _f x Textgroesse-Regler).
var _tf := 1.0
var _dev_trigger := DevTrigger.new()
var _dev_dialog: Control
var _preset_pick: OptionButton

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
## wirklich aendert — _rebuild wirft die Rows weg und baut sie frisch).
func _on_viewport_resized() -> void:
	if absf(UiScale.for_viewport(get_viewport()) - _f) > 0.01:
		_rebuild()


## Aktueller Wert (fuers HUD/Tests; Quelle: Autoload-Spiegel oder lokal).
func get_value(key: String) -> Variant:
	return _values.get(key)


func _load_from_settings_autoload() -> void:
	var app := _app()
	if app != null and app.has_method("audio_level"):
		for key: String in AUDIO_KEYS:
			_values[key] = app.audio_level(str(AUDIO_KEYS[key]))
	if app != null and app.has_method("get_setting"):
		for key: String in APP_KEYS:
			var value: Variant = app.get_setting(str(APP_KEYS[key]))
			if value != null:
				_values[key] = value
	_values["language"] = I18nService.get_locale()
	var svc := get_node_or_null("/root/Settings")
	if svc == null or not svc.has_method("get_value"):
		return
	for key: String in _values:
		var value: Variant = svc.get_value(key)
		if value != null:
			_values[key] = value


func _set_value(key: String, value: Variant) -> void:
	_values[key] = value
	var app := _app()
	if app != null and app.has_method("set_setting"):
		if AUDIO_KEYS.has(key):
			app.set_setting("audio." + str(AUDIO_KEYS[key]), value)
		elif APP_KEYS.has(key):
			app.set_setting(str(APP_KEYS[key]), value)
	var svc := get_node_or_null("/root/Settings")
	if svc != null and svc.has_method("set_value"):
		svc.set_value(key, value)
	if key == "reduced_motion":
		var theme_svc := get_node_or_null("/root/UiTheme")
		if theme_svc != null and "reduced_motion" in theme_svc:
			theme_svc.reduced_motion = value
	if key == "orientation":
		_reapply_orientation()
	setting_changed.emit(StringName(key), value)


## Versionierte AppSettings-Keys (graphics./display./...) direkt schreiben —
## die Anwendung uebernehmen die lauschenden Dienste (QualityService & Co.).
func _set_app(path: String, value: Variant) -> void:
	var app := _app()
	if app != null and app.has_method("set_setting"):
		app.set_setting(path, value)
	setting_changed.emit(StringName(path), value)


## Grafik-Einzelregler: laeuft ein Profil (auto/niedrig/...), wird ERST das
## aktuell wirksame Buendel als Basis uebernommen und das Profil auf
## "benutzerdefiniert" gestellt (Doc §4.3) — dann der eine Wert gesetzt.
func _set_graphics(key: String, value: Variant) -> void:
	var app := _app()
	if app == null or not app.has_method("value_of"):
		return
	if String(app.value_of("graphics.preset")) != "benutzerdefiniert":
		var bundle := _effective_graphics()
		for k: String in bundle:
			if k != key and GRAPHICS_KEYS.has(k):
				app.set_setting("graphics." + k, bundle[k])
		app.set_setting("graphics.preset", "benutzerdefiniert")
		_select_pick(_preset_pick, "benutzerdefiniert", _preset_options())
	_set_app("graphics." + key, value)


## Aktuell WIRKSAMES Grafik-Buendel: bei laufendem Profil aus dem
## QualityService (nach Auto-Aufloesung), sonst die gespeicherten Werte.
func _effective_graphics() -> Dictionary:
	var quality := get_node_or_null("/root/Quality")
	if quality != null and quality.has_method("applied_bundle"):
		var applied: Dictionary = quality.applied_bundle()
		if not applied.is_empty():
			return applied
	var app := _app()
	var out := {}
	if app != null and app.has_method("value_of"):
		for k in GRAPHICS_KEYS:
			out[k] = app.value_of("graphics." + k)
	return out


func _rebuild() -> void:
	_f = UiScale.for_viewport(get_viewport())
	_tf = UiScale.font_scale(get_viewport())
	_apply_scale()
	_title.text = I18nService.t("settings.titel")
	for child in _sections.get_children():
		child.queue_free()
	_build_general_section()
	_build_graphics_section()
	_build_display_section()
	_build_controls_section()
	_build_accessibility_section()
	_build_audio_section()
	_build_notify_section()
	_build_game_section()
	_build_transfer_section()
	_build_updates_section()
	_build_about_section()


## FIX1: Chrome (Raender/Header/Sektions-Breite) an Faktor + Safe-Area ziehen.
func _apply_scale() -> void:
	var canvas := Vector2(get_viewport().get_visible_rect().size)
	var insets := UiScale.safe_insets_canvas(get_viewport())
	_margin.add_theme_constant_override("margin_left", int(24.0 + float(insets["left"])))
	_margin.add_theme_constant_override("margin_top", int(16.0 + float(insets["top"])))
	_margin.add_theme_constant_override("margin_right", int(24.0 + float(insets["right"])))
	_margin.add_theme_constant_override("margin_bottom", int(16.0 + float(insets["bottom"])))
	var floor_px := HudLayoutLogic.touch_floor_canvas(canvas)
	_back.custom_minimum_size = Vector2.ONE * maxf(56.0 * _f, floor_px)
	_title.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_HEADLINE * _tf))
	var avail := canvas.x - float(insets["left"]) - float(insets["right"]) - 48.0
	_sections.custom_minimum_size = Vector2(minf(660.0 * _f, avail), 0.0)


## ------------------------------------------------------------- Abschnitte


func _build_general_section() -> void:
	var rows := _add_section("Allgemein", I18nService.t("settings.allgemein"))
	_build_language_row(rows)
	_add_pick_row(
		rows,
		"orientation",
		I18nService.t("settings.orientierung"),
		[
			["auto", I18nService.t("settings.orientierung_auto")],
			["portrait", I18nService.t("settings.orientierung_hochkant")],
			["landscape", I18nService.t("settings.orientierung_quer")],
		],
		str(_values.get("orientation")),
		func(id: String) -> void: _set_value("orientation", id)
	)


## Sprachwahl als Segmented-Row: Tipp auf die INAKTIVE Sprache wechselt;
## Tipp auf das aktive "Deutsch" zaehlt fuer den Dev-Trigger (Doc §5.1).
func _build_language_row(rows: VBoxContainer) -> void:
	var row := _make_row(rows, "language", I18nService.t("settings.sprache"))
	var seg := HBoxContainer.new()
	seg.name = "Value"
	seg.add_theme_constant_override("separation", int(8.0 * _f))
	var active := str(_values.get("language"))
	var options := [
		["de", I18nService.t("settings.sprache_de")],
		["en", I18nService.t("settings.sprache_en")],
	]
	for opt: Array in options:
		var id := str(opt[0])
		var btn := SquishButton.new()
		btn.name = "Lang" + id.to_upper()
		btn.theme_type_variation = "BtnYellow" if id == active else "BtnTeal"
		btn.text = str(opt[1])
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(120.0 * _f, AcTokens.TOUCH_FLOOR * _f)
		btn.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BODY * _tf))
		btn.pressed.connect(_on_language_pressed.bind(id))
		seg.add_child(btn)
	row.add_child(seg)


func _build_graphics_section() -> void:
	var rows := _add_section("Grafik", I18nService.t("settings.grafik"))
	_preset_pick = _add_pick_row(
		rows,
		"graphics_preset",
		I18nService.t("settings.qualitaet"),
		_preset_options(),
		str(_app_value("graphics.preset", "auto")),
		func(id: String) -> void: _on_preset_selected(id)
	)
	_add_help(rows, "PresetHelp", I18nService.t("settings.qualitaet_hilfe"))
	var device := DeviceProfile.classify(DeviceProfile.snapshot())
	_add_help(
		rows,
		"DeviceInfo",
		I18nService.t(
			"settings.geraet_info",
			{"klasse": str(device.get("klasse", "?")), "fps": int(device.get("fps", 60))}
		)
	)
	var eff := _effective_graphics()
	_add_range_row(
		rows,
		"graphics_scale_3d",
		I18nService.t("settings.aufloesung"),
		0.5,
		1.0,
		0.05,
		float(eff.get("scale_3d", 1.0)),
		func(v: float) -> void: _set_graphics("scale_3d", v)
	)
	_add_help(rows, "ScaleHelp", I18nService.t("settings.aufloesung_hilfe"))
	_add_pick_row(
		rows,
		"graphics_fps",
		I18nService.t("settings.bildrate"),
		[
			["30", I18nService.t("settings.bildrate_fps", {"fps": 30})],
			["60", I18nService.t("settings.bildrate_fps", {"fps": 60})],
			["120", I18nService.t("settings.bildrate_fps", {"fps": 120})],
		],
		str(int(eff.get("fps", 60))),
		func(id: String) -> void: _set_graphics("fps", int(id))
	)
	_add_help(rows, "FpsHelp", I18nService.t("settings.bildrate_hilfe"))
	_add_pick_row(
		rows,
		"graphics_msaa",
		I18nService.t("settings.msaa"),
		[
			["aus", I18nService.t("settings.msaa_aus")],
			["2x", I18nService.t("settings.msaa_2x")],
			["4x", I18nService.t("settings.msaa_4x")],
		],
		str(eff.get("msaa", "2x")),
		func(id: String) -> void: _set_graphics("msaa", id)
	)
	_add_pick_row(
		rows,
		"graphics_shadows",
		I18nService.t("settings.schatten"),
		[
			["aus", I18nService.t("settings.schatten_aus")],
			["niedrig", I18nService.t("settings.schatten_niedrig")],
			["hoch", I18nService.t("settings.schatten_hoch")],
		],
		str(eff.get("shadows", "hoch")),
		func(id: String) -> void: _set_graphics("shadows", id)
	)
	_add_range_row(
		rows,
		"graphics_draw_distance",
		I18nService.t("settings.sichtweite"),
		0.7,
		1.0,
		0.05,
		float(eff.get("draw_distance", 1.0)),
		func(v: float) -> void: _set_graphics("draw_distance", v)
	)
	_add_help(rows, "DistanceHelp", I18nService.t("settings.sichtweite_hilfe"))
	_add_range_row(
		rows,
		"graphics_particles",
		I18nService.t("settings.partikel"),
		0.0,
		1.0,
		0.05,
		float(eff.get("particles", 1.0)),
		func(v: float) -> void: _set_graphics("particles", v)
	)
	_add_pick_row(
		rows,
		"graphics_post_fx",
		I18nService.t("settings.post_fx"),
		[
			["aus", I18nService.t("settings.post_fx_aus")],
			["dezent", I18nService.t("settings.post_fx_dezent")],
			["hoch", I18nService.t("settings.post_fx_hoch")],
		],
		str(eff.get("post_fx", "dezent")),
		func(id: String) -> void: _set_graphics("post_fx", id)
	)


func _build_display_section() -> void:
	var rows := _add_section("Anzeige", I18nService.t("settings.anzeige"))
	_add_range_row(
		rows,
		"display_ui_scale",
		I18nService.t("settings.ui_skalierung"),
		0.85,
		1.3,
		0.05,
		float(_app_value("display.ui_scale", 1.0)),
		func(v: float) -> void: _set_app("display.ui_scale", v),
		true
	)
	_add_help(rows, "UiScaleHelp", I18nService.t("settings.ui_skalierung_hilfe"))
	_add_range_row(
		rows,
		"display_text_scale",
		I18nService.t("settings.textgroesse"),
		1.0,
		1.5,
		0.05,
		float(_app_value("display.text_scale", 1.0)),
		func(v: float) -> void: _set_app("display.text_scale", v),
		true
	)
	_add_help(rows, "TextScaleHelp", I18nService.t("settings.textgroesse_hilfe"))
	_add_range_row(
		rows,
		"display_safe_area",
		I18nService.t("settings.safe_area"),
		0.0,
		24.0,
		1.0,
		float(_app_value("display.safe_area_extra", 0.0)),
		func(v: float) -> void: _set_app("display.safe_area_extra", v),
		true
	)
	_add_help(rows, "SafeAreaHelp", I18nService.t("settings.safe_area_hilfe"))


func _build_controls_section() -> void:
	var rows := _add_section("Steuerung", I18nService.t("settings.steuerung"))
	_add_pick_row(
		rows,
		"controls_handedness",
		I18nService.t("settings.haendigkeit"),
		[
			["rechts", I18nService.t("settings.haendigkeit_rechts")],
			["links", I18nService.t("settings.haendigkeit_links")],
		],
		str(_app_value("controls.handedness", "rechts")),
		func(id: String) -> void: _set_app("controls.handedness", id)
	)
	_add_help(rows, "HandHelp", I18nService.t("settings.haendigkeit_hilfe"))
	_add_pick_row(
		rows,
		"controls_scheme",
		I18nService.t("settings.schema"),
		[
			["stick", I18nService.t("settings.schema_stick")],
			["zuegel", I18nService.t("settings.schema_zuegel")],
		],
		str(_app_value("controls.scheme", "stick")),
		func(id: String) -> void: _set_app("controls.scheme", id)
	)
	_add_help(rows, "SchemeHelp", I18nService.t("settings.schema_hilfe"))
	_add_switch_row(
		rows,
		"controls_steering_assist",
		I18nService.t("settings.lenkassistent"),
		_app_on("controls.steering_assist", true),
		func(on: bool) -> void: _set_app("controls.steering_assist", on)
	)
	_add_help(rows, "AssistHelp", I18nService.t("settings.lenkassistent_hilfe"))
	_add_pick_row(
		rows,
		"controls_haptics",
		I18nService.t("settings.haptik"),
		[
			["aus", I18nService.t("settings.haptik_aus")],
			["dezent", I18nService.t("settings.haptik_dezent")],
			["normal", I18nService.t("settings.haptik_normal")],
			["stark", I18nService.t("settings.haptik_stark")],
		],
		str(_app_value("controls.haptics", "normal")),
		func(id: String) -> void: _set_app("controls.haptics", id)
	)
	_add_help(rows, "HapticsHelp", I18nService.t("settings.haptik_hilfe"))


func _build_accessibility_section() -> void:
	var rows := _add_section("Barrierefreiheit", I18nService.t("settings.barrierefreiheit"))
	_add_switch_row(
		rows,
		"reduced_motion",
		I18nService.t("settings.reduced_motion"),
		bool(_values.get("reduced_motion", false)),
		func(on: bool) -> void: _set_value("reduced_motion", on)
	)
	_add_help(rows, "MotionHelp", I18nService.t("settings.reduced_motion_hilfe"))
	_add_pick_row(
		rows,
		"accessibility_color_vision",
		I18nService.t("settings.farbmodus"),
		[
			["aus", I18nService.t("settings.farbmodus_aus")],
			["protan", I18nService.t("settings.farbmodus_protan")],
			["deutan", I18nService.t("settings.farbmodus_deutan")],
			["tritan", I18nService.t("settings.farbmodus_tritan")],
		],
		str(_app_value("accessibility.color_vision", "aus")),
		func(id: String) -> void: _set_app("accessibility.color_vision", id)
	)
	_add_help(rows, "ColorHelp", I18nService.t("settings.farbmodus_hilfe"))
	_add_switch_row(
		rows,
		"accessibility_high_contrast",
		I18nService.t("settings.hoher_kontrast"),
		_app_on("accessibility.high_contrast", false),
		func(on: bool) -> void: _set_app("accessibility.high_contrast", on)
	)
	_add_pick_row(
		rows,
		"accessibility_hint_duration",
		I18nService.t("settings.hinweisdauer"),
		[
			["normal", I18nService.t("settings.hinweisdauer_normal")],
			["lang", I18nService.t("settings.hinweisdauer_lang")],
		],
		str(_app_value("accessibility.hint_duration", "normal")),
		func(id: String) -> void: _set_app("accessibility.hint_duration", id)
	)


func _build_audio_section() -> void:
	var rows := _add_section("Audio", I18nService.t("settings.audio"))
	_add_slider_row(rows, "volume_master", I18nService.t("settings.laut_master"))
	_add_slider_row(rows, "volume_music", I18nService.t("settings.laut_musik"))
	_add_slider_row(rows, "volume_sfx", I18nService.t("settings.laut_effekte"))
	_add_slider_row(rows, "volume_voice", I18nService.t("settings.laut_stimmen"))


func _build_notify_section() -> void:
	var rows := _add_section("Benachrichtigungen", I18nService.t("settings.benachrichtigungen"))
	_add_switch_row(
		rows,
		"notify_enabled",
		I18nService.t("settings.notify_master"),
		_app_on("notifications.enabled", true),
		func(on: bool) -> void: _set_app("notifications.enabled", on)
	)
	var categories := [
		["pflege", "settings.notify_pflege"],
		["warte", "settings.notify_warte"],
		["fohlen", "settings.notify_fohlen"],
		["turnier", "settings.notify_turnier"],
		["freund", "settings.notify_freund"],
	]
	for cat: Array in categories:
		var id := str(cat[0])
		_add_switch_row(
			rows,
			"notify_" + id,
			I18nService.t(str(cat[1])),
			_app_on("notifications." + id, true),
			func(on: bool) -> void: _set_app("notifications." + id, on)
		)
	_add_switch_row(
		rows,
		"notify_quiet",
		I18nService.t("settings.notify_ruhe"),
		_app_on("notifications.quiet_hours", true),
		func(on: bool) -> void: _set_app("notifications.quiet_hours", on)
	)
	_add_help(rows, "QuietHelp", I18nService.t("settings.notify_ruhe_hilfe"))
	_add_pick_row(
		rows,
		"notify_quiet_from",
		I18nService.t("settings.notify_von"),
		_hour_options(),
		str(int(_app_value("notifications.quiet_from", 21))),
		func(id: String) -> void: _set_app("notifications.quiet_from", int(id))
	)
	_add_pick_row(
		rows,
		"notify_quiet_to",
		I18nService.t("settings.notify_bis"),
		_hour_options(),
		str(int(_app_value("notifications.quiet_to", 8))),
		func(id: String) -> void: _set_app("notifications.quiet_to", int(id))
	)
	_add_help(rows, "HonestyNote", I18nService.t("settings.notify_hinweis"))


func _build_game_section() -> void:
	var rows := _add_section("Spiel", I18nService.t("settings.spiel"))
	_add_switch_row(
		rows,
		"door_animation",
		I18nService.t("settings.tuer_animation"),
		bool(_values.get("door_animation", true)),
		func(on: bool) -> void: _set_value("door_animation", on)
	)
	# W6/FIX-3: Nachfrage vor dem Raumwechsel — abschaltbar (Standard: an).
	_add_switch_row(
		rows,
		"door_confirmation",
		I18nService.t("settings.tuer_bestaetigung"),
		bool(_values.get("door_confirmation", true)),
		func(on: bool) -> void: _set_value("door_confirmation", on)
	)
	_add_switch_row(
		rows,
		"game_autosave",
		I18nService.t("settings.autosave"),
		_app_on("game.autosave", true),
		func(on: bool) -> void: _set_app("game.autosave", on)
	)
	_add_help(rows, "AutosaveHelp", I18nService.t("settings.autosave_hilfe"))
	var reset_btn := _section_button(rows, "TutorialResetButton", "settings.tutorial_reset")
	reset_btn.pressed.connect(_on_tutorial_reset)


func _build_updates_section() -> void:
	var rows := _add_section("Updates", I18nService.t("settings.updates"))
	var btn := _section_button(rows, "UpdateCheckButton", "settings.update_suchen")
	btn.pressed.connect(_on_update_check)


## W6/FIX-6: Weg zum Uebernahme-Screen fuer den Spielstand der alten App —
## der User fand ihn sonst nicht ("Wo genau uebertraegt man seinen Save?").
func _build_transfer_section() -> void:
	var rows := _add_section("Spielstand", I18nService.t("settings.spielstand"))
	var btn := _section_button(rows, "TransferButton", "settings.spielstand_uebertragen")
	btn.pressed.connect(_on_transfer_pressed)


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
	version_label.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BODY * _tf))
	rows.add_child(version_label)
	var news_btn := SquishButton.new()
	news_btn.name = "NewsButton"
	news_btn.theme_type_variation = "BtnYellow"
	news_btn.text = I18nService.t("settings.news_button")
	news_btn.custom_minimum_size = Vector2(0, 52.0 * _f)
	news_btn.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BUTTON * _tf))
	news_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	news_btn.focus_mode = Control.FOCUS_NONE
	news_btn.pressed.connect(_on_open_news)
	rows.add_child(news_btn)
	# CC-BY-Pflicht-Credits (RANCH-ASSETS.md §6) — MUESSEN hier erscheinen.
	var credits_title := Label.new()
	credits_title.name = "CreditsTitle"
	credits_title.theme_type_variation = "TitleLabel"
	credits_title.text = I18nService.t("settings.credits_titel")
	credits_title.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BODY * _tf))
	rows.add_child(credits_title)
	_add_help(rows, "CreditsHint", I18nService.t("settings.credits_hinweis"))
	var lines := I18nService.items("settings.credits_liste")
	for i in lines.size():
		var line := Label.new()
		line.name = "CreditLine%d" % i
		line.theme_type_variation = "SoftLabel"
		line.text = str(lines[i])
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_CAPTION * _tf))
		rows.add_child(line)


## ---------------------------------------------------- Dev-Trigger (Doc §5.1)


func _on_language_pressed(id: String) -> void:
	if id == str(_values.get("language")):
		_register_dev_tap(id)
		return
	_set_value("language", id)
	I18nService.set_locale(id)
	_rebuild()


func _register_dev_tap(id: String) -> void:
	if id != "de":
		return
	var result := _dev_trigger.register_tap(Time.get_ticks_msec(), str(_values.get("language")))
	if int(result.get("blocked_ms", 0)) > 0:
		_toast.show_toast(I18nService.t("dev.cooldown"), true)
		return
	if bool(result.get("triggered", false)):
		Haptics.heavy(self)
		_open_dev_dialog()
	elif int(result.get("count", 0)) > 0:
		Haptics.tap(self)


func _open_dev_dialog() -> void:
	if _dev_dialog != null and is_instance_valid(_dev_dialog):
		return
	_dev_dialog = DevUnlockDialog.new()
	_dev_dialog.name = "DevUnlockDialog"
	_dev_dialog.confirmed.connect(_on_dev_confirmed)
	add_child(_dev_dialog)


func _on_dev_confirmed() -> void:
	var dev := get_node_or_null("/root/Dev")
	if dev != null and dev.has_method("enable"):
		dev.enable()
	_toast.show_toast(I18nService.t("dev.aktiviert"))


## ------------------------------------------------------------------ Helfer


func _on_preset_selected(id: String) -> void:
	_set_app("graphics.preset", id)
	# Profilwechsel aendert die wirksamen Einzelwerte — Rows frisch bauen.
	_rebuild()


func _on_tutorial_reset() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("update"):
		gs.update(
			func(s: Dictionary) -> void:
				if s.get("onboarding") is Dictionary:
					s["onboarding"]["whatsNew5Seen"] = false
		)
		if gs.has_method("notify_slice_changed"):
			gs.notify_slice_changed("onboarding")
	_toast.show_toast(I18nService.t("settings.tutorial_reset_ok"))


func _reapply_orientation() -> void:
	var svc := get_node_or_null("/root/OrientationService")
	if svc != null and svc.has_method("lock") and "current_lock" in svc:
		svc.lock(svc.current_lock)


func _preset_options() -> Array:
	return [
		["auto", I18nService.t("settings.qualitaet_auto")],
		["niedrig", I18nService.t("settings.qualitaet_niedrig")],
		["mittel", I18nService.t("settings.qualitaet_mittel")],
		["hoch", I18nService.t("settings.qualitaet_hoch")],
		["benutzerdefiniert", I18nService.t("settings.qualitaet_benutzerdefiniert")],
	]


func _hour_options() -> Array:
	var out := []
	for h in 24:
		out.append([str(h), I18nService.t("settings.notify_uhr", {"stunde": h})])
	return out


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
	picker.custom_minimum_size = Vector2(210.0 * _f, AcTokens.TOUCH_FLOOR * _f)
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
	toggle.custom_minimum_size = Vector2(0, AcTokens.TOUCH_FLOOR * _f)
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
	slider.custom_minimum_size = Vector2(240.0 * _f, AcTokens.TOUCH_FLOOR * _f)
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.value_changed.connect(func(value: float) -> void: handler.call(value))
	if rebuild_on_release:
		slider.drag_ended.connect(
			func(changed: bool) -> void:
				if changed:
					_rebuild()
		)
	row.add_child(slider)
	return slider


## Audio-Slider (Legacy-Kontrakt: schreibt _values + audio.<bus>).
func _add_slider_row(rows: VBoxContainer, key: String, label_text: String) -> void:
	_add_range_row(
		rows,
		key,
		label_text,
		0.0,
		1.0,
		0.05,
		float(_values.get(key, 0.8)),
		func(value: float) -> void: _set_value(key, value)
	)


func _make_row(rows: VBoxContainer, key: String, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.name = "Row" + key.to_pascal_case()
	row.add_theme_constant_override("separation", int(12.0 * _f))
	var label := Label.new()
	label.name = "RowLabel"
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
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


func _app() -> Node:
	return get_node_or_null("/root/AppSettings")


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
