extends TestCase
## W15/CROPS — vier neue Anbau-Crops (radish/corn/eggplant/pumpkin), die das
## veggies-Album-Set 8/8 erspielbar machen: Schema + Web-Werte, Phasen-Assets,
## zeitinjizierte Wachstums-Simulation (pflanzen→gießen→reif→ernten),
## Collections-Buchung, REHWEI-Saatgut-Kauf (→ inventory.items → Verbrauch
## beim Pflanzen), Wind-Empfindlichkeit des Mais (Zaun-Synergie) und der
## Wochenmarkt-Verkauf der neuen Ernten.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

const NOW_MS := 1768478400000
const JETZT_S := 1768478400.0
## Samstag 2026-07-25 12:00 UTC — Markttag (Muster test_city_markt.gd).
const MARKT_S := 1784980800

const NEUE_CROPS: Array[String] = ["radish", "corn", "eggplant", "pumpkin"]
## Web-Referenz GOOBY/src/data/constants.js CROP_TABLE (sellPrice/yield/seedPrice).
const WEB_WERTE := {
	"radish": {"preis": 6, "ernte": 2, "samen_preis": 5},
	"corn": {"preis": 16, "ernte": 2, "samen_preis": 20},
	"eggplant": {"preis": 20, "ernte": 2, "samen_preis": 25},
	"pumpkin": {"preis": 55, "ernte": 1, "samen_preis": 35},
}

var _seq := 0


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://w15_crops_tests/%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	HomeState.register_slice()
	CityState.register_slice()
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.initialize(dir + "/save_v5.json")
	return gs


func _teardown(gs: Node) -> void:
	gs.free()
	SaveSchema.unregister_slice(HomeState.SLICE_ID)
	SaveSchema.unregister_slice(CityState.SLICE_ID)
	HomeState.reset_for_tests()


func _gib_samen(gs: Node, crop_id: String, menge := 1) -> void:
	var items: Dictionary = gs.get_value("inventory.items", {})
	items[GardenCrops.samen_item(crop_id)] = menge
	gs.set_value("inventory.items", items)


## Pflanzen → gießen → Zeit vorspulen → ernten auf der windstillen
## Grid-Mitte (2,2). Liefert die Erntemenge; `t` läuft kumulativ weiter.
func _anbau_zyklus(gs: Node, crop_id: String, t: Dictionary) -> int:
	var beet := Vector2i(2, 2)
	assert_true(GardenState.pflanzen(gs, beet, crop_id), "%s: pflanzen" % crop_id)
	assert_true(GardenState.giessen(gs, beet, float(t["s"])), "%s: gießen" % crop_id)
	t["s"] = float(t["s"]) + GardenCrops.total_minutes(crop_id) * 60.0
	GardenState.tick(gs, float(t["s"]))
	assert_true(
		GardenGrowth.ist_erntereif(GardenState.grid(gs).cell(beet)), "%s: erntereif" % crop_id
	)
	return GardenState.ernten(gs, beet)


# ── Schema & Web-Werte ───────────────────────────────────────────────────────


func test_neue_crops_schema_und_web_werte() -> void:
	for id: String in NEUE_CROPS:
		var crop := GardenCrops.crop(id)
		assert_false(crop.is_empty(), "%s existiert im Katalog" % id)
		assert_true(GardenCrops.LICHT_ARTEN.has(str(crop["licht"])), "%s: Lichtart" % id)
		assert_false(bool(crop["exot"]), "%s: kein Exot — Set ohne Gewächshaus schließbar" % id)
		assert_eq(GardenCrops.base_price(id), int(WEB_WERTE[id]["preis"]), "%s: sellPrice" % id)
		assert_eq(int(crop["ernte"]), int(WEB_WERTE[id]["ernte"]), "%s: yield" % id)
		assert_eq(GardenCrops.samen_item(id), "samen_%s" % id, "%s: Saatgut-Item" % id)
		assert_ne(str(crop["food"]), "", "%s: Ernte landet im Food-Inventar" % id)
	assert_true(GardenCrops.wind_empfindlich("corn"), "Mais ist wind-empfindlich")
	assert_false(GardenCrops.wind_empfindlich("radish"), "Radieschen nicht")
	assert_false(GardenCrops.wind_empfindlich("carrot"), "Alt-Crops nicht")
	assert_eq(GardenCrops.samen_item("carrot"), "", "Alt-Crops bleiben frei pflanzbar")
	# Einordnung: Radieschen ist das schnellste Crop, Kürbis das langsamste
	# und wertvollste Nicht-Exot-Crop.
	for id: String in GardenCrops.ids():
		if id == "radish":
			continue
		assert_true(
			GardenCrops.total_minutes("radish") < GardenCrops.total_minutes(id),
			"radish schneller als %s" % id
		)
		if not bool(GardenCrops.crop(id)["exot"]) and id != "pumpkin":
			assert_true(
				GardenCrops.total_minutes("pumpkin") > GardenCrops.total_minutes(id),
				"pumpkin langsamer als %s" % id
			)
			assert_true(
				GardenCrops.base_price("pumpkin") > GardenCrops.base_price(id),
				"pumpkin wertvoller als %s" % id
			)


func test_markt_preise_synchron_zum_katalog() -> void:
	# markt_preise.json führte die Web-sellPrices schon seit M2 — jetzt
	# müssen Katalog-preis und Markt-basis für die neuen Crops übereinstimmen.
	for id: String in NEUE_CROPS:
		var sorte := MarktPreise.sorte(id)
		assert_false(sorte.is_empty(), "%s: Markt kennt die Sorte" % id)
		assert_eq(int(sorte["basis"]), GardenCrops.base_price(id), "%s: basis == preis" % id)


# ── Phasen-Visuals ───────────────────────────────────────────────────────────


func test_phasen_assets_existieren() -> void:
	for id: String in NEUE_CROPS:
		assert_true(HomeProps.CROP_STUFEN_GLBS.has(id), "%s: Stufen-Modelle definiert" % id)
		var stufen: Array = HomeProps.CROP_STUFEN_GLBS[id]
		assert_true(stufen.size() >= 2, "%s: mindestens Spross + reif" % id)
		for pfad: String in stufen:
			assert_true(FileAccess.file_exists(pfad), "GLB fehlt: %s" % pfad)
	var radish: Array = HomeProps.CROP_STUFEN_GLBS["radish"]
	assert_true(str(radish.back()).ends_with("crop_turnip.glb"), "Radieschen reif = Turnip")
	var pumpkin: Array = HomeProps.CROP_STUFEN_GLBS["pumpkin"]
	assert_true(
		str(pumpkin.back()).ends_with("crop_pumpkin.glb"), "Kürbis nutzt das Repo-Kürbis-GLB"
	)
	assert_eq(HomeProps.CROP_STUFEN_GLBS["corn"].size(), 4, "Mais wächst sichtbar in Phasen")
	# Food-GLBs der neuen Ernten (Kühlschrank/REHWEI-Konvention essen/<id>.glb).
	for food_id: Array in [["radish"], ["eggplant"]]:
		assert_true(
			FileAccess.file_exists("res://assets/city/essen/%s.glb" % food_id[0]),
			"Food-GLB fehlt: %s" % food_id[0]
		)


func test_stufen_index_mathe() -> void:
	# Reif (anteil 1.0) zeigt IMMER das letzte Modell, die Wachstumsphase
	# verteilt sich gleichmäßig auf die früheren (Web-Semantik crops.js).
	assert_eq(HomeProps.crop_stufen_index(2, 0.15), 0, "Spross")
	assert_eq(HomeProps.crop_stufen_index(2, 0.5), 0, "halbreif bleibt Spross")
	assert_eq(HomeProps.crop_stufen_index(2, 1.0), 1, "reif = letzter Eintrag")
	assert_eq(HomeProps.crop_stufen_index(4, 0.15), 0, "Mais Stufe 0")
	assert_eq(HomeProps.crop_stufen_index(4, 1.0 / 3.0), 1, "Mais Stufe 1")
	assert_eq(HomeProps.crop_stufen_index(4, 2.0 / 3.0), 2, "Mais Stufe 2")
	assert_eq(HomeProps.crop_stufen_index(4, 1.0), 3, "Mais reif")
	assert_eq(HomeProps.crop_stufen_index(3, 2.0 / 3.0), 1, "Aubergine jung")
	assert_eq(HomeProps.crop_stufen_index(1, 0.4), 0, "Ein-Modell-Fallback")


# ── Wachstum & Collections ───────────────────────────────────────────────────


func test_wachstums_simulation_und_collections() -> void:
	var gs := _fresh_gs()
	var t := {"s": JETZT_S}
	GardenState.tick(gs, float(t["s"]))
	for id: String in NEUE_CROPS:
		_gib_samen(gs, id)
		var menge := _anbau_zyklus(gs, id, t)
		assert_eq(menge, int(WEB_WERTE[id]["ernte"]), "%s: Erntemenge" % id)
		assert_eq(int(GardenState.ernte(gs).get(id, 0)), menge, "%s: Ernte-Lager" % id)
		assert_eq(int(gs.get_value("inventory.food.%s" % id, 0)), menge, "%s: Food-Inventar" % id)
		assert_true(
			CollectionsLogic.count_of(gs.get_value("collections", {}), "veggies", id) >= 1,
			"%s: veggies-Sticker gebucht" % id
		)
	# Die vier Alt-Sorten dazu — damit ist das veggies-Set 8/8 komplett.
	for id: String in ["carrot", "tomate", "melone", "salat"]:
		_anbau_zyklus(gs, id, t)
	assert_true(
		CollectionsLogic.is_set_complete(gs.get_value("collections", {}), "veggies"),
		"veggies-Set 8/8 erspielbar"
	)
	_teardown(gs)


func test_food_verwertung_ehrlich() -> void:
	# Alle vier Ernten sind ECHTE FoodCatalog-Speisen: corn/pumpkin seit
	# W13/FOOD, radish/eggplant seit W15/CROPS (Kenney-GLBs liegen jetzt
	# unter assets/city/essen/, Deltas verbatim Web-FOOD_TABLE). Damit ist
	# der volle Weg Ernte → Kühlschrank („Gemüse“-Regal) → Füttern offen —
	# der ef1-Katalog-Invariantentest deckt die Garten-Crops mit ab.
	for id: String in NEUE_CROPS:
		assert_true(FoodCatalog.FOODS.has(id), "%s ist FoodCatalog-Speise" % id)
		assert_eq(FoodCatalog.kategorie(id), "gemuese", "%s: Gemüse-Regal" % id)
	assert_eq(int(FoodCatalog.deltas("radish")["hunger"]), 8, "radish: Web-hunger verbatim")
	assert_eq(int(FoodCatalog.deltas("eggplant")["hunger"]), 16, "eggplant: Web-hunger verbatim")
	for id: String in ["radish", "eggplant"]:
		assert_true(I18nService.table("de").has("rewards.food.%s" % id), "DE-Anzeigename: %s" % id)
		assert_true(I18nService.table("en").has("rewards.food.%s" % id), "EN-Anzeigename: %s" % id)


# ── Saatgut (REHWEI → Inventar → Verbrauch) ──────────────────────────────────


func test_rehwei_saatgut_kauf_und_verbrauch() -> void:
	var gs := _fresh_gs()
	gs.set_value("economy.coins", 100)
	var saatgut := CitySortiment.saatgut(CitySortiment.REHWEI_PFAD)
	assert_eq(saatgut.size(), 4, "vier Saatgut-Sorten bei REHWEI")
	for id: String in NEUE_CROPS:
		var ware := CitySortiment.ware(saatgut, "samen_%s" % id)
		assert_false(ware.is_empty(), "samen_%s im Sortiment" % id)
		assert_eq(int(ware["preis"]), int(WEB_WERTE[id]["samen_preis"]), "%s: Web-seedPrice" % id)
		assert_eq(str(ware["inventar"]), "samen_%s" % id, "%s: landet in items" % id)
	var sheet := HaendlerSheet.new()
	sheet.gs = gs
	sheet.waren = saatgut
	tree.root.add_child(sheet)
	var ware := CitySortiment.ware(saatgut, "samen_radish")
	assert_true(sheet.kaufe(ware), "Kauf klappt")
	assert_eq(int(gs.get_value("economy.coins", 0)), 95, "5 Münzen bezahlt")
	assert_eq(int(gs.get_value("inventory.items.samen_radish", 0)), 1, "Samen im Inventar")
	assert_eq(GardenState.samen_count(gs, "radish"), 1, "Garten sieht den Samen")
	# Pflanzen verbraucht den Samen; ohne Samen prallt das Beet ab.
	assert_true(GardenState.pflanzen(gs, Vector2i(2, 2), "radish"), "mit Samen pflanzbar")
	assert_eq(GardenState.samen_count(gs, "radish"), 0, "Samen verbraucht")
	assert_false(GardenState.pflanzen(gs, Vector2i(3, 2), "radish"), "ohne Samen kein Beet")
	assert_eq(GardenState.samen_count(gs, "carrot"), -1, "Alt-Crops brauchen keine Samen")
	assert_true(GardenState.pflanzen(gs, Vector2i(3, 2), "carrot"), "Möhre bleibt frei")
	sheet.queue_free()
	await wait_frames(1)
	_teardown(gs)


# ── Wind-Empfindlichkeit (Mais ↔ Zaun) ───────────────────────────────────────


func test_wind_empfindlichkeit_und_zaun_schutz() -> void:
	var size := Vector2i(10, 8)
	var rand := Vector2i(0, 0)
	assert_almost(GardenGrowth.wind_faktor(rand, size, {}, false), 0.85, 1e-6, "normal")
	assert_almost(GardenGrowth.wind_faktor(rand, size, {}, false, true), 0.7, 1e-6, "empfindlich")
	assert_almost(
		GardenGrowth.wind_faktor(Vector2i(4, 4), size, {}, false, true), 1.0, 1e-6, "Mitte"
	)
	assert_almost(
		GardenGrowth.wind_faktor(rand, size, {rand: true}, false, true),
		1.0,
		1e-6,
		"Zaun schirmt auch empfindliche Crops komplett ab"
	)
	assert_almost(GardenGrowth.wind_faktor(rand, size, {}, true, true), 1.0, 1e-6, "Gewächshaus")
	# Integration über faktoren(): Mais am Rand leidet stärker als die Möhre,
	# ein Zaun holt ihn zurück auf ×1.0 — die Zaun-Synergie rechnet sich.
	var grid := GardenGrid.new(size)
	grid.set_cell(
		rand,
		{"kind": "plot", "crop": "corn", "stage": 0, "progress_min": 0.0, "watered_until": 9e9}
	)
	var mais := GardenGrowth.faktoren(grid, rand, 100.0, false, {})
	assert_almost(float(mais["wind"]), 0.7, 1e-6, "Mais im Randwind")
	grid.set_cell(
		rand,
		{"kind": "plot", "crop": "carrot", "stage": 0, "progress_min": 0.0, "watered_until": 9e9}
	)
	var moehre := GardenGrowth.faktoren(grid, rand, 100.0, false, {})
	assert_almost(float(moehre["wind"]), 0.85, 1e-6, "Möhre im Randwind")
	grid.set_cell(
		rand,
		{"kind": "plot", "crop": "corn", "stage": 0, "progress_min": 0.0, "watered_until": 9e9}
	)
	grid.edges.append({"from": Vector2i(0, 0), "dir": "E", "len": 4, "fence": "fence_wood"})
	var geschuetzt := GardenGrowth.faktoren(grid, rand, 100.0, false, {})
	assert_almost(float(geschuetzt["wind"]), 1.0, 1e-6, "Zaun-Synergie")
	assert_almost(
		float(geschuetzt["rate"]) / maxf(float(mais["rate"]), 1e-9),
		1.0 / 0.7,
		1e-6,
		"Zaun beschleunigt Rand-Mais um den vollen Malus"
	)


# ── Wochenmarkt ──────────────────────────────────────────────────────────────


func test_markt_verkauf_der_neuen_ernten() -> void:
	var gs := _fresh_gs()
	gs.set_value("inventory.food", {"radish": 2, "pumpkin": 1})
	assert_eq(MarktPreise.marktpreis("pumpkin"), 63, "Kürbis: 55 × 1,15 gerundet")
	# Startguthaben festhalten (Economy-Slice startet nicht bei 0) — geprüft
	# wird das VERKAUFS-Delta, nicht der Kontostand.
	var start_muenzen := int(gs.get_value("economy.coins", 0))
	var erwartet := MarktPreise.erloes("radish", 2, 0)
	var res := MarktPreise.verkaufen(gs, MARKT_S, "radish", 2)
	assert_true(bool(res["ok"]), "Radieschen-Verkauf klappt")
	assert_eq(int(res["erloes"]), erwartet, "Elastizitäts-Erlös")
	assert_eq(int(gs.get_value("inventory.food.radish", 0)), 0, "Korb leer")
	var kuerbis := MarktPreise.verkaufen(gs, MARKT_S, "pumpkin", 1)
	assert_true(bool(kuerbis["ok"]), "Kürbis-Verkauf klappt")
	assert_eq(int(kuerbis["erloes"]), 63, "Kürbis zahlt den vollen Marktpreis")
	assert_eq(
		int(gs.get_value("economy.coins", 0)) - start_muenzen,
		erwartet + 63,
		"Münzen gutgeschrieben"
	)
	_teardown(gs)


# ── Strings ──────────────────────────────────────────────────────────────────


func test_ernte_sprueche_und_saatgut_strings_de_en() -> void:
	for locale: String in ["de", "en"]:
		var tabelle := I18nService.table(locale)
		for id: String in NEUE_CROPS:
			assert_true(tabelle.has("garten.spruch.%s" % id), "%s-Spruch (%s)" % [id, locale])
		assert_true(tabelle.has("garten.samen_kurz"), "samen_kurz (%s)" % locale)
		assert_true(tabelle.has("garten.samen_fehlt"), "samen_fehlt (%s)" % locale)
		assert_true(tabelle.has("city.laden.saatgut_titel"), "saatgut_titel (%s)" % locale)
