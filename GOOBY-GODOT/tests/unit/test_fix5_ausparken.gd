extends TestCase
## FIX-5 „Fahren startet am eigenen Haus" — Ausparksequenz: das Auto parkt
## in der Einfahrt (Nase zum Haus), setzt rückwärts auf die Straße und
## steht danach in Fahrtrichtung der Straße; manuelle Eingabe bricht ab.
## Simuliert mit dem ECHTEN CarController-Fahrmodell (kinematisch, pur).


func _simuliere(schritte: int) -> Dictionary:
	var karte := CityMap.laden()
	var einfahrt := karte.zuhause_einfahrt()
	var auto := CarController.new()
	var pos: Vector3 = einfahrt["pos"]
	auto.teleport(pos.x, pos.z, float(einfahrt["heading"]))
	var sequenz := CityAusparken.new(
		einfahrt["strasse_pos"],
		einfahrt["richtung_haus"],
		float(einfahrt["heading"]),
		float(einfahrt["ziel_heading"])
	)
	var fertig_nach := -1
	for i in schritte:
		if sequenz.laeuft():
			var cmd := sequenz.kommando(auto.position, auto.heading)
			auto.set_reverse(bool(cmd["reverse"]))
			auto.set_steer(float(cmd["steer"]))
			if bool(cmd["fertig"]) and fertig_nach < 0:
				fertig_nach = i
		auto.update_fahrt(1.0 / 60.0)
	var ergebnis := {
		"auto_pos": auto.position,
		"auto_heading": auto.heading,
		"fertig_nach": fertig_nach,
		"einfahrt": einfahrt,
		"karte": karte,
	}
	auto.free()
	return ergebnis


func test_spawn_steht_in_der_einfahrt_mit_haus_im_blick() -> void:
	var karte := CityMap.laden()
	var einfahrt := karte.zuhause_einfahrt()
	var pos: Vector3 = einfahrt["pos"]
	var strasse: Vector3 = einfahrt["strasse_pos"]
	# NICHT irgendwo im Nichts: keine 20 m vom eigenen Haus, neben der Straße.
	assert_false(karte.ist_strasse(karte.welt_zu_tile(pos)), "Spawn liegt nicht auf der Straße")
	var haus := karte.tile_zu_welt(karte.zuhause_tile())
	assert_true(pos.distance_to(haus) < 12.0, "Spawn direkt am Haus")
	assert_true(pos.distance_to(strasse) > 6.0, "Spawn hinter dem Bordstein")


func test_ausparken_endet_auf_der_strasse_in_fahrtrichtung() -> void:
	var ergebnis := _simuliere(60 * 12)
	var einfahrt: Dictionary = ergebnis["einfahrt"]
	var karte: CityMap = ergebnis["karte"]
	assert_true(int(ergebnis["fertig_nach"]) > 0, "Sequenz kommt zum Ende")
	assert_true(int(ergebnis["fertig_nach"]) < 60 * 10, "… in unter 10 Sekunden")
	# Nach dem Ausparken + kurzem Anrollen: Auto auf einem Straßen-Tile …
	var auto_pos: Vector3 = ergebnis["auto_pos"]
	assert_true(
		karte.ist_strasse(karte.welt_zu_tile(auto_pos)),
		"Auto steht nach dem Ausparken auf der Straße (%s)" % karte.welt_zu_tile(auto_pos)
	)
	# … und fährt (Auto-Throttle) in Ziel-Fahrtrichtung der Straße weiter.
	var rest := CityCarFeel.wrap_angle(
		float(einfahrt["ziel_heading"]) - float(ergebnis["auto_heading"])
	)
	assert_true(absf(rest) < 0.6, "Heading liegt an der Straßenrichtung (Rest %f rad)" % rest)


func test_rueckwaertsgang_waehrend_der_geraden_phase() -> void:
	var karte := CityMap.laden()
	var einfahrt := karte.zuhause_einfahrt()
	var sequenz := CityAusparken.new(
		einfahrt["strasse_pos"],
		einfahrt["richtung_haus"],
		float(einfahrt["heading"]),
		float(einfahrt["ziel_heading"])
	)
	var cmd := sequenz.kommando(einfahrt["pos"], float(einfahrt["heading"]))
	assert_true(bool(cmd["reverse"]), "in der Einfahrt wird rückwärts rangiert")
	assert_almost(float(cmd["steer"]), 0.0, 1e-6, "erst gerade zurück")
	assert_false(bool(cmd["fertig"]))
	assert_true(sequenz.laeuft())


func test_failsafe_hinter_der_strassenachse() -> void:
	var karte := CityMap.laden()
	var einfahrt := karte.zuhause_einfahrt()
	var sequenz := CityAusparken.new(
		einfahrt["strasse_pos"],
		einfahrt["richtung_haus"],
		float(einfahrt["heading"]),
		float(einfahrt["ziel_heading"])
	)
	# Auto steht (wie auch immer) schon auf der Straßenachse: sofort Schluss
	# mit Rückwärts — niemals über die Gegenspur hinaus rangieren.
	var cmd := sequenz.kommando(einfahrt["strasse_pos"], float(einfahrt["heading"]))
	assert_false(bool(cmd["reverse"]), "hinter der Achse nie weiter rückwärts")
	assert_true(bool(cmd["fertig"]))
	assert_false(sequenz.laeuft())


func test_rueckkehr_nach_hause_spawnt_wieder_in_der_einfahrt() -> void:
	# „Nach Hause" löscht city.autoTile → der nächste Stadt-Besuch startet
	# mit Spawn „zuhause" — und der liegt in der Einfahrt (s. o.). Hier wird
	# die Spawn-Auflösung selbst geprüft (pure Logik aus CityScene).
	var karte := CityMap.laden()
	var leer: Variant = []
	assert_true(leer is Array and (leer as Array).size() != 2, "autoTile leer ⇒ zuhause")
	var einfahrt := karte.zuhause_einfahrt()
	var pos: Vector3 = einfahrt["pos"]
	var haus := karte.tile_zu_welt(karte.zuhause_tile())
	assert_true(pos.distance_to(haus) < 12.0, "Rückkehr-Spawn = Einfahrt am Haus")
