extends TestCase
## GoobyPalService gegen NetClient+FakeWsLink (W3c VISIT): Senden nur online
## + gedeckt, Abzug ERST nach Server-ok (Server = Autorität fürs 250/Tag-
## Limit), deutsche Fehler-Keys, PAL_RECEIVED-Push und die Boot-Gutschrift
## aus WELCOME.palPending (Pull, Sammel-Toast).

const Economy := preload("res://scripts/logic/economy.gd")

const PEER := "GOOBY-PEER"


## GameState-Double: dotted get_value + update(mutator) wie /root/GameState.
class FakeGameState:
	extends RefCounted
	var state: Dictionary = {}

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var node: Variant = state
		for part in path.split("."):
			if node is Dictionary and (node as Dictionary).has(part):
				node = node[part]
			else:
				return fallback
		return node

	func update(mutator: Callable) -> void:
		mutator.call(state)

	func coins() -> int:
		return int((state["economy"] as Dictionary).get("coins", 0))


func test_offline_und_betrags_checks() -> void:
	var rig := NetTestRig.boot(tree)
	var gs := _fresh_state(500)
	var pal := _make_service(rig, gs)

	var off: Dictionary = await pal.send_coins(PEER, 50)
	assert_eq(off["code"], "OFFLINE")
	assert_eq(off["message_key"], "social.pal.err.offline", "Toast-Key DEUTSCH gemappt")

	await rig.go_online(tree)
	var zero: Dictionary = await pal.send_coins(PEER, 0)
	assert_eq(zero["code"], "BAD_AMOUNT")
	var too_much: Dictionary = await pal.send_coins(PEER, pal.daily_limit + 1)
	assert_eq(too_much["code"], "BAD_AMOUNT", "über Tageslimit gar nicht erst senden")

	(gs.state["economy"] as Dictionary)["coins"] = 10
	var broke: Dictionary = await pal.send_coins(PEER, 50)
	assert_eq(broke["code"], "NO_COINS")
	assert_eq(broke["message_key"], "social.pal.err.no_coins")
	assert_eq(rig.link().count_sent("PAL_SEND"), 0, "kein einziger Request ging raus")
	await _cleanup(rig, pal)


func test_senden_zieht_erst_nach_server_ok_ab() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var gs := _fresh_state(500)
	var pal := _make_service(rig, gs)
	var sent_events: Array = []
	pal.sent.connect(
		func(to_code: String, amount: int, today: int) -> void:
			sent_events.append([to_code, amount, today])
	)

	var results: Array = []
	_collect(func() -> Dictionary: return await pal.send_coins(PEER, 100), results)
	await wait_frames(1)
	assert_eq(gs.coins(), 500, "VOR der Antwort keine Buchung")
	rig.link().respond_to("PAL_SEND", "OK", {"ok": true, "sentToday": 100, "dailyLimit": 250})
	assert_true(await wait_until(func() -> bool: return results.size() == 1, 3000))
	assert_true((results[0] as Dictionary)["ok"])
	assert_eq(gs.coins(), 400, "ok:true → 100 Coins abgezogen")
	assert_eq(pal.sent_today, 100)
	assert_eq(pal.remaining_today(), 150)
	assert_eq(sent_events, [[PEER, 100, 100]])
	await _cleanup(rig, pal)


func test_server_lehnt_tageslimit_ab() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var gs := _fresh_state(500)
	var pal := _make_service(rig, gs)

	var results: Array = []
	_collect(func() -> Dictionary: return await pal.send_coins(PEER, 100), results)
	await wait_frames(1)
	rig.link().respond_to("PAL_SEND", "ERROR", {"code": "DAILY_LIMIT"})
	assert_true(await wait_until(func() -> bool: return results.size() == 1, 3000))
	var res: Dictionary = results[0]
	assert_false(res["ok"])
	assert_eq(res["code"], "DAILY_LIMIT")
	assert_eq(res["message_key"], "social.pal.err.daily_limit")
	assert_eq(gs.coins(), 500, "Ablehnung → KEIN Abzug")
	await _cleanup(rig, pal)


func test_pal_received_push_schreibt_gut() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var gs := _fresh_state(100)
	var pal := _make_service(rig, gs)
	var received: Array = []
	pal.received.connect(
		func(from_code: String, amount: int) -> void: received.append([from_code, amount])
	)
	rig.link().push_server(
		{"v": 1, "t": "PAL_RECEIVED", "ts": 0, "d": {"from": PEER, "amount": 75}}
	)
	rig.link().push_server({"v": 1, "t": "PAL_RECEIVED", "ts": 0, "d": {"from": PEER, "amount": 0}})
	await wait_frames(2)
	assert_eq(received, [[PEER, 75]], "amount<=0 wird ignoriert")
	assert_eq(gs.coins(), 175)
	await _cleanup(rig, pal)


func test_boot_gutschrift_aus_welcome_pal_pending() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var gs := _fresh_state(100)
	var pal := _make_service(rig, gs)
	var boots: Array = []
	pal.boot_received.connect(
		func(total: int, entries: Array) -> void: boots.append([total, entries.size()])
	)
	# Server drained pending pro WELCOME → hier als 2. WELCOME (Reconnect).
	(
		rig
		. link()
		. push_server(
			{
				"v": 1,
				"t": "WELCOME",
				"ts": 0,
				"d":
				{
					"friendCode": rig.client.friend_code,
					"heartbeatSec": 20,
					"palPending":
					[
						{"from": PEER, "amount": 30},
						{"from": "GOOBY-DRITT", "amount": 20},
						{"from": "GOOBY-NIX", "amount": 0},
					],
				},
			}
		)
	)
	await wait_frames(2)
	assert_eq(boots, [[50, 2]], "Sammel-Signal: Gesamtsumme + gültige Einträge")
	assert_eq(gs.coins(), 150)
	await _cleanup(rig, pal)


func test_spaetes_setup_zieht_gecachtes_welcome() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	# WELCOME mit palPending kommt VOR dem Service-Setup (Boot-Reihenfolge).
	(
		rig
		. link()
		. push_server(
			{
				"v": 1,
				"t": "WELCOME",
				"ts": 0,
				"d":
				{
					"friendCode": rig.client.friend_code,
					"heartbeatSec": 20,
					"palPending": [{"from": PEER, "amount": 40}],
				},
			}
		)
	)
	await wait_frames(2)
	var gs := _fresh_state(100)
	var pal := _make_service(rig, gs)
	await wait_frames(1)
	assert_eq(gs.coins(), 140, "Cache-Pfad: palPending trotzdem gutgeschrieben")
	await _cleanup(rig, pal)


func test_fetch_history_uebernimmt_zaehler() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var pal := _make_service(rig, _fresh_state(100))

	var results: Array = []
	_collect(func() -> Dictionary: return await pal.fetch_history(), results)
	await wait_frames(1)
	rig.link().respond_to(
		"PAL_HISTORY", "OK", {"entries": [{"to": PEER, "amount": 10}], "sentToday": 10}
	)
	assert_true(await wait_until(func() -> bool: return results.size() == 1, 3000))
	var res: Dictionary = results[0]
	assert_true(res["ok"])
	assert_eq((res["entries"] as Array).size(), 1)
	assert_eq(pal.sent_today, 10)
	assert_eq(pal.remaining_today(), 240)
	await _cleanup(rig, pal)


func test_error_key_mapping() -> void:
	assert_eq(GoobyPalService.error_key("DAILY_LIMIT"), "social.pal.err.daily_limit")
	assert_eq(GoobyPalService.error_key("NOT_FRIENDS"), "social.pal.err.not_friends")
	assert_eq(GoobyPalService.error_key("VOELLIG_NEU"), "social.pal.err.generic")


func _fresh_state(coins: int) -> FakeGameState:
	var gs := FakeGameState.new()
	var econ := Economy.default_slice()
	econ["coins"] = coins
	gs.state = {"economy": econ}
	return gs


func _make_service(rig: NetTestRig, gs: FakeGameState) -> GoobyPalService:
	var pal := GoobyPalService.new()
	tree.root.add_child(pal)
	pal.setup(rig.client, gs)
	return pal


func _collect(coroutine: Callable, out: Array) -> void:
	out.append(await coroutine.call())


func _cleanup(rig: NetTestRig, pal: GoobyPalService) -> void:
	pal.queue_free()
	await rig.shutdown(tree)
