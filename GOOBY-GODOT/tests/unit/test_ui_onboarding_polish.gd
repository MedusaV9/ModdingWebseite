extends W1cTestCase
## W4/POLISH-5: Onboarding-Charme — Slide-Übergang zwischen den Karten,
## Konfetti-Burst beim Abschluss-Schritt, Text-Ticker-Kopplung. Der
## Flow-Contract (synchrone Sichtbarkeit, completed-Signal) wird weiter
## von test_ui_onboarding.gd gehalten.

const FLOW_SCENE := preload("res://scripts/ui/onboarding/onboarding_flow.tscn")


func test_slide_uebergang_zwischen_schritten() -> void:
	var flow: OnboardingFlow = FLOW_SCENE.instantiate()
	mount(flow)
	await tree.process_frame
	(flow.get_node("%NameEdit") as LineEdit).text = "Mia"
	(flow.get_node("%WelcomeNext") as Button).pressed.emit()
	check(flow.get_node("%StepNickname").visible, "Sichtbarkeit bleibt SYNCHRON")
	var steps := flow.get_node("Steps") as Control
	check(steps.position.x > 0.0, "Karte startet seitlich versetzt (Slide-in)")
	# TRANS_BACK-Overshoot kreuzt die Null früh — auf Position UND
	# Alpha warten, sonst racet der Check gegen die halbe Blende.
	var frames := 0
	while (absf(steps.position.x) > 0.5 or steps.modulate.a < 0.999) and frames < 120:
		await tree.process_frame
		frames += 1
	check(absf(steps.position.x) <= 0.5, "Slide endet wieder in Ruhelage")
	check_approx(steps.modulate.a, 1.0, "Karte voll eingeblendet")
	unmount(flow)


func test_konfetti_beim_abschluss() -> void:
	var flow: OnboardingFlow = FLOW_SCENE.instantiate()
	mount(flow)
	await tree.process_frame
	check(flow.find_child("KonfettiBurst", true, false) == null, "vorher kein Konfetti")
	(flow.get_node("%NameEdit") as LineEdit).text = "Mia"
	(flow.get_node("%WelcomeNext") as Button).pressed.emit()
	(flow.get_node("%NicknameNext") as Button).pressed.emit()
	(flow.get_node("%EditorSkip") as Button).pressed.emit()
	check(flow.get_node("%StepDone").visible, "Abschluss-Karte sichtbar")
	var konfetti := flow.find_child("KonfettiBurst", true, false)
	check(konfetti is CPUParticles2D, "Konfetti-Burst existiert")
	if konfetti is CPUParticles2D:
		check((konfetti as CPUParticles2D).emitting, "Konfetti feuert")
		check((konfetti as CPUParticles2D).one_shot, "als One-Shot")
	unmount(flow)


func test_text_ticker_faellt_headless_auf_voll() -> void:
	# Headless gibt es keine GoobyVoice — der Text muss dann sofort ganz
	# lesbar sein (visible_ratio 1), nie halb aufgedeckt hängen bleiben.
	var flow: OnboardingFlow = FLOW_SCENE.instantiate()
	mount(flow)
	await tree.process_frame
	check_approx(
		(flow.get_node("%WelcomeText") as Label).visible_ratio, 1.0, "Welcome-Text voll sichtbar"
	)
	(flow.get_node("%NameEdit") as LineEdit).text = "Mia"
	(flow.get_node("%WelcomeNext") as Button).pressed.emit()
	check_approx(
		(flow.get_node("%NicknameText") as Label).visible_ratio, 1.0, "Nickname-Text voll sichtbar"
	)
	unmount(flow)
