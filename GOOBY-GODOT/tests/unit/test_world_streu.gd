extends TestCase
## FB-2 — Streu-Bibliothek (WeltStreu): deterministisch, hält Mindest-
## abstände und Sperrflächen ein, clustert statt gleichzuverteilen, und
## die Ranch-/Stadt-Anwendungen meiden Wege, Plateaus und Fundorte.

const RECT := Rect2(-200.0, -200.0, 400.0, 400.0)


func test_streuung_ist_deterministisch() -> void:
	var regeln := {"rect": RECT, "anzahl": 60, "min_abstand": 4.0}
	var a := WeltStreu.verteile(regeln, 1234)
	var b := WeltStreu.verteile(regeln, 1234)
	assert_eq(a.size(), b.size(), "gleiche Anzahl")
	for i in a.size():
		assert_eq(a[i], b[i], "Transform %d identisch" % i)
	var anders := WeltStreu.verteile(regeln, 99)
	assert_true(anders.size() == 0 or anders[0] != a[0], "anderer Seed = andere Streuung")


func test_min_abstand_wird_eingehalten() -> void:
	var transforms := WeltStreu.verteile({"rect": RECT, "anzahl": 120, "min_abstand": 6.0}, 42)
	assert_true(transforms.size() > 60, "genug Instanzen (%d)" % transforms.size())
	for i in transforms.size():
		for j in range(i + 1, transforms.size()):
			var a := Vector2(transforms[i].origin.x, transforms[i].origin.z)
			var b := Vector2(transforms[j].origin.x, transforms[j].origin.z)
			if a.distance_to(b) < 6.0 - 0.001:
				fail_test("Instanzen %d/%d zu nah: %.2f m" % [i, j, a.distance_to(b)])
				return


func test_sperrflaechen_und_wege_bleiben_frei() -> void:
	var sperr_rect := Rect2(-50.0, -50.0, 100.0, 100.0)
	var regeln := {
		"rect": RECT,
		"anzahl": 150,
		"meide_rects": [sperr_rect] as Array[Rect2],
		"meide_kreise": [{"mitte": Vector2(120.0, 120.0), "radius": 30.0}] as Array[Dictionary],
		"meide_segmente":
		(
			[{"a": Vector2(-200.0, 80.0), "b": Vector2(200.0, 80.0), "abstand": 8.0}]
			as Array[Dictionary]
		),
	}
	for t: Transform3D in WeltStreu.verteile(regeln, 7):
		var p := Vector2(t.origin.x, t.origin.z)
		assert_false(sperr_rect.has_point(p), "Sperr-Rect frei (%s)" % p)
		assert_true(p.distance_to(Vector2(120.0, 120.0)) >= 30.0, "Sperr-Kreis frei (%s)" % p)
		assert_true(absf(p.y - 80.0) >= 8.0, "Weg-Band frei (%s)" % p)


func test_cluster_statt_gleichverteilung() -> void:
	var regeln := {
		"rect": RECT, "anzahl": 90, "cluster": {"anzahl": 4, "radius": 18.0}, "min_abstand": 1.5
	}
	var transforms := WeltStreu.verteile(regeln, 314)
	assert_true(transforms.size() > 40, "genug Instanzen (%d)" % transforms.size())
	# Cluster-Beleg: der mittlere Nachbarabstand ist DEUTLICH kleiner als
	# bei Gleichverteilung derselben Anzahl in derselben Fläche.
	var summe := 0.0
	for i in transforms.size():
		var best := INF
		for j in transforms.size():
			if i == j:
				continue
			best = minf(
				best,
				Vector2(transforms[i].origin.x, transforms[i].origin.z).distance_to(
					Vector2(transforms[j].origin.x, transforms[j].origin.z)
				)
			)
		summe += best
	var mittel := summe / float(transforms.size())
	var gleichverteilt := 0.5 * sqrt(RECT.size.x * RECT.size.y / float(transforms.size()))
	assert_true(
		mittel < gleichverteilt * 0.6,
		"geclustert (Nachbarabstand %.1f m < %.1f m)" % [mittel, gleichverteilt * 0.6]
	)


func test_skala_und_hoehe_regeln() -> void:
	var regeln := {
		"rect": RECT,
		"anzahl": 40,
		"skala_min": 2.0,
		"skala_max": 3.0,
		"hoehe_fn": func(x: float, _z: float) -> float: return 20.0 if x > 0.0 else 0.0,
		"hoehe_min": 10.0,
		"einsenken": -0.5,
	}
	var transforms := WeltStreu.verteile(regeln, 5)
	assert_true(transforms.size() > 10, "genug Instanzen (%d)" % transforms.size())
	for t: Transform3D in transforms:
		assert_true(t.origin.x > 0.0, "nur die hohe Seite erlaubt")
		assert_almost(t.origin.y, 19.5, 0.001, "Bodenhöhe + einsenken")
		var skala := t.basis.get_scale().x
		assert_true(skala >= 2.0 - 0.001 and skala <= 3.0 + 0.001, "Skala im Band (%.2f)" % skala)


func test_ranch_streu_meidet_wege_plateaus_fundorte_wasser() -> void:
	var plaene := RanchStreu.plaene(1.0)
	assert_true(plaene.size() >= 10, "alle Sorten geplant (%d)" % plaene.size())
	var segmente := WeltStreu.weg_segmente(RanchKarte.wege(), RanchStreu.WEG_FREI_M)
	var hof_rect := RanchKarte.zone_rect(RanchKarte.zone("hof")).grow(6.0)
	var gesamt := 0
	for plan: Dictionary in plaene:
		for t: Transform3D in plan["transforms"]:
			gesamt += 1
			var p := Vector2(t.origin.x, t.origin.z)
			assert_false(hof_rect.has_point(p), "Hof-Plateau frei (%s)" % p)
			assert_false(RanchGelaende.ist_wasser(p.x, p.y), "kein Baum im Wasser (%s)" % p)
			for eintrag: Dictionary in RanchEntdeckungen.ORTE:
				var fundort := RanchEntdeckungen.position_von(eintrag)
				assert_true(
					p.distance_to(fundort) >= RanchStreu.FUNDORT_FREI_M - 0.001,
					"Fundort %s bleibt frei (%s)" % [eintrag["id"], p]
				)
			for segment: Dictionary in segmente:
				if (
					WeltStreu.segment_abstand(p, segment["a"], segment["b"])
					< (float(segment["abstand"]) - 0.001)
				):
					fail_test("Streu auf dem Weg bei %s" % p)
					return
	assert_true(gesamt > 600, "Region wirklich dicht bestreut (%d Instanzen)" % gesamt)


func test_dichte_faktor_regelt_herunter() -> void:
	var voll := 0
	for plan: Dictionary in RanchStreu.plaene(1.0):
		voll += (plan["transforms"] as Array[Transform3D]).size()
	var halb := 0
	for plan: Dictionary in RanchStreu.plaene(0.4):
		halb += (plan["transforms"] as Array[Transform3D]).size()
	assert_true(halb < voll * 0.6, "Qualitäts-Faktor reduziert die Dichte (%d → %d)" % [voll, halb])


func test_stadt_gruen_meidet_strassen_und_ist_deterministisch() -> void:
	var karte := CityMap.laden()
	var a := CityGruen.plaene(karte, 11)
	var b := CityGruen.plaene(karte, 11)
	assert_eq(a.size(), b.size(), "deterministisch (Anzahl)")
	assert_true(a.size() > 150, "Stadt wirklich begrünt (%d Einträge)" % a.size())
	for i in mini(a.size(), 25):
		assert_eq(a[i]["pos"], b[i]["pos"], "deterministisch (Eintrag %d)" % i)
	var baeume := 0
	for eintrag: Dictionary in a:
		if str(eintrag["glb"]) == CityGruen.STRASSENBAUM_GLB:
			baeume += 1
			var tile := karte.welt_zu_tile(eintrag["pos"])
			assert_false(karte.ist_strasse(tile), "Straßenbaum steht NEBEN der Fahrbahn")
	assert_true(baeume > 20, "genug Straßenbäume (%d)" % baeume)
