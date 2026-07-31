extends TestCase
## W13B Post/Mail: NetMail-Roundtrip über den FakeWsLink (send → MAIL_NEW →
## inbox → ack), persistente Offline-Outbox mit Flush beim Online-Gehen,
## Geschenk-Transaktionalität des MailSheets (Fehlschlag = Porto + Item
## zurück) und die Quota-Fehlertext-Zuordnung (DE-Strings aus mail.json).

const ITEM_NUTELLA := {"typ": "food", "id": "nutella", "menge": 1}


func test_send_roundtrip_push_inbox_ack() -> void:
	var rig := NetTestRig.boot(tree)
	var mail := _attach_mail(rig)
	await rig.go_online(tree)

	# Senden (ohne Foto → WS-Weg): MAIL_SEND trägt to/text/item/clientId.
	var results: Array = []
	_collect_send(mail, "GOOBY-9ZML", "Hallo Lena!", ITEM_NUTELLA, results)
	await wait_frames(2)
	var sent := rig.link().last_sent("MAIL_SEND")
	var d: Dictionary = sent.get("d", {})
	assert_eq(d.get("to"), "GOOBY-9ZML", "Empfänger im Envelope")
	assert_eq(d.get("text"), "Hallo Lena!", "Text im Envelope")
	assert_eq((d.get("item") as Dictionary).get("id"), "nutella", "Geschenk im Envelope")
	assert_false(str(d.get("clientId", "")).is_empty(), "clientId für Dedupe gesetzt")
	rig.link().respond_to(
		"MAIL_SEND", "MAIL_RESULT", {"ok": true, "id": "mail-1", "sentToday": 1, "dailyLimit": 20}
	)
	assert_true(await wait_until(func() -> bool: return results.size() == 1, 3000))
	assert_true(bool((results[0] as Dictionary)["ok"]), "Senden meldet ok")
	assert_eq((results[0] as Dictionary)["sent_today"], 1)

	# Push MAIL_NEW → Signal + Ungelesen-Zähler.
	var pushes: Array = []
	mail.mail_new.connect(func(m: Dictionary) -> void: pushes.append(m))
	(
		rig
		. link()
		. push_server(
			{
				"v": 1,
				"t": "MAIL_NEW",
				"ts": 0,
				"d":
				{
					"mail":
					{
						"id": "mail-2",
						"from": "GOOBY-9ZML",
						"fromName": "Lena",
						"at": 1000,
						"text": "Hi zurück!",
						"photoId": "",
						"item": null,
						"read": false,
						"claimed": false,
					},
					"unread": 1,
				},
			}
		)
	)
	await wait_frames(2)
	assert_eq(pushes.size(), 1, "MAIL_NEW feuert das Signal")
	assert_eq((pushes[0] as Dictionary).get("id"), "mail-2")
	assert_eq(mail.unread, 1, "Ungelesen-Zähler aus dem Push")

	# Inbox-Pull → MAIL_STATE.
	var inbox: Array = []
	_collect_inbox(mail, inbox)
	await wait_frames(2)
	(
		rig
		. link()
		. respond_to(
			"MAIL_LIST",
			"MAIL_STATE",
			{
				"mails": [{"id": "mail-2", "from": "GOOBY-9ZML", "read": false}],
				"total": 1,
				"unread": 1,
				"offset": 0,
			}
		)
	)
	assert_true(await wait_until(func() -> bool: return inbox.size() == 1, 3000))
	var state: Dictionary = inbox[0]
	assert_true(bool(state["ok"]))
	assert_eq((state["mails"] as Array).size(), 1, "ein Brief in der Liste")

	# Ack → OK mit frischem unread.
	var acks: Array = []
	_collect_ack(mail, "mail-2", acks)
	await wait_frames(2)
	rig.link().respond_to("MAIL_ACK", "OK", {"unread": 0})
	assert_true(await wait_until(func() -> bool: return acks.size() == 1, 3000))
	assert_true(bool((acks[0] as Dictionary)["ok"]))
	assert_eq(mail.unread, 0, "Ack senkt den Ungelesen-Zähler")
	await rig.shutdown(tree)


func test_offline_outbox_persistiert_und_flusht() -> void:
	var rig := NetTestRig.boot(tree)
	var outbox_path := _temp_outbox_path()
	var mail := NetMail.new()
	mail.setup(rig.client, NetOutbox.new(outbox_path))

	# Offline senden → QUEUED + persistenter Eintrag (frische NetOutbox-
	# Instanz liest dieselbe Datei — App-Neustart überlebt).
	var res: Dictionary = await mail.send_mail("GOOBY-9ZML", "Kommt später an!")
	assert_false(bool(res["ok"]))
	assert_eq(res["code"], "QUEUED", "offline landet in der Outbox")
	assert_true(bool(res["queued"]))
	assert_eq(mail.outbox_count(), 1, "ein Outbox-Eintrag")
	var neu_geladen := NetOutbox.new(outbox_path)
	assert_eq(neu_geladen.entries("mail").size(), 1, "Eintrag überlebt Neuladen der Datei")
	var payload: Dictionary = neu_geladen.entries("mail")[0]["payload"]
	assert_eq(payload.get("to"), "GOOBY-9ZML")
	assert_eq(payload.get("text"), "Kommt später an!")

	# Online gehen → Flush schickt MAIL_SEND, ok räumt den Eintrag ab.
	await rig.go_online(tree)
	var gesendet := await wait_until(
		func() -> bool: return not rig.link().last_sent("MAIL_SEND").is_empty(), 3000
	)
	assert_true(gesendet, "Flush schickt den gepufferten Brief")
	rig.link().respond_to(
		"MAIL_SEND", "MAIL_RESULT", {"ok": true, "id": "mail-9", "sentToday": 1, "dailyLimit": 20}
	)
	var geleert := await wait_until(func() -> bool: return mail.outbox_count() == 0, 3000)
	assert_true(geleert, "erfolgreicher Flush leert die Outbox")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(outbox_path))
	await rig.shutdown(tree)


func test_geschenk_transaktional_fehlschlag_bucht_zurueck() -> void:
	# Entnahme: Porto (5) + Geschenk verlassen den Save VOR dem Senden.
	var state := _frischer_state(20, 1)
	assert_true(
		MailSheet.nimm_geschenk_und_porto(state, ITEM_NUTELLA, MailSheet.PORTO),
		"Entnahme klappt bei Deckung"
	)
	assert_eq(int(state["economy"]["coins"]), 15, "Porto abgezogen")
	assert_eq(int(state["inventory"]["food"]["nutella"]), 0, "Geschenk entnommen")

	# Sende-Fehlschlag → Rückbuchung stellt ALLES wieder her.
	MailSheet.gib_zurueck(state, ITEM_NUTELLA, MailSheet.PORTO)
	assert_eq(int(state["economy"]["coins"]), 20, "Porto zurück")
	assert_eq(int(state["inventory"]["food"]["nutella"]), 1, "Geschenk zurück")

	# Ohne Vorrat: nichts wird angefasst (auch das Porto nicht).
	var ohne_item := _frischer_state(20, 0)
	assert_false(MailSheet.nimm_geschenk_und_porto(ohne_item, ITEM_NUTELLA, MailSheet.PORTO))
	assert_eq(int(ohne_item["economy"]["coins"]), 20, "kein Teil-Abzug ohne Vorrat")

	# Ohne Porto-Deckung: ebenfalls unangetastet.
	var ohne_geld := _frischer_state(3, 1)
	assert_false(MailSheet.nimm_geschenk_und_porto(ohne_geld, ITEM_NUTELLA, MailSheet.PORTO))
	assert_eq(int(ohne_geld["economy"]["coins"]), 3)
	assert_eq(int(ohne_geld["inventory"]["food"]["nutella"]), 1)

	# Empfänger-Gutschrift baut fehlende Inventar-Struktur selbst auf.
	var leer: Dictionary = {}
	MailSheet.schreibe_gut(leer, {"typ": "items", "id": "medicine", "menge": 2})
	assert_eq(int(leer["inventory"]["items"]["medicine"]), 2, "Gutschrift legt Struktur an")


func test_quota_fehlertext_ist_gemappt() -> void:
	assert_eq(NetMail.error_key("DAILY_LIMIT"), "mail.err.daily_limit")
	assert_eq(NetMail.error_key("MAILBOX_FULL"), "mail.err.mailbox_full")
	assert_eq(NetMail.error_key("NOT_FRIENDS"), "mail.err.not_friends")
	assert_eq(NetMail.error_key("VOELLIG_UNBEKANNT"), "mail.err.generic")
	var text := I18nService.t("mail.err.daily_limit")
	assert_ne(text, "mail.err.daily_limit", "DE-String existiert in mail.json")
	assert_true(text.contains("20"), "Quota-Text nennt die 20 Briefe")

	# Ende-zu-Ende: Server lehnt mit DAILY_LIMIT ab → message_key gemappt.
	var rig := NetTestRig.boot(tree)
	var mail := _attach_mail(rig)
	await rig.go_online(tree)
	var results: Array = []
	_collect_send(mail, "GOOBY-9ZML", "einer zu viel", {}, results)
	await wait_frames(2)
	rig.link().respond_to(
		"MAIL_SEND",
		"MAIL_RESULT",
		{"ok": false, "code": "DAILY_LIMIT", "sentToday": 20, "dailyLimit": 20}
	)
	assert_true(await wait_until(func() -> bool: return results.size() == 1, 3000))
	var res: Dictionary = results[0]
	assert_false(bool(res["ok"]))
	assert_eq(res["code"], "DAILY_LIMIT")
	assert_eq(res["message_key"], "mail.err.daily_limit", "Fehlertext-Key gemappt")
	await rig.shutdown(tree)


func _attach_mail(rig: NetTestRig) -> NetMail:
	var mail := NetMail.new()
	mail.setup(rig.client, NetOutbox.new(_temp_outbox_path()))
	return mail


func _temp_outbox_path() -> String:
	return "user://test_mail_outbox_%d_%d.json" % [Time.get_ticks_usec(), randi() % 100000]


func _frischer_state(coins: int, nutella: int) -> Dictionary:
	return {
		"economy": {"coins": coins, "coinsEarned": 0, "coinsSpent": 0},
		"inventory": {"food": {"nutella": nutella}, "items": {}},
	}


## Fire-and-forget-Wrapper (Coroutinen-Ergebnisse landen im out-Array,
## der Test pollt per wait_until — Muster test_net_friends.gd).
func _collect_send(mail: NetMail, to: String, text: String, item: Dictionary, out: Array) -> void:
	out.append(await mail.send_mail(to, text, "", item))


func _collect_inbox(mail: NetMail, out: Array) -> void:
	out.append(await mail.fetch_inbox())


func _collect_ack(mail: NetMail, id: String, out: Array) -> void:
	out.append(await mail.ack(id))
