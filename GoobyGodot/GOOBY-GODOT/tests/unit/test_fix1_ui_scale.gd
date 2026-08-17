extends TestCase
## FIX1 P0 „UI ist meist falsch skaliert“: die zentrale Skalierungs-Regel
## `UiScale` — kurze Kante + physischer Retina-Faktor — bei den drei
## iPhone-Viewports aus dem Bug-Report, plus Safe-Area-Klemmung.

## Canvas-Größen, die das Projekt-Stretch (1280×720, canvas_items+expand)
## aus den iPhone-Fenstern macht: quer bleibt die kurze Kante 720,
## hoch wird die kurze Kante 1280 (E5-F2).
const CANVAS_IPHONE_11_QUER := Vector2(1558.3, 720.0)  # Fenster 1792×828 @2x
const CANVAS_IPHONE_15PM_QUER := Vector2(1560.9, 720.0)  # Fenster 2556×1179 @3x
const CANVAS_IPHONE_11_HOCH := Vector2(1280.0, 2770.4)  # Fenster 828×1792 @2x


func test_for_canvas_koppelt_an_die_kurze_kante() -> void:
	# Querformat: kurze Kante = Design-Basis 720 → Faktor 1 (Canvas-Anteil).
	assert_almost(UiScale.for_canvas(CANVAS_IPHONE_11_QUER), 1.0, 1e-4, "quer 1792×828")
	assert_almost(UiScale.for_canvas(CANVAS_IPHONE_15PM_QUER), 1.0, 1e-4, "quer 2556×1179")
	# Hochkant: kurze Kante 1280 → 1280/720 ≈ 1,778.
	assert_almost(UiScale.for_canvas(CANVAS_IPHONE_11_HOCH), 1280.0 / 720.0, 1e-4, "hoch 828×1792")
	# Guards: nie unter 1, Deckel gegen Absurd-Werte, 0-Canvas crasht nicht.
	assert_almost(UiScale.for_canvas(Vector2(320, 240)), 1.0, 1e-6, "kleine Fenster: min 1")
	assert_almost(
		UiScale.for_canvas(Vector2(9999, 9999)), UiScale.MAX_CANVAS_FACTOR, 1e-6, "Deckel"
	)
	assert_almost(UiScale.for_canvas(Vector2.ZERO), 1.0, 1e-6, "0-Canvas → 1")


func test_physical_factor_retina_querformat() -> void:
	# DER Kern des Skalierungs-Bugs: iPhone 11 quer (1792×828 @2× → 414
	# Punkte kurze Kante). 1 Design-px braucht 720/414 ≈ 1,74 Canvas-px,
	# um PHYSISCH so groß zu sein wie in der Web-Referenz.
	var f11 := UiScale.physical_factor(CANVAS_IPHONE_11_QUER, Vector2(1792, 828), 2.0)
	assert_almost(f11, 720.0 / 414.0, 1e-4, "iPhone 11 quer @2x")
	var f15 := UiScale.physical_factor(CANVAS_IPHONE_15PM_QUER, Vector2(2556, 1179), 3.0)
	assert_almost(f15, 720.0 / 393.0, 1e-4, "iPhone 15 Pro Max quer @3x")
	# Desktop (scale 1, Fenster 1280×720): kein Aufblasen.
	assert_almost(
		UiScale.physical_factor(Vector2(1280, 720), Vector2(1280, 720), 1.0), 1.0, 1e-6, "Desktop"
	)
	# Guards: kaputte Eingaben → neutral 1.
	var basis := Vector2(1280, 720)
	assert_almost(UiScale.physical_factor(basis, Vector2.ZERO, 2.0), 1.0, 1e-6, "0-Fenster")
	assert_almost(UiScale.physical_factor(basis, Vector2(1792, 828), 0.0), 1.0, 1e-6, "scale 0")


func test_clamp_insets_deckelt_kaputte_safe_area() -> void:
	var canvas := Vector2(1558.0, 720.0)
	# Realistische iPhone-Notch (59/21 px) bleibt unangetastet.
	var echt := UiScale.clamp_insets(
		{"left": 59.0, "top": 0.0, "right": 59.0, "bottom": 21.0}, canvas
	)
	assert_almost(float(echt["left"]), 59.0, 1e-6, "echte Notch bleibt")
	assert_almost(float(echt["bottom"]), 21.0, 1e-6, "Home-Indicator bleibt")
	# Pathologische Werte (xvfb: Fenster größer als der virtuelle Screen)
	# werden pro Achse auf MAX_INSET_SHARE gedeckelt — vorher wanderte das
	# halbe HUD aus dem Bild.
	var kaputt := UiScale.clamp_insets(
		{"left": 900.0, "top": 500.0, "right": -12.0, "bottom": 999.0}, canvas
	)
	assert_almost(
		float(kaputt["left"]), canvas.x * UiScale.MAX_INSET_SHARE, 1e-4, "links gedeckelt"
	)
	assert_almost(float(kaputt["top"]), canvas.y * UiScale.MAX_INSET_SHARE, 1e-4, "oben gedeckelt")
	assert_almost(float(kaputt["right"]), 0.0, 1e-6, "negativ → 0")
	assert_almost(
		float(kaputt["bottom"]), canvas.y * UiScale.MAX_INSET_SHARE, 1e-4, "unten gedeckelt"
	)


func test_safe_insets_canvas_mit_override_am_echten_viewport() -> void:
	var host := Control.new()
	tree.root.add_child(host)
	var vp := host.get_viewport()
	var canvas := Vector2(vp.get_visible_rect().size)
	# Notch-Simulation (Override in Canvas-Koordinaten, wie die HUD-Tests).
	var override := Rect2(59.0, 0.0, canvas.x - 118.0, canvas.y - 21.0)
	var insets := UiScale.safe_insets_canvas(vp, override)
	assert_almost(float(insets["left"]), 59.0, 1e-4, "Override links")
	assert_almost(float(insets["right"]), 59.0, 1e-4, "Override rechts")
	assert_almost(float(insets["bottom"]), 21.0, 1e-4, "Override unten")
	# Ohne Override (headless): alles 0 — Desktop-Verhalten.
	var ohne := UiScale.safe_insets_canvas(vp)
	for side in ["left", "top", "right", "bottom"]:
		assert_almost(float(ohne[side]), 0.0, 1e-6, "headless ohne Notch: %s" % side)
	host.queue_free()
	await wait_frames(1)
