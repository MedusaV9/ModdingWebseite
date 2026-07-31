extends TestCase
## BUGHUNT-P1 — Regressionstests: gooby_ticker.gd + GameState-Verdrahtung.
##
## Abgesicherter Bug: Die pure Lebenslogik (Offline.simulate_offline,
## Stats.apply_tick, Sleep.tick_sleep) wurde in Produktion NIE aufgerufen —
## Stats verfielen nie, Offline-Zeit wurde nie nachgeholt, schlafende Goobys
## (importierte Saves) schliefen fuer immer. Diese Tests nageln fest, dass
## initialize()/run_live_tick()/run_catch_up() die Logik wirklich fahren.

const GameStateScript := preload("res://scripts/state/game_state.gd")
const GoobyTicker := preload("res://scripts/state/gooby_ticker.gd")

const NOW_MS := 1768478400000
const MIN_MS := 60000

var _dir_seq := 0


func _fresh_path() -> String:
	_dir_seq += 1
	var dir := "user://bughunt_tests/ticker_%d_%d" % [Time.get_ticks_usec(), _dir_seq]
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	return dir + "/save_v5.json"


func _fresh_game_state(path: String, now_ms := NOW_MS) -> Node:
	var gs: Node = GameStateScript.new()
	gs.clock.pin(now_ms)
	gs.clock.set_utc_offset_minutes(0)
	gs.initialize(path)
	return gs


func test_live_tick_decays_stats_awake() -> void:
	var gs := _fresh_game_state(_fresh_path())
	gs.set_value("gooby.lastTickAt", NOW_MS)
	gs.clock.advance(10 * MIN_MS)
	gs.run_live_tick()
	# §C1 wache Raten pro Minute: hunger -0.35, energy -0.25, hygiene -0.15,
	# fun -0.5 — Startwerte 80/90/85/70.
	assert_almost(gs.get_value("gooby.stats.hunger"), 76.5, 1e-6, "hunger -3.5")
	assert_almost(gs.get_value("gooby.stats.energy"), 87.5, 1e-6, "energy -2.5")
	assert_almost(gs.get_value("gooby.stats.hygiene"), 83.5, 1e-6, "hygiene -1.5")
	assert_almost(gs.get_value("gooby.stats.fun"), 65.0, 1e-6, "fun -5.0")
	assert_eq(int(gs.get_value("gooby.lastTickAt")), NOW_MS + 10 * MIN_MS, "Basislinie rueckt vor")
	gs.free()


func test_live_tick_emits_stats_changed_and_stat_low() -> void:
	var gs := _fresh_game_state(_fresh_path())
	gs.set_value("gooby.stats.fun", 26.0)
	gs.set_value("gooby.lastTickAt", NOW_MS)
	var stats_seen: Array = []
	var events_seen: Array = []
	gs.stats_changed.connect(func(s: Dictionary) -> void: stats_seen.append(s.duplicate()))
	gs.gooby_events.connect(func(ev: Array) -> void: events_seen.append_array(ev))
	gs.clock.advance(10 * MIN_MS)
	gs.run_live_tick()
	assert_eq(stats_seen.size(), 1, "stats_changed feuert")
	assert_true(
		events_seen.has("statLow:fun"), "fun kreuzt 25 → statLow:fun (got %s)" % [events_seen]
	)
	gs.free()


func test_live_tick_completes_sleep_with_grants() -> void:
	var gs := _fresh_game_state(_fresh_path())
	gs.set_value("gooby.stats.energy", 50.0)
	gs.set_value(
		"gooby.sleep", {"sleeping": true, "startedAt": NOW_MS, "wakeAt": NOW_MS + 10 * MIN_MS}
	)
	gs.set_value("gooby.lastTickAt", NOW_MS)
	var events_seen: Array = []
	gs.gooby_events.connect(func(ev: Array) -> void: events_seen.append_array(ev))
	gs.clock.advance(11 * MIN_MS)
	gs.run_live_tick()
	assert_false(bool(gs.get_value("gooby.sleep.sleeping")), "aufgewacht")
	# 10 Schlafminuten fuellen energy: 50 + 3.334*10 = 83.34.
	assert_almost(gs.get_value("gooby.stats.energy"), 83.34, 1e-6, "energy gefuellt")
	assert_eq(gs.get_value("progression.xp"), 10.0, "Schlaf-Grant XP +10")
	assert_eq(int(gs.get_value("achievements.counters.sleeps")), 1, "sleeps-Zaehler")
	assert_true(events_seen.has("wokeUp"), "wokeUp-Event (got %s)" % [events_seen])
	gs.free()


func test_initialize_catches_up_offline_decay() -> void:
	var path := _fresh_path()
	var gs := _fresh_game_state(path)
	gs.set_value("gooby.lastTickAt", NOW_MS - 120 * MIN_MS)
	assert_true(gs.save_now())
	gs.free()
	# Neustart: 120 min Offline-Zeit → 0.3x wache Raten (§E4).
	var gs2 := _fresh_game_state(path)
	assert_almost(gs2.get_value("gooby.stats.hunger"), 80.0 - 0.35 * 120 * 0.3, 1e-6, "hunger 0.3x")
	assert_almost(gs2.get_value("gooby.stats.fun"), 70.0 - 0.5 * 120 * 0.3, 1e-6, "fun 0.3x")
	assert_eq(int(gs2.get_value("gooby.lastTickAt")), NOW_MS, "Basislinie = jetzt")
	gs2.free()


func test_initialize_completes_overdue_sleep_exactly_once() -> void:
	var path := _fresh_path()
	var gs := _fresh_game_state(path)
	gs.set_value("gooby.stats.energy", 40.0)
	gs.set_value(
		"gooby.sleep",
		{"sleeping": true, "startedAt": NOW_MS - 120 * MIN_MS, "wakeAt": NOW_MS - 60 * MIN_MS}
	)
	gs.set_value("gooby.lastTickAt", NOW_MS - 120 * MIN_MS)
	assert_true(gs.save_now())
	gs.free()
	var events_seen: Array = []
	var gs2: Node = GameStateScript.new()
	gs2.clock.pin(NOW_MS)
	gs2.clock.set_utc_offset_minutes(0)
	gs2.gooby_events.connect(func(ev: Array) -> void: events_seen.append_array(ev))
	gs2.initialize(path)
	assert_false(bool(gs2.get_value("gooby.sleep.sleeping")), "ueberfaelliger Schlaf beendet")
	assert_eq(gs2.get_value("progression.xp"), 10.0, "Grant genau einmal")
	assert_eq(int(gs2.get_value("achievements.counters.sleeps")), 1)
	assert_true(events_seen.has("wokeUp"), "wokeUp beim Laden (got %s)" % [events_seen])
	assert_true(gs2.save_now())
	gs2.free()
	# Zweiter Neustart zur selben Zeit: KEIN Doppel-Grant.
	var gs3 := _fresh_game_state(path)
	assert_eq(gs3.get_value("progression.xp"), 10.0, "kein Doppel-Grant")
	assert_eq(int(gs3.get_value("achievements.counters.sleeps")), 1, "kein Doppel-Zaehler")
	gs3.free()


func test_clock_rollback_resets_baseline_without_negative_decay() -> void:
	var gs := _fresh_game_state(_fresh_path())
	var before_stats: Dictionary = gs.get_value("gooby.stats").duplicate()
	gs.set_value("gooby.lastTickAt", NOW_MS + 86_400_000)
	gs.run_live_tick()
	assert_eq(gs.get_value("gooby.stats"), before_stats, "kein negativer Verfall")
	assert_eq(int(gs.get_value("gooby.lastTickAt")), NOW_MS, "Basislinie neu gesetzt")
	gs.free()


func test_vacation_freezes_stats_live() -> void:
	var gs := _fresh_game_state(_fresh_path())
	gs.update(
		func(s: Dictionary) -> void:
			s["vacation"]["phase"] = "away"
			s["vacation"]["destId"] = "beach"
			s["vacation"]["returnAt"] = NOW_MS + 86_400_000
			s["vacation"]["pickupBy"] = NOW_MS + 2 * 86_400_000
	)
	var before_stats: Dictionary = gs.get_value("gooby.stats").duplicate()
	gs.set_value("gooby.lastTickAt", NOW_MS)
	gs.clock.advance(60 * MIN_MS)
	gs.run_live_tick()
	assert_eq(gs.get_value("gooby.stats"), before_stats, "Urlaub friert Stats ein")
	assert_eq(int(gs.get_value("gooby.lastTickAt")), NOW_MS + 60 * MIN_MS)
	gs.free()


func test_application_resumed_runs_catch_up() -> void:
	var gs := _fresh_game_state(_fresh_path())
	gs.set_value("gooby.lastTickAt", NOW_MS)
	gs.clock.advance(100 * MIN_MS)
	gs.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	# Resume = Offline-Pfad: 100 min mit 0.3x-Raten.
	assert_almost(gs.get_value("gooby.stats.hunger"), 80.0 - 0.35 * 100 * 0.3, 1e-6, "hunger")
	assert_eq(int(gs.get_value("gooby.lastTickAt")), NOW_MS + 100 * MIN_MS)
	gs.free()


## ------------------------------------------ W13B (Doc E §3.3) Erholungs-Boost


func test_live_tick_erholungs_boost_bremst_energie_drain() -> void:
	var gs := _fresh_game_state(_fresh_path())
	gs.set_value("vacation.erholtBis", NOW_MS + 48 * 60 * MIN_MS)
	gs.set_value("gooby.lastTickAt", NOW_MS)
	gs.clock.advance(10 * MIN_MS)
	gs.run_live_tick()
	# Energie-Drain ×0,8 (Vacation.energie_drain_faktor): 90 − 0.25·10·0.8
	# = 88.0 statt 87.5; der Boost wirkt NUR auf energy.
	assert_almost(gs.get_value("gooby.stats.energy"), 88.0, 1e-6, "energy-Drain x0.8")
	assert_almost(gs.get_value("gooby.stats.hunger"), 76.5, 1e-6, "hunger unveraendert")
	gs.free()


func test_catch_up_erholungs_boost_nur_im_boost_fenster() -> void:
	var gs := _fresh_game_state(_fresh_path())
	# Boost endet 40 min nach der Basislinie — von 100 Offline-Minuten sind
	# nur diese 40 gebremst (0.3x-Offline-Rate): 90 − 0.25·100·0.3
	# + 0.25·0.2·40·0.3 = 83.1.
	gs.set_value("vacation.erholtBis", NOW_MS + 40 * MIN_MS)
	gs.set_value("gooby.lastTickAt", NOW_MS)
	gs.clock.advance(100 * MIN_MS)
	gs.notification(Node.NOTIFICATION_APPLICATION_RESUMED)
	assert_almost(gs.get_value("gooby.stats.energy"), 83.1, 1e-6, "Teilfenster gebremst")
	assert_almost(gs.get_value("gooby.stats.hunger"), 80.0 - 0.35 * 100 * 0.3, 1e-6, "hunger 0.3x")
	gs.free()


func test_flat_view_write_back_roundtrip_preserves_other_keys() -> void:
	var state := {
		"gooby":
		{
			"stats": {"hunger": 50.0, "energy": 60.0, "hygiene": 70.0, "fun": 80.0},
			"sleep": {"sleeping": false, "startedAt": 0, "wakeAt": 0},
			"grumpyUntil": 0,
			"lastTickAt": NOW_MS,
			"weight": 42.0,
			"health": {"state": "healthy"},
		},
		"progression": {"level": 3, "xp": 55.0, "unlockedRooms": ["living"]},
		"economy": {"coins": 123, "iap": {"noAds": true}},
		"vacation": {"phase": "none"},
		"achievements": {"unlocked": {}, "counters": {"sleeps": 2}},
	}
	var flat := GoobyTicker.flat_view(state)
	GoobyTicker.write_back(state, flat)
	assert_eq(state["gooby"]["weight"], 42.0, "gooby.weight ueberlebt")
	assert_eq(state["gooby"]["health"]["state"], "healthy", "gooby.health ueberlebt")
	assert_eq(state["progression"]["unlockedRooms"], ["living"], "unlockedRooms ueberlebt")
	assert_eq(state["economy"]["iap"]["noAds"], true, "iap ueberlebt")
	assert_eq(state["economy"]["coins"], 123)
	assert_eq(state["achievements"]["counters"]["sleeps"], 2)
