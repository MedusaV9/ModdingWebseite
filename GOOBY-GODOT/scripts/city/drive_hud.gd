class_name DriveHud
extends Control
## Fahr-HUD in der Stadt (W3a CITY): Links/Rechts-Daumen-Zonen (halbe
## Schirmhälften, Web g7-drive-Port), Brems-Knopf unten-mittig,
## Rückwärts-Toggle daneben, „Nach Hause“-Knopf (IMMER kostenlos, oben
## rechts), der Parkplatz-Prompt („<Ort> betreten? Energie −N“) und die
## Minimap mit den Orts-Pins (oben links, `minimap`).

signal steer_changed(value: float)
signal brake_changed(on: bool)
signal reverse_changed(on: bool)
signal nach_hause_pressed
signal betreten_pressed(ort_id: String)

## Minimap oben links — CityScene setzt `minimap.karte` und füttert sie.
var minimap: CityMinimap

var _held_left := false
var _held_right := false
var _reverse := false
var _prompt_ort := ""

var _zone_l: Control
var _zone_r: Control
var _brake: Button
var _reverse_btn: Button
var _home_btn: Button
var _prompt: PanelContainer
var _prompt_label: Label
var _prompt_btn: Button


func _ready() -> void:
	# anchors+offsets (nicht nur anchors): _ready läuft NACH add_child —
	# set_anchors_preset allein lässt den Rect dann bei 0×0.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_zone_l = _baue_zone(true)
	_zone_r = _baue_zone(false)
	# Anker-relative Offsets (PRESET_MODE_MINSIZE) statt position-Mathe:
	# zur _ready-Zeit hat das Layout noch keine Größen — position+= landet
	# sonst offscreen.
	_brake = _baue_knopf(I18nService.t("city.fahren.bremse"), "AccentButton")
	_brake.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 96
	)
	_brake.button_down.connect(func() -> void: brake_changed.emit(true))
	_brake.button_up.connect(func() -> void: brake_changed.emit(false))
	_reverse_btn = _baue_knopf(I18nService.t("city.fahren.rueckwaerts"), "GhostButton")
	_reverse_btn.toggle_mode = true
	_reverse_btn.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 96
	)
	_reverse_btn.offset_left += 130.0
	_reverse_btn.offset_right += 130.0
	_reverse_btn.toggled.connect(func(on: bool) -> void: reverse_changed.emit(on))
	_home_btn = _baue_knopf(I18nService.t("city.fahren.nach_hause"), "PrimaryButton")
	_home_btn.set_anchors_and_offsets_preset(
		Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16
	)
	_home_btn.pressed.connect(func() -> void: nach_hause_pressed.emit())
	minimap = CityMinimap.new()
	minimap.name = "Minimap"
	minimap.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT, Control.PRESET_MODE_MINSIZE, 16)
	add_child(minimap)
	_baue_prompt()


func _gui_input(_event: InputEvent) -> void:
	pass


## Parkplatz-Prompt zeigen/verstecken (energie 0 = „kostenlos“).
func zeige_prompt(ort_id: String, ort_name: String, energie: int) -> void:
	_prompt_ort = ort_id
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
