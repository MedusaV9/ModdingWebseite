extends TestCase
## PresenceService: flüchtig per Kontrakt (W2c §3/§7) — offline wird NICHTS
## gepuffert, idempotente Wiederholung wird geschluckt, nach jedem WELCOME
## (Reconnect) wird der aktuelle Zustand genau einmal neu gemeldet.


func test_offline_wird_nichts_gesendet_und_nichts_gepuffert() -> void:
	var rig := NetTestRig.boot(tree)
	var presence := _attach_presence(rig)
	presence.set_kind("park")
	assert_eq(presence.current_kind(), "park")

	# Online kommen → der zuletzt gesetzte Zustand wird EINMAL gemeldet.
	await rig.go_online(tree)
	await wait_frames(1)
	assert_eq(rig.link().count_sent("PRESENCE_SET"), 1)
	assert_eq((rig.link().last_sent("PRESENCE_SET").get("d", {}) as Dictionary).get("kind"), "park")
	await rig.shutdown(tree)


func test_gleicher_kind_wird_geschluckt_neuer_gesendet() -> void:
	var rig := NetTestRig.boot(tree)
	var presence := _attach_presence(rig)
	await rig.go_online(tree)

	presence.set_kind("home")
	presence.set_kind("home")
	presence.set_kind("home")
	assert_eq(rig.link().count_sent("PRESENCE_SET"), 1, "idempotent lokal geschluckt")

	presence.set_kind("minigame:teaParty")
	assert_eq(rig.link().count_sent("PRESENCE_SET"), 2)
	assert_eq(
		(rig.link().last_sent("PRESENCE_SET").get("d", {}) as Dictionary).get("kind"),
		"minigame:teaParty"
	)
	await rig.shutdown(tree)


func test_reconnect_meldet_zustand_neu() -> void:
	var rig := NetTestRig.boot(tree)
	var presence := _attach_presence(rig)
	await rig.go_online(tree)
	presence.set_kind("city")
	assert_eq(rig.link().count_sent("PRESENCE_SET"), 1)

	# Abriss + Reconnect: neuer Link, neues WELCOME → Zustand wird neu gemeldet.
	rig.link().drop()
	await wait_frames(3)
	var reconnected := await wait_until(func() -> bool: return rig.links.size() >= 2, 5000)
	assert_true(reconnected)
	rig.link().open()
	await wait_frames(3)
	rig.link().respond_to("HELLO", "WELCOME", {"friendCode": "GOOBY-TEST", "heartbeatSec": 20})
	await wait_frames(3)
	assert_eq(rig.link().count_sent("PRESENCE_SET"), 1, "genau eine Neu-Meldung auf dem neuen Link")
	assert_eq((rig.link().last_sent("PRESENCE_SET").get("d", {}) as Dictionary).get("kind"), "city")
	await rig.shutdown(tree)


func test_kind_wird_auf_32_zeichen_gekappt() -> void:
	var rig := NetTestRig.boot(tree)
	var presence := _attach_presence(rig)
	presence.set_kind("x".repeat(64))
	assert_eq(presence.current_kind().length(), 32, "Server-Limit ≤32 Zeichen (W2c §3)")
	await rig.shutdown(tree)


func _attach_presence(rig: NetTestRig) -> PresenceService:
	var presence := PresenceService.new()
	rig.client.add_child(presence)
	presence.setup(rig.client)
	return presence
