extends TestCase
## RANCH-2 — Pferde-Pflege & Bindung (RanchHorseCare): Verfalls-Kurven
## (wach/schlafend, Stall-Dreck, Weidezaun), Launen-Formel + Bänder,
## Futter-/Pflege-Deltas, Bindungs-Tagesdeckel und -Verfall, Stall-Mathe
## und die Reit-Perks.

const Care := preload("res://scripts/ranch/gameplay/horse_care.gd")


func test_clamp_wert_faengt_unsinn() -> void:
	assert_eq(Care.clamp_wert(150.0), 100.0)
	assert_eq(Care.clamp_wert(-3.0), 0.0)
	assert_eq(Care.clamp_wert(NAN), 0.0)
	assert_eq(Care.clamp_wert(INF), 0.0)
	assert_eq(Care.clamp_wert("kaputt"), 0.0)
	var werte := Care.clamp_werte({"hunger": 300, "durst": "x"})
	assert_eq(werte["hunger"], 100.0)
	assert_eq(werte["durst"], 0.0)
	assert_eq(werte["sauberkeit"], 0.0, "fehlende Werte fallen auf 0")


func test_tick_wach_verfaellt_mit_weide_raten() -> void:
	var werte := {"hunger": 80.0, "durst": 85.0, "sauberkeit": 75.0}
	var nach := Care.tick(werte, 10.0)
	assert_almost(float(nach["hunger"]), 77.5)
	assert_almost(float(nach["durst"]), 81.0)
	assert_almost(float(nach["sauberkeit"]), 73.5)
	assert_eq(werte["hunger"], 80.0, "Eingabe bleibt unberührt (pure)")


func test_tick_schlafend_zehrt_weniger_aber_macht_schmutzig() -> void:
	var werte := {"hunger": 80.0, "durst": 85.0, "sauberkeit": 75.0}
	var nach := Care.tick(werte, 10.0, {"schlaeft": true})
	assert_almost(float(nach["hunger"]), 79.2)
	assert_almost(float(nach["durst"]), 83.5)
	assert_almost(float(nach["sauberkeit"]), 73.0)


func test_dreckiger_stall_verdoppelt_nur_im_stall() -> void:
	var werte := {"hunger": 50.0, "durst": 50.0, "sauberkeit": 50.0}
	var im_stall := Care.tick(werte, 10.0, {"schlaeft": true, "stallSauberkeit": 30.0})
	assert_almost(float(im_stall["sauberkeit"]), 46.0, 1e-6, "0.2 · 2 = 0.4/min")
	var auf_weide := Care.tick(werte, 10.0, {"stallSauberkeit": 30.0})
	assert_almost(
		float(auf_weide["sauberkeit"]), 48.5, 1e-6, "Stall-Dreck wirkt NICHT auf der Weide"
	)


func test_weidezaun_mult_wirkt_nur_wach() -> void:
	var werte := {"hunger": 50.0, "durst": 50.0, "sauberkeit": 50.0}
	var wach := Care.tick(werte, 10.0, {"sauberkeitMult": 0.8})
	assert_almost(float(wach["sauberkeit"]), 48.8, 1e-6, "0.15 · 0.8 = 0.12/min")
	var schlaf := Care.tick(werte, 10.0, {"schlaeft": true, "sauberkeitMult": 0.8})
	assert_almost(float(schlaf["sauberkeit"]), 48.0, 1e-6, "nachts zählt der Stall, nicht der Zaun")


func test_rate_mult_skaliert_offline() -> void:
	var werte := {"hunger": 50.0, "durst": 50.0, "sauberkeit": 50.0}
	var nach := Care.tick(werte, 10.0, {"rateMult": 0.3})
	assert_almost(float(nach["hunger"]), 49.25)


func test_laune_formel_und_bindungs_schub() -> void:
	var mitte := {"hunger": 50.0, "durst": 50.0, "sauberkeit": 50.0}
	assert_almost(Care.laune(mitte, 50.0), 50.0)
	assert_almost(Care.laune(mitte, 100.0), 55.0, 1e-6, "Bindung 100 = +5")
	assert_almost(Care.laune(mitte, 0.0), 45.0, 1e-6, "Bindung 0 = −5")
	var einseitig := {"hunger": 0.0, "durst": 100.0, "sauberkeit": 100.0}
	assert_almost(
		Care.laune(einseitig, 50.0),
		0.35 * 0.0 + 0.65 * (200.0 / 3.0),
		1e-4,
		"min zieht mit 0.35 runter"
	)


func test_sehr_durstig_deckelt_die_laune() -> void:
	var durstig := {"hunger": 100.0, "durst": 10.0, "sauberkeit": 100.0}
	assert_almost(Care.laune(durstig, 50.0), 39.0, 1e-6, "Deckel 39 bei Durst <= 15")
	var ok := {"hunger": 100.0, "durst": 16.0, "sauberkeit": 100.0}
	assert_true(Care.laune(ok, 50.0) > 39.0, "knapp über der Schwelle kein Deckel")


func test_launen_baender_und_bindungs_stufen() -> void:
	assert_eq(Care.laune_band(95.0), "strahlend")
	assert_eq(Care.laune_band(80.0), "strahlend")
	assert_eq(Care.laune_band(79.9), "froh")
	assert_eq(Care.laune_band(40.0), "zufrieden")
	assert_eq(Care.laune_band(25.0), "muffig")
	assert_eq(Care.laune_band(10.0), "elend")
	assert_eq(Care.bindung_stufe(90.0), "seelenpferd")
	assert_eq(Care.bindung_stufe(69.9), "freund")
	assert_eq(Care.bindung_stufe(20.0), "bekannt")
	assert_eq(Care.bindung_stufe(0.0), "fremd")


func test_futter_und_pflege_deltas() -> void:
	var werte := {"hunger": 50.0, "durst": 50.0, "sauberkeit": 50.0}
	assert_almost(float(Care.fuettern(werte, "heu")["hunger"]), 80.0)
	assert_almost(float(Care.fuettern(werte, "apfel")["hunger"]), 62.0)
	assert_almost(float(Care.fuettern(werte, "apfel")["durst"]), 54.0)
	assert_almost(float(Care.fuettern(werte, "karotte")["hunger"]), 58.0)
	assert_eq(Care.fuettern(werte, "pizza"), Care.clamp_werte(werte), "unbekanntes Futter no-op")
	assert_almost(float(Care.traenken(werte)["durst"]), 95.0)
	assert_almost(float(Care.striegeln(werte)["sauberkeit"]), 85.0)
	var voll := {"hunger": 95.0, "durst": 95.0, "sauberkeit": 95.0}
	assert_almost(float(Care.fuettern(voll, "heu")["hunger"]), 100.0, 1e-6, "klemmt bei 100")


func test_bond_tagesdeckel_laeuft_exakt_gegen_12() -> void:
	var bindung := 0.0
	var heute := 0.0
	var gesamt := 0.0
	for aktion: String in ["striegeln", "striegeln", "striegeln", "striegeln", "striegeln"]:
		var nach := Care.bond_nach_aktion(bindung, heute, aktion)
		bindung = nach["bindung"]
		heute = nach["bondHeute"]
		gesamt += float(nach["gewinn"])
	assert_almost(gesamt, Care.BOND_TAGES_DECKEL, 1e-6, "5 × 3 wird auf 12 gedeckelt")
	assert_almost(heute, Care.BOND_TAGES_DECKEL)
	var nix := Care.bond_nach_aktion(bindung, heute, "striegeln")
	assert_almost(float(nix["gewinn"]), 0.0, 1e-6, "Deckel erreicht = kein Gewinn mehr")


func test_bond_tag_wechsel_setzt_deckel_zurueck() -> void:
	var nach := Care.bond_nach_aktion(20.0, 12.0, "striegeln", true)
	assert_almost(float(nach["gewinn"]), 3.0, 1e-6, "neuer Tag = volle Basis")
	assert_almost(float(nach["bondHeute"]), 3.0)


func test_bond_verfall_hat_48h_karenz() -> void:
	assert_almost(Care.bond_verfall(50.0, 0.0, 2880.0), 50.0, 1e-6, "48 h Karenz kostenlos")
	assert_almost(Care.bond_verfall(50.0, 0.0, 4320.0), 49.0, 1e-6, "danach 1 Punkt/Tag")
	assert_almost(Care.bond_verfall(50.0, 2880.0, 1440.0), 49.0, 1e-6, "Karenz schon aufgebraucht")
	assert_almost(Care.bond_verfall(0.5, 0.0, 999999.0), 0.0, 1e-6, "klemmt bei 0")


func test_stall_mathe_und_ausmisten() -> void:
	assert_almost(Care.stall_tick(100.0, 60.0, 1), 97.0)
	assert_almost(Care.stall_tick(100.0, 60.0, 0), 100.0, 1e-6, "leerer Stall bleibt sauber")
	assert_eq(Care.ausmisten(), 100.0)


func test_reit_perks_wachsen_linear_ab_45() -> void:
	var kalt := Care.reit_perks(45.0)
	assert_almost(float(kalt["tempo_mult"]), 1.0)
	assert_almost(float(kalt["ausdauer_regen_mult"]), 1.0)
	var voll := Care.reit_perks(100.0)
	assert_almost(float(voll["tempo_mult"]), 1.06)
	assert_almost(float(voll["ausdauer_regen_mult"]), 1.25)
	assert_true(
		float(Care.reit_perks(70.0)["tempo_mult"]) < float(voll["tempo_mult"]), "monoton steigend"
	)
