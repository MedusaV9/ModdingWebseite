extends TestCase
## W1d — game_state.gd: Store-API, Signal-Kontrakt (W1c!), Persistenz-Kopplung.

const GameStateScript := preload("res://scripts/state/game_state.gd")

const NOW_MS := 1768478400000

var _dir_seq := 0


func _fresh_path() -> String:
	_dir_seq += 1
	var dir := "user://w1d_tests/gs_%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	return dir + "/save_v5.json"


func _fresh_game_state(path: String) -> Node:
	var gs: Node = GameStateScript.new()
	gs.clock.pin(NOW_MS)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(path)
	return gs


func test_initialize_emits_loaded_and_initial_values() -> void:
	var gs := _fresh_game_state(_fresh_path())
	var seen := {"coins": [], "loaded": []}
	gs.coins_changed.connect(func(c: int) -> void: seen["coins"].append(c))
	gs.state_loaded.connect(func(f: bool, r: bool) -> void: seen["loaded"].append([f, r]))
	gs.initialize(_fresh_path())
	assert_eq(seen["loaded"], [[true, false]], "frischer Save")
	assert_eq(seen["coins"], [100], "Initial-Emit nach Load")
	gs.free()


func test_set_value_and_signals() -> void:
	var gs := _fresh_game_state(_fresh_path())
	var coins_seen: Array = []
	var stats_seen: Array = []
	var level_seen: Array = []
	gs.coins_changed.connect(func(c: int) -> void: coins_seen.append(c))
	gs.stats_changed.connect(func(s: Dictionary) -> void: stats_seen.append(s.duplicate()))
	gs.level_changed.connect(func(l: int, r: float) -> void: level_seen.append([l, r]))
	gs.set_value("economy.coins", 555)
	assert_eq(gs.get_value("economy.coins"), 555)
	assert_eq(coins_seen, [555])
	gs.set_value("gooby.stats.energy", 12.0)
	assert_eq(stats_seen.size(), 1)
	assert_eq(stats_seen[0]["energy"], 12.0)
	gs.update(
		func(s: Dictionary) -> void:
			s["progression"]["level"] = 2
			s["progression"]["xp"] = 75
	)
	assert_eq(level_seen.size(), 1)
	assert_eq(level_seen[0][0], 2)
	assert_almost(level_seen[0][1], 0.5, 1e-9, "xp_ratio 75/150")
	gs.set_value("economy.coins", 555)
	assert_eq(coins_seen, [555], "unveraenderter Wert emittiert NICHT")
	gs.free()


func test_vacation_signal_and_slice_notify() -> void:
	var gs := _fresh_game_state(_fresh_path())
	var vac_seen: Array = []
	var slice_seen: Array = []
	gs.vacation_changed.connect(func(p: String, d: String) -> void: vac_seen.append([p, d]))
	gs.slice_changed.connect(func(id: String, _data: Variant) -> void: slice_seen.append(id))
	gs.update(
		func(s: Dictionary) -> void:
			s["vacation"]["phase"] = "away"
			s["vacation"]["destId"] = "beach"
	)
	assert_eq(vac_seen, [["away", "beach"]])
	gs.notify_slice_changed("stickers")
	assert_eq(slice_seen, ["stickers"])
	gs.free()


func test_w1c_onboarding_and_news_contract() -> void:
	var gs := _fresh_game_state(_fresh_path())
	(
		gs
		. apply_onboarding_profile(
			{
				"player_name": "  Mia  ",
				"gooby_nickname": "",
				"editor": {"eyes_apart": 0.5, "eye_scale": 1.2, "ear_len": 0.8, "chubby": 0.3},
			}
		)
	)
	assert_eq(gs.get_value("meta.playerName"), "Mia", "getrimmt")
	assert_eq(gs.get_value("meta.goobyNickname"), "Gooby", "leer → Default")
	assert_eq(gs.get_value("meta.charMorphs.eyes_apart"), 0.5)
	assert_true(gs.get_value("onboarding.done"))
	assert_false(gs.get_value("onboarding.whatsNew5Seen"))
	gs.mark_news_50_seen()
	assert_true(gs.get_value("onboarding.whatsNew5Seen"))
	gs.free()


func test_save_and_reload_persists() -> void:
	var path := _fresh_path()
	var gs := _fresh_game_state(path)
	gs.set_value("economy.coins", 9000)
	gs.apply_onboarding_profile({"player_name": "Kim", "gooby_nickname": "Flausch"})
	assert_true(gs.save_now())
	gs.free()
	var gs2 := _fresh_game_state(path)
	assert_eq(gs2.get_value("economy.coins"), 9000)
	assert_eq(gs2.get_value("meta.playerName"), "Kim")
	assert_eq(gs2.get_value("meta.goobyNickname"), "Flausch")
	gs2.free()


func test_xp_ratio_full_at_max_level() -> void:
	var gs := _fresh_game_state(_fresh_path())
	gs.update(
		func(s: Dictionary) -> void:
			s["progression"]["level"] = 40
			s["progression"]["xp"] = 0
	)
	assert_eq(gs.xp_ratio(), 1.0, "Ring voll bei MAX_LEVEL")
	gs.free()
