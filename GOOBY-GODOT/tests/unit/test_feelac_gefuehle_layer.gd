extends TestCase
## FEEL-AC: GoobyFeelings über dem ECHTEN Rig — Gesicht/Pose laufen über das
## Ausdrucks-Override, Extra-Shapekeys werden exakt restauriert, das
## Emote-Symbol erscheint und verschwindet, Reduced Motion lässt den Zustand
## lesbar (nur die Bewegungs-Beats entfallen).


func _rig_mit_gefuehlen() -> Array:
	var rig := GoobyRig.new()
	tree.root.add_child(rig)
	await wait_frames(3)
	var layer := GoobyFeelings.attach_to(rig)
	layer.reduced_motion_override = 0
	# Regie in den milden Modus: kein Zoom/Zeitlupe im Test-Baum.
	layer.regie().reduced_motion_override = 1
	await wait_frames(1)
	return [rig, layer]


func test_attach_ist_idempotent() -> void:
	var paar := await _rig_mit_gefuehlen()
	var rig: GoobyRig = paar[0]
	var layer: GoobyFeelings = paar[1]
	assert_true(GoobyFeelings.attach_to(rig) == layer, "zweites attach_to liefert dieselbe")
	assert_true(layer.regie() != null, "MomentRegie hängt dran")
	assert_false(layer.zeige("quatsch"), "unbekannte Emotion abgelehnt")
	assert_false(layer.aktiv(), "nichts aktiv nach Ablehnung")
	rig.free()


func test_zeige_setzt_override_symbol_und_dauer() -> void:
	var paar := await _rig_mit_gefuehlen()
	var rig: GoobyRig = paar[0]
	var layer: GoobyFeelings = paar[1]
	assert_true(layer.zeige("schreck"), "Schreck angenommen")
	assert_true(layer.aktiv(), "aktiv")
	assert_eq(layer.aktuelle(), "schreck", "aktuelle Emotion")
	assert_true(rig.has_expression_override(), "Rig trägt das Ausdrucks-Override")
	var symbol := layer.symbol_node()
	assert_true(symbol != null, "Emote-Symbol hängt am Gooby")
	assert_true(
		(
			symbol.position.y >= GoobyFeelings.SYMBOL_HOEHE_MIN_M
			and symbol.position.y <= GoobyFeelings.SYMBOL_HOEHE_MAX_M
		),
		"Symbol sitzt über dem Kopf (y=%f)" % symbol.position.y
	)
	await wait_until(func() -> bool: return rig._emotion_weights["scared"] > 0.5, 4000)
	assert_true(rig._emotion_weights["scared"] > 0.5, "Schreck-Gesicht blendet ein")
	rig.free()


func test_ende_raeumt_auf_und_meldet() -> void:
	var paar := await _rig_mit_gefuehlen()
	var rig: GoobyRig = paar[0]
	var layer: GoobyFeelings = paar[1]
	var beendet: Array = []
	layer.gefuehl_beendet.connect(func(id: String) -> void: beendet.append(id))
	layer.zeige("freude")
	await wait_frames(5)
	layer._rest_s = 0.05
	await wait_until(func() -> bool: return not layer.aktiv(), 4000)
	assert_false(layer.aktiv(), "Gefühl vorbei")
	assert_false(rig.has_expression_override(), "Override geräumt")
	assert_eq(beendet, ["freude"], "gefuehl_beendet gemeldet")
	await wait_until(func() -> bool: return layer.get_node_or_null("EmoteSymbol") == null, 4000)
	assert_true(layer.get_node_or_null("EmoteSymbol") == null, "Symbol poppt aus und räumt sich")
	rig.free()


func test_extra_shapekeys_werden_exakt_restauriert() -> void:
	var paar := await _rig_mit_gefuehlen()
	var rig: GoobyRig = paar[0]
	var layer: GoobyFeelings = paar[1]
	rig.set_morph("eye_size", 1.3)
	var mesh: MeshInstance3D = rig._mesh
	var eye_idx := mesh.find_blend_shape_by_name("eye_size")
	var mund_idx := mesh.find_blend_shape_by_name("mouth_open")
	var eye_vorher := mesh.get_blend_shape_value(eye_idx)
	layer.zeige("ueberraschung")
	await wait_until(
		func() -> bool: return mesh.get_blend_shape_value(eye_idx) > eye_vorher + 0.3, 4000
	)
	assert_true(
		mesh.get_blend_shape_value(eye_idx) > eye_vorher + 0.3,
		"Augen reißen auf (Boost RELATIV zum Spieler-Morph)"
	)
	assert_true(mesh.get_blend_shape_value(mund_idx) > 0.2, "Mund geht auf")
	layer.beende()
	await wait_frames(2)
	assert_almost(
		mesh.get_blend_shape_value(eye_idx), eye_vorher, 0.001, "Spieler-Morph exakt zurück"
	)
	assert_almost(mesh.get_blend_shape_value(mund_idx), 0.0, 0.001, "Mund exakt zurück")
	rig.free()


func test_neues_gefuehl_loest_das_alte_sauber_ab() -> void:
	var paar := await _rig_mit_gefuehlen()
	var rig: GoobyRig = paar[0]
	var layer: GoobyFeelings = paar[1]
	layer.zeige("freude")
	await wait_frames(5)
	layer.zeige("schreck")
	assert_eq(layer.aktuelle(), "schreck", "Schreck übernimmt")
	assert_true(rig.has_expression_override(), "Override bleibt aktiv")
	var symbole := 0
	for child in layer.get_children():
		if child is EmoteSymbol and not (child as EmoteSymbol).geht_gerade():
			symbole += 1
	assert_eq(symbole, 1, "genau EIN aktives Symbol")
	rig.free()


func test_reduced_motion_laesst_den_zustand_lesbar() -> void:
	var paar := await _rig_mit_gefuehlen()
	var rig: GoobyRig = paar[0]
	var layer: GoobyFeelings = paar[1]
	layer.reduced_motion_override = 1
	layer.zeige("begeisterung")
	await wait_frames(20)
	assert_true(layer.aktiv(), "Gefühl läuft")
	assert_true(layer.symbol_node() != null, "Symbol bleibt (Lesbarkeit!)")
	assert_true(rig.has_expression_override(), "Gesicht/Pose bleiben")
	assert_almost(rig.position.y, 0.0, 0.001, "kein Hüpfen unter Reduced Motion")
	assert_almost(rig.scale.y, 1.0, 0.02, "kein Squash unter Reduced Motion")
	rig.free()


func test_bewegungs_beat_bewegt_den_koerper() -> void:
	var paar := await _rig_mit_gefuehlen()
	var rig: GoobyRig = paar[0]
	var layer: GoobyFeelings = paar[1]
	layer.zeige("begeisterung")
	var bewegt := await wait_until(
		func() -> bool: return rig.position.y > 0.05 or absf(rig.scale.y - 1.0) > 0.03, 4000
	)
	assert_true(bewegt, "Hüpf-Beat bewegt den Körper sichtbar")
	layer.beende()
	var zurueck := await wait_until(
		func() -> bool: return absf(rig.position.y) < 0.01 and absf(rig.scale.y - 1.0) < 0.01, 4000
	)
	assert_true(zurueck, "Basis-Transform kommt exakt zurück")
	rig.free()
