extends TestCase
## W13/NETZ-Kleinpaket:
## (a) GoobyPal-Verlaufs-Liste (P3 AP-3) — pure Formatierung + Sheet-Render,
## (b) ws://-Heimnetz-Gate (Doc C §7 / AP-12) — pure Host-Klassifikation +
##     NetClient-Verhalten am FakeWsLink (Muster aus test_net_client.gd),
## (c) Presence-i18n (P6 H12) — kind-basierte Übersetzung mit
##     Server-Label-Fallback.

const HEUTE_UTC := {"year": 2026, "month": 7, "day": 15, "hour": 12, "minute": 0, "second": 0}


## Stub-Netz für den echten GoobyPalService: liefert PAL_HISTORY sofort.
class StubNet:
	extends Node

	signal pushed(type: String, data: Dictionary)
	signal welcome_received(data: Dictionary)

	var welcome_data: Dictionary = {}
	var online := true
	var history_d: Dictionary = {"entries": [], "sentToday": 0, "dailyLimit": 250}

	func is_online() -> bool:
		return online

	func request(_type: String, _data: Dictionary) -> Dictionary:
		return {"ok": true, "code": "", "t": "PAL_HISTORY_STATE", "d": history_d}

	func send(_type: String, _data: Dictionary) -> int:
		return 1


# ── (b) Heimnetz-Gate: pure Host-Klassifikation ─────────────────────────────


func test_host_gate_erlaubt_private_und_lokale_ziele() -> void:
	var erlaubt := [
		"localhost",
		"LOCALHOST",
		" localhost ",
		"127.0.0.1",
		"127.42.0.99",
		"10.0.0.5",
		"10.255.255.254",
		"172.16.0.1",
		"172.31.255.254",
		"192.168.0.10",
		"192.168.1.5:8765",
		"fritz-nas.local",
		"GOOBY.LOCAL",
		"gooby.keller.local",
		"::1",
		"[::1]",
		"[::1]:8765",
		"0:0:0:0:0:0:0:1",
		"fd12:3456::1",
		"fe80::abcd",
		"fe80::1%eth0",
		"fake.test",
		"server.invalid",
		"mein.localhost",
	]
	for host: String in erlaubt:
		assert_true(NetHostGate.is_private_host(host), "erlaubt erwartet: %s" % host)


func test_host_gate_blockt_oeffentliche_ziele() -> void:
	var blockiert := [
		"example.com",
		"ark.atomi23.de",
		"example.com:8765",
		"8.8.8.8",
		"11.0.0.1",
		"126.255.0.1",
		"128.0.0.1",
		"172.15.0.1",
		"172.32.0.1",
		"192.169.0.1",
		"193.168.0.1",
		"10.0.0.256",
		"10.0.0",
		"2a01:4f8::1",
		"[2a01:4f8::1]:443",
		"meinserver",
		"local",
		"test",
		"notlocal.com",
		"192.168.1.evil.com",
		"",
		"   ",
	]
	for host: String in blockiert:
		assert_false(NetHostGate.is_private_host(host), "blockiert erwartet: %s" % host)


func test_host_gate_strip_port_randfaelle() -> void:
	assert_eq(NetHostGate.strip_port("192.168.1.5:8765"), "192.168.1.5")
	assert_eq(NetHostGate.strip_port("[::1]:8765"), "::1")
	assert_eq(NetHostGate.strip_port("[fe80::1]"), "fe80::1")
	assert_eq(NetHostGate.strip_port("fe80::1"), "fe80::1", "klammerlose IPv6 bleibt ganz")
	assert_eq(NetHostGate.strip_port("example.com"), "example.com")
	assert_eq(NetHostGate.strip_port("host:kein_port"), "host:kein_port")


# ── (b) Heimnetz-Gate: NetClient-Verhalten (FakeWsLink-Rig) ─────────────────


func test_gate_blockt_ws_zu_oeffentlichem_host() -> void:
	var rig := NetTestRig.boot(tree)
	rig.client.config_override = {"host": "ark.atomi23.de", "port": 5055, "tls": false}
	var blocked: Array = []
	rig.client.insecure_blocked.connect(func(host: String) -> void: blocked.append(host))
	rig.client.connect_now()
	await wait_frames(2)
	assert_eq(rig.links.size(), 0, "kein Verbindungsversuch (kein Link gebaut)")
	assert_eq(rig.client.status, NetClient.Status.OFFLINE, "Offline-Modus")
	assert_eq(blocked, ["ark.atomi23.de"], "insecure_blocked gefeuert")
	await rig.shutdown(tree)


func test_gate_laesst_wss_zu_oeffentlichem_host_durch() -> void:
	var rig := NetTestRig.boot(tree)
	rig.client.config_override = {"host": "ark.atomi23.de", "port": 5055, "tls": true}
	rig.client.connect_now()
	assert_eq(rig.links.size(), 1, "wss:// (tls) bleibt immer erlaubt")
	assert_eq(rig.link().connected_url, "wss://ark.atomi23.de:5055/ws")
	await rig.shutdown(tree)


func test_gate_laesst_ws_im_heimnetz_durch() -> void:
	var rig := NetTestRig.boot(tree)
	rig.client.config_override = {"host": "192.168.0.42", "port": 8765, "tls": false}
	rig.client.connect_now()
	assert_eq(rig.links.size(), 1)
	assert_eq(rig.link().connected_url, "ws://192.168.0.42:8765/ws")
	await rig.shutdown(tree)


func test_gate_bricht_bestehenden_handshake_nicht() -> void:
	# Offline-first-Semantik der bestehenden test_net_*-Suiten bleibt: das
	# Standard-Rig (fake.test, tls=false) kommt weiter normal online.
	var rig := NetTestRig.boot(tree)
	await rig.go_online(tree, "GOOBY-W13G")
	assert_true(rig.client.is_online())
	assert_eq(rig.client.friend_code, "GOOBY-W13G")
	await rig.shutdown(tree)


# ── (c) Presence-i18n ────────────────────────────────────────────────────────


func test_presence_kind_wird_de_uebersetzt() -> void:
	var row := {
		"online": true,
		"goobyName": "Knöpfchen",
		"activity": {"kind": "park", "label": "GANZ ANDERES SERVER-LABEL"},
	}
	assert_eq(FriendListUi.presence_text(row), "ist gerade mit Knöpfchen im Park")


func test_presence_kind_wird_en_uebersetzt() -> void:
	I18nService.set_locale("en")
	var row := {
		"online": true,
		"goobyName": "Knöpfchen",
		"activity": {"kind": "sleep", "label": "schläft — pssst, Knöpfchen auch"},
	}
	assert_eq(FriendListUi.presence_text(row), "is asleep — shhh, so is Knöpfchen")
	var mg := {
		"online": true,
		"goobyName": "Knöpfchen",
		"activity": {"kind": "minigame:goobnom", "label": "spielt gerade „goobnom“"},
	}
	assert_eq(FriendListUi.presence_text(mg), "is playing “goobnom”")
	I18nService.set_locale("de")


func test_presence_minigame_de_wie_server_template() -> void:
	assert_eq(
		FriendListUi.presence_text_for_kind("minigame:goobnom", "Knöpfchen"),
		"spielt gerade „goobnom“"
	)


func test_presence_unbekannter_kind_faellt_auf_server_label() -> void:
	var row := {
		"online": true,
		"goobyName": "Knöpfchen",
		"activity": {"kind": "post", "label": "ist mit Knöpfchen unterwegs"},
	}
	assert_eq(FriendListUi.presence_text(row), "ist mit Knöpfchen unterwegs")
	var ohne_label := {"online": true, "activity": {"kind": "post"}}
	assert_eq(FriendListUi.presence_text(ohne_label), I18nService.t("net.friends.online"))


func test_presence_offline_und_ohne_activity_unveraendert() -> void:
	assert_eq(FriendListUi.presence_text({"online": false}), I18nService.t("net.friends.offline"))
	assert_eq(FriendListUi.presence_text({"online": true}), I18nService.t("net.friends.online"))


# ── (a) GoobyPal-Verlauf: pure Formatierung ──────────────────────────────────


func test_verlauf_zeile_modell_geschickt_und_bekommen() -> void:
	var now := int(Time.get_unix_time_from_datetime_dict(HEUTE_UTC))
	var namen := {"GOOBY-AAAA": "Lena"}
	var raus := GoobyPalVerlauf.zeile_modell(
		{"dir": "out", "peer": "GOOBY-AAAA", "amount": 50, "at": now * 1000}, namen, now, 0
	)
	assert_true(raus["raus"])
	assert_eq(raus["name"], "Lena", "peer-Code über Freundesliste aufgelöst")
	assert_eq(raus["richtung"], I18nService.t("phone.goobypal.verlauf_geschickt"))
	assert_eq(raus["betrag"], "−50 ᴳ")
	assert_eq(raus["icon"], GoobyPalVerlauf.ICON_GESCHICKT)
	var rein := GoobyPalVerlauf.zeile_modell(
		{"dir": "in", "peer": "GOOBY-ZZZZ", "amount": 7, "at": now * 1000}, namen, now, 0
	)
	assert_false(rein["raus"])
	assert_eq(rein["name"], "GOOBY-ZZZZ", "unbekannter Code bleibt sichtbar")
	assert_eq(rein["betrag"], "+7 ᴳ")
	assert_eq(rein["icon"], GoobyPalVerlauf.ICON_BEKOMMEN)
	assert_ne(rein["farbe"], raus["farbe"], "Richtung hat eigene Farbe")


func test_verlauf_datum_lokal_formatiert() -> void:
	# Injizierte Zeit: 15.07.2026 12:00 UTC, Anzeige in UTC+2 (14:00 lokal).
	var now := int(Time.get_unix_time_from_datetime_dict(HEUTE_UTC))
	var offset := 120
	assert_eq(
		GoobyPalVerlauf.format_datum(now * 1000, now, offset),
		I18nService.t("phone.goobypal.verlauf_heute", {"zeit": "14:00"}),
		"UTC-Offset fließt in die Uhrzeit ein"
	)
	var mitternacht := (now - 14 * 3600) * 1000
	assert_eq(
		GoobyPalVerlauf.format_datum(mitternacht, now, offset),
		I18nService.t("phone.goobypal.verlauf_heute", {"zeit": "00:00"}),
		"00:00 lokal ist noch heute"
	)
	var gestern := (now - 15 * 3600) * 1000
	assert_eq(
		GoobyPalVerlauf.format_datum(gestern, now, offset),
		I18nService.t("phone.goobypal.verlauf_gestern", {"zeit": "23:00"})
	)
	var alt := (now - 10 * GoobyPalVerlauf.SEC_PRO_TAG) * 1000
	assert_eq(
		GoobyPalVerlauf.format_datum(alt, now, offset),
		I18nService.t("phone.goobypal.verlauf_datum", {"tag": "05", "monat": "07", "jahr": "2026"})
	)


func test_verlauf_namen_von_freundesliste() -> void:
	var namen := (
		GoobyPalVerlauf
		. namen_von(
			[
				{"friendCode": "GOOBY-AAAA", "name": "Lena", "goobyName": "Knöpfchen"},
				{"friendCode": "", "name": "kaputt"},
				"kein_dictionary",
			]
		)
	)
	assert_eq(namen, {"GOOBY-AAAA": "Lena"})


func test_verlauf_build_liste_leer_nutzt_empty_state() -> void:
	var now := int(Time.get_unix_time_from_datetime_dict(HEUTE_UTC))
	var box := GoobyPalVerlauf.build_liste([], {}, now, 0)
	assert_true(box.find_child("EmptyState", true, false) != null, "Empty-State-Komponente")
	assert_true(box.find_child("VerlaufZeilen", true, false) == null)
	box.free()


func test_verlauf_build_liste_neueste_zuerst() -> void:
	var now := int(Time.get_unix_time_from_datetime_dict(HEUTE_UTC))
	var entries := [
		{"dir": "out", "peer": "GOOBY-ALT1", "amount": 10, "at": (now - 9000) * 1000},
		{"dir": "in", "peer": "GOOBY-NEU1", "amount": 20, "at": now * 1000},
	]
	var box := GoobyPalVerlauf.build_liste(entries, {}, now, 0)
	var rows: Node = box.find_child("VerlaufZeilen", true, false)
	assert_true(rows != null and rows.get_child_count() == 2)
	var erste: Node = rows.get_child(0).find_child("ZeileName", true, false)
	assert_true(str((erste as Label).text).contains("GOOBY-NEU1"), "neuester Eintrag oben")
	box.free()


# ── (a) GoobyPal-Sheet: Verlauf + Tageslimit-Anzeige zusammen ────────────────


func test_sheet_rendert_verlauf_und_tageslimit() -> void:
	var net := StubNet.new()
	net.history_d = {
		"entries":
		[
			{"dir": "out", "peer": "GOOBY-AAAA", "amount": 50, "at": 1000},
			{"dir": "in", "peer": "GOOBY-BBBB", "amount": 25, "at": 2000},
		],
		"sentToday": 50,
		"dailyLimit": 250,
	}
	tree.root.add_child(net)
	var pal := GoobyPalService.new()
	pal.seen_path = "user://test_w13_pal_seen.json"
	tree.root.add_child(pal)
	pal.setup(net, null)
	var sheet := GoobyPalSheet.new()
	sheet.setup(pal, {"friendCode": "GOOBY-AAAA", "name": "Lena", "goobyName": "Knöpfchen"})
	tree.root.add_child(sheet)
	await wait_frames(3)

	var rows: Node = sheet.find_child("VerlaufZeilen", true, false)
	assert_true(rows != null, "Verlaufs-Liste ist gerendert")
	assert_eq(rows.get_child_count(), 2)
	# Neueste zuerst: Zeile 0 = at 2000 (bekommen, unbekannter Code bleibt
	# sichtbar), Zeile 1 = at 1000 (der angeschriebene Freund ist benannt).
	var oben: Node = rows.get_child(0).find_child("ZeileName", true, false)
	assert_true(str((oben as Label).text).begins_with("GOOBY-BBBB"), "neuester Eintrag oben")
	var unten: Node = rows.get_child(1).find_child("ZeileName", true, false)
	assert_true(str((unten as Label).text).begins_with("Lena"), "Freundesname aufgelöst")
	# Tageslimit-Anzeige („Heute noch X“) bleibt intakt — nicht kaputt machen!
	assert_eq(sheet._remaining_label.text, I18nService.t("social.pal.remaining", {"rest": 200}))
	assert_false(sheet._send_button.disabled, "online → Senden aktiv")

	sheet.queue_free()
	pal.queue_free()
	net.queue_free()
	await wait_frames(1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_w13_pal_seen.json"))


func test_sheet_offline_zeigt_leeren_verlauf_und_sperrt_senden() -> void:
	var net := StubNet.new()
	net.online = false
	tree.root.add_child(net)
	var pal := GoobyPalService.new()
	pal.seen_path = "user://test_w13_pal_seen2.json"
	tree.root.add_child(pal)
	pal.setup(net, null)
	var sheet := GoobyPalSheet.new()
	sheet.setup(pal, {"friendCode": "GOOBY-AAAA", "name": "Lena"})
	tree.root.add_child(sheet)
	await wait_frames(3)

	assert_true(sheet._send_button.disabled, "offline → Senden aus (Bestand)")
	assert_true(
		sheet.find_child("EmptyState", true, false) != null, "offline → knuffiger Leerzustand"
	)

	sheet.queue_free()
	pal.queue_free()
	net.queue_free()
	await wait_frames(1)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_w13_pal_seen2.json"))
