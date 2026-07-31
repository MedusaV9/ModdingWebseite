class_name SettingsScreen
extends SettingsRowsBasis
## Settings-Screen (H §5.2 + RW-7). Schreibt sofort nach /root/AppSettings;
## Quality/Audio/Notify lauschen. Versteckter Dev-Modus: 3× Tip auf aktives
## „Deutsch“. Skaliert mit UiScale; bei Resize/_rebuild neu.
## W14: generische Row-/Karten-Builder + AppSettings-Leser wohnen in der
## Basisklasse SettingsRowsBasis (scripts/ui/settings/settings_rows_basis.gd).

signal setting_changed(key: StringName, value: Variant)
signal update_check_requested
signal open_news_requested
signal back_pressed

const ICON_DIR := "res://assets/ui/icons/"
const NEWS_PANEL_SCENE := "res://scripts/ui/news_50_panel.tscn"
const VERSION_FALLBACK := "5.0.0-dev"
## W14/UISCREENS-A: die 6 klar benannten Gruppen (ACNH-Aufräumung). Jede
## Gruppe trägt einen Icon-Glyph-Header über den bestehenden Sektions-Karten;
## die Karten-Node-Namen (SectionGrafik, …) bleiben W1c-/RW-7-Kontrakt.
## `sections` listet die Karten-Namen in Anzeige-Reihenfolge (pure, testbar).
const GRUPPEN: Array = [
	{
		"id": "spiel",
		"icon": "gamepad",
		"titel_key": "settings.gruppe_spiel",
		"sections": ["Allgemein", "Steuerung", "Spiel", "DLC", "Benachrichtigungen"],
	},
	{
		"id": "anzeige",
		"icon": "eye",
		"titel_key": "settings.gruppe_anzeige",
		"sections": ["Grafik", "Anzeige", "Barrierefreiheit"],
	},
	{"id": "ton", "icon": "music", "titel_key": "settings.gruppe_ton", "sections": ["Audio"]},
	{
		"id": "mehrspieler",
		"icon": "phone",
		"titel_key": "settings.gruppe_mehrspieler",
		"sections": ["Mehrspieler"],
	},
	{
		"id": "spielstand",
		"icon": "suitcase",
		"titel_key": "settings.gruppe_spielstand",
		"sections": ["Spielstand"],
	},
	{
		"id": "info",
		"icon": "book",
		"titel_key": "settings.gruppe_info",
		"sections": ["Updates", "Ueber"],
	},
]
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
var _dev_trigger := DevTrigger.new()
var _dev_dialog: Control
var _preset_pick: OptionButton
## W14: Einblend-Stagger nur beim ERSTEN Aufbau (Resize-Rebuilds ploppen nicht).
var _revealed := false

@onready var _title: Label = %HeaderTitle
@onready var _toast: ToastLayer = %Toast
@onready var _back: Button = %BackButton
@onready var _margin: MarginContainer = $Margin


func _ready() -> void:
	_sections = %SectionsVBox
	# W14: konsistente Kopfzeile — Zurück ist überall die Ghost-Outline-Pill
	# mit ‹-Text (wie Arcade/Album/Profil), nicht der Icon-Quadrat-Knopf.
	_back.theme_type_variation = &"GhostButton"
	_back.pressed.connect(func() -> void: back_pressed.emit())
	_load_from_settings_autoload()
	get_viewport().size_changed.connect(_on_viewport_resized)
	var scroll := _scroll()
	if scroll != null:
		scroll.scroll_deadzone = 0
		scroll.gui_input.connect(_on_scroll_gui_input)
	_rebuild()


## FIX1: bei Resize/Rotation neu skalieren (nur wenn sich der Faktor
## wirklich aendert — _rebuild wirft die Rows weg und baut sie frisch).
func _on_viewport_resized() -> void:
	if _scroll_dragging:
		return
	if absf(UiScale.for_viewport(get_viewport()) - _f) > 0.01:
		_rebuild()


func _scroll() -> ScrollContainer:
	return get_node_or_null("%Scroll") as ScrollContainer


func _on_scroll_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_scroll_dragging = (event as InputEventScreenTouch).pressed
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_scroll_dragging = event.pressed


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
	var scroll := _scroll()
	var keep_y := scroll.scroll_vertical if scroll != null else 0
	_f = UiScale.for_viewport(get_viewport())
	_tf = UiScale.font_scale(get_viewport())
	_apply_scale()
	_title.text = I18nService.t("settings.titel")
	_back.text = I18nService.t("settings.zurueck")
	for child in _sections.get_children():
		child.queue_free()
	# W14: EINE Hierarchie pro Bild — 6 Icon-Gruppen, darunter die Themen-
	# Karten (Reihenfolge und Zuordnung kommen aus GRUPPEN).
	var builders := {
		"Allgemein": _build_general_section,
		"Steuerung": _build_controls_section,
		"Spiel": _build_game_section,
		"DLC": func() -> void: DlcSektion.baue(self, _sections, _f, _tf),
		"Benachrichtigungen": _build_notify_section,
		"Grafik": _build_graphics_section,
		"Anzeige": _build_display_section,
		"Barrierefreiheit": _build_accessibility_section,
		"Audio": _build_audio_section,
		"Mehrspieler": _build_multiplayer_section,
		"Spielstand": _build_transfer_section,
		"Updates": _build_updates_section,
		"Ueber": _build_about_section,
	}
	for gruppe: Dictionary in GRUPPEN:
		_sections.add_child(_build_gruppe_header(gruppe))
		for section: String in gruppe["sections"]:
			(builders[section] as Callable).call()
	_sections.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if scroll != null:
		scroll.set_deferred("scroll_vertical", keep_y)
	if not _revealed:
		_revealed = true
		UiMotion.stagger_in(_sections.get_children(), 0.03)


## FIX1: Chrome (Raender/Header/Sektions-Breite) an Faktor + Safe-Area ziehen.
func _apply_scale() -> void:
	var canvas := Vector2(get_viewport().get_visible_rect().size)
	var insets := UiScale.safe_insets_canvas(get_viewport())
	_margin.add_theme_constant_override("margin_left", int(24.0 + float(insets["left"])))
	_margin.add_theme_constant_override("margin_top", int(16.0 + float(insets["top"])))
	_margin.add_theme_constant_override("margin_right", int(24.0 + float(insets["right"])))
	_margin.add_theme_constant_override("margin_bottom", int(16.0 + float(insets["bottom"])))
	var floor_px := HudLayoutLogic.touch_floor_canvas(canvas)
	_back.custom_minimum_size = Vector2(0.0, maxf(48.0 * _f, floor_px))
	_back.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BODY * _tf))
	# W14: Kopfzeilen-Konsistenz — Titelgröße wie auf allen anderen Screens.
	_title.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_TITLE * _tf))
	var avail := canvas.x - float(insets["left"]) - float(insets["right"]) - 48.0
	_sections.custom_minimum_size = Vector2(minf(660.0 * _f, maxf(avail, 1.0)), 0.0)
	_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sections.size_flags_vertical = Control.SIZE_SHRINK_BEGIN


## ------------------------------------------------------------- Abschnitte


## W14: Gruppen-Header mit Icon-Glyph (ACNH-Muster) — sitzt ÜBER den Karten
## der Gruppe und trennt die 6 Themen mit Luft nach dem 8er-Raster.
func _build_gruppe_header(gruppe: Dictionary) -> Control:
	var wrap := MarginContainer.new()
	wrap.name = "Gruppe" + str(gruppe["id"]).to_pascal_case()
	wrap.add_theme_constant_override("margin_top", int(16.0 * _f))
	wrap.add_theme_constant_override("margin_left", int(8.0 * _f))
	var row := HBoxContainer.new()
	row.name = "GruppeHeader"
	row.add_theme_constant_override("separation", int(8.0 * _f))
	var glyph := TextureRect.new()
	glyph.name = "GruppeIcon"
	var icon_path := "%s%s.svg" % [ICON_DIR, str(gruppe["icon"])]
	if ResourceLoader.exists(icon_path):
		glyph.texture = load(icon_path)
	glyph.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	glyph.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	glyph.custom_minimum_size = Vector2.ONE * roundf(24.0 * _tf)
	glyph.self_modulate = AcTokens.INK
	glyph.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(glyph)
	var title := Label.new()
	title.name = "GruppeTitel"
	title.theme_type_variation = "TitleLabel"
	title.text = I18nService.t(str(gruppe["titel_key"]))
	title.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_TITLE * _tf))
	row.add_child(title)
	wrap.add_child(row)
	return wrap


## W14: Mehrspieler-Sektions-HÜLLE — die eigentlichen Zeilen baut W14/NETSET
## ADDITIV in dieses Rows-VBox (Node-Name „SectionMehrspieler“ ist Kontrakt).
## Der Gruppen-Header direkt darüber trägt den Titel, die Karte selbst nicht.
func _build_multiplayer_section() -> void:
	var rows := _add_section("Mehrspieler", "", false)
	# >> W14/NETSET Andock-Zeile (minimal): Server/Port/Secret-Zeilen samt
	# Verbindungstest leben in scripts/ui/settings/mehrspieler_sektion.gd.
	rows.add_child(MehrspielerSektion.new())


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
		# UIFINAL: klare Rangfolge — die GEWÄHLTE Sprache ist die gefüllte
		# Teal-Pill, die andere eine leise Ghost-Outline (vorher Gelb gegen
		# Teal: beide riefen „aktiv!“).
		btn.theme_type_variation = "BtnTeal" if id == active else "GhostButton"
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
	# W14: umbenannt zu „Haptik-Stärke“ — der Hauptschalter „Haptik“
	# (game.haptik) wohnt in der Spiel-Sektion.
	_add_pick_row(
		rows,
		"controls_haptics",
		I18nService.t("settings.haptik_staerke"),
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
	# W13-C FOTOWERK: Gyro-/Pointer-Parallax (Fallback = migriertes settings.gyro).
	_add_switch_row(
		rows,
		"game_parallax",
		I18nService.t("settings.parallax"),
		GyroParallax.setting_aktiv(_app(), get_node_or_null("/root/GameState")),
		func(on: bool) -> void: _set_app("game.parallax", on)
	)
	# W14/UIKERN-Kontrakt: Haptik-Hauptschalter `game.haptik` (Default AN) —
	# den zentralen Button-Pfad (Haptics.tap/success/warn) gated UIKERN.
	# Default explizit über get_setting(…, true): AppSettings._defaults kennt
	# den Key noch nicht, is_on() würde sonst fälschlich AUS liefern.
	_add_switch_row(
		rows,
		"game_haptik",
		I18nService.t("settings.haptik_an"),
		_app_on_default("game.haptik", true),
		func(on: bool) -> void: _set_app("game.haptik", on)
	)
	_add_help(rows, "HaptikAnHelp", I18nService.t("settings.haptik_an_hilfe"))
	_add_help(rows, "AutosaveHelp", I18nService.t("settings.autosave_hilfe"))
	var reset_btn := _section_button(rows, "TutorialResetButton", "settings.tutorial_reset")
	reset_btn.pressed.connect(_on_tutorial_reset)
	# REST-4 (EVAL Rang 11): Aktionscodes-Screen (Route `codes`).
	var codes_btn := _section_button(rows, "CodesButton", "codes.settings_eintrag")
	codes_btn.pressed.connect(_on_codes_pressed)


func _build_updates_section() -> void:
	var rows := _add_section("Updates", I18nService.t("settings.updates"))
	var btn := _section_button(rows, "UpdateCheckButton", "settings.update_suchen")
	btn.pressed.connect(_on_update_check)


## W6/FIX-6: Weg zum Uebernahme-Screen fuer den Spielstand der alten App —
## der User fand ihn sonst nicht ("Wo genau uebertraegt man seinen Save?").
func _build_transfer_section() -> void:
	# W14: Titel trägt der Gruppen-Header „Spielstand“ direkt darüber.
	var rows := _add_section("Spielstand", "", false)
	var btn := _section_button(rows, "TransferButton", "settings.spielstand_uebertragen")
	btn.pressed.connect(_on_transfer_pressed)
	# W13-C (Doc C §7): Server-Identitäts-Umzug per Panel-Code — der lokale
	# Spielstand bleibt auf dem Gerät, nur das Online-Konto zieht um.
	var umzug_btn := _section_button(rows, "UmzugButton", "umzug.settings_eintrag")
	umzug_btn.pressed.connect(_on_umzug_pressed)


func _on_umzug_pressed() -> void:
	var sheet := UmzugSheet.new()
	sheet.name = "UmzugSheet"
	add_child(sheet)


func _on_transfer_pressed() -> void:
	TransferScreen.register_routes()
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("goto"):
		router.goto(TransferScreen.ROUTE)


func _on_codes_pressed() -> void:
	CodesScreen.register_routes()
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("goto"):
		router.goto(CodesScreen.ROUTE)


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
