extends TestCase  # gdlint: ignore=max-public-methods
## W15/MARKT — Eigenstand-Vollausbau (Doc D §6.3): deterministische
## Verkaufs-Sim, Elastizität-/Preis-Monotonie, Tagesmodifikator, verlustfreie
## Bestückung/Rückbuchung (auch bei vollem Lager), exakte Abrechnungs-Mathe,
## Kräuterkasten-Wochenertrag (zeitinjiziert), Rezept-Schema+Assets der drei
## neuen Craft-Rezepte und die Bauplan-/Material-Bridge zum City-Baumarkt.

## 2026-07-25 ist ein SAMSTAG (wie test_city_markt.gd): 12:00 UTC liegt im
## Marktfenster 8–14 Uhr. Drumherum: Freitag mittag, Samstag früh/abend.
const SA_MITTAG := 1784980800
const SA_MORGEN := SA_MITTAG - 5 * 3600
const SA_ABEND := SA_MITTAG + 3 * 3600
const FREITAG := SA_MITTAG - 86400
const MARKT_TAG := "2026-07-25"


class FakeGameState:
	extends RefCounted
	var state: Dictionary = {
		"city": {},
		"economy": {"coins": 0, "lifetimeCoins": 0},
		"inventory": {"items": {}, "food": {}},
		"home": {"storage": [], "materials": {}, "blueprints": [], "rooms": {}},
		"achievements": {"counters": {}},
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


func _gs_mit_food(food: Dictionary) -> FakeGameState:
	var gs := FakeGameState.new()
	gs.state["inventory"]["food"] = food
	return gs


func _slots(ware: String, menge: int, faktor: float) -> Array:
	return [{"ware": ware, "menge": menge, "faktor": faktor}]


## ------------------------------------------------ Sim: Determinismus


func test_sim_deterministisch_gleicher_seed_gleicher_erloes() -> void:
	var slots := _slots("pumpkin", 12, 1.1) + _slots("carrot", 6, 0.8)
	var seed_wert := MarktSim.tages_seed(MARKT_TAG)
	var a := MarktSim.simulate(slots, seed_wert)
	var b := MarktSim.simulate(slots, seed_wert)
	assert_eq(a["erloes"], b["erloes"], "gleicher Seed + Preise = gleicher Erlös")
	assert_eq(a["verkauft"], b["verkauft"], "identische Verkaufszähler")
	assert_eq(a["events"], b["events"], "identisches Replay")
	assert_eq(a["kunden"], b["kunden"], "identischer Kundenstrom")
	var anders := MarktSim.simulate(slots, MarktSim.tages_seed("2026-08-01"))
	assert_eq(anders["erloes"], anders["erloes"], "anderer Tag bleibt in sich stabil")


func test_sim_seed_stabil_ueber_tag_key() -> void:
	assert_eq(MarktSim.tages_seed(MARKT_TAG), MarktSim.tages_seed(MARKT_TAG))
	assert_ne(MarktSim.tages_seed(MARKT_TAG), MarktSim.tages_seed("2026-08-01"))


## ---------------------------------------------- Sim: Preis-Monotonie


func test_billiger_verkauft_nie_weniger() -> void:
	# Die Zufallsfolge hängt NICHT vom Preis ab — ein niedrigerer Faktor
	# hebt nur die Kaufchance. Über mehrere Seeds: billiger ⇒ ≥ Absatz.
	for tag in ["2026-07-25", "2026-08-01", "2026-08-08", "2026-08-15"]:
		var seed_wert := MarktSim.tages_seed(tag)
		var teuer: Dictionary = MarktSim.simulate(_slots("pumpkin", 20, 1.5), seed_wert)
		var billig: Dictionary = MarktSim.simulate(_slots("pumpkin", 20, 0.5), seed_wert)
		var teuer_stueck := int(teuer["verkauft"].get("pumpkin", 0))
		var billig_stueck := int(billig["verkauft"].get("pumpkin", 0))
		assert_true(
			billig_stueck >= teuer_stueck,
			"%s: billiger (%d) nie weniger als teuer (%d)" % [tag, billig_stueck, teuer_stueck]
		)


func test_attraktivitaet_faellt_streng_mit_dem_preis() -> void:
	var letzte := 1.0
	for schritt in 11:
		var faktor := 0.5 + 0.1 * schritt
		var p := MarktSim.attraktivitaet(faktor)
		assert_true(p <= letzte, "Attraktivität fällt monoton (Faktor %.1f)" % faktor)
		assert_true(p >= MarktSim.P_MIN and p <= MarktSim.P_MAX, "geklemmt")
		letzte = p


func test_saettigung_nutzt_elastizitaet_wie_doc() -> void:
	assert_almost(MarktSim.saettigung(0), 1.0, 1e-6, "frisch = volle Lust")
	assert_almost(MarktSim.saettigung(4), 0.8, 1e-6, "4 Stück = −20 %")
	assert_almost(MarktSim.saettigung(50), 0.5, 1e-6, "Boden 50 % hält")


## ------------------------------------------------- Tagesmodifikator


func test_tagesmodifikator_hebt_die_kaufchance() -> void:
	var modifikator := {"ware": "pumpkin", "mult": MarktSim.NACHFRAGE_MULT}
	var slot := {"ware": "pumpkin", "menge": 5, "faktor": 1.0}
	var fremd := {"ware": "carrot", "menge": 5, "faktor": 1.0}
	var mit := MarktSim.kauf_chance(slot, 0, modifikator)
	var ohne := MarktSim.kauf_chance(fremd, 0, modifikator)
	assert_almost(mit, ohne * MarktSim.NACHFRAGE_MULT, 1e-6, "Lieblingsware ×1.5")


func test_tagesmodifikator_deterministisch_und_aus_dem_katalog() -> void:
	var seed_wert := MarktSim.tages_seed(MARKT_TAG)
	var a := MarktSim.tagesmodifikator(seed_wert)
	assert_eq(a, MarktSim.tagesmodifikator(seed_wert), "gleicher Seed, gleiche Ware")
	assert_false(MarktWaren.ware(str(a["ware"])).is_empty(), "Ware existiert im Katalog")
	assert_almost(float(a["mult"]), MarktSim.NACHFRAGE_MULT, 1e-6)


## --------------------------------------- Bestückung & Rückbuchung


func test_bestuecken_und_entnehmen_verlustfrei() -> void:
	var gs := _gs_mit_food({"carrot": 5})
	var res := MarktStand.bestuecke(gs, FREITAG, "carrot", 3, 1.0)
	assert_true(res["ok"])
	assert_eq(res["menge"], 3)
	assert_eq(int(gs.state["inventory"]["food"]["carrot"]), 2, "3 liegen auf dem Stand")
	assert_eq(str(MarktStand.slice_von(gs)["tag"]), MARKT_TAG, "an den Samstag gebunden")
	assert_eq(MarktStand.status(gs, FREITAG), MarktStand.STATUS_WARTET)
	assert_eq(MarktStand.entnehme(gs, FREITAG, "carrot", 3), 3)
	assert_eq(int(gs.state["inventory"]["food"]["carrot"]), 5, "alles wieder im Korb")
	assert_true((MarktStand.slice_von(gs)["slots"] as Array).is_empty(), "Stand wieder leer")
	assert_eq(MarktStand.status(gs, FREITAG), MarktStand.STATUS_LEER)


func test_bestuecken_nie_mehr_als_der_vorrat_und_kein_unsinn() -> void:
	var gs := _gs_mit_food({"tomato": 2})
	assert_eq(int(MarktStand.bestuecke(gs, FREITAG, "tomato", 9, 1.0)["menge"]), 2)
	assert_eq(int(gs.state["inventory"]["food"]["tomato"]), 0)
	assert_false(MarktStand.bestuecke(gs, FREITAG, "tomato", 1, 1.0)["ok"], "Korb leer")
	assert_false(MarktStand.bestuecke(gs, FREITAG, "beton", 1, 1.0)["ok"], "keine Markt-Ware")
	assert_false(MarktStand.bestuecke(null, FREITAG, "tomato", 1, 1.0)["ok"], "ohne GameState")
	assert_false(
		MarktStand.bestuecke(gs, SA_MITTAG, "tomato", 1, 1.0)["ok"],
		"mitten im Markttag wird nicht mehr bestückt"
	)


func test_rueckbuchung_auch_bei_vollem_moebellager() -> void:
	# Möbel-Ware (home.storage): Rücklegen prüft BEWUSST keine Kapazität —
	# die Ware kam aus dem Lager, Zurücklegen darf nie etwas verschlucken.
	var gs := FakeGameState.new()
	gs.state["home"]["storageCapacity"] = 0
	StorageLogic.add(gs.state["home"]["storage"], "stool_rustic")
	var res := MarktStand.bestuecke(gs, FREITAG, "stool_rustic", 1, 1.0)
	assert_true(res["ok"], "Hocker liegt auf dem Stand")
	assert_eq(StorageLogic.count_of(gs.state["home"]["storage"], "stool_rustic"), 0)
	assert_eq(MarktStand.entnehme(gs, FREITAG, "stool_rustic", 1), 1)
	assert_eq(
		StorageLogic.count_of(gs.state["home"]["storage"], "stool_rustic"),
		1,
		"trotz Kapazität 0 verlustfrei zurück im Lager"
	)


func test_preis_slider_klemmt_auf_die_50_prozent_spanne() -> void:
	var gs := _gs_mit_food({"carrot": 2})
	MarktStand.bestuecke(gs, FREITAG, "carrot", 1, 9.0)
	var slot: Dictionary = (MarktStand.slice_von(gs)["slots"] as Array)[0]
	assert_almost(float(slot["faktor"]), MarktStand.FAKTOR_MAX, 1e-6, "oben geklemmt")
	assert_true(MarktStand.set_faktor(gs, FREITAG, "carrot", 0.01))
	slot = (MarktStand.slice_von(gs)["slots"] as Array)[0]
	assert_almost(float(slot["faktor"]), MarktStand.FAKTOR_MIN, 1e-6, "unten geklemmt")
	assert_false(MarktStand.set_faktor(gs, SA_MITTAG, "carrot", 1.0), "läuft schon: gesperrt")


## ------------------------------------------------------- Abrechnung


func test_abrechnung_mathe_exakt() -> void:
	var slots := _slots("pumpkin", 10, 1.2) + _slots("carrot", 8, 0.7)
	var sim := MarktSim.simulate(slots, MarktSim.tages_seed(MARKT_TAG))
	var karte := MarktSim.abrechnung(slots, sim)
	var summe := 0
	var beste_erloes := -1
	for zeile: Dictionary in karte["zeilen"]:
		var stueckpreis := MarktSim.stueckpreis(str(zeile["ware"]), _faktor_von(slots, zeile))
		assert_eq(int(zeile["stueckpreis"]), stueckpreis, "fester Slider-Stückpreis")
		assert_eq(
			int(zeile["erloes"]),
			int(zeile["verkauft"]) * stueckpreis,
			"Zeilen-Erlös = verkauft × Stückpreis"
		)
		assert_eq(
			int(zeile["verkauft"]) + int(zeile["uebrig"]),
			int(zeile["bestueckt"]),
			"verkauft + übrig = bestückt"
		)
		summe += int(zeile["erloes"])
		if int(zeile["erloes"]) > beste_erloes and int(zeile["verkauft"]) > 0:
			beste_erloes = int(zeile["erloes"])
	assert_eq(int(karte["erloes"]), summe, "Summe = Zeilensumme")
	assert_eq(int(karte["erloes"]), int(sim["erloes"]), "Abrechnung deckt die Sim")
	if beste_erloes > 0:
		var beste := str(karte["beste_ware"])
		for zeile: Dictionary in karte["zeilen"]:
			if str(zeile["ware"]) == beste:
				assert_eq(int(zeile["erloes"]), beste_erloes, "beste Ware = höchster Erlös")


func _faktor_von(slots: Array, zeile: Dictionary) -> float:
	for slot: Dictionary in slots:
		if str(slot["ware"]) == str(zeile["ware"]):
			return float(slot["faktor"])
	return 1.0


func test_abholen_bucht_erloes_ruecklaeufer_und_sells_zaehler() -> void:
	var gs := _gs_mit_food({"pumpkin": 10})
	MarktStand.bestuecke(gs, FREITAG, "pumpkin", 10, 0.5)
	assert_true(MarktStand.abholen(gs, FREITAG).is_empty(), "vor dem Markttag nichts abholbar")
	var karte := MarktStand.abholen(gs, SA_ABEND)
	assert_false(karte.is_empty(), "nach Marktschluss gibt es die Karte")
	var verkauft := 0
	for zeile: Dictionary in karte["zeilen"]:
		verkauft += int(zeile["verkauft"])
	assert_eq(int(gs.state["economy"]["coins"]), int(karte["erloes"]), "Erlös auf dem Konto")
	assert_eq(
		int(gs.state["inventory"]["food"]["pumpkin"]),
		10 - verkauft,
		"Unverkauftes liegt wieder im Korb — verlustfrei"
	)
	assert_eq(
		int(gs.state["achievements"]["counters"].get("sells", 0)),
		verkauft,
		"sells-Zähler (marketDay-Sticker) zählt die Stand-Verkäufe"
	)
	assert_eq(MarktStand.status(gs, SA_ABEND), MarktStand.STATUS_LEER, "Stand ist geräumt")
	assert_true(MarktStand.abholen(gs, SA_ABEND).is_empty(), "kein Doppel-Abholen")


func test_ankauf_verkauf_speist_ebenfalls_den_sells_zaehler() -> void:
	var gs := _gs_mit_food({"carrot": 4})
	MarktPreise.verkaufen(gs, SA_MITTAG, "carrot", 3)
	assert_eq(int(gs.state["achievements"]["counters"].get("sells", 0)), 3)


## --------------------------------------- Kräuterkasten (Craft-Synergie)


func _gs_mit_kasten() -> FakeGameState:
	var gs := FakeGameState.new()
	StorageLogic.add(gs.state["home"]["storage"], KraeuterKasten.ITEM_ID)
	return gs


func test_kraeuterkasten_wochenertrag_zeitinjiziert() -> void:
	var gs := _gs_mit_kasten()
	var t0 := FREITAG
	assert_eq(KraeuterKasten.schoepfe(gs, t0), 0, "erster Ruf ankert nur")
	assert_eq(KraeuterKasten.faellig(gs, t0 + 3 * 86400), 0, "Teilwoche zählt nicht")
	assert_eq(KraeuterKasten.faellig(gs, t0 + 8 * 86400), 1, "nach einer Woche: 1 Bund")
	assert_eq(KraeuterKasten.schoepfe(gs, t0 + 8 * 86400), 1)
	assert_eq(int(gs.state["inventory"]["items"]["kraeuter"]), 1, "Bund liegt im Inventar")
	assert_eq(
		KraeuterKasten.letzte_ernte_unix(gs),
		t0 + 7 * 86400,
		"Anker rückt um GANZE Wochen vor — der Wochenrest verfällt nicht"
	)
	assert_eq(KraeuterKasten.schoepfe(gs, t0 + 8 * 86400), 0, "kein Doppel-Schöpfen")
	assert_eq(KraeuterKasten.faellig(gs, t0 + 100 * 86400), KraeuterKasten.MAX_WOCHEN, "Deckel")


func test_kraeuterkasten_ohne_kasten_kein_ertrag() -> void:
	var gs := FakeGameState.new()
	assert_eq(KraeuterKasten.anzahl(gs), 0)
	assert_eq(KraeuterKasten.schoepfe(gs, FREITAG), 0)
	assert_eq(KraeuterKasten.faellig(gs, FREITAG + 30 * 86400), 0)


func test_kraeuterkasten_zaehlt_lager_und_platzierte() -> void:
	var gs := _gs_mit_kasten()
	gs.state["home"]["rooms"] = {
		"wohnzimmer": {"items": [{"item": KraeuterKasten.ITEM_ID, "uid": "u1"}]},
	}
	assert_eq(KraeuterKasten.anzahl(gs), 2, "Lager + platziert")
	KraeuterKasten.schoepfe(gs, FREITAG)
	assert_eq(KraeuterKasten.schoepfe(gs, FREITAG + 8 * 86400), 2, "1 Bund je Kasten")


func test_kraeuter_ware_ist_marktfaehig() -> void:
	assert_false(MarktWaren.ware(KraeuterKasten.WARE_ID).is_empty(), "kraeuter im Waren-Katalog")
	assert_true(MarktWaren.basis(KraeuterKasten.WARE_ID) > 0, "hat einen Basiswert")
	var gs := FakeGameState.new()
	gs.state["inventory"]["items"]["kraeuter"] = 2
	assert_eq(MarktWaren.vorrat(gs, "kraeuter"), 2, "liegt im items-Lager")


## ------------------------------------- Rezepte, Assets & Bauplan-Bridge


func test_neue_rezepte_schema_und_assets_valide() -> void:
	for rezept_id in ["r_vogelhaus", "r_kraeuterkasten", "r_windrad_deko"]:
		var rezept := CraftRecipes.recipe(rezept_id)
		assert_false(rezept.is_empty(), "%s existiert" % rezept_id)
		assert_ne(str(rezept["bauplan"]), "", "%s hat ein Bauplan-Gate" % rezept_id)
		for material_id: String in rezept["materialien"]:
			assert_false(
				CraftMaterials.def(material_id).is_empty(),
				"%s: Material %s ist katalogisiert" % [rezept_id, material_id]
			)
		var item_id := str(rezept["output"]["item"])
		var def := FurnitureCatalog.def(item_id)
		assert_false(def.is_empty(), "%s: Output %s im Möbelkatalog" % [rezept_id, item_id])
		assert_true(
			ResourceLoader.exists(FurnitureCatalog.glb_path(def)),
			"%s: GLB vorhanden (%s)" % [rezept_id, FurnitureCatalog.glb_path(def)]
		)
		assert_true(int(def.get("verkaufswert", 0)) > 0, "%s: marktfähiger Basiswert" % item_id)
		assert_false(
			MarktWaren.ware(item_id).is_empty() and item_id != "kraeuterkasten",
			"%s: Vogelhaus/Windrad sind Markt-Waren" % item_id
		)


func test_bauplaene_im_city_baumarkt_kaufbar() -> void:
	# Jedes neue Rezept-Gate "bp_<werkstatt_id>" hat einen kaufbaren
	# City-Baumarkt-Bauplan (bauplan_katalog) — die Bridge schaltet frei.
	var werkstatt_ids: Array[String] = []
	for eintrag: Dictionary in BaumarktKatalog.bauplaene():
		werkstatt_ids.append(str(eintrag.get("werkstatt_id", "")))
	for rezept_id in ["r_vogelhaus", "r_kraeuterkasten", "r_windrad_deko"]:
		var bauplan := str(CraftRecipes.recipe(rezept_id)["bauplan"])
		assert_true(
			werkstatt_ids.has(bauplan.trim_prefix("bp_")),
			"%s: Bauplan %s im Baumarkt" % [rezept_id, bauplan]
		)


func test_bauplan_bridge_schaltet_rezept_frei() -> void:
	var gs := FakeGameState.new()
	assert_false(CraftState.blueprints(gs).has("bp_vogelhaus"))
	gs.state["inventory"]["items"]["bauplan_vogelhaus"] = 1
	assert_true(
		CraftState.blueprints(gs).has("bp_vogelhaus"),
		"City-Bauplan (inventory.items) schaltet bp_vogelhaus frei"
	)
	assert_true(CraftState.has_blueprint(gs, "bp_vogelhaus"))


func test_material_bridge_uebernimmt_city_einkaeufe() -> void:
	var gs := FakeGameState.new()
	gs.state["inventory"]["items"] = {"bretter": 5, "saatgut": 2, "buch_weltraum": 1}
	CraftState.uebernehme_baumarkt_einkaeufe(gs)
	assert_eq(int(gs.state["home"]["materials"].get("holz", 0)), 5, "Bretter = Holz")
	assert_eq(int(gs.state["home"]["materials"].get("saatgut", 0)), 2)
	assert_false(gs.state["inventory"]["items"].has("bretter"), "Einkauf ist umgezogen")
	assert_eq(int(gs.state["inventory"]["items"]["buch_weltraum"]), 1, "Fremd-Items bleiben")


func test_markt_waren_katalog_konsistent() -> void:
	var gesehen: Dictionary = {}
	for eintrag: Dictionary in MarktWaren.waren():
		var id := str(eintrag["id"])
		assert_false(gesehen.has(id), "Ware %s nur einmal gelistet" % id)
		gesehen[id] = true
		assert_true(MarktWaren.basis(id) > 0, "%s hat einen Basiswert" % id)
		match str(eintrag["lager"]):
			"storage":
				assert_false(
					FurnitureCatalog.def(id).is_empty(), "%s: Möbel-Ware katalogisiert" % id
				)
			"food":
				if str(eintrag["kategorie"]) == "ernte":
					assert_false(MarktPreise.sorte(id).is_empty(), "%s: Ernte-Sorte" % id)
