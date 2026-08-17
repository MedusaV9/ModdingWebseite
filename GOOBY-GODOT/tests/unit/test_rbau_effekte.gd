extends TestCase
## RW-4 — RanchBauEffekte: jede Ausbaustufe hat SPÜRBAREN Nutzen (IDEAS-3
## §6): mehr Boxen = mehr Pferde, Reithalle = Regen-Training, Führanlage =
## passives Training, Waschplatz = bessere Pflege, Tribüne = Publikum,
## Heulager = Vorratshaltung. Alle Zahlen kommen aus bau_balance.json.


func _bal() -> Dictionary:
	return RanchBauKatalog.load_balance()


func _bau(anlagen: Dictionary) -> Dictionary:
	var bau := RanchBauState.default_bau()
	for id: String in anlagen:
		bau["anlagen"][id] = {"stufe": int(anlagen[id])}
	return bau


func test_boxen_kapazitaet_waechst_pro_stufe() -> void:
	var bal := _bal()
	assert_eq(RanchBauEffekte.boxen_kapazitaet(_bau({}), bal), 2, "Basis ohne Boxen")
	assert_eq(RanchBauEffekte.boxen_kapazitaet(_bau({"stallboxen": 1}), bal), 2)
	assert_eq(RanchBauEffekte.boxen_kapazitaet(_bau({"stallboxen": 2}), bal), 4)
	assert_eq(RanchBauEffekte.boxen_kapazitaet(_bau({"stallboxen": 3}), bal), 6)
	assert_eq(RanchBauEffekte.boxen_kapazitaet(_bau({"stallboxen": 4}), bal), 8)


func test_heulager_vorratshaltung() -> void:
	var bal := _bal()
	assert_eq(RanchBauEffekte.heu_kapazitaet(_bau({}), bal), 10, "Basis ohne Lager")
	assert_eq(RanchBauEffekte.heu_kapazitaet(_bau({"heulager": 1}), bal), 12)
	assert_eq(RanchBauEffekte.heu_kapazitaet(_bau({"heulager": 3}), bal), 48)


func test_reithalle_training_bei_regen() -> void:
	var bal := _bal()
	assert_false(RanchBauEffekte.training_bei_regen(_bau({}), bal), "ohne Halle kein Regen")
	assert_true(RanchBauEffekte.training_bei_regen(_bau({"reithalle": 1}), bal))
	assert_almost(RanchBauEffekte.dressur_xp_mult(_bau({"reithalle": 1}), bal), 1.2)


func test_fuehranlage_passives_training() -> void:
	var bal := _bal()
	assert_eq(RanchBauEffekte.fuehranlage_xp_pro_tag(_bau({}), bal), 0)
	assert_eq(RanchBauEffekte.fuehranlage_xp_pro_tag(_bau({"fuehranlage": 1}), bal), 40)
	assert_eq(RanchBauEffekte.fuehranlage_xp_pro_tag(_bau({"fuehranlage": 3}), bal), 80)


func test_waschplatz_beschleunigt_pflege() -> void:
	var bal := _bal()
	assert_eq(RanchBauEffekte.striegel_wert(_bau({}), bal), 35, "Basis-Striegel")
	assert_eq(RanchBauEffekte.striegel_wert(_bau({"waschplatz": 1}), bal), 50)
	assert_eq(RanchBauEffekte.warmwasser_bonus(_bau({"waschplatz": 1}), bal), 0)
	assert_eq(RanchBauEffekte.warmwasser_bonus(_bau({"waschplatz": 2}), bal), 2)


func test_pflege_multiplikatoren() -> void:
	var bal := _bal()
	assert_almost(RanchBauEffekte.hunger_mult(_bau({}), bal), 1.0)
	assert_almost(RanchBauEffekte.hunger_mult(_bau({"weide": 2}), bal), 0.85)
	assert_almost(RanchBauEffekte.durst_mult(_bau({"wasserstelle": 1}), bal), 0.7)
	assert_false(RanchBauEffekte.selbsttraenke_aktiv(_bau({"wasserstelle": 1}), bal))
	assert_true(RanchBauEffekte.selbsttraenke_aktiv(_bau({"wasserstelle": 2}), bal))
	assert_almost(RanchBauEffekte.sauberkeit_mult(_bau({"weidezaun": 3}), bal), 0.6)


func test_tribuene_publikum_und_bonus() -> void:
	var bal := _bal()
	assert_eq(RanchBauEffekte.tribuene_zuschauer(_bau({}), bal), 0)
	assert_eq(RanchBauEffekte.tribuene_zuschauer(_bau({"tribuene": 1}), bal), 6)
	assert_eq(RanchBauEffekte.tribuene_zuschauer(_bau({"tribuene": 2}), bal), 12)
	assert_almost(RanchBauEffekte.heim_gold_mult(_bau({"tribuene": 2}), bal), 1.15)


func test_deko_stilpunkte_mit_deckel() -> void:
	var bal := _bal()
	var bau := RanchBauState.default_bau()
	assert_eq(RanchBauEffekte.deko_stilpunkte(bau, bal), 0)
	for i in 12:
		(bau["items"] as Array).append(
			{"uid": "d%d" % i, "item": "bank_holz", "at": [i, 7], "rot": 0}
		)
	assert_eq(RanchBauEffekte.deko_stilpunkte(bau, bal), 2, "12 Deko / 5 = 2 Punkte")
	for i in 60:
		(bau["items"] as Array).append(
			{"uid": "e%d" % i, "item": "laterne", "at": [i, 8], "rot": 0}
		)
	assert_eq(RanchBauEffekte.deko_stilpunkte(bau, bal), 10, "Deckel bei 10")
	# Nicht-Deko zählt nicht.
	var nur_boden := RanchBauState.default_bau()
	for i in 10:
		(nur_boden["items"] as Array).append(
			{"uid": "b%d" % i, "item": "weg_schotter", "at": [i, 7], "rot": 0}
		)
	assert_eq(RanchBauEffekte.deko_stilpunkte(nur_boden, bal), 0)


func test_zusammenfassung_liefert_alle_werte() -> void:
	var bal := _bal()
	var alles := (
		RanchBauEffekte
		. zusammenfassung(
			_bau(
				{
					"stallboxen": 4,
					"weide": 3,
					"wasserstelle": 3,
					"heulager": 3,
					"waschplatz": 3,
					"fuehranlage": 3,
					"reithalle": 3,
					"parcours": 3,
					"tribuene": 2,
					"weidezaun": 3,
				}
			),
			bal
		)
	)
	assert_eq(alles["boxen_kapazitaet"], 8)
	assert_eq(alles["heu_kapazitaet"], 48)
	assert_true(bool(alles["training_bei_regen"]))
	assert_eq(alles["fuehranlage_xp_pro_tag"], 80)
	assert_eq(alles["tribuene_zuschauer"], 12)
	assert_almost(float(alles["parcours_coin_mult"]), 1.1)
	assert_eq(alles["laune_bonus_pro_h"], 1, "Kräuterweide Stufe 3")
