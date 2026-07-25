class_name PresenceService
extends Node
## Presence-Melder (W2c §3): Der Client meldet nur den Status-String `kind`
## (home|park|city|minigame:<id>|…) — das deutsche Label baut der SERVER.
## Flüchtig per Kontrakt: NIE puffern (kein Outbox-Eintrag), idempotente
## Wiederholungen desselben kind werden lokal geschluckt; nach jedem
## WELCOME (Reconnect) wird der aktuelle Zustand einmal neu gemeldet.

var net: NetClient

var _kind := ""
var _sent_kind := ""


func setup(net_client: NetClient) -> void:
	net = net_client
	net.welcome_received.connect(_on_welcome)
	net.status_changed.connect(_on_status_changed)


## Aktuelle Aktivität setzen (z. B. "minigame:teaParty", "home", "park").
func set_kind(kind: String) -> void:
	_kind = kind.substr(0, 32)
	_push()


## Router-Ziel → Presence-kind (E14 P1-5, pur testbar). Der Home-Entry ruft
## das bei jedem travel_finished; game_id kommt vom MinigameHost (falls
## vorhanden). Unbekannte Stadt-Orte melden ihre Ort-Id — der SERVER baut
## daraus das deutsche Label (Templates serverseitig aktualisierbar).
static func kind_for_route(target: String, game_id := "") -> String:
	if target.begins_with("home/"):
		return "home"
	if target == "city":
		return "city"
	if target.begins_with("city/ort/"):
		var ort := target.trim_prefix("city/ort/")
		match ort:
			"rehwei":
				return "park"
			"gouhbus":
				return "ikea"
			_:
				return ort
	if target == "social/visit":
		return "visit"
	if target == "social/battleship":
		return "board"
	if target == "mg_host":
		return "minigame:%s" % (game_id if not game_id.is_empty() else "arcade")
	# Vollbild-Screens (social/album/arcade/…) laufen weiter zuhause.
	return "home"


func current_kind() -> String:
	return _kind


func _push() -> void:
	if net == null or not net.is_online():
		return
	if _kind.is_empty() or _kind == _sent_kind:
		return
	net.send("PRESENCE_SET", {"kind": _kind})
	_sent_kind = _kind


func _on_welcome(_data: Dictionary) -> void:
	_sent_kind = ""
	_push()


func _on_status_changed(status: int) -> void:
	if status != NetClient.Status.ONLINE:
		_sent_kind = ""
