extends TestCase
## M2 HAUS — Goobay-Verhandlung (Doc D §5.4). Die Logik ist PURE und zieht
## ihren Zufall aus einem übergebenen RNG → mit festem Seed deterministisch.
## Dazu die Pflichtmöbel-Regel (letztes Bett/Couch ist unverkäuflich) am
## echten GameState.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

const NOW_MS := 1768478400000
const TAG := "2026-07-25"

var _seq := 0


func _rng(saat: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = saat
	return rng


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://m2_goobay_tests/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.initialize(dir + "/save_v5.json")
	return gs


func _teardown(gs: Node) -> void:
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	HomeState.reset_for_tests()


func test_start_liegt_in_den_baendern() -> void:
	for saat in [1, 7, 99, 4711]:
		var session := GoobayLogic.start("chair", 100, 1.0, _rng(saat))
		assert_eq(session["status"], GoobayLogic.STATUS_OFFEN)
		assert_eq(session["runde"], 0)
		assert_eq(session["stimmung"], 0)
		assert_true(
			session["budget"] >= 95 and session["budget"] <= 135,
			"Budget im Band (ist %d)" % int(session["budget"])
		)
		assert_true(
			session["angebot"] >= 55 and session["angebot"] <= 75,
			"Eröffnung im Band (ist %d)" % int(session["angebot"])
		)
		assert_true(
			(
				session["geduld"] >= GoobayLogic.GEDULD_MIN
				and session["geduld"] <= GoobayLogic.GEDULD_MAX
			),
			"Geduld im Band"
		)


func test_nachfrage_skaliert_den_wert() -> void:
	var mager := GoobayLogic.start("chair", 100, 0.8, _rng(3))
	var fett := GoobayLogic.start("chair", 100, 1.3, _rng(3))
	assert_eq(int(mager["wert"]), 80)
	assert_eq(int(fett["wert"]), 130)
	assert_true(int(fett["angebot"]) > int(mager["angebot"]), "gefragt = besseres Angebot")


func test_hoeher_hebt_angebot_und_senkt_stimmung() -> void:
	var session := GoobayLogic.start("chair", 100, 1.0, _rng(11))
	# Riesiges Budget + viel Geduld: das Nachfassen darf hier nicht platzen.
	session["budget"] = 10_000
	session["geduld"] = 99
	var vorher := int(session["angebot"])
	GoobayLogic.hoeher(session, _rng(5))
	assert_eq(session["status"], GoobayLogic.STATUS_OFFEN)
	assert_eq(session["runde"], 1)
	assert_eq(session["stimmung"], 1, "Stimmung sinkt sichtbar")
	var neu := int(session["angebot"])
	assert_true(neu >= int(ceil(vorher * 1.18)), "mind. +18 %%")
	assert_true(neu <= int(ceil(vorher * 1.25)), "höchstens +25 %%")


func test_stimmung_deckelt_bei_max() -> void:
	var session := GoobayLogic.start("chair", 100, 1.0, _rng(2))
	session["budget"] = 10_000
	session["geduld"] = 99
	for _i in 10:
		GoobayLogic.hoeher(session, _rng(9))
	assert_eq(session["stimmung"], GoobayLogic.STIMMUNG_MAX)


func test_ueber_budget_endet_final_oder_abbruch() -> void:
	var final_gesehen := false
	var abbruch_gesehen := false
	for saat in range(1, 40):
		var session := GoobayLogic.start("chair", 100, 1.0, _rng(saat))
		session["budget"] = 1
		GoobayLogic.hoeher(session, _rng(saat * 13))
		var status := str(session["status"])
		assert_ne(status, GoobayLogic.STATUS_OFFEN, "über Budget bleibt nichts offen")
		if status == GoobayLogic.STATUS_FINAL:
			final_gesehen = true
			assert_true(int(session["angebot"]) <= int(session["budget"]), "final ≤ Budget")
		else:
			abbruch_gesehen = true
	assert_true(final_gesehen, "es gibt ALLERletzte Angebote")
	assert_true(abbruch_gesehen, "und geplatzte Deals")


func test_geduld_laeuft_ab() -> void:
	var session := GoobayLogic.start("chair", 100, 1.0, _rng(21))
	session["budget"] = 10_000
	session["geduld"] = 1
	GoobayLogic.hoeher(session, _rng(4))
	assert_ne(str(session["status"]), GoobayLogic.STATUS_OFFEN, "Geduld aufgebraucht")


func test_final_danach_ist_schluss() -> void:
	var session := GoobayLogic.start("chair", 100, 1.0, _rng(8))
	session["status"] = GoobayLogic.STATUS_FINAL
	GoobayLogic.hoeher(session, _rng(8))
	assert_eq(session["status"], GoobayLogic.STATUS_ABBRUCH, "nach final wird nicht gefeilscht")
	GoobayLogic.annehmen(session)
	assert_eq(session["status"], GoobayLogic.STATUS_ABBRUCH, "abgebrochen bleibt abgebrochen")
	assert_eq(int(session["erloes"]), 0)


func test_annehmen_und_abbrechen() -> void:
	var session := GoobayLogic.start("chair", 100, 1.0, _rng(6))
	GoobayLogic.annehmen(session)
	assert_eq(session["status"], GoobayLogic.STATUS_DEAL)
	assert_eq(int(session["erloes"]), int(session["angebot"]))
	assert_true(GoobayLogic.ist_beendet(session))
	GoobayLogic.abbrechen(session)
	assert_eq(session["status"], GoobayLogic.STATUS_DEAL, "ein Deal platzt nicht nachträglich")


func test_public_view_verdeckt_budget_und_geduld() -> void:
	var sicht := GoobayLogic.public_view(GoobayLogic.start("chair", 100, 1.0, _rng(1)))
	assert_false(sicht.has("budget"), "Budget bleibt verdeckt")
	assert_false(sicht.has("geduld"), "Geduld bleibt verdeckt")
	assert_true(sicht.has("angebot") and sicht.has("stimmung") and sicht.has("status"))


func test_post_bonus_und_abbruch_malus() -> void:
	assert_eq(GoobayLogic.post_bonus(100), 110)
	assert_almost(GoobayLogic.nachfrage_nach_abbruch(1.0), 0.9)
	assert_almost(
		GoobayLogic.nachfrage_nach_abbruch(GoobayLogic.NACHFRAGE_MIN),
		GoobayLogic.NACHFRAGE_MIN,
		1e-6,
		"unter das Band geht es nie"
	)


func test_verkaufswert_faellt_auf_35_prozent_zurueck() -> void:
	assert_eq(GoobayState.verkaufswert({"preis": 200}), 70)
	assert_eq(GoobayState.verkaufswert({"preis": 200, "verkaufswert": 90}), 90)


func test_pflichtmoebel_sind_unverkaeuflich() -> void:
	var platziert: Array = [{"uid": "i-1", "item": "bedSingle", "at": [0, 0], "rot": 0}]
	var lager: Array = [{"item": "chair", "count": 1}]
	assert_true(
		GoobayState.ist_pflicht_gesperrt("bedSingle", platziert, lager), "letztes Bett gesperrt"
	)
	assert_false(GoobayState.ist_pflicht_gesperrt("chair", platziert, lager), "Stuhl frei")
	lager.append({"item": "bedDouble", "count": 1})
	assert_false(
		GoobayState.ist_pflicht_gesperrt("bedSingle", platziert, lager),
		"zweites Bett im Lager gibt das erste frei"
	)
	assert_eq(GoobayState.slot_bestand("bett", platziert, lager), 2)


func test_angebotsliste_filtert_pflicht_und_gesperrte() -> void:
	var gs := _fresh_gs()
	HomeState.ensure_initialized(gs)
	HomeState.store_item(gs, "chair")
	var ids: Array = []
	for eintrag: Dictionary in GoobayState.angebote(gs, TAG):
		ids.append(str(eintrag["item"]))
	assert_true(ids.has("chair"), "Stuhl steht zum Verkauf")
	for id: String in ids:
		assert_false(
			(
				str(FurnitureCatalog.def(id).get("pflicht", "")) != ""
				and GoobayState.ist_pflicht_gesperrt(
					id, GoobayState.placed_items(gs), HomeState.storage(gs)
				)
			),
			"%s dürfte nicht gelistet sein" % id
		)
	GoobayState.abbruch_merken(gs, "chair", "sitzen", TAG)
	var nach_abbruch: Array = []
	for eintrag: Dictionary in GoobayState.angebote(gs, TAG):
		nach_abbruch.append(str(eintrag["item"]))
	assert_false(nach_abbruch.has("chair"), "heute nicht mehr listbar")
	assert_true(
		GoobayState.angebote(gs, "2026-07-26").any(
			func(e: Dictionary) -> bool: return str(e["item"]) == "chair"
		),
		"morgen wieder"
	)
	_teardown(gs)


func test_deal_bucht_muenzen_und_leert_das_lager() -> void:
	var gs := _fresh_gs()
	HomeState.ensure_initialized(gs)
	HomeState.store_item(gs, "chair")
	var vorher := int(gs.get_value("economy.coins", 0))
	var anzahl := StorageLogic.count_of(HomeState.storage(gs), "chair")
	var erloes := GoobayState.deal_abschliessen(gs, "chair", 50)
	assert_eq(erloes, 50)
	assert_eq(int(gs.get_value("economy.coins", 0)), vorher + 50)
	assert_eq(StorageLogic.count_of(HomeState.storage(gs), "chair"), anzahl - 1)
	assert_eq(
		GoobayState.deal_abschliessen(gs, "gibtsnicht", 50), 0, "was nicht da ist, geht nicht"
	)
	_teardown(gs)


func test_versand_gibt_zehn_prozent_mehr() -> void:
	var gs := _fresh_gs()
	HomeState.ensure_initialized(gs)
	HomeState.store_item(gs, "chair")
	var vorher := int(gs.get_value("economy.coins", 0))
	assert_eq(GoobayState.deal_abschliessen(gs, "chair", 100, true), 110)
	assert_eq(int(gs.get_value("economy.coins", 0)), vorher + 110)
	_teardown(gs)


func test_tagesnachfrage_bleibt_pro_tag_stabil() -> void:
	var gs := _fresh_gs()
	var erste := GoobayState.nachfrage(gs, "sitzen", TAG, _rng(5))
	var zweite := GoobayState.nachfrage(gs, "sitzen", TAG, _rng(77))
	assert_almost(erste, zweite, 1e-6, "gleicher Tag = gleicher Faktor")
	var morgen := GoobayState.nachfrage(gs, "sitzen", "2026-07-26", _rng(77))
	assert_true(morgen >= GoobayLogic.NACHFRAGE_MIN and morgen <= GoobayLogic.NACHFRAGE_MAX)
	_teardown(gs)
