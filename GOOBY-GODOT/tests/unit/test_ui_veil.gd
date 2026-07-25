extends W1cTestCase
## W4/POLISH-3+17: LoadingVeil-AC-Optik. Der W1a-Contract (cover/reveal
## awaitbar, Signale, set_progress, Node-Pfade Root/Backdrop/Spinner) wird
## weiter von tests/unit/test_loading_veil.gd gehalten — hier kommen die
## Optik-Varianten dazu: Minigame-Cover-Karte vs. Gooby-„Lädt…“-Karte,
## Tipp-Rotation, Progress-Bar und die geteilten Arcade-Cover-Texturen.

const VEIL_SCENE := preload("res://scripts/core/loading_veil.tscn")


func test_node_pfade_und_spinner_versteckt() -> void:
	var veil := _fresh_veil()
	check(veil.get_node_or_null("Root") != null, "Root-Pfad bleibt (W1a-Contract)")
	check(veil.get_node_or_null("Root/Backdrop") != null, "Root/Backdrop-Pfad bleibt")
	check(veil.get_node_or_null("Root/Spinner") != null, "Root/Spinner-Pfad bleibt")
	check(not (veil.get_node("Root/Spinner") as Control).visible, "Alt-Spinner ist ausgeblendet")
	check(veil.get_node("Root/Backdrop") is AcWallpaper, "Backdrop ist Drift-Wallpaper")
	check(veil.get_node_or_null("%Card") != null, "Mittige Karte existiert")
	_cleanup(veil)


func test_default_variante_huepfender_gooby() -> void:
	var veil := _fresh_veil()
	veil.prepare_for_travel(&"home")
	check((veil.get_node("%Gooby") as Control).visible, "Home-Reise: Mini-Gooby sichtbar")
	check((veil.get_node("%Laedt") as Control).visible, "Home-Reise: Lädt-Text sichtbar")
	check((veil.get_node("%Laedt") as Label).text != "", "Lädt-Text nicht leer")
	check(not (veil.get_node("%Cover") as Control).visible, "Home-Reise: kein Cover")
	check(not (veil.get_node("%Tip") as Control).visible, "Home-Reise: kein Tipp")
	check_eq((veil.get_node("Root/Backdrop") as AcWallpaper).pattern, "dots", "Pattern dots")
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
	check((veil.get_node("%Tip") as Control).visible, "Tipp sichtbar")
	check((veil.get_node("%Tip") as Label).text != "", "Tipp nicht leer")
	check(not (veil.get_node("%Gooby") as Control).visible, "MG-Reise: kein Gooby")
	check_eq((veil.get_node("Root/Backdrop") as AcWallpaper).pattern, "arcade", "Pattern arcade")
	# Hint überlebt die Kette Pregame→Host …
	veil.prepare_for_travel(&"mg_host")
	check((veil.get_node("%Cover") as Control).visible, "Hint gilt auch für mg_host")
	# … und räumt sich bei jedem anderen Ziel selbst auf.
	veil.prepare_for_travel(&"arcade")
	check(not (veil.get_node("%Cover") as Control).visible, "Nicht-MG-Ziel löscht den Hint")
	check((veil.get_node("%Gooby") as Control).visible, "zurück zur Gooby-Variante")
	veil.prepare_for_travel(&"mg_pregame")
	check(not (veil.get_node("%Cover") as Control).visible, "Hint wurde statisch gelöscht")
	_cleanup(veil)


func test_tipps_deutsch_5_bis_8_und_rotierend() -> void:
	var tips: Array = LoadingVeil._tips()
	check(tips.size() >= 5 and tips.size() <= 8, "5–8 Tipps (%d)" % tips.size())
	for tip: Variant in tips:
		check(str(tip).length() > 10, "Tipp ist ein echter Satz: %s" % str(tip))
	var veil := _fresh_veil()
	LoadingVeil.set_travel_hint({"game_id": "teaParty", "title": "T", "targets": [&"mg_pregame"]})
	veil.prepare_for_travel(&"mg_pregame")
	var first: String = (veil.get_node("%Tip") as Label).text
	veil._advance_tip()
	var second: String = (veil.get_node("%Tip") as Label).text
	check(first != second, "Tipp rotiert weiter")
	veil.prepare_for_travel(&"home")
	_cleanup(veil)


func test_progress_bar_zeigt_threaded_load() -> void:
	var veil := _fresh_veil()
	veil.set_progress(0.5)
	check((veil.get_node("%Progress") as Control).visible, "Progress sichtbar bei 0.5")
	check_approx((veil.get_node("%Progress") as ProgressBar).value, 0.5, "Wert übernommen")
	veil.set_progress(1.0)
	check(not (veil.get_node("%Progress") as Control).visible, "bei 1.0 wieder versteckt")
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
