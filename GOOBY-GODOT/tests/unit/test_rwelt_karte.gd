extends TestCase
## RW-1 — Karten-Integrität + Zonen-Abfragen der Ranch-Region: die Karte
## (ranch_karte.json) ist datengetrieben, vollständig (alle Pflichtzonen),
## kollisionsfrei und für andere Agents abfragbar (Spawns, Wege,
## Begehbarkeit). PURE Daten — kein Renderer nötig.

const PFLICHT_ZONEN: Array[String] = [
	"hof",
	"weidetal",
	"waeldchen",
	"see",
	"huegelkamm",
	"bachlauf",
	"scheune_alt",
	"turnierplatz",
	"hufingen",
]


func test_karte_ist_integer() -> void:
	var probleme := RanchKarte.probleme()
	assert_eq(probleme, [] as Array[String], "Karte ohne Befunde: %s" % str(probleme))


func test_alle_pflichtzonen_vorhanden() -> void:
	var ids := RanchKarte.zonen_ids()
	for zone_id: String in PFLICHT_ZONEN:
		assert_true(ids.has(zone_id), "Pflichtzone %s" % zone_id)


func test_zone_bei_findet_zonen_und_freies_land() -> void:
	assert_eq(RanchKarte.zone_bei(Vector3(0.0, 0.0, 0.0)), "hof")
	assert_eq(RanchKarte.zone_bei(Vector3(-380.0, 0.0, 90.0)), "weidetal")
	assert_eq(RanchKarte.zone_bei(Vector3(500.0, 0.0, 270.0)), "see")
	assert_eq(RanchKarte.zone_bei(Vector3(160.0, 0.0, -510.0)), "huegelkamm")
	# Zwischen Hof und Hügelkamm liegt freies Land.
	assert_eq(RanchKarte.zone_bei(Vector3(0.0, 0.0, -250.0)), "")


func test_spawn_punkte_liegen_in_der_zone_und_sind_begehbar() -> void:
	for zone_id: String in PFLICHT_ZONEN:
		var spawn := RanchKarte.spawn_punkt(zone_id)
		var rect := RanchKarte.zone_rect(RanchKarte.zone(zone_id))
		assert_true(rect.has_point(Vector2(spawn.x, spawn.z)), "%s: Spawn in Zone" % zone_id)
		assert_true(RanchKarte.ist_begehbar(spawn), "%s: Spawn begehbar" % zone_id)


func test_wegpunkte_verbinden_zonen_in_beide_richtungen() -> void:
	var hin := RanchKarte.wegpunkte("hof", "see")
	var zurueck := RanchKarte.wegpunkte("see", "hof")
	assert_true(hin.size() >= 2, "Weg hof→see existiert")
	assert_eq(hin.size(), zurueck.size(), "gleiche Punkte in Gegenrichtung")
	if not hin.is_empty() and not zurueck.is_empty():
		assert_eq(hin[0], zurueck[zurueck.size() - 1], "Gegenrichtung ist gespiegelt")
	assert_eq(RanchKarte.wegpunkte("see", "waeldchen").size(), 0, "kein Direktweg")


func test_jede_zone_ist_vom_hof_erreichbar() -> void:
	# Breitensuche über nachbarn(): die Region hängt zusammen (keine Insel).
	var offen: Array[String] = ["hof"]
	var gesehen: Array[String] = ["hof"]
	while not offen.is_empty():
		var zone_id: String = offen.pop_front()
		for nachbar: String in RanchKarte.nachbarn(zone_id):
			if not gesehen.has(nachbar):
				gesehen.append(nachbar)
				offen.append(nachbar)
	for zone_id: String in PFLICHT_ZONEN:
		assert_true(gesehen.has(zone_id), "%s erreichbar" % zone_id)


func test_ist_begehbar_blockiert_wasser_und_grenzen() -> void:
	assert_true(RanchKarte.ist_begehbar(Vector3(0.0, 0.0, 100.0)), "Hofweg begehbar")
	assert_false(RanchKarte.ist_begehbar(Vector3(500.0, 0.0, 270.0)), "Seemitte blockiert")
	assert_false(RanchKarte.ist_begehbar(Vector3(9999.0, 0.0, 0.0)), "außerhalb blockiert")
	var bach: Dictionary = RanchKarte.karte()["bach"]
	var furt: Array = bach["furt"]
	var bruecke: Array = bach["bruecke"]
	assert_true(
		RanchKarte.ist_begehbar(RanchKarte.punkt(float(furt[0]), float(furt[1]))), "Furt begehbar"
	)
	assert_true(
		RanchKarte.ist_begehbar(RanchKarte.punkt(float(bruecke[0]), float(bruecke[1]))),
		"Brücke begehbar"
	)


func test_hoehenabfrage_liefert_fertige_punkte() -> void:
	var p := RanchKarte.punkt(160.0, -510.0)
	assert_almost(p.y, RanchGelaende.hoehe(160.0, -510.0), 0.0001, "punkt() nutzt Bodenhöhe")
	assert_almost(
		RanchKarte.hoehe(-380.0, 90.0),
		RanchGelaende.hoehe(-380.0, 90.0),
		0.0001,
		"hoehe() ist die Gelände-Höhe"
	)


func test_karte_ist_deterministisch() -> void:
	var a := RanchKarte.spawn_punkt("waeldchen")
	RanchKarte.reset_for_tests()
	var b := RanchKarte.spawn_punkt("waeldchen")
	assert_eq(a, b, "Neuladen ändert nichts")
	assert_true(RanchKarte.seed_wert() != 0, "Welt-Seed gesetzt")
