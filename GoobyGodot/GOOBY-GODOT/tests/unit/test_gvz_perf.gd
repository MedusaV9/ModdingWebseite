extends TestCase
## Render-Budget-Wächter für GvZ (Eval C-technik Befund 2): baut die
## Referenz-Kampfszene des Eval-Berichts §3 deterministisch auf (Level 8
## Nacht, 4 Türme, 7 sichtbare Zombies mit Anker-HP, Seed 4242) und prüft
## zwei Budgets:
## - STRUKTUR (läuft auch headless/Dummy-Renderer): sichtbare Geometry-
##   Instanzen der 3D-Bühne — jede ist mindestens EIN Draw-Call — plus die
##   Dreieckssumme aus Mesh × sichtbaren Instanzen. Vor dem MultiMesh-Umbau
##   lag die Bühne bei ~95 Einzelknoten; das Budget hat ein Toleranzband,
##   damit Deko-Feinschliff den Wächter nicht sofort rot macht.
## - RENDERING (nur mit echtem Renderer, z. B. xvfb-Lauf): Draw-Calls und
##   Primitive pro Frame via RenderingServer.get_rendering_info gegen das
##   Minigame-Budget (≤250 Draws; Primitive-Deckel statt der alten ~620k).

const GAME_SCENE := "res://scripts/minigames/games/gvz/gvz_game.tscn"

## Sichtbare MeshInstance3D/MultiMeshInstance3D unter der Bühne (Nach dem
## Umbau: ~55 — Menge via MultiMesh, Kulisse als Schwärme, Boss versteckt).
const STAGE_DRAW_UNIT_BUDGET := 90
## Dreiecke der Bühne (nach Low-Poly-Pass ~60k; vorher ~600k gerendert).
const STAGE_TRIANGLE_BUDGET := 150000
const RENDER_DRAW_BUDGET := 250
const RENDER_PRIMITIVE_BUDGET := 250000


func test_referenzszene_haelt_render_budget() -> void:
	var game: Node = (load(GAME_SCENE) as PackedScene).instantiate()
	var ctx := MinigameCtx.new()
	ctx.game_id = "gvz"
	ctx.difficulty = "normal"
	ctx.orientation = "landscape"
	ctx.run_seed = 4242
	tree.root.add_child(game)
	game.call("setup", ctx)
	await wait_frames(1)
	game.call("start")
	if game.has_method("apply_view"):
		game.call("apply_view", tree.root.get_visible_rect().size)
	await wait_frames(4)
	game.call("open_level", 8)
	var state: Dictionary = game.get("state")
	state["nutella"] = 900
	GvzLogic.place_tower(state, "moehrenschuetze", 1, 1)
	GvzLogic.place_tower(state, "doppelmoehre", 2, 1)
	GvzLogic.place_tower(state, "nutella_sammler", 2, 0)
	GvzLogic.place_tower(state, "eis_gooby", 3, 2)
	GvzZombies.spawn(state, "schlurfi", 2, 6800)
	GvzZombies.spawn(state, "huetchen", 1, 8200)
	GvzZombies.spawn(state, "eimer", 3, 8800)
	GvzZombies.spawn(state, "sprinter", 0, 7600)
	GvzZombies.spawn(state, "tuersteher", 4, 8300)
	GvzZombies.spawn(state, "zeitungsopa", 3, 7200)
	GvzZombies.spawn(state, "schlurfi", 0, 8600)
	# Anker-HP: während der Messung darf niemand sterben (Dichte halten).
	for zombie: Dictionary in state["zombies"]:
		zombie["hp"] = 999999
		zombie["max_hp"] = 999999
	await wait_frames(30)
	var alive := 0
	for zombie: Dictionary in state["zombies"]:
		if not bool(zombie["dead"]):
			alive += 1
	assert_eq(alive, 7, "Referenz-Dichte steht (7 Zombies leben)")
	assert_eq((state["towers"] as Dictionary).size(), 4, "4 Türme platziert")
	# ── Struktur-Budget (headless-tauglich) ──────────────────────────────
	var stage: Node3D = game.get("_stage")
	assert_true(stage != null, "Bühne existiert")
	var tally := {"units": 0, "tris": 0, "multimeshes": 0}
	_tally(stage, tally)
	assert_true(
		int(tally["units"]) <= STAGE_DRAW_UNIT_BUDGET,
		"Bühnen-Draw-Einheiten %d ≤ %d" % [int(tally["units"]), STAGE_DRAW_UNIT_BUDGET]
	)
	assert_true(
		int(tally["tris"]) <= STAGE_TRIANGLE_BUDGET,
		"Bühnen-Dreiecke %d ≤ %d" % [int(tally["tris"]), STAGE_TRIANGLE_BUDGET]
	)
	# Die Menge MUSS über MultiMesh laufen (Zombies, Türme, Mäher, Drops,
	# Rasen, Häuser, Kulissen-Schwärme) — sonst ist der Umbau rückgebaut.
	assert_true(
		int(tally["multimeshes"]) >= 12,
		"Figuren-Menge läuft über MultiMesh (%d aktiv)" % int(tally["multimeshes"])
	)
	print(
		(
			"  GVZ-PERF Struktur: draw_units=%d tris=%d multimeshes=%d"
			% [int(tally["units"]), int(tally["tris"]), int(tally["multimeshes"])]
		)
	)
	# ── Render-Budget (nur mit echtem Renderer aussagekräftig) ───────────
	var draws_max := 0
	var prims_max := 0
	for _i in 40:
		await tree.process_frame
		draws_max = maxi(
			draws_max,
			int(
				RenderingServer.get_rendering_info(
					RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME
				)
			)
		)
		prims_max = maxi(
			prims_max,
			int(
				RenderingServer.get_rendering_info(
					RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME
				)
			)
		)
	if draws_max == 0:
		print("  GVZ-PERF Rendering: Dummy-Renderer (headless) — Budget-Check übersprungen")
	else:
		assert_true(
			draws_max <= RENDER_DRAW_BUDGET,
			"Draw-Calls %d ≤ %d (Minigame-Budget)" % [draws_max, RENDER_DRAW_BUDGET]
		)
		assert_true(
			prims_max <= RENDER_PRIMITIVE_BUDGET,
			"Primitive %d ≤ %d" % [prims_max, RENDER_PRIMITIVE_BUDGET]
		)
		print("  GVZ-PERF Rendering: draws_max=%d prims_max=%d" % [draws_max, prims_max])
	game.queue_free()
	await wait_frames(1)


## Zählt sichtbare Geometry-Instanzen (≙ untere Draw-Call-Schranke) und
## Dreiecke unter `node`. Gepoolte GPUParticles3D-Bursts zählen nicht —
## sie senden nur im Effektmoment und sind im Referenz-Standbild leer.
func _tally(node: Node, acc: Dictionary) -> void:
	if node is MultiMeshInstance3D:
		var mmi := node as MultiMeshInstance3D
		if mmi.is_visible_in_tree() and mmi.multimesh != null:
			var count := mmi.multimesh.visible_instance_count
			if count < 0:
				count = mmi.multimesh.instance_count
			acc["units"] = int(acc["units"]) + 1
			acc["multimeshes"] = int(acc["multimeshes"]) + 1
			acc["tris"] = int(acc["tris"]) + _mesh_tris(mmi.multimesh.mesh) * count
	elif node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.is_visible_in_tree() and mi.mesh != null:
			acc["units"] = int(acc["units"]) + 1
			acc["tris"] = int(acc["tris"]) + _mesh_tris(mi.mesh)
	for child in node.get_children():
		_tally(child, acc)


func _mesh_tris(mesh: Mesh) -> int:
	if mesh == null:
		return 0
	@warning_ignore("integer_division")
	return mesh.get_faces().size() / 3
