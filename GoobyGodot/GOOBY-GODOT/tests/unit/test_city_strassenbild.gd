extends TestCase
## GOOBY-WELT/STADT — Straßenbild-Planer (EVAL-2026-08 B §2 „mehr Leben und
## Vielfalt"): Zebrastreifen liegen an den Ampel-Kreuzungen auf Fahrbahn-
## Höhe, Mülltonnen sind deterministisch und bunt, Haltestellen/Café stehen
## auf echten Straßen-Tiles und die Tauben streuen seed-stabil.


func test_zebrastreifen_an_den_ampeln() -> void:
	var karte := CityMap.laden()
	var streifen := CityStrassenDeko.zebra_transforms(karte)
	assert_false(streifen.is_empty(), "es gibt Zebrastreifen")
	assert_eq(streifen.size() % CityStrassenDeko.ZEBRA_STREIFEN, 0, "volle Übergänge à N Streifen")
	for t in streifen:
		assert_almost(t.origin.y, CityCarFeel.ROAD_Y + 0.03, 1e-4, "Streifen auf Fahrbahn-Höhe")


func test_muelltonnen_deterministisch_und_bunt() -> void:
	var karte := CityMap.laden()
	var tonnen := CityStrassenDeko.muelltonnen(karte)
	assert_false(tonnen.is_empty(), "Tonnen vorhanden")
	assert_eq(tonnen, CityStrassenDeko.muelltonnen(karte), "zweiter Lauf identisch")
	var farben: Dictionary = {}
	for tonne: Dictionary in tonnen:
		assert_true(CityStrassenDeko.TONNEN_FARBEN.has(tonne["farbe"]), "Palette eingehalten")
		farben[tonne["farbe"]] = true
	assert_true(farben.size() >= 2, "mehr als eine Tonnenfarbe im Stadtbild")


func test_haltestellen_und_cafe_geplant() -> void:
	var karte := CityMap.laden()
	var stopps := CityStrassenDeko.bushaltestellen(karte)
	assert_eq(stopps.size(), CityStrassenDeko.HALTESTELLEN.size(), "beide Haltestellen da")
	for eintrag: Dictionary in CityStrassenDeko.HALTESTELLEN:
		assert_true(karte.ist_strasse(eintrag["tile"]), "Haltestellen-Tile ist Straße")
	assert_true(karte.ist_strasse(CityStrassenDeko.CAFE_TILE), "Café-Tile ist Straße")
	assert_true(CityStrassenDeko.cafe(karte).has("pos"), "Café-Terrasse geplant")


func test_tauben_folgen_dem_seed() -> void:
	var karte := CityMap.laden()
	var tauben := CityStrassenDeko.tauben(karte, 99)
	var soll := CityStrassenDeko.TAUBEN_PLAETZE.size() * CityStrassenDeko.TAUBEN_JE_PLATZ
	assert_eq(tauben.size(), soll, "Grüppchen an jedem Platz")
	assert_eq(tauben, CityStrassenDeko.tauben(karte, 99), "gleicher Seed ⇒ gleiche Tauben")
	assert_ne(tauben, CityStrassenDeko.tauben(karte, 100), "anderer Seed ⇒ andere Streuung")


func test_ohne_karte_bleibt_alles_leer() -> void:
	assert_true(CityStrassenDeko.zebra_transforms(null).is_empty(), "Zebra-Wächter")
	assert_true(CityStrassenDeko.muelltonnen(null).is_empty(), "Tonnen-Wächter")
	assert_true(CityStrassenDeko.bushaltestellen(null).is_empty(), "Haltestellen-Wächter")
	assert_true(CityStrassenDeko.tauben(null, 1).is_empty(), "Tauben-Wächter")
	assert_true(CityStrassenDeko.cafe(null).is_empty(), "Café-Wächter")
