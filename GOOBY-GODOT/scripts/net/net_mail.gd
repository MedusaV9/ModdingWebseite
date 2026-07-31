class_name NetMail
extends RefCounted
## Post/Mail-Helfer (W13B, Doc C §3.7) ÜBER der bestehenden request/push-API
## von net_client.gd — net_client.gd selbst bleibt unangetastet. Briefe ohne
## Foto reisen per WS (MAIL_SEND), Briefe MIT Foto per REST (POST /api/mail,
## Base64 — 512-KB-Fotos passen nicht in den 16-KB-WS-Frame). OFFLINE-FIRST:
## send_mail legt bei fehlender Verbindung einen persistenten Outbox-Eintrag
## an (kind "mail"); geflusht wird beim nächsten ONLINE-Wechsel. Jeder Brief
## trägt eine clientId — der Server dedupet, ein Timeout-Retry erzeugt also
## nie einen Doppel-Brief. Geschenk-Gutschrift läuft über claim_gift()
## (server-einmalig) — der Aufrufer bucht das Inventar erst nach ok.
## Lebenszyklus: NetMail.attach(net) parkt die Instanz als Meta am Net-Node
## (überlebt Sheet-Schließen, Pushes/Flush laufen weiter) — kein Autoload,
## keine net_client.gd-Änderung nötig.

## Neuer Brief ist da (Push MAIL_NEW; mail = Client-Sicht des Briefs).
signal mail_new(mail: Dictionary)
## Ungelesen-Zähler hat sich geändert (Push/WELCOME/Liste/Ack).
signal unread_changed(unread: int)
## Outbox-Brief wurde ENDGÜLTIG abgewiesen (z. B. NOT_FRIENDS) — der Eintrag
## ist raus; Zuhörer können Geschenk/Porto zurückbuchen (payload.item).
signal mail_bounced(payload: Dictionary, code: String)

const OUTBOX_KIND := "mail"
const TEXT_MAX := 500
const META_KEY := "gooby_mail_service"

## Fehler-Code → i18n-Key (Toasts, DEUTSCH — strings/<locale>/mail.json).
const ERROR_KEYS := {
	"OFFLINE": "mail.err.offline",
	"TIMEOUT": "mail.err.offline",
	"QUEUED": "mail.toast.queued",
	"DAILY_LIMIT": "mail.err.daily_limit",
	"MAILBOX_FULL": "mail.err.mailbox_full",
	"NOT_FRIENDS": "mail.err.not_friends",
	"NOT_FOUND": "mail.err.not_found",
	"SELF": "mail.err.not_found",
	"BAD_MAIL": "mail.err.bad_mail",
	"TEXT_TOO_LONG": "mail.err.text_too_long",
	"BAD_ITEM": "mail.err.generic",
	"BAD_PHOTO": "mail.err.photo_too_large",
	"PHOTO_TOO_LARGE": "mail.err.photo_too_large",
	"ALREADY_CLAIMED": "mail.err.already_claimed",
	"RATE_LIMIT": "mail.err.rate_limit",
}
## Diese Codes lohnen einen späteren Retry — Outbox-Eintrag bleibt liegen.
const RETRYABLE := ["OFFLINE", "TIMEOUT", "DAILY_LIMIT", "MAILBOX_FULL", "RATE_LIMIT"]

var unread := 0
## Tests: poster.call(url, headers, body) -> Dictionary|null (Transportfehler).
var poster: Callable = Callable()
## Tests: getter.call(url, headers) -> Dictionary|null.
var getter: Callable = Callable()
## Basis-URL für REST (Tests/Integration überschreiben; leer = aus WS-Config).
var rest_base_url := ""

var _net: Node = null
var _outbox: NetOutbox = null
var _flush_in_flight := false


## Produktions-Einstieg: EINE Instanz pro Net-Node (als Meta geparkt, damit
## Pushes + Outbox-Flush auch ohne offenes Sheet weiterlaufen).
static func attach(net: Node) -> NetMail:
	if net == null:
		return null
	if net.has_meta(META_KEY) and net.get_meta(META_KEY) is NetMail:
		return net.get_meta(META_KEY)
	var service := NetMail.new()
	var outbox_instance: Variant = net.get("outbox")
	if not (outbox_instance is NetOutbox):
		outbox_instance = NetOutbox.new(str(net.get("outbox_path")))
	service.setup(net, outbox_instance)
	net.set_meta(META_KEY, service)
	return service


func setup(net_client: Node, outbox_instance: NetOutbox) -> void:
	_net = net_client
	_outbox = outbox_instance
	_net.pushed.connect(_on_push)
	_net.welcome_received.connect(_on_welcome)
	_net.status_changed.connect(_on_status_changed)
	var cached: Variant = _net.get("welcome_data")
	if cached is Dictionary and not (cached as Dictionary).is_empty():
		_on_welcome(cached)


func is_online() -> bool:
	return _net != null and _net.has_method("is_online") and _net.is_online()


static func error_key(code: String) -> String:
	return str(ERROR_KEYS.get(code, "mail.err.generic"))


func outbox_count() -> int:
	return _outbox.entries(OUTBOX_KIND).size() if _outbox != null else 0


## Brief senden. Offline/Transportfehler → persistenter Outbox-Eintrag
## ({ok:false, code:"QUEUED", queued:true} zählt für die UI als „unterwegs“).
## item = {} (kein Geschenk) oder {typ:"food"|"items", id, menge}.
func send_mail(to: String, text: String, photo_path := "", item: Dictionary = {}) -> Dictionary:
	var payload := {
		"to": to,
		"text": text,
		"fotoPfad": photo_path,
		"item": item.duplicate(true),
		"clientId": NetClient.uuid4(),
	}
	if not is_online():
		_enqueue(payload)
		return _queued()
	var res := await _send_now(payload)
	var code := str(res.get("code", ""))
	if code == "OFFLINE" or code == "TIMEOUT":
		# Transportfehler → Outbox; die clientId macht den späteren Retry
		# idempotent (kein Doppel-Brief nach Timeout).
		_enqueue(payload)
		return _queued()
	return res


## Postfach holen (Server sortiert: ungelesen zuerst, dann jüngste zuerst).
func fetch_inbox(offset := 0, limit := 20) -> Dictionary:
	if not is_online():
		return _fail("OFFLINE")
	var res: Dictionary = await _net.request("MAIL_LIST", {"offset": offset, "limit": limit})
	if not bool(res["ok"]):
		return _fail(str(res["code"]))
	var data: Dictionary = res["d"]
	_set_unread(int(data.get("unread", unread)))
	return {
		"ok": true,
		"mails": data.get("mails", []),
		"total": int(data.get("total", 0)),
		"unread": unread,
	}


## Brief als gelesen bestätigen (server-idempotent).
func ack(mail_id: String) -> Dictionary:
	if not is_online():
		return _fail("OFFLINE")
	var res: Dictionary = await _net.request("MAIL_ACK", {"id": mail_id})
	if not bool(res["ok"]):
		return _fail(str(res["code"]))
	_set_unread(int((res["d"] as Dictionary).get("unread", unread)))
	return {"ok": true, "unread": unread}


## Geschenk annehmen — der Server gibt es genau EINMAL heraus; das Inventar
## bucht der Aufrufer erst nach ok:true (keine Doppel-Gutschrift möglich).
func claim_gift(mail_id: String) -> Dictionary:
	if not is_online():
		return _fail("OFFLINE")
	var res: Dictionary = await _net.request("MAIL_CLAIM", {"id": mail_id})
	if not bool(res["ok"]):
		return _fail(str(res["code"]))
	var item: Variant = (res["d"] as Dictionary).get("item", {})
	return {"ok": true, "item": item if item is Dictionary else {}}


## Brief löschen (Server putzt einen Foto-Blob mit).
func delete_mail(mail_id: String) -> Dictionary:
	if not is_online():
		return _fail("OFFLINE")
	var res: Dictionary = await _net.request("MAIL_DELETE", {"id": mail_id})
	if not bool(res["ok"]):
		return _fail(str(res["code"]))
	var data: Dictionary = res["d"]
	_set_unread(int(data.get("unread", unread)))
	return {"ok": true, "removed": bool(data.get("removed", false))}


## Foto eines Briefs lazy nachladen (REST) → {ok, photo_b64}.
func fetch_photo(photo_id: String) -> Dictionary:
	if photo_id.is_empty():
		return _fail("NOT_FOUND")
	var data: Variant = await _http_get("/api/mail/blob/%s" % photo_id)
	if not (data is Dictionary):
		return _fail("OFFLINE")
	if not bool((data as Dictionary).get("ok", false)):
		return _fail(str((data as Dictionary).get("code", "NOT_FOUND")))
	return {"ok": true, "photo_b64": str((data as Dictionary).get("photoB64", ""))}


## Alle gepufferten Briefe zustellen (Reconnect-Flush, Muster RedeemService).
## Endgültige Ablehnungen fliegen raus und feuern mail_bounced (Geschenk-
## Rückbuchung ist Sache des Zuhörers); Transport-/Quota-Fehler bleiben liegen.
func flush() -> void:
	if _outbox == null or _flush_in_flight:
		return
	_flush_in_flight = true
	for entry in _outbox.entries(OUTBOX_KIND):
		if not is_online():
			break
		var payload: Dictionary = entry["payload"]
		var res := await _send_now(payload)
		if bool(res.get("ok", false)):
			_outbox.remove(str(entry["id"]))
			continue
		var code := str(res.get("code", ""))
		if RETRYABLE.has(code):
			break
		_outbox.remove(str(entry["id"]))
		mail_bounced.emit(payload, code)
	_flush_in_flight = false


func _queued() -> Dictionary:
	return {"ok": false, "code": "QUEUED", "queued": true, "message_key": "mail.toast.queued"}


func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code, "queued": false, "message_key": error_key(code)}


func _enqueue(payload: Dictionary) -> void:
	if _outbox == null:
		return
	# upsert über die clientId: ein Retry-Pfad erzeugt keinen zweiten Eintrag.
	_outbox.upsert(OUTBOX_KIND, "mail:%s" % str(payload.get("clientId", "")), payload)


## Einen Brief JETZT zustellen: ohne Foto per WS, mit Foto per REST.
func _send_now(payload: Dictionary) -> Dictionary:
	var data := {
		"to": str(payload.get("to", "")),
		"text": str(payload.get("text", "")),
		"clientId": str(payload.get("clientId", "")),
	}
	var item: Variant = payload.get("item", {})
	if item is Dictionary and not (item as Dictionary).is_empty():
		data["item"] = item
	var photo_b64 := _encode_photo(str(payload.get("fotoPfad", "")))
	if photo_b64.is_empty():
		var res: Dictionary = await _net.request("MAIL_SEND", data)
		if not bool(res["ok"]):
			return _fail(str(res["code"]))
		return _apply_send_result(res["d"])
	data["photoB64"] = photo_b64
	var response: Variant = await _http_post("/api/mail", data)
	if not (response is Dictionary):
		return _fail("OFFLINE")
	return _apply_send_result(response)


func _apply_send_result(data: Dictionary) -> Dictionary:
	if not bool(data.get("ok", false)):
		return _fail(str(data.get("code", "ERROR")))
	return {
		"ok": true,
		"id": str(data.get("id", "")),
		"dupe": bool(data.get("dupe", false)),
		"sent_today": int(data.get("sentToday", 0)),
		"daily_limit": int(data.get("dailyLimit", 0)),
	}


## Foto-Datei → Base64 ("" = kein/fehlendes Foto: der Brief geht dann als
## reiner Text raus — besser zustellen als in der Outbox verhungern).
func _encode_photo(path: String) -> String:
	if path.is_empty() or not FileAccess.file_exists(path):
		return ""
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return ""
	return Marshalls.raw_to_base64(bytes)


func _on_push(type: String, data: Dictionary) -> void:
	if type != "MAIL_NEW":
		return
	_set_unread(int(data.get("unread", unread + 1)))
	var mail: Variant = data.get("mail", {})
	if mail is Dictionary:
		mail_new.emit(mail)


func _on_welcome(data: Dictionary) -> void:
	if data.has("mailUnread"):
		_set_unread(int(data.get("mailUnread", 0)))


func _on_status_changed(status: int) -> void:
	if status == NetClient.Status.ONLINE:
		flush()


func _set_unread(value: int) -> void:
	var clean := maxi(0, value)
	if clean == unread:
		return
	unread = clean
	unread_changed.emit(unread)


# ---- REST-Transport (injizierbar; Default HTTPRequest am Net-Node) ----


func _http_post(path: String, body: Dictionary) -> Variant:
	var headers := _auth_headers()
	var url := _base_url() + path
	if poster.is_valid():
		return poster.call(url, headers, JSON.stringify(body))
	return await _http_request(url, headers, HTTPClient.METHOD_POST, JSON.stringify(body))


func _http_get(path: String) -> Variant:
	var headers := _auth_headers()
	var url := _base_url() + path
	if getter.is_valid():
		return getter.call(url, headers)
	return await _http_request(url, headers, HTTPClient.METHOD_GET, "")


func _http_request(url: String, headers: PackedStringArray, method: int, body: String) -> Variant:
	if _net == null or not _net.is_inside_tree():
		return null
	var req := HTTPRequest.new()
	_net.add_child(req)
	req.timeout = 15.0
	if req.request(url, headers, method, body) != OK:
		req.queue_free()
		return null
	var result: Array = await req.request_completed
	req.queue_free()
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS:
		return null
	var parser := JSON.new()
	if parser.parse((result[3] as PackedByteArray).get_string_from_utf8()) != OK:
		return null
	return parser.data


func _auth_headers() -> PackedStringArray:
	var identity: Dictionary = _net.identity() if _net != null else {}
	return PackedStringArray(
		[
			"Content-Type: application/json",
			(
				"Authorization: Bearer %s:%s"
				% [identity.get("deviceId", ""), identity.get("deviceSecret", "")]
			),
		]
	)


func _base_url() -> String:
	if not rest_base_url.is_empty():
		return rest_base_url
	var net_config: Dictionary = (
		_net._resolve_net_config() if _net != null else NetClient.DEFAULT_NET
	)
	var scheme := "https" if net_config.get("tls", false) else "http"
	return "%s://%s:%d" % [scheme, net_config["host"], int(net_config["port"])]
