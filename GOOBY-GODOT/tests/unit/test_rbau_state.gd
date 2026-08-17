extends TestCase
## RW-4 — RanchBauState: additiver Save `ranch.bau`, ATOMARE Gold-Käufe
## (zu teuer = NICHTS passiert), Kanten-Zäune, Abriss mit Teilerstattung,
## Ausbaustufen, Zonen-Freischaltung und die Bestands-Migration.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

var _dir_seq := 0


func _fresh_gs(coins: int) -> Node:
	RanchState.register_slice()
	_dir_seq += 1
	var dir := "user://rbau_tests/state_%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	gs.set_value("economy.coins", coins)
	return gs


func _teardown_gs(gs: Node) -> void:
	gs.free()
	SaveSchema.unregister_slice(RanchState.SLICE_ID)
	RanchState.reset_for_tests()


func _bal() -> Dictionary:
	return RanchBauKatalog.load_balance()


func test_normalize_heilt_kaputte_daten() -> void:
	var bau := RanchBauState.normalize_bau({"items": "kaputt", "zonen": [], "uidSeq": -3})
	assert_eq(bau["items"], [], "items repariert")
	assert_eq(bau["zonen"], ["start"], "start-Zone immer da")
	assert_eq(bau["uidSeq"], 1)
	var ok := RanchBauState.normalize_bau(
		{"anlagen": {"weide": {"stufe": 2}}, "lager": {"bank_holz": 2, "kaputt": 0}}
	)
	assert_eq(RanchBauState.anlage_stufe(ok, "weide"), 2, "gültige Stufe VERBATIM")
	assert_eq(ok["lager"], {"bank_holz": 2}, "0-Einträge fliegen raus")


func test_platzieren_bucht_gold_atomar() -> void:
	var gs := _fresh_gs(500)
	var res := RanchBauState.platziere(gs, "heulager", Vector2i(1, 7), 0, _bal())
	assert_true(bool(res["ok"]))
	assert_eq(res["kosten"], 200, "Stufe-1-Preis aus bau_balance")
	assert_eq(gs.get_value("economy.coins"), 300, "exakt abgebucht")
	var bau := RanchBauState.lese(gs)
	assert_eq((bau["items"] as Array).size(), 1)
	assert_eq(RanchBauState.anlage_stufe(bau, "heulager"), 1, "Anlage steht auf Stufe 1")
	_teardown_gs(gs)


func test_zu_teuer_aendert_nichts() -> void:
	var gs := _fresh_gs(199)
	var res := RanchBauState.platziere(gs, "heulager", Vector2i(1, 7), 0, _bal())
	assert_false(bool(res["ok"]))
	assert_eq(str(res["fehler"]), RanchBauState.FEHLER_ZU_TEUER)
	assert_eq(gs.get_value("economy.coins"), 199, "Münzen unangetastet")
	assert_eq((RanchBauState.lese(gs)["items"] as Array).size(), 0, "kein Eintrag")
	_teardown_gs(gs)


func test_anlage_nur_einmal_deko_mehrfach() -> void:
	var gs := _fresh_gs(9999)
	assert_true(bool(RanchBauState.platziere(gs, "heulager", Vector2i(1, 7), 0, _bal())["ok"]))
	var nochmal := RanchBauState.platziere(gs, "heulager", Vector2i(5, 7), 0, _bal())
	assert_eq(str(nochmal["fehler"]), RanchBauState.FEHLER_SCHON_GEBAUT)
	assert_true(bool(RanchBauState.platziere(gs, "bank_holz", Vector2i(4, 8), 0, _bal())["ok"]))
	assert_true(
		bool(RanchBauState.platziere(gs, "bank_holz", Vector2i(5, 8), 0, _bal())["ok"]),
		"Deko darf mehrfach stehen"
	)
	_teardown_gs(gs)


func test_kollision_blockt_vor_der_buchung() -> void:
	var gs := _fresh_gs(9999)
	assert_true(bool(RanchBauState.platziere(gs, "heulager", Vector2i(1, 7), 0, _bal())["ok"]))
	var coins_vorher := int(gs.get_value("economy.coins"))
	var drauf := RanchBauState.platziere(gs, "bank_holz", Vector2i(1, 7), 0, _bal())
	assert_false(bool(drauf["ok"]))
	assert_eq(str(drauf["fehler"]), RanchGridData.REASON_OCCUPIED)
	assert_eq(gs.get_value("economy.coins"), coins_vorher, "Fehlversuch kostet nichts")
	_teardown_gs(gs)


func test_zaun_kante_platzieren() -> void:
	var gs := _fresh_gs(100)
	var res := RanchBauState.platziere_kante(gs, "zaun_holz", Vector2i(3, 8), "S", _bal())
	assert_true(bool(res["ok"]))
	assert_eq(gs.get_value("economy.coins"), 80, "Zaunpreis 20 abgebucht")
	var eintrag: Dictionary = (RanchBauState.lese(gs)["items"] as Array)[0]
	assert_eq(eintrag["kante"], "N", "als N(3,9) normalisiert gespeichert")
	assert_eq(eintrag["at"], [3, 9])
	var doppelt := RanchBauState.platziere_kante(gs, "zaun_holz", Vector2i(3, 9), "N", _bal())
	assert_false(bool(doppelt["ok"]), "dieselbe physische Kante ist belegt")
	# Zell-Item auf Kanten-API und umgekehrt -> unbekannt.
	assert_eq(
		str(RanchBauState.platziere_kante(gs, "bank_holz", Vector2i(4, 8), "N", _bal())["fehler"]),
		RanchBauState.FEHLER_UNBEKANNT
	)
	assert_eq(
		str(RanchBauState.platziere(gs, "zaun_holz", Vector2i(4, 8), 0, _bal())["fehler"]),
		RanchBauState.FEHLER_UNBEKANNT
	)
	_teardown_gs(gs)


func test_abriss_erstattet_die_haelfte() -> void:
	var gs := _fresh_gs(1000)
	var res := RanchBauState.platziere(gs, "waschplatz", Vector2i(2, 8), 0, _bal())
	assert_true(bool(res["ok"]))
	assert_eq(gs.get_value("economy.coins"), 700)
	var weg := RanchBauState.entferne(gs, str(res["uid"]), _bal())
	assert_true(bool(weg["ok"]))
	assert_eq(weg["erstattung"], 150, "50% von 300")
	assert_eq(gs.get_value("economy.coins"), 850)
	var bau := RanchBauState.lese(gs)
	assert_eq((bau["items"] as Array).size(), 0)
	assert_eq(RanchBauState.anlage_stufe(bau, "waschplatz"), 0, "Anlage gilt als abgerissen")
	_teardown_gs(gs)


func test_abriss_nach_ausbau_erstattet_alle_stufen() -> void:
	var gs := _fresh_gs(5000)
	var res := RanchBauState.platziere(gs, "waschplatz", Vector2i(2, 8), 0, _bal())
	assert_true(bool(RanchBauState.ausbauen(gs, "waschplatz", _bal())["ok"]))
	# bezahlt: 300 + 700 = 1000; Erstattung 50% = 500.
	var weg := RanchBauState.entferne(gs, str(res["uid"]), _bal())
	assert_eq(weg["erstattung"], 500, "Erstattung rechnet ALLE bezahlten Stufen")
	_teardown_gs(gs)


func test_ausbauen_stufen_und_gates() -> void:
	var gs := _fresh_gs(10000)
	var ohne := RanchBauState.ausbauen(gs, "heulager", _bal())
	assert_eq(str(ohne["fehler"]), RanchBauState.FEHLER_NICHT_GEBAUT, "erst bauen")
	assert_true(bool(RanchBauState.platziere(gs, "heulager", Vector2i(1, 7), 0, _bal())["ok"]))
	var s2 := RanchBauState.ausbauen(gs, "heulager", _bal())
	assert_true(bool(s2["ok"]))
	assert_eq(s2["stufe"], 2)
	assert_eq(s2["kosten"], 500)
	var s3 := RanchBauState.ausbauen(gs, "heulager", _bal())
	assert_eq(s3["stufe"], 3)
	var voll := RanchBauState.ausbauen(gs, "heulager", _bal())
	assert_eq(str(voll["fehler"]), RanchBauState.FEHLER_AUSGEBAUT, "Stufe 3 ist Schluss")
	assert_eq(gs.get_value("economy.coins"), 10000 - 200 - 500 - 1000)
	_teardown_gs(gs)


func test_weidezaun_upgrade_braucht_keine_platzierung() -> void:
	var gs := _fresh_gs(1000)
	assert_eq(
		str(RanchBauState.platziere(gs, "weidezaun", Vector2i(1, 7), 0, _bal())["fehler"]),
		RanchBauState.FEHLER_UNBEKANNT,
		"Upgrade-Anlage ist nicht platzierbar"
	)
	var s1 := RanchBauState.ausbauen(gs, "weidezaun", _bal())
	assert_true(bool(s1["ok"]), "Stufe 1 direkt kaufbar")
	assert_eq(s1["kosten"], 250)
	assert_eq(RanchBauState.anlage_stufe(RanchBauState.lese(gs), "weidezaun"), 1)
	_teardown_gs(gs)


func test_zone_freischalten() -> void:
	var gs := _fresh_gs(1000)
	var nord := RanchBauState.zone_freischalten(gs, "nord", _bal())
	assert_true(bool(nord["ok"]))
	assert_eq(nord["kosten"], 800)
	assert_eq(gs.get_value("economy.coins"), 200)
	assert_eq(
		str(RanchBauState.zone_freischalten(gs, "nord", _bal())["fehler"]),
		RanchBauState.FEHLER_SCHON_FREI
	)
	var ost := RanchBauState.zone_freischalten(gs, "ost", _bal())
	assert_eq(str(ost["fehler"]), RanchBauState.FEHLER_ZU_TEUER, "1600 > 200 Rest")
	# Jetzt ist die Nordwiese bebaubar.
	assert_true(bool(RanchBauState.platziere(gs, "bank_holz", Vector2i(3, 3), 0, _bal())["ok"]))
	_teardown_gs(gs)


func test_lager_platzierung_ist_gratis() -> void:
	var gs := _fresh_gs(0)
	gs.update(
		func(state: Dictionary) -> void:
			var bau := RanchBauState.bau_im_state(state)
			RanchBauState.lager_hinzu(bau, "bank_holz", 2)
	)
	var res := RanchBauState.platziere(gs, "bank_holz", Vector2i(4, 8), 0, _bal())
	assert_true(bool(res["ok"]), "aus dem Lager trotz 0 Gold")
	assert_eq(res["kosten"], 0)
	assert_eq(RanchBauState.lese(gs)["lager"], {"bank_holz": 1}, "ein Exemplar verbraucht")
	assert_true(bool(RanchBauState.platziere(gs, "bank_holz", Vector2i(5, 8), 0, _bal())["ok"]))
	assert_eq(RanchBauState.lese(gs)["lager"], {}, "Lager leer")
	var dritte := RanchBauState.platziere(gs, "bank_holz", Vector2i(6, 8), 0, _bal())
	assert_false(bool(dritte["ok"]), "drittes Exemplar kostet wieder Gold (0 Gold da)")
	_teardown_gs(gs)


func test_migration_uebernimmt_altbestand() -> void:
	var gs := _fresh_gs(0)
	gs.set_value("ranch.wirtschaft.ausbau", {"boxen": 3, "reitplatz": true, "weidezaun": true})
	assert_true(RanchBauState.migriere_bestand(gs, _bal()))
	var bau := RanchBauState.lese(gs)
	assert_eq(RanchBauState.anlage_stufe(bau, "stallboxen"), 3, "Boxen-Stufe übernommen")
	assert_eq(RanchBauState.anlage_stufe(bau, "weide"), 1, "Weide Stufe 1 inklusive")
	assert_eq(RanchBauState.anlage_stufe(bau, "parcours"), 1, "Reitplatz -> Parcours")
	assert_eq(RanchBauState.anlage_stufe(bau, "weidezaun"), 1, "Weidezaun-Flag übernommen")
	assert_eq(gs.get_value("economy.coins"), 0, "Migration kostet NICHTS")
	assert_false(RanchBauState.migriere_bestand(gs, _bal()), "idempotent")
	# Migrierte Items stehen wirklich auf dem Grid (rekonstruierbar).
	var wieder := RanchBauState.grid_von(gs, _bal())
	assert_eq((wieder["leftovers"] as Array).size(), 0, "alle Migrations-Plätze gültig")
	_teardown_gs(gs)


class PackRegistry:
	## Minimal-Fake der ContentRegistry: liefert die balance-Overrides des
	## eingecheckten ranch_bau-Content-Packs.
	var werte: Dictionary

	func _init(pfad: String) -> void:
		var roh := RanchBauKatalog.read_json(pfad)
		werte = roh.get("values") if roh.get("values") is Dictionary else {}

	func get_balance(bereich: String, default_value: Variant = null) -> Variant:
		return werte.get(bereich, default_value)


func test_content_pack_ranch_bau_ist_additiv() -> void:
	# Basis = das ROHE eingebaute JSON (im Spiel laedt die ContentRegistry
	# das eingecheckte Pack bereits — load_balance() ohne Registry waere
	# hier also nicht Pack-frei).
	var basis := RanchBauKatalog.read_json(RanchBauKatalog.BALANCE_PATH)
	var registry := PackRegistry.new("res://content/ranch_bau/data/balance.json")
	var mit_pack := RanchBauKatalog.load_balance(registry)
	assert_false("windspiel" in RanchBauKatalog.ids(basis, "deko"), "nicht eingebaut")
	assert_true(
		"windspiel" in RanchBauKatalog.ids(mit_pack, "deko"), "Pack-Item erscheint im Bau-Katalog"
	)
	var defs := RanchBauKatalog.defs(mit_pack)
	assert_eq(defs["windspiel"]["kosten"], 110, "Preis aus dem Pack")
	# Additiv: bestehende Preise/Stufen bleiben exakt wie eingebaut.
	var basis_defs := RanchBauKatalog.defs(basis)
	for id: String in basis_defs:
		assert_eq(defs[id], basis_defs[id], "Pack laesst '%s' unangetastet" % id)
	# Und das Pack-Item ist mit dem normalen Kaufweg platzierbar.
	var gs := _fresh_gs(150)
	var res := RanchBauState.platziere(gs, "windspiel", Vector2i(4, 8), 0, mit_pack)
	assert_true(bool(res["ok"]), "Kauf ueber Pack-Katalog")
	assert_eq(gs.get_value("economy.coins"), 40, "110 G abgebucht")
	_teardown_gs(gs)
