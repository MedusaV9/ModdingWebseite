class_name NetClient
extends Node
## GOOBY-NetClient (Doc C §6 / W2c-protocol.md): WebSocketPeer-Verbindung zum
## GOOBY-SERVER — Envelope {v,t,seq,ts,d}, HELLO/WELCOME-Handshake (TOFU-
## Identität deviceId+deviceSecret in user://), PING-Heartbeat, Reconnect-
## Backoff. OFFLINE-FIRST: nichts hier blockiert je das Spiel; request() ist
## eine await-bare Coroutine mit Timeout, alle Zustände laufen über Signale.
## Autoload-Wunsch „Net“ (project-godot-requests.md); bis dahin Duck-Typing.
## Komposition: outbox / presence / friends / analytics / redeem /
## server_events hängen als Kinder.

signal status_changed(status: int)
signal welcome_received(data: Dictionary)
signal pushed(type: String, data: Dictionary)
signal message_received(envelope: Dictionary)
## ws://-Heimnetz-Gate (Doc C §7): unverschlüsselte Verbindung zu einem
## öffentlichen Host wurde verweigert — Client bleibt im Offline-Modus.
signal insecure_blocked(host: String)

enum Status { OFFLINE, CONNECTING, ONLINE }

const PROTOCOL_VERSION := 1
const REQUEST_TIMEOUT_MS := 10_000
const RECONNECT_BASE_SEC := 1.0
const RECONNECT_MAX_SEC := 30.0
## Fallback, wenn weder ContentRegistry noch config.json liefern (W2b-Doku).
const DEFAULT_NET := {"host": "127.0.0.1", "port": 8765, "tls": false}
const EMBEDDED_CONFIG_PATH := "res://content/config/data/config.json"
## Toast-Text fürs Heimnetz-Gate (strings/<locale>/net.json).
const GATE_TOAST_KEY := "net.gate.ws_heimnetz"

## Beim _ready automatisch verbinden (Autoload-Betrieb). Tests: false.
var auto_connect := true
## Kinder-Services automatisch anlegen (Outbox/Presence/Friends/Analytics).
var build_services := true
## Tests: Factory für den Link (FakeWsLink); leer → echter WebSocketPeer.
var link_factory: Callable = Callable()
## Tests/Integration: Config-Override {host, port, tls} statt Registry.
var config_override: Dictionary = {}
## Identitäts-Datei (Tests leiten auf ein Temp-user://-File um).
var identity_path := "user://net_identity.json"
## Outbox-Datei (Tests leiten auf ein Temp-user://-File um).
var outbox_path := "user://outbox.json"

var status: int = Status.OFFLINE
var friend_code := ""
var heartbeat_sec := 20.0
var welcome_data: Dictionary = {}

var outbox: NetOutbox
var presence: PresenceService
var friends: FriendsService
var analytics: AnalyticsSessions
var redeem: RedeemService
var server_events: ServerEventsService

var _link: Variant = null
var _want_connected := false
var _hello_sent := false
var _seq := 0
var _responses: Dictionary = {}
var _identity: Dictionary = {}
var _reconnect_attempts := 0
var _reconnect_at_ms := -1
var _heartbeat_accum := 0.0
## Gate-Toast nur EINMAL pro geblocktem Host (Reconnects spammen sonst).
var _gate_toasted_host := ""


func _ready() -> void:
	_identity = _load_or_create_identity()
	if build_services:
		outbox = NetOutbox.new(outbox_path)
		presence = PresenceService.new()
		presence.name = "Presence"
		add_child(presence)
		presence.setup(self)
		friends = FriendsService.new()
		friends.name = "Friends"
		add_child(friends)
		friends.setup(self)
		analytics = AnalyticsSessions.new()
		analytics.name = "Analytics"
		# setup() MUSS vor add_child() kommen: _ready() startet die Session
		# und braucht die Outbox bereits — sonst geht der Session-Start bei
		# Crash vor dem ersten Heartbeat verloren (E14 P1-1).
		analytics.setup(self, outbox)
		add_child(analytics)
		redeem = RedeemService.new()
		redeem.name = "Redeem"
		redeem.setup(self, outbox)
		add_child(redeem)
		server_events = ServerEventsService.new()
		server_events.name = "ServerEvents"
		server_events.setup(self)
		add_child(server_events)
	if auto_connect:
		connect_now()


func _process(delta: float) -> void:
	if _link == null:
		_maybe_reconnect()
		return
	_link.poll()
	var state: int = _link.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _hello_sent:
			_send_hello()
		while _link.get_available_packet_count() > 0:
			var packet: PackedByteArray = _link.get_packet()
			_handle_message(packet.get_string_from_utf8())
		_heartbeat_tick(delta)
	elif state == WebSocketPeer.STATE_CLOSED:
		_on_link_closed()


## Verbindungsaufbau anstoßen (nie blockierend). Liest die Netz-Config bei
## JEDEM Connect frisch (W2b-Contract: Remote-Config wirkt sofort).
func connect_now() -> void:
	_want_connected = true
	if _link != null:
		return
	var net_config := _resolve_net_config()
	var use_tls := bool(net_config.get("tls", false))
	var host := str(net_config.get("host", ""))
	# ws://-Heimnetz-Gate (Doc C §7 / AP-12): unverschlüsselt NUR zu privaten/
	# lokalen Zielen — sonst kein Verbindungsversuch, Offline-Modus + Toast.
	# wss:// (tls) bleibt immer erlaubt. Der Reconnect-Backoff bleibt aktiv,
	# damit eine korrigierte Remote-Config (tls=true) sofort wieder greift.
	if not use_tls and not NetHostGate.is_private_host(host):
		_refuse_insecure(host)
		return
	var scheme := "wss" if use_tls else "ws"
	var url := "%s://%s:%d/ws" % [scheme, host, int(net_config["port"])]
	_link = link_factory.call() if link_factory.is_valid() else WebSocketPeer.new()
	_hello_sent = false
	_set_status(Status.CONNECTING)
	var err: int = _link.connect_to_url(url)
	if err != OK:
		_link = null
		_schedule_reconnect()
		_set_status(Status.OFFLINE)


func disconnect_now() -> void:
	_want_connected = false
	if _link != null:
		_link.close()
		_link = null
	_hello_sent = false
	_set_status(Status.OFFLINE)


func is_online() -> bool:
	return status == Status.ONLINE


## Fire-and-forget-Envelope; liefert die vergebene seq (-1 = kein Link offen).
func send(type: String, data: Dictionary = {}) -> int:
	if _link == null or _link.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return -1
	_seq += 1
	var envelope := {
		"v": PROTOCOL_VERSION,
		"t": type,
		"seq": _seq,
		"ts": _now_ms(),
		"d": data,
	}
	_link.send_text(JSON.stringify(envelope))
	return _seq


## Request/Response-Coroutine: matcht die Server-Antwort über re == seq
## (W2c §7). Liefert {ok, t, d, code} — offline sofort {ok:false, OFFLINE}.
func request(type: String, data: Dictionary = {}, timeout_ms := REQUEST_TIMEOUT_MS) -> Dictionary:
	var seq := send(type, data)
	if seq < 0:
		return {"ok": false, "code": "OFFLINE", "t": "", "d": {}}
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		if _responses.has(seq):
			var envelope: Dictionary = _responses[seq]
			_responses.erase(seq)
			var payload: Dictionary = envelope.get("d", {})
			if envelope.get("t", "") == "ERROR":
				return {
					"ok": false,
					"code": str(payload.get("code", "ERROR")),
					"t": "ERROR",
					"d": payload,
				}
			return {"ok": true, "code": "", "t": str(envelope.get("t", "")), "d": payload}
		if not is_inside_tree():
			break
		await get_tree().process_frame
	return {"ok": false, "code": "TIMEOUT", "t": "", "d": {}}


## Coins-ANZEIGE-Cache an den Server melden (client-autoritativ, kein Ack).
func sync_coins(coins: int) -> void:
	send("SYNC", {"coins": coins})


## Identität für REST-Aufrufe (Authorization: Bearer deviceId:deviceSecret).
func identity() -> Dictionary:
	return {
		"deviceId": str(_identity.get("deviceId", "")),
		"deviceSecret": str(_identity.get("deviceSecret", "")),
	}


static func uuid4() -> String:
	var crypto := Crypto.new()
	var bytes := crypto.generate_random_bytes(16)
	bytes[6] = (bytes[6] & 0x0F) | 0x40
	bytes[8] = (bytes[8] & 0x3F) | 0x80
	var hex := bytes.hex_encode()
	return (
		"%s-%s-%s-%s-%s"
		% [hex.substr(0, 8), hex.substr(8, 4), hex.substr(12, 4), hex.substr(16, 4), hex.substr(20)]
	)


func _send_hello() -> void:
	_hello_sent = true
	var data := {
		"deviceId": _identity["deviceId"],
		"deviceSecret": _identity["deviceSecret"],
		"name": _player_name(),
		"goobyName": _gooby_name(),
		"appVersion": "5.0.0-godot",
	}
	if not friend_code.is_empty():
		data["friendCode"] = friend_code
	elif not str(_identity.get("friendCode", "")).is_empty():
		data["friendCode"] = _identity["friendCode"]
	send("HELLO", data)


func _handle_message(raw: String) -> void:
	var parser := JSON.new()
	if parser.parse(raw) != OK or not (parser.data is Dictionary):
		return
	var envelope: Dictionary = parser.data
	var type := str(envelope.get("t", ""))
	var data: Dictionary = envelope.get("d", {}) if envelope.get("d") is Dictionary else {}
	message_received.emit(envelope)
	if type == "WELCOME":
		_on_welcome(data)
	if envelope.has("re"):
		_responses[int(envelope["re"])] = envelope
		return
	match type:
		"PONG", "OK", "WELCOME":
			pass
		"GOING_DOWN":
			pushed.emit(type, data)
		_:
			pushed.emit(type, data)


func _on_welcome(data: Dictionary) -> void:
	welcome_data = data
	friend_code = str(data.get("friendCode", friend_code))
	heartbeat_sec = maxf(5.0, float(data.get("heartbeatSec", 20)))
	_reconnect_attempts = 0
	_heartbeat_accum = 0.0
	if not friend_code.is_empty() and _identity.get("friendCode", "") != friend_code:
		_identity["friendCode"] = friend_code
		_save_identity()
	_set_status(Status.ONLINE)
	welcome_received.emit(data)


func _heartbeat_tick(delta: float) -> void:
	if status != Status.ONLINE:
		return
	_heartbeat_accum += delta
	if _heartbeat_accum >= heartbeat_sec:
		_heartbeat_accum = 0.0
		send("PING", {})


func _on_link_closed() -> void:
	_link = null
	_hello_sent = false
	_responses.clear()
	_set_status(Status.OFFLINE)
	if _want_connected:
		_schedule_reconnect()


func _schedule_reconnect() -> void:
	var backoff := minf(
		RECONNECT_MAX_SEC, RECONNECT_BASE_SEC * pow(2.0, float(_reconnect_attempts))
	)
	_reconnect_attempts += 1
	var jitter := randf() * 0.3 * backoff
	_reconnect_at_ms = Time.get_ticks_msec() + int((backoff + jitter) * 1000.0)


func _maybe_reconnect() -> void:
	if not _want_connected or _reconnect_at_ms < 0:
		return
	if Time.get_ticks_msec() >= _reconnect_at_ms:
		_reconnect_at_ms = -1
		connect_now()


## Heimnetz-Gate hat zugeschlagen: offline bleiben, Signal + (einmal pro
## Host) deutscher Fehler-Toast über einen ToastLayer im Baum, falls einer
## existiert (headless/Tests: nur das Signal).
func _refuse_insecure(host: String) -> void:
	_schedule_reconnect()
	_set_status(Status.OFFLINE)
	insecure_blocked.emit(host)
	if _gate_toasted_host == host:
		return
	_gate_toasted_host = host
	push_warning("[net] ws:// zu öffentlichem Host »%s« blockiert — wss:// (TLS) nötig" % host)
	_show_gate_toast()


func _show_gate_toast() -> void:
	var tree_ref := get_tree()
	if tree_ref == null:
		return
	for layer in tree_ref.root.find_children("*", "ToastLayer", true, false):
		if layer.has_method("show_toast"):
			layer.show_toast(I18nService.t(GATE_TOAST_KEY), true)
			return


func _set_status(next: int) -> void:
	if status == next:
		return
	status = next
	status_changed.emit(next)


## W2b-Contract: ContentRegistry.get_net_config() > eingebaute config.json >
## DEFAULT_NET. config_override (Tests/Integration) schlägt alles.
func _resolve_net_config() -> Dictionary:
	if not config_override.is_empty():
		return config_override
	var registry := get_node_or_null("/root/ContentRegistry")
	if registry != null and registry.has_method("get_net_config"):
		return registry.get_net_config()
	if FileAccess.file_exists(EMBEDDED_CONFIG_PATH):
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(EMBEDDED_CONFIG_PATH)) == OK:
			if parser.data is Dictionary and (parser.data as Dictionary).get("net") is Dictionary:
				var net: Dictionary = parser.data["net"]
				return {
					"host": str(net.get("host", DEFAULT_NET["host"])),
					"port": int(net.get("port", DEFAULT_NET["port"])),
					"tls": bool(net.get("tls", DEFAULT_NET["tls"])),
				}
	return DEFAULT_NET


func _load_or_create_identity() -> Dictionary:
	if FileAccess.file_exists(identity_path):
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(identity_path)) == OK:
			var data: Variant = parser.data
			if data is Dictionary and data.has("deviceId") and data.has("deviceSecret"):
				return data
	var crypto := Crypto.new()
	var identity_data := {
		"deviceId": "gd-%s" % uuid4(),
		"deviceSecret": crypto.generate_random_bytes(32).hex_encode(),
		"friendCode": "",
	}
	_identity = identity_data
	_save_identity()
	return identity_data


func _save_identity() -> void:
	var file := FileAccess.open(identity_path, FileAccess.WRITE)
	if file == null:
		push_warning("[net] kann Identität nicht speichern: %s" % identity_path)
		return
	file.store_string(JSON.stringify(_identity))
	file.close()


func _player_name() -> String:
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("get_value"):
		var value := str(gs.get_value("meta.playerName", ""))
		if not value.is_empty():
			return value
	return "Gooby-Fan"


func _gooby_name() -> String:
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("get_value"):
		var value := str(gs.get_value("meta.goobyNickname", ""))
		if not value.is_empty():
			return value
	return "Gooby"


func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)
