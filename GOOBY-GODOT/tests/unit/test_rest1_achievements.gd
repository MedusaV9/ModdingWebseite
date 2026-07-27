extends TestCase
## REST-1 Rang 3: Erfolgs-Katalog (44 aus der Web-Vorlage 1:1), Engine-
## Bedingungen (counter + special) und der AchievementsService am ECHTEN
## GameState — Freischaltung einmalig, Belohnung einmalig, DE/EN-Strings
## für jeden Erfolg vorhanden.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

const NOW_MS := 1_750_000_000_000
## Web data/achievements.js: 44 Erfolge, Münzsumme exakt 3410.
const WEB_COUNT := 44
const WEB_COINS_TOTAL := 3410

var _seq := 0


func _fresh_state() -> Dictionary:
	return SaveSchema.default_state(NOW_MS)


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://rest1_tests/ach_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	return gs


func test_katalog_hat_44_valide_erfolge() -> void:
	var catalog := AchievementsCatalog.all()
	assert_eq(catalog.size(), WEB_COUNT, "44 Erfolge wie im Web")
	assert_eq(AchievementsCatalog.total_coins(catalog), WEB_COINS_TOTAL, "Münzsumme 3410")
	var errors := AchievementsCatalog.validate(catalog)
	assert_true(errors.is_empty(), "Katalog valide: %s" % str(errors))
	var per_cat := 0
	for cat in AchievementsCatalog.CATEGORIES:
		per_cat += AchievementsCatalog.by_category(catalog, cat).size()
	assert_eq(per_cat, WEB_COUNT, "jede Kategorie-Sicht deckt den Katalog ab")
	assert_eq(
		str(AchievementsCatalog.by_id(catalog, "firstFeed").get("cat", "")),
		"pflege",
		"by_id findet firstFeed"
	)


func test_strings_de_en_fuer_jeden_erfolg() -> void:
	var catalog := AchievementsCatalog.all()
	for locale in ["de", "en"]:
		var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("res://strings/%s/achievements.json" % locale)
		)
		assert_true(parsed is Dictionary, "%s/achievements.json parst" % locale)
		var defs: Variant = (parsed as Dictionary).get("achievements", {}).get("defs", {})
		assert_true(defs is Dictionary, "%s: defs-Block da" % locale)
		for def: Dictionary in catalog:
			var id := str(def["id"])
			var entry: Variant = (defs as Dictionary).get(id)
			assert_true(entry is Dictionary, "%s: Eintrag für %s" % [locale, id])
			if entry is Dictionary:
				assert_false(str(entry.get("name", "")).is_empty(), "%s: %s.name" % [locale, id])
				assert_false(str(entry.get("desc", "")).is_empty(), "%s: %s.desc" % [locale, id])


func test_engine_counter_bedingungen() -> void:
	var catalog := AchievementsCatalog.all()
	var state := _fresh_state()
	var first_feed := AchievementsCatalog.by_id(catalog, "firstFeed")
	var feed100 := AchievementsCatalog.by_id(catalog, "feed100")
	assert_eq(AchievementsEngine.progress_of(first_feed, state)["current"], 0, "frisch: 0/1")
	assert_false(AchievementsEngine.is_satisfied(first_feed, state), "frisch nicht erfüllt")
	state["achievements"]["counters"]["feeds"] = 1
	assert_true(AchievementsEngine.is_satisfied(first_feed, state), "1 Fütterung reicht")
	assert_eq(AchievementsEngine.progress_of(feed100, state)["current"], 1, "feed100: 1/100")
	assert_false(AchievementsEngine.is_satisfied(feed100, state), "feed100 offen")
	state["achievements"]["counters"]["feeds"] = 250
	var p := AchievementsEngine.progress_of(feed100, state)
	assert_eq(p["current"], 100, "current klemmt auf target")
	assert_true(AchievementsEngine.is_satisfied(feed100, state), "feed100 erfüllt")


func test_engine_special_bedingungen() -> void:
	var catalog := AchievementsCatalog.all()
	var state := _fresh_state()
	var setze_reiseziele := func() -> void:
		for i in 9:
			state["vacation"]["visited"]["ziel%d" % i] = NOW_MS
	var cases: Array = [
		["coins1000", func() -> void: state["economy"]["coins"] = 1000],
		["level10", func() -> void: state["progression"]["level"] = 10],
		["streak7", func() -> void: state["daily"]["streak"] = 7],
		["chonkZone", func() -> void: state["gooby"]["weight"] = 86.0],
		["sleekMode", func() -> void: state["gooby"]["weight"] = 25.0],
		["parkDay", func() -> void: state["park"]["visits"] = 1],
		["coasterFan", func() -> void: state["park"]["rides"]["coaster"] = 5],
		["wheelRide", func() -> void: state["park"]["rides"]["wheel"] = 1],
		["funkelnacht", func() -> void: state["park"]["nightVisit"] = true],
		["weltenbummler", setze_reiseziele],
	]
	for case: Array in cases:
		var id := str(case[0])
		var def := AchievementsCatalog.by_id(catalog, id)
		assert_false(AchievementsEngine.is_satisfied(def, state), "%s: frisch offen" % id)
		(case[1] as Callable).call()
		assert_true(AchievementsEngine.is_satisfied(def, state), "%s: erfüllt" % id)
	# fullOutfit: Hut + Brille + Halsschmuck gleichzeitig.
	var outfit := AchievementsCatalog.by_id(catalog, "fullOutfit")
	assert_eq(AchievementsEngine.progress_of(outfit, state)["current"], 0, "Outfit: 0/3")
	state["cosmetics"]["outfits"]["equipped"] = {
		"hat": "tophat", "glasses": "round", "neck": "scarf", "back": null
	}
	assert_true(AchievementsEngine.is_satisfied(outfit, state), "volles Outfit erfüllt")
	# neverSick: Level 10 UND nie krank (sickEver-Latch bricht es).
	var never := AchievementsCatalog.by_id(catalog, "neverSick")
	assert_true(AchievementsEngine.is_satisfied(never, state), "Level 10, nie krank")
	state["achievements"]["counters"]["sickEver"] = 1
	assert_false(AchievementsEngine.is_satisfied(never, state), "einmal krank → verwirkt")


func test_engine_sticker_und_sammlung() -> void:
	var catalog := AchievementsCatalog.all()
	var state := _fresh_state()
	var first := AchievementsCatalog.by_id(catalog, "firstSticker")
	assert_false(AchievementsEngine.is_satisfied(first, state), "frisch: kein Sticker")
	state["stickers"]["unlocked"]["st1"] = NOW_MS
	assert_true(AchievementsEngine.is_satisfied(first, state), "1 Buch-Sticker reicht")
	var book10 := AchievementsCatalog.by_id(catalog, "stickerBook10")
	for i in 10:
		state["stickers"]["unlocked"]["st%d" % i] = NOW_MS
	assert_true(AchievementsEngine.is_satisfied(book10, state), "10 Sticker im Buch")
	var set_complete := AchievementsCatalog.by_id(catalog, "setComplete")
	assert_false(AchievementsEngine.is_satisfied(set_complete, state), "kein Set claimt")
	state["stickers"]["setRewards"] = {"tiere": NOW_MS}
	assert_true(AchievementsEngine.is_satisfied(set_complete, state), "Godot-Set-Belohnung zählt")


func test_service_schaltet_einmalig_frei_und_zahlt_einmal() -> void:
	var gs := _fresh_gs()
	tree.root.add_child(gs)
	var service := AchievementsService.new()
	tree.root.add_child(service)
	var unlocked_events: Array = []
	service.achievement_unlocked.connect(func(def: Dictionary) -> void: unlocked_events.append(def))
	service.attach(gs)
	await wait_frames(1)
	assert_true(unlocked_events.is_empty(), "frischer Save schaltet nichts frei")
	var coins_before := int(gs.get_value("economy.coins", 0))
	gs.update(func(state: Dictionary) -> void: state["achievements"]["counters"]["feeds"] = 1)
	RewardHub.note_action(gs)
	await wait_frames(1)
	assert_eq(unlocked_events.size(), 1, "genau eine Freischaltung")
	assert_eq(str(unlocked_events[0].get("id", "")), "firstFeed", "firstFeed feuert")
	assert_true(
		(
			gs.get_value("achievements.unlocked.firstFeed", 0) is int
			and int(gs.get_value("achievements.unlocked.firstFeed", 0)) > 0
		),
		"unlocked-Stempel gesetzt"
	)
	var coins_after := int(gs.get_value("economy.coins", 0))
	assert_eq(coins_after, coins_before + 10, "Belohnung +10 Münzen")
	# Zweite Auswertung: KEINE Doppel-Belohnung, kein zweites Event.
	RewardHub.note_action(gs)
	await wait_frames(1)
	assert_eq(unlocked_events.size(), 1, "keine Doppel-Feier")
	assert_eq(int(gs.get_value("economy.coins", 0)), coins_after, "keine Doppel-Belohnung")
	service.free()
	tree.root.remove_child(gs)
	gs.free()


func test_service_belohnung_kann_folgeerfolg_ausloesen() -> void:
	var gs := _fresh_gs()
	tree.root.add_child(gs)
	var service := AchievementsService.new()
	tree.root.add_child(service)
	service.attach(gs)
	await wait_frames(1)
	# 990 Münzen — die firstFeed-Belohnung (+10) hebt über die 1000er-Marke.
	gs.update(
		func(state: Dictionary) -> void:
			state["economy"]["coins"] = 990
			state["achievements"]["counters"]["feeds"] = 1
	)
	RewardHub.note_action(gs)
	await wait_frames(1)
	assert_true(
		AchievementsEngine.is_unlocked(gs.state(), "coins1000"),
		"coins1000 folgt aus der firstFeed-Belohnung (Nachfass-Auswertung)"
	)
	service.free()
	tree.root.remove_child(gs)
	gs.free()
