extends TestCase
## FB-2 — Gelände-Feinstruktur: der Boden ist nicht mehr glatt (spürbare
## Bodenwellen im freien Land), bleibt aber auf Wegen/Plateaus reitbar.
## Die Höhenabfrage RanchGelaende.hoehe ENTHÄLT die Feinstruktur — Reiter
## und Tiere „spüren" die Unebenheit ohne eigene Zusatzabfrage.


func test_feinstruktur_ist_begrenzt_und_deterministisch() -> void:
	var maximum := 0.0
	for x in range(-600, 601, 37):
		for z in range(-600, 601, 41):
			var fein := RanchGelaende.feinstruktur(float(x), float(z))
			maximum = maxf(maximum, absf(fein))
			assert_true(
				absf(fein) <= RanchGelaende.FEIN_MAX_M + 0.001,
				"Feinstruktur klein bei %d/%d" % [x, z]
			)
	assert_true(maximum > 0.2, "Feinstruktur wirklich spürbar (max %.2f m)" % maximum)
	assert_eq(
		RanchGelaende.feinstruktur(211.5, -77.25),
		RanchGelaende.feinstruktur(211.5, -77.25),
		"deterministisch"
	)


func test_hoehe_enthaelt_feinstruktur_im_freien_land() -> void:
	# Kurze zweite Differenzen (2-m-Schritt) im freien Land: die groben
	# Hügel (~100 m Wellenlänge) sind dafür fast linear — messbare
	# Krümmung kommt aus der FEINSTRUKTUR. Vor FB-2 war das ~0.
	var max_kruemmung := 0.0
	for i in 60:
		var x := -540.0 + float(i) * 6.5
		var z := -120.0
		if RanchGelaende.weg_glaettung(x, z) < 0.99:
			continue
		var h0 := RanchGelaende.hoehe(x - 2.0, z)
		var h1 := RanchGelaende.hoehe(x, z)
		var h2 := RanchGelaende.hoehe(x + 2.0, z)
		max_kruemmung = maxf(max_kruemmung, absf(h0 - 2.0 * h1 + h2))
	assert_true(max_kruemmung > 0.06, "Boden uneben (max Krümmung %.3f m)" % max_kruemmung)


func test_wege_bleiben_glatt() -> void:
	# Auf der Weg-Mitte ist die Feinstruktur fast weg (Rest-Anteil),
	# weit daneben voll da.
	var weg: Dictionary = RanchKarte.wege()[0]
	var a: Array = weg["punkte"][0]
	var b: Array = weg["punkte"][1]
	var mitte := Vector2((float(a[0]) + float(b[0])) / 2.0, (float(a[1]) + float(b[1])) / 2.0)
	var auf_weg := RanchGelaende.weg_glaettung(mitte.x, mitte.y)
	assert_true(
		auf_weg <= RanchGelaende.WEG_REST_ANTEIL + 0.02, "auf dem Weg gedämpft (%.2f)" % auf_weg
	)
	assert_almost(RanchGelaende.weg_glaettung(-590.0, -590.0), 1.0, 0.001, "freies Land voll")


func test_plateaus_bleiben_flach_trotz_feinstruktur() -> void:
	var basis := float(RanchKarte.zone("hof")["hoehe_basis"])
	for pos: Vector2 in [Vector2(0, 0), Vector2(-40, 30), Vector2(55, -25)]:
		assert_almost(
			RanchGelaende.hoehe(pos.x, pos.y), basis, 0.05, "Hof bleibt Bauplateau bei %s" % pos
		)


func test_reitbarkeit_mit_feinstruktur() -> void:
	# Steigung zwischen 2-m-Schritten bleibt reitbar (< 60 %) — auch MIT
	# Bodenwellen keine Stolperklippen.
	var schlimmste := 0.0
	for x in range(-600, 601, 24):
		for z in range(-600, 601, 24):
			var h0 := RanchGelaende.hoehe(float(x), float(z))
			var h1 := RanchGelaende.hoehe(float(x) + 2.0, float(z))
			schlimmste = maxf(schlimmste, absf(h1 - h0) / 2.0)
	assert_true(schlimmste < 0.6, "max. Steigung %.2f" % schlimmste)


func test_bodentextur_flecken_variieren() -> void:
	# Die Fleck-Maske (Grasbüschel/Erdstellen) ist deterministisch und
	# liefert echte Variation: irgendwo 0, irgendwo deutlich > 0.
	var minimum := 1.0
	var maximum := 0.0
	for x in range(-500, 501, 23):
		for z in range(-500, 501, 29):
			var fleck := RanchTerrain._fleck(float(x), float(z), 0.043, 0.037, 1.9)
			minimum = minf(minimum, fleck)
			maximum = maxf(maximum, fleck)
	assert_almost(minimum, 0.0, 0.01, "es gibt fleckenfreie Wiese")
	assert_true(maximum > 0.6, "es gibt satte Flecken (max %.2f)" % maximum)
	assert_eq(
		RanchTerrain._fleck(31.0, -17.0, 0.043, 0.037, 1.9),
		RanchTerrain._fleck(31.0, -17.0, 0.043, 0.037, 1.9),
		"deterministisch"
	)
