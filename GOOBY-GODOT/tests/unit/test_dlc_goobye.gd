extends TestCase
## G5/P24 DLC-GOOBYE-A — Integration des „Goo und Bye“: Hub-Status nach dem
## Ranch-Muster (installiert/verfügbar/gesperrt), Kauf-Gate GoobyeKauf
## (atomar, Startlager aus dem Pack), Save-Slice dlc.goobye.* (GoobyeState),
## Angebots-Sheet (GoobyeOffer), Routen-Anmeldung, DE↔EN-String-Parität und
## die Laden-Szene: mountet headless, Story-Beat beim Erstbetreten, Regal-Tap,
## kompletter Markttag bis zur Kassensturz-Karte, Geometrie-Grundcheck.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")
const LadenSzene := preload("res://scripts/dlc/goobye/laden_scene.tscn")

var _dir_seq := 0


## GameState-Double NUR fürs Lesen (Hub-Status): dotted get_value/set_value.
class FakeGameState:
	extends RefCounted
	var s: Dictionary = {}

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


class FakeRouter:
	extends RefCounted
	var routen: Dictionary = {}
	var ziele: Array = []

	func register_route(route: StringName, szene: String) -> void:
		routen[route] = szene

	func goto(route: StringName, params: Dictionary = {}) -> void:
		ziele.append({"route": route, "params": params})


func _fake(level: int, gekauft: bool) -> FakeGameState:
	var gs := FakeGameState.new()
	gs.set_value("progression.level", level)
	gs.set_value("dlc.goobye.gekauft", gekauft)
	return gs


func _fresh_gs(level: int, coins: int) -> Node:
	GoobyeState.register_slice()
	_dir_seq += 1
	var dir := "user://goobye_tests/%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	gs.set_value("progression.level", level)
	gs.set_value("economy.coins", coins)
	return gs


func _teardown_gs(gs: Node) -> void:
	gs.free()
	SaveSchema.unregister_slice(GoobyeState.SLICE_ID)
	GoobyeState.reset_for_tests()
	GoobyeKatalog.registry_override = null
	GoobyeKatalog.reset_cache()


## ------------------------------------------------------------ Hub-Status


func test_hub_status_goobye_nach_ranch_muster() -> void:
	DlcKatalog.reset_cache()
	GoobyeKatalog.reset_cache()
	var dlc := DlcKatalog.eintrag("goo_und_bye")
	assert_false(dlc.is_empty(), "Goo-und-Bye-Eintrag über den Katalog lesbar")
	assert_eq(str(dlc.get("status", "")), "verfuegbar", "redaktionell verfügbar (Pack)")
	assert_eq(
		DlcKatalog.status_fuer(dlc, _fake(20, true)),
		DlcKatalog.STATUS_INSTALLIERT,
		"gekauft → installiert"
	)
	assert_eq(
		DlcKatalog.status_fuer(dlc, _fake(GoobyeKatalog.freischalt_level(), false)),
		DlcKatalog.STATUS_VERFUEGBAR,
		"Level 12, nicht gekauft → verfügbar"
	)
	assert_eq(
		DlcKatalog.status_fuer(dlc, _fake(GoobyeKatalog.freischalt_level() - 1, false)),
		DlcKatalog.STATUS_GESPERRT,
		"Level < 12 → gesperrt"
	)
	var text := DlcKatalog.unlock_text(dlc)
	assert_true(text.contains(str(GoobyeKatalog.freischalt_level())), "Level eingesetzt")
	assert_true(text.contains(str(GoobyeKatalog.preis())), "Preis eingesetzt")
	assert_false(text.contains("{"), "keine offenen Platzhalter")


func test_screen_detail_goobye_knoepfe() -> void:
	DlcKatalog.reset_cache()
	var screen := DlcScreen.new()
	screen.gs_override = _fake(20, false)
	screen.auto_navigate = false
	tree.root.add_child(screen)
	await wait_frames(2)
	# Verfügbar → Angebots-Knopf mit Goobye-eigenem Text.
	var detail := screen.oeffne_detail("goo_und_bye")
	var knopf: Button = detail.get_meta(DlcScreen.META_AKTION, null)
	assert_true(knopf != null and not knopf.disabled, "Angebots-Knopf aktiv")
	assert_eq(knopf.text, I18nService.t("dlc_goobye.knopf.angebot"))
	detail.queue_free()
	screen.queue_free()
	await wait_frames(1)
	# Gekauft → „Laden aufschließen!“ (Spielen-Knopf).
	var screen2 := DlcScreen.new()
	screen2.gs_override = _fake(20, true)
	screen2.auto_navigate = false
	tree.root.add_child(screen2)
	await wait_frames(2)
	var detail2 := screen2.oeffne_detail("goo_und_bye")
	var knopf2: Button = detail2.get_meta(DlcScreen.META_AKTION, null)
	assert_true(knopf2 != null and not knopf2.disabled, "Spielen-Knopf aktiv")
	assert_eq(knopf2.text, I18nService.t("dlc_goobye.knopf.zum_laden"))
	detail2.queue_free()
	screen2.queue_free()
	await wait_frames(1)


## ------------------------------------------------------------ Kauf & State


func test_kauf_gate_und_atomik() -> void:
	GoobyeKatalog.reset_cache()
	var gs := _fresh_gs(GoobyeKatalog.freischalt_level() - 1, 99999)
	assert_eq(GoobyeKauf.check(gs), GoobyeKauf.RESULT_LOCKED, "unter Level 12 gesperrt")
	assert_eq(GoobyeKauf.kaufe(gs), GoobyeKauf.RESULT_LOCKED)
	assert_eq(gs.get_value("economy.coins"), 99999, "keine Abbuchung im Gesperrt-Fall")
	assert_eq(gs.get_value("dlc.goobye.gekauft"), false)
	_teardown_gs(gs)
	var arm := _fresh_gs(12, GoobyeKatalog.preis() - 1)
	assert_eq(GoobyeKauf.kaufe(arm), GoobyeKauf.RESULT_BROKE, "zu wenig Münzen blockt")
	assert_eq(arm.get_value("economy.coins"), GoobyeKatalog.preis() - 1, "unangetastet")
	assert_eq(arm.get_value("dlc.goobye.lager"), {}, "kein Startlager eingezogen")
	_teardown_gs(arm)


func test_kauf_bucht_preis_und_zieht_startlager_ein() -> void:
	GoobyeKatalog.reset_cache()
	var gs := _fresh_gs(12, GoobyeKatalog.preis() + 77)
	assert_eq(GoobyeKauf.kaufe(gs), GoobyeKauf.RESULT_OK)
	assert_eq(gs.get_value("economy.coins"), 77, "exakt der Preis wird abgebucht")
	assert_eq(gs.get_value("dlc.goobye.gekauft"), true)
	assert_true(int(gs.get_value("dlc.goobye.gekauftAm", 0)) > 0, "Kaufzeit gemerkt")
	assert_eq(
		gs.get_value("dlc.goobye.lager"),
		GoobyeKatalog.startlager(),
		"Eröffnungspaket (start-Felder) liegt im Lager"
	)
	assert_eq(GoobyeKauf.kaufe(gs), GoobyeKauf.RESULT_OWNED, "Doppelkauf blockiert")
	assert_eq(gs.get_value("economy.coins"), 77, "nur EINMAL abgebucht")
	_teardown_gs(gs)


func test_state_erstbesuch_umsatz_und_fremde_unterschluessel() -> void:
	var gs := _fresh_gs(12, 0)
	assert_true(GoobyeState.erstbesuch_merken(gs), "erster Besuch meldet true")
	assert_false(GoobyeState.erstbesuch_merken(gs), "zweiter Besuch meldet false")
	GoobyeState.umsatz_verbuchen(gs, 68)
	GoobyeState.umsatz_verbuchen(gs, 12)
	assert_eq(gs.get_value("dlc.goobye.umsatz.tage"), 2, "zwei Markttage verbucht")
	assert_eq(gs.get_value("dlc.goobye.umsatz.gestern"), 12, "letzter Tagesumsatz")
	assert_eq(gs.get_value("dlc.goobye.umsatz.gesamt"), 80, "Gesamtumsatz summiert")
	GoobyeState.lager_setzen(gs, {"apple": 3, "kaputt": 0})
	assert_eq(gs.get_value("dlc.goobye.lager"), {"apple": 3}, "0-Mengen heilen raus")
	# Geschwister-DLCs im dlc-Slice bleiben beim Normalisieren VERBATIM.
	var slice := GoobyeState.normalize_slice({"zukunft": {"x": 1}, "goobye": "kaputt"})
	assert_eq(slice["zukunft"], {"x": 1}, "fremder Unterschlüssel unangetastet")
	assert_eq(slice["goobye"]["gekauft"], false, "eigener Unterschlüssel geheilt")
	_teardown_gs(gs)


## ------------------------------------------------------------ Angebot & Routen


func test_angebot_sheet_kauf_und_spaeter() -> void:
	GoobyeKatalog.reset_cache()
	GoobyeOffer.auto_navigate = false
	var host := Control.new()
	tree.root.add_child(host)
	# Fail-closed: gekauft oder Level zu niedrig → kein Sheet.
	assert_true(GoobyeOffer.zeige(host, _fake(5, false)) == null, "Level-Gate blockt Sheet")
	assert_true(GoobyeOffer.zeige(host, _fake(20, true)) == null, "gekauft blockt Sheet")
	# Zu wenig Münzen: Kauf-Klick lässt alles stehen + Klartext-Hinweis.
	var arm := _fresh_gs(12, 3)
	var sheet := GoobyeOffer.zeige(host, arm)
	assert_true(sheet != null, "Sheet öffnet ab Level 12")
	await wait_frames(1)
	var kaufen: Button = sheet.get_meta(GoobyeOffer.META_KAUFEN, null)
	var hinweis: Label = sheet.get_meta(GoobyeOffer.META_HINWEIS, null)
	kaufen.pressed.emit()
	await wait_frames(1)
	assert_eq(arm.get_value("economy.coins"), 3, "Münzen unangetastet")
	assert_true(hinweis.text.contains(str(GoobyeKatalog.preis())), "Zu-wenig-Zeile nennt den Preis")
	# „Später“ merkt den Stand.
	var spaeter: Button = sheet.get_meta(GoobyeOffer.META_SPAETER, null)
	spaeter.pressed.emit()
	await wait_frames(1)
	assert_eq(arm.get_value("dlc.goobye.angebotVerschoben"), true, "verschoben gemerkt")
	_teardown_gs(arm)
	# Genug Münzen: Kauf-Klick kauft atomar.
	var reich := _fresh_gs(12, GoobyeKatalog.preis())
	var sheet2 := GoobyeOffer.zeige(host, reich)
	await wait_frames(1)
	var kaufen2: Button = sheet2.get_meta(GoobyeOffer.META_KAUFEN, null)
	kaufen2.pressed.emit()
	await wait_frames(1)
	assert_eq(reich.get_value("dlc.goobye.gekauft"), true, "Sheet-Kauf greift")
	assert_eq(reich.get_value("economy.coins"), 0, "Preis abgebucht")
	_teardown_gs(reich)
	GoobyeOffer.auto_navigate = true
	host.queue_free()
	await wait_frames(1)


func test_routen_anmeldung() -> void:
	var router := FakeRouter.new()
	GoobyeRouten.registriere(router)
	assert_eq(
		str(router.routen.get(GoobyeRouten.ROUTE_LADEN, "")),
		GoobyeRouten.SZENE_LADEN,
		"Laden-Route registriert"
	)
	GoobyeRouten.router_override = router
	assert_true(GoobyeRouten.fahre_zum_laden(tree, {"frisch_gekauft": true}), "Reise startet")
	GoobyeRouten.router_override = null
	assert_eq(router.ziele.size(), 1)
	assert_eq(router.ziele[0]["route"], GoobyeRouten.ROUTE_LADEN)
	assert_eq(router.ziele[0]["params"], {"frisch_gekauft": true})
	assert_true(FileAccess.file_exists(GoobyeRouten.SZENE_LADEN), "Szene-Datei existiert")


## ------------------------------------------------------------ Strings


func test_strings_de_en_paritaet() -> void:
	I18nService.reset_cache()
	var de := I18nService.table("de")
	var en := I18nService.table("en")
	var de_keys: Array = []
	for key: String in de:
		if key.begins_with("dlc_goobye."):
			de_keys.append(key)
			assert_true(en.has(key), "EN-Gegenstück fehlt: %s" % key)
			assert_false(str(de[key]).is_empty(), "DE leer: %s" % key)
			assert_false(str(en.get(key, "")).is_empty(), "EN leer: %s" % key)
	assert_true(de_keys.size() >= 30, "Domain dlc_goobye gefüllt (%d Keys)" % de_keys.size())
	for key: String in en:
		if key.begins_with("dlc_goobye."):
			assert_true(de.has(key), "DE-Gegenstück fehlt: %s" % key)
	# Jeder name_key des Sortiments löst in DE auf (Waren-Anzeige + Kasse).
	GoobyeKatalog.reset_cache()
	for ware: Dictionary in GoobyeKatalog.waren():
		assert_true(
			I18nService.has_key(str(ware.get("name_key", ""))),
			"name_key auflösbar: %s" % ware.get("name_key")
		)


## ------------------------------------------------------------ Laden-Szene


func test_laden_szene_kompletter_markttag() -> void:
	GoobyeKatalog.reset_cache()
	var gs := _fresh_gs(12, GoobyeKatalog.preis() + 100)
	assert_eq(GoobyeKauf.kaufe(gs), GoobyeKauf.RESULT_OK, "Vorbereitung: Laden gekauft")
	var lager_start := 0
	for menge: Variant in (gs.get_value("dlc.goobye.lager", {}) as Dictionary).values():
		lager_start += int(menge)
	var szene: GoobyeLadenScene = LadenSzene.instantiate()
	szene.game_state_override = gs
	szene.seed_override = 12345
	szene.tempo = 0.05
	szene.auto_navigate = false
	var enthuellt := [false]
	szene.ready_for_reveal.connect(func() -> void: enthuellt[0] = true)
	tree.root.add_child(szene)
	await wait_frames(3)
	assert_true(enthuellt[0], "ready_for_reveal nach dem Aufbau (Router-Contract)")
	# Story-Beat §1.3: Schlüsselübergabe-Karte beim ERSTEN Betreten.
	var intro: Control = szene.find_child("IntroOverlay", true, false)
	assert_true(intro != null, "Erstbesuch zeigt die Übergabe-Karte")
	assert_eq(gs.get_value("dlc.goobye.erstbesuchGesehen"), true, "Besuch gemerkt")
	var weiter: Button = szene.find_child("IntroWeiter", true, false)
	weiter.pressed.emit()
	await wait_frames(2)
	assert_true(szene.find_child("IntroOverlay", true, false) == null, "Karte schließt")
	# Regal-Tap räumt aus dem Lager ein (erste Katalog-Ware: 6 Äpfel).
	assert_eq(szene.phase, GoobyeLadenScene.PHASE_EINRAEUMEN)
	szene.slot_tippen(0)
	szene.slot_tippen(1)
	await wait_frames(1)
	var slot0: Button = szene.find_child("Slot0", true, false)
	assert_eq(slot0.text, "×6", "Slot 0 zeigt die eingeräumten Äpfel")
	# Markttag: öffnen → Kunden kaufen (Zeitraffer) → Kassensturz-Karte.
	szene.laden_oeffnen()
	assert_eq(szene.phase, GoobyeLadenScene.PHASE_OFFEN, "Tür sagt Goo!")
	var fertig := await wait_until(
		func() -> bool: return szene.phase == GoobyeLadenScene.PHASE_ABSCHLUSS, 20000
	)
	assert_true(fertig, "Markttag läuft bis zur Abschluss-Karte durch")
	assert_true(szene.find_child("AbschlussOverlay", true, false) != null, "Kassensturz da")
	var umsatz := szene.umsatz_heute
	assert_true(umsatz > 0, "mindestens ein Kunde hat gekauft (Umsatz %d)" % umsatz)
	var coins_vorher := int(gs.get_value("economy.coins"))
	var feierabend: Button = szene.find_child("Feierabend", true, false)
	feierabend.pressed.emit()
	await wait_frames(2)
	assert_eq(int(gs.get_value("economy.coins")), coins_vorher + umsatz, "Umsatz wird zu Münzen")
	assert_eq(gs.get_value("dlc.goobye.umsatz.tage"), 1, "Markttag verbucht")
	assert_eq(gs.get_value("dlc.goobye.umsatz.gestern"), umsatz)
	assert_eq(szene.phase, GoobyeLadenScene.PHASE_EINRAEUMEN, "nächster Tag beginnt")
	# Verlassen: Regal-Reste wandern verlustfrei zurück ins Lager (§1.4).
	szene.queue_free()
	await wait_frames(2)
	var lager_danach := 0
	for menge: Variant in (gs.get_value("dlc.goobye.lager", {}) as Dictionary).values():
		lager_danach += int(menge)
	# Denselben Tag nachrechnen: Slot 0 = 6 Äpfel, Slot 1 = 8 Möhren
	# (Katalog-Reihenfolge beim Einräumen) — gleicher Seed, gleiche Optionen
	# inkl. Welle B (Trend/Duft/Alwin-Sonderwunsch — 12345 ist ein
	# „ZWEI Möhren?!“-Tag, ohne Schieber/Backen: Faktoren 1.0, kein Duft).
	var verkauft := 0
	var plan := (
		GoobyeMarkttag
		. tag_planen(
			12345,
			[
				{"id": "apple", "bestand": 6, "faktor": 1.0},
				{"id": "carrot", "bestand": 8, "faktor": 1.0},
			],
			{
				"kunden_min": GoobyeLadenScene.KUNDEN_MIN,
				"kunden_max": GoobyeLadenScene.KUNDEN_MAX,
				"trend_gruppe": GoobyeMarkttag.tagestrend(12345),
				"duft_gruppe": "",
				"alwin_menge": GoobyeMarkttag.alwin_menge(12345),
			}
		)
	)
	for anzahl: Variant in (plan["verkauft"] as Dictionary).values():
		verkauft += int(anzahl)
	assert_eq(lager_danach, lager_start - verkauft, "kein Stück geht verloren")
	_teardown_gs(gs)


func test_laden_szene_geometrie_grundcheck() -> void:
	GoobyeKatalog.reset_cache()
	var gs := _fresh_gs(12, GoobyeKatalog.preis())
	GoobyeKauf.kaufe(gs)
	gs.set_value("dlc.goobye.erstbesuchGesehen", true)
	var szene: GoobyeLadenScene = LadenSzene.instantiate()
	szene.game_state_override = gs
	szene.auto_navigate = false
	tree.root.add_child(szene)
	await wait_frames(3)
	assert_true(szene.find_child("IntroOverlay", true, false) == null, "kein Intro mehr")
	var m := ScreenShell.metrics(szene.get_viewport())
	var floor_px: float = m["floor_px"]
	var canvas: Vector2 = m["canvas"]
	# Touch-Floor 44 pt auf allen Tippzielen (User-Leitidee).
	for i in 5:
		var slot: Button = szene.find_child("Slot%d" % i, true, false)
		assert_true(slot != null, "Slot-Knopf %d existiert" % i)
		assert_true(
			slot.custom_minimum_size.x >= floor_px and slot.custom_minimum_size.y >= floor_px,
			"Slot %d hält den Touch-Floor" % i
		)
		var rect := slot.get_global_rect()
		assert_true(
			rect.position.x >= -1.0 and rect.end.x <= canvas.x + 1.0,
			"Slot %d liegt horizontal im Bild" % i
		)
	# Bedienleiste mittig in der Daumenzone (unteres Drittel).
	var leiste: Control = szene.find_child("LadenKnoepfe", true, false)
	assert_true(leiste != null, "Bottom-Leiste existiert")
	var leiste_rect := leiste.get_global_rect()
	assert_true(leiste_rect.position.y > canvas.y * 0.6, "Leiste in der Daumenzone")
	var mitte := absf(leiste_rect.get_center().x - canvas.x / 2.0)
	assert_true(mitte <= canvas.x * 0.1, "Leiste horizontal mittig")
	var oeffnen: Button = szene.find_child("LadenOeffnen", true, false)
	assert_true(oeffnen.custom_minimum_size.y >= floor_px, "Öffnen-Knopf hält den Floor")
	var verlassen: Button = szene.find_child("Verlassen", true, false)
	assert_true(verlassen.get_global_rect().position.y >= 0.0, "Verlassen unter der Notch")
	szene.queue_free()
	await wait_frames(2)
	_teardown_gs(gs)
