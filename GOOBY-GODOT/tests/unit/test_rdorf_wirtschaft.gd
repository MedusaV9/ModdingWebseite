extends TestCase
## RW-4 — DorfWirtschaft (Läden Hufingen): Futterhof (Heu-Kapazität!),
## Ankauf, Reitladen (Gear über RanchWirtschaft), Möbel-Scheune (Deko →
## Bau-Lager, Möbel → Haus-Lager) und Schmiede — alles ATOMAR.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

var _dir_seq := 0


func _fresh_gs(coins: int) -> Node:
	RanchState.register_slice()
	_dir_seq += 1
	var dir := "user://rdorf_tests/laden_%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	gs.set_value("economy.coins", coins)
	return gs


func _teardown_gs(gs: Node) -> void:
	gs.free()
	SaveSchema.unregister_slice(RanchState.SLICE_ID)
	RanchState.reset_for_tests()


func test_futterhof_heu_kauf_mit_kapazitaet() -> void:
	var gs := _fresh_gs(1000)
	var res := DorfWirtschaft.futter_kaufen(gs, "heu_bund")
	assert_true(bool(res["ok"]))
	assert_eq(res["preis"], 35)
	assert_eq(res["menge"], 5)
	assert_eq(gs.get_value("ranch.wirtschaft.lager.heu"), 9, "4 Start + 5 Bund")
	assert_eq(gs.get_value("economy.coins"), 965)
	# Basis-Kapazität 10: noch EIN Ballen geht, der nächste nicht mehr.
	assert_true(bool(DorfWirtschaft.futter_kaufen(gs, "heu")["ok"]))
	var voll := DorfWirtschaft.futter_kaufen(gs, "heu")
	assert_false(bool(voll["ok"]))
	assert_eq(str(voll["fehler"]), DorfWirtschaft.FEHLER_LAGER_VOLL)
	assert_eq(gs.get_value("ranch.wirtschaft.lager.heu"), 10, "Kapazität hält")
	# Heulager Stufe 1 (12 Ballen) öffnet wieder Platz.
	gs.set_value("ranch.bau", {"anlagen": {"heulager": {"stufe": 1}}})
	assert_true(bool(DorfWirtschaft.futter_kaufen(gs, "heu")["ok"]), "Vorratshaltung wirkt")
	_teardown_gs(gs)


func test_futterhof_hafer_und_leckerli() -> void:
	var gs := _fresh_gs(100)
	assert_true(bool(DorfWirtschaft.futter_kaufen(gs, "hafer")["ok"]))
	assert_true(bool(DorfWirtschaft.futter_kaufen(gs, "leckerli")["ok"]))
	assert_true(bool(DorfWirtschaft.futter_kaufen(gs, "leckerli")["ok"]))
	var dorf := RanchDorfState.lese(gs)
	assert_eq(dorf["futter"], {"hafer": 1, "leckerli": 2})
	assert_eq(gs.get_value("economy.coins"), 100 - 12 - 6 - 6)
	var kaputt := DorfWirtschaft.futter_kaufen(gs, "pizza")
	assert_eq(str(kaputt["fehler"]), DorfWirtschaft.FEHLER_UNBEKANNT)
	_teardown_gs(gs)


func test_zu_teuer_aendert_nichts() -> void:
	var gs := _fresh_gs(5)
	var res := DorfWirtschaft.futter_kaufen(gs, "hafer")
	assert_false(bool(res["ok"]))
	assert_eq(str(res["fehler"]), DorfWirtschaft.FEHLER_ZU_TEUER)
	assert_eq(gs.get_value("economy.coins"), 5, "Münzen unangetastet")
	assert_eq(int(RanchDorfState.lese(gs)["futter"]["hafer"]), 0)
	_teardown_gs(gs)


func test_ankauf_verkauft_ernte() -> void:
	var gs := _fresh_gs(0)
	var res := DorfWirtschaft.ernte_verkaufen(gs, "heu", 3)
	assert_true(bool(res["ok"]))
	assert_eq(res["erloes"], 15, "3 x 5 G Ankauf")
	assert_eq(gs.get_value("ranch.wirtschaft.lager.heu"), 1, "4 Start - 3")
	assert_eq(gs.get_value("economy.coins"), 15)
	var leer := DorfWirtschaft.ernte_verkaufen(gs, "heu", 2)
	assert_false(bool(leer["ok"]))
	assert_eq(str(leer["fehler"]), DorfWirtschaft.FEHLER_LAGER_LEER)
	assert_eq(gs.get_value("ranch.wirtschaft.lager.heu"), 1, "Fehlversuch ändert nichts")
	_teardown_gs(gs)


func test_reitladen_gear_kauf() -> void:
	var gs := _fresh_gs(1000)
	var wbal := RanchWirtschaft.load_balance()
	var preis := RanchWirtschaft.gear_preis(wbal, "sattel", "rot")
	assert_true(preis > 0, "Sattelpreis aus wirtschaft.json")
	var res := DorfWirtschaft.gear_kaufen(gs, "sattel_rot")
	assert_true(bool(res["ok"]))
	assert_eq(res["preis"], preis)
	assert_eq(gs.get_value("economy.coins"), 1000 - preis)
	var owned: Array = gs.get_value("ranch.wirtschaft.gear.owned")
	assert_true(owned.has("sattel_rot"), "Gear liegt im gemeinsamen Bestand (RANCH-2)")
	var doppelt := DorfWirtschaft.gear_kaufen(gs, "sattel_rot")
	assert_eq(str(doppelt["fehler"]), "schonGekauft", "RanchWirtschaft-Regel greift")
	_teardown_gs(gs)


func test_moebelscheune_deko_ins_bau_lager() -> void:
	var gs := _fresh_gs(200)
	var res := DorfWirtschaft.deko_kaufen(gs, "bank_holz")
	assert_true(bool(res["ok"]))
	assert_eq(res["preis"], 80, "Preis kommt aus dem BAU-Katalog (eine Wahrheit)")
	assert_eq(gs.get_value("economy.coins"), 120)
	assert_eq(RanchBauState.lese(gs)["lager"], {"bank_holz": 1})
	# Nicht im Sortiment (heuballen_deko fehlt in dorf_waren) -> unbekannt.
	var fremd := DorfWirtschaft.deko_kaufen(gs, "heuballen_deko")
	assert_eq(str(fremd["fehler"]), DorfWirtschaft.FEHLER_UNBEKANNT)
	# Anlagen sind KEINE Scheunen-Ware.
	assert_eq(
		str(DorfWirtschaft.deko_kaufen(gs, "stallboxen")["fehler"]), DorfWirtschaft.FEHLER_UNBEKANNT
	)
	_teardown_gs(gs)


func test_moebelscheune_moebel_ins_haus_lager() -> void:
	var gs := _fresh_gs(500)
	var res := DorfWirtschaft.moebel_kaufen(gs, "loungeChair")
	assert_true(bool(res["ok"]))
	assert_eq(res["preis"], 120)
	assert_eq(gs.get_value("economy.coins"), 380)
	var storage: Array = gs.get_value("home.storage")
	var gefunden := false
	for eintrag: Dictionary in storage:
		if eintrag.get("item") == "loungeChair":
			gefunden = int(eintrag.get("count", 0)) == 1
	assert_true(gefunden, "Möbel liegt im Haus-Lager")
	assert_eq(
		str(DorfWirtschaft.moebel_kaufen(gs, "ufoSofa")["fehler"]), DorfWirtschaft.FEHLER_UNBEKANNT
	)
	_teardown_gs(gs)


func test_moebel_sortiment_existiert_im_furniture_katalog() -> void:
	var defs: Dictionary = FurnitureCatalog.defs()
	for ware: Dictionary in DorfKatalog.moebel(DorfKatalog.load_balance()):
		assert_true(
			defs.has(str(ware.get("id", ""))),
			"Scheunen-Möbel %s fehlt im FurnitureCatalog" % str(ware.get("id"))
		)


func test_schmiede_hufeisen_einmalig() -> void:
	var gs := _fresh_gs(500)
	var res := DorfWirtschaft.schmiede_kaufen(gs, "hufeisen_bronze")
	assert_true(bool(res["ok"]))
	assert_eq(res["preis"], 60)
	assert_eq(RanchDorfState.lese(gs)["hufeisen"]["owned"], ["hufeisen_bronze"])
	var doppelt := DorfWirtschaft.schmiede_kaufen(gs, "hufeisen_bronze")
	assert_eq(str(doppelt["fehler"]), DorfWirtschaft.FEHLER_SCHON_GEKAUFT)
	assert_eq(gs.get_value("economy.coins"), 440, "nur EINMAL bezahlt")
	_teardown_gs(gs)


func test_hufeisen_anlegen_und_abnehmen() -> void:
	var gs := _fresh_gs(1500)
	gs.set_value("ranch.tiere.pferde", {"p1": RanchPlaySlices.neues_pferd("Eins", "braun")})
	assert_eq(
		str(DorfWirtschaft.hufeisen_anlegen(gs, "p1", "hufeisen_gold")["fehler"]),
		DorfWirtschaft.FEHLER_NICHT_GEKAUFT,
		"erst kaufen"
	)
	assert_true(bool(DorfWirtschaft.schmiede_kaufen(gs, "hufeisen_gold")["ok"]))
	assert_true(bool(DorfWirtschaft.hufeisen_anlegen(gs, "p1", "hufeisen_gold")["ok"]))
	assert_eq(RanchDorfState.lese(gs)["hufeisen"]["proPferd"], {"p1": "hufeisen_gold"})
	assert_true(bool(DorfWirtschaft.hufeisen_anlegen(gs, "p1", "")["ok"]), "abnehmen")
	assert_eq(RanchDorfState.lese(gs)["hufeisen"]["proPferd"], {})
	assert_eq(
		str(DorfWirtschaft.hufeisen_anlegen(gs, "fremd", "hufeisen_gold")["fehler"]),
		DorfWirtschaft.FEHLER_KEIN_PFERD
	)
	_teardown_gs(gs)
