extends TestCase
## RW-8: Die Ranch-Variante des LoadingVeils — voller Artwork-Schirm NUR bei
## langen Reisen, echter threaded-Fortschritt wird 1:1 durchgereicht (kein
## Fake-Balken), kurze Reisen behalten die kleine Karte, und der W1a-Contract
## (Node-Pfade, cover/reveal awaitbar) bleibt unangetastet.

const VEIL_SCENE := preload("res://scripts/core/loading_veil.tscn")


func test_lange_reise_zeigt_vollen_schirm() -> void:
	var veil := _fresh_veil()
	veil.stunde_override = 12.0
	veil.prepare_for_travel(&"ranch/hof")
	var screen: RanchLoadingScreen = veil.get_node_or_null("Root/RanchScreen")
	assert_true(screen != null, "RanchScreen wird eingehängt.")
	assert_true(screen.visible, "RanchScreen sichtbar bei langer Reise.")
	assert_false((veil.get_node("%Card") as Control).visible, "Kleine Karte versteckt.")
	assert_eq(screen.artwork_id(), "stall", "Hof-Reise nimmt das Stall-Artwork.")
	assert_true(screen.tip_text().length() > 20, "Tipp gesetzt.")
	_cleanup(veil)


func test_kurze_reise_behaelt_kleine_karte() -> void:
	var veil := _fresh_veil()
	veil.prepare_for_travel(&"ranch/hof")
	veil.prepare_for_travel(&"home")
	var screen: Control = veil.get_node_or_null("Root/RanchScreen")
	assert_true(screen == null or not screen.visible, "Kurze Reise: kein voller Schirm.")
	assert_true((veil.get_node("%Card") as Control).visible, "Kleine Karte wieder da.")
	assert_true((veil.get_node("%Gooby") as Control).visible, "Gooby-Variante aktiv.")
	_cleanup(veil)


func test_door_travel_zeigt_keinen_vollen_schirm() -> void:
	var veil := _fresh_veil()
	veil.prepare_for_travel(&"ranch/welt", LoadingScreenRules.DOOR_TRAVEL)
	var screen: Control = veil.get_node_or_null("Root/RanchScreen")
	assert_true(screen == null or not screen.visible, "DOOR_TRAVEL bleibt kurzer Cut.")
	assert_true((veil.get_node("%Card") as Control).visible, "Karte sichtbar.")
	_cleanup(veil)


func test_artwork_wechselt_mit_ziel_und_tageszeit() -> void:
	var veil := _fresh_veil()
	veil.stunde_override = 12.0
	veil.prepare_for_travel(&"ranch/welt")
	var screen: RanchLoadingScreen = veil.get_node("Root/RanchScreen")
	assert_eq(screen.artwork_id(), "galopp", "Weite Welt → Galopp-Artwork.")
	veil.stunde_override = 22.0
	veil.prepare_for_travel(&"ranch/welt")
	assert_eq(screen.artwork_id(), "nacht", "Nachts → Teich-Artwork.")
	_cleanup(veil)


## Echter Fortschritt: der Router speist set_progress mit dem threaded-Load-
## Stand — der Balken zeigt exakt diesen Wert, nie mehr (Ehrlichkeit).
func test_echter_fortschritt_wird_durchgereicht() -> void:
	var veil := _fresh_veil()
	veil.prepare_for_travel(&"ranch/hof")
	var screen: RanchLoadingScreen = veil.get_node("Root/RanchScreen")
	for wert: float in [0.1, 0.37, 0.62, 0.95]:
		veil.set_progress(wert)
		assert_almost(screen.progress_wert(), wert, 1e-4, "Balken == echter Stand %f" % wert)
	veil.set_progress(1.0)
	assert_almost(veil.get_progress(), 1.0, 1e-4, "Clamp-Contract bleibt.")
	_cleanup(veil)


func test_tipp_rotiert_im_vollen_schirm() -> void:
	var veil := _fresh_veil()
	veil.prepare_for_travel(&"ranch/hof")
	var screen: RanchLoadingScreen = veil.get_node("Root/RanchScreen")
	var erster := screen.tip_text()
	veil._advance_loading_tip()
	assert_ne(screen.tip_text(), erster, "Tipp rotiert weiter (Shuffle-Bag).")
	_cleanup(veil)


func test_w1a_contract_bleibt() -> void:
	var veil := _fresh_veil()
	veil.prepare_for_travel(&"ranch/hof")
	assert_true(veil.get_node_or_null("Root") != null, "Root-Pfad bleibt.")
	assert_true(veil.get_node_or_null("Root/Backdrop") != null, "Backdrop-Pfad bleibt.")
	assert_true(veil.get_node_or_null("Root/Spinner") != null, "Spinner-Pfad bleibt.")
	var events: Array = []
	veil.covered.connect(func() -> void: events.append("covered"))
	veil.revealed.connect(func() -> void: events.append("revealed"))
	await veil.cover(true)
	assert_true(veil.visible, "cover() macht sichtbar.")
	await veil.reveal(true)
	assert_false(veil.visible, "reveal() blendet aus.")
	assert_eq(events, ["covered", "revealed"] as Array, "Signal-Reihenfolge bleibt.")
	_cleanup(veil)


func test_minigame_hint_schlaegt_ranch_schirm() -> void:
	var veil := _fresh_veil()
	LoadingVeil.set_travel_hint({"game_id": "gvz", "title": "T", "targets": [&"ranch/hof"]})
	veil.prepare_for_travel(&"ranch/hof")
	var screen: Control = veil.get_node_or_null("Root/RanchScreen")
	assert_true(screen == null or not screen.visible, "Travel-Hint gewinnt.")
	assert_true((veil.get_node("%Tip") as Control).visible, "Minigame-Variante aktiv.")
	_cleanup(veil)


func _fresh_veil() -> LoadingVeil:
	LoadingVeil.clear_travel_hint()
	var veil: LoadingVeil = VEIL_SCENE.instantiate()
	tree.root.add_child(veil)
	return veil


func _cleanup(veil: LoadingVeil) -> void:
	LoadingVeil.clear_travel_hint()
	tree.root.remove_child(veil)
	veil.free()
