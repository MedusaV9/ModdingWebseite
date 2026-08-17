extends TestCase
## WELT-1 — neue Entdeckungen: sieben zusätzliche Fundorte (je einer pro
## neuer Zone), einmalige Belohnung über den bestehenden Save-Fluss, und
## die neuen Trampelpfade enden wirklich an einem neuen Fundort.


class MiniGs:
	var werte: Dictionary = {}
	var state: Dictionary = {"economy": {"coins": 100}}

	func get_value(pfad: String, fallback: Variant = null) -> Variant:
		return werte.get(pfad, fallback)

	func set_value(pfad: String, wert: Variant) -> void:
		werte[pfad] = wert

	func update(mutator: Callable) -> void:
		mutator.call(state)

	func coins() -> int:
		return int(state["economy"]["coins"])


func test_neue_orte_vollstaendig_und_im_land() -> void:
	var grenzen := RanchKarte.grenzen()
	var ids: Array[String] = []
	for eintrag: Dictionary in RanchEntdeckungen.ORTE_NEU:
		var id := str(eintrag["id"])
		assert_false(ids.has(id), "Id %s eindeutig" % id)
		ids.append(id)
		var p := RanchEntdeckungen.position_von(eintrag)
		assert_true(grenzen.has_point(p), "%s liegt in der Karte" % id)
		assert_false(RanchGelaende.ist_wasser(p.x, p.y), "%s liegt nicht im Wasser" % id)
		assert_true(int(eintrag["muenzen"]) > 0, "%s belohnt" % id)
	assert_eq(ids.size(), 7, "sieben neue Fundorte")
	assert_eq(RanchEntdeckungen.alle_orte().size(), 16, "alle_orte = 9 alt + 7 neu")


func test_jede_neue_zone_hat_eine_besonderheit() -> void:
	var zonen_mit_fund: Array[String] = []
	for eintrag: Dictionary in RanchEntdeckungen.ORTE_NEU:
		var p := RanchEntdeckungen.position_von(eintrag)
		var zone := RanchKarte.zone_bei(Vector3(p.x, 0.0, p.y))
		if not zonen_mit_fund.has(zone):
			zonen_mit_fund.append(zone)
	for zone_id: String in ["bergmassiv", "blumenwiese", "moor", "ruine", "strand", "kornfeld"]:
		assert_true(zonen_mit_fund.has(zone_id), "%s hat eine Besonderheit" % zone_id)


func test_neue_entdeckung_belohnt_einmal_ueber_den_save() -> void:
	var gs := MiniGs.new()
	var erster := RanchEntdeckungen.entdecke(gs, "gipfelkreuz")
	assert_true(bool(erster["neu"]), "erster Fund = neu")
	assert_eq(gs.coins(), 100 + int(erster["muenzen"]), "Münzen gutgeschrieben")
	assert_false(bool(RanchEntdeckungen.entdecke(gs, "gipfelkreuz")["neu"]), "nur einmal")
	assert_eq(RanchEntdeckungen.gefunden(gs), ["gipfelkreuz"] as Array[String], "im Save")


func test_fund_bei_findet_neue_orte() -> void:
	var gs := MiniGs.new()
	var eintrag := RanchEntdeckungen.fundort("kornkreis")
	var p := RanchEntdeckungen.position_von(eintrag)
	var nah := Vector3(p.x + 4.0, 0.0, p.y - 5.0)
	assert_eq(str(RanchEntdeckungen.fund_bei(gs, nah).get("id", "")), "kornkreis", "nah = Fund")
	RanchEntdeckungen.entdecke(gs, "kornkreis")
	assert_true(
		str(RanchEntdeckungen.fund_bei(gs, nah).get("id", "")) != "kornkreis",
		"gefunden = kein zweiter Toast"
	)


func test_neue_pfade_enden_an_neuen_fundorten() -> void:
	for pfad: Dictionary in RanchEntdeckungen.PFADE_NEU:
		var punkte: Array = pfad["punkte"]
		assert_true(punkte.size() >= 2, "%s hat eine Strecke" % pfad["id"])
		var ende: Array = punkte[punkte.size() - 1]
		var ende_p := Vector2(float(ende[0]), float(ende[1]))
		var best := INF
		for eintrag: Dictionary in RanchEntdeckungen.ORTE_NEU:
			best = minf(best, ende_p.distance_to(RanchEntdeckungen.position_von(eintrag)))
		assert_true(
			best <= RanchEntdeckungen.FUND_RADIUS_M + 4.0,
			"%s endet an einem Fundort (%.1f m)" % [pfad["id"], best]
		)


func test_neue_fundort_namen_sind_lokalisiert() -> void:
	for eintrag: Dictionary in RanchEntdeckungen.ORTE_NEU:
		var key := str(eintrag["name_key"])
		var text := I18nService.t(key)
		assert_true(text != key and not text.is_empty(), "Key %s übersetzt" % key)
