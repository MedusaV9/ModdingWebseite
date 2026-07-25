class_name AnalyticsSessions
extends Node
## Analytics-Sessions (Doc C §5 / W2c §5 REST): Session-Start beim Boot,
## Heartbeat alle 60 s (upsert des LAUFENDEN Session-Eintrags in die Outbox —
## ein Crash verliert höchstens die letzte Minute), Ende beim Beenden.
## Flush: sobald der NetClient online kommt (und nach jedem Heartbeat, wenn
## online), werden alle Outbox-Sessions als EIN idempotenter Batch an
## POST /api/analytics geschickt (batchId + sessionId dedupen serverseitig).
## Der HTTP-Sender ist injizierbar (Tests); Default = HTTPRequest.

const HEARTBEAT_SEC := 60.0
const OUTBOX_KIND := "analytics_session"
const MAX_SESSIONS_PER_BATCH := 200

var net: NetClient
var outbox: NetOutbox
## Tests: poster.call(url, headers: PackedStringArray, body: String) -> bool.
var poster: Callable = Callable()
## Basis-URL für REST (Tests/Integration überschreiben; leer = aus WS-Config).
var rest_base_url := ""

var session_id := ""
var started_at_ms := 0

var _accum := 0.0
var _flush_in_flight := false


func setup(net_client: NetClient, outbox_instance: NetOutbox) -> void:
	net = net_client
	outbox = outbox_instance
	net.status_changed.connect(_on_status_changed)
	# E14 P1-1: lief _ready() schon OHNE Outbox (falsche Boot-Reihenfolge),
	# den Session-Start jetzt nachschreiben — sonst zählt die Session erst
	# ab dem ersten Heartbeat und ein Crash davor verliert sie komplett.
	if not session_id.is_empty():
		_write_session(_now_ms())


func _ready() -> void:
	start_session()


func _exit_tree() -> void:
	end_session()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED:
		end_session()
	elif what == NOTIFICATION_APPLICATION_RESUMED:
		# Zurück aus dem Hintergrund → neue Session (Spielzeit ab Sekunde 0).
		start_session()


func _process(delta: float) -> void:
	if session_id.is_empty():
		return
	_accum += delta
	if _accum >= HEARTBEAT_SEC:
		_accum = 0.0
		heartbeat()


func start_session() -> void:
	if not session_id.is_empty():
		return
	session_id = NetClient.uuid4()
	started_at_ms = _now_ms()
	_write_session(started_at_ms)


## Aktualisiert den laufenden Session-Eintrag (idempotent über sessionId).
func heartbeat() -> void:
	if session_id.is_empty():
		return
	_write_session(_now_ms())
	if net != null and net.is_online():
		flush()


func end_session() -> void:
	if session_id.is_empty():
		return
	_write_session(_now_ms())
	session_id = ""


## Alle Outbox-Sessions als EIN Batch senden; Fehlschläge bleiben liegen.
func flush() -> void:
	if outbox == null or _flush_in_flight:
		return
	var sessions := outbox.entries(OUTBOX_KIND)
	if sessions.is_empty():
		return
	_flush_in_flight = true
	var payload_sessions: Array[Dictionary] = []
	var ids: Array[String] = []
	for entry in sessions:
		if payload_sessions.size() >= MAX_SESSIONS_PER_BATCH:
			break
		payload_sessions.append(entry["payload"])
		ids.append(str(entry["id"]))
	var body := JSON.stringify({"batchId": NetClient.uuid4(), "sessions": payload_sessions})
	var ok := await _post("/api/analytics", body)
	if ok:
		for id in ids:
			# E14 P1-2: der Eintrag der LAUFENDEN Session bleibt liegen —
			# der nächste Heartbeat verlängert ihn und der Server upsertet
			# pro sessionId nach max. Dauer. Würde er entfernt, ginge die
			# Restdauer nach einem Reconnect-Flush verloren.
			if id == session_id:
				continue
			outbox.remove(id)
	_flush_in_flight = false


func _write_session(ended_at_ms: int) -> void:
	if outbox == null:
		return
	var minutes := maxf(0.0, float(ended_at_ms - started_at_ms) / 60000.0)
	(
		outbox
		. upsert(
			OUTBOX_KIND,
			session_id,
			{
				"sessionId": session_id,
				"startedAt": started_at_ms,
				"endedAt": ended_at_ms,
				"minutes": snappedf(minutes, 0.1),
				"appVersion": "5.0.0-godot",
			}
		)
	)


func _on_status_changed(status: int) -> void:
	if status == NetClient.Status.ONLINE:
		flush()


func _post(path: String, body: String) -> bool:
	var identity := net.identity() if net != null else {}
	var headers := PackedStringArray(
		[
			"Content-Type: application/json",
			(
				"Authorization: Bearer %s:%s"
				% [identity.get("deviceId"), identity.get("deviceSecret")]
			),
		]
	)
	var url := _base_url() + path
	if poster.is_valid():
		return poster.call(url, headers, body) == true
	if not is_inside_tree():
		return false
	var req := HTTPRequest.new()
	add_child(req)
	req.timeout = 10.0
	var err := req.request(url, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		req.queue_free()
		return false
	var result: Array = await req.request_completed
	req.queue_free()
	return int(result[0]) == HTTPRequest.RESULT_SUCCESS and int(result[1]) < 300


func _base_url() -> String:
	if not rest_base_url.is_empty():
		return rest_base_url
	var net_config := net._resolve_net_config() if net != null else NetClient.DEFAULT_NET
	var scheme := "https" if net_config.get("tls", false) else "http"
	return "%s://%s:%d" % [scheme, net_config["host"], int(net_config["port"])]


func _now_ms() -> int:
	return int(Time.get_unix_time_from_system() * 1000.0)
