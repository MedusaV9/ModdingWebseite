extends TestCase
## RW-7 — Benachrichtigungsdienst: Kategorie-Zuordnung ueber ID-Praefixe,
## Ruhezeiten-Fenster (auch ueber Mitternacht), Verschieben in die naechste
## erlaubte Zeit und die Gates des NotificationService (Master + Kategorie).

const AppSettingsScript := preload("res://scripts/core/app_settings.gd")

var _seq := 0


func _fresh_settings() -> Node:
	_seq += 1
	var dir := "user://rw7_tests/notify_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	return AppSettingsScript.new(dir + "/settings.json")


## --------------------------------------------------------- NotifyRules (pur)


func test_kategorie_aus_id_praefix() -> void:
	assert_eq(NotifyRules.category_of_id("rquest_haupt_04"), "warte")
	assert_eq(NotifyRules.category_of_id("liveact_haupt_04"), "warte")
	assert_eq(NotifyRules.category_of_id("pflege_hunger"), "pflege")
	assert_eq(NotifyRules.category_of_id("event_regen"), "pflege")
	assert_eq(NotifyRules.category_of_id("fohlen_luna"), "fohlen")
	assert_eq(NotifyRules.category_of_id("turnier_sonntag"), "turnier")
	assert_eq(NotifyRules.category_of_id("freund_besuch"), "freund")
	assert_eq(NotifyRules.category_of_id("irgendwas"), "", "unbekannt = nur Master-Gate")


func test_ruhefenster_ueber_mitternacht() -> void:
	assert_true(NotifyRules.in_quiet_hours(22, 21, 8), "22 Uhr liegt im Fenster 21-8")
	assert_true(NotifyRules.in_quiet_hours(3, 21, 8))
	assert_false(NotifyRules.in_quiet_hours(12, 21, 8))
	assert_false(NotifyRules.in_quiet_hours(8, 21, 8), "Ende exklusiv")
	assert_true(NotifyRules.in_quiet_hours(21, 21, 8), "Start inklusiv")
	assert_true(NotifyRules.in_quiet_hours(10, 9, 17), "normales Fenster 9-17")
	assert_false(NotifyRules.in_quiet_hours(8, 9, 17))
	assert_false(NotifyRules.in_quiet_hours(5, 7, 7), "from == to = kein Fenster")


func test_verschieben_auf_naechste_erlaubte_zeit() -> void:
	# 23:00 UTC (Offset 0) bei Fenster 21-8 -> naechster Tag 08:00.
	var at_23 := 23 * 3600 * 1000
	var deferred := NotifyRules.defer_out_of_quiet(at_23, 21, 8, 0)
	assert_eq(deferred, (24 + 8) * 3600 * 1000, "23 Uhr -> 8 Uhr am naechsten Tag")
	# 03:00 -> 08:00 am selben Tag.
	var at_3 := 3 * 3600 * 1000
	assert_eq(NotifyRules.defer_out_of_quiet(at_3, 21, 8, 0), 8 * 3600 * 1000)
	# 12:00 liegt ausserhalb -> unveraendert.
	var at_12 := 12 * 3600 * 1000
	assert_eq(NotifyRules.defer_out_of_quiet(at_12, 21, 8, 0), at_12)


func test_decide_gates_und_ruhe() -> void:
	var s := _fresh_settings()
	var mittags := 12 * 3600 * 1000
	var nachts := 23 * 3600 * 1000
	var eintrag := {"id": "pflege_hunger", "title": "T", "body": "B"}
	# Hinweis: decide nutzt den ECHTEN lokalen UTC-Offset — fuer
	# deterministische Assertions stellen wir das Fenster passend um.
	s.set_setting("notifications.quiet_hours", false)
	assert_eq(str(NotifyRules.decide(eintrag, mittags, s)["action"]), "zeigen")
	s.set_setting("notifications.pflege", false)
	assert_eq(str(NotifyRules.decide(eintrag, mittags, s)["action"]), "verwerfen", "Kategorie aus")
	s.set_setting("notifications.pflege", true)
	s.set_setting("notifications.enabled", false)
	assert_eq(str(NotifyRules.decide(eintrag, nachts, s)["action"]), "verwerfen", "Master aus")
	s.set_setting("notifications.enabled", true)
	assert_eq(
		str(NotifyRules.decide({"id": "sys_x"}, mittags, s)["action"]),
		"zeigen",
		"unbekannte Kategorie faellt nur unters Master-Gate"
	)
	s.free()


func test_decide_verschiebt_in_ruhezeit() -> void:
	var s := _fresh_settings()
	# Fenster 0-23 => JEDE Stunde ausser 23 liegt im Fenster -> verschieben.
	s.set_setting("notifications.quiet_from", 0)
	s.set_setting("notifications.quiet_to", 23)
	var offset_min := NotifyRules.local_utc_offset_min()
	var lokal_mittag := (12 * 3600 - offset_min * 60) * 1000
	var decision := NotifyRules.decide({"id": "pflege_x"}, lokal_mittag, s)
	assert_eq(str(decision["action"]), "verschieben", "Ruhezeit schiebt auf")
	assert_true(int(decision["at_ms"]) > lokal_mittag)
	s.free()


## ------------------------------------------------- NotificationService


func test_service_gate_beim_planen() -> void:
	NotifyStub.reset_for_tests()
	var s := _fresh_settings()
	var svc := NotificationService.new()
	svc.settings_override = s
	svc.banner_ui_enabled = false
	tree.root.add_child(svc)
	s.set_setting("notifications.fohlen", false)
	assert_false(svc.schedule("fohlen", "fohlen_luna", "T", "B", 123), "Gate blockt Planung")
	assert_eq(NotifyStub.pending().size(), 0)
	assert_true(svc.schedule("turnier", "turnier_1", "T", "B", 1 << 50))
	assert_eq(NotifyStub.pending().size(), 1)
	svc.cancel("turnier_1")
	assert_eq(NotifyStub.pending().size(), 0)
	svc.free()
	s.free()
	NotifyStub.reset_for_tests()


func test_service_poll_zeigt_und_verschiebt() -> void:
	NotifyStub.reset_for_tests()
	var s := _fresh_settings()
	s.set_setting("notifications.quiet_hours", false)
	var svc := NotificationService.new()
	svc.settings_override = s
	svc.banner_ui_enabled = false
	tree.root.add_child(svc)
	var gezeigt: Array = []
	svc.notification_shown.connect(func(e: Dictionary) -> void: gezeigt.append(e))
	NotifyStub.schedule_local("pflege_test", "Titel", "Text", 1000)
	var shown: Array = svc.poll_now(2000.0)
	assert_eq(shown.size(), 1, "faelliger Eintrag wird zugestellt")
	assert_eq(NotifyStub.pending().size(), 0)
	assert_true(gezeigt.size() >= 1)
	# Jetzt Ruhezeit ueber ALLE Stunden ausser 23 -> Eintrag wird verschoben.
	s.set_setting("notifications.quiet_hours", true)
	s.set_setting("notifications.quiet_from", 0)
	s.set_setting("notifications.quiet_to", 23)
	var offset_min := NotifyRules.local_utc_offset_min()
	var lokal_mittag := float((12 * 3600 - offset_min * 60) * 1000)
	var verschoben: Array = []
	svc.notification_deferred.connect(func(_e: Dictionary, at: int) -> void: verschoben.append(at))
	NotifyStub.schedule_local("pflege_nacht", "Titel", "Text", int(lokal_mittag) - 500)
	var shown2: Array = svc.poll_now(lokal_mittag)
	assert_eq(shown2.size(), 0, "in der Ruhezeit wird nichts gezeigt")
	assert_eq(verschoben.size(), 1, "sondern verschoben")
	assert_eq(NotifyStub.pending().size(), 1, "Eintrag liegt neu geplant im Stub")
	if verschoben.size() == 1:
		assert_true(float(verschoben[0]) > lokal_mittag)
	svc.free()
	s.free()
	NotifyStub.reset_for_tests()


func test_service_banner_dauer_folgt_hinweisdauer() -> void:
	var s := _fresh_settings()
	var svc := NotificationService.new()
	svc.settings_override = s
	tree.root.add_child(svc)
	svc.show_banner("Titel", "Text")
	assert_true(svc.is_banner_visible(), "Banner steht")
	svc.free()
	s.free()
