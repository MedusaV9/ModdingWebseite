extends TestCase
## MP-A-Kontrakt: die vier tiefenpolierten Bühnen (teaParty, goobySays,
## memoryMatch, pancakeTower) bauen fehlerfrei, halten die BELICHTUNGS-Caps
## (bekannte Falle: Bühnen waren ~40 Luma-Stufen überbelichtet) und liefern
## die Feedback-Signale (Band-Glühen, Fehler-Blitz, Landering, Ghost-Tasse).
## Die Spiel-MECHANIK (<id>_logic.gd) bleibt hier bewusst unberührt.

const TeaStage := preload("res://scripts/minigames/games/tea_party/tea_party_stage3d.gd")
const SaysStage := preload("res://scripts/minigames/games/gooby_says/gooby_says_stage3d.gd")
const MemoryStage := preload("res://scripts/minigames/games/memory_match/memory_match_stage3d.gd")
const CakeStage := preload("res://scripts/minigames/games/pancake_tower/pancake_tower_stage3d.gd")

## Tageslicht-Bühnen: mehr Sonne/Ambient als das wäscht die Pastellfarben aus.
const MAX_SUN := 0.62
const MAX_AMBIENT := 0.45
const MAX_SKY_ENERGY := 0.85


## Sonnen-/Ambient-/Himmel-Energie einer gebauten Bühne prüfen.
func _assert_daylight_caps(holder: Node3D, label: String) -> void:
	var inner: Node3D = holder.get("stage")
	assert_true(inner != null, "%s: Stage3D fehlt" % label)
	var sun := inner.get("sun") as DirectionalLight3D
	var env := inner.get("environment") as Environment
	assert_true(sun.light_energy <= MAX_SUN, "%s: Sonne zu hell (%f)" % [label, sun.light_energy])
	assert_true(
		env.ambient_light_energy <= MAX_AMBIENT,
		"%s: Ambient zu hell (%f)" % [label, env.ambient_light_energy]
	)
	var sky_mat := env.sky.sky_material as ProceduralSkyMaterial
	assert_true(
		sky_mat.sky_energy_multiplier <= MAX_SKY_ENERGY,
		"%s: Himmel zu hell (%f)" % [label, sky_mat.sky_energy_multiplier]
	)


func _free_stage(holder: Node3D) -> void:
	tree.root.remove_child(holder)
	holder.free()


func test_tea_stage_exposure_and_structure() -> void:
	var stage: Node3D = TeaStage.new()
	tree.root.add_child(stage)
	stage.setup_stage()
	_assert_daylight_caps(stage, "teaParty")
	assert_true(stage.get("gooby") != null, "teaParty: Gooby fehlt")
	var screen: Vector2 = stage.call("cup_screen")
	assert_true(screen.is_finite(), "teaParty: cup_screen liefert %s" % screen)
	_free_stage(stage)


func test_tea_band_feedback_and_ghost() -> void:
	var stage: Node3D = TeaStage.new()
	tree.root.add_child(stage)
	stage.setup_stage()
	var band := {"center": 0.7, "half": 0.075}
	# Im Perfect-Kern glüht die Tee-Oberfläche gold (Anzeige AM Geschehen).
	stage.call("sync", 0.7, band, true, 0.0, 0.016)
	var top := stage.get("_tea_top") as MeshInstance3D
	assert_eq(
		top.get_surface_override_material(0),
		stage.get("_mat_top_perfect"),
		"teaParty: Perfect-Level muss gold glühen"
	)
	# Weit unterm Band: neutrale Füllstands-Anzeige.
	stage.call("sync", 0.2, band, true, 0.0, 0.016)
	assert_eq(
		top.get_surface_override_material(0),
		stage.get("_mat_top_fill"),
		"teaParty: außerhalb des Bands keine Grün/Gold-Anzeige"
	)
	# Servierte Tasse rutscht als Ghost sichtbar raus und verschwindet dann.
	stage.call("serve_ghost", 0.8)
	var ghost := stage.get("_ghost") as Node3D
	assert_true(ghost.visible, "teaParty: Ghost-Tasse startet sichtbar")
	stage.call("sync", 0.0, band, false, 1.0, 0.4)
	stage.call("sync", 0.0, band, false, 1.0, 0.4)
	assert_false(ghost.visible, "teaParty: Ghost-Tasse muss nach ~0,55 s weg sein")
	_free_stage(stage)


func test_says_stage_show_and_fail_flash() -> void:
	var stage: Node3D = SaysStage.new()
	tree.root.add_child(stage)
	stage.setup_stage()
	stage.call("apply_size", Vector2(390.0, 844.0))
	var inner: Node3D = stage.get("stage")
	var env := inner.get("environment") as Environment
	assert_true(env.glow_enabled, "goobySays: Show-Bühne braucht Glow")
	var sun := inner.get("sun") as DirectionalLight3D
	assert_true(sun.light_energy <= 0.9, "goobySays: Sonne zu hell (%f)" % sun.light_energy)
	# Vorspielen: Pad 2 leuchtet, Halo an.
	stage.call("sync", 2, 0.5, "watch", 0.0, 0.016)
	var halo := stage.get("_halo") as MeshInstance3D
	assert_true(halo.visible, "goobySays: Halo muss beim Vorspielen leuchten")
	# Fehler: alle Pads blitzen rot (Fehler-Fenster > 0), danach erlischt es.
	stage.call("fail_fx")
	assert_true(float(stage.get("_fail_left")) > 0.0, "goobySays: Fehler-Blitz startet nicht")
	stage.call("sync", -1, 0.0, "input", 0.0, 0.8)
	assert_eq(float(stage.get("_fail_left")), 0.0, "goobySays: Fehler-Blitz muss abklingen")
	_free_stage(stage)


func test_says_pads_layout_both_orientations() -> void:
	var stage: Node3D = SaysStage.new()
	tree.root.add_child(stage)
	stage.setup_stage()
	stage.call("apply_size", Vector2(390.0, 844.0))
	var pads: Array = stage.get("_pads")
	assert_eq(pads.size(), 4, "goobySays: vier Pads")
	# Hochkant: 2×2-Block (zwei z-Reihen), quer: eine Reihe (ein z-Wert).
	var portrait_z := {}
	for pad: Node3D in pads:
		portrait_z[snappedf(pad.position.z, 0.01)] = true
	assert_eq(portrait_z.size(), 2, "goobySays: Hochkant = 2 Pad-Reihen")
	stage.call("apply_size", Vector2(844.0, 390.0))
	var landscape_z := {}
	for pad: Node3D in pads:
		landscape_z[snappedf(pad.position.z, 0.01)] = true
	assert_eq(landscape_z.size(), 1, "goobySays: Quer = 1 Pad-Reihe")
	# Tipp weit außerhalb der Pads darf kein Pad treffen.
	assert_eq(int(stage.call("pad_at", Vector2(2.0, 2.0))), -1, "goobySays: Rand-Tap = daneben")
	_free_stage(stage)


func test_memory_stage_exposure_cards_and_props() -> void:
	var stage: Node3D = MemoryStage.new()
	tree.root.add_child(stage)
	stage.setup_stage()
	_assert_daylight_caps(stage, "memoryMatch")
	var vp := Vector2(390.0, 844.0)
	stage.call("frame", vp)
	var rects: Array[Rect2] = []
	var faces: Array[int] = []
	for i in 16:
		var col := i % 4
		var row := i / 4
		rects.append(Rect2(Vector2(24.0 + col * 88.0, 140.0 + row * 108.0), Vector2(80.0, 98.0)))
		faces.append(i / 2)
	stage.call("layout", rects, faces)
	var cards: Array = stage.get("_cards")
	assert_eq(cards.size(), 16, "memoryMatch: 16 Karten")
	# Kartenrücken tragen das „?" (3-Sekunden-Klarheit).
	var quest_found := false
	for child in (cards[0] as Node3D).get_node("Flipper/Ruecken").get_children():
		if child is Label3D and (child as Label3D).text == "?":
			quest_found = true
	assert_true(quest_found, "memoryMatch: Kartenrücken braucht das ?")
	# Gooby sitzt HINTER dem Feld (kleineres z als alle Karten), nah dran.
	var gooby := stage.get("gooby") as Node3D
	var min_card_z := INF
	for card: Node3D in cards:
		min_card_z = minf(min_card_z, card.position.z)
	assert_true(gooby.position.z < min_card_z, "memoryMatch: Gooby gehört hinter das Feld")
	# Korb + Snacks stehen IM Bild (Bildschirm-Anker statt Weltschätzung).
	# Maßstab ist der ECHTE Kamera-Viewport: im Spiel ist das der SubViewport
	# des Spiels, im Test das Root-Fenster — layout() ankert relativ dazu.
	var inner: Node3D = stage.get("stage")
	var cam := inner.get("camera") as Camera3D
	var real_vp: Vector2 = cam.get_viewport().get_visible_rect().size
	for prop_name: String in ["_basket", "_snacks"]:
		var prop := stage.get(prop_name) as Node3D
		var screen: Vector2 = inner.call("to_screen", prop.global_position)
		assert_true(
			screen.x > 0.0 and screen.x < real_vp.x and screen.y > 0.0 and screen.y < real_vp.y,
			"memoryMatch: %s außerhalb des Bildes (%s vs %s)" % [prop_name, screen, real_vp]
		)
	_free_stage(stage)


func test_pancake_stage_exposure_and_land_ring() -> void:
	var stage: Node3D = CakeStage.new()
	tree.root.add_child(stage)
	stage.call("setup_stage", 2.9, 0.88, 0.18)
	_assert_daylight_caps(stage, "pancakeTower")
	stage.call("frame", Vector2(390.0, 844.0))
	var layers: Array[Dictionary] = [
		{"center": 0.0, "width": 1.5, "topping": false, "index": 1},
	]
	var active := {
		"x": 0.4, "y": 1.8, "width": 1.5, "topping": false, "visible": true, "stack_top": 0.18
	}
	var crumbs: Array[Dictionary] = []
	# Perfect: der Landering pulst einmal auf und klingt wieder ab.
	stage.call("perfect_fx", 0.0, 0.18)
	stage.call("sync", layers, active, 0.0, 0.0, crumbs, 0.0, 0.016)
	var ring := stage.get("_land_ring") as MeshInstance3D
	assert_true(ring.visible, "pancakeTower: Landering muss bei Perfect sichtbar sein")
	assert_true(ring.position.z > 0.75, "pancakeTower: Landering muss VOR dem Stapel liegen")
	stage.call("sync", layers, active, 0.0, 0.0, crumbs, 0.0, 0.5)
	assert_false(ring.visible, "pancakeTower: Landering muss wieder verschwinden")
	_free_stage(stage)
