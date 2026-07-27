class_name WhatsNextHint
extends Control
## Dezenter „Was nun?“-Hinweis (REST-2, roter Faden): eine kleine AC-Karte
## oben mittig, die den nächsten sinnvollen Schritt vorschlägt (Vorschlag
## kommt vom WhatsNextAdvisor über den DailyQuestService). Bewusst leise:
## blendet nach ein paar Sekunden von selbst aus, ist pro Vorschlag+Tag nur
## einmal wegdrückbar (×) und tippbar (öffnet z. B. das Quest-Panel).

signal tapped(suggestion: Dictionary)
signal dismissed(suggestion: Dictionary)

const ICON_DIR := "res://assets/ui/icons/"
## Nach so vielen Sekunden räumt sich der Hinweis selbst weg (kein Nerven).
const AUTO_HIDE_S := 14.0
const MAX_WIDTH_PX := 380.0

var _suggestion: Dictionary = {}
var _card: PanelContainer
var _title: Label
var _text: Label
var _timer: Timer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(hide_hint)
	add_child(_timer)
	_build_card()
	get_viewport().size_changed.connect(_relayout)


func show_suggestion(suggestion: Dictionary) -> void:
	var was_same := str(suggestion.get("id", "")) == str(_suggestion.get("id", ""))
	_suggestion = suggestion.duplicate(true)
	_title.text = I18nService.t("quests.wasnun.titel")
	_text.text = _resolve_text(suggestion)
	_relayout()
	if visible and was_same:
		return
	visible = true
	_relayout_settled()
	UiMotion.pop_in(_card)
	_timer.start(AUTO_HIDE_S)


func hide_hint() -> void:
	visible = false
	_timer.stop()


## Vorschlagstext auflösen — `titel_key` in den Args wird zuerst übersetzt
## (z. B. quests.wasnun.quest mit dem Titel der offenen Quest).
func _resolve_text(suggestion: Dictionary) -> String:
	var args: Dictionary = {}
	var raw: Variant = suggestion.get("args", {})
	if raw is Dictionary:
		args = (raw as Dictionary).duplicate()
	if args.has("titel_key"):
		args["titel"] = I18nService.t(str(args["titel_key"]))
		args.erase("titel_key")
	return I18nService.t(str(suggestion.get("text_key", "")), args)


func _build_card() -> void:
	_card = PanelContainer.new()
	_card.name = "WasNunKarte"
	_card.theme_type_variation = "AcCard"
	_card.mouse_filter = Control.MOUSE_FILTER_STOP
	_card.gui_input.connect(_on_card_input)
	add_child(_card)
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		margin.add_theme_constant_override(side, 10)
	_card.add_child(margin)
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)
	var icon := TextureRect.new()
	icon.texture = load(ICON_DIR + "sparkle.svg")
	icon.custom_minimum_size = Vector2(22, 22)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.self_modulate = AcTokens.YELLOW_DARK
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 2)
	text_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(text_box)
	_title = Label.new()
	_title.theme_type_variation = "CaptionLabel"
	_title.add_theme_font_override("font", ThemeService.font(800))
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(_title)
	_text = Label.new()
	_text.theme_type_variation = "CaptionLabel"
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	text_box.add_child(_text)
	var close := SquishButton.new()
	close.name = "WasNunSchliessen"
	close.theme_type_variation = "GhostButton"
	close.icon = load(ICON_DIR + "close.svg")
	close.focus_mode = Control.FOCUS_NONE
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func() -> void: dismissed.emit(_suggestion))
	box.add_child(close)


## Autowrap-Minima stehen erst NACH dem ersten Layout-Pass — beim ersten
## Einblenden fror reset_size() sonst eine zu hohe Karte ein. Zwei Frames
## warten, dann die echte Größe nachziehen (fire-and-forget).
func _relayout_settled() -> void:
	var tree := get_tree()
	if tree == null:
		return
	await tree.process_frame
	await tree.process_frame
	if is_instance_valid(self) and _card != null and is_instance_valid(_card):
		_relayout()


## Oben mittig unter der Statuszeile — schmal gedeckelt, Safe-Area-bewusst.
func _relayout() -> void:
	if _card == null:
		return
	var f := UiScale.for_viewport(get_viewport())
	var canvas := Vector2(get_viewport().get_visible_rect().size)
	var insets := UiScale.safe_insets_canvas(get_viewport(), Rect2())
	var width := minf(MAX_WIDTH_PX * f, canvas.x - 24.0)
	_card.custom_minimum_size = Vector2(width, 0.0)
	_card.reset_size()
	var size_now := _card.get_combined_minimum_size()
	_card.position = Vector2((canvas.x - size_now.x) / 2.0, float(insets["top"]) + 76.0 * f)


func _on_card_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		AudioDirector.try_play(self, "ui_chip")
		tapped.emit(_suggestion)
