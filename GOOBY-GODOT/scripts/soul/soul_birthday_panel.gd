class_name SoulBirthdayPanel
extends Control
## G4/P23 — Geburtstags-Abfrage als AcCard-Overlay (Muster daily_bonus_popup):
## Vollbild-Veil + mittig zentrierte AcCard mit großen −/+‑Steppern statt der
## auf Touch unbrauchbaren SpinBox-Pfeile. PanelStack-Anmeldung (Back/Escape
## über close(), Backdrop-Tap nur als oberstes Panel — beides „Abbrechen“),
## Kartenbreite/Touch-Floor/Schriften über ScreenShell-Metriken, Relayout bei
## Rotation. Persistenz + Dank-Line + Schließ-Sounds bleiben beim Besitzer
## (gooby_reactions._open_birthday_panel) — hier lebt NUR die Panel-UI.

signal gespeichert(month: int, day: int)
signal abgebrochen

const CARD_BASE_WIDTH := 380.0

var _werte := {"month": 1, "day": 1}
var _karte: PanelContainer


func _init() -> void:
	name = "SoulBirthdayPanel"
	theme = ThemeService.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var veil := ColorRect.new()
	veil.name = "Veil"
	veil.color = AcTokens.VEIL
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.gui_input.connect(_on_veil_input)
	add_child(veil)
	var center := CenterContainer.new()
	center.name = "Mitte"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	_karte = PanelContainer.new()
	_karte.name = "BirthdayKarte"
	_karte.theme_type_variation = "AcCard"
	center.add_child(_karte)
	_build_card()


func _ready() -> void:
	PanelStack.push(self)
	_relayout()
	get_viewport().size_changed.connect(_relayout)


func _exit_tree() -> void:
	PanelStack.remove(self)


## Escape/Back-Pfad (SceneRouter → PanelStack.close_top) = Abbrechen.
func close() -> void:
	abgebrochen.emit()


func _build_card() -> void:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_karte.add_child(box)
	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.text = I18nService.t("soul.geburtstag_panel.titel")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 14)
	box.add_child(row)
	_stepper(row, "soul.geburtstag_panel.monat", "month", 12)
	_stepper(row, "soul.geburtstag_panel.tag", "day", 31)
	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 12)
	box.add_child(buttons)
	var cancel := _button("BirthdayCancel", "GhostButton")
	cancel.text = I18nService.t("soul.geburtstag_panel.abbrechen")
	cancel.pressed.connect(_on_cancel)
	buttons.add_child(cancel)
	var save := _button("BirthdaySave", "BtnLeaf")
	save.text = I18nService.t("soul.geburtstag_panel.speichern")
	save.pressed.connect(_on_save)
	buttons.add_child(save)


## Ein Stepper-Feld (Caption + − Wert +): Touch-taugliche Schritte mit
## Umlauf (1 → Max bzw. Max → 1), Mikro-Schritt klingt als ui_tick.
func _stepper(row: HBoxContainer, label_key: String, feld: String, max_wert: int) -> void:
	var spalte := VBoxContainer.new()
	spalte.add_theme_constant_override("separation", 4)
	row.add_child(spalte)
	var caption := Label.new()
	caption.theme_type_variation = &"CaptionLabel"
	caption.text = I18nService.t(label_key)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	spalte.add_child(caption)
	var zeile := HBoxContainer.new()
	zeile.alignment = BoxContainer.ALIGNMENT_CENTER
	zeile.add_theme_constant_override("separation", 6)
	spalte.add_child(zeile)
	var minus := _button("Minus" + feld.to_pascal_case(), "AccentButton")
	minus.text = "−"
	zeile.add_child(minus)
	var wert := Label.new()
	wert.name = "Wert" + feld.to_pascal_case()
	wert.text = str(int(_werte[feld]))
	wert.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wert.custom_minimum_size = Vector2(44, 0)
	zeile.add_child(wert)
	var plus := _button("Plus" + feld.to_pascal_case(), "AccentButton")
	plus.text = "+"
	zeile.add_child(plus)
	minus.pressed.connect(_on_step.bind(feld, -1, max_wert, wert))
	plus.pressed.connect(_on_step.bind(feld, 1, max_wert, wert))


## Squish + Tap-Haptik zentral (Audio-Grammatik) — Floor zieht _relayout.
func _button(btn_name: String, variation: String) -> SquishButton:
	var btn := SquishButton.new()
	btn.name = btn_name
	btn.theme_type_variation = variation
	btn.focus_mode = Control.FOCUS_NONE
	return btn


func _on_step(feld: String, delta: int, max_wert: int, wert_label: Label) -> void:
	var neu := int(_werte[feld]) + delta
	if neu < 1:
		neu = max_wert
	elif neu > max_wert:
		neu = 1
	_werte[feld] = neu
	wert_label.text = str(neu)
	AudioDirector.try_play(self, "ui_tick")


func _on_save() -> void:
	gespeichert.emit(int(_werte["month"]), int(_werte["day"]))


func _on_cancel() -> void:
	abgebrochen.emit()


func _relayout() -> void:
	if not is_inside_tree():
		return
	var m := ScreenShell.metrics(get_viewport())
	var f: float = m["f"]
	ScreenShell.scale_fonts(self, f)
	for btn: Node in find_children("*", "Button", true, false):
		ScreenShell.touch_target(btn as Control, m)
	_karte.custom_minimum_size = Vector2(ScreenShell.card_width(m, CARD_BASE_WIDTH), 0.0)


## Backdrop-Dismiss-Policy (Web): Tap auf den Schleier = Abbrechen, aber
## nur als oberstes Panel.
func _on_veil_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton or event is InputEventScreenTouch):
		return
	if event is InputEventMouseButton and not (event as InputEventMouseButton).pressed:
		return
	if event is InputEventScreenTouch and not (event as InputEventScreenTouch).pressed:
		return
	if PanelStack.is_top(self):
		abgebrochen.emit()
