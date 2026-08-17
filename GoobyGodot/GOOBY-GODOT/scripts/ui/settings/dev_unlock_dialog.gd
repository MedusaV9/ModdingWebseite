class_name DevUnlockDialog
extends Control
## RW-7 — Warn-Dialog fuer den versteckten Entwicklermodus (Doc §5.1):
## nach 3 Tipps auf das aktive "Deutsch" zeigt der Settings-Screen diesen
## Vollbild-Dialog. Bestaetigt wird NICHT per Klick, sondern durch
## 2 Sekunden HALTEN des Buttons (DevTrigger.HOLD_MS) — dadurch kann das
## Menue niemand versehentlich aktivieren. Loslassen setzt den Fortschritt
## zurueck; Abbrechen/Scrim-Tap schliesst ohne Aktivierung.
##
## Headless testbar: `_process(delta)` laesst sich direkt mit simulierten
## Delta-Zeiten aufrufen, `_holding` wird ueber button_down/up gesetzt.

signal confirmed
signal cancelled

const SCRIM_COLOR := Color(0.11, 0.09, 0.08, 0.72)

## Halte-Dauer bis zur Bestaetigung (ms) — Quelle: DevTrigger.HOLD_MS.
var hold_ms := DevTrigger.HOLD_MS

var _holding := false
var _hold_accum_ms := 0.0
var _done := false
var _progress: ProgressBar
var _hold_btn: Button
var _f := 1.0
var _tf := 1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_f = UiScale.for_viewport(get_viewport())
	_tf = UiScale.font_scale(get_viewport())
	_build()
	FocusNavigation.grab_first_deferred(self)


func _process(delta: float) -> void:
	if _done or not _holding:
		return
	_hold_accum_ms += delta * 1000.0
	if _progress != null:
		_progress.value = hold_progress()
	if _hold_accum_ms >= float(hold_ms):
		_done = true
		confirmed.emit()
		queue_free()


## Fortschritt 0..1 der Halte-Bestaetigung (fuer UI + Tests).
func hold_progress() -> float:
	return clampf(_hold_accum_ms / float(hold_ms), 0.0, 1.0)


func _build() -> void:
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = SCRIM_COLOR
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.gui_input.connect(_on_scrim_input)
	add_child(scrim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var card := PanelContainer.new()
	card.name = "WarnCard"
	card.theme_type_variation = "AcCard"
	var canvas := Vector2(get_viewport().get_visible_rect().size)
	card.custom_minimum_size = Vector2(minf(520.0 * _f, canvas.x - 48.0), 0.0)
	center.add_child(card)
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override("separation", int(12.0 * _f))
	card.add_child(rows)
	var title := Label.new()
	title.name = "WarnTitle"
	title.theme_type_variation = "TitleLabel"
	title.text = I18nService.t("dev.warnung_titel")
	title.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_TITLE * _tf))
	rows.add_child(title)
	var body := Label.new()
	body.name = "WarnBody"
	body.theme_type_variation = "SoftLabel"
	body.text = I18nService.t("dev.warnung_text")
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BODY * _tf))
	rows.add_child(body)
	_progress = ProgressBar.new()
	_progress.name = "HoldProgress"
	_progress.min_value = 0.0
	_progress.max_value = 1.0
	_progress.value = 0.0
	_progress.show_percentage = false
	_progress.custom_minimum_size = Vector2(0.0, 10.0 * _f)
	rows.add_child(_progress)
	_hold_btn = SquishButton.new()
	_hold_btn.name = "HoldButton"
	_hold_btn.theme_type_variation = "BtnYellow"
	_hold_btn.text = I18nService.t("dev.halten")
	_hold_btn.focus_mode = Control.FOCUS_ALL
	_hold_btn.custom_minimum_size = Vector2(0.0, 56.0 * _f)
	_hold_btn.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BUTTON * _tf))
	_hold_btn.button_down.connect(_on_hold_down)
	_hold_btn.button_up.connect(_on_hold_up)
	rows.add_child(_hold_btn)
	var cancel := SquishButton.new()
	cancel.name = "CancelButton"
	cancel.theme_type_variation = "BtnTeal"
	cancel.text = I18nService.t("ui.abbrechen")
	cancel.focus_mode = Control.FOCUS_ALL
	cancel.custom_minimum_size = Vector2(0.0, 48.0 * _f)
	cancel.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BUTTON * _tf))
	cancel.pressed.connect(_cancel)
	rows.add_child(cancel)


func _on_hold_down() -> void:
	_holding = true
	_hold_accum_ms = 0.0
	if is_inside_tree():
		Haptics.tap(self)


func _on_hold_up() -> void:
	_holding = false
	_hold_accum_ms = 0.0
	if _progress != null:
		_progress.value = 0.0


func _on_scrim_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_cancel()


func _cancel() -> void:
	if _done:
		return
	_done = true
	cancelled.emit()
	queue_free()
