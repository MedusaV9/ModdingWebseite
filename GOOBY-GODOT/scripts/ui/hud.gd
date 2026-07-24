class_name Hud
extends Control
## Haupt-HUD mit BEIDEN Layouts aus Doc H §1.3:
## - Hochkant P1 „Daumen-Bogen“: Status-Chips oben, Aktions-Bogen unten rechts.
## - Querformat L1 „Cockpit“: Stats links vertikal, Button-Spalte rechts.
## Wechselt LIVE bei Rotation (hört auf `Viewport.size_changed` — lose
## Kopplung, bis der OrientationService von W1a verdrahtet ist).
##
## Keine eigene Spiel-Logik: Anzeigedaten kommen über `set_stats()`,
## `set_coins()`, `set_level()` (W1d-GameState verdrahtet das später,
## siehe handoffs/W1c-needs-from-state.md).

## Ein Haupt-Button wurde gedrückt (reise/arcade/bau/album/profil/igohbie).
signal action_pressed(action: StringName)
## Interaktions-Auge an/aus (schaltet sich nach 8 s selbst aus).
signal eye_toggled(active: bool)
signal settings_pressed
signal where_is_gooby_pressed

const ICON_DIR := "res://assets/ui/icons/"
const EYE_AUTO_OFF_SEC := 8.0
## Reihenfolge = Bogen von links (flach) nach oben; Spalte nutzt eigene Liste.
const ACTIONS: Array[Dictionary] = [
	{"id": &"igohbie", "icon": "phone"},
	{"id": &"bau", "icon": "wrench"},
	{"id": &"reise", "icon": "suitcase"},
	{"id": &"arcade", "icon": "gamepad"},
	{"id": &"album", "icon": "book"},
	{"id": &"profil", "icon": "rabbit"},
]
const COLUMN_ORDER: Array[StringName] = [
	&"bau", &"reise", &"arcade", &"album", &"profil", &"igohbie"
]
const STATS := [
	{"id": "hunger", "icon": "hunger", "type": "StatHunger"},
	{"id": "energie", "icon": "energy", "type": "StatEnergy"},
	{"id": "hygiene", "icon": "hygiene", "type": "StatHygiene"},
	{"id": "spass", "icon": "fun", "type": "StatFun"},
]

var current_layout: HudLayoutLogic.Layout = HudLayoutLogic.Layout.PORTRAIT

var _buttons: Dictionary = {}
var _stat_bars: Dictionary = {}
var _stat_icons: Dictionary = {}
var _level_label: Label
var _coin_label: Label
var _eye_timer: Timer

@onready var _status_row: HBoxContainer = %StatusRow
@onready var _left_column: VBoxContainer = %LeftColumn
@onready var _portrait_arc: ArcContainer = %PortraitArc
@onready var _landscape_column: VBoxContainer = %LandscapeColumn
@onready var _settings_button: Button = %SettingsButton
@onready var _eye_button: Button = %EyeButton
@onready var _gooby_chip: Button = %WhereIsGoobyChip


func _ready() -> void:
	_build_action_buttons()
	_build_status_chips()
	_setup_static_buttons()
	_eye_timer = Timer.new()
	_eye_timer.one_shot = true
	_eye_timer.timeout.connect(_on_eye_timeout)
	add_child(_eye_timer)
	get_viewport().size_changed.connect(_on_viewport_resized)
	_on_viewport_resized()


## Layout hart setzen (Rotation macht das automatisch; Tests rufen es direkt).
func apply_layout(layout: HudLayoutLogic.Layout) -> void:
	current_layout = layout
	var portrait := layout == HudLayoutLogic.Layout.PORTRAIT
	_portrait_arc.visible = portrait
	_landscape_column.visible = not portrait
	_left_column.visible = not portrait
	_status_row.visible = portrait
	var button_parent: Container = _portrait_arc if portrait else _landscape_column
	var order: Array = []
	if portrait:
		for action in ACTIONS:
			order.append(action["id"])
	else:
		order = COLUMN_ORDER.duplicate()
	for id: StringName in order:
		var btn: Button = _buttons[id]
		if btn.get_parent() != button_parent:
			if btn.get_parent() != null:
				btn.get_parent().remove_child(btn)
			button_parent.add_child(btn)
		else:
			button_parent.move_child(btn, order.find(id))
	var chip_parent: Container = _status_row if portrait else _left_column
	for chip in _chips():
		if chip.get_parent() != chip_parent:
			if chip.get_parent() != null:
				chip.get_parent().remove_child(chip)
			chip_parent.add_child(chip)
		# Hochkant = Mini-Kapseln (H §1.3: Glance-Info, Details per Tap-Sheet).
		chip.theme_type_variation = &"StatusCapsuleMini" if portrait else &"StatusCapsule"
	for info in STATS:
		var bar: ProgressBar = _stat_bars[info["id"]]
		bar.custom_minimum_size = Vector2(34.0 if portrait else 132.0, 12.0)
		(_stat_icons[info["id"]] as Control).visible = not portrait
	_place_eye_button(portrait)


## {"hunger":0..100, "energie":.., "hygiene":.., "spass":..}
func set_stats(stats: Dictionary) -> void:
	for key: String in stats:
		if _stat_bars.has(key):
			(_stat_bars[key] as ProgressBar).value = float(stats[key])


func set_coins(coins: int) -> void:
	_coin_label.text = str(coins)


func set_level(level: int, _xp_ratio: float = 0.0) -> void:
	_level_label.text = I18nService.t("hud.level_pill", {"level": level})


func is_eye_active() -> bool:
	return _eye_button.button_pressed


func _chips() -> Array[Control]:
	var result: Array[Control] = []
	result.append(_level_label.get_parent() as Control)
	for info in STATS:
		result.append((_stat_bars[info["id"]] as Control).get_parent().get_parent())
	result.append(_coin_label.get_parent().get_parent() as Control)
	return result


func _build_action_buttons() -> void:
	for action in ACTIONS:
		var id: StringName = action["id"]
		var btn := SquishButton.new()
		btn.name = "Btn" + String(id).capitalize()
		btn.theme_type_variation = "HudIconButton"
		btn.icon = load("%s%s.svg" % [ICON_DIR, action["icon"]])
		btn.custom_minimum_size = Vector2(72, 72)
		btn.tooltip_text = I18nService.t("hud." + String(id))
		btn.expand_icon = false
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(_on_action_pressed.bind(id))
		_buttons[id] = btn
		_portrait_arc.add_child(btn)


func _build_status_chips() -> void:
	var level_chip := _make_chip("LevelChip")
	_level_label = Label.new()
	_level_label.name = "LevelValue"
	_level_label.theme_type_variation = "SoftLabel"
	level_chip.add_child(_level_label)
	_status_row.add_child(level_chip)
	for info in STATS:
		var chip := _make_chip("StatChip" + String(info["id"]).capitalize())
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		var icon := TextureRect.new()
		icon.texture = load("%s%s.svg" % [ICON_DIR, info["icon"]])
		icon.custom_minimum_size = Vector2(18, 18)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.self_modulate = AcTokens.INK_SOFT
		box.add_child(icon)
		_stat_icons[info["id"]] = icon
		var bar := ProgressBar.new()
		bar.name = "Bar"
		bar.theme_type_variation = info["type"]
		bar.custom_minimum_size = Vector2(56, 12)
		bar.show_percentage = false
		bar.max_value = 100.0
		bar.value = 100.0
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		bar.tooltip_text = I18nService.t("hud.stat_" + String(info["id"]))
		box.add_child(bar)
		chip.add_child(box)
		_stat_bars[info["id"]] = bar
		_status_row.add_child(chip)
	var coin_chip := _make_chip("CoinChip")
	var coin_box := HBoxContainer.new()
	coin_box.add_theme_constant_override("separation", 6)
	var coin_icon := TextureRect.new()
	coin_icon.texture = load("res://assets/ui/coin.png")
	coin_icon.custom_minimum_size = Vector2(22, 22)
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_box.add_child(coin_icon)
	_coin_label = Label.new()
	_coin_label.name = "CoinValue"
	coin_box.add_child(_coin_label)
	coin_chip.add_child(coin_box)
	_status_row.add_child(coin_chip)
	set_level(1)
	set_coins(0)


func _make_chip(chip_name: String) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.name = chip_name
	chip.theme_type_variation = "StatusCapsule"
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	return chip


func _setup_static_buttons() -> void:
	_settings_button.icon = load(ICON_DIR + "gear.svg")
	_settings_button.tooltip_text = I18nService.t("hud.einstellungen")
	_settings_button.pressed.connect(func() -> void: settings_pressed.emit())
	_eye_button.icon = load(ICON_DIR + "eye.svg")
	_eye_button.tooltip_text = I18nService.t("hud.auge")
	_eye_button.toggled.connect(_on_eye_toggled)
	_gooby_chip.text = I18nService.t("hud.wo_ist_gooby")
	_gooby_chip.pressed.connect(func() -> void: where_is_gooby_pressed.emit())


func _place_eye_button(portrait: bool) -> void:
	var vp := Vector2(get_viewport().get_visible_rect().size)
	_eye_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	if portrait:
		# Überm Bogen an der rechten Kante (Daumenzone); der oberste
		# Bogen-Button reicht mit Stagger bis ~y-300, also drüber bleiben.
		_eye_button.position = Vector2(vp.x - 72.0 - 16.0, vp.y - 388.0)
	else:
		# Links neben der Button-Spalte, unten (Cockpit).
		_eye_button.position = Vector2(vp.x - 96.0 - 72.0 - 12.0, vp.y - 72.0 - 16.0)


func _on_viewport_resized() -> void:
	var vp_size := Vector2(get_viewport().get_visible_rect().size)
	apply_layout(HudLayoutLogic.pick_layout(vp_size))


func _on_action_pressed(id: StringName) -> void:
	action_pressed.emit(id)


func _on_eye_toggled(active: bool) -> void:
	eye_toggled.emit(active)
	if active:
		_eye_timer.start(EYE_AUTO_OFF_SEC)
	else:
		_eye_timer.stop()


func _on_eye_timeout() -> void:
	if _eye_button.button_pressed:
		_eye_button.set_pressed_no_signal(false)
		eye_toggled.emit(false)
