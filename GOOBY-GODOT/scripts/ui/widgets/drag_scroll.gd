class_name DragScroll
extends Node
## G8-PT3 Befund B1 (HOCH): Ein ScrollContainer voller Buttons pannt per
## Touch-Drag NIE, wenn der Zug auf einer Kachel beginnt — der Button
## konsumiert den (aus dem Touch emulierten) Maus-Press per accept_event,
## und Godot 4.4 schaltet das native Container-Panning nur scharf, wenn
## der Press den ScrollContainer selbst erreicht (gui_input armt
## drag_touching; Folge-Motions gehen ohnehin nur an den Maus-Fokus).
##
## Dieser Helfer beobachtet die Geste deshalb in _input() — das läuft VOR
## der GUI-Zustellung — und übernimmt ab der Bewegungs-Schwelle selbst:
## - Button-Press abbrechen über den ENGINE-KONTRAKT
##   propagate_notification(NOTIFICATION_SCROLL_BEGIN) — exakt die
##   Notification, mit der auch das native Panning BaseButton.press_attempt
##   abbricht (base_button.cpp behandelt SCROLL_BEGIN/DRAG_BEGIN).
## - Selbst pannen (ScrollBar.value) und die Motions dabei KONSUMIEREN,
##   damit der native Pfad (Press in der Kachel-Lücke traf den Container)
##   nicht doppelt pannt.
## - Press/Release NIE anfassen: Taps ohne Schwellen-Bewegung drücken
##   Buttons exakt wie vorher (die Playtest-Flows tippen Kacheln!).
##
## EIN Helfer, mehrere Anwender (Arcade-Grid, Kleiderschrank, Baumodus-
## Dock-Lager, Füttern-Grid, Customize): DragScroll.anbinden(scroller).
##
## Grenzen (bewusst, Engine-Parität): Der Helfer hört wie BaseButton auf
## MAUS-Events — echte Maus ODER die per emulate_mouse_from_touch
## (Projekt-Default AN) gespiegelten Touches. Zweite Finger pannen nicht.

## Bewegungs-Schwelle in Canvas-px, wenn der Scroller keine eigene
## scroll_deadzone setzt (Engine-Default 0 hieße: jeder Tap-Wackler pannt).
const STANDARD_SCHWELLE := 24.0

## Genau EIN Helfer pannt pro Geste — bei verschachtelten Scrollern
## (Customize: Optionen-Zeile in der rechten Spalte) gewinnt der erste,
## dessen freigeschaltete Achse die Schwelle reißt.
static var _aktiv: DragScroll = null

var _scroller: ScrollContainer
var _gedrueckt := false
var _summe := Vector2.ZERO
var _pannt := false


## Helfer an einen ScrollContainer hängen (idempotent).
static func anbinden(scroller: ScrollContainer) -> DragScroll:
	if scroller == null:
		return null
	for kind in scroller.get_children():
		if kind is DragScroll:
			return kind
	var helfer: DragScroll = new()
	helfer.name = "DragScroll"
	helfer._scroller = scroller
	scroller.add_child(helfer)
	return helfer


## Alle ScrollContainer unter (und inklusive) `wurzel` anbinden — für
## Screens mit mehreren Scrollern in einem Ast (Customize: Kategorie-Spalte,
## rechte Spalte, Optionen-Zeile) reicht so EIN Aufruf nach dem UI-Bau.
static func anbinden_alle(wurzel: Node) -> void:
	if wurzel is ScrollContainer:
		anbinden(wurzel)
	for kind in wurzel.get_children():
		anbinden_alle(kind)


func _exit_tree() -> void:
	_geste_beenden()


func _input(event: InputEvent) -> void:
	if _scroller == null or not is_instance_valid(_scroller):
		return
	if event is InputEventMouseButton:
		var knopf := event as InputEventMouseButton
		if knopf.button_index != MOUSE_BUTTON_LEFT:
			return
		if knopf.pressed:
			_summe = Vector2.ZERO
			_gedrueckt = _geste_gehoert_uns(knopf.position)
		else:
			_geste_beenden()
	elif event is InputEventMouseMotion and _gedrueckt:
		var zug := event as InputEventMouseMotion
		if not (zug.button_mask & MOUSE_BUTTON_MASK_LEFT):
			return
		if not _scroller.is_visible_in_tree():
			_geste_beenden()
			return
		_summe += zug.relative
		if not _pannt:
			_uebernahme_pruefen()
		if _pannt:
			_pannen(zug.relative)
			_scroller.get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and _pannt:
		# Touch-Zwilling DERSELBEN Finger-Bewegung (Index 0 spiegelt die
		# Maus und umgekehrt): schlucken, sonst pannt der NATIVE Container-
		# Pfad dieselbe Strecke DOPPELT, wenn der Press in der Kachel-Lücke
		# den Scroller erreichte und drag_touching armte (B1-Befund: Lücken-
		# Wisch pannt nativ +249). Zweite Finger (Index > 0) bleiben unberührt.
		if (event as InputEventScreenDrag).index == 0:
			_scroller.get_viewport().set_input_as_handled()


## Press-Wache: Geste beginnt sichtbar IM Scroller, nicht auf seinen
## Scrollbalken (deren Grabber-Drag bleibt nativ) und nicht auf etwas,
## das den Scroller VERDECKT (Modal/Sheet).
func _geste_gehoert_uns(pos: Vector2) -> bool:
	if not _scroller.is_visible_in_tree():
		return false
	if not _scroller.get_global_rect().has_point(pos):
		return false
	if _auf_scrollbalken(pos):
		return false
	return not _fremd_verdeckt(pos)


func _auf_scrollbalken(pos: Vector2) -> bool:
	for balken: ScrollBar in [_scroller.get_v_scroll_bar(), _scroller.get_h_scroll_bar()]:
		if balken != null and balken.is_visible_in_tree():
			if balken.get_global_rect().has_point(pos):
				return true
	return false


## Verdeckungs-Wache über den Hover-Stand der GUI: Liegt unterm Druckpunkt
## sichtbar ein FREMDES Control (Modal-Backdrop, Sheet), gehört die Geste
## nicht uns. Stale Hover (reiner Touch ohne Maus-Bewegung) enthält den
## Druckpunkt i. d. R. nicht — dann greift die Wache bewusst NICHT (lieber
## pannen als den B1-Fix auf Geräten auszuhebeln).
func _fremd_verdeckt(pos: Vector2) -> bool:
	var viewport := _scroller.get_viewport()
	if viewport == null:
		return false
	var drueber := viewport.gui_get_hovered_control()
	if drueber == null or not is_instance_valid(drueber) or not drueber.is_visible_in_tree():
		return false
	if not drueber.get_global_rect().has_point(pos):
		return false
	var verwandt := (
		drueber == _scroller
		or _scroller.is_ancestor_of(drueber)
		or drueber.is_ancestor_of(_scroller)
	)
	return not verwandt


## Ab hier pannt der Helfer: Schwelle auf einer freigeschalteten Achse
## gerissen (Engine-Formel — Achsen-Dominanz ist KEINE Bedingung, ein
## vertikales Grid folgt auch einem schrägen Wisch).
func _uebernahme_pruefen() -> void:
	var schwelle := _schwelle()
	var vertikal := _kann_scrollen(true) and absf(_summe.y) > schwelle
	var horizontal := _kann_scrollen(false) and absf(_summe.x) > schwelle
	if not (vertikal or horizontal):
		return
	if _aktiv != null and _aktiv != self and is_instance_valid(_aktiv):
		# Ein anderer Helfer hat die Geste — bis zum Loslassen ruhen.
		_gedrueckt = false
		_summe = Vector2.ZERO
		return
	_aktiv = self
	_pannt = true
	_scroller.propagate_notification(Control.NOTIFICATION_SCROLL_BEGIN)
	_scroller.scroll_started.emit()


func _pannen(relativ: Vector2) -> void:
	if _kann_scrollen(true):
		_scroller.get_v_scroll_bar().value -= relativ.y
	if _kann_scrollen(false):
		_scroller.get_h_scroll_bar().value -= relativ.x


func _kann_scrollen(vertikal: bool) -> bool:
	var modus := _scroller.vertical_scroll_mode if vertikal else _scroller.horizontal_scroll_mode
	if modus == ScrollContainer.SCROLL_MODE_DISABLED:
		return false
	# Explizit ScrollBar: der Ternary mischt VScrollBar/HScrollBar — die
	# Inferenz ergäbe Variant (Warning-as-Error im Headless-Import).
	var balken: ScrollBar = (
		_scroller.get_v_scroll_bar() if vertikal else _scroller.get_h_scroll_bar()
	)
	return balken != null and balken.max_value - balken.page > 0.5


func _schwelle() -> float:
	return maxf(float(_scroller.scroll_deadzone), STANDARD_SCHWELLE)


func _geste_beenden() -> void:
	_gedrueckt = false
	_summe = Vector2.ZERO
	if not _pannt:
		return
	_pannt = false
	if _aktiv == self:
		_aktiv = null
	if _scroller != null and is_instance_valid(_scroller):
		_scroller.propagate_notification(Control.NOTIFICATION_SCROLL_END)
		_scroller.scroll_ended.emit()
