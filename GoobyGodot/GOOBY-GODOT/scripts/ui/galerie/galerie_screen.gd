class_name GalerieScreen
extends Control
## Vollständige Fotogalerie (REST-4, EVAL Rang 14): Raster mit
## Vorschaubildern (city.fotos aus dem FotoModus), Vollansicht mit Zoom
## (Knöpfe + Mausrad, Pan über den Scroll-Container), Favoriten
## (additives fav-Flag), Löschen mit Nachfrage (Index + PNG-Datei),
## Datum/Ort-Anzeige, echter Foto-Export (FERTIG-1: in den Bilder-Ordner
## des Systems) und Speicheranzeige (n von 40 Plätzen). Route `galerie` —
## erreichbar aus der Kamera-App des IGohbie.

signal ready_for_reveal

const ROUTE := &"galerie"
const ROUTES := {ROUTE: "res://scripts/ui/galerie/galerie_screen.tscn"}
const ZOOM_STUFEN: Array[float] = [1.0, 1.5, 2.0, 3.0, 4.0]

## Tests/Screenshots: GameState-Double statt /root/GameState.
var gs_override: Object = null
## Tests: Navigation abschaltbar.
var auto_navigate := true
## Aktueller Filter (false = alle, true = nur Favoriten).
var nur_favoriten := false

var _gs: Object = null
var _rows: VBoxContainer
var _grid: GridContainer
## G4-Nachfix: Kopfzeilen-Teile für den bedarfsbasierten Umbruch
## (_layout_header) — der Speicher-Chip wandert auf schmalen Spalten in
## die eigene Zeile.
var _header: HBoxContainer
var _titel: Label
var _speicher_chip: PanelContainer
var _chip_zeile: HBoxContainer
var _speicher_label: Label
var _back_btn: Button
var _filter_btn: Button
var _leer_label: Label
var _toasts: ToastLayer
var _voll: Control
var _voll_pfad := ""
var _voll_zoom := 0
var _voll_rect: TextureRect
var _voll_scroll: ScrollContainer
var _voll_fav_btn: Button
## G3: Vollansichts-Spalte + Knopfleiste — für die Safe-Area-Rahmung und
## die Touch-Floors auch nach Rotation/Resize (Metrics-Hook).
var _voll_spalte: VBoxContainer
var _voll_leiste: Container
var _bestaetigung: PanelContainer
var _m: Dictionary = {}
var _thumb_cache: Dictionary = {}


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
	_refresh()
	ready_for_reveal.emit()


## ---------------------------------------------------------------- Test-API


func fotos_im_raster() -> int:
	var count := 0
	for kind in _grid.get_children():
		if kind is Button:
			count += 1
	return count


func oeffne_vollansicht(pfad: String) -> void:
	_zeige_vollansicht(pfad)


func vollansicht_offen() -> bool:
	return _voll != null and is_instance_valid(_voll) and _voll.visible


## ---------------------------------------------------------------- Aufbau


func _build_ui() -> void:
	# W21/P3 (d): Album-Stimmung — die Foto-Galerie gehört zur
	# Erinnerungs-Familie (Honig-Wash + Album-Kacheln), nicht zu Cream.
	var wallpaper := AcWallpaper.for_context("album")
	add_child(wallpaper)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 12)
	add_child(_rows)

	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", 12)
	_rows.add_child(_header)
	var back := SquishButton.new()
	back.name = "Zurueck"
	back.theme_type_variation = &"BtnGhost"
	back.text = I18nService.t("galerie.zurueck")
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(_on_back_pressed)
	_header.add_child(back)
	_back_btn = back
	_titel = Label.new()
	_titel.theme_type_variation = &"TitleLabel"
	_titel.text = I18nService.t("galerie.titel")
	_titel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_titel.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_header.add_child(_titel)
	_speicher_chip = PanelContainer.new()
	_speicher_chip.theme_type_variation = &"StatusCapsule"
	_speicher_label = Label.new()
	_speicher_label.name = "Speicher"
	_speicher_label.theme_type_variation = &"SoftLabel"
	_speicher_chip.add_child(_speicher_label)
	_header.add_child(_speicher_chip)
	# G4-Nachfix: Ausweich-Zeile für den Speicher-Chip (Kopfzeilen-Umbruch,
	# s. _layout_header) — leer und unsichtbar, solange die Kopfzeile passt.
	_chip_zeile = HBoxContainer.new()
	_chip_zeile.name = "KopfExtras"
	_chip_zeile.visible = false
	_rows.add_child(_chip_zeile)

	_filter_btn = SquishButton.new()
	_filter_btn.name = "Filter"
	_filter_btn.theme_type_variation = &"AcChip"
	_filter_btn.focus_mode = Control.FOCUS_NONE
	_filter_btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_filter_btn.pressed.connect(_on_filter_pressed)
	_rows.add_child(_filter_btn)

	_leer_label = Label.new()
	_leer_label.name = "LeerHinweis"
	_leer_label.theme_type_variation = &"SoftLabel"
	_leer_label.text = I18nService.t("galerie.leer")
	_leer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_rows.add_child(_leer_label)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.scroll_deadzone = 24
	_rows.add_child(scroll)
	_grid = GridContainer.new()
	_grid.name = "FotoRaster"
	_grid.columns = 3
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(_grid)

	_toasts = ToastLayer.new()
	add_child(_toasts)
	_toasts.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _apply_metrics() -> void:
	if not is_inside_tree():
		return
	_m = ScreenShell.metrics(get_viewport())
	# Inhaltsspalte W16: zentriert + breiten-gedeckelt statt voller Safe-Breite.
	ScreenShell.content_frame(_rows, _m)
	ScreenShell.scale_fonts(self, float(_m["f"]))
	# Spaltenzahl aus der SPALTEN-Breite (vorher volle Canvas-Breite) —
	# sonst überliefe das Foto-Raster die zentrierte Spalte.
	var spalte := ScreenShell.content_width(_m)
	_grid.columns = clampi(int(spalte / (240.0 * float(_m["f"]))), 2, 5)
	# G4-Nachfix: Kachelgröße in die Spalte einpassen — 2 Kacheln à 200·f
	# (+Separation) überschritten auf hoch/f=3 die Klemme (1212 px > 1136)
	# und drückten die Spalte auf (Min-Breiten-Falle G2 §4.4).
	var kachel := _kachel_groesse()
	for kind in _grid.get_children():
		if kind is Control:
			(kind as Control).custom_minimum_size = kachel
	# G3 (HOCH-Fix ui-profil §5): Tippflächen auf den physischen Floor —
	# vorher hatte der Screen keinen einzigen touch_target-Aufruf.
	ScreenShell.touch_target(_back_btn, _m)
	ScreenShell.touch_target(_filter_btn, _m)
	_layout_header()
	# Font-Overrides aus scale_fonts propagieren DEFERRED (THEME_CHANGED) —
	# bereits geshapte Labels melden im selben Frame noch ALTE Minbreiten.
	# Ein nachgezogener Pass misst nach dem Flush die echten Werte.
	call_deferred("_layout_header")
	_rahme_vollansicht()


## G4-Nachfix: Kopfzeilen-Umbruch. Der Speicher-Chip wandert in die eigene
## Zeile darunter, sobald Zurück + Titel + Chip zusammen mehr Minbreite
## verlangen, als die Spalte hergibt — die Min-Breiten-Falle drückte sonst
## die GANZE Spalte auf (hoch/f=3: 1322 px > 1136er-Klemme, Zentrum −93 px).
func _layout_header() -> void:
	if _m.is_empty():
		return
	var sep := float(_header.get_theme_constant("separation"))
	var noetig := (
		_back_btn.get_combined_minimum_size().x
		+ _titel.get_combined_minimum_size().x
		+ _speicher_chip.get_combined_minimum_size().x
		+ 2.0 * sep
	)
	var unten := noetig > ScreenShell.content_width(_m)
	if unten != (_speicher_chip.get_parent() == _chip_zeile):
		_speicher_chip.get_parent().remove_child(_speicher_chip)
		(_chip_zeile if unten else _header).add_child(_speicher_chip)
	_chip_zeile.visible = unten


## G4-Nachfix: Kachelbreite = 200·f, aber nie breiter, als dass `columns`
## Kacheln (+ Separation) in die Inhaltsspalte passen; Seitenverhältnis
## 4:3 bleibt erhalten.
func _kachel_groesse() -> Vector2:
	if _m.is_empty():
		return Vector2(200.0, 150.0)
	var f := float(_m["f"])
	var spalte := ScreenShell.content_width(_m)
	var sep := float(_grid.get_theme_constant("h_separation"))
	var cols := maxi(_grid.columns, 1)
	var breite := minf(AcTokens.px(200.0, f), (spalte - sep * float(cols - 1)) / float(cols))
	return Vector2(breite, breite * 0.75)


## ---------------------------------------------------------------- Raster


func _refresh() -> void:
	var state := _state()
	var speicher := GalerieLogic.speicher(state)
	_speicher_label.text = I18nService.t(
		"galerie.speicher", {"n": int(speicher["n"]), "max": int(speicher["max"])}
	)
	_filter_btn.text = I18nService.t("galerie.alle" if nur_favoriten else "galerie.nur_favoriten")
	for kind in _grid.get_children():
		_grid.remove_child(kind)
		kind.queue_free()
	var fotos := GalerieLogic.fotos_von(state)
	if nur_favoriten:
		fotos = GalerieLogic.favoriten(fotos)
	_leer_label.visible = fotos.is_empty()
	for foto: Dictionary in fotos:
		_grid.add_child(_thumb(foto))
	# G4-Nachfix: der Kopf-Umbruch rechnet mit der ECHTEN Chip-Breite des
	# frischen Speicher-Texts (n/max ändert die Label-Minbreite); der
	# deferred Pass fängt die verzögerten Font-Overrides (s. _apply_metrics).
	_layout_header()
	call_deferred("_layout_header")


func _thumb(foto: Dictionary) -> Control:
	var pfad := str(foto["pfad"])
	var karte := Button.new()
	karte.name = "Foto_%s" % pfad.get_file().get_basename()
	karte.theme_type_variation = &"AcCard"
	# G4-Nachfix: 200·f, aber in die Spalte geklemmt (s. _kachel_groesse).
	karte.custom_minimum_size = _kachel_groesse()
	karte.focus_mode = Control.FOCUS_NONE
	karte.clip_contents = true
	karte.pressed.connect(_zeige_vollansicht.bind(pfad))
	var tex := _lade_textur(pfad)
	if tex != null:
		var rect := TextureRect.new()
		rect.texture = tex
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		rect.set_anchors_preset(Control.PRESET_FULL_RECT)
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		karte.add_child(rect)
	else:
		var kaputt := Label.new()
		kaputt.text = I18nService.t("galerie.fehler_laden")
		kaputt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		kaputt.set_anchors_preset(Control.PRESET_FULL_RECT)
		kaputt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		kaputt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		kaputt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		karte.add_child(kaputt)
	if bool(foto.get("fav", false)):
		var fav := PanelContainer.new()
		fav.theme_type_variation = &"StatusCapsule"
		fav.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var fav_label := Label.new()
		fav_label.text = I18nService.t("galerie.favorit")
		fav_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		fav.add_child(fav_label)
		fav.set_anchors_preset(Control.PRESET_TOP_LEFT)
		fav.offset_left = 6.0
		fav.offset_top = 6.0
		karte.add_child(fav)
	return karte


## ---------------------------------------------------------------- Vollansicht


func _zeige_vollansicht(pfad: String) -> void:
	_schliesse_vollansicht()
	_voll_pfad = pfad
	_voll_zoom = 0
	_voll = Control.new()
	_voll.name = "Vollansicht"
	_voll.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_voll)
	var abdunkler := ColorRect.new()
	abdunkler.color = Color(0.0, 0.0, 0.0, 0.82)
	abdunkler.set_anchors_preset(Control.PRESET_FULL_RECT)
	_voll.add_child(abdunkler)

	# G3 (HOCH-Fix ui-profil §5): Safe-Area-Rahmung statt fixer ±16/±12-
	# Offsets — sonst lag die Knopfleiste unter dem Home-Indicator und das
	# Bild ragte in die Notch-Zone (Rahmung macht _rahme_vollansicht).
	var spalte := VBoxContainer.new()
	spalte.add_theme_constant_override("separation", 10)
	_voll.add_child(spalte)
	_voll_spalte = spalte

	_voll_scroll = ScrollContainer.new()
	_voll_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_voll_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_voll_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_voll_scroll.scroll_deadzone = 24
	spalte.add_child(_voll_scroll)
	_voll_rect = TextureRect.new()
	_voll_rect.name = "VollBild"
	_voll_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_voll_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var tex := _lade_textur(pfad)
	if tex != null:
		_voll_rect.texture = tex
	_voll_scroll.add_child(_voll_rect)
	_wende_zoom_an()
	_voll_scroll.gui_input.connect(_on_voll_input)

	var foto := _foto_von(pfad)
	var info := Label.new()
	info.name = "FotoInfo"
	info.theme_type_variation = &"CaptionLabel"
	info.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.9))
	info.text = (
		"%s   %s   %s"
		% [
			I18nService.t("galerie.datum", {"datum": GalerieLogic.datum(int(foto.get("at", 0)))}),
			I18nService.t("galerie.ort", {"ort": GalerieLogic.ort_name(str(foto.get("ort", "")))}),
			I18nService.t("galerie.zoom_hinweis"),
		]
	)
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	spalte.add_child(info)

	var leiste := HFlowContainer.new()
	leiste.add_theme_constant_override("h_separation", 10)
	spalte.add_child(leiste)
	_voll_leiste = leiste
	_voll_fav_btn = _voll_knopf(leiste, "FavBtn", "", _on_voll_favorit)
	_refresh_fav_knopf()
	_voll_knopf(leiste, "ZoomRein", I18nService.t("galerie.zoom_rein"), _zoom_rein)
	_voll_knopf(leiste, "ZoomRaus", I18nService.t("galerie.zoom_raus"), _zoom_raus)
	var teilen := _voll_knopf(leiste, "Teilen", I18nService.t("galerie.teilen"), _on_teilen)
	teilen.theme_type_variation = &"BtnGhost"
	var loeschen := _voll_knopf(
		leiste, "Loeschen", I18nService.t("galerie.loeschen"), _on_loeschen_gefragt
	)
	loeschen.theme_type_variation = &"BtnGhost"
	_voll_knopf(leiste, "VollZurueck", I18nService.t("galerie.zurueck"), _schliesse_vollansicht)
	_rahme_vollansicht()


## G3: Vollansicht in die Safe-Area rahmen + Knopfleiste auf den Floor —
## läuft beim Öffnen UND aus _apply_metrics (Rotation/Resize/extra_inset).
func _rahme_vollansicht() -> void:
	if _voll == null or not is_instance_valid(_voll) or _m.is_empty():
		return
	if _voll_spalte != null and is_instance_valid(_voll_spalte):
		ScreenShell.frame(_voll_spalte, _m, 16.0, 12.0)
	if _voll_leiste == null or not is_instance_valid(_voll_leiste):
		return
	for knopf in _voll_leiste.get_children():
		if knopf is Control:
			ScreenShell.touch_target(knopf as Control, _m)


func _voll_knopf(parent: Control, node_name: String, text: String, aktion: Callable) -> Button:
	var btn := SquishButton.new()
	btn.name = node_name
	btn.theme_type_variation = &"BtnTeal"
	# G3: 48 Design-px × f statt fixer 48 px (≈15 pt auf Retina); den
	# physischen Floor legt _rahme_vollansicht per touch_target obendrauf.
	btn.custom_minimum_size = Vector2(0.0, 48.0 * float(_m.get("f", 1.0)))
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(aktion)
	parent.add_child(btn)
	return btn


func _schliesse_vollansicht() -> void:
	if _voll != null and is_instance_valid(_voll):
		_voll.queue_free()
	_voll = null
	_voll_spalte = null
	_voll_leiste = null
	_voll_pfad = ""


func _on_voll_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_rein()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_raus()


func _zoom_rein() -> void:
	_voll_zoom = mini(_voll_zoom + 1, ZOOM_STUFEN.size() - 1)
	_wende_zoom_an()


func _zoom_raus() -> void:
	_voll_zoom = maxi(_voll_zoom - 1, 0)
	_wende_zoom_an()


func _wende_zoom_an() -> void:
	if _voll_rect == null or _voll_scroll == null:
		return
	var basis := _voll_scroll.size
	if basis.x <= 0.0 or basis.y <= 0.0:
		basis = Vector2(get_viewport().get_visible_rect().size) * 0.8
	_voll_rect.custom_minimum_size = basis * ZOOM_STUFEN[_voll_zoom]


func _on_voll_favorit() -> void:
	if _gs == null or _voll_pfad.is_empty():
		return
	var pfad := _voll_pfad
	# Box statt lokaler Variable: Lambdas fangen Primitive per WERT.
	var box := {"neu": false}
	_gs.update(
		func(state: Dictionary) -> void: box["neu"] = GalerieLogic.toggle_favorit(state, pfad)
	)
	_gs.notify_slice_changed("city")
	_toasts.show_toast(
		I18nService.t("galerie.favorit_gesetzt" if bool(box["neu"]) else "galerie.favorit_entfernt")
	)
	_refresh_fav_knopf()
	_refresh()


func _refresh_fav_knopf() -> void:
	if _voll_fav_btn == null:
		return
	var foto := _foto_von(_voll_pfad)
	var fav := bool(foto.get("fav", false))
	_voll_fav_btn.text = I18nService.t("galerie.favorit")
	_voll_fav_btn.theme_type_variation = &"BtnYellow" if fav else &"BtnTeal"


## FERTIG-1: aus „Teilen (bald)“ wurde ein echter Export — das PNG landet
## im Bilder-Ordner des Systems (bzw. user://export ohne System-Ordner).
func _on_teilen() -> void:
	var ziel := GalerieLogic.exportiere(_voll_pfad)
	if ziel.is_empty():
		_toasts.show_toast(I18nService.t("galerie.export_fehler"))
		return
	_toasts.show_toast(I18nService.t("galerie.export_ok", {"ziel": ziel}))


## ---------------------------------------------------------------- Löschen


func _on_loeschen_gefragt() -> void:
	if _bestaetigung != null and is_instance_valid(_bestaetigung):
		_bestaetigung.queue_free()
	_bestaetigung = PanelContainer.new()
	_bestaetigung.name = "LoeschDialog"
	_bestaetigung.theme_type_variation = &"AcCard"
	_bestaetigung.set_anchors_preset(Control.PRESET_CENTER)
	_bestaetigung.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_bestaetigung.grow_vertical = Control.GROW_DIRECTION_BOTH
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_bestaetigung.add_child(box)
	var frage := Label.new()
	frage.text = I18nService.t("galerie.loeschen_frage")
	frage.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	frage.custom_minimum_size = Vector2(320.0, 0.0)
	box.add_child(frage)
	var zeile := HBoxContainer.new()
	zeile.add_theme_constant_override("separation", 10)
	box.add_child(zeile)
	var ja := SquishButton.new()
	ja.name = "LoeschenJa"
	ja.theme_type_variation = &"BtnYellow"
	ja.text = I18nService.t("galerie.loeschen_ja")
	ja.focus_mode = Control.FOCUS_NONE
	ja.pressed.connect(_on_loeschen_bestaetigt)
	ScreenShell.touch_target(ja, _m)
	zeile.add_child(ja)
	var nein := SquishButton.new()
	nein.name = "LoeschenNein"
	nein.theme_type_variation = &"BtnGhost"
	nein.text = I18nService.t("galerie.abbrechen")
	nein.focus_mode = Control.FOCUS_NONE
	nein.pressed.connect(func() -> void: _bestaetigung.queue_free())
	ScreenShell.touch_target(nein, _m)
	zeile.add_child(nein)
	var ziel: Control = _voll if _voll != null and is_instance_valid(_voll) else self
	ziel.add_child(_bestaetigung)


func _on_loeschen_bestaetigt() -> void:
	if _bestaetigung != null and is_instance_valid(_bestaetigung):
		_bestaetigung.queue_free()
	if _gs == null or _voll_pfad.is_empty():
		return
	var pfad := _voll_pfad
	# Box statt lokaler Variable: Lambdas fangen Primitive per WERT.
	var box := {"entfernt": false}
	_gs.update(
		func(state: Dictionary) -> void: box["entfernt"] = GalerieLogic.entferne(state, pfad)
	)
	_gs.notify_slice_changed("city")
	if bool(box["entfernt"]):
		_thumb_cache.erase(pfad)
		var absolut := ProjectSettings.globalize_path(pfad)
		if FileAccess.file_exists(absolut):
			DirAccess.remove_absolute(absolut)
		_toasts.show_toast(I18nService.t("galerie.geloescht"))
	_schliesse_vollansicht()
	_refresh()


## ---------------------------------------------------------------- Sonstiges


func _on_filter_pressed() -> void:
	nur_favoriten = not nur_favoriten
	_refresh()


func _lade_textur(pfad: String) -> Texture2D:
	if _thumb_cache.has(pfad):
		return _thumb_cache[pfad]
	var bild := Image.new()
	if pfad.is_empty() or bild.load(pfad) != OK:
		return null
	var tex := ImageTexture.create_from_image(bild)
	_thumb_cache[pfad] = tex
	return tex


func _foto_von(pfad: String) -> Dictionary:
	for foto: Dictionary in GalerieLogic.fotos_von(_state()):
		if str(foto["pfad"]) == pfad:
			return foto
	return {}


func _state() -> Dictionary:
	if _gs == null or not _gs.has_method("state"):
		return {}
	return _gs.state()


func _on_back_pressed() -> void:
	if not auto_navigate:
		return
	var router := get_node_or_null("/root/SceneRouter")
	if router == null:
		return
	if router.has_method("handle_back_request") and router.handle_back_request():
		return
	if router.has_method("goto"):
		router.goto(&"city", {})
