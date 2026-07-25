class_name FriendsScreen
extends Control
## Freunde-Screen (Doc C §3 / W2c §3, AC-Theme): eigener Freundes-Code groß,
## Hinzufügen per Code ODER Name, offene Anfragen (annehmen/ablehnen) und die
## Freundesliste (Name, Gooby-Spitzname, Presence-Label vom SERVER, Coins).
## Offline-first: ohne Verbindung bleibt der Screen hübsch benutzbar und
## zeigt „Offline — Freunde brauchen Internet“; alles aktualisiert sich live
## über die FriendsService-/NetClient-Signale. Net-Anbindung per Duck-Typing
## (/root/Net, Autoload-Request in project-godot-requests.md) oder Injektion.

signal back_requested

const ROUTE_FRIENDS := &"friends"
const ROUTES := {ROUTE_FRIENDS: "res://scripts/ui/friends/friends_screen.tscn"}

## Tests/Screenshots: NetClient-Instanz injizieren statt /root/Net.
var net_override: NetClient = null
## Tests: Navigation abschaltbar.
var auto_navigate := true

var _net: NetClient
var _status_chip: Button
var _code_value: Label
var _copy_button: Button
var _add_input: LineEdit
var _add_button: Button
var _add_feedback: Label
var _offline_hint: Label
var _requests_box: VBoxContainer
var _requests_title: Label
var _friends_box: VBoxContainer


## Freunde-Route am SceneRouter anmelden (idempotent, wie ArcadeScreen).
static func register_routes() -> void:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return
	var router := (loop as SceneTree).root.get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("register_routes"):
		router.register_routes(ROUTES)


func _ready() -> void:
	# and_offsets: nur-Anker-Preset behält den leeren Ist-Rect, wenn der
	# Parent beim Einhängen schon gelayoutet ist (Router-Wechsel/Screenshots).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	register_routes()
	_net = net_override
	if _net == null:
		var candidate := get_node_or_null("/root/Net")
		if candidate is NetClient:
			_net = candidate
	_build_ui()
	if _net != null:
		_net.status_changed.connect(_on_status_changed)
		if _net.friends != null:
			_net.friends.friends_changed.connect(_on_friends_changed)
			_net.friends.requests_changed.connect(_on_requests_changed)
			_net.friends.friend_code_changed.connect(func(_code: String) -> void: _refresh_code())
	_refresh_all()


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.98, 0.94, 0.87)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var rows := VBoxContainer.new()
	rows.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rows.offset_left = 24.0
	rows.offset_right = -24.0
	rows.offset_top = 16.0
	rows.offset_bottom = -16.0
	rows.add_theme_constant_override("separation", 12)
	add_child(rows)

	# Header: Zurück | Titel | Status-Chip.
	var header := HBoxContainer.new()
	rows.add_child(header)
	var back := Button.new()
	back.theme_type_variation = &"GhostButton"
	back.text = I18nService.t("net.friends.back")
	back.pressed.connect(_on_back_pressed)
	header.add_child(back)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = I18nService.t("net.friends.title")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)
	_status_chip = Button.new()
	header.add_child(_status_chip)

	_offline_hint = Label.new()
	_offline_hint.text = I18nService.t("net.friends.offline_hint")
	_offline_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_offline_hint.add_theme_color_override("font_color", FriendListUi.COLOR_HINT)
	rows.add_child(_offline_hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)

	# Eigener Freundes-Code — groß zum Zeigen/Abtippen.
	var code_card := PanelContainer.new()
	code_card.theme_type_variation = &"AcCard"
	content.add_child(code_card)
	var code_rows := VBoxContainer.new()
	code_rows.alignment = BoxContainer.ALIGNMENT_CENTER
	code_card.add_child(code_rows)
	var code_caption := Label.new()
	code_caption.theme_type_variation = &"CaptionLabel"
	code_caption.text = I18nService.t("net.friends.my_code")
	code_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_rows.add_child(code_caption)
	var code_row := HBoxContainer.new()
	code_row.alignment = BoxContainer.ALIGNMENT_CENTER
	code_row.add_theme_constant_override("separation", 10)
	code_rows.add_child(code_row)
	_code_value = Label.new()
	_code_value.theme_type_variation = &"TitleLabel"
	_code_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_row.add_child(_code_value)
	_copy_button = Button.new()
	_copy_button.name = "CopyButton"
	_copy_button.theme_type_variation = &"GhostButton"
	_copy_button.text = I18nService.t("net.friends.copy")
	_copy_button.pressed.connect(_on_copy_pressed)
	code_row.add_child(_copy_button)

	# Freund hinzufügen: Code ODER Name.
	var add_card := PanelContainer.new()
	add_card.theme_type_variation = &"AcCard"
	content.add_child(add_card)
	var add_rows := VBoxContainer.new()
	add_rows.add_theme_constant_override("separation", 8)
	add_card.add_child(add_rows)
	var add_title := Label.new()
	add_title.theme_type_variation = &"HeadlineLabel"
	add_title.text = I18nService.t("net.friends.add_title")
	add_rows.add_child(add_title)
	var add_row := HBoxContainer.new()
	add_row.add_theme_constant_override("separation", 8)
	add_rows.add_child(add_row)
	_add_input = LineEdit.new()
	_add_input.placeholder_text = I18nService.t("net.friends.add_placeholder")
	_add_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_input.text_submitted.connect(func(_text: String) -> void: _on_add_pressed())
	add_row.add_child(_add_input)
	_add_button = Button.new()
	_add_button.name = "AddButton"
	_add_button.theme_type_variation = &"BtnTeal"
	_add_button.text = I18nService.t("net.friends.add_button")
	_add_button.pressed.connect(_on_add_pressed)
	add_row.add_child(_add_button)
	_add_feedback = Label.new()
	_add_feedback.theme_type_variation = &"CaptionLabel"
	_add_feedback.visible = false
	add_rows.add_child(_add_feedback)

	_requests_title = Label.new()
	_requests_title.theme_type_variation = &"HeadlineLabel"
	_requests_title.text = I18nService.t("net.friends.requests_title")
	content.add_child(_requests_title)
	_requests_box = VBoxContainer.new()
	_requests_box.add_theme_constant_override("separation", 8)
	content.add_child(_requests_box)

	var list_title := Label.new()
	list_title.theme_type_variation = &"HeadlineLabel"
	list_title.text = I18nService.t("net.friends.list_title")
	content.add_child(list_title)
	_friends_box = VBoxContainer.new()
	_friends_box.add_theme_constant_override("separation", 8)
	content.add_child(_friends_box)


func _refresh_all() -> void:
	_on_status_changed(_net.status if _net != null else NetClient.Status.OFFLINE)
	_refresh_code()
	_on_requests_changed(_net.friends.requests if _has_friends_service() else [])
	_on_friends_changed(_net.friends.friends if _has_friends_service() else [])


func _refresh_code() -> void:
	var code := _net.friend_code if _net != null else ""
	_code_value.text = code if not code.is_empty() else "—"
	_copy_button.disabled = code.is_empty()


func _on_copy_pressed() -> void:
	var code := _net.friend_code if _net != null else ""
	if code.is_empty():
		return
	DisplayServer.clipboard_set(code)
	_copy_button.text = I18nService.t("net.friends.copied")
	var timer := get_tree().create_timer(1.4)
	timer.timeout.connect(
		func() -> void:
			if is_instance_valid(_copy_button):
				_copy_button.text = I18nService.t("net.friends.copy")
	)


func _on_status_changed(status: int) -> void:
	var online := status == NetClient.Status.ONLINE
	_offline_hint.visible = not online
	_add_button.disabled = not online
	FriendListUi.style_status_chip(_status_chip, status)
	_refresh_code()


func _on_requests_changed(requests: Array) -> void:
	for child in _requests_box.get_children():
		child.queue_free()
	_requests_title.visible = not requests.is_empty()
	_requests_box.visible = _requests_title.visible
	for row: Dictionary in requests:
		_requests_box.add_child(_build_request_row(row))


func _on_friends_changed(friends: Array) -> void:
	for child in _friends_box.get_children():
		child.queue_free()
	if friends.is_empty():
		_friends_box.add_child(
			FriendListUi.build_empty_state("net.friends.empty_art", "net.friends.empty")
		)
		return
	for row: Dictionary in friends:
		_friends_box.add_child(_build_friend_row(row))


func _build_request_row(row: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"AcCard"
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)
	var who := Label.new()
	who.text = I18nService.t(
		"net.friends.request_from",
		{"name": str(row.get("name", "?")), "gooby": str(row.get("goobyName", "Gooby"))}
	)
	who.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(who)
	var from_code := str(row.get("from", ""))
	var accept := Button.new()
	accept.theme_type_variation = &"BtnTeal"
	accept.text = I18nService.t("net.friends.accept")
	accept.pressed.connect(_on_accept_pressed.bind(from_code))
	box.add_child(accept)
	var decline := Button.new()
	decline.theme_type_variation = &"GhostButton"
	decline.text = I18nService.t("net.friends.decline")
	decline.pressed.connect(_on_decline_pressed.bind(from_code))
	box.add_child(decline)
	return card


func _build_friend_row(row: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"AcCard"
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	card.add_child(box)

	box.add_child(FriendListUi.presence_icon(row))
	var online: bool = row.get("online", false) == true

	var names := VBoxContainer.new()
	names.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(names)
	var name_label := Label.new()
	name_label.theme_type_variation = &"HeadlineLabel"
	name_label.text = "%s · %s" % [str(row.get("name", "?")), str(row.get("goobyName", "Gooby"))]
	names.add_child(name_label)
	var status_label := Label.new()
	status_label.theme_type_variation = &"CaptionLabel"
	status_label.text = FriendListUi.presence_text(row)
	if not online:
		status_label.add_theme_color_override("font_color", FriendListUi.COLOR_OFFLINE)
	names.add_child(status_label)

	var coins := Label.new()
	coins.theme_type_variation = &"HeadlineLabel"
	coins.text = I18nService.t("net.friends.coins", {"coins": int(row.get("coins", 0))})
	box.add_child(coins)
	return card


func _on_add_pressed() -> void:
	var value := _add_input.text.strip_edges()
	if value.is_empty():
		return
	if not _has_friends_service():
		_show_feedback(NetErrorText.for_code("OFFLINE", "net.friends.add_error"), false)
		return
	_add_input.editable = false
	var res: Dictionary = await _net.friends.add_friend(value)
	_add_input.editable = true
	if res.get("ok", false):
		_add_input.text = ""
		_show_feedback(I18nService.t("net.friends.add_sent"), true)
	else:
		_show_feedback(
			NetErrorText.for_code(str(res.get("code", "?")), "net.friends.add_error"), false
		)


func _on_accept_pressed(from_code: String) -> void:
	if _has_friends_service():
		await _net.friends.accept(from_code)


func _on_decline_pressed(from_code: String) -> void:
	if _has_friends_service():
		await _net.friends.decline(from_code)


func _show_feedback(text: String, ok: bool) -> void:
	_add_feedback.text = text
	_add_feedback.visible = true
	_add_feedback.add_theme_color_override(
		"font_color", Color(0.24, 0.6, 0.35) if ok else Color(0.75, 0.35, 0.3)
	)


func _has_friends_service() -> bool:
	return _net != null and _net.friends != null


func _on_back_pressed() -> void:
	back_requested.emit()
	if not auto_navigate:
		return
	var router := get_node_or_null("/root/SceneRouter")
	if router == null or not router.has_method("goto"):
		return
	var routes: Variant = router.get("_routes")
	if routes is Dictionary and (routes as Dictionary).has(&"home"):
		router.goto(&"home", {})
