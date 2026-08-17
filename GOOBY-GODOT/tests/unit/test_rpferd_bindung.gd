extends TestCase
## RW-2 — Bindungs-Level 1-10 (RanchHorseBond, IDEAS-1 A1 + IDEAS-3 Kap.
## 1.4): Level-Mapping aus der 0-100-Bindung, jede Stufe schaltet etwas
## SPUERBARES frei, Pfiff-Reichweite/Zweiter-Wind/Rutsch-Stopp-Formeln,
## Naechste-Freischaltung-UI und DE/EN-String-Paritaet der Unlock-Ids.

const Bond := preload("res://scripts/ranch/gameplay/horse_bond.gd")


func test_level_mapping_aus_bindung() -> void:
	assert_eq(Bond.level_fuer_bindung(0.0), 1)
	assert_eq(Bond.level_fuer_bindung(9.99), 1)
	assert_eq(Bond.level_fuer_bindung(10.0), 2)
	assert_eq(Bond.level_fuer_bindung(55.0), 6)
	assert_eq(Bond.level_fuer_bindung(90.0), 10)
	assert_eq(Bond.level_fuer_bindung(100.0), 10, "gedeckelt bei 10")
	assert_eq(Bond.level_fuer_bindung(-5.0), 1, "negativ geklemmt")


func test_jede_stufe_ab_2_schaltet_genau_eins_frei() -> void:
	assert_eq(Bond.freischaltungen_bis(1).size(), 0, "Level 1 = Kennenlernen")
	for level in range(2, Bond.LEVEL_MAX + 1):
		var vorher := Bond.freischaltungen_bis(level - 1).size()
		var jetzt := Bond.freischaltungen_bis(level)
		assert_eq(jetzt.size(), vorher + 1, "Level %d schaltet genau 1 Ding frei" % level)
		assert_eq(str(jetzt[-1]), str(Bond.FREISCHALTUNGEN[level]), "Reihenfolge = Level")
	assert_eq(Bond.freischaltungen_bis(10).size(), 9, "9 Freischaltungen insgesamt")


func test_ist_frei_folgt_der_bindung() -> void:
	assert_false(Bond.ist_frei(0.0, "maennchen"))
	assert_true(Bond.ist_frei(10.0, "maennchen"), "L2 ab Bindung 10")
	assert_false(Bond.ist_frei(59.0, "autopilot"))
	assert_true(Bond.ist_frei(60.0, "autopilot"), "L7 ab Bindung 60")
	assert_true(Bond.ist_frei(90.0, "seelenpferd_aura"), "L10 ab Bindung 90")
	assert_false(Bond.ist_frei(100.0, "gibtsnicht"))


func test_pfiff_reichweite_waechst_mit_bindung() -> void:
	assert_almost(Bond.pfiff_reichweite_m(29.0), 0.0, 1e-6, "vor L4 kein Pfiff")
	assert_almost(Bond.pfiff_reichweite_m(30.0), 20.0 + 30.0 * 0.6, 1e-6)
	assert_almost(Bond.pfiff_reichweite_m(100.0), 80.0, 1e-6)
	assert_true(
		Bond.pfiff_reichweite_m(80.0) > Bond.pfiff_reichweite_m(40.0), "Reichweite waechst weiter"
	)


func test_zweiter_wind_und_rutsch_stopp_boni() -> void:
	assert_almost(Bond.zweiter_wind_bonus(40.0, 25.0), 25.0, 1e-6, "vor L6 Basis")
	assert_almost(Bond.zweiter_wind_bonus(50.0, 25.0), 35.0, 1e-6, "ab L6 Plus-Wert")
	assert_almost(Bond.brems_bonus(19.0), 0.0, 1e-6, "vor L3 kein Rutsch-Stopp")
	assert_almost(Bond.brems_bonus(20.0), 1.5, 1e-6, "ab L3 williger bremsen")


func test_naechste_freischaltung_fuer_die_ui() -> void:
	var start := Bond.naechste_freischaltung(0.0)
	assert_eq(int(start["level"]), 2)
	assert_eq(str(start["id"]), "maennchen")
	assert_almost(float(start["fehlt"]), 10.0, 1e-6)
	var fast := Bond.naechste_freischaltung(85.0)
	assert_eq(int(fast["level"]), 10)
	assert_eq(str(fast["id"]), "seelenpferd_aura")
	assert_almost(float(fast["fehlt"]), 5.0, 1e-6)
	assert_true(Bond.naechste_freischaltung(95.0).is_empty(), "alles offen = leer")


func test_unlock_ids_haben_de_en_strings() -> void:
	var de := _bindung_strings("res://strings/de/rpferd.json")
	var en := _bindung_strings("res://strings/en/rpferd.json")
	for level: int in Bond.FREISCHALTUNGEN:
		var id := str(Bond.FREISCHALTUNGEN[level])
		assert_true(de.has(id), "DE-Text fuer rpferd.bindung.%s" % id)
		assert_true(en.has(id), "EN-Text fuer rpferd.bindung.%s" % id)
	assert_eq(de.keys().size(), en.keys().size(), "DE/EN paritaetisch")


func _bindung_strings(pfad: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(pfad)
	var daten: Variant = JSON.parse_string(text)
	if not (daten is Dictionary):
		return {}
	var rpferd: Variant = (daten as Dictionary).get("rpferd", {})
	if not (rpferd is Dictionary):
		return {}
	var bindung: Variant = (rpferd as Dictionary).get("bindung", {})
	return bindung if bindung is Dictionary else {}
