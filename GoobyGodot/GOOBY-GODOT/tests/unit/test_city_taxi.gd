extends TestCase
## W3a — TaxiLogic: Warte-Loop-Statemaschine (Doc E §4) inkl. Timestamps-
## Persistenz, App-Neustart-Recovery, Verpasst-Gebühr und Storno.

const NOW := 1768478400000


func test_rufen_plant_notifications() -> void:
	var res := TaxiLogic.rufen(TaxiLogic.default_slice(), NOW, 400, "beach")
	assert_true(res["ok"])
	assert_eq(res["kosten"], 10, "Taxi kostet 10 Münzen")
	var slice: Dictionary = res["slice"]
	assert_eq(slice["state"], "gerufen")
	assert_eq(slice["ankunftAt"], NOW + 400 * 1000)
	assert_eq(slice["zielId"], "beach")
	var notifs: Array = res["notifications"]
	assert_eq(notifs.size(), 3, "T−15 s / T+0 / T+60 s")
	assert_eq(notifs[0]["at_ms"], NOW + 400 * 1000 - 15000)
	assert_eq(notifs[1]["at_ms"], NOW + 400 * 1000)
	assert_eq(notifs[2]["at_ms"], NOW + 400 * 1000 + 60000)


func test_rufen_nur_in_idle() -> void:
	var gerufen: Dictionary = TaxiLogic.rufen(TaxiLogic.default_slice(), NOW, 300)["slice"]
	assert_false(TaxiLogic.rufen(gerufen, NOW, 300)["ok"], "doppelt rufen verboten")


func test_tick_gerufen_zu_wartet() -> void:
	var slice: Dictionary = TaxiLogic.rufen(TaxiLogic.default_slice(), NOW, 300)["slice"]
	var frueh := TaxiLogic.tick(slice, NOW + 299 * 1000)
	assert_eq(frueh["slice"]["state"], "gerufen", "vor Ankunft bleibt gerufen")
	assert_eq(frueh["events"].size(), 0)
	var da := TaxiLogic.tick(slice, NOW + 300 * 1000)
	assert_eq(da["slice"]["state"], "wartet")
	assert_eq(da["events"][0]["typ"], "wartet")


func test_einsteigen_im_fenster() -> void:
	var slice: Dictionary = TaxiLogic.rufen(TaxiLogic.default_slice(), NOW, 300)["slice"]
	slice = TaxiLogic.tick(slice, NOW + 300 * 1000)["slice"]
	var res := TaxiLogic.einsteigen(slice, NOW + 330 * 1000)
	assert_true(res["ok"], "innerhalb 60 s einsteigen")
	assert_eq(res["slice"]["state"], "fahrt")
	assert_eq(TaxiLogic.abgeschlossen(res["slice"])["state"], "idle", "Fahrt-Ende → idle")


func test_verpasst_nach_fenster() -> void:
	var slice: Dictionary = TaxiLogic.rufen(TaxiLogic.default_slice(), NOW, 300)["slice"]
	slice = TaxiLogic.tick(slice, NOW + 300 * 1000)["slice"]
	var res := TaxiLogic.tick(slice, NOW + 361 * 1000)
	assert_eq(res["slice"]["state"], "idle", "verpasst → wieder bestellbar")
	assert_eq(res["events"][0]["typ"], "verpasst")
	assert_eq(res["events"][0]["erstattung"], 5, "5 von 10 zurück (Gebühr 5)")
	assert_false(TaxiLogic.einsteigen(slice, NOW + 361 * 1000)["ok"], "zu spät")


func test_app_neustart_recovery_still() -> void:
	# App zu während GERUFEN, Neustart LANGE nach dem Fenster: EIN tick
	# wickelt wartet+verpasst still ab (Doc E §4 Recovery-Zeile).
	var slice: Dictionary = TaxiLogic.rufen(TaxiLogic.default_slice(), NOW, 300)["slice"]
	var res := TaxiLogic.tick(slice, NOW + 3600 * 1000)
	assert_eq(res["slice"]["state"], "idle")
	var typen: Array = []
	for e: Dictionary in res["events"]:
		typen.append(e["typ"])
	assert_eq(typen, ["wartet", "verpasst"], "übersprungene Phasen in Reihenfolge")


func test_storno_nur_in_gerufen() -> void:
	var slice: Dictionary = TaxiLogic.rufen(TaxiLogic.default_slice(), NOW, 300)["slice"]
	var res := TaxiLogic.storno(slice)
	assert_true(res["ok"])
	assert_eq(res["erstattung"], 8, "8 zurück = 2 Gebühr")
	assert_eq(res["slice"]["state"], "idle")
	assert_false(TaxiLogic.storno(TaxiLogic.default_slice())["ok"], "idle: nichts zu stornieren")
	var wartet: Dictionary = TaxiLogic.tick(slice, NOW + 300 * 1000)["slice"]
	assert_false(TaxiLogic.storno(wartet)["ok"], "wartet: zu spät zum Stornieren")


func test_rest_countdowns() -> void:
	var slice: Dictionary = TaxiLogic.rufen(TaxiLogic.default_slice(), NOW, 300)["slice"]
	assert_eq(TaxiLogic.warte_rest_s(slice, NOW + 100 * 1000), 200)
	assert_eq(TaxiLogic.fenster_rest_s(slice, NOW), 0, "kein Fenster in gerufen")
	var wartet: Dictionary = TaxiLogic.tick(slice, NOW + 300 * 1000)["slice"]
	assert_eq(TaxiLogic.fenster_rest_s(wartet, NOW + 310 * 1000), 50)


func test_normalize_heilt_junk() -> void:
	var healed := TaxiLogic.normalize_slice({"state": "quatsch", "ankunftAt": -5})
	assert_eq(healed["state"], "idle")
	assert_eq(healed["ankunftAt"], 0)
	assert_eq(TaxiLogic.normalize_slice("müll")["state"], "idle")
	var ok := TaxiLogic.normalize_slice({"state": "wartet", "ankunftAt": 12, "zielId": "beach"})
	assert_eq(ok["state"], "wartet", "gültige Zustände bleiben verbatim")
	assert_eq(ok["zielId"], "beach")
