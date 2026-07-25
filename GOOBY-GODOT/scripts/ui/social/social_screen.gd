class_name SocialScreen
extends Control
## Freunde & Besuche (W3c VISIT): DIE Andockstelle für alle Social-Aktionen —
## pro Freund „Besuchen“, „Schiffe versenken“ und „GoobyPal“ (der W2d-
## FriendsScreen bleibt unangetastet, er hat keine Extension-API). Behandelt
## außerdem eingehende Besuchs-/Brettspiel-Anfragen (Karten mit Annehmen/
## Ablehnen) und navigiert bei VISIT_READY / BOARD_START in die Szenen.
## Offline degradieren die Knöpfe (W2d-Status-Signal), der Screen bleibt
## benutzbar.

signal back_requested

const ROUTE := &"social"
const ROUTES := {ROUTE: "res://scripts/ui/social/social_screen.tscn"}

## Tests/Screenshots: eigene Services/NetClient injizieren + Navigation aus.
var services_override: Node = null
var net_override: NetClient = null
var auto_navigate := true

var toast: ToastLayer

var _net: NetClient
var _services: Node
var _status_chip: Button
var _offline_hint: Label
var _friends_box: VBoxContainer
var _incoming_box: VBoxContainer
var _busy := false


static func register_routes() -> void:
	var loop := Engine.get_main_loop()
	if not (loop is SceneTree):
		return
	var router := (loop as SceneTree).root.get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("register_routes"):
		router.register_routes(ROUTES)


func _ready() -> void:
	# and_offsets: nur-Anker-Preset behält den leeren Ist-Rect, wenn der
	# Parent beim Einhängen schon gelayoutet ist (Router-Wechsel).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	register_routes()
	VisitScene.register_routes()
	BattleshipScene.register_routes()
	_net = net_override
	if _net == null:
		var candidate := get_node_or_null("/root/Net")
		if candidate is NetClient:
			_net = candidate
	_services = services_override
	if _services == null:
		_services = SocialServices.get_or_create(self)
	_build_ui()
	if _net != null:
		_net.status_changed.connect(_on_status_changed)
		if _net.friends != null:
			_net.friends.friends_changed.connect(_on_friends_changed)
	_wire_services()
	_refresh_all()


func visit_service() -> VisitService:
	return _services.visit if _services != null else null


func board_session() -> BoardSession:
	return _services.board if _services != null else null


func pal_service() -> GoobyPalService:
	return _services.pal if _services != null else null


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

	var header := HBoxContainer.new()
	rows.add_child(header)
	var back := Button.new()
	back.theme_type_variation = &"GhostButton"
	back.text = I18nService.t("social.screen.back")
	back.pressed.connect(_on_back_pressed)
	header.add_child(back)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = I18nService.t("social.screen.title")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)
	_status_chip = Button.new()
	header.add_child(_status_chip)

	_offline_hint = Label.new()
	_offline_hint.text = I18nService.t("social.screen.offline_hint")
	_offline_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_offline_hint.add_theme_color_override("font_color", FriendListUi.COLOR_HINT)
	rows.add_child(_offline_hint)

	if FurnitureCatalog.def("brettspieltisch").is_empty():
		var hint := Label.new()
		hint.theme_type_variation = &"CaptionLabel"
		hint.text = I18nService.t("board.table_hint")
		hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		rows.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)
	_incoming_box = VBoxContainer.new()
	_incoming_box.add_theme_constant_override("separation", 8)
	content.add_child(_incoming_box)
	_friends_box = VBoxContainer.new()
	_friends_box.add_theme_constant_override("separation", 8)
	content.add_child(_friends_box)

	toast = ToastLayer.new()
	add_child(toast)


func _wire_services() -> void:
	var vs := visit_service()
	if vs != null:
		vs.visit_incoming.connect(_on_visit_incoming)
		vs.visit_ready.connect(_on_visit_ready)
		vs.visit_denied.connect(_on_visit_denied)
	var session := board_session()
	if session != null:
		session.invite_incoming.connect(_on_board_invited)
		session.invite_declined.connect(_on_board_declined)
		session.game_started.connect(_on_board_started)
	var pal := pal_service()
	if pal != null:
		pal.received.connect(_on_pal_received)
		pal.boot_received.connect(_on_pal_boot_received)


func _refresh_all() -> void:
	_on_status_changed(_net.status if _net != null else NetClient.Status.OFFLINE)
	var friends: Array = []
	if _net != null and _net.friends != null:
		friends = _net.friends.friends
	_on_friends_changed(friends)


func _on_status_changed(status: int) -> void:
	var online := status == NetClient.Status.ONLINE
	_offline_hint.visible = not online
	FriendListUi.style_status_chip(_status_chip, status)
	_refresh_buttons()


func _on_friends_changed(friends: Array) -> void:
	for child in _friends_box.get_children():
		child.queue_free()
	if friends.is_empty():
		_friends_box.add_child(
			FriendListUi.build_empty_state("social.screen.empty_art", "social.screen.empty")
		)
		return
	for row: Dictionary in friends:
		_friends_box.add_child(_build_friend_row(row))


func _build_friend_row(row: Dictionary) -> Control:
	var card := PanelContainer.new()
	card.theme_type_variation = &"AcCard"
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	card.add_child(box)
	var online: bool = row.get("online", false) == true
	box.add_child(FriendListUi.presence_icon(row))
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
	var can_act := online and _is_online()
	var visit_btn := Button.new()
	visit_btn.theme_type_variation = &"BtnTeal"
	visit_btn.text = I18nService.t("social.visit.button")
	visit_btn.disabled = not can_act
	visit_btn.pressed.connect(_on_visit_pressed.bind(row))
	box.add_child(visit_btn)
	var board_btn := Button.new()
	board_btn.theme_type_variation = &"BtnTeal"
	board_btn.text = I18nService.t("board.button")
	board_btn.disabled = not can_act
	board_btn.pressed.connect(_on_board_pressed.bind(row))
	box.add_child(board_btn)
	var pal_btn := Button.new()
	pal_btn.theme_type_variation = &"GhostButton"
	pal_btn.text = I18nService.t("social.pal.button")
	pal_btn.disabled = not _is_online()
	pal_btn.pressed.connect(_on_pal_pressed.bind(row))
	box.add_child(pal_btn)
	return card


# ── Besuch ───────────────────────────────────────────────────────────────────


func _on_visit_pressed(row: Dictionary) -> void:
	var vs := visit_service()
	if vs == null or _busy:
		return
	var res: Dictionary = await vs.request_visit(str(row.get("friendCode", "")))
	if res["ok"]:
		toast.show_toast(
			I18nService.t("social.visit.request_sent", {"name": str(row.get("goobyName", "?"))})
		)
	elif str(res["code"]) == "OFFLINE_TARGET":
		toast.show_toast(I18nService.t("social.visit.target_offline"))
	else:
		toast.show_toast(NetErrorText.for_code(str(res["code"]), "social.visit.request_failed"))


func _on_visit_incoming(data: Dictionary) -> void:
	var text := I18nService.t("social.visit.incoming", {"name": str(data.get("goobyName", "?"))})
	_add_incoming_card(
		text,
		I18nService.t("social.visit.accept"),
		I18nService.t("social.visit.decline"),
		func() -> void: _accept_visit(str(data.get("from", ""))),
		func() -> void: visit_service().decline_visit(str(data.get("from", "")))
	)


## Host: erst Snapshot hochladen (Doc C §3.4 Punkt 2), dann annehmen.
func _accept_visit(guest_code: String) -> void:
	var vs := visit_service()
	var gs := get_node_or_null("/root/GameState")
	if gs != null:
		var uploaded: Dictionary = await vs.upload_snapshot(gs)
		if not uploaded["ok"]:
			toast.show_toast(
				NetErrorText.for_code(str(uploaded["code"]), "social.visit.upload_failed")
			)
			return
	await vs.accept_visit(guest_code)


## VISIT_READY (beidseitig): Gast lädt das Haus, Host nimmt sein eigenes.
func _on_visit_ready(_data: Dictionary) -> void:
	var vs := visit_service()
	if vs == null or _busy:
		return
	_busy = true
	var snapshot: Dictionary = {}
	if vs.role == VisitService.ROLE_GUEST:
		var res: Dictionary = await vs.fetch_house(vs.host_code)
		if not res["ok"]:
			_busy = false
			toast.show_toast(NetErrorText.for_code(str(res["code"]), "social.visit.fetch_failed"))
			await vs.end_visit()
			return
		snapshot = res["snapshot"]
	else:
		var gs := get_node_or_null("/root/GameState")
		if gs != null:
			snapshot = VisitSnapshot.build_from_state(gs)
	_busy = false
	_navigate(VisitScene.ROUTE, {"snapshot": snapshot, "role": vs.role})


func _on_visit_denied(data: Dictionary) -> void:
	toast.show_toast(I18nService.t("social.visit.denied", {"name": str(data.get("from", "?"))}))


# ── Brettspiel ───────────────────────────────────────────────────────────────


func _on_board_pressed(row: Dictionary) -> void:
	var session := board_session()
	if session == null:
		return
	var res: Dictionary = await session.invite(str(row.get("friendCode", "")))
	if res["ok"]:
		toast.show_toast(
			I18nService.t("board.invite_sent", {"name": str(row.get("goobyName", "?"))})
		)
	else:
		toast.show_toast(NetErrorText.for_code(str(res["code"]), "board.invite_failed"))


func _on_board_invited(data: Dictionary) -> void:
	var text := I18nService.t("board.invited", {"name": str(data.get("goobyName", "?"))})
	_add_incoming_card(
		text,
		I18nService.t("board.accept"),
		I18nService.t("board.decline"),
		func() -> void: board_session().accept(str(data.get("from", ""))),
		func() -> void: board_session().decline(str(data.get("from", "")))
	)


func _on_board_declined(data: Dictionary) -> void:
	toast.show_toast(I18nService.t("board.declined", {"name": str(data.get("from", "?"))}))


func _on_board_started(_data: Dictionary) -> void:
	_navigate(BattleshipScene.ROUTE, {})


# ── GoobyPal ─────────────────────────────────────────────────────────────────


func _on_pal_pressed(row: Dictionary) -> void:
	var sheet := GoobyPalSheet.new()
	sheet.setup(pal_service(), row)
	sheet.toast_requested.connect(toast.show_toast)
	add_child(sheet)


func _on_pal_received(from_code: String, amount: int) -> void:
	toast.show_toast(I18nService.t("social.pal.received", {"name": from_code, "amount": amount}))


func _on_pal_boot_received(total: int, _entries: Array) -> void:
	toast.show_toast(I18nService.t("social.pal.boot_received", {"amount": total}))


# ── Helfer ───────────────────────────────────────────────────────────────────


func _add_incoming_card(
	text: String, yes_text: String, no_text: String, on_yes: Callable, on_no: Callable
) -> void:
	var card := PanelContainer.new()
	card.theme_type_variation = &"AcCard"
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	card.add_child(box)
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(label)
	var yes := Button.new()
	yes.theme_type_variation = &"BtnTeal"
	yes.text = yes_text
	box.add_child(yes)
	var no := Button.new()
	no.theme_type_variation = &"GhostButton"
	no.text = no_text
	box.add_child(no)
	yes.pressed.connect(
		func() -> void:
			card.queue_free()
			on_yes.call()
	)
	no.pressed.connect(
		func() -> void:
			card.queue_free()
			on_no.call()
	)
	_incoming_box.add_child(card)


func _refresh_buttons() -> void:
	var friends: Array = []
	if _net != null and _net.friends != null:
		friends = _net.friends.friends
	_on_friends_changed(friends)


func _is_online() -> bool:
	return _net != null and _net.is_online()


func _navigate(route: StringName, params: Dictionary) -> void:
	if not auto_navigate:
		return
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("goto"):
		router.goto(route, params)


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
