extends TestCase
## W13-C Account-Umzug (Doc C §7): UmzugSheet-Flow am FakeWsLink — Erfolg
## (MOVE_REDEEM → Identity-Swap persistiert + Reconnect mit neuer Identität),
## falscher Code, abgelaufener Code, lokale Längen-Validierung (kein Request)
## und Offline-Verhalten. Dazu: adopt_identity() schreibt die Identitätsdatei.

const NEW_SECRET := "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"


func _new_identity(device_id: String) -> Dictionary:
	return {
		"deviceId": device_id,
		"deviceSecret": NEW_SECRET,
		"friendCode": "GOOBY-MOVD",
		"name": "Anna",
		"goobyName": "Flausch",
	}


func _make_sheet(rig: NetTestRig) -> UmzugSheet:
	var sheet := UmzugSheet.new()
	sheet.name = "UmzugSheet"
	sheet.net = rig.client
	tree.root.add_child(sheet)
	return sheet


func _read_identity_file(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


func test_erfolg_identity_swap_persistiert_und_reconnect() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var alte_device_id := str(rig.client.identity()["deviceId"])
	var sheet := _make_sheet(rig)
	await wait_frames(1)

	sheet.set_code("k7qwx2mp ")  # Kleinschreibung + Leerzeichen → normalisiert
	sheet.submit()
	await wait_frames(2)
	var req := rig.link().last_sent("MOVE_REDEEM")
	assert_eq(
		(req.get("d", {}) as Dictionary).get("code"), "K7QWX2MP", "Code normalisiert im Envelope"
	)

	rig.link().respond_to(
		"MOVE_REDEEM", "MOVE_RESULT", {"ok": true, "identity": _new_identity("gd-umzug-neu")}
	)
	assert_true(
		await wait_until(func() -> bool: return sheet.succeeded, 3000), "Umzug meldet Erfolg"
	)
	assert_eq(sheet.status_key, "umzug.erfolg")

	# Identity-Swap: NetClient trägt die übernommene Identität …
	assert_eq(rig.client.identity()["deviceId"], "gd-umzug-neu")
	assert_eq(rig.client.friend_code, "GOOBY-MOVD")
	assert_ne(rig.client.identity()["deviceId"], alte_device_id, "alte Identität ersetzt")
	# … und sie ist PERSISTIERT (App-Neustart überlebt den Swap).
	var stored := _read_identity_file(rig.identity_path)
	assert_eq(stored.get("deviceId"), "gd-umzug-neu", "Identitätsdatei umgeschrieben")
	assert_eq(stored.get("friendCode"), "GOOBY-MOVD")
	assert_eq(str(stored.get("deviceSecret", "")), NEW_SECRET)

	# adopt_identity verbindet neu: frischer Link, HELLO mit NEUER Identität.
	assert_true(rig.links.size() >= 2, "Reconnect erzeugt neuen Link")
	rig.link().open()
	await wait_frames(3)
	var hello := rig.link().last_sent("HELLO")
	assert_eq((hello.get("d", {}) as Dictionary).get("deviceId"), "gd-umzug-neu")

	sheet.queue_free()
	await rig.shutdown(tree)


func test_falscher_code_laesst_identitaet_unangetastet() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var alte_device_id := str(rig.client.identity()["deviceId"])
	var sheet := _make_sheet(rig)
	await wait_frames(1)

	sheet.set_code("AAAAAAAA")
	sheet.submit()
	await wait_frames(2)
	rig.link().respond_to("MOVE_REDEEM", "MOVE_RESULT", {"ok": false, "code": "INVALID_CODE"})
	assert_true(
		await wait_until(func() -> bool: return sheet.status_key == "umzug.fehler_code", 3000),
		"falscher Code → eigener Fehlertext"
	)
	assert_false(sheet.succeeded)
	assert_eq(rig.client.identity()["deviceId"], alte_device_id, "Identität unverändert")
	assert_eq(rig.links.size(), 1, "kein Reconnect bei Fehlschlag")

	sheet.queue_free()
	await rig.shutdown(tree)


func test_abgelaufener_code_meldet_ablauf() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var sheet := _make_sheet(rig)
	await wait_frames(1)

	sheet.set_code("BBBBBBBB")
	sheet.submit()
	await wait_frames(2)
	rig.link().respond_to("MOVE_REDEEM", "MOVE_RESULT", {"ok": false, "code": "EXPIRED"})
	assert_true(
		await wait_until(
			func() -> bool: return sheet.status_key == "umzug.fehler_abgelaufen", 3000
		),
		"EXPIRED → 24-h-Erklärtext"
	)
	assert_false(sheet.succeeded)

	sheet.queue_free()
	await rig.shutdown(tree)


func test_kurzer_code_wird_lokal_abgefangen() -> void:
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree)
	var sheet := _make_sheet(rig)
	await wait_frames(1)

	sheet.set_code("ABC")
	sheet.submit()
	await wait_frames(2)
	assert_eq(sheet.status_key, "umzug.fehler_kurz")
	assert_eq(rig.link().count_sent("MOVE_REDEEM"), 0, "kein Request bei lokalem Fehler")

	sheet.queue_free()
	await rig.shutdown(tree)


func test_offline_meldet_offline() -> void:
	var rig := NetTestRig.boot(tree)  # bewusst NICHT online
	var sheet := _make_sheet(rig)
	await wait_frames(1)

	sheet.set_code("CCCCCCCC")
	sheet.submit()
	assert_true(
		await wait_until(func() -> bool: return sheet.status_key == "umzug.fehler_offline", 3000),
		"offline → Offline-Hinweis"
	)
	assert_false(sheet.succeeded)

	sheet.queue_free()
	await rig.shutdown(tree)


func test_strings_paritaet_umzug_domain() -> void:
	I18nService.reset_cache()
	var de := I18nService.table("de")
	var en := I18nService.table("en")
	var keys := [
		"umzug.settings_eintrag",
		"umzug.titel",
		"umzug.intro",
		"umzug.erfolg",
		"umzug.fehler_code",
		"umzug.fehler_abgelaufen",
		"umzug.fehler_offline",
	]
	for key: String in keys:
		assert_true(de.has(key), "DE hat %s" % key)
		assert_true(en.has(key), "EN hat %s" % key)
	assert_true(
		str(de["umzug.intro"]).contains("Spielstand bleibt"),
		"Intro macht glasklar: Spielstand bleibt lokal"
	)
