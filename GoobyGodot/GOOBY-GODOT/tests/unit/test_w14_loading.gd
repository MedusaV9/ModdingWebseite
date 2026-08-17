extends TestCase
## W14/LOADING — Boot-Cover-Screen + Veil-Politur: Phasen→Prozent-Mapping
## (pur), deterministische Spruch-Rotation, Cover-Crop-Mathe (Quer/Hochkant/
## Zoom-Deckel + Randfarbe aus dem Bild), Reduced-Motion-Pfade und die
## Ehrlichkeits-Regel des Möhren-Balkens (Anzeige nie vor dem echten Ziel).

const VEIL_SCENE := preload("res://scripts/core/loading_veil.tscn")


func test_phasen_prozente_monoton_und_geklemmt() -> void:
	var ids := BootPhasen.phasen_ids()
	assert_eq(ids, ["packs", "save", "welt", "einrichten", "zuhause"] as Array[String])
	var vorher := 0.0
	for id in ids:
		var ende := BootPhasen.prozent(id, 1.0)
		assert_true(ende > vorher, "Phasen-Enden steigen streng: %s" % id)
		assert_true(
			BootPhasen.prozent(id, 0.0) >= vorher - 1e-6,
			"Phasen-Start = Ende der Vorphase: %s" % id
		)
		vorher = ende
	assert_almost(BootPhasen.prozent("zuhause", 1.0), 1.0, 1e-6, "Letzte Phase endet bei 1.0.")
	assert_almost(BootPhasen.prozent("gibtsnicht", 1.0), 0.0, 1e-6, "Unbekannte Phase → 0.")
	assert_almost(
		BootPhasen.prozent("welt", 2.5),
		BootPhasen.prozent("welt", 1.0),
		1e-6,
		"Sub-Fortschritt wird auf 0..1 geklemmt."
	)
	assert_almost(BootPhasen.prozent("welt", -1.0), BootPhasen.prozent("welt", 0.0), 1e-6)


func test_phasen_sub_interpolation() -> void:
	var start := BootPhasen.prozent("save", 1.0)
	var ende := BootPhasen.prozent("welt", 1.0)
	var mitte := BootPhasen.prozent("welt", 0.5)
	assert_almost(mitte, (start + ende) / 2.0, 1e-6, "Sub interpoliert linear in der Phase.")
	assert_true(mitte > start and mitte < ende, "Sub bleibt in der Phasen-Spanne.")


func test_router_sub_meilensteine_monoton() -> void:
	# SceneRouter.State: IDLE=0, COVER=1, SWAP=2, WAIT_READY=3, REVEAL=4.
	var vorher := -1.0
	for state: int in [0, 1, 2, 3, 4]:
		var sub := BootPhasen.zuhause_sub_fuer_router_state(state)
		assert_true(sub > vorher, "Router-Meilensteine steigen: State %d" % state)
		assert_true(sub <= 1.0, "Sub bleibt ≤ 1.")
		vorher = sub
	assert_almost(BootPhasen.zuhause_sub_fuer_router_state(99), 0.0, 1e-6, "Unbekannt → 0.")


func test_spruch_rotation_deterministisch() -> void:
	var a := BootPhasen.spruch_reihenfolge(10, 42)
	var b := BootPhasen.spruch_reihenfolge(10, 42)
	assert_eq(a, b, "Gleicher Seed → gleiche Reihenfolge.")
	assert_ne(
		BootPhasen.spruch_reihenfolge(10, 1),
		BootPhasen.spruch_reihenfolge(10, 2),
		"Verschiedene Seeds mischen verschieden."
	)
	var sortiert := a.duplicate()
	sortiert.sort()
	assert_eq(sortiert, [0, 1, 2, 3, 4, 5, 6, 7, 8, 9] as Array[int], "Echte Permutation.")


func test_spruch_rotation_runden_und_randfaelle() -> void:
	for anzahl: int in [3, 10]:
		var gesehen: Dictionary = {}
		var vorher := -1
		for schritt in anzahl * 4:
			var index := BootPhasen.spruch_index(schritt, anzahl, 7)
			assert_true(index >= 0 and index < anzahl, "Index im Bereich.")
			assert_ne(index, vorher, "Nie derselbe Spruch zweimal hintereinander.")
			vorher = index
			var runde := schritt / anzahl
			if not gesehen.has(runde):
				gesehen[runde] = {}
			assert_false(gesehen[runde].has(index), "Kein Spruch doppelt in einer Runde.")
			gesehen[runde][index] = true
	assert_eq(BootPhasen.spruch_index(0, 0, 7), -1, "Keine Sprüche → -1.")
	assert_eq(BootPhasen.spruch_index(0, 1, 7), 0, "Ein Spruch → immer 0.")
	assert_eq(BootPhasen.spruch_index(5, 1, 7), 0, "Ein Spruch wiederholt 0.")


func test_boot_sprueche_10_de_en_paritaetisch() -> void:
	I18nService.reset_cache()
	var de: Array = _tabelle_pfad(I18nService.table("de"))
	var en: Array = _tabelle_pfad(I18nService.table("en"))
	assert_eq(de.size(), 10, "10 deutsche Boot-Sprüche.")
	assert_eq(en.size(), de.size(), "EN paritätisch.")
	for spruch: Variant in de + en:
		assert_true(str(spruch).length() > 8, "Spruch ist ein echter Satz: %s" % str(spruch))


func test_cover_crop_quer() -> void:
	var layout := BootPhasen.cover_layout(Vector2(1280, 720), Vector2(1920, 1080))
	var rect: Rect2 = layout["rect"]
	assert_false(layout["gedeckelt"], "16:9 auf 16:9: kein Deckel.")
	assert_almost(rect.position.x, 0.0, 0.5, "Querformat füllt exakt.")
	assert_almost(rect.position.y, 0.0, 0.5)
	assert_almost(rect.size.x, 1280.0, 0.5)
	assert_almost(rect.size.y, 720.0, 0.5)


func test_cover_crop_hochkant_fokus_auf_gooby() -> void:
	var viewport := Vector2(720, 1280)
	var layout := BootPhasen.cover_layout(viewport, Vector2(1920, 1080))
	var rect: Rect2 = layout["rect"]
	assert_false(layout["gedeckelt"], "9:16 bleibt unter dem sanften Zoom-Deckel.")
	# Deckt voll (keine Balken): Kanten außerhalb oder auf dem Viewport-Rand.
	assert_true(rect.position.x <= 0.5 and rect.end.x >= viewport.x - 0.5, "Deckt horizontal.")
	assert_true(rect.position.y <= 0.5 and rect.end.y >= viewport.y - 0.5, "Deckt vertikal.")
	var fokus: Vector2 = layout["fokus_px"]
	assert_almost(fokus.x, viewport.x / 2.0, 0.5, "Gooby-Fokus sitzt horizontal mittig.")
	assert_true(fokus.y >= 0.0 and fokus.y <= viewport.y, "Fokus bleibt im sichtbaren Bereich.")


func test_cover_crop_fokus_zieht_keine_kante_rein() -> void:
	# Fokus hart am Bildrand: das Fenster klemmt, statt Lücken zu zeigen.
	var viewport := Vector2(720, 1280)
	var layout := BootPhasen.cover_layout(viewport, Vector2(1920, 1080), Vector2(0.02, 0.5))
	var rect: Rect2 = layout["rect"]
	assert_true(rect.position.x <= 0.5 and rect.end.x >= viewport.x - 0.5, "Keine Lücke links.")
	assert_almost(rect.position.x, 0.0, 0.5, "Fenster klemmt an der linken Bildkante.")


func test_cover_crop_deckel_und_randfarbe_aus_bild() -> void:
	# Extremes Hochformat: der sanfte Zoom-Deckel greift → Ränder bleiben,
	# und die füllt die Randfarbe AUS dem Bild (nie schwarze Balken).
	var viewport := Vector2(500, 2200)
	var layout := BootPhasen.cover_layout(viewport, Vector2(1920, 1080))
	var rect: Rect2 = layout["rect"]
	assert_true(layout["gedeckelt"], "Zoom-Deckel greift bei extremem Format.")
	assert_true(rect.size.y < viewport.y - 1.0, "Vertikale Ränder bleiben (gedeckelt).")
	assert_almost(rect.position.y, (viewport.y - rect.size.y) / 2.0, 0.5, "Gedeckelt → mittig.")
	var img := Image.create_empty(16, 16, false, Image.FORMAT_RGB8)
	img.fill(Color(0.5, 0.25, 0.125))
	var farbe := BootPhasen.randfarbe(img)
	assert_almost(farbe.r, 0.5, 0.02, "Randfarbe kommt aus dem Bild (R).")
	assert_almost(farbe.g, 0.25, 0.02, "Randfarbe kommt aus dem Bild (G).")
	assert_almost(farbe.b, 0.125, 0.02, "Randfarbe kommt aus dem Bild (B).")
	assert_eq(BootPhasen.randfarbe(null), BootPhasen.RANDFARBE_FALLBACK, "Kein Bild → Fallback.")


func test_wipe_variante_reduced_motion() -> void:
	assert_eq(BootPhasen.wipe_variante(true), "fade", "Reduced Motion → schlichter Fade.")
	assert_eq(BootPhasen.wipe_variante(false), "kreis", "Sonst Kreis-Wipe auf Gooby.")


func test_ladebalken_zeigt_nie_mehr_als_geladen() -> void:
	var balken := BootLadebalken.new()
	tree.root.add_child(balken)
	await wait_frames(1)
	balken.set_progress(0.8)
	assert_true(balken.anzeige_wert() <= 0.8 + 1e-6, "Anzeige nie vor dem echten Ziel.")
	await wait_frames(3)
	assert_true(balken.anzeige_wert() <= 0.8 + 1e-6, "Auch nach Frames nie voraus.")
	assert_true(balken.anzeige_wert() > 0.0, "Anzeige holt sichtbar auf.")
	balken.set_progress(2.0)
	assert_almost(balken.get_progress(), 1.0, 1e-6, "Ziel wird geklemmt.")
	balken.set_animated(false)
	assert_almost(balken.anzeige_wert(), 1.0, 1e-6, "Reduced Motion springt aufs Ziel.")
	balken.queue_free()
	await wait_frames(1)


func test_boot_cover_screen_smoke_und_reduced_fade() -> void:
	var cover := BootCoverScreen.new()
	cover.spruch_seed = 7
	tree.root.add_child(cover)
	await wait_frames(1)
	assert_eq(cover.layer, 120, "Cover liegt ÜBER dem LoadingVeil (100).")
	var sprueche := I18nService.items(BootCoverScreen.SPRUECHE_KEY)
	var erwartet := str(sprueche[BootPhasen.spruch_index(0, sprueche.size(), 7)])
	assert_eq(cover.spruch_text(), erwartet, "Erster Spruch folgt der Seed-Rotation.")
	cover.set_progress(0.42)
	assert_almost(cover.get_progress(), 0.42, 1e-6, "Fortschritt wird durchgereicht.")
	cover.set_progress(-3.0)
	assert_almost(cover.get_progress(), 0.0, 1e-6, "Clamp unten.")
	var geoeffnet: Array = []
	cover.geoeffnet.connect(func() -> void: geoeffnet.append(true))
	await cover.oeffne(true)
	assert_false(cover.visible, "Reduced-Motion-Fade blendet das Cover aus.")
	assert_eq(geoeffnet.size(), 1, "geoeffnet feuert genau einmal.")
	await cover.oeffne(true)
	assert_eq(geoeffnet.size(), 1, "Doppel-Öffnen bleibt still (idempotent).")
	cover.queue_free()
	await wait_frames(1)


## W16/VEIL: Der Indeterminate-Sweep (Web .mg-loading-bar-indet) ersetzt
## die W14-Punkte — die Regel bleibt dieselbe: nie zwei Ladeanzeigen
## gleichzeitig, und Reduced Motion friert die Deko-Animation ein.
func test_veil_sweep_weicht_dem_echten_balken() -> void:
	var veil: LoadingVeil = VEIL_SCENE.instantiate()
	tree.root.add_child(veil)
	await wait_frames(1)
	var sweep: LoadingVeilSweep = veil.find_child("Sweep", true, false)
	assert_true(sweep != null, "Indeterminate-Sweep hängt in der Karte.")
	assert_true(sweep.visible, "Ohne Balken ist der Sweep da.")
	veil.set_progress(0.5)
	assert_false(sweep.visible, "Echter Balken sichtbar → Sweep weicht.")
	veil.set_progress(1.0)
	assert_true(sweep.visible, "Balken weg → Sweep wieder da.")
	await veil.cover(true)
	assert_false(sweep.is_animated(), "Reduced Motion: Sweep steht still.")
	await veil.reveal(true)
	await veil.cover(false)
	assert_true(sweep.is_animated(), "Animierter Pfad: Sweep wischt.")
	await veil.reveal(false)
	assert_false(sweep.is_animated(), "Nach reveal ruht der Sweep.")
	veil.queue_free()
	await wait_frames(1)


func _tabelle_pfad(tabelle: Dictionary) -> Array:
	var wert: Variant = tabelle.get(BootCoverScreen.SPRUECHE_KEY, [])
	return wert if wert is Array else []
