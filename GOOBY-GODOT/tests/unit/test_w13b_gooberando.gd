extends TestCase
## W13B — GOOBERANDO-Vollausbau (Doc E §5) + Guber-Politur (Doc E §4):
## Restaurant-Katalog (3 Lieferküchen, nur FoodCatalog-Ids), deterministische
## Fahrer-Sim auf dem road_graph (Position = reine Funktion der Zeit,
## Routen-Endpunkt = Haus), Warenkorb-Bestellung → exakte Inventar-
## Gutschrift, Guber 30 Münzen (Doc-Parität) + Surge-Fenster 18–20 Uhr (45).

const NOW := 1768478400000


func _karte() -> CityMap:
	return CityMap.laden()


func _route(karte: CityMap, graph: CityRoadGraph, restaurant_id: String) -> PackedVector3Array:
	return GooberandoFahrerSim.route_welt(
		karte, graph, GooberandoRestaurants.strasse_tile(restaurant_id), karte.zuhause_tile()
	)


## ------------------------------------------------------ Restaurant-Daten


func test_restaurant_katalog() -> void:
	var restaurants := GooberandoRestaurants.alle()
	assert_eq(restaurants.size(), 3, "3 Restaurants (Doc E §5.1)")
	var ids := {}
	for restaurant: Dictionary in restaurants:
		var id := str(restaurant.get("id", ""))
		assert_false(ids.has(id), "Restaurant-Id doppelt: %s" % id)
		ids[id] = true
		assert_false(str(restaurant.get("name_de", "")).is_empty())
		var prep_min := int(restaurant.get("prep_min_s", 0))
		var prep_max := int(restaurant.get("prep_max_s", 0))
		assert_true(prep_min > 0 and prep_min <= prep_max, "Wartezeit-Range %s" % id)
		var gerichte: Array = restaurant.get("gerichte", [])
		assert_true(gerichte.size() >= 4, "eigenes Menü mit ≥4 Gerichten (%s)" % id)
		for gericht: Dictionary in gerichte:
			var gericht_id := str(gericht.get("id", ""))
			assert_true(
				FoodCatalog.all().has(gericht_id),
				"Gericht-Id muss FoodCatalog-Id sein: %s" % gericht_id
			)
			assert_true(int(gericht.get("preis", 0)) > 0)
			assert_false(str(gericht.get("name_de", "")).is_empty())


func test_restaurant_strassen_und_routen_enden_am_haus() -> void:
	var karte := _karte()
	var graph := CityRoadGraph.aus_karte(karte)
	var haus_knoten := graph.naechste_strasse(karte.zuhause_tile())
	for restaurant: Dictionary in GooberandoRestaurants.alle():
		var id := str(restaurant.get("id", ""))
		var strasse := GooberandoRestaurants.strasse_tile(id)
		assert_true(karte.ist_strasse(strasse), "%s: strasse muss Straßen-Tile sein" % id)
		var route := _route(karte, graph, id)
		assert_true(route.size() >= 2, "%s: Route existiert" % id)
		assert_eq(route[0], karte.tile_zu_welt(strasse), "%s: Start am Restaurant" % id)
		assert_eq(
			route[route.size() - 1],
			karte.tile_zu_welt(haus_knoten),
			"%s: Routen-Endpunkt = Haus" % id
		)


## ------------------------------------------------------------ Fahrer-Sim


func test_fahrer_sim_deterministisch() -> void:
	var karte := _karte()
	var graph := CityRoadGraph.aus_karte(karte)
	var route := _route(karte, graph, "moehrenschmiede")
	var fertig := NOW + 300 * 1000
	var probe := NOW + 200 * 1000
	var a := GooberandoFahrerSim.status(route, NOW, fertig, probe)
	# Andere Abfragen dazwischen dürfen NICHTS ändern (kein interner Zustand).
	GooberandoFahrerSim.status(route, NOW, fertig, NOW + 250 * 1000)
	var b := GooberandoFahrerSim.status(route, NOW, fertig, probe)
	assert_eq(a["punkt"], b["punkt"], "gleiche Zeit = gleiche Position")
	assert_eq(a["fortschritt"], b["fortschritt"])
	assert_eq(a["phase"], b["phase"])


func test_fahrer_sim_phasen_und_monotonie() -> void:
	var karte := _karte()
	var graph := CityRoadGraph.aus_karte(karte)
	var route := _route(karte, graph, "burger_bau")
	var fahrzeit_ms := int(GooberandoFahrerSim.fahrzeit_s(route) * 1000.0)
	assert_true(fahrzeit_ms > 0, "Route hat Länge")
	var fertig := NOW + fahrzeit_ms + 120 * 1000
	var los := GooberandoFahrerSim.abfahrt_ms(NOW, fertig, route)
	assert_eq(los, fertig - fahrzeit_ms, "Abfahrt = fertig − Fahrzeit")
	var kueche := GooberandoFahrerSim.status(route, NOW, fertig, los - 1000)
	assert_eq(kueche["phase"], GooberandoFahrerSim.PHASE_KUECHE)
	assert_eq(kueche["punkt"], route[0], "vor der Abfahrt steht der Fahrer am Restaurant")
	var frueh := GooberandoFahrerSim.status(route, NOW, fertig, los + fahrzeit_ms / 4)
	var spaet := GooberandoFahrerSim.status(route, NOW, fertig, los + fahrzeit_ms / 2)
	assert_eq(frueh["phase"], GooberandoFahrerSim.PHASE_UNTERWEGS)
	assert_true(
		float(frueh["fortschritt"]) < float(spaet["fortschritt"]), "Fortschritt wächst monoton"
	)
	var da := GooberandoFahrerSim.status(route, NOW, fertig, fertig)
	assert_eq(da["phase"], GooberandoFahrerSim.PHASE_DA)
	assert_eq(da["punkt"], route[route.size() - 1], "bei fertigAt steht der Fahrer am Haus")


func test_fahrer_sim_abfahrt_nie_vor_bestellung() -> void:
	var karte := _karte()
	var graph := CityRoadGraph.aus_karte(karte)
	var route := _route(karte, graph, "pasta_hoppel")
	# Debug-verkürzte Bestellung: fertig lange VOR Ablauf der Fahrzeit.
	assert_eq(GooberandoFahrerSim.abfahrt_ms(NOW, NOW + 1000, route), NOW)
	var da := GooberandoFahrerSim.status(route, NOW, NOW + 1000, NOW + 1000)
	assert_eq(da["phase"], GooberandoFahrerSim.PHASE_DA, "fertigAt gewinnt immer")


## --------------------------------------------------- Warenkorb + Inventar


func test_warenkorb_bestellung_kosten_und_gutschrift() -> void:
	var korb := [
		GooberandoRestaurants.gericht("burger_bau", "burger"),
		GooberandoRestaurants.gericht("burger_bau", "fries"),
		GooberandoRestaurants.gericht("burger_bau", "fries"),
	]
	var res := GooberandoLogic.bestellen_korb(
		GooberandoLogic.default_slice(), NOW, 180, korb, "burger_bau"
	)
	assert_true(res["ok"])
	assert_eq(res["kosten"], 27 + 15 + 15 + 3, "Summe + Liefergebühr 3")
	assert_eq(res["slice"]["gerichte"], ["burger", "fries", "fries"])
	assert_eq(res["slice"]["restaurantId"], "burger_bau")
	assert_eq(res["slice"]["gerichtId"], "burger", "Alt-Feld bleibt gefüllt (Kompatibilität)")
	var slice: Dictionary = GooberandoLogic.tick(res["slice"], NOW + 180 * 1000)["slice"]
	var ueb := GooberandoLogic.uebergabe(slice, NOW + 200 * 1000)
	assert_true(ueb["ok"])
	assert_eq(ueb["gerichte"], ["burger", "fries", "fries"])
	# Gutschrift wie im App-Code (_gib_essen je Id): EXAKTE Stückzahlen.
	var food := {}
	for id: Variant in ueb["gerichte"]:
		food[str(id)] = int(food.get(str(id), 0)) + 1
	assert_eq(food, {"burger": 1, "fries": 2}, "Bestellung → Inventar-Gutschrift exakt")
	var tg := GooberandoLogic.trinkgeld(ueb["slice"], NOW + 210 * 1000, true, 0.9)
	assert_eq(tg["slice"]["state"], "idle")
	assert_eq(tg["slice"]["gerichte"], [], "Korb nach Lieferung geräumt")
	assert_eq(tg["slice"]["restaurantId"], "")


func test_bestellen_einzeln_bleibt_kompatibel() -> void:
	var res := GooberandoLogic.bestellen(
		GooberandoLogic.default_slice(), NOW, 60, {"id": "pizza", "preis": 30}
	)
	assert_true(res["ok"])
	assert_eq(res["kosten"], 33)
	assert_eq(res["slice"]["gerichte"], ["pizza"], "Einzelgericht = Ein-Gericht-Korb")


func test_abgestellt_liefert_ganzen_warenkorb() -> void:
	var korb := [
		GooberandoRestaurants.gericht("moehrenschmiede", "carrot"),
		GooberandoRestaurants.gericht("moehrenschmiede", "salad"),
	]
	var slice: Dictionary = (
		GooberandoLogic
		. bestellen_korb(GooberandoLogic.default_slice(), NOW, 60, korb, "moehrenschmiede")["slice"]
	)
	# EIN Recovery-Tick wickelt beides ab: erst Klingel, dann Abstellen.
	var res := GooberandoLogic.tick(slice, NOW + 60 * 1000 + 301 * 1000)
	assert_eq(res["events"].size(), 2)
	assert_eq(res["events"][0]["typ"], "vor_der_tuer")
	assert_eq(res["events"][1]["typ"], "abgestellt")
	assert_eq(res["events"][1]["gerichte"], ["carrot", "salad"], "Tüte enthält ALLES")
	assert_eq(res["slice"]["state"], "idle")


func test_normalize_altsave_ohne_warenkorb() -> void:
	var healed := GooberandoLogic.normalize_slice({"state": "bestellt", "gerichtId": "pizza"})
	assert_eq(healed["gerichte"], ["pizza"], "Alt-Save: gerichtId wird zum Ein-Gericht-Korb")
	assert_eq(healed["restaurantId"], "")
	assert_eq(GooberandoLogic.normalize_slice(42)["gerichte"], [])


## ------------------------------------------------------- Guber-Politur


func test_guber_kostet_30() -> void:
	assert_eq(Fahrdienst.kosten(Fahrdienst.GUBER), 30, "Doc E §4: Guber = 30 Münzen")


func test_surge_fenster_mathe() -> void:
	assert_false(Fahrdienst.ist_stosszeit(17.99), "17:59 ist noch keine Stoßzeit")
	assert_true(Fahrdienst.ist_stosszeit(18.0))
	assert_true(Fahrdienst.ist_stosszeit(19.5))
	assert_false(Fahrdienst.ist_stosszeit(20.0), "20:00 ist schon Feierabend")
	assert_false(Fahrdienst.ist_stosszeit(0.0))


func test_surge_preis_nur_fuer_guber() -> void:
	assert_eq(Fahrdienst.kosten_zur_stunde(Fahrdienst.GUBER, 12.0), 30)
	assert_eq(Fahrdienst.kosten_zur_stunde(Fahrdienst.GUBER, 19.0), 45, "Stoßzeit = 45")
	assert_eq(
		Fahrdienst.kosten_zur_stunde(Fahrdienst.TAXI, 19.0),
		TaxiLogic.KOSTEN,
		"das Taxi bleibt ehrlich"
	)


func test_surge_erstattung_vom_bezahlten_preis() -> void:
	assert_eq(Fahrdienst.erstattung_fuer(45, false), 43, "Surge-Storno: 45 − 2")
	assert_eq(Fahrdienst.erstattung_fuer(45, true), 40, "Surge-Verpasst: 45 − 5")
	assert_eq(Fahrdienst.erstattung(Fahrdienst.GUBER, false), 28, "Basis-Storno: 30 − 2")
