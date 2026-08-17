extends TestCase
## RW-3 — Freundschaft am ECHTEN GameState (RNpcState): additiver
## `ranch.npc`-Unterschluessel, Reden/Geschenk/Quest-Bonus persistieren,
## Freischaltungs-Toasts (neu_freigeschaltet), Geschichten-Merker und
## der Verfall ueber die gepinnte Uhr.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

const NOW_MS := 1768478400000
const TAG_MS := RNpcFreundschaft.MS_PRO_TAG

var _seq := 0


func _fresh_gs() -> Node:
	RQuestSlices.ensure_registered()
	_seq += 1
	var dir := "user://rw3_tests/npc_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.initialize(dir + "/save_v5.json")
	return gs


func _teardown(gs: Node) -> void:
	gs.free()
	SaveSchema.unregister_slice(RQuestSlices.SLICE_ID)
	RQuestSlices.reset_for_tests()


func test_frischer_save_hat_additive_unterschluessel() -> void:
	var gs := _fresh_gs()
	assert_eq(RNpcState.npc_daten(gs), RQuestSlices.default_npc())
	assert_eq(RNpcState.herzen(gs, "rosi", NOW_MS), 0)
	var karte := RNpcState.herzen_map(gs, NOW_MS)
	for npc_id: String in RNpcKatalog.ids():
		assert_eq(karte.get(npc_id), 0, "%s startet bei Herz 0" % npc_id)
	_teardown(gs)


func test_reden_persistiert_und_respektiert_tageslimit() -> void:
	var gs := _fresh_gs()
	var tag := str(gs.clock.local_day())
	RNpcState.reden(gs, "rosi", tag, NOW_MS)
	var erneut := RNpcState.reden(gs, "rosi", tag, NOW_MS + 1000)
	assert_almost(
		float(erneut["punkte"]),
		RNpcFreundschaft.REDEN_PUNKTE + RNpcFreundschaft.REDEN_TROST,
		1e-6,
		"zweites Gespraech am selben Tag gibt Trost"
	)
	var gespeichert: Variant = gs.get_value("ranch.npc.freunde.rosi.geredetTag")
	assert_eq(gespeichert, tag, "geredetTag liegt im Save")
	_teardown(gs)


func test_geschenk_liefert_reaktion_und_freischaltungs_toast() -> void:
	var gs := _fresh_gs()
	var tag := str(gs.clock.local_day())
	var ergebnis := RNpcState.geschenk(gs, "rosi", "apfel", tag, NOW_MS)
	assert_eq(str(ergebnis["reaktion"]), "liebt", "Rosi liebt Aepfel")
	assert_eq(int(ergebnis["herzen"]), 1, "12 Punkte = Herz 1")
	assert_eq(
		ergebnis["neu_freigeschaltet"],
		[{"typ": "smalltalk"}],
		"Herz-1-Freischaltung kommt als Toast-Delta"
	)
	_teardown(gs)


func test_quest_bonus_bucht_geber_plus_extra() -> void:
	var gs := _fresh_gs()
	RNpcState.quest_bonus(gs, "rosi", 8.0, NOW_MS)
	var punkte := float(RNpcState.freund(gs, "rosi", NOW_MS)["punkte"])
	assert_almost(punkte, RNpcFreundschaft.QUEST_PUNKTE + 8.0)
	_teardown(gs)


func test_verfall_wirkt_ueber_die_gepinnte_uhr() -> void:
	var gs := _fresh_gs()
	RNpcState.quest_bonus(gs, "rosi", 22.0, NOW_MS)
	assert_almost(float(RNpcState.freund(gs, "rosi", NOW_MS)["punkte"]), 30.0)
	var spaeter := NOW_MS + TAG_MS * 10
	assert_almost(
		float(RNpcState.freund(gs, "rosi", spaeter)["punkte"]),
		27.0,
		1e-6,
		"3 Tage ueber der 7-Tage-Karenz = -3 (nur beim Lesen, Save unberuehrt)"
	)
	assert_eq(
		RNpcState.herzen(gs, "rosi", NOW_MS + TAG_MS * 400),
		2,
		"Boden der erreichten Stufe haelt (30 Punkte = Herz 2)"
	)
	_teardown(gs)


func test_geschichte_gehoert_ist_idempotent() -> void:
	var gs := _fresh_gs()
	RNpcState.geschichte_gehoert(gs, "rosi", "geschichte_1", NOW_MS)
	RNpcState.geschichte_gehoert(gs, "rosi", "geschichte_1", NOW_MS)
	assert_eq(
		RNpcState.freund(gs, "rosi", NOW_MS)["geschichtenGehoert"],
		["geschichte_1"],
		"doppelt gehoert wird nicht doppelt gemerkt"
	)
	_teardown(gs)


func test_fremde_ranch_schluessel_ueberleben_meine_schreibzugriffe() -> void:
	var gs := _fresh_gs()
	gs.update(
		func(state: Dictionary) -> void:
			(state["ranch"] as Dictionary)["pferde"] = [{"id": "brauni"}]
	)
	RNpcState.reden(gs, "rosi", "2026-07-26", NOW_MS)
	assert_eq(
		gs.get_value("ranch.pferde"),
		[{"id": "brauni"}],
		"RANCH-1-Daten bleiben beim Freundschafts-Schreiben unberuehrt"
	)
	_teardown(gs)
