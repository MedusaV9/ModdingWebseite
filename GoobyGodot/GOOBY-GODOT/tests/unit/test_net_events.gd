extends TestCase
## ServerEventsService (E14 P1-4): WELCOME.pendingEvents + Live-SERVER_EVENT
## werden konsumiert, JEDE Zustellung wird per EVENT_ACK bestätigt (der
## Server markiert deliveredTo erst nach dem Ack) und über die persistierte
## Event-Id-Liste dedupet — Mehrfach-Zustellung ist harmlos.


func test_welcome_pending_events_werden_konsumiert_und_geackt() -> void:
	var setup := await _boot()
	var rig: NetTestRig = setup["rig"]
	var received: Array = setup["received"]

	await _go_online_with_events(
		rig,
		[
			{"id": "evt-1", "type": "DOUBLE_COINS", "params": {"name": "Doppel-Coins"}},
			{"id": "evt-2", "type": "WEATHER_RAIN", "params": {}},
		]
	)
	assert_eq(received.size(), 2, "beide Pull-Events kommen an")
	assert_eq(received[0], ["evt-1", "DOUBLE_COINS", {"name": "Doppel-Coins"}])
	assert_eq(rig.link().count_sent("EVENT_ACK"), 2, "jede Zustellung wird geackt")
	assert_eq((rig.link().last_sent("EVENT_ACK").get("d", {}) as Dictionary).get("id"), "evt-2")
	await _teardown(setup)


func test_live_push_kommt_an_und_wird_geackt() -> void:
	var setup := await _boot()
	var rig: NetTestRig = setup["rig"]
	var received: Array = setup["received"]
	await rig.go_online(tree)

	(
		rig
		. link()
		. push_server(
			{
				"v": 1,
				"t": "SERVER_EVENT",
				"ts": 0,
				"d": {"id": "evt-live", "type": "ANNOUNCEMENT", "params": {"text": "Hallo"}},
			}
		)
	)
	await wait_frames(2)
	assert_eq(received.size(), 1)
	assert_eq(received[0], ["evt-live", "ANNOUNCEMENT", {"text": "Hallo"}])
	assert_eq(rig.link().count_sent("EVENT_ACK"), 1)
	await _teardown(setup)


func test_doppelte_zustellung_wird_dedupet_aber_erneut_geackt() -> void:
	# Ack ging verloren → der Server stellt beim nächsten WELCOME erneut zu:
	# kein zweites event_received, aber ein weiteres Ack (bis der Server ruht).
	var setup := await _boot()
	var rig: NetTestRig = setup["rig"]
	var received: Array = setup["received"]

	await _go_online_with_events(rig, [{"id": "evt-x", "type": "DOUBLE_COINS", "params": {}}])
	assert_eq(received.size(), 1)
	rig.link().push_server(
		{"v": 1, "t": "SERVER_EVENT", "ts": 0, "d": {"id": "evt-x", "type": "DOUBLE_COINS"}}
	)
	await wait_frames(2)
	assert_eq(received.size(), 1, "Duplikat löst KEINE zweite Wirkung aus")
	assert_eq(rig.link().count_sent("EVENT_ACK"), 2, "Duplikat wird trotzdem geackt")
	await _teardown(setup)


func test_seen_liste_ueberlebt_neustart() -> void:
	var setup := await _boot()
	var rig: NetTestRig = setup["rig"]
	var received: Array = setup["received"]
	var seen_path: String = setup["seen_path"]

	await _go_online_with_events(rig, [{"id": "evt-p", "type": "DOUBLE_COINS", "params": {}}])
	assert_eq(received.size(), 1)

	# "Neustart": frischer Service auf derselben Seen-Datei.
	var events2 := ServerEventsService.new()
	events2.seen_path = seen_path
	events2.setup(rig.client)
	rig.client.add_child(events2)
	var received2: Array = []
	events2.event_received.connect(
		func(id: String, type: String, params: Dictionary) -> void:
			received2.append([id, type, params])
	)
	events2._on_welcome({"pendingEvents": [{"id": "evt-p", "type": "DOUBLE_COINS"}]})
	assert_eq(received2, [], "persistierte Seen-Liste dedupet über App-Neustarts")
	await _teardown(setup)


func _go_online_with_events(rig: NetTestRig, pending: Array) -> void:
	rig.client.connect_now()
	rig.link().open()
	for _i in 3:
		await tree.process_frame
	(
		rig
		. link()
		. respond_to(
			"HELLO",
			"WELCOME",
			{
				"friendCode": "GOOBY-TEST",
				"heartbeatSec": 20,
				"serverTime": 0,
				"pendingEvents": pending,
			}
		)
	)
	for _i in 3:
		await tree.process_frame


func _boot() -> Dictionary:
	var rig := NetTestRig.boot(tree)
	var seen_path := "user://test_events_seen_%d_%d.json" % [Time.get_ticks_usec(), randi()]
	var events := ServerEventsService.new()
	events.seen_path = seen_path
	events.setup(rig.client)
	rig.client.add_child(events)
	var received: Array = []
	events.event_received.connect(
		func(id: String, type: String, params: Dictionary) -> void:
			received.append([id, type, params])
	)
	await wait_frames(1)
	return {"rig": rig, "events": events, "received": received, "seen_path": seen_path}


func _teardown(setup: Dictionary) -> void:
	await (setup["rig"] as NetTestRig).shutdown(tree)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(str(setup["seen_path"])))
