extends TestCase
## POLISH-A: Kontrakt der Game-Feel-Soundkarte (FeelSfx). Jede Feel-Id muss
## auf eine existierende OGG-Datei zeigen, die sechs Pflicht-Momente
## (Treffer/Fehler/Combo/Countdown/Sieg/Niederlage) müssen belegt sein und
## die Combo-Tonhöhen-Treppe muss monoton steigen (Deckel: +1 Oktave).


func test_alle_ids_haben_dateien() -> void:
	for id: String in FeelSfx.ids():
		var path := FeelSfx.path(id)
		assert_true(path.begins_with(FeelSfx.BASE_DIR), "Pfad unter game/: %s" % id)
		assert_true(ResourceLoader.exists(path), "OGG fehlt für '%s' (%s)" % [id, path])


func test_pflicht_momente_sind_belegt() -> void:
	for id: String in FeelSfx.REQUIRED_MOMENT_IDS:
		assert_true(FeelSfx.SOUNDS.has(id), "Pflicht-Moment ohne Sound-Id: %s" % id)


func test_unbekannte_id_hat_leeren_pfad() -> void:
	assert_eq(FeelSfx.path("gibts_nicht"), "")


func test_combo_pitch_steigt_monoton() -> void:
	assert_almost(FeelSfx.combo_pitch(1), 1.0, 1e-6, "Stufe 1 = Grundton")
	var previous := FeelSfx.combo_pitch(1)
	for streak in range(2, 14):
		var pitch := FeelSfx.combo_pitch(streak)
		assert_true(pitch > previous, "Pitch muss bei Stufe %d steigen" % streak)
		previous = pitch


func test_combo_pitch_deckel_bei_oktave() -> void:
	assert_almost(FeelSfx.combo_pitch(13), 2.0, 1e-6, "Deckel = +12 Halbtöne")
	assert_almost(FeelSfx.combo_pitch(50), 2.0, 1e-6, "Über dem Deckel bleibt es bei 2.0")
	# Ein Halbton-Schritt: Stufe 2 liegt genau 2^(1/12) über dem Grundton.
	assert_almost(FeelSfx.combo_pitch(2), pow(2.0, 1.0 / 12.0), 1e-6)


func test_play_ohne_baum_ist_no_op() -> void:
	var orphan := Node.new()
	FeelSfx.play(orphan, "game_hit")
	FeelSfx.play(null, "game_hit")
	orphan.free()
	assert_true(true, "kein Crash ohne Baum")
