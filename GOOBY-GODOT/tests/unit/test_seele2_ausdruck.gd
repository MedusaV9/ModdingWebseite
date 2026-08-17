extends TestCase
## SEELE-2: Ausdrucks-Schicht (GoobyExpressions) über dem echten Rig.
## Kernversprechen: der Ausdruck folgt der Stimmung MESSBAR — Ohren-Droop,
## Lider-Bias und Reaktions-Latenz unterscheiden sich zwischen elend und
## selig; Reduced Motion nimmt nur die Mikro-Bewegung, nie den Zustand.


func _rig_mit_schicht() -> Array:
	var rig := GoobyRig.new()
	tree.root.add_child(rig)
	await wait_frames(3)
	var schicht := GoobyExpressions.attach_to(rig)
	schicht.reduced_motion_override = 0
	await wait_frames(2)
	return [rig, schicht]


func test_attach_ist_idempotent_und_findet_rig_teile() -> void:
	var paar := await _rig_mit_schicht()
	var rig: GoobyRig = paar[0]
	var schicht: GoobyExpressions = paar[1]
	assert_true(GoobyExpressions.attach_to(rig) == schicht, "zweites attach_to liefert dieselbe")
	assert_true(schicht._skeleton != null, "Skeleton3D nicht gefunden")
	assert_true(schicht._blink_idx >= 0, "blink-Shapekey nicht gefunden")
	assert_true(schicht._modifier != null, "ExpressionModifier fehlt")
	assert_true(schicht._modifier.ear_l >= 0 and schicht._modifier.ear_r >= 0, "Ohr-Bones fehlen")
	rig.free()


func test_ohren_und_lider_folgen_der_stimmung() -> void:
	var paar := await _rig_mit_schicht()
	var rig: GoobyRig = paar[0]
	var schicht: GoobyExpressions = paar[1]
	schicht.set_stimmung(5.0)
	await wait_until(func() -> bool: return schicht.ohren_droop() > 0.4, 8000)
	var ohren_elend := schicht.ohren_droop()
	var lider_elend := schicht.lider_bias()
	schicht.set_stimmung(95.0)
	await wait_until(func() -> bool: return schicht.ohren_droop() < -0.01, 8000)
	var ohren_selig := schicht.ohren_droop()
	var lider_selig := schicht.lider_bias()
	assert_true(
		ohren_elend > ohren_selig + 0.2,
		"Ohren hängen bei Elend sichtbar (%f vs %f)" % [ohren_elend, ohren_selig]
	)
	assert_true(ohren_selig < 0.0, "beste Laune perkt die Ohren auf (ist=%f)" % ohren_selig)
	assert_true(
		lider_elend > lider_selig + 0.15,
		"Lider schwer bei Elend (%f vs %f)" % [lider_elend, lider_selig]
	)
	rig.free()


func test_lider_bias_liegt_auf_dem_blink_shapekey() -> void:
	var paar := await _rig_mit_schicht()
	var rig: GoobyRig = paar[0]
	var schicht: GoobyExpressions = paar[1]
	schicht.set_stimmung(5.0)
	await wait_frames(40)
	var mesh: MeshInstance3D = schicht._mesh
	var wert := mesh.get_blend_shape_value(schicht._blink_idx)
	assert_true(wert > 0.15, "blink-Shapekey trägt den Lider-Bias (ist=%f)" % wert)
	rig.free()


func test_reaktions_latenz_folgt_der_laune() -> void:
	var paar := await _rig_mit_schicht()
	var rig: GoobyRig = paar[0]
	var schicht: GoobyExpressions = paar[1]
	schicht.set_stimmung(5.0)
	var traege := schicht.reaktions_latenz_s()
	schicht.set_stimmung(95.0)
	var flink := schicht.reaktions_latenz_s()
	assert_true(traege > flink + 0.2, "elend reagiert träger (%f vs %f)" % [traege, flink])
	assert_true(flink <= 0.1, "selig reagiert fast sofort (ist=%f)" % flink)
	rig.free()


func test_aufmerken_zuckt_ohren_und_sucht_blick() -> void:
	var paar := await _rig_mit_schicht()
	var rig: GoobyRig = paar[0]
	var schicht: GoobyExpressions = paar[1]
	schicht.set_stimmung(90.0)
	await wait_frames(5)
	schicht.aufmerken()
	var gezuckt := await wait_until(func() -> bool: return schicht._zucken < -0.05, 3000)
	assert_true(gezuckt, "Aufmerken perkt die Ohren (zucken=%f)" % schicht._zucken)
	rig.free()


func test_blick_auf_punkt_setzt_look_at() -> void:
	var paar := await _rig_mit_schicht()
	var rig: GoobyRig = paar[0]
	var schicht: GoobyExpressions = paar[1]
	assert_true(rig.look_at_target == null, "ohne Blickbefehl kein Look-At")
	schicht.blick_auf_punkt(Vector3(2.0, 1.0, 3.0), 5.0)
	await wait_frames(2)
	assert_true(rig.look_at_target != null, "Blickpunkt aktiviert das Rig-Look-At")
	schicht.blick_frei()
	await wait_frames(2)
	assert_true(rig.look_at_target == null, "blick_frei gibt das Look-At zurück")
	rig.free()


func test_reduced_motion_nimmt_bewegung_nicht_zustand() -> void:
	var paar := await _rig_mit_schicht()
	var rig: GoobyRig = paar[0]
	var schicht: GoobyExpressions = paar[1]
	schicht.reduced_motion_override = 1
	schicht.set_stimmung(5.0)
	await wait_frames(40)
	assert_almost(schicht.wippen_offset(0.0), 0.0, 1e-6, "kein Ohren-Wippen bei Reduced Motion")
	assert_almost(schicht.kopf_wandern_yaw(), 0.0, 1e-6, "kein Kopf-Wandern bei Reduced Motion")
	assert_true(
		schicht.ohren_droop() > 0.2, "Zustands-Kanal Ohren-Droop bleibt — Stimmung bleibt lesbar"
	)
	assert_true(schicht.lider_bias() > 0.15, "Zustands-Kanal Lider bleibt")
	rig.free()
