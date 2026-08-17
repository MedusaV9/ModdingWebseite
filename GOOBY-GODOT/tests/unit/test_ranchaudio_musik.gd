extends TestCase
## RW-8: Die 5 Ranch-Musikstücke hängen in der MusicRegistry (Dateien da,
## Kontexte ranch/ranch_reiten/ranch_turnier/ranch_nacht/ranch_menue lösen
## auf, Trims moderat), laufen in keinem Themen-Sender (nur "alle") und die
## Reiseziel→Kontext-Zuordnung von RanchAudio stimmt inkl. Nachtfenster.

const RANCH_TRACKS := ["ranch-tag", "ranch-reiten", "ranch-turnier", "ranch-nacht", "ranch-menue"]
const RANCH_KONTEXTE := ["ranch", "ranch_reiten", "ranch_turnier", "ranch_nacht", "ranch_menue"]


func test_fuenf_ranch_tracks_registriert_und_dateien_da() -> void:
	for track_id: String in RANCH_TRACKS:
		var row := MusicRegistry.entry(track_id)
		assert_false(row.is_empty(), "Track fehlt in der Registry: %s" % track_id)
		assert_eq(str(row.get("category")), "Ranch", "Kategorie Ranch: %s" % track_id)
		var pfad := MusicRegistry.path(track_id)
		assert_true(ResourceLoader.exists(pfad), "Musik-Datei fehlt: %s (%s)" % [track_id, pfad])
		assert_false(MusicRegistry.is_stinger(track_id), "Volles Stück, kein Stinger.")


func test_ranch_kontexte_loesen_auf() -> void:
	assert_eq(MusicRegistry.track_for("ranch"), "ranch-tag", "Hof → Ranch-Tag.")
	assert_eq(MusicRegistry.track_for("ranch_reiten"), "ranch-reiten", "Weite → Reiten.")
	assert_eq(MusicRegistry.track_for("ranch_turnier"), "ranch-turnier", "Turnier-Stück.")
	assert_eq(MusicRegistry.track_for("ranch_nacht"), "ranch-nacht", "Nacht-Piano.")
	assert_eq(MusicRegistry.track_for("ranch_menue"), "ranch-menue", "Menü-Stück.")
	for kontext: String in RANCH_KONTEXTE:
		assert_true(
			MusicRegistry.REQUIRED_CONTEXTS.has(kontext),
			"Kontext im Pflicht-Kontrakt: %s" % kontext
		)


func test_ranch_tracks_nur_im_sender_alle() -> void:
	for track_id: String in RANCH_TRACKS:
		assert_true(
			MusicRegistry.track_belongs_to(track_id, "alle"), "'%s' läuft in 'alle'." % track_id
		)
		for station: String in ["bordmusik", "gooby-fm", "recap-fm", "game-fm"]:
			assert_false(
				MusicRegistry.track_belongs_to(track_id, station),
				"'%s' kapert nicht Sender '%s'." % [track_id, station]
			)


func test_trims_auf_bestands_loudness_eingemessen() -> void:
	for track_id: String in RANCH_TRACKS:
		var db := MusicRegistry.trim_db(track_id)
		assert_true(is_finite(db), "trim_db endlich: %s" % track_id)
		assert_true(db > -6.0 and db < 8.0, "Trim moderat: %s = %f dB" % [track_id, db])


func test_reiseziel_zu_musik_kontext() -> void:
	assert_eq(RanchAudio.musik_kontext_fuer("ranch/hof", 12.0), "ranch")
	assert_eq(RanchAudio.musik_kontext_fuer("ranch/bau", 12.0), "ranch")
	assert_eq(RanchAudio.musik_kontext_fuer("ranch/dorf", 12.0), "ranch")
	assert_eq(RanchAudio.musik_kontext_fuer("ranch/welt", 12.0), "ranch_reiten")
	assert_eq(RanchAudio.musik_kontext_fuer("ranch/fahrt", 12.0), "ranch_reiten")
	assert_eq(RanchAudio.musik_kontext_fuer("ranch/turnier", 12.0), "ranch_turnier")
	assert_eq(
		RanchAudio.musik_kontext_fuer("ranch/hof", 22.0), "ranch_nacht", "Nachts Nacht-Musik."
	)
	assert_eq(
		RanchAudio.musik_kontext_fuer("ranch/turnier", 22.0),
		"ranch_turnier",
		"Turnier schlägt Nacht."
	)
	assert_eq(RanchAudio.musik_kontext_fuer("city", 12.0), "", "Fremde Ziele bleiben unberührt.")


## Der bestehende MusicDirector löst die Ranch-Kontexte ohne Sonderweg auf —
## wir fügen uns ins vorhandene System ein statt ein zweites zu bauen.
func test_music_director_loest_ranch_kontexte() -> void:
	var director := MusicDirector.new()
	assert_eq(director.resolve_track("ranch"), "ranch-tag")
	assert_eq(director.resolve_track("ranch_nacht"), "ranch-nacht")
	director.free()


func test_bestand_bleibt_unangetastet() -> void:
	assert_true(MusicRegistry.ids().size() >= 56, "51 Bestands-Tracks + 5 Ranch-Stücke.")
	assert_eq(MusicRegistry.track_for("home"), "room-cloud-hopper-s-day-off", "Bestand intakt.")
	assert_eq(MusicRegistry.track_for("city"), "location-stadtrundfahrt", "Bestand intakt.")
