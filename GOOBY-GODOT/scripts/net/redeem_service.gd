class_name RedeemService
extends Node
## Code-Einlösung (Doc C §4 / E14 P1-3): POST /api/codes/redeem mit
## Bearer-Auth. OFFLINE-FIRST: ist der Server nicht erreichbar, landet der
## Code in der persistenten Outbox (kind "redeem", upsert über den Code —
## kein Doppel-Eintrag) und wird beim nächsten ONLINE-Wechsel geflusht.
## Idempotenz: der Server dedupet pro Gerät (ALREADY_REDEEMED) — ein Retry
## nach Crash zwischen Server-ok und Outbox-Aufräumen ist dadurch harmlos
## und wird still aus der Queue entfernt. Endgültige Ablehnungen (UNKNOWN,
## EXPIRED, …) fliegen ebenfalls raus; nur Transportfehler bleiben liegen.
## Der HTTP-Sender ist injizierbar (Tests); Default = HTTPRequest (10 s).

signal redeemed(code: String, reward: Dictionary)
signal redeem_failed(code: String, error: String)

const OUTBOX_KIND := "redeem"
## Endgültige Server-Antworten: Retry ändert nichts mehr → Eintrag fliegt.
const FINAL_ERRORS: Array[String] = [
	"UNKNOWN", "INACTIVE", "NOT_YET_VALID", "EXPIRED", "EXHAUSTED", "BAD_CODE"
]

var net: NetClient
var outbox: NetOutbox
## Tests: poster.call(url, headers, body) -> Dictionary (geparste Antwort)
## oder null (Transportfehler). Ungültig → echter HTTPRequest.
var poster: Callable = Callable()
## Basis-URL für REST (Tests/Integration überschreiben; leer = aus WS-Config).
var rest_base_url := ""

var _flush_in_flight := false


func setup(net_client: NetClient, outbox_instance: NetOutbox) -> void:
	net = net_client
	outbox = outbox_instance
	net.status_changed.connect(_on_status_changed)


## Code einlösen. Online → sofortiger Versuch; offline/Transportfehler →
## Outbox. Liefert {ok, code, queued[, reward]} — nie blockierend > 10 s.
func redeem(code: String) -> Dictionary:
	var clean := code.strip_edges().to_upper()
	if clean.is_empty():
		return {"ok": false, "code": "BAD_CODE", "queued": false}
	if net == null or not net.is_online():
		_enqueue(clean)
		return {"ok": false, "code": "QUEUED", "queued": true}
	var response := await _post_redeem(clean)
	if not bool(response["transport_ok"]):
		_enqueue(clean)
		return {"ok": false, "code": "QUEUED", "queued": true}
	return _apply_result(clean, response["data"], "")


## Alle gepufferten Redeems senden (Reconnect-Flush, analog Analytics).
func flush() -> void:
	if outbox == null or _flush_in_flight:
		return
	var entries := outbox.entries(OUTBOX_KIND)
	if entries.is_empty():
		return
	_flush_in_flight = true
	for entry in entries:
		if net == null or not net.is_online():
			break
		var code := str((entry["payload"] as Dictionary).get("code", ""))
		if code.is_empty():
			outbox.remove(str(entry["id"]))
			continue
		var response := await _post_redeem(code)
		if not bool(response["transport_ok"]):
			break
		_apply_result(code, response["data"], str(entry["id"]))
	_flush_in_flight = false


func _enqueue(code: String) -> void:
	if outbox == null:
		return
	outbox.upsert(OUTBOX_KIND, "redeem:%s" % code, {"code": code})


## Server-Antwort auswerten; outbox_id != "" räumt den Queue-Eintrag ab.
func _apply_result(code: String, data: Dictionary, outbox_id: String) -> Dictionary:
	if bool(data.get("ok", false)):
		if not outbox_id.is_empty():
			outbox.remove(outbox_id)
		var reward: Dictionary = data.get("reward") if data.get("reward") is Dictionary else {}
		redeemed.emit(code, reward)
		return {"ok": true, "code": "", "queued": false, "reward": reward}
	var error := str(data.get("code", "ERROR"))
	if error == "ALREADY_REDEEMED":
		# Idempotenter Retry (Crash nach Server-ok): still abräumen.
		if not outbox_id.is_empty():
			outbox.remove(outbox_id)
		return {"ok": false, "code": error, "queued": false}
	if FINAL_ERRORS.has(error):
		if not outbox_id.is_empty():
			outbox.remove(outbox_id)
		redeem_failed.emit(code, error)
		return {"ok": false, "code": error, "queued": false}
	# RATE_LIMIT & Co.: liegen lassen, nächster Flush versucht es erneut.
	return {"ok": false, "code": error, "queued": not outbox_id.is_empty()}


func _on_status_changed(status: int) -> void:
	if status == NetClient.Status.ONLINE:
		flush()


## Liefert {transport_ok: bool, data: Dictionary} — nie eine Exception.
func _post_redeem(code: String) -> Dictionary:
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
	var body := JSON.stringify({"code": code})
	var url := _base_url() + "/api/codes/redeem"
	if poster.is_valid():
		return _transport(poster.call(url, headers, body))
	if not is_inside_tree():
		return _transport(null)
	var req := HTTPRequest.new()
	add_child(req)
	req.timeout = 10.0
	if req.request(url, headers, HTTPClient.METHOD_POST, body) != OK:
		req.queue_free()
		return _transport(null)
	var result: Array = await req.request_completed
	req.queue_free()
	return _transport(_parse_response(result))


static func _transport(data: Variant) -> Dictionary:
	if data is Dictionary:
		return {"transport_ok": true, "data": data}
	return {"transport_ok": false, "data": {}}


static func _parse_response(result: Array) -> Variant:
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS:
		return null
	var parser := JSON.new()
	if parser.parse((result[3] as PackedByteArray).get_string_from_utf8()) != OK:
		return null
	return parser.data


func _base_url() -> String:
	if not rest_base_url.is_empty():
		return rest_base_url
	var net_config := net._resolve_net_config() if net != null else NetClient.DEFAULT_NET
	var scheme := "https" if net_config.get("tls", false) else "http"
	return "%s://%s:%d" % [scheme, net_config["host"], int(net_config["port"])]
