extends TestCase
## FIX-4: MusicRegistry — die 51 generierten Web-Tracks liegen wirklich im
## Projekt, jeder Pflicht-Kontext hat Musik, Sender/Stinger/Trims stimmen.


func test_registry_hat_alle_web_tracks() -> void:
	assert_true(MusicRegistry.ids().size() >= 51, "Web-Manifest hatte 51 Tracks.")


func test_alle_track_dateien_existieren() -> void:
	for track_id: String in MusicRegistry.ids():
		var path := MusicRegistry.path(track_id)
		assert_true(ResourceLoader.exists(path), "Track-Datei fehlt: %s (%s)" % [track_id, path])


func test_pflicht_kontexte_haben_musik() -> void:
	for context: String in MusicRegistry.REQUIRED_CONTEXTS:
		var track := MusicRegistry.track_for(context)
		assert_false(track.is_empty(), "Kontext ohne Musik: %s" % context)
		assert_true(MusicRegistry.TRACKS.has(track), "Kontext-Track unbekannt: %s" % track)


func test_alle_minigame_tracks_aufloesbar() -> void:
	for track_id: String in MusicRegistry.ids():
		var row: Dictionary = MusicRegistry.entry(track_id)
		var context := str(row.get("context", ""))
		if context.begins_with("game:"):
			assert_eq(MusicRegistry.track_for(context), track_id, "game-Kontext löst falsch auf.")


func test_schlafzimmer_varianten() -> void:
	assert_eq(MusicRegistry.track_for("room:bedroom", false), "room-pixie-puddle-awake")
	assert_eq(MusicRegistry.track_for("room:bedroom", true), "room-pixie-puddle-sleeping")
	assert_eq(
		MusicRegistry.track_for("home_night"),
		"room-pixie-puddle-sleeping",
		"home_night impliziert sleeping."
	)


func test_sender_haben_tracks_und_keine_stinger() -> void:
	var seen: Array[String] = []
	for row: Dictionary in MusicRegistry.stations():
		seen.append(str(row["id"]))
		assert_true(int(row["count"]) > 0, "Sender ohne Tracks: %s" % row["id"])
		for track_id: String in row["track_ids"]:
			assert_false(
				MusicRegistry.is_stinger(track_id),
				"Stinger im Sender %s: %s" % [row["id"], track_id]
			)
	for wanted in ["bordmusik", "gooby-fm", "recap-fm", "game-fm", "alle"]:
		assert_true(seen.has(wanted), "Sender fehlt: %s" % wanted)


func test_stinger_erkennung() -> void:
	assert_true(MusicRegistry.is_stinger("stinger-levelup"))
	assert_true(MusicRegistry.is_stinger("stinger-results"))
	assert_false(MusicRegistry.is_stinger("recap-abenteuer"))
	assert_false(MusicRegistry.is_stinger("unbekannt"))


func test_trims_sind_endlich_und_moderat() -> void:
	for track_id: String in MusicRegistry.ids():
		var db := MusicRegistry.trim_db(track_id)
		assert_true(is_finite(db), "trim_db nicht endlich: %s" % track_id)
		assert_true(db > -30.0 and db < 12.0, "trim_db absurd: %s = %f" % [track_id, db])


func test_recap_fm_fuer_das_rueckblick_kino() -> void:
	var track_ids := MusicRegistry.station_track_ids("recap-fm")
	assert_true(track_ids.size() >= 3, "Recap-FM braucht die 3 Recap-Tracks.")
	for track_id: String in track_ids:
		var grid := MusicRegistry.beat_grid(track_id)
		if not grid.is_empty():
			assert_true(float(grid.get("bpm", 0.0)) > 0.0, "Beat-Grid ohne bpm: %s" % track_id)


func test_string_keys_der_sender_existieren() -> void:
	for def: Dictionary in MusicRegistry.STATION_DEFS:
		var key := str(def["name_key"])
		assert_true(I18nService.table("de").has(key), "DE-String fehlt für Sender: %s" % key)
		assert_true(I18nService.table("en").has(key), "EN-String fehlt für Sender: %s" % key)
