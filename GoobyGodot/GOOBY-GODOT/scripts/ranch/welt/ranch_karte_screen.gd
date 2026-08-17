class_name RanchKarteScreen
extends Control
## Entdecker-Karte der Ranch (W19) — der Sammelspaß-Screen zur offenen
## Ranch-Region: 2D-Stilisierung aus den RanchKarte-Daten (handgezeichneter
## Look aus Shapes im Gooby-Pastell), bereiste Zonen farbig mit Namen,
## unbereiste als Nebel-„?“, alle Fundorte als Pins (entdeckt = Stern +
## Detail-Karte, unentdeckt = „?“-Pin an GROBER Position), Fortschritts-
## Kopf und „NEU“-Badges bis zum ersten Ansehen. ALLE Daten kommen aus
## RanchEntdeckerKarte (PURE) — dieser Screen ist nur Verdrahtung.
##
## Router-Contract (W1a): `ready_for_reveal` nach dem Aufbau;
## `receive_params({"spieler": [x, z]})` setzt den „Du bist hier“-Punkt.
## Tests injizieren `game_state_override` VOR add_child.

signal ready_for_reveal

## Eigene Spalten-Basis (Muster AlbumScreen): die Karte braucht mehr Luft
## als die 660er-Listen-Spalte, bleibt aber zentriert + gedeckelt (W16).
const SPALTE_BASIS := 880.0
## Einfacher Touch-Zoom über Stufen-Knöpfe (+/−); Scrollen übernimmt der
## ScrollContainer (Touch-Drag).
const ZOOM_STUFEN: Array[float] = [1.0, 1.5, 2.1]

## Tests: Navigation abschaltbar (kein echter Router-Travel im Runner).
var auto_navigate := true
var game_state_override: Object

var _modell: Dictionary = {}
var _spieler := Vector2.INF
var _f := 1.0
var _zoom_index := 0
var _rows: VBoxContainer
var _titel: Label
var _fortschritt_label: Label
var _back: Button
var _zoom_rein: Button
var _zoom_raus: Button
var _scroll: ScrollContainer
var _canvas: Control
var _pins: Dictionary = {}
var _sheet: PanelSheet


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ThemeService.theme()
	_modell = RanchEntdeckerKarte.modell(game_state())
	_build_ui()
	_apply_metrics()
	FocusNavigation.wire(self)
	_back.call_deferred("grab_focus")
	get_viewport().size_changed.connect(_on_resized)
	# Erst-Ansehen buchen (genau-einmal): die Badges zeigen JETZT noch,
	# beim nächsten Öffnen gelten die Funde als gesehen.
	_markiere_gesehen.call_deferred()
	ready_for_reveal.emit()


## Router-Params (W1a-Contract): Spielerposition für „Du bist hier“.
func receive_params(params: Dictionary) -> void:
	var roh: Variant = params.get("spieler")
	if roh is Array and (roh as Array).size() >= 2:
		_spieler = Vector2(float(roh[0]), float(roh[1]))


func game_state() -> Object:
	if game_state_override != null:
		return game_state_override
	return get_node_or_null("/root/GameState")


## Fortschritts-Zeile (Tests lesen hier mit).
func fortschritt_text() -> String:
	return _fortschritt_label.text


func pins() -> Dictionary:
	return _pins


## ---------------------------------------------------------------- Aufbau


func _build_ui() -> void:
	add_child(AcWallpaper.for_context("ranch"))
	_rows = VBoxContainer.new()
	_rows.name = "Zeilen"
	_rows.add_theme_constant_override("separation", 8)
	add_child(_rows)
	_rows.add_child(_build_header())
	_fortschritt_label = Label.new()
	_fortschritt_label.name = "Fortschritt"
	_fortschritt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_fortschritt_label.add_theme_color_override("font_color", AcTokens.INK_SOFT)
	_fortschritt_label.add_theme_font_size_override("font_size", AcTokens.FONT_SIZE_CAPTION)
	_fortschritt_label.text = _fortschritt_zeile()
	_rows.add_child(_fortschritt_label)
	_rows.add_child(_build_karte())
	_baue_pins()
	_sheet = (load("res://scripts/ui/panel_sheet.tscn") as PackedScene).instantiate()
	add_child(_sheet)


func _build_header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.name = "Kopf"
	header.add_theme_constant_override("separation", 8)
	_back = SquishButton.new()
	_back.name = "Zurueck"
	_back.theme_type_variation = "GhostButton"
	_back.text = I18nService.t("rkarte.zurueck")
	_back.focus_mode = Control.FOCUS_ALL
	_back.pressed.connect(_on_zurueck)
	header.add_child(_back)
	_titel = Label.new()
	_titel.theme_type_variation = "TitleLabel"
	_titel.text = I18nService.t("rkarte.titel")
	_titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_titel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(_titel)
	_zoom_raus = SquishButton.new()
	_zoom_raus.name = "ZoomRaus"
	_zoom_raus.theme_type_variation = "GhostButton"
	_zoom_raus.text = "−"
	_zoom_raus.tooltip_text = I18nService.t("rkarte.zoom_raus")
	_zoom_raus.focus_mode = Control.FOCUS_ALL
	_zoom_raus.pressed.connect(_on_zoom.bind(-1))
	header.add_child(_zoom_raus)
	_zoom_rein = SquishButton.new()
	_zoom_rein.name = "ZoomRein"
	_zoom_rein.theme_type_variation = "GhostButton"
	_zoom_rein.text = "+"
	_zoom_rein.tooltip_text = I18nService.t("rkarte.zoom_rein")
	_zoom_rein.focus_mode = Control.FOCUS_ALL
	_zoom_rein.pressed.connect(_on_zoom.bind(1))
	header.add_child(_zoom_rein)
	return header


func _build_karte() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "KartenPanel"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = AcTokens.PAPER
	sb.set_corner_radius_all(AcTokens.RADIUS_CARD)
	sb.set_content_margin_all(8.0)
	sb.border_color = AcTokens.OUTLINE_SOFT
	sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", sb)
	_scroll = ScrollContainer.new()
	_scroll.name = "KartenScroll"
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.resized.connect(_layout_karte)
	panel.add_child(_scroll)
	var flaeche := KartenFlaeche.new()
	flaeche.name = "KartenFlaeche"
	flaeche.modell = _modell
	flaeche.spieler = _spieler
	flaeche.mouse_filter = Control.MOUSE_FILTER_PASS
	flaeche.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	flaeche.size_flags_vertical = Control.SIZE_EXPAND_FILL
	# Der ScrollContainer layoutet die Fläche erst NACH _layout_karte neu
	# (z. B. wenn Scrollbalken beim Zoomen erscheinen/verschwinden) — die
	# Pins müssen der endgültigen Größe folgen, sonst kleben sie daneben.
	flaeche.resized.connect(_positioniere_pins, CONNECT_DEFERRED)
	_canvas = flaeche
	_scroll.add_child(flaeche)
	return panel


## Fundort-Pins als Touch-Knöpfe über der Kartenfläche (entdeckt = Stern
## auf Gold, unentdeckt = „?“ auf Papier an GROBER Position).
func _baue_pins() -> void:
	for fund: Dictionary in _modell["fundorte"]:
		var id := str(fund["id"])
		var knopf := SquishButton.new()
		knopf.name = "Pin_%s" % id
		knopf.focus_mode = Control.FOCUS_ALL
		knopf.text = "★" if bool(fund["entdeckt"]) else "?"
		knopf.tooltip_text = (
			I18nService.t(str(fund["name_key"]))
			if bool(fund["entdeckt"])
			else I18nService.t("rkarte.unbekannt")
		)
		_stil_pin(knopf, bool(fund["entdeckt"]))
		knopf.pressed.connect(_on_pin.bind(id))
		_canvas.add_child(knopf)
		_pins[id] = knopf
		if bool(fund["neu"]):
			knopf.add_child(_baue_badge())


func _stil_pin(knopf: Button, entdeckt: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = AcTokens.GOLD if entdeckt else AcTokens.PAPER
	sb.set_corner_radius_all(AcTokens.RADIUS_PILL)
	sb.border_color = AcTokens.lip_color(sb.bg_color)
	sb.set_border_width_all(2)
	for zustand: String in ["normal", "hover", "pressed"]:
		knopf.add_theme_stylebox_override(zustand, sb)
	var fokus := sb.duplicate() as StyleBoxFlat
	fokus.border_color = AcTokens.TEAL_DARK
	fokus.set_border_width_all(4)
	knopf.add_theme_stylebox_override("focus", fokus)
	var tinte := AcTokens.INK if entdeckt else AcTokens.INK_SOFT
	for farb_key: String in ["font_color", "font_hover_color", "font_pressed_color"]:
		knopf.add_theme_color_override(farb_key, tinte)


func _baue_badge() -> Label:
	var badge := Label.new()
	badge.name = "Neu"
	badge.text = I18nService.t("rkarte.neu")
	badge.add_theme_color_override("font_color", AcTokens.WHITE)
	badge.add_theme_font_size_override("font_size", 11)
	var sb := StyleBoxFlat.new()
	sb.bg_color = AcTokens.PINK
	sb.set_corner_radius_all(AcTokens.RADIUS_PILL)
	sb.content_margin_left = 6.0
	sb.content_margin_right = 6.0
	sb.content_margin_top = 1.0
	sb.content_margin_bottom = 1.0
	badge.add_theme_stylebox_override("normal", sb)
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return badge


## ---------------------------------------------------------------- Layout


func _on_resized() -> void:
	if not is_inside_tree():
		return
	_apply_metrics()


func _apply_metrics() -> void:
	var m := ScreenShell.metrics(get_viewport())
	_f = m["f"]
	ScreenShell.content_frame(_rows, m, SPALTE_BASIS)
	for knopf: Control in [_back, _zoom_raus, _zoom_rein]:
		knopf.custom_minimum_size = Vector2.ZERO
		ScreenShell.touch_target(knopf, m)
	ScreenShell.scale_fonts(self, _f)
	_layout_karte()


## Karte in die verfügbare Fläche einpassen (Zoom 1 = alles sichtbar);
## höhere Stufen scrollen im ScrollContainer (Touch-Drag).
func _layout_karte() -> void:
	if _scroll == null or _modell.is_empty():
		return
	var innen := _scroll.size
	if innen.x <= 1.0 or innen.y <= 1.0:
		return
	var grenzen: Rect2 = _modell["grenzen"]
	var zoom: float = ZOOM_STUFEN[_zoom_index]
	var skala := minf(innen.x / grenzen.size.x, innen.y / grenzen.size.y) * zoom
	var flaeche := _canvas as KartenFlaeche
	flaeche.px_pro_meter = skala
	flaeche.faktor = _f
	flaeche.custom_minimum_size = grenzen.size * skala
	flaeche.queue_redraw()
	_positioniere_pins.call_deferred()


func _positioniere_pins() -> void:
	if _canvas == null or not is_inside_tree():
		return
	var m := ScreenShell.metrics(get_viewport())
	var kante := maxf(44.0 * _f, float(m["floor_px"]))
	var flaeche := _canvas as KartenFlaeche
	for fund: Dictionary in _modell["fundorte"]:
		var knopf: Button = _pins.get(str(fund["id"]))
		if knopf == null:
			continue
		knopf.size = Vector2(kante, kante)
		knopf.position = flaeche.welt_zu_px(fund["zeig_pos"]) - knopf.size / 2.0
		var badge := knopf.get_node_or_null("Neu") as Label
		if badge != null:
			badge.position = Vector2(kante - badge.size.x * 0.5, -badge.size.y * 0.35)


## --------------------------------------------------------------- Laufzeit


func _fortschritt_zeile() -> String:
	var fortschritt: Dictionary = _modell["fortschritt"]
	return (
		I18nService
		. t(
			"rkarte.fortschritt",
			{
				"funde": str(int(fortschritt["funde"])),
				"funde_gesamt": str(int(fortschritt["funde_gesamt"])),
				"zonen": str(int(fortschritt["zonen"])),
				"zonen_gesamt": str(int(fortschritt["zonen_gesamt"])),
			}
		)
	)


## Alle aktuell entdeckten Funde als „auf der Karte gesehen“ buchen.
func _markiere_gesehen() -> void:
	var ids: Array[String] = []
	for fund: Dictionary in _modell["fundorte"]:
		if bool(fund["entdeckt"]):
			ids.append(str(fund["id"]))
	RanchEntdeckerKarte.markiere_funde_gesehen(game_state(), ids)


func _on_zoom(schritt: int) -> void:
	var neu := clampi(_zoom_index + schritt, 0, ZOOM_STUFEN.size() - 1)
	if neu == _zoom_index:
		return
	_zoom_index = neu
	_layout_karte()


## Pin angetippt: Detail-Karte (Name, warme Beschreibung, „Dahin!“-Hinweis
## — nur Richtungstext, kein Teleport). Entdeckte verlieren ihr NEU-Badge.
func _on_pin(id: String) -> void:
	var fund := _fund(id)
	if fund.is_empty():
		return
	_zeige_detail(fund)
	if bool(fund["entdeckt"]):
		RanchEntdeckerKarte.markiere_funde_gesehen(game_state(), [id])
		var knopf: Button = _pins.get(id)
		var badge: Node = null if knopf == null else knopf.get_node_or_null("Neu")
		if badge != null:
			badge.queue_free()


func _fund(id: String) -> Dictionary:
	for fund: Dictionary in _modell["fundorte"]:
		if str(fund["id"]) == id:
			return fund
	return {}


func _zeige_detail(fund: Dictionary) -> void:
	var entdeckt := bool(fund["entdeckt"])
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(10.0 * _f))
	var beschreibung := Label.new()
	beschreibung.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	beschreibung.text = (
		I18nService.t("rkarte.beschr.%s" % fund["id"])
		if entdeckt
		else I18nService.t("rkarte.geheimnis")
	)
	box.add_child(beschreibung)
	var dahin := Label.new()
	dahin.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dahin.add_theme_color_override("font_color", AcTokens.INK_SOFT)
	dahin.text = _dahin_text(fund)
	box.add_child(dahin)
	var ok := SquishButton.new()
	ok.theme_type_variation = "PrimaryButton"
	ok.text = I18nService.t("rkarte.schliessen")
	ok.focus_mode = Control.FOCUS_ALL
	ok.pressed.connect(_sheet.close)
	box.add_child(ok)
	_sheet.set_title(I18nService.t(str(fund["name_key"])) if entdeckt else _unbekannt_titel())
	_sheet.add_content(box)
	_sheet.open()
	FocusNavigation.grab_first_deferred(box)


func _unbekannt_titel() -> String:
	return I18nService.t("rkarte.unbekannt")


## „Dahin!“-Hinweis vom Zuhause (Hof-Spawn) aus — bei unentdeckten Orten
## bewusst nur die GROBE Richtung.
func _dahin_text(fund: Dictionary) -> String:
	var ziel: Vector2 = fund["zeig_pos"]
	var zone_id := RanchEntdeckerKarte.hinweis_zone(fund["pos"] if bool(fund["entdeckt"]) else ziel)
	var zonen_name := I18nService.t("rwelt.zone.%s" % zone_id)
	var richtung := RanchEntdeckerKarte.richtung_key(RanchEntdeckerKarte.heimat_punkt(), ziel)
	if richtung.is_empty():
		return I18nService.t("rkarte.dahin_nah", {"zone": zonen_name})
	return I18nService.t(
		"rkarte.dahin",
		{"richtung": I18nService.t("rkarte.richtung.%s" % richtung), "zone": zonen_name}
	)


func _on_zurueck() -> void:
	if not auto_navigate:
		return
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("handle_back_request"):
		if router.handle_back_request():
			return
	RanchRouten.fahre_zum_hof(get_tree())


## Die gezeichnete Kartenfläche (Muster CityMinimap): alles in _draw —
## kein Viewport, keine zweite Kamera; Pins liegen als Kinder obendrauf.
class KartenFlaeche:
	extends Control

	const WASSER := Color("#9AD3EA")
	const WEG := Color(0.2902, 0.2314, 0.2118, 0.28)

	var modell: Dictionary = {}
	var px_pro_meter := 1.0
	var faktor := 1.0
	var spieler := Vector2.INF

	func _init() -> void:
		resized.connect(queue_redraw)

	## Welt-XZ → Pixel auf der (zentrierten) Kartenfläche.
	func welt_zu_px(welt: Vector2) -> Vector2:
		var grenzen: Rect2 = modell.get("grenzen", Rect2())
		var karte_px := grenzen.size * px_pro_meter
		var versatz := ((size - karte_px) / 2.0).max(Vector2.ZERO)
		return versatz + (welt - grenzen.position) * px_pro_meter

	func _draw() -> void:
		if modell.is_empty():
			return
		_zeichne_pergament()
		for zone: Dictionary in modell["zonen"]:
			_zeichne_zone(zone)
		for weg: Dictionary in modell["wege"]:
			_zeichne_weg(weg)
		_zeichne_bach()
		for zone: Dictionary in modell["zonen"]:
			_zeichne_wasser(zone)
		_zeichne_spieler()

	func _zeichne_pergament() -> void:
		var grenzen: Rect2 = modell["grenzen"]
		var rect := Rect2(welt_zu_px(grenzen.position), grenzen.size * px_pro_meter)
		_runde_flaeche(rect, AcTokens.PAPER_SHADE, 16.0 * faktor)

	func _zeichne_zone(zone: Dictionary) -> void:
		var rect_w: Rect2 = zone["rect"]
		var rect := Rect2(welt_zu_px(rect_w.position), rect_w.size * px_pro_meter)
		var entdeckt := bool(zone["entdeckt"])
		var farbe: Color = zone["farbe"] if entdeckt else RanchEntdeckerKarte.FOG_FARBE
		_runde_flaeche(rect, farbe, 10.0 * faktor)
		var font := get_theme_default_font()
		var groesse := int(maxf(12.0, 13.0 * faktor))
		var text := (
			I18nService.t(str(zone["name_key"])) if entdeckt else I18nService.t("rkarte.unbekannt")
		)
		var tinte := AcTokens.INK if entdeckt else AcTokens.INK_FAINT
		var pos := rect.position + Vector2(0.0, rect.size.y / 2.0 + float(groesse) / 2.0)
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_CENTER, rect.size.x, groesse, tinte)

	func _zeichne_weg(weg: Dictionary) -> void:
		if not bool(weg["bekannt"]):
			return
		var punkte: Array[Vector2] = weg["punkte"]
		for i in punkte.size() - 1:
			draw_line(welt_zu_px(punkte[i]), welt_zu_px(punkte[i + 1]), WEG, 3.0 * faktor)

	func _zeichne_bach() -> void:
		var punkte: Array[Vector2] = modell["bach"]
		for i in punkte.size() - 1:
			draw_line(welt_zu_px(punkte[i]), welt_zu_px(punkte[i + 1]), WASSER, 4.0 * faktor)

	func _zeichne_wasser(zone: Dictionary) -> void:
		if not bool(zone["entdeckt"]):
			return
		for kreis: Dictionary in zone["wasser"]:
			var mitte: Vector2 = kreis["mitte"]
			draw_circle(welt_zu_px(mitte), float(kreis["radius"]) * px_pro_meter, WASSER)

	func _zeichne_spieler() -> void:
		if spieler == Vector2.INF:
			return
		var mitte := welt_zu_px(spieler)
		draw_circle(mitte, 7.0 * faktor, AcTokens.WHITE)
		draw_circle(mitte, 5.0 * faktor, AcTokens.PINK)

	func _runde_flaeche(rect: Rect2, farbe: Color, radius: float) -> void:
		var sb := StyleBoxFlat.new()
		sb.bg_color = farbe
		sb.set_corner_radius_all(int(radius))
		sb.draw(get_canvas_item(), rect)
