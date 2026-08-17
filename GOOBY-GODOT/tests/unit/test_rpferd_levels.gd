extends TestCase
## RW-2 — Level & Training (RanchHorseLevels): Doc-Kurve XP(L→L+1) =
## 30·L + L², Ritt-Tagesdeckel, Trainingsraten, Frische-Bremse,
## Level-Gate der Punktevergabe, Hafermash und Meilenstein-Geschenke.

const Levels := preload("res://scripts/ranch/gameplay/horse_levels.gd")

const TAG := "2026-07-26"


func _pferd(felder: Dictionary = {}) -> Dictionary:
	var p := RanchPlaySlices.neues_pferd("Testhorst", "braun")
	p.merge(felder, true)
	return p


func test_xp_kurve_folgt_dem_doc() -> void:
	assert_almost(Levels.xp_fuer_level(1), 31.0, 1e-6, "L1→2 = 31")
	assert_almost(Levels.xp_fuer_level(10), 400.0)
	assert_almost(Levels.xp_fuer_level(29), 1711.0, 1e-6, "L29→30 = 1711")
	assert_almost(Levels.xp_summe_bis(30), 21605.0, 1e-6, "Σ 1→30 ≈ 21 600")
	assert_eq(Levels.level_fuer_xp(0.0), 1)
	assert_eq(Levels.level_fuer_xp(30.9), 1)
	assert_eq(Levels.level_fuer_xp(31.0), 2)
	assert_eq(Levels.level_fuer_xp(999999.0), 30, "Deckel bei 30")
	var fortschritt := Levels.level_fortschritt(31.0 + 10.0)
	assert_eq(int(fortschritt["level"]), 2)
	assert_almost(float(fortschritt["im_level"]), 10.0)
	assert_almost(float(fortschritt["noetig"]), 64.0)


func test_ritt_xp_tagesdeckel_und_reset() -> void:
	var erst := Levels.xp_buchen(_pferd(), 50.0, "ritt", TAG)
	assert_almost(float(erst["gewinn"]), 50.0)
	var zweit := Levels.xp_buchen(erst["pferd"], 50.0, "ritt", TAG)
	assert_almost(float(zweit["gewinn"]), 10.0, 1e-6, "Deckel 60/Tag")
	var dritt := Levels.xp_buchen(zweit["pferd"], 50.0, "ritt", "2026-07-27")
	assert_almost(float(dritt["gewinn"]), 50.0, 1e-6, "neuer Tag = neuer Deckel")
	var stern := Levels.xp_buchen(zweit["pferd"], 20.0, "stern", TAG)
	assert_almost(float(stern["gewinn"]), 20.0, 1e-6, "Sterne-XP ohne Ritt-Deckel")


func test_levelups_und_meilensteine() -> void:
	var p := _pferd({"xp": Levels.xp_summe_bis(5) - 1.0})
	p["level"] = Levels.level_fuer_xp(p["xp"])
	var ergebnis := Levels.xp_buchen(p, 2.0, "direkt", TAG)
	assert_eq(ergebnis["levelUps"], [5], "genau ein Level-Up auf 5")
	assert_eq(ergebnis["meilensteine"], ["schleife_jungstar"], "Meilenstein 5")
	var gross := Levels.xp_buchen(_pferd(), Levels.xp_summe_bis(11), "direkt", TAG)
	assert_true((gross["meilensteine"] as Array).has("maehnenfrisur"), "Meilenstein 10 im Sprung")


func test_stat_gate_und_punktkosten() -> void:
	assert_eq(Levels.stat_gate(1), 1)
	assert_eq(Levels.stat_gate(3), 1)
	assert_eq(Levels.stat_gate(4), 2)
	assert_eq(Levels.stat_gate(30), 10)
	assert_almost(Levels.punkt_kosten(0), 100.0)
	assert_almost(Levels.punkt_kosten(1), 140.0)
	assert_almost(Levels.punkt_kosten(2), 196.0)


func test_stat_xp_vergibt_punkte_mit_gate() -> void:
	var p := _pferd({"level": 3})
	var eins := Levels.stat_xp_buchen(p, "tempo", 250.0, 0.0, TAG)
	assert_eq(int(eins["neue_punkte"]), 1, "Level 3 = Gate 1: nur 1 Punkt")
	var pferd: Dictionary = eins["pferd"]
	assert_eq(int(pferd["trainiert"]["tempo"]), 1)
	assert_almost(
		float(pferd["statXp"]["tempo"]), 140.0, 1e-6, "Ueberlauf gebankt (Deckel 1 Punkt Vorrat)"
	)
	pferd["level"] = 6
	var zwei := Levels.stat_xp_buchen(pferd, "tempo", 0.0, 0.0, TAG)
	assert_eq(int(zwei["neue_punkte"]), 1, "hoeheres Gate reift den Bank-Punkt")
	assert_eq(Levels.stat_wert(zwei["pferd"], "tempo"), 12, "10 Basis + 2 trainiert")


func test_frische_bremst_und_verbraucht_sich() -> void:
	assert_almost(Levels.frische_faktor(100.0), 1.0)
	assert_almost(Levels.frische_faktor(0.0), 0.15, 1e-6, "Boden 15 %")
	var p := _pferd()
	var eine_einheit := Levels.stat_xp_buchen(p, "ausdauer", 10.0, 180.0, TAG)
	var pferd: Dictionary = eine_einheit["pferd"]
	assert_almost(float(pferd["frische"]["ausdauer"]), 65.0, 1e-6, "eine Einheit = −35")
	assert_almost(float(eine_einheit["xp_effektiv"]), 10.0, 1e-6, "volle Frische = voller Ertrag")
	pferd["frische"]["ausdauer"] = 0.0
	var muede := Levels.stat_xp_buchen(pferd, "ausdauer", 10.0, 0.0, TAG)
	assert_almost(float(muede["xp_effektiv"]), 1.5, 1e-6, "leere Frische = 15 %")


func test_fleissig_verbraucht_weniger_frische() -> void:
	var p := _pferd({"charakter": ["fleissig", "mutig"]})
	var ergebnis := Levels.stat_xp_buchen(p, "tempo", 5.0, 180.0, TAG)
	assert_almost(
		float((ergebnis["pferd"] as Dictionary)["frische"]["tempo"]), 70.0, 1e-6, "−30 statt −35"
	)


func test_hafermash_einmal_pro_tag_und_wert() -> void:
	# frischeTag = TAG, sonst wuerde der Tageswechsel die Frische fuellen.
	var p := _pferd({"frischeTag": TAG})
	p["frische"] = {"tempo": 50.0}
	var erst := Levels.hafermash(p, "tempo", TAG)
	assert_true(bool(erst["ok"]))
	assert_almost(float((erst["pferd"] as Dictionary)["frische"]["tempo"]), 75.0)
	var zweit := Levels.hafermash(erst["pferd"], "tempo", TAG)
	assert_false(bool(zweit["ok"]), "gleicher Tag + Wert = gesperrt")
	var anderer := Levels.hafermash(erst["pferd"], "ausdauer", TAG)
	assert_true(bool(anderer["ok"]), "anderer Wert geht noch")


func test_ritt_training_bucht_alle_kanaele() -> void:
	var telemetrie := {
		"galopp_m": 500.0,
		"galopp_s": 60.0,
		"unterwegs_min": 5.0,
		"sprung_gut": 2,
		"sprung_perfekt": 1,
		"slalom_tore": 3,
		"schritt_laune_min": 2.0,
	}
	var ergebnis := Levels.ritt_training(_pferd(), telemetrie, TAG)
	var pferd: Dictionary = ergebnis["pferd"]
	var statxp: Dictionary = pferd["statXp"]
	assert_almost(float(statxp["tempo"]), 10.0, 1e-6, "500 m Galopp = 10 Tempo-XP")
	assert_true(float(statxp["ausdauer"]) > 0.0, "Minuten zahlen auf Ausdauer ein")
	assert_true(float(statxp["sprungkraft"]) > 0.0, "2×4 + 1×8 Sprung-XP (frischeskaliert)")
	assert_almost(float(statxp["wendigkeit"]), 6.0, 1e-6, "3 Tore × 2")
	assert_almost(float(statxp["gelassenheit"]), 6.0, 1e-6, "2 min Schritt × 3")
	assert_almost(float(pferd["xp"]), 20.0, 1e-6, "5 min × 4 Pferde-XP")
	assert_almost(float(pferd["rittXpHeute"]), 20.0)


func test_jungpferd_lernt_schneller_aber_gedeckelt() -> void:
	var p := _pferd({"alter": "jungpferd"})
	var ergebnis := Levels.stat_xp_buchen(p, "tempo", 10.0, 0.0, TAG)
	assert_almost(float(ergebnis["xp_effektiv"]), 12.0, 1e-6, "×1,2 Lern-Bonus")
	p["stats"]["tempo"] = 14
	p["trainiert"]["tempo"] = 4
	assert_eq(Levels.stat_wert(p, "tempo"), 15, "Jungpferd-Deckel 15")
	p["alter"] = "ausgewachsen"
	assert_eq(Levels.stat_wert(p, "tempo"), 18, "ausgewachsen wieder frei")
