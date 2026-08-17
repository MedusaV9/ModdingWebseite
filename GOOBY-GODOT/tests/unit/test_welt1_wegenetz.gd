extends TestCase
## WELT-1 — Wegenetz-Ausstattung: Wegweiser-Plan nennt jede angebundene
## Zone mit plausibler Distanz, Rastplätze/Gatter liegen im Land, und die
## Distanz-Funktion misst echte Polyline-Längen (symmetrisch).


func test_distanz_ist_symmetrisch_und_plausibel() -> void:
	var hin := RanchWegenetz.distanz_m("hof", "see")
	var zurueck := RanchWegenetz.distanz_m("see", "hof")
	assert_almost(hin, zurueck, 0.001, "Distanz symmetrisch")
	assert_true(hin > 200.0 and hin < 800.0, "hof→see plausibel (%.0f m)" % hin)
	assert_eq(RanchWegenetz.distanz_m("see", "waeldchen"), 0.0, "kein Direktweg = 0")


func test_wegweiser_plan_deckt_alle_angebundenen_zonen() -> void:
	var plaene := RanchWegenetz.wegweiser_plan()
	var beschildert: Array[String] = []
	for plan: Dictionary in plaene:
		beschildert.append(str(plan["zone"]))
		var arme: Array = plan["arme"]
		assert_true(arme.size() >= 1, "%s hat mindestens einen Arm" % plan["zone"])
		for arm: Dictionary in arme:
			assert_true(float(arm["distanz_m"]) > 0.0, "Arm mit echter Distanz")
			assert_true(str(arm["name_key"]).begins_with("rwelt.zone."), "Arm nennt Zonen-Key")
	for zone_id: String in RanchKarte.zonen_ids():
		if RanchKarte.nachbarn(zone_id).is_empty():
			continue
		assert_true(beschildert.has(zone_id), "%s hat einen Wegweiser" % zone_id)


func test_wegweiser_stehen_im_land_und_nicht_im_wasser() -> void:
	var grenzen := RanchKarte.grenzen()
	for plan: Dictionary in RanchWegenetz.wegweiser_plan():
		var p: Vector2 = plan["pos"]
		assert_true(grenzen.has_point(p), "Wegweiser %s in der Welt" % plan["zone"])
		assert_false(
			RanchGelaende.ist_wasser(p.x, p.y), "Wegweiser %s nicht im Wasser" % plan["zone"]
		)


func test_rastplaetze_und_gatter_liegen_begehbar() -> void:
	for platz: Array in RanchWegenetz.RASTPLAETZE:
		var pos := RanchKarte.punkt(float(platz[0]), float(platz[1]))
		assert_true(RanchKarte.ist_begehbar(pos), "Rastplatz %s begehbar" % str(platz))
	for gatter: Dictionary in RanchWegenetz.GATTER:
		var punkte := RanchKarte.wegpunkte(str(gatter["von"]), str(gatter["nach"]))
		assert_true(punkte.size() >= 2, "Gatter-Weg %s existiert" % str(gatter))
