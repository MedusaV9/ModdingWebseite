class_name HudLangdruckGeste
extends RefCounted
## G8/IDEA-J2 — PURE Langdruck-Erkennung für die HUD-Kacheln (Icon-Bühne):
## hält der Finger eine Kachel ~0,4 s ruhig gedrückt, zeigt die Bühne das
## Namensschild (sie pollt `tick()`); Loslassen VOR der Schwelle bleibt ein
## ganz normaler Kachel-Tap — diese Klasse verzögert/bricht NICHTS, der
## Button feuert selbst. Nach einem ECHTEN Langdruck wird der Release-Tap
## der Kachel genau EINMAL geschluckt (`schluckt_tap`), damit das Halten
## keine App öffnet.
##
## Lektionen aus dem TapGeste-Arbiter (FIX-6/R2, interactables_host.gd):
## - DEVICE_ID_EMULATION VERWERFEN: `emulate_touch_from_mouse` liefert zu
##   jedem physischen Event einen synthetischen Zwilling — ohne Filter
##   würden Press/Release doppelt verarbeitet.
## - Bewegung über der Wackel-Toleranz VOR der Schwelle bricht ab (das ist
##   ein Wisch/Pan, kein Halten); NACH der Schwelle darf der Finger wandern
##   (das Schild bleibt, solange gehalten wird).
## - Zeit wird INJIZIERT (`now_ms`-Parameter, AGENTS-Regel) — headless
##   deterministisch testbar, keine OS-Uhr in der Kernlogik.

## Haltezeit bis zum Namensschild (J2-Design: ~0,4 s).
const SCHWELLE_MS := 400
## Pseudo-Finger für Maus-Events (echte Touch-Indizes sind >= 0).
const MAUS_FINGER := -1001
## Wackel-Toleranz-Default in Canvas-px — die Bühne setzt den echten Wert
## physisch (~10 pt × px/pt), Tests rechnen mit dem Default.
const SLOP_PX_DEFAULT := 24.0

## Erlaubte Fingerbewegung vor der Schwelle (Canvas-px, injizierbar).
var slop_px := SLOP_PX_DEFAULT

var _gedrueckt := false
var _aktiv := false
var _finger := MAUS_FINGER
var _start_pos := Vector2.ZERO
var _start_ms := 0
var _schlucken := false


## Roh-Event einer Kachel (gui_input) einspeisen. Positionen sind lokal
## zur Kachel — für die Wackel-Toleranz zählt nur die Distanz.
func verarbeite(event: InputEvent, now_ms: int) -> void:
	if event.device == InputEvent.DEVICE_ID_EMULATION:
		# Synthetischer Zwilling (emulate_touch_from_mouse bzw.
		# emulate_mouse_from_touch) — die physische Familie genügt.
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_press(touch.index, touch.position, now_ms)
		else:
			_release(touch.index)
	elif event is InputEventMouseButton:
		var maus := event as InputEventMouseButton
		if maus.button_index != MOUSE_BUTTON_LEFT:
			return
		if maus.pressed:
			_press(MAUS_FINGER, maus.position, now_ms)
		else:
			_release(MAUS_FINGER)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_move(drag.index, drag.position)
	elif event is InputEventMouseMotion:
		_move(MAUS_FINGER, (event as InputEventMouseMotion).position)


## Von der Bühne pro Frame gepollt: true GENAU in dem Moment, in dem die
## Haltezeit die Schwelle überschreitet (danach false — Einmal-Impuls).
func tick(now_ms: int) -> bool:
	if not _gedrueckt or _aktiv:
		return false
	if now_ms - _start_ms < SCHWELLE_MS:
		return false
	_aktiv = true
	return true


## Finger liegt gerade auf einer Kachel (vor ODER nach der Schwelle).
func gedrueckt() -> bool:
	return _gedrueckt


## Langdruck läuft (Schwelle überschritten, Finger noch unten).
func aktiv() -> bool:
	return _aktiv


## Muss der nächste Kachel-Tap geschluckt werden? Konsumiert das Flag
## (einmalig) — der Release NACH einem Langdruck darf keine App öffnen.
func schluckt_tap() -> bool:
	if not _schlucken:
		return false
	_schlucken = false
	return true


## Schluck-Flag verfallen lassen (die Bühne ruft das DEFERRED nach dem
## Release — falls der Button gar kein pressed feuerte, bleibt sonst ein
## altes Flag liegen und würde den NÄCHSTEN echten Tap fressen).
func schluck_verfallen() -> void:
	_schlucken = false


## Harter Reset (Layout-Wechsel/Verdeckung) — kein Schlucken, kein Halten.
func zuruecksetzen() -> void:
	_gedrueckt = false
	_aktiv = false
	_schlucken = false


func _press(finger: int, pos: Vector2, now_ms: int) -> void:
	if _gedrueckt and finger != _finger:
		# Zweiter Finger während einer laufenden Geste: der erste behält
		# Vorrang (Kinder-Doppelgriff, wie beim TapGeste-Arbiter).
		return
	_gedrueckt = true
	_aktiv = false
	_schlucken = false
	_finger = finger
	_start_pos = pos
	_start_ms = now_ms


func _move(finger: int, pos: Vector2) -> void:
	if not _gedrueckt or finger != _finger or _aktiv:
		return
	if pos.distance_to(_start_pos) >= slop_px:
		# Bewegung über der Toleranz VOR der Schwelle: Wisch, kein Halten.
		_gedrueckt = false


func _release(finger: int) -> void:
	if not _gedrueckt or finger != _finger:
		return
	_gedrueckt = false
	if _aktiv:
		# Echter Langdruck endet: das Schild geht zu, der Button-Release
		# (pressed feuert im selben Event-Lauf) wird EINMAL geschluckt.
		_schlucken = true
	_aktiv = false
