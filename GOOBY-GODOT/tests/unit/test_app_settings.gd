extends TestCase
## Settings-Roundtrip-Tests (W1a) — AppSettings ist GameState-unabhängig und
## komplett headless testbar (eigener user://-Testpfad pro Test).

const SETTINGS_SCRIPT := preload("res://scripts/core/app_settings.gd")


func test_defaults() -> void:
	var path := _temp_path()
	var settings: Node = SETTINGS_SCRIPT.new(path)
	assert_eq(settings.language(), "de", "Sprache muss default 'de' sein.")
	assert_false(settings.is_reduced_motion())
	assert_true(settings.are_doors_animated())
	assert_eq(settings.orientation_mode(), "auto")
	assert_almost(settings.audio_level("master"), 1.0)
	assert_almost(settings.audio_level("music"), 1.0)
	assert_almost(settings.audio_level("sfx"), 1.0)
	settings.free()
	_remove(path)


func test_roundtrip_save_and_load() -> void:
	var path := _temp_path()
	var first: Node = SETTINGS_SCRIPT.new(path)
	first.set_setting("reduced_motion", true)
	first.set_setting("doors_animated", false)
	first.set_setting("orientation_mode", "landscape")
	first.set_setting("audio.music", 0.25)
	first.free()

	var second: Node = SETTINGS_SCRIPT.new(path)
	assert_true(second.is_reduced_motion(), "reduced_motion ging verloren.")
	assert_false(second.are_doors_animated(), "doors_animated ging verloren.")
	assert_eq(second.orientation_mode(), "landscape")
	assert_almost(second.audio_level("music"), 0.25)
	assert_almost(second.audio_level("sfx"), 1.0, 1e-6, "Nicht gesetzte Busse = Default.")
	assert_eq(second.language(), "de", "Sprache bleibt de.")
	second.free()
	_remove(path)


func test_corrupt_file_falls_back_to_defaults() -> void:
	var path := _temp_path()
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string("{ kaputt !!")
	file.close()
	var settings: Node = SETTINGS_SCRIPT.new(path)
	assert_eq(settings.language(), "de")
	assert_true(settings.are_doors_animated())
	settings.free()
	_remove(path)


func test_setting_changed_signal() -> void:
	var path := _temp_path()
	var settings: Node = SETTINGS_SCRIPT.new(path)
	var events: Array = []
	var on_changed := func(key: String, value: Variant) -> void: events.append([key, value])
	settings.setting_changed.connect(on_changed)
	settings.set_setting("audio.sfx", 0.5)
	assert_eq(events, [["audio.sfx", 0.5]] as Array)
	settings.free()
	_remove(path)


func test_invalid_orientation_mode_normalizes_to_auto() -> void:
	var path := _temp_path()
	var settings: Node = SETTINGS_SCRIPT.new(path)
	settings.set_setting("orientation_mode", "diagonal")
	assert_eq(settings.orientation_mode(), "auto")
	settings.free()
	_remove(path)


func _temp_path() -> String:
	return "user://test_settings_%d.json" % Time.get_ticks_usec()


func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
