extends TestCase
## UICOZY: UiMotion-Mikro-Animations-Bibliothek — Endzustände, Web-Paritäts-
## Konstanten und Reduced-Motion-Sofortsprünge (Haupt-Runner, TestCase-Stil).


func _host() -> Control:
	var host := Control.new()
	host.size = Vector2(200.0, 100.0)
	tree.root.add_child(host)
	return host


func test_count_to_zaehlt_statt_zu_springen() -> void:
	var host := _host()
	var label := Label.new()
	label.text = "0"
	host.add_child(label)
	var tween := UiMotion.count_to(label, 0, 300)
	if tween == null:
		# Reduced-Motion-Lauf: Sofortsprung ist das korrekte Verhalten.
		assert_eq(label.text, "300", "Reduced Motion → Zielwert sofort")
		host.free()
		return
	assert_eq(label.text, "0", "startet beim Alt-Wert statt zu springen")
	var done := await wait_until(func() -> bool: return label.text == "300", 3000)
	assert_true(done, "zählt bis 300 hoch (%s)" % UiMotion.COUNT_SEC)
	host.free()


func test_count_to_gleicher_wert_springt_sofort() -> void:
	var host := _host()
	var label := Label.new()
	label.text = "7"
	host.add_child(label)
	var tween := UiMotion.count_to(label, 7, 7)
	assert_true(tween == null, "gleicher Wert → kein Tween")
	assert_eq(label.text, "7", "Text bleibt gesetzt")
	host.free()


func test_bar_to_gleitet_weich() -> void:
	var host := _host()
	var bar := ProgressBar.new()
	bar.max_value = 100.0
	bar.value = 100.0
	host.add_child(bar)
	var tween := UiMotion.bar_to(bar, 40.0)
	if tween == null:
		assert_almost(bar.value, 40.0, 0.001, "Reduced Motion → Wert sofort")
		host.free()
		return
	assert_almost(bar.value, 100.0, 0.001, "direkt nach Aufruf noch Alt-Wert (gleitet)")
	var done := await wait_until(func() -> bool: return absf(bar.value - 40.0) < 0.01, 3000)
	assert_true(done, "erreicht den Zielwert (Web .stat-fill 300 ms)")
	assert_almost(UiMotion.BAR_SEC, 0.3, 0.001, "Web-Paritäts-Dauer 300 ms")
	host.free()


func test_pop_bounce_wiggle_enden_neutral() -> void:
	var host := _host()
	var card := Panel.new()
	card.size = Vector2(80.0, 40.0)
	host.add_child(card)
	UiMotion.pop_in(card)
	UiMotion.bounce(card)
	UiMotion.wiggle(card)
	var settled := await wait_until(
		func() -> bool:
			return (
				card.scale.is_equal_approx(Vector2.ONE)
				and absf(card.rotation) < 0.001
				and card.modulate.a > 0.999
			),
		3000
	)
	assert_true(settled, "Scale/Rotation/Alpha landen neutral (1/0/1)")
	host.free()


func test_attach_hover_verbindet_nur_einmal() -> void:
	var host := _host()
	var card := Panel.new()
	host.add_child(card)
	UiMotion.attach_hover(card)
	UiMotion.attach_hover(card)
	assert_eq(card.mouse_entered.get_connections().size(), 1, "Doppel-Attach → nur EINE Verbindung")
	host.free()


func test_sparkle_partikel_raeumen_sich_auf() -> void:
	var host := _host()
	await tree.process_frame
	var before := host.get_child_count()
	UiMotion.sparkle(host)
	if ThemeService.is_reduced_motion(host):
		assert_eq(host.get_child_count(), before, "Reduced Motion → kein Glitzer")
		host.free()
		return
	assert_eq(host.get_child_count(), before + UiMotion.SPARKLE_COUNT, "Sterne gespawnt")
	var cleaned := await wait_until(func() -> bool: return host.get_child_count() == before, 4000)
	assert_true(cleaned, "alle Sparkles freen sich selbst")
	host.free()


func test_reduced_motion_springt_sofort() -> void:
	var svc := tree.root.get_node_or_null("/root/UiTheme")
	if svc == null or not ("reduced_motion" in svc):
		return  # isolierter Lauf ohne Autoload — Verhalten deckt UiMotion.reduced ab
	var vorher: bool = svc.reduced_motion
	svc.reduced_motion = true
	var host := _host()
	var label := Label.new()
	host.add_child(label)
	assert_true(UiMotion.count_to(label, 0, 42) == null, "Reduced → kein Tween")
	assert_eq(label.text, "42", "Reduced → Zielwert sofort")
	var bar := ProgressBar.new()
	bar.max_value = 100.0
	bar.value = 100.0
	host.add_child(bar)
	assert_true(UiMotion.bar_to(bar, 10.0) == null, "Reduced → kein Balken-Tween")
	assert_almost(bar.value, 10.0, 0.001, "Reduced → Balken springt")
	svc.reduced_motion = vorher
	host.free()
