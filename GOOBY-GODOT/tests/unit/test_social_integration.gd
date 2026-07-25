extends TestCase
## OPTIONALER Integrationstest gegen den ECHTEN GOOBY-SERVER (W3c VISIT,
## Muster W2d test_net_integration.gd): startet `node server.js` auf einem
## Zufallsport mit Temp-DATA_DIR und fährt den kompletten Social-Stack mit
## ZWEI echten Clients:
##   1. Besuch: Snapshot-Upload (PUT /api/house) + Abruf, VISIT_REQUEST →
##      INCOMING → ACCEPT → READY, POS-Relay, Bau-Warnung, VISIT_END.
##   2. Schiffe versenken: Vollpartie mit deterministischen Flotten bis zum
##      Sieg (Turn-Relay SHOT/SHOT_RESULT), Tomate: 2. Wurf/Runde wird vom
##      SERVER abgelehnt (TOMATO_LIMIT), Emote-Relay.
##   3. GoobyPal: Transfer + PAL_RECEIVED, Tageslimit 250 greift serverseitig.
## Wird sauber GESKIPPT (PASS ohne Asserts), wenn Server oder node fehlen.

const StateUtil := preload("res://tests/fixtures/state_test_util.gd")

const SERVER_JS := "/workspace/GOOBY-SERVER/server.js"
const ENV_BIN := "/usr/bin/env"


## GameState-Double (dotted get_value + update) für Snapshot & GoobyPal.
class IntState:
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
		return int((state.get("economy", {}) as Dictionary).get("coins", 0))


func test_social_stack_gegen_echten_server() -> void:
	if not FileAccess.file_exists(SERVER_JS):
		print("    SKIP (optional): GOOBY-SERVER/server.js fehlt noch")
		return
	if OS.execute(ENV_BIN, ["node", "--version"]) != 0:
		print("    SKIP (optional): node nicht auffindbar")
		return

	var port := 21000 + randi() % 9000
	var data_dir := "/tmp/gooby-w3c-integration-%d" % port
	DirAccess.make_dir_recursive_absolute(data_dir)
	var pid := OS.create_process(
		ENV_BIN, ["PORT=%d" % port, "DATA_DIR=%s" % data_dir, "node", SERVER_JS]
	)
	if pid <= 0:
		print("    SKIP (optional): Server-Prozess startet nicht")
		return
	if not await _wait_port(port, 20000):
		OS.kill(pid)
		fail_test("Server wurde nicht binnen 20 s erreichbar (Port %d)" % port)
		return

	var alice := _make_client(port, "w3c_alice")
	var bob := _make_client(port, "w3c_bob")
	alice.connect_now()
	bob.connect_now()
	var both := await wait_until(
		func() -> bool: return alice.is_online() and bob.is_online(), 15000
	)
	assert_true(both, "beide Clients müssen online kommen")
	if both:
		# Freundschaft ist Voraussetzung für Visit/Board/Pal.
		var req: Dictionary = await alice.request("FRIEND_REQUEST", {"target": bob.friend_code})
		assert_true(req["ok"], "FRIEND_REQUEST: %s" % str(req))
		var acc: Dictionary = await bob.request("FRIEND_ACCEPT", {"target": alice.friend_code})
		assert_true(acc["ok"], "FRIEND_ACCEPT: %s" % str(acc))
		print("[W3C-INT] Freunde: %s <-> %s" % [alice.friend_code, bob.friend_code])

		await _teil1_besuch(port, alice, bob)
		await _teil2_battleship(alice, bob)
		await _teil3_goobypal(alice, bob)

	alice.queue_free()
	bob.queue_free()
	await wait_frames(1)
	OS.kill(pid)
	for who in ["w3c_alice", "w3c_bob"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_int_%s.json" % who))


## ---- Teil 1: Besuch (Snapshot-REST + Lifecycle + POS-Relay) ----
func _teil1_besuch(port: int, alice: NetClient, bob: NetClient) -> void:
	var host_service := VisitService.new()
	var guest_service := VisitService.new()
	tree.root.add_child(host_service)
	tree.root.add_child(guest_service)
	host_service.setup(alice)
	guest_service.setup(bob)
	var rest := {"host": "127.0.0.1", "port": port, "tls": false}
	host_service.rest_override = rest
	guest_service.rest_override = rest

	var gs := IntState.new()
	gs.state = {
		"meta": {"goobyNickname": "AliceGooby"},
		"home":
		{
			"rooms":
			{
				"living": {"items": [{"uid": "c1", "item": "chair", "at": [5, 5], "rot": 0}]},
				"bedroom": {"items": []},
			}
		},
	}

	# 1) Haus hochladen (PUT /api/house) → rev 1.
	var up: Dictionary = await host_service.upload_snapshot(gs)
	assert_true(up["ok"], "Snapshot-Upload: %s" % str(up))
	assert_eq(int(up.get("rev", 0)), 1, "erste rev")
	print("[W3C-INT] Besuch: Snapshot hochgeladen (rev %s)" % str(up.get("rev")))

	# 2) Abruf durch den Freund — Layout kommt verlustfrei zurück.
	var house: Dictionary = await guest_service.fetch_house(alice.friend_code)
	assert_true(house["ok"], "fetch_house: %s" % str(house))
	var uploaded := VisitSnapshot.build_from_state(gs)
	assert_true(
		StateUtil.deep_equal(uploaded, house["snapshot"]),
		"Snapshot-Roundtrip: %s" % StateUtil.first_diff(uploaded, house["snapshot"])
	)

	# 3) VISIT_REQUEST → VISIT_INCOMING beim Host → ACCEPT → beidseitig READY.
	var incoming: Array = []
	host_service.visit_incoming.connect(func(data: Dictionary) -> void: incoming.append(data))
	var vreq: Dictionary = await guest_service.request_visit(alice.friend_code)
	assert_true(vreq["ok"], "VISIT_REQUEST: %s" % str(vreq))
	assert_true(
		await wait_until(func() -> bool: return incoming.size() == 1, 8000),
		"Host muss VISIT_INCOMING sehen"
	)
	if incoming.size() == 1:
		assert_eq((incoming[0] as Dictionary).get("from"), bob.friend_code)
	var vacc: Dictionary = await host_service.accept_visit(bob.friend_code)
	assert_true(vacc["ok"], "VISIT_ACCEPT: %s" % str(vacc))
	var joined := await wait_until(
		func() -> bool: return host_service.is_active() and guest_service.is_active(), 8000
	)
	assert_true(joined, "beide Sessions aktiv (Room beigetreten)")
	assert_eq(host_service.role, VisitService.ROLE_HOST)
	assert_eq(guest_service.role, VisitService.ROLE_GUEST)
	assert_eq(host_service.snapshot_rev, 1, "READY trägt die Haus-rev")
	print("[W3C-INT] Besuch: READY, Room %s" % host_service.room_id)

	# 4) POS-Relay Gast → Host (5 Hz; bis der Peer im Room angekommen ist).
	var positions: Array = []
	host_service.peer_pos.connect(
		func(pos: Vector3, anim: String, in_room: String) -> void:
			positions.append([pos, anim, in_room])
	)
	for _attempt in 40:
		guest_service.send_pos(Vector3(3.25, 0, 4.5), "walk", "living", true)
		await wait_frames(6)
		if not positions.is_empty():
			break
	assert_true(positions.size() >= 1, "Host muss POS vom Gast empfangen")
	if positions.size() >= 1:
		assert_eq(positions[0][0], Vector3(3.25, 0.0, 4.5))
		assert_eq(positions[0][2], "living")
		assert_eq(host_service.peer_room_id, "living")
	print("[W3C-INT] Besuch: POS-Relay ok (%d empfangen)" % positions.size())

	# 5) Bau-Warnung Host → Gast (Toast beidseitig; Bauen bleibt erlaubt).
	var warned: Array = []
	guest_service.build_warning.connect(func() -> void: warned.append(true))
	host_service.send_build_start()
	assert_true(
		await wait_until(func() -> bool: return warned.size() == 1, 8000),
		"Gast muss die Bau-Warnung sehen"
	)

	# 6) Sauber beenden: beidseitig VISIT_ENDED + Reset.
	var vend: Dictionary = await guest_service.end_visit()
	assert_true(vend["ok"], "VISIT_END: %s" % str(vend))
	var ended := await wait_until(
		func() -> bool: return not host_service.is_active() and not guest_service.is_active(), 8000
	)
	assert_true(ended, "beide Seiten sauber zurückgesetzt")
	print("[W3C-INT] Besuch: sauber beendet")

	host_service.queue_free()
	guest_service.queue_free()
	await wait_frames(1)


## ---- Teil 2: Schiffe versenken — Vollpartie bis zum Sieg + Tomate ----
func _teil2_battleship(alice: NetClient, bob: NetClient) -> void:
	var host := BoardSession.new()
	var guest := BoardSession.new()
	tree.root.add_child(host)
	tree.root.add_child(guest)
	host.setup(alice)
	guest.setup(bob)

	var invites: Array = []
	guest.invite_incoming.connect(func(data: Dictionary) -> void: invites.append(data))
	var inv: Dictionary = await host.invite(bob.friend_code)
	assert_true(inv["ok"], "BOARD_INVITE: %s" % str(inv))
	assert_true(
		await wait_until(func() -> bool: return invites.size() == 1, 8000),
		"Gast muss BOARD_INVITED sehen"
	)
	var acc: Dictionary = await guest.accept(alice.friend_code)
	assert_true(acc["ok"], "BOARD_ACCEPT: %s" % str(acc))
	var started := await wait_until(
		func() -> bool: return host.is_active() and guest.is_active(), 8000
	)
	assert_true(started, "beide Sessions im board:-Room")
	assert_eq(host.seed_value, guest.seed_value, "gleicher Server-Seed")
	assert_true(host.my_turn(), "der Einladende beginnt (first)")

	# Deterministische Flotten: jeder kann BEIDE Flotten reproduzieren.
	assert_true(host.set_fleet(host.default_fleet()))
	assert_true(guest.set_fleet(guest.default_fleet()))
	var bob_fleet := BattleshipLogic.auto_fleet(
		BoardSession.fleet_seed(host.seed_value, bob.friend_code)
	)
	var alice_fleet := BattleshipLogic.auto_fleet(
		BoardSession.fleet_seed(host.seed_value, alice.friend_code)
	)
	var targets: Array[Vector2i] = []
	for ship in bob_fleet:
		targets.append_array(BattleshipLogic.ship_cells(ship))
	var alice_cells: Dictionary = {}
	for ship in alice_fleet:
		for cell in BattleshipLogic.ship_cells(ship):
			alice_cells[cell] = true
	var water: Array[Vector2i] = []
	for x in BattleshipLogic.GRID:
		for y in BattleshipLogic.GRID:
			if not alice_cells.has(Vector2i(x, y)) and water.size() < targets.size():
				water.append(Vector2i(x, y))
	print(
		(
			"[W3C-INT] Battleship: Seed %d, Alice jagt %d Zellen, Bob schießt Wasser"
			% [host.seed_value, targets.size()]
		)
	)

	# Tomate in Runde 0: 1. Wurf ok, 2. lokal geblockt, roher 2. Wurf wird
	# vom SERVER abgelehnt (TOMATO_LIMIT — Beweis fürs Server-Enforcement).
	var tomato_hits: Array = []
	guest.tomato_incoming.connect(func() -> void: tomato_hits.append(true))
	var server_errors: Array = []
	alice.message_received.connect(
		func(envelope: Dictionary) -> void:
			if str(envelope.get("t", "")) == "ERROR":
				server_errors.append(str((envelope.get("d", {}) as Dictionary).get("code", "")))
	)
	assert_true(host.throw_tomato(), "1. Tomate der Runde fliegt")
	assert_false(host.throw_tomato(), "Client-Spiegel blockt die 2.")
	alice.send("ROOM_MSG", {"room": host.room_id, "kind": "TOMATO", "body": {}})
	assert_true(
		await wait_until(func() -> bool: return server_errors.has("TOMATO_LIMIT"), 8000),
		"Server muss den 2. Wurf mit TOMATO_LIMIT ablehnen (gesehen: %s)" % str(server_errors)
	)
	assert_true(
		await wait_until(func() -> bool: return tomato_hits.size() == 1, 8000),
		"Gegner sieht GENAU eine Tomate"
	)
	print("[W3C-INT] Battleship: Tomaten-Limit greift serverseitig (TOMATO_LIMIT)")

	# Emote-Relay einmal quer.
	var emotes: Array = []
	host.opponent_emote.connect(func(emote_id: String) -> void: emotes.append(emote_id))
	assert_true(guest.send_emote("laugh"))
	assert_true(
		await wait_until(func() -> bool: return emotes == ["laugh"], 8000), "Emote kommt an"
	)

	# Vollpartie: Alice versenkt alles, Bob trifft nur Wasser.
	var overs_host: Array = []
	var overs_guest: Array = []
	host.game_over.connect(
		func(winner_code: String, i_won: bool) -> void: overs_host.append([winner_code, i_won])
	)
	guest.game_over.connect(
		func(winner_code: String, i_won: bool) -> void: overs_guest.append([winner_code, i_won])
	)
	var target_index := 0
	var water_index := 0
	var deadline := Time.get_ticks_msec() + 60000
	while not host.finished and Time.get_ticks_msec() < deadline:
		if host.my_turn() and target_index < targets.size():
			assert_true(host.shoot(targets[target_index]), "Alice-Schuss %d" % target_index)
			target_index += 1
		elif guest.my_turn() and not guest.finished and water_index < water.size():
			assert_true(guest.shoot(water[water_index]), "Bob-Schuss %d" % water_index)
			water_index += 1
		await wait_frames(1)
	assert_true(host.finished, "Partie muss binnen 60 s durch sein")
	assert_eq(overs_host, [[alice.friend_code, true]], "Alice gewinnt")
	var guest_over := await wait_until(func() -> bool: return overs_guest.size() == 1, 8000)
	assert_true(guest_over, "auch Bob sieht GAME_OVER")
	if guest_over:
		assert_eq(overs_guest, [[alice.friend_code, false]])
	assert_eq(target_index, targets.size(), "alle 17 Flottenzellen wurden gebraucht")
	print(
		(
			"[W3C-INT] Battleship: VOLLPARTIE fertig — Sieger %s nach %d Treffern, %d Bob-Schüssen"
			% [alice.friend_code, target_index, water_index]
		)
	)

	await host.leave()
	await guest.leave()
	host.queue_free()
	guest.queue_free()
	await wait_frames(1)


## ---- Teil 3: GoobyPal — Transfer + Tageslimit (Server-autoritativ) ----
func _teil3_goobypal(alice: NetClient, bob: NetClient) -> void:
	var sender_state := IntState.new()
	sender_state.state = {"economy": {"coins": 500, "coinsEarned": 0}}
	var receiver_state := IntState.new()
	receiver_state.state = {"economy": {"coins": 100, "coinsEarned": 0}}
	var sender := GoobyPalService.new()
	var receiver := GoobyPalService.new()
	tree.root.add_child(sender)
	tree.root.add_child(receiver)
	sender.setup(alice, sender_state)
	receiver.setup(bob, receiver_state)

	var received: Array = []
	receiver.received.connect(
		func(from_code: String, amount: int) -> void: received.append([from_code, amount])
	)

	var ok_send: Dictionary = await sender.send_coins(bob.friend_code, 100)
	assert_true(ok_send["ok"], "PAL_SEND 100: %s" % str(ok_send))
	assert_eq(sender_state.coins(), 400, "Abzug nach Server-ok")
	assert_eq(int(ok_send["sent_today"]), 100)
	assert_true(
		await wait_until(func() -> bool: return received.size() == 1, 8000),
		"Empfänger muss PAL_RECEIVED sehen"
	)
	assert_eq(received[0], [alice.friend_code, 100])
	assert_eq(receiver_state.coins(), 200, "Gutschrift beim Empfänger")

	var over_limit: Dictionary = await sender.send_coins(bob.friend_code, 200)
	assert_false(over_limit["ok"], "100+200 > 250 muss scheitern")
	assert_eq(over_limit["code"], "DAILY_LIMIT")
	assert_eq(over_limit["message_key"], "social.pal.err.daily_limit")
	assert_eq(sender_state.coins(), 400, "kein Abzug bei Ablehnung")
	print(
		(
			"[W3C-INT] GoobyPal: 100 Coins übertragen, 200 weitere → DAILY_LIMIT (heute: %d/%d)"
			% [sender.sent_today, sender.daily_limit]
		)
	)

	sender.queue_free()
	receiver.queue_free()
	await wait_frames(1)


func _make_client(port: int, who: String) -> NetClient:
	var client := NetClient.new()
	client.auto_connect = false
	client.build_services = false
	client.identity_path = "user://test_int_%s.json" % who
	client.config_override = {"host": "127.0.0.1", "port": port, "tls": false}
	tree.root.add_child(client)
	return client


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
