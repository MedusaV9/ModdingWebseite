extends "res://tools/capture/clips/_city_base.gd"
## Clip: Stadt-Panorama — eigene Kino-Kamera schwenkt am hellen Tag über
## die belebte Stadt (Verkehr + Fußgänger laufen weiter). Bewusst KEINE
## Dämmerung: unter tageslicht<1 wird die Boden-Hemisphäre des
## Prozedural-Himmels schlammig-grün und die Plattenkante fällt auf.


func _setup() -> void:
	duration = 8.0
	stunde = 10.5
	spawn = "wochenmarkt"
	ziel_ort = "wochenmarkt"
	super._setup()
	# Kino-Shot: Fahr-HUD (Minimap/Bremse) ausblenden — reine Kulisse.
	schedule(
		0.1,
		func() -> void:
			var layer := city.get_node_or_null("HudLayer")
			if layer != null:
				layer.visible = false
	)
	# Kranfahrt: von hoch über dem Stadtrand hinunter Richtung Zentrum.
	# Steil genug pitchen, dass die Plattenkante außerhalb des Bildes bleibt.
	cine_camera(Vector3(-70.0, 92.0, 100.0), Vector3(25.0, 0.0, 15.0), 50.0)
	move_camera(Vector3(30.0, 40.0, 58.0), Vector3(15.0, 0.0, -8.0), duration, 46.0)


func _tick(_delta: float) -> void:
	# Auto bleibt geparkt — nur Kulisse mit Verkehr/Fußgängern.
	if city != null and city.auto != null:
		city.auto.set_frozen(true)
