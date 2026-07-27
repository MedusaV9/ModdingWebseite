class_name DailyBonusPopup
extends Control
## Tagesbonus-Popup (REST-1): erscheint beim ersten Start des Tages über
## allem (RewardHub-Layer) — AC-Look-Karte mit Serien-Zeile, Kalender-
## Andeutung (7 Tages-Chips, gefüllt bis zum heutigen Serientag), Belohnungs-
## Zeile und Abholen/Später. Abholen claimt über die pure DailyBonus-Logik
## im EINEN gs.update() (Münzen via Economy.award); Später schließt nur —
## der Bonus bleibt bis Mitternacht abholbar. Kulanz-Hinweis erscheint,
## wenn der Kulanztag die Serie gerettet hat.
##
## Geometrie: ScreenShell-Metriken (UiScale + Safe-Area + Touch-Floor) —
## die Karte sitzt mittig in der SAFE-Area, nie unter Notch/Home-Indicator.
##
## Panel-Verhalten: meldet sich am PanelStack an — Backdrop-Tap und
## Escape/Back (SceneRouter → PanelStack.close_top) wirken wie „Später“,
## und sobald ein ANDERES Panel darüber aufgeht (z. B. das Status-Sheet),
## räumt das Popup selbst das Feld (der Bonus bleibt bis Mitternacht da).

signal claimed(reward: Dictionary)
signal dismissed

const CARD_BASE_WIDTH := 520.0
const CHIP_BASE := 44.0

## Tests/Screenshots: Notch-Simulation (Rect2() = aus).
var safe_area_override := Rect2()

var _gs: Object = null
var _card: PanelContainer
var _chips: Array[Control] = []
var _claim_btn: Button
var _later_btn: Button
var _next: Dictionary = {"streak": 1, "grace": false}


## Nur anbieten, wenn das Onboarding durch ist UND heute noch nichts
## abgeholt wurde (Web shouldOfferDailyBonus).
static func should_offer(gs: Object, day: String) -> bool:
	if gs == null or not bool(gs.get_value("onboarding.done", false)):
		return false
	var daily: Variant = gs.get_value("daily", {})
	return DailyBonus.is_claimable(daily if daily is Dictionary else {}, day)


## GameState anbinden (VOR add_child) — liest Serie + Belohnung für heute.
func setup(gs: Object) -> void:
	_gs = gs


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var daily: Variant = _gs.get_value("daily", {}) if _gs != null else {}
	_next = DailyBonus.next_streak(daily if daily is Dictionary else {}, _today())
	_build_ui()
	_relayout()
	get_viewport().size_changed.connect(_relayout)
	# Autowrap-Nachmessung (Kulanz-Label): beim ersten Pass kennt das Label
	# seine Breite noch nicht und meldet eine zu hohe Mindesthöhe — sobald
	# der Container die echte Breite zuteilt, schrumpft die Mindestgröße und
	# die Karte zentriert sich neu. Deferred, nie während des Layout-Laufs.
	_card.minimum_size_changed.connect(_relayout, CONNECT_DEFERRED)
	PanelStack.push(self)
	AudioDirector.try_play(self, "ui_open")


func _exit_tree() -> void:
	PanelStack.remove(self)


## Ein Panel ist ÜBER uns aufgegangen (Status-Sheet, Sheets vom HUD) →
## „Später“, das Popup drängelt nie über anderen Blättern.
func _process(_delta: float) -> void:
	if not PanelStack.is_top(self):
		_on_later()


## Escape/Back-Pfad (SceneRouter → PanelStack.close_top) — wie „Später“.
func close() -> void:
	_on_later()


func _build_ui() -> void:
	var veil := ColorRect.new()
	veil.name = "Veil"
	veil.color = AcTokens.VEIL
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.gui_input.connect(_on_veil_input)
	add_child(veil)

	_card = PanelContainer.new()
	_card.name = "BonusCard"
	_card.theme_type_variation = &"AcCardLg"
	add_child(_card)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_card.add_child(box)

	var title := Label.new()
	title.name = "BonusTitle"
	title.theme_type_variation = &"TitleLabel"
	title.text = I18nService.t("daily.titel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var serie := Label.new()
	serie.name = "SerieLabel"
	serie.theme_type_variation = &"SoftLabel"
	serie.text = I18nService.t("daily.serie", {"tag": int(_next["streak"])})
	serie.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(serie)

	box.add_child(_build_calendar())

	var reward := DailyBonus.reward_for_streak(int(_next["streak"]))
	var reward_label := Label.new()
	reward_label.name = "RewardLabel"
	reward_label.theme_type_variation = &"HeadlineLabel"
	reward_label.add_theme_color_override("font_color", AcTokens.YELLOW_DARK)
	var reward_text := I18nService.t("daily.belohnung", {"coins": int(reward["coins"])})
	if bool(reward["includes_food"]):
		reward_text += "  %s" % I18nService.t("daily.snack")
	reward_label.text = reward_text
	reward_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(reward_label)

	if bool(_next["grace"]):
		var grace := Label.new()
		grace.name = "GraceLabel"
		grace.theme_type_variation = &"SoftLabel"
		grace.text = I18nService.t("daily.kulanz")
		grace.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grace.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		box.add_child(grace)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	_later_btn = SquishButton.new()
	_later_btn.name = "LaterBtn"
	_later_btn.theme_type_variation = &"BtnGhost"
	_later_btn.text = I18nService.t("daily.spaeter")
	_later_btn.focus_mode = Control.FOCUS_NONE
	_later_btn.pressed.connect(_on_later)
	buttons.add_child(_later_btn)
	_claim_btn = SquishButton.new()
	_claim_btn.name = "ClaimBtn"
	_claim_btn.theme_type_variation = &"BtnLeaf"
	_claim_btn.text = I18nService.t("daily.abholen")
	_claim_btn.focus_mode = Control.FOCUS_NONE
	_claim_btn.pressed.connect(_on_claim)
	buttons.add_child(_claim_btn)


## Kalender-Andeutung: 7 Tages-Chips — gefüllt bis gestern, Gold-Ring auf
## dem heutigen Serientag (ab Tag 7 bleibt der Ring auf Chip 7).
func _build_calendar() -> Control:
	var row := HBoxContainer.new()
	row.name = "CalendarRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 8)
	_chips.clear()
	var today := mini(int(_next["streak"]), DailyBonus.REWARD_TABLE.size())
	for i in DailyBonus.REWARD_TABLE.size():
		var day_num := i + 1
		var chip := PanelContainer.new()
		chip.name = "DayChip%d" % day_num
		var style := StyleBoxFlat.new()
		style.set_corner_radius_all(AcTokens.RADIUS_ROW)
		style.set_content_margin_all(6.0)
		if day_num < today:
			style.bg_color = AcTokens.LEAF
		elif day_num == today:
			style.bg_color = AcTokens.GOLD
			style.border_color = AcTokens.YELLOW_DARK
			style.set_border_width_all(3)
		else:
			style.bg_color = AcTokens.PAPER_SHADE
		chip.add_theme_stylebox_override("panel", style)
		var label := Label.new()
		label.text = str(day_num)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		if day_num <= today:
			label.add_theme_color_override("font_color", AcTokens.WHITE)
		else:
			label.add_theme_color_override("font_color", AcTokens.INK_FAINT)
		chip.add_child(label)
		row.add_child(chip)
		_chips.append(chip)
	return row


func _relayout() -> void:
	if not is_inside_tree() or _card == null:
		return
	var m := ScreenShell.metrics(get_viewport(), safe_area_override)
	var f: float = m["f"]
	ScreenShell.scale_fonts(self, f)
	ScreenShell.touch_target(_claim_btn, m)
	ScreenShell.touch_target(_later_btn, m)
	var chip_side := maxf(CHIP_BASE * f, float(m["floor_px"]) * 0.72)
	for chip in _chips:
		chip.custom_minimum_size = Vector2(chip_side, chip_side)
	var width := ScreenShell.card_width(m, CARD_BASE_WIDTH)
	_card.custom_minimum_size = Vector2(width, 0.0)
	var wanted := _card.get_combined_minimum_size()
	var height := minf(wanted.y, ScreenShell.card_max_height(m))
	var insets: Dictionary = m["insets"]
	var canvas: Vector2 = m["canvas"]
	var safe := Rect2(
		Vector2(float(insets["left"]), float(insets["top"])),
		Vector2(
			canvas.x - float(insets["left"]) - float(insets["right"]),
			canvas.y - float(insets["top"]) - float(insets["bottom"])
		)
	)
	var pos := safe.position + (safe.size - Vector2(width, height)) / 2.0
	_card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_card.offset_left = pos.x
	_card.offset_top = pos.y
	_card.offset_right = pos.x + width
	_card.offset_bottom = pos.y + height


func _on_claim() -> void:
	if _gs == null:
		queue_free()
		return
	var result := {"ok": false}
	var day := _today()
	_gs.update(
		func(state: Dictionary) -> void:
			var r := DailyBonus.claim(state, day)
			result.merge(r, true)
	)
	if bool(result.get("ok", false)):
		_gs.notify_slice_changed("daily")
		AudioDirector.try_play(self, "ui_coins")
		claimed.emit(result)
	set_process(false)
	queue_free()


func _on_later() -> void:
	AudioDirector.try_play(self, "ui_close")
	dismissed.emit()
	set_process(false)
	queue_free()


## Backdrop-Dismiss-Policy (Web): Tap auf den Schleier = „Später“, aber nur
## als oberstes Panel.
func _on_veil_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton or event is InputEventScreenTouch):
		return
	if event is InputEventMouseButton and not (event as InputEventMouseButton).pressed:
		return
	if event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed:
		return
	if PanelStack.is_top(self):
		_on_later()


func _today() -> String:
	if _gs != null and "clock" in _gs:
		return str(_gs.clock.local_day())
	var d := Time.get_datetime_dict_from_system()
	return "%04d-%02d-%02d" % [d.year, d.month, d.day]
