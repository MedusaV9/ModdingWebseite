extends TestCase
## GOOBY-WELT/STADT — Funkelpark-Deko-Planer (EVAL-2026-08 B §4 „wirkt wie
## eine Whitebox"): Zaun umschließt den Park mit Tor-Lücke, der Plaza-Weg
## bleibt ein Schachbrett mit Fehlstellen, Wimpel hängen durch, Konfetti/
## Ballons folgen Seed + Palette und das Wiesen-Grün meidet Wege und
## Fahrgeschäft-Zonen.


func test_zaun_umschliesst_den_park_mit_torluecke() -> void:
	var posten := ParkDeko.zaun_posten()
	assert_true(posten.size() > 40, "dichter Pfosten-Ring")
	for p in posten:
		var am_rand := (
			is_equal_approx(p.x, ParkDeko.ZAUN_MIN.x)
			or is_equal_approx(p.x, ParkDeko.ZAUN_MAX.x)
			or is_equal_approx(p.z, ParkDeko.ZAUN_MIN.y)
			or is_equal_approx(p.z, ParkDeko.ZAUN_MAX.y)
		)
		assert_true(am_rand, "Pfosten liegt auf dem Zaun-Rechteck")
		if is_equal_approx(p.z, ParkDeko.ZAUN_MAX.y):
			assert_true(absf(p.x) > ParkDeko.ZAUN_TOR_X, "Tor-Lücke bleibt frei")


func test_zaun_riegel_verbinden_nur_nachbarn() -> void:
	var posten := ParkDeko.zaun_posten()
	var riegel := ParkDeko.zaun_riegel(posten)
	assert_true(riegel.size() > posten.size() * 8 / 10, "fast jeder Pfosten hat einen Riegel")
	for t in riegel:
		assert_true(
			t.basis.z.length() <= ParkDeko.ZAUN_SCHRITT_M * 1.3 + 1e-3,
			"Riegel nur zwischen Nachbar-Pfosten"
		)
		assert_almost(t.basis.x.length(), 1.0, 1e-4, "quer bleibt Einheitsmaß")
		if is_equal_approx(t.origin.z, ParkDeko.ZAUN_MAX.y):
			assert_true(absf(t.origin.x) > ParkDeko.ZAUN_TOR_X, "kein Riegel quer durchs Tor")


func test_weg_platten_schachbrett_mit_fehlstellen() -> void:
	var platten := ParkDeko.weg_platten(7)
	assert_eq(platten, ParkDeko.weg_platten(7), "Seed ⇒ deterministisch")
	var raster_x := int(ParkDeko.WEG_HALB.x * 2.0 / ParkDeko.PLATTE_M)
	var raster_z := int(ParkDeko.WEG_HALB.y * 2.0 / ParkDeko.PLATTE_M)
	var voll := raster_x * raster_z
	assert_true(platten.size() < voll, "Fehlstellen brechen das perfekte Raster")
	assert_true(platten.size() > voll * 8 / 10, "aber der Weg bleibt weitgehend gepflastert")
	for platte: Dictionary in platten:
		var pos: Vector3 = platte["pos"]
		var rel_x := (pos.x - ParkDeko.WEG_MITTE.x + ParkDeko.WEG_HALB.x) / ParkDeko.PLATTE_M
		var rel_z := (pos.z - ParkDeko.WEG_MITTE.y + ParkDeko.WEG_HALB.y) / ParkDeko.PLATTE_M
		var ix := int(roundf(rel_x - 0.5))
		var iz := int(roundf(rel_z - 0.5))
		assert_eq(bool(platte["hell"]), (ix + iz) % 2 == 0, "Schachbrett-Wechsel stimmt")


func test_wimpel_haengen_zwischen_den_masten() -> void:
	var alle := ParkDeko.alle_wimpel()
	assert_true(alle.size() >= ParkDeko.WIMPEL_KETTEN.size() * 3, "jede Kette trägt Wimpel")
	for kette: Dictionary in ParkDeko.WIMPEL_KETTEN:
		var von: Vector3 = kette["von"]
		var bis: Vector3 = kette["bis"]
		for w: Dictionary in ParkDeko.wimpel_dreiecke(kette, 0):
			var pos: Vector3 = w["pos"]
			assert_true(pos.y <= maxf(von.y, bis.y) + 1e-4, "Wimpel hängen, sie schweben nicht")
			assert_true(ParkDeko.WIMPEL_FARBEN.has(w["farbe"]), "Wimpel-Palette eingehalten")
	var kette0: Dictionary = ParkDeko.WIMPEL_KETTEN[0]
	var dreiecke := ParkDeko.wimpel_dreiecke(kette0, 0)
	var mitte: Vector3 = dreiecke[dreiecke.size() / 2]["pos"]
	var von0: Vector3 = kette0["von"]
	var bis0: Vector3 = kette0["bis"]
	assert_true(mitte.y < ((von0 + bis0) * 0.5).y, "Durchhang in Kettenmitte")


func test_konfetti_und_ballons_folgen_seed_und_palette() -> void:
	var konfetti := ParkDeko.konfetti(11)
	assert_eq(konfetti.size(), 90, "Standard-Menge")
	assert_eq(konfetti, ParkDeko.konfetti(11), "gleicher Seed ⇒ gleiche Tupfer")
	assert_ne(konfetti, ParkDeko.konfetti(12), "anderer Seed ⇒ andere Tupfer")
	for tupfer: Dictionary in konfetti:
		var pos: Vector3 = tupfer["pos"]
		assert_true(absf(pos.x - ParkDeko.WEG_MITTE.x) <= ParkDeko.WEG_HALB.x, "auf dem Weg (x)")
		assert_true(absf(pos.z - ParkDeko.WEG_MITTE.y) <= ParkDeko.WEG_HALB.y, "auf dem Weg (z)")
		assert_true(ParkDeko.KONFETTI_FARBEN.has(tupfer["farbe"]), "Konfetti-Palette")
	var ballons := ParkDeko.ballons(3)
	assert_eq(ballons.size(), ParkDeko.BALLON_FARBEN.size(), "jede Ballonfarbe genau einmal")
	for ballon: Dictionary in ballons:
		var off: Vector3 = ballon["off"]
		assert_true(off.y >= 2.5, "Ballons schweben über dem Wagen")


func test_wiesen_gruen_meidet_wege_und_fahrgeschaefte() -> void:
	var gruen := ParkDeko.wiesen_gruen(5)
	assert_false(gruen.is_empty(), "es wächst etwas auf der Wiese")
	assert_eq(gruen, ParkDeko.wiesen_gruen(5), "Seed ⇒ deterministisch")
	for tupfe: Dictionary in gruen:
		assert_false(ParkDeko._liegt_frei(tupfe["pos"]), "nie auf Weg oder Fahrgeschäft")
		var pfad := CityBau.glb_pfad(str(tupfe["glb"]))
		assert_true(ResourceLoader.exists(pfad), "Grün-Asset %s existiert" % pfad)
		var groesse := float(tupfe["scale"])
		assert_true(groesse >= 2.0 and groesse <= 3.2, "Skalen-Jitter im Fenster")


func test_lichterketten_ueberspannen_den_park() -> void:
	var punkte := ParkDeko.lichter_punkte()
	assert_eq(punkte.size(), 54, "Portal + Naschgasse + Karussell + Arena + Zaunlinie")
	for p in punkte:
		assert_true(p.y >= 2.0, "Lichter hängen über Kopfhöhe")
		assert_true(absf(p.x) <= 30.0 and p.z >= -32.0 and p.z <= 20.0, "im Parkgelände")
