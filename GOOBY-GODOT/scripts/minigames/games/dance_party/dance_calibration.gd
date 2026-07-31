class_name DanceCalibration
extends Control
## W15/TECHKIT (Doc G §9 R5) — manuelle Audio-Latenz-Feinkalibrierung für
## danceParty, gemountet im Pregame („Timing anpassen"): 8 Metronom-Schläge
## im Spieltakt (100 BPM), der Spieler tippt mit — der MEDIAN der
## Abweichungen (abzüglich der automatischen Basis-Latenz, s. DanceTiming)
## wandert geklemmt (±150 ms) als additiver Key `minigames.danceOffsetMs`
## in den Save. Reset-Knopf setzt den Feinoffset zurück auf 0.
##
## Zeit ist INJIZIERT testbar: advance_time(delta) treibt die Uhr, Tipps
## laufen über register_tap() — _process ist nur der dünne Laufzeit-Treiber.

signal calibrated(manual_ms: int)

## Ergebnis-Grace nach dem letzten Schlag (Nachzügler-Tipps zählen noch).
const FINISH_GRACE_SEC := 0.9
const SCRIM_COLOR := Color(0.11, 0.09, 0.08, 0.72)

## Duck-Typing-GameState (Pregame reicht seinen _resolve_state durch);
## null = kein Save (Tests) — die Kalibrierung läuft trotzdem.
var state_node: Node = null
## Automatische Basis-Latenz (ms) — für die Median-Verrechnung.
var base_latency_ms := 0.0
var running := false
var clock := 0.0
var next_beat := 0
var tap_deltas: Array[float] = []
var result_ms := 0

var _tapped_beats: Dictionary = {}
var _status_label: Label
var _offset_label: Label
var _tap_button: Button
var _start_button: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	base_latency_ms = DanceTiming.from_audio_server().base_latency_ms
	_build_ui()
	_refresh_offset_label()


func _process(delta: float) -> void:
	if running:
		advance_time(delta)


## ---------------------------------------------------------- Kalibrier-Lauf


## Kalibrierung starten: Uhr auf 0, 8 Schläge ab CALIBRATION_LEAD_IN_SEC.
func start_run() -> void:
	running = true
	clock = 0.0
	next_beat = 0
	tap_deltas = []
	_tapped_beats = {}
	if _status_label != null:
		_status_label.text = I18nService.t(
			"mg.danceParty.kalib_beat", {"n": 0, "max": DanceTiming.CALIBRATION_BEATS}
		)
	if _start_button != null:
		_start_button.disabled = true
	if _tap_button != null:
		_tap_button.disabled = false


## Uhr treiben (Laufzeit: _process; Tests: direkt mit Fake-Deltas).
func advance_time(delta: float) -> void:
	if not running:
		return
	clock += delta
	while next_beat < DanceTiming.CALIBRATION_BEATS and clock >= _beat_time(next_beat):
		_play_tick(next_beat)
		next_beat += 1
	var last := _beat_time(DanceTiming.CALIBRATION_BEATS - 1)
	if next_beat >= DanceTiming.CALIBRATION_BEATS and clock >= last + FINISH_GRACE_SEC:
		_finish()


## Einen Mit-Tipp zur aktuellen Uhr registrieren (ein Tipp pro Schlag).
func register_tap() -> void:
	if not running:
		return
	var match_result := DanceTiming.tap_delta_ms(clock)
	var beat := int(match_result["beat"])
	if _tapped_beats.has(beat):
		return
	_tapped_beats[beat] = true
	tap_deltas.append(float(match_result["delta_ms"]))
	if _status_label != null:
		_status_label.text = I18nService.t(
			"mg.danceParty.kalib_beat",
			{"n": tap_deltas.size(), "max": DanceTiming.CALIBRATION_BEATS}
		)


func _finish() -> void:
	running = false
	var manual := DanceTiming.manual_from_taps(tap_deltas, base_latency_ms)
	result_ms = int(round(manual))
	if not tap_deltas.is_empty():
		_write_offset(result_ms)
	if _status_label != null:
		_status_label.text = I18nService.t("mg.danceParty.kalib_ergebnis", {"ms": result_ms})
	if _start_button != null:
		_start_button.disabled = false
	if _tap_button != null:
		_tap_button.disabled = true
	_refresh_offset_label()
	calibrated.emit(result_ms)


func _reset_offset() -> void:
	AudioDirector.try_play(self, "ui_chip")
	_write_offset(0)
	result_ms = 0
	if _status_label != null:
		_status_label.text = I18nService.t("mg.danceParty.kalib_text")
	_refresh_offset_label()
	calibrated.emit(0)


## Aktueller Feinoffset aus dem Save (0 ohne GameState).
func stored_offset_ms() -> int:
	if state_node == null or not state_node.has_method("state"):
		return 0
	return int(DanceTiming.manual_offset_from_state(state_node.state()))


func _write_offset(ms: int) -> void:
	if state_node == null or not state_node.has_method("update"):
		return
	state_node.update(
		func(state: Dictionary) -> void: DanceTiming.store_manual_offset(state, float(ms))
	)


func _beat_time(beat: int) -> float:
	return DanceTiming.CALIBRATION_LEAD_IN_SEC + float(beat) * DanceTiming.CALIBRATION_BEAT_SEC


func _play_tick(beat: int) -> void:
	# Letzter Schlag klingt höher — hörbares „gleich fertig".
	var last := beat == DanceTiming.CALIBRATION_BEATS - 1
	FeelSfx.play(self, "game_countdown", 1.2 if last else 0.95)
	if _tap_button != null:
		var tween := create_tween()
		tween.tween_property(_tap_button, "modulate", Color(1.0, 0.85, 0.4), 0.05)
		tween.tween_property(_tap_button, "modulate", Color.WHITE, 0.25)


## ------------------------------------------------------------ Pregame-Hook


## Vom Pregame gerufen (eine Zeile): Abschnitts-Label + „Timing anpassen"-
## Knopf (zeigt den gespeicherten Offset in ms) unter die Karte hängen.
static func mount_pregame_section(host: Control, rows: VBoxContainer, state: Node) -> Button:
	var button := Button.new()
	button.name = "DanceKalibKnopf"
	button.theme_type_variation = &"GhostButton"
	button.custom_minimum_size = Vector2(0, 46)
	_update_button_text(button, state)
	button.pressed.connect(_open_overlay.bind(host, button, state))
	rows.add_child(button)
	return button


static func _open_overlay(host: Control, button: Button, state: Node) -> void:
	AudioDirector.try_play(host, "ui_open")
	var overlay := DanceCalibration.new()
	overlay.name = "DanceKalibOverlay"
	overlay.state_node = state
	host.add_child(overlay)
	overlay.calibrated.connect(
		func(_ms: int) -> void:
			if is_instance_valid(button):
				_update_button_text(button, state)
	)


static func _update_button_text(button: Button, state: Node) -> void:
	var ms := 0
	if state != null and state.has_method("state"):
		ms = int(DanceTiming.manual_offset_from_state(state.state()))
	button.text = I18nService.t("mg.danceParty.kalib_knopf", {"ms": _signed(ms)})


static func _signed(ms: int) -> String:
	return "+%d" % ms if ms > 0 else str(ms)


## ---------------------------------------------------------------------- UI


func _build_ui() -> void:
	var scrim := ColorRect.new()
	scrim.name = "Scrim"
	scrim.color = SCRIM_COLOR
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scrim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var card := PanelContainer.new()
	card.name = "KalibCard"
	card.theme_type_variation = &"AcCardLg"
	card.custom_minimum_size = Vector2(360, 0)
	center.add_child(card)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 12)
	card.add_child(rows)

	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text = I18nService.t("mg.danceParty.kalib_titel")
	rows.add_child(title)

	var info := Label.new()
	info.theme_type_variation = &"CaptionLabel"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(320, 0)
	info.text = I18nService.t("mg.danceParty.kalib_text")
	rows.add_child(info)

	_offset_label = Label.new()
	_offset_label.name = "OffsetLabel"
	_offset_label.theme_type_variation = &"HeadlineLabel"
	_offset_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rows.add_child(_offset_label)

	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	_status_label.theme_type_variation = &"CaptionLabel"
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.text = I18nService.t("mg.danceParty.kalib_text")
	rows.add_child(_status_label)

	_tap_button = Button.new()
	_tap_button.name = "TapButton"
	_tap_button.theme_type_variation = &"PrimaryButton"
	_tap_button.text = I18nService.t("mg.danceParty.kalib_tap")
	_tap_button.custom_minimum_size = Vector2(0, 110)
	_tap_button.disabled = true
	_tap_button.focus_mode = Control.FOCUS_NONE
	_tap_button.pressed.connect(register_tap)
	rows.add_child(_tap_button)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 10)
	rows.add_child(buttons)
	_start_button = Button.new()
	_start_button.name = "StartButton"
	_start_button.theme_type_variation = &"AcChip"
	_start_button.custom_minimum_size = Vector2(0, 46)
	_start_button.text = I18nService.t("mg.danceParty.kalib_start")
	_start_button.pressed.connect(_on_start_pressed)
	buttons.add_child(_start_button)
	var reset := Button.new()
	reset.name = "ResetButton"
	reset.theme_type_variation = &"AcChip"
	reset.custom_minimum_size = Vector2(0, 46)
	reset.text = I18nService.t("mg.danceParty.kalib_reset")
	reset.pressed.connect(_reset_offset)
	buttons.add_child(reset)
	var close := Button.new()
	close.name = "CloseButton"
	close.theme_type_variation = &"GhostButton"
	close.custom_minimum_size = Vector2(0, 46)
	close.text = I18nService.t("mg.danceParty.kalib_zu")
	close.pressed.connect(_on_close_pressed)
	buttons.add_child(close)


func _on_start_pressed() -> void:
	AudioDirector.try_play(self, "ui_confirm")
	start_run()


func _on_close_pressed() -> void:
	AudioDirector.try_play(self, "ui_back")
	queue_free()


func _refresh_offset_label() -> void:
	if _offset_label == null:
		return
	_offset_label.text = I18nService.t(
		"mg.danceParty.kalib_offset", {"ms": _signed(stored_offset_ms())}
	)
