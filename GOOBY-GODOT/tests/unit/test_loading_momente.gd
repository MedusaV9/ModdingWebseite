extends TestCase
## RW-8: Ankunfts-/Belohnungsmomente — Einmal-pro-Save-Gate (additiver
## Save-Unterschlüssel, Self-Heal, KEIN Version-Bump), Titelkarten blockieren
## nie den Input, und die Moment-Strings existieren DE/EN.


func test_einmal_pro_save_gate() -> void:
	var gs := GsStub.new()
	assert_true(RanchMoments.sollte_zeigen(gs, "willkommen"), "Erstes Mal → zeigen.")
	assert_false(RanchMoments.sollte_zeigen(gs, "willkommen"), "Zweites Mal → still.")
	assert_true(RanchMoments.sollte_zeigen(gs, "zone:see"), "Andere Momente unabhängig.")
	assert_true(RanchMoments.sollte_zeigen(gs, "zone:waeldchen"))
	assert_false(RanchMoments.sollte_zeigen(gs, "zone:see"), "Zone bleibt gemerkt.")
	var daten: Dictionary = gs.get_value(RanchMoments.SAVE_KEY, {})
	assert_eq(int(daten.get("v", 0)), 1, "Versionierter Unterschlüssel.")
	assert_true((daten.get("gesehen") as Array).has("willkommen"), "Persistiert im Save.")


func test_gate_heilt_kaputte_daten() -> void:
	var gs := GsStub.new()
	gs.set_value(RanchMoments.SAVE_KEY, "kaputt")
	assert_true(RanchMoments.sollte_zeigen(gs, "willkommen"), "Self-Heal statt Crash.")
	assert_false(RanchMoments.sollte_zeigen(gs, "willkommen"), "Danach normal gemerkt.")
	assert_true(RanchMoments.sollte_zeigen(null, "egal"), "Ohne GameState kein Crash.")


func test_zonen_titelkarte_blockiert_keinen_input() -> void:
	var momente := RanchMoments.new()
	momente.game_state_override = GsStub.new()
	tree.root.add_child(momente)
	await wait_frames(1)
	momente.zone_entdeckt("see")
	await wait_frames(1)
	var karte: Control = momente.get_node_or_null("Root/Moment")
	assert_true(karte != null, "Titelkarte wird eingeblendet.")
	assert_eq(
		int(karte.mouse_filter), int(Control.MOUSE_FILTER_IGNORE), "Karte frisst keinen Input."
	)
	var titel: Label = karte.get_node("Titel")
	assert_true(titel.text.length() > 0, "Zonenname steht auf der Karte.")
	assert_ne(titel.text, "rwelt.zone.see", "Zonenname ist lokalisiert, kein roher Key.")
	var wurzel: Control = momente.get_node("Root")
	assert_eq(
		int(wurzel.mouse_filter), int(Control.MOUSE_FILTER_IGNORE), "Overlay frisst nie Input."
	)
	tree.root.remove_child(momente)
	momente.free()


func test_turniersieg_und_fohlen_karten() -> void:
	var momente := RanchMoments.new()
	momente.game_state_override = GsStub.new()
	tree.root.add_child(momente)
	await wait_frames(1)
	momente.turniersieg()
	await wait_frames(1)
	var karte: Control = momente.get_node_or_null("Root/Moment")
	assert_true(karte != null, "Turniersieg-Karte da.")
	assert_eq(
		(karte.get_node("Titel") as Label).text,
		I18nService.t("loading.moment.turniersieg"),
		"Sieg-Titel gesetzt."
	)
	momente.fohlen_geboren("Flöckchen")
	await wait_frames(1)
	var fohlen: Control = momente.get_node_or_null("Root/Moment")
	assert_true(fohlen != null, "Fohlen-Karte ersetzt die alte.")
	assert_true(
		(fohlen.get_node("Untertitel") as Label).text.contains("Flöckchen"),
		"Fohlen-Name im Untertitel."
	)
	tree.root.remove_child(momente)
	momente.free()


func test_moment_strings_de_en() -> void:
	I18nService.reset_cache()
	var keys := [
		"loading.moment.willkommen",
		"loading.moment.willkommen_sub",
		"loading.moment.entdeckt",
		"loading.moment.turniersieg",
		"loading.moment.turniersieg_sub",
		"loading.moment.fohlen",
		"loading.moment.fohlen_sub",
	]
	for key: String in keys:
		assert_true(I18nService.table("de").has(key), "DE-String fehlt: %s" % key)
		assert_true(I18nService.table("en").has(key), "EN-String fehlt: %s" % key)


## GameState-Double (get_value/set_value wie das echte Interface).
class GsStub:
	extends RefCounted

	var werte: Dictionary = {}

	func get_value(path: String, default: Variant = null) -> Variant:
		return werte.get(path, default)

	func set_value(path: String, value: Variant) -> void:
		werte[path] = value
