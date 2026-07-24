class_name OnboardingFlow
extends Control
## Onboarding-Sequenz „knuffig wie AC“ (F §2.2, OHNE Bett-Schritt):
## Begrüßung/Name → Spitzname (optional) → Char-Editor (Slider, live
## Gooby-Preview) → „Los geht’s!“. Alle Texte aus strings/ (DE führend).
##
## Ergebnis geht als `completed(profile)`-Signal raus (Vertrag mit W1d,
## siehe handoffs/W1c-needs-from-state.md). Extension-Point für W2a:
## `register_final_step(callable)` — der Callable bekommt dieses Flow-Node,
## zeigt seinen Schritt und ruft am Ende `final_step_finished()`.

signal completed(profile: Dictionary)
signal step_changed(step: OnboardingLogic.Step)

var logic := OnboardingLogic.new()

var _final_steps: Array[Callable] = []
var _pending_final: Array[Callable] = []

@onready var _steps: Dictionary = {
	OnboardingLogic.Step.WELCOME: %StepWelcome,
	OnboardingLogic.Step.NICKNAME: %StepNickname,
	OnboardingLogic.Step.EDITOR: %StepEditor,
	OnboardingLogic.Step.DONE: %StepDone,
}
@onready var _name_edit: LineEdit = %NameEdit
@onready var _name_hint: Label = %NameHint
@onready var _nickname_edit: LineEdit = %NicknameEdit
@onready var _preview: GoobyPreview = %GoobyPreview
@onready var _editor_title: Label = %EditorTitle
@onready var _done_text: Label = %DoneText


func _ready() -> void:
	_apply_texts()
	_build_sliders()
	%WelcomeNext.pressed.connect(_on_welcome_next)
	_name_edit.text_submitted.connect(func(_t: String) -> void: _on_welcome_next())
	%NicknameNext.pressed.connect(_on_nickname_next)
	_nickname_edit.text_submitted.connect(func(_t: String) -> void: _on_nickname_next())
	%EditorSkip.pressed.connect(_on_editor_skip)
	%EditorNext.pressed.connect(_on_editor_next)
	%DoneButton.pressed.connect(_on_done_pressed)
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
	step_changed.emit(step)


func _on_welcome_next() -> void:
	if logic.submit_name(_name_edit.text):
		_name_hint.visible = false
		_show_step(logic.step)
	else:
		_name_hint.visible = true


func _on_nickname_next() -> void:
	logic.submit_nickname(_nickname_edit.text)
	_show_step(logic.step)


func _on_slider_changed(value: float, key: String) -> void:
	logic.set_editor_value(key, value)
	_preview.set_morphs(logic.editor)


func _on_editor_skip() -> void:
	logic.skip_editor()
	_show_step(logic.step)


func _on_editor_next() -> void:
	logic.confirm_editor()
	_show_step(logic.step)


func _on_done_pressed() -> void:
	_pending_final = _final_steps.duplicate()
	_run_next_final_step()


func _run_next_final_step() -> void:
	if _pending_final.is_empty():
		completed.emit(logic.finish())
		return
	var next: Callable = _pending_final.pop_front()
	next.call(self)
