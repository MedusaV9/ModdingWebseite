extends TestCase
## M2/ORTE — Ort-Katalog (Doc E §2.1): Karte↔Katalog-Konsistenz der fünf
## neuen Orte (POW!, Post, Autohaus, Baumarkt, Wochenmarkt), Öffnungszeiten
## (Wochenmarkt NUR samstags 8–14 Uhr) und die Erst-Besuch-Buchführung.
##
## Der Test läuft gegen die ECHTE city_map.json — er ist damit gleichzeitig
## das Netz gegen „Szene im Katalog eingetragen, aber Datei fehlt“.

## Die fünf Orte aus dem ORTE-Auftrag.
const NEUE_ORTE: Array[String] = ["pow", "post", "autohaus", "baumarkt", "wochenmarkt"]
const SONNTAG := 0
const FREITAG := 5
const SAMSTAG := 6


## GameState-Double: dotted get/set + update(mutator) wie /root/GameState.
class FakeGameState:
	extends RefCounted
	var state: Dictionary = {"city": {}, "inventory": {"items": {}, "food": {}}}
	var slices_notified: Array[String] = []

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var node: Variant = state
		for part in path.split("."):
			if node is Dictionary and (node as Dictionary).has(part):
				node = node[part]
			else:
				return fallback
		return node

	func set_value(path: String, wert: Variant) -> void:
		var teile := path.split(".")
		var node: Dictionary = state
		for i in teile.size() - 1:
			if not (node.get(teile[i]) is Dictionary):
				node[teile[i]] = {}
			node = node[teile[i]]
		node[teile[teile.size() - 1]] = wert

	func update(mutator: Callable) -> void:
		mutator.call(state)

	func notify_slice_changed(slice_id: String) -> void:
		slices_notified.append(slice_id)


func test_alle_neuen_orte_stehen_in_der_karte() -> void:
	var karte := CityMap.laden()
	for id in NEUE_ORTE:
		var eintrag := OrtKatalog.eintrag(id, karte)
		assert_false(eintrag.is_empty(), "Ort fehlt in city_map.json: %s" % id)
		assert_ne(str(eintrag.get("name_key", "")), "", "%s: name_key fehlt" % id)
		assert_ne(
			I18nService.t(str(eintrag.get("name_key", ""))),
			str(eintrag.get("name_key", "")),
			"%s: name_key ist nicht übersetzt" % id
		)


func test_betretbare_orte_haben_existierende_szenen() -> void:
	var karte := CityMap.laden()
	var ids := OrtKatalog.betretbare_ids(karte)
	for id in NEUE_ORTE:
		assert_true(ids.has(id), "%s ist nicht betretbar (keine szene)" % id)
	for id in ids:
		var szene := str(OrtKatalog.eintrag(id, karte).get("szene", ""))
		assert_true(ResourceLoader.exists(szene), "%s: Szene fehlt (%s)" % [id, szene])


func test_karte_bleibt_valide() -> void:
	var fehler := CityMap.laden().validieren()
	assert_eq(fehler, [] as Array[String], "city_map.json Validierung")


func test_wochenmarkt_nur_samstags_8_bis_14() -> void:
	var karte := CityMap.laden()
	var regel := OrtKatalog.oeffnung("wochenmarkt", karte)
	assert_false(regel.is_empty(), "Wochenmarkt braucht eine Öffnungsregel")
	assert_true(OrtKatalog.ist_offen_an(regel, SAMSTAG, 8.0), "Sa 8 Uhr auf")
	assert_true(OrtKatalog.ist_offen_an(regel, SAMSTAG, 13.99), "Sa kurz vor 14 auf")
	assert_false(OrtKatalog.ist_offen_an(regel, SAMSTAG, 7.99), "Sa 7:59 noch zu")
	assert_false(OrtKatalog.ist_offen_an(regel, SAMSTAG, 14.0), "Sa 14 Uhr Feierabend")
	assert_false(OrtKatalog.ist_offen_an(regel, FREITAG, 10.0), "Freitag ist Markt zu")
	assert_false(OrtKatalog.ist_offen_an(regel, SONNTAG, 10.0), "Sonntag ist Markt zu")


func test_andere_orte_sind_immer_offen() -> void:
	var karte := CityMap.laden()
	for id in ["pow", "post", "autohaus", "baumarkt"]:
		assert_true(OrtKatalog.oeffnung(id, karte).is_empty(), "%s braucht keine Öffnungszeit" % id)
		assert_true(OrtKatalog.ist_offen(id, 0, karte), "%s ist immer offen" % id)


func test_geschlossen_text_erklaert_den_samstag() -> void:
	var karte := CityMap.laden()
	assert_eq(OrtKatalog.geschlossen_key("wochenmarkt", karte), "city.ort.nur_samstag")
	assert_eq(OrtKatalog.geschlossen_key("pow", karte), "city.ort.geschlossen")
	for key in ["city.ort.nur_samstag", "city.ort.geschlossen"]:
		assert_ne(I18nService.t(key), key, "Text fehlt: %s" % key)


func test_tage_bis_samstag() -> void:
	assert_eq(OrtKatalog.tage_bis_samstag(SAMSTAG), 0, "samstags ist heute Markt")
	assert_eq(OrtKatalog.tage_bis_samstag(FREITAG), 1)
	assert_eq(OrtKatalog.tage_bis_samstag(SONNTAG), 6)


func test_erstbesuch_wird_genau_einmal_gemeldet() -> void:
	var gs := FakeGameState.new()
	assert_false(OrtKatalog.schon_besucht(gs, "pow"), "frischer Save: nie da gewesen")
	assert_true(OrtKatalog.besuch_merken(gs, "pow"), "erster Besuch meldet true")
	assert_true(OrtKatalog.schon_besucht(gs, "pow"))
	assert_false(OrtKatalog.besuch_merken(gs, "pow"), "zweiter Besuch meldet false")
	assert_false(OrtKatalog.schon_besucht(gs, "baumarkt"), "andere Orte unberührt")
	assert_true(gs.slices_notified.has(CityState.SLICE_ID), "city-Slice wurde gemeldet")


func test_besuch_ohne_gamestate_kracht_nicht() -> void:
	assert_false(OrtKatalog.besuch_merken(null, "pow"))
	assert_false(OrtKatalog.schon_besucht(null, "pow"))
