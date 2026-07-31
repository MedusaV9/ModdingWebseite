extends TestCase
## W13B — Stadtleben-Polish (Doc E §1.4/§1.5): Ziel-Chevron-Mathe
## (Screen-Space-Platzierung am Schirmrand + Pin-Tipp-Auswahl, beides pur)
## und Near-Miss-Funken (NUR bei echtem Near-Miss, Reduced-Motion
## respektiert, one-shot GPUParticles3D mit Selbst-Aufräumen).

const SCHIRM := Vector2(1000.0, 600.0)
const RAND := 36.0

## ---------------------------------------------------------- Chevron-Mathe


func test_chevron_ziel_rechts_ausserhalb() -> void:
	var lage := DriveHud.chevron_platzierung(SCHIRM, Vector2(2000.0, 300.0), false, RAND)
	assert_true(lage["sichtbar"])
	assert_almost((lage["pos"] as Vector2).x, 1000.0 - RAND, 1e-4, "am rechten Rand")
	assert_almost((lage["pos"] as Vector2).y, 300.0, 1e-4)
	assert_almost(float(lage["winkel"]), 0.0, 1e-6, "Keil zeigt nach rechts")


func test_chevron_ziel_oben_ausserhalb() -> void:
	var lage := DriveHud.chevron_platzierung(SCHIRM, Vector2(500.0, -100.0), false, RAND)
	assert_true(lage["sichtbar"])
	assert_almost((lage["pos"] as Vector2).x, 500.0, 1e-4)
	assert_almost((lage["pos"] as Vector2).y, RAND, 1e-4, "am oberen Rand")
	assert_almost(float(lage["winkel"]), -PI / 2.0, 1e-6, "Keil zeigt nach oben")


func test_chevron_diagonale_klemmt_an_kante() -> void:
	# Richtung (600, 600): die y-Kante klemmt zuerst (264/600 < 464/600).
	var lage := DriveHud.chevron_platzierung(SCHIRM, Vector2(1100.0, 900.0), false, RAND)
	assert_true(lage["sichtbar"])
	assert_almost((lage["pos"] as Vector2).x, 764.0, 1e-4)
	assert_almost((lage["pos"] as Vector2).y, 564.0, 1e-4)
	assert_almost(float(lage["winkel"]), PI / 4.0, 1e-6)


func test_chevron_ziel_im_bild_ist_unsichtbar() -> void:
	var lage := DriveHud.chevron_platzierung(SCHIRM, Vector2(500.0, 300.0), false, RAND)
	assert_false(lage["sichtbar"], "Ziel im Bild braucht keinen Pfeil")


func test_chevron_hinter_der_kamera_spiegelt() -> void:
	# Ziel „rechts hinter mir“: unproject liefert (700, 300), hinter=true →
	# gespiegelt (300, 300) → der Keil zeigt nach LINKS an den linken Rand.
	var lage := DriveHud.chevron_platzierung(SCHIRM, Vector2(700.0, 300.0), true, RAND)
	assert_true(lage["sichtbar"], "hinter der Kamera ist IMMER ein Pfeil nötig")
	assert_almost((lage["pos"] as Vector2).x, RAND, 1e-4, "am linken Rand")
	assert_almost((lage["pos"] as Vector2).y, 300.0, 1e-4)
	assert_almost(absf(float(lage["winkel"])), PI, 1e-6, "Keil zeigt nach links")


func test_chevron_degeneriert_ziel_auf_mitte() -> void:
	var lage := DriveHud.chevron_platzierung(SCHIRM, SCHIRM * 0.5, true, RAND)
	assert_true(lage["sichtbar"])
	assert_almost(float(lage["winkel"]), PI / 2.0, 1e-6, "Fallback-Richtung = unten")


func test_naechster_pin_tipp_auswahl() -> void:
	var pins := [
		{"id": "rehwei", "px": Vector2(10.0, 10.0)},
		{"id": "post", "px": Vector2(100.0, 10.0)},
	]
	assert_eq(DriveHud.naechster_pin(pins, Vector2(12.0, 11.0), 18.0), "rehwei")
	assert_eq(DriveHud.naechster_pin(pins, Vector2(96.0, 14.0), 18.0), "post")
	assert_eq(DriveHud.naechster_pin(pins, Vector2(55.0, 10.0), 18.0), "", "zu weit weg")
	var gleichstand := [
		{"id": "a", "px": Vector2(10.0, 10.0)},
		{"id": "b", "px": Vector2(10.0, 10.0)},
	]
	assert_eq(
		DriveHud.naechster_pin(gleichstand, Vector2(10.0, 10.0), 18.0),
		"a",
		"Gleichstand: erster gewinnt"
	)


## ------------------------------------------------------ Near-Miss-Funken


func test_funken_nur_bei_near_miss() -> void:
	# CityAmbiente.ist_beinahe: Abstand ≤ 7 m UND |Tempo| ≥ 4 m/s.
	assert_true(NearMissFunken.soll_funken(6.9, 5.0, false), "echter Near-Miss sprüht")
	assert_false(NearMissFunken.soll_funken(7.1, 5.0, false), "zu weit weg: keine Funken")
	assert_false(NearMissFunken.soll_funken(6.9, 3.9, false), "zu langsam: keine Funken")
	assert_false(NearMissFunken.soll_funken(6.9, 5.0, true), "Reduced-Motion: Hupe ja, Funken nein")


func test_funkenpunkt_liegt_in_der_mitte() -> void:
	var punkt := NearMissFunken.funkenpunkt(Vector3(0.0, 0.0, 0.0), Vector3(2.0, 0.0, 4.0))
	assert_almost(punkt.x, 1.0, 1e-6)
	assert_almost(punkt.y, NearMissFunken.FUNKEN_HOEHE_M, 1e-6, "Stoßstangen-Höhe")
	assert_almost(punkt.z, 2.0, 1e-6)


func test_funken_spawn_one_shot_und_aufraeumen() -> void:
	var wurzel := Node3D.new()
	tree.root.add_child(wurzel)
	var punkt := Vector3(1.0, NearMissFunken.FUNKEN_HOEHE_M, 2.0)
	var funken := NearMissFunken.spawne(wurzel, punkt)
	assert_true(funken is GPUParticles3D)
	assert_true(funken.one_shot, "one-shot: sprüht genau einmal")
	assert_true(funken.emitting)
	assert_eq(funken.position, punkt)
	assert_true(
		funken.finished.is_connected(funken.queue_free), "räumt sich nach dem Ausbrennen weg"
	)
	wurzel.queue_free()
	await wait_frames(1)
