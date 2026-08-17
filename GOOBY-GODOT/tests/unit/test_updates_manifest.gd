extends TestCase
## W2b UPDATES — manifest.gd: semver, Parser/Validator, Vergleichslogik,
## min_native-Gate, installed.json-Roundtrip. Alles ohne echtes res://content
## (injizierte Temp-Roots), damit der Flow-Test (Pack-Override) uns nicht stört.

const BASE := "user://w2b_manifest_test"


func test_semver_parse() -> void:
	assert_eq(Array(UpdatesManifest.parse_semver("1.2.3")), [1, 2, 3], "einfaches semver")
	assert_eq(Array(UpdatesManifest.parse_semver("v5.0.0")), [5, 0, 0], "v-Präfix erlaubt")
	assert_eq(Array(UpdatesManifest.parse_semver("1.2.3-beta.1")), [1, 2, 3], "prerelease-Suffix")
	assert_true(UpdatesManifest.parse_semver("1.2").is_empty(), "zwei Teile = ungültig")
	assert_true(UpdatesManifest.parse_semver("1.2.x").is_empty(), "Buchstaben = ungültig")
	assert_true(UpdatesManifest.parse_semver("").is_empty(), "leer = ungültig")
	assert_true(UpdatesManifest.parse_semver(null).is_empty(), "null = ungültig")
	assert_true(UpdatesManifest.parse_semver("1.-2.3").is_empty(), "negativ = ungültig")
	assert_false(UpdatesManifest.is_semver("1.2.3.4"), "vier Teile = ungültig")


func test_semver_compare() -> void:
	assert_eq(UpdatesManifest.compare_semver("1.2.3", "1.2.3"), 0, "gleich")
	assert_eq(UpdatesManifest.compare_semver("1.2.3", "1.2.4"), -1, "patch kleiner")
	assert_eq(UpdatesManifest.compare_semver("1.10.0", "1.9.9"), 1, "minor numerisch")
	assert_eq(UpdatesManifest.compare_semver("2.0.0", "1.99.99"), 1, "major gewinnt")
	assert_eq(UpdatesManifest.compare_semver("1.2.3-beta", "1.2.3"), -1, "prerelease < release")
	assert_true(UpdatesManifest.semver_gt("5.1.0", "5.0.0"), "semver_gt")
	assert_true(UpdatesManifest.semver_lte("5.0.0", "5.0.0"), "semver_lte bei Gleichheit")
	assert_eq(UpdatesManifest.compare_semver("kaputt", "0.0.0"), 0, "ungültig zählt als 0.0.0")


func test_manifest_parse_ok() -> void:
	var parsed := UpdatesManifest.parse(JSON.stringify(_valid_manifest()))
	assert_true(parsed["ok"], "valides Manifest parst: %s" % parsed["error"])
	var manifest: Dictionary = parsed["manifest"]
	assert_eq(str(manifest["latest_native"]), "5.1.0", "latest_native übernommen")
	assert_eq((manifest["packs"] as Array).size(), 2, "beide Packs da")


func test_manifest_parse_fehler() -> void:
	assert_false(UpdatesManifest.parse("{kaputt")["ok"], "kaputtes JSON")
	assert_false(UpdatesManifest.parse("[1,2]")["ok"], "kein Objekt")
	var wrong_schema := _valid_manifest()
	wrong_schema["schema"] = 99
	assert_false(UpdatesManifest.parse(JSON.stringify(wrong_schema))["ok"], "falsches Schema")
	var bad_native := _valid_manifest()
	bad_native["latest_native"] = "neueste"
	assert_false(
		UpdatesManifest.parse(JSON.stringify(bad_native))["ok"], "latest_native kein semver"
	)
	var missing_field := _valid_manifest()
	(missing_field["packs"][0] as Dictionary).erase("sha256")
	assert_false(UpdatesManifest.parse(JSON.stringify(missing_field))["ok"], "sha256 fehlt")
	var bad_sha := _valid_manifest()
	bad_sha["packs"][0]["sha256"] = "zu-kurz"
	assert_false(UpdatesManifest.parse(JSON.stringify(bad_sha))["ok"], "sha256 kein 64er-Hex")
	var dup := _valid_manifest()
	dup["packs"].append(dup["packs"][0])
	assert_false(UpdatesManifest.parse(JSON.stringify(dup))["ok"], "doppelte Pack-Id")


func test_effective_version_und_priority() -> void:
	var installed := {
		"schema": 1,
		"packs":
		{
			"cosmetics": {"version": "1.4.0", "enabled": true},
			"codes": {"version": "3.0.0", "enabled": false},
		},
	}
	var builtin := {"cosmetics": "1.2.0", "codes": "2.0.0", "balance": "1.0.0"}
	assert_eq(
		UpdatesManifest.effective_version("cosmetics", installed, builtin),
		"1.4.0",
		"user-Version gewinnt wenn enabled + größer"
	)
	assert_eq(
		UpdatesManifest.effective_version("codes", installed, builtin),
		"2.0.0",
		"disabled user-Pack zählt nicht"
	)
	assert_eq(
		UpdatesManifest.effective_version("balance", installed, builtin), "1.0.0", "nur eingebaut"
	)
	assert_eq(UpdatesManifest.priority_of({"id": "balance"}), 200, "Default-Priorität")
	assert_eq(UpdatesManifest.priority_of({"id": "x", "priority": 42}), 42, "Manifest gewinnt")
	assert_eq(UpdatesManifest.priority_of({"id": "unbekannt"}), 900, "Fallback 900")


func test_plan_updates_gate_und_sortierung() -> void:
	var manifest := {
		"schema": 1,
		"latest_native": "5.1.0",
		"packs":
		[
			_pack_entry("stickers", "2.0.0", "5.0.0"),
			_pack_entry("cosmetics", "1.4.0", "5.0.0"),
			_pack_entry("codes", "2.0.0", "5.1.0"),
			_pack_entry("balance", "1.0.0", "5.0.0"),
		],
	}
	var installed := {"schema": 1, "packs": {}}
	var builtin := {"cosmetics": "1.0.0", "codes": "1.0.0", "stickers": "1.0.0", "balance": "1.0.0"}
	var plan := UpdatesManifest.plan_updates(manifest, installed, builtin, "5.0.0")
	assert_true(plan["native_update"], "5.1.0 > 5.0.0 → Native-Update-Banner")
	var ids: Array = plan["to_install"].map(func(entry): return entry["id"])
	assert_eq(ids, ["cosmetics", "stickers"], "balance aktuell; codes gated; Prioritäts-Sortierung")
	var gated_ids: Array = plan["gated"].map(func(entry): return entry["id"])
	assert_eq(gated_ids, ["codes"], "min_native 5.1.0 > App 5.0.0 → gated, NIE laden")
	assert_false(plan["up_to_date"], "nicht up_to_date")
	var all_current := UpdatesManifest.plan_updates(
		{"schema": 1, "latest_native": "5.0.0", "packs": []}, installed, builtin, "5.0.0"
	)
	assert_true(all_current["up_to_date"], "leeres Manifest + gleiche Native = up_to_date")


func test_installed_json_roundtrip() -> void:
	_wipe(BASE)
	var path := BASE + "/packs/installed.json"
	var fresh := UpdatesManifest.read_installed(path)
	assert_eq(fresh["packs"], {}, "fehlende Datei → leerer Stand")
	fresh["packs"]["cosmetics"] = {"version": "1.4.0", "enabled": true}
	assert_true(UpdatesManifest.write_installed(path, fresh), "write ok")
	var reread := UpdatesManifest.read_installed(path)
	assert_eq(str(reread["packs"]["cosmetics"]["version"]), "1.4.0", "Roundtrip")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{kaputt")
	file.close()
	assert_eq(UpdatesManifest.read_installed(path)["packs"], {}, "kaputte Datei → leerer Stand")
	_wipe(BASE)


func test_builtin_versions_aus_content_root() -> void:
	_wipe(BASE)
	var root := BASE + "/content"
	_write_json(root + "/alpha/pack.json", {"id": "alpha", "version": "1.2.3"})
	_write_json(root + "/beta/pack.json", {"id": "beta", "version": "0.9.0"})
	DirAccess.make_dir_recursive_absolute(root + "/base")  # Ordner OHNE pack.json (W2a)
	var versions := UpdatesManifest.read_builtin_versions(root)
	assert_eq(versions, {"alpha": "1.2.3", "beta": "0.9.0"}, "nur Ordner mit pack.json zählen")
	_wipe(BASE)


func _valid_manifest() -> Dictionary:
	return {
		"schema": 1,
		"latest_native": "5.1.0",
		"notes_de": "Testnotizen",
		"packs":
		[
			_pack_entry("cosmetics", "1.4.0", "5.0.0"),
			_pack_entry("codes", "2.0.1", "5.0.0"),
		],
	}


func _pack_entry(pack_id: String, version: String, min_native: String) -> Dictionary:
	return {
		"id": pack_id,
		"version": version,
		"url": "https://example.org/%s-v%s.pck" % [pack_id, version],
		"sha256": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
		"min_native": min_native,
		"priority": UpdatesManifest.DEFAULT_PRIORITIES.get(pack_id, 900),
	}


func _write_json(path: String, data: Dictionary) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify(data, "\t"))
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
