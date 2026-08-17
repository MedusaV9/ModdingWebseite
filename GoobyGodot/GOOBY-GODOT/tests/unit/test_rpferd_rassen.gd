extends TestCase
## RW-2 — Rassen-Integritaet (rassen.json + RanchRassen): 12 Rassen mit
## gueltigen Werten/Preisen/einzigartigen Eigenheiten, deterministische
## Individuen aus dem Seed und das Gen→Fellfarben-Mapping (Kap. 1.2).

const Rassen := preload("res://scripts/ranch/data/ranch_rassen.gd")


func test_zwoelf_rassen_mit_gueltigen_werten() -> void:
	var balance := Rassen.load_balance()
	var liste := Rassen.rassen_liste(balance)
	assert_eq(liste.size(), 12, "genau 12 Rassen (Kap. 1.1)")
	var ids := {}
	var eigenheiten := {}
	for eintrag: Dictionary in liste:
		var id := str(eintrag.get("id", ""))
		assert_false(ids.has(id), "Rassen-Id doppelt: %s" % id)
		ids[id] = true
		for k in Rassen.STAT_KEYS:
			var wert := int(eintrag.get(k, -1))
			assert_true(wert >= 1 and wert <= 20, "%s.%s in 1..20" % [id, k])
		assert_true(
			Rassen.RARITAETEN.has(str(eintrag.get("raritaet"))), "%s: Raritaet gueltig" % id
		)
		assert_true(float(eintrag.get("preis", -1.0)) >= 0.0, "%s: Preis >= 0" % id)
		var groesse := float(eintrag.get("groesse", 0.0))
		assert_true(groesse >= 0.7 and groesse <= 1.3, "%s: Groesse plausibel" % id)
		var eigenheit := str(eintrag.get("eigenheit", ""))
		assert_true(Rassen.EIGENHEIT_EFFEKTE.has(eigenheit), "%s: Eigenheit bekannt" % id)
		assert_false(eigenheiten.has(eigenheit), "Eigenheit doppelt: %s" % eigenheit)
		eigenheiten[eigenheit] = true
	assert_eq(int(Rassen.rasse(balance, "puschelhufer").get("preis", -1)), 0, "Startpferd gratis")


func test_unbekannte_rasse_faellt_auf_puschelhufer() -> void:
	var balance := Rassen.load_balance()
	assert_eq(str(Rassen.rasse(balance, "gibtsnicht").get("id")), "puschelhufer")


func test_individuum_ist_deterministisch() -> void:
	var balance := Rassen.load_balance()
	var a := Rassen.neues_individuum("flitzewind", 777, balance)
	var b := Rassen.neues_individuum("flitzewind", 777, balance)
	assert_eq(a, b, "gleicher Seed = gleiches Pferd")
	var c := Rassen.neues_individuum("flitzewind", 778, balance)
	assert_ne(a, c, "anderer Seed = anderes Pferd")


func test_individuum_felder_sind_konsistent() -> void:
	var balance := Rassen.load_balance()
	var p := Rassen.neues_individuum("wolkentraber", 42, balance)
	assert_eq(str(p["rasse"]), "wolkentraber")
	assert_eq(str(p["farbe"]), Rassen.fellfarbe_aus_genen(p["gene"]), "Farbe folgt den Genen")
	var charakter: Array = p["charakter"]
	assert_eq(charakter.size(), 2, "zwei Charakterzuege")
	assert_ne(charakter[0], charakter[1], "Zuege verschieden")
	for zug: Variant in charakter:
		assert_true(Rassen.CHARAKTERZUEGE.has(str(zug)))
	assert_eq(p["stats"], Rassen.basis_stats(Rassen.rasse(balance, "wolkentraber")))
	var basis := float(Rassen.rasse(balance, "wolkentraber").get("groesse", 1.0))
	assert_true(absf(float(p["groesse"]) - basis) <= basis * 0.081, "Statur-Varianz ±8 %")
	var pitch := float(p["stimmPitch"])
	assert_true(pitch >= 0.85 and pitch <= 1.15, "Stimm-Pitch im Band")
	assert_eq(str(p["alter"]), "ausgewachsen")


func test_fellfarben_mapping_folgt_dominanz() -> void:
	assert_eq(Rassen.fellfarbe_aus_genen({"g": ["B", "B"], "h": ["h0", "h0"]}), "braun")
	assert_eq(Rassen.fellfarbe_aus_genen({"g": ["B", "F"], "h": ["h0", "h0"]}), "braun", "B > F")
	assert_eq(Rassen.fellfarbe_aus_genen({"g": ["F", "Z"], "h": ["h0", "h0"]}), "fuchs", "F > Z")
	assert_eq(Rassen.fellfarbe_aus_genen({"g": ["Z", "Z"], "h": ["h0", "h0"]}), "schwarz")
	assert_eq(
		Rassen.fellfarbe_aus_genen({"g": ["B", "B"], "h": ["h+", "h0"]}),
		"palomino",
		"1× Aufhellung"
	)
	assert_eq(Rassen.fellfarbe_aus_genen({"g": ["Z", "Z"], "h": ["h+", "h0"]}), "rauchgrau")
	assert_eq(
		Rassen.fellfarbe_aus_genen({"g": ["F", "F"], "h": ["h+", "h+"]}),
		"weiss",
		"2× Aufhellung = weiss"
	)
	assert_eq(Rassen.fellfarbe_aus_genen({}), "braun", "kaputte Gene fallen sicher")


func test_schecke_und_glitzer_allele() -> void:
	assert_true(Rassen.ist_schecke({"s": ["Sch", "s0"]}), "Sch ist dominant")
	assert_false(Rassen.ist_schecke({"s": ["s0", "s0"]}))
	assert_false(Rassen.ist_glitzer({"glitzer": ["gx", "g0"]}), "Glitzer nur reinerbig")
	assert_true(Rassen.ist_glitzer({"glitzer": ["gx", "gx"]}))
	assert_eq(Rassen.allele({}, "g", "B"), ["B", "B"], "kaputt → Fallback-Paar")


func test_sternschnuppler_glitzert_immer() -> void:
	var balance := Rassen.load_balance()
	for seed_wert in [1, 22, 333]:
		var p := Rassen.neues_individuum("sternschnuppler", seed_wert, balance)
		assert_true(Rassen.ist_glitzer(p["gene"]), "Seed %d" % seed_wert)


func test_charakter_effekte_sind_spuerbar_definiert() -> void:
	for zug in Rassen.CHARAKTERZUEGE:
		if zug == "scheu":
			continue
		assert_false(Rassen.charakter_effekte(zug).is_empty(), "Zug %s hat einen Effekt" % zug)
	assert_almost(float(Rassen.charakter_effekte("mutig").get("scheu_mult")), 0.0)
	assert_almost(float(Rassen.charakter_effekte("fleissig").get("frische_verbrauch")), 30.0)
