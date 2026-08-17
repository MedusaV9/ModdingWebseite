extends TestCase
## W2b UPDATES — End-zu-End-Flow (M1-DoD-Beweis): ein zur LAUFZEIT per PCKPacker
## gebautes Cosmetics-Test-Pack wird über ein file://-manifest.json GEFUNDEN →
## GELADEN (Download + sha256-Verify + installed.json) → per PackLoader in res://
## gemountet → die ContentRegistry zeigt nach reload() den NEUEN Inhalt.
## Dazu: config-Sofortpfad (Server-IP ohne IPA), sha-Mismatch, min_native-Gate,
## Toast-Key-Mapping der Settings-Glue, updates.*-String-Parität.

## Eigene Basis PRO Test: das E2E-Verzeichnis wird am Ende NICHT gewischt,
## weil das gemountete PCK bis Prozessende lesbar bleiben muss (PackedData hält
## den Dateipfad); gewischt wird es beim nächsten Lauf VOR dem Mounten.
const BASE_E2E := "user://w2b_flow_e2e"
const BASE_SHA := "user://w2b_flow_sha"
const BASE_GATE := "user://w2b_flow_gate"
const PACK_VERSION := "1.1.0"


func test_flow_finden_laden_registry() -> void:
	_wipe(BASE_E2E)
	DirAccess.make_dir_recursive_absolute(BASE_E2E + "/dist")
	# --- 1. Test-Pack zur Laufzeit bauen (PCKPacker; --export-pack braucht den
	#        Editor-Exporter — für Tests ist PCKPacker der dokumentierte Weg).
	var pck_path := BASE_E2E + "/dist/cosmetics-v%s.pck" % PACK_VERSION
	_build_test_pack(BASE_E2E, pck_path)
	var pck_sha := UpdateService.sha256_of_file(pck_path)
	assert_eq(pck_sha.length(), 64, "sha256 des Test-Packs berechnet (HashingContext)")
	# --- 2. Remote-config (Server-IP-ohne-IPA-Weg) + file://-Manifest schreiben.
	var config_path := BASE_E2E + "/dist/config.json"
	_write_text(
		config_path, JSON.stringify({"schema": 1, "net": {"host": "42.42.42.42", "port": 4242}})
	)
	var manifest := {
		"schema": 1,
		"latest_native": "5.0.0",
		"notes_de": "Flow-Test",
		"packs":
		[
			{
				"id": "cosmetics",
				"version": PACK_VERSION,
				"type": "pck",
				"url": "file://" + ProjectSettings.globalize_path(pck_path),
				"sha256": pck_sha,
				"min_native": "5.0.0",
				"priority": 400,
			},
			{
				"id": "config",
				# Muss NEUER sein als der eingebaute config-Pack (seit W16: 1.1.0).
				"version": "1.1.1",
				"type": "json",
				"url": "file://" + ProjectSettings.globalize_path(config_path),
				"sha256": UpdateService.sha256_of_file(config_path),
				"min_native": "5.0.0",
				"priority": 700,
			},
		],
	}
	var manifest_path := BASE_E2E + "/dist/manifest.json"
	_write_text(manifest_path, JSON.stringify(manifest, "\t"))
	# --- 3. Vorher-Stand: eingebaute Registry-Sicht (3 Cosmetics, v1.0.0).
	var registry := ContentRegistryService.new()
	registry.auto_reload = false
	registry.packs_dir = BASE_E2E + "/packs"
	registry.reload()
	# W6: der eingebaute Cosmetics-Katalog waechst (CONTENT-A: 92 Items) — der
	# Test misst deshalb die DIFFERENZ, nicht die absolute Groesse.
	var builtin_count := registry.get_cosmetics().size()
	assert_true(builtin_count > 0, "eingebaute Cosmetics vorhanden")
	assert_eq(registry.version_of("cosmetics"), "1.0.0", "eingebaute Version")
	assert_false(_has_item(registry, "hat_flamingo"), "neuer Inhalt noch NICHT da")
	print(
		(
			"[FLOW] vorher: cosmetics v%s, %d Items"
			% [registry.version_of("cosmetics"), registry.get_cosmetics().size()]
		)
	)
	# --- 4. „Suche nach Updates“: finden + laden + verifizieren + verbuchen.
	var service := UpdateService.new()
	service.packs_dir = BASE_E2E + "/packs"
	service.app_version = "5.0.0"
	service.manifest_url_override = "file://" + ProjectSettings.globalize_path(manifest_path)
	tree.root.add_child(service)
	var events: Array = []
	service.check_started.connect(func() -> void: events.append("started"))
	service.pack_downloaded.connect(
		func(pack_id: String, version: String) -> void:
			events.append("dl:%s@%s" % [pack_id, version])
	)
	var outcome: Dictionary = await service.check_for_updates()
	assert_eq(outcome["result"], UpdateService.Result.UPDATED, "Ergebnis: UPDATED")
	assert_eq(
		events, ["started", "dl:cosmetics@1.1.0", "dl:config@1.1.1"], "Signale in Prioritätsfolge"
	)
	assert_true(
		FileAccess.file_exists(BASE_E2E + "/packs/cosmetics-v%s.pck" % PACK_VERSION),
		"Pack liegt unter user://packs/<id>-v<version>.pck"
	)
	var installed := UpdatesManifest.read_installed(BASE_E2E + "/packs/installed.json")
	assert_eq(str(installed["packs"]["cosmetics"]["version"]), PACK_VERSION, "verbucht")
	assert_eq(str(installed["packs"]["cosmetics"]["sha256"]), pck_sha, "sha verbucht")
	print("[FLOW] Update gefunden+geladen: %s" % str(outcome["details"]["updated"]))
	# --- 5. config wirkt SOFORT (ohne Neustart) über das Registry-Overlay.
	registry.reload()
	assert_eq(str(registry.get_net_config()["host"]), "42.42.42.42", "Server-IP ohne IPA")
	assert_eq(int(registry.get_net_config()["port"]), 4242, "Port ohne IPA")
	# --- 6. „Neustart“: PackLoader mountet das Pack → Registry zeigt neuen Inhalt.
	var loader := PackLoaderService.new()
	loader.auto_boot = false
	loader.packs_dir = BASE_E2E + "/packs"
	loader.guard_path = BASE_E2E + "/boot_guard.json"
	loader.app_version = "5.0.0"
	var report := loader.load_packs_at_boot()
	assert_eq(report["loaded"], ["cosmetics"], "PCK geladen (config ist kein PCK)")
	registry.reload()
	assert_eq(registry.version_of("cosmetics"), PACK_VERSION, "Registry sieht Pack-Version")
	assert_eq(registry.get_cosmetics().size(), builtin_count + 1, "eingebaute + 1 neues Pack-Item")
	assert_true(_has_item(registry, "hat_flamingo"), "NEUER Inhalt nach Reload sichtbar")
	print(
		(
			"[FLOW] nachher: cosmetics v%s, %d Items, neu: hat_flamingo=%s"
			% [
				registry.version_of("cosmetics"),
				registry.get_cosmetics().size(),
				_has_item(registry, "hat_flamingo"),
			]
		)
	)
	# --- 7. Erfolgs-Boot: Guard genullt, Pack als bewährt markiert.
	loader.mark_boot_successful()
	assert_eq(BootGuard.open(BASE_E2E + "/boot_guard.json").attempts, 0, "Guard genullt")
	installed = UpdatesManifest.read_installed(BASE_E2E + "/packs/installed.json")
	assert_true(bool(installed["packs"]["cosmetics"]["survived_boot"]), "survived_boot")
	# --- 8. Zweiter Check gegen dasselbe Manifest: alles aktuell.
	var second: Dictionary = await service.check_for_updates()
	assert_eq(second["result"], UpdateService.Result.UP_TO_DATE, "2. Check: UP_TO_DATE")
	print("[FLOW] 2. Check: UP_TO_DATE ✓")
	loader.free()
	registry.free()
	service.queue_free()
	await wait_frames(1)
	# KEIN _wipe: das PCK ist gemountet; Aufräumen passiert beim nächsten Lauf.


func test_sha_mismatch_verwirft_download() -> void:
	_wipe(BASE_SHA)
	DirAccess.make_dir_recursive_absolute(BASE_SHA + "/dist")
	var pck_path := BASE_SHA + "/dist/cosmetics-v9.9.9.pck"
	_build_test_pack(BASE_SHA, pck_path)
	var manifest := {
		"schema": 1,
		"latest_native": "5.0.0",
		"packs":
		[
			{
				"id": "cosmetics",
				"version": "9.9.9",
				"url": "file://" + ProjectSettings.globalize_path(pck_path),
				"sha256": "deadbeef".repeat(8),
				"min_native": "5.0.0",
			}
		],
	}
	var manifest_path := BASE_SHA + "/dist/manifest.json"
	_write_text(manifest_path, JSON.stringify(manifest))
	var service := _make_service(BASE_SHA, manifest_path)
	var outcome: Dictionary = await service.check_for_updates()
	assert_eq(outcome["result"], UpdateService.Result.ERROR, "sha-Mismatch → ERROR")
	assert_false(
		FileAccess.file_exists(BASE_SHA + "/packs/cosmetics-v9.9.9.pck"),
		"verworfener Download landet NICHT in user://packs"
	)
	assert_false(
		UpdatesManifest.read_installed(BASE_SHA + "/packs/installed.json")["packs"].has(
			"cosmetics"
		),
		"nichts verbucht"
	)
	service.queue_free()
	await wait_frames(1)
	_wipe(BASE_SHA)


func test_min_native_gate_meldet_ipa() -> void:
	_wipe(BASE_GATE)
	DirAccess.make_dir_recursive_absolute(BASE_GATE + "/dist")
	var manifest := {
		"schema": 1,
		"latest_native": "5.0.0",
		"packs":
		[
			{
				"id": "cosmetics",
				"version": "9.9.9",
				"url": "https://example.org/nie-geladen.pck",
				"sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
				"min_native": "9.0.0",
			}
		],
	}
	var manifest_path := BASE_GATE + "/dist/manifest.json"
	_write_text(manifest_path, JSON.stringify(manifest))
	var service := _make_service(BASE_GATE, manifest_path)
	var outcome: Dictionary = await service.check_for_updates()
	assert_eq(outcome["result"], UpdateService.Result.NEEDS_NATIVE, "Gate → NEEDS_NATIVE")
	assert_eq(outcome["details"]["gated"], ["cosmetics"], "Pack als gated gemeldet, NIE geladen")
	service.queue_free()
	await wait_frames(1)
	_wipe(BASE_GATE)


func test_manifest_fehler_ist_offline_first() -> void:
	var service := _make_service(BASE_GATE, BASE_GATE + "/gibt/es/nicht/manifest.json")
	var outcome: Dictionary = await service.check_for_updates()
	assert_eq(outcome["result"], UpdateService.Result.ERROR, "fehlendes Manifest → ERROR")
	assert_false(outcome["details"]["errors"].is_empty(), "Fehlertext vorhanden")
	service.queue_free()
	await wait_frames(1)


func test_glue_toast_keys() -> void:
	var keys := SettingsUpdateGlue.result_text_keys(UpdateService.Result.UP_TO_DATE, {})
	assert_eq(keys, ["updates.alles_aktuell"], "„Alles aktuell!“")
	keys = SettingsUpdateGlue.result_text_keys(UpdateService.Result.UPDATED, {})
	assert_eq(keys, ["updates.update_geladen"], "„Update geladen — Neustart lädt Inhalte“")
	keys = SettingsUpdateGlue.result_text_keys(
		UpdateService.Result.UPDATED, {"native_update": true}
	)
	assert_eq(
		keys, ["updates.update_geladen", "updates.braucht_ipa"], "Update + IPA-Hinweis zusammen"
	)
	keys = SettingsUpdateGlue.result_text_keys(UpdateService.Result.NEEDS_NATIVE, {})
	assert_eq(keys, ["updates.braucht_ipa"], "„Neue App-Version nötig — bitte neue IPA …“")
	keys = SettingsUpdateGlue.result_text_keys(UpdateService.Result.ERROR, {})
	assert_eq(keys, ["updates.fehler"], "Fehler-Toast")
	assert_eq(I18nService.t("updates.alles_aktuell"), "Alles aktuell!", "DE-String vorhanden")


func test_updates_strings_paritaet() -> void:
	var de_keys := _prefixed_keys(I18nService.table("de"))
	var en_keys := _prefixed_keys(I18nService.table("en"))
	assert_true(de_keys.size() >= 8, "updates.*-Domain gefüllt")
	assert_eq(de_keys, en_keys, "DE/EN-Parität für updates.* (strings/OWNERSHIP.md)")


func _prefixed_keys(table: Dictionary) -> Array:
	var keys := table.keys().filter(func(key): return str(key).begins_with("updates."))
	keys.sort()
	return keys


## Baut das Test-Pack: überschattet res://content/cosmetics/ mit v1.1.0 und
## einem vierten Item (hat_flamingo) — Packs liefern immer den KOMPLETTEN Katalog.
func _build_test_pack(base: String, pck_path: String) -> void:
	var src_dir := base + "/src"
	var meta := {
		"schema": 1,
		"id": "cosmetics",
		"version": PACK_VERSION,
		"priority": 400,
		"min_native": "5.0.0",
		"domains": ["cosmetics"],
	}
	var json := JSON.new()
	json.parse(FileAccess.get_file_as_string("res://content/cosmetics/data/cosmetics.json"))
	var catalog: Dictionary = json.data
	(
		catalog["items"]
		. append(
			{
				"id": "hat_flamingo",
				"type": "hat",
				"name_de": "Flamingo-Hut",
				"price": 480,
				"rarity": "epic",
				"asset": "",
			}
		)
	)
	_write_text(src_dir + "/pack.json", JSON.stringify(meta, "\t"))
	_write_text(src_dir + "/cosmetics.json", JSON.stringify(catalog, "\t"))
	var packer := PCKPacker.new()
	assert_eq(packer.pck_start(pck_path), OK, "PCKPacker.pck_start")
	packer.add_file("res://content/cosmetics/pack.json", src_dir + "/pack.json")
	packer.add_file("res://content/cosmetics/data/cosmetics.json", src_dir + "/cosmetics.json")
	assert_eq(packer.flush(), OK, "PCKPacker.flush")


func _make_service(base: String, manifest_path: String) -> UpdateService:
	var service := UpdateService.new()
	service.packs_dir = base + "/packs"
	service.app_version = "5.0.0"
	service.manifest_url_override = "file://" + ProjectSettings.globalize_path(manifest_path)
	tree.root.add_child(service)
	return service


func _has_item(registry: ContentRegistryService, item_id: String) -> bool:
	for item: Dictionary in registry.get_cosmetics():
		if str(item.get("id", "")) == item_id:
			return true
	return false


func _write_text(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
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
