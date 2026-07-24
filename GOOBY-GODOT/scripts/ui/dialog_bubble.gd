class_name DialogBubble
extends Control
## Text-Bubble für Gooby-Sprüche (DEUTSCH über strings/). Zeigt eine
## Zeilen-Sequenz; JEDER Tap auf die Bubble blättert weiter („Weiter-Tap“).
## Signale: `advanced(index)` pro Blättern, `finished` nach der letzten Zeile.

signal advanced(index: int)
signal finished

var _lines: Array[String] = []
var _index := -1

@onready var _bubble: PanelContainer = %Bubble
@onready var _text: Label = %BubbleText
@onready var _hint: Label = %BubbleHint


func _ready() -> void:
	visible = false
	_hint.text = I18nService.t("dialog.weiter_hinweis")
	_bubble.gui_input.connect(_on_bubble_input)


## Sequenz anzeigen (ersetzt eine laufende Sequenz).
func show_lines(lines: Array[String]) -> void:
	if lines.is_empty():
		return
	_lines = lines.duplicate()
	_index = -1
	visible = true
	_advance()


func is_active() -> bool:
	return visible and _index >= 0


func current_line() -> String:
	return _text.text


func _advance() -> void:
	_index += 1
	if _index >= _lines.size():
		visible = false
		finished.emit()
		return
	_text.text = _lines[_index]
	_hint.visible = _index < _lines.size() - 1
	advanced.emit(_index)
	_pop()


func _pop() -> void:
	if ThemeService.is_reduced_motion(self):
		return
	_bubble.pivot_offset = _bubble.size / 2.0
	_bubble.scale = Vector2.ONE * 0.92
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_bubble, "scale", Vector2.ONE, AcTokens.DUR_POP)


func _on_bubble_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_advance()
