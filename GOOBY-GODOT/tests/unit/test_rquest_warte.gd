extends TestCase
## RW-3 — Warte-Quests (RQuestWarte) + Live-Activity-Schnittstelle
## (RanchLiveActivity): Restzeit-Rechnung/-Format, deterministische
## Alternativ-Tipps, Notification-Planung ueber den NotifyStub und der
## Live-Activity-Fallback ohne native Bridge.

const MIN := RQuestEngine.MS_PRO_MIN


func _aufraeumen() -> void:
	for eintrag: Dictionary in NotifyStub.pending():
		NotifyStub.cancel_local(str(eintrag["id"]))
	RanchLiveActivity.reset_for_tests()


func test_restzeit_rechnung() -> void:
	var lauf := {"status": RQuestSlices.STATUS_WARTEND, "bereitAt": 90 * MIN}
	assert_eq(RQuestWarte.restzeit_ms(lauf, 30 * MIN), 60 * MIN)
	assert_eq(RQuestWarte.restzeit_ms(lauf, 95 * MIN), 0, "faellig = 0")
	assert_eq(
		RQuestWarte.restzeit_ms({"status": "aktiv", "bereitAt": 999}, 0),
		0,
		"nur wartende Laeufe haben Restzeit"
	)


func test_restzeit_format() -> void:
	assert_eq(RQuestWarte.restzeit_text(0), I18nService.t("rquest.warte.gleich"))
	assert_eq(RQuestWarte.restzeit_text(12 * MIN), I18nService.t("rquest.warte.minuten", {"m": 12}))
	assert_eq(
		RQuestWarte.restzeit_text(125 * MIN),
		I18nService.t("rquest.warte.stunden", {"h": 2, "m": "05"})
	)


func test_alternative_ist_deterministisch() -> void:
	var a := RQuestWarte.alternative_text("haupt_04")
	assert_eq(a, RQuestWarte.alternative_text("haupt_04"), "gleiche Quest = gleicher Tipp")
	assert_false(a.is_empty())


func test_warte_gestartet_plant_notification_und_activity() -> void:
	_aufraeumen()
	var lauf := {"status": RQuestSlices.STATUS_WARTEND, "bereitAt": 777 * MIN}
	RQuestWarte.warte_gestartet(
		"fx_q", {"typ": "warte_bis", "dauerMin": 5, "liveActivity": true}, lauf, "Fixture-Quest"
	)
	var pending := NotifyStub.pending()
	assert_eq(pending.size(), 2, "Quest-Notification + Live-Activity-Fallback")
	var ids: Array = []
	for eintrag: Dictionary in pending:
		ids.append(str(eintrag["id"]))
		assert_eq(int(eintrag["at_ms"]), 777 * MIN)
	assert_true(ids.has("rquest_fx_q"))
	assert_true(ids.has("liveact_fx_q"), "liveActivity-Ziel startet die Activity")
	assert_eq(RanchLiveActivity.aktive().size(), 1)
	_aufraeumen()


func test_warte_gestartet_ohne_live_activity_flag() -> void:
	_aufraeumen()
	var lauf := {"status": RQuestSlices.STATUS_WARTEND, "bereitAt": 5 * MIN}
	RQuestWarte.warte_gestartet("fx_still", {"typ": "warte_bis", "dauerMin": 5}, lauf, "Still")
	assert_eq(NotifyStub.pending().size(), 1, "nur die lokale Notification")
	assert_eq(RanchLiveActivity.aktive().size(), 0)
	_aufraeumen()


func test_warte_fertig_und_aufraeumen() -> void:
	_aufraeumen()
	var lauf := {"status": RQuestSlices.STATUS_WARTEND, "bereitAt": 5 * MIN}
	RQuestWarte.warte_gestartet(
		"fx_q", {"typ": "warte_bis", "dauerMin": 5, "liveActivity": true}, lauf, "Fixture"
	)
	RQuestWarte.warte_fertig("fx_q")
	assert_eq(RanchLiveActivity.aktive().size(), 0, "warte_fertig beendet die Activity")
	RQuestWarte.aufraeumen("fx_q")
	assert_eq(NotifyStub.pending().size(), 0, "aufraeumen storniert die Notification")


func test_live_activity_update_und_sortierung() -> void:
	RanchLiveActivity.reset_for_tests()
	RanchLiveActivity.start("b", "B", "laeuft", 2000)
	RanchLiveActivity.start("a", "A", "laeuft", 1000)
	RanchLiveActivity.update("a", "fast fertig", 900)
	RanchLiveActivity.update("fremd", "no-op", 1)
	var aktive := RanchLiveActivity.aktive()
	assert_eq(aktive.size(), 2)
	assert_eq(aktive[0]["id"], "a", "nach Ende sortiert")
	assert_eq(aktive[0]["text"], "fast fertig")
	RanchLiveActivity.beende("a")
	RanchLiveActivity.beende("b")
	assert_eq(RanchLiveActivity.aktive().size(), 0)
	_aufraeumen()
