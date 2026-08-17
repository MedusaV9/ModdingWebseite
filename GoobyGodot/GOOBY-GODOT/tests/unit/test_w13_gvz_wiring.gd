extends TestCase
## W13/GVZ — Verdrahtung (P5-Report G18 + P1-B11):
## (a) Goldi-Code: „GOLDIGOLD“ setzt gvz.goldi über den neuen
##     unlock_flag-Effekt (CodesEngine + CodesScreen), Feier-Text inklusive,
##     Pack-Katalog (content/codes) bleibt per sha256 mit der Engine synchron.
## (b) Sticker erreichbar: die pure Sim zählt Run-Stats deterministisch
##     (Seed injiziert, keine OS-Uhr), das Rundenende bucht sie in die
##     achievements.counters der stickers.json-Conds und L5/10/15-Siege
##     feuern die Event-Hooks (L15 = gvz_kampagne → „Garten gerettet!“).
## (c) B11: der Level-Select ist size-verwaltet — gleichseitige Anker auch
##     nach feindlichem FULL_RECT-Preset; der Fortschritts-Balken bleibt
##     rein Anker-verwaltet.

const SaveSchema := preload("res://scripts/state/save_schema.gd")

const GAME_SCENE := "res://scripts/minigames/games/gvz/gvz_game.tscn"
const PACK_CODES := "res://content/codes/data/codes.json"

const NOW := 1768478400000


## GameState-Double (Duck-Typing wie /root/GameState, Muster test_gvz_game).
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


## Voller Save-State-Fake für den CodesScreen (Muster test_rest4_codes).
class FakeGameState:
	extends RefCounted
	var s: Dictionary = {}
	var slices_notified: Array[String] = []

	func _init() -> void:
		s = SaveSchema.default_state(NOW)

	func state() -> Dictionary:
		return s

	func get_value(path: String, fallback: Variant = null) -> Variant:
		var node: Variant = s
		for part in path.split("."):
			if node is Dictionary and (node as Dictionary).has(part):
				node = node[part]
			else:
				return fallback
		return node

	func update(mutator: Callable) -> void:
		mutator.call(s)

	func notify_slice_changed(slice_id: String) -> void:
		slices_notified.append(slice_id)


## ---------------------------------------------------------- (a) Goldi-Code


func test_goldi_code_setzt_flag_und_feiert() -> void:
	var gs := FakeGameState.new()
	assert_false(GvzProgress.goldi_unlocked(gs), "frischer Save: Goldi gesperrt")
	var screen: CodesScreen = CodesScreen.new()
	screen.gs_override = gs
	screen.now_override = NOW
	screen.auto_navigate = false
	tree.root.add_child(screen)
	await wait_frames(2)
	screen.set_input_text(" GOLDI Gold ")
	var result := screen.redeem_now()
	assert_true(bool(result.get("ok", false)), "GOLDIGOLD löst ein")
	assert_true(bool(gs.get_value("gvz.goldi", false)), "gvz.goldi sitzt im Save")
	assert_true(GvzProgress.goldi_unlocked(gs), "GvzProgress sieht das Flag")
	assert_true(gs.slices_notified.has("gvz"), "gvz-Slice benachrichtigt")
	assert_true(
		screen.feedback_text().contains(I18nService.t("codes.erfolg.flag.goldiGold")),
		"Feier-Text für Goldi wird angezeigt"
	)
	assert_true(
		screen.find_child("Verlauf_goldiGold", true, false) != null, "Verlauf zeigt den Goldi-Code"
	)
	screen.set_input_text("goldigold")
	assert_eq(str(screen.redeem_now()["reason"]), "already", "once-Code nur einmal")
	screen.queue_free()
	await wait_frames(1)


func test_goldi_pack_katalog_synchron_zur_engine() -> void:
	var engine_code := CodesEngine.code_by_id("goldiGold")
	assert_false(engine_code.is_empty(), "goldiGold im Engine-Katalog")
	assert_eq(
		str((engine_code["effect"] as Dictionary).get("unlock_flag", "")),
		"gvz.goldi",
		"Effekt zeigt auf das GvZ-Gate"
	)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PACK_CODES))
	assert_true(parsed is Dictionary, "Pack-Katalog parst")
	var eintrag := {}
	for item: Variant in (parsed as Dictionary).get("items", []):
		if item is Dictionary and str((item as Dictionary).get("id", "")) == "goldiGold":
			eintrag = item
	assert_false(eintrag.is_empty(), "goldiGold im Pack-Katalog (content/codes)")
	assert_eq(
		str(eintrag.get("secret_sha256", "")),
		str(engine_code["secret"]).sha256_text(),
		"Pack-sha256 == sha256(Engine-Secret) — kein Klartext im Pack"
	)
	var effect: Dictionary = eintrag.get("effect", {})
	assert_eq(str(effect.get("type", "")), "unlock_flag", "Pack-Effekt-Typ")
	assert_eq(str(effect.get("flag", "")), "gvz.goldi", "Pack-Flag-Pfad")


func test_goldi_flag_landet_im_spielfluss() -> void:
	var gs := GameStateDouble.new()
	gs.state = {"gvz": {"goldi": true}}
	var ctx := MinigameCtx.new()
	ctx.game_id = "gvz"
	ctx.difficulty = "normal"
	ctx.run_seed = 3
	var scene: PackedScene = load(GAME_SCENE)
	var game: MinigameBase = scene.instantiate()
	game.set("game_state_override", gs)
	tree.root.add_child(game)
	game.setup(ctx)
	game.start()
	game.call("open_level", 1)
	var state: Dictionary = game.get("state")
	assert_true(
		GvzLogic.available_towers(state).has("goldi"),
		"eingelöster Code schaltet Goldi im Lauf frei"
	)
	game.free()


## ------------------------------------------------- (b) Stats/Counter/Hooks


func _stat_level() -> Dictionary:
	return {
		"id": 1,
		"lanes": [0, 1, 2, 3, 4],
		"start_nutella": 800,
		"unlock_towers": ["moehrenschuetze", "eis_gooby", "dicker_bert"],
		"spawns": [{"t": 1.0, "lane": 0, "type": "schlurfi"}],
		"waves": [],
	}


func test_run_stats_zaehlen_deterministisch_in_der_sim() -> void:
	var state := GvzLogic.new_run(_stat_level(), GvzData.load_balance(null), "normal", 7)
	assert_true(bool(GvzLogic.place_tower(state, "moehrenschuetze", 0, 0)["ok"]))
	assert_true(bool(GvzLogic.place_tower(state, "eis_gooby", 0, 1)["ok"]))
	assert_true(bool(GvzLogic.place_tower(state, "dicker_bert", 1, 0)["ok"]))
	var collected := false
	while not GvzLogic.is_over(state) and int(state["tick"]) < 4000:
		GvzLogic.tick(state)
		if not collected and not (state["drops"] as Array).is_empty():
			var drop: Dictionary = (state["drops"] as Array)[0]
			assert_true(GvzLogic.collect_drop(state, int(drop["id"])) > 0)
			collected = true
	assert_eq(str(state["outcome"]), "won", "Referenzlauf gewinnt")
	var stats: Dictionary = state["stats"]
	assert_eq(int(stats["eis_placed"]), 1, "Eis-Gooby-Einsatz gezählt")
	assert_eq(int(stats["bert_placed"]), 1, "Bert-Einsatz gezählt")
	assert_true(int(stats["moehren_shots"]) > 0, "Möhren-Schüsse gezählt")
	assert_true(collected and int(stats["drops_collected"]) == 1, "Nutella-Glas gezählt")
	assert_true(int(state["kills"]) >= 1, "Zombie gestoppt")
	# PvP-/Replay-Schutz: stats verändern den State-Hash NICHT.
	var hash_before := GvzLogic.state_hash(state)
	GvzLogic.bump_stat(state, "moehren_shots", 99)
	assert_eq(GvzLogic.state_hash(state), hash_before, "stats sind hash-neutral")


func _run_over(game: MinigameBase, level_id: int, outcome: String) -> void:
	game.call("open_level", level_id)
	var state: Dictionary = game.get("state")
	state["stats"] = {"drops_collected": 3, "eis_placed": 2, "bert_placed": 1, "moehren_shots": 40}
	state["kills"] = 5
	state["outcome"] = outcome
	game._process(0.05)


func test_rundenende_bucht_counter_und_meilenstein_hooks() -> void:
	var gs := GameStateDouble.new()
	var ctx := MinigameCtx.new()
	ctx.game_id = "gvz"
	ctx.difficulty = "normal"
	ctx.run_seed = 11
	var scene: PackedScene = load(GAME_SCENE)
	var game: MinigameBase = scene.instantiate()
	game.set("game_state_override", gs)
	tree.root.add_child(game)
	game.setup(ctx)
	game.start()
	# L1-Sieg: Counter laufen, aber KEIN Meilenstein-Hook.
	_run_over(game, 1, "won")
	assert_eq(int(gs.get_value("achievements.counters.gvzNutella", 0)), 3)
	assert_eq(int(gs.get_value("achievements.counters.gvzEisEinsaetze", 0)), 2)
	assert_eq(int(gs.get_value("achievements.counters.gvzBertEinsaetze", 0)), 1)
	assert_eq(int(gs.get_value("achievements.counters.gvzMoehrenSchuesse", 0)), 40)
	assert_eq(int(gs.get_value("achievements.counters.gvzZombiesGestoppt", 0)), 5)
	assert_true(gs.notified.has("achievements"), "RewardHub-Auswertung angestoßen")
	assert_eq(gs.get_value("stickers.hooks", {}), {}, "L1 feuert keinen Hook")
	# L5/L10/L15-Siege feuern ihre Hooks (Board→Sieg→Award-Pfad).
	game.call("back_to_select")
	_run_over(game, 5, "won")
	assert_true(bool(gs.get_value("stickers.hooks.gvz_l5", false)), "L5-Hook")
	game.call("back_to_select")
	_run_over(game, 10, "won")
	assert_true(bool(gs.get_value("stickers.hooks.gvz_l10", false)), "L10-Hook")
	game.call("back_to_select")
	_run_over(game, 15, "won")
	assert_true(bool(gs.get_value("stickers.hooks.gvz_kampagne", false)), "L15 = Kampagne")
	# Counter kumulieren über die Runden (4 Siege × 3 Gläser).
	assert_eq(int(gs.get_value("achievements.counters.gvzNutella", 0)), 12)
	game.free()


func test_niederlage_bucht_counter_aber_keinen_hook() -> void:
	var gs := GameStateDouble.new()
	var ctx := MinigameCtx.new()
	ctx.game_id = "gvz"
	ctx.difficulty = "normal"
	ctx.run_seed = 13
	var scene: PackedScene = load(GAME_SCENE)
	var game: MinigameBase = scene.instantiate()
	game.set("game_state_override", gs)
	tree.root.add_child(game)
	game.setup(ctx)
	game.start()
	_run_over(game, 15, "lost")
	assert_eq(int(gs.get_value("achievements.counters.gvzNutella", 0)), 3, "gesammelt bleibt")
	assert_eq(gs.get_value("stickers.hooks", {}), {}, "Niederlage feuert keinen Hook")
	game.free()


func test_alle_gvz_sticker_conds_sind_erfuellbar() -> void:
	# Save-Zustand, den der verdrahtete Spielfluss real erzeugt (Counter über
	# _book_sticker_progress, Hooks über die L5/L10/L15-Siege) — jede der
	# Conds aus stickers.json muss damit erfüllbar sein. W13B/STICKER: die
	# Meilenstein-Hooks gvz_l5/gvz_l10 haben jetzt Katalog-Sticker → 8.
	var state := {
		"achievements":
		{
			"counters":
			{
				"gvzNutella": 100,
				"gvzEisEinsaetze": 10,
				"gvzMoehrenSchuesse": 500,
				"gvzBertEinsaetze": 10,
				"gvzZombiesGestoppt": 50,
			}
		},
		"stickers":
		{
			"unlocked": {},
			"hooks": {"gvz_l5": true, "gvz_l10": true, "gvz_kampagne": true},
		},
	}
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/stickers/data/stickers.json")
	)
	var gvz_defs: Array = []
	for def: Variant in (parsed as Dictionary).get("items", []):
		if def is Dictionary and str((def as Dictionary).get("set", "")) == "gvz":
			gvz_defs.append(def)
	assert_eq(gvz_defs.size(), 8, "8 GvZ-Sticker im Katalog (6 + 2 Meilensteine)")
	for def: Dictionary in gvz_defs:
		assert_true(
			StickerUnlocks.cond_met(def.get("cond", {}), state),
			"Cond erreichbar: %s" % str(def.get("id"))
		)


## ----------------------------------------------------------------- (c) B11


func test_b11_level_select_haelt_anker_gleichseitig() -> void:
	var gs := GameStateDouble.new()
	var select := GvzLevelSelect.new()
	select.game_state = gs
	tree.root.add_child(select)
	await wait_frames(1)
	# Feindlicher Host-Preset (der alte gvz_game-Pfad): _fit_viewport muss
	# die Anker neutralisieren — size-verwaltete Nodes ohne Stretch-Anker.
	select.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	select.call("_fit_viewport")
	assert_eq(select.anchor_left, select.anchor_right, "Anker horizontal gleichseitig")
	assert_eq(select.anchor_top, select.anchor_bottom, "Anker vertikal gleichseitig")
	assert_eq(select.size, select.get_viewport_rect().size, "Rect = Viewport")
	assert_eq(select.position, Vector2.ZERO, "Optik unverändert (Ursprung)")
	# Der Fortschritts-Balken bleibt rein Anker-verwaltet (Anker ODER size).
	var fill: ColorRect = select.get("_progress_fill")
	GvzProgress.record_win(gs, 1, 3, 100)
	select.refresh()
	assert_almost(fill.anchor_right, clampf(3.0 / 45.0, 0.05, 1.0), 1e-6, "Balken via Anker")
	assert_eq(fill.anchor_left, 0.0, "Balken-Anker links fix")
	select.free()


func test_b11_gvz_game_setzt_keine_stretch_anker_mehr() -> void:
	var gs := GameStateDouble.new()
	var ctx := MinigameCtx.new()
	ctx.game_id = "gvz"
	ctx.difficulty = "normal"
	ctx.run_seed = 1
	var scene: PackedScene = load(GAME_SCENE)
	var game: MinigameBase = scene.instantiate()
	game.set("game_state_override", gs)
	tree.root.add_child(game)
	game.setup(ctx)
	var select: Control = game.get("_select_screen")
	assert_true(select != null, "Select-Screen gebaut")
	assert_eq(select.anchor_left, select.anchor_right, "kein Stretch-Anker (B11)")
	assert_eq(select.anchor_top, select.anchor_bottom, "kein Stretch-Anker (B11)")
	game.free()
