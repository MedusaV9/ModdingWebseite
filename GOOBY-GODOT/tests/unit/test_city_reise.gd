extends TestCase
## W3a — ReiseLogic: Bestätigungs-Dialog (Preis/Dauer/Warnung, Doc E §3),
## Buchen über den W1d-vacation-Slice und Rückkehr-NUTZEN (souvenirCoins +
## Postkarten). Katalogpreise kommen VERBATIM aus scripts/logic/vacation.gd.

const Vacation := preload("res://scripts/logic/vacation.gd")

const NOW := 1768478400000


func test_bestaetigung_preis_dauer_nutzen() -> void:
	var info := ReiseLogic.bestaetigung("beach", 500)
	assert_eq(info["preis"], 180, "Glitzermeer kostet 180 (Katalog verbatim)")
	assert_eq(info["tage"], 3, "3 Tage weg — Kern der WARNUNG")
	assert_eq(info["souvenir_coins"], 30, "Nutzen-Hinweis: Souvenirs")
	assert_true(info["kann_zahlen"])
	assert_eq(info["name_key"], "travel.ziel.beach")


func test_bestaetigung_kann_nicht_zahlen() -> void:
	assert_false(ReiseLogic.bestaetigung("space", 349)["kann_zahlen"], "space kostet 350")
	assert_true(ReiseLogic.bestaetigung("space", 350)["kann_zahlen"], "exakt reicht")


func test_bestaetigung_unbekanntes_ziel() -> void:
	assert_true(ReiseLogic.bestaetigung("mond", 9999).is_empty())


func test_ziele_decken_katalog() -> void:
	assert_eq(ReiseLogic.ZIELE.size(), Vacation.CATALOG.size(), "UI-Liste = Katalog")
	for ziel_id in ReiseLogic.ZIELE:
		assert_true(Vacation.CATALOG.has(ziel_id), "Ziel %s im Katalog" % ziel_id)


func test_buchen_setzt_slice_und_kosten() -> void:
	var res := ReiseLogic.buchen(Vacation.default_slice(), "harbor", NOW)
	assert_true(res["ok"])
	assert_eq(res["kosten"], 200, "Hafenstadt-Preis")
	var v: Dictionary = res["vacation"]
	assert_eq(v["phase"], Vacation.PHASE_AWAY)
	assert_eq(v["destId"], "harbor")
	assert_eq(v["returnAt"], NOW + 3 * Vacation.MS_PER_DAY)
	assert_eq(v["pickupBy"], NOW + 3 * Vacation.MS_PER_DAY + Vacation.PICKUP_WINDOW_MS)


func test_buchen_doppelt_und_unbekannt_verboten() -> void:
	var weg: Dictionary = ReiseLogic.buchen(Vacation.default_slice(), "beach", NOW)["vacation"]
	assert_false(ReiseLogic.buchen(weg, "harbor", NOW)["ok"], "schon im Urlaub")
	assert_false(ReiseLogic.buchen(Vacation.default_slice(), "mond", NOW)["ok"])


func test_abholen_nutzen_souvenirs_und_postkarten() -> void:
	var weg: Dictionary = ReiseLogic.buchen(Vacation.default_slice(), "beach", NOW)["vacation"]
	var res := ReiseLogic.abholen(weg, NOW + 3 * Vacation.MS_PER_DAY + 1000)
	assert_true(res["ok"])
	assert_eq(res["souvenir_coins"], 30, "souvenirCoins fließen bei Rückkehr")
	assert_eq(res["postkarten"], 2, "1/voller Tag, gedeckelt auf tage−1")
	assert_eq(res["ziel_id"], "beach")
	var v: Dictionary = res["vacation"]
	assert_eq(v["phase"], Vacation.PHASE_NONE)
	assert_true(v["visited"].get("beach", false), "Sammelpass-Eintrag")
	assert_eq(v["trips"], 1)


func test_abholen_zu_frueh_verboten() -> void:
	var weg: Dictionary = ReiseLogic.buchen(Vacation.default_slice(), "beach", NOW)["vacation"]
	var res := ReiseLogic.abholen(weg, NOW + 1 * Vacation.MS_PER_DAY)
	assert_false(res["ok"], "während PHASE_AWAY keine Abholung")
	assert_eq(res["souvenir_coins"], 0)


func test_abholen_overdue_geht_noch() -> void:
	var weg: Dictionary = ReiseLogic.buchen(Vacation.default_slice(), "beach", NOW)["vacation"]
	var spaet := NOW + 3 * Vacation.MS_PER_DAY + Vacation.PICKUP_WINDOW_MS + 1000
	var res := ReiseLogic.abholen(weg, spaet)
	assert_true(res["ok"], "overdue = selbst Taxi genommen, Abholung schließt ab")
	assert_eq(res["souvenir_coins"], 30)
