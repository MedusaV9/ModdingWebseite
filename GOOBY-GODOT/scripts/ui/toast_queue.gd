class_name ToastQueue
extends RefCounted
## PURE Toast-Warteschlangen-Logik (headless testbar, keine Nodes).
## Lehre aus dem Web: Toasts NIE stapeln — es ist immer höchstens einer
## sichtbar, der Rest wartet in einer FIFO-Queue. Doppelte aufeinander-
## folgende Texte werden verschluckt, die Queue ist gedeckelt.

const MAX_PENDING := 4

var _pending: Array[String] = []
var _current: String = ""


## Toast anfordern. Gibt zurück, ob er angenommen wurde (Dedupe/Cap).
func push(text: String) -> bool:
	if text.is_empty():
		return false
	if text == _current or (not _pending.is_empty() and _pending.back() == text):
		return false  # identischer Nachbar → verschlucken
	if _pending.size() >= MAX_PENDING:
		return false  # Queue voll → verwerfen statt stapeln
	_pending.append(text)
	return true


## Der aktuell sichtbare Toast ("" = keiner).
func current() -> String:
	return _current


## Der aktuelle Toast ist abgelaufen → nächsten holen ("" = Queue leer).
func advance() -> String:
	_current = _pending.pop_front() if not _pending.is_empty() else ""
	return _current


func has_pending() -> bool:
	return not _pending.is_empty()


func pending_count() -> int:
	return _pending.size()


func is_idle() -> bool:
	return _current.is_empty() and _pending.is_empty()


func clear() -> void:
	_pending.clear()
	_current = ""
