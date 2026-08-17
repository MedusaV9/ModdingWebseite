class_name WischPan
extends Node
## W20/P3 — Maus-/Finger-Pan für ScrollContainer: Godots eingebautes
## Touch-Pan greift nur bei echten ScreenDrag-Events; Maus-Drags (Desktop,
## Playtest-Harness) ließen Listen unbeweglich, sobald Buttons die Events
## stoppten (User-Befund F2 „Kategorie-Chips reagieren nicht auf Wisch").
## Muster aus ArcadeScreen W18-B5 als EIN Baustein statt weiterer Kopien.
##
## Nutzung: `WischPan.an(scroll)` — tappbare Kinder (Buttons/Chips)
## brauchen zusätzlich `mouse_filter = MOUSE_FILTER_PASS`, damit ihre
## Drags hier ankommen; der Tap bleibt beim Button (unter der Deadzone
## feuert `pressed` wie bisher).

var _scroll: ScrollContainer
var _druck := false
var _aktiv := false
var _summe := Vector2.ZERO
var _start := Vector2.ZERO


## Pan an einen ScrollContainer hängen (Achsen folgen den scroll_modes).
static func an(scroll: ScrollContainer) -> WischPan:
	var pan := WischPan.new()
	pan.name = "WischPan"
	pan._scroll = scroll
	scroll.add_child(pan)
	scroll.gui_input.connect(pan._on_gui_input)
	return pan


func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		_on_maus_knopf(event as InputEventMouseButton)
		return
	if not (event is InputEventMouseMotion) or not _druck:
		return
	var mm := event as InputEventMouseMotion
	if (mm.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0:
		return
	_summe += mm.relative
	if not _aktiv and _summe.length() > float(_scroll.scroll_deadzone):
		_aktiv = true
		# Control.-qualifiziert: WischPan ist ein Node — nur Control-
		# Ableitungen sehen die Konstante unqualifiziert.
		_scroll.propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)
		# Weicher Einstieg: ab der Deadzone zählt nur der weitere Weg.
		_start = Vector2(_scroll.scroll_horizontal, _scroll.scroll_vertical)
		_summe = mm.relative
	if _aktiv:
		if _scroll.horizontal_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			_scroll.scroll_horizontal = int(roundf(_start.x - _summe.x))
		if _scroll.vertical_scroll_mode != ScrollContainer.SCROLL_MODE_DISABLED:
			_scroll.scroll_vertical = int(roundf(_start.y - _summe.y))
		_scroll.accept_event()


func _on_maus_knopf(mb: InputEventMouseButton) -> void:
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		_druck = true
		_aktiv = false
		_summe = Vector2.ZERO
		_start = Vector2(_scroll.scroll_horizontal, _scroll.scroll_vertical)
	else:
		if _aktiv:
			_scroll.propagate_notification(Control.NOTIFICATION_SCROLL_END)
		_druck = false
		_aktiv = false
	_scroll.accept_event()
