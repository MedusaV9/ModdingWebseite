class_name PanelSheet
extends Control
## Bottom-Sheet im AC-2.0-Look: Veil-Backdrop + Paper-Karte (Radius 36),
## die von unten hereinfedert. Backdrop-Dismiss-Policy wie im Web:
## ein Tap auf den Backdrop schließt NUR das oberste Sheet (`PanelStack`).
##
## Nutzung: Szene `panel_sheet.tscn` instanzieren, `add_content(node)`,
## dann `open()`. `closed`-Signal abonnieren.

signal opened
signal closed

var _open := false

@onready var _backdrop: ColorRect = %Backdrop
@onready var _sheet: PanelContainer = %Sheet
@onready var _title_label: Label = %SheetTitle
@onready var _body: MarginContainer = %SheetBody


func _ready() -> void:
	visible = false
	_backdrop.color = AcTokens.VEIL
	_backdrop.gui_input.connect(_on_backdrop_input)


## Titel setzen ("" blendet die Titelzeile aus).
func set_title(text: String) -> void:
	_title_label.text = text
	_title_label.visible = not text.is_empty()


## Inhalt einhängen (ersetzt vorherigen Inhalt).
func add_content(node: Control) -> void:
	for child in _body.get_children():
		child.queue_free()
	_body.add_child(node)


func open() -> void:
	if _open:
		return
	AudioDirector.try_play(self, "ui_open")
	_open = true
	visible = true
	PanelStack.push(self)
	opened.emit()
	if ThemeService.is_reduced_motion(self):
		return
	_sheet.position.y += 60.0
	_sheet.modulate.a = 0.0
	var tween := create_tween().set_parallel()
	tween.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(_sheet, "position:y", _sheet.position.y - 60.0, AcTokens.DUR_SHEET)
	tween.tween_property(_sheet, "modulate:a", 1.0, AcTokens.DUR_SHEET / 2.0)


func close() -> void:
	if not _open:
		return
	AudioDirector.try_play(self, "ui_close")
	_open = false
	PanelStack.remove(self)
	visible = false
	closed.emit()


func is_open() -> bool:
	return _open


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if PanelStack.is_top(self):
			close()
