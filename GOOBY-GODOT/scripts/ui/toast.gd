class_name ToastLayer
extends Control
## Sichtbarer Toast-Layer: genau EIN Toast gleichzeitig (Queue in
## `ToastQueue`, pure Logik). In eine Screen-Szene legen (Full-Rect,
## oberste UI-Ebene) und `show_toast("…")` rufen.

const HOLD_SEC := 2.2
const FADE_SEC := 0.18

var queue := ToastQueue.new()

var _panel: PanelContainer
var _label: Label
var _hold_timer: Timer


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel = PanelContainer.new()
	_panel.name = "ToastPanel"
	_panel.theme_type_variation = "StatusCapsule"
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	_panel.z_index = 100
	add_child(_panel)
	_label = Label.new()
	_label.name = "ToastText"
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(_label)
	_hold_timer = Timer.new()
	_hold_timer.one_shot = true
	_hold_timer.timeout.connect(_on_hold_done)
	add_child(_hold_timer)


## Toast anfordern; wird ggf. eingereiht (nie gestapelt). `error = true`
## spielt den Fehler-Blip (W4P1-SFX-Wiring: Erfolgs-Toasts bleiben stumm).
func show_toast(text: String, error := false) -> void:
	var accepted := queue.push(text)
	if accepted and error:
		AudioDirector.try_play(self, "ui_error")
	if accepted and queue.current().is_empty():
		_show_next()


func is_showing() -> bool:
	return _panel != null and _panel.visible


func _show_next() -> void:
	var text := queue.advance()
	if text.is_empty():
		_panel.visible = false
		return
	_label.text = text
	_panel.visible = true
	_panel.reset_size()
	_reposition()
	if not ThemeService.is_reduced_motion(self):
		_panel.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(_panel, "modulate:a", 1.0, FADE_SEC)
	else:
		_panel.modulate.a = 1.0
	_hold_timer.start(HOLD_SEC)


func _reposition() -> void:
	await get_tree().process_frame
	if not is_instance_valid(_panel):
		return
	var panel_size := _panel.size
	_panel.position = Vector2((size.x - panel_size.x) / 2.0, size.y * 0.12)


func _on_hold_done() -> void:
	if ThemeService.is_reduced_motion(self):
		_show_next()
		return
	var tween := create_tween()
	tween.tween_property(_panel, "modulate:a", 0.0, FADE_SEC)
	tween.tween_callback(_show_next)
