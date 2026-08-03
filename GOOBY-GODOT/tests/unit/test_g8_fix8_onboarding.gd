extends TestCase
## PT4-B5 (G8-Playtest, W18/R3): Onboarding-Karten im Leitformat quer.
## Zwei Teile, beide nachgemessen statt geraten:
## 1. „Karten 7,5 % links der Mitte" — im xvfb-Playtest erzeugte der zu
##    kleine Screen PHANTOM-Insets rechts/unten (PT3-B6); die Karten
##    zentrieren KORREKT im Safe-Rechteck. Hier festgenagelt: ohne Insets
##    mittig im Canvas, mit simulierten Phantom-Insets mittig im Safe-Feld.
## 2. „Editor-Karte gequetscht" — ECHTER Bug: _relayout maß chrome_h bei
##    _ready, als der Autowrap-EditorText noch 0 px breit war und
##    Wort-pro-Zeile-Minimalhöhe (~350 px) meldete. Der EditorScroll bekam
##    nur den Rest (27 px im Playtest): Preview + Regler unsichtbar, nur
##    „Augenabstand" + Scrollbalken ragten heraus. Fix: Text vor der
##    Messung auf Kartenbreite bringen (size.x + update_minimum_size).

const FLOW_SCENE := preload("res://scripts/ui/onboarding/onboarding_flow.tscn")
## Leitformat der G8-Playtests (2868x1320 quer → Canvas 1564x720).
const LEIT_QUER := Vector2i(2868, 1320)
## xvfb-Screen der Playtest-Umgebung (PT3-B6: kleiner als das Fenster).
const XVFB_SCREEN := Vector2(1280.0, 1024.0)

var _saved_root := Vector2i.ZERO


func _mount_flow(window: Vector2i, phantom_insets: bool) -> OnboardingFlow:
	_saved_root = tree.root.size
	tree.root.size = window
	await wait_frames(1)
	if phantom_insets:
		# Safe-Rect in CANVAS-Koordinaten, wie ihn der xvfb-Lauf meldet:
		# Screen (1280x1024) mal Fenster→Canvas-Faktor.
		var canvas := Vector2(tree.root.get_visible_rect().size)
		var faktor := canvas.y / float(window.y)
		UiScale.insets_override = Rect2(Vector2.ZERO, XVFB_SCREEN * faktor)
	var flow: OnboardingFlow = FLOW_SCENE.instantiate()
	tree.root.add_child(flow)
	await wait_frames(2)
	return flow


func _unmount(flow: OnboardingFlow) -> void:
	UiScale.insets_override = Rect2()
	flow.queue_free()
	await wait_frames(2)
	tree.root.size = _saved_root
	await wait_frames(1)


## Bis zur Editor-Karte klicken (Name → Spitzname → Editor).
func _zum_editor(flow: OnboardingFlow) -> void:
	(flow.get_node("%NameEdit") as LineEdit).text = "Pionier"
	(flow.get_node("%WelcomeNext") as Button).pressed.emit()
	(flow.get_node("%NicknameNext") as Button).pressed.emit()
	await wait_frames(2)


## Slide-in der Karten ausschwingen lassen (Muster test_ui_onboarding_polish)
## — Zentrier-Messungen mitten im Tween wären um bis zu 56 px verschoben.
func _warte_bis_ruhe(flow: OnboardingFlow) -> void:
	var steps := flow.get_node("Steps") as Control
	var frames := 0
	while frames < 180:
		await tree.process_frame
		frames += 1
		if absf(steps.position.x - flow._steps_rest.x) <= 0.5 and steps.modulate.a > 0.999:
			break
	await wait_frames(1)


## PT4-B5-Kern: Editor-Karte zeigt ihren Inhalt VOLL im nutzbaren Feld.
func _assert_editor_voll(flow: OnboardingFlow, feld: Rect2) -> void:
	var editor := flow.find_child("StepEditor", true, false) as Control
	var preview := flow.find_child("GoobyPreview", true, false) as Control
	var scroll := flow.find_child("EditorScroll", true, false) as ScrollContainer
	assert_true(preview.is_visible_in_tree(), "GoobyPreview sichtbar")
	assert_true(
		editor.get_global_rect().encloses(preview.get_global_rect()),
		(
			"Preview VOLL in der Karte (vorher bekam der Scroll ~27 px Krümel: %s in %s)"
			% [preview.get_global_rect(), editor.get_global_rect()]
		)
	)
	assert_true(
		scroll.custom_minimum_size.y >= preview.get_combined_minimum_size().y,
		(
			"Scroll-Deckel (%.0f) >= Preview-Höhe (%.0f)"
			% [scroll.custom_minimum_size.y, preview.get_combined_minimum_size().y]
		)
	)
	assert_true(
		feld.encloses(editor.get_global_rect()),
		"Karte bleibt im nutzbaren Feld (%s in %s)" % [editor.get_global_rect(), feld]
	)


func test_karten_mittig_und_editor_voll_ohne_insets() -> void:
	var flow := await _mount_flow(LEIT_QUER, false)
	var canvas := Vector2(tree.root.get_visible_rect().size)
	var mitte_soll := canvas.x / 2.0
	await _warte_bis_ruhe(flow)
	var welcome := flow.find_child("StepWelcome", true, false) as Control
	assert_almost(
		welcome.get_global_rect().get_center().x, mitte_soll, 2.0, "Welcome mittig im Canvas"
	)
	await _zum_editor(flow)
	await _warte_bis_ruhe(flow)
	var editor := flow.find_child("StepEditor", true, false) as Control
	assert_almost(
		editor.get_global_rect().get_center().x, mitte_soll, 2.0, "Editor mittig im Canvas"
	)
	_assert_editor_voll(flow, Rect2(Vector2.ZERO, canvas))
	await _unmount(flow)


func test_karten_im_safe_feld_bei_phantom_insets() -> void:
	var flow := await _mount_flow(LEIT_QUER, true)
	var canvas := Vector2(tree.root.get_visible_rect().size)
	var insets := UiScale.safe_insets_canvas(tree.root)
	var safe_mitte := (float(insets["left"]) + canvas.x - float(insets["right"])) / 2.0
	var safe_feld := Rect2(
		float(insets["left"]),
		float(insets["top"]),
		canvas.x - float(insets["left"]) - float(insets["right"]),
		canvas.y - float(insets["top"]) - float(insets["bottom"])
	)
	await _warte_bis_ruhe(flow)
	var welcome := flow.find_child("StepWelcome", true, false) as Control
	assert_almost(
		welcome.get_global_rect().get_center().x,
		safe_mitte,
		2.0,
		"Welcome zentriert im SAFE-Feld (die 7,5 % im Playtest waren Phantom-Insets, PT3-B6)"
	)
	await _zum_editor(flow)
	await _warte_bis_ruhe(flow)
	var editor := flow.find_child("StepEditor", true, false) as Control
	assert_almost(
		editor.get_global_rect().get_center().x, safe_mitte, 2.0, "Editor zentriert im SAFE-Feld"
	)
	_assert_editor_voll(flow, safe_feld)
	await _unmount(flow)
