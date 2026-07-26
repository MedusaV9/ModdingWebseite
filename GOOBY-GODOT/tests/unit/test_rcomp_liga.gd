extends TestCase
## RW-5 — Katalog (Klassen/Gold/XP, Kap. 5.1) + Liga-Regelwerk: Aufstieg
## durch Punkte, KEIN Abstieg, Level-Gates, deterministischer Turniertag.

const Katalog := preload("res://scripts/ranch/comp/comp_katalog.gd")
const Liga := preload("res://scripts/ranch/comp/comp_liga.gd")


class FakeRegistry:
	extends RefCounted

	var balance: Dictionary = {}

	func get_balance(_key: String, default_value: Variant = null) -> Variant:
		return balance if not balance.is_empty() else default_value


func _bal() -> Dictionary:
	return RanchWirtschaft.read_json(Katalog.BALANCE_PATH)


func test_balance_json_vollstaendig_und_synchron() -> void:
	var bal := _bal()
	assert_eq((bal.get("klassen") as Array).size(), 5, "5 Klassen Holz→Sternenklasse")
	assert_eq((bal.get("disziplinen") as Array).size(), 7, "7 Disziplinen")
	for klasse in Katalog.KLASSEN:
		var eintrag := Katalog.klasse(bal, klasse)
		assert_eq(
			int(eintrag["ab_level"]),
			int(Katalog.KLASSE_AB_LEVEL[klasse]),
			"ab_level-Fallback synchron: %s" % klasse
		)
		assert_almost(
			float(eintrag["gold_faktor"]),
			float(Katalog.GOLD_FAKTOR[klasse]),
			1e-6,
			"gold_faktor-Fallback synchron: %s" % klasse
		)
		# Kap. 5.1: XP 60–240 — deckungsgleich mit RanchHorseLevels.
		assert_eq(
			Katalog.xp_fuer_teilnahme(bal, klasse),
			int(RanchHorseLevels.XP_WETTBEWERB[klasse]),
			"XP synchron zu RanchHorseLevels: %s" % klasse
		)
	for disziplin in Katalog.DISZIPLINEN:
		assert_eq(
			str(Katalog.disziplin(bal, disziplin).get("id", "")), disziplin, "Disziplin fehlt"
		)


func test_katalog_gold_je_platz_kap51() -> void:
	var bal := _bal()
	assert_eq(Katalog.gold_fuer_platz(bal, "holz", 1), 40, "Basis 40 G × 100 %")
	assert_eq(Katalog.gold_fuer_platz(bal, "holz", 2), 24, "60 %")
	assert_eq(Katalog.gold_fuer_platz(bal, "holz", 3), 14, "35 %")
	assert_eq(Katalog.gold_fuer_platz(bal, "holz", 5), 4, "Trostgold 10 %")
	assert_eq(Katalog.gold_fuer_platz(bal, "sternenklasse", 1), 160, "×4,0 laut Doc")
	assert_eq(Katalog.gold_fuer_platz(bal, "gold", 2), 72, "40 × 0,6 × 3,0")


func test_katalog_wertungsrichtung_und_richtzeiten() -> void:
	var bal := _bal()
	assert_false(Katalog.zeit_gewinnt(bal, "springen"), "Punkte-Disziplin")
	assert_false(Katalog.zeit_gewinnt(bal, "schau"))
	assert_true(Katalog.zeit_gewinnt(bal, "gelaende"), "Zeit-Disziplin")
	assert_true(Katalog.zeit_gewinnt(bal, "tonnen"))
	assert_true(Katalog.zeit_gewinnt(bal, "rennen"), "Platz-Disziplin zählt wie Zeit")
	assert_almost(Katalog.richtzeit_s(bal, "tonnen", "holz"), 24.0, 1e-6, "Doc: 24 s")
	assert_almost(Katalog.richtzeit_s(bal, "tonnen", "sternenklasse"), 17.0, 1e-6, "Doc: 17 s")
	assert_true(Katalog.richtzeit_s(bal, "springen", "holz") > 0.0)
	assert_almost(Katalog.richtzeit_s(bal, "dressur", "holz"), 0.0, 1e-6, "Dressur ohne Zeit")
	for klasse_idx in Katalog.KLASSEN.size() - 1:
		var schneller := Katalog.KLASSEN[klasse_idx + 1]
		var langsamer := Katalog.KLASSEN[klasse_idx]
		assert_true(
			(
				Katalog.richtzeit_s(bal, "tonnen", schneller)
				< Katalog.richtzeit_s(bal, "tonnen", langsamer)
			),
			"Richtzeiten werden je Klasse strenger"
		)


func test_katalog_registry_override() -> void:
	var registry := FakeRegistry.new()
	registry.balance = {"basis_gold": 100}
	var bal := Katalog.load_balance(registry)
	assert_eq(Katalog.gold_fuer_platz(bal, "holz", 1), 100, "Content-Pack-Override greift")
	assert_eq((bal.get("klassen") as Array).size(), 5, "Rest bleibt")


func test_liga_punkte_je_platz() -> void:
	var bal := _bal()
	assert_eq(Liga.punkte_fuer_platz(bal, 1), 10)
	assert_eq(Liga.punkte_fuer_platz(bal, 2), 7)
	assert_eq(Liga.punkte_fuer_platz(bal, 3), 5)
	assert_eq(Liga.punkte_fuer_platz(bal, 4), 3)
	assert_eq(Liga.punkte_fuer_platz(bal, 5), 1)
	assert_eq(Liga.punkte_fuer_platz(bal, 6), 1, "jeder nimmt etwas mit")
	assert_eq(Liga.punkte_fuer_platz(bal, 0), 0)


func test_liga_aufstieg_nur_nach_oben() -> void:
	var bal := _bal()
	var knapp := Liga.pruefe_aufstieg(bal, "holz", Liga.aufstieg_ab(bal, "holz") - 1)
	assert_false(bool(knapp["aufgestiegen"]))
	assert_eq(str(knapp["klasse"]), "holz")
	var auf := Liga.pruefe_aufstieg(bal, "holz", Liga.aufstieg_ab(bal, "holz"))
	assert_true(bool(auf["aufgestiegen"]))
	assert_eq(str(auf["klasse"]), "bronze")
	var dach := Liga.pruefe_aufstieg(bal, "sternenklasse", 9999)
	assert_false(bool(dach["aufgestiegen"]), "Sternenklasse ist das Dach")
	# KEIN Abstieg: das Regelwerk kennt gar keinen Pfad nach unten.
	for klasse in Katalog.KLASSEN:
		var nix := Liga.pruefe_aufstieg(bal, klasse, 0)
		assert_eq(str(nix["klasse"]), klasse, "0 Punkte lassen die Klasse in Ruhe")


func test_liga_startrecht_gates() -> void:
	var bal := _bal()
	assert_true(Liga.start_erlaubt(bal, "holz", "holz", 1))
	assert_false(Liga.start_erlaubt(bal, "holz", "bronze", 20), "Liga noch nicht erreicht")
	assert_false(Liga.start_erlaubt(bal, "gold", "gold", 17), "Pferde-Level-Gate (ab 18)")
	assert_true(Liga.start_erlaubt(bal, "gold", "gold", 18))
	assert_true(Liga.start_erlaubt(bal, "gold", "holz", 3), "runter starten ist ok")
	assert_almost(Liga.aufstieg_fortschritt(bal, "holz", 0), 0.0, 1e-6)
	assert_almost(Liga.aufstieg_fortschritt(bal, "holz", Liga.aufstieg_ab(bal, "holz")), 1.0, 1e-6)
	assert_almost(Liga.aufstieg_fortschritt(bal, "sternenklasse", 0), 1.0, 1e-6, "Dach = voll")


func test_turniertag_deterministisch() -> void:
	var bal := _bal()
	var a := Liga.turniertag_plan(bal, "2026-07-20", 4711)
	var b := Liga.turniertag_plan(bal, "2026-07-22", 4711)
	assert_eq(a["disziplinen"], b["disziplinen"], "gleiche Woche = gleicher Plan")
	var plan: Array = a["disziplinen"]
	assert_eq(plan.size(), 3, "3 Disziplinen je Woche")
	for disziplin: Variant in plan:
		assert_true(Katalog.DISZIPLINEN.has(str(disziplin)), "nur echte Disziplinen")
	assert_eq(plan.size(), (plan as Array).size())
	var unikate := {}
	for disziplin: Variant in plan:
		unikate[disziplin] = true
	assert_eq(unikate.size(), plan.size(), "keine Doppel im Plan")
	var andere_woche := Liga.turniertag_plan(bal, "2026-09-14", 4711)
	var anderer_seed := Liga.turniertag_plan(bal, "2026-07-20", 999)
	assert_true(
		andere_woche["disziplinen"] != plan or anderer_seed["disziplinen"] != plan,
		"Plan variiert über Wochen/Seeds"
	)
	assert_almost(float(a["bonus_mult"]), 1.25, 1e-6, "Turniertag-Bonusgold ×1,25")


func test_schleifen_und_trophaeen_keys() -> void:
	assert_eq(Liga.schleifen_key("springen", "holz"), "springen_holz")
	assert_eq(Liga.trophaee_fuer("tonnen", "sternenklasse", 1), "stern_tonnen")
	assert_eq(Liga.trophaee_fuer("tonnen", "silber", 2), "pokal_silber")
	assert_eq(Liga.trophaee_fuer("tonnen", "silber", 4), "", "ohne Podium nichts")
