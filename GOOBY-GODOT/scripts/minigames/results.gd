class_name MinigameResults
extends Control
## Results-Screen des Minigame-Hosts: Score, Coins (inkl. Tagesbonus-×2-Chip,
## Tageslimit-Hinweis), Bestwert/Neuer-Rekord, XP/Level-Ups. Buttons feuern
## nur Signale — Navigation gehört dem Host (again → Neustart, back → Arcade).

signal again_pressed
signal back_pressed

var _panel: PanelContainer
var _rows: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.24, 0.16, 0.12, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"AcCardLg"
	_panel.custom_minimum_size = Vector2(420, 0)
	center.add_child(_panel)
	_rows = VBoxContainer.new()
	_rows.add_theme_constant_override("separation", 10)
	_panel.add_child(_rows)


## breakdown = MinigameAward.award()-Ergebnis; meta = Registry-Zeile.
func show_results(breakdown: Dictionary, meta: Dictionary) -> void:
	for child in _rows.get_children():
		child.queue_free()
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = I18nService.t("mg.results.title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rows.add_child(title)
	var game_name := Label.new()
	game_name.theme_type_variation = &"CaptionLabel"
	game_name.text = I18nService.t(str(meta.get("title_key", "mg.results.title")))
	game_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rows.add_child(game_name)
	var score := Label.new()
	score.theme_type_variation = &"HeadlineLabel"
	score.text = I18nService.t("mg.results.score", {"score": int(breakdown.get("score", 0))})
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rows.add_child(score)
	if breakdown.get("newBest", false):
		_add_line(I18nService.t("mg.results.new_best"), Color(1.0, 0.62, 0.16))
	else:
		_add_line(
			I18nService.t("mg.results.best", {"best": int(breakdown.get("best", 0))}),
			Color(0.55, 0.42, 0.35)
		)
	var coins_text := I18nService.t("mg.results.coins", {"coins": int(breakdown.get("coins", 0))})
	if breakdown.get("firstToday", false):
		coins_text += "  " + I18nService.t("mg.results.daily_bonus")
	_add_line(coins_text, Color(0.93, 0.61, 0.15))
	if breakdown.get("dayCapReached", false):
		_add_line(I18nService.t("mg.results.day_cap"), Color(0.72, 0.5, 0.42))
	_add_line(
		I18nService.t("mg.results.xp", {"xp": int(breakdown.get("xp", 0))}), Color(0.42, 0.6, 0.36)
	)
	if int(breakdown.get("levelsGained", 0)) > 0:
		_add_line(
			I18nService.t(
				"mg.results.level_up", {"coins": int(breakdown.get("coinsFromLevels", 0))}
			),
			Color(0.95, 0.45, 0.66)
		)
	if breakdown.get("beatTarget", false):
		_add_line(I18nService.t("mg.results.beat_target"), Color(0.42, 0.6, 0.36))
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 14)
	_rows.add_child(buttons)
	var again := Button.new()
	again.theme_type_variation = &"PrimaryButton"
	again.text = I18nService.t("mg.results.again")
	again.pressed.connect(func() -> void: again_pressed.emit())
	buttons.add_child(again)
	var back := Button.new()
	back.theme_type_variation = &"GhostButton"
	back.text = I18nService.t("mg.results.back")
	back.pressed.connect(func() -> void: back_pressed.emit())
	buttons.add_child(back)
	show()


func _add_line(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", color)
	_rows.add_child(label)
