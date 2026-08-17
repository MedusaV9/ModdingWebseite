extends TestCase
## W4-P3 POLISH-6 — Kamera-Framing (pure Statics in HomeCameraRig): die
## Distanz folgt dem Viewport-Aspekt, damit der Raum das Bild in Hochkant
## UND Quer ordentlich füllt (User-Wunsch „Handy-Platz nutzen“).

const QUER := 16.0 / 9.0
const HOCHKANT := 9.0 / 19.5
const WOHNZIMMER := Vector2(6.0, 5.0)
const BAD := Vector2(4.0, 3.5)


func test_quer_sieht_den_ganzen_raum() -> void:
	var d := HomeCameraRig.follow_distanz(WOHNZIMMER, QUER)
	var sichtbar := HomeCameraRig.sichtbreite(d, QUER)
	assert_true(sichtbar >= WOHNZIMMER.x, "Sichtbreite %f deckt Raumbreite" % sichtbar)
	assert_true(sichtbar <= WOHNZIMMER.x * 1.8, "aber nicht winzig im Bild")


func test_hochkant_zoomt_naeher_ans_geschehen() -> void:
	var d := HomeCameraRig.follow_distanz(WOHNZIMMER, HOCHKANT)
	var sichtbar := HomeCameraRig.sichtbreite(d, HOCHKANT)
	assert_true(
		sichtbar >= HomeCameraRig.MIN_SICHTBREITE_HOCHKANT - 1e-6,
		"Mindest-Sichtbreite gehalten (%f)" % sichtbar
	)
	assert_true(sichtbar < WOHNZIMMER.x, "Hochkant zeigt einen Ausschnitt, nicht Leere")


func test_kleiner_raum_kleinere_distanz() -> void:
	assert_true(
		HomeCameraRig.follow_distanz(BAD, QUER) < HomeCameraRig.follow_distanz(WOHNZIMMER, QUER),
		"Bad rückt näher ran als Wohnzimmer"
	)


func test_baumodus_zeigt_das_ganze_grid_in_beiden_lagen() -> void:
	for aspekt: float in [QUER, HOCHKANT, 1.0]:
		var d := HomeCameraRig.build_distanz(WOHNZIMMER, aspekt)
		var sichtbar := HomeCameraRig.sichtbreite(d, aspekt)
		var tan_y := tan(deg_to_rad(HomeCameraRig.FOV_Y * 0.5))
		var pitch := atan2(HomeCameraRig.BUILD_OFFSET.y, HomeCameraRig.BUILD_OFFSET.z)
		var sichthoehe := 2.0 * d * tan_y
		var d_max := HomeCameraRig.DIST_MAX
		if d < d_max - 1e-6:
			assert_true(
				sichtbar >= WOHNZIMMER.x, "Aspekt %f: Breite passt (%f)" % [aspekt, sichtbar]
			)
			assert_true(
				sichthoehe >= WOHNZIMMER.y * sin(pitch),
				"Aspekt %f: Tiefe passt (%f)" % [aspekt, sichthoehe]
			)


func test_front_sichtweite_clamp_haelt_die_raumkante_im_bild() -> void:
	# Hochkant-Wohnzimmer: Pivot ganz vorn (z = Raumtiefe) würde ~2 m Leere
	# unter der Raumkante zeigen — der Front-Clamp muss also greifen.
	var d := HomeCameraRig.follow_distanz(WOHNZIMMER, HOCHKANT)
	var front := HomeCameraRig.front_sichtweite(d)
	assert_true(front > 0.0, "unterer Frustum-Rand liegt vor dem Pivot (%f)" % front)
	assert_true(WOHNZIMMER.y - front < WOHNZIMMER.y, "Clamp-Limit liegt vor der Raum-Vorderkante")
	# Näher dran = weniger Vorlauf: die Sichtweite wächst mit der Distanz.
	assert_true(
		HomeCameraRig.front_sichtweite(d) > HomeCameraRig.front_sichtweite(d * 0.5),
		"Front-Sichtweite skaliert mit der Distanz"
	)


func test_distanzen_bleiben_geclampt() -> void:
	var winzig := HomeCameraRig.follow_distanz(Vector2(1.0, 1.0), QUER)
	var riesig := HomeCameraRig.follow_distanz(Vector2(60.0, 60.0), HOCHKANT)
	assert_true(winzig >= HomeCameraRig.DIST_MIN, "nie näher als DIST_MIN")
	assert_true(riesig <= HomeCameraRig.DIST_MAX, "nie weiter als DIST_MAX")
	var kaputt := HomeCameraRig.follow_distanz(WOHNZIMMER, 0.0)
	assert_true(
		kaputt >= HomeCameraRig.DIST_MIN and kaputt <= HomeCameraRig.DIST_MAX, "Aspekt 0 geclampt"
	)
