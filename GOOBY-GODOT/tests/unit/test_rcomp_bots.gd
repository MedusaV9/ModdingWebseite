extends TestCase
## RW-5 — Bot-Gegner: Roster-Integrität (echte Rassen/Farben), Determinismus
## (Seed rein = identisches Ergebnis raus) und FAIRNESS über die Klassen:
## In Holz gewinnt auch ein Anfänger mit schwachem Pferd meistens; in der
## Sternenklasse braucht es ein starkes Pferd UND saubere Läufe (kein
## Gummiband — die Bots würfeln, BEVOR der Spieler reitet).

const Katalog := preload("res://scripts/ranch/comp/comp_katalog.gd")
const Bots := preload("res://scripts/ranch/comp/comp_bots.gd")
const Turnier := preload("res://scripts/ranch/comp/comp_turnier.gd")

const FAIRNESS_DURCHLAEUFE := 40


func _bal() -> Dictionary:
	return RanchWirtschaft.read_json(Katalog.BALANCE_PATH)


func test_roster_integritaet() -> void:
	var rassen := RanchRassen.load_balance()
	var ids := {}
	assert_true(Bots.ROSTER.size() >= 10, "genug Gesichter für 5er-Felder")
	for eintrag in Bots.ROSTER:
		var id := str(eintrag.get("id", ""))
		assert_false(ids.has(id), "Bot-Id doppelt: %s" % id)
		ids[id] = true
		assert_true(str(eintrag.get("name", "")) != "", "Bot braucht Namen")
		assert_true(str(eintrag.get("pferd", "")) != "", "Bot braucht Pferdenamen")
		assert_true(
			not RanchRassen.rasse(rassen, str(eintrag.get("rasse", ""))).is_empty(),
			"Rasse existiert: %s" % eintrag.get("rasse")
		)
		assert_true(
			RanchPferd.FELL.has(str(eintrag.get("farbe", ""))),
			"Fellfarbe existiert: %s" % eintrag.get("farbe")
		)
		var talent := float(eintrag.get("talent", -1.0))
		assert_true(talent >= 0.0 and talent <= 1.0, "Talent 0..1")
		assert_true(
			Katalog.DISZIPLINEN.has(str(eintrag.get("liebling", ""))),
			"Lieblings-Disziplin existiert"
		)


func test_koennen_baender_je_klasse() -> void:
	var bal := _bal()
	var rosalinde := Bots.bot("rosalinde")
	var holz := Bots.koennen(bal, rosalinde, "holz", "dressur")
	var stern := Bots.koennen(bal, rosalinde, "sternenklasse", "dressur")
	assert_true(stern > holz, "höhere Klasse = stärkere Bots")
	assert_true(
		Bots.koennen(bal, rosalinde, "holz", "springen") > holz,
		"Lieblings-Disziplin gibt einen Schub"
	)
	for klasse in Katalog.KLASSEN:
		var band := Katalog.bot_band(bal, klasse)
		for eintrag in Bots.ROSTER:
			var k := Bots.koennen(bal, eintrag, klasse, "gelaende")
			assert_true(
				(
					k >= float(band[0]) - Bots.FREMD_MALUS - 0.001
					and k <= float(band[1]) + Bots.LIEBLING_BONUS + 0.001
				),
				"Können bleibt nah am Klassen-Band (%s)" % klasse
			)


func test_starterfeld_und_simulation_deterministisch() -> void:
	var bal := _bal()
	var a := Bots.starterfeld(bal, "silber", "tonnen", 20260726, 5)
	var b := Bots.starterfeld(bal, "silber", "tonnen", 20260726, 5)
	assert_eq(a.size(), 5)
	for i in a.size():
		assert_eq(
			str((a[i] as Dictionary)["id"]),
			str((b[i] as Dictionary)["id"]),
			"gleicher Seed = gleiches Feld"
		)
	var feld_ids := {}
	for starter: Variant in a:
		feld_ids[(starter as Dictionary)["id"]] = true
	assert_eq(feld_ids.size(), 5, "keine Doppelstarter")
	for disziplin in Katalog.DISZIPLINEN:
		var lauf_a := Bots.simuliere_lauf(bal, disziplin, "bronze", 0.5, 42)
		var lauf_b := Bots.simuliere_lauf(bal, disziplin, "bronze", 0.5, 42)
		assert_eq(lauf_a, lauf_b, "Simulation deterministisch: %s" % disziplin)


## Mehr Können führt (im Mittel) zu besseren Werten — je Disziplin.
func test_simulation_monoton_im_koennen() -> void:
	var bal := _bal()
	for disziplin in Katalog.DISZIPLINEN:
		var kleiner_gewinnt := Katalog.zeit_gewinnt(bal, disziplin)
		var schwach := 0.0
		var stark := 0.0
		for i in FAIRNESS_DURCHLAEUFE:
			schwach += float(Bots.simuliere_lauf(bal, disziplin, "silber", 0.25, 7000 + i)["wert"])
			stark += float(Bots.simuliere_lauf(bal, disziplin, "silber", 0.85, 7000 + i)["wert"])
		if kleiner_gewinnt:
			assert_true(stark < schwach, "%s: mehr Können = schneller" % disziplin)
		else:
			assert_true(stark > schwach, "%s: mehr Können = mehr Punkte" % disziplin)


func _sieg_quote(klasse: String, stats: Dictionary, fahr: float, podium := false) -> float:
	var bal := _bal()
	var treffer := 0
	var disziplinen: Array[String] = ["tonnen", "springen", "gelaende"]
	for i in FAIRNESS_DURCHLAEUFE:
		var disziplin: String = disziplinen[i % disziplinen.size()]
		var seed_wert := 31000 + i * 17
		var bots := Turnier.bots_simulieren(bal, disziplin, klasse, seed_wert)
		var koennen := Bots.spieler_koennen(bal, disziplin, stats, fahr)
		var lauf := Bots.simuliere_lauf(bal, disziplin, klasse, koennen, seed_wert + 5)
		var stand := Turnier.endstand(bal, disziplin, bots, lauf)
		var platz := Turnier.spieler_platz(stand)
		if (podium and platz <= 3) or (not podium and platz == 1):
			treffer += 1
	return float(treffer) / FAIRNESS_DURCHLAEUFE


## Kap. 5-Fairness: Holz verzeiht, Sternenklasse fordert Pferd + Können.
func test_fairness_ueber_die_klassen() -> void:
	var anfaenger_stats := {
		"tempo": 8, "sprungkraft": 8, "wendigkeit": 8, "ausdauer": 8, "gelassenheit": 8
	}
	var top_stats := {
		"tempo": 18, "sprungkraft": 18, "wendigkeit": 18, "ausdauer": 18, "gelassenheit": 18
	}
	var holz_sieg := _sieg_quote("holz", anfaenger_stats, 0.55)
	assert_true(holz_sieg >= 0.6, "Holz: Anfänger gewinnt meistens (%.2f)" % holz_sieg)
	var stern_schwach := _sieg_quote("sternenklasse", anfaenger_stats, 0.55)
	assert_true(
		stern_schwach <= 0.25, "Sternenklasse: schwaches Pferd gewinnt kaum (%.2f)" % stern_schwach
	)
	var stern_stark := _sieg_quote("sternenklasse", top_stats, 0.9, true)
	assert_true(
		stern_stark >= 0.5,
		"Sternenklasse: Top-Pferd + sauberer Ritt schafft Podien (%.2f)" % stern_stark
	)
	var gold_mittel := _sieg_quote("gold", anfaenger_stats, 0.55, true)
	assert_true(gold_mittel < 0.5, "Gold ist für Anfänger schon fordernd (%.2f)" % gold_mittel)


func test_spieler_koennen_proxy() -> void:
	var bal := _bal()
	var schwach := Bots.spieler_koennen(bal, "tonnen", {"wendigkeit": 4, "tempo": 4}, 0.3)
	var stark := Bots.spieler_koennen(bal, "tonnen", {"wendigkeit": 19, "tempo": 19}, 0.9)
	assert_true(stark > schwach)
	assert_true(schwach >= 0.0 and stark <= 1.0, "geklemmt 0..1")
	var ohne_stats := Bots.spieler_koennen(bal, "schau", {}, 0.5)
	assert_true(ohne_stats > 0.0, "Schau ist stat-unabhängig, zählt nur Fahrqualität")
