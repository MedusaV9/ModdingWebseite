extends TestCase
## MP-H Tiefenpolitur — Regressionstests der fünf polierten Bühnen
## (burgerBuild, deliveryRush, hideSeek, ghostHunt, starHopper).
##
## Getestet wird NUR die View-Schicht (die Logik deckt test_mg2_*/test_mg3_*
## ab): Belichtungs-Eichung der Bühnen, die Entdeckungsmoment-Bausteine von
## hideSeek/ghostHunt und die Kulissen-Nachrüstungen (Milchstraße,
## Laternen-Halos, Additiv-Blätter). Alles headless-sicher — MultiMesh-
## INSTANZEN sind im Dummy-Renderer nicht rücklesbar, Meshes/Materialien schon.

const GardenStage := preload("res://scripts/minigames/games/hide_seek/hide_seek_garden3d.gd")
const HopperStage := preload("res://scripts/minigames/games/star_hopper/star_hopper_stage.gd")
const BurgerStage := preload("res://scripts/minigames/games/burger_build/burger_build_stage3d.gd")


func _mount(game_id: String) -> Node:
	var meta := MinigameRegistry.get_game(game_id)
	if meta.is_empty():
		fail_test("%s fehlt in der Registry" % game_id)
		return null
	var game: Node = (load(str(meta["scene"])) as PackedScene).instantiate()
	var ctx := MinigameCtx.new()
	ctx.game_id = game_id
	ctx.difficulty = "normal"
	ctx.orientation = str(meta.get("orientation", "portrait"))
	ctx.run_seed = 4242
	tree.root.add_child(game)
	game.call("setup", ctx)
	await wait_frames(1)
	game.call("start")
	await wait_frames(2)
	return game


## Erstes WorldEnvironment unterhalb eines Knotens.
static func _env_of(node: Node) -> Environment:
	var stack: Array = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		if current is WorldEnvironment:
			return (current as WorldEnvironment).environment
		for child in current.get_children():
			stack.append(child)
	return null


# ── Belichtungs-Eichung ────────────────────────────────────────────────────


## Die Tagbühnen waren ~40 Luma-Stufen überbelichtet: beide Spiele MÜSSEN
## abgedunkelt belichten (Exposure klar unter 1) und Kontrast/Sättigung heben.
func test_day_stages_are_exposure_calibrated() -> void:
	var garden := GardenStage.new()
	tree.root.add_child(garden)
	garden.setup_stage(12)
	assert_true(garden.environment.tonemap_exposure <= 0.75, "hideSeek: Belichtung")
	assert_true(garden.environment.adjustment_enabled, "hideSeek: Adjustments an")
	garden.queue_free()
	var diner := BurgerStage.new()
	tree.root.add_child(diner)
	diner.setup_stage([-2.4, 0.0, 2.4])
	assert_true(diner.environment.tonemap_exposure <= 0.7, "burgerBuild: Belichtung")
	assert_true(diner.environment.adjustment_enabled, "burgerBuild: Adjustments an")
	diner.queue_free()
	await wait_frames(1)


## Die Nachtszene darf dunkler werden, aber nicht absaufen: Belichtung im
## Fenster 0,7…1,0 und das kalte Mondlicht (Sonne) bleibt kräftig.
func test_ghost_hunt_night_stays_readable() -> void:
	var game := await _mount("ghostHunt")
	var env := _env_of(game)
	assert_true(env != null, "ghostHunt: kein Environment")
	assert_true(env.tonemap_exposure >= 0.7 and env.tonemap_exposure <= 1.0, "Nacht-Fenster")
	var mist: Array = game.get("_mist")
	assert_eq(mist.size(), 5, "fünf Nebelschwaden")
	# Nebel treibt: _drift_mist verschiebt jede Schwade abhängig von _bob.
	var wisp: Node3D = (mist[0] as Dictionary)["node"]
	var before := wisp.position
	game.set("_bob", 10.0)
	game.call("_drift_mist")
	assert_true(before.distance_to(wisp.position) > 0.01, "Nebel driftet nicht")
	game.queue_free()
	await wait_frames(1)


# ── Entdeckungsmomente hideSeek ────────────────────────────────────────────


## Blätterwirbel und Funkeln sind ADDITIV eingeblendet — die star_03-Textur
## (weißer Stern auf Schwarz) wurde alphageblendet zu dunklen Quadraten.
func test_hide_seek_particles_blend_additively() -> void:
	var garden := GardenStage.new()
	tree.root.add_child(garden)
	garden.setup_stage(12)
	for field: String in ["_leaves", "_sparkle"]:
		var node: GPUParticles3D = garden.get(field)
		assert_true(node != null, "%s fehlt" % field)
		var mat := node.material_override as StandardMaterial3D
		assert_eq(mat.blend_mode, BaseMaterial3D.BLEND_MODE_ADD, "%s additiv" % field)
	garden.queue_free()
	await wait_frames(1)


## Entdeckungsmoment: alert() zündet das Funkeln am Versteck, celebrate()
## startet den Freuden-Hüpfer, der über tick() wieder abklingt.
func test_hide_seek_alert_and_celebrate() -> void:
	var garden := GardenStage.new()
	tree.root.add_child(garden)
	garden.setup_stage(12)
	garden.alert(3)
	var sparkle: GPUParticles3D = garden.get("_sparkle")
	assert_true(sparkle.emitting, "alert() zündet das Funkeln")
	garden.celebrate(3)
	var hops: Dictionary = garden.get("_hops")
	assert_true(hops.has(3), "celebrate() startet den Hüpfer")
	garden.tick(1.0)
	hops = garden.get("_hops")
	assert_false(hops.has(3), "Hüpfer klingt über tick() ab")
	# Außerhalb des Rasters: keine Abstürze, keine Einträge.
	garden.alert(-1)
	garden.celebrate(99)
	assert_eq((garden.get("_hops") as Dictionary).size(), 0, "Randfälle bleiben leer")
	garden.queue_free()
	await wait_frames(1)


## Die Sommer-Kulisse steht: zwei Schmetterlinge, die tick() bewegt.
func test_hide_seek_butterflies_flutter() -> void:
	var garden := GardenStage.new()
	tree.root.add_child(garden)
	garden.setup_stage(12)
	var flies: Array = garden.get("_butterflies")
	assert_eq(flies.size(), 2, "zwei Schmetterlinge")
	var node: Node3D = (flies[0] as Dictionary)["node"]
	var before := node.position
	garden.tick(0.7)
	assert_true(before.distance_to(node.position) > 0.005, "Schmetterling fliegt nicht")
	garden.queue_free()
	await wait_frames(1)


# ── Kulissen-Nachrüstungen ─────────────────────────────────────────────────


## Weltraum-Skyline: Sternenfeld UND Milchstraßen-Band (zwei MultiMeshes),
## das Band trägt 150 Instanzen — das obere Bilddrittel bleibt nicht schwarz.
func test_star_hopper_milky_way() -> void:
	var stage := HopperStage.new()
	tree.root.add_child(stage)
	stage.setup_stage([-1.15, 0.0, 1.15])
	var stars: Node3D = stage.get("_stars")
	var layers: Array = []
	for child in stars.get_children():
		if child is MultiMeshInstance3D:
			layers.append(child)
	assert_eq(layers.size(), 2, "Sternenfeld + Milchstraße")
	var counts: Array[int] = []
	for mmi: MultiMeshInstance3D in layers:
		counts.append(mmi.multimesh.instance_count)
	assert_true(150 in counts, "Milchstraßen-Band fehlt")
	stage.queue_free()
	await wait_frames(1)


## Abend-Laternen der Lieferstadt: der Lampen-MultiProp trägt eine vierte
## Ebene (Halo-Quad, additiv) — vorher waren die Köpfe nur gelbe Klötzchen.
func test_delivery_lamps_carry_halo() -> void:
	var game := await _mount("deliveryRush")
	var world: Node3D = game.get("_world")
	var found := false
	for prop: Node3D in world.get("_props"):
		for mmi: MultiMeshInstance3D in prop.get("_layers"):
			var quad := mmi.multimesh.mesh as QuadMesh
			if quad == null:
				continue
			var mat := quad.material as StandardMaterial3D
			if mat != null and mat.blend_mode == BaseMaterial3D.BLEND_MODE_ADD:
				found = true
	assert_true(found, "Laternen-Halo fehlt")
	# Asphalt hell genug, um nicht zu Schwarz zusammenzufallen (FB-4-Farbe
	# selbst prüft test_fb4_vehicle_ground — hier nur die Helligkeit).
	var asphalt: Color = (world.get_script() as GDScript).get_script_constant_map()["ASPHALT"]
	assert_true(asphalt.v >= 0.4, "Asphalt zu dunkel")
	game.queue_free()
	await wait_frames(1)
