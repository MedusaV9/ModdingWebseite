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


func _fresh_veil() -> LoadingVeil:
	LoadingVeil.clear_travel_hint()
	var veil: LoadingVeil = VEIL_SCENE.instantiate()
	mount(veil)
	return veil


func _cleanup(veil: LoadingVeil) -> void:
	LoadingVeil.clear_travel_hint()
	unmount(veil)
