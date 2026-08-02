class_name Spiegel
extends Node3D
## Spiegel-Interactable (W3d CONTENT, Doc F §3.2): öffnet die
## Char-Editor-Teilmenge als Sheet (Morph-Slider wie im W1c-Onboarding,
## Kontrakt meta.charMorphs — FROZEN W1d-Keys). Änderungen gehen live auf
## den GoobyRig (eyes_apart→eye_width, eye_scale→eye_size, ear_len→
## ear_length; chubby ist Weight-Tier, M2). Gooby posiert währenddessen.

const MORPHS: Array[Dictionary] = [
	{"id": "eyes_apart", "label": "bad.spiegel.augenabstand", "min": -1.0, "max": 1.0},
	{"id": "eye_scale", "label": "bad.spiegel.augengroesse", "min": 0.7, "max": 1.4},
	{"id": "ear_len", "label": "bad.spiegel.ohrlaenge", "min": 0.7, "max": 1.4},
	{"id": "chubby", "label": "bad.spiegel.pausbacken", "min": 0.0, "max": 1.0},
]
const RIG_MAP := {"eyes_apart": "eye_width", "eye_scale": "eye_size", "ear_len": "ear_length"}
## G6-FEEL: Morph-Slider ticken hörbar, aber gedrosselt (Muster
## settings_rows_basis.gd — Grammatik §3: „ui_tick … ggf. drosseln“).
const TICK_DEBOUNCE_MS := 90
const TICK_META := &"_g6_tick_ab_ms"

var _host: InteractablesHost
var _sheet: PanelSheet


func setup(host: InteractablesHost, furniture: Node3D) -> void:
	_host = host
	add_child(InteractablesHost.make_tap_area(furniture, _on_tapped))


func _on_tapped() -> void:
	if _room_busy():
		return
	_open_sheet()


func _open_sheet() -> void:
	if _sheet == null:
		_sheet = (load("res://scripts/ui/panel_sheet.tscn") as PackedScene).instantiate()
		# Theme explizit setzen: Window-Theme propagiert NICHT durch CanvasLayer.
		_sheet.theme = ThemeService.theme()
		_ui_layer().add_child(_sheet)
		_sheet.closed.connect(_on_sheet_closed)
	_sheet.set_title(I18nService.t("bad.spiegel.titel"))
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 8)
	for morph: Dictionary in MORPHS:
		body.add_child(_build_slider_row(morph))
	_sheet.add_content(body)
	_sheet.open()
	var gooby := _gooby()
	if gooby != null:
		gooby.set_wander_enabled(false)
		gooby.play_clip("idle_lookaround")


func _build_slider_row(morph: Dictionary) -> Control:
	var row := VBoxContainer.new()
	var label := Label.new()
	label.theme_type_variation = &"SoftLabel"
	label.text = I18nService.t(str(morph["label"]))
	row.add_child(label)
	var slider := HSlider.new()
	slider.name = "Slider_%s" % str(morph["id"])
	slider.min_value = float(morph["min"])
	slider.max_value = float(morph["max"])
	slider.step = 0.01
	slider.value = _current_value(str(morph["id"]))
	slider.value_changed.connect(_on_morph_changed.bind(str(morph["id"])))
	slider.value_changed.connect(func(_wert: float) -> void: _spiele_slider_tick(slider))
	row.add_child(slider)
	return row


## Gedrosseltes Raststufen-Tick — pro Slider frühestens alle
## TICK_DEBOUNCE_MS (has_meta-Guard statt get_meta(key, null), Lint-Regel).
func _spiele_slider_tick(slider: HSlider) -> void:
	var now := Time.get_ticks_msec()
	if slider.has_meta(TICK_META) and now < int(slider.get_meta(TICK_META)):
		return
	slider.set_meta(TICK_META, now + TICK_DEBOUNCE_MS)
	AudioDirector.try_play(slider, "ui_tick")


func _current_value(morph_id: String) -> float:
	var gs := _host.game_state()
	if gs == null:
		return 1.0 if morph_id == "eye_scale" or morph_id == "ear_len" else 0.0
	var fallback := 1.0 if morph_id == "eye_scale" or morph_id == "ear_len" else 0.0
	return float(gs.get_value("meta.charMorphs.%s" % morph_id, fallback))


func _on_morph_changed(value: float, morph_id: String) -> void:
	var gs := _host.game_state()
	if gs != null:
		gs.set_value("meta.charMorphs.%s" % morph_id, value)
		gs.notify_slice_changed("meta")
	var gooby := _gooby()
	if gooby != null and RIG_MAP.has(morph_id) and "rig" in gooby and gooby.rig != null:
		gooby.rig.set_morph(str(RIG_MAP[morph_id]), value)


func _on_sheet_closed() -> void:
	var gooby := _gooby()
	if gooby != null:
		gooby.play_clip("idle")
		gooby.set_wander_enabled(true)


func _gooby() -> Node:
	var room := _host.room()
	if room != null and room.has_method("gooby"):
		return room.gooby()
	return null


func _room_busy() -> bool:
	var room := _host.room()
	return room != null and room.has_method("is_build_mode_active") and room.is_build_mode_active()


func _ui_layer() -> CanvasLayer:
	var existing := _host.get_node_or_null("W3dUiLayer")
	if existing is CanvasLayer:
		return existing
	var layer := CanvasLayer.new()
	layer.name = "W3dUiLayer"
	layer.layer = 6
	_host.add_child(layer)
	return layer
