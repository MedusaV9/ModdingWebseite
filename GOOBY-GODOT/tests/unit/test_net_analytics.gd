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


func test_produktions_boot_puffert_session_ab_sekunde_null() -> void:
	# E14 P1-1: der ECHTE Boot-Pfad (build_services=true) muss den
	# Session-Start sofort in die Outbox schreiben — ein Crash/OS-Kill vor
	# dem ersten 60-s-Heartbeat darf die Session nicht mehr verlieren.
	var stamp := "%d_%d" % [Time.get_ticks_usec(), randi() % 100000]
	var net := NetClient.new()
	net.auto_connect = false
	net.identity_path = "user://test_prodboot_id_%s.json" % stamp
	net.outbox_path = "user://test_prodboot_outbox_%s.json" % stamp
	net.config_override = {"host": "fake.test", "port": 1, "tls": false}
	tree.root.add_child(net)
	await wait_frames(1)

	assert_true(net.analytics != null, "Analytics-Service gebaut")
	assert_false(net.analytics.session_id.is_empty(), "Session läuft")
	var entries := net.outbox.entries(AnalyticsSessions.OUTBOX_KIND)
	assert_eq(entries.size(), 1, "Session-Start liegt SOFORT in der Outbox")
	assert_eq((entries[0]["payload"] as Dictionary).get("sessionId"), net.analytics.session_id)
	assert_true(FileAccess.file_exists(net.outbox_path), "Outbox-Datei persistiert (Crash-sicher)")

	var identity_path := net.identity_path
	var outbox_path := net.outbox_path
	net.queue_free()
	await wait_frames(1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(identity_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(outbox_path))


func test_spaetes_setup_schreibt_session_start_nach() -> void:
	# Regressionsnetz für die alte Boot-Reihenfolge: _ready() lief ohne
	# Outbox → setup() muss den Start nachschreiben statt ihn zu verlieren.
	var rig := NetTestRig.boot(tree)
	var analytics := AnalyticsSessions.new()
	rig.client.add_child(analytics)
	await wait_frames(1)
	assert_false(analytics.session_id.is_empty(), "_ready() startete die Session")

	var outbox_path := "user://test_backfill_%d_%d.json" % [Time.get_ticks_usec(), randi()]
	var outbox := NetOutbox.new(outbox_path)
	assert_eq(outbox.size(), 0, "vor setup(): nichts gepuffert")
	analytics.setup(rig.client, outbox)
	assert_eq(outbox.entries(AnalyticsSessions.OUTBOX_KIND).size(), 1, "setup() schreibt nach")

	analytics.queue_free()
	await rig.shutdown(tree)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(outbox_path))


func test_flush_behaelt_laufende_session() -> void:
	# E14 P1-2 (Client-Hälfte): der Eintrag der LAUFENDEN Session bleibt nach
	# einem erfolgreichen Flush liegen — Heartbeats verlängern ihn weiter,
	# der Server upsertet pro sessionId nach max. Dauer. Erst nach
	# end_session() räumt der nächste Flush ihn ab.
	var setup := await _boot()
	var analytics: AnalyticsSessions = setup["analytics"]
	var outbox: NetOutbox = setup["outbox"]

	analytics.poster = func(_url: String, _headers: PackedStringArray, _body: String) -> bool:
		return true
	analytics.rest_base_url = "http://fake.test:1"
	await analytics.flush()
	assert_eq(
		outbox.entries(AnalyticsSessions.OUTBOX_KIND).size(),
		1,
		"laufende Session bleibt in der Outbox"
	)

	analytics.heartbeat()
	assert_eq(outbox.size(), 1, "Heartbeat upsertet weiter denselben Eintrag")

	analytics.end_session()
	await analytics.flush()
	assert_eq(outbox.size(), 0, "beendete Session wird nach dem Flush abgeräumt")
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
