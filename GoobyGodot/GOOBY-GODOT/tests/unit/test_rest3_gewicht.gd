extends TestCase
## REST-3 P1-Bug — „Gewicht veraendert Goobys sichtbaren Koerper nicht":
## Web-§B5-Werte (on_eat/Minispiel/Drift), §C4.3-Stufen und die NEUE
## Silhouetten-Verkabelung: Weight.body_scale → GoobyRig.set_weight skaliert
## den Koerper MESSBAR (X/Z am Modell), sanft und stetig statt Stufensprung.
## Dazu die Fuetter-Verkabelung (apply_feed speist gooby.weight) und die
## Krankheits-Optik am Rig (set_care: blass, Schniefnase, Eisbeutel,
## Augenringe).

const Weight := preload("res://scripts/logic/weight.gd")

const EPS := 1e-4


func _make_rig() -> GoobyRig:
	var rig := GoobyRig.new()
	tree.root.add_child(rig)
	await wait_frames(3)
	return rig


func test_web_deltas_essen_spiel_ball() -> void:
	assert_almost(Weight.on_eat(50.0, true), 52.0, 1e-6, "Junk +2.0")
	assert_almost(Weight.on_eat(50.0, false), 50.5, 1e-6, "gesund +0.5")
	assert_almost(Weight.on_minigame_end(50.0, "runner"), 49.0, 1e-6, "aktives Spiel -1.0")
	assert_almost(Weight.on_minigame_end(50.0, "memory"), 49.75, 1e-6, "anderes Spiel -0.25")
	assert_almost(Weight.on_ball_fetch(50.0), 49.8, 1e-6, "Ball-Apport -0.2")
	assert_almost(Weight.on_eat(94.5, true), 95.0, 1e-6, "Klemme oben bei 95")
	assert_almost(Weight.on_minigame_end(5.5, "runner"), 5.0, 1e-6, "Klemme unten bei 5")
	assert_almost(Weight.clamp_weight("kaputt"), 50.0, 1e-6, "Junk-Werte fallen auf 50")


func test_drift_zieht_sanft_richtung_50() -> void:
	# ±2.0 pro 24 h — nie ueber das Ziel hinaus.
	assert_almost(Weight.tick(60.0, 1440.0), 58.0, 1e-6, "von oben -2/Tag")
	assert_almost(Weight.tick(40.0, 1440.0), 42.0, 1e-6, "von unten +2/Tag")
	assert_almost(Weight.tick(50.5, 1440.0), 50.0, 1e-6, "stoppt am Ziel")
	assert_almost(Weight.tick(60.0, 1440.0, 0.3), 59.4, 1e-6, "Offline-Faktor 0.3")


func test_stufen_und_stetige_silhouette() -> void:
	assert_eq(Weight.tier_of(20.0), "sleek")
	assert_eq(Weight.tier_of(50.0), "chubby")
	assert_eq(Weight.tier_of(75.0), "chonky")
	assert_eq(Weight.tier_of(90.0), "floof")
	# Anker exakt auf den Web-TIER_SCALE-Werten.
	assert_almost(Weight.body_scale(15.0), 0.93, 1e-6, "sleek-Mitte")
	assert_almost(Weight.body_scale(42.5), 1.0, 1e-6, "chubby-Mitte")
	assert_almost(Weight.body_scale(72.5), 1.07, 1e-6, "chonky-Mitte")
	assert_almost(Weight.body_scale(90.0), 1.14, 1e-6, "floof-Anker")
	assert_almost(Weight.body_scale(5.0), 0.93, 1e-6, "Rand klemmt unten")
	assert_almost(Weight.body_scale(95.0), 1.14, 1e-6, "Rand klemmt oben")
	# Stetig + monoton: kein Stufensprung, Gooby wird nie schlagartig rund.
	var prev := Weight.body_scale(5.0)
	for i in range(6, 96):
		var cur := Weight.body_scale(float(i))
		assert_true(cur >= prev, "monoton bei %d (%f -> %f)" % [i, prev, cur])
		assert_true(cur - prev < 0.02, "sanfter Schritt bei %d" % i)
		prev = cur


func test_fuettern_speist_das_gewicht_im_save() -> void:
	var state := {
		"gooby":
		{
			"stats": {"hunger": 20.0, "energy": 90.0, "hygiene": 85.0, "fun": 70.0},
			"weight": 50.0,
			"health": {"state": "healthy"},
		},
		"inventory": {"food": {"cookie": 1, "salad": 1}},
		"achievements": {"counters": {}},
	}
	var res := FoodCatalog.apply_feed(state, "cookie")
	assert_true(bool(res.get("junk", false)), "cookie ist Junk")
	assert_almost(float(state["gooby"]["weight"]), 52.0, 1e-6, "Junk +2.0 im Save")
	res = FoodCatalog.apply_feed(state, "salad")
	assert_false(bool(res.get("junk", true)), "Salat ist gesund")
	assert_almost(float(state["gooby"]["weight"]), 52.5, 1e-6, "gesund +0.5 im Save")
	assert_almost(float(state["gooby"]["health"]["junkScore"]), 0.5, 1e-6, "Junk-Druck 1 - 0.5")


func test_rig_silhouette_reagiert_messbar_auf_gewicht() -> void:
	var rig := await _make_rig()
	var model: Node3D = rig._model
	assert_true(model != null, "Rig hat ein Modell")
	rig.set_weight(42.5)
	assert_almost(rig.weight_scale(), 1.0, EPS, "42.5 = neutrale Silhouette")
	assert_almost(model.scale.x, 1.0, EPS, "Modell-X neutral")
	rig.set_weight(90.0)
	assert_almost(rig.weight_scale(), 1.14, EPS, "rund bei 90")
	assert_almost(model.scale.x, 1.14, EPS, "Modell-X rund")
	assert_almost(model.scale.z, 1.14, EPS, "Modell-Z rund")
	assert_almost(model.scale.y, 1.0, EPS, "Hoehe bleibt (nur breiter, nie gestaucht)")
	rig.set_weight(15.0)
	assert_almost(model.scale.x, 0.93, EPS, "schlank bei 15")
	# Messbar unterscheidbar: schlank < normal < rund.
	rig.set_weight(15.0)
	var schlank := rig.weight_scale()
	rig.set_weight(50.0)
	var normal := rig.weight_scale()
	rig.set_weight(90.0)
	var rund := rig.weight_scale()
	assert_true(schlank < normal and normal < rund, "drei sichtbar verschiedene Silhouetten")
	rig.queue_free()
	await wait_frames(1)


func test_rig_kranksymptome_sichtbar_und_reversibel() -> void:
	var rig := await _make_rig()
	rig.set_care(0, 0.0)
	assert_eq(rig.care_grade(), 0, "gesund")
	# Kraenklich: blasse Toenung + Schniefnase, noch kein Eisbeutel.
	rig.set_care(1, 0.0)
	await wait_frames(1)
	assert_eq(rig.care_grade(), 1)
	assert_true(rig._care_nose != null and rig._care_nose.visible, "Schniefnase sichtbar")
	assert_true(rig._care_ice == null or not rig._care_ice.visible, "Eisbeutel erst bei sick")
	assert_true(
		rig._mesh.get_surface_override_material(0) != null, "blasse Kraenklichkeits-Toenung"
	)
	# Richtig krank: Eisbeutel dazu.
	rig.set_care(2, 0.0)
	await wait_frames(1)
	assert_true(rig._care_ice != null and rig._care_ice.visible, "Eisbeutel sichtbar")
	# Muede (gesund): Augenringe ohne Krank-Requisiten.
	rig.set_care(0, 0.8)
	await wait_frames(1)
	assert_false(rig._care_nose.visible, "gesund: keine Schniefnase")
	assert_true(rig._care_eyebags.size() > 0, "Augenring-Requisiten existieren")
	for bag: MeshInstance3D in rig._care_eyebags:
		assert_true(bag.visible, "Augenringe bei 0.8 Muedigkeit sichtbar")
	assert_true(rig._mesh.get_surface_override_material(0) == null, "keine Blaesse ohne Krankheit")
	# Alles wieder gut: Symptome verschwinden restlos.
	rig.set_care(0, 0.0)
	await wait_frames(1)
	assert_false(rig._care_nose.visible)
	assert_false(rig._care_ice.visible)
	for bag: MeshInstance3D in rig._care_eyebags:
		assert_false(bag.visible, "Augenringe weg")
	rig.queue_free()
	await wait_frames(1)
