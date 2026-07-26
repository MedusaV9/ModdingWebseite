extends TestCase
## RANCH-1 — Überlandfahrt: Welt + Auto stehen, Fahrt-Ankunft am Ranch-Tor
## (tor_erreicht + Prompt), Kauf-Sheet am Tor („Kaufen“ reist zum Hof,
## „Später kaufen“ merkt den Stand) und das offene Tor nach dem Kauf.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")
const FahrtSzene := preload("res://scenes/ranch/ranch_fahrt.tscn")

var _seq := 0


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


func _fresh_gs(level := 20, coins := 99999) -> Node:
	RanchState.register_slice()
	_seq += 1
	var dir := "user://ranch_tests/fahrt_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	gs.set_value("progression.level", level)
	gs.set_value("economy.coins", coins)
	return gs


func _mount(gs: Node) -> RanchFahrtScene:
	var szene: RanchFahrtScene = FahrtSzene.instantiate()
	szene.game_state_override = gs
	szene.stunde_override = 13.0
	tree.root.add_child(szene)
	await wait_frames(3)
	return szene


func _cleanup(szene: Node, gs: Node) -> void:
	PanelStack.clear()
	szene.queue_free()
	await wait_frames(2)
	gs.free()
	SaveSchema.unregister_slice(RanchState.SLICE_ID)
	RanchState.reset_for_tests()
	RanchRouten.router_override = null


## Auto ans Tor teleportieren und die Tor-Erkennung ticken lassen.
func _fahre_ans_tor(szene: RanchFahrtScene) -> void:
	szene.auto.teleport(-CityCarFeel.LANE_OFFSET_M, float(szene.plan["tor_z"]) - 10.0, 0.0)
	await wait_frames(3)


func test_welt_und_auto_stehen() -> void:
	var gs := _fresh_gs()
	var szene := await _mount(gs)
	assert_ne(szene.auto, null, "SpielerAuto steht")
	assert_almost(szene.auto.position.z, float(szene.plan["spawn_z"]), 0.5, "Spawn am Stadtende")
	assert_true(szene.cam != null and szene.cam.current, "ChaseCam aktiv")
	assert_true(szene.hud != null, "Fahr-HUD steht")
	assert_false(szene.hud.prompt_sichtbar(), "Prompt erst am Tor")
	assert_true(
		float(szene.plan["tor_z"]) > float(szene.plan["spawn_z"]), "Tor liegt in Fahrtrichtung"
	)
	await _cleanup(szene, gs)


func test_ankunft_am_tor_zeigt_kauf_prompt() -> void:
	var gs := _fresh_gs()
	var szene := await _mount(gs)
	var ankuenfte: Array = []
	szene.tor_erreicht.connect(func() -> void: ankuenfte.append(true))
	await _fahre_ans_tor(szene)
	assert_eq(ankuenfte.size(), 1, "tor_erreicht feuert genau einmal")
	assert_true(szene.hud.prompt_sichtbar(), "Ankunft zeigt den Tor-Prompt")
	await _cleanup(szene, gs)


func test_tor_kauf_reist_zum_hof() -> void:
	var gs := _fresh_gs()
	var router := FakeRouter.new()
	RanchRouten.router_override = router
	var szene := await _mount(gs)
	await _fahre_ans_tor(szene)
	szene.hud.prompt_pressed.emit()
	await wait_frames(2)
	assert_ne(szene.tor_sheet, null, "Kauf-Sheet am Tor offen")
	var kaufen: Button = szene.tor_sheet.get_meta(RanchOffer.META_JETZT)
	kaufen.pressed.emit()
	await wait_frames(2)
	assert_eq(gs.get_value("ranch.gekauft"), true, "Tor-Kauf kauft die Ranch")
	assert_eq(router.reisen.size(), 1, "genau EINE Reise")
	assert_eq(router.reisen[0]["ziel"], RanchRouten.ROUTE_HOF, "Ziel = Hof")
	await _cleanup(szene, gs)


func test_tor_spaeter_merkt_den_stand() -> void:
	var gs := _fresh_gs()
	var router := FakeRouter.new()
	RanchRouten.router_override = router
	var szene := await _mount(gs)
	await _fahre_ans_tor(szene)
	szene.hud.prompt_pressed.emit()
	await wait_frames(2)
	var spaeter: Button = szene.tor_sheet.get_meta(RanchOffer.META_SPAETER)
	spaeter.pressed.emit()
	await wait_frames(2)
	assert_eq(gs.get_value("ranch.gekauft"), false, "nicht gekauft")
	assert_eq(gs.get_value("ranch.angebotVerschoben"), true, "Stand gemerkt")
	assert_eq(router.reisen, [], "keine Reise — Rueckweg bleibt frei")
	assert_eq(szene.tor_sheet, null, "Sheet ist zu")
	await _cleanup(szene, gs)


func test_tor_offen_nach_kauf() -> void:
	var gs := _fresh_gs()
	assert_eq(RanchKauf.kaufe(gs), RanchKauf.RESULT_OK, "Vorbedingung: gekauft")
	var router := FakeRouter.new()
	RanchRouten.router_override = router
	var szene := await _mount(gs)
	await _fahre_ans_tor(szene)
	assert_true(szene.hud.prompt_sichtbar(), "Prompt auch nach dem Kauf")
	szene.hud.prompt_pressed.emit()
	await wait_frames(2)
	assert_eq(szene.tor_sheet, null, "kein Kauf-Sheet mehr")
	assert_eq(router.reisen.size(), 1, "direkt rein")
	assert_eq(router.reisen[0]["ziel"], RanchRouten.ROUTE_HOF)
	await _cleanup(szene, gs)
