extends TestCase
## W14/GAMESQA — Politur-Logik der Qualitätsrunde (nur Präsentation/Input):
## (1) Intro-Beat-Timing: alle sechs polierten Spiele teilen den 1,5-s-Beat;
##     starHopper GATET die Sim (Lauf bleibt zahlengleich), gvz läuft bewusst
##     ungebremst weiter (1. Welle kommt spät — Bestandstests bauen darauf).
## (2) starHopper-Wisch-Forgiveness: Zwei-Bahn-Schwelle skaliert mit der
##     Screenbreite (8 %), fällt aber nie unter den Web-Kontrakt von 40 px.
## (3) deliveryRush-Landmarken-Regel: die Leuchtkugel MUSS über der
##     Hochkant-Kamerahöhe schweben (7,5 m lag exakt drauf und fraß das Bild).

const Star := preload("res://scripts/minigames/games/star_hopper/star_hopper.gd")
const Delivery := preload("res://scripts/minigames/games/delivery_rush/delivery_rush.gd")
const DeliveryWorld := preload("res://scripts/minigames/games/delivery_rush/delivery_rush_world.gd")
const DeliveryLogic := preload("res://scripts/minigames/games/delivery_rush/delivery_rush_logic.gd")
const STAR_SCENE := "res://scripts/minigames/games/star_hopper/star_hopper.tscn"
const GVZ_SCENE := "res://scripts/minigames/games/gvz/gvz_game.tscn"

## Alle W14-polierten Spiele mit Intro-Beat (Skriptpfade).
const INTRO_SCRIPTS := {
	"starHopper": "res://scripts/minigames/games/star_hopper/star_hopper.gd",
	"gvz": "res://scripts/minigames/games/gvz/gvz_game.gd",
	"runner": "res://scripts/minigames/games/runner/runner.gd",
	"ranchZeit": "res://scripts/minigames/games/ranch_zeit/zeit_game.gd",
	"ranchTonnen": "res://scripts/minigames/games/ranch_tonnen/tonnen_game.gd",
	"ranchTurnier": "res://scripts/minigames/games/ranch_turnier/turnier_game.gd",
}


class GameStateDouble:
	extends RefCounted
	var state := {}

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var cursor: Variant = state
		for part in path.split("."):
			if cursor is Dictionary and (cursor as Dictionary).has(part):
				cursor = cursor[part]
			else:
				return fallback
		return cursor

	func update(mutator: Callable) -> void:
		mutator.call(state)

	func notify_slice_changed(_slice_id: String) -> void:
		pass


func test_intro_beat_timing_shared() -> void:
	for id: String in INTRO_SCRIPTS:
		var script: GDScript = load(INTRO_SCRIPTS[id])
		var consts := script.get_script_constant_map()
		assert_true(consts.has("INTRO_S"), "%s hat INTRO_S" % id)
		assert_almost(float(consts["INTRO_S"]), 1.5, 1e-6, "%s Intro-Beat = 1,5 s" % id)


func test_star_swipe_threshold_floor_and_scale() -> void:
	# Auf Phone-Breiten greift weiter der Web-Kontrakt (40 px Mindest-Wisch) …
	assert_almost(Star.swipe_threshold_px(390.0), 40.0, 1e-6, "iPhone-Breite: Web-Minimum")
	assert_almost(Star.swipe_threshold_px(500.0), 40.0, 1e-6, "Grenzbereich bleibt 40 px")
	# … auf breiten/Retina-Screens skaliert die Schwelle mit 8 % der Breite.
	assert_almost(Star.swipe_threshold_px(720.0), 57.6, 1e-6, "720 px → 8 % Breite")
	assert_almost(Star.swipe_threshold_px(1170.0), 93.6, 1e-6, "Retina → 8 % Breite")


func test_star_swipe_threshold_monotonic_and_bounded() -> void:
	var prev := 0.0
	for width: float in [320.0, 390.0, 430.0, 500.0, 640.0, 720.0, 900.0, 1170.0, 1290.0]:
		var got := Star.swipe_threshold_px(width)
		assert_true(got >= 40.0, "nie unter dem Web-Minimum (%.0f px)" % width)
		assert_true(got >= prev, "monoton steigend (%.0f px)" % width)
		assert_true(got < width * 0.5, "Tippen bleibt erreichbar (%.0f px)" % width)
		prev = got


func test_star_intro_gates_sim_then_runs() -> void:
	var ctx := MinigameCtx.new()
	ctx.game_id = "starHopper"
	ctx.difficulty = "normal"
	ctx.run_seed = 5
	var game: MinigameBase = (load(STAR_SCENE) as PackedScene).instantiate()
	tree.root.add_child(game)
	game.setup(ctx)
	game.start()
	assert_almost(float(game.get("_intro_left")), 1.5, 1e-6, "Intro startet voll")
	# Während des Beats wartet die Sim: elapsed/traveled bleiben exakt 0.
	for _i in 3:
		game._process(0.4)
	assert_true(float(game.get("_intro_left")) > 0.0, "Beat läuft noch (1,2 s)")
	assert_almost(float(game.get("elapsed")), 0.0, 1e-6, "Sim wartet im Intro")
	assert_almost(float(game.get("traveled")), 0.0, 1e-6, "kein Meter gefahren")
	game._process(0.4)
	assert_almost(float(game.get("_intro_left")), 0.0, 1e-6, "Beat nach 1,6 s vorbei")
	assert_almost(float(game.get("elapsed")), 0.0, 1e-6, "Übergangs-Frame zählt nicht")
	game._process(0.2)
	assert_almost(float(game.get("elapsed")), 0.2, 1e-6, "danach tickt die Sim normal")
	assert_true(float(game.get("traveled")) > 0.0, "und der Lauf fährt los")
	game.free()


func test_gvz_intro_does_not_block_sim() -> void:
	var gs := GameStateDouble.new()
	var ctx := MinigameCtx.new()
	ctx.game_id = "gvz"
	ctx.difficulty = "normal"
	ctx.run_seed = 7
	var game: MinigameBase = (load(GVZ_SCENE) as PackedScene).instantiate()
	game.set("game_state_override", gs)
	tree.root.add_child(game)
	game.setup(ctx)
	game.start()
	game.call("open_level", 1)
	assert_almost(float(game.get("_intro_left")), 1.5, 1e-6, "Intro-Beat gestartet")
	var tick_before := int((game.get("state") as Dictionary)["tick"])
	for _i in 10:
		game._process(0.05)
	# GvZ-Design: der Beat animiert NUR die Kamera — die Sim läuft ungebremst
	# (1. Welle kommt bei t=25 s; Bestandstests erwarten sofortiges Ticken).
	assert_true(float(game.get("_intro_left")) > 0.0, "Beat läuft noch (0,5 s)")
	assert_true(
		int((game.get("state") as Dictionary)["tick"]) > tick_before,
		"Sim tickt WÄHREND des Intro-Beats"
	)
	game.free()


func test_delivery_landmark_ball_clears_portrait_camera() -> void:
	var world: Node3D = DeliveryWorld.new()
	tree.root.add_child(world)
	world.call("_build_landmarks")
	var cam_height := float(Delivery.CAM_LIFT) + float(Delivery.CAM_PORTRAIT_LIFT)
	var balls := 0
	for child: Node in world.get_children():
		if child is MeshInstance3D and (child as MeshInstance3D).mesh is SphereMesh:
			balls += 1
			var mesh := (child as MeshInstance3D).mesh as SphereMesh
			var clearance := (child as MeshInstance3D).position.y - mesh.radius
			assert_true(
				clearance > cam_height + 1.0,
				"Leuchtkugel schwebt klar über der Hochkant-Kamera (%.1f m)" % cam_height
			)
	assert_eq(balls, (DeliveryLogic.LANDMARKS as Array).size(), "je Landmarke eine Kugel")
	world.free()
