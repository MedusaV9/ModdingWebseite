extends TestCase
## FB-6/CI: Regressions-Wachen für die Build-Härtung. Diese Tests machen
## rot, wenn jemand die Maßnahmen zurückdreht, die die CI-Dauerbrenner
## verhindert haben (Preflight, Preset-abgeleitete IPA-Verifikation,
## Import-bis-vollständig-Schleife im Linux-Job).


## Die CI-Dateien liegen AUSSERHALB des Godot-Projekts (Repo-Wurzel) —
## res:// kennt kein "..", darum über den globalisierten Projektpfad.
func _repo(rel: String) -> String:
	return ProjectSettings.globalize_path("res://").path_join("..").path_join(rel)


func _read(rel: String) -> String:
	var path := _repo(rel)
	if not FileAccess.file_exists(path):
		fail_test("Datei fehlt: %s" % path)
		return ""
	return FileAccess.get_file_as_string(path)


func test_preflight_prueft_alles_was_die_ci_prueft() -> void:
	var text := _read("tools/ci/preflight.sh")
	assert_true(text.contains("gdformat --check"), "Preflight: Format-Check")
	assert_true(text.contains("gdlint"), "Preflight: Lint")
	assert_true(text.contains("check_imports.py"), "Preflight: Import-Vollständigkeit")
	assert_true(text.contains("tests/run_tests.gd"), "Preflight: Haupt-Runner")
	assert_true(text.contains("run_w1c_tests.gd"), "Preflight: W1c-Runner")
	assert_true(text.contains("git ls-files"), "Preflight: exakt die CI-Dateiliste")
	# LF-Zeilenenden — CRLF bricht bash (der Fehler ist kryptisch).
	assert_false(text.contains("\r"), "Preflight hat LF-Zeilenenden")


func test_verify_ipa_leitet_erwartungen_aus_preset_ab() -> void:
	var text := _read("tools/ci/verify_ipa.py")
	# DER Dauerbrenner: hartkodierte Orientierungs-Erwartungen brachen, als
	# das Preset umgestellt wurde. Jetzt liest das Skript export_presets.cfg.
	assert_true(text.contains("export_presets.cfg"), "liest das Preset")
	assert_true(text.contains("orientation/"), "leitet Orientierungen ab")
	assert_true(text.contains("application/bundle_identifier"), "leitet Bundle-Id ab")
	assert_true(text.contains("min_ios_version"), "leitet Min-iOS ab")
	# Erfolgs-Ausgabe auf einen Blick (.ipa gebaut: X MB, Y Dateien im PCK).
	assert_true(text.contains("ipa gebaut"), "Erfolgszeile vorhanden")
	assert_false(text.contains("\r"), "verify_ipa hat LF-Zeilenenden")


func test_workflow_importiert_bis_vollstaendig() -> void:
	var text := _read(".github/workflows/gooby-godot.yml")
	assert_true(text.contains("check_imports.py"), "Workflow nutzt den Import-Check")
	assert_true(text.contains("verify_ipa.py"), "iOS-Job nutzt das externe Verify-Skript")
	# Beide Jobs (linux + ios) müssen die Import-Schleife fahren — ein
	# einzelner --import-Durchlauf lässt Ressourcen offen (Dauerbrenner c).
	assert_eq(text.count("Import-Durchlauf"), 2, "Import-Schleife in beiden Jobs")


func test_check_imports_existiert() -> void:
	assert_true(
		FileAccess.file_exists(_repo("tools/ci/check_imports.py")), "check_imports.py vorhanden"
	)


func test_soul_pack_registriert() -> void:
	# Content-Pack der Seele: pack.json lesbar, Domain "soul" deklariert.
	var raw := FileAccess.get_file_as_string("res://content/soul/pack.json")
	var meta: Variant = JSON.parse_string(raw)
	assert_true(meta is Dictionary, "pack.json lesbar")
	assert_eq(str(meta.get("id", "")), "soul", "Pack-Id")
	assert_true(meta.get("domains", []).has("soul"), "Domain soul deklariert")
