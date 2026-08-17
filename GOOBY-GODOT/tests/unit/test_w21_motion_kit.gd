extends TestCase
## W21 „ACNH-UI" — Motion-Kit-Verträge (UI-DESIGN-ACNH §6): die Grammatik-
## Zeiten sind VERBINDLICH (kein Screen erfindet eigene Dauern), und JEDER
## Helfer ist Reduced-Motion-gated — bei aktivem Reduced Motion springt er
## sofort in den Endzustand und gibt null zurück (kein Tween, keine Teilchen).
## Zusätzlich: Count-Up endet EXAKT am Zielwert, Papier-Puff ist über den
## injizierten RNG deterministisch und räumt seine Flöckchen selbst auf.

## Frame-Deckel für „Animation fertig"-Schleifen (Watchdog-freundlich).
const MAX_FRAMES := 240


func _set_reduced_motion(an: bool) -> bool:
	var svc := tree.root.get_node_or_null("/root/UiTheme")
	if svc == null:
		return false
	var vorher: bool = svc.reduced_motion
	svc.reduced_motion = an
	return vorher


func _control() -> Control:
	var ctl := Control.new()
	ctl.custom_minimum_size = Vector2(80, 40)
	ctl.size = Vector2(80, 40)
	tree.root.add_child(ctl)
	return ctl


func test_grammatik_konstanten_verbindlich() -> void:
	assert_almost(MotionKit.POP_S, 0.24, 1e-6, "Pop-In: 240 ms")
	assert_almost(MotionKit.POP_OVERSHOOT, 1.04, 1e-6, "Pop-In: 1.04-Overshoot")
	assert_almost(MotionKit.SQUISH_SCALE, 0.94, 1e-6, "Squish: 0.94-Druck")
	assert_almost(MotionKit.SQUISH_S, 0.12, 1e-6, "Squish: 120 ms")
	assert_almost(MotionKit.BLATT_S, 0.28, 1e-6, "Blatt-Slide: 280 ms")
	assert_almost(MotionKit.STAGGER_S, 0.04, 1e-6, "Stagger: 40 ms Versatz")
	assert_almost(MotionKit.COUNT_S, 0.6, 1e-6, "Count-Up: 600 ms")
	assert_almost(MotionKit.PULS_SCALE, 1.03, 1e-6, "Wert-Puls: 1.03")
	for dauer: float in [MotionKit.STEMPEL_S, MotionKit.PUFF_S, MotionKit.PULS_S]:
		assert_true(dauer > 0.0, "keine 0-Dauer-Kante (Loop-Schutz)")


func test_reduced_motion_springt_in_den_endzustand() -> void:
	var rm_vorher := _set_reduced_motion(true)
	var ctl := _control()
	ctl.scale = Vector2(0.5, 0.5)
	ctl.modulate.a = 0.2
	assert_eq(MotionKit.pop_in(ctl), null, "pop_in: kein Tween unter Reduced Motion")
	assert_eq(ctl.scale, Vector2.ONE, "pop_in: Scale sofort in Ruhelage")
	assert_almost(ctl.modulate.a, 1.0, 1e-6, "pop_in: sofort sichtbar")
	ctl.scale = Vector2(0.5, 0.5)
	assert_eq(MotionKit.squish(ctl), null, "squish: kein Tween")
	assert_eq(ctl.scale, Vector2.ONE, "squish: Ruhelage")
	var rest_y := ctl.position.y
	ctl.modulate.a = 0.0
	assert_eq(MotionKit.blatt_slide_in(ctl), null, "blatt_slide_in: kein Tween")
	assert_almost(ctl.modulate.a, 1.0, 1e-6, "blatt_slide_in: sofort sichtbar")
	assert_almost(ctl.position.y, rest_y, 1e-6, "blatt_slide_in: Position unangetastet")
	assert_eq(MotionKit.blatt_slide_out(ctl), null, "blatt_slide_out: kein Tween")
	assert_almost(ctl.modulate.a, 0.0, 1e-6, "blatt_slide_out: sofort unsichtbar")
	ctl.modulate.a = 0.3
	ctl.scale = Vector2(2.0, 2.0)
	ctl.rotation = 0.5
	assert_eq(MotionKit.stempel(ctl), null, "stempel: kein Tween")
	assert_eq(ctl.scale, Vector2.ONE, "stempel: Scale 1")
	assert_almost(ctl.rotation, 0.0, 1e-6, "stempel: Rotation 0")
	assert_eq(MotionKit.puls(ctl), null, "puls: kein Tween")
	var kinder_vorher := ctl.get_child_count()
	MotionKit.papier_puff(ctl)
	assert_eq(ctl.get_child_count(), kinder_vorher, "papier_puff: keine Flöckchen")
	var label := Label.new()
	tree.root.add_child(label)
	assert_eq(MotionKit.count_up(label, 0, 250), null, "count_up: kein Tween")
	assert_eq(label.text, "250", "count_up: Zielwert steht sofort")
	var liste := [_control(), _control()]
	for eintrag: Control in liste:
		eintrag.modulate.a = 0.0
	MotionKit.stagger_ein(liste)
	for eintrag: Control in liste:
		assert_almost(eintrag.modulate.a, 1.0, 1e-6, "stagger_ein: sofort sichtbar")
		eintrag.free()
	label.free()
	ctl.free()
	_set_reduced_motion(rm_vorher)


func test_pop_in_endet_in_ruhelage() -> void:
	var rm_vorher := _set_reduced_motion(false)
	var ctl := _control()
	var tween := MotionKit.pop_in(ctl)
	assert_true(tween != null and tween.is_valid(), "pop_in liefert laufenden Tween")
	assert_true(ctl.scale.x < 1.0, "pop_in startet klein (0.9)")
	var frames := 0
	while tween.is_valid() and frames < MAX_FRAMES:
		await wait_frames(1)
		frames += 1
	assert_true(ctl.scale.is_equal_approx(Vector2.ONE), "pop_in endet exakt in Ruhelage")
	assert_almost(ctl.modulate.a, 1.0, 1e-4, "pop_in endet voll sichtbar")
	ctl.free()
	_set_reduced_motion(rm_vorher)


func test_count_up_endet_exakt_und_formatiert() -> void:
	var rm_vorher := _set_reduced_motion(false)
	var label := Label.new()
	tree.root.add_child(label)
	var fmt := func(v: int) -> String: return "%d Münzen" % v
	var tween := MotionKit.count_up(label, 0, 300, fmt)
	assert_true(tween != null and tween.is_valid(), "count_up liefert laufenden Tween")
	var frames := 0
	while tween.is_valid() and frames < MAX_FRAMES:
		await wait_frames(1)
		frames += 1
	assert_eq(label.text, "300 Münzen", "Count-Up endet EXAKT am Zielwert (formatiert)")
	assert_eq(MotionKit.count_up(label, 300, 300, fmt), null, "gleicher Wert: kein Tween")
	label.free()
	_set_reduced_motion(rm_vorher)


func test_papier_puff_deterministisch_und_raeumt_auf() -> void:
	var rm_vorher := _set_reduced_motion(false)
	var host := _control()
	var rng := RandomNumberGenerator.new()
	rng.seed = 21
	MotionKit.papier_puff(host, MotionKit.PUFF_TEILE, rng)
	assert_eq(host.get_child_count(), MotionKit.PUFF_TEILE, "genau PUFF_TEILE Flöckchen")
	# RNG injiziert: identischer Seed → identische Streuung (Determinismus).
	var rotation_erste := (host.get_child(0) as Control).rotation
	var rng2 := RandomNumberGenerator.new()
	rng2.seed = 21
	assert_almost(
		rotation_erste, rng2.randf_range(-PI, PI), 1e-5, "Streuung kommt aus dem injizierten RNG"
	)
	var frames := 0
	while host.get_child_count() > 0 and frames < MAX_FRAMES:
		await wait_frames(1)
		frames += 1
	assert_eq(host.get_child_count(), 0, "Flöckchen räumen sich selbst auf (queue_free)")
	host.free()
	_set_reduced_motion(rm_vorher)


func test_stagger_blendet_alle_ein() -> void:
	var rm_vorher := _set_reduced_motion(false)
	var liste: Array = [_control(), _control(), _control()]
	MotionKit.stagger_ein(liste)
	for eintrag: Control in liste:
		assert_almost(eintrag.modulate.a, 0.0, 1e-6, "Stagger: alle starten unsichtbar")
	var frames := 0
	while frames < MAX_FRAMES:
		await wait_frames(1)
		frames += 1
		var fertig := true
		for eintrag: Control in liste:
			if eintrag.modulate.a < 0.999:
				fertig = false
		if fertig:
			break
	for eintrag: Control in liste:
		assert_almost(eintrag.modulate.a, 1.0, 1e-3, "Stagger: alle enden voll sichtbar")
		eintrag.free()
	_set_reduced_motion(rm_vorher)
