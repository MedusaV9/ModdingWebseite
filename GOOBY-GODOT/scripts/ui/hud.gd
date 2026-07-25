class_name Hud
extends Control
## Haupt-HUD mit BEIDEN Layouts aus Doc H §1.3:
## - Hochkant P1 „Daumen-Bogen“: Status-Chips oben, Aktions-Bogen unten rechts.
## - Querformat L1 „Cockpit“: Stats links vertikal, Button-Spalte rechts.
## Wechselt LIVE bei Rotation (hört auf `Viewport.size_changed` — lose
## Kopplung, bis der OrientationService von W1a verdrahtet ist).
##
## W4/POLISH-4-Feinschliff: Status-Kapsel-Tap öffnet das Stat-Detail-Sheet
## (`hud_status_sheet.gd`), Level-Ring (`hud_progress_ring.gd`) statt
## Text-Pill, Badge-Pulse bei Stat < 25, Safe-Area-Insets (Notch/Home-
## Indicator, `HudLayoutLogic.safe_insets`) und Coins-Zähl-Animation.
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

const SHEET_SCENE := preload("res://scripts/ui/panel_sheet.tscn")
const ICON_DIR := "res://assets/ui/icons/"
const EYE_AUTO_OFF_SEC := 8.0
## Unter diesem Wert pulsiert die Status-Kapsel (Doc H „Pflege-Alarm“).
const STAT_ALERT_THRESHOLD := 25.0
const COIN_TWEEN_SEC := 0.45
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
## Notch-Simulation für Tests: Safe-Area in CANVAS-Koordinaten
## (Rect2() = aus, dann fragt das HUD den DisplayServer).
var safe_area_override := Rect2()

var _buttons: Dictionary = {}
var _stat_bars: Dictionary = {}
var _stat_icons: Dictionary = {}
var _stat_chips: Dictionary = {}
var _chip_nodes: Array[Control] = []
var _alert_tweens: Dictionary = {}
var _last_stats: Dictionary = {}
var _level_label: Label
var _level_ring: HudProgressRing
var _coin_label: Label
var _coin_chip: Control
var _coin_tween: Tween
var _coin_shown := 0
var _status_sheet: PanelSheet
var _eye_timer: Timer

@onready var _top_bar: MarginContainer = $TopBar
@onready var _status_row: HBoxContainer = %StatusRow
@onready var _left_column: VBoxContainer = %LeftColumn
@onready var _bottom_left: VBoxContainer = $BottomLeft
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
	for chip in _chip_nodes:
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
	refresh_safe_area()


## Safe-Area-Insets neu anwenden (Rotation/Resize macht das automatisch;
## Tests setzen `safe_area_override` und rufen es direkt).
func refresh_safe_area() -> void:
	var insets := _safe_insets()
	var left := float(insets["left"])
	var top := float(insets["top"])
	var right := float(insets["right"])
	var bottom := float(insets["bottom"])
	_top_bar.add_theme_constant_override("margin_left", int(16.0 + left))
	_top_bar.add_theme_constant_override("margin_top", int(12.0 + top))
	_top_bar.add_theme_constant_override("margin_right", int(16.0 + right))
	_left_column.offset_left = 16.0 + left
	_bottom_left.offset_left = 16.0 + left
	_bottom_left.offset_bottom = -16.0 - bottom
	_landscape_column.offset_right = -16.0 - right
	_portrait_arc.offset_right = -8.0 - right
	_portrait_arc.offset_bottom = -8.0 - bottom
	_place_eye_button(current_layout == HudLayoutLogic.Layout.PORTRAIT, right, bottom)


## {"hunger":0..100, "energie":.., "hygiene":.., "spass":..}
func set_stats(stats: Dictionary) -> void:
	for key: String in stats:
		if _stat_bars.has(key):
			var value := float(stats[key])
			(_stat_bars[key] as ProgressBar).value = value
			_last_stats[key] = value
	_update_stat_alerts()
	if _status_sheet != null and _status_sheet.is_open():
		_fill_status_sheet()


func set_coins(coins: int) -> void:
	if _coin_tween != null and _coin_tween.is_valid():
		_coin_tween.kill()
	if _coin_shown == coins or not is_inside_tree() or ThemeService.is_reduced_motion(self):
		_coin_shown = coins
		_coin_label.text = str(coins)
		return
	# Zähl-Animation + kleiner Chip-Pop (W4/POLISH-4).
	_coin_tween = create_tween()
	(
		_coin_tween
		. tween_method(_show_coin_value, float(_coin_shown), float(coins), COIN_TWEEN_SEC)
		. set_trans(Tween.TRANS_QUAD)
		. set_ease(Tween.EASE_OUT)
	)
	_coin_chip.pivot_offset = _coin_chip.size / 2.0
	_coin_chip.scale = Vector2.ONE * 1.1
	(
		_coin_tween
		. parallel()
		. tween_property(_coin_chip, "scale", Vector2.ONE, COIN_TWEEN_SEC)
		. set_trans(Tween.TRANS_BACK)
		. set_ease(Tween.EASE_OUT)
	)
	_coin_shown = coins


func set_level(level: int, xp_ratio: float = 0.0) -> void:
	_level_label.text = str(level)
	_level_ring.ratio = xp_ratio
	(_level_ring.get_parent() as Control).tooltip_text = I18nService.t(
		"hud.level_pill", {"level": level}
	)


func is_eye_active() -> bool:
	return _eye_button.button_pressed


## Stat-Detail-Sheet (Tap auf eine Status-Kapsel): 4 Stats groß mit
## Icons + Balken + Buff-Anzeige (`hud_status_sheet.gd`).
func open_status_sheet() -> void:
	if _status_sheet == null:
		_status_sheet = SHEET_SCENE.instantiate()
		add_child(_status_sheet)
	_fill_status_sheet()
	_status_sheet.open()


## Pulsiert die Kapsel dieser Stat gerade? (Badge-Pulse bei Wert < 25.)
func is_stat_alerting(stat_id: String) -> bool:
	return _alert_tweens.has(stat_id)


func _fill_status_sheet() -> void:
	_status_sheet.set_title(HudStatusSheet.title_text())
	var gs := get_node_or_null("/root/GameState")
	var now_ms := int(Time.get_unix_time_from_system() * 1000.0)
	var boni := HudStatusSheet.stat_boni(gs, now_ms)
	_status_sheet.add_content(HudStatusSheet.build_content(_last_stats, boni))


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
	_level_ring = HudProgressRing.new()
	_level_ring.name = "LevelRing"
	_level_ring.custom_minimum_size = Vector2(34, 34)
	_level_label = Label.new()
	_level_label.name = "LevelValue"
	_level_label.theme_type_variation = "CaptionLabel"
	_level_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_level_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_level_ring.add_child(_level_label)
	level_chip.add_child(_level_ring)
	_status_row.add_child(level_chip)
	for info in STATS:
		var chip := _make_chip("StatChip" + String(info["id"]).capitalize())
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		box.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon := TextureRect.new()
		icon.texture = load("%s%s.svg" % [ICON_DIR, info["icon"]])
		icon.custom_minimum_size = Vector2(18, 18)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.self_modulate = AcTokens.INK_SOFT
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
		bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(bar)
		chip.add_child(box)
		_stat_bars[info["id"]] = bar
		_stat_chips[info["id"]] = chip
		_status_row.add_child(chip)
	var coin_chip := _make_chip("CoinChip")
	var coin_box := HBoxContainer.new()
	coin_box.add_theme_constant_override("separation", 6)
	coin_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var coin_icon := TextureRect.new()
	coin_icon.texture = load("res://assets/ui/coin.png")
	coin_icon.custom_minimum_size = Vector2(22, 22)
	coin_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin_box.add_child(coin_icon)
	_coin_label = Label.new()
	_coin_label.name = "CoinValue"
	_coin_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	coin_box.add_child(_coin_label)
	coin_chip.add_child(coin_box)
	_coin_chip = coin_chip
	_status_row.add_child(coin_chip)
	_chip_nodes = [level_chip]
	for info in STATS:
		_chip_nodes.append(_stat_chips[info["id"]] as Control)
	_chip_nodes.append(coin_chip)
	set_level(1)
	set_coins(0)


func _make_chip(chip_name: String) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.name = chip_name
	chip.theme_type_variation = "StatusCapsule"
	chip.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	chip.mouse_filter = Control.MOUSE_FILTER_PASS
	chip.gui_input.connect(_on_chip_input)
	return chip


func _setup_static_buttons() -> void:
	_settings_button.icon = load(ICON_DIR + "gear.svg")
	_settings_button.tooltip_text = I18nService.t("hud.einstellungen")
	_settings_button.pressed.connect(_on_settings_pressed)
	_eye_button.icon = load(ICON_DIR + "eye.svg")
	_eye_button.tooltip_text = I18nService.t("hud.auge")
	_eye_button.toggled.connect(_on_eye_toggled)
	_gooby_chip.text = I18nService.t("hud.wo_ist_gooby")
	_gooby_chip.pressed.connect(_on_gooby_chip_pressed)


func _place_eye_button(portrait: bool, inset_right := 0.0, inset_bottom := 0.0) -> void:
	var vp := Vector2(get_viewport().get_visible_rect().size)
	_eye_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	if portrait:
		# Überm Bogen an der rechten Kante (Daumenzone); der oberste
		# Bogen-Button reicht mit Stagger bis ~y-300, also drüber bleiben.
		_eye_button.position = Vector2(
			vp.x - 72.0 - 16.0 - inset_right, vp.y - 388.0 - inset_bottom
		)
	else:
		# Links neben der Button-Spalte, unten (Cockpit).
		_eye_button.position = Vector2(
			vp.x - 96.0 - 72.0 - 12.0 - inset_right, vp.y - 72.0 - 16.0 - inset_bottom
		)


## Insets in Canvas-Koordinaten: Override (Tests/Notch-Simulation) >
## DisplayServer-Safe-Area (auf Canvas skaliert) > 0 (Desktop/Headless).
func _safe_insets() -> Dictionary:
	var canvas := Vector2(get_viewport().get_visible_rect().size)
	if safe_area_override != Rect2():
		return HudLayoutLogic.safe_insets(canvas, safe_area_override)
	if DisplayServer.get_name() == "headless":
		return HudLayoutLogic.safe_insets(canvas, Rect2(Vector2.ZERO, canvas))
	var win_size := Vector2(DisplayServer.window_get_size())
	var win_pos := Vector2(DisplayServer.window_get_position())
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var local := Rect2(safe.position - win_pos, safe.size).intersection(
		Rect2(Vector2.ZERO, win_size)
	)
	var raw := HudLayoutLogic.safe_insets(win_size, local)
	if win_size.x <= 0.0 or win_size.y <= 0.0:
		return raw
	var fx := canvas.x / win_size.x
	var fy := canvas.y / win_size.y
	return {
		"left": float(raw["left"]) * fx,
		"top": float(raw["top"]) * fy,
		"right": float(raw["right"]) * fx,
		"bottom": float(raw["bottom"]) * fy,
	}


func _update_stat_alerts() -> void:
	for info in STATS:
		var id := String(info["id"])
		var alerting := float(_last_stats.get(id, 100.0)) < STAT_ALERT_THRESHOLD
		if alerting == _alert_tweens.has(id):
			continue
		var chip := _stat_chips[id] as Control
		if alerting:
			_start_alert_pulse(id, chip)
		else:
			_stop_alert_pulse(id, chip)


func _start_alert_pulse(id: String, chip: Control) -> void:
	if ThemeService.is_reduced_motion(self):
		# Statischer Alarm-Tint statt Puls (Reduced Motion).
		chip.modulate = Color(1.0, 0.82, 0.82)
		_alert_tweens[id] = null
		return
	chip.pivot_offset = chip.size / 2.0
	var tween := create_tween().set_loops()
	tween.tween_property(chip, "scale", Vector2.ONE * 1.07, 0.42)
	tween.parallel().tween_property(chip, "modulate", Color(1.0, 0.8, 0.8), 0.42)
	tween.tween_property(chip, "scale", Vector2.ONE, 0.42)
	tween.parallel().tween_property(chip, "modulate", Color.WHITE, 0.42)
	_alert_tweens[id] = tween


func _stop_alert_pulse(id: String, chip: Control) -> void:
	var tween: Variant = _alert_tweens[id]
	if tween is Tween and (tween as Tween).is_valid():
		(tween as Tween).kill()
	_alert_tweens.erase(id)
	chip.scale = Vector2.ONE
	chip.modulate = Color.WHITE


func _show_coin_value(value: float) -> void:
	_coin_label.text = str(int(roundf(value)))


func _on_chip_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if mouse.pressed and mouse.button_index == MOUSE_BUTTON_LEFT:
		open_status_sheet()


func _on_viewport_resized() -> void:
	var vp_size := Vector2(get_viewport().get_visible_rect().size)
	apply_layout(HudLayoutLogic.pick_layout(vp_size))


func _on_action_pressed(id: StringName) -> void:
	AudioDirector.try_play(self, "ui_click")
	action_pressed.emit(id)


func _on_settings_pressed() -> void:
	AudioDirector.try_play(self, "ui_click")
	settings_pressed.emit()


func _on_gooby_chip_pressed() -> void:
	AudioDirector.try_play(self, "ui_chip")
	where_is_gooby_pressed.emit()


func _on_eye_toggled(active: bool) -> void:
	AudioDirector.try_play(self, "ui_toggle")
	eye_toggled.emit(active)
	if active:
		_eye_timer.start(EYE_AUTO_OFF_SEC)
	else:
		_eye_timer.stop()


func _on_eye_timeout() -> void:
	if _eye_button.button_pressed:
		_eye_button.set_pressed_no_signal(false)
		eye_toggled.emit(false)
