extends TestCase
## W3a — GooberandoLogic: Bestell-Timer, Klingel, Übergabe, Trinkgeld-Buff
## (30 % / 2 h / ×0,75), „Trinkgeld schadet nie ;)“-Hinweis nach 3× keins,
## Abstell-Fallback nach 5 min Geduld (Doc E §5).

const NOW := 1768478400000
const GERICHT := {"id": "pizza", "preis": 30}


func _bestellt() -> Dictionary:
	return GooberandoLogic.bestellen(GooberandoLogic.default_slice(), NOW, 180, GERICHT)["slice"]


func test_bestellen_kosten_und_notification() -> void:
	var res := GooberandoLogic.bestellen(GooberandoLogic.default_slice(), NOW, 180, GERICHT)
	assert_true(res["ok"])
	assert_eq(res["kosten"], 33, "Preis 30 + Liefergebühr 3")
	assert_eq(res["slice"]["state"], "bestellt")
	assert_eq(res["slice"]["fertigAt"], NOW + 180 * 1000)
	assert_eq(res["notifications"].size(), 1, "eine Klingel-Notification")
	assert_false(GooberandoLogic.bestellen(res["slice"], NOW, 180, GERICHT)["ok"], "kein Doppel")


func test_tick_klingelt() -> void:
	var slice := _bestellt()
	assert_eq(GooberandoLogic.liefer_rest_s(slice, NOW + 60 * 1000), 120)
	var res := GooberandoLogic.tick(slice, NOW + 180 * 1000)
	assert_eq(res["slice"]["state"], "vorDerTuer")
	assert_eq(res["events"][0]["typ"], "vor_der_tuer")


func test_uebergabe_und_trinkgeld_buff() -> void:
	var slice: Dictionary = GooberandoLogic.tick(_bestellt(), NOW + 180 * 1000)["slice"]
	var ueb := GooberandoLogic.uebergabe(slice, NOW + 200 * 1000)
	assert_true(ueb["ok"])
	assert_eq(ueb["gerichtId"], "pizza", "Essen ins Inventar (Aufrufer)")
	assert_eq(ueb["slice"]["state"], "trinkgeld")
	var tg := GooberandoLogic.trinkgeld(ueb["slice"], NOW + 210 * 1000, true, 0.29)
	assert_eq(tg["kosten"], 5, "Trinkgeld = 5 Münzen")
	assert_true(tg["buff"], "roll 0.29 < 30 % → Buff")
	assert_eq(tg["slice"]["state"], "idle")
	assert_eq(tg["slice"]["lieferungen"], 1)
	assert_eq(tg["slice"]["trinkgelder"], 1)
	assert_true(GooberandoLogic.buff_aktiv(tg["slice"], NOW + 210 * 1000 + 7199000))
	assert_false(GooberandoLogic.buff_aktiv(tg["slice"], NOW + 210 * 1000 + 7200001), "2 h um")
	assert_almost(GooberandoLogic.energie_drain_faktor(tg["slice"], NOW + 300 * 1000), 0.75, 1e-9)


func test_kein_buff_bei_hohem_roll() -> void:
	var slice: Dictionary = GooberandoLogic.tick(_bestellt(), NOW + 180 * 1000)["slice"]
	slice = GooberandoLogic.uebergabe(slice, NOW + 200 * 1000)["slice"]
	var tg := GooberandoLogic.trinkgeld(slice, NOW + 210 * 1000, true, 0.31)
	assert_false(tg["buff"], "roll 0.31 ≥ 30 %")
	assert_almost(GooberandoLogic.energie_drain_faktor(tg["slice"], NOW), 1.0, 1e-9)


func test_hinweis_nach_drei_mal_keins() -> void:
	var slice := GooberandoLogic.default_slice()
	for i in 3:
		slice = GooberandoLogic.bestellen(slice, NOW, 60, GERICHT)["slice"]
		slice = GooberandoLogic.tick(slice, NOW + 60 * 1000)["slice"]
		slice = GooberandoLogic.uebergabe(slice, NOW + 61 * 1000)["slice"]
		var tg := GooberandoLogic.trinkgeld(slice, NOW + 62 * 1000, false, 0.9)
		slice = tg["slice"]
		if i < 2:
			assert_false(tg["hinweis"], "Hinweis erst beim 3. Mal (Lauf %d)" % i)
		else:
			assert_true(tg["hinweis"], "„Trinkgeld schadet nie ;)“ beim 3. Mal")
	# Hinweis kommt nur EINMAL
	slice = GooberandoLogic.bestellen(slice, NOW, 60, GERICHT)["slice"]
	slice = GooberandoLogic.tick(slice, NOW + 60 * 1000)["slice"]
	slice = GooberandoLogic.uebergabe(slice, NOW + 61 * 1000)["slice"]
	assert_false(
		GooberandoLogic.trinkgeld(slice, NOW + 62 * 1000, false, 0.9)["hinweis"], "nur einmal"
	)


func test_trinkgeld_reset_der_folge() -> void:
	var slice := GooberandoLogic.default_slice()
	slice["state"] = GooberandoLogic.STATE_TRINKGELD
	slice["ohneTrinkgeldFolge"] = 2
	var tg := GooberandoLogic.trinkgeld(slice, NOW, true, 0.9)
	assert_eq(tg["slice"]["ohneTrinkgeldFolge"], 0, "Trinkgeld resettet die Folge")


func test_abgestellt_nach_geduld() -> void:
	var slice: Dictionary = GooberandoLogic.tick(_bestellt(), NOW + 180 * 1000)["slice"]
	var res := GooberandoLogic.tick(slice, NOW + 180 * 1000 + 301 * 1000)
	assert_eq(res["slice"]["state"], "idle")
	assert_eq(res["events"][0]["typ"], "abgestellt")
	assert_eq(res["events"][0]["gerichtId"], "pizza", "Essen kommt TROTZDEM an")
	assert_eq(res["slice"]["ohneTrinkgeldFolge"], 0, "abgestellt zählt nicht als „keins“")
	assert_eq(res["slice"]["lieferungen"], 1)


func test_recovery_ueber_neustart() -> void:
	# App zu von Bestellung bis weit nach der Geduld: EIN tick wickelt ab.
	var slice := _bestellt()
	var res := GooberandoLogic.tick(slice, NOW + 3600 * 1000)
	var typen: Array = []
	for e: Dictionary in res["events"]:
		typen.append(e["typ"])
	assert_eq(typen, ["vor_der_tuer", "abgestellt"])
	assert_eq(res["slice"]["state"], "idle")


func test_gooberando_gerichte_aus_rehwei() -> void:
	var gerichte := CitySortiment.gooberando_gerichte()
	assert_eq(gerichte.size(), 3, "3 Gerichte im App-Sheet (Doc E §5.1)")
	for gericht: Dictionary in gerichte:
		assert_true(int(gericht.get("preis", 0)) > 0)
		assert_false(str(gericht.get("name_de", "")).is_empty())


func test_normalize_heilt_junk() -> void:
	assert_eq(GooberandoLogic.normalize_slice(42)["state"], "idle")
	var healed := GooberandoLogic.normalize_slice({"state": "kaputt", "lieferungen": -2})
	assert_eq(healed["state"], "idle")
	assert_eq(healed["lieferungen"], 0)
