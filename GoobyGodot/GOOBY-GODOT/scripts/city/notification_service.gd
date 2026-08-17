class_name CityNotificationService
extends RefCounted
## Lokale-Notification-Schnittstelle (W3a CITY, Doc E §4/§C M1): plant
## Erinnerungen („Dein Taxi ist gleich da!“, „Dein Essen ist da!“) zu
## bekannten Zeitpunkten. M1 = OS-STUB: Godot hat keine portable
## Local-Notification-API (DisplayServer kann es nicht; iOS braucht
## UNUserNotificationCenter). Die Planung ist trotzdem VOLL implementiert
## und getestet — nur `_os_planen`/`_os_stornieren` sind Stubs.
##
## BACKLOG (M2, §C-Plugin): natives iOS-Plugin `gooby_notify`
## (requestAuthorization + UNCalendarNotificationTrigger); dieselbe
## Schnittstelle, nur die zwei _os_*-Methoden implementieren. Solange die
## App OFFEN ist, feuern Notifications als In-App-Banner (Foreground-
## Handler): Konsumenten pollen `faellige(now_ms)` im _process und zeigen
## einen Toast (W1c) statt der System-Notification.

## Geplante Einträge: id → {id, text, at_ms, os (bool = ans OS übergeben)}.
var _geplant: Dictionary = {}


## Notification planen (id-Dedupe: neu planen ersetzt). text ist der FERTIGE
## String (Aufrufer übersetzt via I18n), at_ms = Unix-ms.
func plane(id: String, text: String, at_ms: int) -> void:
	storniere(id)
	_geplant[id] = {"id": id, "text": text, "at_ms": at_ms, "os": _os_planen(id, text, at_ms)}


func storniere(id: String) -> void:
	if not _geplant.has(id):
		return
	_os_stornieren(id)
	_geplant.erase(id)


## Alle Einträge mit id-Präfix stornieren (z. B. "taxi.").
func storniere_gruppe(prefix: String) -> void:
	for id: String in _geplant.keys().duplicate():
		if id.begins_with(prefix):
			storniere(id)


func geplant() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for id: String in _geplant:
		out.append(_geplant[id])
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["at_ms"] < b["at_ms"])
	return out


## Fällige Einträge abholen UND entfernen (In-App-Banner-Pfad, App offen).
func faellige(now_ms: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for eintrag in geplant():
		if int(eintrag["at_ms"]) <= now_ms:
			out.append(eintrag)
			storniere(str(eintrag["id"]))
	return out


## OS-Stub: true = ans OS übergeben (M1: immer false → In-App-Banner-Pfad).
func _os_planen(_id: String, _text: String, _at_ms: int) -> bool:
	return false


func _os_stornieren(_id: String) -> void:
	pass
