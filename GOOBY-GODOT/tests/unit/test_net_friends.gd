extends TestCase
## FriendsService: FRIENDS_STATE-Anwendung, Push-Typen (W2c §3), Code-vs-Name-
## Routing von add_friend, Accept/Decline-Request-Pflege und die reine
## Coins-SYNC-Policy (5 min / >100 Coins mit 60-s-Debounce, W2c §7).


func test_refresh_uebernimmt_friends_state() -> void:
	var rig := NetTestRig.boot(tree)
	var friends := _attach_friends(rig)
	await rig.go_online(tree)
	(
		rig
		. link()
		. respond_to(
			"FRIENDS_LIST",
			"FRIENDS_STATE",
			{
				"friends":
				[
					{
						"friendCode": "GOOBY-9ZML",
						"name": "Lena",
						"goobyName": "Knöpfchen",
						"online": true,
						"activity": {"kind": "park", "label": "ist im Park"},
						"coins": 842,
					}
				],
				"requests": [{"from": "GOOBY-AAAA", "name": "Timo", "goobyName": "Gooby", "at": 1}],
			}
		)
	)
	# go_online() hat via _on_welcome bereits ein refresh() angestoßen — die
	# Antwort oben bedient genau diesen Request.
	var synced := await wait_until(func() -> bool: return friends.friends.size() == 1, 3000)
	assert_true(synced, "FRIENDS_STATE muss den Cache füllen")
	assert_eq(friends.friends[0].get("name"), "Lena")
	assert_eq(friends.requests.size(), 1)
	assert_eq(friends.requests[0].get("from"), "GOOBY-AAAA")
	await rig.shutdown(tree)


func test_add_friend_routet_code_und_name() -> void:
	var rig := NetTestRig.boot(tree)
	var friends := _attach_friends(rig)
	await rig.go_online(tree)

	var results: Array = []
	_collect_add(friends, " gooby-9zml ", results)
	await wait_frames(1)
	var by_code := rig.link().last_sent("FRIEND_REQUEST")
	assert_eq((by_code.get("d", {}) as Dictionary).get("target"), "GOOBY-9ZML", "Code → target")
	rig.link().respond_to("FRIEND_REQUEST", "OK", {})
	assert_true(await wait_until(func() -> bool: return results.size() == 1, 3000))
	assert_true((results[0] as Dictionary)["ok"])

	_collect_add(friends, "Lena", results)
	await wait_frames(1)
	var by_name := rig.link().last_sent("FRIEND_REQUEST")
	assert_eq((by_name.get("d", {}) as Dictionary).get("targetName"), "Lena", "Name → targetName")
	rig.link().respond_to("FRIEND_REQUEST", "OK", {})
	assert_true(await wait_until(func() -> bool: return results.size() == 2, 3000))

	var res_empty: Dictionary = await friends.add_friend("   ")
	assert_false(res_empty["ok"])
	await rig.shutdown(tree)


func test_pushes_pflegen_cache() -> void:
	var rig := NetTestRig.boot(tree)
	var friends := _attach_friends(rig)
	await rig.go_online(tree)

	(
		rig
		. link()
		. push_server(
			{
				"v": 1,
				"t": "FRIEND_ADDED",
				"ts": 0,
				"d":
				{
					"friendCode": "GOOBY-9ZML",
					"name": "Lena",
					"goobyName": "Knöpfchen",
					"online": true
				},
			}
		)
	)
	await wait_frames(2)
	assert_eq(friends.friends.size(), 1)

	(
		rig
		. link()
		. push_server(
			{
				"v": 1,
				"t": "FRIEND_PRESENCE",
				"ts": 0,
				"d":
				{
					"friendCode": "GOOBY-9ZML",
					"online": false,
					"activity": {"kind": "home", "label": "ist zu Hause"},
				},
			}
		)
	)
	await wait_frames(2)
	assert_eq(friends.friends[0].get("online"), false)
	assert_eq((friends.friends[0].get("activity") as Dictionary).get("kind"), "home")

	(
		rig
		. link()
		. push_server(
			{
				"v": 1,
				"t": "FRIEND_REQUEST_INCOMING",
				"ts": 0,
				"d": {"from": "GOOBY-BBBB", "name": "Ali", "goobyName": "Gooby", "at": 2},
			}
		)
	)
	await wait_frames(2)
	assert_eq(friends.requests.size(), 1)

	rig.link().push_server(
		{"v": 1, "t": "FRIEND_REMOVED", "ts": 0, "d": {"friendCode": "GOOBY-9ZML"}}
	)
	await wait_frames(2)
	assert_eq(friends.friends.size(), 0)
	await rig.shutdown(tree)


func test_accept_entfernt_request_aus_liste() -> void:
	var rig := NetTestRig.boot(tree)
	var friends := _attach_friends(rig)
	await rig.go_online(tree)
	(
		rig
		. link()
		. push_server(
			{
				"v": 1,
				"t": "FRIEND_REQUEST_INCOMING",
				"ts": 0,
				"d": {"from": "GOOBY-CCCC", "name": "Mia", "goobyName": "Gooby", "at": 3},
			}
		)
	)
	await wait_frames(2)
	assert_eq(friends.requests.size(), 1)

	var results: Array = []
	_collect_accept(friends, "GOOBY-CCCC", results)
	await wait_frames(1)
	rig.link().respond_to("FRIEND_ACCEPT", "OK", {})
	assert_true(await wait_until(func() -> bool: return results.size() == 1, 3000))
	assert_true((results[0] as Dictionary)["ok"])
	assert_eq(friends.requests.size(), 0, "Accept räumt den Request weg")
	await rig.shutdown(tree)


func test_coins_sync_policy() -> void:
	var rig := NetTestRig.boot(tree)
	var friends := _attach_friends(rig)
	var minute := 60 * 1000

	# Allererster Sync: immer.
	assert_true(friends.should_sync_coins(100, 0))
	friends._last_sync_ms = 0
	friends._last_synced_coins = 100

	# Kleine Änderung kurz danach: nein.
	assert_false(friends.should_sync_coins(150, 30 * 1000))
	# Große Änderung (>100), aber innerhalb der 60-s-Debounce: nein.
	assert_false(friends.should_sync_coins(300, 30 * 1000))
	# Große Änderung nach der Debounce: ja.
	assert_true(friends.should_sync_coins(300, int(1.5 * minute)))
	# Keine große Änderung, aber 5 Minuten um: ja.
	assert_true(friends.should_sync_coins(101, 5 * minute))
	assert_false(friends.should_sync_coins(101, int(4.9 * minute)))
	await rig.shutdown(tree)


func _attach_friends(rig: NetTestRig) -> FriendsService:
	var friends := FriendsService.new()
	rig.client.add_child(friends)
	friends.setup(rig.client)
	return friends


## Fire-and-forget-Wrapper (Coroutinen dürfen nicht zugewiesen werden):
## Ergebnis landet im out-Array, der Test pollt per wait_until.
func _collect_add(friends: FriendsService, code_or_name: String, out: Array) -> void:
	out.append(await friends.add_friend(code_or_name))


func _collect_accept(friends: FriendsService, code: String, out: Array) -> void:
	out.append(await friends.accept(code))
