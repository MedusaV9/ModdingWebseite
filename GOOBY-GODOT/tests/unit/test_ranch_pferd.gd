extends TestCase
## RANCH-1 — das Gooby-Pferd: Gangarten (Idle/Trab/Galopp — User-Pflicht),
## Beinanimation bewegt sich wirklich, und der RANCH-2-Modell-VERTRAG
## (RANCH2-needs.md §2): set_farbe/set_gait/tick/head_pivot/equip/
## body_height/phase. Blickrichtung -z, Boden bei y=0.


func _mount() -> RanchPferd:
	var pferd := RanchPferd.neu(Color("#D9A066"), Color("#8A5A33"))
	tree.root.add_child(pferd)
	await wait_frames(1)
	return pferd


func _cleanup(pferd: RanchPferd) -> void:
	pferd.queue_free()
	await wait_frames(1)


func test_gangarten_umschalten() -> void:
	var pferd := await _mount()
	assert_eq(pferd.gangart, RanchPferd.GANG_IDLE, "Start = Idle")
	pferd.set_gangart(RanchPferd.GANG_TRAB)
	assert_eq(pferd.gangart, RanchPferd.GANG_TRAB)
	pferd.set_gangart("quatsch")
	assert_eq(pferd.gangart, RanchPferd.GANG_TRAB, "unbekannte Gangart ignoriert")
	pferd.set_gangart(RanchPferd.GANG_GALOPP)
	assert_eq(pferd.gangart, RanchPferd.GANG_GALOPP)
	await _cleanup(pferd)


func test_beine_bewegen_sich_im_trab() -> void:
	var pferd := await _mount()
	pferd.set_gangart(RanchPferd.GANG_TRAB)
	var beine: Array[Node3D] = pferd._beine
	assert_eq(beine.size(), 4, "vier Beine")
	var maximal := 0.0
	for _i in 30:
		pferd.update_gang(1.0 / 60.0)
		maximal = maxf(maximal, absf(beine[0].rotation.x))
	assert_true(maximal > 0.1, "Beine schwingen im Trab (max %.3f rad)" % maximal)
	# Diagonalpaar: vorn-links (0) und hinten-rechts (3) laufen synchron.
	assert_almost(beine[0].rotation.x, beine[3].rotation.x, 0.001, "Diagonalpaar synchron")
	assert_almost(beine[0].rotation.x, -beine[1].rotation.x, 0.001, "Gegenpaar spiegelt")
	await _cleanup(pferd)


func test_ranch2_vertrag_gaits_und_masse() -> void:
	var pferd := await _mount()
	pferd.set_gait("galopp")
	assert_eq(pferd.gangart, RanchPferd.GANG_GALOPP, "RANCH-2-Id galopp")
	pferd.set_gait("stand")
	assert_eq(pferd.gangart, RanchPferd.GANG_IDLE, "stand → Idle")
	pferd.set_gait("schritt")
	assert_eq(pferd.gangart, RanchPferd.GANG_SCHRITT, "schritt vorhanden")
	assert_ne(pferd.head_pivot(), null, "head_pivot liefert den Kopf")
	assert_true(pferd.body_height() > 1.0, "Sitzhoehe plausibel")
	var vorher := pferd.phase()
	pferd.tick(0.25, 2.0)
	assert_ne(pferd.phase(), vorher, "tick treibt die Phase")
	await _cleanup(pferd)


func test_ranch2_vertrag_equip_und_farbe() -> void:
	var pferd := await _mount()
	pferd.equip("sattel", "rot")
	assert_ne(pferd.get_node_or_null("Gear_sattel"), null, "Sattel haengt am Pferd")
	pferd.equip("halfter", "blau")
	assert_ne(pferd.head_pivot().get_node_or_null("Gear_halfter"), null, "Halfter haengt am Kopf")
	pferd.equip("sattel", null)
	await wait_frames(1)
	assert_eq(pferd.get_node_or_null("Gear_sattel"), null, "null = abnehmen")
	pferd.set_farbe("weiss")
	assert_eq(pferd.farbe, RanchPferd.FELL["weiss"][0], "Fellfarbe per Id")
	await wait_frames(1)
	assert_ne(pferd.head_pivot(), null, "Umbau haelt den Vertrag (Kopf da)")
	assert_ne(
		pferd.head_pivot().get_node_or_null("Gear_halfter"), null, "Gear ueberlebt den Farb-Umbau"
	)
	await _cleanup(pferd)
