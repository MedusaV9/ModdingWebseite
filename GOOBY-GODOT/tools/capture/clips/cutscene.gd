extends "res://tools/capture/clip_driver.gd"
## Clip: Reise-Cutscene (Abflug) — 5-Shot-Sequenz des Spiels: Haustür,
## Einfahrt-Dolly + Winken, Taxi, Stadt-Montage, Flugzeug hebt ab.


func _setup() -> void:
	duration = 26.0
	var packed: PackedScene = load("res://scenes/city/reise_cutscene.tscn")
	var cut: Node3D = packed.instantiate()
	cut.ziel_id = "flughafen"
	cut.fertig.connect(func() -> void: get_tree().quit())
	add_child(cut)
