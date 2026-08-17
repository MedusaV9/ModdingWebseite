extends TestCase
## RANCH-1 — Stadtausfahrt (scripts/city/ranch_exit.gd): Zonen-Erkennung,
## Level-15-Gate (W13: 20→15; unter 15 nur Hinweis-Toast, ab 15 der
## Losfahren-Prompt) und die Reise auf die Landstraße über den Fake-Router.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

var _seq := 0


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
	_seq += 1
	var dir := "user://ranch_tests/exit_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.initialize(dir + "/save_v5.json")
	gs.set_value("progression.level", level)
	return gs


## Exit ohne komplette Stadt: karte = null (Fallback-Position), Auto als
## nackter Node3D — genau die Duck-Typing-Injektion aus dem Header.
func _mount(gs: Node) -> RanchExit:
	var exit := RanchExit.new()
	exit.game_state_override = gs
	var auto := Node3D.new()
	auto.position = Vector3(0.0, 0.0, 0.0)
	tree.root.add_child(auto)
	exit.auto = auto
	tree.root.add_child(exit)
	await wait_frames(2)
	return exit


func _cleanup(exit: RanchExit, gs: Node) -> void:
	exit.auto.queue_free()
	exit.queue_free()
	await wait_frames(2)
	gs.free()
	SaveSchema.unregister_slice(RanchState.SLICE_ID)
	RanchState.reset_for_tests()
	RanchRouten.router_override = null


func test_zone_erkennung() -> void:
	var gs := _fresh_gs(15)
	var exit := await _mount(gs)
	assert_false(exit.in_zone(), "weit weg = draussen")
	exit.auto.position = exit.ausfahrt_pos() + Vector3(2.0, 0.0, 1.0)
	assert_true(exit.in_zone(), "an der Ausfahrt = drin")
	await _cleanup(exit, gs)


func test_unter_level_15_nur_hinweis() -> void:
	var gs := _fresh_gs(14)
	var router := FakeRouter.new()
	RanchRouten.router_override = router
	var exit := await _mount(gs)
	exit.auto.position = exit.ausfahrt_pos()
	await wait_frames(3)
	assert_false(exit.prompt_sichtbar(), "Level 14: kein Losfahren-Prompt")
	# Auch ein direkter Losfahren-Versuch bleibt am Gate haengen.
	exit._on_losfahren()
	assert_eq(router.reisen, [], "Level 14: keine Reise")
	await _cleanup(exit, gs)


func test_ab_level_15_prompt_und_reise() -> void:
	var gs := _fresh_gs(15)
	var router := FakeRouter.new()
	RanchRouten.router_override = router
	var exit := await _mount(gs)
	exit.auto.position = exit.ausfahrt_pos()
	await wait_frames(3)
	assert_true(exit.prompt_sichtbar(), "Level 15: Prompt offen")
	exit._on_losfahren()
	assert_eq(router.reisen.size(), 1, "Losfahren reist")
	assert_eq(router.reisen[0]["ziel"], RanchRouten.ROUTE_FAHRT, "Ziel = Landstrasse")
	assert_true(router.routen.has(RanchRouten.ROUTE_FAHRT), "Route selbst registriert")
	# Wegfahren schliesst den Prompt wieder.
	exit.auto.position = exit.ausfahrt_pos() + Vector3(50.0, 0.0, 0.0)
	await wait_frames(3)
	assert_false(exit.prompt_sichtbar(), "draussen = Prompt zu")
	await _cleanup(exit, gs)
