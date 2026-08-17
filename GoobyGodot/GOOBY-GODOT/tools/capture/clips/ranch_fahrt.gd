extends "res://tools/capture/clip_driver.gd"
## Clip: Überlandfahrt zur Gooby Ranch (RANCH-1) — die echte Fahr-Strecke
## (Landstraße mit Feldern, Heuballen, Zäunen, Windrad, Bachbrücke,
## Kühen/Schafen) mit der ChaseCam des Spiels. Das Auto fährt von selbst
## (CarController-Cruise), wir halten nur die Spur per set_steer —
## Eingriff NUR über die öffentliche API, wie ein Spieler-Daumen.

var fahrt: Node3D


func _setup() -> void:
	duration = 12.0
	var packed: PackedScene = load("res://scenes/ranch/ranch_fahrt.tscn")
	# Goldene Stunde: schließt an das Sonnenuntergangs-Artwork der
	# Ranch-Kapitelkarte an und gibt der flachen Landstraße warmes Licht.
	fahrt = packed.instantiate()
	fahrt.stunde_override = 16.8
	add_child(fahrt)
	schedule(0.2, func() -> void: _hud_aus())


## Pure-Pursuit auf die rechte Fahrspur: Zielpunkt 25 m voraus auf
## Spur-x, Vorzeichen-Kontrakt wie _city_base (§G3.1-a: steer senkt heading).
func _tick(_delta: float) -> void:
	if fahrt == null or fahrt.auto == null:
		return
	var auto: Node3D = fahrt.auto
	var ziel_x := -CityCarFeel.LANE_OFFSET_M
	var wunsch := atan2(ziel_x - auto.position.x, 25.0)
	var fehler := wrapf(wunsch - auto.heading, -PI, PI)
	auto.set_steer(clampf(-fehler * 1.8, -1.0, 1.0))


func _hud_aus() -> void:
	for child in fahrt.get_children():
		if child is CanvasLayer:
			child.visible = false
