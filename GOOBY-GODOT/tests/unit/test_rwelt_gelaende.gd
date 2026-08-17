extends TestCase
## RW-1 — Höhenmodell der Ranch-Region: kein flaches Brett, aber reitbar.
## Hof/Turnierplatz/Hufingen bleiben bebaubare Plateaus, der Hügelkamm
## erhebt sich, der See liegt unter Wasser, das Bachbett ist eingekerbt
## und die Furt bleibt flach genug zum Durchreiten. Alles deterministisch.


func test_hof_plateau_ist_flach_fuer_gebaeude() -> void:
	var basis := float(RanchKarte.zone("hof")["hoehe_basis"])
	for pos: Vector2 in [Vector2(0, 0), Vector2(-46, 24), Vector2(38, -18), Vector2(120, 100)]:
		assert_almost(RanchGelaende.hoehe(pos.x, pos.y), basis, 0.35, "Hof flach bei %s" % pos)


func test_gelaende_ist_kein_flaches_brett() -> void:
	var minimum := INF
	var maximum := -INF
	for x in range(-650, 651, 50):
		for z in range(-600, 601, 50):
			var h := RanchGelaende.hoehe(float(x), float(z))
			minimum = minf(minimum, h)
			maximum = maxf(maximum, h)
	assert_true(maximum - minimum > 10.0, "Relief > 10 m (min %.1f, max %.1f)" % [minimum, maximum])


func test_huegelkamm_liegt_deutlich_hoeher() -> void:
	var zone := RanchKarte.zone("huegelkamm")
	var punkt: Array = zone["aussichtspunkt"]
	var oben := RanchGelaende.hoehe(float(punkt[0]), float(punkt[1]))
	assert_true(oben > 14.0, "Aussichtspunkt hoch (%.1f m)" % oben)
	assert_true(oben > RanchGelaende.hoehe(0.0, 0.0) + 12.0, "höher als der Hof")


func test_see_liegt_unter_wasser() -> void:
	var zone := RanchKarte.zone("see")
	var mitte: Array = zone["see_mitte"]
	var grund := RanchGelaende.hoehe(float(mitte[0]), float(mitte[1]))
	assert_true(grund < RanchGelaende.WASSER_HOEHE - 1.0, "Seegrund unter Wasser (%.1f)" % grund)
	assert_true(RanchGelaende.ist_wasser(float(mitte[0]), float(mitte[1])), "Seemitte = Wasser")


func test_bachbett_ist_eingekerbt_und_furt_flach() -> void:
	var bach: Dictionary = RanchKarte.karte()["bach"]
	var mitte: Array = bach["punkte"][4]
	var bett := RanchGelaende.hoehe(float(mitte[0]), float(mitte[1]))
	var ufer := RanchGelaende.hoehe(float(mitte[0]) + 14.0, float(mitte[1]))
	assert_true(bett < ufer - 0.8, "Bett tiefer als Ufer (%.2f vs %.2f)" % [bett, ufer])
	assert_true(
		RanchGelaende.ist_wasser(float(mitte[0]), float(mitte[1])), "Bachmitte führt Wasser"
	)
	var furt: Array = bach["furt"]
	assert_false(RanchGelaende.ist_wasser(float(furt[0]), float(furt[1])), "Furt seicht + begehbar")
	assert_true(
		RanchGelaende.bach_wasserspiegel(float(mitte[0]), float(mitte[1])) > bett,
		"Wasserspiegel über dem Bett"
	)


func test_gelaende_ist_sanft_reitbar() -> void:
	# Steigung zwischen 2-m-Schritten bleibt unter 60 % — keine Klippen
	# auf Wegen/Weiden (Bachböschung ist die steilste erlaubte Stelle).
	var schlimmste := 0.0
	for x in range(-600, 601, 24):
		for z in range(-600, 601, 24):
			var h0 := RanchGelaende.hoehe(float(x), float(z))
			var h1 := RanchGelaende.hoehe(float(x) + 2.0, float(z))
			schlimmste = maxf(schlimmste, absf(h1 - h0) / 2.0)
	assert_true(schlimmste < 0.6, "max. Steigung %.2f" % schlimmste)


func test_hoehe_ist_deterministisch() -> void:
	assert_eq(
		RanchGelaende.hoehe(123.4, -321.9),
		RanchGelaende.hoehe(123.4, -321.9),
		"gleiche Eingabe = gleiche Höhe"
	)
	var normale := RanchGelaende.normale(120.0, -390.0)
	assert_true(normale.y > 0.5, "Normale zeigt nach oben")
	assert_almost(normale.length(), 1.0, 0.001, "Normale normiert")
