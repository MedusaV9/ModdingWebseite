extends TestCase
## NetClient gegen den FakeWsLink: HELLO/WELCOME-Handshake (W2c §2),
## re-Korrelation von request() (§1/§7), Offline-first-Verhalten,
## Reconnect nach Abriss, Heartbeat, Push-Signal, Identitäts-Persistenz.


func test_connect_sendet_hello_mit_identitaet() -> void:
	var rig := NetTestRig.boot(tree)
	rig.client.connect_now()
	assert_eq(rig.client.status, NetClient.Status.CONNECTING)
	assert_eq(rig.link().connected_url, "ws://fake.test:1/ws")
	rig.link().open()
	await wait_frames(3)

	var hello := rig.link().last_sent("HELLO")
	assert_eq(int(hello.get("v", -1)), 1, "Envelope v==1")
	assert_eq(int(hello.get("seq", -1)), 1, "HELLO ist seq 1")
	var d: Dictionary = hello.get("d", {})
	assert_true(str(d.get("deviceId", "")).begins_with("gd-"), "deviceId gd-<uuid>")
	assert_eq(str(d.get("deviceSecret", "")).length(), 64, "32 Byte random → 64 hex")
	assert_true(d.has("name") and d.has("goobyName"))
	assert_false(d.has("friendCode"), "allererstes HELLO ohne friendCode")
	await rig.shutdown(tree)


func test_welcome_setzt_online_und_merkt_friend_code() -> void:
	var rig := NetTestRig.boot(tree)
	var statuses: Array[int] = []
	rig.client.status_changed.connect(func(status: int) -> void: statuses.append(status))
	var welcomes: Array[Dictionary] = []
	rig.client.welcome_received.connect(func(data: Dictionary) -> void: welcomes.append(data))

	await rig.go_online(tree, "GOOBY-4K7Q")
	assert_true(rig.client.is_online())
	assert_eq(rig.client.friend_code, "GOOBY-4K7Q")
	assert_eq(statuses, [NetClient.Status.CONNECTING, NetClient.Status.ONLINE])
	assert_eq(welcomes.size(), 1)

	# Reconnect: das nächste HELLO trägt den gemerkten friendCode (Persistenz).
	rig.link().drop()
	await wait_frames(3)
	assert_eq(rig.client.status, NetClient.Status.OFFLINE)
	var reconnected := await wait_until(func() -> bool: return rig.links.size() >= 2, 5000)
	assert_true(reconnected, "Reconnect-Backoff muss einen neuen Link bauen")
	rig.link().open()
	await wait_frames(3)
	var hello2 := rig.link().last_sent("HELLO")
	assert_eq((hello2.get("d", {}) as Dictionary).get("friendCode"), "GOOBY-4K7Q")
	await rig.shutdown(tree)


func test_request_korreliert_antwort_ueber_re() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)

	var results: Array = []
	_collect_request(rig.client, "FRIENDS_LIST", {}, results)
	await wait_frames(1)
	rig.link().respond_to("FRIENDS_LIST", "FRIENDS_STATE", {"friends": [], "requests": []})
	assert_true(await wait_until(func() -> bool: return results.size() == 1, 3000))
	var res: Dictionary = results[0]
	assert_true(res["ok"])
	assert_eq(res["t"], "FRIENDS_STATE")
	assert_true((res["d"] as Dictionary).has("friends"))
	await rig.shutdown(tree)


func test_request_error_liefert_code() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)

	var results: Array = []
	_collect_request(rig.client, "FRIEND_REQUEST", {"target": "GOOBY-NIX"}, results)
	await wait_frames(1)
	rig.link().respond_to("FRIEND_REQUEST", "ERROR", {"code": "NOT_FOUND"})
	assert_true(await wait_until(func() -> bool: return results.size() == 1, 3000))
	var res: Dictionary = results[0]
	assert_false(res["ok"])
	assert_eq(res["code"], "NOT_FOUND")
	await rig.shutdown(tree)


func test_request_offline_kommt_sofort_zurueck() -> void:
	var rig := NetTestRig.boot(tree)
	var before := Time.get_ticks_msec()
	var res: Dictionary = await rig.client.request("FRIENDS_LIST", {})
	assert_false(res["ok"])
	assert_eq(res["code"], "OFFLINE")
	assert_true(Time.get_ticks_msec() - before < 1000, "offline-first: nie blockieren")
	await rig.shutdown(tree)


func test_heartbeat_sendet_ping_nach_intervall() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	assert_eq(rig.client.heartbeat_sec, 20.0, "aus WELCOME übernommen")
	# Weißbox: Intervall aufgelaufen → nächster Tick schickt PING.
	rig.client._heartbeat_accum = rig.client.heartbeat_sec
	await wait_frames(2)
	assert_eq(rig.link().count_sent("PING"), 1)
	await rig.shutdown(tree)


func test_push_ohne_re_feuert_pushed_signal() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var pushes: Array = []
	rig.client.pushed.connect(
		func(type: String, data: Dictionary) -> void: pushes.append([type, data])
	)
	rig.link().push_server(
		{"v": 1, "t": "FRIEND_PRESENCE", "ts": 0, "d": {"friendCode": "GOOBY-X", "online": true}}
	)
	await wait_frames(2)
	assert_eq(pushes.size(), 1)
	assert_eq(pushes[0][0], "FRIEND_PRESENCE")
	assert_eq((pushes[0][1] as Dictionary).get("friendCode"), "GOOBY-X")
	await rig.shutdown(tree)


func test_identitaet_ist_stabil_ueber_neustarts() -> void:
	var rig := NetTestRig.boot(tree)
	var first := rig.client.identity()
	assert_false(str(first["deviceId"]).is_empty())
	rig.client.queue_free()
	await wait_frames(1)

	# „Neustart“: zweiter Client auf derselben Identitäts-Datei.
	var reborn := NetClient.new()
	reborn.auto_connect = false
	reborn.build_services = false
	reborn.identity_path = rig.identity_path
	tree.root.add_child(reborn)
	await wait_frames(1)
	assert_eq(reborn.identity()["deviceId"], first["deviceId"])
	assert_eq(reborn.identity()["deviceSecret"], first["deviceSecret"])
	reborn.queue_free()
	await wait_frames(1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(rig.identity_path))


func test_poll_tick_schlaeft_offline_und_reconnect_bleibt_wach() -> void:
	# Quickwin #15: offline ohne Verbindungswunsch pollt nichts — aber JEDER
	# Reconnect-Pfad (Abriss → _schedule_reconnect) muss den Tick wecken.
	var rig := NetTestRig.boot(tree)
	rig.client.connect_now()
	assert_true(rig.client.is_processing(), "Verbindungswunsch weckt den Poll-Tick")
	rig.client.disconnect_now()
	assert_false(rig.client.is_processing(), "offline ohne Wunsch: Tick schläft")
	await rig.go_online(tree)
	assert_true(rig.client.is_processing(), "online: Tick läuft")
	rig.link().drop()
	await wait_frames(3)
	assert_eq(rig.client.status, NetClient.Status.OFFLINE)
	assert_true(rig.client.is_processing(), "nach Abriss bleibt der Reconnect-Tick wach")
	await rig.shutdown(tree)


func test_uuid4_format() -> void:
	for _i in 20:
		var id := NetClient.uuid4()
		assert_eq(id.length(), 36)
		assert_eq(id[14], "4", "Version-Nibble 4")
		assert_true("89ab".contains(id[19]), "Variant-Bits 10xx")
		var parts := id.split("-")
		assert_eq(parts.size(), 5)


## Fire-and-forget-Wrapper: request() ist eine Coroutine — das Ergebnis landet
## im out-Array (Referenztyp), der Test pollt darauf per wait_until.
func _collect_request(client: NetClient, type: String, data: Dictionary, out: Array) -> void:
	out.append(await client.request(type, data))
