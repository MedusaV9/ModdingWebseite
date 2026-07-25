class_name OrtDialogView
extends Control
## Dialog-View (W3a CITY, Doc E §2.4): rendert einen OrtDialogRunner —
## Text-Bubbles (W1c DialogBubble) + NPC-Gebrabbel (W1b GoobyVoice) +
## Options-Knöpfe. Effekte werden ANS ORT-SCRIPT gemeldet (Signal `effekt`),
## das GameState/Laden-Öffnen übernimmt (der Runner bleibt pure).

signal effekt(daten: Dictionary)
signal beendet

const BubbleScene := preload("res://scripts/ui/dialog_bubble.tscn")

var runner: OrtDialogRunner
var voice: GoobyVoice

var _bubble: DialogBubble
var _optionen_box: VBoxContainer


func _ready() -> void:
	# anchors+offsets (nicht nur anchors): _ready läuft NACH add_child —
	# set_anchors_preset allein lässt den Rect dann bei 0×0.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Bubble behält das Szenen-Layout (unten-breit) — Anker hier NICHT
	# überschreiben, sonst wandert sie über den oberen Schirmrand.
	_bubble = BubbleScene.instantiate()
	add_child(_bubble)
	_bubble.finished.connect(_on_bubble_finished)
	# Options-Stapel direkt ÜBER der Bubble, wächst nach oben.
	_optionen_box = VBoxContainer.new()
	_optionen_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_optionen_box.offset_left = -170.0
	_optionen_box.offset_right = 170.0
	_optionen_box.offset_top = -190.0
	_optionen_box.offset_bottom = -190.0
	_optionen_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_optionen_box.custom_minimum_size = Vector2(340.0, 0.0)
	_optionen_box.add_theme_constant_override("separation", 10)
	add_child(_optionen_box)


## Dialog starten (Baum + Flags kommen vom Ort-Script).
func starte(dialog_baum: Dictionary, flags: Dictionary) -> void:
	runner = OrtDialogRunner.new(dialog_baum, flags)
	if not runner.ist_geladen():
		beendet.emit()
		return
	_zeige_knoten()


func _zeige_knoten() -> void:
	for kind in _optionen_box.get_children():
		kind.queue_free()
	var zeilen := runner.text()
	if voice != null and not zeilen.is_empty():
		voice.sagt(zeilen[0])
	_bubble.show_lines(zeilen)


func _on_bubble_finished() -> void:
	for eintrag in runner.effekte():
		effekt.emit(eintrag)
	if runner.ist_ende():
		beendet.emit()
		return
	if runner.optionen().is_empty() and runner.weiter():
		_zeige_knoten()
		return
	var optionen := runner.optionen()
	for i in optionen.size():
		var btn := Button.new()
		btn.text = str(optionen[i]["text"])
		btn.theme_type_variation = "AccentButton"
		btn.pressed.connect(_on_option.bind(i))
		_optionen_box.add_child(btn)


func _on_option(index: int) -> void:
	if runner.waehlen(index):
		_zeige_knoten()
