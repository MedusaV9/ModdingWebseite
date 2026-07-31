class_name VisitHud
extends CanvasLayer
## HUD der Besuchs-Szene (W3c VISIT): Banner „Zu Besuch bei …“, Peer-Status
## („X ist in der Küche“ statt Rendern, Doc C §3.4 Punkt 4), Raumwechsel-
## Leiste, Besuch-beenden-Knopf, Toasts und (nur Host) die Mini-Bau-Leiste
## („Bauen bleibt erlaubt“ — Items aus dem Lager platzieren / entfernen).

signal end_pressed
signal room_selected(room_id: String)
signal build_toggled(active: bool)
signal build_item_selected(item_id: String)
signal remove_mode_toggled(active: bool)

const MAX_BUILD_ITEMS := 6

var toast: ToastLayer

var _title: Label
var _peer_status: Label
var _rooms_box: HBoxContainer
var _build_button: Button
var _build_bar: HBoxContainer
var _remove_button: Button
var _item_buttons: Dictionary = {}
var _selected_item := ""


func _ready() -> void:
	layer = 5
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 10.0
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)
	_title = Label.new()
	_title.theme_type_variation = &"TitleLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Outline: das Banner steht oft vor weißen Raumwänden.
	_title.add_theme_color_override("font_outline_color", Color(0.25, 0.18, 0.12))
	_title.add_theme_constant_override("outline_size", 8)
	top.add_child(_title)
	_peer_status = Label.new()
	_peer_status.theme_type_variation = &"CaptionLabel"
	_peer_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_peer_status.add_theme_color_override("font_outline_color", Color(0.25, 0.18, 0.12))
	_peer_status.add_theme_constant_override("outline_size", 6)
	top.add_child(_peer_status)

	var end_button := Button.new()
	end_button.theme_type_variation = &"AccentButton"
	end_button.text = I18nService.t("social.visit.end_button")
	end_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	end_button.position = Vector2(-16.0, 12.0)
	end_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	end_button.pressed.connect(func() -> void: end_pressed.emit())
	root.add_child(end_button)

	var bottom := VBoxContainer.new()
	bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	bottom.offset_bottom = -12.0
	bottom.offset_top = -140.0
	bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bottom.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(bottom)
	_build_bar = HBoxContainer.new()
	_build_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_build_bar.add_theme_constant_override("separation", 6)
	_build_bar.visible = false
	bottom.add_child(_build_bar)
	_rooms_box = HBoxContainer.new()
	_rooms_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_rooms_box.add_theme_constant_override("separation", 6)
	bottom.add_child(_rooms_box)

	toast = ToastLayer.new()
	root.add_child(toast)
	# ToastLayer setzt in _ready nur die Anker — kommt er in einen bereits
	# gelayouteten Parent, bleibt sein Rect leer → hier explizit aufziehen.
	toast.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func set_title(text: String) -> void:
	_title.text = text


func set_peer_status(text: String) -> void:
	_peer_status.text = text


func show_toast(text: String) -> void:
	toast.show_toast(text)


## Raumwechsel-Leiste aus den Snapshot-Räumen (Namen via home.raum.*).
func set_rooms(room_ids: Array[String], active_id: String) -> void:
	for child in _rooms_box.get_children():
		child.queue_free()
	for room_id in room_ids:
		var btn := Button.new()
		btn.theme_type_variation = &"BtnTeal" if room_id == active_id else &"GhostButton"
		btn.text = _room_label(room_id)
		btn.disabled = room_id == active_id
		btn.pressed.connect(func() -> void: room_selected.emit(room_id))
		_rooms_box.add_child(btn)


## Host-Bau-Leiste: Toggle + Lager-Items + Entfernen-Modus.
func enable_build_controls(storage_items: Array) -> void:
	if _build_button != null:
		return
	_build_button = Button.new()
	_build_button.theme_type_variation = &"PrimaryButton"
	_build_button.toggle_mode = true
	_build_button.text = I18nService.t("social.visit.build_button")
	_build_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_build_button.position = Vector2(-16.0, -160.0)
	_build_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_build_button.toggled.connect(_on_build_toggled)
	(get_child(0) as Control).add_child(_build_button)
	_remove_button = Button.new()
	_remove_button.theme_type_variation = &"GhostButton"
	_remove_button.toggle_mode = true
	_remove_button.text = "✕"
	_remove_button.toggled.connect(func(active: bool) -> void: remove_mode_toggled.emit(active))
	_build_bar.add_child(_remove_button)
	var shown := 0
	for entry: Variant in storage_items:
		if shown >= MAX_BUILD_ITEMS or not (entry is Dictionary):
			continue
		var item_id := str((entry as Dictionary).get("item", ""))
		var def := FurnitureCatalog.def(item_id)
		if def.is_empty():
			continue
		# W13B: WALL und CEILING bleiben Besuchs-tabu — die Bau-Leiste
		# platziert nur Boden-Ebenen (CEILING kam mit dem Girlanden-Layer
		# dazu und wäre sonst implizit erlaubt gewesen).
		var item_layer := int(def["layer"])
		if item_layer == GridData.Layer.WALL or item_layer == GridData.Layer.CEILING:
			continue
		var btn := Button.new()
		btn.theme_type_variation = &"GhostButton"
		btn.toggle_mode = true
		btn.text = str(def.get("name", item_id))
		btn.toggled.connect(_on_item_toggled.bind(item_id))
		_build_bar.add_child(btn)
		_item_buttons[item_id] = btn
		shown += 1


func selected_item() -> String:
	return _selected_item


func _on_build_toggled(active: bool) -> void:
	_build_bar.visible = active
	build_toggled.emit(active)


func _on_item_toggled(active: bool, item_id: String) -> void:
	if active:
		_selected_item = item_id
		if _remove_button != null:
			_remove_button.button_pressed = false
		for other_id: String in _item_buttons:
			if other_id != item_id:
				(_item_buttons[other_id] as Button).button_pressed = false
	elif _selected_item == item_id:
		_selected_item = ""
	build_item_selected.emit(_selected_item)


func _room_label(room_id: String) -> String:
	var key := "home.raum.%s" % room_id
	return I18nService.t(key) if I18nService.has_key(key) else room_id.capitalize()
