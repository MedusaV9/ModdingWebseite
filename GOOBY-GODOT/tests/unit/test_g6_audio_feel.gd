extends TestCase
## G6-FEEL — Mix-Wache über den Audio-Grammatik-Lückenschluss (Muster
## test_ef2_audio_levels/test_ef2_sfx_gaps, erweitert um die NEUEN Sounds):
## 1. Alle SfxMap.G6_FEEL_IDS existieren, laden und stehen im Mess-Fixture.
## 2. Kein Clipping: effektiver Peak (Quelle + volume_db) ≤ −1 dBFS.
## 3. Keine Lautheits-Ausreißer: eff. Loudness im Band um die gemeinsame
##    Effekt-Ebene ~−22 dBFS (EVAL1-Metrik, Fixture von ef2_manifest.py).
## 4. Die Emotions-Familie bleibt AC-weich (Zentroid/Höhen-Deckel) und
##    jede der 12 FeelEmotions hat ihr EIGENES emo_*-Motiv (keine
##    recycelten UI-Sounds, keine stummen Emotionen mehr).
## 5. RaumKlang: Zonen-Mathematik pur + Bus-Reverb dezent und abschaltbar.
## Nach Audio-Änderungen Fixture neu erzeugen:
## `python3 tools/audio/ef2_manifest.py`.

const FIXTURE := "res://tests/fixtures/ef2_audio_levels.json"
const REGEN_HINWEIS := "Fixture neu erzeugen: python3 tools/audio/ef2_manifest.py"
## Clipping-Deckel wie test_ef2_audio_levels (Fixture rundet auf 0,1 dB).
const MAX_EFF_PEAK_DB := -0.95
## Lautheits-Band um die gemeinsame Effekt-Ebene (~−22 dBFS eff.) — die
## G6-Sounds sind auf −22 bis −24 eingemessen, das Band fängt Ausreißer.
const EFF_LOUD_MIN_DB := -27.0
const EFF_LOUD_MAX_DB := -17.0
## soft-Kontrakt der Emotions-Familie (wie test_ef2_sfx_gaps).
const SOFT_CENTROID_MAX_HZ := 2500.0
const SOFT_HI4K_MAX_PCT := 10.0

var _manifest: Dictionary = {}


func _fixture_sfx() -> Dictionary:
	if _manifest.is_empty():
		var data: Variant = JsonFixtures.load_json(FIXTURE)
		if data is Dictionary:
			_manifest = data
	return _manifest.get("sfx", {})


func test_neue_ids_gemappt_ladbar_und_gemessen() -> void:
	var sfx := _fixture_sfx()
	for id: String in SfxMap.G6_FEEL_IDS:
		assert_true(SfxMap.SOUNDS.has(id), "SFX-Id fehlt in der Map: %s" % id)
		var path := SfxMap.path(id)
		assert_true(ResourceLoader.exists(path), "Datei fehlt: %s (%s)" % [id, path])
		if ResourceLoader.exists(path):
			assert_true(load(path) is AudioStream, "%s laedt keinen AudioStream" % id)
		assert_true(sfx.has(id), "%s fehlt im Mess-Fixture. %s" % [id, REGEN_HINWEIS])


func test_kein_clipping_ueber_den_neuen_sfx() -> void:
	var sfx := _fixture_sfx()
	for id: String in SfxMap.G6_FEEL_IDS:
		if not sfx.has(id):
			continue
		var row: Dictionary = sfx[id]
		var vol := float(SfxMap.entry(id).get("volume_db", 0.0))
		var eff_peak := float(row.get("peak_db", 0.0)) + vol
		assert_true(
			eff_peak <= MAX_EFF_PEAK_DB,
			"%s peakt effektiv bei %.2f dBFS (> −1 — Clipping-Gefahr)" % [id, eff_peak]
		)


func test_keine_lautheits_ausreisser_ueber_den_neuen_sfx() -> void:
	## Grobe Ausreißer-Wache: alles bleibt im Band um die Effekt-Ebene —
	## nichts schreit heraus, nichts säuft ab (EVAL-1-S7-Lektion).
	var sfx := _fixture_sfx()
	for id: String in SfxMap.G6_FEEL_IDS:
		if not sfx.has(id):
			continue
		var row: Dictionary = sfx[id]
		var eff := float(row.get("loud_db", 0.0)) + float(SfxMap.entry(id).get("volume_db", 0.0))
		assert_true(
			eff >= EFF_LOUD_MIN_DB and eff <= EFF_LOUD_MAX_DB,
			(
				"%s eff. Loudness %.1f dBFS ausserhalb [%.0f, %.0f]"
				% [id, eff, EFF_LOUD_MIN_DB, EFF_LOUD_MAX_DB]
			)
		)


func test_emotions_familie_bleibt_weich() -> void:
	## AC-Ästhetik: die emo_*-Motive sind Sinus-Plucks, kein Grell-Klirren
	## (city_vogel ist bewusst hell — ein Vogel — und zählt hier nicht).
	var sfx := _fixture_sfx()
	for id: String in SfxMap.G6_FEEL_IDS:
		if not id.begins_with("emo_"):
			continue
		var file := str(SfxMap.entry(id).get("file", ""))
		assert_true(file.begins_with("soft/"), "%s liegt nicht in soft/: %s" % [id, file])
		if not sfx.has(id):
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


func test_jede_emotion_hat_ihr_eigenes_motiv() -> void:
	## Keine stummen Emotionen mehr (muedigkeit/angst) und keine
	## recycelten UI-Sounds — jede Emotion feuert ihr eigenes emo_*.
	var gesehen: Dictionary = {}
	for emotion: String in FeelEmotions.alle():
		var sfx_id := str(FeelEmotions.def_of(emotion).get("sfx", ""))
		assert_false(sfx_id.is_empty(), "%s ist stumm (sfx leer)" % emotion)
		assert_true(sfx_id.begins_with("emo_"), "%s nutzt kein emo_*-Motiv: %s" % [emotion, sfx_id])
		assert_false(SfxMap.entry(sfx_id).is_empty(), "%s: Id %s ungemappt" % [emotion, sfx_id])
		assert_false(gesehen.has(sfx_id), "%s teilt sein Motiv mit %s" % [emotion, gesehen])
		gesehen[sfx_id] = emotion
	assert_eq(gesehen.size(), 12, "12 Emotionen -> 12 eigene Motive")


func test_wiring_kontrakte_der_orts_momente() -> void:
	## Die umverdrahteten Konstanten bleiben auf den neuen Ids (Glocke war
	## gvz_wave@1.35, Kasse ui_coins@1.15 — Grammatik-Bereinigung G6).
	assert_eq(OrtLeben.GLOCKE_ID, "laden_glocke", "Ladentuer-Gloeckchen nutzt eigene Id")
	assert_almost(OrtLeben.GLOCKE_PITCH, 1.0, 0.001, "Glocke unverstimmt (eigene Datei)")
	assert_eq(KassenNpc.PIEP_ID, "kasse_piep", "Kassen-Piep nutzt eigene Id")
	assert_almost(KassenNpc.PIEP_PITCH, 1.0, 0.001, "Piep unverstimmt (eigene Datei)")


func test_raum_klang_zonen_mathematik() -> void:
	## PURE Zuordnung Router-Ziel -> Zone ("" = Ort meldet sich selbst).
	assert_eq(RaumKlang.zone_fuer_ziel("ranch/welt"), "weite")
	assert_eq(RaumKlang.zone_fuer_ziel("ranch/hof"), "weite")
	assert_eq(RaumKlang.zone_fuer_ziel("city/ort/rehwei"), "")
	assert_eq(RaumKlang.zone_fuer_ziel("city/ort/wochenmarkt"), "")
	assert_eq(RaumKlang.zone_fuer_ziel("arcade"), "laden_innen")
	assert_eq(RaumKlang.zone_fuer_ziel("city"), "neutral")
	assert_eq(RaumKlang.zone_fuer_ziel("home/living"), "neutral")
	for zone: String in ["neutral", "laden_innen", "ort_draussen", "station_halle", "weite"]:
		assert_true(RaumKlang.kennt(zone), "Zonen-Profil fehlt: %s" % zone)


func test_raum_klang_profile_bleiben_dezent() -> void:
	## Der Auftrag sagt DEZENT — kein Profil darf nasser als MAX_WET sein,
	## draußen/neutral bleiben komplett trocken.
	for zone: String in RaumKlang.PROFILE:
		var wet := float(RaumKlang.profil(zone).get("wet", 1.0))
		assert_true(wet <= RaumKlang.MAX_WET, "%s zu nass: wet %.2f" % [zone, wet])
		assert_true(wet >= 0.0, "%s negativer Wet-Anteil" % zone)
	assert_almost(float(RaumKlang.profil("neutral")["wet"]), 0.0, 0.0001, "neutral trocken")
	assert_almost(float(RaumKlang.profil("ort_draussen")["wet"]), 0.0, 0.0001, "draussen trocken")


func test_raum_klang_bus_reverb_an_und_aus() -> void:
	## Bus-Kontrakt: laden_innen aktiviert GENAU EINEN Reverb auf dem
	## Sfx-Bus (dezent), neutral schaltet ihn wieder komplett ab.
	var raum := RaumKlang.get_or_create(tree.root)
	if not raum.is_inside_tree():
		await wait_frames(2)
	if not raum.is_inside_tree():
		fail_test("RaumKlang kommt nicht in den Baum")
		return
	raum.setze_zone("neutral", true)
	raum.setze_zone("laden_innen", true)
	var bus := AudioServer.get_bus_index("Sfx")
	assert_true(bus >= 0, "Sfx-Bus fehlt")
	var reverbs := 0
	var aktiv := false
	var wet := -1.0
	for i in AudioServer.get_bus_effect_count(bus):
		var effekt := AudioServer.get_bus_effect(bus, i)
		if effekt is AudioEffectReverb:
			reverbs += 1
			aktiv = AudioServer.is_bus_effect_enabled(bus, i)
			wet = (effekt as AudioEffectReverb).wet
	assert_eq(reverbs, 1, "genau EIN Reverb auf dem Sfx-Bus")
	assert_true(aktiv, "laden_innen aktiviert den Reverb")
	assert_almost(wet, 0.10, 0.005, "laden_innen-Wet dezent wie im Profil")
	assert_true(wet <= RaumKlang.MAX_WET, "Wet ueber dem Dezenz-Deckel")
	raum.setze_zone("station_halle", true)
	assert_almost(raum.wet(), 0.13, 0.005, "station_halle etwas mehr Luft")
	# Aufräumen: zurück auf trocken — Effekt bleibt (wie der Limiter),
	# ist aber deaktiviert und kostet kein DSP.
	raum.setze_zone("neutral", true)
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) is AudioEffectReverb:
			assert_false(AudioServer.is_bus_effect_enabled(bus, i), "neutral laesst den Reverb an")
	assert_almost(raum.wet(), 0.0, 0.0001, "neutral faehrt Wet auf 0")


func test_tuer_und_schalter_ids_dokumentiert() -> void:
	## Wiring-Kontrakt der Haus-Momente (door_transition/lampen_schalter/
	## foto_modus spielen über try_play — die Ids müssen stabil bleiben).
	for id: String in ["tuer_auf", "tuer_zu", "tuer_ruettel", "tuer_plopp", "licht_schalter"]:
		assert_false(SfxMap.entry(id).is_empty(), "Haus-Id %s fehlt" % id)
	for id: String in ["city_hupe", "city_vogel"]:
		assert_false(
			SfxMap.entry(id).is_empty(), "%s fehlt — city_scene wartet seit W4 auf diese Id" % id
		)
