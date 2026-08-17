extends TestCase
## CI-WATCH regression guards: first-run UI must not depend on a developer's
## persisted user://settings.json, and a red Linux test must not suppress the
## only installable iOS test artifact.


func _repo(rel: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").path_join(rel)


func _read(rel: String) -> String:
	var path := _repo(rel)
	assert_true(FileAccess.file_exists(path), "CI-Datei vorhanden: %s" % rel)
	return FileAccess.get_file_as_string(path)


func test_test_runner_uses_fresh_godot_user_data() -> void:
	var helper := _read("tools/ci/run_godot_isolated.sh")
	for variable in ["HOME", "XDG_DATA_HOME", "XDG_CONFIG_HOME", "XDG_CACHE_HOME"]:
		assert_true(helper.contains("export %s=" % variable), "%s wird isoliert" % variable)

	var preflight := _read("tools/ci/preflight.sh")
	assert_eq(
		preflight.count('bash "$ISOLATED_GODOT"'), 3, "Preflight isoliert beide Runner + Boot"
	)

	var workflow := _read(".github/workflows/gooby-godot.yml")
	assert_eq(
		workflow.count("bash tools/ci/run_godot_isolated.sh"),
		3,
		"CI isoliert beide Runner + Boot",
	)


func test_isolated_process_maps_user_dir_into_fresh_root() -> void:
	# Direkte Entwickleraufrufe bleiben erlaubt. In GitHub Actions muss der
	# Marker dagegen gesetzt sein; dadurch macht ein Rückbau des Wrappers rot.
	var in_actions := OS.get_environment("GITHUB_ACTIONS") == "true"
	var isolated := OS.get_environment("CIWATCH_ISOLATED_USER_DATA") == "1"
	if not in_actions and not isolated:
		return
	assert_true(isolated, "GitHub-Testlauf nutzt den Isolations-Wrapper")
	var root := OS.get_environment("CIWATCH_USER_DATA_ROOT")
	var user_dir := ProjectSettings.globalize_path("user://")
	assert_true(not root.is_empty(), "Isolationswurzel ist bekannt")
	assert_true(
		user_dir.begins_with(root.path_join("xdg-data")),
		"user:// liegt unter der frischen XDG_DATA_HOME (%s)" % user_dir,
	)


func test_ios_build_is_not_suppressed_by_failed_linux_tests() -> void:
	var workflow := _read(".github/workflows/gooby-godot.yml")
	assert_true(
		workflow.contains("always() && needs.linux-checks.result != 'cancelled'"),
		"iOS-Job läuft nach roten Linux-Tests weiter",
	)
	assert_true(
		workflow.contains("GOOBY-godot-unsigned-ipa-UNVERIFIED-linux-"),
		"Artefakt aus rotem Test-Vorlauf ist klar gekennzeichnet",
	)
	assert_true(
		workflow.contains("name: GOOBY-godot-unsigned-ipa\n"),
		"Grüner Vorlauf behält den stabilen Artefaktnamen",
	)
