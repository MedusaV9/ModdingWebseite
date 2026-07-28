class_name DialogBubble
extends Control
## Text-Bubble für Gooby-Sprüche (DEUTSCH über strings/). Zeigt eine
## Zeilen-Sequenz; JEDER Tap auf die Bubble blättert weiter („Weiter-Tap“).
## Signale: `advanced(index)` pro Blättern, `finished` nach der letzten Zeile.

signal advanced(index: int)
signal finished

## Breiten-Deckel in Design-px (skaliert mit UiScale) — Web-Karten ≤ 600.
const MAX_WIDTH_PX := 600.0
## Luft zwischen Blase und HUD-Bodenzeile bzw. Safe-Area-Unterkante.
const BOTTOM_GAP := 10.0

var _lines: Array[String] = []
var _index := -1
var _hud_ref: Control

@onready var _bubble: PanelContainer = %Bubble
@onready var _text: Label = %BubbleText
@onready var _hint: Label = %BubbleHint


func _ready() -> void:
	visible = false
	_hint.text = I18nService.t("dialog.weiter_hinweis")
	_bubble.gui_input.connect(_on_bubble_input)
	get_viewport().size_changed.connect(_relayout)
	_relayout()


## Sequenz anzeigen (ersetzt eine laufende Sequenz).
func show_lines(lines: Array[String]) -> void:
	if lines.is_empty():
		return
	_lines = lines.duplicate()
	_index = -1
	visible = true
	_relayout()
	_advance()


## UIFINAL: Im Home-HUD-Kontext lag die Blase HINTER der Boden-Zeile (Auge/
## „Wo ist mein Gooby?“-Chip schnitten in den Text) und ignorierte Safe-Area
## + UiScale. Läuft ein HUD mit, weicht die Blase dessen Boden-Zeile aus und
## skaliert ihre Schriften; ohne HUD (Stadt-Dialoge) bleibt die Szenen-
## Geometrie unangetastet — deren Options-Stapel rechnet mit ihr.
func _relayout() -> void:
	if _bubble == null or not is_inside_tree():
		return
	var hud := _find_hud()
	if hud == null or not hud.is_visible_in_tree():
		return
	var f := UiScale.for_viewport(get_viewport())
	var canvas := Vector2(get_viewport().get_visible_rect().size)
	var insets := UiScale.safe_insets_canvas(get_viewport())
	_text.add_theme_font_size_override("font_size", int(maxf(AcTokens.FONT_SIZE_BODY * f, 12.0)))
	_hint.add_theme_font_size_override("font_size", int(maxf(AcTokens.FONT_SIZE_CAPTION * f, 10.0)))
	var safe_w := canvas.x - float(insets["left"]) - float(insets["right"])
	var width := minf(MAX_WIDTH_PX * f, safe_w - 24.0 * f)
	var lane_top: float = canvas.y - float(insets["bottom"])
	if hud is Hud:
		var lane: Dictionary = (hud as Hud).bubble_lane()
		lane_top = float(lane["top"])
		width = minf(width, float(lane["width"]))
	_bubble.offset_left = -width / 2.0
	_bubble.offset_right = width / 2.0
	_bubble.offset_bottom = -(canvas.y - lane_top) - BOTTOM_GAP * f
	# Höhe folgt dem Inhalt (Autowrap braucht die finale Breite — deshalb
	# nach einem Frame nachziehen, s. whats_next_hint._relayout_settled).
	_fit_height()
	_fit_height_settled()


func _fit_height() -> void:
	var needed := _bubble.get_combined_minimum_size().y
	_bubble.offset_top = _bubble.offset_bottom - maxf(needed, 96.0)


func _fit_height_settled() -> void:
	var tree := get_tree()
	if tree == null:
		return
	await tree.process_frame
	if is_instance_valid(self) and _bubble != null and is_instance_valid(_bubble):
		_fit_height()


func _find_hud() -> Control:
	if _hud_ref != null and is_instance_valid(_hud_ref):
		return _hud_ref
	_hud_ref = null
	var tree := get_tree()
	if tree == null:
		return null
	for node: Node in tree.root.find_children("*", "Control", true, false):
		if node is Hud:
			_hud_ref = node
			break
	return _hud_ref


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
