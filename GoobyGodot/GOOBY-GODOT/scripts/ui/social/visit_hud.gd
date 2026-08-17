class_name VisitHud
extends CanvasLayer
## HUD der Besuchs-Szene (W3c VISIT): Banner „Zu Besuch bei …“, Peer-Status
## („X ist in der Küche“ statt Rendern, Doc C §3.4 Punkt 4), Raumwechsel-
## Leiste, Besuch-beenden-Knopf, Toasts und (nur Host) die Mini-Bau-Leiste
## („Bauen bleibt erlaubt“ — Items aus dem Lager platzieren / entfernen).
##
## G3 P06 (Fixliste F8 + g1/ui-onboarding 2.9.2): keine Ecken-Kleber mehr —
## „Besuch beenden“ sitzt in einer Safe-Area-Kopfzeile rechts, Selfie/Bauen
## (+ VisitManager-Aktionen via add_action_button) in EINER zentrierten
## Bottom-Aktionszeile über der Raumleiste. Raum-/Bau-Leisten brechen als
## HFlowContainer im Hochformat um; alle Knöpfe sind SquishButtons mit
## Touch-Floor und die Handler spielen SfxMap-Ids (Audio-Grammatik §3).

signal end_pressed
signal room_selected(room_id: String)
signal build_toggled(active: bool)
signal build_item_selected(item_id: String)
signal remove_mode_toggled(active: bool)
## W13C FOTOWERK (C §3.9): „Snap A Gooby!“-Selfie-Knopf gedrückt.
signal selfie_pressed

const MAX_BUILD_ITEMS := 6
## Reservierte Höhe der Bottom-Zone (Design-px, × f) — Platz für Bau-Leiste
## im Umbruch + Aktionszeile + Raumleiste; alignment END hält alles unten.
const BOTTOM_RESERVE := 320.0

var toast: ToastLayer

var _root: Control
var _top: VBoxContainer
var _bottom: VBoxContainer
var _title: Label
var _peer_status: Label
var _end_button: Button
var _selfie_button: Button
var _actions_box: HFlowContainer
var _rooms_box: HFlowContainer
var _build_button: Button
var _build_bar: HFlowContainer
var _remove_button: Button
var _item_buttons: Dictionary = {}
var _selected_item := ""


func _ready() -> void:
	layer = 5
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	# Kopfzeile: Titel/Status mittig, „Besuch beenden“ rechts — beides in
	# EINER Zeile innerhalb der Safe-Area (statt Ecken-Kleber oben rechts).
	_top = VBoxContainer.new()
	_top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_top)
	var head_row := HBoxContainer.new()
	head_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.add_child(head_row)
	var left_pad := Control.new()
	left_pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head_row.add_child(left_pad)
	var title_box := VBoxContainer.new()
	title_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head_row.add_child(title_box)
	_title = Label.new()
	_title.theme_type_variation = &"TitleLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	# Outline: das Banner steht oft vor weißen Raumwänden.
	_title.add_theme_color_override("font_outline_color", Color(0.25, 0.18, 0.12))
	_title.add_theme_constant_override("outline_size", 8)
	title_box.add_child(_title)
	_peer_status = Label.new()
	_peer_status.theme_type_variation = &"CaptionLabel"
	_peer_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_peer_status.add_theme_color_override("font_outline_color", Color(0.25, 0.18, 0.12))
	_peer_status.add_theme_constant_override("outline_size", 6)
	title_box.add_child(_peer_status)
	var right_box := HBoxContainer.new()
	right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_box.alignment = BoxContainer.ALIGNMENT_END
	right_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head_row.add_child(right_box)
	_end_button = SquishButton.new()
	_end_button.theme_type_variation = &"AccentButton"
	_end_button.text = I18nService.t("social.visit.end_button")
	_end_button.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_end_button.pressed.connect(_on_end_pressed)
	right_box.add_child(_end_button)

	# Bottom-Zone (alignment END): Bau-Leiste → Aktionszeile → Raumleiste.
	# Alle drei zentriert, Umbruch im Hochformat statt Überlauf.
	_bottom = VBoxContainer.new()
	_bottom.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bottom.alignment = BoxContainer.ALIGNMENT_END
	_bottom.add_theme_constant_override("separation", 8)
	_root.add_child(_bottom)
	_build_bar = HFlowContainer.new()
	_build_bar.alignment = FlowContainer.ALIGNMENT_CENTER
	_build_bar.add_theme_constant_override("h_separation", 6)
	_build_bar.add_theme_constant_override("v_separation", 6)
	_build_bar.visible = false
	_bottom.add_child(_build_bar)
	_actions_box = HFlowContainer.new()
	_actions_box.alignment = FlowContainer.ALIGNMENT_CENTER
	_actions_box.add_theme_constant_override("h_separation", 8)
	_actions_box.add_theme_constant_override("v_separation", 6)
	_bottom.add_child(_actions_box)
	# W13C FOTOWERK (C §3.9): „Snap A Gooby!“ — Besuchs-Selfie, jetzt in der
	# zentrierten Aktionszeile statt in der linken Ecke. Selbstverdrahtet
	# (Parent = VisitScene, duck-typed), das Signal feuert zusätzlich.
	_selfie_button = SquishButton.new()
	_selfie_button.name = "SelfieButton"
	_selfie_button.theme_type_variation = &"BtnTeal"
	_selfie_button.text = I18nService.t("social.selfie.emote")
	_selfie_button.pressed.connect(_on_selfie_pressed)
	_actions_box.add_child(_selfie_button)
	_rooms_box = HFlowContainer.new()
	_rooms_box.alignment = FlowContainer.ALIGNMENT_CENTER
	_rooms_box.add_theme_constant_override("h_separation", 6)
	_rooms_box.add_theme_constant_override("v_separation", 6)
	_bottom.add_child(_rooms_box)

	toast = ToastLayer.new()
	_root.add_child(toast)
	# ToastLayer setzt in _ready nur die Anker — kommt er in einen bereits
	# gelayouteten Parent, bleibt sein Rect leer → hier explizit aufziehen.
	toast.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	get_viewport().size_changed.connect(_relayout)
	_relayout()


## Safe-Area + UiScale + Touch-Floor auf Kopf-/Bottom-Zeile und alle
## (auch dynamischen) Knöpfe anwenden — läuft bei Rotation/Resize erneut.
func _relayout() -> void:
	if _root == null or not is_inside_tree():
		return
	var m := ScreenShell.metrics(get_viewport())
	var f: float = m["f"]
	var insets: Dictionary = m["insets"]
	_top.offset_left = float(insets["left"]) + 16.0 * f
	_top.offset_right = -float(insets["right"]) - 16.0 * f
	_top.offset_top = float(insets["top"]) + 10.0 * f
	_bottom.offset_left = float(insets["left"]) + 12.0 * f
	_bottom.offset_right = -float(insets["right"]) - 12.0 * f
	_bottom.offset_bottom = -float(insets["bottom"]) - 12.0 * f
	_bottom.offset_top = _bottom.offset_bottom - BOTTOM_RESERVE * f
	ScreenShell.scale_fonts(_root, f)
	ScreenShell.touch_target(_end_button, m)
	ScreenShell.touch_target(_selfie_button, m)
	for box: Control in [_actions_box, _rooms_box, _build_bar]:
		for child in box.get_children():
			if child is Button:
				ScreenShell.touch_target(child, m)


## Aktions-Knopf von außen (z. B. VisitManager „Aufwecken“/„Gemeinsam
## fahren“) in die zentrierte Bottom-Aktionszeile einreihen — damit unten
## EINE Daumenzonen-Zeile existiert statt eigener Ecken-Layer.
func add_action_button(btn: Button) -> void:
	_actions_box.add_child(btn)
	_relayout()


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
		var btn := SquishButton.new()
		btn.theme_type_variation = &"BtnTeal" if room_id == active_id else &"GhostButton"
		btn.text = _room_label(room_id)
		btn.disabled = room_id == active_id
		btn.pressed.connect(_on_room_pressed.bind(room_id))
		_rooms_box.add_child(btn)
	_relayout()


## Host-Bau-Leiste: Toggle + Lager-Items + Entfernen-Modus.
func enable_build_controls(storage_items: Array) -> void:
	if _build_button != null:
		return
	_build_button = SquishButton.new()
	_build_button.theme_type_variation = &"PrimaryButton"
	_build_button.toggle_mode = true
	_build_button.text = I18nService.t("social.visit.build_button")
	_build_button.toggled.connect(_on_build_toggled)
	_actions_box.add_child(_build_button)
	_remove_button = SquishButton.new()
	_remove_button.theme_type_variation = &"GhostButton"
	_remove_button.toggle_mode = true
	_remove_button.text = "✕"
	_remove_button.toggled.connect(_on_remove_toggled)
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
		var btn := SquishButton.new()
		btn.theme_type_variation = &"GhostButton"
		btn.toggle_mode = true
		btn.text = str(def.get("name", item_id))
		btn.toggled.connect(_on_item_toggled.bind(item_id))
		_build_bar.add_child(btn)
		_item_buttons[item_id] = btn
		shown += 1
	_relayout()


func selected_item() -> String:
	return _selected_item


func _on_end_pressed() -> void:
	AudioDirector.try_play(self, "ui_close")
	end_pressed.emit()


func _on_room_pressed(room_id: String) -> void:
	AudioDirector.try_play(self, "ui_chip")
	room_selected.emit(room_id)


func _on_build_toggled(active: bool) -> void:
	AudioDirector.try_play(self, "ui_toggle")
	_build_bar.visible = active
	build_toggled.emit(active)


func _on_remove_toggled(active: bool) -> void:
	AudioDirector.try_play(self, "ui_toggle")
	remove_mode_toggled.emit(active)


func _on_item_toggled(active: bool, item_id: String) -> void:
	# Ab-/Umwahl-Kaskade (button_pressed = false) feuert dieselbe Id erneut —
	# der 45-ms-Debounce des AudioDirector schluckt das Duplikat.
	AudioDirector.try_play(self, "ui_chip")
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


## W13C: Selfie starten — läuft nur einmal gleichzeitig (Overlay-Name-Guard).
func _on_selfie_pressed() -> void:
	AudioDirector.try_play(self, "ui_click")
	selfie_pressed.emit()
	var szene := get_parent()
	if szene == null or szene.get_node_or_null("SnapAGooby") != null:
		return
	SnapAGooby.starte(szene, get_node_or_null("/root/GameState"))
