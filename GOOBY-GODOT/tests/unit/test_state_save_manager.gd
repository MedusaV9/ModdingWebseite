extends TestCase
## W1d — save_manager.gd: atomares Schreiben, Debounce, Backup-Rotation,
## Korruptions-Recovery. Schreibt in ein eigenes user://-Unterverzeichnis.

const SaveSchema := preload("res://scripts/state/save_schema.gd")
const SaveManager := preload("res://scripts/state/save_manager.gd")
const Util := preload("res://tests/fixtures/state_test_util.gd")

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
