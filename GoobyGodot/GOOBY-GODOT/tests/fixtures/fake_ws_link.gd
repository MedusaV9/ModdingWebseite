class_name FakeWsLink
extends RefCounted
## WebSocketPeer-Double für NetClient-Tests: gleiche Duck-Typing-Oberfläche
## (connect_to_url/poll/get_ready_state/get_available_packet_count/get_packet/
## send_text/close). Tests steuern den Zustand (open()/drop()) und spielen
## Server-Frames über push_server() ein; alles Gesendete liegt geparst in
## `sent` (Envelope-Dictionaries, W2c §1).

var state: int = WebSocketPeer.STATE_CONNECTING
var connected_url := ""
var sent: Array[Dictionary] = []

var _incoming: Array[PackedByteArray] = []


func connect_to_url(url: String) -> int:
	connected_url = url
	state = WebSocketPeer.STATE_CONNECTING
	return OK


func poll() -> void:
	pass


func get_ready_state() -> int:
	return state


func get_available_packet_count() -> int:
	return _incoming.size()


func get_packet() -> PackedByteArray:
	return _incoming.pop_front()


func send_text(text: String) -> int:
	var parser := JSON.new()
	if parser.parse(text) == OK and parser.data is Dictionary:
		sent.append(parser.data)
	return OK


func close(_code := 1000, _reason := "") -> void:
	state = WebSocketPeer.STATE_CLOSED


## Test-Steuerung: „Handshake fertig“ — ab jetzt sieht NetClient STATE_OPEN.
func open() -> void:
	state = WebSocketPeer.STATE_OPEN


## Test-Steuerung: Verbindungsabriss (Server weg / Netz weg).
func drop() -> void:
	state = WebSocketPeer.STATE_CLOSED


## Server → Client: Envelope einspielen (nächster poll()-Durchlauf liest ihn).
func push_server(envelope: Dictionary) -> void:
	_incoming.append(JSON.stringify(envelope).to_utf8_buffer())


## Antwort auf den LETZTEN gesendeten Request dieses Typs (re == dessen seq).
func respond_to(request_type: String, response_type: String, data: Dictionary) -> void:
	var req := last_sent(request_type)
	push_server(
		{
			"v": 1,
			"t": response_type,
			"re": int(req.get("seq", -1)),
			"ts": 0,
			"d": data,
		}
	)


## Jüngster gesendeter Envelope dieses Typs ({} wenn nie gesendet).
func last_sent(type: String) -> Dictionary:
	for i in range(sent.size() - 1, -1, -1):
		if sent[i].get("t", "") == type:
			return sent[i]
	return {}


## Anzahl gesendeter Envelopes eines Typs.
func count_sent(type: String) -> int:
	var n := 0
	for envelope in sent:
		if envelope.get("t", "") == type:
			n += 1
	return n
