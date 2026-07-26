extends TestCase
## RW-1 — Save-Anbindung: `ranch.welt` + `ranch.wetter` sind ADDITIVE
## Unterschlüssel im ranch-Slice (kein Version-Bump), heilen sich beim
## Lesen selbst und überleben kaputte Rohdaten.


## Miniatur-GameState (Duck-Typing wie RanchState): nur get/set_value.
class MiniGs:
	var werte: Dictionary = {}

	func get_value(pfad: String, fallback: Variant = null) -> Variant:
		return werte.get(pfad, fallback)

	func set_value(pfad: String, wert: Variant) -> void:
		werte[pfad] = wert


func test_defaults_ohne_gamestate() -> void:
	assert_eq(RanchWeltState.entdeckte_zonen(null), ["hof"] as Array[String])
	assert_eq(RanchWeltState.wetter_seed(null), RanchKarte.seed_wert())


func test_zone_entdecken_ist_additiv_und_idempotent() -> void:
	var gs := MiniGs.new()
	assert_true(RanchWeltState.entdecke_zone(gs, "see"), "erste Entdeckung = neu")
	assert_false(RanchWeltState.entdecke_zone(gs, "see"), "zweite Entdeckung = alt")
	assert_false(RanchWeltState.entdecke_zone(gs, "mondbasis"), "unbekannte Zone = nein")
	var entdeckt := RanchWeltState.entdeckte_zonen(gs)
	assert_true(entdeckt.has("hof"), "Hof ist immer entdeckt")
	assert_true(entdeckt.has("see"), "See gemerkt")
	assert_eq(entdeckt.size(), 2, "keine Duplikate/Geister")


func test_normalize_heilt_kaputte_daten() -> void:
	var kaputt: Variant = {"v": -3, "entdeckt": ["see", "see", 42, "mondbasis", "waeldchen"]}
	var geheilt := RanchWeltState.normalize_welt(kaputt)
	assert_eq(int(geheilt["v"]), 1, "Version geklemmt")
	assert_eq(
		geheilt["entdeckt"],
		["hof", "see", "waeldchen"] as Array[String],
		"nur echte Zonen, dedupliziert, Hof ergänzt"
	)
	assert_eq(
		RanchWeltState.normalize_welt("quatsch")["entdeckt"],
		["hof"] as Array[String],
		"Nicht-Dictionary → Default"
	)


func test_wetter_seed_ist_stabil_pro_save() -> void:
	var gs := MiniGs.new()
	gs.set_value(RanchWeltState.WETTER_KEY, {"v": 1, "seed": 777})
	assert_eq(RanchWeltState.wetter_seed(gs), 777, "gespeicherter Seed gewinnt")
	var kaputt := MiniGs.new()
	kaputt.set_value(RanchWeltState.WETTER_KEY, {"seed": "banane"})
	assert_eq(RanchWeltState.wetter_seed(kaputt), RanchKarte.seed_wert(), "geheilt auf Welt-Seed")


func test_slice_normalize_laesst_neue_unterschluessel_leben() -> void:
	# Der bestehende ranch-Slice (RanchState) darf unsere additiven Keys
	# beim Self-Heal NICHT verwerfen — sonst wäre jedes Laden ein Reset.
	var slice := RanchState.default_slice()
	slice["welt"] = {"v": 1, "entdeckt": ["hof", "see"]}
	slice["wetter"] = {"v": 1, "seed": 42}
	var geheilt := RanchState.normalize_slice(slice)
	assert_eq(geheilt.get("welt"), {"v": 1, "entdeckt": ["hof", "see"]}, "welt bleibt")
	assert_eq(geheilt.get("wetter"), {"v": 1, "seed": 42}, "wetter bleibt")


## Fake-Router (Duck-Typing wie SceneRouter): merkt Registrierung + Reisen.
class FakeRouter:
	var routen: Dictionary = {}
	var besucht: Array = []

	func register_route(ziel: StringName, szene: String) -> void:
		routen[ziel] = szene

	func goto(ziel: StringName, params: Dictionary = {}) -> void:
		besucht.append({"ziel": ziel, "params": params})


func test_route_ranch_welt_wird_registriert_und_bereist() -> void:
	var router := FakeRouter.new()
	RanchWeltRouten.router_override = router
	assert_true(RanchWeltRouten.reite_los(null, {"spawn_zone": "see"}))
	assert_eq(
		router.routen.get(RanchWeltRouten.ROUTE_WELT, ""),
		RanchWeltRouten.SZENE_WELT,
		"Route ranch/welt zeigt auf die Region-Szene"
	)
	assert_eq(router.besucht.size(), 1)
	assert_eq(router.besucht[0]["ziel"], RanchWeltRouten.ROUTE_WELT)
	assert_eq(str(router.besucht[0]["params"]["spawn_zone"]), "see")
	RanchWeltRouten.router_override = null
	assert_false(RanchWeltRouten.reite_los(null, {}), "ohne Router keine Reise")
