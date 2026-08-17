class_name NotifyStub
extends RefCounted
## Schlankes Notification-Interface (W3d CONTENT). Das ECHTE lokale
## Push-Backend (iOS UNUserNotificationCenter-Plugin, Ruhezeiten) gehört
## W3a — dieses Stub teilt bewusst das NAMENSSCHEMA, damit der Orchestrator
## beide auf EIN Backend mergen kann (Handoff: W3d-content.md
## „notify-Merge-Request“). Bis dahin: In-Memory-Queue, deterministisch
## testbar; `take_due()` liefert fällige Einträge für In-App-Bubbles.
##
## Gemeinsames Schema (W3a bitte identisch):
##   schedule_local(id, title, body, at_ms)  — id-idempotent (ersetzt)
##   cancel_local(id)
##   pending() -> Array[Dictionary{id,title,body,at_ms}]

static var _pending: Dictionary = {}


## Notification planen (gleiche id ersetzt den alten Eintrag).
static func schedule_local(id: String, title: String, body: String, at_ms: int) -> void:
	_pending[id] = {"id": id, "title": title, "body": body, "at_ms": at_ms}


static func cancel_local(id: String) -> void:
	_pending.erase(id)


static func pending() -> Array:
	var entries := _pending.values()
	entries.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return int(a["at_ms"]) < int(b["at_ms"])
	)
	return entries


## Fällige Einträge (at_ms <= now_ms) entnehmen — In-App-Ersatz fürs Push.
static func take_due(now_ms: int) -> Array:
	var due: Array = []
	for id: String in _pending.keys().duplicate():
		if int(_pending[id]["at_ms"]) <= now_ms:
			due.append(_pending[id])
			_pending.erase(id)
	due.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool: return int(a["at_ms"]) < int(b["at_ms"])
	)
	return due


## Nur für Tests.
static func reset_for_tests() -> void:
	_pending = {}
