extends TestCase
## EF-2 (EVAL-1 S1/S2): Pegel-Kontrakt für Musik + SFX gegen das Mess-Fixture
## tests/fixtures/ef2_audio_levels.json (erzeugt von tools/audio/
## ef2_manifest.py — EVAL1-Metrik: gated 400-ms-RMS dBFS @48k mono).
## Nach JEDER Audio-Änderung (Datei, gain_trim, volume_db, neue Ids) das
## Fixture neu erzeugen: `python3 tools/audio/ef2_manifest.py` — sonst
## schlagen die sha256-Drift-Tests hier absichtlich an.

const FIXTURE := "res://tests/fixtures/ef2_audio_levels.json"
const REGEN_HINWEIS := "Fixture neu erzeugen: python3 tools/audio/ef2_manifest.py"
## DoD S1: kein Track peakt nach Trim über −1 dBFS (Werte im Fixture sind
## auf 0,1 dB gerundet, daher minimale Toleranz).
const MAX_EFF_PEAK_DB := -0.95
## Beds untereinander gleich laut: −20 dBFS gemastert (EVAL1-Metrik −17);
## Ranch-Dateien sind fremd und nur per gain_trim gedeckelt → weichere Spanne.
const BED_EFF_LOUD_MIN := -21.0
const BED_EFF_LOUD_MAX := -16.5
## Sollspanne AC-Verhältnis (EVAL-1 §S1): Musik-Playback (Datei-Loudness +
## Music-Bus-Offset) liegt 6–10 dB UNTER dem SFX-Median.
const RATIO_MIN_DB := 6.0
const RATIO_MAX_DB := 10.0
## S2: Naht am Loop-Punkt (Dateiende → loop_offset) hörbar glatt.
const MAX_SEAM_LOOP_DB := 8.0

var _manifest: Dictionary = {}


func _fixture() -> Dictionary:
	if _manifest.is_empty():
		var data: Variant = JsonFixtures.load_json(FIXTURE)
		if data is Dictionary:
			_manifest = data
	return _manifest


func test_fixture_vorhanden_und_vollstaendig() -> void:
	var manifest := _fixture()
	assert_false(manifest.is_empty(), "Fixture fehlt/kaputt: %s" % FIXTURE)
	if manifest.is_empty():
		return
	var music: Dictionary = manifest.get("music", {})
	var sfx: Dictionary = manifest.get("sfx", {})
	for track_id: String in MusicRegistry.ids():
		assert_true(
			music.has(track_id), "Track %s fehlt im Mess-Fixture. %s" % [track_id, REGEN_HINWEIS]
		)
	for sfx_id: String in SfxMap.ids():
		assert_true(
			sfx.has(sfx_id), "SFX-Id %s fehlt im Mess-Fixture. %s" % [sfx_id, REGEN_HINWEIS]
		)


func test_audio_dateien_ohne_drift() -> void:
	## sha256-Kontrakt: geänderte Audio-Dateien erfordern eine Neu-Messung.
	var manifest := _fixture()
	for kind: String in ["music", "sfx", "voice"]:
		var rows: Dictionary = manifest.get(kind, {})
		for key: String in rows:
			var row: Dictionary = rows[key]
			var path := "res://" + str(row.get("file", ""))
			if not FileAccess.file_exists(path):
				fail_test("Datei fehlt: %s (%s/%s)" % [path, kind, key])
				continue
			var got := FileAccess.get_sha256(path)
			assert_eq(
				got,
				str(row.get("sha256", "")),
				"Audio-Drift bei %s/%s (%s). %s" % [kind, key, path, REGEN_HINWEIS]
			)


func test_musik_peakt_nach_trim_unter_minus_1_dbfs() -> void:
	var music: Dictionary = _fixture().get("music", {})
	for track_id: String in MusicRegistry.ids():
		if not music.has(track_id):
			continue
		var row: Dictionary = music[track_id]
		var eff_peak := float(row.get("peak_db", 0.0)) + MusicRegistry.trim_db(track_id)
		assert_true(
			eff_peak <= MAX_EFF_PEAK_DB,
			"%s peakt nach gain_trim bei %.2f dBFS (> −1)" % [track_id, eff_peak]
		)


func test_musik_beds_untereinander_gleich_laut() -> void:
	var music: Dictionary = _fixture().get("music", {})
	for track_id: String in MusicRegistry.ids():
		if MusicRegistry.is_stinger(track_id) or not music.has(track_id):
			continue
		var row: Dictionary = music[track_id]
		var eff_loud := float(row.get("loud_db", 0.0)) + MusicRegistry.trim_db(track_id)
		assert_true(
			eff_loud >= BED_EFF_LOUD_MIN and eff_loud <= BED_EFF_LOUD_MAX,
			(
				"%s effektive Loudness %.1f dBFS ausserhalb [%.1f, %.1f]"
				% [track_id, eff_loud, BED_EFF_LOUD_MIN, BED_EFF_LOUD_MAX]
			)
		)


func test_musik_liegt_6_bis_10_db_unter_den_effekten() -> void:
	## AC-Verhältnis: Median Musik-Playback vs. Median SFX (Ambience-Betten
	## sind bewusst leiser und zählen nicht als Interaktions-Sound).
	var manifest := _fixture()
	var music: Dictionary = manifest.get("music", {})
	var sfx: Dictionary = manifest.get("sfx", {})
	var music_levels: Array[float] = []
	for track_id: String in MusicRegistry.ids():
		if MusicRegistry.is_stinger(track_id) or not music.has(track_id):
			continue
		var row: Dictionary = music[track_id]
		music_levels.append(float(row.get("loud_db", 0.0)) + MusicRegistry.trim_db(track_id))
	var sfx_levels: Array[float] = []
	for sfx_id: String in SfxMap.ids():
		if sfx_id.begins_with("ranch_ambience") or sfx_id.begins_with("ranch_menge"):
			continue
		if not sfx.has(sfx_id):
			continue
		var row: Dictionary = sfx[sfx_id]
		var vol := float(SfxMap.entry(sfx_id).get("volume_db", 0.0))
		sfx_levels.append(float(row.get("loud_db", 0.0)) + vol)
	var bus_db := float(AudioDirector.BUS_BASE_DB.get("Music", 0.0))
	var playback := _median(music_levels) + bus_db
	var abstand := _median(sfx_levels) - playback
	assert_true(
		abstand >= RATIO_MIN_DB and abstand <= RATIO_MAX_DB,
		(
			"Musik liegt %.1f dB unter den Effekten (Soll %.0f–%.0f; Musik %.1f, SFX %.1f)"
			% [abstand, RATIO_MIN_DB, RATIO_MAX_DB, playback, _median(sfx_levels)]
		)
	)


func test_sfx_effektive_peaks_unter_minus_1_dbfs() -> void:
	var sfx: Dictionary = _fixture().get("sfx", {})
	for sfx_id: String in SfxMap.ids():
		if not sfx.has(sfx_id):
			continue
		var row: Dictionary = sfx[sfx_id]
		var vol := float(SfxMap.entry(sfx_id).get("volume_db", 0.0))
		var eff_peak := float(row.get("peak_db", 0.0)) + vol
		assert_true(
			eff_peak <= MAX_EFF_PEAK_DB,
			"SFX %s peakt effektiv bei %.2f dBFS (> −1)" % [sfx_id, eff_peak]
		)


func test_fehler_feedback_hoerbar() -> void:
	## EVAL-1 S7: mg_spill/mg_junk waren mit −28,8/−25,5 fast unhörbar —
	## Ziel eff. ≈ −22 dBFS, Wache gegen Rückfall.
	var sfx: Dictionary = _fixture().get("sfx", {})
	for sfx_id: String in ["mg_spill", "mg_junk"]:
		if not sfx.has(sfx_id):
			fail_test("%s fehlt im Fixture. %s" % [sfx_id, REGEN_HINWEIS])
			continue
		var row: Dictionary = sfx[sfx_id]
		var eff := (
			float(row.get("loud_db", 0.0)) + float(SfxMap.entry(sfx_id).get("volume_db", 0.0))
		)
		assert_true(eff >= -25.0, "%s zu leise: eff. %.1f dBFS (Soll ≥ −25)" % [sfx_id, eff])


func test_kontext_tracks_haben_saubere_loops() -> void:
	## S2: jeder Kontext-Track (loopt im MusicDirector) hat loop_offset > 0
	## und eine unauffällige Naht am Loop-Punkt (vorher bis 95,5 dB Sprung).
	var music: Dictionary = _fixture().get("music", {})
	for track_id: String in _kontext_track_ids():
		if not music.has(track_id):
			continue
		var row: Dictionary = music[track_id]
		var offset := float(row.get("loop_offset_s", 0.0))
		assert_true(offset > 0.0, "%s hat keinen loop_offset in der .import-Datei" % track_id)
		var seam := float(row.get("seam_loop_db", 99.0))
		assert_true(
			seam <= MAX_SEAM_LOOP_DB,
			"%s Naht-Pegeldifferenz %.1f dB (> %.0f)" % [track_id, seam, MAX_SEAM_LOOP_DB]
		)


func test_master_limiter_und_music_bus_offset() -> void:
	## S1: Brickwall auf Master (−1 dBFS) + Music-Bus-Basisoffset aktiv.
	var director := _director()
	if director == null:
		fail_test("Kein AudioDirector (/root/Audio) im Testbaum")
		return
	var master := AudioServer.get_bus_index("Master")
	var limiter_da := false
	for i in AudioServer.get_bus_effect_count(master):
		var effect := AudioServer.get_bus_effect(master, i)
		if effect is AudioEffectHardLimiter:
			limiter_da = true
			assert_almost(
				(effect as AudioEffectHardLimiter).ceiling_db,
				AudioDirector.LIMITER_CEILING_DB,
				0.01,
				"Limiter-Ceiling verstellt"
			)
	assert_true(limiter_da, "Kein AudioEffectHardLimiter auf dem Master-Bus")
	var music_idx := AudioServer.get_bus_index("Music")
	assert_true(music_idx >= 0, "Music-Bus fehlt")
	if music_idx < 0:
		return
	var vorher := AudioServer.get_bus_volume_db(music_idx)
	director.apply_volume("Music", 1.0)
	assert_almost(
		AudioServer.get_bus_volume_db(music_idx),
		float(AudioDirector.BUS_BASE_DB.get("Music", 0.0)),
		0.05,
		"Music-Bus-Offset greift nicht bei Regler 1.0"
	)
	AudioServer.set_bus_volume_db(music_idx, vorher)


func _director() -> AudioDirector:
	var autoload := tree.root.get_node_or_null("/root/Audio")
	if autoload is AudioDirector:
		return autoload
	return null


## Kontext-Tracks unter assets/music (Ranch-Dateien sind fremd und werden
## von RanchAudio gefahren, nicht vom MusicDirector-Loop).
func _kontext_track_ids() -> Array[String]:
	var out: Array[String] = []
	for track_id: String in MusicRegistry.ids():
		if MusicRegistry.is_stinger(track_id):
			continue
		if MusicRegistry.path(track_id).begins_with(MusicRegistry.RANCH_MUSIK_DIR):
			continue
		var context := str(MusicRegistry.entry(track_id).get("context", ""))
		var extra: bool = MusicRegistry.EXTRA_CONTEXT_TRACKS.values().has(track_id)
		if context.is_empty() and not extra:
			continue
		out.append(track_id)
	return out


func _median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var mid := sorted.size() / 2
	if sorted.size() % 2 == 1:
		return sorted[mid]
	return (sorted[mid - 1] + sorted[mid]) / 2.0
