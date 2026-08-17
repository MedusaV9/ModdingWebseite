extends TestCase
## RedeemService (E14 P1-3): Code-Einlösungen offline → persistente Outbox →
## Flush beim Reconnect. Endgültige Server-Ablehnungen räumen den Eintrag ab
## (ALREADY_REDEEMED still — idempotenter Retry nach Crash), Transportfehler
## lassen ihn für den nächsten Versuch liegen.


func test_offline_redeem_landet_in_der_outbox() -> void:
	var setup := await _boot()
	var redeem: RedeemService = setup["redeem"]
	var outbox: NetOutbox = setup["outbox"]

	var res: Dictionary = await redeem.redeem("  sommer26 ")
	assert_false(res["ok"])
	assert_eq(res["code"], "QUEUED")
	assert_true(res["queued"])
	var entries := outbox.entries(RedeemService.OUTBOX_KIND)
	assert_eq(entries.size(), 1, "offline → Outbox")
	assert_eq((entries[0]["payload"] as Dictionary).get("code"), "SOMMER26", "normalisiert")

	var res2: Dictionary = await redeem.redeem("SOMMER26")
	assert_eq(res2["code"], "QUEUED")
	assert_eq(outbox.entries(RedeemService.OUTBOX_KIND).size(), 1, "upsert: kein Doppel-Eintrag")
	await _teardown(setup)


func test_reconnect_flusht_und_wendet_reward_an() -> void:
	var setup := await _boot()
	var redeem: RedeemService = setup["redeem"]
	var outbox: NetOutbox = setup["outbox"]
	var rig: NetTestRig = setup["rig"]
	await redeem.redeem("SOMMER26")
	assert_eq(outbox.entries(RedeemService.OUTBOX_KIND).size(), 1)

	var rewards: Array = []
	redeem.redeemed.connect(
		func(code: String, reward: Dictionary) -> void: rewards.append([code, reward])
	)
	var posts: Array = []
	redeem.poster = func(url: String, _headers: PackedStringArray, body: String) -> Variant:
		posts.append([url, body])
		return {"ok": true, "reward": {"coins": 500}}
	redeem.rest_base_url = "http://fake.test:1"

	await rig.go_online(tree)
	var flushed := await wait_until(
		func() -> bool: return outbox.entries(RedeemService.OUTBOX_KIND).is_empty(), 3000
	)
	assert_true(flushed, "ONLINE-Wechsel flusht die Redeem-Outbox")
	assert_eq(rewards, [["SOMMER26", {"coins": 500}]], "redeemed-Signal mit Reward")
	assert_eq((posts[0] as Array)[0], "http://fake.test:1/api/codes/redeem")
	await _teardown(setup)


func test_already_redeemed_raeumt_still_ab() -> void:
	# Crash zwischen Server-ok und Outbox-Aufräumen → Retry ist idempotent:
	# der Server meldet ALREADY_REDEEMED, der Eintrag fliegt OHNE Fehler-Toast.
	var setup := await _boot()
	var redeem: RedeemService = setup["redeem"]
	var outbox: NetOutbox = setup["outbox"]
	var rig: NetTestRig = setup["rig"]
	await redeem.redeem("SOMMER26")

	var failures: Array = []
	redeem.redeem_failed.connect(
		func(code: String, error: String) -> void: failures.append([code, error])
	)
	var rewards: Array = []
	redeem.redeemed.connect(
		func(code: String, reward: Dictionary) -> void: rewards.append([code, reward])
	)
	redeem.poster = func(_url: String, _headers: PackedStringArray, _body: String) -> Variant:
		return {"ok": false, "code": "ALREADY_REDEEMED"}
	redeem.rest_base_url = "http://fake.test:1"

	await rig.go_online(tree)
	var flushed := await wait_until(
		func() -> bool: return outbox.entries(RedeemService.OUTBOX_KIND).is_empty(), 3000
	)
	assert_true(flushed, "ALREADY_REDEEMED räumt den Eintrag ab")
	assert_eq(failures, [], "still — kein Fehler-Signal")
	assert_eq(rewards, [], "keine Doppel-Belohnung")
	await _teardown(setup)


func test_endgueltiger_fehler_raeumt_ab_und_meldet() -> void:
	var setup := await _boot()
	var redeem: RedeemService = setup["redeem"]
	var outbox: NetOutbox = setup["outbox"]
	var rig: NetTestRig = setup["rig"]
	await redeem.redeem("GIBTSNICHT")

	var failures: Array = []
	redeem.redeem_failed.connect(
		func(code: String, error: String) -> void: failures.append([code, error])
	)
	redeem.poster = func(_url: String, _headers: PackedStringArray, _body: String) -> Variant:
		return {"ok": false, "code": "UNKNOWN"}
	redeem.rest_base_url = "http://fake.test:1"

	await rig.go_online(tree)
	var flushed := await wait_until(
		func() -> bool: return outbox.entries(RedeemService.OUTBOX_KIND).is_empty(), 3000
	)
	assert_true(flushed, "UNKNOWN ist endgültig → Eintrag fliegt")
	assert_eq(failures, [["GIBTSNICHT", "UNKNOWN"]])
	await _teardown(setup)


func test_transportfehler_laesst_eintrag_liegen() -> void:
	var setup := await _boot()
	var redeem: RedeemService = setup["redeem"]
	var outbox: NetOutbox = setup["outbox"]
	var rig: NetTestRig = setup["rig"]
	await redeem.redeem("SOMMER26")

	redeem.poster = func(_url: String, _headers: PackedStringArray, _body: String) -> Variant:
		return null
	redeem.rest_base_url = "http://fake.test:1"

	await rig.go_online(tree)
	await redeem.flush()
	assert_eq(
		outbox.entries(RedeemService.OUTBOX_KIND).size(),
		1,
		"Transportfehler → liegt für den nächsten Versuch"
	)
	await _teardown(setup)


func test_online_direktversuch_ohne_outbox() -> void:
	var setup := await _boot()
	var redeem: RedeemService = setup["redeem"]
	var outbox: NetOutbox = setup["outbox"]
	var rig: NetTestRig = setup["rig"]
	await rig.go_online(tree)

	redeem.poster = func(_url: String, _headers: PackedStringArray, _body: String) -> Variant:
		return {"ok": true, "reward": {"coins": 10}}
	redeem.rest_base_url = "http://fake.test:1"
	var res: Dictionary = await redeem.redeem("DIREKT1")
	assert_true(res["ok"])
	assert_eq((res["reward"] as Dictionary).get("coins"), 10)
	assert_eq(outbox.size(), 0, "online + Erfolg → nie in der Outbox")
	await _teardown(setup)


func _boot() -> Dictionary:
	var rig := NetTestRig.boot(tree)
	var outbox_path := "user://test_redeem_%d_%d.json" % [Time.get_ticks_usec(), randi() % 100000]
	var outbox := NetOutbox.new(outbox_path)
	var redeem := RedeemService.new()
	redeem.setup(rig.client, outbox)
	rig.client.add_child(redeem)
	await wait_frames(1)
	return {"rig": rig, "outbox": outbox, "redeem": redeem, "outbox_path": outbox_path}


func _teardown(setup: Dictionary) -> void:
	await (setup["rig"] as NetTestRig).shutdown(tree)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(str(setup["outbox_path"])))
