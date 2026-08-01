class_name RanchRideHud
extends Control
## Touch-HUD fuers Reiten (RW-2, IDEAS-3 Kap. 3.6) — reine VERDRAHTUNG:
## alle Zahlen/Erkennungen kommen aus RanchRideTouch (PURE, getestet),
## die Wirkung geht in einen RanchRideController. Mit EINEM Daumen
## bedienbar; Maus wirkt wie ein Finger (Desktop-Demo).
##
## Layout "Zwei Daumen": linke Haelfte = Floating-Stick (nur X lenkt),
## rechte Haelfte = Gangart-Wische hoch/runter, unten rechts der Sprung-
## Button (pulsiert vor Hindernissen). Dazu Ausdauerbalken + Gangart-
## Chip oben links, "Perfekt!"-Callout mittig, Erschoepfungs-Banner mit
## Streicheln-Button (Zweiter Wind).
##
## Bedienhilfen: `linkshaender` spiegelt das Layout, `zuegel_modus`
## macht Einhand-Reiten (Halten = schneller, Loslassen = eine Gangart
## runter), `button_wunsch_dp` skaliert den Sprung-Button (64–96 dp).
##
## Einbau: hud.controller = <RanchRideController> setzen, add_child.

const Touch := preload("res://scripts/ranch/gameplay/ride_touch.gd")
const Stats := preload("res://scripts/ranch/gameplay/ride_stats.gd")
const Feel := preload("res://scripts/ranch/gameplay/ride_feel.gd")

const INK := Color("#3B3630")
const CREME := Color("#FFF6E8")
const GOLD := Color("#F2B04C")
const TEAL := Color("#5FA8A0")
const ROSA := Color("#E98CA0")

## Bedienhilfen (Kap. 3.6): Spiegelung, Einhand-Zuegel, Button-Groesse.
@export var linkshaender := false
@export var zuegel_modus := false
@export var button_wunsch_dp := 72.0

var controller: RanchRideController

var _stick_finger := -1
var _stick_start := Vector2.ZERO
var _stick_punkt := Vector2.ZERO
var _wisch_finger := -1
var _wisch_start := Vector2.ZERO
var _wisch_start_ms := 0
var _zuegel_halte_s := -1.0
var _ausdauer_fill: ColorRect
var _ausdauer_max_px := 150.0
var _gang_chip: Label
var _callout: Label
var _callout_t := 0.0
var _banner: Label
var _streicheln_btn: Button
var _sprung_btn: Button
var _puls_zeit := 0.0
var _stick_gezeichnet := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_baue_ui()
	if controller != null:
		controller.sprung_gewertet.connect(_on_sprung_gewertet)
		controller.erschoepft.connect(_on_erschoepft)
		controller.zweiter_wind_genutzt.connect(_on_zweiter_wind)
		controller.gait_changed.connect(func(_g: String) -> void: _update_gang_chip())
	_update_gang_chip()


func _process(delta: float) -> void:
	if controller == null:
		return
	_puls_zeit += delta
	_update_ausdauer()
	_update_sprung_puls()
	_update_banner()
	if _callout_t > 0.0:
		_callout_t -= delta
		_callout.modulate.a = clampf(_callout_t / 0.35, 0.0, 1.0)
	if zuegel_modus and _zuegel_halte_s >= 0.0:
		_zuegel_halte_s += delta
		_ziel_gangart(Touch.zuegel_gangart(_zuegel_halte_s))
	# _draw() zeichnet NUR den Floating-Stick (Ausdauer/Puls/Callout laufen
	# über eigene Child-Controls) — redraw nur solange der Stick liegt,
	# plus 1 Frame zum Wegwischen nach dem Loslassen.
	var stick_aktiv := _stick_finger >= 0
	if stick_aktiv or _stick_gezeichnet:
		queue_redraw()
	_stick_gezeichnet = stick_aktiv


func _gui_input(event: InputEvent) -> void:
	var als_touch := _als_touch(event)
	if als_touch.is_empty():
		return
	accept_event()
	var idx := int(als_touch["index"])
	var pos: Vector2 = als_touch["position"]
	match str(als_touch["typ"]):
		"start":
			_touch_start(idx, pos)
		"drag":
			_touch_drag(idx, pos)
		"ende":
			_touch_ende(idx, pos)


## Der Floating-Stick zeichnet sich selbst (Basisring + Knubbel).
func _draw() -> void:
	if _stick_finger < 0:
		return
	var radius := Touch.STICK_RADIUS_DP * _dp_skala()
	draw_circle(_stick_start, radius, Color(CREME.r, CREME.g, CREME.b, 0.22))
	draw_arc(_stick_start, radius, 0.0, TAU, 40, Color(INK.r, INK.g, INK.b, 0.5), 3.0)
	var knubbel := _stick_start + (_stick_punkt - _stick_start).limit_length(radius)
	draw_circle(knubbel, radius * 0.34, Color(TEAL.r, TEAL.g, TEAL.b, 0.85))


## ------------------------------------------------------------- Touch-Logik


func _touch_start(idx: int, pos: Vector2) -> void:
	var links := _ist_links(pos)
	if zuegel_modus and not links:
		_zuegel_halte_s = 0.0
		return
	if links and _stick_finger < 0:
		_stick_finger = idx
		_stick_start = pos
		_stick_punkt = pos
	elif not links and _wisch_finger < 0:
		_wisch_finger = idx
		_wisch_start = pos
		_wisch_start_ms = Time.get_ticks_msec()


func _touch_drag(idx: int, pos: Vector2) -> void:
	if idx == _stick_finger and controller != null:
		_stick_punkt = pos
		var lenk := Touch.stick_lenkung(_stick_start, pos, _dp_skala())
		controller.steer_input(-lenk if linkshaender else lenk)


func _touch_ende(idx: int, pos: Vector2) -> void:
	if zuegel_modus and _zuegel_halte_s >= 0.0 and idx != _stick_finger:
		_zuegel_halte_s = -1.0
		if controller != null:
			_ziel_gangart(Touch.zuegel_loslassen(controller.gait))
		return
	if idx == _stick_finger:
		_stick_finger = -1
		if controller != null:
			controller.steer_input(0.0)
	elif idx == _wisch_finger:
		_wisch_finger = -1
		var dauer := float(Time.get_ticks_msec() - _wisch_start_ms)
		match Touch.wisch_richtung(_wisch_start, pos, dauer, _dp_skala()):
			"hoch":
				if controller != null:
					controller.gait_up()
			"runter":
				if controller != null:
					controller.gait_down()


## Gangart schrittweise Richtung Wunsch schalten (Zuegel-Modus).
func _ziel_gangart(wunsch: String) -> void:
	if controller == null or wunsch == controller.gait:
		return
	var reihe := Stats.GANGARTEN_TOELT
	if reihe.find(wunsch) > reihe.find(controller.gait):
		controller.gait_up()
	else:
		controller.gait_down()


## Touch/Maus vereinheitlichen: {"typ": start|drag|ende, index, position}.
func _als_touch(event: InputEvent) -> Dictionary:
	if event is InputEventScreenTouch:
		var t := event as InputEventScreenTouch
		return {"typ": "start" if t.pressed else "ende", "index": t.index, "position": t.position}
	if event is InputEventScreenDrag:
		var d := event as InputEventScreenDrag
		return {"typ": "drag", "index": d.index, "position": d.position}
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == 1:
		var m := event as InputEventMouseButton
		return {"typ": "start" if m.pressed else "ende", "index": 99, "position": m.position}
	if event is InputEventMouseMotion and (event as InputEventMouseMotion).button_mask & 1:
		return {"typ": "drag", "index": 99, "position": (event as InputEventMouseMotion).position}
	return {}


func _ist_links(pos: Vector2) -> bool:
	return Touch.spiegel_x(pos.x, size.x, linkshaender) < size.x * 0.5


func _dp_skala() -> float:
	var fenster := get_window()
	return maxf(0.5, fenster.content_scale_factor if fenster != null else 1.0)


## ---------------------------------------------------------------- Aufbau


func _baue_ui() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(16.0, 16.0)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	var titel := Label.new()
	titel.text = I18nService.t("rpferd.reiten.ausdauer")
	titel.add_theme_font_size_override("font_size", 14)
	box.add_child(titel)
	var balken := ColorRect.new()
	balken.color = Color(INK.r, INK.g, INK.b, 0.25)
	balken.custom_minimum_size = Vector2(_ausdauer_max_px, 14.0)
	balken.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(balken)
	_ausdauer_fill = ColorRect.new()
	_ausdauer_fill.color = TEAL
	_ausdauer_fill.size = Vector2(_ausdauer_max_px, 14.0)
	_ausdauer_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	balken.add_child(_ausdauer_fill)
	_gang_chip = Label.new()
	_gang_chip.add_theme_font_size_override("font_size", 16)
	box.add_child(_gang_chip)
	_callout = Label.new()
	_callout.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_callout.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_callout.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_callout.add_theme_font_size_override("font_size", 44)
	_callout.add_theme_color_override("font_color", GOLD)
	_callout.add_theme_color_override("font_outline_color", INK)
	_callout.add_theme_constant_override("outline_size", 8)
	_callout.position.y -= 90.0
	_callout.modulate.a = 0.0
	_callout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_callout)
	_banner = Label.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.position.y -= 140.0
	_banner.add_theme_font_size_override("font_size", 20)
	_banner.add_theme_color_override("font_color", CREME)
	_banner.add_theme_color_override("font_outline_color", INK)
	_banner.add_theme_constant_override("outline_size", 6)
	_banner.visible = false
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)
	_streicheln_btn = Button.new()
	_streicheln_btn.text = I18nService.t("rpferd.reiten.streicheln")
	_streicheln_btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_streicheln_btn.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_streicheln_btn.position.y -= 100.0
	_streicheln_btn.visible = false
	_streicheln_btn.pressed.connect(_on_streicheln)
	add_child(_streicheln_btn)
	var dp := Touch.button_dp(button_wunsch_dp) * _dp_skala()
	_sprung_btn = Button.new()
	_sprung_btn.text = I18nService.t("rpferd.reiten.springen")
	_sprung_btn.custom_minimum_size = Vector2(dp, dp)
	_sprung_btn.pivot_offset = Vector2(dp, dp) * 0.5
	_sprung_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_sprung_btn.position -= Vector2(dp + 24.0, dp + 24.0)
	_sprung_btn.pressed.connect(_on_sprung)
	add_child(_sprung_btn)
	if linkshaender:
		_sprung_btn.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
		_sprung_btn.position += Vector2(24.0, -(dp + 24.0))


## ------------------------------------------------------------ Aktualisieren


func _update_ausdauer() -> void:
	var anteil := clampf(controller.ausdauer / maxf(1.0, controller.ausdauer_max()), 0.0, 1.0)
	_ausdauer_fill.size.x = _ausdauer_max_px * anteil
	_ausdauer_fill.color = TEAL if anteil > 0.25 else ROSA


func _update_gang_chip() -> void:
	if controller == null:
		return
	_gang_chip.text = I18nService.t("rpferd.gang.%s" % controller.gait)


func _update_sprung_puls() -> void:
	var dist := controller.naechstes_hindernis_m()
	if Touch.sprung_button_pulsiert(dist):
		_sprung_btn.scale = Vector2.ONE * (1.0 + 0.08 * sin(_puls_zeit * TAU * 2.2))
	else:
		_sprung_btn.scale = Vector2.ONE


func _update_banner() -> void:
	_streicheln_btn.visible = controller.zweiter_wind_bereit()
	if controller.ausdauer <= Feel.ZWEITER_WIND_AB and _callout_t <= 0.0:
		_banner.text = I18nService.t("rpferd.reiten.puste_leer")
		_banner.visible = true
	elif _banner.text == I18nService.t("rpferd.reiten.puste_leer"):
		_banner.visible = controller.ausdauer <= Feel.ZWEITER_WIND_AB


## ------------------------------------------------------------------ Events


func _on_sprung() -> void:
	if controller != null:
		controller.jump()


func _on_streicheln() -> void:
	if controller != null:
		controller.zweiter_wind()


func _on_sprung_gewertet(wertung: String, _punkte: int) -> void:
	if wertung == "daneben":
		return
	_callout.text = I18nService.t(
		"rpferd.reiten.%s" % ("perfekt" if wertung == "perfekt" else "gut")
	)
	_callout.add_theme_color_override("font_color", GOLD if wertung == "perfekt" else CREME)
	_callout.modulate.a = 1.0
	_callout_t = 1.1
	AudioDirector.try_play(self, "mg_perfect" if wertung == "perfekt" else "mg_good")


func _on_erschoepft() -> void:
	_banner.text = I18nService.t("rpferd.reiten.puste_leer")
	_banner.visible = true


func _on_zweiter_wind(_bonus: float) -> void:
	_banner.visible = false
	_callout.text = I18nService.t("rpferd.reiten.zweiter_wind")
	_callout.add_theme_color_override("font_color", TEAL)
	_callout.modulate.a = 1.0
	_callout_t = 1.2
	AudioDirector.try_play(self, "mg_good", 1.1)
