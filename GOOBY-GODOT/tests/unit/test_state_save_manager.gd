extends TestCase
## W1d — save_manager.gd: atomares Schreiben, Debounce, Backup-Rotation,
## Korruptions-Recovery. Schreibt in ein eigenes user://-Unterverzeichnis.

const SaveSchema := preload("res://scripts/state/save_schema.gd")
const SaveManager := preload("res://scripts/state/save_manager.gd")
const Util := preload("res://tests/fixtures/state_test_util.gd")
## Fault-Injection-Fassade (EVAL-2026-08/C Befund 14): volle Platte,
## Permission, Rename-Failure, Crash-Fenster zwischen Rotationsschritten.
const FakeSaveIo := preload("res://tests/tools/fake_save_io.gd")

const NOW_MS := 1768478400000

var _dir_seq := 0


func _fresh_manager() -> SaveManager:
	_dir_seq += 1
	var dir := "user://w1d_tests/mgr_%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var manager := SaveManager.new()
	manager.save_path = dir + "/save_v5.json"
	return manager


func test_fresh_load_and_roundtrip() -> void:
	var manager := _fresh_manager()
	var first := manager.load_state(NOW_MS)
	assert_true(first["fresh"])
	assert_false(first["recovered"])
	var state: Dictionary = first["state"]
	state["economy"]["coins"] = 4321
	assert_true(manager.save_now(state))
	assert_false(FileAccess.file_exists(manager.save_path + ".tmp"), "tmp weggerenamed")
	var loaded := manager.load_state(NOW_MS)
	assert_false(loaded["fresh"])
	assert_eq(loaded["source"], "save")
	# Numerisch tolerant (JSON: int → float); strukturell muss ALLES gleich sein.
	var diff := Util.first_diff(loaded["state"], state)
	assert_true(diff.is_empty(), "Datei-Roundtrip deep-equal: " + diff)


func test_backup_rotation_three_generations() -> void:
	var manager := _fresh_manager()
	var state: Dictionary = manager.load_state(NOW_MS)["state"]
	for coins in [1, 2, 3, 4]:
		state["economy"]["coins"] = coins
		assert_true(manager.save_now(state))
	for gen in [1, 2, 3]:
		var bak := "%s.bak%d" % [manager.save_path, gen]
		assert_true(FileAccess.file_exists(bak), "bak%d existiert" % gen)
		var json := JSON.new()
		json.parse(FileAccess.get_file_as_string(bak))
		assert_eq(
			int(json.data["economy"]["coins"]), 4 - gen, "bak%d = Generation n-%d" % [gen, gen]
		)


func test_corruption_recovers_from_backup() -> void:
	var manager := _fresh_manager()
	var state: Dictionary = manager.load_state(NOW_MS)["state"]
	state["economy"]["coins"] = 111
	manager.save_now(state)
	state["economy"]["coins"] = 222
	manager.save_now(state)
	# Hauptdatei zerstoeren → Recovery aus bak1 (== coins 111).
	var f := FileAccess.open(manager.save_path, FileAccess.WRITE)
	f.store_string("{{{ kaputt %#!")
	f = null
	var loaded := manager.load_state(NOW_MS)
	assert_true(loaded["recovered"])
	assert_eq(loaded["source"], "bak1")
	assert_eq(loaded["state"]["economy"]["coins"], 111)
	assert_true(FileAccess.file_exists(manager.corrupt_path()), "Rohdatei gesichert")


func test_all_corrupt_falls_back_to_fresh() -> void:
	var manager := _fresh_manager()
	var f := FileAccess.open(manager.save_path, FileAccess.WRITE)
	f.store_string("kein json")
	f = null
	var loaded := manager.load_state(NOW_MS)
	assert_true(loaded["recovered"])
	assert_eq(loaded["source"], "fresh")
	assert_eq(loaded["state"]["economy"]["coins"], 100, "frischer Default-State")


func test_wrong_typed_slice_is_corrupt_not_crash() -> void:
	var manager := _fresh_manager()
	var f := FileAccess.open(manager.save_path, FileAccess.WRITE)
	f.store_string('{"v":5,"gooby":"nope"}')
	f = null
	var loaded := manager.load_state(NOW_MS)
	assert_true(loaded["recovered"], "valid-JSON-wrong-types = korrupt (web F2/E12)")
	assert_eq(loaded["source"], "fresh")


func test_missing_file_recovers_from_bak1() -> void:
	var manager := _fresh_manager()
	var state: Dictionary = manager.load_state(NOW_MS)["state"]
	state["economy"]["coins"] = 111
	manager.save_now(state)
	state["economy"]["coins"] = 222
	manager.save_now(state)
	# Crash-Fenster von save_now(): Rotation lief (alter Save → bak1), der
	# Rename .tmp → save kam nicht mehr → Hauptdatei fehlt, bak1 = 111.
	DirAccess.remove_absolute(ProjectSettings.globalize_path(manager.save_path))
	var loaded := manager.load_state(NOW_MS)
	assert_false(loaded["fresh"], "kein Frisch-Start trotz fehlender Hauptdatei")
	assert_true(loaded["recovered"])
	assert_eq(loaded["source"], "bak1")
	assert_eq(int(loaded["state"]["economy"]["coins"]), 111)


func test_missing_file_skips_broken_bak1_uses_bak2() -> void:
	var manager := _fresh_manager()
	var state: Dictionary = manager.load_state(NOW_MS)["state"]
	for coins in [1, 2, 3]:
		state["economy"]["coins"] = coins
		manager.save_now(state)
	# Hauptdatei weg, liegengebliebenes .tmp UND bak1 kaputt → bak2 (= 1).
	DirAccess.remove_absolute(ProjectSettings.globalize_path(manager.save_path))
	for broken in [manager.save_path + ".tmp", manager.save_path + ".bak1"]:
		var f := FileAccess.open(broken, FileAccess.WRITE)
		f.store_string("{{{ kaputt %#!")
		f = null
	var loaded := manager.load_state(NOW_MS)
	assert_true(loaded["recovered"])
	assert_eq(loaded["source"], "bak2")
	assert_eq(int(loaded["state"]["economy"]["coins"]), 1)


func test_missing_file_prefers_complete_tmp_over_bak() -> void:
	var manager := _fresh_manager()
	var state: Dictionary = manager.load_state(NOW_MS)["state"]
	state["economy"]["coins"] = 111
	manager.save_now(state)
	# Crash exakt zwischen Rotation und Rename: .tmp = neuester voll
	# geflushter Stand (333), bak1 = 111, Hauptdatei fehlt.
	state["economy"]["coins"] = 333
	var f := FileAccess.open(manager.save_path + ".tmp", FileAccess.WRITE)
	f.store_string(JSON.stringify(state))
	f = null
	DirAccess.remove_absolute(ProjectSettings.globalize_path(manager.save_path))
	var loaded := manager.load_state(NOW_MS)
	assert_true(loaded["recovered"])
	assert_eq(loaded["source"], "tmp")
	assert_eq(int(loaded["state"]["economy"]["coins"]), 333)


func test_missing_file_and_all_backups_falls_back_to_fresh() -> void:
	var manager := _fresh_manager()
	var state: Dictionary = manager.load_state(NOW_MS)["state"]
	for coins in [1, 2, 3, 4]:
		state["economy"]["coins"] = coins
		manager.save_now(state)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(manager.save_path))
	for gen in [1, 2, 3]:
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path("%s.bak%d" % [manager.save_path, gen])
		)
	var loaded := manager.load_state(NOW_MS)
	assert_true(loaded["fresh"], "alles fehlt → fresh wie bisher")
	assert_false(loaded["recovered"])
	assert_eq(loaded["source"], "fresh")
	assert_eq(int(loaded["state"]["economy"]["coins"]), 100, "frischer Default-State")


func test_v4_file_is_migrated_on_load() -> void:
	var manager := _fresh_manager()
	var raw := FileAccess.get_file_as_string("res://tests/fixtures/v4_fresh.json")
	var f := FileAccess.open(manager.save_path, FileAccess.WRITE)
	f.store_string(raw)
	f = null
	var loaded := manager.load_state(NOW_MS)
	assert_false(loaded["recovered"])
	assert_eq(loaded["state"]["v"], 5)
	assert_eq(loaded["state"]["economy"]["coins"], 350, "100 + 250 Umzugsbonus")


func test_debounce_flushes_after_window() -> void:
	var manager := _fresh_manager()
	manager.debounce_ms = 500
	var state: Dictionary = manager.load_state(NOW_MS)["state"]
	state["economy"]["coins"] = 777
	manager.mark_dirty(1000)
	assert_true(manager.is_dirty())
	assert_false(manager.autosave_tick(state, 1200), "innerhalb des Debounce-Fensters")
	assert_false(FileAccess.file_exists(manager.save_path))
	assert_true(manager.autosave_tick(state, 1500), "Fenster abgelaufen → Flush")
	assert_false(manager.is_dirty())
	assert_true(FileAccess.file_exists(manager.save_path))
	assert_false(manager.autosave_tick(state, 9999), "nicht mehr dirty → kein Doppel-Flush")


## ── Fault-Injection (EVAL-2026-08/C Befund 14) ──────────────────────────
## Save-Fehler müssen SICHTBAR scheitern (Signal + letzter_fehler + false)
## und dürfen nie einen Zustand hinterlassen, in dem weder die alte noch
## die neue Datei gültig ist.


## Volle Platte: store_string schreibt nur teilweise → save_now bricht VOR
## Rotation und Rename ab, die halbe .tmp wird NIE zur Hauptdatei, der
## alte Save bleibt vollständig gültig.
func test_volle_platte_bricht_vor_rotation_ab_und_meldet_sichtbar() -> void:
	var manager := _fresh_manager()
	var state: Dictionary = manager.load_state(NOW_MS)["state"]
	state["economy"]["coins"] = 111
	assert_true(manager.save_now(state), "Setup-Save gelingt mit echtem I/O")
	var fake := FakeSaveIo.new()
	fake.platte_voll = true
	manager.io = fake
	var meldungen: Array[String] = []
	manager.save_fehlgeschlagen.connect(func(grund: String) -> void: meldungen.append(grund))
	state["economy"]["coins"] = 222
	assert_false(manager.save_now(state), "volle Platte → save_now false")
	assert_eq(meldungen.size(), 1, "Signal save_fehlgeschlagen gefeuert")
	assert_true(manager.letzter_fehler().contains("Schreiben"), "Grund nennt das Schreiben")
	assert_false(
		FileAccess.file_exists(manager.save_path + ".bak1"),
		"KEINE Rotation nach Schreibfehler (alter Save nicht verschoben)"
	)
	var kontrolle := _fresh_kontrolle(manager)
	assert_eq(kontrolle["source"], "save", "Hauptdatei weiterhin gültig")
	assert_eq(int(kontrolle["state"]["economy"]["coins"]), 111, "alter Stand unversehrt")


## Permission-Fehler beim Öffnen der .tmp: sichtbarer Fehlschlag, keine
## Dateiänderung.
func test_permission_beim_oeffnen_schlaegt_sichtbar_fehl() -> void:
	var manager := _fresh_manager()
	var state: Dictionary = manager.load_state(NOW_MS)["state"]
	state["economy"]["coins"] = 111
	assert_true(manager.save_now(state))
	var fake := FakeSaveIo.new()
	fake.open_verbieten = [".tmp"]
	manager.io = fake
	var meldungen: Array[String] = []
	manager.save_fehlgeschlagen.connect(func(grund: String) -> void: meldungen.append(grund))
	state["economy"]["coins"] = 222
	assert_false(manager.save_now(state), "Permission → save_now false")
	assert_eq(meldungen.size(), 1, "Signal gefeuert")
	assert_true(manager.letzter_fehler().contains("öffnen"), "Grund nennt das Öffnen")
	var kontrolle := _fresh_kontrolle(manager)
	assert_eq(kontrolle["source"], "save")
	assert_eq(int(kontrolle["state"]["economy"]["coins"]), 111, "alter Stand unversehrt")


## Scheitert das FINALE Rename (tmp → save), ist die Rotation schon
## gelaufen: die Hauptdatei fehlt, aber .tmp ist der voll geflushte neueste
## Stand und wird beim nächsten Laden bevorzugt — neue Datei gültig.
func test_rename_failure_haelt_tmp_als_neuesten_stand() -> void:
	var manager := _fresh_manager()
	var state: Dictionary = manager.load_state(NOW_MS)["state"]
	state["economy"]["coins"] = 111
	assert_true(manager.save_now(state))
	var fake := FakeSaveIo.new()
	fake.rename_verbieten = [manager.save_path.get_file()]
	manager.io = fake
	state["economy"]["coins"] = 222
	assert_false(manager.save_now(state), "Rename-Failure → save_now false")
	assert_true(manager.letzter_fehler().contains("rename"), "Grund nennt das Rename")
	var kontrolle := _fresh_kontrolle(manager)
	assert_eq(kontrolle["source"], "tmp", "Recovery bevorzugt die voll geflushte .tmp")
	assert_true(kontrolle["recovered"])
	assert_eq(int(kontrolle["state"]["economy"]["coins"]), 222, "neuester Stand geladen")


## Fehler in der Backup-Rotation (remove/rename der .bakN) sind nicht
## fatal: der NEUE Save gelingt, die alte Generationen-Kette bleibt stehen.
func test_rotationsfehler_sind_nicht_fatal_save_gelingt() -> void:
	var manager := _fresh_manager()
	var state: Dictionary = manager.load_state(NOW_MS)["state"]
	for coins in [1, 2, 3, 4]:
		state["economy"]["coins"] = coins
		assert_true(manager.save_now(state))
	var fake := FakeSaveIo.new()
	fake.remove_verbieten = true
	fake.rename_verbieten = [".bak1", ".bak2", ".bak3"]
	manager.io = fake
	var meldungen: Array[String] = []
	manager.save_fehlgeschlagen.connect(func(grund: String) -> void: meldungen.append(grund))
	state["economy"]["coins"] = 5
	assert_true(manager.save_now(state), "Save gelingt trotz kaputter Rotation")
	assert_eq(meldungen.size(), 0, "kein Fehl-Signal — nur Rotations-Warnungen")
	var kontrolle := _fresh_kontrolle(manager)
	assert_eq(kontrolle["source"], "save")
	assert_eq(int(kontrolle["state"]["economy"]["coins"]), 5, "neuer Stand in der Hauptdatei")
	for gen in [1, 2, 3]:
		var json := JSON.new()
		json.parse(FileAccess.get_file_as_string("%s.bak%d" % [manager.save_path, gen]))
		assert_eq(int(json.data["economy"]["coins"]), 4 - gen, "bak%d unverändert" % gen)


## Crash EXAKT zwischen Rotation und finalem Rename (Budget: open, write,
## flush, bak1→bak2, save→bak1 = 5 Mutationen, dann stirbt der Prozess):
## Hauptdatei fehlt, .tmp ist voll geflusht → Recovery lädt den NEUESTEN
## Stand aus .tmp, die Generationen dahinter bleiben konsistent.
func test_crash_zwischen_rotation_und_finalem_rename_laedt_tmp() -> void:
	var manager := _fresh_manager()
	var state: Dictionary = manager.load_state(NOW_MS)["state"]
	state["economy"]["coins"] = 111
	assert_true(manager.save_now(state))
	state["economy"]["coins"] = 222
	assert_true(manager.save_now(state))
	var fake := FakeSaveIo.new()
	fake.budget_mutationen = 5
	manager.io = fake
	state["economy"]["coins"] = 333
	assert_false(manager.save_now(state), "Crash-Fenster → save_now false")
	assert_false(FileAccess.file_exists(manager.save_path), "Hauptdatei im Crash-Fenster weg")
	var kontrolle := _fresh_kontrolle(manager)
	assert_eq(kontrolle["source"], "tmp", "Recovery lädt die voll geflushte .tmp")
	assert_eq(int(kontrolle["state"]["economy"]["coins"]), 333, "neuester Stand")
	var json := JSON.new()
	json.parse(FileAccess.get_file_as_string(manager.save_path + ".bak1"))
	assert_eq(int(json.data["economy"]["coins"]), 222, "bak1 = vorletzte Generation")


## Crash MITTEN in der Rotation (Budget 4: bak1→bak2 lief noch, save→bak1
## nicht mehr): die Hauptdatei existiert weiter → Recovery lädt den letzten
## ERFOLGREICH gemeldeten Save; das liegengebliebene .tmp wird bewusst
## ignoriert (Design, s. save_manager-Kopf) — nie beide Dateien ungültig.
func test_crash_mitten_in_der_rotation_laedt_alten_save() -> void:
	var manager := _fresh_manager()
	var state: Dictionary = manager.load_state(NOW_MS)["state"]
	state["economy"]["coins"] = 111
	assert_true(manager.save_now(state))
	state["economy"]["coins"] = 222
	assert_true(manager.save_now(state))
	var fake := FakeSaveIo.new()
	fake.budget_mutationen = 4
	manager.io = fake
	state["economy"]["coins"] = 333
	assert_false(manager.save_now(state), "Crash-Fenster → save_now false")
	assert_true(FileAccess.file_exists(manager.save_path), "Hauptdatei blieb stehen")
	var kontrolle := _fresh_kontrolle(manager)
	assert_eq(kontrolle["source"], "save", "Recovery lädt die intakte Hauptdatei")
	assert_false(kontrolle["recovered"])
	assert_eq(int(kontrolle["state"]["economy"]["coins"]), 222, "letzter erfolgreicher Save")


## Fehlgeschlagene Autosaves lassen den Zustand dirty und versuchen es nach
## einem weiteren Debounce-Fenster erneut (Retry statt stillem Verlust) —
## ohne pro Tick die Platte zu hämmern.
func test_autosave_retry_nach_save_fehler() -> void:
	var manager := _fresh_manager()
	manager.debounce_ms = 500
	var state: Dictionary = manager.load_state(NOW_MS)["state"]
	state["economy"]["coins"] = 777
	var fake := FakeSaveIo.new()
	fake.platte_voll = true
	manager.io = fake
	var meldungen: Array[String] = []
	manager.save_fehlgeschlagen.connect(func(grund: String) -> void: meldungen.append(grund))
	manager.mark_dirty(1000)
	assert_false(manager.autosave_tick(state, 1600), "Save scheitert (volle Platte)")
	assert_eq(meldungen.size(), 1, "Fehlschlag sichtbar gemeldet")
	assert_true(manager.is_dirty(), "Zustand bleibt dirty → Retry steht aus")
	assert_false(manager.autosave_tick(state, 1700), "im neuen Debounce-Fenster kein Versuch")
	assert_eq(meldungen.size(), 1, "kein I/O-Hämmern pro Tick")
	fake.platte_voll = false
	assert_true(manager.autosave_tick(state, 2200), "Retry nach Fenster gelingt")
	assert_false(manager.is_dirty())
	assert_eq(manager.letzter_fehler(), "", "Erfolg räumt den Fehlerzustand auf")
	var kontrolle := _fresh_kontrolle(manager)
	assert_eq(int(kontrolle["state"]["economy"]["coins"]), 777, "Stand kam doch noch an")


## Pinnt die Crash-sichere Schrittfolge: erst Schreiben+Flush der .tmp,
## DANN Rotation, ZULETZT das atomare Rename — nie umgekehrt.
func test_save_reihenfolge_schreiben_flush_vor_rotation() -> void:
	var manager := _fresh_manager()
	var state: Dictionary = manager.load_state(NOW_MS)["state"]
	var fake := FakeSaveIo.new()
	manager.io = fake
	state["economy"]["coins"] = 1
	assert_true(manager.save_now(state))
	state["economy"]["coins"] = 2
	assert_true(manager.save_now(state))
	var ops: Array[String] = []
	for eintrag in fake.protokoll:
		ops.append(str(eintrag).get_slice(" ", 0))
	assert_eq(
		ops,
		["open", "write", "flush", "rename", "open", "write", "flush", "rename", "rename"],
		"1. Save ohne Rotation; 2. Save: write+flush VOR save→bak1 VOR tmp→save"
	)
	var letzte := str(fake.protokoll[fake.protokoll.size() - 1])
	assert_true(letzte.ends_with(manager.save_path.get_file()), "letzter Schritt = tmp→save")


## Frischer Manager mit ECHTEM I/O auf demselben Pfad — so sieht der
## nächste App-Start die vom Fake hinterlassene Datei-Landschaft.
func _fresh_kontrolle(manager: SaveManager) -> Dictionary:
	var kontrolle := SaveManager.new()
	kontrolle.save_path = manager.save_path
	return kontrolle.load_state(NOW_MS)
