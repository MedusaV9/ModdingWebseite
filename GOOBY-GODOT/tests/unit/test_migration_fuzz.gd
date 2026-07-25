extends TestCase
## W4-P5 (INFRA) — Save-Migrations-Härtetest (Plan §2.4-18): 20+ gezielte
## Mutationen der echten v4-/v2-Fixtures (kaputt / halb / vertauscht) durch
## die KOMPLETTE Kette. Vertrag, der hier bewiesen wird:
##  1. MigrationV4.migrate_any crasht NIE und liefert IMMER den vollen
##     Antwort-Vertrag {ok, state, error, report} — ok=false trägt einen
##     benannten Fehler, ok=true einen normalize-sauberen v5-State.
##  2. save_manager.load_state mit derselben kaputten Datei bootet IMMER
##     (Recovery: Default-State, recovered=true — nie ein toter Save).
##  3. moving_box_import.import_text härtet auch String-Ebene ab
##     (halbe JSONs, Leerzeichen, Müll-Codes) — nie Crash, immer Report-Key.

const SaveSchema := preload("res://scripts/state/save_schema.gd")
const MigrationV4 := preload("res://scripts/state/migration_v4.gd")
const SaveManager := preload("res://scripts/state/save_manager.gd")
const MovingBox := preload("res://scripts/state/moving_box_import.gd")

const NOW_MS := 1768478400000

var _seq := 0


func _load_fixture(file_name: String) -> Dictionary:
	var json := JSON.new()
	var err := json.parse(FileAccess.get_file_as_string("res://tests/fixtures/" + file_name))
	assert_eq(err, OK, file_name + " muss parsen")
	return json.data


## Alle Dict-Mutationen: {name, base_fixture, mutate: Callable(Dictionary)}.
## mutate mutiert die tiefe Kopie in place.
func _dict_mutations() -> Array[Dictionary]:
	var muts: Array[Dictionary] = []
	var add := func(mut_name: String, fixture: String, mutate: Callable) -> void:
		muts.append({"name": mut_name, "fixture": fixture, "mutate": mutate})
	# — kaputte Versionsfelder —
	add.call(
		"v_fehlt (wird als v0 behandelt)",
		"v4_midgame.json",
		func(s: Dictionary) -> void: s.erase("v")
	)
	add.call("v_negativ", "v4_midgame.json", func(s: Dictionary) -> void: s["v"] = -1)
	add.call("v_string", "v4_midgame.json", func(s: Dictionary) -> void: s["v"] = "vier")
	add.call("v_nachkomma", "v4_midgame.json", func(s: Dictionary) -> void: s["v"] = 2.5)
	add.call("v_zukunft_99", "v4_midgame.json", func(s: Dictionary) -> void: s["v"] = 99)
	# — Stats: Typ-Tausch + hostile Zahlen —
	add.call("stats_ist_array", "v4_midgame.json", func(s: Dictionary) -> void: s["stats"] = [1, 2])
	add.call(
		"stats_ist_string", "v4_fresh.json", func(s: Dictionary) -> void: s["stats"] = "kaputt"
	)
	add.call(
		"stats_riesig_und_negativ",
		"v4_midgame.json",
		func(s: Dictionary) -> void:
			s["stats"]["hunger"] = 1.0e308
			s["stats"]["energy"] = -999999
	)
	add.call(
		"stats_werte_sind_strings",
		"v4_midgame.json",
		func(s: Dictionary) -> void:
			s["stats"] = {"hunger": "NaN", "energy": "viel", "hygiene": null, "fun": []}
	)
	# — Ökonomie/Progression —
	add.call("coins_negativ", "v4_midgame.json", func(s: Dictionary) -> void: s["coins"] = -500)
	add.call("coins_string", "v4_midgame.json", func(s: Dictionary) -> void: s["coins"] = "reich")
	add.call("level_999", "v4_midgame.json", func(s: Dictionary) -> void: s["level"] = 999)
	add.call("level_negativ", "v4_midgame.json", func(s: Dictionary) -> void: s["level"] = -3)
	add.call(
		"xp_und_level_vertauscht",
		"v4_midgame.json",
		func(s: Dictionary) -> void:
			var tmp: Variant = s["xp"]
			s["xp"] = s["level"]
			s["level"] = tmp
	)
	# — Schlaf/Gesundheit —
	add.call(
		"sleep_junk_timestamps",
		"v4_midgame.json",
		func(s: Dictionary) -> void:
			s["sleep"] = {"sleeping": "ja", "startedAt": "gestern", "wakeAt": []}
	)
	add.call(
		"health_unbekannter_zustand",
		"v4_midgame.json",
		func(s: Dictionary) -> void:
			s["health"]["state"] = "zombifiziert"
			s["weight"] = {"value": -80}
	)
	# — Möbel/Home —
	add.call(
		"furniture_owned_junk_eintraege",
		"v4_midgame.json",
		func(s: Dictionary) -> void:
			s["furniture"]["owned"] = ["radio", 42, null, {"was": "das"}, "couch", "couch"]
	)
	add.call(
		"furniture_ist_string",
		"v4_midgame.json",
		func(s: Dictionary) -> void: s["furniture"] = "weg"
	)
	# — Urlaub —
	add.call(
		"vacation_unbekanntes_ziel",
		"v4_midgame.json",
		func(s: Dictionary) -> void: s["vacation"]["destId"] = "atlantis"
	)
	add.call(
		"vacation_junk_timestamps",
		"v4_midgame.json",
		func(s: Dictionary) -> void:
			s["vacation"] = {
				"phase": "away", "destId": "beach", "returnAt": "morgen", "bookedAt": []
			}
	)
	# — Garten/Achievements/Settings —
	add.call(
		"garden_plots_ist_string",
		"v4_midgame.json",
		func(s: Dictionary) -> void: s["garden"]["plots"] = "beet"
	)
	add.call(
		"achievements_ist_array",
		"v4_midgame.json",
		func(s: Dictionary) -> void: s["achievements"] = []
	)
	add.call(
		"settings_uiScale_700",
		"v4_midgame.json",
		func(s: Dictionary) -> void:
			s["settings"]["uiScale"] = 700
			s["settings"]["volumes"] = {"master": 9000, "sfx": -5}
	)
	add.call(
		"codes_lockUntil_fernzukunft",
		"v4_midgame.json",
		func(s: Dictionary) -> void: s["codes"]["lockUntil"] = 9.9e15
	)
	add.call(
		"onboarding_ist_zahl", "v4_midgame.json", func(s: Dictionary) -> void: s["onboarding"] = 42
	)
	add.call(
		"radio_trims_junk",
		"v4_midgame.json",
		func(s: Dictionary) -> void:
			s["radio"]["trims"] = {"a": {"vol": "laut"}, "b": "kaputt", "c": {"vol": 1.0e9}}
	)
	# — E2-P0: bool-vs-String-Crash-Klasse (headless BEWIESENE Payloads:
	#   `"no" == false` war ein GDScript-Laufzeitfehler → {} statt Vertrag) —
	add.call(
		"e2_trims_on_ist_string",
		"v4_midgame.json",
		func(s: Dictionary) -> void: s["radio"]["trims"] = {"a": {"vol": 100, "on": "no"}}
	)
	add.call(
		"e2_quick_delivery_ist_string",
		"v4_midgame.json",
		func(s: Dictionary) -> void: s["quickDelivery"] = "ja"
	)
	add.call(
		"e2_sleeping_string_mit_zahlen_stamps",
		"v4_midgame.json",
		func(s: Dictionary) -> void:
			s["sleep"] = {"sleeping": "ja", "startedAt": 1000, "wakeAt": 2000}
	)
	add.call(
		"e2_bool_strings_ueberall",
		"v4_midgame.json",
		func(s: Dictionary) -> void:
			s["settings"]["gyro"] = "ja"
			s["settings"]["devUnlocked"] = "ja"
			s["settings"]["sfx"] = "nein"
			s["settings"]["music"] = "ja"
			s["onboarding"]["done"] = "ja"
			s["radio"]["playing"] = "ja"
			s["radio"]["station"] = 42
	)
	add.call(
		"e2_vacation_visited_strings",
		"v4_midgame.json",
		func(s: Dictionary) -> void: s["vacation"]["visited"] = {"beach": "ja", "space": true}
	)
	add.call(
		"e2_park_cheater_und_bool_string",
		"v4_midgame.json",
		func(s: Dictionary) -> void:
			s["themePark"] = {
				"visits": 1.0e15,
				"nightVisit": "ja",
				"rides": {"coaster": -5, "ufo": 9},
				"handsUp": 1.0e15,
				"candyBought": "12",
			}
	)
	add.call(
		"e2_additive_slices_junk",
		"v4_midgame.json",
		func(s: Dictionary) -> void:
			s["cutscenes"] = {"seen": {"vacDeparture": "ja"}}
			s["care"] = {"toiletAt": "gestern", "sickNotifyAt": true}
			s["minigames"]["difficulty"] = "schwer"
	)
	add.call(
		"stickers_hostile_keys",
		"v4_midgame.json",
		func(s: Dictionary) -> void:
			s["stickers"]["unlocked"]["../../etc/passwd"] = true
			s["stickers"]["unlocked"]["💥"] = {"tief": {"verschachtelt": []}}
	)
	# — halbe Saves (Slices fehlen komplett) —
	add.call(
		"halber_save_nur_5_keys",
		"v4_midgame.json",
		func(s: Dictionary) -> void:
			for k in s.keys().duplicate():
				if not ["v", "coins", "level", "stats", "onboarding"].has(k):
					s.erase(k)
	)
	add.call("leeres_objekt", "v4_fresh.json", func(s: Dictionary) -> void: s.clear())
	# — alte Kette: v2-Fixture kaputt gemacht —
	add.call(
		"v2_legacy_outfits_vertauscht",
		"v2_legacy.json",
		func(s: Dictionary) -> void:
			var tmp: Variant = s.get("outfits")
			s["outfits"] = s.get("stats")
			s["stats"] = tmp
	)
	add.call("v2_legacy_ohne_version", "v2_legacy.json", func(s: Dictionary) -> void: s.erase("v"))
	return muts


func test_fuzz_migrate_any_crasht_nie_und_liefert_vertrag() -> void:
	var muts := _dict_mutations()
	assert_true(muts.size() >= 20, "mind. 20 Mutationen (sind: %d)" % muts.size())
	var ok_count := 0
	var rejected := 0
	for mut: Dictionary in muts:
		var raw: Dictionary = _load_fixture(mut["fixture"]).duplicate(true)
		(mut["mutate"] as Callable).call(raw)
		var res: Dictionary = MigrationV4.migrate_any(raw, NOW_MS)
		# Vertrag: volle Antwortstruktur, egal was reinkam.
		for key in ["ok", "state", "error", "report"]:
			assert_true(res.has(key), "%s: Antwort-Key %s" % [mut["name"], key])
		if res["ok"]:
			ok_count += 1
			var s: Dictionary = res["state"]
			assert_eq(int(s.get("v", 0)), 5, "%s: ok → v5" % mut["name"])
			var again := SaveSchema.normalize(s, NOW_MS)
			assert_true(again["ok"], "%s: Ergebnis ist normalize-stabil" % mut["name"])
			# Kern-Klamps halten auch unter Beschuss.
			var stats: Dictionary = s["gooby"]["stats"]
			for k in ["hunger", "energy", "hygiene", "fun"]:
				var v := float(stats[k])
				assert_true(v >= 0.0 and v <= 100.0, "%s: stat %s in [0,100]" % [mut["name"], k])
			assert_true(int(s["economy"]["coins"]) >= 0, "%s: coins >= 0" % mut["name"])
			var level := int(s["progression"]["level"])
			assert_true(level >= 1 and level <= 40, "%s: level in [1,40]" % mut["name"])
		else:
			rejected += 1
			assert_false(String(res["error"]).is_empty(), "%s: Fehler benannt" % mut["name"])
	print(
		(
			"    Fuzz-Bericht: %d Mutationen — %d migriert+geklampt, %d sauber abgelehnt"
			% [muts.size(), ok_count, rejected]
		)
	)
	assert_eq(ok_count + rejected, muts.size(), "jede Mutation deterministisch behandelt")


func test_fuzz_geklampte_werte_stimmen() -> void:
	# Stichproben: die Klamps liefern nicht nur "irgendwas Gültiges",
	# sondern die dokumentierten Doc-H-§5.2-Werte.
	var raw := _load_fixture("v4_midgame.json").duplicate(true)
	raw["coins"] = -500
	raw["level"] = 999
	raw["stats"]["hunger"] = 1.0e308
	raw["stats"]["energy"] = -999999
	var res := MigrationV4.migrate_any(raw, NOW_MS)
	assert_true(res["ok"], "geklampte Mutation migriert: " + res["error"])
	var s: Dictionary = res["state"]
	# midgame hat eine laufende beach-Reise → Erstattung 180 bleibt Teil des Betrags.
	assert_eq(int(s["economy"]["coins"]), 0 + 250 + 180, "coins -500 → 0 + Bonus + Erstattung")
	assert_eq(int(s["progression"]["level"]), 40, "level 999 → MAX 40")
	assert_almost(float(s["gooby"]["stats"]["hunger"]), 100.0, 1e-9, "1e308 → 100")
	assert_almost(float(s["gooby"]["stats"]["energy"]), 0.0, 1e-9, "-999999 → 0")


func test_fuzz_save_manager_bootet_immer() -> void:
	# Ende-zu-Ende: kaputte Datei auf Platte → load_state liefert IMMER einen
	# brauchbaren State (Default, recovered) statt zu crashen oder zu hängen.
	var text_level_payloads := {
		"halbes_json": '{"v": 4, "coins": 123, "stats": {"hun',
		"leer": "",
		"nur_whitespace": " \n\t ",
		"json_array": "[1,2,3]",
		"json_string": '"nur ein string"',
		"null_literal": "null",
		"binaer_muell": "\u0000\u0001GOOBY\u00ff kaputt",
	}
	for mut_name: String in text_level_payloads.keys():
		_seq += 1
		var dir := "user://w4p5_tests/fuzz_%d_%d" % [Time.get_ticks_usec(), _seq]
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var manager: SaveManager = SaveManager.new()
		manager.save_path = dir + "/save_v5.json"
		var f := FileAccess.open(manager.save_path, FileAccess.WRITE)
		f.store_string(text_level_payloads[mut_name])
		f = null
		var res := manager.load_state(NOW_MS)
		assert_true(res["state"] is Dictionary, "%s: State ist Dict" % mut_name)
		assert_eq(int(res["state"].get("v", 0)), 5, "%s: bootet als v5-Default" % mut_name)
		assert_true(res["recovered"], "%s: als Recovery markiert" % mut_name)
		assert_true(
			FileAccess.file_exists(manager.corrupt_path()),
			"%s: Rohdatei nach .corrupt gesichert" % mut_name
		)


func test_e2_crash_repro_load_state_bootet_immer() -> void:
	# E2-P0-Repro (Eval, headless bewiesen): exakt DIESE Datei crashte
	# load_state komplett (SCRIPT ERROR → {}; kein Recovery, kein Backup).
	# Jetzt: bootet IMMER. Der Save ist web-gueltig (on:"no" ist NICHT
	# === false) und muss regulaer MIGRIEREN — Web-Paritaet statt Recovery.
	_seq += 1
	var dir := "user://w4p5_tests/e2repro_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var manager: SaveManager = SaveManager.new()
	manager.save_path = dir + "/save_v5.json"
	var f := FileAccess.open(manager.save_path, FileAccess.WRITE)
	f.store_string('{"v":4,"radio":{"trims":{"a":{"vol":100,"on":"no"}}}}')
	f = null
	var res := manager.load_state(NOW_MS)
	assert_true(res.get("state") is Dictionary, "E2-Payload: load_state liefert State")
	assert_eq(int(res["state"].get("v", 0)), 5, "E2-Payload bootet als v5")
	var trim: Dictionary = res["state"]["radio"]["trims"]["a"]
	assert_eq(trim["on"], true, "Web `=== false`: 'no' schaltet den Trim NICHT ab")
	assert_eq(int(trim["vol"]), 100, "vol bleibt")
	# Struktur-korrupter v4-Save daneben → sauberes Recovery (Backup + Default).
	var manager2: SaveManager = SaveManager.new()
	manager2.save_path = dir + "/save_korrupt.json"
	var f2 := FileAccess.open(manager2.save_path, FileAccess.WRITE)
	f2.store_string('{"v":4,"stats":"nope","radio":{"trims":{"a":{"on":"no"}}}}')
	f2 = null
	var res2 := manager2.load_state(NOW_MS)
	assert_eq(int(res2["state"].get("v", 0)), 5, "korrupter v4-Save bootet als v5-Default")
	assert_true(res2["recovered"], "als Recovery markiert")
	assert_true(FileAccess.file_exists(manager2.corrupt_path()), "Rohdatei → .corrupt gesichert")


func test_park_klamps_cheater_fixture() -> void:
	# E2-P2-1: v4_extras.json traegt einen ECHTEN (web-persistierten) Cheater-
	# Park — Godot muss wie web themePark.sliceOf klampen + whitelisten.
	var res := MigrationV4.migrate_any(_load_fixture("v4_extras.json"), NOW_MS)
	assert_true(res["ok"], "extras-Fixture migriert: " + res["error"])
	var park: Dictionary = res["state"]["park"]
	assert_eq(int(park["visits"]), 99999, "visits 1e15 → MAX_COUNT 99999")
	assert_eq(int(park["handsUp"]), 99999, "handsUp 1e15 → MAX_COUNT")
	assert_eq(int(park["rides"]["coaster"]), 0, "coaster -5 → 0")
	assert_false(park["rides"].has("ufo"), "unbekannte Ride-Id 'ufo' verworfen")
	assert_eq(int(park["rides"]["wheel"]), 0, "bekannte Ride-Id ergaenzt (Default 0)")
	assert_eq(int(park["candyBought"]), 12, "gueltiger Zaehler bleibt verbatim")
	assert_eq(park["nightVisit"], false, "'ja' ist kein echtes true (web ===)")


func test_vergessene_slices_gemappt_und_verlustliste_ehrlich() -> void:
	# E2-P1: cutscenes.seen / care.* / minigames.difficulty aus echten Saves.
	var res := MigrationV4.migrate_any(_load_fixture("v4_extras.json"), NOW_MS)
	assert_true(res["ok"], "extras-Fixture migriert: " + res["error"])
	var s: Dictionary = res["state"]
	# difficulty hat einen v5-Zielort (minigames.difficulty.<id>, pregame.gd).
	assert_eq(s["minigames"]["difficulty"].get("carrotCatch"), "easy", "difficulty gemappt")
	assert_eq(s["minigames"]["difficulty"].get("bunnyHop"), "hard", "difficulty gemappt")
	# care.toiletAt → bad.kloLastMs (gleiche Klo-Cooldown-Semantik).
	assert_eq(int(s["bad"]["kloLastMs"]), 1768474800000, "care.toiletAt → bad.kloLastMs")
	# additive Zaehler ueberleben verbatim (E2 'Verifiziert OK' absichern).
	assert_eq(int(s["achievements"]["counters"]["sickEver"]), 2, "sickEver bleibt")
	assert_eq(int(s["achievements"]["counters"]["holeInOnes"]), 3, "holeInOnes bleibt")
	# Verlustliste ist EHRLICH: nennt alles, was wirklich verworfen wird.
	var lost_text := "\n".join(PackedStringArray(s["migration"]["lost"]))
	assert_true(lost_text.contains("cutscenes.seen"), "lost nennt cutscenes.seen")
	assert_true(lost_text.contains("care.sickNotifyAt"), "lost nennt care.sickNotifyAt")
	assert_true(lost_text.contains("recap.pendingLevel"), "lost nennt recap.pendingLevel")
	# midgame traegt difficulty ebenfalls (Fixture-Beweis am zweiten Save).
	var mid := MigrationV4.migrate_any(_load_fixture("v4_midgame.json"), NOW_MS)
	assert_true(mid["ok"], mid["error"])
	assert_eq(mid["state"]["minigames"]["difficulty"].get("carrotCatch"), "hard")
	# Ohne care/cutscenes im Save: keine erfundenen Verlust-Eintraege.
	var mid_lost := "\n".join(PackedStringArray(mid["state"]["migration"]["lost"]))
	assert_false(mid_lost.contains("cutscenes.seen"), "kein cutscenes-Eintrag ohne Daten")
	assert_false(mid_lost.contains("care.sickNotifyAt"), "kein care-Eintrag ohne Daten")


func test_numerische_strings_koerziert_wie_web() -> void:
	# E2-P2-2: Web validate() koerziert Leaf-Strings lenient (Number('62')→62);
	# Godot mappte sie vorher auf 0/NaN→Default (hygiene '62' wurde 85).
	var raw := _load_fixture("v4_midgame.json").duplicate(true)
	raw["stats"]["hygiene"] = "62"
	raw["coins"] = "5000"
	raw["weight"] = {"value": "88"}
	var res := MigrationV4.migrate_any(raw, NOW_MS)
	assert_true(res["ok"], "numerische Strings migrieren: " + res["error"])
	var s: Dictionary = res["state"]
	assert_almost(float(s["gooby"]["stats"]["hygiene"]), 62.0, 1e-9, "'62' → 62 (nicht 85)")
	assert_eq(int(s["economy"]["coins"]), 5000 + 250 + 180, "'5000' + Bonus + Erstattung")
	assert_almost(float(s["gooby"]["weight"]), 88.0, 1e-9, "weight '88' → 88")
	# Nicht-numerische Strings bleiben Junk → Default (kein JS-NaN-Leck).
	raw["stats"]["hygiene"] = "viel"
	var res2 := MigrationV4.migrate_any(raw, NOW_MS)
	assert_true(res2["ok"], res2["error"])
	assert_almost(float(res2["state"]["gooby"]["stats"]["hygiene"]), 85.0, 1e-9, "Junk → Default")


func test_fuzz_moving_box_import_text_haertung() -> void:
	# String-Ebene des Umzugskoffers: nie Crash, immer voller Antwort-Vertrag.
	var payloads: Array[String] = [
		"",
		"   ",
		"kein json {{{",
		'{"v": 4, "coins": 1',
		"GOOBY5.",
		"GOOBY5..",
		"GOOBY5.!!!.zzz",
		"GOOBY5.%s.00000000" % Marshalls.raw_to_base64("kein gzip".to_utf8_buffer()),
		"[1,2,3]",
		'{"v": 6, "aus": "der Zukunft"}',
	]
	for text in payloads:
		var res := MovingBox.import_text(text, NOW_MS)
		for key in ["ok", "state", "error", "report"]:
			assert_true(res.has(key), "'%s…': Antwort-Key %s" % [text.left(12), key])
		assert_false(res["ok"], "'%s…': sauber abgelehnt" % text.left(12))
		assert_false(String(res["error"]).is_empty(), "'%s…': Fehler benannt" % text.left(12))
