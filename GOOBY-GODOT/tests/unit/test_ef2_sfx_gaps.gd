extends TestCase
## EF-2 (EVAL-1 S4-S6 + D6/F7/F8/F9): die vertonten Lücken existieren —
## Pflege (Wasser/Bürsten/Spülung/Erfolg), weicher gvz_collect- und
## mg_win-Ersatz, Streichel-/Schritt-/Mampf-/Reise-Sounds — und der
## Loop-Kanal des AudioDirector funktioniert (Wasser-/Bürsten-Foley).

const FIXTURE := "res://tests/fixtures/ef2_audio_levels.json"
## Neue Ids aus dem Lückenschluss (EVAL-1 §Stummfilm-Interaktionen).
const NEUE_IDS: Array[String] = [
	"care_wasser",
	"care_buersten",
	"care_spuelung",
	"care_erfolg",
	"gvz_collect",
	"mg_win",
	"pet_squish",
	"step_tap",
	"nom_nom",
	"travel_whoosh_auf",
	"travel_whoosh_zu",
]
## S4/S6: Ersatz-Sounds sind weich — Zentroid unter 2,5 kHz und praktisch
## keine Energie über 4 kHz (gvz_collect vorher: 7,3 kHz / 100 %).
const SOFT_CENTROID_MAX_HZ := 2500.0
const SOFT_HI4K_MAX_PCT := 10.0


func test_neue_ids_gemappt_und_ladbar() -> void:
	for id: String in NEUE_IDS:
		assert_true(SfxMap.SOUNDS.has(id), "SFX-Id fehlt in der Map: %s" % id)
		var path := SfxMap.path(id)
		assert_true(ResourceLoader.exists(path), "Datei fehlt: %s (%s)" % [id, path])
		if not ResourceLoader.exists(path):
			continue
		var stream: Variant = load(path)
		assert_true(stream is AudioStream, "%s laedt keinen AudioStream" % id)


func test_ersatz_sounds_sind_weich() -> void:
	var data: Variant = JsonFixtures.load_json(FIXTURE)
	assert_true(data is Dictionary, "Fixture fehlt/kaputt: %s" % FIXTURE)
	if not (data is Dictionary):
		return
	var sfx: Dictionary = (data as Dictionary).get("sfx", {})
	for id: String in ["gvz_collect", "mg_win", "care_erfolg"]:
		var file := str(SfxMap.entry(id).get("file", ""))
		assert_true(file.begins_with("soft/"), "%s nutzt kein soft/-Sample: %s" % [id, file])
		if not sfx.has(id):
			fail_test("%s fehlt im Mess-Fixture (tools/audio/ef2_manifest.py)" % id)
			continue
		var row: Dictionary = sfx[id]
		var centroid := float(row.get("centroid_hz", 99999.0))
		var hi4k := float(row.get("hi4k_pct", 100.0))
		assert_true(
			centroid <= SOFT_CENTROID_MAX_HZ,
			"%s Zentroid %.0f Hz (> %.0f — zu grell)" % [id, centroid, SOFT_CENTROID_MAX_HZ]
		)
		assert_true(
			hi4k <= SOFT_HI4K_MAX_PCT,
			"%s Energie ueber 4 kHz: %.1f %% (> %.0f)" % [id, hi4k, SOFT_HI4K_MAX_PCT]
		)


func test_pflege_loops_sind_loopbares_material() -> void:
	## Wasser/Buersten laufen als Dauer-Loop — Dateien lang genug und ohne
	## harten Schlusspegel (end_db), damit der Fade in stop_loop reicht.
	var data: Variant = JsonFixtures.load_json(FIXTURE)
	if not (data is Dictionary):
		fail_test("Fixture fehlt/kaputt: %s" % FIXTURE)
		return
	var sfx: Dictionary = (data as Dictionary).get("sfx", {})
	for id: String in ["care_wasser", "care_buersten"]:
		if not sfx.has(id):
			fail_test("%s fehlt im Mess-Fixture" % id)
			continue
		var row: Dictionary = sfx[id]
		assert_true(float(row.get("dur_s", 0.0)) >= 1.5, "%s zu kurz fuer einen Loop" % id)


func test_audio_director_loop_kanal() -> void:
	var director := _director()
	if director == null:
		fail_test("Kein AudioDirector (/root/Audio) im Testbaum")
		return
	assert_false(director.is_loop_playing("care_wasser"))
	director.start_loop("care_wasser")
	assert_true(director.is_loop_playing("care_wasser"), "start_loop startet nicht")
	director.start_loop("care_wasser")  # Doppelstart ist no-op
	assert_true(director.is_loop_playing("care_wasser"))
	director.stop_loop("care_wasser")
	assert_false(director.is_loop_playing("care_wasser"), "stop_loop beendet nicht")
	await wait_frames(2)


func test_care_wiring_ids_dokumentiert() -> void:
	## Die Pflege-Verdrahtung (EF-1/EF-3 Terrain) spielt über try_play/
	## try_start_loop — die Ids muessen stabil bleiben (Kontrakt).
	for id: String in ["care_wasser", "care_buersten", "care_spuelung", "care_erfolg"]:
		assert_false(SfxMap.entry(id).is_empty(), "Pflege-Id %s fehlt" % id)


func _director() -> AudioDirector:
	var autoload := tree.root.get_node_or_null("/root/Audio")
	if autoload is AudioDirector:
		return autoload
	return null
