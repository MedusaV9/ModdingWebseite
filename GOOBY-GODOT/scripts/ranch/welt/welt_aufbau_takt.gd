class_name WeltAufbauTakt
extends RefCounted
## Frame-Budget-Takt des gestückelten Weltaufbaus (W19-Perf): arbeitet
## eine Schritt-Liste (Callables) in Einfüge-Reihenfolge ab und gibt den
## Frame ab, sobald das Budget erschöpft ist. Pro Tick läuft IMMER
## mindestens ein Schritt (Fortschritts-Garantie — sonst könnte ein
## einzelner teurer Schritt den Aufbau dauerhaft blockieren). Die
## Zeitquelle ist injizierbar, damit Tests die Budget-Logik ohne echte
## Wartezeit nachrechnen können.

## Standard-Budget je Frame in Millisekunden: Release-Gate <= 4 ms, damit
## der Rest nach dem Reveal ohne 30-ms-Streaming-Hitches nachströmt.
const BUDGET_MS := 4.0

var budget_ms := BUDGET_MS

var _schritte: Array[Callable] = []
var _zeit_fn: Callable


func _init(budget := BUDGET_MS, zeit_fn := Callable()) -> void:
	budget_ms = budget
	_zeit_fn = zeit_fn if zeit_fn.is_valid() else Callable(Time, "get_ticks_msec")


## Schritt anhängen (läuft in Einfüge-Reihenfolge).
func fuege_hinzu(schritt: Callable) -> void:
	_schritte.append(schritt)


func fertig() -> bool:
	return _schritte.is_empty()


func offen() -> int:
	return _schritte.size()


## Ein Frame-Tick: führt Schritte aus, bis das Budget erschöpft ist.
## Rückgabe: Anzahl der in diesem Tick ausgeführten Schritte.
func tick() -> int:
	var start := int(_zeit_fn.call())
	var gelaufen := 0
	while not _schritte.is_empty():
		var schritt: Callable = _schritte.pop_front()
		schritt.call()
		gelaufen += 1
		if float(int(_zeit_fn.call()) - start) >= budget_ms:
			break
	return gelaufen


## Alle offenen Schritte sofort abarbeiten (Tools/Tests, die die
## KOMPLETT gebaute Welt brauchen, ohne Frames zu ticken).
func alles_sofort() -> int:
	var gelaufen := 0
	while not _schritte.is_empty():
		var schritt: Callable = _schritte.pop_front()
		schritt.call()
		gelaufen += 1
	return gelaufen
