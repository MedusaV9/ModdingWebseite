extends TestCase
## EF-1 (EVAL-1 D1+D3) — Füttern: der FoodCatalog deckt ALLE erreichbaren
## Nahrungs-Ids ab (Starter-Kühlschrank, REHWEI-Sortiment, Garten-Ernten,
## Werte 1:1), und die PURE Fütter-Wirkung apply_feed macht Vorrat −1,
## Stats +Deltas, Junk-Gewicht, feeds-Counter — mit Satt-/Leer-Gates.

const SaveSchema := preload("res://scripts/state/save_schema.gd")


func _state(food: Dictionary, hunger := 40.0) -> Dictionary:
	return {
		"inventory": {"food": food},
		"gooby":
		{
			"stats": {"hunger": hunger, "fun": 50.0, "energy": 50.0, "hygiene": 50.0},
			"weight": 50.0,
			"health": {"junkScore": 0},
		},
		"achievements": {"counters": {}},
	}


func test_katalog_deckt_starter_rehwei_und_garten() -> void:
	for id: String in SaveSchema.STARTER_FOOD:
		assert_true(FoodCatalog.FOODS.has(id), "Starter-Essen fehlt im Katalog: %s" % id)
	var rehwei: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://scripts/city/data/rehwei_sortiment.json")
	)
	assert_true((rehwei.get("waren") is Array) and not rehwei["waren"].is_empty(), "Sortiment lädt")
	for eintrag: Dictionary in rehwei["waren"]:
		var id := str(eintrag["id"])
		assert_true(FoodCatalog.FOODS.has(id), "REHWEI-Essen fehlt im Katalog: %s" % id)
		assert_eq(
			int(FoodCatalog.deltas(id)["hunger"]),
			int(eintrag["hunger"]),
			"Hunger-Wert weicht vom REHWEI-Sortiment ab: %s" % id
		)
		assert_eq(
			FoodCatalog.is_junk(id),
			bool(eintrag.get("junk", false)),
			"Junk-Flag weicht vom REHWEI-Sortiment ab: %s" % id
		)
	var crops: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://scripts/home/data/garden_crops.json")
	)
	for crop: Dictionary in crops["crops"]:
		var food_id := str(crop["food"])
		assert_true(FoodCatalog.FOODS.has(food_id), "Garten-Ernte fehlt im Katalog: %s" % food_id)


func test_jedes_essen_hat_de_und_en_namen() -> void:
	var de: Dictionary = I18nService.table("de")
	var en: Dictionary = I18nService.table("en")
	for id: String in FoodCatalog.FOODS:
		var key := "rewards.food." + id
		assert_true(de.has(key), "DE-Name fehlt: %s" % key)
		assert_true(en.has(key), "EN-Name fehlt: %s" % key)


func test_apply_feed_wirkt_auf_stats_vorrat_und_counter() -> void:
	var state := _state({"carrot": 2})
	var result := FoodCatalog.apply_feed(state, "carrot")
	assert_eq(str(result.get("id", "")), "carrot")
	assert_eq(int(state["inventory"]["food"]["carrot"]), 1, "Vorrat −1")
	assert_almost(float(state["gooby"]["stats"]["hunger"]), 50.0, 1e-6, "Hunger +10")
	assert_almost(float(state["gooby"]["stats"]["fun"]), 52.0, 1e-6, "Spaß +2")
	assert_eq(int(state["achievements"]["counters"]["feeds"]), 1, "feeds-Counter zählt")
	assert_almost(float(result["hunger_gain"]), 10.0, 1e-6, "Anzeigewert fürs Float")
	assert_true(bool(result["favorit"]), "Möhre ist Goobys Liebling")
	assert_false(bool(result["junk"]))
	# Letzte Portion räumt den Eintrag komplett aus dem Vorrat.
	FoodCatalog.apply_feed(state, "carrot")
	assert_false(state["inventory"]["food"].has("carrot"), "leerer Eintrag verschwindet")
	assert_eq(int(state["achievements"]["counters"]["feeds"]), 2)


func test_junk_speist_gewicht_und_junkscore() -> void:
	var state := _state({"pizza": 1})
	var result := FoodCatalog.apply_feed(state, "pizza")
	assert_true(bool(result["junk"]))
	assert_almost(float(state["gooby"]["weight"]), 52.0, 1e-6, "Junk: Gewicht +2")
	assert_eq(int(state["gooby"]["health"]["junkScore"]), 1, "Junk: junkScore +1")
	assert_almost(float(state["gooby"]["stats"]["hygiene"]), 48.0, 1e-6, "Pizza: Hygiene −2")


func test_gates_satt_leer_und_unbekannt() -> void:
	# Zu satt: nichts wird gefüttert, nichts verändert.
	var satt := _state({"apple": 1}, 99.9)
	assert_true(FoodCatalog.too_full(satt), "99,9 Hunger = pappsatt")
	assert_eq(FoodCatalog.apply_feed(satt, "apple"), {}, "satt = höfliche Ablehnung")
	assert_eq(int(satt["inventory"]["food"]["apple"]), 1, "Vorrat unangetastet")
	# Kein Vorrat: {}.
	var leer := _state({})
	assert_eq(FoodCatalog.apply_feed(leer, "apple"), {}, "ohne Vorrat kein Füttern")
	# Unbekannte Id im Vorrat (feindlicher Save): Fallback-Snack, kein Crash.
	var fremd := _state({"mystery_snack": 1})
	var result := FoodCatalog.apply_feed(fremd, "mystery_snack")
	assert_almost(float(result["hunger_gain"]), 10.0, 1e-6, "Fallback-Snack nährt")
	assert_eq(int(fremd["achievements"]["counters"]["feeds"]), 1)


func test_inventory_entries_sortiert_stabil() -> void:
	var state := _state({"apple": 1, "carrot": 3, "cupcake": 3, "kaputt": 0})
	var entries := FoodCatalog.inventory_entries(state)
	assert_eq(entries.size(), 3, "0-Bestände fliegen raus")
	assert_eq(str(entries[0]["id"]), "carrot", "meiste zuerst, dann alphabetisch")
	assert_eq(str(entries[1]["id"]), "cupcake")
	assert_eq(str(entries[2]["id"]), "apple")
