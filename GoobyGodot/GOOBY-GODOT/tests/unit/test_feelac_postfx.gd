extends TestCase
## FEEL-AC: PostFx — der zentrale Stapel folgt der Qualitätsstufe
## (aus/dezent/hoch), Puls/Blende/Tageszeit-Tönung funktionieren, Bloom und
## Sättigung liegen NUR am vorhandenen Environment, Tiefenschärfe nur auf
## Stufe "hoch". Dazu die Moment-Regie: Cooldown + saubere Restauration.


class SettingsStub:
	extends RefCounted
	var post_fx := "dezent"
	var reduced := false

	func value_of(key: String) -> Variant:
		if key == "graphics.post_fx":
			return post_fx
		return ""

	func is_reduced_motion() -> bool:
		return reduced


func _fx(level: String) -> Array:
	var stub := SettingsStub.new()
	stub.post_fx = level
	var viewport := SubViewport.new()
	# Eigene Welt VOR dem Einhängen zuweisen (own_world_3d würde beim
	# Ersetzen "Parameter scenario is null" in den Runner-Log spucken).
	var welt := World3D.new()
	welt.environment = Environment.new()
	viewport.world_3d = welt
	tree.root.add_child(viewport)
	var fx := PostFx.new()
	fx.settings_override = stub
	fx.viewport_override = viewport
	fx.reduced_motion_override = 0
	tree.root.add_child(fx)
	await wait_frames(1)
	return [fx, stub, viewport]


func _frei(fx: PostFx, viewport: SubViewport) -> void:
	fx.free()
	viewport.free()


func test_stufen_schalten_overlay_und_bloom() -> void:
	var trio := await _fx("hoch")
	var fx: PostFx = trio[0]
	var stub: SettingsStub = trio[1]
	var viewport: SubViewport = trio[2]
	var env: Environment = viewport.world_3d.environment
	assert_eq(fx.level(), "hoch", "Stufe hoch aktiv")
	assert_true(fx.overlay_sichtbar(), "Overlay an")
	assert_true(env.glow_enabled, "Bloom nur auf hoch — an")
	stub.post_fx = "dezent"
	fx.refresh()
	assert_true(fx.overlay_sichtbar(), "dezent: Overlay an")
	assert_false(env.glow_enabled, "dezent: Bloom aus")
	stub.post_fx = "aus"
	fx.refresh()
	assert_eq(fx.level(), "aus", "Stufe aus")
	assert_false(fx.overlay_sichtbar(), "aus: Overlay weg")
	assert_false(env.adjustment_enabled, "aus: keine Farbanpassung")
	_frei(fx, viewport)


func test_emotions_puls_klingt_ab_und_respektiert_aus() -> void:
	var trio := await _fx("hoch")
	var fx: PostFx = trio[0]
	var stub: SettingsStub = trio[1]
	var viewport: SubViewport = trio[2]
	fx.emotions_puls(Color.RED, 1.0)
	assert_almost(fx.puls_wert(), 1.0, 0.01, "voller Puls auf hoch")
	var abgeklungen := await wait_until(func() -> bool: return fx.puls_wert() <= 0.0, 4000)
	assert_true(abgeklungen, "Puls klingt von selbst ab")
	stub.post_fx = "aus"
	fx.refresh()
	fx.emotions_puls(Color.RED, 1.0)
	assert_almost(fx.puls_wert(), 0.0, 0.001, "Stufe aus = kein Puls")
	_frei(fx, viewport)


func test_reduced_motion_macht_den_puls_mild() -> void:
	var trio := await _fx("hoch")
	var fx: PostFx = trio[0]
	var viewport: SubViewport = trio[2]
	fx.reduced_motion_override = 1
	fx.emotions_puls(Color.RED, 1.0)
	assert_true(fx.puls_wert() < 0.6, "milder Farbstoß (ist=%f)" % fx.puls_wert())
	_frei(fx, viewport)


func test_blende_zu_und_auf() -> void:
	var trio := await _fx("dezent")
	var fx: PostFx = trio[0]
	var viewport: SubViewport = trio[2]
	fx.blende_zu(0.0)
	assert_almost(fx.blende_wert(), 1.0, 0.001, "Blende zu")
	fx.blende_auf(0.0)
	assert_almost(fx.blende_wert(), 0.0, 0.001, "Blende auf")
	_frei(fx, viewport)


func test_tageszeit_toent_abends_und_bleibt_mittags_neutral() -> void:
	var trio := await _fx("dezent")
	var fx: PostFx = trio[0]
	var viewport: SubViewport = trio[2]
	fx.set_tageszeit(19.0)
	assert_true(fx._tint.a > 0.02, "abends warm getönt (a=%f)" % fx._tint.a)
	var abend_rot := fx._tint.r
	fx.set_tageszeit(12.5)
	assert_almost(fx._tint.a, 0.0, 0.005, "mittags neutral")
	fx.set_tageszeit(23.0)
	assert_true(fx._tint.b > abend_rot * 0.5, "nachts kühl (b=%f)" % fx._tint.b)
	_frei(fx, viewport)


func test_stimmung_steuert_die_saettigung() -> void:
	var trio := await _fx("dezent")
	var fx: PostFx = trio[0]
	var viewport: SubViewport = trio[2]
	var env: Environment = viewport.world_3d.environment
	fx.set_stimmung(0.0)
	assert_true(env.adjustment_enabled, "Anpassung aktiv")
	var elend := env.adjustment_saturation
	fx.set_stimmung(100.0)
	assert_true(
		env.adjustment_saturation > elend + 0.05,
		"selig satter als elend (%f vs %f)" % [env.adjustment_saturation, elend]
	)
	_frei(fx, viewport)


func test_tiefenschaerfe_nur_auf_hoch_und_restauriert() -> void:
	var trio := await _fx("hoch")
	var fx: PostFx = trio[0]
	var stub: SettingsStub = trio[1]
	var viewport: SubViewport = trio[2]
	var cam := Camera3D.new()
	viewport.add_child(cam)
	cam.current = true
	fx.nahaufnahme(true, 2.0)
	assert_true(fx.nahaufnahme_aktiv(), "Nahaufnahme aktiv")
	assert_true(cam.attributes is CameraAttributesPractical, "DoF-Attribute gesetzt")
	fx.nahaufnahme(false)
	assert_false(fx.nahaufnahme_aktiv(), "Nahaufnahme vorbei")
	assert_true(cam.attributes == null, "Kamera exakt restauriert")
	stub.post_fx = "dezent"
	fx.refresh()
	fx.nahaufnahme(true, 2.0)
	assert_false(fx.nahaufnahme_aktiv(), "dezent: keine Tiefenschärfe (Budget)")
	_frei(fx, viewport)


func test_messung_liefert_kosten_kennzahlen() -> void:
	var trio := await _fx("dezent")
	var fx: PostFx = trio[0]
	var viewport: SubViewport = trio[2]
	var messung := fx.messung()
	for key in ["draw_calls", "objekte", "frame_ms"]:
		assert_true(messung.has(key), "Kennzahl %s fehlt" % key)
	_frei(fx, viewport)


func test_autoload_fx_ist_registriert() -> void:
	var autoload := tree.root.get_node_or_null(NodePath("Fx"))
	assert_true(autoload is PostFx, "Autoload Fx fehlt unter /root (project.godot)")
	var helper := Node.new()
	tree.root.add_child(helper)
	assert_true(PostFx.get_or_create(helper) == autoload, "get_or_create nutzt den Autoload")
	helper.free()


func test_regie_cooldown_haelt_momente_besonders() -> void:
	var regie := MomentRegie.new()
	regie.reduced_motion_override = 1
	tree.root.add_child(regie)
	regie.reset_cooldown()
	assert_true(regie.inszeniere(null, Color.RED), "erster Moment läuft")
	assert_false(regie.inszeniere(null, Color.RED), "direkt danach: Cooldown")
	assert_true(regie.cooldown_uebrig_ms(Time.get_ticks_msec()) > 0, "Cooldown läuft")
	regie.free()


func test_regie_zeitlupe_restauriert_immer() -> void:
	var regie := MomentRegie.new()
	regie.reduced_motion_override = 0
	tree.root.add_child(regie)
	regie._zeitlupe()
	assert_almost(Engine.time_scale, MomentRegie.ZEITLUPE, 0.001, "Zeitlupe an")
	regie.free()
	assert_almost(Engine.time_scale, 1.0, 0.001, "time_scale nach free exakt zurück")
