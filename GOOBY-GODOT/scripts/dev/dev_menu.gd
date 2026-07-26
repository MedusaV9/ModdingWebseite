class_name DevMenu
extends Control
## RW-7 — Verstecktes Dev-Menü (Doc §5.2). Wird vom DevService als Overlay
## geöffnet (nur nach Trigger + Halte-Bestätigung im Settings-Screen).
##
## Bereiche: Performance (PerfOverlay-Wiederverwendung), Zeit/Wetter
## (transiente Szenen-Overrides), Gold/Level (Clamp + Snapshot), Quest
## (Warte-Timer 10 s), Pferd (Daten-Spawn, Allowlist), Sticker (alle
## freischalten), Szenen-Sprung (nur registrierte Routen), Spielstand
## (Snapshot/Export/Import über den validierenden Transferweg), Netzwerk
## (redigierter Log). JEDE mutierende Aktion läuft über DevActions:
## Snapshot vorher + dev.touched-Markierung.

const SCRIM_COLOR := Color(0.11, 0.09, 0.08, 0.72)
const REFRESH_S := 1.0

var _f := 1.0
var _tf := 1.0
var _rows: VBoxContainer
var _toast: ToastLayer
var _perf_label: Label
var _net_label: Label
var _zeit_slider: HSlider
var _wetter_pick: OptionButton
var _gold_spin: SpinBox
var _level_spin: SpinBox
var _pferd_name: LineEdit
var _pferd_farbe: OptionButton
var _szene_pick: OptionButton
var _szene_routen: Array = []
var _accum := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_f = UiScale.for_viewport(get_viewport())
	_tf = UiScale.font_scale(get_viewport())
	_build_chrome()
	_build_sections()
	_refresh_live()


func _process(delta: float) -> void:
	_accum += delta
	if _accum < REFRESH_S:
		return
	_accum = 0.0
	_refresh_live()


func _build_chrome() -> void:
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = SCRIM_COLOR
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	card.name = "DevCard"
	card.theme_type_variation = "AcCard"
	var canvas := Vector2(get_viewport().get_visible_rect().size)
	card.custom_minimum_size = Vector2(
		minf(680.0 * _f, canvas.x - 40.0), minf(620.0 * _f, canvas.y - 40.0)
	)
	center.add_child(card)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", int(8.0 * _f))
	card.add_child(layout)
	layout.add_child(_build_header())
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	_rows = VBoxContainer.new()
	_rows.name = "Sections"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", int(10.0 * _f))
	scroll.add_child(_rows)
	_toast = ToastLayer.new()
	_toast.name = "Toast"
	_toast.set_anchors_preset(Control.PRESET_FULL_RECT)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast)


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", int(10.0 * _f))
	var badge := Label.new()
	badge.name = "DevChip"
	badge.text = "DEV"
	var chip := StyleBoxFlat.new()
	chip.bg_color = Color("#FFD34D")
	chip.border_color = Color("#1A1A1A")
	chip.set_border_width_all(2)
	chip.set_corner_radius_all(6)
	chip.content_margin_left = 8.0
	chip.content_margin_right = 8.0
	badge.add_theme_stylebox_override("normal", chip)
	badge.add_theme_color_override("font_color", Color("#1A1A1A"))
	header.add_child(badge)
	var title := Label.new()
	title.name = "Title"
	title.theme_type_variation = "TitleLabel"
	title.text = I18nService.t("dev.titel")
	title.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_TITLE * _tf))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := SquishButton.new()
	close.name = "CloseButton"
	close.text = I18nService.t("ui.schliessen")
	close.theme_type_variation = "BtnTeal"
	close.focus_mode = Control.FOCUS_NONE
	close.custom_minimum_size = Vector2(0, 44.0 * _f)
	close.pressed.connect(func() -> void: queue_free())
	header.add_child(close)
	return header


func _build_sections() -> void:
	_build_performance()
	_build_zeit_wetter()
	_build_gold_level()
	_build_quest_pferd()
	_build_sticker_szene()
	_build_save()
	_build_netzwerk()
	_build_footer()


func _build_performance() -> void:
	var rows := _section("Performance", I18nService.t("dev.perf"))
	var toggle := CheckButton.new()
	toggle.name = "PerfToggle"
	toggle.text = I18nService.t("dev.perf_overlay")
	toggle.focus_mode = Control.FOCUS_NONE
	toggle.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BODY * _tf))
	var overlay := get_node_or_null("/root/PerfOverlay")
	toggle.button_pressed = overlay != null and overlay.is_shown()
	toggle.toggled.connect(_on_perf_toggled)
	rows.add_child(toggle)
	_perf_label = Label.new()
	_perf_label.name = "PerfStats"
	_perf_label.theme_type_variation = "SoftLabel"
	_perf_label.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_CAPTION * _tf))
	rows.add_child(_perf_label)


func _build_zeit_wetter() -> void:
	var rows := _section("ZeitWetter", I18nService.t("dev.zeit_wetter"))
	var zeit_row := _row(rows, I18nService.t("dev.uhrzeit"))
	_zeit_slider = HSlider.new()
	_zeit_slider.name = "ZeitSlider"
	_zeit_slider.min_value = 0.0
	_zeit_slider.max_value = 23.5
	_zeit_slider.step = 0.5
	_zeit_slider.value = 12.0
	_zeit_slider.focus_mode = Control.FOCUS_NONE
	_zeit_slider.custom_minimum_size = Vector2(200.0 * _f, 36.0 * _f)
	_zeit_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	zeit_row.add_child(_zeit_slider)
	var wetter_row := _row(rows, I18nService.t("dev.wetter"))
	_wetter_pick = OptionButton.new()
	_wetter_pick.name = "WetterPick"
	_wetter_pick.focus_mode = Control.FOCUS_NONE
	_wetter_pick.add_item(I18nService.t("dev.wetter_simulation"), 0)
	var idx := 1
	for typ in ["sonne", "wolken", "niesel", "regen", "gewitter", "nebel"]:
		_wetter_pick.add_item(typ, idx)
		idx += 1
	wetter_row.add_child(_wetter_pick)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", int(8.0 * _f))
	buttons.add_child(_button("ApplyZeit", I18nService.t("dev.anwenden"), _on_zeit_anwenden))
	buttons.add_child(_button("ResetZeit", I18nService.t("dev.zurueck_simulation"), _on_zeit_reset))
	rows.add_child(buttons)


func _build_gold_level() -> void:
	var rows := _section("GoldLevel", I18nService.t("dev.gold_level"))
	var gold_row := _row(rows, I18nService.t("dev.gold"))
	_gold_spin = _spin(0, DevActions.GOLD_MAX, 1000)
	_gold_spin.name = "GoldSpin"
	gold_row.add_child(_gold_spin)
	gold_row.add_child(_button("SetGold", I18nService.t("dev.setzen"), _on_gold_setzen))
	var level_row := _row(rows, I18nService.t("dev.level"))
	_level_spin = _spin(1, 40, 1)
	_level_spin.name = "LevelSpin"
	level_row.add_child(_level_spin)
	level_row.add_child(_button("SetLevel", I18nService.t("dev.setzen"), _on_level_setzen))
	var hint := Label.new()
	hint.theme_type_variation = "SoftLabel"
	hint.text = I18nService.t("dev.markierung_hinweis")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_CAPTION * _tf))
	rows.add_child(hint)


func _build_quest_pferd() -> void:
	var rows := _section("QuestPferd", I18nService.t("dev.quest_pferd"))
	rows.add_child(_button("QuestWarte", I18nService.t("dev.quest_warte"), _on_quest_warte))
	var pferd_row := _row(rows, I18nService.t("dev.pferd_name"))
	_pferd_name = LineEdit.new()
	_pferd_name.name = "PferdName"
	_pferd_name.text = "Testpferd"
	_pferd_name.custom_minimum_size = Vector2(160.0 * _f, 40.0 * _f)
	pferd_row.add_child(_pferd_name)
	_pferd_farbe = OptionButton.new()
	_pferd_farbe.name = "PferdFarbe"
	_pferd_farbe.focus_mode = Control.FOCUS_NONE
	for farbe in ["braun", "weiss", "schwarz", "fuchs"]:
		_pferd_farbe.add_item(farbe)
	pferd_row.add_child(_pferd_farbe)
	rows.add_child(_button("SpawnPferd", I18nService.t("dev.pferd_spawnen"), _on_pferd_spawnen))


func _build_sticker_szene() -> void:
	var rows := _section("StickerSzene", I18nService.t("dev.sticker_szene"))
	rows.add_child(
		_button("AlleSticker", I18nService.t("dev.sticker_freischalten"), _on_sticker_alle)
	)
	var szene_row := _row(rows, I18nService.t("dev.szene"))
	_szene_pick = OptionButton.new()
	_szene_pick.name = "SzenePick"
	_szene_pick.focus_mode = Control.FOCUS_NONE
	_szene_routen = _routen()
	for route in _szene_routen:
		_szene_pick.add_item(str(route))
	szene_row.add_child(_szene_pick)
	rows.add_child(_button("SzeneGo", I18nService.t("dev.szene_springen"), _on_szene_springen))


func _build_save() -> void:
	var rows := _section("Save", I18nService.t("dev.spielstand"))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", int(8.0 * _f))
	buttons.add_child(_button("SnapNow", I18nService.t("dev.snapshot"), _on_snapshot))
	buttons.add_child(_button("ExportSave", I18nService.t("dev.export"), _on_export))
	buttons.add_child(_button("ImportSave", I18nService.t("dev.import"), _on_import))
	rows.add_child(buttons)
	var hint := Label.new()
	hint.theme_type_variation = "SoftLabel"
	hint.text = I18nService.t("dev.save_hinweis")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_CAPTION * _tf))
	rows.add_child(hint)


func _build_netzwerk() -> void:
	var rows := _section("Netzwerk", I18nService.t("dev.netzwerk"))
	_net_label = Label.new()
	_net_label.name = "NetLog"
	_net_label.theme_type_variation = "SoftLabel"
	_net_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_net_label.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_CAPTION * _tf))
	rows.add_child(_net_label)


func _build_footer() -> void:
	var off := SquishButton.new()
	off.name = "DevOff"
	off.theme_type_variation = "BtnDanger"
	off.text = I18nService.t("dev.deaktivieren")
	off.focus_mode = Control.FOCUS_NONE
	off.custom_minimum_size = Vector2(0, 48.0 * _f)
	off.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	off.pressed.connect(_on_dev_off)
	_rows.add_child(off)


## ---------------------------------------------------------------- Aktionen


func _on_perf_toggled(shown: bool) -> void:
	var overlay := get_node_or_null("/root/PerfOverlay")
	if overlay != null and overlay.has_method("set_shown"):
		overlay.set_shown(shown)


func _on_zeit_anwenden() -> void:
	var wetter := ""
	if _wetter_pick.selected > 0:
		wetter = _wetter_pick.get_item_text(_wetter_pick.selected)
	var touched := DevActions.apply_time_weather(_aktuelle_szene(), _zeit_slider.value, wetter)
	_toast.show_toast(I18nService.t("dev.zeit_gesetzt", {"n": touched}), touched == 0)


func _on_zeit_reset() -> void:
	DevActions.apply_time_weather(_aktuelle_szene(), -1.0, "")
	_toast.show_toast(I18nService.t("dev.zeit_zurueck"))


func _on_gold_setzen() -> void:
	var gs := _game_state()
	if gs == null:
		return
	var wert := DevActions.set_gold(gs, int(_gold_spin.value), _now_ms())
	_toast.show_toast(I18nService.t("dev.gold_gesetzt", {"wert": wert}))


func _on_level_setzen() -> void:
	var gs := _game_state()
	if gs == null:
		return
	var wert := DevActions.set_level(gs, int(_level_spin.value), _now_ms())
	_toast.show_toast(I18nService.t("dev.level_gesetzt", {"wert": wert}))


func _on_quest_warte() -> void:
	var gs := _game_state()
	if gs == null:
		return
	var n := DevActions.quest_warte_verkuerzen(gs, _now_ms())
	_toast.show_toast(I18nService.t("dev.quest_warte_ok", {"n": n}), n == 0)


func _on_pferd_spawnen() -> void:
	var gs := _game_state()
	if gs == null:
		return
	var farbe := _pferd_farbe.get_item_text(_pferd_farbe.selected)
	var ok := DevActions.spawn_horse(gs, _pferd_name.text.strip_edges(), farbe, _now_ms())
	_toast.show_toast(
		I18nService.t("dev.pferd_ok" if ok else "dev.pferd_fehler", {"name": _pferd_name.text}),
		not ok
	)


func _on_sticker_alle() -> void:
	var gs := _game_state()
	if gs == null:
		return
	var n := DevActions.unlock_all_stickers(gs, _now_ms())
	_toast.show_toast(I18nService.t("dev.sticker_ok", {"n": n}))


func _on_szene_springen() -> void:
	if _szene_pick.selected < 0 or _szene_routen.is_empty():
		return
	var router := get_node_or_null("/root/SceneRouter")
	if router == null:
		return
	var ziel := StringName(str(_szene_routen[_szene_pick.selected]))
	queue_free()
	router.goto(ziel)


func _on_snapshot() -> void:
	var gs := _game_state()
	if gs == null:
		return
	var path := DevActions.snapshot(gs, "manuell", _now_ms())
	_toast.show_toast(I18nService.t("dev.snapshot_ok", {"pfad": path}), path.is_empty())


func _on_export() -> void:
	var gs := _game_state()
	if gs == null:
		return
	var path := DevActions.export_save(gs, _now_ms())
	_toast.show_toast(I18nService.t("dev.export_ok", {"pfad": path}), path.is_empty())


func _on_import() -> void:
	var router := get_node_or_null("/root/SceneRouter")
	if router == null:
		return
	TransferScreen.register_routes()
	queue_free()
	router.goto(TransferScreen.ROUTE)


func _on_dev_off() -> void:
	var dev := get_node_or_null("/root/Dev")
	if dev != null and dev.has_method("disable"):
		dev.disable()
	queue_free()


## ------------------------------------------------------------------ Helfer


func _refresh_live() -> void:
	if _perf_label != null:
		var overlay := get_node_or_null("/root/PerfOverlay")
		if overlay != null and overlay.has_method("snapshot"):
			var m: Dictionary = overlay.snapshot()
			_perf_label.text = (
				"FPS %d · %.1f ms · Draw Calls %d · Nodes %d · VRAM %.1f MB"
				% [int(m["fps"]), m["frame_ms"], m["draw_calls"], m["nodes"], m["vram_mb"]]
			)
	if _net_label != null:
		_net_label.text = _net_text()


func _net_text() -> String:
	var dev := get_node_or_null("/root/Dev")
	if dev == null or not dev.has_method("net_log"):
		return I18nService.t("dev.netz_leer")
	var entries: Array = dev.net_log()
	if entries.is_empty():
		return I18nService.t("dev.netz_leer")
	var lines: Array[String] = []
	for i in range(maxi(0, entries.size() - 8), entries.size()):
		var e: Dictionary = entries[i]
		lines.append("%s · %d B" % [str(e.get("typ", "?")), int(e.get("groesse", 0))])
	return "\n".join(lines)


func _section(node_name: String, title: String) -> VBoxContainer:
	var card := PanelContainer.new()
	card.name = "Dev" + node_name
	card.theme_type_variation = "AcCard"
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override("separation", int(6.0 * _f))
	var label := Label.new()
	label.theme_type_variation = "TitleLabel"
	label.text = title
	label.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BODY * _tf))
	rows.add_child(label)
	card.add_child(rows)
	_rows.add_child(card)
	return rows


func _row(rows: VBoxContainer, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", int(10.0 * _f))
	var label := Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BODY * _tf))
	row.add_child(label)
	rows.add_child(row)
	return row


func _button(node_name: String, text: String, handler: Callable) -> Button:
	var btn := SquishButton.new()
	btn.name = node_name
	btn.theme_type_variation = "BtnTeal"
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 44.0 * _f)
	btn.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_CAPTION * _tf))
	btn.pressed.connect(handler)
	return btn


func _spin(min_value: int, max_value: int, step: int) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = step
	spin.custom_minimum_size = Vector2(150.0 * _f, 40.0 * _f)
	return spin


## Registrierte Router-Routen (sortiert) — nur diese sind anspringbar
## (Doc §5.2: „keine freien Dateipfade“).
func _routen() -> Array:
	var router := get_node_or_null("/root/SceneRouter")
	if router == null:
		return []
	var routes: Variant = router.get("_routes")
	if not (routes is Dictionary):
		return []
	var keys: Array = (routes as Dictionary).keys().map(func(k: Variant) -> String: return str(k))
	keys.sort()
	return keys


func _aktuelle_szene() -> Node:
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("get_current_scene"):
		var scene: Node = router.get_current_scene()
		if scene != null:
			return scene
	return get_tree().current_scene


func _game_state() -> Object:
	return get_node_or_null("/root/GameState")


func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)
