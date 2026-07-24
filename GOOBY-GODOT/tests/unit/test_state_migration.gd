extends TestCase
## W1d — Migration v0-v4 → v5 gegen die ECHTEN Web-Fixtures
## (tests/fixtures/v4_*.json / v2_legacy*.json, erzeugt vom Web-Code selbst).
## Feld-fuer-Feld-Asserts: Coins, Level, Sticker-Set, Outfits, Counters,
## Garten, laufender Urlaub (Restzeit!), Grandfathering, Verlustliste.

const SaveSchema := preload("res://scripts/state/save_schema.gd")
const MigrationV4 := preload("res://scripts/state/migration_v4.gd")
const Util := preload("res://tests/fixtures/state_test_util.gd")

## Gepinnte Uhr der Fixture-Generierung (2026-01-15T12:00:00Z).
const NOW_MS := 1768478400000


## Numerisch tolerantes Deep-Equal (JSON floats vs GDScript ints — JS-Semantik).
func assert_deep_eq(got: Variant, want: Variant, message := "") -> void:
	var diff := Util.first_diff(got, want)
	assert_true(diff.is_empty(), "%s — erster Diff: %s" % [message, diff])


func _load_fixture(file_name: String) -> Dictionary:
	var json := JSON.new()
	var err := json.parse(FileAccess.get_file_as_string("res://tests/fixtures/" + file_name))
	assert_eq(err, OK, file_name + " muss parsen")
	return json.data


func _migrate(file_name: String) -> Dictionary:
	var res := MigrationV4.migrate_any(_load_fixture(file_name), NOW_MS)
	assert_true(res["ok"], file_name + " migriert: " + res["error"])
	return res


func test_fresh_fixture_migrates() -> void:
	var res := _migrate("v4_fresh.json")
	var s: Dictionary = res["state"]
	assert_eq(s["v"], 5)
	assert_eq(s["meta"]["importedFrom"], "web-v4")
	assert_eq(s["economy"]["coins"], 350, "100 + 250 Umzugsbonus")
	assert_eq(s["progression"]["level"], 1)
	assert_eq(s["progression"]["xp"], 0)
	assert_deep_eq(s["inventory"]["food"], {"carrot": 3, "apple": 1, "cupcake": 1}, "Starter-Food")
	assert_true(s["radio"]["owned"], "Web-v4 verschenkte das Radio → Grandfathering")
	assert_false(s["camera"]["owned"], "nie fotografiert → keine Kamera")
	assert_true(s["home"]["movingDay"], "Umzugstag-Marker gesetzt")
	assert_eq(s["home"]["storage"], [{"item": "radio", "variant": "default", "count": 1}])
	assert_eq(s["vacation"]["phase"], "none")
	assert_eq(res["report"]["furnitureBoxed"], 1)


func test_midgame_fixture_migrates_losslessly() -> void:
	var v4 := _load_fixture("v4_midgame.json")
	var res := _migrate("v4_midgame.json")
	var s: Dictionary = res["state"]
	# Coins: 4210 + 250 Umzugsbonus + 180 Beach-Erstattung (laufende Reise!).
	assert_eq(s["economy"]["coins"], 4210 + 250 + 180)
	assert_eq(s["economy"]["coinsEarned"], v4["profile"]["coinsEarned"])
	assert_eq(s["economy"]["coinsSpent"], v4["profile"]["coinsSpent"])
	assert_eq(s["progression"]["level"], 12, "Level 1:1")
	assert_eq(s["progression"]["xp"], 0, "XP-Rest verschenkt (M2-Kurve)")
	assert_deep_eq(s["gooby"]["stats"], v4["stats"], "Stats verbatim")
	assert_eq(s["gooby"]["lastTickAt"], v4["lastTickAt"])
	assert_eq(s["gooby"]["weight"], v4["weight"]["value"])
	assert_eq(s["gooby"]["health"]["state"], v4["health"]["state"])
	# Sticker-SET identisch (85er-ID-Raum bleibt).
	var got_ids: Array = s["stickers"]["unlocked"].keys()
	var want_ids: Array = v4["stickers"]["unlocked"].keys()
	got_ids.sort()
	want_ids.sort()
	assert_eq(got_ids, want_ids, "Sticker-Set gleich (%d IDs)" % want_ids.size())
	assert_eq(s["stickers"]["unlocked"].size(), 20)
	# Outfits/Skins 1:1.
	assert_deep_eq(s["cosmetics"]["outfits"]["owned"], v4["outfits"]["owned"], "Outfits owned")
	assert_eq(s["cosmetics"]["outfits"]["equipped"]["hat"], "partyHat")
	assert_deep_eq(
		s["cosmetics"]["fur"], {"owned": ["cream", "caramel"], "equipped": "caramel"}, "Fur/Skins"
	)
	# Achievements verbatim (Superset-kompatible Counters).
	assert_deep_eq(
		s["achievements"]["unlocked"], v4["achievements"]["unlocked"], "Achievements verbatim"
	)
	for k: String in v4["achievements"]["counters"].keys():
		assert_eq(
			s["achievements"]["counters"][k], v4["achievements"]["counters"][k], "counter " + k
		)
	# Garten: Plots 1-6 → erste 6 Grid-Felder, plotsOwned bleibt.
	assert_eq(s["garden"]["plotsOwned"], 5)
	assert_eq(s["garden"]["grid"][0]["crop"], "carrot")
	assert_eq(s["garden"]["grid"][1]["crop"], "pumpkin")
	assert_eq(s["garden"]["grid"][2]["crop"], null)
	# Laufender Urlaub: phase → none, Preis erstattet, Restzeit dokumentiert.
	assert_eq(s["vacation"]["phase"], "none")
	assert_eq(s["vacation"]["destId"], "")
	assert_eq(s["vacation"]["postcards"], 1, "Postkarten verbatim")
	assert_eq(s["vacation"]["archive"].size(), 1, "Postkarten-Archiv verbatim")
	var interrupted: Dictionary = s["migration"]["interruptedVacation"]
	assert_eq(interrupted["destId"], "beach")
	assert_eq(interrupted["phase"], "away")
	assert_eq(interrupted["remainingMs"], 172800000, "Urlaubs-Restzeit korrekt (2 Tage)")
	assert_eq(interrupted["refund"], 180)
	# Minigames: Bestwerte als Web-Rekorde, plays bleiben.
	assert_deep_eq(s["minigames"]["legacy"]["best"], v4["minigames"]["best"], "Minigame-Best")
	assert_deep_eq(s["minigames"]["plays"], v4["minigames"]["plays"], "Minigame-Plays")
	# Sonstiges verbatim.
	assert_deep_eq(s["daily"], v4["daily"], "daily verbatim")
	assert_eq(s["quests"]["completedTotal"], v4["quests"]["completedTotal"])
	assert_deep_eq(s["park"], v4["themePark"], "themePark → park verbatim")
	assert_eq(s["settings"]["imported"]["uiScale"], 115)
	assert_eq(s["settings"]["imported"]["sfxMuted"], true, "sfx:false → Bus-Mute")
	assert_eq(s["settings"]["imported"]["musicMuted"], false)
	assert_eq(s["settings"]["imported"]["devUnlocked"], true)
	assert_true(s["onboarding"]["done"])
	assert_false(s["onboarding"]["whatsNew5Seen"], "5.0-Panel faellig")
	assert_true(s["home"]["movingDay"])
	assert_eq(s["home"]["storage"].size(), 9, "9 owned-Moebel im Umzugskarton")
	assert_false(s["migration"]["lost"].is_empty(), "Verlustliste im Save vermerkt")
	assert_eq(res["report"]["level"], 12)
	assert_eq(res["report"]["stickers"], 20)


func test_maxed_fixture_migrates() -> void:
	var res := _migrate("v4_maxed.json")
	var s: Dictionary = res["state"]
	assert_eq(s["progression"]["level"], 40, "Max-Level bleibt 40")
	assert_eq(s["economy"]["coins"], 99999 + 250)
	assert_eq(s["stickers"]["unlocked"].size(), 85, "alle 85 Sticker bleiben")
	assert_eq(s["cosmetics"]["outfits"]["owned"].size(), 42, "alle 42 Outfits bleiben")
	assert_eq(s["gallery"]["legacyCount"], 40, "Foto-Zaehler bleibt (Erfolge)")
	assert_true(s["camera"]["owned"], "je fotografiert → POW!-Kamera geschenkt")
	assert_eq(s["park"]["visits"], 30)
	assert_true(s["park"]["nightVisit"])


func test_v2_legacy_chain_matches_web_chain() -> void:
	# Beweis der Ketten-Parity: v2 → (GDScript-Kette v2→v3→v4) → v5 muss
	# EXAKT dasselbe v5 ergeben wie das vom WEB-CODE vormigrierte v4-Fixture.
	var from_v2 := _migrate("v2_legacy.json")
	var from_v4 := _migrate("v2_legacy.expected_v4.json")
	assert_deep_eq(from_v2["state"], from_v4["state"], "v2-Kette == Web-Kette (deep-equal)")


func test_junk_inputs_are_rejected() -> void:
	assert_false(MigrationV4.migrate_any("kein dict", NOW_MS)["ok"])
	assert_false(MigrationV4.migrate_any({"v": 99}, NOW_MS)["ok"], "keine Web-Version")
	assert_false(MigrationV4.migrate_any({"v": 1.5}, NOW_MS)["ok"], "absurde Version")
	assert_false(
		MigrationV4.migrate_any({"v": 2, "stats": "nope"}, NOW_MS)["ok"],
		"Struktur-Korruption faellt durch validate (web F2)"
	)


func test_v0_save_runs_whole_chain() -> void:
	# Prae-versionierter Mini-Save (v fehlt) → v0-Kette → v5 mit Defaults.
	var res := MigrationV4.migrate_any({"coins": 42, "level": 3}, NOW_MS)
	assert_true(res["ok"], res["error"])
	assert_eq(res["state"]["economy"]["coins"], 42 + 250)
	assert_eq(res["state"]["progression"]["level"], 3)
	assert_true(res["state"]["radio"]["owned"], "v3→v4-Radio-Grant greift auch hier")
