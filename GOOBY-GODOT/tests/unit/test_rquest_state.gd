extends TestCase
## RW-3 — Quest-Engine am ECHTEN GameState (RQuestState): Annehmen →
## Ereignisse → Abgeben end-to-end (haupt_01), Belohnungen (Muenzen →
## economy.coins, Items → ranch.wirtschaft.lager, Herzen → Freundschaft),
## Warte-Quest ueber die gepinnte Uhr inkl. Notification/Live-Activity
## und der Kapitel-Fortschritt.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const SaveSchema := preload("res://scripts/state/save_schema.gd")

const NOW_MS := 1768478400000
const MIN_MS := RQuestEngine.MS_PRO_MIN

var _seq := 0


## Registry-Attrappe mit fester Item-Liste (fuer Warte-Quest-Fixtures).
class FakeRegistry:
	var items: Array = []

	func get_items(_domain: String) -> Array:
		return items


func _fresh_gs() -> Node:
	RQuestSlices.ensure_registered()
	_seq += 1
	var dir := "user://rw3_tests/quest_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.initialize(dir + "/save_v5.json")
	return gs


func _teardown(gs: Node) -> void:
	gs.free()
	SaveSchema.unregister_slice(RQuestSlices.SLICE_ID)
	RQuestSlices.reset_for_tests()
	RQuestKatalog.registry_override = null
	RQuestKatalog.reset_cache()
	for eintrag: Dictionary in NotifyStub.pending():
		NotifyStub.cancel_local(str(eintrag["id"]))
	RanchLiveActivity.reset_for_tests()


func test_haupt_01_annehmen_bis_abgeben_mit_belohnung() -> void:
	var gs := _fresh_gs()
	var start_muenzen := int(gs.get_value("economy.coins", 0))
	assert_eq(RQuestState.status(gs, "haupt_01"), RQuestEngine.STATUS_VERFUEGBAR)
	assert_eq(RQuestState.kapitel(gs), 1)
	assert_true(RQuestState.annehmen(gs, "haupt_01"))
	assert_false(RQuestState.annehmen(gs, "haupt_01"), "doppelt annehmen blockiert")
	assert_eq(RQuestState.status(gs, "haupt_01"), RQuestEngine.STATUS_AKTIV)
	assert_eq(RQuestState.ereignis(gs, {"typ": "sprich_mit", "npc": "rosi"}), ["haupt_01"])
	assert_eq(
		RQuestState.ereignis(gs, {"typ": "sprich_mit", "npc": "rosi"}),
		[],
		"falsches Ereignis (Ziel 2 ist gehe_zu) bucht nichts"
	)
	RQuestState.ereignis(gs, {"typ": "gehe_zu", "ort": "stall"})
	RQuestState.ereignis(gs, {"typ": "pflege", "aktion": "ausmisten"})
	RQuestState.ereignis(gs, {"typ": "sammle", "item": "hufeisen", "n": 3})
	assert_eq(RQuestState.status(gs, "haupt_01"), RQuestEngine.STATUS_ERFUELLBAR)
	assert_true(RQuestState.abgeben(gs, "haupt_01"))
	assert_eq(RQuestState.status(gs, "haupt_01"), RQuestEngine.STATUS_ERLEDIGT)
	assert_eq(RQuestState.kapitel(gs), 2, "Kapitel rueckt vor")
	assert_eq(
		int(gs.get_value("economy.coins", 0)),
		start_muenzen + 150,
		"Muenzen-Belohnung landet in economy.coins"
	)
	assert_eq(
		int(gs.get_value("ranch.wirtschaft.lager.apfel", 0)),
		2,
		"Item-Belohnung landet im Ranch-Lager"
	)
	var rosi_punkte := float(RNpcState.freund(gs, "rosi", NOW_MS)["punkte"])
	assert_almost(
		rosi_punkte,
		RNpcFreundschaft.QUEST_PUNKTE + 8.0,
		1e-6,
		"Geber-Bonus + herzen-Belohnung landen bei Rosi"
	)
	_teardown(gs)


func test_herz_gate_haelt_am_echten_state() -> void:
	var gs := _fresh_gs()
	assert_eq(
		RQuestState.status(gs, "neben_rosi_saat"),
		RQuestEngine.STATUS_GESPERRT,
		"Herz-3-Quest ist ohne Freundschaft gesperrt"
	)
	RNpcState.quest_bonus(gs, "rosi", 37.0, NOW_MS)
	assert_eq(
		RQuestState.status(gs, "neben_rosi_saat"),
		RQuestEngine.STATUS_VERFUEGBAR,
		"45 Punkte = Herz 3 = Quest schaltet frei"
	)
	_teardown(gs)


func test_warte_quest_ueber_zeitsprung_mit_notification() -> void:
	var gs := _fresh_gs()
	var fake := FakeRegistry.new()
	fake.items = [
		{
			"id": "fx_warte",
			"typ": "neben",
			"geber": "rosi",
			"ziele": [{"typ": "warte_bis", "dauerMin": 60, "liveActivity": true}],
			"belohnung": {"muenzen": 10},
		}
	]
	RQuestKatalog.registry_override = fake
	RQuestKatalog.reset_cache()
	# WARN-SWEEP: die synthetische Quest hat keine echten Strings — den
	# Titel-Key in die gecachte DE-Tabelle legen, sonst schreit I18nService
	# bei warte_gestartet („Fehlender String-Key“) in jedem Testlauf.
	# Aufgeräumt wird unten per I18nService.reset_cache().
	I18nService.table("de")["rquest.q.fx_warte.titel"] = "Warte-Test"
	assert_true(RQuestState.annehmen(gs, "fx_warte"))
	assert_eq(RQuestState.status(gs, "fx_warte"), RQuestEngine.STATUS_WARTEND)
	var ids: Array = []
	for eintrag: Dictionary in NotifyStub.pending():
		ids.append(str(eintrag["id"]))
	assert_true(ids.has("rquest_fx_warte"), "Fertig-Notification ist geplant")
	assert_eq(RanchLiveActivity.aktive().size(), 1, "Live Activity laeuft")
	gs.clock.advance(59 * MIN_MS)
	assert_eq(RQuestState.tick(gs), [], "vor Ablauf loest tick nichts")
	gs.clock.advance(2 * MIN_MS)
	assert_eq(RQuestState.tick(gs), ["fx_warte"], "Zeitsprung loest das Warten")
	assert_eq(RQuestState.status(gs, "fx_warte"), RQuestEngine.STATUS_ERFUELLBAR)
	assert_eq(RanchLiveActivity.aktive().size(), 0, "Activity endet mit dem Warten")
	assert_true(RQuestState.abgeben(gs, "fx_warte"))
	assert_eq(NotifyStub.pending().size(), 0, "Abgabe raeumt Notifications ab")
	_teardown(gs)
	I18nService.reset_cache()


func test_verfuegbare_enthaelt_tagesaufgaben() -> void:
	var gs := _fresh_gs()
	var ids: Array = []
	for def: Dictionary in RQuestState.verfuegbare(gs):
		ids.append(str(def["id"]))
	assert_true(ids.has("haupt_01"), "Kapitel 1 ist sofort verfuegbar")
	assert_false(ids.has("haupt_02"), "Kapitel 2 haengt an haupt_01")
	var tages := 0
	for def: Dictionary in RQuestKatalog.tagesaufgaben(RQuestState.datum(gs)):
		if ids.has(str(def["id"])):
			tages += 1
	assert_eq(tages, RQuestKatalog.TAGES_SLOTS, "alle Tages-Slots sind annehmbar")
	_teardown(gs)


func test_fremde_ranch_schluessel_ueberleben_quest_schreibzugriffe() -> void:
	var gs := _fresh_gs()
	gs.update(
		func(state: Dictionary) -> void:
			(state["ranch"] as Dictionary)["wetter"] = {"heute": "sonne"}
	)
	RQuestState.annehmen(gs, "haupt_01")
	assert_eq(
		gs.get_value("ranch.wetter"),
		{"heute": "sonne"},
		"RANCH-1-Daten bleiben beim Quest-Schreiben unberuehrt"
	)
	_teardown(gs)
