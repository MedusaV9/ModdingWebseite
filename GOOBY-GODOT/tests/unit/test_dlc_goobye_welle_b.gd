extends TestCase
## G6/GOOBYE-B — Welle B des „Goo und Bye“: Großmarkt-Rechnung + atomarer
## Rampen-Kauf (GoobyeGrossmarkt, §4.1/§4.2), Preis-Schieber-Save +
## Gruppen→Waren-Faktoren (GoobyeState/GoobyePreis, §2.2/§4.4), Markttag-
## Optionen (Tagestrend, Backecken-Duft, Alwins Sonderwunsch — alles
## deterministisch, injizierte Seeds statt OS-Uhr), Alwin-Streak mit
## Trinkgeld (GoobyeAlwin, §6.3), Backstation-Tagesdeckel (GoobyeBackofen,
## §7.1) und die Szenen headless: Großmarkt-Fahrt bis zur Einräum-Karte,
## Laden-Stationen (Preise-Sheet, Backen) inkl. Touch-Floor-Konformität.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")
const GrossmarktSzene := preload("res://scripts/dlc/goobye/grossmarkt_scene.tscn")
const LadenSzene := preload("res://scripts/dlc/goobye/laden_scene.tscn")

const GOLDEN_SEED := 20260801

## Festes Golden-Sortiment (wie test_dlc_goobye_logik.gd).
const GOLDEN_SORTIMENT := [
	{"id": "carrot", "bestand": 8},
	{"id": "apple", "bestand": 6},
	{"id": "cookie", "bestand": 5, "faktor": 0.9},
	{"id": "cheese", "bestand": 4, "faktor": 1.2},
	{"id": "bread", "bestand": 5},
]

var _dir_seq := 0


func _fresh_gs(level: int, coins: int) -> Node:
	GoobyeState.register_slice()
	_dir_seq += 1
	var dir := "user://goobye_welle_b/%d_%d" % [Time.get_ticks_usec(), _dir_seq]
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


func _lager_von(gs: Node) -> Dictionary:
	var raw: Variant = gs.get_value("dlc.goobye.lager", {})
	return raw if raw is Dictionary else {}


## ------------------------------------------------------- Großmarkt-Preise


func test_grossmarkt_rechnung() -> void:
	GoobyeKatalog.reset_cache()
	# Rampen-Tagesangebot: deterministisch und immer eine echte Gruppe.
	var gruppen_ids: Array = []
	for gruppe: Dictionary in GoobyeKatalog.gruppen():
		gruppen_ids.append(str(gruppe["id"]))
	for seed_wert in [1, 7, GOLDEN_SEED, 999]:
		var angebot := GoobyeGrossmarkt.tagesangebot_gruppe(seed_wert)
		assert_eq(
			angebot,
			GoobyeGrossmarkt.tagesangebot_gruppe(seed_wert),
			"Tagesangebot stabil (Seed %d)" % seed_wert
		)
		assert_true(gruppen_ids.has(angebot), "Tagesangebot ist eine Katalog-Gruppe")
	# Stückpreis an der Rampe = Einkaufspreis; Angebots-Gruppe −15 %.
	var apple := GoobyeKatalog.ware("apple")
	var bread := GoobyeKatalog.ware("bread")
	assert_eq(GoobyeGrossmarkt.stueckpreis(apple), 4, "Rampe = Einkaufspreis (60 % von 6)")
	assert_eq(GoobyeGrossmarkt.stueckpreis(apple, "backwaren"), 4, "fremde Gruppe unberührt")
	assert_eq(GoobyeGrossmarkt.stueckpreis(bread), 6)
	assert_eq(GoobyeGrossmarkt.stueckpreis(bread, "backwaren"), 5, "6 × 0.85 → 5")
	# Staffel (§4.1): ab 10 Stück −5 % auf die Zeile.
	assert_eq(GoobyeGrossmarkt.palette_preis(apple, 9), 36, "9 × 4 ohne Staffel")
	assert_eq(GoobyeGrossmarkt.palette_preis(apple, 10), 38, "40 × 0.95 → 38")
	assert_eq(GoobyeGrossmarkt.palette_preis(apple, 0), 0)
	assert_eq(GoobyeGrossmarkt.palette_preis({}, 5), 0, "unbekannte Ware kostet nichts")
	# Korb-Summe + Kisten: nur Katalog-Waren zählen (zahlen = laden = ankommen).
	var korb := {"apple": 2, "carrot": 1, "gibtsnicht": 5}
	assert_eq(GoobyeGrossmarkt.korb_summe(korb), 11, "2×4 + 1×3")
	assert_eq(GoobyeGrossmarkt.korb_kisten(korb), 3, "Unfug-Ids belegen keine Kiste")
	# Kofferraum-Deckel (§4.2): Standard-Kombi = 24 Kisten.
	assert_true(GoobyeGrossmarkt.passt_in_kofferraum({"apple": 24}))
	assert_false(GoobyeGrossmarkt.passt_in_kofferraum({"apple": 25}))


func test_grossmarkt_kauf_atomar() -> void:
	GoobyeKatalog.reset_cache()
	var gs := _fresh_gs(12, 100)
	# Fail-closed-Reihenfolge: leer → Kofferraum → Münzen.
	assert_eq(str(GoobyeGrossmarkt.kaufen(gs, {})["grund"]), GoobyeGrossmarkt.RESULT_LEER)
	assert_eq(
		str(GoobyeGrossmarkt.kaufen(gs, {"apple": 30})["grund"]),
		GoobyeGrossmarkt.RESULT_KOFFERRAUM,
		"30 Kisten passen nicht in 24"
	)
	var teuer := GoobyeGrossmarkt.kaufen(gs, {"bread": 20})
	assert_eq(str(teuer["grund"]), GoobyeGrossmarkt.RESULT_BROKE, "114 > 100 Münzen")
	assert_eq(int(gs.get_value("economy.coins")), 100, "Fehlkauf ändert NICHTS")
	assert_true(_lager_von(gs).is_empty(), "Fehlkauf legt nichts ins Lager")
	# Erfolgs-Kauf: Münzen runter UND Lager rauf (ein update-Block).
	var ergebnis := GoobyeGrossmarkt.kaufen(gs, {"apple": 2, "carrot": 1, "gibtsnicht": 2})
	assert_true(bool(ergebnis["ok"]))
	assert_eq(int(ergebnis["kosten"]), 11)
	assert_eq(int(ergebnis["kisten"]), 3)
	assert_eq(int(gs.get_value("economy.coins")), 89, "100 − 11")
	assert_eq(_lager_von(gs), {"apple": 2, "carrot": 1}, "nur echte Waren kommen an")
	_teardown_gs(gs)


## ---------------------------------------------------------- Preis-Schieber


func test_preis_schieber_save_und_faktoren() -> void:
	GoobyeKatalog.reset_cache()
	var gs := _fresh_gs(12, 0)
	GoobyeState.preis_faktor_setzen(gs, "gemuese", 1.2)
	assert_almost(float(GoobyeState.preise_von(gs).get("gemuese", 0.0)), 1.2, 1e-6)
	GoobyeState.preis_faktor_setzen(gs, "gemuese", 1.0)
	assert_false(GoobyeState.preise_von(gs).has("gemuese"), "Richtwert wird NICHT gespeichert")
	GoobyeState.preis_faktor_setzen(gs, "obst", 9.9)
	assert_almost(
		float(GoobyeState.preise_von(gs).get("obst", 0.0)),
		GoobyeState.FAKTOR_HEIL_MAX,
		1e-6,
		"grobe Heil-Klemme beim Schreiben"
	)
	_teardown_gs(gs)
	# Self-Heal beim Laden: Unfug fliegt raus, Werte werden geklemmt.
	var heil := GoobyeState.normalize_goobye(
		{"preise": {"gemuese": 99.0, "obst": 1.0}, "alwin": "unfug", "backofen": {"chargen": -3}}
	)
	assert_almost(float((heil["preise"] as Dictionary).get("gemuese", 0.0)), 1.5, 1e-6)
	assert_false((heil["preise"] as Dictionary).has("obst"), "1.0 wird herausgeheilt")
	assert_eq(int((heil["alwin"] as Dictionary).get("streak", -1)), 0, "Alwin-Unfug geheilt")
	assert_eq(int((heil["backofen"] as Dictionary).get("chargen", -1)), 0, "Chargen ≥ 0")
	# Gruppen-Schieber → Waren-Faktoren (nur Nicht-Richtwert, geklemmt).
	assert_true(GoobyePreis.ware_faktoren({}).is_empty(), "ohne Schieber keine Faktoren")
	var faktoren := GoobyePreis.ware_faktoren({"gemuese": 1.2, "obst": 1.4})
	assert_almost(float(faktoren.get("carrot", 0.0)), 1.2, 1e-6, "Möhre erbt Gemüse-Faktor")
	assert_almost(float(faktoren.get("apple", 0.0)), 1.3, 1e-6, "Klemme auf ±30 %")
	assert_false(faktoren.has("bread"), "Richtwert-Gruppen bleiben weg")


## ------------------------------------------------- Markttag Welle-B-Optionen


func test_markttag_optionen_neutral_bleibt_golden() -> void:
	GoobyeKatalog.reset_cache()
	var ohne := GoobyeMarkttag.tag_planen(GOLDEN_SEED, GOLDEN_SORTIMENT)
	var neutral := GoobyeMarkttag.tag_planen(
		GOLDEN_SEED, GOLDEN_SORTIMENT, {"trend_gruppe": "", "duft_gruppe": "", "alwin_menge": 1}
	)
	assert_eq(str(ohne), str(neutral), "neutrale Optionen = byte-identischer Welle-A-Plan")


func test_markttag_tagestrend_und_sonderwunsch() -> void:
	GoobyeKatalog.reset_cache()
	var gruppen_ids: Array = []
	for gruppe: Dictionary in GoobyeKatalog.gruppen():
		gruppen_ids.append(str(gruppe["id"]))
	for seed_wert in [1, 7, GOLDEN_SEED, 999]:
		var trend := GoobyeMarkttag.tagestrend(seed_wert)
		assert_eq(trend, GoobyeMarkttag.tagestrend(seed_wert), "Trend stabil (Seed %d)" % seed_wert)
		assert_true(gruppen_ids.has(trend), "Trend ist eine Katalog-Gruppe")
	# Sonderwunsch-Takt: jeder 5. Seed ist ein „ZWEI Möhren?!“-Tag.
	assert_eq(GoobyeMarkttag.alwin_menge(5), 2)
	assert_eq(GoobyeMarkttag.alwin_menge(12345), 2)
	assert_eq(GoobyeMarkttag.alwin_menge(GOLDEN_SEED), 1)
	assert_eq(GoobyeMarkttag.alwin_menge(7), 1)
	# Am Sonderwunsch-Tag kauft Alwin GENAU 2 Möhren (Bestand reicht).
	var plan := GoobyeMarkttag.tag_planen(GOLDEN_SEED, GOLDEN_SORTIMENT, {"alwin_menge": 2})
	var alwin: Dictionary = plan["bons"][0]
	assert_eq(str(alwin["archetyp"]), "alwin")
	assert_eq(
		alwin["positionen"],
		[{"ware": "carrot", "preis": 5}, {"ware": "carrot", "preis": 5}],
		"heute ZWEI Möhren?!"
	)
	assert_eq(int(alwin["summe"]), 10)


func test_markttag_trend_und_duft_monoton() -> void:
	GoobyeKatalog.reset_cache()
	# Trend-/Duft-Boni sind additiv auf die Griff-Chance: MIT Bonus wird nie
	# weniger verkauft als ohne (über Seeds und alle Gruppen geprüft).
	for seed_wert in [3, 11, 77, 2024]:
		var basis := _stueckzahl(GoobyeMarkttag.tag_planen(seed_wert, GOLDEN_SORTIMENT))
		for gruppe: Dictionary in GoobyeKatalog.gruppen():
			var gruppe_id := str(gruppe["id"])
			var mit_trend := _stueckzahl(
				GoobyeMarkttag.tag_planen(seed_wert, GOLDEN_SORTIMENT, {"trend_gruppe": gruppe_id})
			)
			var mit_duft := _stueckzahl(
				GoobyeMarkttag.tag_planen(seed_wert, GOLDEN_SORTIMENT, {"duft_gruppe": gruppe_id})
			)
			assert_true(
				mit_trend >= basis,
				(
					"Trend %s ⇒ nie weniger (Seed %d: %d vs %d)"
					% [gruppe_id, seed_wert, mit_trend, basis]
				)
			)
			assert_true(
				mit_duft >= basis,
				(
					"Duft %s ⇒ nie weniger (Seed %d: %d vs %d)"
					% [gruppe_id, seed_wert, mit_duft, basis]
				)
			)


func _stueckzahl(plan: Dictionary) -> int:
	var summe := 0
	for anzahl: Variant in (plan["verkauft"] as Dictionary).values():
		summe += int(anzahl)
	return summe


## ------------------------------------------------------------ Alwin-Ausbau


func test_alwin_sprueche_und_streak() -> void:
	# Sprüche: deterministisch, immer im Key-Fenster 1..SPRUECHE.
	for seed_wert in range(0, 20):
		var key := GoobyeAlwin.spruch_key(seed_wert)
		assert_eq(key, GoobyeAlwin.spruch_key(seed_wert), "Spruch stabil (Seed %d)" % seed_wert)
		assert_true(key.begins_with("dlc_goobye.alwin.spruch_"), "Key-Schema")
		var nummer := int(key.trim_prefix("dlc_goobye.alwin.spruch_"))
		assert_true(nummer >= 1 and nummer <= GoobyeAlwin.SPRUECHE, "Nummer im Fenster")
	assert_ne(GoobyeAlwin.spruch_key(0), GoobyeAlwin.spruch_key(3), "Abwechslung ist drin")
	# Trinkgeld-Kurve: jeder 3. Streak-Tag.
	assert_eq(GoobyeAlwin.belohnung_fuer(0), 0)
	assert_eq(GoobyeAlwin.belohnung_fuer(1), 0)
	assert_eq(GoobyeAlwin.belohnung_fuer(3), GoobyeAlwin.BELOHNUNG_MUENZEN)
	assert_eq(GoobyeAlwin.belohnung_fuer(4), 0)
	assert_eq(GoobyeAlwin.belohnung_fuer(6), GoobyeAlwin.BELOHNUNG_MUENZEN)
	# Streak-Verbuchung auf echtem GameState: 3× bedient → Trinkgeld, dann
	# ein leerer Tag → Streak fällt, Best bleibt.
	var gs := _fresh_gs(12, 50)
	assert_eq(int(GoobyeAlwin.verbuchen(gs, true)["streak"]), 1)
	assert_eq(int(GoobyeAlwin.verbuchen(gs, true)["streak"]), 2)
	var dritter := GoobyeAlwin.verbuchen(gs, true)
	assert_eq(int(dritter["streak"]), 3)
	assert_eq(int(dritter["belohnung"]), GoobyeAlwin.BELOHNUNG_MUENZEN, "Trinkgeld am 3. Tag")
	assert_eq(int(gs.get_value("economy.coins")), 50 + GoobyeAlwin.BELOHNUNG_MUENZEN)
	var leer := GoobyeAlwin.verbuchen(gs, false)
	assert_eq(int(leer["streak"]), 0, "leeres Regal reißt die Streak")
	assert_eq(int(leer["best"]), 3, "Best bleibt stehen")
	assert_eq(int(leer["belohnung"]), 0)
	var stand := GoobyeAlwin.stand_von(gs)
	assert_eq(int(stand["bedientGesamt"]), 3, "bedientGesamt zählt nur bediente Tage")
	assert_eq(int(gs.get_value("economy.coins")), 50 + GoobyeAlwin.BELOHNUNG_MUENZEN)
	_teardown_gs(gs)


## ------------------------------------------------------------ Backstation


func test_backofen_tagesdeckel_und_duft() -> void:
	GoobyeKatalog.reset_cache()
	assert_eq(GoobyeBackofen.kosten(), 9, "0.5 × EK(Brot 6) × 3 Stück")
	var gs := _fresh_gs(12, 100)
	assert_true(GoobyeBackofen.kann_backen(gs, "2026-08-01"))
	assert_false(GoobyeBackofen.duft_aktiv(gs, "2026-08-01"), "ohne Charge kein Duft")
	var erste := GoobyeBackofen.backen(gs, "2026-08-01")
	assert_true(bool(erste["ok"]))
	assert_eq(int(erste["menge"]), GoobyeBackofen.BROT_JE_CHARGE)
	assert_eq(int(erste["chargen"]), 1)
	assert_true(bool(erste["duft"]))
	assert_eq(int(gs.get_value("economy.coins")), 91, "Selbstkosten abgebucht")
	assert_eq(int(_lager_von(gs).get("bread", 0)), 3, "Brot liegt im Lager")
	assert_true(GoobyeBackofen.duft_aktiv(gs, "2026-08-01"), "Duft hängt im Laden")
	assert_false(GoobyeBackofen.duft_aktiv(gs, "2026-08-02"), "…aber nur heute")
	# Tagesdeckel: nach MAX_CHARGEN ist der Ofen fertig — ohne Abbuchung.
	GoobyeBackofen.backen(gs, "2026-08-01")
	GoobyeBackofen.backen(gs, "2026-08-01")
	assert_false(GoobyeBackofen.kann_backen(gs, "2026-08-01"))
	var voll := GoobyeBackofen.backen(gs, "2026-08-01")
	assert_false(bool(voll["ok"]))
	assert_eq(str(voll["grund"]), GoobyeBackofen.RESULT_AUSGEBACKEN)
	assert_eq(int(gs.get_value("economy.coins")), 73, "Fehlversuch bucht nichts ab")
	assert_eq(int(_lager_von(gs).get("bread", 0)), 9)
	# Neuer Tag: Zähler frisch, Backen geht wieder.
	assert_eq(GoobyeBackofen.chargen_heute(gs, "2026-08-02"), 0)
	var morgen := GoobyeBackofen.backen(gs, "2026-08-02")
	assert_true(bool(morgen["ok"]))
	assert_eq(int(morgen["chargen"]), 1, "Tageswechsel setzt die Chargen zurück")
	# Pleite-Fall: zu wenig Münzen → gar nichts passiert.
	gs.set_value("economy.coins", 5)
	var pleite := GoobyeBackofen.backen(gs, "2026-08-02")
	assert_false(bool(pleite["ok"]))
	assert_eq(str(pleite["grund"]), GoobyeBackofen.RESULT_BROKE)
	assert_eq(int(_lager_von(gs).get("bread", 0)), 12)
	_teardown_gs(gs)


## ------------------------------------------------------- Großmarkt-Szene


func test_grossmarkt_szene_fahrt_und_kauf() -> void:
	GoobyeKatalog.reset_cache()
	var gs := _fresh_gs(12, 100)
	var szene: GoobyeGrossmarktScene = GrossmarktSzene.instantiate()
	szene.game_state_override = gs
	szene.seed_override = 777
	szene.tempo = 0.02
	szene.auto_navigate = false
	var enthuellt := [false]
	szene.ready_for_reveal.connect(func() -> void: enthuellt[0] = true)
	tree.root.add_child(szene)
	await wait_frames(2)
	assert_true(enthuellt[0], "ready_for_reveal nach dem Aufbau (Router-Contract)")
	# Hinfahrt (Zeitraffer) → Rampe mit Paletten-Zeilen.
	var rampe := await wait_until(
		func() -> bool: return szene.phase == GoobyeGrossmarktScene.PHASE_RAMPE, 5000
	)
	assert_true(rampe, "Fahrt endet an der Rampe")
	var plus_apple: Button = szene.find_child("Plus_apple", true, false)
	assert_true(plus_apple != null, "Paletten-Zeile für Äpfel existiert")
	var m := ScreenShell.metrics(szene.get_viewport())
	var floor_px: float = m["floor_px"]
	assert_true(plus_apple.custom_minimum_size.y >= floor_px - 1.0, "Stepper hält den Touch-Floor")
	# Stepper: 2× Apfel + 1× Möhre; die Anzeige zählt mit.
	szene.plus_tippen("apple")
	szene.plus_tippen("apple")
	szene.plus_tippen("carrot")
	await wait_frames(1)
	var anzahl_apple: Label = szene.find_child("Anzahl_apple", true, false)
	assert_eq(anzahl_apple.text, "2", "Stepper zählt")
	# Kaufen & losfahren: atomar, dann Rückfahrt bis zur Einräum-Karte.
	szene.kaufen()
	assert_eq(int(gs.get_value("economy.coins")), 89, "Rampen-Kauf bucht sofort ab")
	assert_eq(_lager_von(gs), {"apple": 2, "carrot": 1}, "Ware liegt schon sicher im Lager")
	var ankunft := await wait_until(
		func() -> bool: return szene.phase == GoobyeGrossmarktScene.PHASE_ANKUNFT, 5000
	)
	assert_true(ankunft, "Rückfahrt endet an der Einräum-Karte")
	assert_true(szene.find_child("AnkunftOverlay", true, false) != null, "Einräum-Karte da")
	var zurueck: Button = szene.find_child("ZurueckInDenLaden", true, false)
	assert_true(zurueck != null and zurueck.custom_minimum_size.y >= floor_px - 1.0)
	szene.queue_free()
	await wait_frames(2)
	_teardown_gs(gs)


## ------------------------------------------------------- Laden-Stationen


func test_laden_stationen_preise_und_backen() -> void:
	GoobyeKatalog.reset_cache()
	var gs := _fresh_gs(12, GoobyeKatalog.preis() + 100)
	assert_eq(GoobyeKauf.kaufe(gs), GoobyeKauf.RESULT_OK, "Vorbereitung: Laden gekauft")
	gs.set_value("dlc.goobye.erstbesuchGesehen", true)
	var szene: GoobyeLadenScene = LadenSzene.instantiate()
	szene.game_state_override = gs
	szene.seed_override = 12345
	szene.tempo = 0.05
	szene.auto_navigate = false
	tree.root.add_child(szene)
	await wait_frames(3)
	var m := ScreenShell.metrics(szene.get_viewport())
	var floor_px: float = m["floor_px"]
	# Welle-B-Knöpfe existieren und halten den Touch-Floor (44 pt).
	for knopf_name in ["Grossmarkt", "Preise", "Backen"]:
		var knopf: Button = szene.find_child(knopf_name, true, false)
		assert_true(knopf != null, "%s-Knopf existiert" % knopf_name)
		assert_true(
			knopf.custom_minimum_size.y >= floor_px - 1.0, "%s hält den Touch-Floor" % knopf_name
		)
	# Backen: Münzen runter, Brot ins Lager (Save UND Szenen-Kopie).
	var coins_vorher := int(gs.get_value("economy.coins"))
	var brot_vorher := int(_lager_von(gs).get("bread", 0))
	var backen: Button = szene.find_child("Backen", true, false)
	backen.pressed.emit()
	await wait_frames(1)
	assert_eq(
		int(gs.get_value("economy.coins")), coins_vorher - GoobyeBackofen.kosten(), "Selbstkosten"
	)
	assert_eq(
		int(_lager_von(gs).get("bread", 0)),
		brot_vorher + GoobyeBackofen.BROT_JE_CHARGE,
		"Charge liegt im Lager"
	)
	# Preise-Sheet: Slider je Warengruppe, Stellung landet im Save.
	var preise: Button = szene.find_child("Preise", true, false)
	preise.pressed.emit()
	await wait_frames(2)
	var schieber: HSlider = szene.find_child("Schieber_gemuese", true, false)
	assert_true(schieber != null, "Gemüse-Schieber im Sheet")
	assert_true(
		szene.find_child("Schieber_eigenmarke", true, false) != null, "alle 6 Gruppen haben Slider"
	)
	schieber.value = 1.2
	await wait_frames(1)
	assert_almost(
		float(GoobyeState.preise_von(gs).get("gemuese", 0.0)), 1.2, 1e-6, "Schieber → Save"
	)
	szene.queue_free()
	await wait_frames(2)
	_teardown_gs(gs)
