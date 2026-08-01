extends TestCase
## MP-C-Bühnen-Rauchtests (Tiefenpolitur bunnyHop/trampoline/danceParty/
## veggieChop): jede 3D-Bühne muss HEADLESS aufbaubar sein und alle Hooks,
## die das Spiel aufruft, müssen crashfrei laufen. Dazu Regressions-Wächter
## für die Politur-Bugs: Messer über der Arbeitsplatte (nicht im Körper),
## Hälften-Pool läuft nicht voll, Frenzy-Lampe kehrt zurück.

const BunnyStage := preload("res://scripts/minigames/games/bunny_hop/bunny_hop_stage3d.gd")
const TrampStage := preload("res://scripts/minigames/games/trampoline/trampoline_stage3d.gd")
const DanceStage := preload("res://scripts/minigames/games/dance_party/dance_party_stage3d.gd")
const Kitchen := preload("res://scripts/minigames/games/veggie_chop/veggie_chop_kitchen3d.gd")

const VIEW := Vector2(720.0, 1160.0)


## Fenster VOR dem Stage-Aufbau aufs Projekt-Design (1280×720) pinnen
## (W17-Konvention): die Screen-Pos-Wächter unprojizieren über die ECHTE
## Root-Kamera, und ihre Soll-Bereiche sind auf das Default-Fenster
## kalibriert — hinterlässt ein Vorgänger-Test ein Hochkant-Fenster,
## wandert Gooby sonst aus dem Soll-Bild (Volllauf-Befund W17: x=-343,
## isoliert grün).
func _pin_view() -> void:
	tree.root.size = Vector2i(1280, 720)
	tree.root.size_changed.emit()
	await wait_frames(2)


func test_bunny_hop_stage_builds_and_fx_run() -> void:
	await _pin_view()
	var stage: Node3D = BunnyStage.new()
	tree.root.add_child(stage)
	stage.setup_stage(-3.1)
	assert_ne(stage.gooby, null, "Gooby fehlt auf der Wiese")
	assert_ne(stage.stage, null, "Stage3D-Kern fehlt")
	stage.apply_size(VIEW)
	var pillars: Array[Dictionary] = []
	var coins: Array[Dictionary] = []
	for _i in 3:
		stage.sync(pillars, coins, -1.4, 0.5, -1.2, 4.0, 2.0, 0.2, 0.5, 0.016)
		await wait_frames(1)
	stage.hop_fx()
	stage.coin_fx(0.5, 1.0)
	stage.crash_fx()
	var on_screen: Vector2 = stage.gooby_screen()
	assert_true(on_screen.x > 0.0 and on_screen.x < VIEW.x, "Gooby-Screenpos: %s" % on_screen)
	await wait_frames(2)
	stage.queue_free()
	await wait_frames(1)


func test_trampoline_stage_builds_and_fx_run() -> void:
	await _pin_view()
	var stage: Node3D = TrampStage.new()
	tree.root.add_child(stage)
	stage.setup_stage()
	assert_ne(stage.gooby, null, "Gooby fehlt in der Turnhalle")
	stage.apply_size(VIEW)
	for i in 4:
		stage.sync(1.5 + float(i), 3.0, 0.0, 0.0, 0.0, "", 4.0, 0.4, 0.5, 0.016)
		await wait_frames(1)
	stage.land_fx(0.8)
	stage.boost_fx()
	stage.butt_fx()
	stage.trick_fx()
	var on_screen: Vector2 = stage.gooby_screen()
	assert_true(on_screen.y > 0.0 and on_screen.y < VIEW.y, "Gooby-Screenpos: %s" % on_screen)
	await wait_frames(2)
	stage.queue_free()
	await wait_frames(1)


func test_dance_party_stage_builds_and_fx_run() -> void:
	var stage: Node3D = DanceStage.new()
	tree.root.add_child(stage)
	stage.setup_stage()
	assert_ne(stage.gooby, null, "Gooby fehlt in der Disko")
	assert_ne(stage.get("_spot"), null, "Gooby-Spot fehlt")
	assert_ne(stage.get("_encore_light"), null, "Encore-Licht fehlt")
	stage.frame(VIEW)
	var lane_xs: Array[float] = [180.0, 360.0, 540.0]
	stage.layout(lane_xs, 220.0, 760.0, 420.0)
	var notes: Array[Dictionary] = [{"lane": 1, "x": 360.0, "y": 400.0}]
	var flash: Array[float] = [0.0, 0.1, 0.0]
	for i in 4:
		stage.sync(notes, flash, i % 3, 0.6, 1.0, 0.2, i == 3, float(i) * 0.4, 0.016)
		await wait_frames(1)
	stage.hit_fx(360.0, true)
	stage.miss_fx()
	stage.encore_fx()
	await wait_frames(2)
	stage.queue_free()
	await wait_frames(1)


func test_kitchen_builds_knife_above_counter() -> void:
	var stage: Node3D = Kitchen.new()
	tree.root.add_child(stage)
	stage.setup_stage()
	assert_ne(stage.gooby, null, "Gooby fehlt in der Küche")
	assert_ne(stage.get("_sparkle"), null, "Stern-Emitter fehlt")
	assert_ne(stage.get("_miss_puff"), null, "Staub-Emitter fehlt")
	assert_ne(stage.get("_lamp"), null, "Küchenlampe fehlt")
	# Politur-Regression: das Messer hing unsichtbar im Körper/hinter der
	# Platte — es muss ÜBER der Arbeitsplatte und VOR Gooby schweben.
	var knife: Node3D = stage.get("_knife")
	assert_ne(knife, null, "Messer fehlt")
	assert_true(knife.global_position.y > Kitchen.COUNTER_Y, "Messer unter der Platte")
	assert_true(knife.global_position.z > -2.9, "Messer hinter Gooby")
	stage.queue_free()
	await wait_frames(1)


func test_kitchen_pools_reuse_nodes() -> void:
	var stage: Node3D = Kitchen.new()
	tree.root.add_child(stage)
	stage.setup_stage()
	var apple := {"item": {"key": "apple"}, "pos": Vector2(0.0, 1.0), "spin": 0.4, "t": 0.2}
	stage.sync([apple], 0.1)
	var items: Node3D = stage.get("_items")
	assert_eq(items.get_child_count(), 1, "erster Wurf erzeugt genau einen Knoten")
	stage.sync([], 0.2)
	stage.sync([apple], 0.3)
	assert_eq(items.get_child_count(), 1, "Pool wiederverwendet statt neu zu bauen")
	# Schnitt: zwei Hälften fliegen, landen nach ~1,1 s zurück im Pool.
	stage.split(Vector2(0.0, 1.0), "apple-half", Color(1.0, 0.8, 0.4))
	var halves: Node3D = stage.get("_halves")
	assert_eq(halves.get_child_count(), 2, "Schnitt erzeugt zwei Hälften")
	var drained := await wait_until(
		func() -> bool:
			stage.sync([], 0.4)
			return (stage.get("_flying") as Array).is_empty(),
		6000
	)
	assert_true(drained, "Hälften kehren in den Pool zurück")
	stage.split(Vector2(0.5, 1.2), "apple-half", Color(1.0, 0.8, 0.4))
	assert_eq(halves.get_child_count(), 2, "zweiter Schnitt nutzt den Pool")
	stage.queue_free()
	await wait_frames(1)


func test_kitchen_frenzy_lamp_and_chop_swing() -> void:
	var stage: Node3D = Kitchen.new()
	tree.root.add_child(stage)
	stage.setup_stage()
	var lamp: OmniLight3D = stage.get("_lamp")
	var base_energy := lamp.light_energy
	stage.set_frenzy(true)
	var flared := await wait_until(
		func() -> bool: return lamp.light_energy > base_energy + 1.0, 3000
	)
	assert_true(flared, "Frenzy-Lampe flammt auf")
	stage.set_frenzy(false)
	var calmed := await wait_until(
		func() -> bool: return lamp.light_energy < base_energy + 0.2, 3000
	)
	assert_true(calmed, "Lampe kehrt nach dem Frenzy zurück")
	# Hieb: Gelenk reißt sofort zur Antizipation hoch und pendelt auf 0 aus.
	stage.chop()
	var swing: Node3D = stage.get("_knife_swing")
	assert_almost(swing.rotation_degrees.x, -55.0, 0.01, "Antizipation fehlt")
	var settled := await wait_until(
		func() -> bool: return absf(swing.rotation_degrees.x) < 5.0, 3000
	)
	assert_true(settled, "Messer pendelt nicht aus")
	stage.miss(Vector2(0.0, -3.0))
	stage.junk_smash(Vector2(0.5, 0.5))
	stage.feel("ecstatic")
	stage.feel("neutral")
	await wait_frames(2)
	stage.queue_free()
	await wait_frames(1)
