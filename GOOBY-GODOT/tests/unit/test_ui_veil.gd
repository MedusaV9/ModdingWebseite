extends W1cTestCase
## W16/VEIL: LoadingVeil-Karte im Look der alten Web-Version. Der
## W1a-Contract (cover/reveal awaitbar, Signale, set_progress, Node-Pfade
## Root/Backdrop/Spinner) wird weiter von tests/unit/test_loading_veil.gd
## gehalten — hier kommen die Optik-Varianten dazu: die drei Karten-Modi
## home/trip/game (Titel, Ready-Zeile, Cover, Motiv-Sticker), das statische
## Blätter-Pattern, Tipp-Rotation je Modus, Indeterminate-Sweep vs. echter
## Balken und die geteilten Arcade-Cover-Texturen.
##
## Bewusste W16-Anpassung (Spez ladebild-alt.md §2.4): statt EINEM
## `veil.tips`-Pool (5–8) gibt es je Modus einen eigenen Pool mit den
## 3 Web-Tipps im Original-Wortlaut — geprüft werden jetzt 3–8 Tipps je
## Modus plus DE/EN-Parität.

const VEIL_SCENE := preload("res://scripts/core/loading_veil.tscn")
const MODI: Array[String] = ["home", "trip", "game"]
## W16/G2b: Petal-Sweep-Wipe (Maske+Stempel auf/über dem FROZEN Root).
const VeilWipe := preload("res://scripts/core/loading_veil_wipe.gd")


func test_node_pfade_und_spinner_versteckt() -> void:
	var veil := _fresh_veil()
	check(veil.get_node_or_null("Root") != null, "Root-Pfad bleibt (W1a-Contract)")
	check(veil.get_node_or_null("Root/Backdrop") != null, "Root/Backdrop-Pfad bleibt")
	check(veil.get_node_or_null("Root/Spinner") != null, "Root/Spinner-Pfad bleibt")
	check(not (veil.get_node("Root/Spinner") as Control).visible, "Alt-Spinner ist ausgeblendet")
	check(veil.get_node("Root/Backdrop") is AcWallpaper, "Backdrop ist AcWallpaper")
	var backdrop := veil.get_node("Root/Backdrop") as AcWallpaper
	check_eq(backdrop.pattern, "leaves", "Vorhang trägt das Blätter-Pattern (Web .acui-veil)")
	check_eq(backdrop.drift, Vector2.ZERO, "Vorhang ist STATISCH (Web: kein Drift)")
	check(veil.get_node_or_null("%Card") != null, "Mittige Karte existiert")
	_cleanup(veil)


func test_home_variante_alte_karte() -> void:
	var veil := _fresh_veil()
	veil.prepare_for_travel(&"home")
	check((veil.get_node("%Cover") as Control).visible, "Home-Reise: Heim-Cover sichtbar")
	check(
		(veil.get_node("%Cover") as TextureRect).texture == load(LoadingVeil.COVER_HOME_PFAD),
		"Cover-Zone nutzt das portierte veil_home_cover"
	)
	check_eq(
		(veil.get_node("%Title") as Label).text,
		I18nService.t("veil.home.titel"),
		"Titel „Trautes Heim“"
	)
	check_eq(
		(veil.get_node("%Ready") as Label).text,
		I18nService.t("veil.home.bereit"),
		"Ready-Zeile „Auf dem Heimweg…“"
	)
	check((veil.get_node("%Gooby") as Control).visible, "Motiv-Sticker sichtbar")
	check((veil.get_node("%Laedt") as Control).visible, "Lädt-Text sichtbar")
	check((veil.get_node("%Laedt") as Label).text != "", "Lädt-Text nicht leer")
	check((veil.get_node("%Tip") as Control).visible, "Home-Reise: Tipp sichtbar (Web-Parität)")
	check((veil.get_node("%Tip") as Label).text != "", "Tipp nicht leer")
	_cleanup(veil)


func test_trip_variante_fuer_shop_und_stadt() -> void:
	check_eq(LoadingVeil.modus_fuer_ziel(&"ikea"), "trip", "Shop-Reise = trip")
	check_eq(LoadingVeil.modus_fuer_ziel(&"city"), "trip", "Stadt-Reise = trip")
	check_eq(LoadingVeil.modus_fuer_ziel(&"city/ort/tierarzt"), "trip", "Klinik (Stadt-Ort) = trip")
	check_eq(LoadingVeil.modus_fuer_ziel(&"home"), "home", "Rückkehr = home")
	check_eq(LoadingVeil.modus_fuer_ziel(&"home/kitchen"), "home", "Hausraum = home")
	check_eq(LoadingVeil.modus_fuer_ziel(&"arcade"), "home", "Sonstige Screens = home")
	var veil := _fresh_veil()
	veil.prepare_for_travel(&"ikea")
	check_eq(
		(veil.get_node("%Title") as Label).text,
		I18nService.t("veil.trip.titel"),
		"Titel „Auf geht’s!“"
	)
	check_eq(
		(veil.get_node("%Ready") as Label).text,
		I18nService.t("veil.trip.bereit"),
		"Ready-Zeile „Zeit für einen kleinen Ausflug…“"
	)
	check((veil.get_node("%Cover") as Control).visible, "Trip nutzt ebenfalls das Heim-Cover")
	_cleanup(veil)


func test_minigame_variante_cover_titel_tipp() -> void:
	var veil := _fresh_veil()
	var cover := ArcadeScreen.cover_texture("gvz")
	check(cover != null, "GvZ-Cover auflösbar")
	var hint := {
		"game_id": "gvz",
		"title": "Goobys vs Zombies",
		"cover": cover,
		"targets": [&"mg_pregame", &"mg_host"],
	}
	LoadingVeil.set_travel_hint(hint)
	veil.prepare_for_travel(&"mg_pregame")
	check((veil.get_node("%Cover") as Control).visible, "MG-Reise: Cover sichtbar")
	check_eq(
		(veil.get_node("%Cover") as TextureRect).texture,
		ArcadeScreen.COVERS["gvz"],
		"Veil nutzt DIESELBE preloaded Textur wie die Arcade-Kachel"
	)
	check_eq((veil.get_node("%Title") as Label).text, "Goobys vs Zombies", "Titel gesetzt")
	check_eq(
		(veil.get_node("%Ready") as Label).text,
		I18nService.t("veil.game.bereit"),
		"Ready-Zeile „Mach dich bereit!“"
	)
	check((veil.get_node("%Tip") as Control).visible, "Tipp sichtbar")
	check((veil.get_node("%Tip") as Label).text != "", "Tipp nicht leer")
	check((veil.get_node("%Gooby") as Control).visible, "Game-Motiv-Sticker sichtbar")
	# Hint überlebt die Kette Pregame→Host …
	veil.prepare_for_travel(&"mg_host")
	check_eq(
		(veil.get_node("%Cover") as TextureRect).texture,
		ArcadeScreen.COVERS["gvz"],
		"Hint gilt auch für mg_host"
	)
	# … und räumt sich bei jedem anderen Ziel selbst auf.
	veil.prepare_for_travel(&"arcade")
	check(
		(veil.get_node("%Cover") as TextureRect).texture != ArcadeScreen.COVERS["gvz"],
		"Nicht-MG-Ziel löscht den Hint (zurück zum Heim-Cover)"
	)
	check_eq(
		(veil.get_node("%Title") as Label).text,
		I18nService.t("veil.home.titel"),
		"zurück zur Home-Variante"
	)
	veil.prepare_for_travel(&"mg_pregame")
	check(
		(veil.get_node("%Cover") as TextureRect).texture != ArcadeScreen.COVERS["gvz"],
		"Hint wurde statisch gelöscht"
	)
	_cleanup(veil)


func test_tipps_je_modus_mit_en_paritaet_und_rotation() -> void:
	for modus in MODI:
		var key := LoadingVeil.tips_key(modus)
		var de: Array = I18nService.table("de").get(key, [])
		var en: Array = I18nService.table("en").get(key, [])
		check(de.size() >= 3 and de.size() <= 8, "3–8 Tipps im Modus %s (%d)" % [modus, de.size()])
		check_eq(en.size(), de.size(), "EN-Parität im Modus %s" % modus)
		for tip: Variant in de:
			check(str(tip).length() > 10, "Tipp ist ein echter Satz: %s" % str(tip))
	var veil := _fresh_veil()
	veil.prepare_for_travel(&"home")
	var first: String = (veil.get_node("%Tip") as Label).text
	veil._advance_tip()
	var second: String = (veil.get_node("%Tip") as Label).text
	check(first != second, "Tipp rotiert weiter")
	_cleanup(veil)


func test_progress_bar_zeigt_threaded_load() -> void:
	var veil := _fresh_veil()
	check((veil.get_node("%Sweep") as Control).visible, "Ohne Fortschritt: Sweep sichtbar")
	veil.set_progress(0.5)
	check((veil.get_node("%Progress") as Control).visible, "Progress sichtbar bei 0.5")
	check_approx((veil.get_node("%Progress") as ProgressBar).value, 0.5, "Wert übernommen")
	check(
		not (veil.get_node("%Sweep") as Control).visible,
		"Echter Balken sichtbar → Sweep weicht (Web-Regel)"
	)
	check(
		(veil.get_node("%Laedt") as Label).text.contains("50%"),
		"„Lädt… NN%“ nur bei echtem Fortschritt"
	)
	veil.set_progress(1.0)
	check(not (veil.get_node("%Progress") as Control).visible, "bei 1.0 wieder versteckt")
	check((veil.get_node("%Sweep") as Control).visible, "Sweep kehrt zurück")
	check_eq(
		(veil.get_node("%Laedt") as Label).text,
		I18nService.t("veil.laedt"),
		"ohne Fortschritt kein Prozent-Text"
	)
	veil.set_progress(-2.0)
	check_approx(veil.get_progress(), 0.0, "Clamp bleibt (W1a-Contract)")
	_cleanup(veil)


func test_cover_und_blende_awaitbar() -> void:
	var veil := _fresh_veil()
	var events: Array = []
	veil.covered.connect(func() -> void: events.append("covered"))
	veil.revealed.connect(func() -> void: events.append("revealed"))
	await veil.cover(false)
	check(veil.visible, "cover() macht sichtbar")
	check_approx((veil.get_node("Root") as Control).modulate.a, 1.0, "sanft voll eingeblendet")
	check_eq((veil.get_node("%Card") as Control).scale, Vector2.ONE, "Karten-Pop endet bei 1.0")
	await veil.reveal(false)
	check(not veil.visible, "reveal() blendet aus")
	check_eq(events, ["covered", "revealed"] as Array, "Signal-Reihenfolge bleibt")
	_cleanup(veil)


func test_arcade_cover_preload_und_gobnom() -> void:
	for id in ["teaParty", "carrotCatch", "gvz", "gobnom"]:
		check(ArcadeScreen.COVERS.has(id), "Cover compile-zeitig preloaded: %s" % id)
		check_eq(
			ArcadeScreen.cover_texture(id), ArcadeScreen.COVERS[id], "cover_texture == preload"
		)
	check(ArcadeScreen.cover_texture("gibtsnicht") == null, "unbekanntes Spiel → null")


## W16/G2b: Varianten-Weiche wie Web veilWipeVariant + Ehrlichkeits-Deckel
## (test_loading_regeln pinnt Blenden ≤ 0.4 s → Web-450-ms bewusst 400 ms).
func test_wipe_varianten_weiche_und_ehrlichkeits_deckel() -> void:
	check_eq(VeilWipe.wipe_variante(true), "fade", "Reduced Motion → fade")
	check_eq(
		VeilWipe.wipe_variante(true, false), "fade", "Reduced Motion schlägt den Iris-Fallback"
	)
	check_eq(VeilWipe.wipe_variante(false, false), "iris", "ohne Stempel-Zeichner → Kreis-Wipe")
	check_eq(VeilWipe.wipe_variante(false), "petal", "Standard → Petal-Sweep")
	check(VeilWipe.PETAL_S <= 0.4, "Petal-Wipe hält den ≤-0.4-s-Deckel (Web: 450 ms)")
	check(VeilWipe.IRIS_REIN_S <= 0.4 and VeilWipe.IRIS_RAUS_S <= 0.4, "Iris bleibt ≤ 0.4 s")
	check_approx(LoadingVeil.COVER_DURATION, VeilWipe.PETAL_S, "Einblende = Petal-Dauer")
	check_approx(LoadingVeil.REVEAL_DURATION, VeilWipe.PETAL_S, "Ausblende = Petal-Dauer")


func test_wipe_petal_feld_deterministisch_mit_web_parametern() -> void:
	var feld := VeilWipe.petal_feld()
	check_eq(feld.size(), 26, "26 Stempel je Wipe (Web PETAL.COUNT)")
	check_eq(str(feld), str(VeilWipe.petal_feld()), "LCG-Feld (Seed 7) ist deterministisch")
	var rosa := 0
	for blatt: Dictionary in feld:
		if int(blatt["sprite"]) == 0:
			rosa += 1
		var groesse := float(blatt["size"])
		check(groesse >= 0.035 and groesse <= 0.06, "Größe 3,5–6 %% der kurzen Seite: %s" % groesse)
		var lane := float(blatt["lane"])
		check(lane >= 0.0 and lane <= 1.0, "Lane bleibt im Viewport: %s" % lane)
	check(rosa > feld.size() - rosa, "überwiegend rosa Blüten (~72 %)")
	check(rosa < feld.size(), "…aber auch grüne Blätter im Feld")


func test_wipe_stempel_pose_und_clip_keyframes() -> void:
	var blatt: Dictionary = VeilWipe.petal_feld()[0]
	check_approx(float(VeilWipe.stempel_pose(blatt, 0.0)["alpha"]), 0.0, "Alpha blendet am Anfang")
	check_approx(float(VeilWipe.stempel_pose(blatt, 1.0)["alpha"]), 0.0, "…und am Wipe-Ende")
	check_approx(float(VeilWipe.stempel_pose(blatt, 0.5)["alpha"]), 1.0, "voll sichtbar mittig")
	check(
		(
			float(VeilWipe.stempel_pose(blatt, 0.8)["x"])
			> float(VeilWipe.stempel_pose(blatt, 0.2)["x"])
		),
		"Wischkante läuft links→rechts"
	)
	var oben := {"lane": 0.0, "ahead": 0.0, "phase": 0.0, "sway": 0.0, "spin": 0.0}
	var unten := {"lane": 1.0, "ahead": 0.0, "phase": 0.0, "sway": 0.0, "spin": 0.0}
	check_approx(
		(
			float(VeilWipe.stempel_pose(oben, 0.5)["x"])
			- float(VeilWipe.stempel_pose(unten, 0.5)["x"])
		),
		VeilWipe.SLANT,
		"Oberkante eilt 15 % voraus (Slant)"
	)
	var g := Vector2(1000.0, 500.0)
	var halb := VeilWipe.clip_punkte_rein(0.5, g)
	check_approx(halb[1].x, 575.0, "Cover-Kante oben bei u·115 % (Web-Keyframe)")
	check_approx(halb[2].x, 425.0, "Unterkante 15 % dahinter")
	var voll := VeilWipe.clip_punkte_rein(1.0, g)
	check_approx(voll[1].x, 1150.0, "Web-Endpolygon: 115 % oben")
	check_approx(voll[2].x, 1000.0, "Web-Endpolygon: 100 % unten")
	var raus := VeilWipe.clip_punkte_raus(0.5, g)
	check_approx(raus[0].x, 575.0, "Reveal-Frontier: identische Kanten-Mathe")
	check_approx(raus[3].x, 425.0, "…mit vorauseilender Oberkante")


## Der Wipe animiert NUR die Maske — die FROZEN Endwerte des W1a-Contracts
## (modulate 1.0/0.0, visible) müssen nach cover/reveal exakt stimmen und
## der Clip darf im Ruhezustand nicht aktiv bleiben.
func test_wipe_endzustaende_und_reduced_motion() -> void:
	var veil := _fresh_veil()
	var root := veil.get_node("Root") as Control
	await veil.cover(false)
	check_approx(root.modulate.a, 1.0, "cover endet voll deckend (W1a-Endwert)")
	check_eq(root.clip_children, CanvasItem.CLIP_CHILDREN_DISABLED, "Clip-Maske nach cover aus")
	check_eq(
		(veil.get_node("%Card/Clip") as CanvasItem).clip_children,
		CanvasItem.CLIP_CHILDREN_AND_DRAW,
		"runder Karten-Clip nach dem Wipe exakt restauriert (pausiert nur währenddessen)"
	)
	var stempel := veil.get_node_or_null("WipeStempel") as Control
	check(stempel != null, "Petal-Stempel-Overlay wurde erzeugt")
	check(stempel != null and not stempel.visible, "…und ruht nach dem Wipe")
	await veil.reveal(false)
	check_approx(root.modulate.a, 0.0, "reveal endet transparent (W1a-Endwert)")
	check_eq(root.clip_children, CanvasItem.CLIP_CHILDREN_DISABLED, "Clip-Maske nach reveal aus")
	check(not veil.visible, "Veil unsichtbar nach reveal")
	_cleanup(veil)
	var ruhig := _fresh_veil()
	var ruhig_root := ruhig.get_node("Root") as Control
	await ruhig.cover(true)
	check(ruhig.get_node_or_null("WipeStempel") == null, "Reduced Motion: keine Stempel")
	check_eq(
		ruhig_root.clip_children,
		CanvasItem.CLIP_CHILDREN_DISABLED,
		"Reduced Motion: keine Clip-Maske"
	)
	check_approx(ruhig_root.modulate.a, 1.0, "Reduced Motion: instantan deckend")
	await ruhig.reveal(true)
	check_approx(ruhig_root.modulate.a, 0.0, "Reduced Motion: instantan transparent")
	_cleanup(ruhig)


func _fresh_veil() -> LoadingVeil:
	LoadingVeil.clear_travel_hint()
	var veil: LoadingVeil = VEIL_SCENE.instantiate()
	mount(veil)
	return veil


func _cleanup(veil: LoadingVeil) -> void:
	LoadingVeil.clear_travel_hint()
	unmount(veil)
