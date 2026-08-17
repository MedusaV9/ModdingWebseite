extends TestCase
## WELT-1 — Höhenmodell des Ausbaus: echtes Bergmassiv (Gipfel ~90 m,
## flaches Plateau, Bergsee mit eigenem Spiegel, Schlucht mit Steilwänden
## und tragendem Brückendeck), Moor-Pfannen bleiben watbar, die Bucht
## liegt unter Wasser, Großformen bleiben aus dem alten Kern draußen,
## und der Weltrand läuft weich in die Fernwiese aus.


func test_bergmassiv_hat_echte_hoehe() -> void:
	var zone := RanchKarte.zone("bergmassiv")
	var gipfel: Array = zone["gipfel"]
	var oben := RanchGelaende.hoehe(float(gipfel[0]), float(gipfel[1]))
	assert_true(oben > 70.0, "Gipfel ist hochalpin (%.1f m)" % oben)
	assert_true(
		oben > RanchGelaende.hoehe(0.0, 0.0) + 60.0, "Gipfel weit über dem Hof (%.1f m)" % oben
	)


func test_plateau_ist_flach_mit_rundumblick() -> void:
	var zone := RanchKarte.zone("bergmassiv")
	var mitte: Array = zone["plateau_mitte"]
	var basis := float(zone["hoehe_basis"])
	for versatz: Vector2 in [Vector2(0, 0), Vector2(30, 12), Vector2(-26, -20), Vector2(12, 34)]:
		var h := RanchGelaende.hoehe(float(mitte[0]) + versatz.x, float(mitte[1]) + versatz.y)
		assert_almost(h, basis, 1.2, "Plateau eben bei %s" % versatz)


func test_bergsee_hat_eigenen_spiegel() -> void:
	var zone := RanchKarte.zone("bergmassiv")
	var mitte: Array = zone["bergsee_mitte"]
	var grund := RanchGelaende.hoehe(float(mitte[0]), float(mitte[1]))
	var spiegel := float(zone["bergsee_wasser"])
	assert_true(grund < spiegel - 1.5, "Seegrund unter dem Spiegel (%.1f)" % grund)
	assert_true(RanchGelaende.ist_wasser(float(mitte[0]), float(mitte[1])), "Bergsee = Wasser")
	var ufer_x := float(mitte[0]) - float(zone["bergsee_radius"]) - 8.0
	assert_false(RanchGelaende.ist_wasser(ufer_x, float(mitte[1])), "Ufer bleibt begehbar")


func test_schlucht_ist_tief_mit_brueckendeck() -> void:
	var bruecke: Dictionary = RanchKarte.bruecken()[0]
	var a: Array = bruecke["a"]
	var b: Array = bruecke["b"]
	var mx := (float(a[0]) + float(b[0])) / 2.0
	var mz := (float(a[1]) + float(b[1])) / 2.0
	var sohle := RanchGelaende.hoehe(mx, mz)
	var deck := RanchGelaende.reit_hoehe(mx, mz)
	assert_true(deck - sohle > 8.0, "Deck trägt über der Sohle (%.1f m)" % (deck - sohle))
	var anker_a := RanchGelaende.hoehe(float(a[0]), float(a[1]))
	assert_true(absf(deck - anker_a) < 2.0, "Deck etwa auf Anker-Höhe (%.1f)" % deck)
	# Neben der Brücke gilt weiter die Bodenhöhe.
	var frei_x := mx + 30.0
	assert_almost(
		RanchGelaende.reit_hoehe(frei_x, mz),
		RanchGelaende.hoehe(frei_x, mz),
		0.001,
		"reit_hoehe == hoehe abseits des Decks"
	)


func test_serpentine_ist_begehbar_bis_zum_plateau() -> void:
	var punkte := RanchKarte.wegpunkte("huegelkamm", "bergmassiv")
	assert_true(punkte.size() >= 8, "Serpentine hat viele Kehren (%d)" % punkte.size())
	var start := RanchGelaende.hoehe(punkte[0].x, punkte[0].z)
	var ende := RanchGelaende.hoehe(punkte[punkte.size() - 1].x, punkte[punkte.size() - 1].z)
	assert_true(ende - start > 30.0, "Serpentine steigt wirklich auf (%.1f m)" % (ende - start))
	for p in punkte:
		assert_true(RanchKarte.ist_begehbar(p), "Kehre (%.0f, %.0f) begehbar" % [p.x, p.z])


func test_moor_bleibt_watbar() -> void:
	var zone := RanchKarte.zone("moor")
	for paar: Array in zone["tuempel"]:
		var h := RanchGelaende.hoehe(float(paar[0]), float(paar[1]))
		assert_true(h < 0.0, "Tümpel (%s) ist eine nasse Delle (%.2f)" % [paar, h])
		assert_true(
			h > RanchGelaende.WASSER_HOEHE - 0.05, "Tümpel (%s) bleibt watbar (%.2f)" % [paar, h]
		)


func test_bucht_liegt_unter_wasser() -> void:
	var zone := RanchKarte.zone("strand")
	var mitte: Array = zone["bucht_mitte"]
	assert_true(
		RanchGelaende.hoehe(float(mitte[0]), float(mitte[1])) < RanchGelaende.WASSER_HOEHE - 1.0,
		"Buchtgrund unter Wasser"
	)
	assert_true(RanchGelaende.ist_wasser(float(mitte[0]), float(mitte[1])), "Bucht = Wasser")


func test_grossformen_bleiben_aus_dem_kern_draussen() -> void:
	# Im alten Kern-Rechteck ist die Großform-Maske 0 — Bestandszonen
	# behalten exakt ihr Profil.
	for p: Vector2 in [Vector2(0, 0), Vector2(-380, 90), Vector2(160, -510), Vector2(500, 270)]:
		assert_almost(RanchGelaende.grossform_maske(p.x, p.y), 0.0, 0.0001, "Maske 0 bei %s" % p)
	assert_true(RanchGelaende.grossform_maske(-950.0, 800.0) > 0.9, "Maske greift weit draußen")


func test_weltrand_laeuft_weich_aus() -> void:
	var grenzen := RanchKarte.grenzen()
	for p: Vector2 in [
		Vector2(grenzen.end.x - 4.0, 0.0),
		Vector2(0.0, grenzen.end.y - 4.0),
		Vector2(grenzen.position.x + 4.0, -400.0),
	]:
		var h := RanchGelaende.hoehe(p.x, p.y)
		assert_almost(h, RanchGelaende.RAND_ZIEL_M, 0.5, "Rand ~Fernwiesen-Höhe bei %s" % p)


func test_mehrstufiges_rauschen_ist_aktiv() -> void:
	# Großformen + Grundhügel + Feinstruktur: draußen im Neuland gibt es
	# deutlich mehr Relief als ±3-m-Grundhügel allein.
	var minimum := INF
	var maximum := -INF
	for x in range(-950, 951, 60):
		for z in range(660, 941, 40):
			var h := RanchGelaende.hoehe(float(x), float(z))
			minimum = minf(minimum, h)
			maximum = maxf(maximum, h)
	assert_true(maximum - minimum > 7.0, "Neuland-Relief (min %.1f, max %.1f)" % [minimum, maximum])
	assert_true(RanchGelaende.feinstruktur(333.3, 777.7) != 0.0, "Feinstruktur liefert")
