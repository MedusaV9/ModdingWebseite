extends TestCase
## G5/P24 DLC-GOOBYE-A — die PUREN Logik-Module des „Goo und Bye“:
## Sortiment-Pack-Schema (Form+Farbe-Kodierung §2.5), GoobyeKatalog-Sichten,
## Preis-/Margen-Rechnung (GoobyePreis, §2.2/§4.4), deterministischer
## Markttag als GOLDEN-Test (fester Seed → exakte Bon-Liste, §6.1/§10.4)
## inkl. Alwin-Gag-Vertrag (§6.3) und Monotonie (billiger ⇒ nie weniger
## Absatz) sowie Regal-Bestand/Nachfüllen (GoobyeRegal, §4.3).

const PACK_DATEI := "res://content/dlc/data/goobye_sortiment.json"
const GOLDEN_SEED := 20260801

## Festes Golden-Sortiment: 5 gelistete Waren, teils mit Preis-Schieber.
const GOLDEN_SORTIMENT := [
	{"id": "carrot", "bestand": 8},
	{"id": "apple", "bestand": 6},
	{"id": "cookie", "bestand": 5, "faktor": 0.9},
	{"id": "cheese", "bestand": 4, "faktor": 1.2},
	{"id": "bread", "bestand": 5},
]


func _pack() -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PACK_DATEI))
	return parsed if parsed is Dictionary else {}


## ------------------------------------------------------------ Pack-Schema


func test_sortiment_pack_schema() -> void:
	assert_true(FileAccess.file_exists(PACK_DATEI), "goobye_sortiment.json existiert")
	var items: Array = _pack().get("items", [])
	var gruppen: Dictionary = {}
	var waren := 0
	for eintrag: Dictionary in items:
		assert_true(not str(eintrag.get("id", "")).is_empty(), "jeder Eintrag hat eine id")
		match str(eintrag.get("typ", "")):
			"gruppe":
				# §2.5: Warengruppen IMMER Form + Farbe (nie nur Farbe) + Ton.
				assert_true(not str(eintrag.get("form", "")).is_empty(), "Gruppe hat Form")
				assert_true(str(eintrag.get("farbe", "")).begins_with("#"), "Gruppe hat Hex-Farbe")
				var ton := float(eintrag.get("ton", 0.0))
				assert_true(ton >= 0.9 and ton <= 1.6, "Gebrabbel-Ton in der Pitch-Reihe")
				gruppen[str(eintrag["id"])] = eintrag
			"ware":
				waren += 1
			_:
				fail_test("unbekannter typ: %s" % eintrag.get("typ"))
	assert_eq(gruppen.size(), 6, "6 Warengruppen (§4.1)")
	assert_true(waren >= 20 and waren <= 40, "20–40 Waren im Startsortiment (§4.1)")
	for eintrag: Dictionary in items:
		if str(eintrag.get("typ", "")) != "ware":
			continue
		assert_true(
			gruppen.has(str(eintrag.get("gruppe", ""))), "%s: Gruppe bekannt" % eintrag.get("id")
		)
		assert_true(int(eintrag.get("vk", 0)) >= 1, "%s: vk >= 1" % eintrag.get("id"))
		assert_true(
			not str(eintrag.get("name_key", "")).is_empty(),
			"%s: name_key gesetzt" % eintrag.get("id")
		)
	# pack.json deklariert die neuen Domains (updatebar nach Ranch-Muster).
	var meta: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/dlc/pack.json")
	)
	var domains: Array = (meta as Dictionary).get("domains", [])
	assert_true(domains.has("goobye_sortiment"), "Domain goobye_sortiment deklariert")
	assert_true(domains.has("balance"), "Domain balance deklariert")


func test_katalog_sichten() -> void:
	GoobyeKatalog.reset_cache()
	assert_eq(GoobyeKatalog.gruppen().size(), 6, "6 Gruppen über den Katalog")
	var carrot := GoobyeKatalog.ware("carrot")
	assert_eq(int(carrot.get("vk", 0)), 5, "Möhren-Richtwert wie REHWEI")
	assert_eq(str(carrot.get("gruppe", "")), "gemuese")
	assert_true(GoobyeKatalog.ware("gibtsnicht").is_empty(), "unbekannte Ware = {}")
	assert_true(GoobyeKatalog.gruppe("carrot").is_empty(), "Ware ist keine Gruppe")
	var obst := GoobyeKatalog.waren_der_gruppe("obst")
	assert_eq(obst.size(), 5, "5 Obst-Waren")
	var startlager := GoobyeKatalog.startlager()
	assert_eq(int(startlager.get("carrot", 0)), 8, "Eröffnungspaket: 8 Möhren")
	assert_eq(int(startlager.get("apple", 0)), 6, "Eröffnungspaket: 6 Äpfel")
	assert_false(startlager.has("cake"), "ohne start-Feld nicht im Paket")
	# Gebrabbel-Ton (§1.2) kommt aus der Warengruppe.
	assert_almost(GoobyeKatalog.ton_fuer("cookie"), 1.35, 1e-6, "Süßes-Ton")
	assert_almost(GoobyeKatalog.ton_fuer("carrot"), 1.1, 1e-6, "Gemüse-Ton")
	assert_almost(GoobyeKatalog.ton_fuer("gibtsnicht"), 1.0, 1e-6, "Fallback-Ton")


## ------------------------------------------------------------ Preis-Logik


func test_preis_empfehlung_und_marge() -> void:
	GoobyeKatalog.reset_cache()
	var apple := GoobyeKatalog.ware("apple")
	assert_eq(GoobyePreis.empfohlener_preis(apple), 6, "Empfehlung = Richtwert vk")
	assert_eq(GoobyePreis.einkaufspreis(apple), 4, "Einkauf = 60 % von 6 → 4")
	assert_eq(GoobyePreis.marge(apple), 2, "Marge beim Richtwert")
	# Eigenmarke −20 % (§4.1): Hoppel-Pops vk 8 → 6.
	var pops := GoobyeKatalog.ware("gb_hoppel_pops")
	assert_eq(GoobyePreis.empfohlener_preis(pops), 6, "Eigenmarke −20 %")
	# Bio +10 % (§2.2, Welle B nutzt es — Rechnung steht schon).
	assert_eq(GoobyePreis.empfohlener_preis({"vk": 10, "bio": true}), 11, "Bio-Aufschlag +10 %")
	# Preis-Schieber ±30 %: Klemme + echter Stückpreis.
	assert_almost(GoobyePreis.faktor_begrenzen(0.1), 0.7, 1e-6, "Untergrenze −30 %")
	assert_almost(GoobyePreis.faktor_begrenzen(9.9), 1.3, 1e-6, "Obergrenze +30 %")
	assert_eq(GoobyePreis.verkaufspreis(apple, 1.3), 8, "6 × 1.3 → 8")
	assert_eq(GoobyePreis.verkaufspreis(apple, 0.7), 4, "6 × 0.7 → 4")
	assert_eq(GoobyePreis.marge(apple, 0.7), 0, "−30 % kann die Marge auffressen")
	assert_true(GoobyePreis.verkaufspreis({"vk": 0}) >= 1, "nie unter 1 Münze")


func test_griff_kurve_monoton() -> void:
	# Griff-Chance: bei ≤ Richtwert sicher, darüber streng fallend.
	assert_almost(GoobyePreis.griff_chance(1.0), 1.0, 1e-6, "Richtwert = sicherer Griff")
	assert_almost(GoobyePreis.griff_chance(0.7), 1.0, 1e-6, "billiger bleibt sicher")
	var vorher := 2.0
	for stufe in [1.0, 1.1, 1.2, 1.3]:
		var chance := GoobyePreis.griff_chance(stufe)
		assert_true(chance <= vorher, "Griff-Chance fällt monoton (Faktor %s)" % stufe)
		vorher = chance
	assert_true(GoobyePreis.griff_chance(1.3) >= 0.3, "gutmütiger Boden")
	# Spontankauf-Bonus nur UNTER dem Richtwert, gedeckelt.
	assert_almost(GoobyePreis.spontan_bonus(1.0), 0.0, 1e-6)
	assert_almost(GoobyePreis.spontan_bonus(1.3), 0.0, 1e-6)
	assert_almost(GoobyePreis.spontan_bonus(0.7), 0.24, 1e-6, "Deckel 0.24")


## ------------------------------------------------------------ Markttag


## GOLDEN: fester Seed + festes Sortiment → EXAKT dieser Tagesplan.
## (Zahlen einmalig per Treiber-Lauf erhoben — ändert sich die Zieh-Logik,
## MUSS dieser Test bewusst mit angefasst werden.)
func test_markttag_golden() -> void:
	GoobyeKatalog.reset_cache()
	var plan := GoobyeMarkttag.tag_planen(GOLDEN_SEED, GOLDEN_SORTIMENT)
	assert_eq(int(plan["kundenzahl"]), 3, "3 Kunden am Golden-Tag")
	assert_eq(int(plan["umsatz"]), 68, "Golden-Umsatz 68")
	assert_eq(int(plan["verpasst"]), 0, "kein leerer Griff")
	assert_eq(
		plan["verkauft"],
		{"apple": 2, "bread": 2, "carrot": 3, "cheese": 1, "cookie": 1},
		"Golden-Absatz je Ware"
	)
	var bons: Array = plan["bons"]
	assert_eq(bons.size(), 3)
	var alwin: Dictionary = bons[0]
	assert_eq(str(alwin["archetyp"]), "alwin")
	assert_eq(int(alwin["minute"]), 60, "Alwin kommt 9 Uhr")
	assert_eq(alwin["positionen"], [{"ware": "carrot", "preis": 5}], "GENAU eine Möhre")
	assert_eq(int(alwin["summe"]), 5)
	var zweiter: Dictionary = bons[1]
	assert_eq(str(zweiter["archetyp"]), "listen_gooby")
	assert_eq(int(zweiter["minute"]), 345)
	assert_eq(int(zweiter["summe"]), 28)
	assert_eq(
		zweiter["positionen"],
		[
			{"ware": "cookie", "preis": 7},
			{"ware": "bread", "preis": 10},
			{"ware": "carrot", "preis": 5},
			{"ware": "apple", "preis": 6},
		],
		"Bon 1: Schieber-Preise (cookie ×0.9 → 7) sitzen"
	)
	var dritter: Dictionary = bons[2]
	assert_eq(int(dritter["summe"]), 35, "Bon 2 mit Käse ×1.2 → 14")
	# Kassen-Melodie (§1.2): Alwins Möhre piept im Gemüse-Ton.
	assert_eq(GoobyeMarkttag.melodie(alwin), [1.1])


func test_markttag_determinismus_und_alwin() -> void:
	GoobyeKatalog.reset_cache()
	var a := GoobyeMarkttag.tag_planen(GOLDEN_SEED, GOLDEN_SORTIMENT)
	var b := GoobyeMarkttag.tag_planen(GOLDEN_SEED, GOLDEN_SORTIMENT)
	assert_eq(str(a), str(b), "gleicher Seed = EXAKT derselbe Plan")
	assert_eq(
		GoobyeMarkttag.tages_seed("2026-08-01"),
		GoobyeMarkttag.tages_seed("2026-08-01"),
		"Tages-Seed stabil"
	)
	# Alwin-Vertrag hält über viele Seeds: immer Kunde 0, nie mehr als 1
	# Möhre; kaputte Zeilen fliegen still raus.
	for seed_wert in [1, 7, 42, 999, 123456]:
		var plan := GoobyeMarkttag.tag_planen(seed_wert, GOLDEN_SORTIMENT)
		var alwin: Dictionary = plan["bons"][0]
		assert_eq(str(alwin["archetyp"]), "alwin", "Kunde 0 ist Alwin (Seed %d)" % seed_wert)
		assert_true((alwin["positionen"] as Array).size() <= 1, "höchstens 1 Möhre")
	var kaputt := GoobyeMarkttag.tag_planen(
		GOLDEN_SEED, [{"id": "gibtsnicht", "bestand": 5}, "unfug", {"id": "apple", "bestand": 2}]
	)
	for bon: Dictionary in kaputt["bons"]:
		for position: Dictionary in bon["positionen"]:
			assert_eq(str(position["ware"]), "apple", "nur Katalog-Waren im Bon")


func test_markttag_monotonie_billiger_nie_weniger() -> void:
	GoobyeKatalog.reset_cache()
	for seed_wert in [3, 11, 77, 2024, 55555]:
		var billig: Array = []
		var teuer: Array = []
		for zeile: Dictionary in GOLDEN_SORTIMENT:
			var b := zeile.duplicate(true)
			b["faktor"] = 0.7
			billig.append(b)
			var t := zeile.duplicate(true)
			t["faktor"] = 1.3
			teuer.append(t)
		var stueck_billig := _stueckzahl(GoobyeMarkttag.tag_planen(seed_wert, billig))
		var stueck_teuer := _stueckzahl(GoobyeMarkttag.tag_planen(seed_wert, teuer))
		assert_true(
			stueck_billig >= stueck_teuer,
			(
				"billiger ⇒ nie weniger Absatz (Seed %d: %d vs %d)"
				% [seed_wert, stueck_billig, stueck_teuer]
			)
		)


func _stueckzahl(plan: Dictionary) -> int:
	var summe := 0
	for anzahl: Variant in (plan["verkauft"] as Dictionary).values():
		summe += int(anzahl)
	return summe


## ------------------------------------------------------------ Regal


func test_regal_einraeumen_und_entnehmen() -> void:
	var regal := GoobyeRegal.neues_regal()
	assert_eq((regal["slots"] as Array).size(), 5, "5 Slots im Grundregal")
	assert_eq(GoobyeRegal.gesamt_bestand(regal), 0)
	var lager := {"apple": 10, "carrot": 3}
	assert_eq(GoobyeRegal.einraeumen(regal, 0, "apple", 99, lager), 8, "Slot-Deckel 8")
	assert_eq(int(lager["apple"]), 2, "Lager entsprechend leerer")
	assert_eq(GoobyeRegal.einraeumen(regal, 0, "carrot", 1, lager), 0, "fremde Ware blockt")
	assert_eq(GoobyeRegal.einraeumen(regal, 1, "carrot", 2, lager), 2, "Teilmenge ok")
	assert_eq(GoobyeRegal.einraeumen(regal, 1, "carrot", 5, lager), 1, "Rest-Vorrat begrenzt")
	assert_false(lager.has("carrot"), "leergezogene Ware verschwindet aus dem Lager")
	assert_eq(GoobyeRegal.einraeumen(regal, 9, "apple", 1, lager), 0, "Slot-Index geprüft")
	assert_eq(GoobyeRegal.bestand(regal, "apple"), 8)
	assert_eq(GoobyeRegal.bestand(regal, "carrot"), 3)
	assert_eq(GoobyeRegal.gesamt_bestand(regal), 11)
	# Entnahme räumt Slots sauber aus (Kunde greift zu).
	assert_eq(GoobyeRegal.entnehmen(regal, "carrot", 2), 2)
	assert_eq(GoobyeRegal.entnehmen(regal, "carrot", 5), 1, "mehr als da ist geht nicht")
	assert_eq(GoobyeRegal.bestand(regal, "carrot"), 0)
	var slots: Array = regal["slots"]
	assert_eq(str((slots[1] as Dictionary)["ware"]), "", "leerer Slot ist wieder frei")
	# Sortiment-Sicht fürs Markttag-Modul (Preis-Faktoren wandern mit).
	var sortiment := GoobyeRegal.sortiment_von(regal, {"apple": 1.2})
	assert_eq(sortiment.size(), 1)
	assert_eq(sortiment[0], {"id": "apple", "bestand": 8, "faktor": 1.2})


func test_regal_normalisieren_und_vorschlag() -> void:
	# Self-Heal: kaputte Saves werden repariert, Deckel greift.
	var heil := GoobyeRegal.normalisieren(
		{"slots": [{"ware": "apple", "menge": 99}, "unfug", {"ware": "", "menge": 3}]}
	)
	assert_eq((heil["slots"] as Array).size(), 5, "immer volle Slot-Zahl")
	assert_eq(GoobyeRegal.bestand(heil, "apple"), 8, "Menge auf den Slot-Deckel geklemmt")
	assert_eq(GoobyeRegal.gesamt_bestand(GoobyeRegal.normalisieren("kaputt")), 0)
	# Nachfüll-Kompass: leere Slots nur, solange das Lager etwas hergibt.
	var regal := GoobyeRegal.neues_regal()
	GoobyeRegal.einraeumen(regal, 2, "apple", 4, {"apple": 4})
	assert_eq(GoobyeRegal.nachfuell_vorschlag(regal, {"carrot": 2}), [0, 1, 3, 4], "leere Slots")
	assert_eq(GoobyeRegal.nachfuell_vorschlag(regal, {}), [], "leeres Lager = kein Vorschlag")
	assert_eq(GoobyeRegal.nachfuell_vorschlag(regal, {"carrot": 0}), [], "0-Bestand zählt nicht")
