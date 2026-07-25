extends TestCase
## GvZ-View + Arcade-Integration (W3b): Registry-Kachel spielbar, Szene lädt,
## Strings-Domain gvz.* DE/EN-paritätisch, und die Spielszene durchläuft
## headless den Vertrag setup→start→open_level→Sieg→finish_session mit
## Score-Meldungen NUR über ctx.report_score/report_end.

const GAME_SCENE := "res://scripts/minigames/games/gvz/gvz_game.tscn"

## Alle vom View benutzten gvz.*-Keys (Banner, Karten, Overlays, Select).
const USED_KEYS := [
	"gvz.select.title",
	"gvz.select.done",
	"gvz.select.stars",
	"gvz.hud.level",
	"gvz.hud.wave",
	"gvz.hud.huge_wave",
	"gvz.hud.boss",
	"gvz.hud.boss_phase",
	"gvz.hud.free",
	"gvz.hud.reason_nutella",
	"gvz.hud.reason_cooldown",
	"gvz.hud.reason_cell_occupied",
	"gvz.hud.reason_locked",
	"gvz.end.win",
	"gvz.end.lose",
	"gvz.end.score",
	"gvz.end.first_clear",
	"gvz.end.lose_hint",
	"gvz.end.next",
	"gvz.end.retry",
	"gvz.end.select",
]


class GameStateDouble:
	extends RefCounted
	var state := {}
	var notified: Array = []

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

	func notify_slice_changed(slice_id: String) -> void:
		notified.append(slice_id)


func test_registry_tile_is_playable() -> void:
	var meta := MinigameRegistry.get_game("gvz")
	assert_false(meta.is_empty(), "gvz in der Registry")
	assert_false(meta.get("coming_soon", false), "gvz ist keine Bald!-Kachel mehr")
	assert_eq(str(meta.get("scene", "")), GAME_SCENE, "Szenen-Pfad")
	assert_eq(str(meta.get("orientation", "")), "landscape", "Querformat bevorzugt")
	var ids: Array = []
	for game: Dictionary in MinigameRegistry.playable():
		ids.append(game["id"])
	assert_true(ids.has("gvz"), "gvz unter playable()")
	var coin_table: Dictionary = meta.get("coin_table", {})
	assert_true(int(coin_table.get("max", 0)) > int(coin_table.get("min", 0)), "Coin-Row sinnvoll")
	assert_true(ResourceLoader.exists(MinigameRegistry.cover_path("gvz")), "Cover gvz.png liegt da")
	assert_true(ResourceLoader.exists(GAME_SCENE), "Szene existiert")
	var scene: PackedScene = load(GAME_SCENE)
	var game := scene.instantiate()
	assert_true(game is MinigameBase, "Szene erfüllt den MinigameBase-Vertrag")
	game.free()


func test_arcade_covers_have_gvz() -> void:
	var arcade_script: GDScript = load("res://scripts/minigames/arcade_screen.gd")
	var covers: Dictionary = arcade_script.get_script_constant_map().get("COVERS", {})
	assert_true(covers.has("gvz"), "ArcadeScreen.COVERS enthält gvz")
	assert_true(covers["gvz"] is Texture2D, "gvz-Cover ist eine Textur")


func test_strings_domain_parity_and_keys() -> void:
	I18nService.reset_cache()
	var de := I18nService.table("de")
	var en := I18nService.table("en")
	for key: String in de:
		if key.begins_with("gvz."):
			assert_true(en.has(key), "EN fehlt Key: %s" % key)
	for key: String in en:
		if key.begins_with("gvz."):
			assert_true(de.has(key), "DE fehlt Key: %s" % key)
	for key: String in USED_KEYS:
		assert_true(de.has(key), "DE fehlt benutzter Key: %s" % key)
		assert_true(en.has(key), "EN fehlt benutzter Key: %s" % key)


func test_view_flow_battle_win_finish() -> void:
	var gs := GameStateDouble.new()
	var scores: Array = []
	var results: Array = []
	var ctx := MinigameCtx.new()
	ctx.game_id = "gvz"
	ctx.difficulty = "normal"
	ctx.run_seed = 7
	ctx.on_score = func(total: int, delta: int) -> void: scores.append([total, delta])
	ctx.on_end = func(result: Dictionary) -> void: results.append(result)
	var scene: PackedScene = load(GAME_SCENE)
	var game: MinigameBase = scene.instantiate()
	game.set("game_state_override", gs)
	tree.root.add_child(game)
	game.setup(ctx)
	game.start()
	assert_eq(str(game.get("phase")), "select", "Start im Level-Select")
	game.call("open_level", 1)
	assert_eq(str(game.get("phase")), "battle", "Nach open_level im Gefecht")
	var state: Dictionary = game.get("state")
	assert_false(state.is_empty(), "Simulation initialisiert")
	var tick_before := int(state["tick"])
	for _i in 30:
		game._process(0.05)
	assert_true(int((game.get("state") as Dictionary)["tick"]) > tick_before, "Simulation tickt")
	# Eingabe-Pfad: Karte antippen → Zelle antippen → Turm steht.
	var picked: Dictionary = game.get("state")
	picked["nutella"] = 1000
	game.call("_touch_down", (game.call("_card_rect", 0) as Rect2).get_center())
	assert_ne(str(game.get("selected_card")), "", "Karte ausgewählt")
	game.call("_touch_down", game.call("_cell_center", 2, 1))
	assert_eq((picked["towers"] as Dictionary).size(), 1, "Turm über Touch platziert")
	# Sieg erzwingen (Simulations-Sieg testet test_gvz_logic) → Overlay + Slice.
	picked["outcome"] = "won"
	game._process(0.05)
	assert_eq(str(game.get("phase")), "won", "Sieg-Phase erreicht")
	assert_true(int(game.get("session_score")) > 0, "Session-Score gebucht")
	assert_true(bool(gs.get_value("gvz.cleared.1", false)), "Fortschritt im GameState-Slice")
	assert_true(scores.size() > 0, "ctx.report_score wurde benutzt")
	game.call("finish_session")
	assert_eq(results.size(), 1, "report_end genau einmal")
	assert_true(results[0].has("score"), "Ergebnis enthält score")
	assert_eq(int(results[0]["score"]), int(game.get("session_score")), "End-Score = Session")
	game.free()


func test_level_select_locks_and_refresh() -> void:
	var gs := GameStateDouble.new()
	var select := GvzLevelSelect.new()
	select.game_state = gs
	tree.root.add_child(select)
	await wait_frames(2)
	var buttons: Dictionary = select.get("_buttons")
	assert_eq(buttons.size(), 15, "15 Level-Kacheln")
	assert_false((buttons[1] as Button).disabled, "L1 offen")
	assert_true((buttons[2] as Button).disabled, "L2 gesperrt")
	GvzProgress.record_win(gs, 1, 3, 100)
	select.refresh()
	assert_false((buttons[2] as Button).disabled, "L2 nach L1-Sieg offen")
	assert_true((buttons[1] as Button).text.contains("★★★"), "Sterne auf der Kachel")
	var chosen: Array = []
	select.level_chosen.connect(func(id: int) -> void: chosen.append(id))
	(buttons[1] as Button).pressed.emit()
	assert_eq(chosen, [1], "Kachel-Klick meldet Level-Id")
	select.free()
