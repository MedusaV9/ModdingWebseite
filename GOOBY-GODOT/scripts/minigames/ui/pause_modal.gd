class_name MinigamePauseModal
extends Control
## FB3 — DAS kompakte, mittige Pause-Modal für ALLE Minigames (P0 „Pause
## vereinnahmt die ganze Fläche“). Abdunkelung + kleine AcCardLg-Karte mit
## Fortsetzen / Neustart / Ton / Hilfe / Beenden. Das Modal ist reine UI:
## die ECHTE Pause (Zeit + Eingaben stoppen) und der 3-2-1-Weiterspiel-
## Countdown gehören dem MinigameHost — hier laufen nur Signale.
##
## Bausteine statt Eigenbau: Geometrie über `ScreenShell` (UiScale +
## Safe-Area + Touch-Floor), Öffnen/Schließen über `UiMotion` (Federung,
## reduced-motion-gated), Backdrop-Policy über `PanelStack` (Back-Geste
## schließt das Modal = Fortsetzen).

signal resume_requested
signal restart_requested
signal quit_requested

## Wunschbreite der Karte (Design-px; wird gedeckelt, nie Vollfläche).
const CARD_BASE_WIDTH := 340.0
const DIM_COLOR := Color(0.24, 0.16, 0.12, 0.5)

## mg.<id>.hint — leer/unbekannt → Hilfe zeigt den freundlichen Fallback.
var hint_key := ""

## W14/UISCREENS-B: der Hilfe-Text „erzählt“ — Buchstaben-Typewriter im
## Gebrabbel-Tempo (Reduced Motion / „Schnelle Dialoge“ = sofort).
var _typewriter := DialogTypewriter.new()

var _dim: ColorRect
var _card: PanelContainer
var _title: Label
var _resume: Button
var _restart: Button
var _sound: Button
var _help: Button
var _quit: Button
var _hint_label: Label
var _open := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dim = ColorRect.new()
	_dim.color = DIM_COLOR
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Der Backdrop frisst JEDEN Tap — nichts erreicht das pausierte Spiel.
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_dim.gui_input.connect(_on_backdrop_input)
	add_child(_dim)
	_card = PanelContainer.new()
	_card.name = "PauseCard"
	_card.theme_type_variation = &"AcCardLg"
	add_child(_card)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 10)
	_card.add_child(rows)
	_title = Label.new()
	_title.theme_type_variation = &"TitleLabel"
	_title.text = I18nService.t("mg.host.paused")
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_title)
	_resume = _button(rows, &"PrimaryButton", "mg.host.resume", _on_resume_pressed)
	_resume.name = "ResumeButton"
	_restart = _button(rows, &"GhostButton", "mg.host.restart", _on_restart_pressed)
	_restart.name = "RestartButton"
	var toggles := HBoxContainer.new()
	toggles.alignment = BoxContainer.ALIGNMENT_CENTER
	toggles.add_theme_constant_override("separation", 10)
	rows.add_child(toggles)
	_sound = _button(toggles, &"AcChip", "mg.host.sound_on", _on_sound_pressed)
	_sound.name = "SoundButton"
	_sound.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_help = _button(toggles, &"AcChip", "mg.host.help", _on_help_pressed)
	_help.name = "HelpButton"
	_help.toggle_mode = true
	_help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_hint_label = Label.new()
	_hint_label.theme_type_variation = &"CaptionLabel"
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint_label.hide()
	rows.add_child(_hint_label)
	_quit = _button(rows, &"GhostButton", "mg.host.quit", _on_quit_pressed)
	_quit.name = "QuitButton"
	get_viewport().size_changed.connect(_relayout)
	set_process(false)


func _exit_tree() -> void:
	# Host kann samt offenem Modal freigegeben werden (Szenenwechsel) —
	# sonst bleibt ein toter Eintrag im PanelStack zurück.
	PanelStack.remove(self)


func open() -> void:
	if _open:
		return
	_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	_help.button_pressed = false
	_hint_label.hide()
	_refresh_sound_label()
	PanelStack.push(self)
	_relayout()
	UiMotion.pop_in(_card)
	if not ThemeService.is_reduced_motion(self):
		_dim.modulate.a = 0.0
		var tween := create_tween()
		tween.tween_property(_dim, "modulate:a", 1.0, AcTokens.DUR_SHEET / 2.0)


## PanelStack-Contract (Back-Geste/Backdrop): Schließen = Fortsetzen.
func close() -> void:
	if not _open:
		return
	hide_modal()
	resume_requested.emit()


## Nur ausblenden (Host steuert, was danach passiert).
func hide_modal() -> void:
	if not _open:
		return
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	PanelStack.remove(self)


func is_open() -> bool:
	return _open


## Kompakte, mittige Karte: Breite gedeckelt (nie Vollfläche), Fonts und
## Tippflächen über die zentralen Regeln — bei Resize/Rotation erneut.
func _relayout() -> void:
	if _card == null or not is_inside_tree():
		return
	var m := ScreenShell.metrics(get_viewport())
	var insets: Dictionary = m["insets"]
	var canvas: Vector2 = m["canvas"]
	# Kompakt: nie breiter als 60 % des Canvas (Quer) bzw. Safe-Breite.
	var width := minf(ScreenShell.card_width(m, CARD_BASE_WIDTH), canvas.x * 0.6)
	_card.custom_minimum_size = Vector2(width, 0.0)
	for btn in [_resume, _restart, _sound, _help, _quit]:
		ScreenShell.touch_target(btn, m)
	ScreenShell.scale_fonts(_card, m["f"])
	# Mittig in der SAFE-Area zentrieren (Notch/Home-Indicator).
	_card.reset_size()
	var size := _card.get_combined_minimum_size()
	var safe_pos := Vector2(float(insets["left"]), float(insets["top"]))
	var safe_size := Vector2(
		canvas.x - safe_pos.x - float(insets["right"]),
		canvas.y - safe_pos.y - float(insets["bottom"])
	)
	_card.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_card.position = safe_pos + (safe_size - size) / 2.0
	_card.size = size


func _button(parent: Container, variation: StringName, key: String, handler: Callable) -> Button:
	var btn := Button.new()
	btn.theme_type_variation = variation
	btn.text = I18nService.t(key)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(handler)
	parent.add_child(btn)
	return btn


func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and PanelStack.is_top(self):
		close()


func _on_resume_pressed() -> void:
	AudioDirector.try_play(self, "ui_close")
	close()


func _on_restart_pressed() -> void:
	AudioDirector.try_play(self, "ui_confirm")
	hide_modal()
	restart_requested.emit()


func _on_quit_pressed() -> void:
	AudioDirector.try_play(self, "ui_back")
	hide_modal()
	quit_requested.emit()


## Ton-Schalter: audio.master 0/1 über AppSettings (der AudioDirector hört
## auf setting_changed und mutet die Busse); ohne Autoload (Tests) no-op.
func _on_sound_pressed() -> void:
	AudioDirector.try_play(self, "ui_toggle")
	var settings := get_node_or_null("/root/AppSettings")
	if settings == null or not settings.has_method("set_setting"):
		return
	var muted := float(settings.get_setting("audio.master", 1.0)) <= 0.0
	settings.set_setting("audio.master", 1.0 if muted else 0.0)
	_refresh_sound_label()


func _on_help_pressed() -> void:
	AudioDirector.try_play(self, "ui_chip")
	if _help.button_pressed:
		var text := ""
		if not hint_key.is_empty() and I18nService.has_key(hint_key):
			text = I18nService.t(hint_key)
		else:
			text = I18nService.t("mg.host.help_none")
		_hint_label.text = text
		_hint_label.show()
		UiMotion.pop_in(_hint_label)
		# W14: Hilfe „erzählt“ — Zeichen ticken im Gebrabbel-Tempo herein.
		_typewriter.start(text, _sofort_modus())
		_zeige_hint_zeichen()
		set_process(_typewriter.laeuft())
	else:
		_hint_label.hide()
		set_process(false)
	_relayout()


func _process(delta: float) -> void:
	if not _typewriter.laeuft():
		set_process(false)
		return
	_typewriter.tick(delta)
	_zeige_hint_zeichen()


func _zeige_hint_zeichen() -> void:
	_hint_label.visible_characters = -1 if _typewriter.ist_fertig() else _typewriter.sichtbar


## Sofort-Modus wie dialog_view: Reduced Motion ODER „Schnelle Dialoge“.
func _sofort_modus() -> bool:
	if ThemeService.is_reduced_motion(self):
		return true
	var settings := get_node_or_null("/root/AppSettings")
	return settings != null and bool(settings.call("get_setting", "game.schnelle_dialoge", false))


func _refresh_sound_label() -> void:
	var settings := get_node_or_null("/root/AppSettings")
	var on := true
	if settings != null and settings.has_method("get_setting"):
		on = float(settings.get_setting("audio.master", 1.0)) > 0.0
	_sound.text = I18nService.t("mg.host.sound_on" if on else "mg.host.sound_off")
