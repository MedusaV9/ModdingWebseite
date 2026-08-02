class_name RmpLobbyPanel
extends PanelContainer
## Lobby-/Ergebnis-Panel der Ranch-Minispiele (RW-6): Spielerliste mit
## Bereit-Häkchen, Countdown, Bereit-/Verlassen-Knöpfe — nach dem Lauf die
## Ergebnisliste mit Revanche. Verdrahtet sich über setup(service) mit dem
## RanchMultiplayerService (Signale), enthält die Verbindungsanzeige
## (NetStatusIndicator, FIX-6). Alle Texte aus ranch_mp.* (DE führend).

signal leave_pressed

var service: RanchMultiplayerService = null

var _titel: Label
var _status: NetStatusIndicator
var _spieler_box: VBoxContainer
var _countdown: Label
var _hinweis: Label
var _bereit_btn: Button
var _verlassen_btn: Button
var _revanche_btn: Button
var _ready_codes: Array = []
var _results: Array = []
var _countdown_aktiv := false


func _ready() -> void:
	# G4: Wunschbreite ×f mit Safe-Area-Klemmung statt fixer 420 px.
	var m := ScreenShell.metrics(get_viewport())
	custom_minimum_size = Vector2(ScreenShell.card_width(m, 420.0), 0.0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	var kopf := HBoxContainer.new()
	kopf.add_theme_constant_override("separation", 12)
	box.add_child(kopf)
	_titel = Label.new()
	_titel.theme_type_variation = &"HeadlineLabel"
	_titel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kopf.add_child(_titel)
	_status = NetStatusIndicator.new()
	kopf.add_child(_status)
	_spieler_box = VBoxContainer.new()
	_spieler_box.add_theme_constant_override("separation", 4)
	box.add_child(_spieler_box)
	_countdown = Label.new()
	_countdown.theme_type_variation = &"TitleLabel"
	_countdown.visible = false
	box.add_child(_countdown)
	_hinweis = Label.new()
	_hinweis.theme_type_variation = &"CaptionLabel"
	_hinweis.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hinweis.visible = false
	box.add_child(_hinweis)
	var knoepfe := HBoxContainer.new()
	knoepfe.add_theme_constant_override("separation", 10)
	box.add_child(knoepfe)
	_bereit_btn = Button.new()
	_bereit_btn.theme_type_variation = &"PrimaryButton"
	_bereit_btn.text = I18nService.t("ranch_mp.lobby.bereit_knopf")
	_bereit_btn.pressed.connect(_on_bereit)
	knoepfe.add_child(_bereit_btn)
	_revanche_btn = Button.new()
	_revanche_btn.theme_type_variation = &"PrimaryButton"
	_revanche_btn.text = I18nService.t("ranch_mp.ergebnis.revanche")
	_revanche_btn.visible = false
	_revanche_btn.pressed.connect(_on_revanche)
	knoepfe.add_child(_revanche_btn)
	_verlassen_btn = Button.new()
	_verlassen_btn.theme_type_variation = &"GhostButton"
	_verlassen_btn.text = I18nService.t("ranch_mp.lobby.verlassen")
	_verlassen_btn.pressed.connect(func() -> void: leave_pressed.emit())
	knoepfe.add_child(_verlassen_btn)
	# G7/P57 (FB3-Altbefund „Verlassen/Bereit! 18,7–36,7 pt"): physischer
	# Touch-Floor — Theme-Höhen sind Design-px und auf Retina zu klein.
	for btn: Button in [_bereit_btn, _revanche_btn, _verlassen_btn]:
		ScreenShell.touch_target(btn, m)
	_refresh()


func setup(mp_service: RanchMultiplayerService) -> void:
	service = mp_service
	if _status != null and service.net() != null:
		_status.setup(service.net())
	service.session_ready.connect(func(_d: Dictionary) -> void: _zeige_lobby())
	service.lobby_updated.connect(_on_lobby)
	service.match_started.connect(_on_start)
	service.result_received.connect(_on_result)
	service.rematch_wait.connect(_on_rematch_wait)
	service.rematch_declined.connect(_on_rematch_declined)
	if is_inside_tree():
		_zeige_lobby()


func _process(_delta: float) -> void:
	if not _countdown_aktiv or service == null:
		return
	var rest := service.countdown_ms()
	if rest <= 0:
		_countdown.text = I18nService.t("ranch_mp.lauf.ziel").replace("!", "…")
		_countdown_aktiv = false
		return
	_countdown.text = I18nService.t(
		"ranch_mp.lobby.countdown", {"s": "%.1f" % (float(rest) / 1000.0)}
	)


## ---------------------------------------------------------------- intern


func _zeige_lobby() -> void:
	_ready_codes = []
	_results = []
	_countdown_aktiv = false
	_countdown.visible = false
	_hinweis.visible = false
	_revanche_btn.visible = false
	_bereit_btn.visible = true
	_bereit_btn.disabled = false
	_refresh()


func _on_lobby(data: Dictionary) -> void:
	_ready_codes = data.get("ready", []) if data.get("ready") is Array else []
	_refresh()


func _on_start(_data: Dictionary) -> void:
	_bereit_btn.visible = false
	_countdown.visible = true
	_countdown_aktiv = true
	_refresh()


func _on_result(data: Dictionary) -> void:
	if service != null and data.get("room", "") != service.room_id:
		return
	_results = data.get("results", []) if data.get("results") is Array else [data]
	_countdown_aktiv = false
	_countdown.visible = false
	_bereit_btn.visible = false
	_revanche_btn.visible = true
	_revanche_btn.disabled = false
	_hinweis.visible = false
	_refresh()


func _on_rematch_wait(_data: Dictionary) -> void:
	_hinweis.text = I18nService.t("ranch_mp.ergebnis.revanche_warte")
	_hinweis.visible = true


func _on_rematch_declined(data: Dictionary) -> void:
	_hinweis.text = I18nService.t(
		"ranch_mp.ergebnis.revanche_abgelehnt",
		{"name": _name_fuer(str(data.get("friendCode", "")))}
	)
	_hinweis.visible = true
	_revanche_btn.disabled = true


func _on_bereit() -> void:
	if service == null:
		return
	_bereit_btn.disabled = true
	var res: Dictionary = await service.set_ready()
	if not res["ok"]:
		_bereit_btn.disabled = false
		_hinweis.text = RanchMultiplayerService.fehler_text(str(res["code"]))
		_hinweis.visible = true


func _on_revanche() -> void:
	if service == null:
		return
	var res: Dictionary = await service.rematch()
	if not res["ok"]:
		_hinweis.text = RanchMultiplayerService.fehler_text(str(res["code"]))
		_hinweis.visible = true


func _refresh() -> void:
	if _titel == null:
		return
	var spiel := "?"
	var max_spieler := 4
	var anzahl := 0
	if service != null:
		spiel = (
			I18nService.t("ranch_mp.menu.%s" % service.mode) if not service.mode.is_empty() else "?"
		)
		max_spieler = int(RmpKurse.MAX_SPIELER.get(service.mode, 4))
		anzahl = service.players.size()
	if _results.is_empty():
		_titel.text = I18nService.t("ranch_mp.lobby.titel", {"spiel": spiel})
	else:
		_titel.text = I18nService.t("ranch_mp.ergebnis.titel")
	for kind in _spieler_box.get_children():
		kind.queue_free()
	if not _results.is_empty():
		_zeige_ergebnis_zeilen()
		return
	var kopf := Label.new()
	kopf.theme_type_variation = &"CaptionLabel"
	kopf.text = I18nService.t("ranch_mp.lobby.spieler", {"n": anzahl, "max": max_spieler})
	_spieler_box.add_child(kopf)
	if service == null or service.players.is_empty():
		var leer := Label.new()
		leer.theme_type_variation = &"SoftLabel"
		leer.text = I18nService.t("ranch_mp.lobby.leer")
		_spieler_box.add_child(leer)
		return
	for spieler: Variant in service.players:
		if not (spieler is Dictionary):
			continue
		var code := str((spieler as Dictionary).get("friendCode", ""))
		var zeile := Label.new()
		zeile.theme_type_variation = &"SoftLabel"
		var zustand := (
			I18nService.t("ranch_mp.lobby.bereit")
			if _ready_codes.has(code)
			else I18nService.t("ranch_mp.lobby.warten")
		)
		zeile.text = (
			"%s %s — %s"
			% [
				"✔" if _ready_codes.has(code) else "•",
				str((spieler as Dictionary).get("name", code)),
				zustand,
			]
		)
		_spieler_box.add_child(zeile)


func _zeige_ergebnis_zeilen() -> void:
	for result: Variant in _results:
		if not (result is Dictionary):
			continue
		var r: Dictionary = result
		var zeile := Label.new()
		zeile.theme_type_variation = &"SoftLabel"
		var text := I18nService.t(
			"ranch_mp.ergebnis.zeile",
			{"platz": int(r.get("rank", 0)), "name": _name_fuer(str(r.get("friendCode", "")))}
		)
		if bool(r.get("dnf", false)):
			text += " — %s" % I18nService.t("ranch_mp.ergebnis.dnf")
		else:
			text += (
				" — %s"
				% I18nService.t(
					"ranch_mp.ergebnis.zeit",
					{"s": "%.1f" % (float(int(r.get("zeitMs", 0))) / 1000.0)}
				)
			)
		if not bool(r.get("ranked", false)) and not bool(r.get("dnf", false)):
			text += " (%s)" % I18nService.t("ranch_mp.ergebnis.unranked")
		zeile.text = text
		_spieler_box.add_child(zeile)


func _name_fuer(code: String) -> String:
	if service != null:
		for spieler: Variant in service.players:
			if spieler is Dictionary and str((spieler as Dictionary).get("friendCode", "")) == code:
				return str((spieler as Dictionary).get("name", code))
	return code
