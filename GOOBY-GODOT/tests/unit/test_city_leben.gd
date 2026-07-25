extends TestCase
## M2/ORTE — Stadt-Feinschliff: Fußgänger-Routen (pur, deterministisch),
## Beinahe-Unfall-Schwelle für die Hupe, Nacht-Glow der Ladenschilder und
## die Minimap-Projektion inkl. Orts-Pins.


func test_fussgaenger_routen_sind_deterministisch() -> void:
	var karte := CityMap.laden()
	var a := CityFussgaenger.routen(karte, 5, 4242)
	var b := CityFussgaenger.routen(karte, 5, 4242)
	assert_eq(a.size(), 5, "fünf Spaziergänger")
	for i in a.size():
		assert_eq(a[i]["von"], b[i]["von"], "Route %d startet gleich" % i)
		assert_eq(a[i]["nach"], b[i]["nach"], "Route %d endet gleich" % i)
	assert_ne(CityFussgaenger.routen(karte, 5, 9), a, "anderer Seed ⇒ andere Runde")


func test_fussgaenger_bleiben_im_budget_und_auf_der_karte() -> void:
	var karte := CityMap.laden()
	var halb := karte.welt_halb()
	var routen := CityFussgaenger.routen(karte, 99, 1)
	assert_eq(routen.size(), CityFussgaenger.MAX_GOOBYS, "Mobile-Budget deckelt die Menge")
	for route in routen:
		for punkt: Vector3 in [route["von"], route["nach"]]:
			assert_true(absf(punkt.x) <= halb.x, "x innerhalb der Karte")
			assert_true(absf(punkt.z) <= halb.y, "z innerhalb der Karte")
		assert_true(float(route["laenge"]) > 0.0, "Route hat Länge")
		assert_true(
			(
				float(route["tempo"]) >= CityFussgaenger.TEMPO_MIN
				and float(route["tempo"]) <= CityFussgaenger.TEMPO_MAX
			),
			"Gehtempo im Fenster"
		)


func test_fussgaenger_gehen_neben_der_fahrbahn() -> void:
	var karte := CityMap.laden()
	for route in CityFussgaenger.routen(karte, 6, 77):
		for ende: Vector3 in [route["von"], route["nach"]]:
			var tile := karte.welt_zu_tile(ende)
			assert_true(karte.ist_strasse(tile), "Gehweg gehört zu einem Straßen-Tile")
			var zentrum := karte.tile_zu_welt(tile)
			var abstand := Vector2(ende.x, ende.z).distance_to(Vector2(zentrum.x, zentrum.z))
			assert_almost(abstand, CityFussgaenger.GEHWEG_M, 0.01, "seitlich neben der Fahrbahn")


func test_fussgaenger_laufen_ping_pong() -> void:
	var route := {"von": Vector3(0, 0, 0), "nach": Vector3(10, 0, 0), "laenge": 10.0, "tempo": 1.0}
	assert_eq(CityFussgaenger.punkt(route, 0.0)["pos"], Vector3(0, 0, 0), "Start")
	assert_eq(CityFussgaenger.punkt(route, 0.5)["pos"], Vector3(5, 0, 0), "halber Hinweg")
	assert_eq(CityFussgaenger.punkt(route, 1.0)["pos"], Vector3(10, 0, 0), "Wendepunkt")
	assert_eq(CityFussgaenger.punkt(route, 1.5)["pos"], Vector3(5, 0, 0), "halber Rückweg")
	assert_eq(CityFussgaenger.punkt(route, 2.0)["pos"], Vector3(0, 0, 0), "wieder daheim")
	assert_eq(CityFussgaenger.punkt(route, 4.5)["pos"], Vector3(5, 0, 0), "Runden wiederholen sich")
	var hin := float(CityFussgaenger.punkt(route, 0.5)["heading"])
	var zurueck := float(CityFussgaenger.punkt(route, 1.5)["heading"])
	assert_ne(hin, zurueck, "auf dem Rückweg schaut er andersrum")


func test_fussgaenger_fortschritt_folgt_dem_tempo() -> void:
	var route := {"von": Vector3.ZERO, "nach": Vector3(10, 0, 0), "laenge": 10.0, "tempo": 2.0}
	assert_almost(CityFussgaenger.fortschritt(route, 5.0), 1.0, 1e-6, "10 m bei 2 m/s = 5 s")
	route["phase"] = 0.5
	assert_almost(CityFussgaenger.fortschritt(route, 0.0), 1.0, 1e-6, "Phase versetzt den Start")


func test_leere_karte_liefert_keine_routen() -> void:
	assert_eq(CityFussgaenger.routen(null, 3, 1).size(), 0)
	assert_eq(CityFussgaenger.routen(CityMap.new(), 3, 1).size(), 0, "ungeladene Karte")


func test_near_miss_braucht_naehe_und_tempo() -> void:
	var nah := CityAmbiente.NEAR_MISS_M - 1.0
	var schnell := CityAmbiente.NEAR_MISS_TEMPO + 1.0
	assert_true(CityAmbiente.ist_beinahe(nah, schnell), "knapp + schnell = Hupe")
	assert_false(CityAmbiente.ist_beinahe(nah, 0.5), "im Schritttempo hupt keiner")
	assert_false(CityAmbiente.ist_beinahe(CityAmbiente.NEAR_MISS_M + 1.0, schnell), "zu weit weg")
	assert_true(CityAmbiente.ist_beinahe(nah, -schnell), "rückwärts zählt auch")
	assert_true(CityAmbiente.NEAR_MISS_PAUSE_S > 0.0, "Sperrzeit gegen Hupkonzert")
	for key in ["city.fahren.beinahe", "city.fahren.beinahe_hupe"]:
		assert_ne(I18nService.t(key), key, "Near-Miss-Text fehlt: %s" % key)


func test_ladenschilder_leuchten_nur_nachts() -> void:
	assert_eq(CityAmbiente.schild_farbe(false), AcTokens.INK, "tagsüber Theme-Tinte")
	var nachts := CityAmbiente.schild_farbe(true)
	assert_true(nachts.r > 0.9 and nachts.b < nachts.r, "nachts warmes Neon")
	assert_true(CityAmbiente.licht_profil(23.0)["lichter_an"], "nachts geht der Glow an")
	assert_false(CityAmbiente.licht_profil(12.0)["lichter_an"], "mittags nicht")


func test_minimap_projektion_und_pins() -> void:
	var karte := CityMap.laden()
	var map := CityMinimap.new()
	map.karte = karte
	map.aktualisiere_pins()
	var pins := map.pins()
	assert_eq(pins.size(), karte.orte().size() + 1, "jeder Ort + Zuhause bekommt einen Pin")
	var ids: Array[String] = []
	for pin in pins:
		ids.append(str(pin["id"]))
		var px: Vector2 = map.welt_zu_pixel(pin["welt"])
		assert_true(
			px.x >= 0.0 and px.x <= CityMinimap.GROESSE, "Pin %s liegt in der Kachel" % pin["id"]
		)
		assert_true(px.y >= 0.0 and px.y <= CityMinimap.GROESSE)
	assert_true(ids.has("zuhause"), "Zuhause ist markiert")
	for id in ["pow", "post", "autohaus", "baumarkt", "wochenmarkt"]:
		assert_true(ids.has(id), "Pin fehlt: %s" % id)
	var mitte := map.welt_zu_pixel(Vector3.ZERO)
	assert_almost(mitte.x, CityMinimap.GROESSE * 0.5, 0.001, "Weltmitte = Kachelmitte")
	assert_almost(mitte.y, CityMinimap.GROESSE * 0.5, 0.001)
	map.free()
