extends TestCase
## POLISH-A: Tests der JuiceKit-Erweiterungen (hit_flash, scale_pop, burst,
## ring_burst, show_combo, edge_glow, confetti, coin_rain, count_to,
## win_moment) — inklusive der Regel, dass Reduced Motion ALLE
## Bewegungs-Effekte weich abschaltet (Töne bleiben, nichts crasht).


## Baut Overlay + Kit; liefert {kit, overlay}. Aufräumen macht _teardown.
func _setup() -> Dictionary:
	var overlay := Control.new()
	overlay.size = Vector2(390, 844)
	tree.root.add_child(overlay)
	var kit := JuiceKit.new()
	kit.float_text_parent = overlay
	tree.root.add_child(kit)
	return {"kit": kit, "overlay": overlay}


func _teardown(env: Dictionary) -> void:
	(env["kit"] as Node).queue_free()
	(env["overlay"] as Node).queue_free()
	Engine.time_scale = 1.0
	await wait_frames(1)


## Schaltet Reduced Motion am ECHTEN AppSettings-Autoload (ein Stub gleichen
## Namens würde vom Autoload verdeckt). Liefert den vorherigen Zustand zurück.
func _set_reduced_motion(enabled: bool) -> bool:
	var settings := tree.root.get_node_or_null("AppSettings")
	if settings == null:
		return false
	var previous := bool(settings.is_reduced_motion())
	settings.set_setting("reduced_motion", enabled)
	return previous


func test_hit_flash_erzeugt_und_entfernt_blitz() -> void:
	var env := _setup()
	var overlay: Control = env["overlay"]
	var kit: JuiceKit = env["kit"]
	await wait_frames(1)
	var before := overlay.get_child_count()
	kit.hit_flash(Color(1, 1, 1, 0.3), 60)
	assert_eq(overlay.get_child_count(), before + 1, "Blitz-Rect hängt im Overlay")
	var gone := await wait_until(func() -> bool: return overlay.get_child_count() == before, 2000)
	assert_true(gone, "Blitz räumt sich selbst auf")
	await _teardown(env)


func test_scale_pop_kehrt_zur_basis_zurueck() -> void:
	var env := _setup()
	var kit: JuiceKit = env["kit"]
	var label := Label.new()
	(env["overlay"] as Control).add_child(label)
	await wait_frames(1)
	kit.scale_pop(label, 1.3, 120)
	kit.scale_pop(label, 1.3, 120)
	var back := await wait_until(
		func() -> bool: return label.scale.is_equal_approx(Vector2.ONE), 2000
	)
	assert_true(back, "Scale federt auf die Basis zurück (auch bei Doppel-Pop)")
	await _teardown(env)


func test_show_combo_waechst_und_verschwindet() -> void:
	var env := _setup()
	var overlay: Control = env["overlay"]
	var kit: JuiceKit = env["kit"]
	await wait_frames(1)
	kit.show_combo(2)
	await wait_frames(1)
	var label := _combo_label(overlay)
	assert_true(label != null, "Combo-Label erscheint ab Stufe 2")
	assert_eq(label.text, "×2")
	var small := label.get_theme_font_size("font_size")
	kit.show_combo(9)
	await wait_frames(1)
	var big := label.get_theme_font_size("font_size")
	assert_true(big > small, "Anzeige wächst mit der Serie (%d → %d)" % [small, big])
	kit.show_combo(0)
	var gone := await wait_until(func() -> bool: return _combo_label(overlay) == null, 2000)
	assert_true(gone, "Serie vorbei → Anzeige blendet aus")
	await _teardown(env)


func test_burst_und_ring_raeumen_sich_auf() -> void:
	var env := _setup()
	var overlay: Control = env["overlay"]
	var kit: JuiceKit = env["kit"]
	await wait_frames(1)
	var before := overlay.get_child_count()
	kit.burst(overlay, Vector2(100, 100), Color.YELLOW, 8)
	kit.ring_burst(overlay, Vector2(100, 100))
	kit.confetti(12)
	kit.coin_rain(6)
	assert_true(overlay.get_child_count() > before, "Partikel/Ringe hängen im Baum")
	var clean := await wait_until(func() -> bool: return overlay.get_child_count() == before, 4000)
	assert_true(clean, "alle Effekte räumen sich selbst auf")
	await _teardown(env)


func test_float_text_ohne_baum_crasht_nicht() -> void:
	# Quickwin #8: Late-Callback nach Szenenwechsel — Kit hängt nicht (mehr)
	# im Baum, der Reduced-Zweig hat dann keinen get_tree().
	var kit := JuiceKit.new()
	kit.float_text(Vector2.ZERO, "+10")
	assert_eq(kit.get_child_count(), 1, "Label wurde angelegt")
	assert_true(kit.get_child(0).is_queued_for_deletion(), "Label räumt sich sofort auf")
	kit.free()


func test_partikel_aufraeumen_haengt_am_finished_signal() -> void:
	# Quickwin #16: Aufräumen über particles.finished statt SceneTreeTimer
	# (der nach Szenenwechsel auf freed Instanzen feuern würde).
	var env := _setup()
	var overlay: Control = env["overlay"]
	var kit: JuiceKit = env["kit"]
	await wait_frames(1)
	var before := overlay.get_child_count()
	kit.burst(overlay, Vector2(60, 60), Color.YELLOW, 4)
	kit.confetti(4)
	kit.coin_rain(4)
	assert_eq(overlay.get_child_count(), before + 3, "drei Partikel-Nodes im Overlay")
	for i in 3:
		var particles := overlay.get_child(before + i) as CPUParticles2D
		if particles == null:
			fail_test("Partikel-Node %d ist kein CPUParticles2D" % i)
			continue
		assert_true(particles.one_shot, "one_shot gesetzt → finished feuert (Node %d)" % i)
		assert_true(
			particles.finished.is_connected(particles.queue_free),
			"Aufräumen hängt am finished-Signal (Node %d)" % i
		)
	await _teardown(env)


func test_count_to_endet_exakt_und_tickt() -> void:
	var env := _setup()
	var kit: JuiceKit = env["kit"]
	var label := Label.new()
	(env["overlay"] as Control).add_child(label)
	await wait_frames(1)
	kit.count_to(label, 0, 137, 0.25, "", " Punkte")
	var done := await wait_until(func() -> bool: return label.text == "137 Punkte", 2000)
	assert_true(done, "Count-Up endet exakt beim Zielwert (steht: '%s')" % label.text)
	await _teardown(env)


func test_win_moment_stellt_time_scale_zurueck() -> void:
	var env := _setup()
	var kit: JuiceKit = env["kit"]
	await wait_frames(1)
	kit.win_moment()
	assert_true(Engine.time_scale < 1.0, "Siegmoment = Zeitlupe")
	var restored := await wait_until(
		func() -> bool: return is_equal_approx(Engine.time_scale, 1.0), 2000
	)
	assert_true(restored, "time_scale kehrt auf 1.0 zurück")
	await _teardown(env)


func test_reduced_motion_schaltet_bewegung_ab() -> void:
	var was_reduced := _set_reduced_motion(true)
	var env := _setup()
	var overlay: Control = env["overlay"]
	var kit: JuiceKit = env["kit"]
	await wait_frames(1)
	var before := overlay.get_child_count()
	kit.hit_flash()
	kit.burst(overlay, Vector2(50, 50))
	kit.ring_burst(overlay, Vector2(50, 50))
	kit.confetti()
	kit.coin_rain()
	kit.edge_glow(1.0)
	kit.win_moment()
	kit.hit_freeze(80)
	assert_eq(overlay.get_child_count(), before, "Reduced Motion: keine Effekt-Nodes im Overlay")
	assert_almost(Engine.time_scale, 1.0, 1e-6, "Reduced Motion: keine Zeitlupe/Freeze")
	var label := Label.new()
	overlay.add_child(label)
	await wait_frames(1)
	kit.scale_pop(label, 1.5, 200)
	assert_true(label.scale.is_equal_approx(Vector2.ONE), "Reduced Motion: kein Scale-Pop")
	kit.count_to(label, 0, 55, 0.5)
	assert_eq(label.text, "55", "Reduced Motion: Endwert steht sofort da")
	# Combo-Anzeige bleibt sichtbar (Information), nur ohne Bewegung.
	kit.show_combo(4)
	await wait_frames(1)
	assert_true(_combo_label(overlay) != null, "Combo-Info auch unter Reduced Motion")
	kit.show_combo(0)
	await wait_frames(1)
	assert_true(_combo_label(overlay) == null, "Reset räumt sofort auf")
	await _teardown(env)
	_set_reduced_motion(was_reduced)
	await wait_frames(1)


func test_sfx_und_combo_tone_crashen_nicht_headless() -> void:
	var env := _setup()
	var kit: JuiceKit = env["kit"]
	await wait_frames(1)
	kit.sfx("game_hit")
	kit.sfx("game_win", 1.2)
	kit.combo_tone(1)
	kit.combo_tone(9)
	await wait_frames(2)
	assert_true(true, "Feel-Sounds laufen headless (Dummy-Treiber) ohne Fehler")
	await _teardown(env)


## Sucht das Combo-Label (Text beginnt mit ×) im Overlay.
func _combo_label(overlay: Control) -> Label:
	for child in overlay.get_children():
		if child is Label and (child as Label).text.begins_with("×"):
			return child
	return null
