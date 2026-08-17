extends TestCase
## M2/ORTE — Wochenmarkt-Preise (Doc D §6.3, USER §D51): Markt-Bonus,
## PREIS-ELASTIZITÄT (jede heute verkaufte Einheit drückt den Preis, mit
## Boden), Tageswechsel-Reset und die Verkaufs-Buchung gegen inventory.food.

## 2026-07-25 12:00 UTC (Samstag) und derselbe Moment einen Tag später.
const HEUTE := 1784980800
const MORGEN := HEUTE + 86400


class FakeGameState:
	extends RefCounted
	var state: Dictionary = {
		"city": {},
		"economy": {"coins": 0, "lifetimeCoins": 0},
		"inventory": {"items": {}, "food": {}},
	}

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

	func notify_slice_changed(_slice_id: String) -> void:
		pass


func _gs_mit(food: Dictionary) -> FakeGameState:
	var gs := FakeGameState.new()
	gs.state["inventory"]["food"] = food
	return gs


func test_marktpreis_hat_bonus_auf_den_basispreis() -> void:
	# Möhre: basis 5 → 5 × 1,15 = 5,75 → 6
	assert_eq(MarktPreise.marktpreis("carrot"), 6, "Möhre mit Markt-Bonus")
	assert_eq(MarktPreise.marktpreis("watermelon"), 81, "Wassermelone 70 × 1,15")
	assert_eq(MarktPreise.marktpreis("gibtsnicht"), 0, "unbekannte Ware = 0")
	for eintrag: Dictionary in MarktPreise.ernte_sorten():
		var id := str(eintrag.get("id", ""))
		assert_true(
			MarktPreise.marktpreis(id) >= int(eintrag.get("basis", 0)),
			"%s: Markt zahlt nie weniger als Kompost" % id
		)


func test_elastizitaet_druckt_den_preis() -> void:
	var voll := MarktPreise.marktpreis("watermelon")
	assert_eq(MarktPreise.stueckpreis("watermelon", 0), voll, "erste Einheit voll")
	var nach_fuenf := MarktPreise.stueckpreis("watermelon", 5)
	assert_true(nach_fuenf < voll, "nach 5 Stück ist der Preis gefallen")
	assert_eq(nach_fuenf, roundi(float(voll) * 0.75), "5 × 5 % = 25 % Abschlag")
	var letzte := 999999
	for schon in 20:
		var preis := MarktPreise.stueckpreis("watermelon", schon)
		assert_true(preis <= letzte, "Preis fällt monoton (bei %d)" % schon)
		letzte = preis


func test_preis_boden_haelt() -> void:
	var voll := MarktPreise.marktpreis("watermelon")
	var boden := maxi(1, roundi(float(voll) * 0.5))
	assert_eq(MarktPreise.stueckpreis("watermelon", 10), boden, "genau am Boden")
	assert_eq(MarktPreise.stueckpreis("watermelon", 500), boden, "und nie darunter")
	assert_true(MarktPreise.stueckpreis("carrot", 500) >= 1, "nie unter 1 Münze")


func test_erloes_summiert_fallende_stueckpreise() -> void:
	var einzeln := (
		MarktPreise.stueckpreis("pumpkin", 0)
		+ MarktPreise.stueckpreis("pumpkin", 1)
		+ MarktPreise.stueckpreis("pumpkin", 2)
	)
	assert_eq(MarktPreise.erloes("pumpkin", 3, 0), einzeln, "3 am Stück = Summe der Einzelpreise")
	assert_true(
		MarktPreise.erloes("pumpkin", 3, 0) < 3 * MarktPreise.marktpreis("pumpkin"),
		"Mengenrabatt geht zu Goobys Lasten"
	)
	assert_eq(MarktPreise.erloes("pumpkin", 0, 0), 0, "nichts verkauft, nichts verdient")


func test_verkauf_bucht_ware_muenzen_und_tageszaehler() -> void:
	var gs := _gs_mit({"carrot": 4})
	var erwartet := MarktPreise.erloes("carrot", 3, 0)
	var res := MarktPreise.verkaufen(gs, HEUTE, "carrot", 3)
	assert_true(res["ok"], "Verkauf geht durch")
	assert_eq(res["menge"], 3)
	assert_eq(res["erloes"], erwartet)
	assert_eq(int(gs.state["inventory"]["food"]["carrot"]), 1, "Rest bleibt im Korb")
	assert_eq(int(gs.state["economy"]["coins"]), erwartet, "Münzen gutgeschrieben")
	assert_eq(MarktPreise.heute_verkauft(gs, HEUTE, "carrot"), 3, "Tageszähler steht")


func test_verkauf_nie_mehr_als_der_vorrat() -> void:
	var gs := _gs_mit({"tomato": 2})
	var res := MarktPreise.verkaufen(gs, HEUTE, "tomato", 10)
	assert_eq(res["menge"], 2, "verkauft wird, was da ist")
	assert_eq(int(gs.state["inventory"]["food"]["tomato"]), 0)
	assert_false(MarktPreise.verkaufen(gs, HEUTE, "tomato", 1)["ok"], "leerer Korb: kein Verkauf")


func test_verkauf_lehnt_unsinn_ab() -> void:
	var gs := _gs_mit({"carrot": 5})
	assert_false(MarktPreise.verkaufen(gs, HEUTE, "carrot", 0)["ok"], "0 Stück")
	assert_false(MarktPreise.verkaufen(gs, HEUTE, "carrot", -3)["ok"], "negative Menge")
	assert_false(MarktPreise.verkaufen(gs, HEUTE, "beton", 1)["ok"], "keine Ernte")
	assert_false(MarktPreise.verkaufen(null, HEUTE, "carrot", 1)["ok"], "ohne GameState")
	assert_eq(int(gs.state["economy"]["coins"]), 0, "nichts davon zahlt aus")


func test_neuer_markttag_setzt_die_elastizitaet_zurueck() -> void:
	var gs := _gs_mit({"corn": 20})
	MarktPreise.verkaufen(gs, HEUTE, "corn", 8)
	assert_true(
		(
			MarktPreise.stueckpreis("corn", MarktPreise.heute_verkauft(gs, HEUTE, "corn"))
			< MarktPreise.marktpreis("corn")
		),
		"heute ist der Preis im Keller"
	)
	assert_eq(MarktPreise.heute_verkauft(gs, MORGEN, "corn"), 0, "morgen zählt neu")
	var morgen_angebot := MarktPreise.angebot_des_spielers(gs, MORGEN)
	for eintrag: Dictionary in morgen_angebot:
		if str(eintrag["id"]) == "corn":
			assert_eq(int(eintrag["preis"]), MarktPreise.marktpreis("corn"), "morgen voller Preis")


func test_tages_key() -> void:
	assert_eq(MarktPreise.tages_key(HEUTE), "2026-07-25")
	assert_eq(MarktPreise.tages_key(HEUTE + 3600), "2026-07-25", "eine Stunde später gleicher Tag")
	assert_eq(MarktPreise.tages_key(MORGEN), "2026-07-26")


func test_angebot_zeigt_nur_was_im_korb_liegt() -> void:
	var gs := _gs_mit({"carrot": 2, "salad": 0, "pumpkin": 1})
	var ids: Array[String] = []
	for eintrag: Dictionary in MarktPreise.angebot_des_spielers(gs, HEUTE):
		ids.append(str(eintrag["id"]))
		assert_true(int(eintrag["vorrat"]) > 0, "keine leeren Zeilen")
		assert_true(int(eintrag["preis"]) > 0, "jede Zeile hat einen Preis")
	assert_true(ids.has("carrot") and ids.has("pumpkin"), "Vorrat wird gelistet")
	assert_false(ids.has("salad"), "0 Salat = keine Zeile")
	assert_eq(MarktPreise.angebot_des_spielers(null, HEUTE).size(), 0, "ohne GameState leer")
