class_name GvzNetzPanel
extends PanelContainer
## „PvP übers Netz“-Panel im GvZ-Level-Select (G5/P26 — Muster
## GobnomNetzPanel/W15): Gate nur online + Freund online (C §3.8),
## Herausforderung/Beitritt über den bestehenden Freunde-Flow
## (GvzNetSession), danach Start-Handshake (beide drücken „Los geht's!“ →
## Server pusht GVZ_START mit Seed + Seiten gooby/zombie). Ohne Session/
## offline bleibt die lokale Kampagne unberührt. Alle Knöpfe sind
## SquishButtons (zentrale Haptik) auf dem Touch-Floor (AcTokens).

var session: GvzNetSession

var _status: Label
var _action: Button
var _start: Button
var _invites_box: VBoxContainer
var _friends_box: VBoxContainer
var _picking := false


## Gate-Text fürs „PvP übers Netz“-Angebot ("" = spielbereit).
static func gate_key(online: bool, online_friend_count: int) -> String:
	if not online:
		return "gvz.netz.offline"
	if online_friend_count <= 0:
		return "gvz.netz.keine_freunde"
	return ""


func setup(net_session: GvzNetSession) -> void:
	session = net_session
	session.invite_incoming.connect(_on_invite_incoming)
	session.invite_declined.connect(_on_invite_declined)
	session.session_ready.connect(_on_session_ready)
	session.game_started.connect(_on_game_started)
	session.session_aborted.connect(_on_session_aborted)
	session.online_state_changed.connect(func(_online: bool) -> void: refresh())


func _ready() -> void:
	theme_type_variation = &"AcCard"
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	add_child(column)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	_status = Label.new()
	_status.theme_type_variation = &"CaptionLabel"
	_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(_status)
	_start = SquishButton.new()
	_start.text = I18nService.t("gvz.netz.los")
	_start.custom_minimum_size = Vector2(150, AcTokens.TOUCH_FLOOR)
	_start.visible = false
	_start.pressed.connect(_on_start_pressed)
	row.add_child(_start)
	_action = SquishButton.new()
	_action.custom_minimum_size = Vector2(170, AcTokens.TOUCH_FLOOR)
	_action.pressed.connect(_on_action_pressed)
	row.add_child(_action)
	_invites_box = VBoxContainer.new()
	_invites_box.add_theme_constant_override("separation", 4)
	column.add_child(_invites_box)
	_friends_box = VBoxContainer.new()
	_friends_box.add_theme_constant_override("separation", 4)
	_friends_box.visible = false
	column.add_child(_friends_box)
	refresh()


func refresh() -> void:
	if session == null or _status == null:
		return
	if session.is_paired():
		var side_key := (
			"gvz.netz.seite_gooby"
			if session.my_side == GvzPvpLockstep.SIDE_GOOBY
			else "gvz.netz.seite_zombie"
		)
		if session.start_requested:
			_status.text = I18nService.t(
				"gvz.netz.warte_start", {"name": session.partner_gooby_name}
			)
		else:
			_status.text = I18nService.t(
				"gvz.netz.verbunden",
				{"name": session.partner_gooby_name, "seite": I18nService.t(side_key)}
			)
		_start.visible = not session.start_requested
		_action.text = I18nService.t("gvz.netz.trennen")
		_action.disabled = false
		_picking = false
		_friends_box.visible = false
		return
	_start.visible = false
	var gate := gate_key(session.is_online(), session.online_friends().size())
	_action.text = I18nService.t("gvz.netz.button")
	_action.disabled = gate != ""
	_status.text = I18nService.t(gate if gate != "" else "gvz.netz.bereit")
	_friends_box.visible = _picking and gate == ""


func _on_start_pressed() -> void:
	AudioDirector.try_play(self, "ui_confirm")
	session.request_start()
	refresh()


func _on_action_pressed() -> void:
	AudioDirector.try_play(self, "ui_click")
	if session.is_paired():
		session.leave()
		refresh()
		return
	_picking = not _picking
	if _picking:
		_rebuild_friend_rows()
	refresh()


func _rebuild_friend_rows() -> void:
	for child in _friends_box.get_children():
		child.queue_free()
	for row: Dictionary in session.online_friends():
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 8)
		var name_label := Label.new()
		name_label.theme_type_variation = &"CaptionLabel"
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.text = (
			"%s · %s" % [str(row.get("name", "?")), str(row.get("goobyName", "Gooby"))]
		)
		line.add_child(name_label)
		var invite_btn := SquishButton.new()
		invite_btn.text = I18nService.t("gvz.netz.einladen")
		invite_btn.custom_minimum_size = Vector2(140, AcTokens.TOUCH_FLOOR)
		invite_btn.pressed.connect(_on_invite_pressed.bind(row))
		line.add_child(invite_btn)
		_friends_box.add_child(line)


func _on_invite_pressed(row: Dictionary) -> void:
	AudioDirector.try_play(self, "ui_confirm")
	var target := str(row.get("friendCode", ""))
	var res: Dictionary = await session.invite(target)
	if bool(res.get("ok", false)):
		_status.text = I18nService.t(
			"gvz.netz.eingeladen", {"name": str(row.get("goobyName", "Gooby"))}
		)
		_picking = false
		_friends_box.visible = false
	else:
		_status.text = I18nService.t("gvz.netz.fehler", {"code": str(res.get("code", "?"))})


func _on_invite_incoming(data: Dictionary) -> void:
	var from := str(data.get("from", ""))
	for child in _invites_box.get_children():
		if str(child.get_meta("from", "")) == from:
			return
	var line := HBoxContainer.new()
	line.set_meta("from", from)
	line.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.theme_type_variation = &"CaptionLabel"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = I18nService.t("gvz.netz.laedt_ein", {"name": str(data.get("goobyName", "Gooby"))})
	line.add_child(label)
	var accept_btn := SquishButton.new()
	accept_btn.text = I18nService.t("gvz.netz.annehmen")
	accept_btn.custom_minimum_size = Vector2(120, AcTokens.TOUCH_FLOOR)
	accept_btn.pressed.connect(_on_accept_pressed.bind(from, line))
	line.add_child(accept_btn)
	var decline_btn := SquishButton.new()
	decline_btn.text = I18nService.t("gvz.netz.ablehnen")
	decline_btn.custom_minimum_size = Vector2(110, AcTokens.TOUCH_FLOOR)
	decline_btn.pressed.connect(_on_decline_pressed.bind(from, line))
	line.add_child(decline_btn)
	_invites_box.add_child(line)


func _on_accept_pressed(from: String, line: Node) -> void:
	AudioDirector.try_play(self, "ui_confirm")
	line.queue_free()
	await session.accept(from)
	refresh()


func _on_decline_pressed(from: String, line: Node) -> void:
	AudioDirector.try_play(self, "ui_back")
	line.queue_free()
	session.decline(from)


func _on_invite_declined(data: Dictionary) -> void:
	_status.text = I18nService.t("gvz.netz.abgelehnt", {"name": str(data.get("from", "?"))})


func _on_session_ready(_data: Dictionary) -> void:
	for child in _invites_box.get_children():
		child.queue_free()
	refresh()


func _on_game_started(_data: Dictionary) -> void:
	refresh()


func _on_session_aborted(_reason: String, _by: String) -> void:
	refresh()
