extends TestCase
## W13C InstantGooby: REST-Post-Roundtrip mit injiziertem poster (Foto ist
## Pflicht → immer REST) → Push INSTANT_NEW → FEED_LIST/FEED_ACK über den
## FakeWsLink, Like einmalig (Server-Idempotenz + like_erlaubt-Regel),
## persistente Offline-Outbox (kind "instant") mit Flush beim Online-Gehen,
## Caption-Limit/Foto-Pflicht (endgültig, landet NIE in der Outbox) und die
## Feed-Cap-Anzeige/Badge-Helfer der App.

const POST_LENA := {
	"id": "inst-2",
	"kind": "instant",
	"from": "GOOBY-9ZML",
	"fromName": "Lena",
	"fromGooby": "Flausch",
	"at": 1000,
	"caption": "Hi aus dem Park!",
	"photoId": "instp-1",
	"likes": 0,
	"liked": false,
	"mine": false,
}


func test_post_roundtrip_push_feed_ack() -> void:
	var rig := NetTestRig.boot(tree)
	var mail := _attach_mail(rig)
	await rig.go_online(tree)
	var foto := _temp_foto_pfad()

	# Posten (REST — poster injiziert): caption + photoB64 + clientId im Body.
	var posted: Array = []
	mail.poster = func(url: String, _headers: PackedStringArray, body: String) -> Dictionary:
		posted.append({"url": url, "body": body})
		return {"ok": true, "id": "inst-1", "recipients": 2, "sentToday": 1, "dailyLimit": 20}
	var results: Array = []
	_collect_post(mail, "Möhrenernte!", foto, results)
	assert_true(await wait_until(func() -> bool: return results.size() == 1, 3000))
	var res: Dictionary = results[0]
	assert_true(bool(res["ok"]), "Posten meldet ok")
	assert_eq(res["recipients"], 2, "Fan-out-Zähler kommt durch")
	assert_eq(posted.size(), 1, "genau EIN REST-Post")
	assert_true(str((posted[0] as Dictionary)["url"]).ends_with("/api/instant"))
	var body: Dictionary = JSON.parse_string(str((posted[0] as Dictionary)["body"]))
	assert_eq(body.get("caption"), "Möhrenernte!", "Caption im Body")
	assert_false(str(body.get("photoB64", "")).is_empty(), "Foto als Base64 im Body")
	assert_false(str(body.get("clientId", "")).is_empty(), "clientId für Dedupe gesetzt")

	# Push INSTANT_NEW → Signal + Ungesehen-Badge-Zähler.
	var pushes: Array = []
	mail.instant_new.connect(func(p: Dictionary) -> void: pushes.append(p))
	rig.link().push_server(
		{"v": 1, "t": "INSTANT_NEW", "ts": 0, "d": {"post": POST_LENA, "unseen": 1}}
	)
	await wait_frames(2)
	assert_eq(pushes.size(), 1, "INSTANT_NEW feuert das Signal")
	assert_eq((pushes[0] as Dictionary).get("kind"), "instant")
	assert_eq(mail.instant_unseen, 1, "Ungesehen-Zähler aus dem Push")

	# Feed-Pull → FEED_STATE; danach FEED_ACK → Badge aus.
	var feeds: Array = []
	_collect_feed(mail, feeds)
	await wait_frames(2)
	rig.link().respond_to(
		"FEED_LIST",
		"FEED_STATE",
		{"posts": [POST_LENA], "total": 1, "cap": 30, "unseen": 1, "offset": 0}
	)
	assert_true(await wait_until(func() -> bool: return feeds.size() == 1, 3000))
	var feed: Dictionary = feeds[0]
	assert_true(bool(feed["ok"]))
	assert_eq((feed["posts"] as Array).size(), 1, "ein Post im Feed")
	assert_eq(((feed["posts"] as Array)[0] as Dictionary).get("kind"), "instant")

	var acks: Array = []
	_collect_ack_feed(mail, acks)
	await wait_frames(2)
	rig.link().respond_to("FEED_ACK", "OK", {"unseen": 0})
	assert_true(await wait_until(func() -> bool: return acks.size() == 1, 3000))
	assert_eq(mail.instant_unseen, 0, "FEED_ACK setzt das Badge zurück")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(foto))
	await rig.shutdown(tree)


func test_like_einmalig() -> void:
	# UI-Regel: nie beim eigenen Post, nie doppelt.
	assert_true(InstantGoobyApp.like_erlaubt({"mine": false, "liked": false}))
	assert_false(InstantGoobyApp.like_erlaubt({"mine": true, "liked": false}), "eigener Post")
	assert_false(InstantGoobyApp.like_erlaubt({"mine": false, "liked": true}), "schon gemöhrt")
	assert_eq(InstantGoobyApp.moehren_text(3), "🥕 3", "Möhren-Knopf mit Zähler")

	# Server-Roundtrip: erster Like zählt, der zweite ist idempotent (already).
	var rig := NetTestRig.boot(tree)
	var mail := _attach_mail(rig)
	await rig.go_online(tree)
	var likes: Array = []
	_collect_like(mail, "inst-2", likes)
	await wait_frames(2)
	var sent := rig.link().last_sent("INSTANT_LIKE")
	assert_eq((sent.get("d", {}) as Dictionary).get("id"), "inst-2", "Post-Id im Envelope")
	rig.link().respond_to("INSTANT_LIKE", "OK", {"likes": 1})
	assert_true(await wait_until(func() -> bool: return likes.size() == 1, 3000))
	assert_true(bool((likes[0] as Dictionary)["ok"]))
	assert_eq((likes[0] as Dictionary)["likes"], 1)
	assert_false(bool((likes[0] as Dictionary)["already"]))

	_collect_like(mail, "inst-2", likes)
	await wait_frames(2)
	rig.link().respond_to("INSTANT_LIKE", "OK", {"likes": 1, "already": true})
	assert_true(await wait_until(func() -> bool: return likes.size() == 2, 3000))
	assert_eq((likes[1] as Dictionary)["likes"], 1, "Zähler bleibt bei 1")
	assert_true(bool((likes[1] as Dictionary)["already"]), "zweiter Like ist idempotent")
	await rig.shutdown(tree)


func test_offline_outbox_persistiert_und_flusht() -> void:
	var rig := NetTestRig.boot(tree)
	var outbox_path := _temp_outbox_path()
	var mail := NetMail.new()
	mail.setup(rig.client, NetOutbox.new(outbox_path))
	var foto := _temp_foto_pfad()

	# Offline posten → QUEUED + persistenter Eintrag (kind "instant").
	var res: Dictionary = await mail.post_instant("Kommt später in den Feed!", foto)
	assert_false(bool(res["ok"]))
	assert_eq(res["code"], "QUEUED", "offline landet in der Outbox")
	assert_eq(res["message_key"], "instant.toast.queued")
	assert_eq(mail.instant_outbox_count(), 1, "ein Instant-Outbox-Eintrag")
	var neu_geladen := NetOutbox.new(outbox_path)
	assert_eq(neu_geladen.entries("instant").size(), 1, "Eintrag überlebt Neuladen")
	assert_eq(neu_geladen.entries("mail").size(), 0, "kind-Trennung in der Outbox")
	var payload: Dictionary = neu_geladen.entries("instant")[0]["payload"]
	assert_eq(payload.get("caption"), "Kommt später in den Feed!")
	assert_eq(payload.get("fotoPfad"), foto)

	# Online gehen → Flush lädt den Post per REST hoch, ok räumt ab.
	var posted: Array = []
	mail.poster = func(url: String, _headers: PackedStringArray, _body: String) -> Dictionary:
		posted.append(url)
		return {"ok": true, "id": "inst-9", "recipients": 1, "sentToday": 1, "dailyLimit": 20}
	await rig.go_online(tree)
	var geleert := await wait_until(func() -> bool: return mail.instant_outbox_count() == 0, 3000)
	assert_true(geleert, "erfolgreicher Flush leert die Outbox")
	assert_eq(posted.size(), 1, "Flush hat genau einmal gepostet")
	assert_true(str(posted[0]).ends_with("/api/instant"))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(outbox_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(foto))
	await rig.shutdown(tree)


func test_caption_limit_und_foto_pflicht() -> void:
	var rig := NetTestRig.boot(tree)
	var mail := _attach_mail(rig)

	# Beides endgültige Client-Fehler: kein Request, KEIN Outbox-Eintrag.
	var zu_lang: Dictionary = await mail.post_instant(
		"x".repeat(NetMail.CAPTION_MAX + 1), "egal.png"
	)
	assert_eq(zu_lang["code"], "CAPTION_TOO_LONG")
	assert_eq(zu_lang["message_key"], "instant.err.caption_too_long")
	var ohne_foto: Dictionary = await mail.post_instant("hübsch hier", "")
	assert_eq(ohne_foto["code"], "NO_PHOTO")
	assert_eq(mail.instant_outbox_count(), 0, "endgültige Fehler landen nie in der Outbox")

	# Fehler-Mapping + DE-Texte existieren (instant.json).
	assert_eq(NetMail.CAPTION_MAX, 120, "Caption-Limit laut Vertrag")
	assert_eq(NetMail.instant_error_key("DAILY_LIMIT"), "instant.err.daily_limit")
	assert_eq(NetMail.instant_error_key("VOELLIG_UNBEKANNT"), "instant.err.generic")
	var text := I18nService.t("instant.err.caption_too_long")
	assert_ne(text, "instant.err.caption_too_long", "DE-String existiert in instant.json")
	assert_true(I18nService.t("instant.err.daily_limit").contains("20"), "Quota-Text nennt die 20")
	await rig.shutdown(tree)


func test_feed_cap_anzeige_und_badge() -> void:
	assert_eq(InstantGoobyApp.cap_hinweis(12, 30), "", "unter dem Cap kein Hinweis")
	var voll := InstantGoobyApp.cap_hinweis(30, 30)
	assert_ne(voll, "", "voller Ringpuffer zeigt den Hinweis")
	assert_true(voll.contains("30"), "Hinweis nennt die 30 Posts")
	assert_ne(voll, "instant.cap_hinweis", "Text kommt aus instant.json")
	assert_eq(NetMail.FEED_CAP, 30, "Cap laut Server-Vertrag")

	# Badge am App-Icon: leer bei 0, Zahl bis 9, danach „9+“.
	assert_eq(InstantGoobyApp.badge_text(0), "")
	assert_eq(InstantGoobyApp.badge_text(3), "3")
	assert_eq(InstantGoobyApp.badge_text(12), "9+")
	assert_eq(InstantGoobyApp.unread_badge("taxi"), null, "fremde Apps bekommen kein Badge")


func _attach_mail(rig: NetTestRig) -> NetMail:
	var mail := NetMail.new()
	mail.setup(rig.client, NetOutbox.new(_temp_outbox_path()))
	return mail


func _temp_outbox_path() -> String:
	return "user://test_instant_outbox_%d_%d.json" % [Time.get_ticks_usec(), randi() % 100000]


## Winziges echtes PNG in user:// (post_instant liest die Datei als Base64).
func _temp_foto_pfad() -> String:
	var pfad := "user://test_instant_foto_%d_%d.png" % [Time.get_ticks_usec(), randi() % 100000]
	var img := Image.create(4, 4, false, Image.FORMAT_RGB8)
	img.fill(Color.ORANGE)
	img.save_png(ProjectSettings.globalize_path(pfad))
	return pfad


## Fire-and-forget-Wrapper (Coroutinen-Ergebnisse landen im out-Array,
## der Test pollt per wait_until — Muster test_w13b_mail.gd).
func _collect_post(mail: NetMail, caption: String, foto: String, out: Array) -> void:
	out.append(await mail.post_instant(caption, foto))


func _collect_feed(mail: NetMail, out: Array) -> void:
	out.append(await mail.fetch_feed())


func _collect_ack_feed(mail: NetMail, out: Array) -> void:
	out.append(await mail.ack_feed())


func _collect_like(mail: NetMail, id: String, out: Array) -> void:
	out.append(await mail.like_post(id))
