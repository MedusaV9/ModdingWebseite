extends TestCase
## REST-4 — Offline-Codes (EVAL Rang 11): pure CodesEngine (Normalisierung,
## Einlösen inkl. Fehlerfälle + Einmaligkeit, Fehlversuch-Sperre, Buff-Uhr)
## und der CodesScreen headless (Erfolgs-Feier bucht Münzen + Verlauf,
## klare Fehlermeldungen, Sperr-Anzeige).

const SaveSchema := preload("res://scripts/state/save_schema.gd")

const NOW := 1700000000000


## GameState-Double: dotted get/set + update(mutator) wie /root/GameState.
class FakeGameState:
	extends RefCounted
	var s: Dictionary = {}
	var slices_notified: Array[String] = []

	func _init() -> void:
		s = SaveSchema.default_state(1700000000000)

	func state() -> Dictionary:
		return s

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var node: Variant = s
		for part in path.split("."):
			if node is Dictionary and (node as Dictionary).has(part):
				node = node[part]
			else:
				return fallback
		return node

	func set_value(path: String, wert: Variant) -> void:
		var teile := path.split(".")
		var node: Dictionary = s
		for i in teile.size() - 1:
			if not (node.get(teile[i]) is Dictionary):
				node[teile[i]] = {}
			node = node[teile[i]]
		node[teile[teile.size() - 1]] = wert

	func update(mutator: Callable) -> void:
		mutator.call(s)

	func notify_slice_changed(slice_id: String) -> void:
		slices_notified.append(slice_id)


## ------------------------------------------------------ CodesEngine (pur)


func test_normalize() -> void:
	assert_eq(CodesEngine.normalize("  Ich LIE3B  Dich \n"), "ichlie3bdich")
	assert_eq(CodesEngine.normalize("update\tLiebe"), "updateliebe")
	assert_eq(CodesEngine.normalize(42), "", "Nicht-Strings werden leer")
	assert_eq(CodesEngine.normalize("   "), "", "nur Weißraum wird leer")


func test_redeem_erfolg_und_einmalig() -> void:
	var state := {}
	var attempts: Array = []
	var result := CodesEngine.redeem(state, " ICH lie3b dich ", NOW, attempts)
	assert_true(bool(result["ok"]), "bekannter Code löst ein")
	assert_eq(str((result["code"] as Dictionary)["id"]), "herzGooby")
	assert_true((state["codes"]["redeemed"] as Dictionary).has("herzGooby"), "Einlöse-Latch sitzt")
	var nochmal := CodesEngine.redeem(state, "ichlie3bdich", NOW + 1000, attempts)
	assert_false(bool(nochmal["ok"]))
	assert_eq(str(nochmal["reason"]), "already", "once-Code nur einmal")
	assert_eq(attempts.size(), 0, "gültige Eingaben zählen nicht als Fehlversuch")


func test_redeem_unbekannt_sperrt_nach_fuenf() -> void:
	var state := {}
	var attempts: Array = []
	for i in CodesEngine.LOCK_AFTER - 1:
		var r := CodesEngine.redeem(state, "quatsch%d" % i, NOW + i * 1000, attempts)
		assert_eq(str(r["reason"]), "unknown")
	assert_eq(int((state["codes"] as Dictionary).get("lockUntil", 0)), 0, "noch keine Sperre")
	var fuenfter := CodesEngine.redeem(state, "quatsch4", NOW + 4000, attempts)
	assert_eq(str(fuenfter["reason"]), "unknown", "der 5. Versuch meldet noch unknown")
	assert_true(int((state["codes"] as Dictionary)["lockUntil"]) > NOW, "5. Fehlversuch sperrt")
	var gesperrt := CodesEngine.redeem(state, "ichlie3bdich", NOW + 5000, attempts)
	assert_eq(str(gesperrt["reason"]), "locked", "während der Sperre geht NICHTS")
	var nach_ablauf := CodesEngine.redeem(
		state, "ichlie3bdich", NOW + 4000 + CodesEngine.LOCK_SEC * 1000 + 1, attempts
	)
	assert_true(bool(nach_ablauf["ok"]), "nach Sperr-Ablauf löst der Code ein")


func test_fehlversuchs_fenster_rollt() -> void:
	var state := {}
	var attempts: Array = []
	for i in 4:
		CodesEngine.redeem(state, "alt%d" % i, NOW + i * 1000, attempts)
	# Der 5. Versuch liegt WEIT hinter dem 60-s-Fenster: alte Versuche
	# fallen raus, es wird NICHT gesperrt.
	var spaeter := NOW + (CodesEngine.LOCK_WINDOW_SEC + 10) * 1000
	CodesEngine.redeem(state, "neu", spaeter, attempts)
	assert_eq(int((state["codes"] as Dictionary).get("lockUntil", 0)), 0, "Fenster rollt")
	assert_eq(attempts.size(), 1, "nur der frische Versuch bleibt im Fenster")


func test_buff_und_sperr_uhren() -> void:
	var state := {"codes": {"redeemed": {}, "lockUntil": 0, "buffs": {"doubleCoinsUntil": 0}}}
	assert_false(CodesEngine.is_double_coins_active(state, NOW))
	state["codes"]["buffs"]["doubleCoinsUntil"] = NOW + 60000
	assert_true(CodesEngine.is_double_coins_active(state, NOW))
	assert_eq(CodesEngine.remaining_ms(state, NOW), 60000)
	assert_false(CodesEngine.is_double_coins_active(state, NOW + 60001), "Buff läuft ab")
	state["codes"]["lockUntil"] = NOW + 30000
	assert_eq(CodesEngine.lock_remaining_ms(state, NOW), 30000)
	assert_eq(CodesEngine.lock_remaining_ms(state, NOW + 30001), 0)


## ------------------------------------------------------ CodesScreen (UI)


func test_codes_screen_erfolg_bucht_muenzen_und_verlauf() -> void:
	var gs := FakeGameState.new()
	gs.s["economy"]["coins"] = 100
	var screen: CodesScreen = CodesScreen.new()
	screen.gs_override = gs
	screen.now_override = NOW
	screen.auto_navigate = false
	tree.root.add_child(screen)
	await wait_frames(2)
	screen.set_input_text("ich lie3b dich")
	var result := screen.redeem_now()
	assert_true(bool(result.get("ok", false)), "Einlösen klappt")
	assert_eq(int(gs.get_value("economy.coins", 0)), 150, "50 Münzen aus dem Code")
	assert_eq(int(gs.get_value("achievements.counters.codesRedeemed", 0)), 1, "Zähler steigt")
	assert_true(gs.slices_notified.has("codes"), "Slice-Notify für die Sticker")
	var eintrag := screen.find_child("Verlauf_herzGooby", true, false)
	assert_true(eintrag != null, "Verlauf zeigt den eingelösten Code")
	screen.queue_free()
	await wait_frames(1)


func test_codes_screen_fehlerfaelle() -> void:
	var gs := FakeGameState.new()
	var screen: CodesScreen = CodesScreen.new()
	screen.gs_override = gs
	screen.now_override = NOW
	screen.auto_navigate = false
	tree.root.add_child(screen)
	await wait_frames(2)
	screen.set_input_text("   ")
	assert_eq(str(screen.redeem_now()["reason"]), "empty", "leere Eingabe")
	assert_eq(screen.feedback_text(), I18nService.t("codes.fehler.leer"))
	screen.set_input_text("gibtsnicht")
	assert_eq(str(screen.redeem_now()["reason"]), "unknown", "unbekannter Code")
	assert_eq(screen.feedback_text(), I18nService.t("codes.fehler.unbekannt"))
	screen.set_input_text("update liebe")
	assert_true(bool(screen.redeem_now()["ok"]), "Buff-Code löst ein")
	assert_true(
		int(gs.get_value("codes.buffs.doubleCoinsUntil", 0)) == NOW + 10 * 60 * 1000,
		"Doppel-Münzen-Buff endet nach 10 Minuten"
	)
	screen.set_input_text("updateliebe")
	assert_eq(str(screen.redeem_now()["reason"]), "already", "einmalige Codes bleiben einmalig")
	assert_eq(screen.feedback_text(), I18nService.t("codes.fehler.schon"))
	screen.queue_free()
	await wait_frames(1)


func test_codes_screen_sperre_zeigt_countdown() -> void:
	var gs := FakeGameState.new()
	var screen: CodesScreen = CodesScreen.new()
	screen.gs_override = gs
	screen.now_override = NOW
	screen.auto_navigate = false
	tree.root.add_child(screen)
	await wait_frames(2)
	for i in CodesEngine.LOCK_AFTER:
		screen.set_input_text("falsch%d" % i)
		screen.redeem_now()
	assert_true(int(gs.get_value("codes.lockUntil", 0)) > NOW, "Sperre sitzt im Save")
	screen.set_input_text("ichlie3bdich")
	assert_eq(str(screen.redeem_now()["reason"]), "locked", "gesperrt bleibt gesperrt")
	assert_true(screen.feedback_text().length() > 0, "Sperr-Meldung mit Countdown wird angezeigt")
	screen.queue_free()
	await wait_frames(1)
