extends TestCase
## RW-7 — Aktivierung des versteckten Entwicklermodus (Doc §5.1):
## 3 Tipps auf das aktive "Deutsch" innerhalb 1,5 s, Fehlversuchs-Cooldown,
## und der Warn-Dialog mit 2-s-Halte-Bestaetigung (DevUnlockDialog).


func test_drei_schnelle_tipps_loesen_aus() -> void:
	var trigger := DevTrigger.new()
	assert_false(bool(trigger.register_tap(1000, "de")["triggered"]))
	assert_false(bool(trigger.register_tap(1400, "de")["triggered"]))
	var third: Dictionary = trigger.register_tap(1900, "de")
	assert_true(bool(third["triggered"]), "3 Tipps in 1,5 s = Trigger")
	assert_false(bool(trigger.register_tap(2000, "de")["triggered"]), "Serie startet danach neu")


func test_langsame_tipps_zaehlen_nicht() -> void:
	var trigger := DevTrigger.new()
	trigger.register_tap(1000, "de")
	trigger.register_tap(1400, "de")
	var spaet: Dictionary = trigger.register_tap(4000, "de")
	assert_false(bool(spaet["triggered"]), "Fenster von 1,5 s ist abgelaufen")
	assert_eq(int(spaet["count"]), 1, "verfallene Serie beginnt bei 1")


func test_falsche_sprache_zaehlt_als_fehlversuch() -> void:
	var trigger := DevTrigger.new()
	for i in 3:
		var result: Dictionary = trigger.register_tap(1000 + i * 100, "en")
		assert_false(bool(result["triggered"]))
	assert_true(trigger.is_blocked(1400), "3 Fehlversuche = 10 s Cooldown")
	var blocked: Dictionary = trigger.register_tap(1500, "de")
	assert_true(int(blocked["blocked_ms"]) > 0, "im Cooldown zaehlt nichts")
	assert_false(trigger.is_blocked(1300 + DevTrigger.COOLDOWN_MS + 1))
	var danach: Dictionary = trigger.register_tap(1300 + DevTrigger.COOLDOWN_MS + 100, "de")
	assert_eq(int(danach["count"]), 1, "nach dem Cooldown geht es normal weiter")


func test_reset() -> void:
	var trigger := DevTrigger.new()
	trigger.register_tap(1000, "de")
	trigger.register_tap(1100, "de")
	trigger.reset()
	var next: Dictionary = trigger.register_tap(1200, "de")
	assert_eq(int(next["count"]), 1, "Reset verwirft die Serie")


func test_dialog_halten_bestaetigt() -> void:
	var dialog := DevUnlockDialog.new()
	tree.root.add_child(dialog)
	dialog.set_process(false)
	var confirmed: Array = []
	var cancelled: Array = []
	dialog.confirmed.connect(func() -> void: confirmed.append(true))
	dialog.cancelled.connect(func() -> void: cancelled.append(true))
	dialog._on_hold_down()
	dialog._process(1.0)
	assert_true(confirmed.is_empty(), "1 s halten reicht nicht")
	assert_almost(dialog.hold_progress(), 0.5, 0.01)
	dialog._on_hold_up()
	assert_almost(dialog.hold_progress(), 0.0, 0.001, "Loslassen setzt zurueck")
	dialog._on_hold_down()
	dialog._process(1.0)
	dialog._process(1.1)
	assert_eq(confirmed.size(), 1, "2 s halten bestaetigt")
	assert_true(cancelled.is_empty())
	await wait_frames(2)


func test_dialog_abbrechen() -> void:
	var dialog := DevUnlockDialog.new()
	tree.root.add_child(dialog)
	dialog.set_process(false)
	var confirmed: Array = []
	var cancelled: Array = []
	dialog.confirmed.connect(func() -> void: confirmed.append(true))
	dialog.cancelled.connect(func() -> void: cancelled.append(true))
	var cancel_btn := dialog.find_child("CancelButton", true, false) as Button
	assert_true(cancel_btn != null, "Abbrechen-Button existiert")
	if cancel_btn != null:
		cancel_btn.pressed.emit()
	assert_eq(cancelled.size(), 1)
	assert_true(confirmed.is_empty())
	await wait_frames(2)
