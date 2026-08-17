extends TestCase
## RW-4 — RanchDorfState + DorfRouten: additiver Save `ranch.dorf`,
## Entdeckungs-Gate (Schnellreise ERST nach dem ersten Anritt),
## Self-Heal des Unterschlüssels und die Routen-Helfer.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

var _dir_seq := 0


class FakeRouter:
	extends RefCounted

	var routen: Dictionary = {}
	var besucht: Array = []

	func register_route(ziel: StringName, szene: String) -> void:
		routen[ziel] = szene

	func goto(ziel: StringName, params: Dictionary = {}) -> void:
		besucht.append({"ziel": ziel, "params": params})


func _fresh_gs() -> Node:
	RanchState.register_slice()
	_dir_seq += 1
	var dir := "user://rdorf_tests/state_%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	return gs


func _teardown_gs(gs: Node) -> void:
	gs.free()
	SaveSchema.unregister_slice(RanchState.SLICE_ID)
	RanchState.reset_for_tests()
	DorfRouten.router_override = null


func test_normalize_heilt_kaputte_daten() -> void:
	var dorf := RanchDorfState.normalize_dorf("quatsch")
	assert_eq(dorf["entdeckt"], false)
	assert_eq(dorf["futter"], {"hafer": 0, "leckerli": 0})
	var halb := (
		RanchDorfState
		. normalize_dorf(
			{
				"entdeckt": true,
				"futter": {"hafer": 3},
				"hufeisen": {"owned": ["hufeisen_gold", "hufeisen_gold", 7]},
			}
		)
	)
	assert_eq(halb["entdeckt"], true, "gültige Daten VERBATIM")
	assert_eq(halb["futter"]["hafer"], 3)
	assert_eq(halb["futter"]["leckerli"], 0, "fehlender Key ergänzt")
	assert_eq(halb["hufeisen"]["owned"], ["hufeisen_gold"], "Duplikate + Müll raus")


func test_entdeckung_ist_idempotent_und_gated() -> void:
	var gs := _fresh_gs()
	assert_false(RanchDorfState.ist_entdeckt(gs), "frisch = unentdeckt")
	assert_false(DorfRouten.schnellreise_moeglich(gs), "Schnellreise gesperrt")
	assert_true(RanchDorfState.entdecke(gs), "erster Anritt = NEU entdeckt")
	assert_true(RanchDorfState.ist_entdeckt(gs))
	assert_true(int(RanchDorfState.lese(gs)["entdecktAm"]) > 0, "Zeitpunkt gemerkt")
	assert_false(RanchDorfState.entdecke(gs), "zweiter Aufruf ändert nichts")
	assert_true(DorfRouten.schnellreise_moeglich(gs), "Gate offen nach Entdeckung")
	_teardown_gs(gs)


func test_schnellreise_blockt_vor_der_entdeckung() -> void:
	var gs := _fresh_gs()
	var router := FakeRouter.new()
	DorfRouten.router_override = router
	assert_false(DorfRouten.schnellreise(null, gs), "vor Entdeckung KEINE Schnellreise")
	assert_eq(router.besucht.size(), 0, "Router wurde nicht angefasst")
	RanchDorfState.entdecke(gs)
	assert_true(DorfRouten.schnellreise(null, gs))
	assert_eq(router.besucht.size(), 1)
	assert_eq(router.besucht[0]["ziel"], DorfRouten.ROUTE_DORF)
	assert_eq(str(router.besucht[0]["params"]["via"]), "schnellreise")
	_teardown_gs(gs)


func test_anritt_und_betreten_ueber_router() -> void:
	var gs := _fresh_gs()
	var router := FakeRouter.new()
	DorfRouten.router_override = router
	assert_true(DorfRouten.betrete_dorf(null, {}))
	assert_eq(router.besucht[0]["ziel"], DorfRouten.ROUTE_DORF)
	assert_eq(str(router.besucht[0]["params"]["via"]), "ritt", "Betreten = per Ritt")
	assert_eq(
		router.routen.get(DorfRouten.ROUTE_DORF, ""),
		DorfRouten.SZENE_DORF,
		"Route wird idempotent registriert"
	)
	assert_true(DorfRouten.reite_los(null, {}), "Losreiten geht immer (Region ODER Pfad)")
	assert_eq(router.besucht.size(), 2)
	_teardown_gs(gs)


func test_heute_liefert_tages_string() -> void:
	var gs := _fresh_gs()
	var tag := RanchDorfState.heute(gs)
	assert_true(tag.length() >= 8, "Tages-String vorhanden: %s" % tag)
	assert_eq(RanchDorfState.heute(gs), tag, "stabil innerhalb des Tages")
	_teardown_gs(gs)
