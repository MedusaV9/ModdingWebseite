extends TestCase
## FERTIG-1: PostLogic — das TAGESPAKET der Post (Ersatz für den gestrichenen
## „Versand an Freunde kommt bald“-Platzhalter). Ein Paket pro Lokaltag,
## 15–40 Münzen deterministisch über den Tages-String geseedet.

const TAG_A := "2026-07-27"
const TAG_B := "2026-07-28"


func test_frischer_stand_hat_ein_paket() -> void:
	assert_true(PostLogic.verfuegbar({}, TAG_A), "ohne Abhol-Eintrag liegt ein Paket bereit")


func test_coins_deterministisch_und_in_grenzen() -> void:
	var a1 := PostLogic.coins_fuer(TAG_A)
	var a2 := PostLogic.coins_fuer(TAG_A)
	assert_eq(a1, a2, "gleicher Tag = gleiches Paket (kein Farm-Reroll)")
	for tag in [TAG_A, TAG_B, "2027-01-01", "2026-02-29"]:
		var coins := PostLogic.coins_fuer(str(tag))
		assert_true(
			coins >= PostLogic.COINS_MIN and coins <= PostLogic.COINS_MAX,
			"Paket '%s' in 15–40 (ist %d)" % [tag, coins]
		)


func test_hole_paket_bucht_und_sperrt_den_tag() -> void:
	var state := {"economy": {"coins": 100, "coinsEarned": 0}, "city": {}}
	var res := PostLogic.hole_paket(state, TAG_A)
	assert_true(bool(res["ok"]), "erste Abholung klappt")
	var coins := int(res["coins"])
	assert_eq(int(state["economy"]["coins"]), 100 + coins, "Münzen gebucht")
	assert_eq(str(state["city"]["postPaket"]["tag"]), TAG_A, "Abhol-Tag gemerkt")
	assert_false(PostLogic.verfuegbar(state, TAG_A), "heute ist abgeholt")
	var nochmal := PostLogic.hole_paket(state, TAG_A)
	assert_false(bool(nochmal["ok"]), "zweite Abholung am selben Tag scheitert")
	assert_eq(int(state["economy"]["coins"]), 100 + coins, "kein Doppel-Buchen")


func test_naechster_tag_bringt_neues_paket() -> void:
	var state := {"economy": {"coins": 0, "coinsEarned": 0}, "city": {}}
	PostLogic.hole_paket(state, TAG_A)
	assert_true(PostLogic.verfuegbar(state, TAG_B), "morgen liegt wieder eins bereit")
	var res := PostLogic.hole_paket(state, TAG_B)
	assert_true(bool(res["ok"]), "Abholung am Folgetag klappt")
