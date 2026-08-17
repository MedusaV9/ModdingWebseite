class_name DriveHud
extends Control
## Fahr-HUD in der Stadt (W3a CITY): Links/Rechts-Daumen-Zonen (halbe
## Schirmhälften, Web g7-drive-Port), Brems-Knopf + Rückwärts-Toggle in
## der RECHTEN Daumen-Ecke (W20/P4, Befund D2: unten-mittig war im
## Querformat tote Daumenzone — die Daumen liegen an den Kanten),
## „Nach Hause“-Knopf (IMMER kostenlos, oben rechts), der Parkplatz-
## Prompt („<Ort> betreten? Energie −N“) und die Minimap mit den
## Orts-Pins (oben links, `minimap`). Alle Anker sind Safe-Area-bewusst
## (ScreenShell.metrics) und laufen bei jedem Viewport-Resize neu.
##
## W13B Ziel-Chevron (Doc E §1.4 „GPS-Pfeil“): Pin auf der Minimap antippen
## → dezenter Richtungskeil am Bildschirmrand zeigt zum Ziel (Screen-Space
## über die 3D-Kamera, Mathe pur in `chevron_platzierung`). Gleicher Pin
## nochmal = GPS aus; Ankunft (Parkplatz-Prompt des Ziels) räumt es auf.

signal steer_changed(value: float)
signal brake_changed(on: bool)
signal reverse_changed(on: bool)
signal nach_hause_pressed
signal betreten_pressed(ort_id: String)

## Innenabstand des Chevrons zum Schirmrand (px).
const CHEVRON_RAND_PX := 36.0
## Tipp-Toleranz um einen Minimap-Pin (px).
const ZIEL_TIPP_RADIUS_PX := 18.0
## Basis-Kantenlänge der Fahr-Knöpfe (Design-px, skaliert mit UiScale).
const KNOPF_BASIS_PX := 72.0
## Randabstand der Ecken-Anker zur Safe-Area (Design-px, skaliert mit f).
const ECKEN_RAND_PX := 16.0

## Minimap oben links — CityScene setzt `minimap.karte` und füttert sie.
var minimap: CityMinimap

var _held_left := false
var _held_right := false
var _reverse := false
var _prompt_ort := ""
var _ziel_ort := ""
var _ziel_welt := Vector3.ZERO

var _zone_l: Control
var _zone_r: Control
var _brake: Button
var _reverse_btn: Button
var _home_btn: Button
var _prompt: PanelContainer
var _prompt_label: Label
var _prompt_btn: Button
var _ziel_catcher: Control
var _chevron: Control


func _ready() -> void:
	# anchors+offsets (nicht nur anchors): _ready läuft NACH add_child —
	# set_anchors_preset allein lässt den Rect dann bei 0×0.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zone_l = _baue_zone(true)
	_zone_r = _baue_zone(false)
	# W20/P4 (Befund D2): Bremse + Rückwärts wandern in die RECHTE
	# Daumen-Ecke (Bremse unten, R direkt darüber — Daumen bleibt liegen);
	# die konkreten Offsets rechnet _apply_metrics Safe-Area-bewusst.
	_brake = _baue_knopf(I18nService.t("city.fahren.bremse"), "AccentButton")
	_brake.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_brake.button_down.connect(func() -> void: brake_changed.emit(true))
	_brake.button_up.connect(func() -> void: brake_changed.emit(false))
	_reverse_btn = _baue_knopf(I18nService.t("city.fahren.rueckwaerts"), "GhostButton")
	_reverse_btn.toggle_mode = true
	_reverse_btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_reverse_btn.toggled.connect(func(on: bool) -> void: reverse_changed.emit(on))
	_home_btn = _baue_knopf(I18nService.t("city.fahren.nach_hause"), "PrimaryButton")
	_home_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_home_btn.pressed.connect(func() -> void: nach_hause_pressed.emit())
	minimap = CityMinimap.new()
	minimap.name = "Minimap"
	minimap.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	add_child(minimap)
	# Tipp-Fänger ÜBER der Minimap (sie selbst bleibt MOUSE_FILTER_IGNORE):
	# Pin antippen setzt/löscht das Fahrziel für den Chevron.
	_ziel_catcher = Control.new()
	_ziel_catcher.name = "ZielCatcher"
	_ziel_catcher.custom_minimum_size = Vector2(CityMinimap.GROESSE, CityMinimap.GROESSE)
	_ziel_catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	_ziel_catcher.set_anchors_and_offsets_preset(
		Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 16
	)
	_ziel_catcher.gui_input.connect(_on_karte_tipp)
	add_child(_ziel_catcher)
	_chevron = ZielChevron.new()
	_chevron.name = "ZielChevron"
	_chevron.visible = false
	add_child(_chevron)
	_baue_prompt()
	get_viewport().size_changed.connect(_apply_metrics)
	_apply_metrics()


## W20/P4 (Befund D2): Fahr-UI-Anker Safe-Area-bewusst in die Daumen-Ecken
## legen — BREMSE in die rechte untere Ecke, Rückwärts-Toggle direkt
## darüber (der rechte Daumen bleibt an der Kante liegen; gelenkt wird
## weiter über die Halbschirm-Zonen). „Nach Hause“ oben rechts und
## Minimap/Tipp-Fänger oben links rücken von Insets/Island-Rundung weg.
## Tippflächen ≥ Touch-Floor, Schriften skalieren mit f.
func _apply_metrics() -> void:
	var m := ScreenShell.metrics(get_viewport())
	var f: float = m["f"]
	var insets: Dictionary = m["insets"]
	var rand := ECKEN_RAND_PX * f
	for knopf: Button in [_brake, _reverse_btn, _home_btn]:
		knopf.custom_minimum_size = Vector2(KNOPF_BASIS_PX, KNOPF_BASIS_PX) * f
		ScreenShell.touch_target(knopf, m)
		ScreenShell.scale_fonts(knopf, f)
	var rechts := float(insets["right"]) + rand
	var unten := float(insets["bottom"]) + rand
	var brake_size := _brake.get_combined_minimum_size()
	_brake.offset_right = -rechts
	_brake.offset_left = -rechts - brake_size.x
	_brake.offset_bottom = -unten
	_brake.offset_top = -unten - brake_size.y
	var reverse_size := _reverse_btn.get_combined_minimum_size()
	var reverse_unten := unten + brake_size.y + 12.0 * f
	_reverse_btn.offset_right = -rechts
	_reverse_btn.offset_left = -rechts - reverse_size.x
	_reverse_btn.offset_bottom = -reverse_unten
	_reverse_btn.offset_top = -reverse_unten - reverse_size.y
	var home_size := _home_btn.get_combined_minimum_size()
	var oben := float(insets["top"]) + rand
	_home_btn.offset_right = -rechts
	_home_btn.offset_left = -rechts - home_size.x
	_home_btn.offset_top = oben
	_home_btn.offset_bottom = oben + home_size.y
	var karte_rand := Vector2(float(insets["left"]) + rand, oben)
	for feld: Control in [minimap, _ziel_catcher]:
		if feld == null:
			continue
		feld.offset_left = karte_rand.x
		feld.offset_top = karte_rand.y
		feld.offset_right = karte_rand.x + CityMinimap.GROESSE
		feld.offset_bottom = karte_rand.y + CityMinimap.GROESSE


func _process(_delta: float) -> void:
	_update_chevron()


func _gui_input(_event: InputEvent) -> void:
	pass


## Parkplatz-Prompt zeigen/verstecken (energie 0 = „kostenlos“).
func zeige_prompt(ort_id: String, ort_name: String, energie: int) -> void:
	_prompt_ort = ort_id
	# Ziel erreicht: der Prompt des GPS-Ziels räumt den Chevron auf.
	if not _ziel_ort.is_empty() and ort_id == _ziel_ort:
		_ziel_ort = ""
		_chevron.visible = false
		_zeige_toast(I18nService.t("city_leben.ziel_erreicht").format({"ort": _ort_name(ort_id)}))
	if energie > 0:
		_prompt_label.text = I18nService.t("city.fahren.betreten_energie").format(
			{"ort": ort_name, "energie": energie}
		)
	else:
		_prompt_label.text = I18nService.t("city.fahren.betreten_frei").format({"ort": ort_name})
	_prompt.visible = true


func verstecke_prompt() -> void:
	_prompt_ort = ""
	_prompt.visible = false


func prompt_sichtbar() -> bool:
	return _prompt.visible


func aktueller_steer() -> float:
	return (1.0 if _held_right else 0.0) - (1.0 if _held_left else 0.0)


## ------------------------------------------------------- Ziel-Chevron


## Aktives GPS-Ziel ("" = keins) — für CityScene/Tests.
func ziel_ort() -> String:
	return _ziel_ort


## Fahrziel setzen ("" oder gleicher Ort = GPS aus). Braucht minimap.karte.
func setze_ziel(ort_id: String) -> void:
	if ort_id.is_empty() or ort_id == _ziel_ort:
		_ziel_ort = ""
		_chevron.visible = false
		if not ort_id.is_empty():
			_zeige_toast(I18nService.t("city_leben.ziel_weg"))
		return
	if minimap == null or minimap.karte == null:
		return
	_ziel_ort = ort_id
	_ziel_welt = minimap.karte.parkplatz_welt(ort_id)
	_zeige_toast(I18nService.t("city_leben.ziel_gesetzt").format({"ort": _ort_name(ort_id)}))


## Chevron-Platzierung am Schirmrand — MATHE PUR (testbar). ziel_px =
## unprojizierte Ziel-Position, hinter_kamera spiegelt sie um die Mitte.
## Rückgabe {sichtbar, pos, winkel}; sichtbar=false, wenn das Ziel ohnehin
## im Bild liegt (dann braucht niemand einen Pfeil).
static func chevron_platzierung(
	schirm: Vector2, ziel_px: Vector2, hinter_kamera: bool, rand_px := CHEVRON_RAND_PX
) -> Dictionary:
	var mitte := schirm * 0.5
	var punkt := ziel_px
	if hinter_kamera:
		punkt = mitte * 2.0 - ziel_px
	var innen := Rect2(Vector2(rand_px, rand_px), schirm - Vector2(rand_px, rand_px) * 2.0)
	if not hinter_kamera and innen.has_point(punkt):
		return {"sichtbar": false, "pos": punkt, "winkel": 0.0}
	var richtung := punkt - mitte
	if richtung.length_squared() < 0.000001:
		richtung = Vector2.DOWN
	var skala := 1.0e9
	if absf(richtung.x) > 0.0001:
		skala = minf(skala, (mitte.x - rand_px) / absf(richtung.x))
	if absf(richtung.y) > 0.0001:
		skala = minf(skala, (mitte.y - rand_px) / absf(richtung.y))
	return {"sichtbar": true, "pos": mitte + richtung * skala, "winkel": richtung.angle()}


## Nächster Pin zum Tipp-Punkt — MATHE PUR. pins = [{id, px: Vector2}];
## "" wenn keiner innerhalb max_d_px liegt (Gleichstand: erster gewinnt).
static func naechster_pin(pins: Array, tipp: Vector2, max_d_px: float) -> String:
	var beste_id := ""
	var beste_d := max_d_px
	for pin: Dictionary in pins:
		var d := tipp.distance_to(pin["px"])
		if d < beste_d:
			beste_d = d
			beste_id = str(pin["id"])
	return beste_id


func _on_karte_tipp(event: InputEvent) -> void:
	var tippt := false
	if event is InputEventMouseButton:
		tippt = event.pressed
	elif event is InputEventScreenTouch:
		tippt = event.pressed
	if not tippt or minimap == null:
		return
	var pins: Array = []
	for pin: Dictionary in minimap.pins():
		pins.append({"id": pin["id"], "px": minimap.welt_zu_pixel(pin["welt"])})
	var ort_id := naechster_pin(pins, event.position, ZIEL_TIPP_RADIUS_PX)
	if not ort_id.is_empty():
		setze_ziel(ort_id)


## Chevron jede Frame nachführen: Ziel über die 3D-Kamera in den Schirm
## projizieren, Platzierung rechnet `chevron_platzierung` (Mathe pur).
func _update_chevron() -> void:
	if _ziel_ort.is_empty():
		_chevron.visible = false
		return
	var kamera := get_viewport().get_camera_3d()
	if kamera == null:
		_chevron.visible = false
		return
	var ziel := _ziel_welt + Vector3(0.0, 1.0, 0.0)
	var lage := chevron_platzierung(
		size, kamera.unproject_position(ziel), kamera.is_position_behind(ziel)
	)
	_chevron.visible = bool(lage["sichtbar"])
	if not _chevron.visible:
		return
	_chevron.position = (lage["pos"] as Vector2) - _chevron.pivot_offset
	_chevron.rotation = float(lage["winkel"])


func _ort_name(ort_id: String) -> String:
	if ort_id == "zuhause":
		return I18nService.t("city_leben.zuhause")
	if minimap == null or minimap.karte == null:
		return ort_id
	var eintrag := minimap.karte.ort(ort_id)
	if eintrag.is_empty():
		return ort_id
	return I18nService.t(str(eintrag.get("name_key", ort_id)))


func _zeige_toast(text: String) -> void:
	var toasts := get_tree().root.find_children("*", "ToastLayer", true, false)
	if not toasts.is_empty():
		toasts[0].show_toast(text)


func _baue_zone(links: bool) -> Control:
	var zone := Control.new()
	zone.name = "ZoneL" if links else "ZoneR"
	zone.mouse_filter = Control.MOUSE_FILTER_STOP
	if links:
		zone.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	else:
		zone.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	zone.anchor_right = 0.5 if links else 1.0
	zone.anchor_left = 0.0 if links else 0.5
	add_child(zone)
	var chev := Label.new()
	chev.text = "‹" if links else "›"
	chev.add_theme_font_size_override("font_size", 56)
	chev.modulate = Color(1, 1, 1, 0.55)
	chev.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_LEFT if links else Control.PRESET_CENTER_RIGHT,
		Control.PRESET_MODE_MINSIZE,
		18
	)
	zone.add_child(chev)
	zone.gui_input.connect(_on_zone_input.bind(links))
	return zone


func _on_zone_input(event: InputEvent, links: bool) -> void:
	var neu: bool
	if event is InputEventMouseButton:
		neu = event.pressed
	elif event is InputEventScreenTouch:
		neu = event.pressed
	else:
		return
	if links:
		_held_left = neu
	else:
		_held_right = neu
	steer_changed.emit(aktueller_steer())


func _baue_knopf(text: String, variation: String) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.theme_type_variation = variation
	btn.custom_minimum_size = Vector2(72.0, 72.0)
	add_child(btn)
	return btn


func _baue_prompt() -> void:
	_prompt = PanelContainer.new()
	_prompt.theme_type_variation = "AcCard"
	_prompt.visible = false
	_prompt.custom_minimum_size = Vector2(360.0, 0.0)
	_prompt.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 24
	)
	_prompt.grow_vertical = Control.GROW_DIRECTION_END
	add_child(_prompt)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_prompt.add_child(box)
	_prompt_label = Label.new()
	_prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_prompt_label)
	_prompt_btn = Button.new()
	_prompt_btn.text = I18nService.t("city.fahren.betreten")
	_prompt_btn.theme_type_variation = "PrimaryButton"
	_prompt_btn.pressed.connect(
		func() -> void:
			if not _prompt_ort.is_empty():
				betreten_pressed.emit(_prompt_ort)
	)
	box.add_child(_prompt_btn)


## Dezenter Richtungskeil (zeigt lokal nach +X, DriveHud dreht/platziert).
class ZielChevron:
	extends Control

	func _ready() -> void:
		custom_minimum_size = Vector2(44.0, 44.0)
		size = custom_minimum_size
		pivot_offset = size * 0.5
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var m := size * 0.5
		var punkte := PackedVector2Array(
			[
				m + Vector2(16.0, 0.0),
				m + Vector2(-10.0, 11.0),
				m + Vector2(-5.0, 0.0),
				m + Vector2(-10.0, -11.0),
			]
		)
		draw_colored_polygon(punkte, AcTokens.PINK)
		punkte.append(punkte[0])
		draw_polyline(punkte, AcTokens.PAPER, 2.0)
