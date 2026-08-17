extends TestCase
## RW-7 — AppSettings Schema v2: Defaults, Normalisierung (value_of/is_on),
## Persistenz-Roundtrip und Migration alter (v1-)Dateien ohne die neuen
## Gruppen. Settings liegen bewusst NICHT im Spielstand (kein Save-Bump).

const AppSettingsScript := preload("res://scripts/core/app_settings.gd")

var _seq := 0


func _fresh_path() -> String:
	_seq += 1
	var dir := "user://rw7_tests/settings_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	return dir + "/settings.json"


func test_v2_defaults() -> void:
	var s: Node = AppSettingsScript.new(_fresh_path())
	assert_eq(s.value_of("graphics.preset"), "auto", "Default-Profil = Auto")
	assert_eq(s.value_of("graphics.fps"), 60.0)
	assert_eq(s.value_of("graphics.msaa"), "2x")
	assert_eq(s.value_of("display.ui_scale"), 1.0)
	assert_eq(s.value_of("controls.handedness"), "rechts")
	assert_eq(s.value_of("accessibility.color_vision"), "aus")
	assert_true(s.is_on("notifications.enabled"))
	assert_true(s.is_on("notifications.quiet_hours"))
	assert_eq(s.value_of("notifications.quiet_from"), 21.0)
	assert_eq(s.value_of("notifications.quiet_to"), 8.0)
	assert_true(s.is_on("game.autosave"))
	assert_false(s.is_dev_enabled())
	assert_almost(s.audio_level("voice"), 1.0, 1e-6, "audio.voice ergaenzt")
	s.free()


func test_normalisierung_beim_lesen() -> void:
	var s: Node = AppSettingsScript.new(_fresh_path())
	s.set_setting("graphics.msaa", "8x")
	assert_eq(s.value_of("graphics.msaa"), "2x", "unbekannter Enum-Wert faellt auf Default")
	s.set_setting("graphics.scale_3d", 9.0)
	assert_eq(s.value_of("graphics.scale_3d"), 1.0, "Range-Werte werden geklemmt")
	s.set_setting("graphics.scale_3d", 0.1)
	assert_eq(s.value_of("graphics.scale_3d"), 0.5)
	s.set_setting("graphics.fps", 45)
	assert_eq(s.value_of("graphics.fps"), 30.0, "FPS rundet auf erlaubte Stufe (30/60/120)")
	s.set_setting("graphics.fps", 100)
	assert_eq(s.value_of("graphics.fps"), 120.0)
	s.set_setting("display.ui_scale", "kaputt")
	assert_eq(s.value_of("display.ui_scale"), 1.0, "Nicht-Zahl faellt auf Default")
	s.free()


func test_persistenz_roundtrip() -> void:
	var path := _fresh_path()
	var s: Node = AppSettingsScript.new(path)
	s.set_setting("graphics.preset", "niedrig")
	s.set_setting("display.text_scale", 1.3)
	s.set_setting("notifications.pflege", false)
	s.set_setting("controls.haptics", "stark")
	s.free()
	var s2: Node = AppSettingsScript.new(path)
	assert_eq(s2.value_of("graphics.preset"), "niedrig", "Preset ueberlebt Neustart")
	assert_eq(s2.value_of("display.text_scale"), 1.3)
	assert_false(s2.is_on("notifications.pflege"))
	assert_eq(s2.value_of("controls.haptics"), "stark")
	s2.free()


func test_v1_datei_bekommt_v2_gruppen() -> void:
	var path := _fresh_path()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(
		JSON.stringify({"language": "en", "reduced_motion": true, "audio": {"music": 0.5}})
	)
	file.close()
	var s: Node = AppSettingsScript.new(path)
	assert_eq(s.language(), "en", "alte Werte bleiben")
	assert_true(s.is_reduced_motion())
	assert_almost(s.audio_level("music"), 0.5, 1e-6)
	assert_almost(s.audio_level("master"), 1.0, 1e-6, "fehlende audio-Unterkeys = Default")
	assert_eq(s.value_of("graphics.preset"), "auto", "neue Gruppen kommen als Defaults dazu")
	assert_true(s.is_on("notifications.enabled"))
	s.free()


func test_notify_gate_master_und_kategorie() -> void:
	var s: Node = AppSettingsScript.new(_fresh_path())
	assert_true(s.notify_allowed("pflege"), "Default: alles erlaubt")
	s.set_setting("notifications.pflege", false)
	assert_false(s.notify_allowed("pflege"), "Kategorie-Gate")
	assert_true(s.notify_allowed("warte"), "andere Kategorien unabhaengig")
	s.set_setting("notifications.enabled", false)
	assert_false(s.notify_allowed("warte"), "Master-Gate schlaegt alles")
	s.free()


func test_unbekannter_value_of_key_ist_null() -> void:
	var s: Node = AppSettingsScript.new(_fresh_path())
	assert_eq(s.value_of("gibt.es.nicht"), null, "Tippfehler-Schutz")
	s.free()
