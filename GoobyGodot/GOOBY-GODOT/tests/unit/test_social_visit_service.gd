extends TestCase
## VisitService gegen NetClient+FakeWsLink (W3c VISIT): Offline-Degradierung,
## VISIT_READY-Rollen (Host per Antwort, Gast per Push) inkl. ROOM_JOIN,
## POS-Relay (5-Hz-Drossel, force bei Raumwechsel), Empfang von POS/EMOTE/
## BUILD_START/BUILD_DELTA und der saubere Reset bei VISIT_ENDED.

const ROOM := "visit:test-1"
const PEER := "GOOBY-PEER"


func test_offline_alles_degradiert_sofort() -> void:
	var rig := NetTestRig.boot(tree)
	var service := _make_service(rig)
	assert_false(service.is_online())
	var req: Dictionary = await service.request_visit(PEER)
	assert_eq(req["code"], "OFFLINE")
	var acc: Dictionary = await service.accept_visit(PEER)
	assert_eq(acc["code"], "OFFLINE")
	var up: Dictionary = await service.upload_snapshot(null)
	assert_eq(up["code"], "OFFLINE")
	var house: Dictionary = await service.fetch_house(PEER)
	assert_eq(house["code"], "OFFLINE")
	assert_false(service.send_pos(Vector3.ZERO, "idle", "living"), "ohne Session kein POS")
	await _cleanup(rig, service)


func test_visit_ready_push_macht_gast() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var service := _make_service(rig)
	var ready: Array = []
	service.visit_ready.connect(func(data: Dictionary) -> void: ready.append(data))

	await _push_ready(rig, PEER, rig.client.friend_code)
	assert_eq(service.room_id, ROOM)
	assert_eq(service.role, VisitService.ROLE_GUEST, "host!=ich → ich bin Gast")
	assert_eq(service.snapshot_rev, 3)
	assert_eq(ready.size(), 1)
	assert_eq(rig.link().count_sent("ROOM_JOIN"), 1, "Session tritt dem Relay-Room bei")
	assert_eq(rig.link().last_sent("ROOM_JOIN")["d"]["room"], ROOM)
	await _cleanup(rig, service)


func test_accept_visit_antwort_macht_host() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var service := _make_service(rig)

	var results: Array = []
	_collect(func() -> Dictionary: return await service.accept_visit(PEER), results)
	await wait_frames(1)
	rig.link().respond_to(
		"VISIT_ACCEPT",
		"VISIT_READY",
		{"room": ROOM, "host": rig.client.friend_code, "guest": PEER, "rev": 7}
	)
	await wait_frames(2)
	rig.link().respond_to("ROOM_JOIN", "OK", {})
	assert_true(await wait_until(func() -> bool: return results.size() == 1, 3000))
	assert_true((results[0] as Dictionary)["ok"])
	assert_eq(service.role, VisitService.ROLE_HOST)
	assert_eq(service.room_id, ROOM)
	assert_eq(service.snapshot_rev, 7)
	await _cleanup(rig, service)


func test_pos_relay_gedrosselt_und_force() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var service := _make_service(rig)
	await _push_ready(rig, PEER, rig.client.friend_code)

	assert_true(service.send_pos(Vector3(1, 0, 2), "walk", "living"), "1. Send sofort")
	assert_false(service.send_pos(Vector3(1, 0, 2), "walk", "living"), "2. Send < 200 ms")
	assert_true(
		service.send_pos(Vector3(5, 0, 5), "idle", "kitchen", true),
		"force (Raumwechsel) umgeht die Drossel"
	)
	var sent := 0
	for envelope in rig.link().sent:
		if envelope.get("t") == "ROOM_MSG" and envelope["d"].get("kind") == "POS":
			sent += 1
	assert_eq(sent, 2)
	var last: Dictionary = rig.link().last_sent("ROOM_MSG")
	assert_eq(last["d"]["room"], ROOM)
	assert_eq(last["d"]["body"]["roomId"], "kitchen")
	await _cleanup(rig, service)


func test_room_msg_empfang_pos_emote_build() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var service := _make_service(rig)
	await _push_ready(rig, PEER, rig.client.friend_code)

	var positions: Array = []
	var emotes: Array = []
	var warnings: Array = []
	var deltas: Array = []
	service.peer_pos.connect(
		func(pos: Vector3, anim: String, in_room: String) -> void:
			positions.append([pos, anim, in_room])
	)
	service.peer_emote.connect(func(emote_id: String) -> void: emotes.append(emote_id))
	service.build_warning.connect(func() -> void: warnings.append(true))
	service.build_delta_received.connect(func(delta: Dictionary) -> void: deltas.append(delta))

	_push_room_msg(rig, "POS", {"pos": [2.5, 3.5], "anim": "walk", "roomId": "living"})
	_push_room_msg(rig, "EMOTE", {"id": "dance"})
	_push_room_msg(rig, "BUILD_START", {})
	_push_room_msg(rig, "BUILD_DELTA", {"op": "place", "item": "chair", "cell": [1, 1]})
	# Fremder Room wird ignoriert (Guard in _on_push).
	(
		rig
		. link()
		. push_server(
			{
				"v": 1,
				"t": "ROOM_MSG",
				"ts": 0,
				"d": {"room": "visit:andere", "kind": "EMOTE", "body": {"id": "laugh"}},
			}
		)
	)
	await wait_frames(3)

	assert_eq(positions.size(), 1)
	assert_eq(positions[0][0], Vector3(2.5, 0.0, 3.5))
	assert_eq(positions[0][2], "living")
	assert_eq(service.peer_room_id, "living", "POS aktualisiert den Peer-Raum")
	assert_eq(emotes, ["dance"], "EMOTE aus fremdem Room darf NICHT ankommen")
	assert_eq(warnings.size(), 1, "BUILD_START → beidseitige Bau-Warnung")
	assert_eq(deltas.size(), 1)
	assert_eq(deltas[0]["item"], "chair")
	await _cleanup(rig, service)


func test_build_start_warnt_auch_lokal() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var service := _make_service(rig)
	await _push_ready(rig, rig.client.friend_code, PEER)
	var warnings: Array = []
	service.build_warning.connect(func() -> void: warnings.append(true))
	service.send_build_start()
	assert_eq(warnings.size(), 1, "Sender sieht die Warnung ebenfalls (Toast beidseitig)")
	assert_eq(rig.link().last_sent("ROOM_MSG")["d"]["kind"], "BUILD_START")
	service.send_build_delta("living", "place", "chair", Vector2i(2, 3), 1)
	var delta: Dictionary = rig.link().last_sent("ROOM_MSG")["d"]["body"]
	assert_eq(BattleshipLogic.to_cell(delta["cell"]), Vector2i(2, 3))
	assert_eq(delta["roomId"], "living")
	await _cleanup(rig, service)


func test_visit_ended_setzt_zurueck() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var service := _make_service(rig)
	await _push_ready(rig, PEER, rig.client.friend_code)
	assert_true(service.is_active())

	var ended: Array = []
	service.visit_ended.connect(func(data: Dictionary) -> void: ended.append(data))
	rig.link().push_server({"v": 1, "t": "VISIT_ENDED", "ts": 0, "d": {"room": ROOM, "by": PEER}})
	await wait_frames(2)
	assert_eq(ended.size(), 1)
	assert_false(service.is_active(), "Reset: room/role leer")
	assert_eq(service.role, VisitService.ROLE_NONE)
	assert_false(service.send_pos(Vector3.ZERO, "idle", "living"), "kein Relay mehr")
	await _cleanup(rig, service)


func test_peer_joined_uebernimmt_namen() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var service := _make_service(rig)
	await _push_ready(rig, rig.client.friend_code, PEER)
	var joins: Array = []
	service.peer_joined.connect(func(data: Dictionary) -> void: joins.append(data))
	(
		rig
		. link()
		. push_server(
			{
				"v": 1,
				"t": "ROOM_PEER_JOINED",
				"ts": 0,
				"d": {"room": ROOM, "friendCode": PEER, "name": "Mia", "goobyName": "Flauschi"},
			}
		)
	)
	await wait_frames(2)
	assert_eq(joins.size(), 1)
	assert_eq(service.peer_name, "Mia")
	assert_eq(service.peer_gooby_name, "Flauschi")
	await _cleanup(rig, service)


func _make_service(rig: NetTestRig) -> VisitService:
	var service := VisitService.new()
	tree.root.add_child(service)
	service.setup(rig.client)
	return service


## VISIT_READY als Push einspielen + den folgenden ROOM_JOIN beantworten.
func _push_ready(rig: NetTestRig, host: String, guest: String) -> void:
	(
		rig
		. link()
		. push_server(
			{
				"v": 1,
				"t": "VISIT_READY",
				"ts": 0,
				"d": {"room": ROOM, "host": host, "guest": guest, "rev": 3},
			}
		)
	)
	await wait_frames(2)
	rig.link().respond_to("ROOM_JOIN", "OK", {})
	await wait_frames(2)


func _push_room_msg(rig: NetTestRig, kind: String, body: Dictionary) -> void:
	rig.link().push_server(
		{"v": 1, "t": "ROOM_MSG", "ts": 0, "d": {"room": ROOM, "kind": kind, "body": body}}
	)


func _collect(coroutine: Callable, out: Array) -> void:
	out.append(await coroutine.call())


func _cleanup(rig: NetTestRig, service: VisitService) -> void:
	service.queue_free()
	await rig.shutdown(tree)
