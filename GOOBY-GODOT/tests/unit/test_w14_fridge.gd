extends TestCase
## W14/FRIDGE — Kühlschrank 2.0: PURE Fütter-Sequenz (zeitinjiziert; Buchung
## erst NACH Sequenz-Ende), Doppel-Tap-Guard, Refusal-Kurzschluss über die
## BESTEHENDEN Gates, Kategorien-Ableitung (Katalog additiv), Chips-Ableitung,
## Regal-Grid-Karten (Badge/Pillen/Junk-Warnung/Auswahl) und der knuffige
## Leerzustand mit REHWEI-Knopf. Die apply_feed-Semantik selbst bleibt
## unangetastet — Wachen: test_ef1_fuettern + test_w13_food_nougat.


func _state(food: Dictionary, hunger := 40.0) -> Dictionary:
	return {
		"inventory": {"food": food},
		"gooby":
		{
			"stats": {"hunger": hunger, "fun": 50.0, "energy": 50.0, "hygiene": 50.0},
			"weight": 50.0,
			"health": {"junkScore": 0},
		},
		"achievements": {"counters": {}},
	}


# ── Sequenz-Statemaschine (pur, zeitinjiziert) ────────────────────────────────


func test_sequenz_reihenfolge_und_buchung_erst_nach_ende() -> void:
	var sequenz := FuetterSequenz.new()
	assert_eq(sequenz.phase(0), FuetterSequenz.PHASE_BEREIT, "vor start: bereit")
	assert_true(sequenz.start("bread", 10_000), "Start angenommen")
	assert_eq(sequenz.dauer_ms(), 2500, "volle Sequenz = 2,5 s")
	assert_eq(sequenz.biss_anzahl(), 3, "drei Mampf-Bisse")
	var typen: Array = []
	for ev: Dictionary in sequenz.tick(10_000 + 2499):
		typen.append(str(ev["typ"]))
	assert_false(typen.has("buchen"), "Buchung NICHT vor Sequenz-Ende fällig")
	assert_true(sequenz.ist_aktiv(), "1 ms vor Schluss läuft sie noch")
	for ev: Dictionary in sequenz.tick(10_000 + 2500):
		typen.append(str(ev["typ"]))
	assert_eq(
		typen,
		["schwebt", "biss", "biss", "biss", "schluck", "emotion", "buchen"],
		"Ereignisse in Reihenfolge, buchen als LETZTES"
	)
	assert_false(sequenz.ist_aktiv(), "nach buchen beendet")
	assert_eq(sequenz.phase(10_000 + 2500), FuetterSequenz.PHASE_FERTIG)
	assert_eq(sequenz.tick(10_000 + 9999).size(), 0, "jedes Ereignis nur EINMAL")


func test_sequenz_phasen_zeitabgeleitet() -> void:
	var sequenz := FuetterSequenz.new()
	sequenz.start("bread", 0)
	sequenz.tick(100)
	assert_eq(sequenz.phase(100), FuetterSequenz.PHASE_SCHWEBEN)
	sequenz.tick(800)
	assert_eq(sequenz.phase(800), FuetterSequenz.PHASE_MAMPF, "ab erstem Biss: mampf")
	sequenz.tick(1800)
	assert_eq(sequenz.phase(1800), FuetterSequenz.PHASE_SCHLUCK)
	sequenz.tick(2100)
	assert_eq(sequenz.phase(2100), FuetterSequenz.PHASE_EMOTION)


func test_doppel_tap_guard() -> void:
	var sequenz := FuetterSequenz.new()
	assert_true(sequenz.start("apple", 0))
	assert_false(sequenz.start("apple", 10), "Doppel-Tap abgewehrt")
	assert_false(sequenz.start("cookie", 500), "auch mit anderer Speise")
	assert_eq(sequenz.food_id(), "apple", "laufende Sequenz bleibt unangetastet")
	sequenz.tick(2500)
	assert_false(sequenz.ist_aktiv())
	assert_true(sequenz.start("cookie", 3000), "nach dem Ende wieder frei")


func test_reduced_motion_kurzfassung_ein_biss() -> void:
	var sequenz := FuetterSequenz.new()
	assert_true(sequenz.start("apple", 0, true))
	assert_eq(sequenz.biss_anzahl(), 1, "Kurzfassung: genau EIN Biss")
	assert_eq(sequenz.dauer_ms(), 1500, "400 + 350 + 300 + 450 ms")
	var typen: Array = []
	for ev: Dictionary in sequenz.tick(1500):
		typen.append(str(ev["typ"]))
	assert_eq(typen, ["schwebt", "biss", "schluck", "emotion", "buchen"])


func test_refusal_kurzschluss_ueber_bestehende_gates() -> void:
	assert_eq(FuetterSequenz.refusal(_state({"apple": 1}, 99.9), "apple"), "satt")
	assert_eq(FuetterSequenz.refusal(_state({}), "apple"), "leer")
	assert_eq(FuetterSequenz.refusal(_state({"apple": 0}), "apple"), "leer")
	assert_eq(FuetterSequenz.refusal(_state({"apple": 1}), "apple"), "", "frei")
	# Dieselben Gates wie in apply_feed (fail-closed bleibt bestehen).
	assert_eq(FoodCatalog.apply_feed(_state({"apple": 1}, 99.9), "apple"), {})
	assert_eq(FoodCatalog.apply_feed(_state({}), "apple"), {})


func test_emotions_ableitung() -> void:
	assert_eq(FuetterSequenz.emotion_fuer("carrot"), FuetterSequenz.EMOTION_VERLIEBT, "Liebling")
	assert_eq(FuetterSequenz.emotion_fuer("pizza"), FuetterSequenz.EMOTION_ZUCKER, "Junk-Gag")
	assert_eq(FuetterSequenz.emotion_fuer("bread"), FuetterSequenz.EMOTION_FROH)
	var sequenz := FuetterSequenz.new()
	sequenz.start("carrot", 0)
	var emotion := {}
	for ev: Dictionary in sequenz.tick(2500):
		if str(ev["typ"]) == "emotion":
			emotion = ev
	assert_eq(str(emotion.get("art", "")), FuetterSequenz.EMOTION_VERLIEBT)


# ── Kategorien + Chips (Katalog additiv) ──────────────────────────────────────


func test_kategorien_ableitung_deckt_den_ganzen_katalog() -> void:
	for id: String in FoodCatalog.FOODS:
		assert_true(FoodCatalog.FOOD_KATEGORIE.has(id), "explizite Kategorie fehlt: %s" % id)
		assert_true(
			FoodCatalog.KATEGORIEN.has(FoodCatalog.kategorie(id)), "ungültige Kategorie: %s" % id
		)
	assert_eq(FoodCatalog.kategorie("carrot"), "gemuese")
	assert_eq(FoodCatalog.kategorie("melone"), "gemuese", "deutsche Garten-Id")
	assert_eq(FoodCatalog.kategorie("pizza"), "warm")
	assert_eq(FoodCatalog.kategorie("nutella"), "suesses")
	# Feindliche/unbekannte Ids: Ableitung statt Leerstring.
	assert_eq(FoodCatalog.kategorie("mystery_snack"), "gemuese", "unbekannt + kein junk")


func test_chips_ableitung_aus_vorrat() -> void:
	var leer: Array[Dictionary] = []
	assert_eq(FuetterGrid.chips_fuer(leer), [], "leerer Vorrat: keine Chips")
	var nur_gemuese: Array[Dictionary] = [{"id": "carrot", "count": 2}]
	assert_eq(FuetterGrid.chips_fuer(nur_gemuese), ["gemuese"], "eine Kategorie: kein Alles-Chip")
	var gemischt: Array[Dictionary] = [
		{"id": "cookie", "count": 1}, {"id": "carrot", "count": 2}, {"id": "pizza", "count": 1}
	]
	assert_eq(
		FuetterGrid.chips_fuer(gemischt),
		["alle", "gemuese", "suesses", "warm"],
		"feste Reihenfolge + Alles voran"
	)


func test_jede_speise_hat_aufloesbares_modell_oder_knubbel() -> void:
	for id: String in FoodCatalog.FOODS:
		var pfad := FuetterModelle.glb_pfad(id)
		if not pfad.is_empty():
			assert_true(ResourceLoader.exists(pfad), "GLB-Pfad kaputt: %s → %s" % [id, pfad])
	var knubbel := FuetterModelle.instanz("cottonCandy")
	assert_true(knubbel is Node3D, "Fallback-Knubbel ist ein Node3D")
	knubbel.free()


# ── Sprüche ───────────────────────────────────────────────────────────────────


func test_sprueche_acht_je_kategorie_de_und_en() -> void:
	for locale: String in ["de", "en"]:
		var tabelle := I18nService.table(locale)
		for kategorie: String in FoodCatalog.KATEGORIEN:
			var liste: Variant = tabelle.get("fuettern.sprueche." + kategorie)
			assert_true(liste is Array, "%s/%s: Sprüche fehlen" % [locale, kategorie])
			if liste is Array:
				assert_eq((liste as Array).size(), 8, "%s/%s: 8 Sprüche" % [locale, kategorie])


func test_sprueche_rotieren_statt_wuerfeln() -> void:
	FuetterSprueche.reset_fuer_tests()
	var erster := FuetterSprueche.naechster("bread")
	var zweiter := FuetterSprueche.naechster("bread")
	assert_ne(erster, zweiter, "zweite Fütterung = nächster Spruch")
	for _i in 6:
		FuetterSprueche.naechster("bread")
	assert_eq(FuetterSprueche.naechster("bread"), erster, "nach 8 wieder von vorn")
	FuetterSprueche.reset_fuer_tests()


# ── Regal-Grid (Szene) ────────────────────────────────────────────────────────


func test_leerzustand_gaehnt_und_bietet_rehwei_route() -> void:
	var grid := FuetterGrid.new()
	tree.root.add_child(grid)
	var leer: Array[Dictionary] = []
	grid.setup(leer)
	var titel := grid.find_child("LeerTitel", true, false)
	assert_true(titel is Label, "Gähn-Zeile da")
	if titel is Label:
		assert_eq((titel as Label).text, I18nService.t("fuettern.leer_titel"))
	var rehwei := grid.find_child("RehweiKnopf", true, false)
	assert_true(rehwei is Button, "REHWEI-Direkt-Knopf da")
	var getroffen := {"n": 0}
	grid.rehwei_gewuenscht.connect(func() -> void: getroffen["n"] += 1)
	(rehwei as Button).pressed.emit()
	assert_eq(int(getroffen["n"]), 1, "Knopf feuert den Route-Wunsch")
	assert_eq(grid.find_child("Regal", true, false), null, "kein Regal im Leerzustand")
	tree.root.remove_child(grid)
	grid.free()


func test_regal_karten_badge_pillen_warnung_und_auswahl() -> void:
	var grid := FuetterGrid.new()
	tree.root.add_child(grid)
	var entries: Array[Dictionary] = [{"id": "carrot", "count": 3}, {"id": "pizza", "count": 1}]
	grid.setup(entries)
	var karte := grid.find_child("Karte_carrot", true, false)
	assert_true(karte is Button, "Karte pro Speise")
	var badge := karte.find_child("Badge", true, false)
	assert_true(badge is Label)
	if badge is Label:
		assert_eq(
			(badge as Label).text,
			I18nService.t("fuettern.vorrat_badge", {"anzahl": 3}),
			"Vorrats-Badge ×3"
		)
	var pillen := karte.find_child("Pillen", true, false)
	assert_eq(pillen.get_child_count(), 2, "Möhre: +Hunger- und +Spaß-Pille")
	assert_eq(karte.find_child("JunkWarnung", true, false), null, "Möhre ohne Zucker-Warnung")
	var pizza := grid.find_child("Karte_pizza", true, false)
	assert_true(pizza.find_child("JunkWarnung", true, false) != null, "Pizza warnt vor Zucker")
	var gewaehlt := {"id": ""}
	grid.speise_gewaehlt.connect(func(id: String) -> void: gewaehlt["id"] = id)
	(karte as Button).pressed.emit()
	assert_eq(str(gewaehlt["id"]), "carrot", "Karten-Tap wählt die Speise")
	tree.root.remove_child(grid)
	grid.free()


func test_chips_filtern_das_regal() -> void:
	var grid := FuetterGrid.new()
	tree.root.add_child(grid)
	var entries: Array[Dictionary] = [{"id": "carrot", "count": 2}, {"id": "pizza", "count": 1}]
	grid.setup(entries)
	var chip := grid.find_child("Chip_warm", true, false)
	assert_true(chip is Button, "Kategorie-Chip da")
	(chip as Button).pressed.emit()
	await wait_frames(2)
	assert_eq(grid.find_child("Karte_carrot", true, false), null, "Filter blendet Gemüse aus")
	assert_true(grid.find_child("Karte_pizza", true, false) is Button, "Warmes bleibt")
	tree.root.remove_child(grid)
	grid.free()
