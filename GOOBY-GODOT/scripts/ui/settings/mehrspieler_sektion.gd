class_name MehrspielerSektion
extends VBoxContainer
## W14/NETSET — Inhalt der Settings-Sektion "Mehrspieler" (OHNE Dev-Modus
## sichtbar). Eigene Datei: die Sektions-HUELLE ("SectionMehrspieler") baut
## W14/UISCREENS-A in settings_screen.gd (_build_multiplayer_section), dort
## haengt NUR eine minimale Andock-Zeile `rows.add_child(
## MehrspielerSektion.new())`. Felder: Server-Adresse (Host oder wss://-URL),
## Port, Server-Secret (optional, maskiert). Persistenz laeuft ueber den
## User-Override des NetClient (user://net_user_override.json), den
## _resolve_net_config MIT VORRANG vor der Pack-Config liest — die Aenderung
## wirkt beim naechsten Connect (W2b-Contract: Config wird bei JEDEM Connect
## frisch gelesen); nach dem Speichern wird /root/Net einmal neu verbunden.
## Das W13-Heimnetz-Gate bleibt unangetastet wirksam (ws:// nur zu privaten
## Hosts; wss:// immer erlaubt).
##
## "Verbindung testen": async HELLO-Roundtrip ueber einen WEGWERF-NetClient
## mit EIGENER Identitaetsdatei (verdraengt die Live-Verbindung nicht) —
## Status-Chip zeigt Erfolg (+Roundtrip-ms) oder Fehler + Grund
## (fehler_text_key mappt Server-Codes auf netset.mp.fehler.*).

## Timeout fuer den Test-Roundtrip (Verbindung + HELLO -> WELCOME).
const TEST_TIMEOUT_MS := 10_000
## Eigene Identitaet NUR fuer den Verbindungstest (kein REPLACED-Kick der
## echten Session, wenn beide auf denselben Server zeigen).
const TEST_IDENTITY_PATH := "user://net_test_identity.json"
## Server-Fehlercode -> i18n-Key (netset.mp.fehler.*). Unbekannte Codes
## landen auf "unbekannt" (Text traegt {code}).
const FEHLER_KEYS := {
	"SECRET_REQUIRED": "netset.mp.fehler.secret_required",
	"SECRET_WRONG": "netset.mp.fehler.secret_wrong",
	"AUTH_FAIL": "netset.mp.fehler.auth_fail",
	"BANNED": "netset.mp.fehler.banned",
	"RATE_LIMIT": "netset.mp.fehler.rate_limit",
	"TIMEOUT": "netset.mp.fehler.timeout",
	"UNREACHABLE": "netset.mp.fehler.unreachable",
	"GATE": "netset.mp.fehler.gate",
}

const CHIP_NEUTRAL := Color("#8A8177")
const CHIP_OK := Color("#3E9B4F")
const CHIP_FEHLER := Color("#C4453C")

var _f := 1.0
var _tf := 1.0
var _server_edit: LineEdit
var _port_edit: LineEdit
var _secret_edit: LineEdit
var _chip: Label
var _testing := false
var _zuletzt_gespeichert := {}


func _ready() -> void:
	name = "MehrspielerZeilen"
	mouse_filter = Control.MOUSE_FILTER_PASS
	_f = UiScale.for_viewport(get_viewport())
	_tf = UiScale.font_scale(get_viewport())
	add_theme_constant_override("separation", int(10.0 * _f))
	_build()
	_lade_override()


## ---------------------------------------------------------------- Statisch


## PURE: Adress-Eingabe zerlegen. Akzeptiert nackten Host ("192.168.0.10",
## "gooby.example"), "host:port" sowie ws://- und wss://-URLs (Pfad wird
## ignoriert). wss:// erzwingt tls=true, ws:// tls=false, nackter Host
## tls=false (Heimnetz-Standard — oeffentliche Hosts blockt das W13-Gate).
## Rueckgabe: {host: String, tls: bool, port: int (-1 = keiner in der URL)}.
static func parse_server_adresse(text: String) -> Dictionary:
	var rest := text.strip_edges()
	var tls := false
	if rest.begins_with("wss://"):
		tls = true
		rest = rest.substr(6)
	elif rest.begins_with("ws://"):
		rest = rest.substr(5)
	var slash := rest.find("/")
	if slash >= 0:
		rest = rest.substr(0, slash)
	var port := -1
	var colon := rest.rfind(":")
	if colon >= 0 and rest.substr(colon + 1).is_valid_int():
		port = int(rest.substr(colon + 1))
		rest = rest.substr(0, colon)
	return {"host": rest.strip_edges(), "tls": tls, "port": port}


## PURE: Fehlercode -> i18n-Key (Status-Chip-Grund).
static func fehler_text_key(code: String) -> String:
	return str(FEHLER_KEYS.get(code, "netset.mp.fehler.unbekannt"))


## ------------------------------------------------------------------ Aufbau


func _build() -> void:
	_add_hilfe(self, "MpHelp", I18nService.t("netset.mp.hilfe"))
	_server_edit = _add_edit_row(
		self, "server", I18nService.t("netset.mp.server"), I18nService.t("netset.mp.server_hinweis")
	)
	_port_edit = _add_edit_row(
		self, "port", I18nService.t("netset.mp.port"), I18nService.t("netset.mp.port_hinweis")
	)
	_secret_edit = _add_edit_row(
		self, "secret", I18nService.t("netset.mp.secret"), I18nService.t("netset.mp.secret_hinweis")
	)
	_secret_edit.secret = true
	var buttons := HBoxContainer.new()
	buttons.name = "MpButtons"
	buttons.add_theme_constant_override("separation", int(8.0 * _f))
	buttons.add_child(_button("TestButton", I18nService.t("netset.mp.testen"), _on_testen))
	buttons.add_child(
		_button("ResetButton", I18nService.t("netset.mp.zuruecksetzen"), _on_zuruecksetzen)
	)
	add_child(buttons)
	_chip = Label.new()
	_chip.name = "StatusChip"
	_chip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_chip.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_CAPTION * _tf))
	_set_chip(I18nService.t("netset.mp.chip_leer"), CHIP_NEUTRAL)
	add_child(_chip)


func _add_edit_row(
	rows: VBoxContainer, key: String, label_text: String, placeholder: String
) -> LineEdit:
	var row := HBoxContainer.new()
	row.name = "Row" + key.to_pascal_case()
	row.add_theme_constant_override("separation", int(12.0 * _f))
	var label := Label.new()
	label.name = "RowLabel"
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# W16-Inhaltsspalte: ohne Umbruch erzwingt der Label-Text eine
	# Mindest-Zeilenbreite (Label + 240·f-Feld > Spalten-Deckel auf hohen
	# Faktoren) — mit Autowrap passt sich die Zeile der Spalte an.
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BODY * _tf))
	row.add_child(label)
	var edit := LineEdit.new()
	edit.name = "Value"
	edit.placeholder_text = placeholder
	edit.custom_minimum_size = Vector2(240.0 * _f, AcTokens.TOUCH_FLOOR * _f)
	edit.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_BODY * _tf))
	edit.text_submitted.connect(func(_t: String) -> void: _speichern())
	edit.focus_exited.connect(_speichern)
	row.add_child(edit)
	rows.add_child(row)
	return edit


func _add_hilfe(rows: VBoxContainer, node_name: String, text: String) -> void:
	var label := Label.new()
	label.name = node_name
	label.theme_type_variation = "SoftLabel"
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_CAPTION * _tf))
	rows.add_child(label)


func _button(node_name: String, text: String, handler: Callable) -> SquishButton:
	var btn := SquishButton.new()
	btn.name = node_name
	btn.theme_type_variation = "BtnTeal"
	btn.text = text
	btn.focus_mode = Control.FOCUS_NONE
	btn.custom_minimum_size = Vector2(0, 48.0 * _f)
	btn.add_theme_font_size_override("font_size", int(AcTokens.FONT_SIZE_CAPTION * _tf))
	btn.pressed.connect(handler)
	return btn


## ------------------------------------------------------------- Persistenz


func _lade_override() -> void:
	var override := NetClient.load_user_override()
	if override.has("host"):
		var prefix := "wss://" if bool(override.get("tls", false)) else ""
		_server_edit.text = prefix + str(override["host"])
	if int(override.get("port", 0)) > 0:
		_port_edit.text = str(int(override["port"]))
	_secret_edit.text = str(override.get("secret", ""))
	_zuletzt_gespeichert = _config_aus_feldern()


## Felder -> Override-Config ({} = alles leer, zurueck auf Pack-Standard).
func _config_aus_feldern() -> Dictionary:
	var out := {}
	var adresse := parse_server_adresse(_server_edit.text)
	if not str(adresse["host"]).is_empty():
		out["host"] = adresse["host"]
		out["tls"] = bool(adresse["tls"])
	var port := int(adresse["port"])
	if _port_edit.text.strip_edges().is_valid_int():
		port = int(_port_edit.text.strip_edges())
	if port > 0 and out.has("host"):
		out["port"] = port
	if not _secret_edit.text.is_empty():
		out["secret"] = _secret_edit.text
	return out


func _speichern() -> void:
	var config := _config_aus_feldern()
	if config == _zuletzt_gespeichert:
		return
	_zuletzt_gespeichert = config
	if config.is_empty():
		NetClient.clear_user_override()
	else:
		NetClient.save_user_override(config)
	_set_chip(I18nService.t("netset.mp.chip_gespeichert"), CHIP_NEUTRAL)
	_neu_verbinden()


## "Zuruecksetzen auf Standard": Override-Datei weg, Felder leeren — ab dem
## naechsten Connect gilt wieder die Pack-Config des Update-Systems.
func _on_zuruecksetzen() -> void:
	NetClient.clear_user_override()
	_server_edit.text = ""
	_port_edit.text = ""
	_secret_edit.text = ""
	_zuletzt_gespeichert = {}
	_set_chip(I18nService.t("netset.mp.chip_zurueckgesetzt"), CHIP_NEUTRAL)
	_neu_verbinden()


## /root/Net einmal frisch verbinden lassen — der naechste Connect liest den
## Override (W2b-Contract). Fehlt der Autoload (Tests), passiert nichts.
func _neu_verbinden() -> void:
	var net := get_node_or_null("/root/Net")
	if net == null:
		return
	if net.has_method("disconnect_now") and net.has_method("connect_now"):
		net.disconnect_now()
		net.connect_now()


## ---------------------------------------------------------- Verbindungstest


func _on_testen() -> void:
	if _testing:
		return
	_speichern()
	var config := _config_aus_feldern()
	if config.is_empty():
		# Kein Override: gegen die effektive Pack-Config testen.
		config = _pack_config()
	_testing = true
	_set_chip(I18nService.t("netset.mp.chip_testet"), CHIP_NEUTRAL)
	var start_ms := Time.get_ticks_msec()
	var code := await _hello_roundtrip(config)
	_testing = false
	if not is_instance_valid(self) or not is_inside_tree():
		return
	if code == "OK":
		var ms := Time.get_ticks_msec() - start_ms
		_set_chip(I18nService.t("netset.mp.test_ok", {"ms": ms}), CHIP_OK)
	else:
		var grund := I18nService.t(fehler_text_key(code), {"code": code})
		_set_chip(I18nService.t("netset.mp.test_fehler", {"grund": grund}), CHIP_FEHLER)


## Wegwerf-NetClient: verbinden, HELLO laeuft automatisch, auf WELCOME/ERROR/
## Gate/Abbruch warten. Rueckgabe "OK" oder ein Fehlercode fuer den Chip.
func _hello_roundtrip(config: Dictionary) -> String:
	var probe := NetClient.new()
	probe.name = "MpTestClient"
	probe.auto_connect = false
	probe.build_services = false
	probe.identity_path = TEST_IDENTITY_PATH
	probe.config_override = config
	add_child(probe)
	var resultat := {"code": ""}
	probe.message_received.connect(
		func(envelope: Dictionary) -> void:
			var typ := str(envelope.get("t", ""))
			if typ == "WELCOME":
				resultat["code"] = "OK"
			elif typ == "ERROR" and envelope.get("d") is Dictionary:
				resultat["code"] = str((envelope["d"] as Dictionary).get("code", "UNREACHABLE"))
	)
	probe.insecure_blocked.connect(func(_host: String) -> void: resultat["code"] = "GATE")
	probe.status_changed.connect(
		func(status: int) -> void:
			if status == NetClient.Status.OFFLINE and str(resultat["code"]).is_empty():
				resultat["code"] = "UNREACHABLE"
	)
	probe.connect_now()
	var deadline := Time.get_ticks_msec() + TEST_TIMEOUT_MS
	while Time.get_ticks_msec() < deadline and str(resultat["code"]).is_empty():
		if not is_inside_tree():
			break
		await get_tree().process_frame
	probe.disconnect_now()
	probe.queue_free()
	if str(resultat["code"]).is_empty():
		return "TIMEOUT"
	# GATE gewinnt ueber das generische OFFLINE-UNREACHABLE (Signalreihenfolge:
	# status_changed feuert VOR insecure_blocked).
	return str(resultat["code"])


## Effektive Pack-Config (Registry oder NetClient-Default) als Test-Basis.
func _pack_config() -> Dictionary:
	var registry := get_node_or_null("/root/ContentRegistry")
	if registry != null and registry.has_method("get_net_config"):
		return registry.get_net_config()
	return NetClient.DEFAULT_NET.duplicate(true)


func _set_chip(text: String, farbe: Color) -> void:
	if _chip == null:
		return
	_chip.text = text
	_chip.add_theme_color_override("font_color", farbe)
