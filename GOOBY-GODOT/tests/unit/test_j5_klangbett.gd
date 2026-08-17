extends TestCase
## W18/J5 „Jeder Ort ein Klangbett“ (I-33) — Wächter für das Klangbett-System
## (scripts/audio/klangbett.gd): zentrale Ort→Bett-Zuordnung, Router-Hook,
## nahtlose Loops (Mess-Fixture ef2_audio_levels.json), deterministische
## Duck-Kurve (injizierte Zeit), Betten-Pegel deutlich unter Musik/SFX und
## Settings-/Stumm-/RM-Verhalten. Nach Audio-Änderungen gilt weiter:
## Fixture neu erzeugen via `python3 tools/audio/ef2_manifest.py`.

const FIXTURE := "res://tests/fixtures/ef2_audio_levels.json"
const AMBIENT_DIR := "res://assets/audio/sfx/ambient"
## Loop-Naht-Schwelle wie die Musik-Wache (test_ef2_audio_levels).
const MAX_SEAM_DB := 8.0
## Betten liegen mindestens so viele dB UNTER dem Musik-Playback …
const MIN_ABSTAND_ZU_MUSIK_DB := 2.0
## … aber nie unhörbar leise.
const MIN_EFF_LOUD_DB := -45.0

var _manifest: Dictionary = {}


func _fixture() -> Dictionary:
	if _manifest.is_empty():
		var data: Variant = JsonFixtures.load_json(FIXTURE)
		if data is Dictionary:
			_manifest = data
	return _manifest


## Frische, stumme Instanz mit injizierter Zeit (auto_takt aus).
func _neues_bett() -> Klangbett:
	var bett := Klangbett.new()
	bett.stumm = true
	bett.auto_takt = false
	tree.root.add_child(bett)
	return bett


func test_map_ebenen_dateien_und_lizenz_vollstaendig() -> void:
	# Jede Ebene der zentralen Map ist bekannt, jede Bett-Id gemappt,
	# jede Datei + die CC0-Lizenznotiz vorhanden (wie beim Bestand).
	for ziel: String in Klangbett.ORT_BETTEN:
		for ebene: String in Klangbett.ORT_BETTEN[ziel] as Dictionary:
			assert_true(
				Klangbett.EBENEN_IDS.has(ebene),
				"Unbekannte Ebene '%s' im Map-Eintrag '%s'" % [ebene, ziel]
			)
	for ebene: String in Klangbett.EBENEN_IDS:
		var sfx_id := str(Klangbett.EBENEN_IDS[ebene])
		assert_true(sfx_id.begins_with("bett_"), "Bett-Id-Konvention: %s" % sfx_id)
		var pfad := SfxMap.path(sfx_id)
		assert_false(pfad.is_empty(), "SfxMap-Eintrag fehlt: %s" % sfx_id)
		assert_true(ResourceLoader.exists(pfad), "Bett-Datei fehlt: %s" % pfad)
	assert_true(
		FileAccess.file_exists(AMBIENT_DIR + "/LICENSE.md"),
		"Lizenznotiz fehlt: %s/LICENSE.md" % AMBIENT_DIR
	)


func test_map_ziele_sind_echte_routen() -> void:
	# Tippfehler-Schutz: Heim-/Screen-Ziele müssen im MusicDirector-Kontrakt
	# stehen, city/ort/*-Ziele im Ort-Katalog (betretbare Orte der Karte).
	var betretbar := OrtKatalog.betretbare_ids()
	for ziel: String in Klangbett.ORT_BETTEN:
		if ziel.begins_with("city/ort/"):
			var ort_id := ziel.trim_prefix("city/ort/")
			assert_true(betretbar.has(ort_id), "Ort '%s' ist nicht betretbar" % ort_id)
		else:
			assert_true(
				MusicDirector.ROUTE_CONTEXTS.has(ziel),
				"Ziel '%s' ist keine bekannte Route (MusicDirector.ROUTE_CONTEXTS)" % ziel
			)


func test_bett_plan_je_zieltyp() -> void:
	var wohnen := Klangbett.bett_plan_fuer("home/living")
	assert_true(bool(wohnen["wechsel"]), "home/living wechselt das Bett")
	assert_true((wohnen["ebenen"] as Dictionary).has("kamin"), "Wohnzimmer hat Kamin")
	assert_true((wohnen["ebenen"] as Dictionary).has("uhr"), "Wohnzimmer hat Uhr")
	var stadt := Klangbett.bett_plan_fuer("city")
	assert_true((stadt["ebenen"] as Dictionary).has("stadt"), "Stadt hat Stadt-Bett")
	var laden := Klangbett.bett_plan_fuer("city/ort/rehwei")
	assert_eq(laden["ebenen"], Klangbett.LADEN_STANDARD, "Innenraum-Fallback = Laden-Raumton")
	var ranch := Klangbett.bett_plan_fuer("ranch/welt")
	assert_true(bool(ranch["wechsel"]), "Ranch wechselt (auf aus)")
	assert_true((ranch["ebenen"] as Dictionary).is_empty(), "Ranch fährt RanchAudio, kein Bett")
	var host := Klangbett.bett_plan_fuer("mg_host")
	assert_true(
		bool(host["wechsel"]) and (host["ebenen"] as Dictionary).is_empty(), "Minigames: Bett aus"
	)
	var screen := Klangbett.bett_plan_fuer("galerie")
	assert_false(bool(screen["wechsel"]), "UI-Screens behalten das laufende Bett (wie Musik)")
	assert_false(bool(Klangbett.bett_plan_fuer("")["wechsel"]), "Leeres Ziel = kein Wechsel")


func test_router_hook_verdrahtet_und_wechsel_faehrt_betten() -> void:
	# Der vom MusicDirector gebootstrapte Knoten hängt am echten Router.
	var router := tree.root.get_node_or_null("/root/SceneRouter")
	var global_bett := tree.root.get_node_or_null("/root/Klangbett")
	if router != null and global_bett is Klangbett:
		assert_true(
			router.travel_finished.is_connected(global_bett._on_travel_finished),
			"Klangbett hängt nicht an SceneRouter.travel_finished"
		)
	else:
		fail_test("Bootstrap fehlt: /root/Klangbett (MusicDirector._ready)")
	# Ortswechsel mit injizierter Zeit: Wohnzimmer-Bett fährt hoch, nach dem
	# Wechsel in die Stadt fährt der Kamin aus und das Stadt-Bett hoch.
	var bett := _neues_bett()
	bett._on_travel_finished(&"home/living")
	assert_eq(bett.ziel_ort(), "home/living", "Router-Hook setzt das Ziel")
	for _i in 30:
		bett.takt(0.1)
	var dump := bett.debug_dump()
	var kamin: Dictionary = dump["ebenen"]["kamin"]
	assert_almost(float(kamin["ist"]), 0.85, 0.01, "Kamin nach 3 s auf Ziel-Gain")
	bett._on_travel_finished(&"city")
	for _i in 40:
		bett.takt(0.1)
	dump = bett.debug_dump()
	assert_almost(
		float((dump["ebenen"]["kamin"] as Dictionary)["ist"]), 0.0, 0.01, "Kamin in der Stadt aus"
	)
	assert_almost(
		float((dump["ebenen"]["stadt"] as Dictionary)["ist"]), 0.85, 0.01, "Stadt-Bett an"
	)
	# UI-Screen dazwischen: Bett bleibt (wie die Kontext-Musik).
	bett._on_travel_finished(&"galerie")
	assert_eq(bett.ziel_ort(), "city", "UI-Screen lässt das Bett stehen")
	bett.free()


func test_duck_kurve_deterministisch() -> void:
	# Pure Hüllkurve mit injizierter Zeit: runter in DUCK_ZU_S (Rate 3/s),
	# rauf in DUCK_AUF_S (Rate 0,8333/s) — exakt vorhersagbare Stützstellen.
	assert_eq(Klangbett.duck_ziel(false, 0.0), 1.0, "frei = kein Duck")
	assert_eq(Klangbett.duck_ziel(true, 0.0), Klangbett.DUCK_FAKTOR, "Stimme duckt")
	assert_eq(Klangbett.duck_ziel(false, 0.2), Klangbett.DUCK_FAKTOR, "Jingle duckt")
	var duck := 1.0
	duck = Klangbett.duck_schritt(duck, 0.25, 0.1)
	assert_almost(duck, 0.7, 0.0001, "Duck-Stützstelle 1 (100 ms)")
	duck = Klangbett.duck_schritt(duck, 0.25, 0.1)
	assert_almost(duck, 0.4, 0.0001, "Duck-Stützstelle 2 (200 ms)")
	duck = Klangbett.duck_schritt(duck, 0.25, 0.1)
	assert_almost(duck, 0.25, 0.0001, "Duck erreicht den Boden in DUCK_ZU_S")
	duck = Klangbett.duck_schritt(duck, 1.0, 0.3)
	assert_almost(duck, 0.5, 0.0001, "Release-Stützstelle (300 ms)")
	duck = Klangbett.duck_schritt(duck, 1.0, 0.6)
	assert_almost(duck, 1.0, 0.0001, "Release komplett in DUCK_AUF_S")
	# Fade-Mathe der Betten: volle Skala in BETT_FADE_S.
	var gain := Klangbett.gain_schritt(0.0, 0.85, 1.0)
	assert_almost(gain, 0.4, 0.0001, "Bett-Fade-Stützstelle 1 s")
	assert_almost(Klangbett.gain_schritt(gain, 0.85, 2.0), 0.85, 0.0001, "Bett-Fade fertig")
	assert_almost(Klangbett.ebene_db(-14.0, 1.0, 1.0), -14.0, 0.0001, "Voller Gain = Trim")
	assert_almost(
		Klangbett.ebene_db(-14.0, 0.5, 0.25),
		-14.0 + linear_to_db(0.125),
		0.0001,
		"Gain × Duck multiplikativ in dB"
	)


func test_duck_quellen_gebrabbel_stinger_und_sweep() -> void:
	var bett := _neues_bett()
	var stimme := Node.new()
	tree.root.add_child(stimme)
	bett.gebrabbel_setzen(stimme, true)
	bett.takt(0.1)
	assert_almost(bett.duck_faktor(), 0.7, 0.0001, "Gebrabbel drückt das Bett runter")
	bett.gebrabbel_setzen(stimme, false)
	for _i in 20:
		bett.takt(0.1)
	assert_almost(bett.duck_faktor(), 1.0, 0.0001, "Nach dem Satz kommt das Bett zurück")
	# Jingle: hält Dauer (0,5 s) + Nachhall (0,4 s) = 0,9 s, dann Release —
	# bei 0,8 s ist der Duck also noch voll unten, 2 s später wieder frei.
	bett.stinger_setzen(0.5)
	for _i in 8:
		bett.takt(0.1)
	assert_almost(bett.duck_faktor(), 0.25, 0.0001, "Jingle-Duck hält (0,5 s + Nachhall)")
	for _i in 20:
		bett.takt(0.1)
	assert_almost(bett.duck_faktor(), 1.0, 0.0001, "Nach dem Jingle wieder frei")
	# Sweep 1: eine freigegebene Stimme darf das Bett nicht ewig ducken.
	bett.gebrabbel_setzen(stimme, true)
	stimme.free()
	for _i in 20:
		bett.takt(0.1)
	assert_almost(bett.duck_faktor(), 1.0, 0.0001, "Freigegebene Quelle wird ausgefegt")
	# Sweep 2 (Selbstheilung, Playtest-Befund): eine VERSTUMMTE Stimme —
	# ist_am_reden() false, Ende-Meldung verpasst (z. B. sagt() mit leerem
	# Plan ersetzt ein unterbrochenes Gebrabbel) — wird ebenfalls ausgefegt.
	var stumm := StummeStimme.new()
	tree.root.add_child(stumm)
	stumm.reden = true
	bett.gebrabbel_setzen(stumm, true)
	bett.takt(0.1)
	assert_almost(bett.duck_faktor(), 0.7, 0.0001, "Redende Quelle duckt")
	stumm.reden = false
	for _i in 20:
		bett.takt(0.1)
	assert_almost(bett.duck_faktor(), 1.0, 0.0001, "Verstummte Quelle wird ausgefegt")
	stumm.free()
	bett.free()


func test_loop_naht_jeder_neuen_bett_datei() -> void:
	# Loop-Naht-Prüfung (Muster test_kontext_tracks_haben_saubere_loops):
	# Kopf-/Schwanz-Pegel jeder Bett-Datei dürfen an der Naht nicht springen.
	var sfx: Dictionary = _fixture().get("sfx", {})
	for ebene: String in Klangbett.EBENEN_IDS:
		var sfx_id := str(Klangbett.EBENEN_IDS[ebene])
		if not sfx.has(sfx_id):
			fail_test("%s fehlt im Mess-Fixture — python3 tools/audio/ef2_manifest.py" % sfx_id)
			continue
		var row: Dictionary = sfx[sfx_id]
		var seam := float(row.get("seam_loop_db", 99.0))
		assert_true(
			seam <= MAX_SEAM_DB,
			"%s Loop-Naht %.1f dB (> %.0f) — Loop knackt" % [sfx_id, seam, MAX_SEAM_DB]
		)
		assert_true(float(row.get("dur_s", 0.0)) >= 2.0, "%s zu kurz für ein Bett" % sfx_id)


func test_betten_liegen_deutlich_unter_musik_und_sfx() -> void:
	# Bett-Pegel-Kontrakt: eff. Loudness jedes Betts liegt UNTER dem
	# Musik-Playback (Datei-Median + Music-Bus-Offset) und erst recht unter
	# dem SFX-Median — aber über der Hörbarkeits-Untergrenze.
	var manifest := _fixture()
	var music: Dictionary = manifest.get("music", {})
	var sfx: Dictionary = manifest.get("sfx", {})
	var music_levels: Array[float] = []
	for track_id: String in MusicRegistry.ids():
		if MusicRegistry.is_stinger(track_id) or not music.has(track_id):
			continue
		var row: Dictionary = music[track_id]
		music_levels.append(float(row.get("loud_db", 0.0)) + MusicRegistry.trim_db(track_id))
	var playback := _median(music_levels) + float(AudioDirector.BUS_BASE_DB.get("Music", 0.0))
	for ebene: String in Klangbett.EBENEN_IDS:
		var sfx_id := str(Klangbett.EBENEN_IDS[ebene])
		if not sfx.has(sfx_id):
			continue
		var eff := (
			float((sfx[sfx_id] as Dictionary).get("loud_db", 0.0))
			+ float(SfxMap.entry(sfx_id).get("volume_db", 0.0))
		)
		assert_true(
			eff <= playback - MIN_ABSTAND_ZU_MUSIK_DB,
			(
				"%s eff. %.1f dBFS liegt nicht deutlich unter Musik-Playback %.1f"
				% [sfx_id, eff, playback]
			)
		)
		assert_true(eff >= MIN_EFF_LOUD_DB, "%s unhörbar leise (%.1f dBFS)" % [sfx_id, eff])


func test_settings_stumm_und_rm_verhalten() -> void:
	# Betten laufen auf dem Sfx-Bus: Nutzer-Regler audio.sfx + Stumm-Modus
	# (Regler 0 → Bus-Mute im AudioDirector) greifen ohne Sonderweg.
	var bett := Klangbett.new()
	bett.auto_takt = false
	tree.root.add_child(bett)
	var player: AudioStreamPlayer = bett._erzeuge_player("bett_wind")
	assert_true(player != null, "Bett-Player entsteht")
	if player != null:
		assert_eq(player.bus, &"Sfx", "Betten hängen am Sfx-Bus (Settings greifen)")
		assert_true(
			player.stream is AudioStreamOggVorbis and (player.stream as AudioStreamOggVorbis).loop,
			"Bett-Stream loopt"
		)
		assert_false(player.playing, "_erzeuge_player startet noch nichts")
	var audio := tree.root.get_node_or_null("/root/Audio")
	var sfx_idx := AudioServer.get_bus_index("Sfx")
	if audio is AudioDirector and sfx_idx >= 0:
		var vorher_db := AudioServer.get_bus_volume_db(sfx_idx)
		var vorher_mute := AudioServer.is_bus_mute(sfx_idx)
		(audio as AudioDirector).apply_volume("Sfx", 0.0)
		assert_true(AudioServer.is_bus_mute(sfx_idx), "Regler 0 = Stumm (Bus-Mute)")
		(audio as AudioDirector).apply_volume("Sfx", 1.0)
		assert_false(AudioServer.is_bus_mute(sfx_idx), "Regler 1 = wieder hörbar")
		AudioServer.set_bus_volume_db(sfx_idx, vorher_db)
		AudioServer.set_bus_mute(sfx_idx, vorher_mute)
	else:
		fail_test("Kein AudioDirector (/root/Audio) im Testbaum")
	# Reduced Motion ist ein Bewegungs-Setting: die Bett-Planung bleibt
	# identisch (Audio wird nicht mitreduziert — Absicht, s. Klassen-Doku).
	var settings := tree.root.get_node_or_null("/root/AppSettings")
	if settings != null and settings.has_method("set_setting"):
		var vorher: Variant = settings.get_setting("reduced_motion", false)
		settings.set_setting("reduced_motion", true)
		assert_eq(
			Klangbett.bett_plan_fuer("home/living"),
			Klangbett.bett_plan_fuer("home/living"),
			"Planung deterministisch"
		)
		assert_true(
			bool(Klangbett.bett_plan_fuer("city")["wechsel"]),
			"RM lässt die Betten an (nur Bewegung wird reduziert)"
		)
		settings.set_setting("reduced_motion", vorher)
	bett.free()


func _median(values: Array[float]) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	var mid := sorted.size() / 2
	if sorted.size() % 2 == 1:
		return sorted[mid]
	return (sorted[mid - 1] + sorted[mid]) / 2.0


## GoobyVoice-Attrappe für den Selbstheilungs-Sweep: nur das
## ist_am_reden()-Protokoll, das der Klangbett-Takt abfragt.
class StummeStimme:
	extends Node

	var reden := false

	func ist_am_reden() -> bool:
		return reden
