extends TestCase
## FIX-5 „Leben" — Verkehr: Ampel-Phasen (N/S vs. O/W mit Alles-Rot-Puffer),
## Autos halten an roten Ampeln und hinter dem Vordermann, biegen an den
## Loop-Ecken ab, nachts fährt weniger und die Ampeln blinken gelb.


func _test_wagen(karte: CityMap) -> Dictionary:
	# Loop 1 der Karte: Ring über die Kreuzungen (1,1)→(1,6)→(4,6)→(4,1).
	var graph := CityRoadGraph.aus_karte(karte)
	var tiles := graph.schleife(karte.traffic_loops()[0])
	var punkte := PackedVector3Array()
	for tile in tiles:
		var p := karte.tile_zu_welt(tile)
		p.y = CityCarFeel.ROAD_Y
		punkte.append(p)
	return {
		"punkte": punkte,
		"s": 0.0,
		"tempo": CityCarFeel.TRAFFIC_SPEED,
		"laenge": CityRoadGraph.polyline_laenge(punkte, true),
	}


func test_ampel_phasen_schliessen_sich_aus() -> void:
	for zeit: float in [0.0, 2.0, 4.0, 6.0, 8.0, 11.0, 14.5]:
		var zustand := CityVerkehr.ampel_zustand(zeit)
		assert_false(
			bool(zustand["ns_gruen"]) and bool(zustand["ew_gruen"]),
			"niemals beide Achsen grün (t=%f)" % zeit
		)
	assert_true(CityVerkehr.ampel_zustand(0.0)["ns_gruen"], "Zyklus startet mit N/S grün")
	assert_true(CityVerkehr.ampel_zustand(7.0)["ew_gruen"], "zweite Hälfte O/W grün")
	# Alles-Rot-Puffer am Phasenende: Räumzeit für die Kreuzung.
	var puffer := CityVerkehr.ampel_zustand(CityVerkehr.ZYKLUS_S / 2.0 - 0.1)
	assert_false(bool(puffer["ns_gruen"]) or bool(puffer["ew_gruen"]), "Alles-Rot-Puffer existiert")


func test_ampel_tiles_sind_echte_kreuzungen() -> void:
	var karte := CityMap.laden()
	var tiles := CityVerkehr.ampel_tiles(karte)
	assert_true(tiles.size() >= 10, "genug Ampel-Kreuzungen: %d" % tiles.size())
	for tile in tiles:
		assert_true(karte.ist_strasse(tile), "Ampel steht auf Straße: %s" % tile)
		assert_false(karte.ist_kreisel(tile), "Kreisel haben keine Ampel: %s" % tile)
	assert_false(tiles.has(Vector2i(1, 6)), "Kreisel Nord bleibt ampelfrei")


func test_auto_haelt_an_roter_ampel_und_faehrt_bei_gruen() -> void:
	var karte := CityMap.laden()
	var wagen := _test_wagen(karte)
	var ampeln := {}
	for tile in CityVerkehr.ampel_tiles(karte):
		ampeln[tile] = true
	# Loop 1 startet auf (1,1) Richtung Osten → nächste Ampel-Kreuzung (1,6)
	# ist ein Kreisel, also weiter simulieren, bis eine rote O/W-Ampel kommt.
	# Wir wählen die Zeit so, dass O/W ROT ist (N/S grün: t=0).
	var gestoppt := false
	for _i in 2000:
		var abstand := CityVerkehr.vordermann_abstand(wagen, [], float(wagen["laenge"]))
		CityVerkehr.schritt(wagen, 1.0 / 60.0, 0.0, karte, ampeln, abstand)
		if float(wagen["tempo"]) < 0.05 and CityVerkehr.rot_voraus(wagen, 0.0, karte, ampeln):
			gestoppt = true
			break
	assert_true(gestoppt, "Auto kommt vor einer roten Ampel zum Stehen")
	var stand_s := float(wagen["s"])
	# Grün schalten (O/W grün bei t=7) → Auto fährt wieder an.
	for _i in 240:
		CityVerkehr.schritt(wagen, 1.0 / 60.0, 7.0, karte, ampeln, INF)
	assert_true(float(wagen["tempo"]) > 1.0, "bei Grün fährt das Auto an")
	assert_true(float(wagen["s"]) > stand_s + 1.0, "und rollt über die Kreuzung")


func test_auto_haelt_hinter_dem_vordermann() -> void:
	var karte := CityMap.laden()
	var wagen := _test_wagen(karte)
	for _i in 120:
		CityVerkehr.schritt(wagen, 1.0 / 60.0, 0.0, karte, {}, CityVerkehr.MIN_ABSTAND_M - 2.0)
	assert_almost(float(wagen["tempo"]), 0.0, 0.01, "dichter Vordermann ⇒ stehen")
	for _i in 240:
		CityVerkehr.schritt(wagen, 1.0 / 60.0, 0.0, karte, {}, INF)
	assert_true(float(wagen["tempo"]) > 5.0, "freie Bahn ⇒ Reisetempo")


func test_loops_biegen_ab() -> void:
	var karte := CityMap.laden()
	var wagen := _test_wagen(karte)
	var punkte: PackedVector3Array = wagen["punkte"]
	var richtungen := {}
	var laenge := float(wagen["laenge"])
	for i in 40:
		var bei := CityRoadGraph.punkt_bei_laenge(punkte, laenge * float(i) / 40.0, true)
		var richtung: Vector3 = bei["richtung"]
		richtungen[Vector2i(roundi(richtung.x), roundi(richtung.z))] = true
	assert_true(richtungen.size() >= 4, "Loop fährt alle vier Himmelsrichtungen (biegt ab)")


func test_nachts_weniger_verkehr_und_gelbes_blinken() -> void:
	assert_eq(CityVerkehr.anzahl(12.0), CityVerkehr.TAG_AUTOS, "mittags volle Menge")
	assert_eq(CityVerkehr.anzahl(23.0), CityVerkehr.NACHT_AUTOS, "nachts Nachtschwärmer")
	assert_true(CityVerkehr.anzahl(23.0) < CityVerkehr.anzahl(12.0), "nachts deutlich weniger")
	assert_true(CityVerkehr.ampel_blinkt(23.0), "nachts blinken die Ampeln")
	assert_false(CityVerkehr.ampel_blinkt(12.0), "mittags regeln sie")
	var blink_an := CityVerkehr.ampel_farbe(false, 0.0, true)
	var blink_aus := CityVerkehr.ampel_farbe(false, CityVerkehr.BLINK_TAKT_S + 0.01, true)
	assert_eq(blink_an, CityVerkehr.FARBE_GELB, "Blinken ist gelb")
	assert_ne(blink_an, blink_aus, "Blinken wechselt an/aus")
	assert_eq(
		CityVerkehr.ampel_farbe(false, 0.0, false), CityVerkehr.FARBE_GRUEN, "N/S grün bei t=0"
	)
	assert_eq(CityVerkehr.ampel_farbe(true, 0.0, false), CityVerkehr.FARBE_ROT, "O/W rot bei t=0")


func test_fussgaenger_menge_folgt_der_tageszeit() -> void:
	assert_eq(CityFussgaenger.anzahl(12.0), CityFussgaenger.TAG_ANZAHL)
	assert_eq(CityFussgaenger.anzahl(23.0), CityFussgaenger.NACHT_ANZAHL)
	assert_true(CityFussgaenger.anzahl(23.0) < CityFussgaenger.anzahl(12.0))


func test_fussgaenger_pausieren_am_schaufenster_und_winken() -> void:
	var route := {
		"von": Vector3.ZERO,
		"nach": Vector3(10, 0, 0),
		"laenge": 10.0,
		"tempo": 1.0,
		"phase": 0.0,
		"pause_s": 4.0,
		"winkt": true,
		"blick": 1.234,
	}
	var unterwegs := CityFussgaenger.zustand(route, 5.0)
	assert_false(bool(unterwegs["steht"]), "bei t=5 s noch unterwegs")
	var pause := CityFussgaenger.zustand(route, 12.0)
	assert_true(bool(pause["steht"]), "nach dem Hinweg wird pausiert")
	assert_true(bool(pause["winkt"]), "dieser Gooby winkt dabei")
	assert_eq(pause["pos"], Vector3(10, 0, 0), "Pause am Wendepunkt")
	assert_almost(float(pause["heading"]), 1.234, 1e-6, "Blick zur Ladenzeile")
	var rueckweg := CityFussgaenger.zustand(route, 15.0)
	assert_false(bool(rueckweg["steht"]), "nach der Pause geht es zurück")
	var daheim := CityFussgaenger.zustand(route, 25.0)
	assert_true(bool(daheim["steht"]), "am Start wird wieder pausiert")
	assert_eq(daheim["pos"], Vector3.ZERO)


func test_schaufenster_routen_werden_bevorzugt() -> void:
	var karte := CityMap.laden()
	var laden_strassen := {}
	for eintrag: Dictionary in karte.orte():
		laden_strassen[CityMap._tile_von(eintrag.get("strasse", [0, 0]))] = true
	var routen := CityFussgaenger.routen(karte, 6, 4242)
	assert_eq(routen.size(), 6)
	var vor_laeden := 0
	for route in routen:
		for ende: Vector3 in [route["von"], route["nach"]]:
			if laden_strassen.has(karte.welt_zu_tile(ende)):
				vor_laeden += 1
				break
	assert_true(vor_laeden >= 3, "mind. die Hälfte schlendert vor Läden (%d/6)" % vor_laeden)
