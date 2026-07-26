extends TestCase
## FIX-4: SfxMap — die neue weiche UI-Familie ist vollständig (jede
## Pflicht-Id gemappt), alle Dateien existieren, UI-Sounds kommen aus den
## generierten soft/-Samples (User-Meldung 2: „grauenhafte" Sounds ersetzt).


func test_ui_pflicht_ids_vollstaendig() -> void:
	for id: String in SfxMap.UI_REQUIRED_IDS:
		assert_true(SfxMap.SOUNDS.has(id), "UI-Sound-Id fehlt in der Map: %s" % id)


func test_alle_sound_dateien_existieren() -> void:
	for id: String in SfxMap.ids():
		var path := SfxMap.path(id)
		assert_true(ResourceLoader.exists(path), "Sound-Datei fehlt: %s (%s)" % [id, path])


func test_ui_familie_nutzt_weiche_soft_samples() -> void:
	for id: String in SfxMap.UI_REQUIRED_IDS:
		var file := str(SfxMap.entry(id).get("file", ""))
		assert_true(
			file.begins_with("soft/"),
			"UI-Sound %s nutzt kein weiches soft/-Sample: %s" % [id, file]
		)


func test_lautstaerken_moderat() -> void:
	for id: String in SfxMap.ids():
		var db := float(SfxMap.entry(id).get("volume_db", 0.0))
		assert_true(db > -24.0 and db <= 0.0, "volume_db absurd: %s = %f" % [id, db])


func test_unbekannte_id_ist_leer() -> void:
	assert_eq(SfxMap.path("gibt_es_nicht"), "")
	assert_true(SfxMap.entry("gibt_es_nicht").is_empty())
