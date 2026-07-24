extends Node
## Test-Fixture (W1a): hat das ready_for_reveal-Signal, emittiert es aber NIE —
## für den Hard-Timeout-/Force-Reveal-Test des SceneRouters.

signal ready_for_reveal

var ready_emitted := false


## Nur vorhanden, damit das Signal formal emittierbar ist (Tests rufen das
## bewusst nicht auf).
func force_emit() -> void:
	ready_emitted = true
	ready_for_reveal.emit()
