extends "res://tools/capture/clip_driver.gd"
## Clip: Wetter + Tageszeiten in der Ranch-Region — Zeitraffer vom
## goldenen Nachmittag in die Sternennacht. Erst Regen (Partikel,
## nasser Boden), ab Sekunde 5 klart es zum Regenbogen auf, danach
## Dämmerung → Nacht (Sterne + Mond). Der Reiter trabt gemütlich,
## damit die Szene lebt; die Uhrzeit läuft pro Frame weiter.

const STUNDE_START := 16.2
## Ende bei ~21:15 — Sterne sind da, aber die Landschaft säuft nicht
## komplett ins Schwarz ab (23 Uhr war im Probelauf zu dunkel).
const STUNDE_PRO_SEKUNDE := 0.42

var region: Node3D


func _setup() -> void:
	duration = 12.0
	var packed: PackedScene = load("res://scenes/ranch/welt/ranch_region.tscn")
	region = packed.instantiate()
	region.stunde_override = STUNDE_START
	region.wetter_override = "regen"
	region.receive_params({"spawn_zone": "hof"})
	add_child(region)
	schedule(0.2, func() -> void: _hud_aus())
	schedule(0.6, func() -> void: Input.action_press("ui_up"))
	schedule(
		5.0,
		func() -> void:
			region.wetter_override = "regenbogen"
			if region.wetter != null:
				region.wetter.wetter_override = "regenbogen"
	)


func _tick(_delta: float) -> void:
	if region != null:
		region.stunde_override = STUNDE_START + t * STUNDE_PRO_SEKUNDE


func _hud_aus() -> void:
	for child in region.get_children():
		if child is CanvasLayer:
			child.visible = false
