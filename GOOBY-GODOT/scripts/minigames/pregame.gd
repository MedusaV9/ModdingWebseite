class_name MinigamePregame
extends Control
## Pregame-Screen (Doc G §Pregame): Schwierigkeitswahl (Leicht/Normal/Schwer
## + Endlos, wo unterstützt UND freigeschaltet — §G5.5) und ORIENTIERUNGSWAHL
## (Auto/Hochkant/Quer). Die Orientierung wird PRO SPIEL in AppSettings
## unter "mg_orientation.<id>" gemerkt; die Schwierigkeitswahl landet im
## Save (minigames.difficulty.<id>, additiver v5-Key). PLAY reist zum Host.

signal play_requested(params: Dictionary)
signal back_requested

const DIFF_ORDER: Array[String] = ["easy", "normal", "hard", "endless"]
const ORIENT_ORDER: Array[String] = ["auto", "portrait", "landscape"]

## Tests: Navigation abschaltbar; State-Override wie beim Host.
var auto_navigate := true
var state_node: Node = null

var game_id := ""
var selected_difficulty := "normal"
var selected_orientation := "auto"

var _meta: Dictionary = {}
var _best_label: Label
var _diff_buttons: Dictionary = {}
var _orient_buttons: Dictionary = {}


func receive_params(params: Dictionary) -> void:
	game_id = str(params.get("game_id", ""))


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_meta = MinigameRegistry.get_game(game_id)
	if _meta.is_empty():
		push_warning("[mg_pregame] unbekanntes Spiel '%s'" % game_id)
		_go_back()
		return
	_load_selections()
	_build_ui()
	_refresh_buttons()


func _load_selections() -> void:
	var gs := _resolve_state()
	if gs != null:
		var slice := MinigameFrameworkLogic.difficulty_slice_of(gs.state(), game_id)
		selected_difficulty = str(slice["selected"])
	var settings := get_node_or_null("/root/AppSettings")
	if settings != null and settings.has_method("get_setting"):
		selected_orientation = str(settings.get_setting("mg_orientation.%s" % game_id, "auto"))
	if not ORIENT_ORDER.has(selected_orientation):
		selected_orientation = "auto"


func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.98, 0.94, 0.87)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	card.theme_type_variation = &"AcCardLg"
	card.custom_minimum_size = Vector2(520, 0)
	center.add_child(card)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	card.add_child(rows)

	var cover := TextureRect.new()
	cover.custom_minimum_size = Vector2(0, 180)
	cover.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	cover.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var cover_path := MinigameRegistry.cover_path(game_id)
	if ResourceLoader.exists(cover_path):
		cover.texture = load(cover_path)
	rows.add_child(cover)

	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = I18nService.t(str(_meta.get("title_key", game_id)))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(title)

	_best_label = Label.new()
	_best_label.theme_type_variation = &"CaptionLabel"
	_best_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_best_label)

	rows.add_child(_section_label(I18nService.t("mg.pregame.difficulty")))
	var diff_row := HBoxContainer.new()
	diff_row.alignment = BoxContainer.ALIGNMENT_CENTER
	diff_row.add_theme_constant_override("separation", 8)
	rows.add_child(diff_row)
	for mode in DIFF_ORDER:
		if mode == "endless" and not _endless_available():
			continue
		var btn := Button.new()
		btn.toggle_mode = true
		btn.theme_type_variation = &"AcChip"
		btn.text = I18nService.t("mg.diff.%s" % mode)
		btn.pressed.connect(_on_difficulty_pressed.bind(mode))
		diff_row.add_child(btn)
		_diff_buttons[mode] = btn

	rows.add_child(_section_label(I18nService.t("mg.pregame.orientation")))
	var orient_row := HBoxContainer.new()
	orient_row.alignment = BoxContainer.ALIGNMENT_CENTER
	orient_row.add_theme_constant_override("separation", 8)
	rows.add_child(orient_row)
	for orient in ORIENT_ORDER:
		var btn := Button.new()
		btn.toggle_mode = true
		btn.theme_type_variation = &"AcChip"
		btn.text = I18nService.t("mg.orient.%s" % orient)
		btn.pressed.connect(_on_orientation_pressed.bind(orient))
		orient_row.add_child(btn)
		_orient_buttons[orient] = btn

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	rows.add_child(buttons)
	var back := Button.new()
	back.theme_type_variation = &"GhostButton"
	back.text = I18nService.t("mg.pregame.back")
	back.pressed.connect(_go_back)
	buttons.add_child(back)
	var play := Button.new()
	play.theme_type_variation = &"PrimaryButton"
	play.text = I18nService.t("mg.pregame.play")
	play.pressed.connect(_on_play_pressed)
	buttons.add_child(play)


func _section_label(text: String) -> Label:
	var label := Label.new()
	label.theme_type_variation = &"SoftLabel"
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _endless_available() -> bool:
	if not _meta.get("supports_endless", false):
		return false
	var gs := _resolve_state()
	if gs == null:
		return false
	return MinigameFrameworkLogic.endless_unlocked(gs.state(), game_id)


func _refresh_buttons() -> void:
	if not _diff_buttons.has(selected_difficulty):
		selected_difficulty = "normal"
	for mode: String in _diff_buttons:
		(_diff_buttons[mode] as Button).button_pressed = mode == selected_difficulty
	for orient: String in _orient_buttons:
		(_orient_buttons[orient] as Button).button_pressed = orient == selected_orientation
	var gs := _resolve_state()
	var best := 0
	if gs != null:
		best = MinigameFrameworkLogic.best_for_mode(gs.state(), game_id, selected_difficulty)
	_best_label.text = I18nService.t("mg.pregame.best", {"best": best})


func _on_difficulty_pressed(mode: String) -> void:
	AudioDirector.try_play(self, "ui_chip")
	selected_difficulty = mode
	# Web-Muster: die Wahl easy/normal/hard wird im Save gemerkt (Endlos nicht).
	if mode != "endless":
		var gs := _resolve_state()
		if gs != null:
			var id := game_id
			gs.update(
				func(state: Dictionary) -> void:
					var mg: Dictionary = state["minigames"]
					if not (mg.get("difficulty") is Dictionary):
						mg["difficulty"] = {}
					mg["difficulty"][id] = mode
			)
	_refresh_buttons()


func _on_orientation_pressed(orient: String) -> void:
	AudioDirector.try_play(self, "ui_chip")
	selected_orientation = orient
	var settings := get_node_or_null("/root/AppSettings")
	if settings != null and settings.has_method("set_setting"):
		settings.set_setting("mg_orientation.%s" % game_id, orient)
	_refresh_buttons()


func _on_play_pressed() -> void:
	AudioDirector.try_play(self, "ui_confirm")
	var params := {
		"game_id": game_id,
		"difficulty": selected_difficulty,
		"orientation": selected_orientation,
	}
	play_requested.emit(params)
	if not auto_navigate:
		return
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("goto"):
		router.goto(&"mg_host", params)


func _go_back() -> void:
	AudioDirector.try_play(self, "ui_back")
	back_requested.emit()
	if not auto_navigate:
		return
	var router := get_node_or_null("/root/SceneRouter")
	if router != null and router.has_method("goto"):
		router.goto(&"arcade", {})


func _resolve_state() -> Node:
	if state_node != null:
		return state_node
	var gs := get_node_or_null("/root/GameState")
	if gs != null and gs.has_method("state") and gs.has_method("update"):
		return gs
	return null
