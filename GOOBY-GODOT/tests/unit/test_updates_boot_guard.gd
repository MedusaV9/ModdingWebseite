extends TestCase
## W2b UPDATES — Boot-Guard-Statemaschine (Doc B §2.5) + PackLoaderService-
## Anwendung: 1×→Retry, 2×→jüngstes Pack deaktivieren (mit Rollback auf
## previous), 3×→Safe-Mode; Erfolgs-Boot resettet; Stale-Cleanup + min_native.
## Alles mit injizierten user://-Pfaden — kein echtes res://content nötig.

const BASE := "user://w2b_guard_test"


func test_decision_tabelle() -> void:
	assert_eq(BootGuard.decision_for_attempts(0), BootGuard.Decision.NORMAL, "0 = normal")
	assert_eq(BootGuard.decision_for_attempts(1), BootGuard.Decision.NORMAL, "1 = normaler Retry")
	assert_eq(
		BootGuard.decision_for_attempts(2),
		BootGuard.Decision.DISABLE_NEWEST,
		"2 = jüngstes Pack deaktivieren"
	)
	assert_eq(BootGuard.decision_for_attempts(3), BootGuard.Decision.SAFE_MODE, "3 = Safe-Mode")
	assert_eq(
		BootGuard.decision_for_attempts(7), BootGuard.Decision.SAFE_MODE, ">3 bleibt Safe-Mode"
	)


func test_zaehler_persistiert_und_resettet() -> void:
	_wipe(BASE)
	var path := BASE + "/boot_guard.json"
	var guard := BootGuard.open(path)
	assert_eq(guard.begin_boot(), BootGuard.Decision.NORMAL, "1. Versuch")
	# Neuer Prozess (simuliert): frische Instanz liest den persistierten Zähler.
	var guard2 := BootGuard.open(path)
	assert_eq(guard2.attempts, 1, "attempts überlebt den 'Crash'")
	assert_eq(guard2.begin_boot(), BootGuard.Decision.DISABLE_NEWEST, "2. Versuch")
	var guard3 := BootGuard.open(path)
	assert_eq(guard3.begin_boot(), BootGuard.Decision.SAFE_MODE, "3. Versuch")
	guard3.mark_boot_ok(1234)
	var guard4 := BootGuard.open(path)
	assert_eq(guard4.attempts, 0, "Erfolgs-Boot nullt")
	assert_eq(guard4.last_ok_unix, 1234, "last_ok persistiert")
	assert_eq(guard4.begin_boot(), BootGuard.Decision.NORMAL, "nach Erfolg wieder normal")
	_wipe(BASE)


func test_kaputte_datei_faellt_auf_null() -> void:
	_wipe(BASE)
	var path := BASE + "/boot_guard.json"
	DirAccess.make_dir_recursive_absolute(BASE)
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{{{{")
	file.close()
	assert_eq(BootGuard.open(path).attempts, 0, "kaputt → 0 (kein Crash, kein Soft-Lock)")
	_wipe(BASE)


func test_loader_statemaschine_attempts_1_2_3() -> void:
	_wipe(BASE)
	var loader := _make_loader()
	# Zwei „installierte“ Packs; min_native 9.9.9 hält load_resource_pack raus —
	# hier geht es NUR um die Guard-/installed.json-Statemaschine.
	_seed_installed(
		{
			"aeltestes": _entry("aeltestes-v1.1.0.pck", "1.1.0", 1, true),
			"juengstes": _entry("juengstes-v2.1.0.pck", "2.1.0", 2, false),
		}
	)
	# Boot 1: normal, nichts deaktiviert.
	var report1 := loader.load_packs_at_boot()
	assert_eq(report1["decision"], BootGuard.Decision.NORMAL, "Boot 1 normal")
	assert_eq(report1["disabled"], [], "Boot 1 deaktiviert nichts")
	assert_eq(report1["skipped"], ["aeltestes", "juengstes"], "min_native-Gate: NIE laden")
	# Boot 2 (ohne mark_boot_successful == Crash): jüngstes nicht-bewährtes Pack aus.
	var disabled_events: Array = []
	loader.pack_disabled.connect(
		func(pack_id: String, reason: String) -> void: disabled_events.append([pack_id, reason])
	)
	var report2 := loader.load_packs_at_boot()
	assert_eq(report2["decision"], BootGuard.Decision.DISABLE_NEWEST, "Boot 2")
	assert_eq(report2["disabled"], ["juengstes"], "höchste installed_seq + survived_boot=false")
	assert_eq(disabled_events, [["juengstes", "boot_guard_rollback"]], "Signal gefeuert")
	var installed := UpdatesManifest.read_installed(loader.installed_path())
	assert_false(bool(installed["packs"]["juengstes"]["enabled"]), "persistiert deaktiviert")
	assert_true(bool(installed["packs"]["aeltestes"]["enabled"]), "bewährtes Pack bleibt an")
	# Boot 3: Safe-Mode — ALLE user-Packs aus.
	var safe_fired := [false]
	loader.safe_mode_entered.connect(func() -> void: safe_fired[0] = true)
	var report3 := loader.load_packs_at_boot()
	assert_eq(report3["decision"], BootGuard.Decision.SAFE_MODE, "Boot 3")
	assert_true(bool(report3["safe_mode"]), "Report meldet Safe-Mode")
	assert_true(safe_fired[0], "safe_mode_entered gefeuert")
	assert_true(loader.is_safe_mode(), "is_safe_mode()")
	installed = UpdatesManifest.read_installed(loader.installed_path())
	assert_false(bool(installed["packs"]["aeltestes"]["enabled"]), "Safe-Mode: alles aus")
	# Erfolgs-Boot + „Erneut versuchen“: Guard genullt, Packs wieder an.
	loader.reenable_all_packs()
	var report4 := loader.load_packs_at_boot()
	assert_eq(report4["decision"], BootGuard.Decision.NORMAL, "nach Reset wieder normal")
	installed = UpdatesManifest.read_installed(loader.installed_path())
	assert_true(bool(installed["packs"]["juengstes"]["enabled"]), "reenable_all_packs")
	loader.free()
	_wipe(BASE)


func test_rollback_auf_previous() -> void:
	_wipe(BASE)
	var loader := _make_loader()
	var entry := _entry("verdaechtig-v2.0.0.pck", "2.0.0", 5, false)
	entry["previous"] = "verdaechtig-v1.0.0.pck"
	entry["previous_version"] = "1.0.0"
	entry["previous_sha256"] = "aa"
	_seed_installed({"verdaechtig": entry})
	_touch(BASE + "/packs/verdaechtig-v1.0.0.pck")
	_touch(BASE + "/packs/verdaechtig-v2.0.0.pck")
	BootGuard.open(loader.guard_path).begin_boot()  # simulierter Crash-Vorlauf → attempts 1
	var report := loader.load_packs_at_boot()
	assert_eq(report["decision"], BootGuard.Decision.DISABLE_NEWEST, "2. Versuch")
	var installed := UpdatesManifest.read_installed(loader.installed_path())
	var rolled: Dictionary = installed["packs"]["verdaechtig"]
	assert_eq(str(rolled["file"]), "verdaechtig-v1.0.0.pck", "auf previous zurückgerollt")
	assert_eq(str(rolled["version"]), "1.0.0", "Version zurückgerollt")
	assert_true(bool(rolled["enabled"]), "rollback bleibt aktiv (nicht deaktiviert)")
	assert_true(bool(rolled["survived_boot"]), "previous galt als bewährt")
	assert_false(
		FileAccess.file_exists(BASE + "/packs/verdaechtig-v2.0.0.pck"),
		"kaputte neue Datei gelöscht"
	)
	loader.free()
	_wipe(BASE)


func test_stale_cleanup_und_load_fail() -> void:
	_wipe(BASE)
	var loader := _make_loader()
	loader.app_version = "5.0.0"
	# stale: user-Version <= eingebaut (neue IPA enthält den Stand schon).
	var stale := _entry("stale-v1.0.0.pck", "1.0.0", 1, true)
	stale["min_native"] = "5.0.0"
	# ladbar laut Gate, aber Datei ist Schrott → load_resource_pack false → disabled.
	var broken := _entry("broken-v9.0.0.pck", "9.0.0", 2, true)
	broken["min_native"] = "5.0.0"
	_seed_installed({"stale": stale, "broken": broken})
	_write_builtin("stale", "2.0.0")
	_touch(BASE + "/packs/stale-v1.0.0.pck")
	var broken_file := FileAccess.open(BASE + "/packs/broken-v9.0.0.pck", FileAccess.WRITE)
	broken_file.store_string("kein pck")
	broken_file.close()
	var report := loader.load_packs_at_boot()
	assert_eq(report["cleaned"], ["stale"], "Stale-Cleanup greift")
	assert_false(FileAccess.file_exists(BASE + "/packs/stale-v1.0.0.pck"), "stale Datei gelöscht")
	var installed := UpdatesManifest.read_installed(loader.installed_path())
	assert_false(installed["packs"].has("stale"), "stale Eintrag entfernt")
	assert_eq(report["disabled"], ["broken"], "unladbares Pack deaktiviert")
	assert_false(bool(installed["packs"]["broken"]["enabled"]), "persistiert")
	loader.free()
	_wipe(BASE)


func _make_loader() -> PackLoaderService:
	var loader := PackLoaderService.new()
	loader.auto_boot = false
	loader.packs_dir = BASE + "/packs"
	loader.guard_path = BASE + "/boot_guard.json"
	loader.content_root = BASE + "/content"
	loader.app_version = "5.0.0"
	DirAccess.make_dir_recursive_absolute(BASE + "/packs")
	DirAccess.make_dir_recursive_absolute(BASE + "/content")
	return loader


func _entry(file_name: String, version: String, seq: int, survived: bool) -> Dictionary:
	return {
		"version": version,
		"file": file_name,
		"sha256": "00",
		"min_native": "9.9.9",
		"priority": 400 + seq,
		"type": "pck",
		"enabled": true,
		"installed_at": "2026-07-24T20:0%d:00Z" % seq,
		"installed_seq": seq,
		"survived_boot": survived,
	}


func _seed_installed(packs: Dictionary) -> void:
	UpdatesManifest.write_installed(BASE + "/packs/installed.json", {"schema": 1, "packs": packs})


func _write_builtin(pack_id: String, version: String) -> void:
	var path := "%s/content/%s/pack.json" % [BASE, pack_id]
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"id": pack_id, "version": version}))
	file.close()


func _touch(path: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("x")
	file.close()


func _wipe(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var child := path + "/" + entry
		if dir.current_is_dir():
			_wipe(child)
		else:
			DirAccess.remove_absolute(ProjectSettings.globalize_path(child))
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
