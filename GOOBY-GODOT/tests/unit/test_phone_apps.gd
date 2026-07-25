extends TestCase
## M2/ORTE — IGohbie (Doc E §5.1): App-Registry (Reihenfolge, Icons, Texte,
## Kamera-Gate) und die Fahrdienst-Logik hinter Taxi + Guber, die sich EINE
## TaxiLogic-Maschine teilen und sich deshalb gegenseitig blockieren.

const ERWARTETE_REIHENFOLGE: Array[String] = [
	"taxi", "guber", "gooberando", "kamera", "freunde", "goobypal"
]


class FakeGameState:
	extends RefCounted
	var state: Dictionary = {
		"city": {"taxi": TaxiLogic.default_slice(), "fahrdienst": ""},
		"economy": {"coins": 300},
		"gooby": {"stats": {"energy": 80.0}},
		"inventory": {"items": {}, "food": {}},
	}

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var node: Variant = state
		for part in path.split("."):
			if node is Dictionary and (node as Dictionary).has(part):
				node = node[part]
			else:
				return fallback
		return node

	func set_value(path: String, wert: Variant) -> void:
		var teile := path.split(".")
		var node: Dictionary = state
		for i in teile.size() - 1:
			if not (node.get(teile[i]) is Dictionary):
				node[teile[i]] = {}
			node = node[teile[i]]
		node[teile[teile.size() - 1]] = wert

	func update(mutator: Callable) -> void:
		mutator.call(state)

	func notify_slice_changed(_slice_id: String) -> void:
		pass


## ---------------------------------------------------------- App-Registry


func test_registry_reihenfolge_ist_der_contract() -> void:
	assert_eq(PhoneApps.ids(), ERWARTETE_REIHENFOLGE, "App-Grid-Reihenfolge (Doc E §5.1)")


func test_jede_app_hat_texte_und_ein_icon() -> void:
	for app: Dictionary in PhoneApps.alle():
		var id := str(app["id"])
		for key_feld: String in ["name_key", "text_key"]:
			var key := str(app[key_feld])
			assert_ne(I18nService.t(key), key, "%s: Text fehlt (%s)" % [id, key])
		var icon := PhoneApps.icon_pfad(id)
		assert_true(ResourceLoader.exists(icon), "%s: Icon fehlt (%s)" % [id, icon])


func test_unbekannte_app_bleibt_leer() -> void:
	assert_true(PhoneApps.app("tetris").is_empty())
	assert_eq(PhoneApps.icon_pfad("tetris"), "")
	assert_false(PhoneApps.ist_offen("tetris", null), "unbekannte App ist nie offen")


func test_kamera_app_ist_das_pow_gate() -> void:
	var gs := FakeGameState.new()
	assert_false(PhoneApps.ist_offen("kamera", gs), "ohne Kamera bleibt die App zu")
	assert_eq(PhoneApps.gesperrt_key("kamera", gs), "phone.app.kamera_gesperrt")
	assert_ne(
		I18nService.t("phone.app.kamera_gesperrt"),
		"phone.app.kamera_gesperrt",
		"Sperr-Hinweis übersetzt"
	)
	gs.state["inventory"]["items"][PowAngebote.KAMERA_ITEM] = 1
	assert_true(PhoneApps.ist_offen("kamera", gs), "nach dem POW!-Kauf offen")
	assert_eq(PhoneApps.gesperrt_key("kamera", gs), "", "und ohne Hinweis")


func test_nur_die_kamera_ist_hart_gesperrt() -> void:
	var gs := FakeGameState.new()
	for eintrag: Dictionary in PhoneApps.grid(gs):
		var offen: bool = eintrag["offen"]
		if str(eintrag["id"]) == "kamera":
			assert_false(offen, "Kamera ist gegated")
		else:
			assert_true(offen, "%s bleibt antippbar (degradiert im UI)" % eintrag["id"])


func test_grid_liefert_kopien() -> void:
	var grid := PhoneApps.grid(null)
	grid[0]["id"] = "kaputt"
	assert_eq(PhoneApps.ids()[0], "taxi", "Manifest bleibt unangetastet")


## ------------------------------------------------------------ Fahrdienst


func test_guber_ist_teurer_und_schneller_als_das_taxi() -> void:
	assert_eq(Fahrdienst.kosten(Fahrdienst.TAXI), TaxiLogic.KOSTEN)
	assert_true(
		Fahrdienst.kosten(Fahrdienst.GUBER) > Fahrdienst.kosten(Fahrdienst.TAXI),
		"Guber kostet mehr"
	)
	var taxi := Fahrdienst.def(Fahrdienst.TAXI)
	var guber := Fahrdienst.def(Fahrdienst.GUBER)
	assert_true(
		int(guber["warte_max_s"]) < int(taxi["warte_min_s"]), "Guber ist immer schneller da"
	)
	assert_eq(Fahrdienst.kosten("rikscha"), 0, "unbekannter Dienst kostet nichts")


func test_erstattung_passt_zur_taxilogic() -> void:
	assert_eq(
		Fahrdienst.erstattung(Fahrdienst.TAXI, false),
		TaxiLogic.ERSTATTUNG_STORNO,
		"Taxi-Storno wie in der Maschine"
	)
	assert_eq(
		Fahrdienst.erstattung(Fahrdienst.TAXI, true),
		TaxiLogic.ERSTATTUNG_VERPASST,
		"Taxi-Verpasst wie in der Maschine"
	)
	assert_eq(Fahrdienst.erstattung(Fahrdienst.GUBER, false), 25 - Fahrdienst.GEBUEHR_STORNO)
	assert_eq(Fahrdienst.erstattung(Fahrdienst.GUBER, true), 25 - Fahrdienst.GEBUEHR_VERPASST)
	assert_eq(Fahrdienst.erstattung("rikscha", false), 0, "nie negativ")


func test_wartezeit_liegt_im_fenster_und_folgt_dem_debug_key() -> void:
	for dienst: String in [Fahrdienst.TAXI, Fahrdienst.GUBER]:
		var d := Fahrdienst.def(dienst)
		assert_eq(Fahrdienst.warte_s(dienst, 0, 0.0), int(d["warte_min_s"]), "%s: roll 0" % dienst)
		assert_eq(Fahrdienst.warte_s(dienst, 0, 1.0), int(d["warte_max_s"]), "%s: roll 1" % dienst)
		var mitte := Fahrdienst.warte_s(dienst, 0, 0.5)
		assert_true(
			mitte >= int(d["warte_min_s"]) and mitte <= int(d["warte_max_s"]),
			"%s: roll 0,5 im Fenster" % dienst
		)
		assert_eq(Fahrdienst.warte_s(dienst, 7, 0.9), 7, "%s: Dev-Key sticht" % dienst)


func test_nur_ein_wagen_gleichzeitig() -> void:
	var gs := FakeGameState.new()
	assert_eq(Fahrdienst.aktiver(gs), "", "im Leerlauf fährt niemand")
	assert_eq(Fahrdienst.blockiert_durch(gs, Fahrdienst.TAXI), "")
	var slice: Dictionary = TaxiLogic.rufen(TaxiLogic.default_slice(), 1000, 300)["slice"]
	gs.state["city"]["taxi"] = slice
	Fahrdienst.merke_dienst(gs, Fahrdienst.GUBER)
	assert_eq(Fahrdienst.aktiver(gs), Fahrdienst.GUBER, "der Guber ist unterwegs")
	assert_eq(
		Fahrdienst.blockiert_durch(gs, Fahrdienst.TAXI),
		Fahrdienst.GUBER,
		"die Taxi-App sieht den Guber als Blocker"
	)
	assert_eq(Fahrdienst.blockiert_durch(gs, Fahrdienst.GUBER), "", "sich selbst blockiert keiner")


func test_alter_save_ohne_dienst_gilt_als_taxi() -> void:
	var gs := FakeGameState.new()
	gs.state["city"]["taxi"] = TaxiLogic.rufen(TaxiLogic.default_slice(), 1000, 300)["slice"]
	gs.state["city"]["fahrdienst"] = ""
	assert_eq(Fahrdienst.aktiver(gs), Fahrdienst.TAXI, "Alt-Save-Fahrt ist eine Taxifahrt")


func test_rettungsweg_bei_leerer_energie() -> void:
	var gs := FakeGameState.new()
	assert_false(Fahrdienst.ist_rettungsweg(gs), "mit Energie ist es nur ein Taxi")
	gs.state["gooby"]["stats"]["energy"] = 0.0
	assert_true(Fahrdienst.ist_rettungsweg(gs), "bei 0 Energie ist es der Rettungsweg")
	assert_false(Fahrdienst.ist_rettungsweg(null))
