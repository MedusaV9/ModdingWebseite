extends "res://tools/capture/clips/_city_base.gd"
## Clip: Stadt am Tag — Rückwärts-Ausparken aus der eigenen Einfahrt und
## Fahrt Richtung Wochenmarkt (Verkehr, Ampeln, Fußgänger).


func _setup() -> void:
	duration = 14.0
	stunde = 13.5
	spawn = ""
	ziel_ort = "gouhbus"
	super._setup()
