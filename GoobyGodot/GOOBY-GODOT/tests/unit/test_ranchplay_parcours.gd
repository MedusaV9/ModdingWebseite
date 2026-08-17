extends TestCase
## RANCH-2 — Hindernis-Parcours (RanchParcoursLogic): Kurs-Daten (10 Kurse,
## strukturell valide, Steigerung), Sprung-Bewertung (perfekt/gut/abwurf),
## Punkte/Kombo/Zeitbonus/Sterne, Difficulty-Fenster und die deterministische
## Bot-Zertifizierung (gleicher Seed = identischer Lauf, easy verzeiht mehr).

const Logic := preload("res://scripts/minigames/games/ranch_parcours/parcours_logic.gd")
const Feel := preload("res://scripts/ranch/gameplay/ride_feel.gd")


class FakeRegistry:
	extends RefCounted

	var balance: Dictionary = {}

	func get_balance(_key: String, default_value: Variant = null) -> Variant:
		return balance if not balance.is_empty() else default_value


func _kurse() -> Array:
	return Logic.load_kurse(FakeRegistry.new())


func test_kurse_laden_und_validieren() -> void:
	var kurse := _kurse()
	assert_eq(kurse.size(), Logic.KURS_ANZAHL, "10 Kurse")
	var fehler := Logic.validate_kurse(kurse)
	assert_eq(fehler.size(), 0, "Kurs-Daten strukturell sauber: %s" % ", ".join(fehler))


func test_kurse_steigern_sich() -> void:
	var kurse := _kurse()
	var vorher := 0
	for id in range(1, Logic.KURS_ANZAHL + 1):
		var kurs := Logic.kurs_by_id(kurse, id)
		assert_eq(int(kurs.get("id", 0)), id, "Kurs %d existiert" % id)
		var anzahl := (kurs.get("hindernisse", []) as Array).size()
		assert_true(anzahl >= vorher, "Kurs %d: Hinderniszahl sinkt nicht" % id)
		vorher = anzahl
	var erster := Logic.kurs_by_id(kurse, 1)
	var letzter := Logic.kurs_by_id(kurse, 10)
	assert_true(
		(letzter["hindernisse"] as Array).size() > (erster["hindernisse"] as Array).size(),
		"Kurs 10 hat mehr Hindernisse als Kurs 1"
	)


func test_registry_kann_kurse_ersetzen() -> void:
	var registry := FakeRegistry.new()
	registry.balance = {"parcours_kurse": [{"id": 1, "tempo": 5.0}]}
	var kurse := Logic.load_kurse(registry)
	assert_eq(kurse.size(), 1, "Content-Pack-Override greift")


func test_bewerte_sprung_fenster() -> void:
	var tempo := 6.0
	var weite := float(Feel.sprung_daten(tempo)["weite_m"])
	var x0 := 10.0
	var mittig := Logic.bewerte_sprung(x0, tempo, x0 + weite * 0.5, "zaun")
	assert_eq(mittig["qualitaet"], "perfekt", "Bogenmitte = perfekt")
	assert_almost(float(mittig["fehler_m"]), 0.0)
	var versetzt := Logic.bewerte_sprung(x0, tempo, x0 + weite * 0.5 + 0.7, "zaun")
	assert_eq(versetzt["qualitaet"], "gut", "0.7 m daneben > PERFEKT_M, noch sicher")
	var kurz := Logic.bewerte_sprung(x0, tempo, x0 + weite * 0.95, "zaun")
	assert_eq(kurz["qualitaet"], "abwurf", "Hindernis am Bogen-Ende = Abwurf")
	var breit := Logic.bewerte_sprung(x0, tempo, x0 + weite * 0.5, "wasser")
	assert_eq(breit["qualitaet"], "perfekt", "Wasser (1.6 m) passt mittig noch")


func test_difficulty_veraendert_die_toleranz() -> void:
	var easy := Logic.apply_difficulty(Logic.TUNE, "easy")
	var hard := Logic.apply_difficulty(Logic.TUNE, "hard")
	assert_almost(float(easy["TOLERANZ"]), 1.25)
	assert_almost(float(hard["TOLERANZ"]), 0.8)
	assert_eq(Logic.apply_difficulty(Logic.TUNE, "normal"), Logic.TUNE, "normal unverändert")
	assert_eq(
		float(Logic.apply_difficulty(Logic.TUNE, "quatsch").get("TOLERANZ")),
		float(Logic.TUNE["TOLERANZ"]),
		"unbekannter Modus fällt auf normal"
	)
	var tempo := 6.0
	var weite := float(Feel.sprung_daten(tempo)["weite_m"])
	var knapp := 10.0 + weite * 0.24
	assert_eq(
		Logic.bewerte_sprung(10.0, tempo, knapp, "zaun", easy)["qualitaet"],
		"gut",
		"easy weitet das sichere Fenster"
	)
	assert_eq(
		Logic.bewerte_sprung(10.0, tempo, knapp, "zaun", hard)["qualitaet"],
		"abwurf",
		"hard verengt es"
	)


func test_punkte_kombo_und_zeitbonus() -> void:
	assert_eq(Logic.sprung_punkte("perfekt", 0), 15)
	assert_eq(Logic.sprung_punkte("perfekt", 3), 21, "3er-Kombo = +6")
	assert_eq(Logic.sprung_punkte("perfekt", 99), 25, "Kombo-Deckel 10")
	assert_eq(Logic.sprung_punkte("gut", 2), 14)
	assert_eq(Logic.sprung_punkte("abwurf", 5), 0)
	assert_eq(Logic.zeitbonus(60.0, 50.0), 40, "10 s unter Par × 4")
	assert_eq(Logic.zeitbonus(60.0, 70.0), 0, "nie negativ")
	assert_eq(Logic.kurs_score(100, 40, false, 5), 155, "Punkte + Bonus + Kurs-Bonus")
	assert_eq(Logic.kurs_score(100, 40, true, 5), 180, "Erst-Abschluss +25")


func test_sterne_regeln() -> void:
	assert_eq(Logic.sterne(0, 50.0, 60.0), 3, "fehlerfrei unter Par")
	assert_eq(Logic.sterne(0, 65.0, 60.0), 2, "fehlerfrei über Par")
	assert_eq(Logic.sterne(1, 50.0, 60.0), 2)
	assert_eq(Logic.sterne(2, 50.0, 60.0), 1)


func test_bot_ist_deterministisch() -> void:
	var kurs := Logic.kurs_by_id(_kurse(), 5)
	var a := Logic.simulate_lauf(kurs, 42, "normal")
	var b := Logic.simulate_lauf(kurs, 42, "normal")
	assert_eq(str(a), str(b), "gleicher Seed = identischer Lauf")
	var anders := Logic.simulate_lauf(kurs, 43, "normal")
	assert_ne(str(a), str(anders), "anderer Seed streut anders")


func test_bot_schafft_jeden_kurs_auf_normal() -> void:
	var kurse := _kurse()
	for id in range(1, Logic.KURS_ANZAHL + 1):
		var res := Logic.simulate_lauf(Logic.kurs_by_id(kurse, id), 1, "normal")
		assert_true(int(res["score"]) > 0, "Kurs %d gibt Punkte" % id)
		assert_true(int(res["sterne"]) >= 1, "Kurs %d ist schaffbar" % id)
		assert_true(float(res["zeit_s"]) > 0.0)


func test_difficulty_ordnet_die_fehlerquote() -> void:
	var kurse := _kurse()
	var abwuerfe := {"easy": 0, "normal": 0, "hard": 0}
	for mode: String in abwuerfe.keys():
		for id in range(1, Logic.KURS_ANZAHL + 1):
			for seed_value in range(1, 6):
				var res := Logic.simulate_lauf(Logic.kurs_by_id(kurse, id), seed_value, mode)
				abwuerfe[mode] += int(res["abwuerfe"])
	assert_true(
		abwuerfe["easy"] <= abwuerfe["normal"],
		"easy verzeiht mehr (easy=%d normal=%d)" % [abwuerfe["easy"], abwuerfe["normal"]]
	)
	assert_true(
		abwuerfe["normal"] < abwuerfe["hard"],
		"hard straft mehr (normal=%d hard=%d)" % [abwuerfe["normal"], abwuerfe["hard"]]
	)
	assert_true(abwuerfe["easy"] < 15, "easy bleibt fair über 50 Läufe")
