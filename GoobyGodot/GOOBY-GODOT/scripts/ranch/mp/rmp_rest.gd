class_name RmpRest
extends Node
## REST-Anbindung des Ranch-Multiplayers (RW-6) — hängt als Kind unter dem
## RanchMultiplayerService (`service.rest`): Ranch-Metadaten (Besuch),
## Score-/Bestenlisten- und Geister-Endpunkte. Bearer-Auth über die
## NetClient-Identität, eigener HTTPRequest pro Aufruf mit Timeout
## (Muster VisitService._rest). Offline-first: sofort {ok:false, OFFLINE}.

## Tests/Integration: REST-Ziel {host, port, tls} statt NetClient-Config.
var rest_override: Dictionary = {}

var _service: Node = null


func setup(mp_service: Node) -> void:
	_service = mp_service


## Eigene Ranch-Metadaten hochladen (vor dem Annehmen eines Besuchs).
func upload_ranch_meta(gs: Object) -> Dictionary:
	if not _online():
		return {"ok": false, "code": "OFFLINE"}
	var meta := RmpRanchMeta.build_from_state(gs)
	var verdict := RmpRanchMeta.validate(meta)
	if not verdict["ok"]:
		return {"ok": false, "code": str(verdict["reason"])}
	var res := await _rest(HTTPClient.METHOD_PUT, "/api/ranch", JSON.stringify(meta))
	if res["ok"]:
		return {"ok": true, "rev": int((res["data"] as Dictionary).get("rev", 0))}
	return res


## Ranch eines Freundes abrufen (nur Freunde; geheilt über normalize).
func fetch_ranch_meta(friend_code: String) -> Dictionary:
	if not _online():
		return {"ok": false, "code": "OFFLINE"}
	var res := await _rest(HTTPClient.METHOD_GET, "/api/ranch/%s" % friend_code, "")
	if not res["ok"]:
		return res
	var data: Dictionary = res["data"]
	return {
		"ok": true,
		"rev": int(data.get("rev", 0)),
		"meta": RmpRanchMeta.normalize(data.get("meta")),
	}


## Asynchrone Bestzeit/Bestpunkte melden (Best-Only entscheidet der Server).
func post_score(kurs_id: String, wert: int) -> Dictionary:
	if not _online():
		return {"ok": false, "code": "OFFLINE"}
	var body := {"kurs": kurs_id, "wert": wert}
	if bool(_service.get("dev_session")):
		body["devSession"] = true
	return await _rest(HTTPClient.METHOD_POST, "/api/rmp/score", JSON.stringify(body))


## Freundes-Bestenliste eines Kurses/RW-5-Wettbewerbs.
func fetch_leaderboard(kurs_id: String) -> Dictionary:
	if not _online():
		return {"ok": false, "code": "OFFLINE"}
	var res := await _rest(HTTPClient.METHOD_GET, "/api/rmp/leaderboard/%s" % kurs_id, "")
	if not res["ok"]:
		return res
	var data: Dictionary = res["data"]
	return {
		"ok": true,
		"kurs": str(data.get("kurs", kurs_id)),
		"richtung": str(data.get("richtung", "ab")),
		"me": str(data.get("me", "")),
		"entries": data.get("entries", []) if data.get("entries") is Array else [],
	}


## Geist hochladen: Live-Kurs = {rateHz, samples}; RW-5 = {b64} (G5-Format
## aus RanchCompGhost). Der Server behält nur den besten Lauf + pruned.
func upload_ghost(kurs_id: String, wert: int, payload: Dictionary) -> Dictionary:
	if not _online():
		return {"ok": false, "code": "OFFLINE"}
	if bool(_service.get("dev_session")):
		return {"ok": false, "code": "DEV_SESSION"}
	var body := payload.duplicate()
	body["wert"] = wert
	return await _rest(HTTPClient.METHOD_PUT, "/api/rmp/ghost/%s" % kurs_id, JSON.stringify(body))


func fetch_ghost(kurs_id: String, friend_code: String) -> Dictionary:
	if not _online():
		return {"ok": false, "code": "OFFLINE"}
	var res := await _rest(
		HTTPClient.METHOD_GET, "/api/rmp/ghost/%s/%s" % [kurs_id, friend_code], ""
	)
	if not res["ok"]:
		return res
	return {"ok": true, "ghost": res["data"]}


## ---------------------------------------------------------------- intern


func _online() -> bool:
	return _service != null and _service.has_method("is_online") and _service.is_online()


func _net() -> Node:
	return _service.net() if _service != null and _service.has_method("net") else null


func _rest(method: int, path: String, body: String) -> Dictionary:
	var cfg := _rest_config()
	var scheme := "https" if bool(cfg.get("tls", false)) else "http"
	var url := "%s://%s:%d%s" % [scheme, cfg.get("host", ""), int(cfg.get("port", 443)), path]
	var net := _net()
	var identity: Dictionary = net.identity() if net != null and net.has_method("identity") else {}
	var headers := PackedStringArray(
		[
			(
				"Authorization: Bearer %s:%s"
				% [identity.get("deviceId", ""), identity.get("deviceSecret", "")]
			),
			"Content-Type: application/json",
		]
	)
	var request := HTTPRequest.new()
	add_child(request)
	request.timeout = 10.0
	var err := request.request(url, headers, method, body)
	if err != OK:
		request.queue_free()
		return {"ok": false, "code": "REQUEST_FAILED"}
	var result: Array = await request.request_completed
	request.queue_free()
	if int(result[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "code": "NO_CONNECTION"}
	var parser := JSON.new()
	var text := (result[3] as PackedByteArray).get_string_from_utf8()
	if parser.parse(text) != OK or not (parser.data is Dictionary):
		return {"ok": false, "code": "BAD_RESPONSE"}
	var data: Dictionary = parser.data
	if int(result[1]) >= 400 or not bool(data.get("ok", false)):
		return {"ok": false, "code": str(data.get("code", "HTTP_%d" % int(result[1])))}
	return {"ok": true, "data": data}


func _rest_config() -> Dictionary:
	if not rest_override.is_empty():
		return rest_override
	var net := _net()
	if net != null and net.has_method("_resolve_net_config"):
		return net._resolve_net_config()
	return NetClient.DEFAULT_NET.duplicate(true)
