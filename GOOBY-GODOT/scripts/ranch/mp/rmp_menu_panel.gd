class_name RmpMenuPanel
extends PanelContainer
## Mehrspieler-Hub der Ranch (RW-6): Spielmodus wählen, Online-Freunde
## einladen, eingehende Einladungen annehmen/ablehnen. OFFLINE-FIRST:
## ohne Verbindung sind die Knöpfe höflich deaktiviert und der Hinweis
## erklärt warum — das Spiel selbst läuft ungestört weiter. Enthält die
## Verbindungsanzeige (NetStatusIndicator).

signal leaderboard_pressed

const MODI: Array[String] = ["besuch", "ausritt", "rennen", "fangen", "parcours"]

var service: RanchMultiplayerService = null

var _status: NetStatusIndicator
var _hinweis: Label
var _modus_wahl: OptionButton
var _freunde_box: VBoxContainer
var _einladung_box: VBoxContainer
var _friends: Node = null


func _ready() -> void:
	# G4 (G1 §1.7): Wunschbreite ×f, aber nie breiter als die Safe-Area —
	# statt fixer 440 px (Panel läuft jetzt im PanelSheet, s. RmpHub).
	var m := ScreenShell.metrics(get_viewport())
	custom_minimum_size = Vector2(ScreenShell.card_width(m, 440.0), 0.0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var kopf := HBoxContainer.new()
	kopf.add_theme_constant_override("separation", 12)
	box.add_child(kopf)
	var titel := Label.new()
	titel.theme_type_variation = &"HeadlineLabel"
	titel.text = I18nService.t("ranch_mp.menu.title")
	titel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kopf.add_child(titel)
	_status = NetStatusIndicator.new()
	kopf.add_child(_status)
	_hinweis = Label.new()
	_hinweis.theme_type_variation = &"CaptionLabel"
	_hinweis.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hinweis.visible = false
	box.add_child(_hinweis)
	_modus_wahl = OptionButton.new()
	for mode in MODI:
		_modus_wahl.add_item(I18nService.t("ranch_mp.menu.%s" % mode))
	box.add_child(_modus_wahl)
	_freunde_box = VBoxContainer.new()
	_freunde_box.add_theme_constant_override("separation", 4)
	box.add_child(_freunde_box)
	_einladung_box = VBoxContainer.new()
	_einladung_box.add_theme_constant_override("separation", 4)
	box.add_child(_einladung_box)
	var besten := Button.new()
	besten.theme_type_variation = &"GhostButton"
	besten.text = I18nService.t("ranch_mp.menu.bestenlisten")
	besten.pressed.connect(func() -> void: leaderboard_pressed.emit())
	box.add_child(besten)
	_refresh()


func setup(mp_service: RanchMultiplayerService, friends_service: Node = null) -> void:
	service = mp_service
	_friends = friends_service
	if _status != null and service.net() != null:
		_status.setup(service.net())
		if service.net().has_signal("status_changed"):
			service.net().status_changed.connect(func(_s: int) -> void: _refresh())
	service.invited.connect(_on_invited)
	service.invite_declined.connect(_on_declined)
	if _friends != null and _friends.has_signal("friends_changed"):
		_friends.friends_changed.connect(func() -> void: _refresh())
	if is_inside_tree():
		_refresh()


func gewaehlter_modus() -> String:
	return MODI[clampi(_modus_wahl.selected, 0, MODI.size() - 1)]


## ---------------------------------------------------------------- intern


func _refresh() -> void:
	if _freunde_box == null:
		return
	for kind in _freunde_box.get_children():
		kind.queue_free()
	var online := service != null and service.is_online()
	_modus_wahl.disabled = not online
	_hinweis.visible = not online
	if not online:
		_hinweis.text = I18nService.t("ranch_mp.menu.offline_hint")
		return
	var online_freunde := _online_freunde()
	if online_freunde.is_empty():
		var leer := Label.new()
		leer.theme_type_variation = &"SoftLabel"
		leer.text = I18nService.t("ranch_mp.menu.keine_freunde")
		_freunde_box.add_child(leer)
		return
	for freund: Dictionary in online_freunde:
		var zeile := HBoxContainer.new()
		zeile.add_theme_constant_override("separation", 8)
		var label := Label.new()
		label.theme_type_variation = &"SoftLabel"
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.text = str(freund.get("name", freund.get("friendCode", "?")))
		zeile.add_child(label)
		var btn := Button.new()
		btn.theme_type_variation = &"PrimaryButton"
		btn.text = I18nService.t("ranch_mp.menu.einladen")
		var code := str(freund.get("friendCode", ""))
		btn.pressed.connect(func() -> void: _einladen(code, label.text))
		zeile.add_child(btn)
		_freunde_box.add_child(zeile)


## Online-Freunde aus dem FriendsService (Duck-Typing: friends-Liste mit
## {friendCode, name, online}); ohne Service leere Liste.
func _online_freunde() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if _friends == null:
		return out
	var liste: Variant = _friends.get("friends")
	if not (liste is Array):
		return out
	for eintrag: Variant in liste:
		if eintrag is Dictionary and bool((eintrag as Dictionary).get("online", false)):
			out.append(eintrag)
	return out


func _einladen(code: String, wer: String) -> void:
	if service == null:
		return
	var res: Dictionary = await service.invite(code, gewaehlter_modus())
	_hinweis.visible = true
	if res["ok"]:
		_hinweis.text = I18nService.t("ranch_mp.menu.invite_gesendet", {"name": wer})
	else:
		_hinweis.text = RanchMultiplayerService.fehler_text(str(res["code"]))


func _on_invited(data: Dictionary) -> void:
	for kind in _einladung_box.get_children():
		kind.queue_free()
	var zeile := HBoxContainer.new()
	zeile.add_theme_constant_override("separation", 8)
	var label := Label.new()
	label.theme_type_variation = &"TitleLabel"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text = (
		I18nService
		. t(
			"ranch_mp.menu.invite_von",
			{
				"name": str(data.get("name", "?")),
				"spiel": I18nService.t("ranch_mp.menu.%s" % str(data.get("mode", "besuch"))),
			}
		)
	)
	zeile.add_child(label)
	var von := str(data.get("from", ""))
	var ja := Button.new()
	ja.theme_type_variation = &"PrimaryButton"
	ja.text = I18nService.t("ranch_mp.menu.annehmen")
	ja.pressed.connect(func() -> void: _annehmen(von))
	zeile.add_child(ja)
	var nein := Button.new()
	nein.theme_type_variation = &"GhostButton"
	nein.text = I18nService.t("ranch_mp.menu.ablehnen")
	nein.pressed.connect(func() -> void: _ablehnen(von))
	zeile.add_child(nein)
	_einladung_box.add_child(zeile)


func _annehmen(von: String) -> void:
	_einladung_leeren()
	if service == null:
		return
	var res: Dictionary = await service.accept(von)
	if not res["ok"]:
		_hinweis.text = RanchMultiplayerService.fehler_text(str(res["code"]))
		_hinweis.visible = true


func _ablehnen(von: String) -> void:
	_einladung_leeren()
	if service != null:
		await service.decline(von)


func _on_declined(data: Dictionary) -> void:
	_hinweis.text = I18nService.t("ranch_mp.menu.abgelehnt", {"name": str(data.get("from", "?"))})
	_hinweis.visible = true


func _einladung_leeren() -> void:
	for kind in _einladung_box.get_children():
		kind.queue_free()
