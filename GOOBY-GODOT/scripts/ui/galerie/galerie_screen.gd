class_name GalerieScreen
extends Control
## Vollständige Fotogalerie (REST-4, EVAL Rang 14): Raster mit
## Vorschaubildern (city.fotos aus dem FotoModus), Vollansicht mit Zoom
## (Knöpfe + Mausrad, Pan über den Scroll-Container), Favoriten
## (additives fav-Flag), Löschen mit Nachfrage (Index + PNG-Datei),
## Datum/Ort-Anzeige, ehrlich benannter Teilen-Platzhalter und
## Speicheranzeige (n von 40 Plätzen). Route `galerie` — erreichbar aus
## der Kamera-App des IGohbie.

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
var _speicher_label: Label
var _filter_btn: Button
var _leer_label: Label
var _toasts: ToastLayer
var _voll: Control
var _voll_pfad := ""
var _voll_zoom := 0
var _voll_rect: TextureRect
var _voll_scroll: ScrollContainer
var _voll_fav_btn: Button
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
	var wallpaper := AcWallpaper.new()
	wallpaper.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(wallpaper)

	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 12)
	add_child(_rows)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 12)
	_rows.add_child(header)
	var back := SquishButton.new()
	back.name = "Zurueck"
	back.theme_type_variation = &"BtnGhost"
	back.text = I18nService.t("galerie.zurueck")
	back.focus_mode = Control.FOCUS_NONE
	back.pressed.connect(_on_back_pressed)
	header.add_child(back)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = I18nService.t("galerie.titel")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)
	var chip := PanelContainer.new()
	chip.theme_type_variation = &"StatusCapsule"
	_speicher_label = Label.new()
	_speicher_label.name = "Speicher"
	_speicher_label.theme_type_variation = &"SoftLabel"
	chip.add_child(_speicher_label)
	header.add_child(chip)

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
	ScreenShell.frame(_rows, _m, 24.0, 16.0)
	ScreenShell.scale_fonts(self, float(_m["f"]))
	var canvas: Vector2 = _m["canvas"]
	_grid.columns = clampi(int(canvas.x / (240.0 * float(_m["f"]))), 2, 5)


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


func _thumb(foto: Dictionary) -> Control:
	var pfad := str(foto["pfad"])
	var karte := Button.new()
	karte.name = "Foto_%s" % pfad.get_file().get_basename()
	karte.theme_type_variation = &"AcCard"
	karte.custom_minimum_size = Vector2(200.0, 150.0) * float(_m.get("f", 1.0))
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

	var spalte := VBoxContainer.new()
	spalte.set_anchors_preset(Control.PRESET_FULL_RECT)
	spalte.offset_left = 16.0
	spalte.offset_right = -16.0
	spalte.offset_top = 12.0
	spalte.offset_bottom = -12.0
	spalte.add_theme_constant_override("separation", 10)
	_voll.add_child(spalte)

	_voll_scroll = ScrollContainer.new()
	_voll_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_voll_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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


func _voll_knopf(parent: Control, node_name: String, text: String, aktion: Callable) -> Button:
	var btn := SquishButton.new()
	btn.name = node_name
	btn.theme_type_variation = &"BtnTeal"
	btn.text = text
	btn.custom_minimum_size = Vector2(0.0, 48.0)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(aktion)
	parent.add_child(btn)
	return btn


func _schliesse_vollansicht() -> void:
	if _voll != null and is_instance_valid(_voll):
		_voll.queue_free()
	_voll = null
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


func _on_teilen() -> void:
	_toasts.show_toast(I18nService.t("galerie.teilen_hinweis"))


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
	ja.custom_minimum_size = Vector2(0.0, 48.0)
	ja.focus_mode = Control.FOCUS_NONE
	ja.pressed.connect(_on_loeschen_bestaetigt)
	zeile.add_child(ja)
	var nein := SquishButton.new()
	nein.name = "LoeschenNein"
	nein.theme_type_variation = &"BtnGhost"
	nein.text = I18nService.t("galerie.abbrechen")
	nein.custom_minimum_size = Vector2(0.0, 48.0)
	nein.focus_mode = Control.FOCUS_NONE
	nein.pressed.connect(func() -> void: _bestaetigung.queue_free())
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
