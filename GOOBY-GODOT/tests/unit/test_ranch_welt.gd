extends TestCase
## RANCH-1 — Weltdaten-Integrität: die Pläne aus RanchWelt (Riesenfeld +
## Überlandfahrt) sind deterministisch, kollisionsfrei und deutlich größer
## als die Stadt (User-Wunsch „Riesen Feld“). Kein Renderer nötig — die
## Pläne sind PURE Daten.

## Stadtmaße aus city_map.json: 15×12 Tiles à 20 m.
const STADT_BREITE_M := 300.0
const STADT_TIEFE_M := 240.0


func test_hof_plan_ist_integer() -> void:
	var plan := RanchWelt.hof_plan()
	var probleme := RanchWelt.plan_probleme(plan)
	assert_eq(probleme, [] as Array[String], "Hof-Plan ohne Befunde: %s" % str(probleme))


func test_fahrt_plan_ist_integer() -> void:
	var plan := RanchWelt.fahrt_plan()
	var probleme := RanchWelt.fahrt_probleme(plan)
	assert_eq(probleme, [] as Array[String], "Fahrt-Plan ohne Befunde: %s" % str(probleme))


func test_riesenfeld_ist_groesser_als_die_stadt() -> void:
	var daten := RanchWelt.welt_daten()
	assert_true(float(daten["feld_breite_m"]) > STADT_BREITE_M, "Feld breiter als die Stadtkacheln")
	assert_true(float(daten["feld_tiefe_m"]) > STADT_TIEFE_M, "Feld tiefer als die Stadtkacheln")


func test_plaene_sind_deterministisch() -> void:
	var a := RanchWelt.hof_plan()
	var b := RanchWelt.hof_plan()
	assert_eq(a["baeume"], b["baeume"], "gleicher Seed = gleiche Baeume")
	var fa := RanchWelt.fahrt_plan()
	var fb := RanchWelt.fahrt_plan()
	assert_eq(fa["heuballen"], fb["heuballen"], "gleicher Seed = gleiche Heuballen")
	assert_eq(fa["felder"].size(), fb["felder"].size())


func test_fahrt_hat_alle_zutaten() -> void:
	var plan := RanchWelt.fahrt_plan()
	assert_true((plan["felder"] as Array).size() >= 8, "Felderreihen links+rechts")
	assert_true((plan["heuballen"] as Array).size() >= 6, "Heuballen")
	assert_true((plan["baeume"] as Array).size() >= 10, "Baumreihen")
	assert_true((plan["kuehe"] as Array).size() >= 2, "Kuehe auf der Weide")
	assert_true((plan["schafe"] as Array).size() >= 3, "Schafe auf der Weide")
	assert_true(float(plan["laenge"]) >= 400.0, "echte Fahrstrecke, kein Ladebildschirm")
	assert_eq(int(plan["schild_km"]), 8, "Schild sagt 8 km (User-Wunsch)")


func test_zaun_ring_laesst_torluecke() -> void:
	var rect := Rect2(0.0, 0.0, 26.0, 26.0)
	var ohne_tor := RanchWelt.zaun_ring(rect, 2.6, "")
	var mit_tor := RanchWelt.zaun_ring(rect, 2.6, "sued")
	assert_true(mit_tor.size() < ohne_tor.size(), "Tor-Seite laesst Latten weg")
	# Kein Segment mit Tor darf in der Süd-Lücke liegen.
	for eintrag: Dictionary in mit_tor:
		var pos: Vector3 = eintrag["pos"]
		if absf(pos.z - rect.end.y) < 0.01:
			assert_true(absf(pos.x - rect.get_center().x) > 2.9, "Luecke bleibt frei")


func test_gebaeude_groessen_sind_definiert() -> void:
	for id: String in ["scheune", "stall", "haus", "heulager"]:
		var groesse := RanchWelt.gebaeude_groesse(id)
		assert_true(groesse.x > 0.0 and groesse.y > 0.0 and groesse.z > 0.0, id)
	assert_true(RanchWelt.gebaeude_groesse("unbekannt").x > 0.0, "Fallback-Fussabdruck")
