extends TestCase
## W3a — CityRoadGraph: A*-Pfade über das Straßen-Lattice, Erreichbarkeit
## aller Orte, Polyline-Helfer (GOOBERANDO-Fahrer-Mathe) und Traffic-Loops.


func _graph() -> CityRoadGraph:
	return CityRoadGraph.aus_karte(CityMap.laden())


func test_alle_orte_von_zuhause_erreichbar() -> void:
	var karte := CityMap.laden()
	var graph := _graph()
	var start := karte.zuhause_strasse()
	for eintrag: Dictionary in karte.orte():
		var ziel := CityMap._tile_von(eintrag.get("strasse", [0, 0]))
		var pfad := graph.pfad(start, ziel)
		assert_true(pfad.size() >= 2, "Pfad zuhause → %s existiert" % eintrag["id"])
		assert_eq(pfad[0], start)
		assert_eq(pfad[pfad.size() - 1], ziel)


func test_pfad_ist_zusammenhaengend_und_optimal() -> void:
	var graph := _graph()
	var pfad := graph.pfad(Vector2i(1, 1), Vector2i(1, 6))
	assert_eq(pfad.size(), 6, "geradeaus = Manhattan-Distanz + 1")
	for i in range(1, pfad.size()):
		var schritt := (pfad[i] - pfad[i - 1]).abs()
		assert_eq(schritt.x + schritt.y, 1, "nur 4er-Nachbarschritte")


func test_pfad_unerreichbar_und_identitaet() -> void:
	var graph := _graph()
	assert_eq(graph.pfad(Vector2i(1, 1), Vector2i(0, 0)).size(), 0, "kein Knoten → leer")
	assert_eq(graph.pfad(Vector2i(1, 1), Vector2i(1, 1)).size(), 1, "von==nach → [von]")


func test_naechste_strasse() -> void:
	var karte := CityMap.laden()
	var graph := _graph()
	assert_eq(graph.naechste_strasse(Vector2i(5, 2)), Vector2i(5, 1), "REHWEI → Straße davor")
	var heim := graph.naechste_strasse(karte.zuhause_tile())
	assert_true(graph.ist_knoten(heim))


func test_polyline_laenge_und_punkt() -> void:
	var punkte := PackedVector3Array([Vector3(0, 0, 0), Vector3(10, 0, 0), Vector3(10, 0, 10)])
	assert_almost(CityRoadGraph.polyline_laenge(punkte), 20.0)
	assert_almost(CityRoadGraph.polyline_laenge(punkte, true), 20.0 + sqrt(200.0))
	var bei := CityRoadGraph.punkt_bei_laenge(punkte, 15.0)
	assert_almost(bei["punkt"].x, 10.0)
	assert_almost(bei["punkt"].z, 5.0)
	assert_almost(bei["richtung"].z, 1.0, 0.001, "Richtung zeigt +z im 2. Segment")
	var wrap := CityRoadGraph.punkt_bei_laenge(punkte, 20.0 + sqrt(200.0) + 15.0, true)
	assert_almost(wrap["punkt"].x, 10.0, 0.001, "geschlossene Loops wickeln")
	assert_almost(wrap["punkt"].z, 5.0, 0.001)


func test_traffic_schleifen_liegen_auf_strassen() -> void:
	var karte := CityMap.laden()
	var graph := _graph()
	assert_true(karte.traffic_loops().size() >= 3, "mind. 3 Ambient-Loops")
	for ecken: Array in karte.traffic_loops():
		var tiles := graph.schleife(ecken)
		assert_true(tiles.size() >= 8, "Loop expandiert")
		for tile in tiles:
			assert_true(karte.ist_strasse(tile), "Loop-Tile %s ist Straße" % tile)


func test_gooberando_route_kueche_zu_haus() -> void:
	var karte := CityMap.laden()
	var graph := _graph()
	var kueche := graph.naechste_strasse(Vector2i(5, 5))
	var haus := karte.zuhause_strasse()
	var pfad := graph.pfad(kueche, haus)
	assert_true(pfad.size() >= 2, "Liefer-Route existiert (Doc E §5.2)")
