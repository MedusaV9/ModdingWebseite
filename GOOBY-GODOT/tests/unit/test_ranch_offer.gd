extends TestCase
## RANCH-1 — RanchOffer: das Angebot direkt nach dem Rückblick. Gate
## (Level 20), Einmaligkeit (angebotGesehen), „Jetzt losfahren“ vs.
## „Später kaufen“ (merkt den Stand, bleibt über zeige() erreichbar),
## nach dem Kauf kein Angebot mehr.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

var _dir_seq := 0


## Fake-Router (Muster test_shop_screen.gd) — fängt goto ab, statt im
## Runner eine echte Reise zu starten.
class FakeRouter:
	extends RefCounted

	var routen: Dictionary = {}
	var reisen: Array = []

	func register_route(ziel: StringName, pfad: String) -> void:
		routen[ziel] = pfad

	func goto(ziel: StringName, params: Dictionary = {}) -> void:
		reisen.append({"ziel": ziel, "params": params})


func _fresh_gs(level: int) -> Node:
	RanchState.register_slice()
	_dir_seq += 1
	var dir := "user://ranch_tests/offer_%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	gs.set_value("progression.level", level)
	return gs


func _teardown_gs(gs: Node) -> void:
	PanelStack.clear()
	gs.free()
	SaveSchema.unregister_slice(RanchState.SLICE_ID)
	RanchState.reset_for_tests()
	RanchRouten.router_override = null


func test_unter_level_20_kein_angebot() -> void:
	var gs := _fresh_gs(19)
	assert_false(RanchOffer.sollte_zeigen(gs), "Level 19: kein Angebot")
	var sheet := RanchOffer.maybe_show(tree.root, gs)
	assert_eq(sheet, null, "maybe_show liefert null")
	_teardown_gs(gs)


func test_ab_level_20_erscheint_das_angebot() -> void:
	var gs := _fresh_gs(20)
	assert_true(RanchOffer.sollte_zeigen(gs), "Level 20: Angebot faellig")
	var sheet := RanchOffer.maybe_show(tree.root, gs)
	assert_ne(sheet, null, "Sheet gebaut")
	await wait_frames(2)
	assert_true(sheet.visible, "Sheet offen")
	assert_true(sheet.has_meta(RanchOffer.META_JETZT), "Jetzt-Knopf verdrahtet")
	assert_true(sheet.has_meta(RanchOffer.META_SPAETER), "Spaeter-Knopf verdrahtet")
	sheet.queue_free()
	await wait_frames(1)
	_teardown_gs(gs)


func test_spaeter_kaufen_merkt_den_stand() -> void:
	var gs := _fresh_gs(20)
	var sheet := RanchOffer.maybe_show(tree.root, gs)
	assert_ne(sheet, null)
	await wait_frames(1)
	var spaeter: Button = sheet.get_meta(RanchOffer.META_SPAETER)
	spaeter.pressed.emit()
	await wait_frames(2)
	assert_eq(gs.get_value("ranch.angebotVerschoben"), true, "Stand gemerkt")
	assert_false(RanchOffer.sollte_zeigen(gs), "kein automatisches zweites Angebot")
	# Aber: das Angebot bleibt ueber zeige() (Handy/Hinweis) erreichbar.
	var erneut := RanchOffer.zeige(tree.root, gs)
	assert_ne(erneut, null, "zeige() oeffnet das Angebot weiterhin")
	erneut.queue_free()
	await wait_frames(1)
	_teardown_gs(gs)


func test_jetzt_losfahren_markiert_gesehen_und_reist() -> void:
	var gs := _fresh_gs(20)
	var router := FakeRouter.new()
	RanchRouten.router_override = router
	var sheet := RanchOffer.maybe_show(tree.root, gs)
	assert_ne(sheet, null)
	await wait_frames(1)
	var jetzt: Button = sheet.get_meta(RanchOffer.META_JETZT)
	jetzt.pressed.emit()
	await wait_frames(2)
	assert_eq(gs.get_value("ranch.angebotGesehen"), true, "gesehen")
	assert_eq(gs.get_value("ranch.angebotVerschoben"), false, "nicht verschoben")
	assert_eq(router.reisen.size(), 1, "genau EINE Reise gestartet")
	assert_eq(router.reisen[0]["ziel"], RanchRouten.ROUTE_FAHRT, "Ziel = Landstrasse")
	assert_true(router.routen.has(RanchRouten.ROUTE_FAHRT), "Route selbst registriert")
	assert_false(RanchOffer.sollte_zeigen(gs), "Angebot kommt nicht doppelt")
	_teardown_gs(gs)


func test_nach_kauf_kein_angebot_mehr() -> void:
	var gs := _fresh_gs(20)
	gs.set_value("economy.coins", RanchKatalog.preis())
	assert_eq(RanchKauf.kaufe(gs), RanchKauf.RESULT_OK)
	assert_false(RanchOffer.sollte_zeigen(gs), "gekauft = kein Angebot")
	assert_eq(RanchOffer.zeige(tree.root, gs), null, "auch zeige() blockt nach dem Kauf")
	assert_eq(RanchOffer.maybe_show(tree.root, gs), null)
	_teardown_gs(gs)
