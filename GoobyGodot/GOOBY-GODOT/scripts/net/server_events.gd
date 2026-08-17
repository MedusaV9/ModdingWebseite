class_name ServerEventsService
extends Node
## Server-Events-Consumer (E14 P1-4 / E13 P1-2): konsumiert
## WELCOME.pendingEvents (Boot-Pull) und Live-SERVER_EVENT-Pushes, dedupet
## über die Event-Id (persistiert in user:// — übersteht App-Neustarts) und
## ACKt JEDE Zustellung per EVENT_ACK. Der Server markiert `deliveredTo`
## erst NACH dem Ack — verlorene WELCOMEs/Pushes werden dadurch beim
## nächsten Connect erneut zugestellt statt verloren zu gehen.
## Konsumenten (Home-Entry: Toast + Content-Hook) hängen an event_received.

signal event_received(id: String, type: String, params: Dictionary)

## Kappe der Dedupe-Liste (älteste Ids fliegen zuerst; Events verfallen
## serverseitig nach spätestens 7 Tagen, 200 reicht großzügig).
const SEEN_CAP := 200

var net: NetClient
## Dedupe-Datei (Tests leiten auf ein Temp-user://-File um).
var seen_path := "user://events_seen.json"

var _seen: Array[String] = []


func setup(net_client: NetClient) -> void:
	net = net_client
	net.welcome_received.connect(_on_welcome)
	net.pushed.connect(_on_push)
	_load_seen()


func _on_welcome(data: Dictionary) -> void:
	var pending: Variant = data.get("pendingEvents", [])
	if not (pending is Array):
		return
	for evt: Variant in pending as Array:
		if evt is Dictionary:
			_ingest(evt)


func _on_push(type: String, data: Dictionary) -> void:
	if type == "SERVER_EVENT":
		_ingest(data)


func _ingest(evt: Dictionary) -> void:
	var id := str(evt.get("id", ""))
	if id.is_empty():
		return
	# Ack IMMER (auch für Duplikate): ging ein früheres Ack verloren, würde
	# der Server das Event sonst bei jedem Connect erneut zustellen.
	if net != null:
		net.send("EVENT_ACK", {"id": id})
	if _seen.has(id):
		return
	_mark_seen(id)
	var params: Dictionary = evt.get("params") if evt.get("params") is Dictionary else {}
	event_received.emit(id, str(evt.get("type", "")), params)


func _load_seen() -> void:
	_seen = []
	if not FileAccess.file_exists(seen_path):
		return
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(seen_path)) != OK:
		return
	if not (parser.data is Dictionary):
		return
	var ids: Variant = (parser.data as Dictionary).get("ids")
	if not (ids is Array):
		return
	for id: Variant in ids as Array:
		if id is String:
			_seen.append(id)


func _mark_seen(id: String) -> void:
	_seen.append(id)
	while _seen.size() > SEEN_CAP:
		_seen.pop_front()
	var tmp := seen_path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_warning("[events] kann %s nicht schreiben" % tmp)
		return
	file.store_string(JSON.stringify({"v": 1, "ids": _seen}))
	file.close()
	var dir := DirAccess.open(seen_path.get_base_dir())
	if dir != null:
		dir.rename(tmp, seen_path)
