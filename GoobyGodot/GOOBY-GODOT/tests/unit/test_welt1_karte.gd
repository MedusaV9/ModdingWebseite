extends TestCase
## WELT-1 — Zonen-Integrität des Welt-Ausbaus: die sieben NEUEN Zonen
## existieren mit Charakter-Daten, liegen kollisionsfrei in den neuen
## Grenzen, ihre Spawns sind begehbar, und das Wegenetz erreicht JEDE
## Zone vom Hof aus (Breitensuche über nachbarn()).

const NEUE_ZONEN: Array[String] = [
	"bergmassiv",
	"blumenwiese",
	"moor",
	"ruine",
	"strand",
	"obstgarten",
	"kornfeld",
]


func test_karte_bleibt_integer() -> void:
	assert_eq(RanchKarte.probleme(), [] as Array[String], "Karte ohne Befunde")


func test_grenzen_sind_gewachsen() -> void:
	var grenzen := RanchKarte.grenzen()
	assert_true(grenzen.size.x >= 1800.0, "Welt breit genug (%.0f m)" % grenzen.size.x)
	assert_true(grenzen.size.y >= 2200.0, "Welt tief genug (%.0f m)" % grenzen.size.y)


func test_neue_zonen_vorhanden_mit_charakter() -> void:
	for zone_id: String in NEUE_ZONEN:
		var zone := RanchKarte.zone(zone_id)
		assert_false(zone.is_empty(), "Zone %s existiert" % zone_id)
		assert_true(str(zone["name_key"]).begins_with("rwelt.zone."), "%s: name_key" % zone_id)
		assert_false(str(zone.get("stimmung", "")).is_empty(), "%s: eigene Stimmung" % zone_id)
		var spawn := RanchKarte.spawn_punkt(zone_id)
		assert_true(
			RanchKarte.zone_rect(zone).has_point(Vector2(spawn.x, spawn.z)),
			"%s: Spawn in der Zone" % zone_id
		)
		assert_true(RanchKarte.ist_begehbar(spawn), "%s: Spawn begehbar" % zone_id)


func test_neue_zonen_namen_sind_lokalisiert() -> void:
	for zone_id: String in NEUE_ZONEN:
		var key := "rwelt.zone.%s" % zone_id
		var text := I18nService.t(key)
		assert_true(text != key and not text.is_empty(), "Key %s übersetzt" % key)


func test_jede_zone_vom_hof_erreichbar() -> void:
	var offen: Array[String] = ["hof"]
	var gesehen: Array[String] = ["hof"]
	while not offen.is_empty():
		var zone_id: String = offen.pop_front()
		for nachbar: String in RanchKarte.nachbarn(zone_id):
			if not gesehen.has(nachbar):
				gesehen.append(nachbar)
				offen.append(nachbar)
	for zone_id: String in RanchKarte.zonen_ids():
		assert_true(gesehen.has(zone_id), "%s über das Wegenetz erreichbar" % zone_id)


func test_wege_zu_neuen_zonen_sind_reitbar() -> void:
	# Jeder Wegpunkt begehbar UND die Steigung zwischen 2-m-Schritten
	# entlang des Weges bleibt unter 60 % (Serpentine statt Kletterwand).
	for weg: Dictionary in RanchKarte.wege():
		var punkte := RanchKarte.wegpunkte(str(weg["von"]), str(weg["nach"]))
		var schlimmste := 0.0
		for i in punkte.size() - 1:
			var a := punkte[i]
			var b := punkte[i + 1]
			var schritte := maxi(1, int(a.distance_to(b) / 2.0))
			for s in schritte:
				var p0 := a.lerp(b, float(s) / float(schritte))
				var p1 := a.lerp(b, float(s + 1) / float(schritte))
				var flach := Vector2(p1.x - p0.x, p1.z - p0.z).length()
				var steigung := (
					absf(
						RanchGelaende.reit_hoehe(p1.x, p1.z) - RanchGelaende.reit_hoehe(p0.x, p0.z)
					)
					/ maxf(flach, 0.5)
				)
				schlimmste = maxf(schlimmste, steigung)
		assert_true(schlimmste < 0.6, "%s reitbar (max. Steigung %.2f)" % [weg["id"], schlimmste])


func test_schlucht_und_bruecke_sind_definiert() -> void:
	var karte := RanchKarte.karte()
	assert_true(karte.has("schlucht"), "Schlucht in der Karte")
	assert_true(RanchKarte.bruecken().size() >= 1, "Hängebrücke in der Karte")
	var bruecke: Dictionary = RanchKarte.bruecken()[0]
	var a: Array = bruecke["a"]
	var b: Array = bruecke["b"]
	var mitte := Vector2((float(a[0]) + float(b[0])) / 2.0, (float(a[1]) + float(b[1])) / 2.0)
	assert_true(RanchGelaende.schlucht_kerbe(mitte.x, mitte.y) > 6.0, "Brücke quert echte Tiefe")
