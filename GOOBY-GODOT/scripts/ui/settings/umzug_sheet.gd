class_name UmzugSheet
extends Control
## Account-Umzug (W13-C, Doc C §7): kleines Sheet hinter der Settings-Zeile
## „Account umziehen“. Auf dem NEUEN Gerät wird der im Server-Panel erzeugte
## 8-Zeichen-Umzugs-Code eingegeben; der Server prüft ihn (MOVE_REDEEM) und
## liefert die übernommene Server-Identität (deviceId + ROTIERTES Secret +
## FriendCode). Der lokale Spielstand bleibt auf dem Gerät — glasklar im
## UI-Text — nur Freunde/FriendCode/Pal-Verlauf hängen danach hier.
## Testbar ohne echtes Netz: `net` ist injizierbar (Duck-Typing: request()/
## adopt_identity()); der Status landet zusätzlich in `status_key`.

signal moved(identity: Dictionary)
signal closed

const SCRIM_COLOR := Color(0.11, 0.09, 0.08, 0.72)
const CODE_LEN := 8

## Injizierbarer Netz-Client (Tests: NetClient am FakeWsLink); null → /root/Net.
var net: Node = null
## Letzter Status als String-Key (Tests prüfen Keys statt übersetzter Texte).
var status_key := ""
## true nach erfolgreichem Umzug (Eingabe wird dann versteckt).
var succeeded := false

var _busy := false
var _code_edit: LineEdit
var _status: Label
var _submit: Button
var _f := 1.0
var _tf := 1.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_f = UiScale.for_viewport(get_viewport())
	_tf = UiScale.font_scale(get_viewport())
	_build()
	FocusNavigation.grab_first_deferred(self)


## Test-/Automatisierungs-Helfer: Code ins Eingabefeld setzen.
func set_code(code: String) -> void:
	_code_edit.text = code


## Eingegebenen Code normalisieren + einlösen (await-bar, auch für Tests).
func submit() -> void:
	if _busy or succeeded:
		return
	var code := _code_edit.text.strip_edges().to_upper()
	if code.length() != CODE_LEN:
		_set_status("umzug.fehler_kurz")
		return
	var client := _net()
	if client == null or not client.has_method("request"):
		_set_status("umzug.fehler_offline")
		return
	_busy = true
	_submit.disabled = true
	_set_status("umzug.laeuft")
	var res: Dictionary = await client.request("MOVE_REDEEM", {"code": code})
	_busy = false
	_submit.disabled = false
	if not bool(res.get("ok", false)):
		var transport := str(res.get("code", ""))
		if transport == "OFFLINE":
			_set_status("umzug.fehler_offline")
		else:
			_set_status("umzug.fehler_generisch", {"code": transport})
		return
	var d: Dictionary = res.get("d", {})
	if not bool(d.get("ok", false)):
		match str(d.get("code", "")):
			"INVALID_CODE":
				_set_status("umzug.fehler_code")
			"EXPIRED":
				_set_status("umzug.fehler_abgelaufen")
			_:
				_set_status("umzug.fehler_generisch", {"code": str(d.get("code", "?"))})
		return
	var identity: Dictionary = d.get("identity", {})
	if client.has_method("adopt_identity"):
		client.adopt_identity(identity)
	succeeded = true
	_code_edit.visible = false
	_submit.visible = false
	_set_status("umzug.erfolg", {"code": str(identity.get("friendCode", ""))})
	moved.emit(identity)


func _net() -> Node:
	if net != null:
		return net
	return get_node_or_null("/root/Net")


func _set_status(key: String, args: Dictionary = {}) -> void:
	status_key = key
	if _status != null:
		_status.text = I18nService.t(key, args)


func _build() -> void:
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = SCRIM_COLOR
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	var card := PanelContainer.new()
	card.name = "Card"
	card.theme_type_variation = "AcCard"
	var canvas := Vector2(get_viewport().get_visible_rect().size)
	card.custom_minimum_size = Vector2(minf(540.0 * _f, canvas.x - 48.0), 0.0)
	center.add_child(card)
	var rows := VBoxContainer.new()
	rows.name = "Rows"
	rows.add_theme_constant_override("separation", int(12.0 * _f))
	card.add_child(rows)

	var title := Label.new()
	title.name = "Title"
	title.theme_type_variation = "TitleLabel"
	title.text = I18nService.t("umzug.titel")
	title.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_TITLE * _tf))
	rows.add_child(title)

	# GLASKLAR: der Spielstand bleibt lokal — hier zieht nur das Online-Konto um.
	var intro := Label.new()
	intro.name = "Intro"
	intro.text = I18nService.t("umzug.intro")
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BODY * _tf))
	rows.add_child(intro)
	for info: Array in [["Erklaerung", "umzug.erklaerung"], ["WarnungAlt", "umzug.warnung_alt"]]:
		var line := Label.new()
		line.name = str(info[0])
		line.theme_type_variation = "SoftLabel"
		line.text = I18nService.t(str(info[1]))
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_CAPTION * _tf))
		rows.add_child(line)

	var code_label := Label.new()
	code_label.name = "CodeLabel"
	code_label.text = I18nService.t("umzug.code_label")
	code_label.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BODY * _tf))
	rows.add_child(code_label)
	_code_edit = LineEdit.new()
	_code_edit.name = "CodeEdit"
	_code_edit.placeholder_text = I18nService.t("umzug.code_hint")
	_code_edit.max_length = CODE_LEN
	_code_edit.custom_minimum_size = Vector2(0.0, AcTokens.TOUCH_FLOOR * _f)
	_code_edit.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BODY * _tf))
	_code_edit.text_submitted.connect(func(_text: String) -> void: submit())
	rows.add_child(_code_edit)

	_status = Label.new()
	_status.name = "Status"
	_status.theme_type_variation = "SoftLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_CAPTION * _tf))
	rows.add_child(_status)

	_submit = SquishButton.new()
	_submit.name = "SubmitButton"
	_submit.theme_type_variation = "BtnTeal"
	_submit.text = I18nService.t("umzug.einloesen")
	_submit.focus_mode = Control.FOCUS_ALL
	_submit.custom_minimum_size = Vector2(0.0, 56.0 * _f)
	_submit.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BUTTON * _tf))
	_submit.pressed.connect(func() -> void: submit())
	rows.add_child(_submit)

	var close := SquishButton.new()
	close.name = "CloseButton"
	close.theme_type_variation = "GhostButton"
	close.text = I18nService.t("umzug.schliessen")
	close.focus_mode = Control.FOCUS_ALL
	close.custom_minimum_size = Vector2(0.0, 48.0 * _f)
	close.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BUTTON * _tf))
	close.pressed.connect(_close)
	rows.add_child(close)


func _close() -> void:
	closed.emit()
	queue_free()
