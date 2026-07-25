class_name EmoteWheel
extends Control
## Emote-Rad fürs Brettspiel (W3c VISIT): 4 Emotes (BoardEmotes) im Kreis,
## Layout über BoardEmotes.wheel_position (pur getestet). toggle() öffnet/
## schließt; Auswahl feuert emote_picked und schließt das Rad.

signal emote_picked(emote_id: String)

const RADIUS := 96.0
const BUTTON_SIZE := Vector2(88, 44)


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(RADIUS, RADIUS) * 2.0 + BUTTON_SIZE
	var ids := BoardEmotes.ids()
	for index in ids.size():
		var emote_id := ids[index]
		var btn := Button.new()
		btn.theme_type_variation = &"BtnTeal"
		btn.text = I18nService.t(str(BoardEmotes.def(emote_id).get("label_key", "")))
		btn.custom_minimum_size = BUTTON_SIZE
		var offset := BoardEmotes.wheel_position(index, ids.size(), RADIUS)
		btn.position = size * 0.5 + offset - BUTTON_SIZE * 0.5
		btn.pressed.connect(_on_pick.bind(emote_id))
		add_child(btn)
	resized.connect(_relayout)
	_relayout()


func toggle() -> void:
	visible = not visible


func _on_pick(emote_id: String) -> void:
	visible = false
	emote_picked.emit(emote_id)


func _relayout() -> void:
	var ids := BoardEmotes.ids()
	var index := 0
	for child in get_children():
		if child is Button:
			var offset := BoardEmotes.wheel_position(index, ids.size(), RADIUS)
			(child as Button).position = size * 0.5 + offset - BUTTON_SIZE * 0.5
			index += 1
