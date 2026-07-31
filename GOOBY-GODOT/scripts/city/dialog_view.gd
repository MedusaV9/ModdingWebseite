class_name OrtDialogView
extends Control
## Dialog-View (W3a CITY, Doc E §2.4): rendert einen OrtDialogRunner —
## Text-Bubbles (W1c DialogBubble) + NPC-Gebrabbel (W1b GoobyVoice) +
## Options-Knöpfe. Effekte werden ANS ORT-SCRIPT gemeldet (Signal `effekt`),
## das GameState/Laden-Öffnen übernimmt (der Runner bleibt pure).
##
## W13B (E §2.2-Rest): ECHTER Buchstaben-Typewriter als Standard-Modus —
## Zeichen für Zeichen im Gebrabbel-Tempo (DialogTypewriter, Zeit injiziert
## über `_process`), Tap auf die Bubble zeigt erst die GANZE Zeile und
## blättert erst danach weiter. Reduced-Motion ODER der Settings-Schalter
## „Schnelle Dialoge“ (`game.schnelle_dialoge`) = Zeile sofort komplett.
## Die Bubble-Szene (scripts/ui, fremder Owner) bleibt unangetastet: die View
## legt einen eigenen Tap-Fänger ÜBER den Bubble-Inhalt und reicht das
## „Weiter“ als synthetischen Klick an die Bubble durch.

signal effekt(daten: Dictionary)
signal beendet

const BubbleScene := preload("res://scripts/ui/dialog_bubble.tscn")

var runner: OrtDialogRunner
var voice: GoobyVoice
## Standard = Typewriter AN (fühlt sich AC-mäßiger an); false = altes
## Sofort-Verhalten (ganze Zeile auf einmal).
var typewriter_aktiv := true
## Test-Hook: -1 = Settings/Reduced-Motion fragen, 0/1 = sofort erzwingen.
var sofort_override := -1

var _bubble: DialogBubble
var _optionen_box: VBoxContainer
var _typewriter := DialogTypewriter.new()
var _label: Label
var _fang: Control


func _ready() -> void:
	# anchors+offsets (nicht nur anchors): _ready läuft NACH add_child —
	# set_anchors_preset allein lässt den Rect dann bei 0×0.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Bubble behält das Szenen-Layout (unten-breit) — Anker hier NICHT
	# überschreiben, sonst wandert sie über den oberen Schirmrand.
	_bubble = BubbleScene.instantiate()
	add_child(_bubble)
	_bubble.finished.connect(_on_bubble_finished)
	_bubble.advanced.connect(_on_zeile_begonnen)
	_install_typewriter()
	# Options-Stapel direkt ÜBER der Bubble, wächst nach oben.
	_optionen_box = VBoxContainer.new()
	_optionen_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_optionen_box.offset_left = -170.0
	_optionen_box.offset_right = 170.0
	_optionen_box.offset_top = -190.0
	_optionen_box.offset_bottom = -190.0
	_optionen_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_optionen_box.custom_minimum_size = Vector2(340.0, 0.0)
	_optionen_box.add_theme_constant_override("separation", 10)
	add_child(_optionen_box)


## Dialog starten (Baum + Flags kommen vom Ort-Script).
func starte(dialog_baum: Dictionary, flags: Dictionary) -> void:
	runner = OrtDialogRunner.new(dialog_baum, flags)
	if not runner.ist_geladen():
		beendet.emit()
		return
	_zeige_knoten()


func _process(delta: float) -> void:
	if _typewriter.laeuft():
		_typewriter.tick(delta)
		_zeige_zeichen()


func _zeige_knoten() -> void:
	for kind in _optionen_box.get_children():
		kind.queue_free()
	var zeilen := runner.text()
	if voice != null and not zeilen.is_empty():
		voice.sagt(zeilen[0])
	_bubble.show_lines(zeilen)


func _on_bubble_finished() -> void:
	if _label != null:
		_label.visible_characters = -1
	for eintrag in runner.effekte():
		effekt.emit(eintrag)
	if runner.ist_ende():
		beendet.emit()
		return
	if runner.optionen().is_empty() and runner.weiter():
		_zeige_knoten()
		return
	var optionen := runner.optionen()
	for i in optionen.size():
		var btn := Button.new()
		btn.text = str(optionen[i]["text"])
		btn.theme_type_variation = "AccentButton"
		btn.pressed.connect(_on_option.bind(i))
		_optionen_box.add_child(btn)


func _on_option(index: int) -> void:
	if runner.waehlen(index):
		_zeige_knoten()


# ── W13B Buchstaben-Typewriter ───────────────────────────────────────────────


## Tap-Fänger über den Bubble-Inhalt legen und die Bubble-eigene Tap-Fläche
## stilllegen — ALLE Taps laufen ab jetzt über `_on_fang_input` (erst Zeile
## vervollständigen, dann weiterblättern). Runtime-only, kein Bubble-Edit.
func _install_typewriter() -> void:
	_label = _bubble.get_node("%BubbleText") as Label
	var panel := _bubble.get_node("%Bubble") as Control
	if panel == null:
		return
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fang = Control.new()
	_fang.name = "TypewriterTapFang"
	_fang.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.add_child(_fang)
	_fang.gui_input.connect(_on_fang_input)


## Bubble hat eine (neue) Zeile gesetzt → Typewriter für genau diese Zeile
## neu anwerfen (das Gebrabbel läuft parallel im selben Tempo weiter).
func _on_zeile_begonnen(_index: int) -> void:
	if _label == null:
		return
	_typewriter.start(_label.text, _sofort_modus())
	_zeige_zeichen()


func _on_fang_input(event: InputEvent) -> void:
	var tippbar := event is InputEventMouseButton or event is InputEventScreenTouch
	if not tippbar or not event.is_pressed():
		return
	if not _typewriter.ist_fertig():
		# Erster Tap: ganze Zeile sofort.
		_typewriter.skip()
		_zeige_zeichen()
		return
	_bubble_weiter()


## „Weiter“ an die Bubble durchreichen (synthetischer Klick auf ihre
## Original-Tap-Leitung — dieselbe, die test_ui_theme benutzt).
func _bubble_weiter() -> void:
	var panel := _bubble.get_node("%Bubble") as Control
	if panel == null:
		return
	var klick := InputEventMouseButton.new()
	klick.pressed = true
	klick.button_index = MOUSE_BUTTON_LEFT
	panel.gui_input.emit(klick)


func _zeige_zeichen() -> void:
	if _label == null:
		return
	_label.visible_characters = -1 if _typewriter.ist_fertig() else _typewriter.sichtbar


## Sofort-Modus: Typewriter aus, Reduced-Motion ODER „Schnelle Dialoge“.
func _sofort_modus() -> bool:
	if sofort_override >= 0:
		return sofort_override == 1
	if not typewriter_aktiv:
		return true
	if ThemeService.is_reduced_motion(self):
		return true
	var settings := get_node_or_null("/root/AppSettings")
	return settings != null and bool(settings.call("get_setting", "game.schnelle_dialoge", false))
