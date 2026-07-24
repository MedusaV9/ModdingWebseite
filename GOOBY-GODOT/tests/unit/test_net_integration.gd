extends TestCase
## OPTIONALER Integrationstest gegen den ECHTEN GOOBY-SERVER (W2c):
## startet `node server.js` auf einem Zufallsport mit Temp-DATA_DIR und fährt
## HELLO/WELCOME + den kompletten Freunde-Flow (Request → Push → Accept →
## FRIENDS_STATE) über ECHTE WebSocketPeer-Verbindungen. Wird sauber
## GESKIPPT (PASS ohne Asserts), wenn Server oder node fehlen — reine
## Unit-Tests mit FakeWsLink liegen in den übrigen test_net_*-Dateien.

const SERVER_JS := "/workspace/GOOBY-SERVER/server.js"
const ENV_BIN := "/usr/bin/env"


func test_hello_und_freunde_flow_gegen_echten_server() -> void:
	if not FileAccess.file_exists(SERVER_JS):
		print("    SKIP (optional): GOOBY-SERVER/server.js fehlt noch")
		return
	var probe := OS.execute(ENV_BIN, ["node", "--version"])
	if probe != 0:
		print("    SKIP (optional): node nicht auffindbar")
		return

	var port := 20000 + randi() % 9000
	var data_dir := "/tmp/gooby-net-integration-%d" % port
	DirAccess.make_dir_recursive_absolute(data_dir)
	var pid := OS.create_process(
		ENV_BIN, ["PORT=%d" % port, "DATA_DIR=%s" % data_dir, "node", SERVER_JS]
	)
	if pid <= 0:
		print("    SKIP (optional): Server-Prozess startet nicht")
		return

	var up := await _wait_port(port, 20000)
	if not up:
		OS.kill(pid)
		fail_test("Server wurde nicht binnen 20 s erreichbar (Port %d)" % port)
		return

	var alice := _make_client(port, "alice")
	var bob := _make_client(port, "bob")
	var bob_pushes: Array = []
	bob.pushed.connect(
		func(type: String, data: Dictionary) -> void: bob_pushes.append([type, data])
	)
	alice.connect_now()
	bob.connect_now()

	# 1) HELLO → WELCOME: beide online, Server vergibt GOOBY-Codes.
	var both := await wait_until(
		func() -> bool: return alice.is_online() and bob.is_online(), 15000
	)
	assert_true(both, "beide Clients müssen online kommen")
	if both:
		assert_true(
			alice.friend_code.begins_with("GOOBY-"), "echter friendCode: %s" % alice.friend_code
		)
		assert_true(bob.friend_code.begins_with("GOOBY-"))
		assert_ne(alice.friend_code, bob.friend_code)

		# 2) Freunde-Flow: Alice → Request per Code, Bob kriegt den Push.
		var req: Dictionary = await alice.request("FRIEND_REQUEST", {"target": bob.friend_code})
		assert_true(req["ok"], "FRIEND_REQUEST: %s" % str(req))
		var pushed := await wait_until(
			func() -> bool: return _has_push(bob_pushes, "FRIEND_REQUEST_INCOMING"), 8000
		)
		assert_true(pushed, "Bob muss FRIEND_REQUEST_INCOMING sehen")

		# 3) Bob akzeptiert → beidseitig FRIEND_ADDED.
		var acc: Dictionary = await bob.request("FRIEND_ACCEPT", {"target": alice.friend_code})
		assert_true(acc["ok"], "FRIEND_ACCEPT: %s" % str(acc))
		var added := await wait_until(
			func() -> bool: return _has_push(bob_pushes, "FRIEND_ADDED"), 8000
		)
		assert_true(added, "Bob muss FRIEND_ADDED sehen")

		# 4) Alices FRIENDS_STATE enthält Bob.
		var state: Dictionary = await alice.request("FRIENDS_LIST", {})
		assert_true(state["ok"])
		assert_eq(state["t"], "FRIENDS_STATE")
		var rows: Array = (state["d"] as Dictionary).get("friends", [])
		assert_eq(rows.size(), 1, "genau ein Freund")
		if rows.size() == 1:
			assert_eq((rows[0] as Dictionary).get("friendCode"), bob.friend_code)

	# Aufräumen: Clients weg, Server-Prozess killen, Identitäten löschen.
	alice.queue_free()
	bob.queue_free()
	await wait_frames(1)
	OS.kill(pid)
	for who in ["alice", "bob"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_int_%s.json" % who))


func _make_client(port: int, who: String) -> NetClient:
	var client := NetClient.new()
	client.auto_connect = false
	client.build_services = false
	client.identity_path = "user://test_int_%s.json" % who
	client.config_override = {"host": "127.0.0.1", "port": port, "tls": false}
	tree.root.add_child(client)
	return client


func _has_push(pushes: Array, type: String) -> bool:
	for push: Array in pushes:
		if push[0] == type:
			return true
	return false


func _wait_port(port: int, timeout_ms: int) -> bool:
	var deadline := Time.get_ticks_msec() + timeout_ms
	while Time.get_ticks_msec() < deadline:
		var tcp := StreamPeerTCP.new()
		if tcp.connect_to_host("127.0.0.1", port) == OK:
			var settle := Time.get_ticks_msec() + 1000
			while Time.get_ticks_msec() < settle:
				tcp.poll()
				var status := tcp.get_status()
				if status == StreamPeerTCP.STATUS_CONNECTED:
					tcp.disconnect_from_host()
					return true
				if status == StreamPeerTCP.STATUS_ERROR:
					break
				await tree.process_frame
		await tree.process_frame
	return false
