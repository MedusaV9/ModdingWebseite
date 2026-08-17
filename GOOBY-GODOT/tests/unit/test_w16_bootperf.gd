extends TestCase
## W16/BOOTPERF — risikoarme Bootzeit-Gewinne (Bericht g1/bootperf.md §4):
## 1. Lazy-Strings (E8/B3): der Domain-Teillade-Pfad des I18nService liefert
##    die Boot-Sprüche identisch zu items(), OHNE die volle Locale
##    (77 Dateien) zu laden — der erste Frame parst nur loading.json.
## 2. Warmup-Liste (E3/B5+B6): _lade_welt fordert neben dem Einstieg die
##    späteren Synchron-Loads threaded an — alle Ziele existieren, die
##    Gewichte summieren sich auf 1.0, der Einstieg bleibt das erste Ziel.

const MainScript := preload("res://scripts/boot/main.gd")


func test_domain_teillade_liefert_sprueche_ohne_vollen_locale_load() -> void:
	I18nService.reset_cache()
	var sprueche := I18nService.items_aus_domain("loading", BootCoverScreen.SPRUECHE_KEY)
	assert_false(sprueche.is_empty(), "Domain-Pfad findet die Boot-Sprüche.")
	assert_true(
		I18nService._tables.is_empty(),
		"Teillade-Pfad lädt NICHT die volle Locale (der Voll-Load bleibt lazy)."
	)
	var voll := I18nService.items(BootCoverScreen.SPRUECHE_KEY)
	assert_eq(sprueche, voll, "Domain-Pfad und items() liefern dieselben Sprüche.")
	assert_false(I18nService._tables.is_empty(), "items() lädt die volle Tabelle wie bisher.")


func test_domain_teillade_faellt_auf_items_zurueck() -> void:
	I18nService.reset_cache()
	# Key liegt NICHT in loading.json → items()-Fallback (volle Tabelle).
	var items := I18nService.items_aus_domain("loading", "veil.home.tips")
	assert_false(items.is_empty(), "Fremder Key kommt über den items()-Fallback an.")
	assert_eq(items, I18nService.items("veil.home.tips"), "Fallback identisch zu items().")
	# Nach dem Voll-Load nimmt der Domain-Pfad direkt die volle Tabelle.
	var sprueche := I18nService.items_aus_domain("loading", BootCoverScreen.SPRUECHE_KEY)
	assert_eq(sprueche, I18nService.items(BootCoverScreen.SPRUECHE_KEY))
	I18nService.reset_cache()


func test_warmup_ziele_existieren_und_gewichte_summieren_auf_1() -> void:
	var ziele: Array[Dictionary] = MainScript.warmup_ziele()
	assert_true(ziele.size() >= 2, "Warmup-Liste enthält Einstieg + Extras.")
	assert_eq(
		str(ziele[0]["pfad"]),
		MainScript.ENTRY_SCENE_PATH,
		"Der Zuhause-Einstieg bleibt das erste (dominante) Ziel."
	)
	var gewicht_summe := 0.0
	var pfade: Array[String] = []
	for ziel in ziele:
		var pfad := str(ziel["pfad"])
		pfade.append(pfad)
		assert_true(ResourceLoader.exists(pfad), "Warmup-Ziel existiert: %s" % pfad)
		assert_true(float(ziel["gewicht"]) > 0.0, "Gewicht positiv: %s" % pfad)
		gewicht_summe += float(ziel["gewicht"])
	assert_almost(gewicht_summe, 1.0, 1e-6, "Gewichte decken den ganzen Balken ab.")
	assert_true(pfade.has("res://scripts/ui/hud.tscn"), "HUD wird vorgewärmt (B6).")
	assert_true(pfade.has("res://assets/character/gooby.glb"), "Gooby-Rig wird vorgewärmt (B6).")
	assert_true(
		pfade.has(str(RoomDefs.route_table().get(RoomDefs.route_target("living"), ""))),
		"Die Start-Raum-Szene (Wohnzimmer) wird vorgewärmt (B5)."
	)
	assert_true(
		pfade.has(MusicRegistry.path(MusicRegistry.track_for("home"))),
		"Der Home-Musik-Track wird vorgewärmt (B6: Reveal-Moment-Hänger)."
	)
