extends TestCase
## EF-2 (EVAL-1 S3): GoobyVoice läuft über den Voice-Bus (der Settings-
## Regler "Stimme" wirkt), mit −6-dB-Trim, und die Babble-WAVs sind auf
## −16 dBFS RMS gemastert (vorher −8…−14 dBFS = lauteste Sounds im Spiel).
## Mess-Fixture: tests/fixtures/ef2_audio_levels.json (voice-Sektion).

const FIXTURE := "res://tests/fixtures/ef2_audio_levels.json"
const VOICE_LOUD_MIN := -17.5
const VOICE_LOUD_MAX := -14.5
const VOICE_PEAK_MAX := -3.0


func test_pool_spielt_auf_voice_bus_mit_trim() -> void:
	var voice := GoobyVoice.new()
	tree.root.add_child(voice)
	await wait_frames(1)
	var players := 0
	for child in voice.get_children():
		if child is AudioStreamPlayer3D:
			players += 1
			assert_eq(
				(child as AudioStreamPlayer3D).bus,
				GoobyVoice.VOICE_BUS,
				"Voice-Player %s haengt nicht am Voice-Bus" % child.name
			)
			assert_almost(
				(child as AudioStreamPlayer3D).volume_db,
				GoobyVoice.VOICE_TRIM_DB,
				0.01,
				"Voice-Trim fehlt an %s" % child.name
			)
	assert_eq(players, GoobyVoice.POOL_SIZE, "Voice-Pool unvollstaendig")
	assert_true(AudioServer.get_bus_index(GoobyVoice.VOICE_BUS) >= 0, "Voice-Bus fehlt")
	voice.queue_free()


func test_silben_geladen_und_sagt_laeuft() -> void:
	var voice := GoobyVoice.new()
	tree.root.add_child(voice)
	await wait_frames(1)
	assert_eq(voice.syllable_count(), 14, "Silben-WAVs unvollstaendig geladen")
	var done := {"fertig": false}
	voice.fertig.connect(func() -> void: done["fertig"] = true)
	voice.sagt("Miau miau?")
	assert_true(voice.ist_am_reden(), "sagt() startet kein Gebrabbel")
	var finished := await wait_until(func() -> bool: return done["fertig"], 8000)
	assert_true(finished, "fertig-Signal kam nicht")
	assert_false(voice.ist_am_reden(), "ist_am_reden bleibt haengen")
	voice.queue_free()


func test_babble_wavs_auf_zielpegel() -> void:
	var data: Variant = JsonFixtures.load_json(FIXTURE)
	assert_true(data is Dictionary, "Fixture fehlt/kaputt: %s" % FIXTURE)
	if not (data is Dictionary):
		return
	var rows: Dictionary = (data as Dictionary).get("voice", {})
	assert_eq(rows.size(), 14, "voice-Sektion im Fixture unvollstaendig")
	for key: String in rows:
		var row: Dictionary = rows[key]
		var loud := float(row.get("loud_db", 0.0))
		var peak := float(row.get("peak_db", 0.0))
		assert_true(
			loud >= VOICE_LOUD_MIN and loud <= VOICE_LOUD_MAX,
			(
				"%s Loudness %.1f dBFS ausserhalb [%.1f, %.1f]"
				% [key, loud, VOICE_LOUD_MIN, VOICE_LOUD_MAX]
			)
		)
		assert_true(
			peak <= VOICE_PEAK_MAX, "%s Peak %.1f dBFS (> %.1f)" % [key, peak, VOICE_PEAK_MAX]
		)
