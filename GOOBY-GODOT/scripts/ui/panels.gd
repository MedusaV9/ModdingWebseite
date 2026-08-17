class_name PanelStack
extends RefCounted
## Basis der Panel-/Sheet-Verwaltung: EIN globaler Stack, damit die
## Backdrop-Dismiss-Policy aus dem Web gilt: ein Tap auf den Backdrop
## schließt NUR das oberste Panel — nie alle auf einmal.
##
## Panels melden sich mit `PanelStack.push(self)` an und mit
## `PanelStack.remove(self)` ab (macht `panel_sheet.gd` automatisch).

static var _stack: Array[Control] = []


static func push(panel: Control) -> void:
	_prune()
	if not _stack.has(panel):
		_stack.append(panel)


static func remove(panel: Control) -> void:
	_stack.erase(panel)
	_prune()


## Nur das oberste Panel darf per Backdrop geschlossen werden.
static func is_top(panel: Control) -> bool:
	_prune()
	return not _stack.is_empty() and _stack.back() == panel


## FIX1: Escape/Back-Geste schließt NUR das oberste Panel — der eine
## gemeinsame Pfad für alle Sheets (SceneRouter.handle_back_request ruft das).
## true = ein Panel wurde geschlossen.
static func close_top() -> bool:
	_prune()
	if _stack.is_empty():
		return false
	var top: Control = _stack.back()
	if top.has_method("close"):
		top.call("close")
	else:
		remove(top)
	return true


static func count() -> int:
	_prune()
	return _stack.size()


## W20 P1 (Verdeckungs-Vertrag): lebende Stack-Mitglieder für Beobachter
## (HudSichtbarkeit zählt FREMDE Panels — Tagesbonus, Reunion-Karte … —
## die kein PanelSheet sind und deshalb keine opened/closed-Signale haben).
## Kopie, damit Aufrufer den Stack nie mutieren können.
static func members() -> Array[Control]:
	_prune()
	return _stack.duplicate()


## Tests/Szenenwechsel: Stack leeren.
static func clear() -> void:
	_stack.clear()


static func _prune() -> void:
	# KEIN filter(): das liefert ein untypisiertes Array (Laufzeitfehler bei
	# der Zuweisung), und die Lambda-Typung schlägt bei bereits FREIGEGEBENEN
	# Instanzen fehl. Von Hand einsammeln ist beides sicher.
	var alive: Array[Control] = []
	for panel: Variant in _stack:
		if is_instance_valid(panel):
			alive.append(panel)
	_stack = alive
