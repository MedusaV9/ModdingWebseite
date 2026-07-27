extends TestCase
## W3a — CityMap: 15×12-Lattice aus Doc E §1.2, Straßen-Netz, Distrikte,
## Energie-Tabelle, Parkplätze und die Web-portierte Straßenstück-Suche.


func test_karte_laedt_und_validiert() -> void:
	var karte := CityMap.laden()
	assert_true(karte.ist_geladen(), "city_map.json lädt")
	assert_eq(karte.spalten, 15)
	assert_eq(karte.reihen, 12)
	assert_almost(karte.tile_m, 20.0)
	var fehler := karte.validieren()
	assert_eq(fehler.size(), 0, "Karte konsistent: %s" % ", ".join(fehler))
	# 11 Orte: 4 aus W3a (REHWEI, GOOBYTHEKE, GOOUHBUS, Flughafen) + die
	# 5 aus M2/ORTE (Baumarkt, Post, POW!, Autohaus, Wochenmarkt) + der
	# Tierarzt (REST-3) + der Funkelpark (REST-4).
	assert_eq(karte.orte().size(), 11, "alle Orte im Plan")


func test_strassen_lattice() -> void:
	var karte := CityMap.laden()
	assert_true(karte.ist_strasse(Vector2i(1, 1)), "Ring oben links")
	assert_true(karte.ist_strasse(Vector2i(10, 13)), "Ring unten rechts")
	assert_true(karte.ist_strasse(Vector2i(0, 4)), "Flughafen-Zubringer")
	assert_false(karte.ist_strasse(Vector2i(5, 2)), "REHWEI-Tile ist Gebäude")
	assert_true(karte.ist_kreisel(Vector2i(1, 6)), "Kreisel Nord")
	assert_true(karte.ist_kreisel(Vector2i(7, 6)), "Kreisel Süd")


func test_energie_kosten_je_distrikt() -> void:
	var karte := CityMap.laden()
	assert_eq(karte.energie_kosten("rehwei"), 4, "Zentrum = 4")
	assert_eq(karte.energie_kosten("goobytheke"), 4)
	assert_eq(karte.energie_kosten("baumarkt"), 5, "Gewerbe = 5")
	assert_eq(karte.energie_kosten("flughafen"), 6, "Flughafen = 6")
	assert_eq(karte.energie_kosten("zuhause"), 0, "Nach Hause IMMER kostenlos")


func test_welt_tile_roundtrip() -> void:
	var karte := CityMap.laden()
	var mitte := karte.tile_zu_welt(Vector2i(5, 7))
	assert_eq(karte.welt_zu_tile(mitte), Vector2i(5, 7))
	assert_almost(karte.welt_von(0, 7).x, 0.0, 0.001, "Spalte 7 = Weltmitte x")


func test_parkplatz_liegt_richtung_strasse() -> void:
	var karte := CityMap.laden()
	var ort_mitte := karte.tile_zu_welt(Vector2i(5, 2))
	var strasse := karte.tile_zu_welt(Vector2i(5, 1))
	var park := karte.parkplatz_welt("rehwei")
	var d_park := Vector2(park.x, park.z).distance_to(Vector2(strasse.x, strasse.z))
	var d_ort := Vector2(ort_mitte.x, ort_mitte.z).distance_to(Vector2(strasse.x, strasse.z))
	assert_true(d_park < d_ort, "Parkplatz zwischen Ort und Straße")
	assert_almost(karte.park_radius(), 4.0, 0.001, "DRIVE.PARKING_RADIUS = 4")


func test_road_piece_suche() -> void:
	var gerade := CityMap.road_piece_for(false, true, false, true)
	assert_eq(gerade["piece"], "road-straight")
	assert_eq(gerade["rot_grad"], 0)
	var vertikal := CityMap.road_piece_for(true, false, true, false)
	assert_eq(vertikal["piece"], "road-straight")
	assert_eq(int(vertikal["rot_grad"]) % 180, 90, "N/S = 90° gedreht")
	var kreuz := CityMap.road_piece_for(true, true, true, true)
	assert_eq(kreuz["piece"], "road-crossroad")
	var t_stueck := CityMap.road_piece_for(false, true, true, true)
	assert_eq(t_stueck["piece"], "road-intersection")
	var kurve := CityMap.road_piece_for(false, false, true, true)
	assert_eq(kurve["piece"], "road-bend")
	assert_eq(kurve["rot_grad"], 0, "S+W ist die geauthorte bend-Lage")
	var ende := CityMap.road_piece_for(false, false, false, true)
	assert_eq(ende["piece"], "road-end")


func test_rotate_ports() -> void:
	assert_eq(CityMap.rotate_ports(["W", "E"], 1), ["S", "N"], "+90° dreht W→S, E→N")
	assert_eq(CityMap.rotate_ports(["N"], 4), ["N"], "Vollkreis = Identität")
