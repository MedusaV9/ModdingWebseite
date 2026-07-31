class_name DevMenu
extends Control
## RW-7 — Verstecktes Dev-Menü (Doc §5.2), W14/NETSET: zum Werkzeugkasten mit
## Tabs ausgebaut (User-Feedback „in meinen DEV Tools fehlt gefühlt alles“).
## Wird vom DevService als Overlay geöffnet (nur nach Trigger + Halte-
## Bestätigung im Settings-Screen — bestehendes Gate, hier ändert sich nichts).
##
## Tabs:
##  SPIELSTAND — Münzen/XP/Level, Stats-Slider, Sticker+Erfolge freischalten,
##    Quest/Pferd, Snapshot/Export/Import + Umzugskoffer-Code in die
##    Zwischenablage + Fixture-Saves der Testsuite laden.
##  ZEIT — Szenen-Override (Uhrzeit, transient) + ECHTER Uhr-Offset über die
##    öffentliche GameState-Clock (DevService.set_clock_offset_ms, DevZeit)
##    inkl. „Nächster Tag“.
##  EVENTS — jedes Random-Event sofort auslösen (Defs aus der Registry inkl.
##    Ranch), Wetter-Override (Tagesplan-Typ erzwingen), Taxi/Lieferung
##    sofort ankommen lassen.
##  GEGENSTÄNDE — durchsuchbare Katalog-Liste (Essen/Möbel/Bücher) → Inventar.
##  NETZ — net_config-Dump (Secret redigiert), Verbindungs-Log (letzte 20),
##    Outbox-Inhalt + Flush.
##  PERF — Perf-Overlay-Toggle (bestehendes /root/PerfOverlay) + Live-Werte.
##
## JEDE mutierende Aktion läuft über DevActions (Snapshot vorher +
## dev.touched-Markierung) bzw. die ÖFFENTLICHEN APIs der Systeme.

const SCRIM_COLOR := Color(0.11, 0.09, 0.08, 0.72)
const REFRESH_S := 1.0
## Verbindungs-Log-Zeilen im NETZ-Tab (W14: 8 → 20).
const NET_LOG_ZEILEN := 20

var _f := 1.0
var _tf := 1.0
var _layout: VBoxContainer
var _tabs: TabContainer
var _toast: ToastLayer
var _perf_label: Label
## W15/TECHKIT: Glow-Downgrade-Liste im Perf-Tab (PerfGlowWatch-Merker).
var _glow_label: Label
var _net_label: Label
var _net_config_label: Label
var _outbox_label: Label
var _zeit_slider: HSlider
var _wetter_pick: OptionButton
var _uhr_slider: HSlider
var _uhr_label: Label
var _gold_spin: SpinBox
var _xp_spin: SpinBox
var _level_spin: SpinBox
var _stat_slider: Dictionary = {}
var _pferd_name: LineEdit
var _pferd_farbe: OptionButton
var _szene_pick: OptionButton
var _szene_routen: Array = []
var _fixture_pick: OptionButton
var _fixtures: Array[Dictionary] = []
var _event_pick: OptionButton
var _event_defs: Array = []
var _item_suche: LineEdit
var _item_liste: ItemList
var _item_eintraege: Array[Dictionary] = []
## Zuletzt angewendete Szenen-Overrides (Stunde/Wetter hängen an derselben
## apply_time_weather-API — so überschreibt der eine Regler den anderen nicht).
var _forced_stunde := -1.0
var _forced_wetter := ""
var _accum := 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_f = UiScale.for_viewport(get_viewport())
	_tf = UiScale.font_scale(get_viewport())
	_build_chrome()
	_build_tabs()
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
	_layout = VBoxContainer.new()
	_layout.add_theme_constant_override("separation", int(8.0 * _f))
	card.add_child(_layout)
	_layout.add_child(_build_header())
	_tabs = TabContainer.new()
	_tabs.name = "DevTabs"
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tabs.clip_tabs = false
	_layout.add_child(_tabs)
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


## ------------------------------------------------------------------- Tabs


func _build_tabs() -> void:
	var spielstand := _tab("TabSpielstand", I18nService.t("netset.dev.tab_spielstand"))
	_build_gold_level(spielstand)
	_build_stats(spielstand)
	_build_quest_pferd(spielstand)
	_build_sticker_szene(spielstand)
	_build_save(spielstand)
	var zeit := _tab("TabZeit", I18nService.t("netset.dev.tab_zeit"))
	_build_zeit_wetter(zeit)
	_build_uhr(zeit)
	var events := _tab("TabEvents", I18nService.t("netset.dev.tab_events"))
	_build_events(events)
	var dinge := _tab("TabGegenstaende", I18nService.t("netset.dev.tab_gegenstaende"))
	_build_gegenstaende(dinge)
	var netz := _tab("TabNetz", I18nService.t("netset.dev.tab_netz"))
	_build_netzwerk(netz)
	var perf := _tab("TabPerf", I18nService.t("netset.dev.tab_perf"))
	_build_performance(perf)
	_build_footer()


## Eine Tab-Seite: ScrollContainer + Sections-VBox (Muster des alten Menüs).
func _tab(node_name: String, titel: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = node_name
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	_tabs.set_tab_title(_tabs.get_tab_count() - 1, titel)
	var rows := VBoxContainer.new()
	rows.name = "Sections"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", int(10.0 * _f))
	scroll.add_child(rows)
	return rows


## ------------------------------------------------------------- SPIELSTAND


func _build_gold_level(parent: VBoxContainer) -> void:
	var rows := _section(parent, "GoldLevel", I18nService.t("dev.gold_level"))
	var gold_row := _row(rows, I18nService.t("dev.gold"))
	_gold_spin = _spin(0, DevActions.GOLD_MAX, 1000)
	_gold_spin.name = "GoldSpin"
	gold_row.add_child(_gold_spin)
	gold_row.add_child(_button("SetGold", I18nService.t("dev.setzen"), _on_gold_setzen))
	var xp_row := _row(rows, I18nService.t("netset.dev.xp"))
	_xp_spin = _spin(0, 999_999, 50)
	_xp_spin.name = "XpSpin"
	xp_row.add_child(_xp_spin)
	xp_row.add_child(_button("SetXp", I18nService.t("dev.setzen"), _on_xp_setzen))
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


func _build_stats(parent: VBoxContainer) -> void:
	var rows := _section(parent, "Stats", I18nService.t("netset.dev.stats"))
	var gs := _game_state()
	for stat: String in ["hunger", "energy", "hygiene", "fun"]:
		var row := _row(rows, I18nService.t("netset.dev.stat_" + stat))
		var slider := HSlider.new()
		slider.name = "Stat" + stat.to_pascal_case()
		slider.min_value = 0.0
		slider.max_value = 100.0
		slider.step = 1.0
		slider.focus_mode = Control.FOCUS_NONE
		slider.custom_minimum_size = Vector2(200.0 * _f, 36.0 * _f)
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		if gs != null:
			slider.value = float(gs.get_value("gooby.stats." + stat, 50.0))
		# Erst beim Loslassen anwenden — sonst ein Snapshot pro Tick.
		slider.drag_ended.connect(_on_stat_gesetzt.bind(stat))
		_stat_slider[stat] = slider
		row.add_child(slider)


func _build_quest_pferd(parent: VBoxContainer) -> void:
	var rows := _section(parent, "QuestPferd", I18nService.t("dev.quest_pferd"))
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


func _build_sticker_szene(parent: VBoxContainer) -> void:
	var rows := _section(parent, "StickerSzene", I18nService.t("dev.sticker_szene"))
	rows.add_child(
		_button("AlleSticker", I18nService.t("dev.sticker_freischalten"), _on_sticker_alle)
	)
	rows.add_child(_button("AlleErfolge", I18nService.t("netset.dev.erfolge"), _on_erfolge_alle))
	var szene_row := _row(rows, I18nService.t("dev.szene"))
	_szene_pick = OptionButton.new()
	_szene_pick.name = "SzenePick"
	_szene_pick.focus_mode = Control.FOCUS_NONE
	_szene_routen = _routen()
	for route in _szene_routen:
		_szene_pick.add_item(str(route))
	szene_row.add_child(_szene_pick)
	rows.add_child(_button("SzeneGo", I18nService.t("dev.szene_springen"), _on_szene_springen))


func _build_save(parent: VBoxContainer) -> void:
	var rows := _section(parent, "Save", I18nService.t("dev.spielstand"))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", int(8.0 * _f))
	buttons.add_child(_button("SnapNow", I18nService.t("dev.snapshot"), _on_snapshot))
	buttons.add_child(_button("ExportSave", I18nService.t("dev.export"), _on_export))
	buttons.add_child(_button("ImportSave", I18nService.t("dev.import"), _on_import))
	rows.add_child(buttons)
	rows.add_child(_button("ExportCode", I18nService.t("netset.dev.export_code"), _on_export_code))
	var fixture_row := _row(rows, I18nService.t("netset.dev.fixture"))
	_fixture_pick = OptionButton.new()
	_fixture_pick.name = "FixturePick"
	_fixture_pick.focus_mode = Control.FOCUS_NONE
	_fixtures = DevActions.fixture_saves()
	for fixture: Dictionary in _fixtures:
		_fixture_pick.add_item(str(fixture["name"]))
	fixture_row.add_child(_fixture_pick)
	rows.add_child(
		_button("FixtureLaden", I18nService.t("netset.dev.fixture_laden"), _on_fixture_laden)
	)
	var hint := Label.new()
	hint.theme_type_variation = "SoftLabel"
	hint.text = I18nService.t("dev.save_hinweis")
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_CAPTION * _tf))
	rows.add_child(hint)


## ------------------------------------------------------------------- ZEIT


func _build_zeit_wetter(parent: VBoxContainer) -> void:
	var rows := _section(parent, "ZeitWetter", I18nService.t("dev.zeit_wetter"))
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
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", int(8.0 * _f))
	buttons.add_child(_button("ApplyZeit", I18nService.t("dev.anwenden"), _on_zeit_anwenden))
	buttons.add_child(_button("ResetZeit", I18nService.t("dev.zurueck_simulation"), _on_zeit_reset))
	rows.add_child(buttons)


func _build_uhr(parent: VBoxContainer) -> void:
	var rows := _section(parent, "Uhr", I18nService.t("netset.dev.uhr"))
	var offset_row := _row(rows, I18nService.t("netset.dev.uhr_offset"))
	_uhr_slider = HSlider.new()
	_uhr_slider.name = "UhrOffsetSlider"
	_uhr_slider.min_value = 0.0
	_uhr_slider.max_value = 168.0
	_uhr_slider.step = 1.0
	_uhr_slider.focus_mode = Control.FOCUS_NONE
	_uhr_slider.custom_minimum_size = Vector2(200.0 * _f, 36.0 * _f)
	_uhr_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var dev := _dev()
	if dev != null and dev.has_method("clock_offset_ms"):
		_uhr_slider.value = float(DevZeit.offset_stunden(int(dev.clock_offset_ms())))
	_uhr_slider.drag_ended.connect(_on_uhr_offset)
	offset_row.add_child(_uhr_slider)
	_uhr_label = Label.new()
	_uhr_label.name = "UhrOffsetLabel"
	_uhr_label.theme_type_variation = "SoftLabel"
	_uhr_label.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_CAPTION * _tf))
	_uhr_label.text = I18nService.t("netset.dev.offset_aus")
	rows.add_child(_uhr_label)
	rows.add_child(
		_button("NaechsterTag", I18nService.t("netset.dev.naechster_tag"), _on_naechster_tag)
	)


## ----------------------------------------------------------------- EVENTS


func _build_events(parent: VBoxContainer) -> void:
	var rows := _section(parent, "Events", I18nService.t("netset.dev.event"))
	var event_row := _row(rows, I18nService.t("netset.dev.event"))
	_event_pick = OptionButton.new()
	_event_pick.name = "EventPick"
	_event_pick.focus_mode = Control.FOCUS_NONE
	_event_defs = RandomEventEngine.defs_from_registry()
	for def: Variant in _event_defs:
		if def is Dictionary:
			var kontext := str((def as Dictionary).get("context", "home"))
			_event_pick.add_item("%s (%s)" % [str((def as Dictionary).get("id", "?")), kontext])
	event_row.add_child(_event_pick)
	rows.add_child(
		_button("EventAusloesen", I18nService.t("netset.dev.event_ausloesen"), _on_event_ausloesen)
	)
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
	rows.add_child(_button("WetterAnwenden", I18nService.t("dev.anwenden"), _on_wetter_anwenden))
	rows.add_child(_button("TaxiSofort", I18nService.t("netset.dev.taxi"), _on_taxi_sofort))
	rows.add_child(
		_button("LieferungSofort", I18nService.t("netset.dev.lieferung"), _on_lieferung_sofort)
	)


## ------------------------------------------------------------ GEGENSTÄNDE


func _build_gegenstaende(parent: VBoxContainer) -> void:
	var rows := _section(parent, "Gegenstaende", I18nService.t("netset.dev.tab_gegenstaende"))
	_item_suche = LineEdit.new()
	_item_suche.name = "ItemSuche"
	_item_suche.placeholder_text = I18nService.t("netset.dev.suche")
	_item_suche.custom_minimum_size = Vector2(0, 40.0 * _f)
	_item_suche.text_changed.connect(func(_t: String) -> void: _fill_item_liste())
	rows.add_child(_item_suche)
	_item_liste = ItemList.new()
	_item_liste.name = "ItemListe"
	_item_liste.custom_minimum_size = Vector2(0, 180.0 * _f)
	_item_liste.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(_item_liste)
	_fill_item_liste()
	rows.add_child(_button("ItemGeben", I18nService.t("netset.dev.geben"), _on_item_geben))


## Katalog-Einträge (Essen/Möbel/Bücher) — gefiltert nach dem Suchfeld.
func _fill_item_liste() -> void:
	var needle := _item_suche.text.strip_edges().to_lower() if _item_suche != null else ""
	_item_eintraege = []
	_item_liste.clear()
	var alle: Array[Dictionary] = []
	for food_id: Variant in FoodCatalog.all():
		alle.append({"kind": "food", "id": str(food_id)})
	for item_id: Variant in ShopCatalog.ids():
		alle.append({"kind": "moebel", "id": str(item_id)})
	for book: Variant in StoryBooks.books_from_registry():
		if book is Dictionary:
			alle.append({"kind": "buch", "id": str((book as Dictionary).get("id", ""))})
	for eintrag: Dictionary in alle:
		var id := str(eintrag["id"])
		if id.is_empty():
			continue
		if not needle.is_empty() and not id.to_lower().contains(needle):
			continue
		_item_eintraege.append(eintrag)
		_item_liste.add_item("%s · %s" % [str(eintrag["kind"]), id])


## ------------------------------------------------------------------- NETZ


func _build_netzwerk(parent: VBoxContainer) -> void:
	var rows := _section(parent, "Netzwerk", I18nService.t("netset.dev.netz_config"))
	_net_config_label = Label.new()
	_net_config_label.name = "NetConfigDump"
	_net_config_label.theme_type_variation = "SoftLabel"
	_net_config_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_net_config_label.add_theme_font_size_override(
		"font_size", int(AcTokens.FONT_SIZE_CAPTION * _tf)
	)
	rows.add_child(_net_config_label)
	var log_titel := Label.new()
	log_titel.theme_type_variation = "TitleLabel"
	log_titel.text = I18nService.t("netset.dev.verbindungslog", {"n": NET_LOG_ZEILEN})
	log_titel.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BODY * _tf))
	rows.add_child(log_titel)
	_net_label = Label.new()
	_net_label.name = "NetLog"
	_net_label.theme_type_variation = "SoftLabel"
	_net_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_net_label.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_CAPTION * _tf))
	rows.add_child(_net_label)
	_outbox_label = Label.new()
	_outbox_label.name = "OutboxInfo"
	_outbox_label.theme_type_variation = "SoftLabel"
	_outbox_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_outbox_label.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_CAPTION * _tf))
	rows.add_child(_outbox_label)
	rows.add_child(_button("OutboxFlush", I18nService.t("netset.dev.flush"), _on_outbox_flush))


## ------------------------------------------------------------------- PERF


func _build_performance(parent: VBoxContainer) -> void:
	var rows := _section(parent, "Performance", I18nService.t("dev.perf"))
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
	_build_glow_watch(parent)


## W15/TECHKIT (Doc G §9 R2): Glow-Downgrade-Merker (PerfGlowWatch,
## user://) — Liste der gedrosselten Spiele + Reset für frische Messfahrten.
func _build_glow_watch(parent: VBoxContainer) -> void:
	var rows := _section(parent, "GlowWatch", I18nService.t("dev.glow_titel"))
	_glow_label = Label.new()
	_glow_label.name = "GlowListe"
	_glow_label.theme_type_variation = "SoftLabel"
	_glow_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_glow_label.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_CAPTION * _tf))
	rows.add_child(_glow_label)
	rows.add_child(_button("GlowReset", I18nService.t("dev.glow_reset"), _on_glow_reset))


func _build_footer() -> void:
	var off := SquishButton.new()
	off.name = "DevOff"
	off.theme_type_variation = "BtnDanger"
	off.text = I18nService.t("dev.deaktivieren")
	off.focus_mode = Control.FOCUS_NONE
	off.custom_minimum_size = Vector2(0, 48.0 * _f)
	off.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	off.pressed.connect(_on_dev_off)
	_layout.add_child(off)


## ---------------------------------------------------------------- Aktionen


func _on_perf_toggled(shown: bool) -> void:
	var overlay := get_node_or_null("/root/PerfOverlay")
	if overlay != null and overlay.has_method("set_shown"):
		overlay.set_shown(shown)


## W15/TECHKIT: alle Glow-Downgrade-Merker löschen — die betroffenen Spiele
## messen beim nächsten Start wieder frisch.
func _on_glow_reset() -> void:
	PerfGlowWatch.clear_store()
	_refresh_live()
	_toast.show_toast(I18nService.t("dev.glow_reset_ok"))


func _on_zeit_anwenden() -> void:
	_forced_stunde = _zeit_slider.value
	var touched := DevActions.apply_time_weather(_aktuelle_szene(), _forced_stunde, _forced_wetter)
	_toast.show_toast(I18nService.t("dev.zeit_gesetzt", {"n": touched}), touched == 0)


func _on_zeit_reset() -> void:
	_forced_stunde = -1.0
	_forced_wetter = ""
	DevActions.apply_time_weather(_aktuelle_szene(), -1.0, "")
	_toast.show_toast(I18nService.t("dev.zeit_zurueck"))


func _on_wetter_anwenden() -> void:
	_forced_wetter = ""
	if _wetter_pick.selected > 0:
		_forced_wetter = _wetter_pick.get_item_text(_wetter_pick.selected)
	var touched := DevActions.apply_time_weather(_aktuelle_szene(), _forced_stunde, _forced_wetter)
	_toast.show_toast(I18nService.t("dev.zeit_gesetzt", {"n": touched}), touched == 0)


func _on_uhr_offset(_changed: bool) -> void:
	var dev := _dev()
	if dev == null or not dev.has_method("set_clock_offset_ms"):
		return
	var stunden := int(_uhr_slider.value)
	dev.set_clock_offset_ms(stunden * DevZeit.MS_PER_HOUR)
	_update_uhr_label(stunden)


func _on_naechster_tag() -> void:
	var dev := _dev()
	if dev == null or not dev.has_method("set_clock_offset_ms"):
		return
	var offset := int(dev.clock_offset_ms()) + DevZeit.MS_PER_DAY
	dev.set_clock_offset_ms(offset)
	var stunden := DevZeit.offset_stunden(offset)
	if _uhr_slider != null:
		_uhr_slider.value = float(mini(stunden, int(_uhr_slider.max_value)))
	_update_uhr_label(stunden)
	_toast.show_toast(I18nService.t("netset.dev.naechster_tag_ok", {"stunden": stunden}))


func _update_uhr_label(stunden: int) -> void:
	if _uhr_label == null:
		return
	if stunden <= 0:
		_uhr_label.text = I18nService.t("netset.dev.offset_aus")
	else:
		_uhr_label.text = I18nService.t("netset.dev.offset_status", {"stunden": stunden})


func _on_gold_setzen() -> void:
	var gs := _game_state()
	if gs == null:
		return
	var wert := DevActions.set_gold(gs, int(_gold_spin.value), _now_ms())
	_toast.show_toast(I18nService.t("dev.gold_gesetzt", {"wert": wert}))


func _on_xp_setzen() -> void:
	var gs := _game_state()
	if gs == null:
		return
	var wert := DevActions.set_xp(gs, int(_xp_spin.value), _now_ms())
	_toast.show_toast(I18nService.t("netset.dev.xp_gesetzt", {"wert": wert}))


func _on_level_setzen() -> void:
	var gs := _game_state()
	if gs == null:
		return
	var wert := DevActions.set_level(gs, int(_level_spin.value), _now_ms())
	_toast.show_toast(I18nService.t("dev.level_gesetzt", {"wert": wert}))


func _on_stat_gesetzt(changed: bool, stat: String) -> void:
	if not changed:
		return
	var gs := _game_state()
	if gs == null or not _stat_slider.has(stat):
		return
	var slider: HSlider = _stat_slider[stat]
	var wert := DevActions.set_stat(gs, stat, slider.value, _now_ms())
	_toast.show_toast(
		I18nService.t(
			"netset.dev.stat_gesetzt",
			{"stat": I18nService.t("netset.dev.stat_" + stat), "wert": int(wert)}
		)
	)


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


func _on_erfolge_alle() -> void:
	var gs := _game_state()
	if gs == null:
		return
	var n := DevActions.unlock_all_achievements(gs, _now_ms())
	_toast.show_toast(I18nService.t("netset.dev.erfolge_ok", {"n": n}))


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


func _on_export_code() -> void:
	var gs := _game_state()
	if gs == null:
		return
	var code := DevActions.export_code_to_clipboard(gs)
	_toast.show_toast(I18nService.t("netset.dev.export_code_ok"), code.is_empty())


func _on_fixture_laden() -> void:
	var gs := _game_state()
	if gs == null or _fixture_pick.selected < 0 or _fixtures.is_empty():
		return
	var fixture: Dictionary = _fixtures[_fixture_pick.selected]
	var res := DevActions.load_fixture(gs, str(fixture["path"]), _now_ms())
	if bool(res["ok"]):
		_toast.show_toast(I18nService.t("netset.dev.fixture_ok", {"name": fixture["name"]}))
	else:
		_toast.show_toast(
			I18nService.t("netset.dev.fixture_fehler", {"fehler": res["error"]}), true
		)


func _on_import() -> void:
	var router := get_node_or_null("/root/SceneRouter")
	if router == null:
		return
	TransferScreen.register_routes()
	queue_free()
	router.goto(TransferScreen.ROUTE)


func _on_event_ausloesen() -> void:
	var gs := _game_state()
	if gs == null or _event_pick.selected < 0 or _event_defs.is_empty():
		_toast.show_toast(I18nService.t("netset.dev.event_fehler"), true)
		return
	var def: Dictionary = _event_defs[_event_pick.selected]
	if DevActions.trigger_event(gs, def, _now_ms()):
		_toast.show_toast(I18nService.t("netset.dev.event_ok", {"id": def.get("id", "?")}))
	else:
		_toast.show_toast(I18nService.t("netset.dev.event_fehler"), true)


func _on_taxi_sofort() -> void:
	var gs := _game_state()
	if gs == null:
		return
	var ok := DevActions.taxi_sofort(gs, _now_ms())
	_toast.show_toast(
		I18nService.t("netset.dev.taxi_ok" if ok else "netset.dev.taxi_keins"), not ok
	)


func _on_lieferung_sofort() -> void:
	var gs := _game_state()
	if gs == null:
		return
	var ok := DevActions.lieferung_sofort(gs, _now_ms())
	_toast.show_toast(
		I18nService.t("netset.dev.lieferung_ok" if ok else "netset.dev.lieferung_keine"), not ok
	)


func _on_item_geben() -> void:
	var gs := _game_state()
	var auswahl := _item_liste.get_selected_items()
	if gs == null or auswahl.is_empty():
		_toast.show_toast(I18nService.t("netset.dev.geben_fehler"), true)
		return
	var eintrag: Dictionary = _item_eintraege[auswahl[0]]
	var ok := DevActions.give_item(gs, str(eintrag["kind"]), str(eintrag["id"]), _now_ms())
	if ok:
		_toast.show_toast(I18nService.t("netset.dev.geben_ok", {"id": eintrag["id"]}))
	else:
		_toast.show_toast(I18nService.t("netset.dev.geben_fehler"), true)


func _on_outbox_flush() -> void:
	var net := get_node_or_null("/root/Net")
	if net == null:
		_toast.show_toast(I18nService.t("netset.dev.flush_offline"), true)
		return
	# Alle Services mit flush()-API anstoßen (Analytics/Redeem/Mail) — die
	# Sender entscheiden selbst, ob sie online genug sind.
	for child in net.get_children():
		if child.has_method("flush"):
			child.flush()
	var online := net.has_method("is_online") and bool(net.is_online())
	_toast.show_toast(
		I18nService.t("netset.dev.flush_ok" if online else "netset.dev.flush_offline"), not online
	)
	_refresh_live()


func _on_dev_off() -> void:
	var dev := _dev()
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
	if _glow_label != null:
		_glow_label.text = _glow_text()
	if _net_label != null:
		_net_label.text = _net_text()
	if _net_config_label != null:
		_net_config_label.text = _net_config_text()
	if _outbox_label != null:
		_outbox_label.text = _outbox_text()


## W15/TECHKIT: Merker-Liste des Glow-Wächters (leer = nichts gedrosselt).
func _glow_text() -> String:
	var rows := PerfGlowWatch.entries()
	if rows.is_empty():
		return I18nService.t("dev.glow_leer")
	var lines: Array[String] = []
	for row: Dictionary in rows:
		lines.append(
			"%s · p95 %.1f ms · %s" % [str(row["game"]), float(row["p95_ms"]), str(row["at"])]
		)
	return "\n".join(lines)


func _net_text() -> String:
	var dev := _dev()
	if dev == null or not dev.has_method("net_log"):
		return I18nService.t("dev.netz_leer")
	var entries: Array = dev.net_log()
	if entries.is_empty():
		return I18nService.t("dev.netz_leer")
	var lines: Array[String] = []
	for i in range(maxi(0, entries.size() - NET_LOG_ZEILEN), entries.size()):
		var e: Dictionary = entries[i]
		lines.append("%s · %d B" % [str(e.get("typ", "?")), int(e.get("groesse", 0))])
	return "\n".join(lines)


## Effektive Netz-Config als Dump (User-Override > Pack > Default; Secret
## wird REDIGIERT — Doc §5.2: Geheimnisse nie im Klartext anzeigen).
func _net_config_text() -> String:
	var pack := NetClient.DEFAULT_NET.duplicate(true)
	var registry := get_node_or_null("/root/ContentRegistry")
	if registry != null and registry.has_method("get_net_config"):
		pack = registry.get_net_config()
	var user := NetClient.load_user_override()
	var merged := NetClient.merge_net_config(NetClient.DEFAULT_NET, pack, user)
	var status := "?"
	var net := get_node_or_null("/root/Net")
	if net != null and net.has_method("is_online"):
		status = "online" if bool(net.is_online()) else "offline"
	return (
		"effektiv: %s · user-override: %s · pack: %s · status: %s"
		% [
			JSON.stringify(DevActions.redact(merged)),
			JSON.stringify(DevActions.redact(user)) if not user.is_empty() else "—",
			JSON.stringify(DevActions.redact(pack)),
			status,
		]
	)


func _outbox_text() -> String:
	var net := get_node_or_null("/root/Net")
	if net == null:
		return I18nService.t("netset.dev.outbox_leer")
	var outbox: Variant = net.get("outbox")
	if outbox == null or not (outbox is Object) or not (outbox as Object).has_method("entries"):
		return I18nService.t("netset.dev.outbox_leer")
	var entries: Array = outbox.entries()
	if entries.is_empty():
		return I18nService.t("netset.dev.outbox_leer")
	var lines: Array[String] = [I18nService.t("netset.dev.outbox", {"n": entries.size()})]
	for i in range(mini(entries.size(), 10)):
		var e: Dictionary = entries[i]
		lines.append("%s · %s" % [str(e.get("kind", "?")), str(e.get("id", "")).left(8)])
	return "\n".join(lines)


func _section(parent: VBoxContainer, node_name: String, title: String) -> VBoxContainer:
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
	parent.add_child(card)
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


func _dev() -> Object:
	return get_node_or_null("/root/Dev")


func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)
