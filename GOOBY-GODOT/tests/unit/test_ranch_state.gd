extends TestCase
## RANCH-1 — RanchState: additiver `ranch`-Slice (register_slice, KEIN
## Version-Bump), Self-Heal, Level-20-Gate und das „Später kaufen“-Merken.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

const NOW_MS := 1768478400000

var _dir_seq := 0


func _fresh_gs() -> Node:
	RanchState.register_slice()
	_dir_seq += 1
	var dir := "user://ranch_tests/state_%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.initialize(dir + "/save_v5.json")
	return gs


func _teardown_gs(gs: Node) -> void:
	gs.free()
	SaveSchema.unregister_slice(RanchState.SLICE_ID)
	RanchState.reset_for_tests()


func test_default_slice_ist_vollstaendig() -> void:
	var gs := _fresh_gs()
	assert_eq(gs.get_value("ranch.gekauft"), false, "frisch = nicht gekauft")
	assert_eq(gs.get_value("ranch.angebotGesehen"), false)
	assert_eq(gs.get_value("ranch.angebotVerschoben"), false)
	assert_eq(gs.get_value("ranch.hoftiere"), [], "keine Hoftiere vor dem Kauf")
	assert_eq(gs.get_value("ranch.ausbau.stall"), 1, "Ausbau startet auf Stufe 1")
	assert_eq(gs.get_value("ranch.ausbau.koppel"), 1)
	assert_eq(gs.get_value("ranch.ausbau.reitplatz"), 1)
	# RANCH-2-Unterschlüssel (RanchPlaySlices) sind mit registriert.
	assert_eq(gs.get_value("ranch.tiere.pferde"), {}, "RANCH-2: leerer Pferdebestand")
	assert_eq(gs.get_value("ranch.wirtschaft.ausbau.boxen"), 1, "RANCH-2: Wirtschaft dabei")
	assert_true(gs.get_value("ranch.spiele") is Dictionary, "RANCH-2: Spiele dabei")
	_teardown_gs(gs)


func test_normalize_heilt_kaputte_daten() -> void:
	var geheilt := RanchState.normalize_slice(
		{"gekauft": 1, "hoftiere": "kaputt", "tiere": "kaputt", "ausbau": {"stall": -3}}
	)
	assert_eq(geheilt["gekauft"], true, "truthy → bool")
	assert_eq(geheilt["hoftiere"], [], "kaputtes Array → leer")
	assert_eq(geheilt["tiere"]["pferde"], {}, "RANCH-2-Unterschlüssel geheilt (Delegation)")
	assert_eq(geheilt["ausbau"]["stall"], 1, "Stufe klemmt auf >= 1")
	assert_eq(geheilt["ausbau"]["koppel"], 1, "fehlende Anlage ergänzt")
	assert_eq(geheilt["angebotGesehen"], false, "fehlender Key → Default")
	var kaputt := RanchState.normalize_slice("voelliger_quatsch")
	assert_eq(kaputt["gekauft"], false, "Nicht-Dictionary → kompletter Default")


func test_level_20_gate() -> void:
	var gs := _fresh_gs()
	assert_false(RanchState.ist_freigeschaltet(gs), "Level 1 gesperrt")
	gs.set_value("progression.level", 19)
	assert_false(RanchState.ist_freigeschaltet(gs), "Level 19 gesperrt")
	gs.set_value("progression.level", 20)
	assert_true(RanchState.ist_freigeschaltet(gs), "Level 20 offen")
	gs.set_value("progression.level", 33)
	assert_true(RanchState.ist_freigeschaltet(gs), "darueber bleibt offen")
	_teardown_gs(gs)


func test_angebot_verschieben_merkt_stand() -> void:
	var gs := _fresh_gs()
	var slice_events: Array = []
	gs.slice_changed.connect(func(id: String, _d: Variant) -> void: slice_events.append(id))
	RanchState.angebot_verschieben(gs)
	assert_eq(gs.get_value("ranch.angebotGesehen"), true)
	assert_eq(gs.get_value("ranch.angebotVerschoben"), true)
	assert_true(slice_events.has("ranch"), "slice_changed(ranch) feuert")
	_teardown_gs(gs)


func test_angebot_gesehen_ohne_verschieben() -> void:
	var gs := _fresh_gs()
	RanchState.angebot_gesehen(gs)
	assert_eq(gs.get_value("ranch.angebotGesehen"), true)
	assert_eq(gs.get_value("ranch.angebotVerschoben"), false, "Jetzt losfahren verschiebt nicht")
	_teardown_gs(gs)


func test_slice_ueberlebt_save_roundtrip() -> void:
	RanchState.register_slice()
	_dir_seq += 1
	var dir := "user://ranch_tests/rt_%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var pfad := dir + "/save_v5.json"
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.initialize(pfad)
	RanchState.angebot_verschieben(gs)
	gs.set_value("ranch.gekauft", true)
	assert_true(gs.save_now(), "Save schreibt")
	gs.free()
	var gs2: Node = GameStateScript.new()
	gs2.clock.pin(NOW_MS)
	gs2.initialize(pfad)
	assert_eq(gs2.get_value("ranch.gekauft"), true, "gekauft ueberlebt Reload")
	assert_eq(gs2.get_value("ranch.angebotVerschoben"), true, "verschoben ueberlebt Reload")
	gs2.free()
	SaveSchema.unregister_slice(RanchState.SLICE_ID)
	RanchState.reset_for_tests()
