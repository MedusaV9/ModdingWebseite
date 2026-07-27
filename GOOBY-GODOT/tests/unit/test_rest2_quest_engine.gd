extends TestCase
## REST-2 — DailyQuestEngine: deterministischer Tagesroll (Web-Parität von
## xmur3/mulberry32), `braucht`-Filter, Zähler-Fortschritt über Baselines,
## Claim/Doppel-Claim, Tageswechsel, Reroll und Abschluss-Bonus.

const DAY := "2026-07-27"
const DAY2 := "2026-07-28"


func _state() -> Dictionary:
	return {
		"achievements":
		{
			"counters":
			{
				"feeds": 0,
				"washes": 0,
				"tickles": 0,
				"teeth_brushed": 0,
				"petsToday": 0,
				"petsDay": "",
				"plantings": 0,
				"waterings": 0,
				"harvests": 0,
				"questsDone": 0,
			}
		},
		"minigames": {"plays": {}, "legacy": {"best": {}, "bestByDiff": {}, "endlessBest": {}}},
		"economy": {"coins": 100, "coinsEarned": 0, "coinsSpent": 0},
		"progression": {"level": 1, "xp": 0},
		"quests": {"completedTotal": 0},
	}


func _ctx(games: Array[String] = [], level := 1, garden := true) -> Dictionary:
	return {"level": level, "minigames": games, "garden": garden}


func _pool_simple() -> Array:
	return [
		{
			"id": "feed2",
			"kategorie": "care",
			"messung": {"typ": "counter", "key": "feeds"},
			"ziel": 2,
			"muenzen": 20,
			"xp": 10,
		},
		{
			"id": "wash1",
			"kategorie": "care",
			"messung": {"typ": "counter", "key": "washes"},
			"ziel": 1,
			"muenzen": 15,
			"xp": 8,
		},
		{
			"id": "spiel1",
			"kategorie": "games",
			"messung": {"typ": "spiele_gesamt"},
			"ziel": 1,
			"muenzen": 25,
			"xp": 12,
		},
		{
			"id": "garten1",
			"kategorie": "garden",
			"messung": {"typ": "counter", "key": "plantings"},
			"ziel": 1,
			"muenzen": 20,
			"xp": 10,
			"braucht": {"garden": true},
		},
		{
			"id": "punkte30",
			"kategorie": "games",
			"messung": {"typ": "spiel_punkte", "spiel": "carrotCatch"},
			"ziel": 30,
			"muenzen": 25,
			"xp": 12,
			"braucht": {"minigame": "carrotCatch"},
		},
	]


## Referenzwerte kommen 1:1 aus GOOBY/src/systems/quests.js (Node-Lauf) —
## derselbe Tag muss auf Web und Godot denselben Seed/Zufallsstrom liefern.
func test_hash32_und_rng_sind_web_paritaetisch() -> void:
	assert_eq(DailyQuestEngine.hash32("2026-07-27"), 1187339125, "hash32(2026-07-27)")
	assert_eq(DailyQuestEngine.hash32("2026-07-28"), 2735185966, "hash32(2026-07-28)")
	assert_eq(DailyQuestEngine.hash32("2026-07-27:r"), 3622789181, "hash32 Reroll-Seed")
	assert_eq(DailyQuestEngine.hash32("gooby"), 3364636767, "hash32(gooby)")
	var rng := {"a": 1187339125}
	assert_almost(DailyQuestEngine.rand_next(rng), 0.019612913951277733, 1e-12, "rng #1")
	assert_almost(DailyQuestEngine.rand_next(rng), 0.0072874457109719515, 1e-12, "rng #2")
	assert_almost(DailyQuestEngine.rand_next(rng), 0.8411460048519075, 1e-12, "rng #3")


func test_roll_ist_deterministisch_und_kategorievielfaeltig() -> void:
	var pool := DailyQuestCatalog.builtin_pool()
	assert_true(pool.size() >= 20, "eingebauter Pool ist gefüllt")
	var games: Array[String] = ["carrotCatch", "bunnyHop", "runner", "teaParty"]
	var slice_a := {"completedTotal": 0}
	var slice_b := {"completedTotal": 0}
	assert_true(DailyQuestEngine.roll_today(slice_a, DAY, pool, _ctx(games), _state()))
	assert_true(DailyQuestEngine.roll_today(slice_b, DAY, pool, _ctx(games), _state()))
	assert_eq(slice_a["day"], DAY, "Tag steht im Slice")
	assert_eq((slice_a["active"] as Array).size(), 3, "3 Quests pro Tag")
	var ids_a := _ids(slice_a)
	assert_eq(ids_a, _ids(slice_b), "gleicher Tag == gleiches Brett (alle Spieler)")
	var by_id := DailyQuestEngine.pool_by_id(pool)
	var cats := {}
	for id: String in ids_a:
		cats[str((by_id[id] as Dictionary).get("kategorie", ""))] = true
	assert_true(cats.size() >= 2, "mindestens 2 Kategorien auf dem Brett: %s" % [ids_a])
	# No-op beim zweiten Roll desselben Tags.
	assert_false(DailyQuestEngine.roll_today(slice_a, DAY, pool, _ctx(games), _state()))
	# Anderer Tag == (in der Regel) anderes Brett + roll_needed.
	assert_true(DailyQuestEngine.roll_needed(slice_a, DAY2), "neuer Tag braucht neuen Roll")
	var slice_c := {"completedTotal": 0}
	DailyQuestEngine.roll_today(slice_c, DAY2, pool, _ctx(games), _state())
	assert_eq(str(slice_c["day"]), DAY2, "Tageswechsel rollt neu")


func test_braucht_filter_gegen_den_fortschritt() -> void:
	var no_games: Array[String] = []
	var eligible := DailyQuestEngine.eligible_defs(_pool_simple(), _ctx(no_games, 1, false))
	var ids: Array[String] = []
	for def in eligible:
		ids.append(str(def["id"]))
	assert_false(ids.has("punkte30"), "gesperrtes Minispiel fliegt raus")
	assert_false(ids.has("garten1"), "ohne Garten keine Garten-Quest")
	assert_true(ids.has("feed2") and ids.has("wash1"), "Pflege bleibt drin")
	var level_pool := [{"id": "spät", "kategorie": "care", "braucht": {"level": 5}}]
	assert_true(DailyQuestEngine.eligible_defs(level_pool, _ctx(no_games, 4)).is_empty())
	assert_eq(DailyQuestEngine.eligible_defs(level_pool, _ctx(no_games, 5)).size(), 1)


func test_zaehler_fortschritt_claim_und_doppel_claim() -> void:
	var state := _state()
	state["achievements"]["counters"]["feeds"] = 5
	var def: Dictionary = _pool_simple()[0]
	var entry := DailyQuestEngine.make_entry(def, state)
	var slice := {"completedTotal": 0, "day": DAY, "active": [entry], "bonusDay": ""}
	assert_eq(DailyQuestEngine.progress_of(entry, def, state), 0, "Baseline eingefroren")
	state["achievements"]["counters"]["feeds"] = 6
	assert_eq(DailyQuestEngine.progress_of(entry, def, state), 1, "Delta seit Roll")
	assert_false(DailyQuestEngine.claim(slice, "feed2", def, state)["ok"], "unfertig != claimbar")
	state["achievements"]["counters"]["feeds"] = 9
	assert_eq(DailyQuestEngine.progress_of(entry, def, state), 2, "auf Ziel gedeckelt")
	var res := DailyQuestEngine.claim(slice, "feed2", def, state)
	assert_true(res["ok"], "fertig -> claimbar")
	assert_eq(res["muenzen"], 20, "Münz-Belohnung aus dem Def")
	assert_eq(res["xp"], 10, "XP-Belohnung aus dem Def")
	assert_eq(int(slice["completedTotal"]), 1, "completedTotal zählt")
	assert_false(DailyQuestEngine.claim(slice, "feed2", def, state)["ok"], "kein Doppel-Claim")


func test_punkte_quest_zaehlt_erst_nach_heutiger_runde() -> void:
	var state := _state()
	state["minigames"]["legacy"]["best"]["carrotCatch"] = 100
	state["minigames"]["plays"]["carrotCatch"] = 5
	var def: Dictionary = _pool_simple()[4]
	var entry := DailyQuestEngine.make_entry(def, state)
	assert_eq(
		DailyQuestEngine.progress_of(entry, def, state),
		0,
		"alter Bestwert allein zählt NICHT (Veteranen-Schutz)"
	)
	state["minigames"]["plays"]["carrotCatch"] = 6
	assert_eq(
		DailyQuestEngine.progress_of(entry, def, state),
		30,
		"nach frischer Runde gilt der Bestwert (auf Ziel gedeckelt)"
	)
	assert_true(DailyQuestEngine.is_complete(entry, def, state))


func test_streicheln_heute_nutzt_tagesgebundenen_zaehler() -> void:
	var state := _state()
	var def := {
		"id": "pet2",
		"kategorie": "care",
		"messung": {"typ": "streicheln_heute"},
		"ziel": 2,
		"muenzen": 10,
		"xp": 5,
	}
	var entry := DailyQuestEngine.make_entry(def, state)
	assert_eq(DailyQuestEngine.progress_of(entry, def, state), 0)
	state["achievements"]["counters"]["petsToday"] = 2
	assert_eq(DailyQuestEngine.progress_of(entry, def, state), 2, "petsToday zählt direkt")


func test_reroll_ersetzt_nur_unangefasste_und_nur_einmal() -> void:
	var pool := _pool_simple()
	var state := _state()
	var no_games: Array[String] = []
	var slice := {"completedTotal": 0}
	DailyQuestEngine.roll_today(slice, DAY, pool, _ctx(no_games), state)
	var before := _ids(slice)
	# Erste Quest anfassen (Fortschritt auf dem Zähler ihrer Messung).
	var by_id := DailyQuestEngine.pool_by_id(pool)
	var touched_id := before[0]
	var messung: Dictionary = (by_id[touched_id] as Dictionary).get("messung", {})
	if str(messung.get("typ", "")) == "counter":
		state["achievements"]["counters"][str(messung["key"])] += 1
	else:
		state["minigames"]["plays"]["teaParty"] = 1
	assert_true(DailyQuestEngine.reroll_today(slice, DAY, pool, _ctx(no_games), state))
	var after := _ids(slice)
	assert_true(after.has(touched_id), "angefangene Quest bleibt liegen")
	assert_eq(after.size(), 3, "Brett bleibt voll")
	assert_eq(str(slice["rerolledDay"]), DAY, "Reroll-Tag gebucht")
	assert_false(
		DailyQuestEngine.reroll_today(slice, DAY, pool, _ctx(no_games), state), "nur 1x pro Tag"
	)


func test_bonus_faellt_einmalig_wenn_alle_drei_geclaimt() -> void:
	var slice := {
		"completedTotal": 3,
		"day": DAY,
		"bonusDay": "",
		"active":
		[
			{"id": "a", "claimed": true, "base": {}},
			{"id": "b", "claimed": true, "base": {}},
			{"id": "c", "claimed": true, "base": {}},
		],
	}
	assert_true(DailyQuestEngine.all_claimed(slice))
	assert_true(DailyQuestEngine.bonus_due(slice, DAY), "Bonus fällig")
	DailyQuestEngine.mark_bonus_paid(slice, DAY)
	assert_false(DailyQuestEngine.bonus_due(slice, DAY), "Bonus nur einmal")
	(slice["active"] as Array)[2]["claimed"] = false
	assert_false(DailyQuestEngine.all_claimed(slice))


func test_pool_integritaet_und_registry_sync() -> void:
	var pool := DailyQuestCatalog.builtin_pool()
	var known_typen := [
		"counter",
		"streicheln_heute",
		"spiele_gesamt",
		"spiele_verschieden",
		"spiel_runden",
		"spiel_punkte",
		"muenzen_verdient",
		"muenzen_ausgegeben",
	]
	var known_cats := ["care", "games", "garden", "economy"]
	var game_ids := {}
	for meta in MinigameRegistry.all_games():
		game_ids[str(meta["id"])] = true
	var seen := {}
	for def: Variant in pool:
		assert_true(def is Dictionary, "Def ist ein Dict")
		var id := str((def as Dictionary).get("id", ""))
		assert_false(id.is_empty(), "jede Quest hat eine id")
		assert_false(seen.has(id), "id '%s' ist eindeutig" % id)
		seen[id] = true
		assert_true(known_cats.has(str(def.get("kategorie", ""))), "%s: Kategorie" % id)
		var messung: Dictionary = def.get("messung", {})
		assert_true(known_typen.has(str(messung.get("typ", ""))), "%s: Messungstyp" % id)
		assert_true(int(def.get("ziel", 0)) >= 1, "%s: Ziel >= 1" % id)
		assert_true(int(def.get("muenzen", 0)) > 0, "%s: Münzen > 0" % id)
		assert_true(int(def.get("xp", 0)) > 0, "%s: XP > 0" % id)
		if str(messung.get("typ", "")) in ["spiel_punkte", "spiel_runden"]:
			var spiel := str(messung.get("spiel", ""))
			assert_true(
				game_ids.has(spiel), "%s: Spiel '%s' existiert in der Registry" % [id, spiel]
			)
			assert_eq(
				str((def.get("braucht", {}) as Dictionary).get("minigame", "")),
				spiel,
				"%s: braucht.minigame gated das eigene Spiel" % id
			)


func _ids(slice: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for entry: Variant in slice.get("active", []):
		out.append(str((entry as Dictionary).get("id", "")))
	return out
