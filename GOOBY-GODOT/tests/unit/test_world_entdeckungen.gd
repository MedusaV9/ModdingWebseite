extends TestCase
## FB-2 — Entdeckungsorte: neun Fundorte mit Belohnung, einmalig pro Save,
## additiv im ranch.welt-Slice; Positionen liegen begehbar im Land und
## die Trampelpfade enden wirklich an einem Fundort.


## Miniatur-GameState mit Economy (Duck-Typing wie GameState.update).
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


func test_orte_vollstaendig_und_im_land() -> void:
	var grenzen := RanchKarte.grenzen()
	var ids: Array[String] = []
	for eintrag: Dictionary in RanchEntdeckungen.ORTE:
		var id := str(eintrag["id"])
		assert_false(ids.has(id), "Id %s eindeutig" % id)
		ids.append(id)
		var p := RanchEntdeckungen.position_von(eintrag)
		assert_true(grenzen.has_point(p), "%s liegt in der Karte" % id)
		assert_false(RanchGelaende.ist_wasser(p.x, p.y), "%s liegt nicht im Wasser" % id)
		assert_true(int(eintrag["muenzen"]) > 0, "%s belohnt" % id)
	assert_eq(ids.size(), 9, "neun Fundorte")


func test_entdecken_belohnt_genau_einmal() -> void:
	var gs := MiniGs.new()
	var erster := RanchEntdeckungen.entdecke(gs, "wasserfall")
	assert_true(bool(erster["neu"]), "erster Fund = neu")
	assert_eq(gs.coins(), 100 + int(erster["muenzen"]), "Münzen gutgeschrieben")
	var zweiter := RanchEntdeckungen.entdecke(gs, "wasserfall")
	assert_false(bool(zweiter["neu"]), "zweiter Besuch = kein Fund")
	assert_eq(gs.coins(), 100 + int(erster["muenzen"]), "keine Doppel-Münzen")
	assert_eq(RanchEntdeckungen.gefunden(gs), ["wasserfall"] as Array[String])
	assert_false(bool(RanchEntdeckungen.entdecke(gs, "mondbasis")["neu"]), "unbekannt = nein")


func test_fund_bei_findet_nur_im_radius_und_nur_neue() -> void:
	var gs := MiniGs.new()
	var eintrag := RanchEntdeckungen.fundort("steinkreis")
	var p := RanchEntdeckungen.position_von(eintrag)
	var nah := Vector3(p.x + 5.0, 0.0, p.y - 4.0)
	assert_eq(str(RanchEntdeckungen.fund_bei(gs, nah).get("id", "")), "steinkreis", "nah = Fund")
	var fern := Vector3(p.x + 80.0, 0.0, p.y + 80.0)
	assert_true(RanchEntdeckungen.fund_bei(gs, fern).is_empty(), "fern = kein Fund")
	RanchEntdeckungen.entdecke(gs, "steinkreis")
	assert_true(
		str(RanchEntdeckungen.fund_bei(gs, nah).get("id", "")) != "steinkreis",
		"gefundene Orte melden sich nicht erneut"
	)


func test_funde_ueberleben_das_zonen_normalisieren() -> void:
	# RanchWeltState.normalize_welt fasst nur v/entdeckt an — der additive
	# funde-Schlüssel muss verbatim überleben (sonst wäre Laden ein Reset).
	var gs := MiniGs.new()
	RanchEntdeckungen.entdecke(gs, "hoehle")
	RanchWeltState.entdecke_zone(gs, "see")
	assert_eq(RanchEntdeckungen.gefunden(gs), ["hoehle"] as Array[String], "Fund bleibt")
	var geheilt := RanchWeltState.normalize_welt(gs.get_value(RanchWeltState.WELT_KEY))
	assert_eq(geheilt.get("funde"), ["hoehle"], "funde übersteht normalize_welt")


func test_trampelpfade_enden_an_fundorten() -> void:
	for pfad: Dictionary in RanchEntdeckungen.PFADE:
		var punkte: Array = pfad["punkte"]
		assert_true(punkte.size() >= 2, "%s hat eine Strecke" % pfad["id"])
		var ende: Array = punkte[punkte.size() - 1]
		var ende_p := Vector2(float(ende[0]), float(ende[1]))
		var best := INF
		for eintrag: Dictionary in RanchEntdeckungen.ORTE:
			best = minf(best, ende_p.distance_to(RanchEntdeckungen.position_von(eintrag)))
		assert_true(
			best <= RanchEntdeckungen.FUND_RADIUS_M + 4.0,
			"%s endet an einem Fundort (%.1f m)" % [pfad["id"], best]
		)


func test_fundort_namen_sind_lokalisiert() -> void:
	for eintrag: Dictionary in RanchEntdeckungen.ORTE:
		var key := str(eintrag["name_key"])
		var text := I18nService.t(key)
		assert_true(text != key and not text.is_empty(), "Key %s übersetzt" % key)
	assert_true(
		I18nService.t("rwelt.fund_entdeckt", {"name": "X", "muenzen": "5"}).contains("X"),
		"Fund-Toast formatiert"
	)
