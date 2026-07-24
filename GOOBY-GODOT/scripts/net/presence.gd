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
