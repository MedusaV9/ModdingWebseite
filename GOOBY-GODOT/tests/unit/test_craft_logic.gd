extends TestCase
## M2 HAUS — Crafting-Regeln (Doc D §5.2/§5.3) als PURE Tests: Rezept-Katalog,
## Materialverbrauch (Alles-oder-nichts), Baupläne, Lagergrenze, Baumarkt-
## Datenvertrag. Kein GameState, kein Node.


func test_katalog_geladen_und_normalisiert() -> void:
	var rezepte := CraftRecipes.all()
	assert_true(rezepte.size() >= 5, "mind. 5 Start-Rezepte (sind: %d)" % rezepte.size())
	for id: String in CraftRecipes.ids():
		var recipe: Dictionary = rezepte[id]
		assert_eq(recipe["id"], id)
		assert_true(recipe["output"]["count"] >= 1, "%s: Ausgabemenge" % id)
		assert_false(
			FurnitureCatalog.def(str(recipe["output"]["item"])).is_empty(),
			"%s: Ausgabe-Möbel liegt im Katalog" % id
		)
		assert_true(recipe["materialien"].size() >= 1, "%s: braucht Material" % id)
		for material_id: String in recipe["materialien"]:
			assert_false(
				CraftMaterials.def(material_id).is_empty(),
				"%s: unbekanntes Material %s" % [id, material_id]
			)
		assert_eq(recipe["station"], CraftRecipes.STATION_WERKBANK)


func test_materialien_haben_quelle_und_preis() -> void:
	for material_id: String in CraftMaterials.ids():
		var row := CraftMaterials.def(material_id)
		assert_true(CraftMaterials.QUELLEN.has(str(row["quelle"])), "%s: Quelle" % material_id)
		if str(row["quelle"]) == "baumarkt":
			assert_true(row["preis"] > 0, "%s: Baumarkt-Material hat Preis" % material_id)
			assert_eq(
				CraftMaterials.baumarkt_preis("material", material_id),
				int(row["preis"]),
				"%s: Sortiment-Preis == Katalog-Preis" % material_id
			)
		else:
			assert_eq(int(row["preis"]), 0, "%s: Fund-Material kostet nichts" % material_id)


func test_baumarkt_sortiment_kennt_alle_bauplaene() -> void:
	var sortiment: Dictionary = {}
	for row: Dictionary in CraftMaterials.baumarkt_angebot():
		sortiment["%s/%s" % [row["art"], row["id"]]] = int(row["preis"])
	for blueprint_id: String in CraftRecipes.blueprint_ids():
		assert_true(
			sortiment.has("bauplan/%s" % blueprint_id),
			"Bauplan %s fehlt im Baumarkt-Sortiment" % blueprint_id
		)
	for kind: String in GardenWorld.KAUFBAR:
		assert_true(sortiment.has("struktur/%s" % kind), "Struktur %s fehlt im Sortiment" % kind)


func test_fehlmengen_und_pruefung() -> void:
	var recipe := CraftRecipes.recipe("r_hocker_rustikal")
	assert_eq(CraftLogic.missing_materials(recipe, {}), {"holz": 2, "naegel": 4})
	assert_eq(CraftLogic.missing_materials(recipe, {"holz": 1, "naegel": 9}), {"holz": 1})
	assert_eq(CraftLogic.missing_materials(recipe, {"holz": 5, "naegel": 9}), {})
	var ohne_werkstatt := CraftLogic.check(recipe, {"holz": 5, "naegel": 9}, [], false)
	assert_false(ohne_werkstatt["ok"])
	assert_eq(ohne_werkstatt["reason"], CraftLogic.REASON_STATION)
	var ok := CraftLogic.check(recipe, {"holz": 5, "naegel": 9}, [], true)
	assert_true(ok["ok"], "mit Werkstatt und Material geht es")
	assert_eq(ok["reason"], CraftLogic.REASON_OK)


func test_bauplan_pflicht() -> void:
	var recipe := CraftRecipes.recipe("r_gartentisch")
	assert_eq(str(recipe["bauplan"]), "bp_gartentisch")
	var inventar := {"holz": 9, "naegel": 20, "eisen": 3}
	var ohne := CraftLogic.check(recipe, inventar, [], true)
	assert_false(ohne["ok"])
	assert_eq(ohne["reason"], CraftLogic.REASON_BLUEPRINT)
	assert_true(CraftLogic.check(recipe, inventar, ["bp_gartentisch"], true)["ok"])


func test_lagergrenze_blockt() -> void:
	var recipe := CraftRecipes.recipe("r_zaun_holz")
	var inventar := {"stock": 4, "holz": 2, "naegel": 8}
	var eng := CraftLogic.check(recipe, inventar, [], true, 3, 1)
	assert_false(eng["ok"], "4 Zäune passen nicht in 3 freie Lagerpunkte")
	assert_eq(eng["reason"], CraftLogic.REASON_STORAGE)
	assert_true(CraftLogic.check(recipe, inventar, [], true, 4, 1)["ok"])


func test_verbrauch_ist_alles_oder_nichts() -> void:
	var recipe := CraftRecipes.recipe("r_hocker_rustikal")
	var inventar := {"holz": 1, "naegel": 4}
	assert_false(CraftLogic.consume(inventar, recipe), "zu wenig Holz")
	assert_eq(inventar, {"holz": 1, "naegel": 4}, "Inventar bleibt unangetastet")
	inventar = {"holz": 3, "naegel": 4, "blatt": 1}
	assert_true(CraftLogic.consume(inventar, recipe))
	assert_eq(inventar, {"holz": 1, "blatt": 1}, "leere Zeilen fliegen raus")


func test_add_und_take() -> void:
	var inventar: Dictionary = {}
	CraftLogic.add(inventar, "stock", 3)
	CraftLogic.add(inventar, "stock", 0)
	assert_eq(CraftLogic.count_of(inventar, "stock"), 3)
	assert_false(CraftLogic.take(inventar, "stock", 4), "mehr als da ist geht nicht")
	assert_true(CraftLogic.take(inventar, "stock", 3))
	assert_false(inventar.has("stock"), "leere Zeile entfernt")
	assert_eq(CraftLogic.count_of(inventar, "gibtsnicht"), 0)


func test_baumarkt_kosten_nur_fuer_kaufmaterial() -> void:
	var recipe := CraftRecipes.recipe("r_gartentisch")
	# 4 Holz (Fund) + 8 Nägel (15 ᴳ) + 1 Eisen (40 ᴳ) = 8*15 + 40.
	assert_eq(CraftLogic.baumarkt_kosten(recipe, {}), 8 * 15 + 40)
	assert_eq(CraftLogic.baumarkt_kosten(recipe, {"naegel": 8, "eisen": 1}), 0)
