extends TestCase
## EVAL-2026-08 Lens B Befund 6 — die GLOBALE Belichtungskette
## (LichtKalibrierung) ist die EINE Referenz für Tonemap/Exposure/Nebel:
## feste Zielwerte, Kontext-Exposures, Void-Dämpfung und die
## Fensterglut-Rampe der Kulisse (CitySkyline) sind pure und headless
## testbar. Die Messwerte selbst liefert tests/tools/licht_messung.gd.

const LichtMessung := preload("res://tests/tools/licht_messung.gd")


func test_exposure_je_kontext() -> void:
	assert_almost(LichtKalibrierung.exposure("innen"), 0.55, 1e-6, "innen")
	assert_almost(LichtKalibrierung.exposure("innen_kuehl"), 0.33, 1e-6, "Bad kühler")
	assert_almost(LichtKalibrierung.exposure("draussen"), 0.36, 1e-6, "draußen")
	assert_almost(
		LichtKalibrierung.exposure("unbekannt"),
		LichtKalibrierung.exposure("innen"),
		1e-6,
		"unbekannter Kontext fällt auf innen zurück"
	)


func test_environment_traegt_die_kette() -> void:
	var env := LichtKalibrierung.environment("innen")
	assert_true(env.tonemap_mode == Environment.TONE_MAPPER_FILMIC, "Filmic überall")
	assert_almost(env.tonemap_white, LichtKalibrierung.TONEMAP_WEISS, 1e-6, "Weißpunkt")
	assert_almost(env.tonemap_exposure, LichtKalibrierung.exposure("innen"), 1e-6, "Exposure")
	assert_true(
		env.ambient_light_source == Environment.AMBIENT_SOURCE_COLOR, "Ambient aus Profilfarbe"
	)


func test_nebel_bindet_horizont() -> void:
	var env := Environment.new()
	var horizont := Color(0.7, 0.8, 0.85)
	LichtKalibrierung.nebel_anwenden(env, horizont)
	assert_true(env.fog_enabled, "Nebel an")
	assert_almost(env.fog_density, LichtKalibrierung.NEBEL_DICHTE_DRAUSSEN, 1e-6, "Dichte")
	assert_almost(env.fog_sky_affect, 0.0, 1e-6, "Himmel bleibt sauber")
	assert_true(env.fog_light_color.is_equal_approx(horizont), "Dunst = Horizontfarbe")


func test_zielfenster_waechter() -> void:
	assert_true(LichtKalibrierung.im_zielfenster(0.5, 0.5), "Mitte + wenig Clip ok")
	assert_false(LichtKalibrierung.im_zielfenster(0.6, 0.5), "zu hell")
	assert_false(LichtKalibrierung.im_zielfenster(0.4, 0.5), "zu dunkel")
	assert_false(LichtKalibrierung.im_zielfenster(0.5, 2.5), "zu viel Clipping")


func test_void_hintergrund_wird_gedaempft() -> void:
	var hell := Color(0.98, 0.92, 0.83)
	var gedaempft := LichtKalibrierung.hintergrund(hell)
	assert_true(gedaempft.r < hell.r and gedaempft.g < hell.g, "dunkler als das Profil-Pastell")
	assert_almost(
		gedaempft.r, hell.r * (1.0 - LichtKalibrierung.HINTERGRUND_DAEMPFUNG), 1e-4, "Faktor"
	)


func test_fensterglut_rampe() -> void:
	assert_almost(CitySkyline.fensterglut(13.0), 0.0, 1e-6, "mittags Tagesglas")
	assert_almost(CitySkyline.fensterglut(22.0), 1.0, 1e-6, "nachts volle Glut")
	assert_almost(CitySkyline.fensterglut(3.0), 1.0, 1e-6, "vor Sonnenaufgang volle Glut")
	var abend := CitySkyline.fensterglut(18.5)
	assert_true(abend > 0.0 and abend < 1.0, "Abend-Rampe dazwischen")
	var morgen := CitySkyline.fensterglut(7.0)
	assert_true(morgen > 0.0 and morgen < 1.0, "Morgen-Rampe dazwischen")


func test_fensterfarbe_kippt_abends_ins_warme() -> void:
	var tag := CitySkyline.fensterfarbe(13.0)
	var nacht := CitySkyline.fensterfarbe(22.0)
	assert_true(tag.b > tag.r, "Tagesglas kühl (Himmelsspiegelung)")
	assert_true(nacht.r > nacht.b, "Abendglut warm (R > B)")


func test_luma_statistik_pure() -> void:
	var grau := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	grau.fill(Color(0.5, 0.5, 0.5))
	var mess := LichtMessung.luma_statistik(grau, 1)
	assert_almost(float(mess["mittel"]), 0.5, 0.01, "Konstantgrau → Mittel 0.5")
	assert_almost(float(mess["clip_hoch_prozent"]), 0.0, 1e-6, "kein Hoch-Clip")
	assert_almost(float(mess["clip_tief_prozent"]), 0.0, 1e-6, "kein Tief-Clip")
	var kontrast := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	kontrast.fill(Color(1.0, 1.0, 1.0))
	kontrast.fill_rect(Rect2i(0, 0, 32, 16), Color(0.0, 0.0, 0.0))
	var mess2 := LichtMessung.luma_statistik(kontrast, 1)
	assert_almost(float(mess2["mittel"]), 0.5, 0.01, "Halb/halb → Mittel 0.5")
	assert_almost(float(mess2["clip_hoch_prozent"]), 50.0, 0.5, "obere Hälfte clippt hell")
	assert_almost(float(mess2["clip_tief_prozent"]), 50.0, 0.5, "untere Hälfte clippt dunkel")
	var histogramm: Array = mess2["histogramm_16"]
	assert_almost(float(histogramm[0]), 0.5, 0.01, "Bin 0 = schwarze Hälfte")
	assert_almost(float(histogramm[15]), 0.5, 0.01, "Bin 15 = weiße Hälfte")
