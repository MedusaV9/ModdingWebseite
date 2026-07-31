extends TestCase
## GOB-NOM-View + Arcade-Integration: Registry-Kachel spielbar (ersetzt die
## „Bald!“-Kachel), Cover liegt da, Strings-Domain gobnom.* DE/EN-paritätisch,
## und die Spielszene durchläuft headless den W2d-Vertrag
## setup→start→open_level→Swipe-Schnitt→Sieg→finish_session mit Meldungen
## NUR über ctx.report_score/report_end. Dazu Level-Select-Sperren + Coop.

const GAME_SCENE := "res://scripts/minigames/games/gobnom/gobnom_game.tscn"

## Alle vom View benutzten gobnom.*-Keys (Banner, HUD, Overlays, Select).
const USED_KEYS := [
	"gobnom.select.title",
	"gobnom.select.campaign",
	"gobnom.select.coop",
	"gobnom.select.done",
	"gobnom.select.stars",
	"gobnom.select.new",
	"gobnom.hud.level",
	"gobnom.hud.coop_level",
	"gobnom.hud.cuts",
	"gobnom.hud.jar",
	"gobnom.hud.wrong_side",
	"gobnom.end.win",
	"gobnom.end.lose",
	"gobnom.end.lose_hint",
	"gobnom.end.score",
	"gobnom.end.first_clear",
	"gobnom.end.next",
	"gobnom.end.retry",
	"gobnom.end.select",
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


func _make_game(gs: Object, ctx: MinigameCtx) -> MinigameBase:
	var scene: PackedScene = load(GAME_SCENE)
	var game: MinigameBase = scene.instantiate()
	game.set("game_state_override", gs)
	tree.root.add_child(game)
	game.setup(ctx)
	game.start()
	return game


func _make_ctx(scores: Array, results: Array) -> MinigameCtx:
	var ctx := MinigameCtx.new()
	ctx.game_id = "gobnom"
	ctx.difficulty = "normal"
	ctx.run_seed = 7
	ctx.on_score = func(total: int, delta: int) -> void: scores.append([total, delta])
	ctx.on_end = func(result: Dictionary) -> void: results.append(result)
	return ctx


func test_registry_tile_is_playable() -> void:
	var meta := MinigameRegistry.get_game("gobnom")
	assert_false(meta.is_empty(), "gobnom in der Registry")
	assert_false(meta.get("coming_soon", false), "gobnom ist keine Bald!-Kachel mehr")
	assert_eq(str(meta.get("scene", "")), GAME_SCENE, "Szenen-Pfad")
	assert_eq(str(meta.get("orientation", "")), "landscape", "Querformat bevorzugt")
	assert_eq(int(meta.get("energy_cost", 0)), 8, "Energie-Gate wie die anderen Spiele")
	var ids: Array = []
	for game: Dictionary in MinigameRegistry.playable():
		ids.append(game["id"])
	assert_true(ids.has("gobnom"), "gobnom unter playable()")
	var coin_table: Dictionary = meta.get("coin_table", {})
	assert_true(int(coin_table.get("max", 0)) > int(coin_table.get("min", 0)), "Coin-Row sinnvoll")
	assert_true(
		ResourceLoader.exists(MinigameRegistry.cover_path("gobnom")), "Cover gobnom.png liegt da"
	)
	assert_true(ResourceLoader.exists(GAME_SCENE), "Szene existiert")
	var scene: PackedScene = load(GAME_SCENE)
	var game := scene.instantiate()
	assert_true(game is MinigameBase, "Szene erfüllt den MinigameBase-Vertrag")
	game.free()


func test_arcade_covers_have_gobnom() -> void:
	var arcade_script: GDScript = load("res://scripts/minigames/arcade_screen.gd")
	var covers: Dictionary = arcade_script.get_script_constant_map().get("COVERS", {})
	assert_true(covers.has("gobnom"), "ArcadeScreen.COVERS enthält gobnom")
	assert_true(covers["gobnom"] is Texture2D, "gobnom-Cover ist eine Textur")


func test_strings_domain_parity_and_keys() -> void:
	I18nService.reset_cache()
	var de := I18nService.table("de")
	var en := I18nService.table("en")
	for key: String in de:
		if key.begins_with("gobnom."):
			assert_true(en.has(key), "EN fehlt Key: %s" % key)
	for key: String in en:
		if key.begins_with("gobnom."):
			assert_true(de.has(key), "DE fehlt Key: %s" % key)
	for key: String in USED_KEYS:
		assert_true(de.has(key), "DE fehlt benutzter Key: %s" % key)
		assert_true(en.has(key), "EN fehlt benutzter Key: %s" % key)
	# Jedes intro-Tag beider Tracks hat einen Banner-Hinweis.
	for track: Array in [GobnomData.load_campaign(), GobnomData.load_coop()]:
		for level: Dictionary in track:
			var key := "gobnom.intro.%s" % str(level.get("intro", ""))
			assert_true(de.has(key), "DE fehlt Intro-Key: %s" % key)


func test_view_flow_swipe_cut_win_finish() -> void:
	var gs := GameStateDouble.new()
	var scores: Array = []
	var results: Array = []
	var game := _make_game(gs, _make_ctx(scores, results))
	assert_eq(str(game.get("phase")), "select", "Start im Level-Select")
	game.call("open_level", "campaign", 1)
	assert_eq(str(game.get("phase")), "play", "Nach open_level im Spiel")
	var state: Dictionary = game.get("state")
	assert_false(state.is_empty(), "Simulation initialisiert")
	var tick_before := int(state["tick"])
	for _i in 10:
		game._process(1.0 / 30.0)
	assert_true(int((game.get("state") as Dictionary)["tick"]) > tick_before, "Sim tickt")
	# Eingabe-Pfad: Swipe quer durchs L1-Seil (Anker 480,90 → Bonbon 480,150).
	var from: Vector2 = game.call("_to_screen", Vector2(400, 120))
	var to: Vector2 = game.call("_to_screen", Vector2(560, 120))
	game.call("_pointer_down", 0, from)
	game.call("_pointer_move", 0, to)
	assert_true(
		bool(((game.get("state") as Dictionary)["ropes"] as Array)[0]["cut"]), "Swipe kappt"
	)
	# Fall in den Mund komplett simulieren (L1 = senkrechte Linie mit Gläsern).
	for _i in 200:
		game._process(1.0 / 30.0)
		if str(game.get("phase")) != "play":
			break
	assert_eq(str(game.get("phase")), "won", "L1 über den ECHTEN Eingabe-Pfad gewonnen")
	assert_true(int(game.get("session_score")) > 0, "Session-Score gebucht")
	assert_eq(int(gs.get_value("gobnom.stars.c1", 0)), 3, "3 Gläser = 3 Sterne im Slice")
	assert_true(bool(gs.get_value("gobnom.cleared.c1", false)), "Fortschritt im Slice")
	assert_true(scores.size() > 0, "ctx.report_score wurde benutzt")
	game.call("finish_session")
	assert_eq(results.size(), 1, "report_end genau einmal")
	assert_eq(int(results[0]["score"]), int(game.get("session_score")), "End-Score = Session")
	game.free()


func test_view_coop_touch_acts_as_side_player() -> void:
	var gs := GameStateDouble.new()
	var game := _make_game(gs, _make_ctx([], []))
	game.call("open_level", "coop", 1)
	var state: Dictionary = game.get("state")
	assert_true(bool(state["coop"]), "Coop-Level läuft im Coop-Modus")
	# Berührung in der RECHTEN Hälfte swiped als Spieler B über As Seil
	# (Anker links) — die Sim verweigert, das Seil bleibt dran.
	var from: Vector2 = game.call("_to_screen", Vector2(600, 170))
	var to: Vector2 = game.call("_to_screen", Vector2(760, 170))
	game.call("_pointer_down", 1, from)
	game.call("_pointer_move", 1, to)
	assert_false(bool((state["ropes"] as Array)[0]["cut"]), "As Anker bleibt für B tabu")
	# Dieselbe Geste in der LINKEN Hälfte (Spieler A) kappt As Seil.
	from = game.call("_to_screen", Vector2(200, 170))
	to = game.call("_to_screen", Vector2(400, 170))
	game.call("_pointer_down", 2, from)
	game.call("_pointer_move", 2, to)
	assert_true(bool((state["ropes"] as Array)[0]["cut"]), "A schneidet den eigenen Anker")
	game.free()


func test_view_lost_shows_retry_and_records_nothing() -> void:
	var gs := GameStateDouble.new()
	var game := _make_game(gs, _make_ctx([], []))
	game.call("open_level", "campaign", 1)
	var state: Dictionary = game.get("state")
	state["outcome"] = "lost"
	game._process(1.0 / 30.0)
	assert_eq(str(game.get("phase")), "lost", "Niederlage-Phase erreicht")
	assert_false(bool(gs.get_value("gobnom.cleared.c1", false)), "kein Fortschritt gebucht")
	assert_eq(int(game.get("session_score")), 0, "keine Punkte für Niederlagen")
	game.free()


func test_level_select_locks_tracks_and_refresh() -> void:
	var gs := GameStateDouble.new()
	var select := GobnomLevelSelect.new()
	select.game_state = gs
	tree.root.add_child(select)
	await wait_frames(2)
	var buttons: Dictionary = select.get("_buttons")
	assert_eq(buttons.size(), 25, "15 Kampagnen- + 10 Coop-Kacheln")
	assert_false((buttons["c1"] as Button).disabled, "L1 offen")
	assert_true((buttons["c2"] as Button).disabled, "L2 gesperrt")
	assert_false((buttons["n1"] as Button).disabled, "CN1 unabhängig offen")
	GobnomProgress.record_win(gs, GobnomProgress.TRACK_CAMPAIGN, 1, 3, 100)
	select.refresh()
	assert_false((buttons["c2"] as Button).disabled, "L2 nach L1-Sieg offen")
	# W15/GAMESQA2: Sterne wohnen jetzt im goldenen Stempel-Label der Kachel.
	var stamps: Dictionary = select.get("_stamps")
	assert_true((stamps["c1"] as Label).text.contains("★★★"), "Sterne auf dem Kachel-Stempel")
	var chosen: Array = []
	select.level_chosen.connect(func(track: String, id: int) -> void: chosen.append([track, id]))
	(buttons["n1"] as Button).pressed.emit()
	assert_eq(chosen, [["coop", 1]], "Kachel-Klick meldet Track + Id")
	select.free()
