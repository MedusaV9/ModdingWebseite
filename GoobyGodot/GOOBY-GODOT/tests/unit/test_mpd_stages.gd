extends TestCase
## MP-D-Kontrakt: die vier ruhigen Bühnen (pipeFlow, purblePlace, snailMail,
## lanternFloat) bauen fehlerfrei, halten die Belichtungs-Caps (bekannte
## Falle: Bühnen waren ~40 Luma-Stufen überbelichtet) und liefern ihre
## Belohnungs-Signale: Farb-Regenbogen + Goldfunken (pipeFlow), Versand-Blitz
## (purblePlace), Ziel-Dach-Glühen + Goldfunken (snailMail), Ring-Puls +
## Licht-Boost (lanternFloat). Die MECHANIK (<id>_logic.gd) bleibt unberührt.

const PipeStage := preload("res://scripts/minigames/games/pipe_flow/pipe_flow_stage3d.gd")
const PurbleStage := preload("res://scripts/minigames/games/purble_place/purble_place_stage3d.gd")
const PurbleLogic := preload("res://scripts/minigames/games/purble_place/purble_place_logic.gd")
const SnailStage := preload("res://scripts/minigames/games/snail_mail/snail_mail_stage3d.gd")
const LanternStage := preload(
	"res://scripts/minigames/games/lantern_float/lantern_float_stage3d.gd"
)

## Ruhige Abend-/Nachmittags-Bühnen: Sonne und Ambient bleiben gedeckelt.
const MAX_SUN := 1.0
const MAX_AMBIENT := 0.6


func _assert_exposure(inner: Node3D, label: String) -> void:
	var sun := inner.get("sun") as DirectionalLight3D
	var env := inner.get("environment") as Environment
	assert_true(sun != null and env != null, "%s: Sonne/Environment fehlen" % label)
	assert_true(sun.light_energy <= MAX_SUN, "%s: Sonne zu hell (%f)" % [label, sun.light_energy])
	assert_true(
		env.ambient_light_energy <= MAX_AMBIENT,
		"%s: Ambient zu hell (%f)" % [label, env.ambient_light_energy]
	)


func _free_stage(holder: Node3D) -> void:
	tree.root.remove_child(holder)
	holder.free()


## pipeFlow: Bühne baut, Belichtung gedeckelt, alle 25 Kacheln laufen über
## die MultiMeshes (Draw-Call-Diät) und der Regenbogen hat DREI Farbbögen.
func test_pipe_stage_exposure_and_tiles() -> void:
	var stage: Node3D = PipeStage.new()
	tree.root.add_child(stage)
	stage.call("setup_stage")
	_assert_exposure(stage.get("stage"), "pipeFlow")
	assert_true(stage.get("gooby") != null, "pipeFlow: Gooby fehlt")
	var rainbow := stage.get("_rainbow") as Node3D
	assert_eq(rainbow.get_child_count(), 3, "pipeFlow: Regenbogen braucht drei Farbbögen")
	stage.call("frame", Vector2(390.0, 844.0))
	var tune: Dictionary = PipeFlowLogic.apply_difficulty(PipeFlowLogic.PIPE, "normal")
	var board: Dictionary = PipeFlowLogic.generate_board(7, tune)
	stage.call(
		"layout", Vector2(20.0, 160.0), 70.0, 5, int(board["srcCol"]), int(board["goalCol"]), 700.0
	)
	var watered: Array[bool] = []
	for _i in 25:
		watered.append(false)
	stage.call("sync", board["tiles"], watered, {}, false, -1, 0.5, 0.016)
	var hubs := stage.get("_mm_hubs") as MultiMesh
	assert_eq(hubs.visible_instance_count, 25, "pipeFlow: 25 Naben über EIN MultiMesh")
	var arms := stage.get("_mm_arms") as MultiMesh
	assert_true(arms.visible_instance_count > 25, "pipeFlow: Rohrarme fehlen im MultiMesh")
	_free_stage(stage)


## pipeFlow: Tap dreht SICHTBAR (Spin-Fenster), die Lösung zündet Regenbogen
## plus Gold-Funken, und beides klingt wieder ab.
func test_pipe_tap_and_solve_reward() -> void:
	var stage: Node3D = PipeStage.new()
	tree.root.add_child(stage)
	stage.call("setup_stage")
	stage.call("frame", Vector2(390.0, 844.0))
	var tune: Dictionary = PipeFlowLogic.apply_difficulty(PipeFlowLogic.PIPE, "normal")
	var board: Dictionary = PipeFlowLogic.generate_board(7, tune)
	stage.call(
		"layout", Vector2(20.0, 160.0), 70.0, 5, int(board["srcCol"]), int(board["goalCol"]), 700.0
	)
	stage.call("tap_fx", 3)
	var spin: PackedFloat32Array = stage.get("_spin")
	assert_true(spin[3] > 0.0, "pipeFlow: Tap muss die Kachel sichtbar drehen")
	stage.call("solve_fx", 22)
	assert_true(float(stage.get("_rainbow_t")) > 0.0, "pipeFlow: Lösung startet den Regenbogen")
	var gold := stage.get("_gold_burst") as GPUParticles3D
	assert_true(gold.emitting, "pipeFlow: Lösung braucht Gold-Funken")
	var watered: Array[bool] = []
	for _i in 25:
		watered.append(false)
	stage.call("sync", board["tiles"], watered, {}, false, -1, 0.5, 0.016)
	var rainbow := stage.get("_rainbow") as Node3D
	assert_true(rainbow.visible, "pipeFlow: Regenbogen muss sichtbar aufgehen")
	stage.call("sync", board["tiles"], watered, {}, false, -1, 0.5, 2.5)
	stage.call("sync", board["tiles"], watered, {}, false, -1, 0.5, 0.016)
	assert_false(rainbow.visible, "pipeFlow: Regenbogen muss wieder verblassen")
	_free_stage(stage)


## purblePlace: Schiene liegt ÜBER Goobys Mütze (~1,23 m Welt), Belichtung
## gedeckelt, und der Versand-Jubel blitzt die Zone + doppelte Funken.
func test_purble_rail_clearance_and_ship_flash() -> void:
	var tune: Dictionary = PurbleLogic.apply_difficulty(PurbleLogic.CAKE, "normal")
	var stage: Node3D = PurbleStage.new()
	tree.root.add_child(stage)
	stage.call("setup_stage", PurbleLogic.STATIONS, tune)
	_assert_exposure(stage, "purblePlace")
	assert_true(stage.get("gooby") != null, "purblePlace: Bäcker-Gooby fehlt")
	assert_true(
		PurbleStage.RAIL_Y >= 1.4,
		"purblePlace: Düsenschiene (%f) schneidet Goobys Mütze" % PurbleStage.RAIL_Y
	)
	stage.call("celebrate", float(tune["SHIP_S"]))
	assert_eq(float(stage.get("_ship_flash")), 1.0, "purblePlace: Versand muss die Zone blitzen")
	var sparkle := stage.get("_sparkle") as GPUParticles3D
	assert_true(sparkle.emitting, "purblePlace: Versand braucht Funken")
	stage.call("tick", 0.5)
	assert_true(float(stage.get("_ship_flash")) < 1.0, "purblePlace: Versand-Blitz muss abklingen")
	_free_stage(stage)


## snailMail: Ziel-Dach glüht (EIN wiederverwendetes Material), Wiesenrand
## ist bewachsen (inkl. Klee-Inseln) und die Trocken-Lieferung zündet Gold.
func test_snail_target_glow_and_dry_reward() -> void:
	var stage: Node3D = SnailStage.new()
	tree.root.add_child(stage)
	stage.call("setup_stage")
	_assert_exposure(stage.get("stage"), "snailMail")
	stage.call("frame", Vector2(390.0, 844.0))
	var houses: Array = [
		{
			"px": Vector2(110.0, 300.0),
			"door_px": Vector2(110.0, 336.0),
			"kind": "house",
			"target": false
		},
		{
			"px": Vector2(280.0, 320.0),
			"door_px": Vector2(280.0, 356.0),
			"kind": "house",
			"target": true
		},
	]
	stage.call(
		"layout_level",
		houses,
		[],
		[Vector2(200.0, 420.0)],
		Vector2(195.0, 600.0),
		Rect2(40.0, 240.0, 310.0, 420.0)
	)
	var nodes: Array = stage.get("_houses")
	var plain := (nodes[0] as Node3D).get_node("Haus/Dach") as MeshInstance3D
	var target := (nodes[1] as Node3D).get_node("Haus/Dach") as MeshInstance3D
	assert_eq(
		target.get_surface_override_material(0),
		stage.get("_mat_roof_target"),
		"snailMail: Ziel-Dach muss das Glüh-Material tragen"
	)
	assert_eq(
		plain.get_surface_override_material(0),
		stage.get("_mat_roof_plain"),
		"snailMail: Nicht-Ziel-Dach bleibt matt"
	)
	var edge := stage.get("_edge_props") as Node3D
	assert_true(
		edge.get_child_count() >= 5,
		"snailMail: Wiesenrand kahl (%d Deko-Gruppen)" % edge.get_child_count()
	)
	stage.call("deliver_fx", Vector2(280.0, 356.0), true)
	var gold := stage.get("_gold_burst") as GPUParticles3D
	assert_true(gold.emitting, "snailMail: Trocken-Lieferung braucht Gold-Funken")
	_free_stage(stage)


## lanternFloat: das Dorfband liegt im SICHTBAREN Bereich (alte Werte fielen
## unter die Bildkante), der Treffer fächert einen Ring auf und der Gold-Ring
## boostet das Laternenlicht.
func test_lantern_village_band_and_award_ring() -> void:
	var stage: Node3D = LanternStage.new()
	tree.root.add_child(stage)
	stage.call("setup_stage", 1.0, 0.8)
	_assert_exposure(stage.get("stage"), "lanternFloat")
	stage.call("frame", Vector2(390.0, 844.0), 73.0, false)
	var shine := stage.get("_lake_shine") as MeshInstance3D
	assert_true(
		shine.position.y > -8.5,
		"lanternFloat: See (%f) liegt unter der Bildkante" % shine.position.y
	)
	stage.call("award_fx", 0.5, 1.0, true)
	assert_true(float(stage.get("_award_ring_t")) > 0.0, "lanternFloat: Ring-Puls startet nicht")
	assert_eq(float(stage.get("_light_boost")), 1.0, "lanternFloat: Gold muss das Licht boosten")
	var rings: Array[Dictionary] = []
	stage.call("sync", rings, 0.0, 0.0, 0.0, 0.1, 0.016)
	var award := stage.get("_award_ring") as MeshInstance3D
	assert_true(award.visible, "lanternFloat: Belohnungsring muss sichtbar auffächern")
	stage.call("sync", rings, 0.0, 0.0, 0.0, 0.2, 0.8)
	stage.call("sync", rings, 0.0, 0.0, 0.0, 0.3, 0.016)
	assert_false(award.visible, "lanternFloat: Belohnungsring muss wieder erlöschen")
	_free_stage(stage)
