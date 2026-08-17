extends TestCase
## REST-2 — handlungsgeführtes Onboarding: Schrittfolge (inkl. Überspringen
## und Tour-Ende), Erfüllung über echte Save-Zähler, Frische-Heuristik
## (Bestands-Saves bekommen NIE nachträglich eine Tour) und Resume.

const GameStateScript := preload("res://scripts/state/game_state.gd")

const NOW_MS := 1785448800000  # 2026-07-30 UTC

var _seq := 0


func _fresh_gs() -> Node:
	_seq += 1
	var dir := "user://rest2_tests/guide_%d_%d" % [Time.get_ticks_usec(), _seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(dir + "/save_v5.json")
	tree.root.add_child(gs)
	return gs


func _finish_flow(gs: Node) -> void:
	gs.apply_onboarding_profile({"player_name": "Tester", "gooby_nickname": "Flauschi"})


func _bump(gs: Node, key: String, amount := 1) -> void:
	gs.update(
		func(state: Dictionary) -> void:
			var counters: Dictionary = state["achievements"]["counters"]
			counters[key] = int(counters.get(key, 0)) + amount
	)


func test_schrittfolge_beginnt_mit_ankunft_und_endet_mit_ausblick() -> void:
	assert_eq(OnboardingGuideLogic.step_count(), 9, "9 Schritte in der Tour")
	assert_eq(str(OnboardingGuideLogic.step_at(0)["id"]), "ankunft")
	assert_eq(str(OnboardingGuideLogic.step_at(0)["art"]), "manuell")
	assert_eq(str(OnboardingGuideLogic.step_at(8)["id"]), "ausblick")
	assert_eq(str(OnboardingGuideLogic.step_at(8)["art"]), "manuell")
	var auto_ids: Array[String] = []
	for i in range(1, 8):
		assert_eq(str(OnboardingGuideLogic.step_at(i)["art"]), "auto", "Mitte = Tun-Schritte")
		auto_ids.append(str(OnboardingGuideLogic.step_at(i)["id"]))
	assert_eq(
		auto_ids,
		(
			["streicheln", "fuettern", "waschen", "muenzen", "minispiel", "moebel", "sticker"]
			as Array[String]
		),
		"Reihenfolge: erst Bedürfnisse, dann Münzen/Spiel/Möbel/Sticker"
	)


func test_erfuellung_laeuft_ueber_echte_zaehler() -> void:
	var gs := _fresh_gs()
	_finish_flow(gs)
	var base := OnboardingGuideLogic.snapshot(gs.state())
	assert_false(OnboardingGuideLogic.satisfied("fuettern", base, gs.state()))
	_bump(gs, "feeds")
	assert_true(OnboardingGuideLogic.satisfied("fuettern", base, gs.state()), "füttern zählt")
	assert_false(OnboardingGuideLogic.satisfied("waschen", base, gs.state()))
	_bump(gs, "washes")
	assert_true(OnboardingGuideLogic.satisfied("waschen", base, gs.state()), "waschen zählt")
	_bump(gs, "petsToday")
	assert_true(OnboardingGuideLogic.satisfied("streicheln", base, gs.state()), "streicheln zählt")
	assert_false(OnboardingGuideLogic.satisfied("muenzen", base, gs.state()))
	gs.update(
		func(state: Dictionary) -> void:
			state["economy"]["coinsEarned"] = int(state["economy"]["coinsEarned"]) + 5
	)
	assert_true(OnboardingGuideLogic.satisfied("muenzen", base, gs.state()), "Münzen zählen")
	assert_false(OnboardingGuideLogic.satisfied("minispiel", base, gs.state()))
	gs.update(func(state: Dictionary) -> void: state["minigames"]["plays"]["teaParty"] = 1)
	assert_true(OnboardingGuideLogic.satisfied("minispiel", base, gs.state()), "Runde zählt")
	assert_false(OnboardingGuideLogic.satisfied("moebel", base, gs.state()))
	gs.update(
		func(state: Dictionary) -> void:
			state["economy"]["coinsSpent"] = int(state["economy"]["coinsSpent"]) + 10
	)
	assert_true(OnboardingGuideLogic.satisfied("moebel", base, gs.state()), "Einkauf zählt")
	assert_false(OnboardingGuideLogic.satisfied("sticker", base, gs.state()))
	gs.update(func(state: Dictionary) -> void: state["stickers"]["unlocked"]["s1"] = NOW_MS)
	assert_true(OnboardingGuideLogic.satisfied("sticker", base, gs.state()), "Sticker zählt")
	gs.get_parent().remove_child(gs)
	gs.free()


func test_frische_heuristik_schont_bestands_saves() -> void:
	var gs := _fresh_gs()
	_finish_flow(gs)
	assert_true(OnboardingGuideLogic.should_start(gs.state()), "frischer Save bekommt die Tour")
	gs.set_value("progression.level", 7)
	assert_false(OnboardingGuideLogic.should_start(gs.state()), "Level 7 ist kein Anfänger")
	# attach_to hakt die Tour bei Bestands-Saves STILL ab.
	var guide := OnboardingGuide.attach_to(tree.root, gs)
	assert_eq(guide, null, "kein Guide für Bestands-Saves")
	assert_true(bool(gs.get_value("onboarding.guide.done", false)), "still als erledigt markiert")
	gs.get_parent().remove_child(gs)
	gs.free()


func test_guide_laeuft_durch_ankunft_streicheln_und_ueberspringen() -> void:
	var gs := _fresh_gs()
	_finish_flow(gs)
	var host := Node.new()
	tree.root.add_child(host)
	var guide := OnboardingGuide.attach_to(host, gs)
	assert_ne(guide, null, "frischer Save startet die Tour")
	await wait_frames(2)
	assert_eq(guide.current_step_id(), "ankunft", "Start: Ankunfts-Inszenierung")
	guide._on_next_pressed()
	assert_eq(guide.current_step_id(), "streicheln", "Weiter-Knopf schaltet weiter")
	assert_eq(int(gs.get_value("onboarding.guide.step", -1)), 1, "Fortschritt persistiert")
	# Echtes Streicheln erfüllt den Schritt (Feier, dann automatisch weiter).
	gs.update(func(state: Dictionary) -> void: state["achievements"]["counters"]["petsToday"] = 1)
	RewardHub.note_action(gs)
	await tree.create_timer(2.4).timeout
	assert_eq(guide.current_step_id(), "fuettern", "Erfüllung schaltet nach der Feier weiter")
	# Sanfter Ausstieg pro Schritt: Überspringen.
	guide._on_skip_step()
	assert_eq(guide.current_step_id(), "waschen", "Überspringen geht ohne Feier weiter")
	# Tour-Ende (x): merken + nie wieder.
	guide._end_tour()
	await wait_frames(2)
	assert_true(bool(gs.get_value("onboarding.guide.skipped", false)), "Tour-Ende merkt skipped")
	assert_true(bool(gs.get_value("onboarding.guide.done", false)), "…und done")
	var again := OnboardingGuide.attach_to(host, gs)
	assert_eq(again, null, "übersprungene Tour kommt nie wieder")
	tree.root.remove_child(host)
	host.free()
	gs.get_parent().remove_child(gs)
	gs.free()


func test_resume_mitten_in_der_tour_auch_wenn_nicht_mehr_frisch() -> void:
	var gs := _fresh_gs()
	_finish_flow(gs)
	gs.update(
		func(state: Dictionary) -> void:
			state["onboarding"]["guide"] = {
				"done": false, "skipped": false, "step": 3, "base": {"washes": 0}
			}
	)
	gs.set_value("progression.level", 9)
	var host := Node.new()
	tree.root.add_child(host)
	var guide := OnboardingGuide.attach_to(host, gs)
	assert_ne(guide, null, "angefangene Tour läuft weiter (Resume)")
	await wait_frames(2)
	assert_eq(guide.current_step_id(), "waschen", "Resume auf Schritt 3")
	tree.root.remove_child(host)
	host.free()
	gs.get_parent().remove_child(gs)
	gs.free()


func test_guide_aktionen_sind_fokussierbar_und_sichtbar_verdrahtet() -> void:
	var gs := _fresh_gs()
	_finish_flow(gs)
	var router := tree.root.get_node_or_null("SceneRouter")
	var previous_scene: Node = router.get("_current_scene")
	var room_stub := RoomBase.new()
	router.set("_current_scene", room_stub)
	var host := Node.new()
	tree.root.add_child(host)
	var guide := OnboardingGuide.attach_to(host, gs)
	assert_ne(guide, null)
	await wait_frames(3)
	assert_eq(guide._next_btn.focus_mode, Control.FOCUS_ALL, "Weiter erlaubt Controller-Fokus")
	assert_eq(guide._skip_btn.focus_mode, Control.FOCUS_ALL, "Überspringen erlaubt Fokus")
	assert_eq(guide._close_btn.focus_mode, Control.FOCUS_ALL, "Tour-Ende erlaubt Fokus")
	assert_eq(tree.root.gui_get_focus_owner(), guide._next_btn, "Primäraktion erhält Erstfokus")
	assert_false(
		guide._next_btn.focus_next.is_empty(), "sichtbare Aktionen sind zyklisch verdrahtet"
	)
	guide._on_next_pressed()
	await wait_frames(2)
	assert_eq(
		tree.root.gui_get_focus_owner(), guide._skip_btn, "Auto-Schritt fokussiert Überspringen"
	)
	tree.root.remove_child(host)
	host.free()
	gs.get_parent().remove_child(gs)
	gs.free()
	router.set("_current_scene", previous_scene)
	room_stub.free()
