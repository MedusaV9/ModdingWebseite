extends TestCase
## VIS-2, Trailer-Review 0:17: „Die Namensschilder über den Gebäuden in der
## Stadt (z. B. ‚Wochenmarkt') sind extrem klein und durch die Perspektive
## kaum lesbar.“ Fix: OrtSchild (Label3D-Billboard) waechst ab REF_DISTANZ
## mit der Kamera-Entfernung mit (konstante Mindest-Bildschirmgroesse),
## blendet sehr weit weg weich aus und traegt immer eine Kontrast-Tafel.

const EPS := 1e-4


func test_skala_haelt_die_bildschirmgroesse() -> void:
	assert_almost(OrtSchild.skala_fuer_distanz(0.0), 1.0, EPS, "nah: Weltgroesse unveraendert")
	assert_almost(
		OrtSchild.skala_fuer_distanz(OrtSchild.REF_DISTANZ), 1.0, EPS, "REF_DISTANZ = Basis"
	)
	# Kern-Invariante: ab REF_DISTANZ bleibt (Skala / Distanz) konstant —
	# die Schrift unterschreitet ihre Bildschirmgroesse bei REF nie.
	var basis := OrtSchild.skala_fuer_distanz(OrtSchild.REF_DISTANZ) / OrtSchild.REF_DISTANZ
	var d := OrtSchild.REF_DISTANZ
	while d <= OrtSchild.REF_DISTANZ * OrtSchild.SKALA_MAX:
		assert_almost(
			OrtSchild.skala_fuer_distanz(d) / d,
			basis,
			EPS,
			"Bildschirmgroesse konstant bei %.0f m" % d
		)
		d += 20.0
	assert_almost(
		OrtSchild.skala_fuer_distanz(9999.0),
		OrtSchild.SKALA_MAX,
		EPS,
		"Mitwachsen ist gedeckelt (keine Riesen-Schilder)"
	)


func test_alpha_blendet_ferne_schilder_aus() -> void:
	assert_almost(OrtSchild.alpha_fuer_distanz(0.0), 1.0, EPS, "nah voll sichtbar")
	assert_almost(
		OrtSchild.alpha_fuer_distanz(OrtSchild.FADE_START), 1.0, EPS, "bis FADE_START voll"
	)
	var mitte := (OrtSchild.FADE_START + OrtSchild.FADE_ENDE) * 0.5
	assert_almost(OrtSchild.alpha_fuer_distanz(mitte), 0.5, EPS, "Mitte = halb")
	assert_almost(OrtSchild.alpha_fuer_distanz(OrtSchild.FADE_ENDE), 0.0, EPS, "ab FADE_ENDE weg")
	var vorher := 1.0
	var d := OrtSchild.FADE_START
	while d <= OrtSchild.FADE_ENDE:
		var a := OrtSchild.alpha_fuer_distanz(d)
		assert_true(a <= vorher + EPS, "Alpha faellt monoton (%.0f m)" % d)
		vorher = a
		d += 10.0


func test_schild_waechst_im_baum_mit_der_kamera_distanz() -> void:
	var kamera := Camera3D.new()
	tree.root.add_child(kamera)
	kamera.current = true
	var schild := OrtSchild.new()
	schild.text = "Wochenmarkt"
	schild.font_size = 150
	schild.pixel_size = 0.013
	tree.root.add_child(schild)
	await wait_frames(1)
	schild.position = Vector3(0.0, 0.0, -120.0)
	await wait_frames(2)
	assert_almost(
		schild.pixel_size,
		0.013 * OrtSchild.skala_fuer_distanz(120.0),
		1e-5,
		"pixel_size waechst mit der Distanz (120 m)"
	)
	assert_true(schild.visible, "bei 120 m sichtbar")
	schild.position = Vector3(0.0, 0.0, -(OrtSchild.FADE_ENDE + 20.0))
	await wait_frames(2)
	assert_false(schild.visible, "hinter FADE_ENDE ausgeblendet statt Pixelbrei")
	schild.queue_free()
	kamera.queue_free()
	await wait_frames(1)


func test_kontrast_tafel_haengt_am_schild_und_skaliert_mit() -> void:
	var kamera := Camera3D.new()
	tree.root.add_child(kamera)
	kamera.current = true
	var schild := OrtSchild.new()
	schild.text = "Wochenmarkt"
	schild.font_size = 150
	schild.pixel_size = 0.013
	tree.root.add_child(schild)
	await wait_frames(1)
	schild.setze_tafel(Color(1.0, 0.97, 0.9, 0.85), 0.25, true)
	var tafel: MeshInstance3D = schild.get_node("SchildTafel")
	assert_ne(tafel, null, "Tafel existiert")
	assert_true(tafel.mesh is QuadMesh, "Tafel ist ein einzelner Quad (Mobil-Budget)")
	var quad: QuadMesh = tafel.mesh
	var text_breite := float(schild.text.length()) * float(schild.font_size) * 0.013
	assert_true(quad.size.x > text_breite * 0.6, "Tafel ist so breit wie die Schrift")
	schild.position = Vector3(0.0, 0.0, -120.0)
	await wait_frames(2)
	assert_almost(
		tafel.scale.x, OrtSchild.skala_fuer_distanz(120.0), 1e-4, "Tafel skaliert mit dem Schild"
	)
	# Nacht-Variante ersetzt die Tages-Tafel, statt eine zweite zu stapeln.
	schild.setze_tafel(Color(1.0, 0.8, 0.4, 1.0), 1.1)
	await wait_frames(1)
	var tafeln := 0
	for kind in schild.get_children():
		if kind.name.begins_with("SchildTafel"):
			tafeln += 1
	assert_eq(tafeln, 1, "genau EINE Tafel pro Schild")
	schild.queue_free()
	kamera.queue_free()
	await wait_frames(1)
