extends "res://tools/capture/clips/_city_base.gd"
## Clip: Stadt bei Nacht — Scheinwerfer, Laternen, leuchtende Fenster;
## Fahrt vom POW quer durch die Stadt.


func _setup() -> void:
	duration = 10.0
	stunde = 21.5
	spawn = "pow"
	ziel_ort = "goobytheke"
	super._setup()
