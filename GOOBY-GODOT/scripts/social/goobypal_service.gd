class_name GoobyPalService
extends Node
## GoobyPal (W3c VISIT, W2c §4.1): Coins an Freunde senden — das EINZIGE
## server-autoritative Ökonomie-Feature, deshalb strikt online-only.
## Ablauf Senden: erst PAL_SEND, Coins werden erst bei ok:true lokal
## abgezogen (W2c-Regel). Empfang: PAL_RECEIVED-Push sofort gutschreiben;
## Offline-Gutschriften kommen beim Boot über WELCOME.palPending (Pull) —
## dafür gibt es das Sammel-Signal boot_received für den Empfangs-Toast.

signal sent(to_code: String, amount: int, sent_today: int)
signal received(from_code: String, amount: int)
signal boot_received(total: int, entries: Array)

const Economy := preload("res://scripts/logic/economy.gd")

const DEFAULT_DAILY_LIMIT := 250

## Fehler-Code → deutscher i18n-Key (Toasts, Auftrag: DEUTSCH).
const ERROR_KEYS := {
	"OFFLINE": "social.pal.err.offline",
	"TIMEOUT": "social.pal.err.offline",
	"DAILY_LIMIT": "social.pal.err.daily_limit",
	"BAD_AMOUNT": "social.pal.err.bad_amount",
	"NOT_FRIENDS": "social.pal.err.not_friends",
	"NOT_FOUND": "social.pal.err.not_found",
	"RATE_LIMIT": "social.pal.err.rate_limit",
	"NO_COINS": "social.pal.err.no_coins",
}

var daily_limit := DEFAULT_DAILY_LIMIT
var sent_today := 0

var _net: Node = null
var _gs: Object = null


func setup(net_client: Node, game_state: Object) -> void:
	_net = net_client
	_gs = game_state
	_net.pushed.connect(_on_push)
	_net.welcome_received.connect(_on_welcome)
	# Spätes Setup: WELCOME war ggf. schon da → palPending aus dem Cache
	# ziehen (der Server drained pending pro WELCOME, keine Doppel-Buchung).
	var cached: Variant = _net.get("welcome_data")
	if cached is Dictionary and not (cached as Dictionary).is_empty():
		_on_welcome(cached)


func is_online() -> bool:
	return _net != null and _net.has_method("is_online") and _net.is_online()


static func error_key(code: String) -> String:
	return str(ERROR_KEYS.get(code, "social.pal.err.generic"))


## Coins senden. Deckung wird VOR dem Request geprüft, abgezogen wird erst
## nach ok:true vom Server (Server = Autorität fürs Tageslimit).
func send_coins(to_code: String, amount: int) -> Dictionary:
	if not is_online():
		return _fail("OFFLINE")
	if amount < 1 or amount > daily_limit:
		return _fail("BAD_AMOUNT")
	if not Economy.can_afford(_econ(), amount):
		return _fail("NO_COINS")
	var res: Dictionary = await _net.request("PAL_SEND", {"to": to_code, "amount": amount})
	if not res["ok"]:
		return _fail(str(res["code"]))
	var data: Dictionary = res["d"]
	sent_today = int(data.get("sentToday", sent_today))
	daily_limit = int(data.get("dailyLimit", daily_limit))
	if not bool(data.get("ok", false)):
		return _fail(str(data.get("code", "ERROR")))
	_change_coins(-amount)
	sent.emit(to_code, amount, sent_today)
	return {"ok": true, "sent_today": sent_today, "daily_limit": daily_limit}


## Verlauf + Tageszähler vom Server (fürs Sheet: "heute noch X Coins").
func fetch_history() -> Dictionary:
	if not is_online():
		return _fail("OFFLINE")
	var res: Dictionary = await _net.request("PAL_HISTORY", {})
	if not res["ok"]:
		return _fail(str(res["code"]))
	var data: Dictionary = res["d"]
	sent_today = int(data.get("sentToday", sent_today))
	daily_limit = int(data.get("dailyLimit", daily_limit))
	return {
		"ok": true,
		"entries": data.get("entries", []),
		"sent_today": sent_today,
		"daily_limit": daily_limit,
	}


func remaining_today() -> int:
	return maxi(0, daily_limit - sent_today)


func _fail(code: String) -> Dictionary:
	return {"ok": false, "code": code, "message_key": error_key(code)}


func _on_push(type: String, data: Dictionary) -> void:
	if type != "PAL_RECEIVED":
		return
	var amount := int(data.get("amount", 0))
	if amount <= 0:
		return
	_change_coins(amount)
	received.emit(str(data.get("from", "")), amount)


## WELCOME.palPending: Offline-Gutschriften einlösen (Empfangs-Toast beim
## Boot — Sammel-Signal mit Gesamtsumme).
func _on_welcome(data: Dictionary) -> void:
	var pending: Variant = data.get("palPending", [])
	if not (pending is Array) or (pending as Array).is_empty():
		return
	var total := 0
	var entries: Array = []
	for entry: Variant in pending as Array:
		if entry is Dictionary:
			var amount := int((entry as Dictionary).get("amount", 0))
			if amount > 0:
				total += amount
				entries.append(entry)
	if total <= 0:
		return
	_change_coins(total)
	boot_received.emit(total, entries)


func _econ() -> Dictionary:
	if _gs != null and _gs.has_method("get_value"):
		var econ: Variant = _gs.get_value("economy", {})
		if econ is Dictionary:
			return econ
	return Economy.default_slice()


## Coins über den W1d-Store buchen (update() diff't + feuert coins_changed).
func _change_coins(delta: int) -> void:
	if _gs == null or not _gs.has_method("update"):
		return
	_gs.update(
		func(s: Dictionary) -> void:
			var econ: Dictionary = s.get("economy", {})
			if delta >= 0:
				Economy.award(econ, delta, "goobypal")
			else:
				Economy.spend(econ, -delta, "goobypal")
	)
