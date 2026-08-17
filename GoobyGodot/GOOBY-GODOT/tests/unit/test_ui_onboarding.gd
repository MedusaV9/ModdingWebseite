extends W1cTestCase
## Onboarding: pure Statemaschine + Szenen-Flow (Signale, Extension-Point).

const FLOW_SCENE := preload("res://scripts/ui/onboarding/onboarding_flow.tscn")


func test_logik_name_ist_pflicht() -> void:
	var logic := OnboardingLogic.new()
	check(not logic.submit_name(""), "leerer Name abgelehnt")
	check(not logic.submit_name("   "), "Nur-Leerzeichen-Name abgelehnt")
	check_eq(logic.step, OnboardingLogic.Step.WELCOME, "Step bleibt WELCOME")
	check(logic.submit_name("  Mia  "), "gültiger Name angenommen")
	check_eq(logic.player_name, "Mia", "Name wird getrimmt")
	check_eq(logic.step, OnboardingLogic.Step.NICKNAME, "weiter zu NICKNAME")
	var langer_name := "X".repeat(60)
	var logic2 := OnboardingLogic.new()
	logic2.submit_name(langer_name)
	check_eq(logic2.player_name.length(), OnboardingLogic.NAME_MAX_LEN, "Name gekappt")


func test_logik_spitzname_default_gooby() -> void:
	var logic := OnboardingLogic.new()
	logic.submit_name("Mia")
	logic.submit_nickname("   ")
	check_eq(logic.gooby_nickname, "Gooby", "leerer Spitzname → Default Gooby")
	check_eq(logic.step, OnboardingLogic.Step.EDITOR, "weiter zu EDITOR")
	var logic2 := OnboardingLogic.new()
	logic2.submit_name("Mia")
	logic2.submit_nickname("Flausch")
	check_eq(logic2.gooby_nickname, "Flausch", "eigener Spitzname übernommen")


func test_logik_editor_clamps_und_skip() -> void:
	var logic := OnboardingLogic.new()
	logic.submit_name("Mia")
	logic.submit_nickname("")
	check(logic.set_editor_value("eye_scale", 99.0), "eye_scale gesetzt")
	check_approx(logic.editor["eye_scale"], 1.4, "eye_scale geclampt auf Max")
	check(logic.set_editor_value("eyes_apart", -5.0), "eyes_apart gesetzt")
	check_approx(logic.editor["eyes_apart"], -1.0, "eyes_apart geclampt auf Min")
	check(not logic.set_editor_value("quatsch", 1.0), "unbekannter Key abgelehnt")
	logic.skip_editor()
	check_eq(logic.step, OnboardingLogic.Step.DONE, "Skip → DONE")
	check_approx(logic.editor["eye_scale"], 1.0, "Skip setzt Editor auf Defaults zurück")


func test_logik_result_vertragsform() -> void:
	var logic := OnboardingLogic.new()
	logic.submit_name("Mia")
	logic.submit_nickname("Flausch")
	logic.set_editor_value("ear_len", 1.2)
	logic.confirm_editor()
	var result := logic.finish()
	check_eq(logic.step, OnboardingLogic.Step.FINISHED, "finish sperrt Maschine")
	check_eq(result["player_name"], "Mia", "player_name im Result")
	check_eq(result["gooby_nickname"], "Flausch", "gooby_nickname im Result")
	var editor: Dictionary = result["editor"]
	for key in ["eyes_apart", "eye_scale", "ear_len", "chubby"]:
		check(editor.has(key), "editor.%s vorhanden" % key)
	check_approx(editor["ear_len"], 1.2, "Slider-Wert im Result")


func test_flow_szene_komplett() -> void:
	var flow := FLOW_SCENE.instantiate()
	mount(flow)
	await tree.process_frame
	var results: Array = []
	flow.completed.connect(func(profile: Dictionary) -> void: results.append(profile))
	check(flow.get_node("%StepWelcome").visible, "Start: Welcome sichtbar")
	(flow.get_node("%WelcomeNext") as Button).pressed.emit()
	check(flow.get_node("%NameHint").visible, "leerer Name → Pflicht-Hinweis")
	check(flow.get_node("%StepWelcome").visible, "bleibt auf Welcome")
	(flow.get_node("%NameEdit") as LineEdit).text = "Mia"
	(flow.get_node("%WelcomeNext") as Button).pressed.emit()
	check(flow.get_node("%StepNickname").visible, "weiter zu Spitzname")
	(flow.get_node("%NicknameNext") as Button).pressed.emit()
	check(flow.get_node("%StepEditor").visible, "weiter zum Editor")
	var slider := flow.get_node("%SliderRows").find_child("SliderEarLen", true, false)
	check(slider != null, "Ohrenlängen-Slider existiert")
	(slider as HSlider).value = 1.3
	(flow.get_node("%EditorNext") as Button).pressed.emit()
	check(flow.get_node("%StepDone").visible, "weiter zu Los geht's")
	(flow.get_node("%DoneButton") as Button).pressed.emit()
	check_eq(results.size(), 1, "completed genau einmal")
	if results.size() == 1:
		var profile: Dictionary = results[0]
		check_eq(profile["player_name"], "Mia", "Profil: Name")
		check_eq(profile["gooby_nickname"], "Gooby", "Profil: Default-Spitzname")
		check_approx(profile["editor"]["ear_len"], 1.3, "Profil: Slider-Wert")
	unmount(flow)


func test_flow_extension_point_final_step() -> void:
	var flow := FLOW_SCENE.instantiate()
	mount(flow)
	await tree.process_frame
	var calls: Array = []
	var results: Array = []
	flow.completed.connect(func(profile: Dictionary) -> void: results.append(profile))
	var bett_step := func(f: OnboardingFlow) -> void:
		calls.append("bett")
		f.final_step_finished()
	flow.register_final_step(bett_step)
	(flow.get_node("%NameEdit") as LineEdit).text = "Mia"
	(flow.get_node("%WelcomeNext") as Button).pressed.emit()
	(flow.get_node("%NicknameNext") as Button).pressed.emit()
	(flow.get_node("%EditorSkip") as Button).pressed.emit()
	(flow.get_node("%DoneButton") as Button).pressed.emit()
	check_eq(calls, ["bett"], "Final-Step wurde gerufen")
	check_eq(results.size(), 1, "completed erst nach Final-Step")
	unmount(flow)


func test_flow_hat_tastatur_und_controller_fokus_pro_schritt() -> void:
	var flow := FLOW_SCENE.instantiate()
	mount(flow)
	await tree.process_frame
	await tree.process_frame
	var name_edit := flow.get_node("%NameEdit") as LineEdit
	var welcome_next := flow.get_node("%WelcomeNext") as Button
	check_eq(name_edit.focus_mode, Control.FOCUS_ALL, "Name ist fokussierbar")
	check_eq(welcome_next.focus_mode, Control.FOCUS_ALL, "Weiter ist fokussierbar")
	check_eq(tree.root.gui_get_focus_owner(), name_edit, "Welcome startet im Namensfeld")
	check(not welcome_next.focus_next.is_empty(), "Tab-Navigation ist verdrahtet")
	name_edit.text = "Mia"
	welcome_next.pressed.emit()
	await tree.process_frame
	var nickname_edit := flow.get_node("%NicknameEdit") as LineEdit
	check_eq(tree.root.gui_get_focus_owner(), nickname_edit, "nächster Schritt übernimmt Fokus")
	(flow.get_node("%NicknameNext") as Button).pressed.emit()
	await tree.process_frame
	var controls := FocusNavigation.focusable(flow.get_node("%StepEditor"))
	check(controls.size() >= 6, "Editor: Slider und Aktionen per Fokus erreichbar")
	for control in controls:
		check_eq(control.focus_mode, Control.FOCUS_ALL, "%s erlaubt Fokus" % control.name)
	unmount(flow)
