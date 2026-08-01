class_name RmpHub
extends Node
## RW-6/G4 (G1 §1.7 [hoch]): DER bisher fehlende Spiel-Einstieg des
## Ranch-Mehrspielers. Hängt per attach_to() an einer Ranch-Szene und
## öffnet die vorhandenen RW-6-Panels als zentrierte PanelSheets
## (Breiten-Deckel + Safe-Area geschenkt, panel_sheet.gd): Hub
## (RmpMenuPanel) → Bestenliste (RmpLeaderboardPanel); meldet der Service
## eine Session, übernimmt die Lobby (RmpLobbyPanel — Bereit/Countdown/
## Ergebnis/Revanche). Session-/Netz-Logik wird NUR konsumiert: der
## geteilte RanchMultiplayerService lebt unter /root (Muster
## SocialServices.get_or_create) und überlebt Szenenwechsel.

const PanelSheetScene := preload("res://scripts/ui/panel_sheet.tscn")
const DIENST_NAME := "RanchMpDienst"
## Meta-Key am Dienst-Knoten: zuletzt geladene Bestenlisten-Geister je
## Kurs-Id (Konsument: der Region-Lauf, s. G4/P19-Abschlussbericht).
const META_GEISTER := "rmp_geist_cache"

var _layer: CanvasLayer
var _menu_sheet: PanelSheet
var _besten_sheet: PanelSheet
var _lobby_sheet: PanelSheet


## Hub an eine Ranch-Szene hängen (idempotent, Muster RanchEventHost).
static func attach_to(szene: Node) -> RmpHub:
	var vorhanden := szene.get_node_or_null("RmpHub")
	if vorhanden is RmpHub:
		return vorhanden
	var hub := RmpHub.new()
	hub.name = "RmpHub"
	szene.add_child(hub)
	return hub


## Geteilten Ranch-MP-Dienst holen/anlegen. Verdrahtet sich mit /root/Net
## (Duck-Typing) — ohne Netz bleibt alles höflich offline (RW-6-Vertrag).
static func dienst(baum: SceneTree) -> RanchMultiplayerService:
	var wurzel := baum.root
	var vorhanden := wurzel.get_node_or_null(DIENST_NAME)
	if vorhanden is RanchMultiplayerService:
		return vorhanden
	var service := RanchMultiplayerService.new()
	service.name = DIENST_NAME
	wurzel.add_child(service)
	var net := wurzel.get_node_or_null("Net")
	if net != null and net.has_signal("pushed") and net.has_signal("welcome_received"):
		service.setup(net)
	return service


func _ready() -> void:
	# Eigener CanvasLayer: die Hof-Szene ist 3D — Sheets müssen ÜBER dem
	# Hof-HUD (CanvasLayer 1) liegen und Vollbild-Anker bekommen.
	_layer = CanvasLayer.new()
	_layer.name = "RmpSheetLayer"
	_layer.layer = 10
	add_child(_layer)
	var service := dienst(get_tree())
	service.session_ready.connect(_on_session_ready)
	service.session_ended.connect(_on_session_ended)


## Einstieg vom Hof-Knopf: laufende Session → direkt in die Lobby,
## sonst der Hub mit Modus-Wahl, Freundesliste und Einladungen.
func oeffne() -> void:
	if dienst(get_tree()).is_active():
		_zeige_lobby()
	else:
		_zeige_menu()


func offenes_sheet() -> PanelSheet:
	for sheet: PanelSheet in [_lobby_sheet, _besten_sheet, _menu_sheet]:
		if sheet != null and is_instance_valid(sheet) and sheet.is_open():
			return sheet
	return null


## ---------------------------------------------------------------- intern


func _zeige_menu() -> void:
	_schliesse_sheets()
	var panel := RmpMenuPanel.new()
	panel.leaderboard_pressed.connect(_zeige_bestenliste)
	_menu_sheet = _sheet(panel)
	panel.setup(dienst(get_tree()), _friends_service())


func _zeige_bestenliste() -> void:
	_schliesse_sheets()
	var panel := RmpLeaderboardPanel.new()
	panel.setup(dienst(get_tree()))
	panel.ghost_requested.connect(_on_geist_gewuenscht)
	_besten_sheet = _sheet(panel)
	await panel.refresh()


func _zeige_lobby() -> void:
	_schliesse_sheets()
	var panel := RmpLobbyPanel.new()
	panel.leave_pressed.connect(_on_lobby_verlassen)
	_lobby_sheet = _sheet(panel)
	panel.setup(dienst(get_tree()))


## Sheet im AC-Look bauen: Panels bringen ihre eigene Headline mit, darum
## ohne Sheet-Titelzeile. open()/close() klingen zentral im PanelSheet.
func _sheet(inhalt: Control) -> PanelSheet:
	var sheet: PanelSheet = PanelSheetScene.instantiate()
	sheet.theme = ThemeService.theme()
	_layer.add_child(sheet)
	sheet.set_title("")
	sheet.add_content(inhalt)
	sheet.open()
	# Nachmessen im Folgeframe: open() im selben Frame wie add_content()
	# misst noch stale Minimum-Caches — das Blatt spannte sonst hochkant
	# auf den Höhen-Deckel statt den Inhalt zu umarmen (_relayout ist laut
	# PanelSheet-Doku direkt aufrufbar, „open/resize; Tests rufen es direkt“).
	sheet._relayout.call_deferred()
	sheet.closed.connect(sheet.queue_free)
	return sheet


func _schliesse_sheets() -> void:
	for sheet: PanelSheet in [_menu_sheet, _besten_sheet, _lobby_sheet]:
		if sheet != null and is_instance_valid(sheet):
			sheet.close()
	_menu_sheet = null
	_besten_sheet = null
	_lobby_sheet = null


## RANCH_READY (Einladung angenommen — egal auf welcher Seite): die Lobby
## übernimmt den Sheet-Platz.
func _on_session_ready(_data: Dictionary) -> void:
	_zeige_lobby()


func _on_session_ended(_data: Dictionary) -> void:
	var lobby_offen := _lobby_sheet != null and is_instance_valid(_lobby_sheet)
	_schliesse_sheets()
	if lobby_offen:
		_melde(I18nService.t("ranch_mp.lobby.beendet"))


func _on_lobby_verlassen() -> void:
	_schliesse_sheets()
	await dienst(get_tree()).leave()


## Bestenlisten-Geist holen und am Dienst zwischenlagern (Konsument:
## der Region-Lauf). Ausgang klingt/meldet ehrlich (Offline-Fehlertext).
func _on_geist_gewuenscht(kurs_id: String, friend_code: String) -> void:
	var service := dienst(get_tree())
	var res: Dictionary = await service.rest.fetch_ghost(kurs_id, friend_code)
	if not bool(res.get("ok", false)):
		_melde(RanchMultiplayerService.fehler_text(str(res.get("code", ""))))
		return
	var cache: Dictionary = {}
	if service.has_meta(META_GEISTER):
		cache = service.get_meta(META_GEISTER)
	cache[kurs_id] = res.get("ghost", {})
	service.set_meta(META_GEISTER, cache)
	_melde(I18nService.t("ranch_mp.besten.geist_ok"))


func _friends_service() -> Node:
	var net := get_node_or_null("/root/Net")
	if net == null:
		return null
	var friends: Variant = net.get("friends")
	return friends if friends is Node else null


## Meldungen über den Toast der Trägerszene (zeige_meldung-Vertrag des
## Hofs — Muster RanchEventHost._melde).
func _melde(text: String) -> void:
	var szene := get_parent()
	if szene != null and szene.has_method("zeige_meldung"):
		szene.zeige_meldung(text)
