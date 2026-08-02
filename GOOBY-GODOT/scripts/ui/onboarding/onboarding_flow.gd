class_name OnboardingFlow
extends Control
## Onboarding-Sequenz „knuffig wie AC“ (F §2.2, OHNE Bett-Schritt):
## Begrüßung/Name → Spitzname (optional) → Char-Editor (Slider, live
## Gooby-Preview) → „Los geht’s!“. Alle Texte aus strings/ (DE führend).
##
## W4/POLISH-5-Charme: Gooby brabbelt die Schritt-Texte (W1b `GoobyVoice`,
## Text tickert silbensynchron über `visible_ratio` mit), sanfte
## Slide-Übergänge zwischen den Karten und Konfetti beim Abschluss
## (eigener CPUParticles2D-Burst, W3d-Album-Muster). Statemaschine und
## `completed`-Vertrag bleiben unangetastet; Sichtbarkeit schaltet
## weiterhin SYNCHRON (Test-Contract test_ui_onboarding).
##
## Ergebnis geht als `completed(profile)`-Signal raus (Vertrag mit W1d,
## siehe handoffs/W1c-needs-from-state.md). Extension-Point für W2a:
## `register_final_step(callable)` — der Callable bekommt dieses Flow-Node,
## zeigt seinen Schritt und ruft am Ende `final_step_finished()`.

signal completed(profile: Dictionary)
signal step_changed(step: OnboardingLogic.Step)

const SLIDE_IN_PX := 56.0
## G4/P23 — Design-Basen des Karten-Layouts (skalieren über ScreenShell).
const CARD_BASE_WIDTH := 540.0
const EDITOR_CARD_BASE_WIDTH := 680.0
const TEXT_BASE_WIDTH := 470.0
const SLIDER_BASE_WIDTH := 280.0
const SLIDER_BASE_HEIGHT := 32.0

var logic := OnboardingLogic.new()

var _final_steps: Array[Callable] = []
var _pending_final: Array[Callable] = []
var _voice: GoobyVoice
var _speaking_label: Label
var _slide_tween: Tween
## P57: Ruhelage des Steps-Containers (Safe-Area-Rahmen, s. _relayout) —
## die Slide-Animation startet/endet relativ zu dieser Position.
var _steps_rest := Vector2.ZERO

@onready var _steps: Dictionary = {
	OnboardingLogic.Step.WELCOME: %StepWelcome,
	OnboardingLogic.Step.NICKNAME: %StepNickname,
	OnboardingLogic.Step.EDITOR: %StepEditor,
	OnboardingLogic.Step.DONE: %StepDone,
}
@onready var _steps_box: Control = $Steps
@onready var _name_edit: LineEdit = %NameEdit
@onready var _name_hint: Label = %NameHint
@onready var _nickname_edit: LineEdit = %NicknameEdit
@onready var _preview: GoobyPreview = %GoobyPreview
@onready var _editor_title: Label = %EditorTitle
@onready var _done_text: Label = %DoneText


func _ready() -> void:
	_apply_texts()
	_build_sliders()
	_setup_voice()
	%WelcomeNext.pressed.connect(_on_welcome_next)
	_name_edit.text_submitted.connect(func(_t: String) -> void: _on_welcome_next())
	%NicknameNext.pressed.connect(_on_nickname_next)
	_nickname_edit.text_submitted.connect(func(_t: String) -> void: _on_nickname_next())
	%EditorSkip.pressed.connect(_on_editor_skip)
	%EditorNext.pressed.connect(_on_editor_next)
	%DoneButton.pressed.connect(_on_done_pressed)
	_relayout()
	get_viewport().size_changed.connect(_relayout)
	_show_step(OnboardingLogic.Step.WELCOME)


## W2a-Extension-Point: zusätzlichen Abschluss-Schritt anmelden (Bett bauen).
func register_final_step(step: Callable) -> void:
	_final_steps.append(step)


## Muss von jedem registrierten Final-Step nach Abschluss gerufen werden.
func final_step_finished() -> void:
	_run_next_final_step()


func _apply_texts() -> void:
	%WelcomeTitle.text = I18nService.t("onboarding.welcome_titel")
	%WelcomeText.text = I18nService.t("onboarding.welcome_text")
	_name_edit.placeholder_text = I18nService.t("onboarding.name_placeholder")
	_name_hint.text = I18nService.t("onboarding.name_pflicht")
	%WelcomeNext.text = I18nService.t("ui.weiter")
	%NicknameTitle.text = I18nService.t("onboarding.nickname_titel")
	%NicknameText.text = I18nService.t("onboarding.nickname_text")
	_nickname_edit.placeholder_text = I18nService.t("onboarding.nickname_placeholder")
	%NicknameNext.text = I18nService.t("ui.weiter")
	%EditorText.text = I18nService.t("onboarding.editor_text")
	%PreviewHint.text = I18nService.t("onboarding.editor_hinweis")
	%EditorSkip.text = I18nService.t("ui.ueberspringen")
	%EditorNext.text = I18nService.t("ui.weiter")
	%DoneTitle.text = I18nService.t("onboarding.done_titel")
	%DoneButton.text = I18nService.t("onboarding.done_button")


func _build_sliders() -> void:
	var rows: VBoxContainer = %SliderRows
	for key: String in OnboardingLogic.EDITOR_DEFAULTS:
		var label := Label.new()
		label.name = "Label" + key.to_pascal_case()
		label.theme_type_variation = "SoftLabel"
		label.text = I18nService.t("onboarding.slider_" + _slider_string_key(key))
		rows.add_child(label)
		var slider := HSlider.new()
		slider.name = "Slider" + key.to_pascal_case()
		var range_v: Vector2 = OnboardingLogic.EDITOR_RANGES[key]
		slider.min_value = range_v.x
		slider.max_value = range_v.y
		slider.step = 0.01
		slider.value = OnboardingLogic.EDITOR_DEFAULTS[key]
		slider.custom_minimum_size = Vector2(280, 32)
		slider.value_changed.connect(_on_slider_changed.bind(key))
		rows.add_child(slider)


func _slider_string_key(editor_key: String) -> String:
	match editor_key:
		"eyes_apart":
			return "augenweite"
		"eye_scale":
			return "augengroesse"
		"ear_len":
			return "ohrenlaenge"
		_:
			return "pausbacken"


## G4/P23 — EIN Layout-Pass nach ScreenShell-Muster (daily_bonus_popup):
## Kartenbreiten über card_width statt Fest-px, physischer Touch-Floor auf
## Buttons/Eingaben/Slider-Griffen, Editor-Spalten stapeln im Hochformat.
## Läuft bei _ready + size_changed — NIE in _show_step (Sichtbarkeit der
## Steps muss SYNCHRON schalten, Vertrag test_ui_onboarding).
## P57 (FB3: „EditorNext/Überspringen laufen unten aus dem Canvas"): der
## Steps-Container zentriert jetzt IM SAFE-Rechteck (frame) statt auf dem
## vollen Canvas, und die Editor-Karte wird auf die Safe-Höhe gedeckelt —
## Titel + Knopfleiste bleiben verankert, nur EditorBox scrollt bei Not.
func _relayout() -> void:
	if not is_inside_tree():
		return
	var m := ScreenShell.metrics(get_viewport())
	var f: float = m["f"]
	var canvas: Vector2 = m["canvas"]
	ScreenShell.scale_fonts(self, f)
	# Läuft noch ein Slide, wird er gekappt — frame() setzt gleich die
	# frische Ruhelage, ein alter Tween zöge zum veralteten Ziel zurück.
	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
		_steps_box.modulate.a = 1.0
	ScreenShell.frame(_steps_box, m)
	_steps_rest = Vector2(_steps_box.offset_left, _steps_box.offset_top)
	var card_w := ScreenShell.card_width(m, CARD_BASE_WIDTH)
	var editor_w := ScreenShell.card_width(m, EDITOR_CARD_BASE_WIDTH)
	for card: Control in [%StepWelcome, %StepNickname, %StepDone]:
		card.custom_minimum_size = Vector2(card_w, 0.0)
	(%StepEditor as Control).custom_minimum_size = Vector2(editor_w, 0.0)
	# Autowrap-Textbreiten mit der Karte deckeln, sonst zwingt das 470er-
	# Minimum die Karte über schmale Hochformat-Lanes hinaus.
	var text_w := maxf(minf(TEXT_BASE_WIDTH * f, card_w - _card_pad_x(%StepWelcome)), 0.0)
	for text: Control in [%WelcomeText, %NameHint, %NicknameText, %DoneText]:
		text.custom_minimum_size.x = text_w
	for ziel: Control in [%WelcomeNext, %NicknameNext, %EditorSkip, %EditorNext, %DoneButton]:
		ScreenShell.touch_target(ziel, m)
	ScreenShell.touch_target(_name_edit, m)
	ScreenShell.touch_target(_nickname_edit, m)
	# Hochformat: Preview ÜBER die Slider stapeln (HBox → vertikal).
	(%EditorBox as BoxContainer).vertical = canvas.x < canvas.y
	var floor_px: float = m["floor_px"]
	for child in (%SliderRows as Control).get_children():
		if child is HSlider:
			(child as HSlider).custom_minimum_size = Vector2(
				SLIDER_BASE_WIDTH * f, maxf(SLIDER_BASE_HEIGHT * f, floor_px)
			)
	# P57 Höhen-Deckel: erst Chrome (Titel/Text/Knopfleiste/Karten-Ränder)
	# OHNE Scroll-Inhalt messen, dann bekommt der Scroll GENAU den Rest der
	# Safe-Höhe — passt der Inhalt, bleibt das Layout wie bisher.
	var scroll: ScrollContainer = %EditorScroll
	scroll.custom_minimum_size = Vector2.ZERO
	var insets: Dictionary = m["insets"]
	var safe_h := canvas.y - float(insets["top"]) - float(insets["bottom"])
	var avail_h := safe_h - 2.0 * ScreenShell.EDGE_Y * f
	var chrome_h := (%StepEditor as Control).get_combined_minimum_size().y
	var inhalt_h := (%EditorBox as Control).get_combined_minimum_size().y
	scroll.custom_minimum_size.y = clampf(avail_h - chrome_h, 0.0, inhalt_h)


## Horizontale Innenränder der Karten-StyleBox (AcCardLg) — get_margin
## liefert den EFFEKTIVEN Rand (Roh-Property kann -1 = Default sein).
func _card_pad_x(card: Control) -> float:
	var sb := card.get_theme_stylebox("panel")
	if sb == null:
		return 0.0
	return sb.get_margin(SIDE_LEFT) + sb.get_margin(SIDE_RIGHT)


func _show_step(step: OnboardingLogic.Step) -> void:
	for key: OnboardingLogic.Step in _steps:
		(_steps[key] as Control).visible = key == step
	if step == OnboardingLogic.Step.EDITOR:
		_editor_title.text = I18nService.t(
			"onboarding.editor_titel", {"nickname": logic.gooby_nickname}
		)
		_preview.set_morphs(logic.editor)
	if step == OnboardingLogic.Step.DONE:
		_done_text.text = I18nService.t(
			"onboarding.done_text", {"nickname": logic.gooby_nickname, "name": logic.player_name}
		)
		_burst_confetti()
	_animate_step_in()
	_speak_step(step)
	step_changed.emit(step)


## Neue Karte federt seitlich herein (Reduced Motion: harter Schnitt).
## Animiert wird der Steps-Container, nicht das Container-Kind — so
## funkt kein Layout-Pass des CenterContainers dazwischen. P57: Start und
## Ziel liegen relativ zur Safe-Area-Ruhelage (_steps_rest), nicht bei 0.
func _animate_step_in() -> void:
	if ThemeService.is_reduced_motion(self):
		return
	if _slide_tween != null and _slide_tween.is_valid():
		_slide_tween.kill()
	_steps_box.position = _steps_rest + Vector2(SLIDE_IN_PX, 0.0)
	_steps_box.modulate.a = 0.35
	_slide_tween = create_tween().set_parallel()
	(
		_slide_tween
		. tween_property(_steps_box, "position:x", _steps_rest.x, AcTokens.DUR_SHEET)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	_slide_tween.tween_property(_steps_box, "modulate:a", 1.0, AcTokens.DUR_SHEET / 2.0)


## W1b-Gebrabbel: nur mit echtem Audio-Backend (nicht headless) — die
## Text-Ticker-Kopplung läuft über das silbe-Signal.
func _setup_voice() -> void:
	if DisplayServer.get_name() == "headless":
		return
	_voice = GoobyVoice.new()
	_voice.name = "GoobyVoice"
	add_child(_voice)
	_voice.silbe.connect(_on_voice_silbe)
	_voice.fertig.connect(_on_voice_fertig)


func _speak_step(step: OnboardingLogic.Step) -> void:
	var label: Label = null
	var emotion := "happy"
	match step:
		OnboardingLogic.Step.WELCOME:
			label = %WelcomeText
		OnboardingLogic.Step.NICKNAME:
			label = %NicknameText
		OnboardingLogic.Step.EDITOR:
			label = %EditorText
		OnboardingLogic.Step.DONE:
			label = _done_text
			emotion = "ecstatic"
	if _speaking_label != null and is_instance_valid(_speaking_label):
		_speaking_label.visible_ratio = 1.0
	_speaking_label = label
	if label == null:
		return
	if _voice == null:
		label.visible_ratio = 1.0
		return
	label.visible_ratio = 0.0
	_voice.sagt(label.text, emotion)


func _on_voice_silbe(index: int, anzahl: int) -> void:
	if _speaking_label == null or not is_instance_valid(_speaking_label):
		return
	if anzahl > 0:
		_speaking_label.visible_ratio = clampf(float(index + 1) / float(anzahl), 0.0, 1.0)


func _on_voice_fertig() -> void:
	if _speaking_label != null and is_instance_valid(_speaking_label):
		_speaking_label.visible_ratio = 1.0


## Konfetti beim Abschluss (W3d-Album-Muster — JuiceKit hat kein Konfetti).
func _burst_confetti() -> void:
	# Fanfare auch bei Reduced Motion (Audio ist laut W4P1 nicht gegated).
	AudioDirector.try_play(self, "mg_win")
	if ThemeService.is_reduced_motion(self):
		return
	var particles := CPUParticles2D.new()
	particles.name = "KonfettiBurst"
	particles.position = size * Vector2(0.5, 0.4)
	particles.amount = 56
	particles.lifetime = 1.2
	particles.one_shot = true
	particles.explosiveness = 0.95
	particles.direction = Vector2(0, -1)
	particles.spread = 75.0
	particles.initial_velocity_min = 260.0
	particles.initial_velocity_max = 540.0
	particles.gravity = Vector2(0, 700)
	particles.scale_amount_min = 3.0
	particles.scale_amount_max = 7.0
	# color_INITIAL_ramp = zufällige Farbe PRO Schnipsel (color_ramp würde
	# alle Schnipsel gemeinsam über die Lebenszeit umfärben — einfarbig).
	particles.color_initial_ramp = _confetti_gradient()
	add_child(particles)
	particles.emitting = true
	get_tree().create_timer(1.6).timeout.connect(particles.queue_free)


func _on_welcome_next() -> void:
	if logic.submit_name(_name_edit.text):
		AudioDirector.try_play(self, "ui_confirm")
		_name_hint.visible = false
		_show_step(logic.step)
	else:
		AudioDirector.try_play(self, "ui_error")
		_name_hint.visible = true


func _on_nickname_next() -> void:
	AudioDirector.try_play(self, "ui_confirm")
	logic.submit_nickname(_nickname_edit.text)
	_show_step(logic.step)


func _on_slider_changed(value: float, key: String) -> void:
	logic.set_editor_value(key, value)
	_preview.set_morphs(logic.editor)


func _on_editor_skip() -> void:
	AudioDirector.try_play(self, "ui_back")
	logic.skip_editor()
	_show_step(logic.step)


func _on_editor_next() -> void:
	AudioDirector.try_play(self, "ui_confirm")
	logic.confirm_editor()
	_show_step(logic.step)


func _on_done_pressed() -> void:
	AudioDirector.try_play(self, "ui_confirm")
	_pending_final = _final_steps.duplicate()
	_run_next_final_step()


func _run_next_final_step() -> void:
	if _pending_final.is_empty():
		completed.emit(logic.finish())
		return
	var next: Callable = _pending_final.pop_front()
	next.call(self)


static func _confetti_gradient() -> Gradient:
	var gradient := Gradient.new()
	gradient.colors = PackedColorArray(
		[AcTokens.PINK, AcTokens.YELLOW, AcTokens.TEAL, AcTokens.LEAF]
	)
	gradient.offsets = PackedFloat32Array([0.0, 0.33, 0.66, 1.0])
	# Constant = jeder Schnipsel bekommt EINE der 4 Candy-Farben — lineare
	# Interpolation ergäbe matschige Zwischentöne (Pink→Gelb→Teal).
	gradient.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	return gradient
