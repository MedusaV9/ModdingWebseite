class_name DlcScreen
extends Control
## DLC-Bibliothek (W14/DLCHUB) — USER-WUNSCH: „in Settings soll es ‚DLC‘
## Bereich geben wo alle DLCs aufgelistet sind mit ihren Coverarts samt dem
## Namen und so einer Art DLC Info ohne zu viel zu Spoilern.“
##
## Voller Screen mit großen Cover-Karten (Cover + Name + Status-Ribbon
## NEU/BALD/INSTALLIERT + Teaser). Tap → Detail-Sheet (großes Cover,
## Features-Stichpunkte, Unlock-Info) mit Aktions-Knopf: Ranch verfügbar →
## bestehendes Angebots-Sheet (RanchOffer.zeige), Ranch gekauft →
## „Losreiten!“ (RanchRouten.fahre_zum_hof), kommt_bald → knuffiger
## „Gooby arbeitet dran…“-Hinweis mit Hammer-Gag. Daten: DlcKatalog
## (Pack `content/dlc/`, updatebar). Sanfte Parallax-Neigung der Cover
## beim Scroll — bei Reduced-Motion komplett aus.
## Erreichbar über Route `dlc` (Settings → Sektion „DLC“, DlcSektion).

signal ready_for_reveal

const ROUTE := &"dlc"
const ROUTES := {ROUTE: "res://scripts/ui/dlc/dlc_screen.tscn"}
const PanelSheetScene := preload("res://scripts/ui/panel_sheet.tscn")

## Parallax-Hub des Covers im Rahmen (Design-px, skaliert mit f).
const PARALLAX_HUB := 16.0
## Zusatzhöhe des Covers über den Rahmen hinaus (verhindert Ränder).
const PARALLAX_POLSTER := 24.0
## Maximale Neigung in Grad (sanft!).
const PARALLAX_NEIGUNG := 1.2

## Meta-Keys am Detail-Sheet (Tests greifen darüber zu).
const META_AKTION := "dlc_aktion_button"
const META_BALD := "dlc_bald_hinweis"

## Tests/Screenshots: GameState-Double statt /root/GameState.
var gs_override: Object = null
## Tests: Navigation abschaltbar.
var auto_navigate := true

var _gs: Object = null
var _rows: VBoxContainer
var _scroll: ScrollContainer
## Pro Karte: {"rahmen": Control, "cover": TextureRect}.
var _parallax_cover: Array[Dictionary] = []
var _m: Dictionary = {}


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
	_gs = gs_override if gs_override != null else get_node_or_null("/root/GameState")
	_build_ui()
	_apply_metrics()
	get_viewport().size_changed.connect(_apply_metrics)
	ready_for_reveal.emit()


## ---------------------------------------------------------------- Test-API


## Detail-Sheet für einen Eintrag öffnen (auch der Karten-Tap landet hier).
func oeffne_detail(id: String) -> PanelSheet:
	var dlc := DlcKatalog.eintrag(id)
	if dlc.is_empty():
		return null
	var sheet: PanelSheet = PanelSheetScene.instantiate()
	sheet.theme = ThemeService.theme()
	add_child(sheet)
	sheet.set_title(str(dlc.get("name", id)))
	sheet.add_content(_detail_inhalt(sheet, dlc))
	sheet.open()
	return sheet


func karten() -> Array[PanelContainer]:
	var out: Array[PanelContainer] = []
	for kind in _rows.get_children():
		if kind is PanelContainer and String(kind.name).begins_with("DlcKarte"):
			out.append(kind)
	return out


## ---------------------------------------------------------------- Aufbau


func _build_ui() -> void:
	var wallpaper := AcWallpaper.new()
	wallpaper.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(wallpaper)

	_scroll = ScrollContainer.new()
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# Inhaltsspalte W16: sichtbarer Scrollbalken stiehlt dem Scroll-Kind
	# Layout-Breite und schöbe die zentrierte Spalte aus der Mitte.
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.scroll_deadzone = 24
	add_child(_scroll)
	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 16)
	_scroll.add_child(_rows)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	_rows.add_child(header)
	var back := SquishButton.new()
	back.name = "Zurueck"
	back.theme_type_variation = &"BtnGhost"
	back.text = I18nService.t("dlc.zurueck")
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(_on_back_pressed)
	header.add_child(back)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = I18nService.t("dlc.titel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)

	var intro := Label.new()
	intro.name = "Intro"
	intro.theme_type_variation = &"CaptionLabel"
	intro.text = I18nService.t("dlc.intro")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rows.add_child(intro)

	for dlc: Dictionary in DlcKatalog.eintraege():
		_baue_karte(dlc)

	# Parallax nur, wenn Bewegung erwünscht ist (Reduced-Motion = ganz aus).
	if not ThemeService.is_reduced_motion(self):
		_scroll.get_v_scroll_bar().value_changed.connect(_update_parallax)


func _baue_karte(dlc: Dictionary) -> void:
	var id := str(dlc.get("id", ""))
	var karte := PanelContainer.new()
	karte.name = "DlcKarte_" + id
	karte.theme_type_variation = &"AcCard"
	karte.mouse_filter = Control.MOUSE_FILTER_PASS
	karte.gui_input.connect(_on_karte_input.bind(id))
	_rows.add_child(karte)
	var inhalt := VBoxContainer.new()
	inhalt.add_theme_constant_override("separation", 10)
	karte.add_child(inhalt)

	# Cover-Rahmen: clippt das etwas größere Cover — Spielraum für Parallax.
	var rahmen := Control.new()
	rahmen.name = "CoverRahmen"
	rahmen.clip_contents = true
	rahmen.custom_minimum_size = Vector2(0.0, 240.0)
	rahmen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	inhalt.add_child(rahmen)
	var cover := TextureRect.new()
	cover.name = "Cover"
	var textur: Variant = load(str(dlc.get("cover", "")))
	if textur is Texture2D:
		cover.texture = textur
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	cover.set_anchors_preset(Control.PRESET_FULL_RECT)
	cover.offset_top = -PARALLAX_POLSTER
	cover.offset_bottom = PARALLAX_POLSTER
	cover.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rahmen.add_child(cover)
	_parallax_cover.append({"rahmen": rahmen, "cover": cover})

	var ribbon := Label.new()
	ribbon.name = "Ribbon"
	ribbon.text = _ribbon_text(DlcKatalog.status_fuer(dlc, _gs))
	ribbon.theme_type_variation = &"CaptionLabel"
	ribbon.add_theme_color_override("font_color", AcTokens.WHITE)
	var band := StyleBoxFlat.new()
	band.bg_color = _ribbon_farbe(DlcKatalog.status_fuer(dlc, _gs))
	band.set_corner_radius_all(AcTokens.RADIUS_ROW)
	band.content_margin_left = 14.0
	band.content_margin_right = 14.0
	band.content_margin_top = 5.0
	band.content_margin_bottom = 5.0
	ribbon.add_theme_stylebox_override("normal", band)
	ribbon.position = Vector2(12.0, 12.0)
	ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rahmen.add_child(ribbon)

	var name_zeile := HBoxContainer.new()
	name_zeile.add_theme_constant_override("separation", 10)
	inhalt.add_child(name_zeile)
	var name_label := Label.new()
	name_label.name = "Name"
	name_label.theme_type_variation = &"TitleLabel"
	name_label.text = str(dlc.get("name", id))
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_zeile.add_child(name_label)
	var ansehen := SquishButton.new()
	ansehen.name = "Ansehen"
	ansehen.theme_type_variation = &"BtnTeal"
	ansehen.text = I18nService.t("dlc.knopf.ansehen")
	ansehen.focus_mode = Control.FOCUS_NONE
	ansehen.custom_minimum_size = Vector2(0.0, AcTokens.TOUCH_FLOOR)
	ansehen.pressed.connect(func() -> void: oeffne_detail(id))
	name_zeile.add_child(ansehen)

	var teaser := Label.new()
	teaser.name = "Teaser"
	teaser.theme_type_variation = &"SoftLabel"
	teaser.text = DlcKatalog.text_von(dlc, "teaser")
	teaser.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inhalt.add_child(teaser)


## ---------------------------------------------------------------- Detail


func _detail_inhalt(sheet: PanelSheet, dlc: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)

	var cover := TextureRect.new()
	cover.name = "DetailCover"
	var textur: Variant = load(str(dlc.get("cover", "")))
	if textur is Texture2D:
		cover.texture = textur
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	cover.custom_minimum_size = Vector2(0.0, 220.0)
	box.add_child(cover)

	var teaser := Label.new()
	teaser.text = DlcKatalog.text_von(dlc, "teaser")
	teaser.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(teaser)

	var features_titel := Label.new()
	features_titel.theme_type_variation = &"HeadlineLabel"
	features_titel.text = I18nService.t("dlc.features_titel")
	box.add_child(features_titel)
	for feature: Variant in DlcKatalog.features_von(dlc):
		var punkt := Label.new()
		punkt.text = "•  %s" % str(feature)
		punkt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(punkt)

	var unlock := Label.new()
	unlock.name = "UnlockInfo"
	unlock.theme_type_variation = &"CaptionLabel"
	unlock.text = "%s: %s" % [I18nService.t("dlc.unlock_titel"), DlcKatalog.unlock_text(dlc)]
	unlock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(unlock)

	_baue_detail_aktion(sheet, dlc, box)
	return box


## Aktionsbereich unterm Detail: je Anzeige-Status Knopf oder Hinweis.
func _baue_detail_aktion(sheet: PanelSheet, dlc: Dictionary, box: VBoxContainer) -> void:
	match DlcKatalog.aktion_fuer(dlc, _gs):
		DlcKatalog.AKTION_HOF:
			var los := _aktion_knopf(box, &"BtnLeaf", I18nService.t("dlc.knopf.losreiten"))
			los.pressed.connect(func() -> void: _losreiten(sheet))
			sheet.set_meta(META_AKTION, los)
		DlcKatalog.AKTION_ANGEBOT:
			var hin := _aktion_knopf(box, &"BtnTeal", I18nService.t("dlc.knopf.zur_ranch"))
			hin.pressed.connect(func() -> void: _zum_angebot(sheet))
			sheet.set_meta(META_AKTION, hin)
		DlcKatalog.AKTION_GESPERRT:
			var zu := _aktion_knopf(box, &"BtnTeal", I18nService.t("dlc.knopf.zur_ranch"))
			zu.disabled = true
			sheet.set_meta(META_AKTION, zu)
			var gate := Label.new()
			gate.name = "GesperrtHinweis"
			gate.theme_type_variation = &"CaptionLabel"
			gate.text = I18nService.t("dlc.gesperrt_hinweis", {"aktuell": _spieler_level()})
			gate.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			gate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(gate)
		_:
			var bald := Label.new()
			bald.name = "BaldHinweis"
			bald.theme_type_variation = &"SoftLabel"
			bald.text = I18nService.t("dlc.bald_hinweis")
			bald.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			bald.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			box.add_child(bald)
			sheet.set_meta(META_BALD, bald)


func _aktion_knopf(box: VBoxContainer, variation: StringName, text: String) -> SquishButton:
	var knopf := SquishButton.new()
	knopf.name = "AktionKnopf"
	knopf.theme_type_variation = variation
	knopf.text = text
	knopf.focus_mode = Control.FOCUS_NONE
	knopf.custom_minimum_size = Vector2(220.0, 52.0)
	knopf.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(knopf)
	return knopf


## „Losreiten!“: direkt auf den Hof (Route registriert RanchRouten selbst).
func _losreiten(sheet: PanelSheet) -> void:
	sheet.close()
	sheet.queue_free()
	if auto_navigate:
		RanchRouten.fahre_zum_hof(get_tree())


## „Zur Ranch“: der BESTEHENDE Angebots-Flow (Preis + Jetzt/Später) —
## RanchOffer prüft Level/Kaufstand selbst noch einmal (fail-closed).
func _zum_angebot(sheet: PanelSheet) -> void:
	sheet.close()
	sheet.queue_free()
	RanchOffer.zeige(self, _gs)


## ---------------------------------------------------------------- Anzeige


func _ribbon_text(status: String) -> String:
	match status:
		DlcKatalog.STATUS_INSTALLIERT:
			return I18nService.t("dlc.ribbon.installiert")
		DlcKatalog.STATUS_KOMMT_BALD:
			return I18nService.t("dlc.ribbon.bald")
		_:
			return I18nService.t("dlc.ribbon.neu")


func _ribbon_farbe(status: String) -> Color:
	match status:
		DlcKatalog.STATUS_INSTALLIERT:
			return AcTokens.LEAF_DARK
		DlcKatalog.STATUS_KOMMT_BALD:
			return AcTokens.TEAL_DARK
		_:
			return AcTokens.PINK_DARK


## Sanfte Parallax-Neigung: Cover wandern/neigen sich minimal relativ zur
## Bildschirmmitte. Nur bei Scroll-Änderung gerechnet, nie pro Frame.
func _update_parallax(_wert: float) -> void:
	var f := float(_m.get("f", 1.0))
	var canvas: Vector2 = _m.get("canvas", Vector2(get_viewport().get_visible_rect().size))
	if canvas.y <= 0.0:
		return
	for paar: Dictionary in _parallax_cover:
		var rahmen: Control = paar["rahmen"]
		var cover: TextureRect = paar["cover"]
		if not is_instance_valid(rahmen) or not is_instance_valid(cover):
			continue
		var mitte := rahmen.get_global_rect().get_center().y
		var norm := clampf((mitte - canvas.y * 0.5) / (canvas.y * 0.5), -1.0, 1.0)
		cover.position.y = -PARALLAX_POLSTER * f + norm * PARALLAX_HUB * f
		cover.pivot_offset = cover.size * 0.5
		cover.rotation_degrees = norm * PARALLAX_NEIGUNG


func _apply_metrics() -> void:
	if not is_inside_tree():
		return
	_m = ScreenShell.metrics(get_viewport())
	var f := float(_m["f"])
	# Inhaltsspalte W16, Scroll-Ergonomie-Variante: der GANZE Screen scrollt
	# (Scroll = FULL_RECT-Wurzel, volle Wisch-Fläche bleibt) — daher kein
	# content_frame, sondern die Content-VBox im Scroll zentrieren + deckeln.
	# EXPAND-Bit nötig: erst damit gibt der ScrollContainer die volle Breite
	# zum Zentrieren her (SHRINK_CENTER allein = linksbündig, engine-geprüft).
	_rows.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
	_rows.custom_minimum_size.x = ScreenShell.content_width(_m)
	_rows.set_meta(ScreenShell.META_CONTENT_COLUMN, true)
	ScreenShell.scale_fonts(self, f)
	for paar: Dictionary in _parallax_cover:
		var rahmen: Control = paar["rahmen"]
		var cover: TextureRect = paar["cover"]
		rahmen.custom_minimum_size = Vector2(0.0, 240.0 * f)
		cover.offset_top = -PARALLAX_POLSTER * f
		cover.offset_bottom = PARALLAX_POLSTER * f
	_update_parallax(0.0)


func _spieler_level() -> int:
	if _gs == null or not _gs.has_method("get_value"):
		return 1
	return int(_gs.get_value("progression.level", 1))


func _on_karte_input(event: InputEvent, id: String) -> void:
	var tap := event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed
	var klick := (
		event is InputEventMouseButton
		and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT
		and not (event as InputEventMouseButton).pressed
	)
	if tap or klick:
		oeffne_detail(id)


func _on_back_pressed() -> void:
	if not auto_navigate:
		return
	var router := get_node_or_null("/root/SceneRouter")
	if router == null:
		return
	if router.has_method("handle_back_request") and router.handle_back_request():
		return
	if router.has_method("goto"):
		router.goto(&"home/living", {})
