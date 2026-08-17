extends "res://tools/capture/clip_driver.gd"
## Clip: Die NEUEN Zonen des WELT-1-Ausbaus als Montage — sechs Mini-Shots
## à 3 s mit harten Schnitten (Teleport + Wetter/Uhrzeit je Zone):
##   0 s Lavendelwiese (Sonne, Bienenstöcke)   3 s Nebelmoor (Morgennebel)
##   6 s Turmruine (Abendlicht)                9 s Muschelbucht/Strand
##  12 s Apfelgarten (Mittag)                 15 s Kornfeld (goldene Stunde)
## Der Reiter galoppiert in jedem Shot geradeaus; Remotion schneidet die
## besten Momente heraus.

## [x, z, ziel_x, ziel_z, stunde, wetter]
const SHOTS: Array[Array] = [
	[-742.0, 84.0, -860.0, 104.0, 10.0, "sonne"],
	[858.0, -36.0, 776.0, -150.0, 7.2, "nebel"],
	[742.0, -444.0, 700.0, -502.0, 18.4, "sonne"],
	[752.0, 302.0, 876.0, 262.0, 14.0, "sonne"],
	[-64.0, 758.0, 96.0, 792.0, 12.0, "sonne"],
	[-544.0, 756.0, -368.0, 782.0, 17.6, "sonne"],
]
const SHOT_SEK := 3.0

var region: Node3D


func _setup() -> void:
	duration = SHOT_SEK * SHOTS.size() + 0.4
	var packed: PackedScene = load("res://scenes/ranch/welt/ranch_region.tscn")
	region = packed.instantiate()
	region.stunde_override = float(SHOTS[0][4])
	region.wetter_override = str(SHOTS[0][5])
	region.receive_params({"spawn_zone": "blumenwiese"})
	add_child(region)
	schedule(0.2, func() -> void: _hud_aus())
	schedule(0.25, func() -> void: gooby_in_den_sattel(region.reiter.pferd))
	schedule(
		0.3,
		func() -> void:
			region.reiter.galopp = true
			Input.action_press("ui_up")
	)
	for i in SHOTS.size():
		var shot: Array = SHOTS[i]
		schedule(0.35 + float(i) * SHOT_SEK, _mach_shot.bind(shot))


func _mach_shot(shot: Array) -> void:
	var start := Vector3(float(shot[0]), 0.0, float(shot[1]))
	var d := Vector2(float(shot[2]) - start.x, float(shot[3]) - start.z)
	region.stunde_override = float(shot[4])
	region.wetter_override = str(shot[5])
	if region.wetter != null:
		region.wetter.wetter_override = str(shot[5])
	region.reiter.springe_zu(start, atan2(-d.x, -d.y))


func _hud_aus() -> void:
	for child in region.get_children():
		if child is CanvasLayer:
			child.visible = false
