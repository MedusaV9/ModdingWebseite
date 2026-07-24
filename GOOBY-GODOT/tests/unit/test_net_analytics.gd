extends TestCase
## AnalyticsSessions: Session-Lebenszyklus in der Outbox (Start/Heartbeat als
## upsert derselben Id/Ende), Batch-Flush an POST /api/analytics mit
## Bearer-Auth (W2c §5) — Erfolg leert die Outbox, Fehlschlag lässt liegen.


func test_session_start_heartbeat_ende_ist_ein_outbox_eintrag() -> void:
	var setup := await _boot()
	var analytics: AnalyticsSessions = setup["analytics"]
	var outbox: NetOutbox = setup["outbox"]

	assert_eq(outbox.entries(AnalyticsSessions.OUTBOX_KIND).size(), 1, "Start schreibt Session")
	var first: Dictionary = outbox.entries()[0]["payload"]
	assert_eq(first.get("sessionId"), analytics.session_id)
	assert_eq(first.get("appVersion"), "5.0.0-godot")

	analytics.heartbeat()
	analytics.heartbeat()
	assert_eq(outbox.size(), 1, "Heartbeats upserten dieselbe Session")

	var session_id := analytics.session_id
	analytics.end_session()
	assert_eq(analytics.session_id, "", "Session beendet")
	assert_eq(outbox.size(), 1)
	assert_eq((outbox.entries()[0]["payload"] as Dictionary).get("sessionId"), session_id)
	await _teardown(setup)


func test_flush_erfolg_leert_outbox_und_sendet_batch() -> void:
	var setup := await _boot()
	var analytics: AnalyticsSessions = setup["analytics"]
	var outbox: NetOutbox = setup["outbox"]
	analytics.end_session()

	var posts: Array[Dictionary] = []
	analytics.poster = func(url: String, headers: PackedStringArray, body: String) -> bool:
		posts.append({"url": url, "headers": headers, "body": body})
		return true
	analytics.rest_base_url = "http://fake.test:1"
	await analytics.flush()

	assert_eq(posts.size(), 1)
	assert_eq(posts[0]["url"], "http://fake.test:1/api/analytics")
	var auth_ok := false
	for header: String in posts[0]["headers"]:
		if header.begins_with("Authorization: Bearer gd-") and header.contains(":"):
			auth_ok = true
	assert_true(auth_ok, "Bearer deviceId:deviceSecret Header")
	var parser := JSON.new()
	assert_eq(parser.parse(posts[0]["body"]), OK)
	var body: Dictionary = parser.data
	assert_true(body.has("batchId"), "Batch idempotent über batchId")
	assert_eq((body["sessions"] as Array).size(), 1)
	assert_eq(outbox.size(), 0, "Erfolg räumt die Outbox")
	await _teardown(setup)


func test_flush_fehlschlag_laesst_eintraege_liegen() -> void:
	var setup := await _boot()
	var analytics: AnalyticsSessions = setup["analytics"]
	var outbox: NetOutbox = setup["outbox"]
	analytics.end_session()

	analytics.poster = func(_url: String, _headers: PackedStringArray, _body: String) -> bool:
		return false
	analytics.rest_base_url = "http://fake.test:1"
	await analytics.flush()
	assert_eq(outbox.size(), 1, "Fehlschlag bleibt für den nächsten Versuch liegen")
	await _teardown(setup)


func test_online_kommen_triggert_flush() -> void:
	var setup := await _boot()
	var analytics: AnalyticsSessions = setup["analytics"]
	var rig: NetTestRig = setup["rig"]
	analytics.end_session()

	# Array statt int: GDScript-Lambdas fangen Primitive by-value.
	var posts: Array = []
	analytics.poster = func(_url: String, _headers: PackedStringArray, _body: String) -> bool:
		posts.append(1)
		return true
	analytics.rest_base_url = "http://fake.test:1"
	await rig.go_online(tree)
	var flushed := await wait_until(func() -> bool: return posts.size() == 1, 3000)
	assert_true(flushed, "ONLINE-Statuswechsel muss flushen")
	assert_eq((setup["outbox"] as NetOutbox).size(), 0)
	await _teardown(setup)


func _boot() -> Dictionary:
	var rig := NetTestRig.boot(tree)
	var outbox_path := (
		"user://test_analytics_%d_%d.json" % [Time.get_ticks_usec(), randi() % 100000]
	)
	var outbox := NetOutbox.new(outbox_path)
	var analytics := AnalyticsSessions.new()
	analytics.setup(rig.client, outbox)
	rig.client.add_child(analytics)
	await wait_frames(1)
	return {"rig": rig, "outbox": outbox, "analytics": analytics, "outbox_path": outbox_path}


func _teardown(setup: Dictionary) -> void:
	await (setup["rig"] as NetTestRig).shutdown(tree)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(str(setup["outbox_path"])))
