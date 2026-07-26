class_name RanchDriveHud
extends Control
## Fahr-HUD der Überlandfahrt (RANCH-1) — bewusst leichter als das
## Stadt-DriveHud (keine Minimap, kein Rückwärts-Toggle): Links/Rechts-
## Daumen-Zonen, Brems-Knopf, „Zur Stadt“-Knopf und der Tor-Prompt.
## Wiederverwendet die city.fahren-Strings für Bremse (ein Wording überall).

signal steer_changed(value: float)
signal brake_changed(on: bool)
signal zur_stadt_pressed
signal prompt_pressed

var _held_left := false
var _held_right := false
var _prompt: PanelContainer
var _prompt_label: Label
var _prompt_btn: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_baue_zone(true)
	_baue_zone(false)
	var brake := _baue_knopf(I18nService.t("city.fahren.bremse"), "AccentButton")
	brake.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 96
	)
	brake.button_down.connect(func() -> void: brake_changed.emit(true))
	brake.button_up.connect(func() -> void: brake_changed.emit(false))
	var stadt := _baue_knopf(I18nService.t("ranch.fahrt.zur_stadt"), "GhostButton")
	stadt.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	stadt.pressed.connect(func() -> void: zur_stadt_pressed.emit())
	_baue_prompt()


## Tor-Prompt mit Text + Aktionsknopf zeigen (Knopftext pro Situation).
func zeige_prompt(text: String, knopf_text: String) -> void:
	_prompt_label.text = text
	_prompt_btn.text = knopf_text
	_prompt.visible = true


func verstecke_prompt() -> void:
	_prompt.visible = false


func prompt_sichtbar() -> bool:
	return _prompt.visible


func aktueller_steer() -> float:
	return (1.0 if _held_right else 0.0) - (1.0 if _held_left else 0.0)


func _baue_zone(links: bool) -> void:
	var zone := Control.new()
	zone.name = "ZoneL" if links else "ZoneR"
	zone.mouse_filter = Control.MOUSE_FILTER_STOP
	zone.set_anchors_and_offsets_preset(
		Control.PRESET_LEFT_WIDE if links else Control.PRESET_RIGHT_WIDE
	)
	zone.anchor_left = 0.0 if links else 0.5
	zone.anchor_right = 0.5 if links else 1.0
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
	_prompt.custom_minimum_size = Vector2(380.0, 0.0)
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
	_prompt_btn.theme_type_variation = "PrimaryButton"
	_prompt_btn.pressed.connect(func() -> void: prompt_pressed.emit())
	box.add_child(_prompt_btn)
