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
## „Gooby arbeitet dran…“-Hinweis mit Hammer-Gag. G5/P24: „Goo und Bye“
## hängt nach demselben Muster dran (GoobyeOffer/GoobyeRouten). Daten: DlcKatalog
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
## Cover-Basis-Höhe (Design-px) und ihr Höhen-Deckel als Canvas-Anteil:
## auf flachen Quer-Canvases (720 px hoch) fräße das volle 240·f-Cover
## (~440 px) 61 % der Höhe — die Namenszeile mit „Ansehen“ lag dadurch
## dauerhaft in der Home-Indicator-Zone (FB3-Befund quer ×2). Muster:
## CustomizeScreen deckelt seine Kacheln in flachen Canvases genauso.
const COVER_BASIS := 240.0
const COVER_MAX_SHARE := 0.35

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
## G4-Nachfix: Polster-Kind im Scroll (vertikale Safe-Insets) + Knopf-Refs
## für die Touch-Floors nach jedem Resize.
var _pad: MarginContainer
var _back: Button
var _ansehen_knoepfe: Array[Button] = []
## Pro Karte: {"rahmen": Control, "cover": TextureRect}.
var _parallax_cover: Array[Dictionary] = []
var _m: Dictionary = {}
## Ruhelage-Pass (s. _ruhelage_sichern): läuft gerade? / nochmal anstoßen?
var _ruhe_pass_aktiv := false
var _ruhe_pass_erneut := false


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
	# G4-Nachfix: der Scroll bleibt bewusst vollflächig (volle Wischfläche),
	# aber das Scroll-KIND polstert oben/unten Notch + Home-Indicator —
	# vorher gab es KEINE vertikalen Ränder („Zurück“ bei y=0 unter der
	# 59-pt-Notch; der letzte „Ansehen“-Knopf lag am Scroll-Ende dauerhaft
	# in der Home-Indicator-Zone). Die Margins setzt _apply_metrics.
	_pad = MarginContainer.new()
	_pad.name = "SafePolster"
	_scroll.add_child(_pad)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 16)
	_pad.add_child(_rows)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	_rows.add_child(header)
	_back = SquishButton.new()
	_back.name = "Zurueck"
	_back.theme_type_variation = &"BtnGhost"
	_back.text = I18nService.t("dlc.zurueck")
	_back.focus_mode = Control.FOCUS_NONE
	_back.pressed.connect(_on_back_pressed)
	header.add_child(_back)
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
	rahmen.custom_minimum_size = Vector2(0.0, COVER_BASIS)
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
	# G4-Nachfix: Referenz für den Touch-Floor-Pass in _apply_metrics
	# (44-pt-Regel — hoch/f=3 waren die Tippflächen nur 41,4 pt).
	_ansehen_knoepfe.append(ansehen)

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
## G5/P24: die Knöpfe kennen jetzt die DLC-Id — die Ranch behält ihre
## Texte/Flows, „Goo und Bye“ hängt sich nach demselben Muster daneben.
func _baue_detail_aktion(sheet: PanelSheet, dlc: Dictionary, box: VBoxContainer) -> void:
	var id := str(dlc.get("id", ""))
	match DlcKatalog.aktion_fuer(dlc, _gs):
		DlcKatalog.AKTION_HOF:
			var los := _aktion_knopf(box, &"BtnLeaf", _spielen_text(id))
			los.pressed.connect(_starte_dlc.bind(sheet, id))
			sheet.set_meta(META_AKTION, los)
		DlcKatalog.AKTION_ANGEBOT:
			var hin := _aktion_knopf(box, &"BtnTeal", _angebot_text(id))
			hin.pressed.connect(_zum_angebot.bind(sheet, id))
			sheet.set_meta(META_AKTION, hin)
		DlcKatalog.AKTION_GESPERRT:
			var zu := _aktion_knopf(box, &"BtnTeal", _angebot_text(id))
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


## Spielen-Knopf-Text je DLC („Losreiten!“ / „Laden aufschließen!“).
func _spielen_text(id: String) -> String:
	if id == "mcgooby":
		# G6/MCGOOBY-B: gekauft = volle Schicht (nicht mehr „Probe“).
		return I18nService.t("dlc_mcgooby.knopf.volle_schicht")
	if id == "goo_und_bye":
		return I18nService.t("dlc_goobye.knopf.zum_laden")
	return I18nService.t("dlc.knopf.losreiten")


## Angebots-Knopf-Text je DLC („Zur Ranch“ / „Schlüssel ansehen“).
func _angebot_text(id: String) -> String:
	if id == "mcgooby":
		# G6/MCGOOBY-B: der Weg zum Angebot IST die freie Probeschicht.
		return I18nService.t("dlc_mcgooby.knopf.schicht")
	if id == "goo_und_bye":
		return I18nService.t("dlc_goobye.knopf.angebot")
	return I18nService.t("dlc.knopf.zur_ranch")


## Installiert → direkt ins DLC (Routen registrieren die DLCs selbst).
func _starte_dlc(sheet: PanelSheet, id: String) -> void:
	sheet.close()
	sheet.queue_free()
	if not auto_navigate:
		return
	if id == "mcgooby":
		McGoobyRouten.fahre_zur_schicht(get_tree())
		return
	if id == "goo_und_bye":
		GoobyeRouten.fahre_zum_laden(get_tree())
	else:
		RanchRouten.fahre_zum_hof(get_tree())


## Verfügbar → der jeweilige Angebots-Flow (Preis + Jetzt/Später) —
## Ranch-/GoobyeOffer prüfen Level/Kaufstand selbst noch einmal
## (fail-closed). G6/MCGOOBY-B: McGooby führt stattdessen in die FREIE
## Probeschicht — das Kauf-Angebot kommt dort nach der Schicht
## („Schicht geschafft → Angebot“, Doc §6.2).
func _zum_angebot(sheet: PanelSheet, id: String) -> void:
	sheet.close()
	sheet.queue_free()
	if id == "mcgooby":
		if auto_navigate:
			McGoobyRouten.fahre_zur_schicht(get_tree())
		return
	if id == "goo_und_bye":
		GoobyeOffer.zeige(self, _gs)
	else:
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
	var canvas: Vector2 = _m["canvas"]
	var insets: Dictionary = _m["insets"]
	# Inhaltsspalte W16, Scroll-Ergonomie-Variante: der GANZE Screen scrollt
	# (Scroll = FULL_RECT-Wurzel, volle Wisch-Fläche bleibt) — daher kein
	# content_frame, sondern das Scroll-Kind zentrieren + deckeln.
	# EXPAND-Bit nötig: erst damit gibt der ScrollContainer die volle Breite
	# zum Zentrieren her (SHRINK_CENTER allein = linksbündig, engine-geprüft).
	_pad.size_flags_horizontal = Control.SIZE_EXPAND | Control.SIZE_SHRINK_CENTER
	# G4-Nachfix: vertikale Ränder = Safe-Insets + EDGE_Y im Polster-Kind —
	# oben Notch-Schutz, unten hebt das Content-Padding den letzten
	# „Ansehen“-Knopf am Scroll-Ende über den Home-Indicator (Padding statt
	# Scroll-Deckel: gescrollt läuft der Inhalt weiter vollflächig durch).
	_pad.add_theme_constant_override(
		"margin_top", roundi(float(insets["top"]) + ScreenShell.EDGE_Y * f)
	)
	_pad.add_theme_constant_override(
		"margin_bottom", roundi(float(insets["bottom"]) + ScreenShell.EDGE_Y * f)
	)
	_rows.custom_minimum_size.x = ScreenShell.content_width(_m)
	_rows.set_meta(ScreenShell.META_CONTENT_COLUMN, true)
	# G4-Nachfix: Zurück + alle „Ansehen“ auf den physischen Touch-Floor.
	ScreenShell.touch_target(_back, _m)
	for knopf in _ansehen_knoepfe:
		ScreenShell.touch_target(knopf, _m)
	ScreenShell.scale_fonts(self, f)
	# Cover-Höhe: 240·f, auf flachen Canvases per COVER_MAX_SHARE gedeckelt
	# (s. Konstanten-Kommentar) — hoch/ipad bleiben unverändert.
	var cover_h := minf(COVER_BASIS * f, canvas.y * COVER_MAX_SHARE)
	for paar: Dictionary in _parallax_cover:
		var rahmen: Control = paar["rahmen"]
		var cover: TextureRect = paar["cover"]
		rahmen.custom_minimum_size = Vector2(0.0, cover_h)
		cover.offset_top = -PARALLAX_POLSTER * f
		cover.offset_bottom = PARALLAX_POLSTER * f
	_update_parallax(0.0)
	# Ruhelage sichern, sobald das frische Layout steht (deferred, damit
	# die Container-Sortierung und die Font-Overrides schon gelandet sind).
	call_deferred("_ruhelage_sichern")


## G4-Nachfix: Ruhelage-Sicherung. Bei Scroll-Position 0 darf KEINE
## „Ansehen“-Zeile in der Home-Indicator-Zone liegen — die Karten-Höhen
## sind aber inhaltsabhängig (Teaser-Längen), also wird nicht geraten,
## sondern gemessen: liegt eine Zeile in Ruhe in der Zone, wächst das
## Cover IHRER Karte, bis die Zeile unter der Falte liegt (gescrollte
## Inhalte sind laut Audit-Klipp-Regel kein Safe-Area-Verstoß; die volle
## Wischfläche und das Unter-dem-Indicator-Durchlaufen bleiben erhalten).
func _ruhelage_sichern() -> void:
	if _ruhe_pass_aktiv:
		_ruhe_pass_erneut = true
		return
	_ruhe_pass_aktiv = true
	# Über ein kleines Frame-Budget messen: die Font-Overrides aus
	# scale_fonts propagieren DEFERRED (THEME_CHANGED) und schieben die
	# Karten-Zeilen erst 1–2 Frames später auf ihre ECHTE Ruhelage — eine
	# Einzelmessung im Bau-Frame sähe veraltete (zu hohe) Positionen.
	# Fertig, wenn zwei Messungen in Folge sauber sind.
	var sauber := 0
	for _versuch in 8:
		if not is_inside_tree():
			break
		await get_tree().process_frame
		if not is_inside_tree():
			break
		if _hebe_ruhe_kollision():
			sauber = 0
		else:
			sauber += 1
			if sauber >= 2:
				break
	_ruhe_pass_aktiv = false
	if _ruhe_pass_erneut:
		_ruhe_pass_erneut = false
		if is_inside_tree():
			call_deferred("_ruhelage_sichern")


## Eine Ruhelage-Kollision anheben (true = etwas geändert, nochmal messen).
func _hebe_ruhe_kollision() -> bool:
	if _m.is_empty() or _ansehen_knoepfe.size() > _parallax_cover.size():
		return false
	var canvas: Vector2 = _m["canvas"]
	var insets: Dictionary = _m["insets"]
	if float(insets["bottom"]) <= 0.0:
		return false
	var zone_ab := canvas.y - float(insets["bottom"]) - 2.0
	var scroll_y := _scroll.get_global_rect().position.y
	for i in _ansehen_knoepfe.size():
		var rect := _ansehen_knoepfe[i].get_global_rect()
		var ruhe_y := rect.position.y - scroll_y + float(_scroll.scroll_vertical)
		if ruhe_y >= canvas.y or ruhe_y + rect.size.y <= zone_ab:
			continue
		var rahmen := _parallax_cover[i]["rahmen"] as Control
		rahmen.custom_minimum_size.y += canvas.y - ruhe_y + 2.0
		return true
	return false


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
