class_name FriendsService
extends Node
## Freunde-Cache + Protokoll-Anbindung (W2c §3): FRIENDS_LIST/FRIENDS_STATE,
## FRIEND_REQUEST (per Code ODER Name), ACCEPT/DECLINE/REMOVE und die
## Push-Typen (FRIEND_ADDED/REMOVED/PRESENCE/REQUEST_INCOMING). Hält
## zusätzlich den Coins-ANZEIGE-Cache-Sync (SYNC alle 5 min bzw. bei
## Änderung > 100 Coins, 60 s debounced — W2c §7). Offline-first: alle
## Aufrufe liefern sofort {ok:false, code:"OFFLINE"} statt zu blockieren.

signal friends_changed(friends: Array)
signal requests_changed(requests: Array)
signal friend_code_changed(code: String)

## W2c §7: SYNC-Kadenz für den Coins-Anzeige-Cache.
const SYNC_INTERVAL_MS := 5 * 60 * 1000
const SYNC_DELTA_THRESHOLD := 100
const SYNC_DEBOUNCE_MS := 60 * 1000

var net: NetClient
var friends: Array[Dictionary] = []
var requests: Array[Dictionary] = []

var _last_sync_ms := -1
var _last_synced_coins := -1


func setup(net_client: NetClient) -> void:
	net = net_client
	net.welcome_received.connect(_on_welcome)
	net.pushed.connect(_on_push)
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_signal("coins_changed"):
		gs.coins_changed.connect(_on_coins_changed)


func my_friend_code() -> String:
	return net.friend_code if net != null else ""


## Freundesliste + offene Requests vom Server ziehen.
func refresh() -> Dictionary:
	var res: Dictionary = await net.request("FRIENDS_LIST", {})
	if res["ok"] and res["t"] == "FRIENDS_STATE":
		_apply_state(res["d"])
	return res


## Anfrage per Freundes-Code ("GOOBY-…") ODER eindeutigem Spielernamen.
func add_friend(code_or_name: String) -> Dictionary:
	var trimmed := code_or_name.strip_edges()
	if trimmed.is_empty():
		return {"ok": false, "code": "BAD_MESSAGE"}
	var payload := {}
	if trimmed.to_upper().begins_with("GOOBY-"):
		payload["target"] = trimmed.to_upper()
	else:
		payload["targetName"] = trimmed
	return await net.request("FRIEND_REQUEST", payload)


func accept(from_code: String) -> Dictionary:
	var res: Dictionary = await net.request("FRIEND_ACCEPT", {"target": from_code})
	if res["ok"]:
		_remove_request(from_code)
	return res


func decline(from_code: String) -> Dictionary:
	var res: Dictionary = await net.request("FRIEND_DECLINE", {"target": from_code})
	if res["ok"]:
		_remove_request(from_code)
	return res


func remove_friend(code: String) -> Dictionary:
	var res: Dictionary = await net.request("FRIEND_REMOVE", {"target": code})
	if res["ok"]:
		_remove_friend_row(code)
	return res


## Coins-Sync-Entscheidung (pur testbar): true == jetzt SYNC senden.
func should_sync_coins(coins: int, now_ms: int) -> bool:
	if _last_sync_ms < 0:
		return true
	if now_ms - _last_sync_ms >= SYNC_INTERVAL_MS:
		return true
	return (
		absi(coins - _last_synced_coins) > SYNC_DELTA_THRESHOLD
		and now_ms - _last_sync_ms >= SYNC_DEBOUNCE_MS
	)


func _on_coins_changed(coins: int) -> void:
	if net == null or not net.is_online():
		return
	var now := Time.get_ticks_msec()
	if should_sync_coins(coins, now):
		net.sync_coins(coins)
		_last_sync_ms = now
		_last_synced_coins = coins


func _on_welcome(data: Dictionary) -> void:
	friend_code_changed.emit(net.friend_code)
	var incoming: Variant = data.get("friendRequests")
	if incoming is Array:
		requests = []
		for row in incoming:
			if row is Dictionary:
				requests.append(row)
		requests_changed.emit(requests)
	refresh()


func _on_push(type: String, data: Dictionary) -> void:
	match type:
		"FRIEND_ADDED":
			_upsert_friend(data)
			friends_changed.emit(friends)
		"FRIEND_REMOVED":
			_remove_friend_row(str(data.get("friendCode", "")))
		"FRIEND_PRESENCE":
			for friend in friends:
				if friend.get("friendCode", "") == data.get("friendCode", ""):
					friend["online"] = data.get("online", false)
					friend["activity"] = data.get("activity", {})
			friends_changed.emit(friends)
		"FRIEND_REQUEST_INCOMING":
			requests.append(data)
			requests_changed.emit(requests)


func _apply_state(data: Dictionary) -> void:
	friends = []
	var rows: Variant = data.get("friends")
	if rows is Array:
		for row in rows:
			if row is Dictionary:
				friends.append(row)
	requests = []
	var reqs: Variant = data.get("requests")
	if reqs is Array:
		for row in reqs:
			if row is Dictionary:
				requests.append(row)
	friends_changed.emit(friends)
	requests_changed.emit(requests)


func _upsert_friend(row: Dictionary) -> void:
	for i in friends.size():
		if friends[i].get("friendCode", "") == row.get("friendCode", ""):
			friends[i] = row
			return
	friends.append(row)


func _remove_friend_row(code: String) -> void:
	for i in friends.size():
		if friends[i].get("friendCode", "") == code:
			friends.remove_at(i)
			break
	friends_changed.emit(friends)


func _remove_request(code: String) -> void:
	for i in requests.size():
		if requests[i].get("from", "") == code:
			requests.remove_at(i)
			break
	requests_changed.emit(requests)
