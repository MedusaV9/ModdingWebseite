extends "res://tools/capture/clip_driver.gd"
## Clip: Funkelpark (REST-4) — kurze Totale über die Plaza (Riesenrad,
## Karussell, Lichterketten-Stimmung am frühen Abend), dann Achterbahn-POV:
## Boarding/Lift werden per deterministischem simuliere()-Vorlauf
## übersprungen, die Kamera übernimmt kurz vor der Kuppe — Drop, Looping,
## Fotopunkt und Hügel laufen in Echtzeit. „Hände hoch" im Drop.

var park: Node3D


func _setup() -> void:
	duration = 15.5
	var packed: PackedScene = load("res://scenes/park/funkelpark.tscn")
	park = packed.instantiate()
	park.stunde_override = 17.5
	add_child(park)
	schedule(0.2, _hud_aus)
	schedule(0.3, _totale)
	schedule(2.6, _fahrt)


func _hud_aus() -> void:
	for child in park.get_children():
		if child is CanvasLayer:
			child.visible = false
	# Die drei Naschgassen-Label3D sind breiter als der Standabstand und
	# stapeln sich aus jeder Totalen-Perspektive zu Buchstabenbrei — für den
	# Trailer aus (Markisen + Stände bleiben, das Torschild trägt den Namen).
	var gasse := park.get_node_or_null("Naschgasse")
	if gasse != null:
		for stand in gasse.get_children():
			for teil in stand.get_children():
				if teil is Label3D:
					teil.visible = false
	# KEINE Schatten-Regie: shadow_enabled auf der Parksonne wäscht unter
	# gl_compatibility das ganze Bild aus (Wiese wird weiß, Farben kippen —
	# per Probelauf verifiziert). Der Park bleibt wie im Spiel schattenlos.


## Establishing-Shot: frontal aufs Torschild (lesbar, Stand-Schilder der
## Gasse bleiben darunter/verdeckt — schräge Winkel stapeln die 3D-Texte
## sonst zu Buchstabenbrei), dann Kran übers Tor in die Park-Totale
## (Riesenrad links, Achterbahn hinten, Karussell rechts).
func _totale() -> void:
	cine_camera(Vector3(0.0, 3.4, 25.0), Vector3(0.0, 4.5, 16.0), 48.0)
	move_camera(Vector3(0.0, 10.5, 20.5), Vector3(-1.5, 1.8, -6.0), 2.2)


## Achterbahn starten und bis kurz vor die Kuppe vorspulen — die POV-Kamera
## (coaster.starte_fahrt) übernimmt ab hier automatisch.
func _fahrt() -> void:
	if park.rig != null:
		park.rig.visible = false
	var coaster: Node3D = park.coaster
	coaster.starte_fahrt()
	var guard := 0
	while coaster.zone_jetzt() != "crest" and guard < 3600:
		coaster.simuliere(1.0 / 60.0)
		guard += 1
	print("[funkelpark] Vorlauf: %d Frames bis zone=%s" % [guard, coaster.zone_jetzt()])
	# Hände hoch, sobald der Drop ansteht (zählt in drop/loop/photo/hills).
	schedule(t + 1.6, func() -> void: coaster.set_hands_up(true))
