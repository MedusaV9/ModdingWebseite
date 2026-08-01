extends TestCase
## W16/G4 (P22) — Ladebild-Rest: ehrliche Boot-Gewichte, Möhren-Balken in
## Alt-Web-Optik samt Reduced-Motion-Verdrahtung, die Papier-Ladekarte des
## Boot-Covers mit „Lädt… NN%“-Zeile + Spruch-Crossfade, und der Ranch-
## Vollbildschirm, der die G2-Veil-Bausteine (Balken/Sticker) konsumiert.

const GOOBY_ALT_PFAD := "res://scripts/core/loading_veil_gooby.gd"


## bootperf §4.3: "packs"/"save" laufen VOR dem ersten Frame — ihr Gewicht
## ist jetzt klein, damit der Balken nicht mehr bei 22 % startet. Die
## beobachtbare Arbeit ("welt" threaded Warmup) traegt die groesste Spanne.
func test_phasen_gewichte_ehrlich() -> void:
	var startsprung := BootPhasen.prozent("save", 1.0)
	assert_true(startsprung <= 0.10, "Startsprung klein (war 22 %%): %f" % startsprung)
	var welt_spanne := BootPhasen.prozent("welt", 1.0) - BootPhasen.prozent("welt", 0.0)
	for id: String in BootPhasen.phasen_ids():
		var spanne := BootPhasen.prozent(id, 1.0) - BootPhasen.prozent(id, 0.0)
		assert_true(welt_spanne >= spanne, "welt traegt die groesste Spanne (vs %s)" % id)
	assert_almost(BootPhasen.prozent("zuhause", 1.0), 1.0, 1e-6, "Ende bleibt 1.0.")


## RM-Entscheid P22: Reduced Motion friert das Balken-Gleiten ein — die
## Anzeige springt aufs ECHTE Ziel (nie voraus), animiert gleitet sie nach.
func test_ladebalken_reduced_motion_springt_aufs_ziel() -> void:
	var balken := BootLadebalken.new()
	tree.root.add_child(balken)
	await wait_frames(1)
	balken.set_animated(false)
	balken.set_progress(0.5)
	assert_almost(balken.anzeige_wert(), 0.5, 1e-6, "RM: Anzeige springt sofort.")
	balken.set_animated(true)
	balken.set_progress(0.9)
	assert_true(balken.anzeige_wert() < 0.9, "Animiert: Anzeige gleitet hinterher.")
	balken.set_animated(false)
	assert_almost(balken.anzeige_wert(), 0.9, 1e-6, "RM mitten im Gleiten: Sprung.")
	balken.queue_free()
	await wait_frames(1)


## Die Papier-Ladekarte unten (Web .mg-loading-card): Papier-Fond, runde
## Ecken, darin Spruch + Möhren-Balken + „Lädt… NN%“-Zeile (Prozent NUR
## bei echtem Fortschritt, Web-Regel aus loadingVeil.js progress()).
func test_boot_cover_karte_und_laedt_zeile() -> void:
	var cover := BootCoverScreen.new()
	cover.spruch_seed = 7
	cover.reduced_motion_override = 1
	tree.root.add_child(cover)
	await wait_frames(1)
	var karte: PanelContainer = cover.get_node("Root/Unten/Karte")
	assert_true(karte != null, "Papier-Karte haengt unter Root/Unten.")
	var stil := karte.get_theme_stylebox("panel") as StyleBoxFlat
	assert_true(stil != null, "Karte traegt einen StyleBoxFlat.")
	assert_eq(stil.bg_color, AcTokens.PAPER, "Karten-Fond ist Web-Papier.")
	assert_true(stil.corner_radius_top_left > 0, "Runde Web-Karten-Ecken.")
	var balken: BootLadebalken = karte.find_child("Balken", true, false)
	var laedt: Label = karte.find_child("Laedt", true, false)
	var spruch: Label = karte.find_child("Spruch", true, false)
	assert_true(balken != null and laedt != null and spruch != null, "Karte komplett.")
	assert_true(spruch.text.length() > 8, "Spruch steht in der Karte.")
	cover.set_progress(0.42)
	assert_true(laedt.text.ends_with("42%"), "Laedt-Zeile haengt Prozent an: %s" % laedt.text)
	assert_almost(balken.anzeige_wert(), 0.42, 1e-6, "RM-Verdrahtung: Balken springt.")
	cover.set_progress(1.0)
	assert_false(laedt.text.contains("%"), "Bei vollem Fortschritt: kein Prozent-Anhang.")
	var artwork: TextureRect = cover.get_node("Root/Artwork")
	var geladen := await wait_until(func() -> bool: return artwork.texture != null, 8000)
	assert_true(geladen, "Threaded Cover-Artwork trifft ein (E2a bleibt).")
	cover.queue_free()
	await wait_frames(1)


## Spruch-Wechsel: Reduced Motion wechselt HART (sofort neuer Text), der
## animierte Pfad crossfadet (Web .mg-loading-tip transition, 200 ms).
func test_boot_cover_spruch_crossfade_und_rm_hart() -> void:
	var cover := BootCoverScreen.new()
	cover.spruch_seed = 7
	cover.reduced_motion_override = 1
	tree.root.add_child(cover)
	await wait_frames(1)
	var vorher := cover.spruch_text()
	cover._rotiere_spruch()
	assert_ne(cover.spruch_text(), vorher, "RM: neuer Spruch ohne Fade, sofort.")
	cover.queue_free()
	var animiert := BootCoverScreen.new()
	animiert.spruch_seed = 7
	animiert.reduced_motion_override = 0
	tree.root.add_child(animiert)
	await wait_frames(1)
	var alter_text := animiert.spruch_text()
	animiert._rotiere_spruch()
	assert_eq(animiert.spruch_text(), alter_text, "Crossfade: erst ausblenden.")
	var gewechselt := await wait_until(
		func() -> bool: return animiert.spruch_text() != alter_text, 2000
	)
	assert_true(gewechselt, "Crossfade wechselt den Spruch nach dem Fade-Out.")
	var spruch_label := animiert.find_child("Spruch", true, false) as Label
	var wieder_da := await wait_until(func() -> bool: return spruch_label.modulate.a > 0.99, 2000)
	assert_true(wieder_da, "Crossfade blendet wieder voll ein.")
	animiert.queue_free()
	await wait_frames(1)


## Der Ranch-Vollbildschirm konsumiert die G2-Karten-Bausteine: der Balken
## ist der Teal-Verlaufsbalken, der Hopser der runde Motiv-Sticker — der
## alte Vektor-Gooby (loading_veil_gooby.gd) ist abgeloest und geloescht.
func test_ranch_screen_konsumiert_g2_bausteine() -> void:
	var screen := RanchLoadingScreen.new()
	tree.root.add_child(screen)
	await wait_frames(1)
	screen.zeige("stall")
	var progress: ProgressBar = screen.find_child("Progress", true, false)
	var gooby: Control = screen.find_child("Gooby", true, false)
	assert_true(progress is LoadingVeilBalken, "Balken = G2-Teal-Verlaufsbalken.")
	assert_true(gooby is LoadingVeilSticker, "Hopser = G2-Motiv-Sticker.")
	screen.set_animated(true)
	assert_true((gooby as LoadingVeilSticker).is_animated(), "Sticker huepft animiert.")
	screen.set_animated(false)
	assert_false((gooby as LoadingVeilSticker).is_animated(), "RM friert den Sticker ein.")
	var laedt: Label = screen.find_child("Laedt", true, false)
	screen.set_progress(0.62)
	assert_almost(screen.progress_wert(), 0.62, 1e-4, "Echter Fortschritt 1:1.")
	assert_true(laedt.text.ends_with("62%"), "Laedt-Zeile mit Prozent: %s" % laedt.text)
	screen.set_progress(1.0)
	assert_false(laedt.text.contains("%"), "Fertig → nackte Laedt-Zeile.")
	assert_false(ResourceLoader.exists(GOOBY_ALT_PFAD), "Alter Vektor-Gooby ist geloescht.")
	screen.queue_free()
	await wait_frames(1)


## Strings: „Lädt…“-Basis existiert DE+EN (die Zeile speist Cover UND
## Ranch-Schirm); die Boot-Sprueche bleiben bei 10 (w14-Assert unberuehrt).
func test_laedt_strings_de_en_vorhanden() -> void:
	I18nService.reset_cache()
	for locale: String in ["de", "en"]:
		var basis := str(I18nService.table(locale).get("loading.laedt", ""))
		assert_true(basis.length() >= 4, "loading.laedt fehlt in %s" % locale)
	var domain_sprueche := I18nService.items_aus_domain("loading", "loading.boot.sprueche")
	assert_eq(
		domain_sprueche,
		I18nService.items("loading.boot.sprueche"),
		"Domain-Teillade-Pfad liefert dieselben Sprueche wie die volle Tabelle."
	)
