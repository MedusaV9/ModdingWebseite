extends TestCase
## RW-2 — Wildpferde zaehmen (RanchHorseTaming): Anschleich-Aufmerksamkeit,
## Beruhigen-Rhythmus, frustfreier Fehlschlag (davontraben + Wiederkehr)
## und das deterministische Wildpferd aus dem Begegnungs-Seed.

const Taming := preload("res://scripts/ranch/gameplay/horse_taming.gd")


func test_neue_begegnung_startet_im_anschleichen() -> void:
	var z := Taming.neue_begegnung(99)
	assert_eq(str(z["phase"]), "anschleichen")
	assert_almost(float(z["aufmerksamkeit"]), 0.0)
	assert_almost(float(z["ruhe"]), Taming.RUHE_START)


func test_anschleichen_geduckt_bleibt_leise() -> void:
	var offen := Taming.neue_begegnung(1)
	var geduckt := Taming.neue_begegnung(1)
	for _i in 40:
		offen = Taming.step_anschleichen(offen, 0.1, 5.0, true, false)
		geduckt = Taming.step_anschleichen(geduckt, 0.1, 5.0, true, true)
	assert_true(
		float(geduckt["aufmerksamkeit"]) < float(offen["aufmerksamkeit"]) * 0.5,
		"geduckt faellt deutlich weniger auf"
	)
	var fern := Taming.step_anschleichen(offen, 1.0, 20.0, true, false)
	assert_true(
		float(fern["aufmerksamkeit"]) < float(offen["aufmerksamkeit"]),
		"ausser Sichtweite baut Aufmerksamkeit ab"
	)


func test_zu_viel_aufmerksamkeit_heisst_davongetrabt() -> void:
	var z := Taming.neue_begegnung(2)
	z["aufmerksamkeit"] = 99.9
	z = Taming.step_anschleichen(z, 1.0, 2.0, true, false)
	assert_eq(str(z["phase"]), "davongetrabt")
	assert_eq(str(z["event"]), "davongetrabt")
	assert_almost(float(z["cooldown_s"]), Taming.COOLDOWN_S)
	# Cooldown ablaufen lassen: die Begegnung beginnt frisch von vorn.
	var wieder := Taming.step_cooldown(z, Taming.COOLDOWN_S + 0.1)
	assert_eq(str(wieder["event"]), "wieder_da", "kein Frust: es kommt wieder")
	assert_eq(str(wieder["phase"]), "anschleichen")
	assert_almost(float(wieder["aufmerksamkeit"]), 0.0)


func test_nah_genug_startet_beruhigen() -> void:
	var z := Taming.neue_begegnung(3)
	z = Taming.step_anschleichen(z, 0.1, 1.2, false, true)
	assert_eq(str(z["phase"]), "beruhigen")
	assert_eq(str(z["event"]), "bereit")


func test_beruhigen_takt_und_fenster() -> void:
	var z := Taming.neue_begegnung(4)
	z["phase"] = "beruhigen"
	z["seit_schnauben_s"] = 0.0
	z = Taming.step_beruhigen(z, Taming.TAKT_S + 0.05)
	assert_eq(str(z["event"]), "schnauben", "neuer Takt-Moment")
	# Tipp direkt nach dem Schnauben (0,05 s) liegt im ±0,3-s-Fenster.
	var treffer := Taming.beruhigen_tap(z)
	assert_eq(str(treffer["event"]), "treffer")
	assert_almost(float(treffer["ruhe"]), Taming.RUHE_START + Taming.RUHE_TREFFER, 1e-6)
	# Tipp mitten zwischen zwei Schnaubern (0,7 s) liegt daneben.
	var mitte := treffer.duplicate(true)
	mitte["seit_schnauben_s"] = Taming.TAKT_S * 0.5
	var daneben := Taming.beruhigen_tap(mitte)
	assert_eq(str(daneben["event"]), "daneben")
	assert_true(float(daneben["ruhe"]) < float(treffer["ruhe"]), "daneben kostet sanft Ruhe")


func test_beruhigen_bis_gezaehmt_und_bis_flucht() -> void:
	var z := Taming.neue_begegnung(5)
	z["phase"] = "beruhigen"
	z["seit_schnauben_s"] = 0.1
	var schutz := 0
	while str(z["phase"]) == "beruhigen" and schutz < 20:
		schutz += 1
		z = Taming.beruhigen_tap(z)
	assert_eq(str(z["phase"]), "gezaehmt", "nur Treffer → gezaehmt")
	assert_eq(str(z["event"]), "gezaehmt")
	var flucht := Taming.neue_begegnung(6)
	flucht["phase"] = "beruhigen"
	flucht["ruhe"] = 6.0
	flucht["seit_schnauben_s"] = Taming.TAKT_S * 0.5
	flucht = Taming.beruhigen_tap(flucht)
	assert_eq(str(flucht["phase"]), "davongetrabt", "Ruhe 0 = davongetrabt (kein Abwurf)")


func test_wildpferd_ist_deterministisch_und_wild() -> void:
	var balance := RanchRassen.load_balance()
	var a := Taming.wildpferd_dict(4711, balance)
	var b := Taming.wildpferd_dict(4711, balance)
	assert_eq(a, b, "gleicher Seed = gleiches Wildpferd")
	assert_true(bool(a["wild"]))
	assert_true(Taming.WILD_RASSEN.has(str(a["rasse"])), "Rasse aus dem Wild-Pool")
	assert_eq(str(a["farbe"]), RanchRassen.fellfarbe_aus_genen(a["gene"]))


func test_wildpferde_haben_oft_besondere_muster() -> void:
	var schecken := 0
	var traeger := 0
	for seed_wert in 400:
		var p := Taming.wildpferd_dict(seed_wert, {})
		if RanchRassen.ist_schecke(p["gene"]):
			schecken += 1
		if RanchRassen.allele(p["gene"], "glitzer", "g0").has("gx"):
			traeger += 1
	# WARN-SWEEP: literale Prozentzeichen als %% escapen — „% (“ / „%+“ sind
	# ungültige Platzhalter und rissen bei JEDEM Lauf zwei Engine-Fehler
	# („String formatting error“), weil die Meldung eager formatiert wird.
	assert_true(schecken >= 200, "Schecken-Chance ~60 %% (%d/400)" % schecken)
	assert_true(traeger >= 60, "Glitzer-Traeger ~25 %%+ (%d/400)" % traeger)
