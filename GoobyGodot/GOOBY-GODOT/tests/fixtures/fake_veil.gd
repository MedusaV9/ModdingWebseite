extends Node
## Test-Doppel (W1a) für LoadingVeil — erfüllt den Veil-Contract synchron:
## cover()/reveal() sind awaitbar (kehren sofort zurück) und feuern die
## Signale; Aufrufe und Fortschritt werden fürs Assert mitgezählt.

signal covered
signal revealed

var cover_calls := 0
var reveal_calls := 0
var progress_values: Array[float] = []


func cover(_reduced_motion := false) -> void:
	cover_calls += 1
	covered.emit()


func reveal(_reduced_motion := false) -> void:
	reveal_calls += 1
	revealed.emit()


func set_progress(ratio: float) -> void:
	progress_values.append(ratio)
